"""Rasterize the pinned Mojang baby zombie rig (Tiny Takeover model and texture)."""
import hashlib, json, math, sys, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image
from bake_native_mobs import Baker, molang
REV = '736072450c26a7c67f07b1661f29d9a5ebaa14b1'
BASE = f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{REV}/resource_pack/'
ROOT = Path(__file__).resolve().parents[3]
ART = ROOT/'Images/characters/我的世界/baby_zombie'
RES = 'res://Images/characters/我的世界/baby_zombie/'
SWING_PHASES = 6 # vanilla mob swing lasts 6 ticks; phase 0 is the plain walk/idle frame
WALK_FRAMES = 16
ATTACK_LEG_PHASES = 8 # legs keep walking during a swing, quantized to every other walk frame

def bake(art=ART):
    art.mkdir(parents=True,exist_ok=True)
    records=[]
    def fetch(rel,name):
        data=urllib.request.urlopen(BASE+rel,timeout=45).read()
        (art/name).write_bytes(data)
        records.append({'file':name,'url':BASE+rel,'sha256':hashlib.sha256(data).hexdigest()})
        return data
    model=json.loads(fetch('models/entity/baby_zombie.geo.json','baby_zombie.geo.json'))
    bones=next(g for g in model['minecraft:geometry'] if g['description']['identifier']=='geometry.zombie.baby')['bones']
    anim=json.loads(fetch('animations/zombie.animation.json','zombie.animation.json'))['animations']['animation.zombie.baby_attack_bare_hand']['bones']
    fetch('textures/entity/zombie/zombie_baby.png','zombie_baby.png')
    class Rig(Baker):
        def __init__(self):
            self.models={'baby':bones}
            self.skins={'baby':np.array(Image.open(art/'zombie_baby.png').convert('RGBA'))}
            yaw,pitch=np.radians([30,12])
            self.right=np.array([math.cos(yaw),0,math.sin(yaw)])
            self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
            self.view=np.array([self.right,-np.cross(self.right,self.camera),self.camera])
            # Same projection as the adult zombie bake: the native baby geometry is
            # authored at true size, so it comes out about half as tall.
            self.scale={'baby':4.55};self.foot={'baby':199}
        def pose(self,role,state,t,peek=0):
            legs,life,attack=state
            p={b['name'].lower():{'position':np.zeros(3),'rotation':np.zeros(3),'scale':np.ones(3)} for b in bones}
            if legs is not None:
                p['leftleg']['rotation'][0]=math.cos(legs*math.tau)*40.105
                p['rightleg']['rotation'][0]=-math.cos(legs*math.tau)*40.105
            env={'variable.attack_time':attack,'query.life_time':life,'this':0.0}
            for name,track in anim.items():p[name.lower()]['rotation']=np.array([molang(v,env) for v in track['rotation']])
            return p
    rig=Rig()
    names=[];clips=[]
    def clip(name,speed,loop,frames):
        clips.append((name,speed,loop,len(names),len(frames)))
        for file,state in frames:
            rig.render('baby',state,0).save(art/file);names.append(file)
    clip('idle',3.44,True,[(f'baby_idle_{i:02}.png',(None,i/12,0.0)) for i in range(12)])
    clip('walk',16.0,True,[(f'baby_walk_{i:02}.png',(i/WALK_FRAMES,0.0,0.0)) for i in range(WALK_FRAMES)])
    clip('attack_idle',20.0,False,[(f'baby_attack_idle_{k}.png',(None,0.0,k/SWING_PHASES)) for k in range(1,SWING_PHASES)])
    # Leg-major grid: frame = leg*(SWING_PHASES-1)+(swing-1).
    clip('attack_walk',20.0,False,[(f'baby_attack_walk_{leg}_{k}.png',(leg/ATTACK_LEG_PHASES,0.0,k/SWING_PHASES)) for leg in range(ATTACK_LEG_PHASES) for k in range(1,SWING_PHASES)])
    text='[gd_resource type="SpriteFrames" format=3]\n\n'
    text+=''.join(f'[ext_resource type="Texture2D" path="{RES}{name}" id="{i+1}"]\n' for i,name in enumerate(names))
    body=[]
    for name,speed,loop,start,count in clips:
        body.append('{"name": &"'+name+'", "loop": '+('true' if loop else 'false')+', "speed": '+str(speed)+', "frames": ['+', '.join('{"duration": 1.0, "texture": ExtResource("%d")}'%(start+i+1) for i in range(count))+']}')
    (art/'baby_zombie.tres').write_text(text+'\n[resource]\nanimations = ['+', '.join(body)+']\n',encoding='utf-8')
    license='Minecraft EULA; Mojang/Microsoft original assets, not freely redistributable artwork.'
    (art/'SOURCE.json').write_text(json.dumps({'revision':REV,'license':license,'files':records,'derivation':'Native baby cuboids and UVs rasterized through the shared Baker with the adult zombie camera and scale; original baby_attack_bare_hand arm track (arms at the sides, swing over 6 ticks) and humanoid leg walk. Sounds reuse audio/characters/我的世界/zombie at baby pitch.'},ensure_ascii=False,indent=2),encoding='utf-8')
    print('BABY_ZOMBIE_ASSETS',len(records),'sources;',len(names),'frames',flush=True)
if __name__=='__main__':bake(Path(sys.argv[1]) if len(sys.argv)>1 else ART)
