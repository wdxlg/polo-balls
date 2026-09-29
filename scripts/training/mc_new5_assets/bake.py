from pathlib import Path
import sys,math,copy,json
import numpy as np
from PIL import Image
HERE=Path(__file__).resolve().parent
BAKER_DIR=next(p for p in [HERE.parent/'mc_native',HERE.parent/'mc_native_assets'] if (p/'bake_native_mobs.py').exists())
sys.path.insert(0,str(BAKER_DIR))
from bake_native_mobs import Baker,load_json,rotation,molang
B=Path(__file__).parent;R=B/'resource_pack';O=B/'assets';O.mkdir(exist_ok=True)
class NewBaker(Baker):
 def __init__(self):
  self.models={};self.skins={};self.scale={'slime':13.,'guardian':3.6,'ghast':1.15,'piston':5.8};self.foot={'slime':180,'guardian':160,'ghast':133,'piston':167};self.armor=False
  yaw,pitch=np.radians([30,18]);self.right=np.array([math.cos(yaw),0,math.sin(yaw)]);self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)]);self.up=np.cross(self.right,self.camera);self.view=np.array([self.right,-self.up,self.camera])
  for r,p in [('slime','slime/slime.png'),('guardian','guardian.png'),('ghast','ghast/ghast.png')]:
   j=load_json(R/f'models/entity/{r}.geo.json');g=j['minecraft:geometry'][0] if 'minecraft:geometry'in j else next(v for k,v in j.items() if k.startswith('geometry.'));self.models[r]=g['bones'];self.skins[r]=np.array(Image.open(R/'textures/entity'/p).convert('RGBA'))
  self.guard_anim=load_json(R/'animations/guardian.animation.json')['animations'];self.ghast_anim=load_json(R/'animations/ghast.animation.json')['animations']
  # Normalize Bedrock's legacy per-part absolute pivot positions into mesh bind space.
  self.spike_bind={}
  for b in self.models['guardian']:
   n=b['name']
   if n=='eye': delta=np.array([0,0,-8.25]);pivot=np.array([0,8,-8.25])
   elif n=='tailpart0':delta=np.zeros(3);pivot=np.array([0,8,7])
   elif n=='tailpart1':delta=np.array([-1.5,-.5,14]);pivot=np.array([-1.5,8,14])
   elif n=='tailpart2':delta=np.array([-1,-1,20]);pivot=np.array([-1,8,20])
   elif n.startswith('spike'):
    env={'this':0,'query.life_time':0,'variable.spike_extension':0,'variable.spike_shake':0}
    pivot=np.array([molang(v,env) for v in self.guard_anim['animation.guardian.spikes']['bones'][n]['position']]);delta=pivot-np.array(b['pivot']);self.spike_bind[n]=pivot
   else:continue
   b['pivot']=pivot.tolist()
   for c in b.get('cubes',[]):c['origin']=(np.array(c['origin'])+delta).tolist()
 def pose(self,role,state,t,peek=0):
  out={b['name'].lower():{'rotation':np.array(b.get('rotation',[0,0,0]),float),'position':np.zeros(3),'scale':np.ones(3)} for b in self.models[role]}
  if role=='ghast':
   for n,channels in self.ghast_anim['animation.ghast.move']['bones'].items():out[n]['rotation']=np.array([molang(x,{'query.life_time':t}) for x in channels['rotation']])
  if role=='guardian':
   for n,channels in self.guard_anim['animation.guardian.setup']['bones'].items():out[n]['rotation']=np.array([molang(x,{'this':0}) for x in channels['rotation']])
   for i in range(3):out[f'tailpart{i}']['rotation'][1]=math.sin(t*math.tau)*[11.6,22.8,34.4][i]
  return out
 def cube(self,cube,m,skin,role,mirror):
  # Bedrock mirrored cubes exchange X faces as well as U orientation.
  if role=='guardian' and cube.get('mirror',mirror):
   c=copy.deepcopy(cube);c['mirror']=False
   reflect=np.eye(4);reflect[0,0]=-1;reflect[0,3]=2*c['origin'][0]+c['size'][0]
   return super().cube(c,m@reflect,skin,role,False)
  if not isinstance(cube['uv'],dict):return super().cube(cube,m,skin,role,mirror)
  lo=np.array(cube['origin']);hi=lo+cube['size'];verts=np.array([[lo[0],lo[1],lo[2]],[hi[0],lo[1],lo[2]],[hi[0],hi[1],lo[2]],[lo[0],hi[1],lo[2]], [lo[0],lo[1],hi[2]],[hi[0],lo[1],hi[2]],[hi[0],hi[1],hi[2]],[lo[0],hi[1],hi[2]]])
  for face,ids,normal in [('north',[3,2,1,0],[0,0,-1]),('south',[6,7,4,5],[0,0,1]),('east',[7,3,0,4],[-1,0,0]),('west',[2,6,5,1],[1,0,0]),('up',[7,6,2,3],[0,1,0]),('down',[0,1,5,4],[0,-1,0])]:
   uv=cube['uv'].get(face)
   if not uv:continue
   n=m[:3,:3]@normal;n=n/np.linalg.norm(n)
   if np.dot(n,self.camera)<-.001:continue
   a,b=uv['uv'];c,d=uv['uv_size'];self.quad(verts[ids],m,np.array([[a,b],[a+c,b],[a+c,b+d],[a,b+d]],float)*np.array([skin.shape[1]/64,skin.shape[0]/32]),skin,role,.76+.24*max(0,float(np.dot(n,[-.35,.8,-.48]))))
b=NewBaker()
for role,count in [('slime',1),('guardian',16),('ghast',16)]:
 for i in range(count):
  im=b.render(role,'idle',i/count)
  if role=='slime':
   saved=b.models[role];b.models[role]=[{'name':'cube','pivot':[0,0,0],'cubes':[{'origin':[-4,0,-4],'size':[8,8,8],'uv':[0,0]}]}]
   shell=b.render(role,'idle',0);ar=np.array(shell);ar[:,:,3]=(ar[:,:,3].astype(float)*.3).astype('uint8');im=Image.alpha_composite(im,Image.fromarray(ar));b.models[role]=saved
  im.save(O/f'{role}_{i:02}.png');assert im.getbbox()[0]>0 and im.getbbox()[2]<160,(role,im.getbbox())
 if role=='ghast':
  b.skins[role]=np.array(Image.open(R/'textures/entity/ghast/ghast_shooting.png').convert('RGBA'))
  for i in range(count):b.render(role,'idle',i/count).save(O/f'ghast_shoot_{i:02}.png')
# Block geometry adapter: original 16x16 block faces arranged on a standard box UV net.
skin=Image.new('RGBA',(64,32))
for box,name in [((0,16),'piston_side'),((16,16),'piston_top_sticky'),((32,16),'piston_side'),((48,16),'piston_bottom'),((16,0),'piston_side'),((32,0),'piston_side')]:skin.paste(Image.open(R/f'textures/blocks/{name}.png').convert('RGBA'),box)
b.skins['piston']=np.array(skin);b.models['piston']=[{'name':'body','pivot':[0,0,0],'cubes':[{'origin':[-8,0,-8],'size':[16,16,16],'uv':[0,0]}]}];b.render('piston','idle',0).save(O/'piston.png')
for key,p in {'fishing_rod':'items/fishing_rod_uncast','fishing_rod_cast':'items/fishing_rod_cast','iron_sword':'items/iron_sword','fireball':'items/fireball','piston_head':'blocks/piston_top_sticky','piston_rod':'blocks/piston_inner','end_rod':'blocks/end_rod','guardian_beam':'entity/guardian_beam'}.items():Image.open(R/f'textures/{p}.png').convert('RGBA').save(O/f'{key}.png')
# Make frames resources, referencing immutable official-texture rasterizations.
for role,count in [('slime',1),('guardian',16),('ghast',16)]:
 paths=[f'{role}_{i:02}.png' for i in range(count)]+([f'ghast_shoot_{i:02}.png' for i in range(count)] if role=='ghast' else [])
 s='[gd_resource type="SpriteFrames" load_steps=%d format=3]\n'%(len(paths)+1)
 for i,p in enumerate(paths):s+='[ext_resource type="Texture2D" path="res://Images/characters/我的世界/new5/'+p+'" id="'+str(i+1)+'"]\n'
 clips=[]
 for name,start in [('idle',0)]+([('shoot',count)] if role=='ghast' else []):
  clips.append('{"frames":['+','.join('{"duration":1.0,"texture":ExtResource("%d")}'%(start+i+1) for i in range(count))+'],"loop":true,"name":&"'+name+'","speed":16.0}')
 s+='[resource]\nanimations = ['+','.join(clips)+']\n';(O/f'{role}.tres').write_text(s)
contact=Image.new('RGBA',(640,224),(32,42,53,255))
for i,r in enumerate(['slime','guardian','ghast','piston']):im=Image.open(O/(r+'_00.png' if r!='piston' else'piston.png'));contact.alpha_composite(im,(i*160,0))
contact.save(B/'models_preview.png')


# Original eye mesh as a separately translated gaze layer, not a painted eye.
eye_baker=NewBaker()
for bone in eye_baker.models['guardian']:
 if bone['name']=='eye': bone['neverRender']=True
for i in range(16):eye_baker.render('guardian','idle',i/16).save(O/f'guardian_{i:02}.png')
for bone in eye_baker.models['guardian']:bone['neverRender']=bone['name']!='eye'
eye_baker.render('guardian','idle',0).save(O/'guardian_eye.png')
Image.open(R/'textures/entity/fishhook.png').convert('RGBA').crop((9,0,12,3)).save(O/'fishhook.png')
im=Image.open(R/'textures/blocks/end_rod.png').convert('RGBA');rod=Image.new('RGBA',(30,8))
rod.alpha_composite(im.crop((0,0,2,15)).resize((4,28),Image.Resampling.NEAREST).rotate(-90,expand=True),(2,2))
rod.alpha_composite(im.crop((2,2,6,8)).resize((4,8),Image.Resampling.NEAREST),(0,0))
rod.save(O/'end_rod_assembled.png')
print('BAKED',len(list(O.glob('*'))))
