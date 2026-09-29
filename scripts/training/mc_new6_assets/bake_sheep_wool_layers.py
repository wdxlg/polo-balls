import sys,json
from pathlib import Path
import numpy as np
from PIL import Image
root=Path.cwd();sys.path.insert(0,str(root/'scripts/training/mc_new6_assets'))
import bake_new6 as N
out=root/'Images/characters/我的世界/new6'
body=N.SheepBaker('wool');fixed=N.SheepBaker('wool');full=N.SheepBaker('wool')
for b in body.models['sheep']:b['neverRender']=b['name'].lower()!='body'
for b in fixed.models['sheep']:b['neverRender']=b['name'].lower()=='body'
atlas=Image.new('RGBA',(1024,256));hidden=0;errors=0
for row,state in enumerate(['walk','idle']):
 for frame in range(8):
  body_im=body.render('sheep',state,frame/8);body_depth=body.depth.copy()
  fixed_im=np.array(fixed.render('sheep',state,frame/8))
  occluded=(fixed.depth<body_depth-1e-6)&(fixed_im[:,:,3]>0)
  hidden+=int(occluded.sum());fixed_im[occluded]=0
  visible=Image.fromarray(fixed_im);composite=Image.alpha_composite(body_im,visible)
  reference=full.render('sheep',state,frame/8)
  error=int(np.any(np.array(composite)!=np.array(reference),axis=2).sum());errors+=error
  atlas.paste(visible,(frame*128,row*128))
  print(state,frame,'hidden',int(occluded.sum()),'mismatch',error)
atlas.save(out/'sheep_wool_fixed.png',optimize=True)
assert errors==0,errors
(out/'SHEEP_WOOL_DEPTH_FIX.json').write_text(json.dumps({'method':'Original native mesh depth test: fixed pixels behind torso removed, foreground head and leg pixels retained','frames':16,'occluded_pixels_removed':hidden,'native_full_render_mismatched_pixels':errors},indent=2))
