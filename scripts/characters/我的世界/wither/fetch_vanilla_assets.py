"""Rebuild the Wither 2D assets from Mojang's Minecraft Java 1.21.11 client.

Requires Pillow (python -m pip install Pillow). Requires acceptance of the
Minecraft EULA and Mojang usage guidelines before fetching/re-distributing.
Only the small derived textures and selected OGG files are written to the repo;
the 31 MB client archive is held in a temporary directory, not committed.
"""
from __future__ import annotations

import hashlib
import json
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

CLIENT_URL = 'https://piston-data.mojang.com/v1/objects/ba2df812c2d12e0219c489c4cd9a5e1f0760f5bd/client.jar'
CLIENT_SHA1 = 'ba2df812c2d12e0219c489c4cd9a5e1f0760f5bd'
INDEX_URL = 'https://piston-meta.mojang.com/v1/packages/adb0a43fae291fd88ee27d85a372ba6f2072b0a3/29.json'
INDEX_SHA1 = 'adb0a43fae291fd88ee27d85a372ba6f2072b0a3'
TEXTURES = [
    'entity/wither/wither.png', 'entity/wither/wither_invulnerable.png',
    'entity/beacon_beam.png', 'block/soul_sand.png', 'block/wither_rose.png',
    'block/beacon.png', 'item/nether_star.png', 'particle/effect_0.png',
    'particle/flash.png', 'particle/big_smoke_0.png',
]
SOUNDS = {
    'spawn': 'mob/wither/spawn', 'shoot': 'mob/wither/shoot',
    'hurt1': 'mob/wither/hurt1', 'hurt2': 'mob/wither/hurt2',
    'hurt3': 'mob/wither/hurt3', 'hurt4': 'mob/wither/hurt4',
    'death': 'mob/wither/death', 'idle1': 'mob/wither/idle1',
    'idle2': 'mob/wither/idle2', 'explode': 'random/explode1',
    'beacon_activate': 'block/beacon/activate',
    'beacon_power': 'block/beacon/power1',
    'beacon_deactivate': 'block/beacon/deactivate',
    'soul_sand': 'block/soul_sand/step1',
    'rose': 'dig/grass1',
}
ROOT = Path(__file__).resolve().parents[4]
TEX_DIR = ROOT / 'Images/characters/我的世界/wither'
SOUND_DIR = ROOT / 'audio/characters/我的世界/wither'


def checked_download(url: str, expected: str) -> bytes:
    data = urllib.request.urlopen(url, timeout=90).read()
    actual = hashlib.sha1(data).hexdigest()
    if actual != expected:
        raise ValueError(f'SHA-1 mismatch {url}: expected {expected}, got {actual}')
    return data


def src(atlas: Image.Image, box: tuple[int, int, int, int], size: tuple[int, int]) -> Image.Image:
    return atlas.crop(box).resize(size, Image.Resampling.NEAREST)


def bake_wither(atlas: Image.Image) -> Image.Image:
    # Vanilla UVs: central head (8,8,8x8), side heads (38,6,6x6),
    # spine/rib/tail texels from the same official 64x64 entity atlas.
    # A front projection for a top-down 2D game, not a new painted texture.
    canvas = Image.new('RGBA', (80, 72))
    canvas.alpha_composite(src(atlas, (0, 25, 12, 34), (12, 28)), (34, 33))
    for y, w in [(37, 54), (45, 39), (53, 26)]:
        canvas.alpha_composite(src(atlas, (3, 19, 23, 22), (w, 6)), ((80-w)//2, y))
    canvas.alpha_composite(src(atlas, (0, 25, 12, 34), (12, 16)), (13, 27))
    canvas.alpha_composite(src(atlas, (0, 25, 12, 34), (12, 16)), (55, 27))
    side = src(atlas, (38, 6, 44, 12), (21, 21))
    canvas.alpha_composite(side, (3, 13))
    canvas.alpha_composite(side, (56, 13))
    canvas.alpha_composite(src(atlas, (8, 8, 16, 16), (28, 28)), (26, 3))
    return canvas.resize((160, 144), Image.Resampling.NEAREST)


def bake_beacon(tile: Image.Image) -> Image.Image:
    # All visible faces reuse Minecraft's original beacon block texture.
    from PIL import ImageDraw
    out = Image.new('RGBA', (64, 70))
    mask = Image.new('L', (64, 70))
    draw = ImageDraw.Draw(mask)
    # Pixel-accurate front face and perspective 2D projections of same texels.
    out.alpha_composite(tile.resize((44, 44), Image.Resampling.NEAREST), (10, 18))
    top = tile.resize((44, 15), Image.Resampling.NEAREST)
    out.alpha_composite(top, (10, 5))
    draw.polygon([(10, 18), (31, 5), (54, 18), (31, 31)], fill=255)
    overlay = Image.new('RGBA', (64, 70))
    overlay.alpha_composite(tile.resize((44, 28), Image.Resampling.NEAREST), (10, 5))
    overlay.putalpha(Image.composite(overlay.getchannel('A'), Image.new('L', (64, 70)), mask))
    out.alpha_composite(overlay)
    return out


def main() -> None:
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    SOUND_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        jar = Path(tmp) / 'client.jar'
        jar.write_bytes(checked_download(CLIENT_URL, CLIENT_SHA1))
        index_data = checked_download(INDEX_URL, INDEX_SHA1)
        index = json.loads(index_data)['objects']
        provenance = {'version': 'Minecraft Java Edition 1.21.11', 'client_sha1': CLIENT_SHA1,
                      'index_sha1': INDEX_SHA1, 'textures': {}, 'sounds': {}}
        with zipfile.ZipFile(jar) as zipped:
            for relative in TEXTURES:
                name = 'assets/minecraft/textures/' + relative
                data = zipped.read(name)
                (TEX_DIR / Path(relative).name).write_bytes(data)
                provenance['textures'][relative] = hashlib.sha1(data).hexdigest()
        atlas = Image.open(TEX_DIR / 'wither.png').convert('RGBA')
        bake_wither(atlas).save(TEX_DIR / 'wither_front.png')
        bake_wither(Image.open(TEX_DIR / 'wither_invulnerable.png').convert('RGBA')).save(TEX_DIR / 'wither_assembling.png')
        src(atlas, (8, 8, 16, 16), (32, 32)).save(TEX_DIR / 'wither_skull.png')
        bake_beacon(Image.open(TEX_DIR / 'beacon.png').convert('RGBA')).save(TEX_DIR / 'beacon_front.png')
        for output, relative in SOUNDS.items():
            key = 'minecraft/sounds/' + relative + '.ogg'
            info = index[key]
            digest = info['hash']
            data = checked_download('https://resources.download.minecraft.net/' + digest[:2] + '/' + digest, digest)
            (SOUND_DIR / (output + '.ogg')).write_bytes(data)
            provenance['sounds'][key] = digest
        (TEX_DIR / 'SOURCE_MANIFEST.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'Validated {len(TEXTURES)} official textures and {len(SOUNDS)} original sounds; baked 4 sprites.')


if __name__ == '__main__':
    main()
