#!/usr/bin/env python3
"""Second batch. Pinned Mojang Bedrock data; see README/NOTICE and LICENSE.
Uses the shared offline renderer; runtime needs neither Python nor a 3D viewport.
"""
import copy,json,math,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from bake_native_mobs import Baker,ROOT,W,H,load_json,molang,rotation

ROLES=('witch','blaze','creeper','silverfish','skeleton','fang')
CLIPS={
 'witch':{'idle':(32,360/57.296,True),'walk':(24,1,True),'hold':(24,360/57.296,True),'drink':(24,.78,True)},
 'blaze':{'idle':(240,10,True)},
 'creeper':{'idle':(1,1,True),'walk':(24,1,True),'fuse':(32,1,False),'fuse_walk':(32,1,False),'idle_charged':(24,2,True),'walk_charged':(24,1,True),'fuse_charged':(32,1,False),'fuse_walk_charged':(32,1,False)},
 'silverfish':{'idle':(24,360/1031.4,True),'walk':(24,360/1031.4,True)},
 'skeleton':{'idle':(32,360/103.2,True),'walk':(24,1,True),'shoot':(24,.45,False)},
 'fang':{'bite':(40,1,False)}}

class BatchBaker(Baker):
 def __init__(self):
  super().__init__(ROOT/'resource_pack')
  for n in (*ROLES[:-1],'villager','evocation_fang'):
   self.animations.update(load_json(self.source/f'animations/{n}.animation.json')['animations'])
  for role in ROLES:
   file='evocation_fang.json' if role=='fang' else role+'.geo.json'
   data=load_json(self.source/f'models/entity/{file}')
   geo=next(v for k,v in data.items() if k.startswith('geometry.'))
   bones=copy.deepcopy(geo['bones'])
   if role=='witch':
    villager=load_json(self.source/'models/entity/villager.geo.json')
    base=copy.deepcopy(next(v for k,v in villager.items() if k.startswith('geometry.'))['bones'])
    lookup={b['name']:b for b in base}
    for b in bones:
     if b['name'] in lookup:
      old=lookup[b['name']];old['cubes']=old.get('cubes',[])+b.get('cubes',[])
      old.update({k:v for k,v in b.items() if k!='cubes'})
     else: base.append(b)
    bones=base
   for b in bones:
    b.setdefault('pivot',[0,0,0])
    if 'bind_pose_rotation' in b:b['rotation']=b['bind_pose_rotation']
   self.models[role]=bones
  for role,path in {'witch':'witch.png','blaze':'blaze.tga','creeper':'creeper/creeper.png','silverfish':'silverfish.png','skeleton':'skeleton/skeleton.png','fang':'illager/fangs.png','armor':'creeper/creeper_armor.png'}.items():
   self.skins[role]=np.array(Image.open(self.source/'textures/entity'/path).convert('RGBA'))
  self.skins['blaze'][:,:,3]=255 # emissivity, not cutout opacity
  armor=self.skins['armor'];armor[:,:,3]=(armor[:,:,:3].max(axis=2)*.55).astype(np.uint8)
  self.bows={k:np.array(Image.open(self.source/f'textures/items/{v}.png').convert('RGBA')) for k,v in {'idle':'bow_standby','shoot':'bow_pulling_2'}.items()}
  self.scale.update({'witch':3.9,'blaze':5.0,'creeper':5.0,'silverfish':5.0,'skeleton':4.5,'fang':4.4})
  self.foot.update({'witch':201,'blaze':199,'creeper':190,'silverfish':160,'skeleton':201,'fang':199})
  self._role='';self._armor=False

 def pose(self,role,state,t,peek=0):
  plain=state.removesuffix('_charged')
  walk=plain in ('walk','fuse_walk')
  progress=max(0,min(t,1))
  env={'this':0,'query.life_time':t,'query.anim_time':t*360/38.17,
       'variable.tcos0':math.cos(t*math.tau)*32 if walk else 0,
       'variable.isholdingitem':float(state in ('hold','drink')),
       'variable.is_holding_left':0,'variable.is_holding_right':1,
       'query.target_x_rotation':0,'query.target_y_rotation':0,
       'variable.attack_time':min(t/.45,1)}
  pose={b['name'].lower():{'position':np.zeros(3),'rotation':np.array(b.get('rotation',[0,0,0]),float),'scale':np.ones(3)} for b in self.models[role]}
  if role=='witch':names=['villager.general']+(['villager.move'] if walk else [])+['witch.general']
  elif role=='blaze':names=['blaze.move']
  elif role=='silverfish':names=['silverfish.move']
  elif role=='skeleton':names=['humanoid.move','humanoid.holding','humanoid.bob','humanoid.bow_and_arrow'] if state=='shoot' else ['humanoid.move','humanoid.bob']
  elif role=='fang':
   env['variable.bite_amount']=(1-min(progress*2,1)**3)*.35*180
   env['variable.y_offset']=(progress+math.sin(math.radians(progress*2.7*80)))*.6*12
   names=['evocation_fang.bite']
  else:
   swell=progress if plain.startswith('fuse') else 0
   wobble=math.sin(math.radians(swell*5730))*swell*.01+1
   env.update({'variable.leg_rot':math.cos(t*math.tau)*32 if walk else 0,'variable.swelling_scale1':(swell**4*.4+1)*wobble,'variable.swelling_scale2':(swell**4*.1+1)/wobble})
   names=['creeper.legs','creeper.swelling']
  for n in names:
   for bone,channels in self.animations['animation.'+n]['bones'].items():
    p=pose.get(bone.lower())
    if p is None:continue
    for channel,values in channels.items():
     if channel not in p:continue
     if isinstance(values,(int,float,str)):values=[values]*3
     for i,v in enumerate(values):
      env['this']=p[channel][i];value=molang(v,env)
      if channel=='scale':p[channel][i]=value
      else:p[channel][i]+=value
  if role=='creeper':
   # These per-bone sample scales are model-global in the Bedrock creeper path;
   # avoid double-applying swelling through the imported body-parent hierarchy.
   for b,p in pose.items():
    if b!='body':p['scale']=np.ones(3)
  if role=='fang' and progress>.9:
   shrink=max(0,(1-progress)/.1)
   pose['base']['scale']*=shrink;pose['base']['position']*=shrink
  return pose

 def matrices(self,role,state,t):
  poses=self.pose(role,state,t); bones={b['name'].lower():b for b in self.models[role]};out={}
  def get(n):
   n=n.lower()
   if n in out:return out[n]
   b=bones[n];p=poses[n];pivot=np.array(b['pivot'],float);m=np.eye(4)
   m[:3,:3]=rotation(p['rotation'])@np.diag(p['scale']);m[:3,3]=pivot+p['position']-m[:3,:3]@pivot
   if b.get('parent'):m=get(b['parent'])@m
   out[n]=m;return m
  for n in bones:get(n)
  return out

 def render(self,role,state,t,peek=0):
  self._role=role
  yaw,pitch=np.radians([60,22] if role=='silverfish' else [30,12])
  self.right=np.array([math.cos(yaw),0,math.sin(yaw)])
  self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
  self.up=np.cross(self.right,self.camera);self.view=np.array([self.right,-self.up,self.camera])
  super().render(role,state,t,peek)
  if role=='skeleton':
   # Grip is the middle of the actual distal right-arm face, not the old
   # rightItem locator (which sits above the hand on this thin skeleton model).
   m=self.matrices(role,state,t)['rightarm']
   center=m[:3,:3]@np.array([-5.0,12.75,-1.05])+m[:3,3]
   # Native bow icons are diagonal. Rotate their handle pixel (5.5,5.5)
   # about the palm, rather than attaching the center of a padded icon.
   # 17 model units per 16 texels gives a full-size, vertically held bow.
   uv=np.array([[0,0],[16,0],[16,16],[0,16]],float)
   local=(uv-np.array([5.5,5.5]))*(17.0/16.0)
   # Lower the bow by a quarter turn while the arm hangs/rests or walks.
   # Only the shooting clip raises the bow into the unchanged aiming pose.
   angle=math.radians(-45.0 if state=='shoot' else -135.0)
   sx=local[:,0]*math.cos(angle)-local[:,1]*math.sin(angle)
   sy=local[:,0]*math.sin(angle)+local[:,1]*math.cos(angle)
   bow_side=self.right if state=='shoot' else self.right*0.75-self.camera*math.sqrt(1.0-0.75**2)
   pts=center+sx[:,None]*bow_side-sy[:,None]*self.up
   self.quad(pts,np.eye(4),uv,self.bows['shoot' if state=='shoot' else 'idle'],role,1.0)
  if role=='creeper' and state.endswith('_charged'):
   mats=self.matrices(role,state,t);self._armor=True
   skin=np.roll(self.skins['armor'],int(t*8),axis=0)
   for b in self.models[role]:
    for c in b.get('cubes',[]):
     c=copy.deepcopy(c);c['inflate']=2.0;self.cube(c,mats[b['name'].lower()],skin,role,b.get('mirror',False))
   self._armor=False
  return Image.fromarray(self.rgba)

 def quad(self,points,m,uv,skin,role,lighting):
  if role=='fang':
   points=points@m[:3,:3].T+m[:3,3];m=np.eye(4)
   # The real terrain occludes the underground base. Clip geometry, not the
   # entire image, so jaws emerge through the projected ground plane correctly.
   poly=[]
   for i in range(len(points)):
    a,at=points[i-1],uv[i-1];b,bt=points[i],uv[i];inside_a=a[1]>=0;inside_b=b[1]>=0
    if inside_a!=inside_b:
     f=-a[1]/(b[1]-a[1]);poly.append((a+(b-a)*f,at+(bt-at)*f))
    if inside_b:poly.append((b,bt))
   if len(poly)<3:return
   for i in range(1,len(poly)-1):
    triangle=[poly[0],poly[i],poly[i+1],poly[i+1]]
    super().quad(np.array([p for p,u in triangle]),m,np.array([u for p,u in triangle]),skin,role,lighting)
   return
  if not self._armor:return super().quad(points,m,uv,skin,role,lighting)
  before=self.rgba.copy();before_depth=self.depth.copy()
  super().quad(points,m,uv,skin,role,lighting)
  changed=(self.depth>before_depth)&(self.rgba[:,:,3]>0)&(self.rgba[:,:,3]<255)
  a=self.rgba[:,:,3:4].astype(float)/255;b=before[:,:,3:4].astype(float)/255;out=a+b*(1-a)
  rgb=(self.rgba[:,:,:3]*a+before[:,:,:3]*b*(1-a))/np.maximum(out,1e-8)
  composed=np.concatenate([rgb,out*255],axis=2).clip(0,255).astype(np.uint8)
  self.rgba[changed]=composed[changed]

def bake():
 out=ROOT/'frames_batch2';out.mkdir(exist_ok=True);b=BatchBaker();meta={'size':[W,H],'roles':{},'source_commit':(ROOT/'commit.txt').read_text().strip()};contact=[]
 for role,clips in CLIPS.items():
  files=[];dedup={};anims=[];info={'clips':{},'foot_y':b.foot[role]}
  for state,(count,duration,loop) in clips.items():
   ids=[];images=[]
   for i in range(count):
    fraction=i/count if loop else i/max(count-1,1)
    im=b.render(role,state,fraction*duration);bb=im.getbbox()
    if bb:assert bb[0]>0 and bb[1]>0 and bb[2]<W and bb[3]<H,(role,state,i,bb)
    else:assert role=='fang' and i==count-1,(role,state,i)
    h=hashlib.sha256(im.tobytes()).hexdigest()
    if h not in dedup:
     file=f'{role}_{len(files):03}.png';im.save(out/file,optimize=True);files.append(file);dedup[h]=len(files)
    ids.append(dedup[h]);images.append(im)
   info['clips'][state]={'count':count,'duration':duration,'loop':loop,'unique':len(set(ids))}
   anims.append('{"frames":['+', '.join('{"duration":1.0,"texture":ExtResource("'+str(n)+'")}' for n in ids)+'],"loop":'+str(loop).lower()+',"name":&"'+state+'","speed":'+str(count/duration)+'}')
   if state in ('idle','walk','drink','shoot','fuse','bite','idle_charged'):contact.append((role+'/'+state,images))
  neutral='bite' if role=='fang' else 'idle';neutral_time=.5 if role=='fang' else 0
  info['neutral_bounds']=list(b.render(role,neutral,neutral_time).getbbox());info['textures']=len(files);meta['roles'][role]=info
  if role=='witch':
   point=np.array([0,24,-7.0])@b.view.T;info['mouth']=[float(point[0]*b.scale[role]+W/2),float(point[1]*b.scale[role]+b.foot[role])]
  resource='[gd_resource type="SpriteFrames" format=3]\n\n'+'\n'.join('[ext_resource type="Texture2D" path="res://Images/characters/我的世界/native_frames/'+f+'" id="'+str(i+1)+'"]' for i,f in enumerate(files))+'\n\n[resource]\nanimations=['+',\n'.join(anims)+']\n'
  (out/f'{role}.tres').write_text(resource,encoding='utf-8');print(role,info,flush=True)
 (out/'manifest_batch2.json').write_text(json.dumps(meta,indent=2))
 image=Image.new('RGB',(W*5,(H+24)*len(contact)),(36,43,53));draw=ImageDraw.Draw(image)
 for row,(label,images) in enumerate(contact):
  draw.text((8,row*(H+24)+5),label,fill='white')
  for col in range(5):
   im=images[round(col*(len(images)-1)/4)];image.paste(im,(col*W,row*(H+24)+24),im)
 image.save(ROOT/'contact_batch2.png')
if __name__=='__main__':bake()
