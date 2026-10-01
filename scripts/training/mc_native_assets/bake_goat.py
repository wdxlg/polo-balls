#!/usr/bin/env python3
"""Offline Bedrock sample -> PNG frames for the goats summoned by the Goat Horn.

Same software renderer and camera as bake_wandering_trader.py (orthographic, yaw 30, pitch 12,
unflipped artwork faces LEFT like ball.dir_left). Runtime has no Python/3D dependency.

Sources: Mojang/bedrock-samples @ commit in sources_goat.json (resource_pack/...):
  models/entity/goat.geo.json        geometry.goat (goat.entity.json, adult)
  animations/goat.animation.json     animation.goat.walk (tcos * 0.5 on the four legs),
                                     animation.goat.ram_attack (head 0 -> [60,0,0], position 0 -> [0,-8,-3])
  textures/entity/goat/goat.png
Originals are subject to the Minecraft EULA, not an open license.
Per-cube rotation about the cube pivot (the head cube is authored at 55 degrees) is applied as in Bedrock.
"""
import argparse, json, math, re, hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
W, H = 176, 176
PX = 4.55 * 0.9375          # same pixels/unit as the trader llama, so herd animals share one scale
FOOT = 150


def load_json(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    text = re.sub(r'//[^\n]*', '', text)
    return json.loads(re.sub(r',\s*([}\]])', r'\1', text))


def rotation(angles):
    x, y, z = np.radians(np.asarray(angles, dtype=float) * [-1, 1, -1])
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]) @ np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]) @ np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])


def about(pivot, angles):
    m = np.eye(4); m[:3, :3] = rotation(angles); p = np.asarray(pivot, float); m[:3, 3] = p - m[:3, :3] @ p
    return m


class Baker:
    def __init__(self, source):
        self.bones = load_json(source / 'models/entity/goat.geo.json')['minecraft:geometry'][0]['bones']
        self.skin = np.array(Image.open(source / 'textures/entity/goat/goat.png').convert('RGBA'))
        yaw, pitch = np.radians([30, 12])
        right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.camera = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
        up = np.cross(right, self.camera)
        self.view = np.array([right, -up, self.camera])

    def pose(self, state, t):
        p = {b['name']: {'position': np.zeros(3), 'rotation': np.zeros(3)} for b in self.bones}
        # animation.goat.walk: legs at tcos * 0.5, tcos = cos(distance * 38.17) * speed * 57.3 (one stride per clip second)
        amplitude = 57.3 * 0.5 * 1.45      # full-speed sprint stride
        c = math.cos(t * math.tau)
        p['right_back_leg']['rotation'][0] = c * amplitude
        p['left_back_leg']['rotation'][0] = -c * amplitude
        p['right_front_leg']['rotation'][0] = -c * amplitude
        p['left_front_leg']['rotation'][0] = c * amplitude
        if state == 'ram':
            # animation.goat.ram_attack sampled at 1.1 s of its 0 -> 2.0 s linear key (horns levelled forward;
            # the full end key buries the head under the body in this 2D side view).
            k = 1.1 / 2.0
            p['head']['rotation'][0] += 60.0 * k
            p['head']['position'] += [0, -8 * k, -3 * k]
        return p

    def render(self, state, t):
        pose = self.pose(state, t)
        by_name = {b['name']: b for b in self.bones}
        world = {}

        def transform(name):
            if name in world:
                return world[name]
            b = by_name[name]; q = pose[name]; pivot = np.array(b.get('pivot', [0, 0, 0]), dtype=float)
            m = np.eye(4); m[:3, :3] = rotation(q['rotation']); m[:3, 3] = pivot + q['position'] - m[:3, :3] @ pivot
            if b.get('parent'):
                m = transform(b['parent']) @ m
            world[name] = m
            return m

        self.rgba = np.zeros((H, W, 4), np.uint8); self.depth = np.full((H, W), -1e10)
        for bone in self.bones:
            m = transform(bone['name'])
            for cube in bone.get('cubes', []):
                cm = m @ about(cube['pivot'], cube['rotation']) if 'rotation' in cube else m
                self.cube(cube, cm, bone.get('mirror', False))
        return Image.fromarray(self.rgba)

    def cube(self, cube, m, mirror):
        x, y, z = cube['origin']; dx, dy, dz = cube['size']; f = cube.get('inflate', 0)
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
            n = m[:3, :3] @ normal; n = n / max(np.linalg.norm(n), 1e-8)
            flat = dx == 0 or dz == 0 or dy == 0
            if np.dot(n, self.camera) < -.001 and not flat:
                continue
            uv = np.array([[a, b], [a + c, b], [a + c, b + d], [a, b + d]], float)
            if mirror:
                uv = uv[[1, 0, 3, 2]]
            lighting = .76 + .24 * max(0, float(np.dot(n, np.array([-.35, .8, -.48]))))
            self.quad(verts[ids], m, uv, lighting)

    def quad(self, points, m, uv, lighting):
        p = points @ m[:3, :3].T + m[:3, 3]; p = p @ self.view.T
        p[:, :2] *= PX; p[:, 0] += W / 2; p[:, 1] += FOOT
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
            rgba = self.skin[np.clip(vv.astype(int), 0, self.skin.shape[0] - 1), np.clip(u.astype(int), 0, self.skin.shape[1] - 1)].copy()
            rgba[:, :, :3] = (rgba[:, :, :3].astype(float) * lighting).astype(np.uint8)
            mask = (a >= -1e-6) & (b >= -1e-6) & (c >= -1e-6) & (depth >= self.depth[y0:y1, x0:x1] - 1e-6) & (rgba[:, :, 3] > 10)
            self.rgba[y0:y1, x0:x1][mask] = rgba[mask]; self.depth[y0:y1, x0:x1][mask] = depth[mask]


CLIPS = {'run': (12, 0.4), 'ram': (12, 0.4)}   # (frames, seconds per stride), looping
RES_DIR = 'res://Images/characters/我的世界/goat_horn/goat/'


def bake(source, output):
    b = Baker(source)
    output.mkdir(parents=True, exist_ok=True)
    files = []; anims = []; dedup = {}; preview = []; info = {'size': [W, H], 'foot_y': FOOT, 'pixels_per_unit': PX, 'clips': {}}
    for state, (count, duration) in CLIPS.items():
        ids = []; frames = []
        for i in range(count):
            image = b.render(state, i / count)
            digest = hashlib.sha256(image.tobytes()).hexdigest()
            if digest not in dedup:
                file = f'goat_{len(files):03}.png'; image.save(output / file, optimize=True); files.append(file); dedup[digest] = len(files)
            ids.append(dedup[digest]); frames.append(image)
        preview.append((state, frames))
        info['clips'][state] = {'count': count, 'duration': duration}
        anims.append('{"frames": [' + ', '.join('{"duration": 1.0, "texture": ExtResource("' + str(j) + '")}' for j in ids) + '], "loop": true, "name": &"' + state + '", "speed": ' + str(round(count / duration, 4)) + '}')
    box = None
    for _, frames in preview:
        for f in frames:
            bb = f.getbbox(); box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    info['union_bounds'] = list(box)
    resource = '[gd_resource type="SpriteFrames" format=3]\n\n' + '\n'.join('[ext_resource type="Texture2D" path="' + RES_DIR + file + '" id="' + str(i + 1) + '"]' for i, file in enumerate(files)) + '\n\n[resource]\nanimations = [' + ',\n'.join(anims) + ']\n'
    (output / 'goat_frames.tres').write_text(resource, encoding='utf-8')
    (output / 'manifest.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
    contact = Image.new('RGB', (W * 6, len(preview) * (H + 20)), (37, 43, 53)); d = ImageDraw.Draw(contact)
    for row, (label, frames) in enumerate(preview):
        d.text((6, row * (H + 20) + 4), label, fill='white')
        for col in range(6):
            f = frames[col * 2]
            contact.paste(f, (col * W, row * (H + 20) + 20), f)
    contact.save(output.parent / 'goat_contact.png')
    print(info)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--source', type=Path, default=ROOT / 'resource_pack_goat'); ap.add_argument('--output', type=Path, default=ROOT / 'frames_goat')
    a = ap.parse_args(); bake(a.source, a.output)
