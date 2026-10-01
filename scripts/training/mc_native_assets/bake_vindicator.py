"""Bake official Vindicator cuboids with the shared native rasterizer."""
import copy, hashlib, json, math, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image
import bake_native_mobs as native
REV='736072450c26a7c67f07b1661f29d9a5ebaa14b1'
BASE=f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{REV}/resource_pack/'

def bake(output):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    records=[]
    def fetch(rel,name):
        data=urllib.request.urlopen(BASE+rel,timeout=40).read()
        (output/name).write_bytes(data)
        records.append({'file':name,'url':BASE+rel,'sha256':hashlib.sha256(data).hexdigest()})
        return data
    model=json.loads(fetch('models/entity/vindicator.geo.json','vindicator.geo.json'))['geometry.vindicator.v1.8']['bones']
    fetch('animations/vindicator.animation.json','vindicator.animation.json')
    fetch('textures/entity/vindicator.png','vindicator.png')
    fetch('textures/items/iron_axe.png','iron_axe.png')
    class Rig(native.Baker):
        def __init__(self):
            self.models={'vindicator':copy.deepcopy(model)}
            self.skins={'vindicator':np.array(Image.open(output/'vindicator.png').convert('RGBA'))}
            yaw,pitch=np.radians([30,12])
            self.right=np.array([math.cos(yaw),0,math.sin(yaw)])
            self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
            self.up=np.cross(self.right,self.camera);self.view=np.array([self.right,-self.up,self.camera])
            self.scale={'vindicator':4.55};self.foot={'vindicator':199}
        def pose(self,role,state,t,peek=0):
            poses={b['name'].lower():{'position':np.zeros(3),'rotation':np.zeros(3),'scale':np.ones(3)} for b in model}
            poses['arms']['scale']=np.zeros(3)
            if state=='walk':
                poses['leg0']['rotation'][0]=math.cos(t*math.tau)*40.105
                poses['leg1']['rotation'][0]=-math.cos(t*math.tau)*40.105
            poses['rightarm']['rotation'][0]=-180
            poses['leftarm']['rotation'][2]=-5.74
            return poses
        def project(self,p):return (np.asarray(p)@self.view.T)[:2]*4.55+np.array([80,199])
    b=Rig()
    for bone in b.models['vindicator']:
        if bone['name']=='rightArm':bone['neverRender']=True
    files=[]
    for i in range(12):
        name=f'walk_{i:02}.png';b.render('vindicator','walk',i/12).save(output/name);files.append(name)
    b.render('vindicator','idle',0).save(output/'idle.png')
    for bone in b.models['vindicator']:bone['neverRender']=bone['name']!='rightArm'
    arm=b.render('vindicator','idle',0);arm.save(output/'arm.png')
    shoulder=b.project([-5,22,0]);hand=b.project([-6,31,0]);wrist=b.project([-6,29.5,0])
    pixels=np.array(arm);skin=(pixels[:,:,3]>0)&(pixels[:,:,0]>64)&(pixels[:,:,1]>=pixels[:,:,0])
    hand_pixels=pixels.copy();hand_pixels[~skin]=0
    forearm_pixels=pixels.copy();forearm_pixels[skin]=0
    hand_image=Image.fromarray(hand_pixels);forearm=Image.fromarray(forearm_pixels)
    hand_image.save(output/'hand.png');forearm.save(output/'forearm.png')
    geom={'shoulder':shoulder.tolist(),'hand':hand.tolist(),'wrist':wrist.tolist(),'hand_split':'unchanged_original_gray_skin_texels','grip_parent':'articulated_hand','rest_wrist_angle':2.75-1.65,'canvas':[160,224],'axe_grip':[5.5,11.5],'axe_blade':[9.0,4.0],'arm_depth':'behind_body_at_rest','front_swing_depth':'in_front_of_body','item_depth':'behind_hand','rest_axe_axis':'screen_up','axe_scale':5.0,'rest_arm_angle':-2.75,'ready_arm_angle':-1.65,'rush_ready_arm_angle':-1.00,'rest_grip_angle':2.75-math.pi/4,'draw_charge_ratio':0.065,'raised_arm_angle':-0.70,'axe_hold_angle':1.65-math.pi/4,'rig_space':'canonical_left_mirror_all','charge_pose_progress':'full_ratio'}
    (output/'rig.json').write_text(json.dumps(geom,indent=2))
    def place(pic,pivot,anchor,angle,scale=1):
        basis=scale*np.array([[math.cos(angle),-math.sin(angle)],[math.sin(angle),math.cos(angle)]])
        inverse=np.linalg.inv(basis)
        translation=pivot-inverse@anchor
        affine=(inverse[0,0],inverse[0,1],translation[0],inverse[1,0],inverse[1,1],translation[1])
        return pic.transform((160,224),Image.Transform.AFFINE,affine,Image.Resampling.NEAREST)
    angle=-0.70
    rotation=np.array([[math.cos(angle),-math.sin(angle)],[math.sin(angle),math.cos(angle)]])
    palm=shoulder+rotation@(hand-shoulder)
    axe=Image.open(output/'iron_axe.png').convert('RGBA')
    preview=place(forearm,shoulder,shoulder,angle)
    preview.alpha_composite(place(axe,np.array([5.5,11.5]),palm,angle+1.65-math.pi/4,5))
    preview.alpha_composite(place(hand_image,shoulder,shoulder,angle))
    preview.alpha_composite(Image.open(output/'idle.png').convert('RGBA'))
    preview.save(output/'preview.png')
    resources=['idle.png']+files
    text='[gd_resource type="SpriteFrames" format=3]\n'+''.join(f'[ext_resource type="Texture2D" path="res://Images/characters/我的世界/vindicator/{n}" id="{i+1}"]\n' for i,n in enumerate(resources))
    text+='\n[resource]\nanimations = [{"name": &"idle", "loop": true, "speed": 1.0, "frames": [{"duration": 1.0,"texture": ExtResource("1")}]}, {"name": &"walk", "loop": true, "speed": 12.0, "frames": ['+','.join('{"duration": 1.0,"texture": ExtResource("%d")}'%(i+2) for i in range(12))+']}]\n'
    (output/'frames.tres').write_text(text,encoding='utf-8')
    (output/'SOURCE.json').write_text(json.dumps({'repository':'https://github.com/Mojang/bedrock-samples','revision':REV,'license':'Minecraft EULA; original Mojang/Microsoft assets, not freely redistributable artwork.','derivation':'Official cuboids and UVs rasterized with bake_native_mobs.Baker; official leg walk formula. Original right-arm pixels split losslessly into sleeve and hand; hand and iron axe share a wrist transform at runtime.','files':records,'rig':geom},ensure_ascii=False,indent=2),encoding='utf-8')
    print('VINDICATOR_ART',geom,flush=True)
if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('output');bake(p.parse_args().output)
