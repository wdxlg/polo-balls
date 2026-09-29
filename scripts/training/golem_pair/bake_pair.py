import sys,importlib.util,json,math,copy,hashlib,requests,concurrent.futures
from pathlib import Path
import numpy as np
from PIL import Image
BASE=Path(__file__).resolve().parent; OUT=BASE.parents[2]; SRC=BASE/'resource_pack'
spec=importlib.util.spec_from_file_location('native', str(BASE.parent/'mc_native_assets/bake_native_mobs.py'));n=importlib.util.module_from_spec(spec);spec.loader.exec_module(n)
class PairBaker(n.Baker):
 def __init__(self):
  self.models={};self.skins={};self.animations={}
  for role,file in [('golem','iron_golem'),('villager','villager_v2')]:
   model=n.load_json(SRC/f'models/entity/{file}.geo.json');geo=model['minecraft:geometry'][0] if 'minecraft:geometry' in model else next(v for k,v in model.items() if k.startswith('geometry.'))
   self.models[role]=geo['bones']
   for b in self.models[role]:b.setdefault('pivot',[0,0,0])
   if role=='golem':
    # Native arms share body-centre X=0, harmless for native X-only rotation but
    # wrong for our enlarged arms: scaling that offset pulls the shoulders apart.
    # Gameplay bake adapter only; original geometry bytes remain untouched.
    for bone in self.models[role]:
     if bone['name'] in ('arm0','arm1'):
      cube=bone['cubes'][0]
      inner_x=cube['origin'][0]+cube['size'][0] if bone['name']=='arm0' else cube['origin'][0]
      bone['pivot']=[inner_x,bone['pivot'][1],bone['pivot'][2]]
   animation_file='villager' if role=='villager' else file
   self.animations.update(n.load_json(SRC/f'animations/{animation_file}.animation.json')['animations'])
  self.skins['golem']=np.array(Image.open(SRC/'textures/entity/iron_golem/iron_golem.png').convert('RGBA'))
  # Official adult plains Toolsmith: base -> biome -> profession -> novice badge.
  layers=['textures/entity/villager2/villager.png','textures/entity/villager2/biomes/biome_plains.png','textures/entity/villager2/professions/toolsmith.tga','textures/entity/villager2/levels/level_stone.png']
  skin=Image.open(SRC/layers[0]).convert('RGBA')
  for layer in layers[1:]: skin=Image.alpha_composite(skin,Image.open(SRC/layer).convert('RGBA'))
  self.skins['villager']=np.array(skin)
  yaw,pitch=np.radians([30,12]);self.right=np.array([math.cos(yaw),0,math.sin(yaw)]);self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)]);self.up=np.cross(self.right,self.camera);self.view=np.array([self.right,-self.up,self.camera]);self.scale={'golem':3.15,'villager':4.3};self.foot={'golem':195,'villager':195}
 def pose(self,role,state,t,peek=0):
  p={b['name'].lower():{'position':np.zeros(3),'rotation':np.array(b.get('rotation',[0,0,0]),float),'scale':np.ones(3)} for b in self.models[role]}
  if role=='golem':
   if state=='walk':
    # Official iron_golem.move + walk: variable.modified_tcos0 drives each bone.
    v=math.cos(t*math.tau)*6
    p['arm0']['rotation'][0]=-v*2;p['arm1']['rotation'][0]=v*2
    p['body']['rotation'][2]=v/1.5;p['head']['rotation'][2]=v/1.5
    p['leg0']['rotation'][0]=v*6;p['leg1']['rotation'][0]=-v*6
   elif state=='charge':
    # Lower the body; arms inherit the body transform with fixed shoulder joints.
    f=t/.38;p['body']['position'][1]=-1.5*f
    for arm in ['arm0','arm1']:p[arm]['rotation'][0]=18*f
   elif state=='swing':
    # Original attack expression sampled backwards over the upswing, then recovered.
    f=min(t/.48,1);tick=10-5*min(f/.5,1)
    angle=-114+((1.5*abs((tick%10)-5)-2.5)/5)*57.3
    if f<.16:angle=18+(angle-18)*f/.16
    elif f>.55:angle*=max(0,(1-f)/.45)
    arm_size=1+1.1*min(f/.18,1) if f<=.36 else 2.1-1.1*(f-.36)/.64
    for arm in ['arm0','arm1']:
     p[arm]['rotation'][0]=angle;p[arm]['scale']=np.full(3,arm_size)
  else:
   # Official general/move/raise_arms tracks; item handling is a gameplay adapter.
   p['arms']['position']=np.array([0,-1,-1],float);p['arms']['rotation'][0]=-42.97
   if state in ['walk','carry_walk']:
    p['leg0']['rotation'][0]=math.cos(t*math.tau)*40;p['leg1']['rotation'][0]=-math.cos(t*math.tau)*40
   if state in ['carry','carry_walk','throw']:
    p['arms']['rotation'][0]-=15*(1 if state!='throw' else math.sin(min(t/.36,1)*math.pi))
  return p
b=PairBaker();folder=OUT/'Images/characters/我的世界/iron_golem';folder.mkdir(parents=True,exist_ok=True)
base_skin=b.skins['golem'].copy();meta={}
for role in ['golem','villager']:
 # Larger transparent canvas prevents enlarged hands clipping; same world foot anchor.
 n.W,n.H=(448,384) if role=='golem' else (160,224)
 b.foot[role]=275 if role=='golem' else 195
 clips={'idle':(1,1,True),'walk':(16,1,True)}
 clips.update({'charge':(8,.38,False),'swing':(24,.48,False)} if role=='golem' else {'carry':(1,1,True),'carry_walk':(16,1,True),'throw':(10,.36,False)})
 for stage in (range(4) if role=='golem' else [0]):
  if role=='golem':
   skin=Image.fromarray(base_skin)
   if stage:skin=Image.alpha_composite(skin,Image.open(SRC/f'textures/entity/iron_golem/cracked_{["","low","medium","high"][stage]}.png').convert('RGBA'))
   b.skins['golem']=np.array(skin)
  stem=f'{role}_{stage}';ext=[];anims=[];dedup={};bounds=[]
  for clip,(count,duration,loop) in clips.items():
   fs=[]
   for i in range(count):
    t=duration*(i/count if loop else i/max(count-1,1));im=b.render(role,clip,t)
    if role=='villager' and clip in ['carry','carry_walk','throw']:
     # Same native ingot sprite rendered at folded hands; projectile has its own sprite.
     ingot=Image.open(SRC/'textures/items/iron_ingot.png').convert('RGBA').resize((30,30),Image.Resampling.NEAREST)
     y=123-int(7*math.sin(t/.36*math.pi)) if clip=='throw' else 123
     im.alpha_composite(ingot,(51,y))
    digest=hashlib.sha256(im.tobytes()).hexdigest()
    if digest not in dedup:
     idx=len(ext)+1;dedup[digest]=idx;name=f'{stem}_{idx:03}.png';im.save(folder/name);ext.append(f'[ext_resource type="Texture2D" path="res://Images/characters/我的世界/iron_golem/{name}" id="{idx}"]')
    fs.append('{"duration":1.0,"texture":ExtResource("%d")}'%dedup[digest])
    if clip=='idle':
     bounds=list(im.getbbox())
     preview=im.crop(((n.W-160)//2,(n.H-224)//2,(n.W+160)//2,(n.H+224)//2)) if role=='golem' else im
     preview.save(folder/f'{stem}_preview.png')
   anims.append('{"frames":['+','.join(fs)+'],"loop":'+str(loop).lower()+',"name":&"'+clip+'","speed":'+str(count/duration)+'}')
  (folder/f'{stem}.tres').write_text('[gd_resource type="SpriteFrames" format=3]\n'+'\n'.join(ext)+'\n[resource]\nanimations = ['+',\n'.join(anims)+']\n')
  meta[stem]={'bounds':bounds,'unique_frames':len(ext),'clips':clips,'canvas':[n.W,n.H],'foot_y':b.foot[role]}
  if role=='golem': meta[stem]['shoulder_anchors']={'arm0':[-9,31,0],'arm1':[9,31,0]}
  if role=='golem': meta[stem]['arm_scale_curve']={'peak':2.1,'grow_until':0.18,'hold_until':0.36,'recover_until':1.0}
  if role=='villager': meta[stem]['profession']='toolsmith'
(folder/'iron_ingot.png').write_bytes((SRC/'textures/items/iron_ingot.png').read_bytes())
(folder/'BAKE.json').write_text(json.dumps(meta,indent=2))
# Official Java sound assets, resolved via Mojang content hashes.
index_url='https://piston-meta.mojang.com/v1/packages/76d7a97b9e0778fda3b14e474f012450ca0de1bb/17.json';objects=requests.get(index_url).json()['objects']
h=objects['minecraft/sounds.json']['hash'];sounds=requests.get(f'https://resources.download.minecraft.net/{h[:2]}/{h}').json()
events=['entity.iron_golem.attack','entity.iron_golem.damage','entity.iron_golem.repair','entity.iron_golem.hurt','entity.iron_golem.death','entity.iron_golem.step','entity.villager.ambient','entity.villager.hurt','entity.villager.death','entity.villager.yes','entity.snowball.throw','block.anvil.hit','block.stone.step','entity.generic.small_fall','entity.generic.big_fall']
records={};jobs={};manifest=json.load(open(BASE/'sources.json'));manifest['audio_index']=index_url;manifest['audio']={}
for event in events:
 records[event]=[]
 for raw in sounds[event]['sounds']:
  data={'name':raw} if isinstance(raw,str) else raw
  assert data.get('type','sound')=='sound'
  key='minecraft/sounds/'+data['name']+'.ogg';sha=objects[key]['hash'];jobs[sha]=f'https://resources.download.minecraft.net/{sha[:2]}/{sha}'
  records[event].append({'sha1':sha,'volume':data.get('volume',1),'pitch':data.get('pitch',1)})
  manifest['audio'][key]={'sha1':sha,'url':jobs[sha]}
audio=OUT/'audio/characters/我的世界/iron_golem';audio.mkdir(parents=True,exist_ok=True)
def fetch(kv):
 sha,url=kv;r=requests.get(url);r.raise_for_status();assert hashlib.sha1(r.content).hexdigest()==sha;(audio/(sha+'.ogg')).write_bytes(r.content)
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(fetch,jobs.items()))
code='extends RefCounted\n# Unmodified Mojang Java 1.21.1 sounds, SHA-1 verified.\nconst EVENTS:Dictionary = {\n'
for event,rs in records.items():
 code+='\t"'+event+'":['+','.join('{"stream":preload("res://audio/characters/我的世界/iron_golem/'+r['sha1']+'.ogg"),"volume":'+str(r['volume'])+',"pitch":'+str(r['pitch'])+'}' for r in rs)+'],\n'
code+='}\n';scripts=OUT/'scripts/characters/我的世界/iron_golem';scripts.mkdir(parents=True,exist_ok=True);(scripts/'native_sounds.gd').write_text(code)
manifest['adaptation']='Official Bedrock skeletons and skins baked to orthographic frames. Walk and upswing adapted from native bone tracks; anticipation and villager item handling are new gameplay timing, not claimed as original gameplay. Crack overlays native; rage is runtime red tint. No AI-painted art or synthetic audio.'
(folder/'SOURCES.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2));print(json.dumps(meta));print('sounds',len(jobs))
