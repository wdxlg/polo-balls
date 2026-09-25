"""Headless native-file, texture provenance and portable GLB round-trip checks."""
import bpy,json,pathlib,struct,hashlib,math
from mathutils import Vector
ROOT=pathlib.Path(bpy.data.filepath).parent
checks=[]
def check(name,ok,detail=None):
    checks.append(dict(name=name,passed=bool(ok),detail=detail))
    if not ok:raise AssertionError(name+': '+str(detail))
def geometry():return [o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('export_geometry',False)]
def bounds(objects):
    points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    return [[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
try:
    native=geometry();metrics=json.loads((ROOT/'model_metrics.json').read_text(encoding='utf-8'))
    check('native geometry objects',len(native)==metrics['mesh_objects'],len(native))
    triangles=sum(len(p.vertices)-2 for o in native for p in o.data.polygons)
    check('native triangles',triangles==metrics['triangles'],triangles)
    native_bounds=bounds(native)
    check('full asset height over 100 blocks',native_bounds[1][2]-native_bounds[0][2]>100,native_bounds)
    for o in native:
        check('valid mesh: '+o.name,not o.data.validate(verbose=False,clean_customdata=False))
        check('nondegenerate faces: '+o.name,all(p.area>1e-8 for p in o.data.polygons))
        check('UV: '+o.name,len(o.data.uv_layers)==1)
    provenance=json.loads((ROOT/'SOURCE.json').read_text(encoding='utf-8'))
    for t in provenance['textures']:
        raw=(ROOT/t['file']).read_bytes()
        check('original SHA256: '+t['file'],hashlib.sha256(raw).hexdigest()==t['sha256'])
    for m in bpy.data.materials:
        if 'original_texture' not in m:continue
        tex=next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE')
        check('packed original: '+m.name,tex.image.packed_file is not None and bytes(tex.image.packed_file.data)==(ROOT/'textures'/m['original_texture']).read_bytes())
        check('nearest texture: '+m.name,tex.interpolation=='Closest')
    raw=(ROOT/'shandian.glb').read_bytes();magic,ver,size=struct.unpack_from('<4sII',raw)
    check('GLB header',magic==b'glTF' and ver==2 and size==len(raw))
    n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);binary=raw[28+n:]
    check('embedded textures only',all('bufferView' in im and 'uri' not in im for im in g['images']))
    check('geometry only, no light/camera',not g.get('cameras') and not g.get('extensions',{}).get('KHR_lights_punctual'))
    check('nearest GLB sampler',all(s.get('magFilter')==9728 for s in g['samplers']))
    for m in g['materials']:
        actual=m['pbrMetallicRoughness'].get('baseColorFactor',[1,1,1,1]);expected=list(bpy.data.materials[m['name']].diffuse_color)
        check('portable tint: '+m['name'],max(abs(a-b) for a,b in zip(actual,expected))<1e-5,actual)
    for im in g['images']:
        v=g['bufferViews'][im['bufferView']];off=v.get('byteOffset',0)
        check('GLB original PNG: '+im['name'],binary[off:off+v['byteLength']]==(ROOT/'textures'/(im['name']+'.png')).read_bytes())
    for o in native:bpy.data.objects.remove(o,do_unlink=True)
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'shandian.glb'))
    imported=[o for o in bpy.data.objects if o not in before and o.type=='MESH']
    check('GLB round-trip mesh count',len(imported)==metrics['mesh_objects'],len(imported))
    rt_triangles=sum(len(p.vertices)-2 for o in imported for p in o.data.polygons)
    check('GLB round-trip triangles',rt_triangles==triangles,rt_triangles)
    bpy.context.view_layer.update();rt_bounds=bounds(imported)
    check('GLB round-trip world bounds',max(abs(a-b) for rowa,rowb in zip(native_bounds,rt_bounds) for a,b in zip(rowa,rowb))<.001,rt_bounds)
    scene=bpy.context.scene;prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.refresh_devices()
    for d in prefs.devices:d.use=d.type=='OPTIX'
    scene.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU'
    scene.cycles.samples=24;scene.render.resolution_x=900;scene.render.resolution_y=700;scene.render.resolution_percentage=100;scene.render.filepath=str(ROOT/'summit_glb_check.png')
    bpy.ops.render.render(write_still=True)
    check('GLB round-trip rendered', (ROOT/'summit_glb_check.png').exists())
    report=dict(passed=True,checks=len(checks),blender=bpy.app.version_string,native_bounds=native_bounds,geometry_objects=len(imported),triangles=rt_triangles,packed_materials=14,render_device=scene.cycles.device,results=checks)
    (ROOT/'validation_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('SUMMIT_VALIDATION_PASS',len(checks),flush=True)
except Exception as e:
    (ROOT/'validation_report.json').write_text(json.dumps(dict(passed=False,error=repr(e),results=checks),ensure_ascii=False,indent=2),encoding='utf-8')
    raise
