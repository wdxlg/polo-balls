#!/usr/bin/env python3
"""Separate native rightItem layers + adapted spider action bones.
Does not overwrite the prior shared/native bakes. See manifest for provenance.
"""
import hashlib,json,math
from pathlib import Path
import numpy as np
from PIL import Image
from bake_spider_drowned import MC16Baker,CLIPS,ROOT,W,H,COMMIT
from bake_native_mobs import Baker,rotation
OUT=ROOT.parents[2]/'Images/characters/我的世界/native_frames/hand_pounce'
ACTIONS={'lunge':(10,.12,False),'lunge_air':(16,.48,True),'attack':(12,.28,False),'land':(10,.18,False)}
class Layers(MC16Baker):
    mode='body'
    def cube(self,cube,m,skin,role,mirror):
        item=cube.get('_mc16_trident',False)
        if self.mode=='body' and item:return
        if self.mode=='item' and not item:return
        if item:
            pivot=np.array(next(b for b in self.models['drowned'] if b['name']=='rightItem')['pivot'])
            shrink=np.eye(4);shrink[:3,:3]=rotation([0,0,180])*.75;shrink[:3,3]=pivot-shrink[:3,:3]@pivot
            m=m@shrink
        super().cube(cube,m,skin,role,mirror)
    def render(self,role,state,t,peek=0):
        if role=='drowned':
            next(b for b in self.models[role] if b['name']=='rightItem')['cubes']=self.trident_cubes
        return Baker.render(self,role,state,t,peek)
class Pounce(MC16Baker):
    def pose(self,role,state,t,peek=0):
        if role!='spider' or state not in ACTIONS:return super().pose(role,state,t,peek)
        poses=super().pose(role,'idle',0,peek)
        p=min(max(t/ACTIONS[state][1],0),1); wave=math.sin(p*math.pi)
        if state=='lunge':
            lift=-.6*math.sin(p*math.pi)+2*p*p
            poses['body0']['rotation'][0]-=6*p
            poses['head']['rotation'][0]-=12*p
            poses['body1']['rotation'][0]+=10*p
            for i in range(8):
                sign=1 if i%2==0 else -1
                poses[f'leg{i}']['rotation'][2]+=sign*((-18 if i>=6 else 18)*p)
                poses[f'leg{i}']['rotation'][1]+=sign*24*p if i>=6 else 0
        elif state=='lunge_air':
            phase=p*math.tau;lift=2
            poses['body0']['rotation'][0]-=6
            poses['head']['rotation'][0]+=-12+2*math.sin(phase)
            poses['body1']['rotation'][0]+=10+3*math.cos(phase)
            for i in range(8):
                sign=1 if i%2==0 else -1
                poses[f'leg{i}']['rotation'][2]+=sign*((-18 if i>=6 else 18)+4*math.sin(phase+i*.7))
                poses[f'leg{i}']['rotation'][1]+=sign*((24 if i>=6 else 0)+5*math.sin(phase+i*.5))
        elif state=='attack':
            lift=2*(1-p)
            poses['body0']['rotation'][0]+=12*wave
            poses['head']['rotation'][0]+=23*wave
            poses['body1']['rotation'][0]-=8*wave
            for i in range(8):
                sign=1 if i%2==0 else -1
                poses[f'leg{i}']['rotation'][2]+=sign*(-18*(1-p)+45*wave if i>=6 else 8*wave)
                if i>=6:poses[f'leg{i}']['rotation'][1]+=sign*24*(1-p)
        else:
            lift=2*(1-p)-.5*wave
            poses['body0']['rotation'][0]-=6*(1-p)
            for i in range(8):poses[f'leg{i}']['rotation'][2]+=(1 if i%2==0 else -1)*12*wave
        poses['body0']['position'][1]+=lift
        return poses

def main():
    OUT.mkdir(parents=True,exist_ok=True);b=Layers();files={};tracks={}
    def save(image,prefix):
        bounds=image.getbbox();assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<W and bounds[3]<H,(prefix,bounds)
        digest=hashlib.sha256(image.tobytes()).hexdigest()
        key=(prefix,digest)
        if key not in files:
            filename=f'{prefix}_{sum(k[0]==prefix for k in files):03}.png'
            image.save(OUT/filename,optimize=True);files[key]=filename
        return files[key]
    item_paths={}
    for state,(count,duration,loop) in CLIPS['drowned'].items():
        track=[]
        for i in range(count):
            t=(i/count if loop else i/max(count-1,1))*duration
            b.mode='body';body=save(b.render('drowned',state,t),'body')
            b.mode='item';im=b.render('drowned',state,t);item=save(im,'item')
            if item not in item_paths:
                y,x=np.nonzero(np.array(im)[:,:,3]);pts=np.column_stack((x+.5,y+.5));mean=pts.mean(axis=0)
                _,_,axes=np.linalg.svd(pts-mean,full_matrices=False);proj=(pts-mean)@axes[0]
                path=[]
                for v in np.linspace(proj.min(),proj.max(),14):
                    chosen=pts[np.abs(proj-v)<=max(1.2,(proj.max()-proj.min())/24)]
                    if len(chosen):path.append((chosen.mean(axis=0)-[W/2,H/2]).tolist())
                item_paths[item]=path
            grip=np.array(b.hand_anchor(state,t))-[W/2,H/2]
            track.append((body,item,grip,item_paths[item]))
        tracks[state]=track
        print('HAND_LAYER',state,len(track),flush=True)
    def resource(f):return 'preload("res://Images/characters/我的世界/native_frames/hand_pounce/'+f+'")'
    lines=['extends RefCounted','# Native rightItem geometry, reduced 25% around the grip; body frames contain no duplicate weapon.','const TRACKS:Dictionary = {']
    for state,track in tracks.items():
        lines.append('"'+state+'": [')
        for body,item,grip,path in track:
            pts=', '.join('Vector2(%.3f,%.3f)'%tuple(p) for p in path)
            lines.append('{"body": '+resource(body)+', "item": '+resource(item)+', "grip": Vector2(%.4f,%.4f), "path": ['%tuple(grip)+pts+']},')
        lines.append('],')
    lines+=['}','static func frame(clip:StringName,index:int) -> Dictionary:','\tvar track:Array = TRACKS.get(str(clip),[])','\treturn {} if track.is_empty() else track[clampi(index,0,track.size()-1)]']
    (OUT/'drowned_hand_layers.gd').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    spider=Pounce();sprites=[];anims=[];counts={}
    for state,(count,duration,loop) in ACTIONS.items():
        ids=[];unique=set()
        for i in range(count):
            t=(i/count if loop else i/max(count-1,1))*duration
            im=spider.render('spider',state,t);filename=save(im,'spider_'+state)
            if filename not in sprites:sprites.append(filename)
            ids.append(sprites.index(filename)+1);unique.add(filename)
        assert len(unique)>1
        entries=', '.join('{"duration": 1.0, "texture": ExtResource("'+str(j)+'")}' for j in ids)
        anims.append('{"frames": ['+entries+'], "loop": '+str(loop).lower()+', "name": &"'+state+'", "speed": '+str(count/duration)+'}')
        counts[state]=len(unique);print('SPIDER_ACTION',state,count,len(unique),flush=True)
    tres='[gd_resource type="SpriteFrames" format=3]\n\n'+'\n'.join('[ext_resource type="Texture2D" path="res://Images/characters/我的世界/native_frames/hand_pounce/'+f+'" id="'+str(i+1)+'"]' for i,f in enumerate(sprites))+'\n\n[resource]\nanimations = ['+',\n'.join(anims)+']\n'
    (OUT/'spider_pounce.tres').write_text(tres,encoding='utf-8')
    manifest={'source_commit':COMMIT,'native_geometry_and_skins':True,'hand_scale':.5,'previous_hand_scale':2/3,'hand_samples':sum(map(len,tracks.values())),'textures':len(files),'spider_actions':counts,'adaptation':'Spider pounce/attack/landing are custom bone poses using the original Mojang model/skin and default leg pose, NOT claimed as vanilla animation files. Held item rendered as separate foreground rightItem layer, oriented outward around the native grip.','license':'Minecraft EULA applies; no additional redistribution rights.'}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print('HAND_POUNCE_BAKE',json.dumps(manifest),flush=True)
if __name__=='__main__':main()
