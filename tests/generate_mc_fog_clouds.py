"""Deterministic original RGBA mist sprites; no third-party license dependency."""
import random, math, struct, zlib
from pathlib import Path
root=Path("Images/characters/我的世界/fog_man")
root.mkdir(parents=True,exist_ok=True)
N=128
for seed in range(4):
 rng=random.Random(7301+seed)
 grids=[[[rng.random() for x in range(k+1)] for y in range(k+1)] for k in [4,8,16,32]]
 def noise(x,y):
  total=0.0
  for g,k,w in zip(grids,[4,8,16,32],[.55,.26,.13,.06]):
   u=x/N*k; v=y/N*k; a=int(u); b=int(v); u-=a; v-=b
   u=u*u*(3-2*u); v=v*v*(3-2*v)
   total+=((g[b][a]*(1-u)+g[b][a+1]*u)*(1-v)+(g[b+1][a]*(1-u)+g[b+1][a+1]*u)*v)*w
  return total
 rows=[]
 for y in range(N):
  row=bytearray([0])
  for x in range(N):
   n=noise(x,y); r=((x-63.5)/61)**2+((y-63.5)/59)**2
   edge=max(0,1-r); alpha=min(1,edge**1.6*max(0,(n-.17)*2.3))
   c=int(157+93*n)
   row.extend([c,min(255,c+5),min(255,c+8),int(alpha*255)])
  rows.append(row)
 def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
 data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',N,N,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
 (root/('cloud_%d.png'%seed)).write_bytes(data)
print('Created 4 original translucent cloud textures')
