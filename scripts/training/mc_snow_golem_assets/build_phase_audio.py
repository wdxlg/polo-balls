#!/usr/bin/env python3
"""Fetch original Minecraft material cues for ice placement/breakage and pumpkin placement.
Vanilla has no dedicated snow-golem birth sound: snow+wood placement is composed at runtime.
No OGG bytes are modified. Standard library only; pinned official source metadata.
"""
from pathlib import Path
import hashlib, json, urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CACHE = HERE / '.cache'
CACHE.mkdir(parents=True, exist_ok=True)
base = json.loads((ROOT / 'MC_SNOW_GOLEM_ASSETS.json').read_text(encoding='utf8'))

def fetch(url, sha1):
    path = CACHE / hashlib.sha256(url.encode()).hexdigest()
    data = path.read_bytes() if path.exists() else urllib.request.urlopen(url, timeout=60).read()
    assert hashlib.sha1(data).hexdigest() == sha1, url
    path.write_bytes(data)
    return data

index_info = base['asset_index']
index = json.loads(fetch(index_info['url'], index_info['sha1']))['objects']
sound_info = base['sounds_definition']
sounds = json.loads(fetch(sound_info['url'], sound_info['sha1']))
wanted = ['block.glass.place', 'block.glass.break', 'block.wood.place']
assets = {}

def resolve(event, volume=1.0, pitch=1.0):
    output = []
    for raw in sounds[event]['sounds']:
        item = {'name': raw} if isinstance(raw, str) else raw
        v, p = volume * item.get('volume', 1.0), pitch * item.get('pitch', 1.0)
        if item.get('type') == 'event':
            output += resolve(item['name'], v, p)
        else:
            key = 'minecraft/sounds/' + item['name'] + '.ogg'
            sha = index[key]['hash']
            filename = 'audio/characters/我的世界/snow_golem/' + sha + '.ogg'
            url = 'https://resources.download.minecraft.net/' + sha[:2] + '/' + sha
            assets[sha] = {'file': filename, 'asset_key': key, 'url': url, 'sha1': sha}
            output.append({'path': 'res://' + filename, 'volume': v, 'pitch': p})
    return output

events = {event: resolve(event) for event in wanted}
def install(record):
    data = fetch(record['url'], record['sha1'])
    path = ROOT / record['file']
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): assert path.read_bytes() == data, 'Refusing changed existing sound: ' + str(path)
    else: path.write_bytes(data)
    return {**record, 'sha256': hashlib.sha256(data).hexdigest()}
with ThreadPoolExecutor(max_workers=4) as pool:
    records = list(pool.map(install, assets.values()))
lines = ['extends RefCounted', '# Generated from official Mojang Java 1.21.1 assets; unmodified, SHA1-verified.', 'const EVENTS:Dictionary = {']
for event, entries in events.items():
    values = ['{\"stream\":preload('+json.dumps(row['path'], ensure_ascii=False)+'),\"volume\":'+str(row['volume'])+',\"pitch\":'+str(row['pitch'])+'}' for row in entries]
    lines.append('\t' + json.dumps(event) + ':[' + ','.join(values) + '],')
lines.append('}')
(ROOT / 'scripts/characters/我的世界/snow_golem/phase_sounds.gd').write_text('\n'.join(lines) + '\n', encoding='utf8')
manifest = {'java_version': '1.21.1', 'asset_index': index_info, 'sounds_definition': sound_info, 'events': events, 'files': records,
    'mapping': {'freeze': ['block.glass.place'], 'ice_break': ['block.glass.break'], 'mini_birth': ['block.snow.place', 'block.wood.place']},
    'notes': 'Ice uses the vanilla glass material sound type; birth combines snow and pumpkin/wood placement. Existing verified block.snow.place files are reused. There is no fabricated entity.snow_golem.spawn event.',
    'copyright': 'Minecraft audio belongs to Mojang/Microsoft; Minecraft EULA applies.'}
(ROOT / 'MC_SNOW_GOLEM_PHASE_AUDIO.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print('NATIVE_PHASE_AUDIO_READY', len(records), 'original OGGs', len(events), 'events')
