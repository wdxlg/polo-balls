#!/usr/bin/env python3
"""Bake the 避雷针 (Lightning Rod) sprites from the Minecraft Java 1.21.1 client jar.

usage: bake_lightning_rod.py --jar <minecraft_1.21.1_client.jar> --output Images/characters/我的世界/lightning_rod

lightning_rod.png / lightning_rod_on.png: side view of the native block model
(block/lightning_rod.json): the 4x4 head (uv 0,0-4,4) on top of the 2x12 stem
(uv 0,4-2,16), each copied pixel for pixel from the native texture.
rain.png is copied unchanged.
"""
import argparse, io, os, zipfile
from PIL import Image

COPIES = {
    "rain.png": "assets/minecraft/textures/environment/rain.png",
}


def side_view(tex):
    out = Image.new("RGBA", (4, 16), (0, 0, 0, 0))
    out.paste(tex.crop((0, 0, 4, 4)), (0, 0))
    out.paste(tex.crop((0, 4, 2, 16)), (1, 4))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jar", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    os.makedirs(a.output, exist_ok=True)
    with zipfile.ZipFile(a.jar) as jar:
        read = lambda p: Image.open(io.BytesIO(jar.read(p))).convert("RGBA")
        side_view(read("assets/minecraft/textures/block/lightning_rod.png")).save(os.path.join(a.output, "lightning_rod.png"))
        side_view(read("assets/minecraft/textures/block/lightning_rod_on.png")).save(os.path.join(a.output, "lightning_rod_on.png"))
        for name, path in COPIES.items():
            with open(os.path.join(a.output, name), "wb") as f:
                f.write(jar.read(path))


if __name__ == "__main__":
    main()
