#!/usr/bin/env python3
"""Offline integrity check for the Minecraft Java 26.2 Sulfur Cube files.

No network/cache/Pillow required. The pinned Mojang provenance was established
by scripts/training/mc_native_assets/fetch_sulfur_cube.py during acquisition.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Images/characters/我的世界/sulfur_cube/sources.json"
CLIENT = "2dc72797acbc1b63fc16a11c4ac393605f453754"
INDEX = "52695890153d94cf946455da532806db8c530831"
SOUNDS = "9ac006d5537ed0fa4a7bcd1eccfc505155847686"


def verify() -> tuple[int, int]:
    info = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert (info["version"], info["client_sha1"], info["asset_index_sha1"], info["sounds_json_sha1"]) == (
        "26.2", CLIENT, INDEX, SOUNDS
    )
    originals, composed = info["source_files"], info["derived_files"]
    assert len(originals) == 45 and len(composed) == 7, (len(originals), len(composed))
    for relative, record in originals.items():
        path = ROOT / relative
        assert path.resolve().is_relative_to(ROOT.resolve()), relative
        contents = path.read_bytes()
        assert len(contents) == record["size"], relative
        assert hashlib.sha1(contents).hexdigest() == record["sha1"], relative
        if "asset_index_entry" in record:
            assert relative.endswith(".ogg") and record["asset_index_entry"].startswith("minecraft/sounds/")
            assert record["url"].endswith("/" + record["sha1"])
        else:
            assert relative.endswith(".png") and record["jar_entry"].startswith("assets/minecraft/textures/")
    for relative, record in composed.items():
        path = ROOT / relative
        assert path.resolve().is_relative_to(ROOT.resolve()), relative
        assert hashlib.sha256(path.read_bytes()).hexdigest() == record["sha256"], relative
        assert set(record["source_textures"]).issubset({
            Path(name).relative_to("Images/characters/我的世界/sulfur_cube").as_posix()
            for name in originals if name.startswith("Images/characters/我的世界/sulfur_cube/source/")
        }), relative
    return len(originals), len(composed)


if __name__ == "__main__":
    source_count, composed_count = verify()
    print(f"SULFUR_ASSETS_VERIFIED: {source_count} original Minecraft files; {composed_count} derived sprites")
