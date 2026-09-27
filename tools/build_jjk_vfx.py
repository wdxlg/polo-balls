"""Build the JJK VFX texture set from CC0 sources downloaded into sources/jjk/vfx/.

Outputs (all small, game-ready):
  Images/characters/动漫/咒术回战/vfx/<name>.png      single textures / atlases
  Images/characters/动漫/咒术回战/vfx/SOURCE.json    provenance (all CC0)
  scripts/characters/动漫/咒术回战/jjk_vfx_atlas.gd   const table: name -> [cols, rows, frames]

Single textures are converted to white masks (alpha = brightness) so the game can tint them.
Atlases keep their colours (drawn additively) unless listed as mask.
Run from the project root:  python tools/build_jjk_vfx.py
"""
import glob
import json
import os

from PIL import Image, ImageChops

SRC = "sources/jjk/vfx"
OUT = "Images/characters/动漫/咒术回战/vfx"
META = "scripts/characters/动漫/咒术回战/jjk_vfx_atlas.gd"
os.makedirs(OUT, exist_ok=True)

atlas_meta = {}
source_meta = {}
SOURCES = json.load(open(os.path.join(SRC, "SOURCES.json"), encoding="utf8"))


def note(name, pack, files):
    info = SOURCES[pack]
    source_meta[name] = {"pack": pack, "page": info["page"], "download": info["file"], "license": "CC0", "files": files}


def to_mask(im):
    """White RGBA whose alpha = brightness * original alpha (works for white-on-transparent and art-on-black)."""
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    white = Image.new("RGBA", im.size, (255, 255, 255, 0))
    white.putalpha(ImageChops.multiply(lum, a))
    return white


def black_to_alpha(im):
    """Coloured additive art on black: alpha = max channel, colour un-premultiplied."""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            m = max(r, g, b)
            if m == 0:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (min(255, r * 255 // m), min(255, g * 255 // m), min(255, b * 255 // m), m * a // 255)
    return im


def single(name, pack, rel, size=256):
    im = Image.open(os.path.join(SRC, pack, rel))
    im = to_mask(im)
    im.thumbnail((size, size), Image.LANCZOS)
    im.save(os.path.join(OUT, name + ".png"), optimize=True)
    note(name, pack, [rel])


def cells(im, cols, rows):
    w, h = im.width // cols, im.height // rows
    for r in range(rows):
        for c in range(cols):
            yield im.crop((c * w, r * h, (c + 1) * w, (r + 1) * h))


def pack_atlas(name, frames, cell, pack, files, mode="color", cols=None):
    frames = [f for f in frames if f.getbbox() is not None and f.split()[-1].getextrema()[1] > 8]
    n = len(frames)
    cols = cols or min(8, n)
    rows = (n + cols - 1) // cols
    cw, ch = cell if isinstance(cell, tuple) else (cell, cell)
    atlas = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        f = f.convert("RGBA")
        if mode == "mask":
            f = to_mask(f)
        elif mode == "black":
            f = black_to_alpha(f)
        f = f.resize((cw, ch), Image.LANCZOS)
        atlas.paste(f, ((i % cols) * cw, (i // cols) * ch))
    atlas.save(os.path.join(OUT, name + ".png"), optimize=True)
    atlas_meta[name] = [cols, rows, n]
    note(name, pack, files)
    print(name, atlas.size, n)


# ---------------------------------------------------------------- Kenney particle textures (masks)
kp = "kenney_particle"
for f in sorted(glob.glob(os.path.join(SRC, kp, "PNG", "*.png"))):
    base = os.path.basename(f)[:-4]
    single("k_" + base.replace("_", ""), kp, os.path.join("PNG", os.path.basename(f)), 256)

# ---------------------------------------------------------------- sequences
def grid_frames(path, cols, rows, scale_to=None):
    im = Image.open(path).convert("RGBA")
    if scale_to:
        im = im.resize((scale_to, scale_to), Image.LANCZOS)
    return list(cells(im, cols, rows))

half1 = os.path.join(SRC, "expl1", "Free - 2D Explosion Animations", "Half Sized")
half2 = os.path.join(SRC, "expl2", "Free Explosion Animations 2", "Half Sized")
pack_atlas("a_expl_fire", grid_frames(os.path.join(half2, "1.png"), 8, 8, 1024), 128, "expl2", ["Half Sized/1.png"])
pack_atlas("a_expl_flare", grid_frames(os.path.join(half1, "explosion 2.png"), 8, 8, 1024), 128, "expl1", ["Half Sized/explosion 2.png"])
pack_atlas("a_expl_ring", grid_frames(os.path.join(half2, "4.png"), 8, 8, 1024), 128, "expl2", ["Half Sized/4.png"])
pack_atlas("a_hit", grid_frames(os.path.join(SRC, "hit2", "Hit-Yellow.png"), 8, 8, 1024), 128, "hit2", ["Hit-Yellow.png"], mode="mask")
pack_atlas("a_hit_arc", grid_frames(os.path.join(SRC, "hit1", "hit - yellow.png"), 8, 8, 1024), 128, "hit1", ["hit - yellow.png"], mode="mask")
for num, nm in (("08", "a_pfx_purple"), ("09", "a_pfx_firering"), ("13", "a_pfx_goldring"), ("14", "a_pfx_cyan"), ("10", "a_pfx_fireburst"), ("01", "a_pfx_sparkring")):
    fr = grid_frames(os.path.join(SRC, "particlefx1", "particlefx_%s.png" % num), 8, 8)
    pack_atlas(nm, fr, 96, "particlefx1", ["particlefx_%s.png" % num], mode="black")
lt = [Image.open(os.path.join(SRC, "lightning", "lightning", "%d.png" % i)) for i in range(11)]
pack_atlas("a_lightning", lt, (512, 128), "lightning", ["lightning/%d.png" % i for i in range(11)], mode="mask", cols=2)
ring = [Image.open(os.path.join(SRC, "bluering", "Blue Ring Explosion%d.png" % i)) for i in range(1, 20)]
pack_atlas("a_bluering", ring, 128, "bluering", ["Blue Ring Explosion1..19.png"], mode="mask", cols=5)
fire = [Image.open(p) for p in sorted(glob.glob(os.path.join(SRC, "fire", "fire_1_40", "fire_1b_40_*.png")), key=lambda p: int(p.rsplit("_", 1)[1][:-4]))]
pack_atlas("a_fire", fire, (64, 96), "fire", ["fire_1_40/fire_1b_40_*.png"], mode="black", cols=8)
ks = os.path.join(SRC, "kenney_smoke", "PNG")
bs = [Image.open(os.path.join(ks, "Black smoke", "blackSmoke%02d.png" % i)) for i in range(0, 25, 2)]
pack_atlas("a_smoke_black", bs, 128, "kenney_smoke", ["Black smoke/blackSmoke00..24.png (every 2nd)"], cols=4)
ex = [Image.open(os.path.join(ks, "Explosion", "explosion%02d.png" % i)) for i in range(9)]
pack_atlas("a_smoke_expl", ex, 160, "kenney_smoke", ["Explosion/explosion00..08.png"], cols=3)
wp = [Image.open(os.path.join(ks, "White puff", "whitePuff%02d.png" % i)) for i in range(0, 25, 2)]
pack_atlas("a_smoke_white", wp, 128, "kenney_smoke", ["White puff/whitePuff00..24.png (every 2nd)"], mode="mask", cols=4)

json.dump(source_meta, open(os.path.join(OUT, "SOURCE.json"), "w", encoding="utf8"), ensure_ascii=False, indent=1)
with open(META, "w", encoding="utf8", newline="\n") as fh:
    fh.write("extends RefCounted\n## 由 tools/build_jjk_vfx.py 生成：序列帧图集 name -> [列, 行, 帧数]。素材全部 CC0（见 vfx/SOURCE.json）。\n")
    fh.write("const ATLAS:Dictionary = {\n")
    for k, v in sorted(atlas_meta.items()):
        fh.write('\t"%s":[%d,%d,%d],\n' % (k, v[0], v[1], v[2]))
    fh.write("}\n")
print("singles", len([k for k in source_meta if k.startswith("k_")]), "atlases", len(atlas_meta))
