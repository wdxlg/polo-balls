"""Mojang Bedrock geometry/animation + official Java client particles and asset-index audio.
No hand-painted textures. Offline orthographic bake for this 2D game.
"""
from pathlib import Path
import sys,json,hashlib,math,io,zipfile,concurrent.futures
import requests,numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).parent
OUT=ROOT/'Images/characters/我的世界/allay'; SOUND=ROOT/'audio/characters/我的世界/allay'
OUT.mkdir(parents=True,exist_ok=True);SOUND.mkdir(parents=True,exist_ok=True)
COMMIT='736072450c26a7c67f07b1661f29d9a5ebaa14b1'
rows=[]
def get(url,sha1=None):
 r=requests.get(url,timeout=90);r.raise_for_status();b=r.content
 if sha1: assert hashlib.sha1(b).hexdigest()==sha1,url
 return b
def save(path,b,url,**extra):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b)
 rows.append({'file':path.relative_to(ROOT).as_posix(),'url':url,'sha256':hashlib.sha256(b).hexdigest(),**extra})
for p in ['models/entity/allay.geo.json','animations/allay.animation.json','entity/allay.entity.json','textures/entity/allay/allay.png']:
 url=f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/{p}'
 save(HERE/'resource_pack'/p,get(url),url)
version_url='https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
manifest=json.loads(get(version_url));version=json.loads(get(next(v['url'] for v in manifest['versions'] if v['id']=='1.21.1')))
index=json.loads(get(version['assetIndex']['url'],version['assetIndex']['sha1']))
client=version['downloads']['client'];jar=zipfile.ZipFile(io.BytesIO(get(client['url'],client['sha1'])))
for name in ['note','generic_0']:
 entry=f'assets/minecraft/textures/particle/{name}.png'
 save(OUT/(name+'.png'),jar.read(entry),client['url'],archive_entry=entry,archive_sha1=client['sha1'])
sounds_hash=index['objects']['minecraft/sounds.json']['hash']
all_sounds=json.loads(get(f'https://resources.download.minecraft.net/{sounds_hash[:2]}/{sounds_hash}',sounds_hash))
events={k:v for k,v in all_sounds.items() if k.startswith('entity.allay.')}
events['block.note_block.harp']=all_sounds['block.note_block.harp']
sound_records={}
for event,data in events.items():
 records=[]
 for item in data['sounds']:
  item={'name':item} if isinstance(item,str) else item
  assert item.get('type','sound')=='sound'
  key='minecraft/sounds/'+item['name']+'.ogg';record=index['objects'][key];sha=record['hash'];url=f'https://resources.download.minecraft.net/{sha[:2]}/{sha}'
  path=SOUND/(sha+'.ogg')
  if sha not in sound_records:
   save(path,get(url,sha),url,asset_key=key,sha1=sha);sound_records[sha]=path
  records.append({'path':'res://'+path.relative_to(ROOT).as_posix(),'volume':item.get('volume',1),'pitch':item.get('pitch',1)})
 events[event]=records
(HERE/'sound_events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2),encoding='utf8')
gd=['extends RefCounted','const EVENTS = {']
for event,records in events.items():
 gd.append('\t'+json.dumps(event)+':['+','.join('{"stream":preload('+json.dumps(r['path'],ensure_ascii=False)+'),"volume":'+str(r['volume'])+',"pitch":'+str(r['pitch'])+'}' for r in records)+'],')
gd+=['}']
(ROOT/'scripts/characters/我的世界/allay/native_sounds.gd').write_text('\n'.join(gd)+'\n',encoding='utf8')
# Use the existing geometry/UV rasterizer, with official Allay keyframe interpolation.
sys.path.insert(0,str(ROOT/'scripts/training/mc_native_assets'))
from bake_native_mobs import Baker,load_json
class AllayBaker(Baker):
 def __init__(self):
  self.models={'allay':load_json(HERE/'resource_pack/models/entity/allay.geo.json')['minecraft:geometry'][0]['bones']}
  self.skins={'allay':np.array(Image.open(HERE/'resource_pack/textures/entity/allay/allay.png').convert('RGBA'))}
  self.animations=load_json(HERE/'resource_pack/animations/allay.animation.json')['animations']
  yaw,pitch=np.radians([30,12]);self.right=np.array([math.cos(yaw),0,math.sin(yaw)])
  self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
  self.up=np.cross(self.right,self.camera);self.view=np.array([self.right,-self.up,self.camera])
  self.scale={'allay':7.0};self.foot={'allay':150}
 def sample(self,values,t):
  if not isinstance(values,dict): return np.array(values,float)
  keys=sorted((float(k),v) for k,v in values.items())
  def vec(v):return np.array(v.get('post',v.get('pre')) if isinstance(v,dict) else v,float)
  if len(keys)==1:return vec(keys[0][1])
  for i in range(len(keys)-1):
   a,va=keys[i];b,vb=keys[i+1]
   if a<=t<=b:
    f=(t-a)/(b-a);p1=vec(va);p2=vec(vb)
    if isinstance(va,dict) and va.get('lerp_mode')=='catmullrom':
     p0=vec(keys[max(0,i-1)][1]);p3=vec(keys[min(len(keys)-1,i+2)][1])
     return .5*((2*p1)+(-p0+p2)*f+(2*p0-5*p1+4*p2-p3)*f*f+(-p0+3*p1-3*p2+p3)*f*f*f)
    return p1+(p2-p1)*f
  return vec(keys[-1][1])
 def pose(self,role,state,t,peek=0):
  pose={b['name'].lower():{'position':np.zeros(3),'rotation':np.array(b.get('rotation',[0,0,0]),float),'scale':np.ones(3)} for b in self.models[role]}
  for name,channels in self.animations['animation.allay.'+state]['bones'].items():
   for channel,values in channels.items():
    if channel in pose[name.lower()]:pose[name.lower()][channel]+=self.sample(values,t%2)
  return pose
baker=AllayBaker();clips={};images=[]
for clip in ['idle','fly']:
 clips[clip]=[]
 for i in range(32):
  image=baker.render('allay',clip,i*2/32);assert image.getbbox();images.append(image);clips[clip].append(len(images)-1)
bounds=[im.getbbox() for im in images];box=(min(b[0] for b in bounds)-3,min(b[1] for b in bounds)-3,max(b[2] for b in bounds)+3,max(b[3] for b in bounds)+3)
lines=['[gd_resource type="SpriteFrames" load_steps=65 format=3]']
for i,im in enumerate(images):
 name=f'allay_{i:03}.png';im.crop(box).save(OUT/name)
 lines.append(f'[ext_resource type="Texture2D" path="res://Images/characters/我的世界/allay/{name}" id="{i+1}"]')
lines+=['[resource]','animations = [']
for clip,ids in clips.items():
 lines.append('{"name":&"'+clip+'","loop":true,"speed":16.0,"frames":['+','.join('{"duration":1.0,"texture":ExtResource("'+str(i+1)+'")}' for i in ids)+']},')
lines+= [']'];(OUT/'allay.tres').write_text('\n'.join(lines),encoding='utf8')
(HERE/'sources.json').write_text(json.dumps({'bedrock_commit':COMMIT,'java_version':'1.21.1','asset_index':version['assetIndex'],'copyright':'Minecraft assets belong to Mojang/Microsoft; Minecraft EULA applies. No permissive asset license is claimed.','adaptation':'Official geometry, texture and Catmull-Rom animation baked to orthographic frames. Original particle PNGs unmodified; blue tint applied at runtime. Audio bytes unchanged and SHA-1 verified.','render_crop':box,'files':rows},ensure_ascii=False,indent=2),encoding='utf8')
print('ALLAY_NATIVE_READY frames=',len(images),'sounds=',len(sound_records),'crop=',box)
