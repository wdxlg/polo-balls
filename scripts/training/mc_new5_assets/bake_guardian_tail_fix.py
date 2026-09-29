from pathlib import Path
import math,json,numpy as np
from PIL import Image
B=Path(__file__).resolve().parent
p=B/'bake.py';ns={'__file__':str(p)};exec(p.read_text().split('\nb=NewBaker()')[0],ns)
b=ns['NewBaker']();rot=ns['rotation'];molang=ns['molang'];b.scale['guardian']=2.;b.foot['guardian']=80
original=b.cube;orientation=np.eye(4)
# The native 1x9x9 fin's opposite broad face points at fully transparent texels.
# Reuse its authored 9x9 fin artwork on that face, retaining depth/occlusion.
original_quad=b.quad;drawing_fin=False
def quad(points,m,uv,skin,role,lighting):
 if drawing_fin and np.allclose(uv.min(axis=0),[35,28]) and np.allclose(uv.max(axis=0),[44,37]):
  uv=uv.copy();uv[:,0]-=10
 return original_quad(points,m,uv,skin,role,lighting)
b.quad=quad
def cube(c,m,skin,role,mirror):
 global drawing_fin
 drawing_fin=role=='guardian' and c['size']==[1,9,9] and c['uv']==[25,19]
 try: return original(c,orientation@m,skin,role,mirror)
 finally: drawing_fin=False
b.cube=cube
original_pose=b.pose;extension=1.0
def pose(role,state,t,peek=0):
 out=original_pose(role,state,t,peek)
 for name,channels in b.guard_anim['animation.guardian.spikes']['bones'].items():
  env={'this':0,'query.life_time':0,'variable.spike_extension':extension,'variable.spike_shake':0}
  out[name]['position']=np.array([molang(v,env) for v in channels['position']])-b.spike_bind[name]
 return out
b.pose=pose
centre=np.eye(4);centre[:3,3]=[0,-8,0]
N=64;F=8
angles=np.arange(0,360,.1);candidates=[]
for yaw in angles:
 v=b.view@(rot([0,yaw,0])@np.array([0,0,-1]));candidates.append(v[:2]/np.linalg.norm(v[:2]))
candidates=np.array(candidates)
O=B/'retraction';O.mkdir(exist_ok=True)
for state,value in [('retracted',1.0),('half',0.5),('extended',0.0)]:
 extension=value;atlas=Image.new('RGBA',(160*N,160*F))
 for view in range(N):
  desired=np.array([math.cos(view*math.tau/N),math.sin(view*math.tau/N)])
  yaw=float(angles[np.argmax(candidates@desired)]);orientation=np.eye(4);orientation[:3,:3]=rot([0,yaw,0]);orientation=orientation@centre
  for frame in range(F):
   im=b.render('guardian','idle',frame/F).crop((0,0,160,160));atlas.alpha_composite(im,(view*160,frame*160))
 atlas.save(O/f'guardian_{state}.webp',lossless=True,method=6)
 s=f'[gd_resource type="SpriteFrames" load_steps={N*F+2} format=3]\n[ext_resource type="Texture2D" path="res://Images/characters/我的世界/new5/guardian_{state}.webp" id="atlas"]\n'
 for view in range(N):
  for frame in range(F):s+=f'[sub_resource type="AtlasTexture" id="a{view}_{frame}"]\natlas = ExtResource("atlas")\nregion = Rect2({view*160}, {frame*160}, 160, 160)\nfilter_clip = true\n'
 s+='[resource]\nanimations = ['+','.join('{"name":&"v%02d","speed":8.0,"loop":true,"frames":['%view+','.join('{"duration":1.0,"texture":SubResource("a%d_%d")}'%(view,frame) for frame in range(F))+']}' for view in range(N))+']\n'
 (O/f'guardian_{state}.tres').write_text(s)
 atlas.crop((32*160,0,33*160,160)).resize((480,480),Image.Resampling.NEAREST).save(O/f'preview_{state}.png')
 print(state,'baked',flush=True)
