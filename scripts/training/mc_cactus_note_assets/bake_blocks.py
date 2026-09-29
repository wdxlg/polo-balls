"""Offline orthographic rasterization of Mojang Java 1.21.1 block models.
No runtime 3D. Parent models/UVs/textures are original; framing fits gameplay's anchored bounds.
"""
from pathlib import Path
import json,math
import numpy as np
from PIL import Image
B=Path(__file__).resolve().parent;SRC=B/'model_source';OUT=B/'assets';OUT.mkdir(parents=True,exist_ok=True)
def model(name):
 j=json.loads((SRC/(name+'.json')).read_text()); p=j.get('parent','').split('/')[-1]
 inherited=model(p) if (SRC/(p+'.json')).exists() else {}
 inherited['textures']={**inherited.get('textures',{}),**j.get('textures',{})}
 if 'elements' in j:inherited['elements']=j['elements']
 return inherited
yaw=math.radians(25);pitch=math.radians(12)
right=np.array([math.cos(yaw),0,-math.sin(yaw)])
up=np.array([-math.sin(yaw)*math.sin(pitch),math.cos(pitch),-math.cos(yaw)*math.sin(pitch)])
front=np.cross(right,up)
normals={'up':[0,1,0],'down':[0,-1,0],'east':[1,0,0],'west':[-1,0,0],'south':[0,0,1],'north':[0,0,-1]}
def bake(name,levels=1):
 m=model(name);faces=[]
 for layer in range(levels):
  for e in m['elements']:
   x,y,z=e['from'];X,Y,Z=e['to'];y+=layer*16;Y+=layer*16
   quads={'up':[(x,Y,z),(X,Y,z),(X,Y,Z),(x,Y,Z)],'down':[(x,y,Z),(X,y,Z),(X,y,z),(x,y,z)],'south':[(x,Y,Z),(X,Y,Z),(X,y,Z),(x,y,Z)],'north':[(X,Y,z),(x,Y,z),(x,y,z),(X,y,z)],'east':[(X,Y,Z),(X,Y,z),(X,y,z),(X,y,Z)],'west':[(x,Y,z),(x,Y,Z),(x,y,Z),(x,y,z)]}
   for side,f in e['faces'].items():
    if np.dot(normals[side],front)<=0:continue
    if side=='up' and layer!=levels-1:continue
    t=f['texture']
    while t.startswith('#'):t=m['textures'][t[1:]]
    tex=np.array(Image.open(SRC/(t.split('/')[-1]+'.png')).convert('RGBA'))
    pts=np.array(quads[side],float)
    uv=np.array([[0,0],[16,0],[16,16],[0,16]],float)
    uvbox=f.get('uv',[0,0,16,16]);uv=uv/16*np.array([uvbox[2]-uvbox[0],uvbox[3]-uvbox[1]])+uvbox[:2]
    p=np.column_stack([pts@right,-pts@up,pts@front])
    faces.append((p,uv,tex,1.0 if side=='up' else .78 if side=='east' else .94))
 width,height=96,96*levels
 allp=np.concatenate([f[0] for f in faces]);lo=allp[:,:2].min(0);hi=allp[:,:2].max(0)
 image=np.zeros((height,width,4),dtype=np.uint8);depth=np.full((height,width),-np.inf)
 for p,uv,tex,shade in faces:
  p=p.copy();p[:,:2]=(p[:,:2]-lo)/(hi-lo)*np.array([width-1,height-1])
  for ids in [[0,1,2],[0,2,3]]:
   tri=p[ids];v=uv[ids];minx,maxx=max(0,int(np.floor(tri[:,0].min()))),min(width-1,int(np.ceil(tri[:,0].max())));miny,maxy=max(0,int(np.floor(tri[:,1].min()))),min(height-1,int(np.ceil(tri[:,1].max())))
   yy,xx=np.mgrid[miny:maxy+1,minx:maxx+1];a,b,c=tri;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
   if abs(den)<1e-8:continue
   w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den;w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w2=1-w0-w1
   zz=w0*a[2]+w1*b[2]+w2*c[2];tu=w0*v[0,0]+w1*v[1,0]+w2*v[2,0];tv=w0*v[0,1]+w1*v[1,1]+w2*v[2,1]
   pixels=tex[np.clip(tv.astype(int),0,15),np.clip(tu.astype(int),0,15)].copy();pixels[:,:,:3]=(pixels[:,:,:3]*shade).astype(np.uint8)
   region=depth[miny:maxy+1,minx:maxx+1];mask=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)&(zz>=region)&(pixels[:,:,3]>0)
   region[mask]=zz[mask];image[miny:maxy+1,minx:maxx+1][mask]=pixels[mask]
 Image.fromarray(image).save(OUT/(f'cactus_{levels}.png' if name=='cactus' else 'note_block.png'))
for n in range(1,6):bake('cactus',n)
bake('note_block')
