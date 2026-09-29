"""Bake ONE tile for each grid connection mask/power state from pinned native rail art.
Straight/ordinary corners preserve native source pixels. Powered corners and junctions
are clearly identified arena-derived visuals; Minecraft does not supply these blocks.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, math
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT/'Images/characters/我的世界/矿车'
normal = Image.open(OUT/'rail_normal.png').convert('RGBA')
curve = Image.open(OUT/'rail_normal_turned.png').convert('RGBA')
powered = Image.open(OUT/'rail_golden_powered.png').convert('RGBA')
assert normal.size == curve.size == powered.size == (16,16)
atlas = Image.new('RGBA',(256,32))
# Bits: right, down, left, up. Native corner opens right and down.
rotations = {3:0,6:1,12:2,9:3}

def powered_corner():
    result = curve.copy()
    for y in range(16):
        for x in range(16):
            r,g,b,a = result.getpixel((x,y))
            if a and max(r,g,b)-min(r,g,b) < 40:
                result.putpixel((x,y),(min(255,int(r*1.2)),min(255,int(g*.87)),int(b*.3),a))
    draw = ImageDraw.Draw(result)
    points = [(round(15+7*math.cos(t)),round(15+7*math.sin(t))) for t in [(-90-i*90/20)*math.pi/180 for i in range(21)]]
    draw.line(points,fill=(230,28,14,255),width=2)
    return result

for power in (False,True):
    base = powered if power else normal
    horizontal = base.transpose(Image.Transpose.ROTATE_90)
    for mask in range(1,16):
        if mask in rotations:
            tile = powered_corner() if power else curve.copy()
            tile = tile.rotate(-90*rotations[mask])
        elif mask in (1,4,5):
            tile = horizontal.copy()
        elif mask in (2,8,10):
            tile = base.copy()
        else:
            # Branches are composited offline into one texture, not stacked runtime rails.
            tile = Image.new('RGBA',(16,16))
            if mask & 8: tile.alpha_composite(base.crop((0,0,16,9)),(0,0))
            if mask & 2: tile.alpha_composite(base.crop((0,7,16,16)),(0,7))
            if mask & 4: tile.alpha_composite(horizontal.crop((0,0,9,16)),(0,0))
            if mask & 1: tile.alpha_composite(horizontal.crop((7,0,16,16)),(7,0))
        atlas.alpha_composite(tile,(mask*16,16 if power else 0))
atlas.save(OUT/'rail_grid_tiles.png',optimize=True)
meta = {'cell_texture_size':[16,16],'mask_bits':{'right':1,'down':2,'left':4,'up':8},'rows':{'ordinary':0,'powered':1},'source_sha256':{name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in ['rail_normal.png','rail_normal_turned.png','rail_golden_powered.png']},'output_sha256':hashlib.sha256((OUT/'rail_grid_tiles.png').read_bytes()).hexdigest(),'notice':'Mojang/Microsoft source art, subject to Minecraft EULA. Powered corners and junctions are derived arena UI representations, not claimed vanilla block types.'}
(OUT/'rail_grid_tiles.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
print('RAIL_GRID_ATLAS: 15 connection masks x 2 power states; one texture quad per cell.')
