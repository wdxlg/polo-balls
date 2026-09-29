#!/usr/bin/env python3
"""Rebuild the Sulfur Cube assets solely from Minecraft Java 26.2 (Mojang).

Requires Pillow only for nearest-neighbour UV-face composition. Does not ship
or stage the complete Minecraft client, asset index or any cache. All downloads
are checked against Mojang's version manifest and asset-index SHA-1 hashes.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
CACHE = Path(tempfile.gettempdir()) / "polo_sulfur_26_2_official"
IMAGE = ROOT / "Images/characters/我的世界/sulfur_cube"
AUDIO = ROOT / "audio/characters/我的世界/sulfur_cube"
VERSION = "26.2"
CLIENT_SHA1 = "2dc72797acbc1b63fc16a11c4ac393605f453754"
ASSET_INDEX_SHA1 = "52695890153d94cf946455da532806db8c530831"
SOUNDS_SHA1 = "9ac006d5537ed0fa4a7bcd1eccfc505155847686"

# The central faces of Mojang's 18x18 outer cube and 16x16 inner cube UVs.
OUTER_FACE = (18, 18, 36, 36)
INNER_FACE = (16, 52, 32, 68)

# The first 16x16 frame of animated vanilla magma. The original source is also
# saved unchanged, so every displayed pixel can be traced to the release JAR.
BLOCKS = {
    "wood": "oak_log",
    "ice": "blue_ice",
    "magma": "magma",
    "honey": "honeycomb_block",
    "iron": "iron_block",
    "tnt": "tnt_side",
}
TEXTURES = {
    "sulfur_cube_outer.png": "entity/sulfur_cube/sulfur_cube_outer.png",
    "sulfur_cube_inner.png": "entity/sulfur_cube/sulfur_cube_inner.png",
    **{f"{name}.png": f"block/{name}.png" for name in BLOCKS.values()},
    "oak_log_top.png": "block/oak_log_top.png",
    "tnt_top.png": "block/tnt_top.png",
    "tnt_bottom.png": "block/tnt_bottom.png",
    "sulfur_cube_goo.png": "particle/sulfur_cube_goo.png",
    **{f"explosion_{i}.png": f"particle/explosion_{i}.png" for i in range(8)},
}
SOUNDS = {
    "absorb1": "mob/sulfur_cube/absorb1",
    "absorb2": "mob/sulfur_cube/absorb2",
    "eject1": "mob/sulfur_cube/eject1",
    "jump1": "mob/sulfur_cube/jump1",
    "jump2": "mob/sulfur_cube/jump2",
    "squish1": "mob/sulfur_cube/squish1",
    "squish2": "mob/sulfur_cube/squish2",
    "hurt1": "mob/sulfur_cube/hit1",
    "hurt2": "mob/sulfur_cube/hit2",
    "death": "mob/sulfur_cube/death",
    "bounce": "mob/sulfur_cube/ball/bounce1",
    "wood_hit": "mob/sulfur_cube/ball/bouncy_hit1",
    "ice_hit": "mob/sulfur_cube/ball/fastsliding_hit1",
    "magma_hit": "mob/sulfur_cube/ball/hot_hit1",
    "honey_hit": "mob/sulfur_cube/ball/sticky_hit1",
    "iron_hit": "mob/sulfur_cube/ball/slowflat_hit1",
    "tnt_hit": "mob/sulfur_cube/ball/explosive_hit1",
    "fuse": "random/fuse",
    "explosion": "random/explode1",
    "impact_hurt1": "damage/hit1",
    "impact_hurt2": "damage/hit2",
    "impact_hurt3": "damage/hit3",
    "impact_crit1": "entity/player/attack/crit1",
    "impact_crit2": "entity/player/attack/crit2",
    "impact_crit3": "entity/player/attack/crit3",
}


def sha1(content: bytes) -> str:
    return hashlib.sha1(content).hexdigest()


def download(url: str, path: Path, expected_sha1: str) -> bytes:
    if path.exists():
        existing = path.read_bytes()
        if sha1(existing) == expected_sha1:
            return existing
    with urllib.request.urlopen(url, timeout=35) as response:
        content = response.read()
    actual = sha1(content)
    if actual != expected_sha1:
        raise ValueError(f"SHA-1 mismatch: {url}: expected {expected_sha1}, got {actual}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return content


def manifest() -> tuple[dict, dict, bytes, dict]:
    CACHE.mkdir(exist_ok=True)
    with urllib.request.urlopen("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json", timeout=35) as r:
        versions = json.load(r)["versions"]
    release = next(v for v in versions if v["id"] == VERSION and v["type"] == "release")
    with urllib.request.urlopen(release["url"], timeout=35) as r:
        version = json.load(r)
    client = version["downloads"]["client"]
    asset_index = version["assetIndex"]
    if client["sha1"] != CLIENT_SHA1 or asset_index["sha1"] != ASSET_INDEX_SHA1:
        raise ValueError("The Mojang version-manifest hashes differ from the pinned 26.2 release")
    index_bytes = download(asset_index["url"], CACHE/"asset-index-26.2.json", ASSET_INDEX_SHA1)
    index = json.loads(index_bytes)["objects"]
    sound_meta = index["minecraft/sounds.json"]
    if sound_meta["hash"] != SOUNDS_SHA1:
        raise ValueError("Mojang sounds.json hash changed")
    sound_url = f"https://resources.download.minecraft.net/{SOUNDS_SHA1[:2]}/{SOUNDS_SHA1}"
    sounds = json.loads(download(sound_url, CACHE/"sounds.json", SOUNDS_SHA1))
    # Verify that every chosen clip occurs in Minecraft's own sound-event table.
    named_sounds = {raw if isinstance(raw, str) else raw["name"]
                    for definition in sounds.values() for raw in definition.get("sounds", [])}
    for key, source in SOUNDS.items():
        if source not in named_sounds:
            raise ValueError(f"Clip {key} is not in Mojang's sound-event table: {source}")
    return version, index, index_bytes, sounds


def produce() -> None:
    version, index, _, _ = manifest()
    client = version["downloads"]["client"]
    jar_bytes = download(client["url"], CACHE/"client-26.2.jar", CLIENT_SHA1)
    # Keep extracted source files byte-identical to the official JAR.
    IMAGE.mkdir(parents=True, exist_ok=True)
    AUDIO.mkdir(parents=True, exist_ok=True)
    provenance: dict = {
        "edition": "Minecraft Java Edition",
        "version": VERSION,
        "release_manifest": "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
        "client_url": client["url"], "client_sha1": CLIENT_SHA1,
        "asset_index_url": version["assetIndex"]["url"], "asset_index_sha1": ASSET_INDEX_SHA1,
        "sounds_json_sha1": SOUNDS_SHA1,
        "source_files": {}, "derived_files": {},
    }
    with zipfile.ZipFile(CACHE/"client-26.2.jar") as jar:
        for output, name in TEXTURES.items():
            entry = "assets/minecraft/textures/" + name
            raw = jar.read(entry)
            path = IMAGE/"source"/output if output not in {"sulfur_cube_goo.png"} and not output.startswith("explosion_") else IMAGE/output
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            provenance["source_files"][str(path.relative_to(ROOT)).replace("\\", "/")] = {
                "jar_entry": entry, "sha1": sha1(raw), "size": len(raw)
            }
    for short, source in SOUNDS.items():
        key = f"minecraft/sounds/{source}.ogg"
        record = index[key]
        digest = record["hash"]
        url = f"https://resources.download.minecraft.net/{digest[:2]}/{digest}"
        path = AUDIO/f"{short}.ogg"
        raw = download(url, path, digest)
        provenance["source_files"][str(path.relative_to(ROOT)).replace("\\", "/")] = {
            "asset_index_entry": key, "sha1": digest, "size": len(raw), "url": url
        }

    outer = Image.open(IMAGE/"source/sulfur_cube_outer.png").convert("RGBA").crop(OUTER_FACE)
    inner = Image.open(IMAGE/"source/sulfur_cube_inner.png").convert("RGBA").crop(INNER_FACE)
    if outer.size != (18, 18) or inner.size != (16, 16):
        raise ValueError("Unexpected sulfur cube model UV size")
    for mode in ("empty", *BLOCKS):
        result = Image.new("RGBA", (128, 128))
        result.alpha_composite(inner.resize((88, 88), Image.Resampling.NEAREST), (20, 24))
        sources = ["source/sulfur_cube_inner.png", "source/sulfur_cube_outer.png"]
        if mode != "empty":
            source_name = BLOCKS[mode] + ".png"
            block = Image.open(IMAGE/"source"/source_name).convert("RGBA")
            result.alpha_composite(block.crop((0, 0, 16, 16)).resize((60, 60), Image.Resampling.NEAREST), (34, 38))
            sources.append("source/" + source_name)
        result.alpha_composite(outer.resize((96, 96), Image.Resampling.NEAREST), (16, 20))
        path = IMAGE/f"{mode}.png"
        result.save(path, optimize=False)
        provenance["derived_files"][str(path.relative_to(ROOT)).replace("\\", "/")] = {
            "source_textures": sources,
            "method": "nearest-neighbour scaling and alpha compositing of native front-facing model UVs",
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
    (IMAGE/"sources.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("SULFUR_ASSETS_OK", "textures", len(TEXTURES), "sounds", len(SOUNDS), "derived", 1+len(BLOCKS))


if __name__ == "__main__":
    produce()
