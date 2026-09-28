#!/usr/bin/env python3
"""Offline Bedrock sample -> PNG frames for the Wandering Trader, trader llamas and llama spit.

Same software renderer and camera as bake_native_mobs.py (orthographic, yaw 30, pitch 12,
unflipped artwork faces LEFT like ball.dir_left). Runtime has no Python/3D dependency.

Sources: Mojang/bedrock-samples @ commit in commit.txt (resource_pack/...):
  models/entity/villager_v2.geo.json   geometry.villager_v2 (wandering_trader.entity.json, scale 0.9375)
  models/entity/llama.geo.json         geometry.llama.v1.8  (trader_llama.entity.json)
  models/entity/llama_spit.json        geometry.llamaspit
  animations/villager.animation.json   villager.general / villager.move / villager.raise_arms
  animations/quadruped.animation.json  quadruped.walk (weighted by query.modified_move_speed)
  animations/llama.animation.json      llama.setup (body)
  textures/entity/wandering_trader.png, llama/llama_{creamy,brown}.png,
  llama/decor/trader_llama_decor.png, llama/spit.png
Originals are subject to the Minecraft EULA, not an open license.

Bind-pose notes (documented deviations, see README section "流浪商人"):
  * The sample llama.geo v1.8 body cube is authored upright (12x18x10) with no bind rotation;
    both Java (LlamaModel body xRot = PI/2) and llama.setup.v1.0 ("90 - this") lay it down.
    We apply that 90 degree bind to the body cube only (legs/head are not children of it in Java).
  * villager_v2 'brim' is fully transparent on wandering_trader.png and is skipped.
  * Decor is the same geometry inflated by 0.5, as Java LlamaDecorLayer does.
"""
import argparse, copy, json, math, re, hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SIZES = {'trader': (160, 224), 'llama': (192, 224), 'spit': (96, 96)}
PX = 4.55 * 0.9375          # evoker pixels/unit * wandering_trader.entity.json scale
FOOT = {'trader': 206, 'llama': 206}


def load_json(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    text = re.sub(r'//[^\n]*', '', text)
    return json.loads(re.sub(r',\s*([}\]])', r'\1', text))


def rotation(angles):
    # Bedrock authored angles -> Y-up model-space (X/Z signs reflected), identical to bake_native_mobs.py
    x, y, z = np.radians(np.asarray(angles, dtype=float) * [-1, 1, -1])
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]) @ np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]) @ np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])


def geometry(path, ident=None):
    model = load_json(path)
    if 'minecraft:geometry' in model:
        return copy.deepcopy(model['minecraft:geometry'][0]['bones'])
    return copy.deepcopy(next(v for k, v in model.items() if k.startswith('geometry.') and (ident is None or k == ident))['bones'])


class Baker:
    def __init__(self, source):
        self.source = source
        self.models = {
            'trader': geometry(source / 'models/entity/villager_v2.geo.json'),
            'llama': geometry(source / 'models/entity/llama.geo.json'),
            'spit': geometry(source / 'models/entity/llama_spit.json', 'geometry.llamaspit'),
        }
        tex = source / 'textures/entity'
        rgba = lambda p: np.array(Image.open(p).convert('RGBA'))
        self.skins = {
            'trader': rgba(tex / 'wandering_trader.png'),
            'llama_creamy': rgba(tex / 'llama/llama_creamy.png'),
            'llama_brown': rgba(tex / 'llama/llama_brown.png'),
            'decor': rgba(tex / 'llama/decor/trader_llama_decor.png'),
            'spit': rgba(tex / 'llama/spit.png'),
        }
        yaw, pitch = np.radians([30, 12])
        self.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.camera = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
        self.up = np.cross(self.right, self.camera)
        self.view = np.array([self.right, -self.up, self.camera])

    # ---------------------------------------------------------------- poses
    def pose(self, role, state, t):
        bones = self.models[role]
        p = {b['name'].lower(): {'position': np.zeros(3), 'rotation': np.array(b.get('rotation', [0, 0, 0]), dtype=float), 'scale': np.ones(3)} for b in bones}
        anim_time = t * 360 / 38.17          # one full leg cycle per clip second, like bake_native_mobs.py
        if role == 'trader':
            # animation.villager.general: arms rotation "-42.97 - this", position [0,-1,-1]
            p['arms']['rotation'][0] = -42.97
            p['arms']['position'] += [0, -1, -1]
            if state == 'walk':
                # animation.villager.move
                p['leg0']['rotation'][0] = math.cos(math.radians(anim_time * 38.17)) * 40.0
                p['leg1']['rotation'][0] = math.cos(math.radians(anim_time * 38.17 + 180)) * 40.0
            if state == 'drink':
                # animation.villager.raise_arms ("variable.raise_arms * -15") while drinking; head tips back to the bottle.
                cycle = math.sin(t / 0.26 * math.tau)      # three sips per 0.78 s clip
                p['arms']['rotation'][0] += 2.0 * -15.0 + 4.0 * cycle
                p['head']['rotation'][0] += -14.0 + 3.0 * cycle
        elif role == 'llama':
            # animation.llama.setup ("-this") keeps body at bind; quadruped.walk weighted by modified_move_speed.
            weight = {'walk': 0.42, 'run': 0.75}.get(state, 0.0)
            c = math.cos(math.radians(anim_time * 38.17))
            for leg, sign in (('leg0', 1), ('leg1', -1), ('leg2', -1), ('leg3', 1)):
                p[leg]['rotation'][0] = c * 80.0 * sign * weight
            if state == 'spit':
                # Vanilla has no dedicated spit clip; a short head thrust makes the shot readable in 2D.
                k = math.sin(min(t / 0.34, 1.0) * math.pi)
                p['head']['rotation'][0] += -16.0 * k
                p['head']['position'] += [0, 0, -1.2 * k]
        return p

    # ---------------------------------------------------------------- render
    def render(self, role, state, t, skin_name=None):
        W, H = SIZES[role]
        bones = self.models[role]
        pose = self.pose(role, state, t)
        by_name = {b['name'].lower(): b for b in bones}
        world = {}

        def transform(name):
            name = name.lower()
            if name in world:
                return world[name]
            b = by_name[name]; q = pose[name]; pivot = np.array(b.get('pivot', [0, 0, 0]), dtype=float)
            m = np.eye(4); m[:3, :3] = rotation(q['rotation']) @ np.diag(q['scale']); m[:3, 3] = pivot + q['position'] - m[:3, :3] @ pivot
            if b.get('parent'):
                m = transform(b['parent']) @ m
            world[name] = m
            return m

        self.W, self.H, self.role = W, H, role
        self.rgba = np.zeros((H, W, 4), np.uint8); self.depth = np.full((H, W), -1e10)
        skin = self.skins[skin_name or role]
        for bone in bones:
            name = bone['name'].lower()
            if name in ('brim', 'held_item', 'chest1', 'chest2'):
                continue
            m = transform(name)
            if role == 'llama' and name == 'body':
                # Java LlamaModel: body xRot = PI/2 about its pivot (bind only for the body cube).
                pivot = np.array(bone['pivot'], dtype=float)
                bind = np.eye(4); bind[:3, :3] = rotation([90, 0, 0]); bind[:3, 3] = pivot - bind[:3, :3] @ pivot
                m = m @ bind
            for cube in bone.get('cubes', []):
                self.cube(cube, m, skin, bone.get('mirror', False), 0.0)
                if role == 'llama':
                    self.cube(cube, m, self.skins['decor'], bone.get('mirror', False), 0.5)
        return Image.fromarray(self.rgba)

    def cube(self, cube, m, skin, mirror, extra):
        x, y, z = cube['origin']; dx, dy, dz = cube['size']; f = cube.get('inflate', 0) + extra
        lo = np.array([x - f, y - f, z - f]); hi = np.array([x + dx + f, y + dy + f, z + dz + f])
        verts = np.array([[lo[0], lo[1], lo[2]], [hi[0], lo[1], lo[2]], [hi[0], hi[1], lo[2]], [lo[0], hi[1], lo[2]],
                          [lo[0], lo[1], hi[2]], [hi[0], lo[1], hi[2]], [hi[0], hi[1], hi[2]], [lo[0], hi[1], hi[2]]])
        u, v = cube['uv']; mirror = cube.get('mirror', mirror)
        faces = [([3, 2, 1, 0], (u + dz, v + dz, dx, dy), [0, 0, -1]), ([6, 7, 4, 5], (u + 2 * dz + dx, v + dz, dx, dy), [0, 0, 1]),
                 ([7, 3, 0, 4], (u, v + dz, dz, dy), [-1, 0, 0]), ([2, 6, 5, 1], (u + dz + dx, v + dz, dz, dy), [1, 0, 0]),
                 ([7, 6, 2, 3], (u + dz, v, dx, dz), [0, 1, 0]), ([0, 1, 5, 4], (u + dz + dx, v, dx, dz), [0, -1, 0])]
        for ids, (a, b, c, d), normal in faces:
            if c == 0 or d == 0:
                continue
            n = m[:3, :3] @ normal; norm = np.linalg.norm(n)
            if norm < 1e-8:
                continue
            n = n / norm
            if np.dot(n, self.camera) < -.001 and dz != 0:
                continue
            uv = np.array([[a, b], [a + c, b], [a + c, b + d], [a, b + d]], float)
            if mirror:
                uv = uv[[1, 0, 3, 2]]
            lighting = .76 + .24 * max(0, float(np.dot(n, np.array([-.35, .8, -.48]))))
            self.quad(verts[ids], m, uv, skin, lighting)

    def quad(self, points, m, uv, skin, lighting):
        W, H = self.W, self.H
        scale = PX * (1.0 if self.role != 'spit' else 2.0)
        p = points @ m[:3, :3].T + m[:3, 3]; p = p @ self.view.T
        p[:, :2] *= scale; p[:, 0] += W / 2
        # spit cubes are centred on model y=23 (geometry.llamaspit); characters stand on FOOT
        p[:, 1] += FOOT[self.role] if self.role != 'spit' else H / 2 + 23 * scale
        for ids in ([0, 1, 2], [0, 2, 3]):
            v = p[ids]; tex = uv[ids]
            x0 = max(0, int(math.floor(v[:, 0].min()))); x1 = min(W, int(math.ceil(v[:, 0].max())))
            y0 = max(0, int(math.floor(v[:, 1].min()))); y1 = min(H, int(math.ceil(v[:, 1].max())))
            if x1 <= x0 or y1 <= y0:
                continue
            xx, yy = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
            det = (v[1, 1] - v[2, 1]) * (v[0, 0] - v[2, 0]) + (v[2, 0] - v[1, 0]) * (v[0, 1] - v[2, 1])
            if abs(det) < 1e-8:
                continue
            a = ((v[1, 1] - v[2, 1]) * (xx - v[2, 0]) + (v[2, 0] - v[1, 0]) * (yy - v[2, 1])) / det
            b = ((v[2, 1] - v[0, 1]) * (xx - v[2, 0]) + (v[0, 0] - v[2, 0]) * (yy - v[2, 1])) / det; c = 1 - a - b
            depth = a * v[0, 2] + b * v[1, 2] + c * v[2, 2]
            u = a * tex[0, 0] + b * tex[1, 0] + c * tex[2, 0]; vv = a * tex[0, 1] + b * tex[1, 1] + c * tex[2, 1]
            rgba = skin[np.clip(vv.astype(int), 0, skin.shape[0] - 1), np.clip(u.astype(int), 0, skin.shape[1] - 1)].copy()
            rgba[:, :, :3] = (rgba[:, :, :3].astype(float) * lighting).astype(np.uint8)
            mask = (a >= -1e-6) & (b >= -1e-6) & (c >= -1e-6) & (depth >= self.depth[y0:y1, x0:x1] - 1e-6) & (rgba[:, :, 3] > 10)
            self.rgba[y0:y1, x0:x1][mask] = rgba[mask]; self.depth[y0:y1, x0:x1][mask] = depth[mask]


# state: (frames, seconds, loop)
CLIPS = {
    'trader': {'idle': (1, 1.0, True), 'walk': (24, 1.0, True), 'drink': (12, 0.78, True)},
    'llama': {'idle': (1, 1.0, True), 'walk': (24, 1.0, True), 'run': (16, 0.5, True), 'spit': (10, 0.34, False)},
}
VARIANTS = {'trader': ['trader'], 'llama': ['llama_creamy', 'llama_brown']}
RES_DIR = 'res://Images/characters/我的世界/流浪商人/frames/'


def bake(output):
    b = Baker(ROOT / 'resource_pack_trader')
    output.mkdir(parents=True, exist_ok=True)
    manifest = {'source_commit': (ROOT / 'commit.txt').read_text().strip(), 'pixels_per_unit': PX, 'sets': {}}
    preview = []
    for role, clips in CLIPS.items():
        for variant in VARIANTS[role]:
            files = []; anims = []; dedup = {}; data = {'size': list(SIZES[role]), 'foot_y': FOOT[role], 'clips': {}}
            for state, (count, duration, loop) in clips.items():
                ids = []; frames = []
                for i in range(count):
                    fraction = i / (count - 1) if not loop and count > 1 else i / count
                    image = b.render(role, state, fraction * duration, variant)
                    digest = hashlib.sha256(image.tobytes()).hexdigest()
                    if digest not in dedup:
                        file = f'{variant}_{len(files):03}.png'; image.save(output / file, optimize=True); files.append(file); dedup[digest] = len(files)
                    ids.append(dedup[digest]); frames.append(image)
                preview.append((variant + ' / ' + state, frames))
                data['clips'][state] = {'count': count, 'duration': duration, 'loop': loop, 'unique': len(set(ids))}
                anims.append('{"frames": [' + ', '.join('{"duration": 1.0, "texture": ExtResource("' + str(j) + '")}' for j in ids) + '], "loop": ' + str(loop).lower() + ', "name": &"' + state + '", "speed": ' + str(round(count / duration, 4)) + '}')
            data['neutral_bounds'] = list(b.render(role, 'idle', 0, variant).getbbox()); data['textures'] = len(files)
            manifest['sets'][variant] = data
            resource = '[gd_resource type="SpriteFrames" format=3]\n\n' + '\n'.join('[ext_resource type="Texture2D" path="' + RES_DIR + file + '" id="' + str(i + 1) + '"]' for i, file in enumerate(files)) + '\n\n[resource]\nanimations = [' + ',\n'.join(anims) + ']\n'
            (output / f'{variant}.tres').write_text(resource, encoding='utf-8'); print(variant, data, flush=True)
    spit = b.render('spit', 'idle', 0, 'spit')
    bbox = spit.getbbox(); spit = spit.crop(bbox); spit.save(output / 'llama_spit.png', optimize=True)
    manifest['spit'] = {'size': list(spit.size)}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
    cw = 192
    contact = Image.new('RGB', (cw * 5, len(preview) * (224 + 24)), (37, 43, 53)); d = ImageDraw.Draw(contact)
    for row, (label, frames) in enumerate(preview):
        d.text((10, row * (224 + 24) + 5), label, fill='white')
        for col in range(5):
            f = frames[int(col * (len(frames) - 1) / 4)]
            contact.paste(f, (col * cw, row * (224 + 24) + 24), f)
    contact.save(output.parent / 'contact.png')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, default=ROOT / 'frames_trader'); args = parser.parse_args(); bake(args.output)
