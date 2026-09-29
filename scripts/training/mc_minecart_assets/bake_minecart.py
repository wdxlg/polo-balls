#!/usr/bin/env python3
"""Orthographic direction/rolling frames from Mojang's unmodified minecart v1.0 model.
Same offline model-to-SpriteFrames approach as guardian. No painted replacement art.
The original animation consumes rail offset/rotation; a small periodic rail profile
adapts that input to free movement in this game. Vanilla has no animated wheel bones.
"""
from pathlib import Path
import argparse, importlib.util, hashlib, json, math
import numpy as np
from PIL import Image
B = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=B/'resource_pack')
parser.add_argument('--output', type=Path, default=B.parents[2]/'Images/characters/我的世界/矿车')
parser.add_argument('--baker', type=Path, default=B.parent/'mc_native_assets/bake_native_mobs.py')
a = parser.parse_args()
spec = importlib.util.spec_from_file_location('minecart_shared_baker', a.baker)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
module.W = module.H = 128
N, F, SIZE, COLS = 64, 9, 128, 32
MODEL='models/entity/minecart_v1.0.geo.json'
SKIN='textures/entity/minecart.png'
ANIM='animations/minecart.animation.v1.0.json'
expected={MODEL:'',SKIN:'',ANIM:''} # hashes below are filled from the pinned source manifest.
manifest_path=B.parents[2]/'MC_MINECART_ASSETS.json'
if manifest_path.exists():
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    expected.update({f['path']:f['sha256'] for f in manifest['files'] if f['path'] in expected})
source_hashes={p:hashlib.sha256((a.source/p).read_bytes()).hexdigest() for p in expected}
for path, digest in expected.items():
    if digest: assert source_hashes[path]==digest, path
class CartBaker(module.Baker):
    def __init__(self):
        geometry=module.load_json(a.source/MODEL)['minecraft:geometry'][0]
        self.models={'cart':geometry['bones']}
        self.skins={'cart':np.array(Image.open(a.source/SKIN).convert('RGBA'))}
        assert self.skins['cart'].shape[:2] == (32,64)
        self.channels=module.load_json(a.source/ANIM)['animations']['animation.minecart.move.v1.0']['bones']['root']
        self.scale={'cart':4.2}; self.foot={'cart':64}
        yaw,pitch=np.radians([30,28])
        self.right=np.array([math.cos(yaw),0,math.sin(yaw)])
        self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
        self.up=np.cross(self.right,self.camera)
        self.view=np.array([self.right,-self.up,self.camera])
        self.orientation=np.eye(4)
    def pose(self,role,state,t,peek=0):
        poses={b['name'].lower():{'rotation':np.array(b.get('rotation',[0,0,0]),float),'position':np.zeros(3),'scale':np.ones(3)} for b in self.models[role]}
        moving=state=='move'
        env={'math.pi':math.pi,'variable.rail_offset.x':0,'variable.rail_offset.y':0.18*math.sin(t*math.tau*2) if moving else 0,'variable.rail_offset.z':0,'query.model_scale':1,'variable.hurt':0,'query.structural_integrity':40,'query.frame_alpha':0,'query.hurt_direction':1,'variable.rail_rotation.z':2.8*math.sin(t*math.tau) if moving else 0}
        for channel, values in self.channels.items():
            poses['root'][channel]=np.array([module.molang(v,env) for v in values])
        return poses
    def cube(self,cube,m,skin,role,mirror):
        return super().cube(cube,self.orientation@m,skin,role,mirror)
b=CartBaker()
# The authored root is y=24; the native rail translation is -18.5 -> shared pivot y=5.5.
centre=np.eye(4); centre[:3,3]=[0,-5.5,0]
angles=np.arange(0,360,0.1)
vectors=np.array([(b.view@(module.rotation([0,y,0])@np.array([1,0,0])))[:2] for y in angles])
vectors/=np.linalg.norm(vectors,axis=1)[:,None]
atlas=Image.new('RGBA',(SIZE*COLS,SIZE*math.ceil(N*F/COLS)))
records=[]; views=[]
for v in range(N):
    desired=np.array([math.cos(v*math.tau/N),math.sin(v*math.tau/N)])
    yaw=float(angles[np.argmax(vectors@desired)])
    projected=vectors[np.argmax(vectors@desired)]
    assert float(projected@desired)>0.99999
    b.orientation=np.eye(4); b.orientation[:3,:3]=module.rotation([0,yaw,0]); b.orientation=b.orientation@centre
    views.append({'index':v,'screen_direction':desired.tolist(),'model_yaw_degrees':yaw})
    hashes=[]
    for f in range(F):
        im=b.render('cart','idle' if f==0 else 'move',(f-1)/8 if f else 0)
        box=im.getbbox(); assert box and min(box[:2])>=3 and max(box[2:])<=125,(v,f,box)
        slot=v*F+f; x=(slot%COLS)*SIZE; y=(slot//COLS)*SIZE
        atlas.alpha_composite(im,(x,y))
        digest=hashlib.sha256(im.tobytes()).hexdigest();hashes.append(digest)
        records.append({'view':v,'frame':f,'rect':[x,y,SIZE,SIZE],'bounds':list(box),'pixel_sha256':digest})
    assert len(set(hashes[1:]))>=4, (v,'static rolling cycle')
    if v%16==0:print('BAKE view',v,flush=True)
a.output.mkdir(parents=True,exist_ok=True)
atlas.save(a.output/'minecart_turns.png',optimize=True)
preview=records[56*F];x,y,w,h=preview['rect'];atlas.crop((x,y,x+w,y+h)).save(a.output/'minecart_preview.png')
text=f'[gd_resource type="SpriteFrames" load_steps={N*F+2} format=3]\n\n[ext_resource type="Texture2D" path="res://Images/characters/我的世界/矿车/minecart_turns.png" id="atlas"]\n'
for r in records:
    x,y,w,h=r['rect'];text+=f'\n[sub_resource type="AtlasTexture" id="v{r["view"]:02d}_{r["frame"]}"]\natlas = ExtResource("atlas")\nregion = Rect2({x}, {y}, {w}, {h})\nfilter_clip = true\n'
text+='\n[resource]\nanimations = [\n'
clips=[]
for v in range(N):
    frames=','.join('{"duration":1.0,"texture":SubResource("v%02d_%d")}'%(v,f) for f in range(F))
    clips.append('{"name":&"v%02d","speed":8.0,"loop":true,"frames":[%s]}'%(v,frames))
text+=',\n'.join(clips)+'\n]\n';(a.output/'minecart_turns.tres').write_text(text,encoding='utf-8')
outputs={p:hashlib.sha256((a.output/p).read_bytes()).hexdigest() for p in ['minecart_turns.png','minecart_turns.tres','minecart_preview.png']}
meta={'views':N,'frames_per_view':F,'neutral_frame':0,'rolling_frames':[1,8],'frame_size':[SIZE,SIZE],'atlas_size':list(atlas.size),'world_model_pivot':[0,5.5,0],'native_source_sha256':source_hashes,'baker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'outputs_sha256':outputs,'animation_adapter':'Native root channels evaluated against a 0.18-unit rail vertical offset and +/-2.8 degree rail pitch. Eight samples per cycle; speed is controlled at runtime. No invented wheels or edited texture pixels.','directions':views,'frames':records}
(a.output/'minecart_turns.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
print('MINECART MODEL BAKE:',N,'directions x',F,'poses;',atlas.size,'atlas;',len(records),'validated frames',flush=True)
