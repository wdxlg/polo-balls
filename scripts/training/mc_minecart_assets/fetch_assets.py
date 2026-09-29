#!/usr/bin/env python3
"""Fetch byte-identical, pinned Mojang assets. Use --check for offline verification.
Minecraft artwork remains Mojang/Microsoft copyrighted; this is not an open-art license.
"""
from pathlib import Path
import hashlib, json, sys, urllib.request
ROOT = Path(__file__).resolve().parents[3]
manifest = json.loads((ROOT / 'MC_MINECART_ASSETS.json').read_text(encoding='utf-8'))
check_only = '--check' in sys.argv
for entry in manifest['files']:
    target = ROOT / entry['project_path']
    if check_only or (target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == entry['sha256']):
        data = target.read_bytes()
    else:
        request = urllib.request.Request(entry['url'], headers={'User-Agent': 'MinecartAssetImport/1.0'})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], f"Original asset hash mismatch: {target}"
    if not check_only and (not target.exists() or target.read_bytes() != data):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print('VERIFIED', entry['project_path'])
# Ensure the renderer reads precisely the official atlas rectangles / flipbooks.
for name, base, step in [('critical_hit',(0,72),(8,0)), ('redstone_torch_dust',(56,0),(-8,0)), ('basic_smoke',(56,0),(-8,0))]:
    src = ROOT / 'scripts/training/mc_minecart_assets/particles' / (name+'.json')
    comp = json.loads(src.read_text(encoding='utf-8'))['particle_effect']['components']
    flip = comp['minecraft:particle_appearance_billboard']['uv']['flipbook']
    assert tuple(flip['base_UV']) == base and tuple(flip['step_UV']) == step
for name, uv in [('electric_spark',(16,48)),('magic_critical_hit',(16,32))]:
    src = ROOT / 'scripts/training/mc_minecart_assets/particles' / (name+'.json')
    comp = json.loads(src.read_text(encoding='utf-8'))['particle_effect']['components']
    assert tuple(comp['minecraft:particle_appearance_billboard']['uv']['uv']) == uv
print(f"MINECART NATIVE ASSETS: {len(manifest['files'])} source hashes and 5 official particle definitions verified.")
