#!/usr/bin/env python3
"""Export final new6 atlases + SpriteFrames .tres + JSON meta + previews.

Clips (all 8f, 128px cells, faces-left native):
  sheep: wool_walk, wool_idle(graze), sheared_walk, sheared_idle(graze)
  boat: idle, row
"""
import sys, json, hashlib
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bake_new6 as N

CELL = 128
OUT = HERE / 'export'
OUT.mkdir(exist_ok=True)

def build(name, clips, res_dir):
    """clips: list of (clip_name, fps, [Image]). Returns (atlas_path, tres_text, meta)."""
    nclips = len(clips)
    atlas = Image.new('RGBA', (CELL * 8, CELL * nclips), (0, 0, 0, 0))
    ids = []
    for r, (clip, fps, frames) in enumerate(clips):
        assert len(frames) == 8, (clip, len(frames))
        for c, im in enumerate(frames):
            atlas.paste(im.convert('RGBA'), (c * CELL, r * CELL))
            ids.append(f'{clip}_{c}')
    apath = OUT / f'{name}.png'
    atlas.save(apath, optimize=True)
    # .tres
    L = [f'[gd_resource type="SpriteFrames" load_steps={1 + len(ids) + 1} format=3]', '',
         f'[ext_resource type="Texture2D" path="res://{res_dir}/{name}.png" id="atlas"]', '']
    for i, cid in enumerate(ids):
        x = (i % 8) * CELL
        y = (i // 8) * CELL
        L += [f'[sub_resource type="AtlasTexture" id="{cid}"]', 'atlas = ExtResource("atlas")',
              f'region = Rect2({x}, {y}, {CELL}, {CELL})', 'filter_clip = true', '']
    L.append('[resource]')
    anims = []
    for r, (clip, fps, frames) in enumerate(clips):
        fr = ', '.join(f'{{"duration": 1.0, "texture": SubResource("{clip}_{c}")}}' for c in range(8))
        anims.append(f'{{\n"frames": [{fr}],\n"loop": true,\n"name": &"{clip}",\n"speed": {fps}\n}}')
    L.append('animations = [' + ',\n'.join(anims) + ']')
    L.append('')
    tres = '\n'.join(L)
    (OUT / f'{name}.tres').write_text(tres, encoding='utf-8')
    return apath, tres

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

# --- bake frames ---
sh_wool = N.SheepBaker('wool')
sh_shorn = N.SheepBaker('sheared')
bt = N.BoatBaker()
sheep_clips = [
    ('wool_walk', 10, [sh_wool.render('sheep', 'walk', i / 8) for i in range(8)]),
    ('wool_idle', 4, [sh_wool.render('sheep', 'idle', i / 8) for i in range(8)]),
    ('sheared_walk', 10, [sh_shorn.render('sheep', 'walk', i / 8) for i in range(8)]),
    ('sheared_idle', 4, [sh_shorn.render('sheep', 'idle', i / 8) for i in range(8)]),
]
boat_clips = [
    ('idle', 5, [bt.render('boat', 'idle', i / 8) for i in range(8)]),
    ('row', 9, [bt.render('boat', 'move', i / 8) for i in range(8)]),
]
RES = 'Images/characters/我的世界/new6'
ap_s, _ = build('sheep_frames', sheep_clips, RES)
ap_b, _ = build('boat_frames', boat_clips, RES)
# previews (neutral frames)
sheep_clips[0][2][0].save(OUT / 'sheep_preview.png', optimize=True)
boat_clips[0][2][0].save(OUT / 'boat_preview.png', optimize=True)

SRC = N.SRC
meta = {
    'bedrock_samples_commit': '46ba6ea985fb5a92d79a9419198f10dda14c199d',
    'native_sources_sha256': {
        'models/entity/sheep.geo.json': sha(SRC / 'models_entity_sheep.geo.json'),
        'animations/sheep.animation.json': sha(SRC / 'animations_sheep.animation.json'),
        'animations/quadruped.animation.json': sha(SRC / 'animations_quadruped.animation.json'),
        'textures/entity/sheep/sheep.tga': sha(SRC / 'textures_entity_sheep_sheep.tga'),
        'textures/entity/boat/boat_oak.png': sha(SRC / 'textures_entity_boat_boat_oak.png'),
    },
    'sheep': {'atlas': 'sheep_frames.png', 'sha256': sha(ap_s),
              'clips': {c: {'frames': 8, 'fps': f} for c, f, _ in sheep_clips}},
    'boat': {'atlas': 'boat_frames.png', 'sha256': sha(ap_b),
             'clips': {c: {'frames': 8, 'fps': f} for c, f, _ in boat_clips}},
    'notes': 'Sheep: native geo+anims+skin; bind_pose_rotation honored; walk=quadruped.walk, idle=grazing.v2. '
             'Boat: no vanilla boat.geo.json exists (engine mesh); hull boxes fitted so every face net is fully inside '
             'opaque native-texture texels (verified); paddles decoded exactly from texture; rowing matches vanilla behavior.',
}
(OUT / 'new6_frames.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
import os
for f in sorted(OUT.iterdir()):
    print(f.name, os.path.getsize(f))
