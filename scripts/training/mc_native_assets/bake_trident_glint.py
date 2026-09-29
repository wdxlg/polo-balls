"""Bake visible rightItem masks without touching any existing character frame.
Native geometry, camera, pose, depth and 2/3 item scale come from MC16Baker.
A black-body / white-item ID render preserves body occlusion exactly.
"""
import hashlib,json,urllib.request
from pathlib import Path
import numpy as np
from PIL import Image
from bake_spider_drowned import MC16Baker,ROOT,CLIPS,COMMIT,W,H
OUT=ROOT.parents[2]/'Images/characters/我的世界/native_frames'
DEST=OUT/'trident_masks'
URL=f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/textures/misc/enchanted_item_glint.png'
SHA='99cf0defcbe422c8b91a42886f469d89cfbaba157371d8142d01ba7e8055a631'
def main():
    DEST.mkdir(parents=True,exist_ok=True)
    glint=DEST/'enchanted_item_glint.png'
    data=glint.read_bytes() if glint.exists() else urllib.request.urlopen(URL,timeout=45).read()
    assert hashlib.sha256(data).hexdigest()==SHA,'Native glint hash mismatch; refusing replacement'
    glint.write_bytes(data)
    lookup={hashlib.sha256(Image.open(p).convert('RGBA').tobytes()).hexdigest():p.stem for p in OUT.glob('drowned_[0-9]*.png')}
    assert lookup,'Existing native frames must be baked first'
    b=MC16Baker(); body=b.skins['drowned']; item=b.trident_skin
    black=body.copy();black[:,:,:3]=0
    white=item.copy();white[:,:,:3]=255
    entries={}
    for state,(count,duration,loop) in CLIPS['drowned'].items():
        if state.endswith('_empty'):continue
        for i in range(count):
            t=(i/count if loop else i/max(count-1,1))*duration
            image=b.render('drowned',state,t)
            key=lookup[hashlib.sha256(image.tobytes()).hexdigest()]
            if key in entries:continue
            b.skins['drowned']=black;b.trident_skin=white
            rendered=np.array(b.render('drowned',state,t))
            b.skins['drowned']=body;b.trident_skin=item
            visible=(rendered[:,:,0]>0)&(rendered[:,:,3]>0)
            if not visible.any():continue
            mask=np.zeros((H,W,4),dtype=np.uint8);mask[visible]=255
            Image.fromarray(mask).save(DEST/(key+'.png'),optimize=True)
            y,x=np.nonzero(visible);pts=np.column_stack((x+.5,y+.5));mean=pts.mean(axis=0)
            _,_,axes=np.linalg.svd(pts-mean,full_matrices=False)
            axis=axes[0];proj=(pts-mean)@axis
            path=[]
            for val in np.linspace(proj.min(),proj.max(),14):
                chosen=pts[np.abs(proj-val)<=max(2.0,(proj.max()-proj.min())/24)]
                if len(chosen):path.append((chosen.mean(axis=0)-[W/2,H/2]).tolist())
            entries[key]=path
    lines=[]
    for key,path in sorted(entries.items()):
        pts=', '.join('Vector2(%.3f,%.3f)'%tuple(p) for p in path)
        lines.append('"'+key+'": {"texture": preload("res://Images/characters/我的世界/native_frames/trident_masks/'+key+'.png"), "path": ['+pts+']}')
    (OUT/'drowned_trident_masks.gd').write_text('extends RefCounted\n# Exact native visible-item masks and shaft paths; no body recoloring.\nconst FRAMES:Dictionary = {\n'+',\n'.join(lines)+'\n}\n',encoding='utf-8')
    manifest={'source_url':URL,'sha256':SHA,'source_commit':COMMIT,'mask_frames':len(entries),'method':'native geometry ID/depth render; same original poses and 2/3 scale; existing frames untouched','license':'Minecraft EULA applies; see ../README.md'}
    (ROOT/'sources_trident_glint.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('TRIDENT_MASK_BAKE',len(entries),'native-glint',SHA,flush=True)
if __name__=='__main__':main()
