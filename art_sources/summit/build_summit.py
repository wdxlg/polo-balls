"""山巅 / SUMMIT — reproducible Blender model, using unmodified local Minecraft textures.
Run in Blender 5.2+: blender --factory-startup --python build_summit.py
Only writes inside this script's asset directory. Does not alter the Godot game.
"""
import bpy, math, random, json, pathlib, traceback, time, struct, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parent
SEED = 9262026
RNG = random.Random(SEED)
N = 144
HALF = N // 2
BASE = -5
BATCHES = {}
HEIGHT = {}
TRAIL = set()
MATERIALS = {}
FOREST_SNOW = []

def status(stage, **kw):
    (ROOT / 'build_status.json').write_text(json.dumps(dict(stage=stage, **kw),ensure_ascii=False,indent=2),encoding='utf-8')
    print('SUMMIT_STAGE',stage,kw,flush=True)

def hashnoise(x,y):
    a=(int(x)*374761393+int(y)*668265263+SEED*17)&0xffffffff
    a=((a^(a>>13))*1274126177)&0xffffffff
    return ((a^(a>>16))&0xffffff)/float(0xffffff)*2-1

def noise(x,y):
    ix,iy=math.floor(x),math.floor(y);fx=x-ix;fy=y-iy
    fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
    a=hashnoise(ix,iy)*(1-fx)+hashnoise(ix+1,iy)*fx
    b=hashnoise(ix,iy+1)*(1-fx)+hashnoise(ix+1,iy+1)*fx
    return a*(1-fy)+b*fy

def fbm(x,y):
    return noise(x,y)+noise(x*2.1+17,y*2.1-5)*.48+noise(x*4.4-8,y*4.4+29)*.22

def terrain(x,y,flatten_summit=True):
    radial=((x/72)**2+(y/65)**2)**.5
    edge=1-radial+.055*noise(x*.12,y*.12)
    if edge<.015:return 0
    xx=x+fbm(x*.045,y*.045)*3.5
    yy=y+fbm(x*.05+35,y*.05)*3.0
    peaks=[(8,15,101,43,42),(-25,18,75,34,39),(33,33,72,31,28),(-25,-21,48,36,33),(33,-21,42,28,32)]
    forms=[]
    for px,py,h,rx,ry in peaks:
        r=(((xx-px)/rx)**2+((yy-py)/ry)**2)**.5
        forms.append(h*max(0,1-r)**1.10)
    h=5+max(forms)+fbm(x*.09,y*.09)*3.5+noise(x*.29,y*.29)*1.5
    # Knife-edged spurs create an asymmetric range instead of a single round cone.
    for ax,ay,bx,by,ha,hb,width in [(8,15,-25,18,98,72,12),(8,15,33,33,98,68,9),(8,15,-25,-21,98,45,10)]:
        dx=bx-ax;dy=by-ay;t=max(0,min(1,((xx-ax)*dx+(yy-ay)*dy)/(dx*dx+dy*dy)))
        d=math.hypot(xx-(ax+dx*t),yy-(ay+dy*t))
        ridge=(ha+(hb-ha)*t)*max(0,1-d/width)**.8
        h=max(h,ridge+noise(x*.2,y*.2)*2)
    # A deep broken gully on the south-west face.
    if y<-7:
        g=abs(x-(-11+.23*y+2*math.sin(y*.12)))
        h-=max(0,1-g/5)*min(12,max(0,(-y-7)*.6))
    h=min(h,10+edge*135)
    if flatten_summit and abs(x-8)<=4 and abs(y-15)<=4: h=96
    return max(1,int(h))

def material(key,texture,tint=(1,1,1,1)):
    m=bpy.data.materials.new('MC / '+key);m.use_nodes=True;m.diffuse_color=tint
    nodes=m.node_tree.nodes;bsdf=nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.92
    image=bpy.data.images.load(str(ROOT/'textures'/texture),check_existing=True)
    tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest';tex.extension='REPEAT'
    if tint!=(1,1,1,1):
        mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=tint
        m.node_tree.links.new(tex.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(mix.outputs[0],bsdf.inputs['Base Color'])
    else:m.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    m['original_texture']=texture;m['source']='Minecraft Java 1.21.1 local client; see SOURCE.json'
    MATERIALS[key]=m
    return m

def face(group,mat,points,uv=None):
    key=(group,mat)
    batch=BATCHES.setdefault(key, [[],[],[]]);v,f,u=batch;k=len(v)
    v.extend(points);f.append((k,k+1,k+2,k+3));u.extend(uv or [(0,0),(1,0),(1,1),(0,1)])

def box(group,mat,x,y,z,sx=1,sy=1,sz=1,top=None):
    a=x+sx;b=y+sy;c=z+sz
    face(group,top or mat,[(x,y,c),(a,y,c),(a,b,c),(x,b,c)],[(0,0),(sx,0),(sx,sy),(0,sy)])
    face(group,mat,[(x,b,z),(a,b,z),(a,y,z),(x,y,z)],[(0,0),(sx,0),(sx,sy),(0,sy)])
    face(group,mat,[(x,y,z),(a,y,z),(a,y,c),(x,y,c)],[(0,0),(sx,0),(sx,sz),(0,sz)])
    face(group,mat,[(a,b,z),(x,b,z),(x,b,c),(a,b,c)],[(0,0),(sx,0),(sx,sz),(0,sz)])
    face(group,mat,[(x,b,z),(x,y,z),(x,y,c),(x,b,c)],[(0,0),(sy,0),(sy,sz),(0,sz)])
    face(group,mat,[(a,y,z),(a,b,z),(a,b,c),(a,y,c)],[(0,0),(sy,0),(sy,sz),(0,sz)])

def topmat(x,y,h):
    if (x,y) in TRAIL:return 'Trail' if hashnoise(x,y)>.12 else 'Worn trail'
    snowline=60+noise(x*.095,y*.095)*7
    if h>=snowline:return 'Snow'
    slope=max(abs(h-HEIGHT.get((x+dx,y+dy),h)) for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])
    if h<34 and slope<=2:return 'Grass'
    if h<46 and slope<2 and noise(x*.19,y*.19)>.23:return 'Grass'
    if h>49 and hashnoise(x//3,y//3)>.35:return 'Pale granite'
    return 'Andesite' if noise(x*.15,y*.15)>.24 else 'Stone'

def sidemat(x,y,z,h,top):
    if z>=h-1:
        if top=='Snow':return 'Snow'
        if top=='Grass':return 'Dirt'
    if z<4:return 'Deep rock'
    if z<13 and (int(z)+int(noise(x*.1,y*.1)*2))%9<3:return 'Deep rock'
    if 34<z<80 and abs(x-(12+math.sin(z*.09)*3))<1.5 and y<10:return 'Glacier'
    if noise(x*.11+z*.034,y*.13-z*.027)>.24:return 'Andesite'
    return 'Stone'

def build_terrain():
    for x in range(-HALF,HALF):
        for y in range(-HALF,HALF):HEIGHT[x,y]=terrain(x,y)
    route=[(-47,-41),(-24,-39),(-33,-24),(-12,-20),(-19,-5),(0,-2),(-4,9),(8,15)]
    for a,b in zip(route,route[1:]):
        steps=int(math.dist(a,b)*3)
        for j in range(steps+1):
            t=j/max(steps,1);xx=round(a[0]+(b[0]-a[0])*t);yy=round(a[1]+(b[1]-a[1])*t)
            for dx,dy in [(0,0),(1,0),(0,1)]:TRAIL.add((xx+dx,yy+dy))
    for (x,y),h in HEIGHT.items():
        if not h:continue
        top=topmat(x,y,h)
        face('01 Mountain',top,[(x,y,h),(x+1,y,h),(x+1,y+1,h),(x,y+1,h)])
        face('01 Mountain','Deep rock',[(x,y+1,BASE),(x+1,y+1,BASE),(x+1,y,BASE),(x,y,BASE)])
        for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
            other=HEIGHT.get((x+dx,y+dy),0);bottom=other if other else BASE
            if bottom>=h:continue
            # Per-block faces preserve voxel silhouette and one texture tile per cube.
            for z in range(bottom,h):
                mat=sidemat(x,y,z,h,top)
                if dx==1:pts=[(x+1,y,z),(x+1,y+1,z),(x+1,y+1,z+1),(x+1,y,z+1)]
                elif dx==-1:pts=[(x,y+1,z),(x,y,z),(x,y,z+1),(x,y+1,z+1)]
                elif dy==1:pts=[(x+1,y+1,z),(x,y+1,z),(x,y+1,z+1),(x+1,y+1,z+1)]
                else:pts=[(x,y,z),(x+1,y,z),(x+1,y,z+1),(x,y,z+1)]
                face('01 Mountain',mat,pts)

def branch_snow(index,x,y,ground,height,leaves):
    """Snow rests on exposed leaf tops, with a stable per-tree weather profile."""
    load=min(3,int((hashnoise(x*17+31,y*23-7)+1)*2))
    names=['none','light','medium','heavy']
    density=[0,.18,.46,.82][load]
    exposed={}
    for lx,ly,lz in leaves:exposed[lx,ly]=max(lz,exposed.get((lx,ly),-1000))
    candidates=sorted((hashnoise(lx*13+index*19,ly*11-index*7),lx,ly,lz)
                      for (lx,ly),lz in exposed.items())
    chosen=[]
    if load:
        chosen=[p for p in candidates if (p[0]+1)*.5<density]
        # Even sparse snow is a few separate branch patches, not a lone tip cap.
        if len(chosen)<3:chosen=candidates[:3]
        if len({p[3] for p in chosen})<2:
            extra=next((p for p in candidates if p[3]!=chosen[0][3]),None)
            if extra is not None:chosen.append(extra)
    patches=[]
    for score,lx,ly,lz in chosen:
        thickness=.125*(1+min(load-1,int((hashnoise(lx+117,ly-43)+1)*1.5)))
        box('02 Alpine spruce','Snow',lx,ly,lz+1,1,1,thickness)
        patches.append([lx,ly,lz+1,thickness])
    FOREST_SNOW.append(dict(index=index,base=[x,y,ground],height=height,
                           load=names[load],patches=patches,
                           snow_levels=sorted({p[2] for p in patches})))


def build_forest(snow_style='tip'):
    assert snow_style in ('tip','varied')
    FOREST_SNOW.clear()
    locations=[]
    for _ in range(2500):
        x=RNG.randrange(-62,63);y=RNG.randrange(-59,57);h=HEIGHT.get((x,y),0)
        if not 8<h<40 or (x,y) in TRAIL:continue
        if max(abs(h-HEIGHT.get((x+dx,y+dy),0)) for dx,dy in [(2,0),(-2,0),(0,2),(0,-2)])>5:continue
        if any(math.hypot(x-a,y-b)<7 for a,b in locations):continue
        locations.append((x,y))
        if len(locations)>=62:break
    for index,(x,y) in enumerate(locations):
        z=HEIGHT[x,y];height=RNG.randrange(7,12)
        leaves=[]
        box('02 Alpine spruce','Spruce bark',x,y,z,1,1,height,top='Spruce end')
        for level,radius in [(height-6,3),(height-4,2),(height-2,2),(height,1)]:
            for dx in range(-radius,radius+1):
                for dy in range(-radius,radius+1):
                    if abs(dx)+abs(dy)>radius+1 or (dx==0 and dy==0):continue
                    if hashnoise(x+dx*3,y+dy*3)<-.65:continue
                    box('02 Alpine spruce','Spruce needles',x+dx,y+dy,z+level)
                    leaves.append((x+dx,y+dy,z+level))
        box('02 Alpine spruce','Spruce needles',x,y,z+height+1)
        leaves.append((x,y,z+height+1))
        if snow_style=='varied':branch_snow(index,x,y,z,height,leaves)
        elif z>30:box('02 Alpine spruce','Snow',x,y,z+height+2,1,1,.2)
    return len(locations)

def build_summit():
    # Weathered cairn and a small summit landing; no gameplay collision implied.
    for x in range(5,12):
        for y in range(12,19):
            if abs(x-8)+abs(y-15)<5:box('03 Summit landmark','Worn trail',x,y,96,1,1,.25)
    box('03 Summit landmark','Cairn',7,14,96.25,3,3,1)
    box('03 Summit landmark','Cairn',8,15,97.25,1,1,2)
    box('03 Summit landmark','Snow',8,15,99.25,1,1,.25)
    anchor=bpy.data.objects.new('SUMMIT_ANCHOR - 1 unit per block',None);bpy.context.scene.collection.objects.link(anchor)
    anchor.location=(8.5,15.5,96.25);anchor.empty_display_type='CUBE';anchor.empty_display_size=2
    anchor['purpose']='Optional future adaptive-map attachment; no collision/navigation generated.'

def flush_meshes():
    collections={}
    for (group,key),(verts,faces,uvs) in BATCHES.items():
        if not verts:continue
        if group not in collections:
            c=bpy.data.collections.new(group);bpy.context.scene.collection.children.link(c);collections[group]=c
        mesh=bpy.data.meshes.new(group+' / '+key);mesh.from_pydata(verts,[],faces);mesh.update()
        uv=mesh.uv_layers.new(name='BlockUV');uv.data.foreach_set('uv',[v for pair in uvs for v in pair])
        mesh.materials.append(MATERIALS[key]);obj=bpy.data.objects.new(group+' / '+key,mesh);collections[group].objects.link(obj)
        obj['export_geometry']=True;obj['block_size']=1.0
    BATCHES.clear()

def point_at(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

def presentation():
    scene=bpy.context.scene
    scene.name='山巅 | SUMMIT'
    scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
    scene.cycles.max_bounces=6;scene.cycles.diffuse_bounces=3;scene.cycles.glossy_bounces=2;scene.cycles.volume_bounces=0
    scene.render.resolution_x=1800;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=-1.0
    world=bpy.data.worlds.new('High altitude / cold sky');world.use_nodes=True;scene.world=world
    nodes=world.node_tree.nodes;back=nodes.get('Background');back.inputs['Strength'].default_value=.20
    sky=nodes.new('ShaderNodeTexSky')
    sky_types={e.identifier for e in sky.bl_rna.properties['sky_type'].enum_items}
    sky.sky_type='MULTIPLE_SCATTERING' if 'MULTIPLE_SCATTERING' in sky_types else 'NISHITA'
    sky.sun_elevation=math.radians(22);sky.sun_rotation=math.radians(125);sky.air_density=.85
    setattr(sky,'aerosol_density' if hasattr(sky,'aerosol_density') else 'dust_density',1.8)
    world.node_tree.links.new(sky.outputs['Color'],back.inputs['Color'])
    ld=bpy.data.lights.new('Late sun / warm rim','SUN');ld.energy=1.6;ld.angle=math.radians(8);ld.color=(1,.82,.62)
    light=bpy.data.objects.new('Late sun / warm rim',ld);scene.collection.objects.link(light);light.rotation_euler=(math.radians(28),math.radians(-24),math.radians(-38))
    fill=bpy.data.lights.new('Sky fill','AREA');fill.energy=10000;fill.shape='DISK';fill.size=100;fill.color=(.54,.71,1)
    o=bpy.data.objects.new('Sky fill',fill);scene.collection.objects.link(o);o.location=(80,-80,140);point_at(o,(0,0,35))
    camdata=bpy.data.cameras.new('Hero Camera');cam=bpy.data.objects.new('Hero Camera',camdata);scene.collection.objects.link(cam)
    cam.location=(-170,-235,132);point_at(cam,(-2,4,43));camdata.lens=52;camdata.clip_end=2000;scene.camera=cam
    # A separate render-only low cloud bank; excluded from GLB geometry.
    bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,4));fog=bpy.context.object;fog.name='RENDER ONLY - cloud sea';fog.dimensions=(270,250,29);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    m=bpy.data.materials.new('Atmosphere / no bitmap texture');m.use_nodes=True;n=m.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputMaterial');volume=n.new('ShaderNodeVolumePrincipled');volume.inputs['Color'].default_value=(.8,.88,1,1);volume.inputs['Anisotropy'].default_value=.25
    coord=n.new('ShaderNodeTexCoord');tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=5;tex.inputs['Detail'].default_value=3
    sep=n.new('ShaderNodeSeparateXYZ');inv=n.new('ShaderNodeMath');inv.operation='SUBTRACT';inv.inputs[0].default_value=1
    mul=n.new('ShaderNodeMath');mul.operation='MULTIPLY';density=n.new('ShaderNodeMath');density.operation='MULTIPLY';density.inputs[1].default_value=.085
    link=m.node_tree.links;link.new(coord.outputs['Generated'],tex.inputs['Vector']);link.new(coord.outputs['Generated'],sep.inputs[0]);link.new(sep.outputs['Z'],inv.inputs[1]);link.new(inv.outputs[0],mul.inputs[0]);link.new(tex.outputs['Fac'],mul.inputs[1]);link.new(mul.outputs[0],density.inputs[0]);link.new(density.outputs[0],volume.inputs['Density']);link.new(volume.outputs[0],out.inputs['Volume'])
    fog.data.materials.append(m);fog.hide_viewport=True;fog.hide_render=True;fog['export_geometry']=False
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                s=area.spaces.active;s.clip_end=2000;s.overlay.show_overlays=False;s.region_3d.view_perspective='CAMERA';s.shading.type='MATERIAL'
                s.shading.use_scene_world=False
    scene['asset_name']='山巅';scene['seed']=SEED;scene['gameplay_status']='Visual model only. No 2D collision, navigation or live-map integration.'

def preserve_gltf_tints(path):
    # Blender 5.2 exports the image from MixRGB but drops its constant multiply.
    # Use standard glTF baseColorFactor; preserve every original embedded PNG byte.
    raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+size]);tail=raw[20+size:]
    binary=tail[8:]
    for image in doc['images']:
        view=doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0)
        assert binary[start:start+view['byteLength']]==(ROOT/'textures'/(image['name']+'.png')).read_bytes(), 'Texture export changed original PNG bytes'
    for m in doc['materials']:
        key=m['name'].removeprefix('MC / ')
        m['pbrMetallicRoughness']['baseColorFactor']=list(MATERIALS[key].diffuse_color)
    encoded=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)

def main():
    if (ROOT/'山巅.blend').exists() and '--rebuild' not in sys.argv:
        raise RuntimeError("Model already exists. Back up artist edits before explicitly using -- --rebuild.")
    t=time.time();status('building')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        if c.name=='Collection':bpy.data.collections.remove(c)
    palette=[('Stone','stone.png',(.9,.94,.98,1)),('Andesite','andesite.png',(.83,.89,.94,1)),('Pale granite','diorite.png',(.93,.96,1,1)),('Deep rock','deepslate.png',(1,1,1,1)),('Snow','snow.png',(1,1,1,1)),('Glacier','packed_ice.png',(1,1,1,1)),('Grass','grass_block_top.png',(.42,.61,.29,1)),('Dirt','dirt.png',(1,1,1,1)),('Spruce bark','spruce_log.png',(1,1,1,1)),('Spruce end','spruce_log_top.png',(1,1,1,1)),('Spruce needles','spruce_leaves.png',(.30,.47,.24,1)),('Trail','stone_bricks.png',(.97,.93,.82,1)),('Worn trail','cracked_stone_bricks.png',(.92,.9,.83,1)),('Cairn','cobblestone.png',(.88,.92,.96,1))]
    for key,tex,tint in palette:material(key,tex,tint)
    build_terrain();trees=build_forest();build_summit();flush_meshes();presentation()
    objects=[o for o in bpy.context.scene.objects if o.get('export_geometry',False)]
    triangles=sum(len(p.vertices)-2 for o in objects for p in o.data.polygons)
    vertices=sum(len(o.data.vertices) for o in objects)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    status('exporting',mesh_objects=len(objects),vertices=vertices,triangles=triangles)
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'shandian.glb'),export_format='GLB',use_selection=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=True)
    preserve_gltf_tints(ROOT/'shandian.glb')
    bpy.ops.object.select_all(action='DESELECT')
    # Pack original PNG bytes into the native project for portability.
    for image in bpy.data.images:
        if image.source=='FILE':image.pack()
    bpy.context.scene.render.filepath=str(ROOT/'summit_hero.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'山巅.blend'))
    metrics=dict(asset='山巅',blender=bpy.app.version_string,seed=SEED,mesh_objects=len(objects),vertices=vertices,triangles=triangles,trees=trees,footprint_blocks=[N,N],height_blocks=max(HEIGHT.values())-BASE,summit_anchor=[8.5,15.5,96.25],build_seconds=round(time.time()-t,2),blend='山巅.blend',glb='shandian.glb',textures_packed=True,gameplay_integrated=False)
    (ROOT/'model_metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2),encoding='utf-8')
    status('model_ready',**metrics)

if __name__=='__main__':
    try:main()
    except Exception as exc:
        status('failed',error=repr(exc));traceback.print_exc();raise
