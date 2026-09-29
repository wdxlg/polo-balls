from pathlib import Path
import numpy as np,math,json
from PIL import Image
B=Path(__file__).resolve().parent;O=B/'assets';O.mkdir(exist_ok=True);p=B/'bake.py' if (B/'bake.py').exists() else B.parent/'mc_new5/bake.py';ns={'__file__':str(p)};exec(p.read_text().split('\nb=NewBaker()')[0],ns)
b=ns['NewBaker']();rot=ns['rotation'];b.scale['guardian']=2.;b.foot['guardian']=80
original=b.cube;orientation=np.eye(4)
def cube(c,m,skin,role,mirror):return original(c,orientation@m,skin,role,mirror)
b.cube=cube
# Translate the *model centre* to the image origin before yaw. Every view has
# exactly the same pivot; never rotate a slanted, off-centre 2D picture.
centre=np.eye(4);centre[:3,3]=[0,-8,0]
N=64;F=8;atlas=Image.new('RGBA',(160*N,160*F));eyes=[];bounds=[]
angles=np.arange(0,360,.1);candidates=[]
for yaw in angles:
 v=b.view@(rot([0,yaw,0])@np.array([0,0,-1]));candidates.append(v[:2]/np.linalg.norm(v[:2]))
candidates=np.array(candidates)
for view in range(N):
 desired=np.array([math.cos(view*math.tau/N),math.sin(view*math.tau/N)])
 yaw=float(angles[np.argmax(candidates@desired)]);orientation=np.eye(4);orientation[:3,:3]=rot([0,yaw,0]);orientation=orientation@centre
 eye=b.view@(orientation@np.array([0,7,-7.75,1]))[:3];eyes.append((eye[:2]*2).tolist())
 for frame in range(F):
  im=b.render('guardian','idle',frame/F).crop((0,0,160,160));box=im.getbbox();assert box and min(box[:2])>1 and max(box[2:])<159,(view,frame,box)
  atlas.alpha_composite(im,(view*160,frame*160));bounds.append(box)
 print(view,flush=True) if view%16==0 else None
atlas.save(O/'guardian_turns.png',optimize=True)
atlas.crop((32*160,0,33*160,160)).save(O/'guardian_still.png')
s='[gd_resource type="SpriteFrames" load_steps=%d format=3]\n[ext_resource type="Texture2D" path="res://Images/characters/我的世界/new5/guardian_turns.png" id="atlas"]\n'%(N*F+2)
for v in range(N):
 for f in range(F):s+=f'[sub_resource type="AtlasTexture" id="a{v}_{f}"]\natlas = ExtResource("atlas")\nregion = Rect2({v*160}, {f*160}, 160, 160)\nfilter_clip = true\n'
s+='[resource]\nanimations = ['
s+=','.join('{"name":&"v%02d","speed":8.0,"loop":true,"frames":['%v+','.join('{"duration":1.0,"texture":SubResource("a%d_%d")}'%(v,f) for f in range(F))+']}' for v in range(N))+']\n';(O/'guardian_turns.tres').write_text(s)
(O/'guardian_turns.json').write_text(json.dumps({'views':N,'frames':F,'size':[160,160],'model_pivot':[0,8,0],'eye_offsets':eyes,'bounds':bounds}))
preview=Image.new('RGBA',(640,320),(45,55,65,255))
for i,v in enumerate([0,8,16,24,32,40,48,56]):preview.alpha_composite(atlas.crop((160*v,0,160*v+160,160)),((i%4)*160,(i//4)*160))
preview.save(B/'guardian_views.png');print('ATLAS', (O/'guardian_turns.png').stat().st_size)
