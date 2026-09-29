"""Pinned original Mojang model/skin/animations + Java 1.21.4 sounds; shared rasterizer.
Only bakes projection/poses of original assets. Never paints a replacement texture.
"""
import sys,json,hashlib,urllib.request,copy,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/training/mc_native_assets'))
import numpy as np
from PIL import Image
from bake_native_mobs import Baker,load_json,molang,rotation,W,H
from bake_native_batch2 import BatchBaker
COMMIT='736072450c26a7c67f07b1661f29d9a5ebaa14b1'
URL=f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/'
OUT=ROOT/'Images/characters/我的世界/wither_skeleton'
SRC=OUT/'source'
AUDIO=ROOT/'audio/characters/我的世界/wither_skeleton'
records=[]
def get(url):
 return urllib.request.urlopen(url,timeout=60).read()
def save(path,data,url,sha1=None):
 if sha1: assert hashlib.sha1(data).hexdigest()==sha1
 path.parent.mkdir(parents=True,exist_ok=True)
 if path.exists(): assert path.read_bytes()==data, 'Refuse overwrite: '+str(path)
 else:path.write_bytes(data)
 records.append({'file':path.relative_to(ROOT).as_posix(),'url':url,'sha256':hashlib.sha256(data).hexdigest(),'sha1':hashlib.sha1(data).hexdigest(),'size':len(data)})
 return path

def main():
 for path in ['textures/entity/skeleton/wither_skeleton.png','textures/items/stone_sword.png','models/entity/wither_skeleton.geo.json','animations/wither_skeleton.animation.json','animations/humanoid.animation.json','entity/wither_skeleton.entity.json']:
  target=(OUT/'stone_sword.png') if path.endswith('/stone_sword.png') else SRC/Path(path).name
  save(target,get(URL+path),URL+path)
 manifest=json.loads(get('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'))
 version=next(x for x in manifest['versions'] if x['id']=='1.21.4')
 version_data=json.loads(get(version['url']));index_url=version_data['assetIndex']['url'];index=json.loads(get(index_url))['objects']
 events={}
 for key,entry in sorted(index.items()):
  if not key.startswith('minecraft/sounds/mob/wither_skeleton/') or not key.endswith('.ogg'):continue
  h=entry['hash'];url='https://resources.download.minecraft.net/'+h[:2]+'/'+h
  path=save(AUDIO/Path(key).name,get(url),url,h)
  name=Path(key).stem.rstrip('0123456789');kind={'idle':'ambient'}.get(name,name)
  events.setdefault(kind,[]).append(path.relative_to(ROOT).as_posix())
 assert all(events.get(k) for k in ['ambient','hurt','death','step']),events
 bank='extends RefCounted\n# Original Java 1.21.4 OGGs, hashes in SOURCE.json.\nconst EVENTS:Dictionary = {\n'
 for name,paths in events.items():bank+='\t"'+name+'":['+','.join('preload("res://'+p+'")' for p in paths)+'],\n'
 bank+='}\n';(ROOT/'scripts/characters/我的世界/wither_skeleton/sounds.gd').write_text(bank,encoding='utf-8')
 bake()
 (OUT/'SOURCE.json').write_text(json.dumps({'owner':'Mojang / Microsoft','license':'Original Minecraft assets: Minecraft EULA/Usage Guidelines; not freely redistributable. No AI-generated or repainted source assets.','bedrock_commit':COMMIT,'java_audio_version':'1.21.4','asset_index':index_url,'renderer':RENDERER,'files':records,'clips':{'idle':16,'walk':16,'attack':50}},ensure_ascii=False,indent=2),encoding='utf-8')
 print('WITHER_SKELETON_ASSETS',len(records),'original files; audio', {k:len(v) for k,v in events.items()})

RENDERER="Existing bake_native_mobs.Baker + BatchBaker matrices; unchanged original model/skin, original idle/walk; project-directed raised-arm downcut/upcut/recovery transforms (not a vanilla animation claim)."
def attack_arm_degrees(t):
 keys=[(0.0,-18.0),(.15,-160.0),(.31,-10.0),(.41,0.0),(.57,-160.0),(.74,-170.0),(.98,-18.0)]
 for (a,x),(b,y) in zip(keys,keys[1:]):
  if t<=b:
   u=max(0,min(1,(t-a)/(b-a)));u=u*u*(3-2*u)
   return x+(y-x)*u
 return -18.0

def bake():
 # Offline rebake only reads the pinned source files; no download or new source art.
 b=BatchBaker()
 b.models['skeleton']=copy.deepcopy(load_json(SRC/'wither_skeleton.geo.json')['geometry.skeleton.wither.v1.8']['bones'])
 b.skins['skeleton']=np.array(Image.open(SRC/'wither_skeleton.png').convert('RGBA'))
 b.animations.update(load_json(SRC/'humanoid.animation.json')['animations'])
 b.animations.update(load_json(SRC/'wither_skeleton.animation.json')['animations'])
 def pose(role,state,t,peek=0):
  result={x['name'].lower():{'position':np.zeros(3),'rotation':np.zeros(3),'scale':np.ones(3)} for x in b.models[role]}
  env={'this':0,'query.life_time':t,'variable.tcos0':math.cos(t*math.tau)*32 if state=='walk' else 0,'variable.is_holding_left':0,'variable.is_holding_right':1,'variable.attack_time':min(t/.30,1),'variable.is_brandishing_spear':0,'variable.is_holding_spyglass':0}
  names=['humanoid.move','humanoid.holding','humanoid.bob']
  # Keep the native model/skin, articulate its real shoulder through one full combo.
  for name in names:
   for bone,channels in b.animations['animation.'+name]['bones'].items():
    if bone.lower() not in result:continue
    p=result[bone.lower()]
    for channel,values in channels.items():
     if channel not in p:continue
     if isinstance(values,(str,float,int)):values=[values]*3
     for i,value in enumerate(values):
      env['this']=p[channel][i];v=molang(value,env)
      if channel=='scale':p[channel][i]=v
      else:p[channel][i]+=v
  if state=='attack':
   result['rightarm']['rotation']=np.array([attack_arm_degrees(t),0.0,5.73])
  return result
 b.pose=pose
 yaw,pitch=np.radians([30,12]);b.right=np.array([math.cos(yaw),0,math.sin(yaw)]);b.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)]);b.up=np.cross(b.right,b.camera);b.view=np.array([b.right,-b.up,b.camera])
 b.scale['skeleton']=4.5;b.foot['skeleton']=201
 files=[];clips=[];hands={}
 for state,count,duration,loop in [('idle',16,360/103.2,True),('walk',16,1.0,True),('attack',50,.98,False)]:
  ids=[];hands[state]=[]
  for i in range(count):
   t=duration*i/(count if loop else count-1)
   im=Baker.render(b,'skeleton',state,t);box=im.getbbox();assert box and box[0]>0 and box[1]>0 and box[2]<W and box[3]<H
   name=f'{state}_{i:02}.png';im.save(OUT/name);files.append(name);ids.append(len(files))
   m=b.matrices('skeleton',state,t)['rightarm'];hand=(m[:3,:3]@np.array([-5,12.75,-1.05])+m[:3,3])@b.view.T
   hands[state].append([round(float(hand[0]*4.5+W/2),4),round(float(hand[1]*4.5+201),4)])
  clips.append('{"name":&"'+state+'","loop":'+str(loop).lower()+',"speed":'+str(count/duration)+',"frames":['+','.join('{"duration":1.0,"texture":ExtResource("'+str(i)+'")}' for i in ids)+']}')
 text='[gd_resource type="SpriteFrames" format=3]\n'+''.join('\n[ext_resource type="Texture2D" path="res://Images/characters/我的世界/wither_skeleton/'+p+'" id="'+str(i+1)+'"]' for i,p in enumerate(files))+'\n\n[resource]\nanimations = ['+',\n'.join(clips)+']\n'
 (OUT/'frames.tres').write_text(text,encoding='utf-8')
 (OUT/'poses.gd').write_text('extends RefCounted\n# Projected original right-hand anchors, in 160x224 frame pixels.\nconst HANDS:Dictionary = '+json.dumps(hands)+'\n',encoding='utf-8')
 print('WITHER_SKELETON_BAKE',len(files),'frames; full arm combo',len(hands['attack']))
if __name__=='__main__':
 if '--rebake' in sys.argv:
  bake()
  metadata=json.loads((OUT/'SOURCE.json').read_text(encoding='utf-8'));metadata['renderer']=RENDERER;metadata['clips']['attack']=50
  (OUT/'SOURCE.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
 else:main()
