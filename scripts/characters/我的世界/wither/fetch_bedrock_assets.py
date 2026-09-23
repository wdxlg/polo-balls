"""Pin the vanilla Bedrock Wither rig to Mojang's public bedrock-samples commit.

The official geometry, animation, controller, client entity and textures are kept
unaltered. SHA-256 checks make future replacement by different assets fail loudly.
Check Mojang's Minecraft usage guidelines before redistributing game assets.
"""
import hashlib
import json
import urllib.request
from pathlib import Path

COMMIT = '46ba6ea985fb5a92d79a9419198f10dda14c199d'
BASE = f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/'
SOURCES = {
    'models/entity/wither_boss.geo.json': 'de2097edee50db825ca0d325fb9ec983e131ff249f5a39df3e1ec6e89cd3aae2',
    'models/entity/wither_boss_armor.geo.json': '0e6ae27a117b9fa8aa2ffbb43d73341ef01b2210bb6011c3f8988c00bddd8d4a',
    'animations/wither_boss.animation.json': '359cb7f4d27d814503cfd179661c99e407d3f6e7d5529ae4286b38d24a7a4dcd',
    'animation_controllers/wither_boss.animation_controllers.json': '0a557a37944642dd4a27e9147d413abda7ef54c20b4b25f0135b580cb769e50a',
    'entity/wither.entity.json': '01234b71ae6d6439534f6ad9b8b378d4183ab588ae4af48b8ac364cec9dc9e1f',
    'textures/entity/wither_boss/wither.png': 'cb4d8aeabd1f0a258aa2fc9cab01e6a124cbc75cd9676d25d13ea98a00875a05',
    'textures/entity/wither_boss/wither_invulnerable.png': 'c806fa5e03c908a607247a35ba5c958f2bbe55ae9112d9377eb3363f22ed38fd',
    'textures/entity/wither_boss/wither_armor_blue.png': '96b844e6ce25a076633954f3540e0864dfc94077fa7bc81200350e179fa51edc',
}
OUT = Path(__file__).resolve().parents[4] / 'Images/characters/我的世界/wither/bedrock'


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, expected in SOURCES.items():
        data = urllib.request.urlopen(BASE + name, timeout=35).read()
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise ValueError(f'Official Bedrock asset changed: {name}: {actual}')
        (OUT / Path(name).name).write_bytes(data)
    (OUT / 'SOURCE_MANIFEST.json').write_text(json.dumps({
        'repository': 'Mojang/bedrock-samples', 'commit': COMMIT,
        'sha256_by_original_resource_pack_path': SOURCES,
        'runtime': 'Original geometry and Molang formulas interpreted as live Godot 3D bones; not an exported static image.',
    }, indent=2) + '\n', encoding='utf-8')
    print('BEDROCK_WITHER_OFFICIAL_ASSETS_OK:', len(SOURCES))


if __name__ == '__main__':
    main()
