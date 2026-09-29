"""Offline native drowned-arm catch/recoil; keeps existing assets untouched."""
import copy, json, math
import numpy as np
from pathlib import Path
from bake_hand_pounce import Layers, W, H, ROOT
OUT=ROOT.parents[2]/'Images/characters/我的世界/native_frames/catch_recoil'
class Catch(Layers):
    candidate=None
    peak=None
    def pose(self,role,state,t,peek=0):
        if role!='drowned' or state!='catch': return super().pose(role,state,t,peek)
        if self.candidate is not None:return copy.deepcopy(self.candidate)
        base=super().pose(role,'idle',0,peek)
        p=min(max(t/.36,0),1)
        # Fast 45ms impact overshoot, then smooth hand return, never a forced wait.
        if p<.125:
            q=p/.125; w=.82+.18*(1-(1-q)**3)
        else:
            q=(p-.125)/.875; w=1-q*q*(3-2*q)
        for name in ['rightarm']:
            for channel in ['rotation','position','scale']:
                base[name][channel]=base[name][channel]*(1-w)+self.peak[name][channel]*w
        return base
b=Catch()
neutral=b.pose('drowned','idle',0)
# Max native throw hand x (the neutral model faces left, so +x is behind).
throw_max=max(b.hand_anchor('throw',float(t))[0] for t in np.linspace(0,.4,40))
best=None
for t in np.linspace(0,.4,20):
    original=b.pose('drowned','throw',float(t))
    for offset in np.linspace(-70,70,29):
        candidate=copy.deepcopy(neutral)
        candidate['rightarm']=copy.deepcopy(original['rightarm'])
        candidate['rightarm']['rotation'][0]+=offset
        b.candidate=candidate
        grip=b.hand_anchor('catch',0)
        # Choose a hand 10-16 baked pixels behind even the furthest throw frame.
        score=abs(grip[0]-(throw_max+14))+.015*abs(offset)
        if best is None or score<best[0]:best=(score,candidate,grip,offset)
b.candidate=None;b.peak=best[1]
OUT.mkdir(parents=True,exist_ok=True)
records=[]
for i in range(19):
    t=i/18*.36
    b.mode='body';body=b.render('drowned','catch',t)
    b.mode='item';item=b.render('drowned','catch',t)
    for image,name in [(body,f'body_{i:02}.png'),(item,f'item_{i:02}.png')]:
        box=image.getbbox();assert box and box[0]>0 and box[1]>0 and box[2]<W and box[3]<H,(name,box)
        image.save(OUT/name,optimize=True)
    # Reuse a stable signed shaft direction: nearest-neighbor rig render has same native orientation.
    y,x=np.nonzero(np.array(item)[:,:,3]);pts=np.column_stack((x+.5,y+.5));mean=pts.mean(axis=0)
    _,_,axes=np.linalg.svd(pts-mean,full_matrices=False);axis=axes[0]
    if axis[0]>0:axis=-axis
    proj=(pts-mean)@axis;path=[]
    for v in np.linspace(proj.min(),proj.max(),14):
        chosen=pts[np.abs(proj-v)<=max(1.2,(proj.max()-proj.min())/24)]
        if len(chosen):path.append((chosen.mean(axis=0)-[W/2,H/2]).tolist())
    grip=np.array(b.hand_anchor('catch',t))-[W/2,H/2]
    prefix='res://Images/characters/我的世界/native_frames/catch_recoil/'
    ptsgd=','.join('Vector2(%.4f,%.4f)'%tuple(p) for p in path)
    records.append('{"body":preload("'+prefix+f'body_{i:02}.png'+'"),"item":preload("'+prefix+f'item_{i:02}.png'+'"),"grip":Vector2(%.4f,%.4f),"path":[%s]}'%(grip[0],grip[1],ptsgd))
(OUT/'catch_layers.gd').write_text('extends RefCounted\nconst FRAMES:Array[Dictionary]=[\n'+',\n'.join(records)+'\n]\n',encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps({'duration':.36,'frames':19,'native_throw_max_x':throw_max,'catch_peak_grip':best[2],'extra_arm_rotation_x':float(best[3]),'description':'Native right-arm bone recoil; early impact peak, eased neutral recovery'},indent=2),encoding='utf-8')
print('CATCH_BAKE',throw_max,best[2],best[3],len(records))
