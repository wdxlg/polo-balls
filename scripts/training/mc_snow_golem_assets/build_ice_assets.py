#!/usr/bin/env python3
"""Extract unchanged native ice / destruction-stage PNGs from the pinned official client.
Standard library only. Reuses the Snow Golem builder's download cache.
Minecraft assets remain Mojang/Microsoft property, subject to the Minecraft EULA.
"""
from pathlib import Path
import hashlib, io, json, urllib.request, zipfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
base = json.loads((ROOT / 'MC_SNOW_GOLEM_ASSETS.json').read_text(encoding='utf8'))
source = next(record for record in base['files'] if record.get('archive_entry') == 'assets/minecraft/textures/item/snowball.png')
url, expected = source['url'], source['archive_sha1']
cache = HERE / '.cache' / hashlib.sha256(url.encode()).hexdigest()
if cache.exists():
    payload = cache.read_bytes()
else:
    payload = urllib.request.urlopen(url, timeout=120).read()
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_bytes(payload)
assert hashlib.sha1(payload).hexdigest() == expected, 'Official client SHA1 mismatch'
archive = zipfile.ZipFile(io.BytesIO(payload))
files = [('ice.png', 'assets/minecraft/textures/block/ice.png')]
files += [(f'ice_crack_{i}.png', f'assets/minecraft/textures/block/destroy_stage_{i}.png') for i in range(10)]
records = []
for name, entry in files:
    data = archive.read(entry)
    path = ROOT / 'Images/characters/我的世界/snow_golem' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    records.append({'file': path.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(data).hexdigest(), 'archive_entry': entry})
manifest = {
    'java_version': '1.21.1', 'archive_url': url, 'archive_sha1': expected,
    'files': records,
    'adaptation': 'Unmodified original PNG bytes. Runtime translucent cuboid fitted to the victim; original block-destruction stages; cropped native ice texels for breakout fragments. No generated replacement art.',
    'copyright': 'Minecraft assets belong to Mojang/Microsoft. The Minecraft EULA applies; no independent redistribution authorization is asserted.'
}
(ROOT / 'MC_SNOW_GOLEM_ICE_ASSETS.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print('Verified original Minecraft ice assets:', len(records))
