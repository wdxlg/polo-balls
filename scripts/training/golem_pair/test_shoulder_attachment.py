"""Offline regression: require numpy/Pillow as with bake_pair.py; no network calls.
Checks both shoulder joints through dense animation sampling and every baked PNG.
"""
import argparse,json
from pathlib import Path
import numpy as np
from PIL import Image

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--renderer',type=Path,help='Optional local renderer override')
 args=parser.parse_args()
 base=Path(__file__).resolve().parent
 source=(base/'bake_pair.py').read_text(encoding='utf-8').split('b=PairBaker();folder=')[0]
 if args.renderer:
  source=source.replace("str(BASE.parent/'mc_native_assets/bake_native_mobs.py')",repr(str(args.renderer.resolve())))
 ns={'__file__':str(base/'bake_pair.py')}
 exec(compile(source,'bake_definitions','exec'),ns)
 baker=ns['PairBaker']();native=ns['n'];checks=0
 bones={b['name']:b for b in baker.models['golem']}
 def matrix(bone,pose):
  pivot=np.array(bone['pivot'],float)
  rs=native.rotation(pose['rotation'])@np.diag(pose['scale'])
  m=np.eye(4);m[:3,:3]=rs;m[:3,3]=pivot+pose['position']-rs@pivot
  return m
 for state,duration,samples in [('idle',0,1),('walk',1,1001),('charge',.38,1001),('swing',.48,1001)]:
  for t in np.linspace(0,duration,samples):
   pose=baker.pose('golem',state,float(t));body=matrix(bones['body'],pose['body'])
   for name,x in [('arm0',-9),('arm1',9)]:
    shoulder=np.array([x,31,0,1],float)
    # The contact point must be invariant in body space and remain on torso side.
    expected=body@shoulder
    actual=body@matrix(bones[name],pose[name])@shoulder
    assert np.allclose(actual,expected,rtol=0,atol=1e-9),(state,t,name,actual,expected)
    cube=bones[name]['cubes'][0];origin=np.array(cube['origin']);size=np.array(cube['size'])
    assert np.all(shoulder[:3]>=origin) and np.all(shoulder[:3]<=origin+size)
    checks+=1
 folder=base.parents[2]/'Images/characters/我的世界/iron_golem'
 pictures=sorted(folder.glob('golem_*.png'))
 for file in pictures:
  im=Image.open(file).convert('RGBA');box=im.getbbox()
  assert box and box[0]>0 and box[1]>0 and box[2]<im.width and box[3]<im.height,(file,'clipped')
  checks+=1
  # Detached visible limbs form large disconnected alpha components.
  mask=np.asarray(im)[:,:,3]>10
  remaining=set(map(tuple,np.argwhere(mask)))
  components=[]
  while remaining:
   todo=[remaining.pop()];count=0
   while todo:
    y,x=todo.pop();count+=1
    for dy,dx in [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]:
     q=(y+dy,x+dx)
     if q in remaining:remaining.remove(q);todo.append(q)
   components.append(count)
  assert len([n for n in components if n>3])==1,(file,'detached alpha components',components)
  checks+=1
 print('GOLEM_SHOULDER_RESULT checks=%d failures=0 poses=3004 png=%d'%(checks,len(pictures)))

if __name__=='__main__':main()
