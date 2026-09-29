#!/usr/bin/env python3
"""Pinned vanilla Anvil assets + deterministic orthographic model bake (no AI art).
Requires Pillow/numpy, already used by the project's native-asset toolchain.
Minecraft assets remain Mojang's; EULA/redistribution restrictions still apply.
"""
import hashlib, io, json, math, pathlib, tempfile, urllib.request, zipfile

CLIENT_URL = 'https://piston-data.mojang.com/v1/objects/a19d9badbea944a4369fd0059e53bf7286597576/client.jar'
CLIENT_SHA1 = 'a19d9badbea944a4369fd0059e53bf7286597576'
NATIVE = 'Images/characters/我的世界/anvil/native'
FILES = {
    'assets/minecraft/models/block/anvil.json': NATIVE+'/anvil.json',
    'assets/minecraft/models/block/template_anvil.json': NATIVE+'/template_anvil.json',
    'assets/minecraft/models/block/block.json': NATIVE+'/block.json',
    'assets/minecraft/textures/block/anvil.png': NATIVE+'/anvil.png',
    'assets/minecraft/textures/block/anvil_top.png': NATIVE+'/anvil_top.png',
}
SOUNDS = {
    'anvil_land.ogg': '781d4bfc6ee0aff2a61b0d78f0da34610a28aa62',
    'anvil_break.ogg': '6fa4895a44f671fd7c24c366f87ca908da6485a3',
}

def install(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() != data:
        raise RuntimeError('Refusing to replace differing existing asset: '+str(path))
    if not path.exists(): path.write_bytes(data)

def bake(root):
    import numpy as np
    from PIL import Image
    native=root/NATIVE
    model=json.loads((native/'template_anvil.json').read_text())
    block=json.loads((native/'block.json').read_text())
    display=block['display']['gui']
    rx,ry,rz=[math.radians(a) for a in display['rotation']]
    X=np.array([[1,0,0],[0,math.cos(rx),-math.sin(rx)],[0,math.sin(rx),math.cos(rx)]])
    Y=np.array([[math.cos(ry),0,math.sin(ry)],[0,1,0],[-math.sin(ry),0,math.cos(ry)]])
    Z=np.array([[math.cos(rz),-math.sin(rz),0],[math.sin(rz),math.cos(rz),0],[0,0,1]])
    rotation=Z@X@Y
    textures={k:np.array(Image.open(native/name).convert('RGBA')) for k,name in [('body','anvil.png'),('top','anvil_top.png')]}
    normals={'up':[0,1,0],'down':[0,-1,0],'north':[0,0,-1],'south':[0,0,1],'east':[1,0,0],'west':[-1,0,0]}
    shade={'up':1.0,'down':0.5,'north':0.8,'south':0.8,'east':0.6,'west':0.6}
    image=np.zeros((64,64,4),dtype=np.uint8)
    depth=np.full((64,64),-np.inf)
    for element in model['elements']:
        x0,y0,z0=element['from'];x1,y1,z1=element['to']
        faces={
          'up':[(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)],
          'down':[(x0,y0,z1),(x1,y0,z1),(x1,y0,z0),(x0,y0,z0)],
          'north':[(x1,y1,z0),(x0,y1,z0),(x0,y0,z0),(x1,y0,z0)],
          'south':[(x0,y1,z1),(x1,y1,z1),(x1,y0,z1),(x0,y0,z1)],
          'east':[(x1,y1,z1),(x1,y1,z0),(x1,y0,z0),(x1,y0,z1)],
          'west':[(x0,y1,z0),(x0,y1,z1),(x0,y0,z1),(x0,y0,z0)],
        }
        for side,face in element['faces'].items():
            if (rotation@normals[side])[2]<=0: continue
            vertices=(np.array(faces[side],dtype=float)-8.0)*np.array(display['scale'])
            vertices=(rotation@vertices.T).T
            vertices[:,0]=32.0+vertices[:,0]*4.0
            vertices[:,1]=32.0-vertices[:,1]*4.0
            u0,v0,u1,v1=face['uv']
            uv=np.array([(u0,v0),(u1,v0),(u1,v1),(u0,v1)],dtype=float)
            uv=np.roll(uv,int(face.get('rotation',0))//90,axis=0)
            texture=textures[face['texture'][1:]]
            for indices in [(0,1,2),(0,2,3)]:
                xyz=vertices[list(indices)];st=uv[list(indices)]
                matrix=np.vstack((xyz[:,:2].T,np.ones(3)))
                if abs(np.linalg.det(matrix))<1e-9: continue
                inverse=np.linalg.inv(matrix)
                for py in range(max(0,int(np.floor(xyz[:,1].min()))),min(64,int(np.ceil(xyz[:,1].max()))+1)):
                    for px in range(max(0,int(np.floor(xyz[:,0].min()))),min(64,int(np.ceil(xyz[:,0].max()))+1)):
                        weight=inverse@np.array([px+0.5,py+0.5,1.0])
                        if weight.min() < -1e-8: continue
                        z=float(weight@xyz[:,2])
                        if z<depth[py,px]-1e-8: continue
                        tex=weight@st
                        tx=max(0,min(texture.shape[1]-1,int(math.floor(tex[0]))))
                        ty=max(0,min(texture.shape[0]-1,int(math.floor(tex[1]))))
                        color=texture[ty,tx].copy()
                        if not color[3]: continue
                        color[:3]=np.rint(color[:3].astype(float)*shade[side]).astype(np.uint8)
                        image[py,px]=color;depth[py,px]=z
    result=Image.fromarray(image,'RGBA')
    buffer=io.BytesIO();result.save(buffer,format='PNG',optimize=False)
    return buffer.getvalue()

def main():
    root=pathlib.Path(__file__).resolve().parents[3]
    manifest=json.loads((root/'MC_ANVIL_ASSETS.json').read_text(encoding='utf-8'))
    wanted={item['path']:item['sha256'] for item in manifest['files']}
    missing=[name for name in FILES.values() if not (root/name).exists()]
    if missing:
        cache=pathlib.Path(tempfile.gettempdir())/'mc-anvil-1.21.8-client.jar'
        if not cache.exists() or hashlib.sha1(cache.read_bytes()).hexdigest()!=CLIENT_SHA1:
            data=urllib.request.urlopen(CLIENT_URL,timeout=90).read()
            if hashlib.sha1(data).hexdigest()!=CLIENT_SHA1: raise RuntimeError('Bad client.jar SHA1')
            cache.write_bytes(data)
        with zipfile.ZipFile(cache) as archive:
            for source,destination in FILES.items(): install(root/destination,archive.read(source))
    for filename,sha1 in SOUNDS.items():
        destination=root/'audio/characters/我的世界/anvil'/filename
        if destination.exists(): data=destination.read_bytes()
        else: data=urllib.request.urlopen('https://resources.download.minecraft.net/'+sha1[:2]+'/'+sha1,timeout=30).read()
        if hashlib.sha1(data).hexdigest()!=sha1: raise RuntimeError('Bad audio SHA1: '+filename)
        install(destination,data)
    rendered='Images/characters/我的世界/anvil/anvil.png'
    if not (root/rendered).exists(): install(root/rendered,bake(root))
    for name,sha in wanted.items():
        if hashlib.sha256((root/name).read_bytes()).hexdigest()!=sha: raise RuntimeError('Asset mismatch: '+name)
    print('ANVIL_NATIVE_ASSETS_OK',len(wanted))

if __name__=='__main__': main()
