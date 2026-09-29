#!/usr/bin/env python3
"""new6 native bakes: sheep (bedrock geo+anim+skin) + boat (native texture, fitted hull).

Sheep: geometry + animations + skin are byte-identical Mojang bedrock-samples files
(pinned commit recorded in manifest). bind_pose_rotation is honored by pre-rotating
body cubes (verified: legs meet body exactly after +90X mapping (x,y,z)->(x,z,-y)).
Boat: NO vanilla boat.geo.json exists anywhere (engine-hardcoded, verified against the
full vanilla pack mirror which also lacks it). Hull boxes are fitted so every face net
lands fully inside opaque native-texture regions; paddle shaft/blade nets are decoded
exactly from the texture layout. Paddle pose/rowing matches vanilla behavior.
"""
import sys, math, json, hashlib
import numpy as np
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent


def _load_shared_baker():
    import importlib.util
    p = HERE.parent / 'mc_native_assets' / 'bake_native_mobs.py'
    if not p.exists():  # local dev checkout layout
        p = HERE / 'baker_base.py'
    spec = importlib.util.spec_from_file_location('new6_shared_baker', p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


B = _load_shared_baker()

B.W = B.H = 128
SRC = HERE / 'source'

# ---------------------------------------------------------------- sheep geo prep
def rot_px_box(origin, size, pivot):
    """Bedrock bind_pose_rotation (90,0,0): (x,y,z)->(x,z,-y) rel pivot (verified)."""
    o = np.array(origin, float) - np.array(pivot, float)
    lo = np.array([o[0], o[2], -o[0] - 0])  # placeholder, recomputed below properly
    x0, y0, z0 = o
    x1, y1, z1 = o + np.array(size, float)
    # (x,y,z)->(x,z,-y): new box spans x:[x0,x1], y:[z0,z1], z:[-y1,-y0]
    lo = np.array([x0, z0, -y1]) + np.array(pivot, float)
    hi = np.array([x1, z1, -y0]) + np.array(pivot, float)
    return lo.tolist(), (hi - lo).tolist()

def bake_bind(bones):
    out = []
    for b in bones:
        b = dict(b)
        bind = b.pop('bind_pose_rotation', None)
        if bind is not None:
            assert [round(v) for v in bind] == [90, 0, 0], bind
            cubes = []
            for c in b.get('cubes', []):
                c = dict(c)
                f = c.get('inflate', 0)
                o = np.array(c['origin'], float) - f
                s = np.array(c['size'], float) + 2 * f
                lo, sz = rot_px_box(o, s, b['pivot'])
                # store back as uninflated origin/size + inflate preserved
                c['origin'] = (np.array(lo) + f).tolist()
                c['size'] = (np.array(sz) - 2 * f).tolist()
                cubes.append(c)
            b['cubes'] = cubes
        out.append(b)
    return out

SHEEP_GEO = B.load_json(SRC / 'models_entity_sheep.geo.json')
SHEEP_ANIM = B.load_json(SRC / 'animations_sheep.animation.json')['animations']
QUAD_ANIM = B.load_json(SRC / 'animations_quadruped.animation.json')['animations']

def sheep_bones(variant):
    key = ('geometry.sheep.v1.8:geometry.sheep.sheared.v1.8' if variant == 'wool'
           else 'geometry.sheep.sheared.v1.8')
    bones = bake_bind(SHEEP_GEO[key]['bones'])
    if variant == 'wool':
        # wool shell covers only upper legs + head back: merge sheared lowers
        # (full legs incl. y0-6) and sheared head (the FACE) into wool bones.
        sh = {b['name']: b for b in SHEEP_GEO['geometry.sheep.sheared.v1.8']['bones']}
        for b in bones:
            if b['name'] == 'head' or b['name'].startswith('leg'):
                b['cubes'] = list(b.get('cubes', [])) + [dict(c) for c in sh[b['name']]['cubes']]
    return bones

# ---------------------------------------------------------------- pose helpers
def _resolve(values, env):
    """Molang-evaluate every element of a keyframe value list -> numeric array."""
    out = []
    for v in values:
        out.append(B.molang(v, env))
    a = np.array(out, float)
    if a.shape == ():
        a = np.array([a, a, a], float)
    return a


def sample_track(track, local, env):
    """Sample a keyframe dict; supports {time: [...]} and {time: {pre,post}}."""
    keys = sorted((float(k), v) for k, v in track.items())
    if local <= keys[0][0]:
        v = keys[0][1]
        return _resolve(v['pre'] if isinstance(v, dict) else v, env)
    if local >= keys[-1][0]:
        v = keys[-1][1]
        return _resolve(v['post'] if isinstance(v, dict) else v, env)
    for (a, va), (b, vb) in zip(keys, keys[1:]):
        if a <= local <= b:
            left = _resolve(va['post'] if isinstance(va, dict) else va, env)
            right = _resolve(vb['pre'] if isinstance(vb, dict) else vb, env)
            f = (local - a) / (b - a)
            return left + (right - left) * f
    raise AssertionError('unreachable')

class SheepBaker(B.Baker):
    def __init__(self, variant):
        self.variant = variant
        self.models = {'sheep': sheep_bones(variant)}
        skin = np.array(Image.open(SRC / 'textures_entity_sheep_sheep.tga').convert('RGBA'))
        assert skin.shape[:2] == (64, 64), skin.shape
        # Bedrock TGA alpha is not cutout opacity (cf. enderman emissive alpha
        # in the shared baker): sheep has no transparent texels, force opaque.
        skin[:, :, 3] = 255
        self.skins = {'sheep': skin}
        self.scale = {'sheep': 2.9}
        self.foot = {'sheep': 104}
        yaw, pitch = np.radians([30, 28])
        self.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.camera = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
        self.up = np.cross(self.right, self.camera)
        self.view = np.array([self.right, -self.up, self.camera])
        self.orientation = np.eye(4)

    def pose(self, role, state, t, peek=0):
        bones = self.models[role]
        poses = {b['name'].lower(): {'position': np.zeros(3),
                 'rotation': np.array(b.get('rotation', [0, 0, 0]), dtype=float),
                 'scale': np.ones(3)} for b in bones}
        walk = state == 'walk'
        cyc = t  # 1.0 == one stride cycle
        env = {'this': 0, 'query.is_baby': 0.0, 'query.anim_time': cyc * 360.0 / 38.17,
               'query.life_time': t, 'query.key_frame_lerp_time': 0.0}
        # setup (adult zeroes + head drop), then walk or graze
        HEAD_UP = 10.0  # new6 user fix: cancel vanilla -6 head drop and raise the adult head to back level
        anims = [('animation.sheep.setup.v2', 0.0)]
        if walk:
            anims.append(('animation.quadruped.walk', 0.0))
        else:
            anims.append(('animation.sheep.grazing.v2', (t * 2.0) % 2.0))
        for name, local in anims:
            bones_anim = (SHEEP_ANIM if name.startswith('animation.sheep') else QUAD_ANIM)[name]['bones']
            for bone, channels in bones_anim.items():
                if bone.lower() not in poses:
                    continue
                p = poses[bone.lower()]
                for channel, values in channels.items():
                    if channel not in p:
                        continue
                    if name.endswith('grazing.v2') and channel == 'rotation':
                        env['query.key_frame_lerp_time'] = local
                    if isinstance(values, dict):
                        vals = sample_track(values, local, env)
                    else:
                        vals = _resolve(values, env)
                    raw = values if isinstance(values, list) else [values]
                    for i, v in enumerate(vals):
                        env['this'] = p[channel][i]
                        r = raw[i] if i < len(raw) else raw[0]
                        if isinstance(r, str) and 'this' in r:
                            v = B.molang(r, env)
                        p[channel][i] += v
        if 'head' in poses:
            poses['head']['position'][1] += HEAD_UP
        return poses

# ---------------------------------------------------------------- boat
# Hull boxes fitted so every face net is fully inside opaque texture regions
# (verified programmatically below). Boat faces -X (bow at -X, screen-left).
BOAT_HULL = [
    {'name': 'hull', 'pivot': [0, 0, 0], 'cubes': [
        {'origin': [-10, 0, -4], 'size': [20, 2, 8], 'uv': [2, 35]},     # inner floor
        {'origin': [-14, 0, -8], 'size': [28, 9, 3], 'uv': [0, 0]},      # port wall
        {'origin': [-14, 0, 5], 'size': [28, 9, 3], 'uv': [0, 0]},       # starboard wall
        {'origin': [11, 0, -5], 'size': [3, 9, 10], 'uv': [2, 20]},      # stern (+X)
        {'origin': [-14, 0, -5], 'size': [3, 9, 10], 'uv': [2, 20]},     # bow (-X, faces left)
        {'origin': [-3, 2, -5], 'size': [6, 2, 10], 'uv': [28, 6]},      # bench seat
    ]},
]
PADDLE_UV0, PADDLE_UV1 = [62, 0], [62, 20]
# port paddle (z=-8): authored pointing -Z (outward); starboard mirrored.
PADDLE_L = [
    {'origin': [1, 7, -26], 'size': [2, 2, 18], 'uv': PADDLE_UV0},
    {'origin': [1.5, 3, -26], 'size': [1, 6, 7], 'uv': PADDLE_UV0},
]
PADDLE_R = [
    {'origin': [1, 7, 8], 'size': [2, 2, 18], 'uv': PADDLE_UV1},
    {'origin': [1.5, 3, 19], 'size': [1, 6, 7], 'uv': PADDLE_UV1},
]
BOAT_BONES = BOAT_HULL + [
    {'name': 'paddle_l', 'pivot': [2, 8, -8], 'cubes': PADDLE_L},
    {'name': 'paddle_r', 'pivot': [2, 8, 8], 'cubes': PADDLE_R},
]

def check_opaque(skin_alpha, uv, size, label):
    u, v = uv
    dx, dy, dz = size
    rects = [(u + dz, v, dx, dz), (u + dz + dx, v, dx, dz), (u, v + dz, dz, dy),
             (u + dz, v + dz, dx, dy), (u + dz + dx, v + dz, dz, dy), (u + 2 * dz + dx, v + dz, dx, dy)]
    bad = []
    H, W = skin_alpha.shape
    for (a, b, w, h) in rects:
        if w == 0 or h == 0:
            continue
        reg = skin_alpha[b:b + h, a:a + w]
        if reg.size == 0 or not reg.all():
            missing = int(reg.size - reg.sum()) if reg.size else w * h
            bad.append(((a, b, w, h), missing))
    return bad

class BoatBaker(B.Baker):
    def __init__(self):
        import copy
        self.models = {'boat': copy.deepcopy(BOAT_BONES)}
        skin = np.array(Image.open(SRC / 'textures_entity_boat_boat_oak.png').convert('RGBA'))
        assert skin.shape[:2] == (64, 128), skin.shape
        self.skins = {'boat': skin}
        self.scale = {'boat': 2.55}
        self.foot = {'boat': 100}
        yaw, pitch = np.radians([30, 28])
        self.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.camera = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
        self.up = np.cross(self.right, self.camera)
        self.view = np.array([self.right, -self.up, self.camera])
        self.orientation = np.eye(4)

    def pose(self, role, state, t, peek=0):
        bones = self.models[role]
        poses = {b['name'].lower(): {'position': np.zeros(3),
                 'rotation': np.array(b.get('rotation', [0, 0, 0]), dtype=float),
                 'scale': np.ones(3)} for b in bones}
        if state == 'move':
            sw = math.sin(t * math.tau) * 28.0
            poses['paddle_l']['rotation'][1] += -18.0 + sw
            poses['paddle_r']['rotation'][1] += 18.0 - sw
            poses['hull']['position'][1] += math.sin(t * math.tau * 2) * 0.35
            poses['hull']['rotation'][2] += math.sin(t * math.tau) * 1.5
        else:
            poses['paddle_l']['rotation'][1] += -18.0
            poses['paddle_r']['rotation'][1] += 18.0
            poses['hull']['position'][1] += math.sin(t * math.tau) * 0.3
        return poses

def contact_sheet(images, labels, path, cols=6):
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new('RGBA', (128 * cols, 128 * rows), (36, 36, 44, 255))
    for i, (im, lb) in enumerate(zip(images, labels)):
        sheet.alpha_composite(im.convert('RGBA'), (128 * (i % cols), 128 * (i // cols)))
    sheet.save(path)
    print('saved', path, labels)

if __name__ == '__main__':
    # 1) verify every hull/paddle face net is inside opaque texels
    skin = np.array(Image.open(SRC / 'textures_entity_boat_boat_oak.png').convert('RGBA'))
    alpha = skin[:, :, 3] > 10
    ok = True
    for b in BOAT_BONES:
        for c in b['cubes']:
            bad = check_opaque(alpha, c['uv'], c['size'], b['name'])
            if bad:
                ok = False
                print('HOLE', b['name'], c['uv'], c['size'], bad)
    print('boat nets fully opaque:', ok)
    sh = SheepBaker('wool')
    imgs, lbs = [], []
    for i in range(8):
        imgs.append(sh.render('sheep', 'idle', i / 8 * 1.0)); lbs.append(f'graze{i}')
    contact_sheet(imgs, lbs, HERE / 'contact_sheep_graze.png')
    imgs = [SheepBaker('wool').render('sheep', 'walk', i / 8) for i in range(8)]
    contact_sheet(imgs, [f'walk{i}' for i in range(8)], HERE / 'contact_sheep_walk.png')
    imgs = [SheepBaker('sheared').render('sheep', 'walk', i / 8) for i in range(8)]
    contact_sheet(imgs, [f'shear{i}' for i in range(8)], HERE / 'contact_sheep_sheared.png')
    bt = BoatBaker()
    imgs = [bt.render('boat', 'idle', i / 6) for i in range(6)]
    contact_sheet(imgs, [f'boat_idle{i}' for i in range(6)], HERE / 'contact_boat_idle.png')
    imgs = [bt.render('boat', 'move', i / 8) for i in range(8)]
    contact_sheet(imgs, [f'boat_row{i}' for i in range(8)], HERE / 'contact_boat_row.png')
