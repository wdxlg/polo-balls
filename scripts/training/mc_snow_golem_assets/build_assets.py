#!/usr/bin/env python3
"""Bake the native Snow Golem and fetch unmodified Minecraft effects/audio.
Build-time dependencies: numpy, Pillow, requests. No runtime Python dependency.
Mojang assets remain subject to the Minecraft EULA; no redistribution license is granted.
"""
from pathlib import Path
import copy, hashlib, io, json, math, sys, zipfile
import requests
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'Images/characters/我的世界/snow_golem'
SOUND = ROOT / 'audio/characters/我的世界/snow_golem'
CACHE = HERE / '.cache'
COMMIT = '736072450c26a7c67f07b1661f29d9a5ebaa14b1'
JAVA_VERSION = '1.21.1'
records = []
for directory in (OUT, SOUND, CACHE): directory.mkdir(parents=True, exist_ok=True)

def fetch(url, sha1=None):
    key = hashlib.sha256(url.encode()).hexdigest()
    path = CACHE / key
    if path.exists():
        data = path.read_bytes()
    else:
        response = requests.get(url, timeout=120)
        response.raise_for_status()
        data = response.content
        path.write_bytes(data)
    if sha1 and hashlib.sha1(data).hexdigest() != sha1:
        raise ValueError('Official SHA-1 mismatch: ' + url)
    return data

def save(path, data, url, **extra):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    records.append({'file': path.relative_to(ROOT).as_posix(), 'url': url,
                    'sha256': hashlib.sha256(data).hexdigest(), **extra})

native_files = [
    'models/entity/snow_golem.v1.0.geo.json',
    'animations/snow_golem.animations.v1.0.json',
    'textures/entity/snow_golem.png',
    'textures/blocks/snow.png',
    'textures/blocks/pumpkin_face_off.png',
    'textures/blocks/pumpkin_side.png',
    'textures/blocks/pumpkin_top.png',
]
for name in native_files:
    url = f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/{name}'
    save(HERE / 'resource_pack' / name, fetch(url), url)
license_url = f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/LICENSE.md'
save(HERE / 'LICENSE.minecraft.md', fetch(license_url), license_url)
manifest_url = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
manifest = json.loads(fetch(manifest_url))
version_entry = next(v for v in manifest['versions'] if v['id'] == JAVA_VERSION)
version = json.loads(fetch(version_entry['url'], version_entry.get('sha1')))
index_info = version['assetIndex']
index = json.loads(fetch(index_info['url'], index_info['sha1']))
client = version['downloads']['client']
jar = zipfile.ZipFile(io.BytesIO(fetch(client['url'], client['sha1'])))
entry = 'assets/minecraft/textures/item/snowball.png'
save(OUT / 'snowball.png', jar.read(entry), client['url'], archive_entry=entry, archive_sha1=client['sha1'])
particle_entry = 'assets/minecraft/particles/snowflake.json'
particle_bytes = jar.read(particle_entry)
save(HERE / 'snowflake.json', particle_bytes, client['url'], archive_entry=particle_entry, archive_sha1=client['sha1'])
for frame, texture in enumerate(json.loads(particle_bytes)['textures']):
    entry = 'assets/minecraft/textures/particle/' + texture.split(':')[-1] + '.png'
    save(OUT / f'snowflake_{frame}.png', jar.read(entry), client['url'], archive_entry=entry, archive_sha1=client['sha1'])
snow_path = HERE / 'resource_pack/textures/blocks/snow.png'
# Preserve the 16x16 native texels in the ground tile, without resampling.
save(OUT / 'snow.png', snow_path.read_bytes(),
     f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/textures/blocks/snow.png')
sound_hash = index['objects']['minecraft/sounds.json']['hash']
sound_url = f'https://resources.download.minecraft.net/{sound_hash[:2]}/{sound_hash}'
all_events = json.loads(fetch(sound_url, sound_hash))
wanted = ['entity.snow_golem.ambient', 'entity.snow_golem.hurt', 'entity.snow_golem.death',
          'entity.snow_golem.shoot', 'entity.snow_golem.shear', 'entity.snowball.throw',
          'block.snow.place', 'block.snow.break', 'block.snow.step', 'block.snow.hit',
          'entity.player.freeze_hurt']
events = {}
downloaded = set()

def resolve(event, inherited_volume=1.0, inherited_pitch=1.0):
    resolved = []
    for item in all_events[event].get('sounds', []):
        item = {'name': item} if isinstance(item, str) else item
        volume = inherited_volume * item.get('volume', 1.0)
        pitch = inherited_pitch * item.get('pitch', 1.0)
        if item.get('type') == 'event':
            resolved.extend(resolve(item['name'], volume, pitch))
            continue
        asset_key = 'minecraft/sounds/' + item['name'] + '.ogg'
        sha1 = index['objects'][asset_key]['hash']
        url = f'https://resources.download.minecraft.net/{sha1[:2]}/{sha1}'
        path = SOUND / (sha1 + '.ogg')
        if sha1 not in downloaded:
            save(path, fetch(url, sha1), url, asset_key=asset_key, sha1=sha1)
            downloaded.add(sha1)
        resolved.append({'path': 'res://' + path.relative_to(ROOT).as_posix(),
                         'volume': volume, 'pitch': pitch})
    return resolved

for event in wanted:
    if event in all_events:
        entries = resolve(event)
        if entries: events[event] = entries
for required in ['entity.snow_golem.hurt', 'entity.snow_golem.death', 'entity.snow_golem.shoot', 'block.snow.place']:
    assert required in events, required
lines = ['extends RefCounted', '# Generated from the official Java 1.21.1 asset index; bytes SHA-1 checked.', 'const EVENTS:Dictionary = {']
for event, entries in events.items():
    encoded = []
    for e in entries:
        encoded.append('{"stream":preload(' + json.dumps(e['path'], ensure_ascii=False) + '),"volume":' + str(e['volume']) + ',"pitch":' + str(e['pitch']) + '}')
    lines.append('\t' + json.dumps(event) + ':[' + ','.join(encoded) + '],')
lines.append('}')
script = ROOT / 'scripts/characters/我的世界/snow_golem/native_sounds.gd'
script.parent.mkdir(parents=True, exist_ok=True)
script.write_text('\n'.join(lines) + '\n', encoding='utf-8')

from snow_renderer import SnowBaker

baker = SnowBaker()
generated = []
for state in ['pumpkin', 'bare']:
    for suffix, yaw in [('left', -28), ('center', 0), ('right', 28)]:
        image = baker.render('snow', state, yaw)
        path = OUT / f'{state}_{suffix}.png'
        image.save(path)
        generated.append({'file': path.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bounds': list(image.getbbox())})
for role in ['pumpkin_block', 'snow_block']:
    image = baker.render(role, '', 0)
    box = image.getbbox()
    image = image.crop((box[0]-1,box[1]-1,box[2]+1,box[3]+1))
    path = OUT / (role + '.png'); image.save(path)
    generated.append({'file': path.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'size': list(image.size)})
source_manifest = {'bedrock_commit': COMMIT, 'java_version': JAVA_VERSION, 'version_manifest_url': version_entry['url'], 'asset_index': index_info,
                   'sounds_definition': {'url': sound_url, 'sha1': sound_hash},
                   'copyright': 'Minecraft assets belong to Mojang/Microsoft. Minecraft EULA applies; no commercial/republication license is asserted.',
                   'adaptation': 'Native Bedrock Snow Golem v1.0 geometry/skin and original arm/torso Molang sampled at three target-yaw angles. Native carved-pumpkin block texels are projected at the head attachment (the engine-specific pumpkin material is not embedded). Bare state removes only that pumpkin, revealing the native snow face. Blocks are orthographic projections of native block textures. This is a 2D software bake, not a Minecraft engine screenshot or an invented official walking/throwing animation. Java snowball/snowflake PNG and OGG bytes are unmodified.',
                   'files': records, 'generated': generated, 'events': events}
(ROOT / 'MC_SNOW_GOLEM_ASSETS.json').write_text(json.dumps(source_manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('SNOW_NATIVE_READY', len(generated), 'baked PNGs;', len(downloaded), 'verified OGGs;', len(events), 'sound events', flush=True)
