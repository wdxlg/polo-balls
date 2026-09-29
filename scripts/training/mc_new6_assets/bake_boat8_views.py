#!/usr/bin/env python3
"""8-direction oak boat atlas baker, two-layer hull so riders sit INSIDE the boat.

Needs numpy + Pillow; run on a dev machine and commit the generated atlases/.tres/preview
(the project machine has no Pillow). Regenerates:
  Images/characters/我的世界/new6/boat_frames8.png|.tres          (back layer: far wall, floor, bench, far paddle, bow/stern)
  Images/characters/我的世界/new6/boat_front_frames8.png|.tres    (front layer: near wall + near paddle)
  Images/characters/我的世界/new6/boat_preview.png
plus contact sheets and seat-anchor meta next to this script.

Runtime draws: back layer (boat Image) < riders < front layer (HullFront sprite),
so a rider's legs are hidden by the near gunwale and their feet rest on the floor.
Seat anchors are the baked floor positions of the bow/stern seats per direction,
so passengers swap front/back on screen whenever the heading switches.
"""
import importlib.util
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent


def _load_shared_baker():
    p = HERE.parent / 'mc_native_assets' / 'bake_native_mobs.py'
    if not p.exists():  # local dev checkout layout
        p = HERE / 'baker_base.py'
    spec = importlib.util.spec_from_file_location('new6_boat8_baker', p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


mod = _load_shared_baker()
mod.W = 160
mod.H = 320

CELL = 160
SCALE = 2.45
WORLD_PER_PX = 0.28  # ball root scale 0.2 * boat image scale 1.4
SRC = HERE / 'source' / 'textures_entity_boat_boat_oak.png'

BOAT_HULL = [
    {'origin': [-10, 0, -4], 'size': [20, 2, 8], 'uv': [2, 35]},      # floor
    {'origin': [-14, 0, -8], 'size': [28, 9, 3], 'uv': [0, 0]},       # side wall A
    {'origin': [-14, 0, 5], 'size': [28, 9, 3], 'uv': [0, 0]},        # side wall B
    {'origin': [11, 0, -5], 'size': [3, 9, 10], 'uv': [2, 20]},       # stern
    {'origin': [-14, 0, -5], 'size': [3, 9, 10], 'uv': [2, 20]},      # bow
    {'origin': [-3, 2, -5], 'size': [6, 2, 10], 'uv': [28, 6]},       # bench
]
WALL_IDS = (1, 2)
PADDLE_UV0, PADDLE_UV1 = [62, 0], [62, 20]
PADDLE_L = [
    {'origin': [1, 7, -26], 'size': [2, 2, 18], 'uv': PADDLE_UV0},
    {'origin': [1.5, 3, -26], 'size': [1, 6, 7], 'uv': PADDLE_UV0},
]
PADDLE_R = [
    {'origin': [1, 7, 8], 'size': [2, 2, 18], 'uv': PADDLE_UV1},
    {'origin': [1.5, 3, 19], 'size': [1, 6, 7], 'uv': PADDLE_UV1},
]
PIVOT_L = np.array([2, 8, -8], float)
PIVOT_R = np.array([2, 8, 8], float)
FORWARD = np.array([-1, 0, 0], float)  # fitted hull bow
SEATS = [np.array([-9, 2, 0], float), np.array([9, 2, 0], float)]  # bow, stern on the floor

FACES = [
    ([3, 2, 1, 0], (lambda u, v, dx, dy, dz: (u + dz, v + dz, dx, dy)), [0, 0, -1]),
    ([6, 7, 4, 5], (lambda u, v, dx, dy, dz: (u + 2 * dz + dx, v + dz, dx, dy)), [0, 0, 1]),
    ([7, 3, 0, 4], (lambda u, v, dx, dy, dz: (u, v + dz, dz, dy)), [-1, 0, 0]),
    ([2, 6, 5, 1], (lambda u, v, dx, dy, dz: (u + dz + dx, v + dz, dz, dy)), [1, 0, 0]),
    ([7, 6, 2, 3], (lambda u, v, dx, dy, dz: (u + dz, v, dx, dz)), [0, 1, 0]),
    ([0, 1, 5, 4], (lambda u, v, dx, dy, dz: (u + dz + dx, v, dx, dz)), [0, -1, 0]),
]


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def make_baker():
    b = mod.Baker.__new__(mod.Baker)
    skin = np.array(Image.open(SRC).convert('RGBA'))
    assert skin.shape[:2] == (64, 128), skin.shape
    b.skins = {'boat': skin}
    b.scale = {'boat': SCALE}
    b.foot = {'boat': 160}
    yaw, pitch = np.radians([30, PITCH_DEG])
    b.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
    b.camera = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
    b.up = np.cross(b.right, b.camera)
    b.view = np.array([b.right, -b.up, b.camera])
    b.rgba = np.zeros((mod.H, mod.W, 4), np.uint8)
    b.depth = np.full((mod.H, mod.W), -1e10)
    return b


PITCH_DEG = 60.0
NORM_CLAMP = (0.92, 1.10)


def draw_cube(b, cube, m):
    x, y, z = cube['origin']
    dx, dy, dz = cube['size']
    lo = np.array([x, y, z], float)
    hi = lo + np.array([dx, dy, dz], float)
    verts = np.array([
        [lo[0], lo[1], lo[2]], [hi[0], lo[1], lo[2]], [hi[0], hi[1], lo[2]], [lo[0], hi[1], lo[2]],
        [lo[0], lo[1], hi[2]], [hi[0], lo[1], hi[2]], [hi[0], hi[1], hi[2]], [lo[0], hi[1], hi[2]]])
    u, v = cube['uv']
    rot = m[:3, :3]
    for ids, rectfn, normal in FACES:
        n = rot @ np.array(normal, float)
        norm = np.linalg.norm(n)
        if norm < 1e-8:
            continue
        n = n / norm
        if np.dot(n, b.camera) < -0.001:
            continue
        a, bb, w, h = rectfn(u, v, dx, dy, dz)
        uv = np.array([[a, bb], [a + w, bb], [a + w, bb + h], [a, bb + h]], float)
        lighting = .76 + .24 * max(0.0, float(np.dot(n, np.array([-.35, .8, -.48]))))
        b.quad(verts[ids], m, uv, b.skins['boat'], 'boat', lighting)


def layer_assignment(b, yaw_angle):
    """Near-side gunwale + near-side paddle render in front of riders."""
    world = ry(yaw_angle)
    depths = []
    for idx in WALL_IDS:
        c = BOAT_HULL[idx]
        centre = np.array(c['origin'], float) + np.array(c['size'], float) / 2
        depths.append(float(np.dot(b.camera, world @ centre)))
    wall_front = WALL_IDS[0] if depths[0] >= depths[1] else WALL_IDS[1]
    paddle_depths = [float(np.dot(b.camera, world @ PIVOT_L)), float(np.dot(b.camera, world @ PIVOT_R))]
    paddle_front = 0 if paddle_depths[0] >= paddle_depths[1] else 1
    return wall_front, paddle_front


def render_layer(b, yaw_angle, paddle_v, wall_front, paddle_front, layer):
    b.rgba = np.zeros((mod.H, mod.W, 4), np.uint8)
    b.depth = np.full((mod.H, mod.W), -1e10)
    world = np.eye(4)
    world[:3, :3] = ry(yaw_angle)
    for idx, cube in enumerate(BOAT_HULL):
        is_front = idx == wall_front
        if is_front != (layer == 'front'):
            continue
        draw_cube(b, cube, world)
    y_sw = math.sin(-paddle_v + 1.0)
    x_dip = -22.5 * math.sin(-paddle_v)
    # keep |yaw| >= 15 deg so paddle tips never reach the cell border in bow/stern views
    rots = [ry(math.radians(-30.0 + 15.0 * y_sw)) @ rx(math.radians(x_dip)),
            ry(math.radians(30.0 - 15.0 * y_sw)) @ rx(math.radians(x_dip))]
    for pi, (cubes, pivot) in enumerate(((PADDLE_L, PIVOT_L), (PADDLE_R, PIVOT_R))):
        is_front = pi == paddle_front
        if is_front != (layer == 'front'):
            continue
        rot = rots[pi]
        m_part = np.eye(4)
        m_part[:3, :3] = rot
        m_part[:3, 3] = pivot - rot @ pivot
        for cube in cubes:
            draw_cube(b, cube, world @ m_part)
    return Image.fromarray(b.rgba)


def solve_yaw(b, desired):
    best, best_dot = 0.0, -2.0
    for deg in np.arange(0, 360, 0.25):
        v = ry(math.radians(deg)) @ FORWARD
        p = b.view @ v
        s = p[:2]
        nl = np.linalg.norm(s)
        if nl < 1e-6:
            continue
        d = float(np.dot(s / nl, desired))
        if d > best_dot:
            best_dot, best = d, deg
    return math.radians(best), best_dot


def write_tres(path, png_name):
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (1 + 128 + 1), '',
             '[ext_resource type="Texture2D" path="res://Images/characters/我的世界/new6/%s" id="atlas"]' % png_name, '']
    for r in range(16):
        for c in range(8):
            lines += ['[sub_resource type="AtlasTexture" id="a%d_%d"]' % (r, c), 'atlas = ExtResource("atlas")',
                      'region = Rect2(%d, %d, %d, %d)' % (c * CELL, r * CELL, CELL, CELL), 'filter_clip = true', '']
    lines.append('[resource]')
    anims = []
    for i in range(8):
        fr = ', '.join('{"duration": 1.0, "texture": SubResource("a%d_%d")}' % (i, 0) for _ in range(8))
        anims.append('{\n"frames": [%s],\n"loop": true,\n"name": &"d%d_idle",\n"speed": 5\n}' % (fr, i))
    for i in range(8):
        fr = ', '.join('{"duration": 1.0, "texture": SubResource("a%d_%d")}' % (8 + i, k) for k in range(8))
        anims.append('{\n"frames": [%s],\n"loop": true,\n"name": &"d%d_row",\n"speed": 9\n}' % (fr, i))
    lines.append('animations = [' + ',\n'.join(anims) + ']')
    lines.append('')
    path.write_text('\n'.join(lines), encoding='utf-8')


def main():
    b = make_baker()
    yaws = []
    for i in range(8):
        desired = np.array([math.cos(i * math.tau / 8), math.sin(i * math.tau / 8)])
        yaw, dot = solve_yaw(b, desired)
        yaws.append(yaw)
        assert dot > 0.999, (i, dot)
    assigns = [layer_assignment(b, y) for y in yaws]
    areas = []
    for i in range(8):
        wf, pf = assigns[i]
        union = Image.alpha_composite(render_layer(b, yaws[i], 0.0, wf, pf, 'back'),
                                      render_layer(b, yaws[i], 0.0, wf, pf, 'front'))
        arr = np.array(union)[:, :, 3]
        areas.append(float((arr > 10).sum()))
    target = float(np.mean(areas))
    norms = [min(NORM_CLAMP[1], max(NORM_CLAMP[0], math.sqrt(target / a))) for a in areas]
    neutral_back = render_layer(b, yaws[0], 0.0, assigns[0][0], assigns[0][1], 'back')
    neutral_front = render_layer(b, yaws[0], 0.0, assigns[0][0], assigns[0][1], 'front')
    union = Image.alpha_composite(neutral_back, neutral_front)
    bbox = union.getbbox()
    half = CELL // 2
    crop = (round((bbox[0] + bbox[2]) / 2), round((bbox[1] + bbox[3]) / 2))
    box = (crop[0] - half, crop[1] - half, crop[0] + half, crop[1] + half)
    back_frames, front_frames = {}, {}
    for i in range(8):
        wf, pf = assigns[i]
        b.scale['boat'] = SCALE * norms[i]
        back_frames[i] = {'idle': [render_layer(b, yaws[i], 0.0, wf, pf, 'back').crop(box)],
                          'row': [render_layer(b, yaws[i], k * math.tau / 8, wf, pf, 'back').crop(box) for k in range(8)]}
        front_frames[i] = {'idle': [render_layer(b, yaws[i], 0.0, wf, pf, 'front').crop(box)],
                           'row': [render_layer(b, yaws[i], k * math.tau / 8, wf, pf, 'front').crop(box) for k in range(8)]}
    b.scale['boat'] = SCALE
    out_dir = HERE.parents[2] / 'Images' / 'characters' / '我的世界' / 'new6' if (HERE.parents[2] / 'Images').exists() else HERE / 'export'
    out_dir.mkdir(parents=True, exist_ok=True)
    for frames, png in ((back_frames, 'boat_frames8.png'), (front_frames, 'boat_front_frames8.png')):
        atlas = Image.new('RGBA', (CELL * 8, CELL * 16), (0, 0, 0, 0))
        for i in range(8):
            atlas.paste(frames[i]['idle'][0], (0, i * CELL))
            for k in range(8):
                atlas.paste(frames[i]['row'][k], (k * CELL, (8 + i) * CELL))
        atlas.save(out_dir / png, optimize=True)
        write_tres(out_dir / png.replace('.png', '.tres'), png)
    back_frames[0]['idle'][0].save(out_dir / 'boat_preview.png', optimize=True)
    meta = {'crop': list(crop), 'neutral_bbox': list(bbox), 'norms': [round(n, 4) for n in norms], 'pitch_deg': PITCH_DEG, 'cell': CELL, 'yaws_deg': [round(math.degrees(y), 3) for y in yaws],
            'scale': SCALE, 'world_per_px': WORLD_PER_PX, 'seats': []}
    for i in range(8):
        row = []
        for seat in SEATS:
            p = b.view @ (ry(yaws[i]) @ seat)
            cellx = p[0] * SCALE * norms[i] + CELL - crop[0]
            celly = p[1] * SCALE * norms[i] + CELL + CELL // 2 - crop[1]
            row.append({'cell': [round(cellx, 2), round(celly, 2)],
                        'world': [round((cellx - CELL / 2) * WORLD_PER_PX, 3), round((celly - CELL / 2) * WORLD_PER_PX, 3)]})
        meta['seats'].append(row)
    (HERE / 'boat_frames8_meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
    (out_dir / 'boat_frames8_meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
    preview = Image.new('RGBA', (512, 512), (32, 42, 52, 255))
    d = ImageDraw.Draw(preview)
    for i in range(8):
        cell = Image.alpha_composite(back_frames[i]['idle'][0], front_frames[i]['idle'][0])
        preview.alpha_composite(cell.resize((128, 128)), ((i % 4) * 128, (i // 4) * 128))
        d.text(((i % 4) * 128 + 5, (i // 4) * 128 + 5), 'd%d' % i, fill='white')
    for i in range(8):
        cell = Image.alpha_composite(back_frames[i]['row'][2], front_frames[i]['row'][2])
        preview.alpha_composite(cell.resize((64, 64)), (256 + (i % 4) * 64, 256 + (i // 4) * 64))
    preview.save(HERE / 'contact_boat8_views.png')
    layer_preview = Image.new('RGBA', (384, 160), (32, 42, 52, 255))
    layer_preview.alpha_composite(back_frames[1]['row'][2].resize((128, 128)), (0, 16))
    layer_preview.alpha_composite(front_frames[1]['row'][2].resize((128, 128)), (128, 16))
    layer_preview.alpha_composite(Image.alpha_composite(back_frames[1]['row'][2], front_frames[1]['row'][2]).resize((128, 128)), (256, 16))
    layer_preview.save(HERE / 'contact_boat8_layers.png')
    print('BAKE_OK crop', crop, 'bbox', bbox)
    print('SEATS_WORLD', json.dumps(meta['seats']))


if __name__ == '__main__':
    main()
