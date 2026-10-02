"""Rasterize the pinned Mojang zombie rig and an equipped golden helmet."""
import copy, hashlib, json, math, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image
from bake_native_mobs import Baker, molang
REV = '736072450c26a7c67f07b1661f29d9a5ebaa14b1'
BASE = f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{REV}/resource_pack/'
ROOT = Path(__file__).resolve().parents[3]
ART = ROOT/'Images/characters/我的世界/zombie'
SOUND = ROOT/'audio/characters/我的世界/zombie'

def bake():
    ART.mkdir(parents=True,exist_ok=True)
    SOUND.mkdir(parents=True,exist_ok=True)
    records=[]
    def fetch(rel,name):
        data=urllib.request.urlopen(BASE+rel,timeout=45).read()
        (ART/name).write_bytes(data)
        records.append({'file':name,'url':BASE+rel,'sha256':hashlib.sha256(data).hexdigest()})
        return data
    bones=json.loads(fetch('models/entity/zombie.geo.json','zombie.geo.json'))['geometry.zombie.v1.8']['bones']
    anim=json.loads(fetch('animations/zombie.animation.json','zombie.animation.json'))['animations']['animation.zombie.attack_bare_hand']['bones']
    fetch('animations/humanoid.animation.json','humanoid.animation.json')
    fetch('textures/entity/zombie/zombie.png','zombie.png')
    fetch('textures/models/armor/gold_1.png','gold_1.png')
    fetch('textures/items/slimeball.png','slimeball.png')
    class Rig(Baker):
        def __init__(self):
            self.models={role:copy.deepcopy(bones) for role in ('zombie','king')}
            head=next(b for b in self.models['king'] if b['name']=='head')
            helmet=copy.deepcopy(head['cubes'][0]);helmet['inflate']=0.5;helmet['_helmet']=True;head['cubes'].append(helmet)
            self.skins={role:np.array(Image.open(ART/'zombie.png').convert('RGBA')) for role in self.models}
            self.gold=np.array(Image.open(ART/'gold_1.png').convert('RGBA'))
            yaw,pitch=np.radians([30,12])
            self.right=np.array([math.cos(yaw),0,math.sin(yaw)])
            self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
            self.view=np.array([self.right,-np.cross(self.right,self.camera),self.camera])
            self.scale={r:4.55 for r in self.models};self.foot={r:199 for r in self.models}
        def pose(self,role,state,t,peek=0):
            p={b['name'].lower():{'position':np.zeros(3),'rotation':np.zeros(3),'scale':np.ones(3)} for b in bones}
            if state=='walk':
                p['leftleg']['rotation'][0]=math.cos(t*math.tau)*40.105
                p['rightleg']['rotation'][0]=-math.cos(t*math.tau)*40.105
            env={'variable.attack_time':0.0,'variable.is_brandishing_spear':0.0,'query.life_time':t,'this':0.0}
            for name,track in anim.items():p[name]['rotation']=np.array([molang(v,env) for v in track['rotation']])
            return p
        def cube(self,cube,m,skin,role,mirror):
            super().cube(cube,m,self.gold if cube.get('_helmet') else skin,role,mirror)
    rig=Rig()
    for role in ('zombie','king'):
        names=[]
        for state,count in [('idle',12),('walk',16)]:
            for i in range(count):
                name=f'{role}_{state}_{i:02}.png';rig.render(role,state,i/count).save(ART/name);names.append(name)
        text='[gd_resource type="SpriteFrames" format=3]\n'
        text+=''.join(f'[ext_resource type="Texture2D" path="res://Images/characters/我的世界/zombie/{name}" id="{i+1}"]\n' for i,name in enumerate(names))
        clips=[];offset=0
        for state,count,speed in [('idle',12,3.44),('walk',16,16.0)]:
            clips.append('{"name": &"'+state+'", "loop": true, "speed": '+str(speed)+', "frames": ['+','.join('{"duration": 1.0, "texture": ExtResource("%d")}'%(offset+i+1) for i in range(count))+']}');offset+=count
        (ART/f'{role}.tres').write_text(text+'\n[resource]\nanimations = ['+','.join(clips)+']\n',encoding='utf-8')
    manifest=json.load(urllib.request.urlopen('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',timeout=45))
    version=json.load(urllib.request.urlopen(next(v['url'] for v in manifest['versions'] if v['id']=='1.21.5'),timeout=45))
    index=json.load(urllib.request.urlopen(version['assetIndex']['url'],timeout=45))['objects']
    sounds=[]
    for kind,count,prefix in [('ambient',3,'say'),('hurt',2,'hurt'),('death',1,'death'),('step',5,'step')]:
        for n in range(1,count+1):
            key=f'minecraft/sounds/mob/zombie/{prefix}{n if count>1 else ""}.ogg'
            sha=index[key]['hash'];url=f'https://resources.download.minecraft.net/{sha[:2]}/{sha}'
            data=urllib.request.urlopen(url,timeout=45).read();assert hashlib.sha1(data).hexdigest()==sha
            name=f'{kind}{n}.ogg';(SOUND/name).write_bytes(data);sounds.append({'file':name,'asset':key,'url':url,'sha1':sha})
    license='Minecraft EULA; Mojang/Microsoft original assets, not freely redistributable artwork.'
    (ART/'SOURCE.json').write_text(json.dumps({'revision':REV,'license':license,'files':records,'derivation':'Native cuboids and UVs rasterized through the shared Baker; original zombie arm track and humanoid leg walk. King equips original golden helmet texture on the inflated native head. Bite reuses native_frames/fang.tres (official Evoker Fangs).'},ensure_ascii=False,indent=2),encoding='utf-8')
    (SOUND/'SOURCE.json').write_text(json.dumps({'version':'Java 1.21.5','license':license,'files':sounds},ensure_ascii=False,indent=2),encoding='utf-8')
    print('ZOMBIE_ASSETS',len(records),'sources;',len(sounds),'original sounds',flush=True)
if __name__=='__main__':bake()
