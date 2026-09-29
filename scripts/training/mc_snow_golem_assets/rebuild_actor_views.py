#!/usr/bin/env python3
"""Fresh Mojang acquisition + full-heading Snow Golem projections (offline only).
Native texels are never repainted. Uses the project's one Bedrock software baker.
Output can be staged outside the project for review before installing any PNGs.
"""
from pathlib import Path
import argparse,copy,concurrent.futures,hashlib,json,math,sys
import numpy as np
import requests
from PIL import Image,ImageDraw
from snow_renderer import SnowBaker,PROJECT,HERE
sys.path.insert(0,str(PROJECT/'scripts/training/mc_native_assets'))
from bake_native_mobs import rotation,W,H
COMMIT='736072450c26a7c67f07b1661f29d9a5ebaa14b1'
FILES=['models/entity/snow_golem.v1.0.geo.json','animations/snow_golem.animations.v1.0.json','textures/entity/snow_golem.png','textures/blocks/snow.png','textures/blocks/pumpkin_face_off.png','textures/blocks/pumpkin_side.png','textures/blocks/pumpkin_top.png']
COUNT=16

def sha(data):return hashlib.sha256(data).hexdigest()
def acquire(item):
 name,url=item
 response=requests.get(url,timeout=60)
 response.raise_for_status()
 return name,url,response.content

class FacingBaker(SnowBaker):
 def __init__(self,source):
  super().__init__(source)
  for bone in self.models['snow']:
   if not bone.get('parent'):bone['parent']='view_root'
  self.models['snow'].append({'name':'view_root','pivot':[0,0,0]})
  self.model_yaw=0.0
 def pose(self,role,state,t,peek=0):
  # Zero relative target yaw; rotate the ENTIRE original model into world heading.
  poses=super().pose(role,'bare' if state=='bare' else 'pumpkin',0.0,peek)
  if role=='snow':poses['view_root']['rotation'][1]=self.model_yaw
  return poses
 def head_image(self):
  hidden=[]
  for bone in self.models['snow']:
   if bone['name']!='pumpkin':
    hidden.append((bone,bone.get('neverRender',False)))
    bone['neverRender']=True
  try:return self.render('snow','pumpkin',0.0)
  finally:
   for bone,value in hidden:bone['neverRender']=value

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--output-root',type=Path,default=PROJECT);args=parser.parse_args();root=args.output_root.resolve()
 source=root/'scripts/training/mc_snow_golem_assets/resource_pack';out=root/'Images/characters/我的世界/snow_golem';(out/'faces').mkdir(parents=True,exist_ok=True);(out/'heads').mkdir(parents=True,exist_ok=True)
 jobs=[(n,f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/{n}') for n in FILES]
 jobs.append(('../LICENSE.minecraft.md',f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/LICENSE.md'))
 records=[]
 # Deliberately no cached-response path: this task requests fresh original assets.
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
  for name,url,data in pool.map(acquire,jobs):
   path=(source/name).resolve();path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
   records.append({'file':path.relative_to(root).as_posix(),'url':url,'bytes':len(data),'sha256':sha(data),'fresh_network_fetch':True})
 baker=FacingBaker(source);frames=[];sheet=Image.new('RGBA',(W*8,H*4),(14,23,34,255));draw=ImageDraw.Draw(sheet)
 ground=np.array([[baker.view[0,0],baker.view[0,2]],[baker.view[1,0],baker.view[1,2]]])
 for index in range(COUNT):
  angle=index*2.0*math.pi/COUNT;wanted=np.array([math.cos(angle),math.sin(angle)])
  native=np.linalg.solve(ground,wanted);native/=np.linalg.norm(native)
  yaw=math.degrees(math.atan2(-native[0],-native[1]));baker.model_yaw=yaw
  normal=rotation([0,yaw,0])@np.array([0.,0.,-1.]);projected=(baker.view@normal)[:2];projected/=np.linalg.norm(projected)
  assert np.allclose(projected,wanted,atol=1e-7),(index,projected,wanted)
  entry={'index':index,'screen_degrees':index*360.0/COUNT,'model_yaw_degrees':yaw,'projected_forward':projected.tolist()}
  for state in ['pumpkin','bare']:
   image=baker.render('snow',state,0.0);bounds=image.getbbox();assert bounds is not None and bounds[0]>0 and bounds[2]<W and bounds[1]>0 and bounds[3]<H,(state,index,bounds)
   path=out/'faces'/f'{state}_{index:02d}.png';image.save(path,optimize=True);entry[state]={'path':path.relative_to(root).as_posix(),'sha256':sha(path.read_bytes()),'bounds':list(bounds)}
   x=(index%8)*W;y=((0 if state=='pumpkin' else 2)+(index//8))*H;sheet.alpha_composite(image,(x,y));draw.text((x+5,y+5),f'{index:02d} / {index*360//COUNT} deg',fill='white')
  head=baker.head_image();box=head.getbbox();assert box is not None
  box=(max(0,box[0]-1),max(0,box[1]-1),min(W,box[2]+1),min(H,box[3]+1));path=out/'heads'/f'pumpkin_{index:02d}.png';head.crop(box).save(path,optimize=True)
  entry['head']={'path':path.relative_to(root).as_posix(),'sha256':sha(path.read_bytes()),'crop':list(box),'center_from_canvas_center':[(box[0]+box[2])/2-W/2,(box[1]+box[3])/2-H/2]}
  frames.append(entry)
 # Keep the actual character selector/rotation portrait in agreement with the new front view.
 preview=root/'Images/UI/rotation_frames/snow_golem.png';preview.parent.mkdir(parents=True,exist_ok=True);preview.write_bytes((out/'faces/pumpkin_03.png').read_bytes())
 # Confirm the original pumpkin break event rather than inventing a placement sound.
 prior=json.loads((PROJECT/'MC_SNOW_GOLEM_ASSETS.json').read_text(encoding='utf-8-sig'));url=prior['sounds_definition']['url'];data=requests.get(url,timeout=60).content
 assert hashlib.sha1(data).hexdigest()==prior['sounds_definition']['sha1']
 events=json.loads(data);sound={'url':url,'sha1':prior['sounds_definition']['sha1'],'break':events.get('block.wood.break'),'place':events.get('block.wood.place')}
 manifest={'source':'Mojang/bedrock-samples','bedrock_commit':COMMIT,'source_files':records,'canvas':[W,H],'foot_y':baker.foot['snow'],'direction_count':COUNT,'direction_convention':'0=right, increasing clockwise on screen; no runtime horizontal mirror; whole original model yaw, not only head poses','camera':'Original 30-degree azimuth/12-degree elevation preserved; ground projection inverted to obtain true screen heading.','frames':frames,'preview':{'path':preview.relative_to(root).as_posix(),'sha256':sha(preview.read_bytes())},'wood_break_event':sound,'renderer_sha256':sha(Path(__file__).read_bytes()),'copyright':'Mojang/Microsoft Minecraft assets. Original files and texels, rendered into 2D direction views. No redistribution license is asserted; see LICENSE.minecraft.md.','supersedes':'Runtime three-look poses in MC_SNOW_GOLEM_ASSETS.json; existing sounds/snow/ice resources remain unchanged.'}
 (out/'SOURCE.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 sheet.convert('RGB').save(root/'snow_golem_direction_sheet.jpg',quality=94)
 print('SNOW_FACING_BAKED',len(frames),'directions;',len(records),'fresh official source files;',len(frames)*3,'PNGs')
 print('WOOD_BREAK_EVENT',json.dumps(sound,ensure_ascii=True))

if __name__=='__main__':main()
