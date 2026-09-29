from pathlib import Path
import sys,copy,math,json
import numpy as np
from PIL import Image
B=Path(__file__).resolve().parent;O=B/'assets';O.mkdir(exist_ok=True)
# Import only class definitions, not the old script's top-level bake job.
SOURCE=B if (B/'bake.py').exists() else B.parent/'mc_new5'
p=SOURCE/'bake.py';ns={'__file__':str(p)};exec(p.read_text().split('\nb=NewBaker()')[0],ns)
NewBaker=ns['NewBaker'];OldBaker=ns['Baker']
class FixedBaker(NewBaker):
 def cube(self,cube,m,skin,role,mirror):
  # Bedrock mirror swaps the X faces of the UV box, not merely each face's U.
  # The old adapter sampled transparent atlas space on guardian's outer cheek.
  if role=='guardian' and cube.get('mirror',mirror):
   c=copy.deepcopy(cube);c['mirror']=False
   reflect=np.eye(4);reflect[0,0]=-1;reflect[0,3]=2*c['origin'][0]+c['size'][0]
   return OldBaker.cube(self,c,m@reflect,skin,role,False)
  return super().cube(cube,m,skin,role,mirror)
b=FixedBaker()
for bone in b.models['guardian']:
 if bone['name']=='eye':bone['neverRender']=True
for i in range(16):b.render('guardian','idle',i/16).save(O/f'guardian_{i:02}.png')
for bone in b.models['guardian']:bone['neverRender']=bone['name']!='eye'
b.render('guardian','idle',0).save(O/'guardian_eye.png')
# Fully textured, aligned 3D pieces. Stationary case has no duplicate sticky face.
b=FixedBaker();b.scale['piston']=5.8;b.foot['piston']=112
R=SOURCE/'resource_pack/textures/blocks'
side=Image.open(R/'piston_side.png').convert('RGBA');inner=Image.open(R/'piston_inner.png').convert('RGBA');sticky=Image.open(R/'piston_top_sticky.png').convert('RGBA');bottom=Image.open(R/'piston_bottom.png').convert('RGBA');endrod=Image.open(R/'end_rod.png').convert('RGBA')
faces=[('north',[3,2,1,0],[0,0,-1]),('south',[6,7,4,5],[0,0,1]),('east',[7,3,0,4],[-1,0,0]),('west',[2,6,5,1],[1,0,0]),('up',[7,6,2,3],[0,1,0]),('down',[0,1,5,4],[0,-1,0])]
axis=b.view@np.array([1,0,0]);angle=math.degrees(math.atan2(axis[1],axis[0]))
def part(name,boxes):
 b.rgba=np.zeros((224,160,4),np.uint8);b.depth=np.full((224,160),-1e10)
 for origin,size,texs in boxes:
  lo=np.array(origin);hi=lo+size
  verts=np.array([[lo[0],lo[1],lo[2]],[hi[0],lo[1],lo[2]],[hi[0],hi[1],lo[2]],[lo[0],hi[1],lo[2]],[lo[0],lo[1],hi[2]],[hi[0],lo[1],hi[2]],[hi[0],hi[1],hi[2]],[lo[0],hi[1],hi[2]]])
  for face,ids,normal in faces:
   if np.dot(normal,b.camera)<0:continue
   tex=texs.get(face,texs['default']);w,h=tex.size
   b.quad(verts[ids],np.eye(4),np.array([[0,0],[w,0],[w,h],[0,h]],float),np.asarray(tex),'piston',.76+.24*max(0,float(np.dot(normal,[-.35,.8,-.48]))))
 # Rotate around exact mesh origin: mechanical axis becomes screen-right.
 im=Image.fromarray(b.rgba).rotate(angle,Image.Resampling.NEAREST,center=(80,112))
 # Common origin preserved across pieces, so geometry cannot drift when extending.
 im.save(O/name)
 return im
case=part('piston_case.png',[([-8,-8,-8],[12,16,16],{'default':side.crop((0,4,16,16)),'east':bottom,'west':inner})])
head=part('piston_head_model.png',[([-2,-8,-8],[4,16,16],{'default':side.crop((0,0,16,4)),'east':inner,'west':sticky})])
shaft=part('piston_shaft_model.png',[([-8,-2,-2],[16,4,4],{'default':side.crop((4,0,12,4))})])
candle=part('end_rod_model.png',[([-7,-1,-1],[14,2,2],{'default':endrod.crop((0,0,2,15))}),([-8,-2,-2],[1,4,4],{'default':endrod.crop((2,2,6,8))})])
# Model-projected physical scale used by the Godot assembly.
(O/'piston_projection.json').write_text(json.dumps({'pixels_per_unit':float(np.linalg.norm(axis[:2])*5.8),'origin':[80,112],'axis_angle_degrees':angle}))
preview=Image.new('RGBA',(560,300),(50,60,70,255));full=Image.open(O/'guardian_00.png');full.alpha_composite(Image.open(O/'guardian_eye.png'));preview.alpha_composite(full,(0,20))
for extent,y in [(6,0),(24,135)]:
 # Preview scaled model assembly, all pieces share a single origin.
 layer=Image.new('RGBA',(600,250));layer.alpha_composite(case,(100,0));layer.alpha_composite(shaft,(100+int((extent+4)/2*5.1),0));layer.alpha_composite(head,(100+int(extent*5.1),0));layer.alpha_composite(candle,(100+int((extent+17)*5.1),0));layer=layer.resize((360,150),Image.Resampling.NEAREST);preview.alpha_composite(layer,(180,y))
preview.save(B/'corrected_models.png')
# Supplied 1024 PNGs are pixel-exact 32x32 tiles expanded 32x. Downsample nearest
# without cropping or re-centering: the expanding crescent animation stays intact.
for i in range(16):
 source=B.parent/f'uploads/explosion_{i}.png'
 if not source.exists(): source=B.parents[2]/f'Images/effects/我的世界/爆炸粒子/explosion_{i:02}.png'
 Image.open(source).convert('RGBA').resize((32,32),Image.Resampling.NEAREST).save(O/f'explosion_{i:02}.png')
print('CORRECTED',len(list(O.glob('*.png'))))
