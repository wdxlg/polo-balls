"""Render the saved model; never overwrite the artist's open .blend scene."""
import bpy,pathlib,json,sys,time,traceback
from mathutils import Vector
ROOT=pathlib.Path(bpy.data.filepath).parent
scene=bpy.context.scene
started=time.time()
def status(stage,**data):
    (ROOT/'render_status.json').write_text(json.dumps(dict(stage=stage,**data),ensure_ascii=False,indent=2),encoding='utf-8')
    print('SUMMIT_RENDER',stage,data,flush=True)
def render(name,width,height,samples):
    scene.render.resolution_x=width;scene.render.resolution_y=height;scene.render.resolution_percentage=100
    scene.cycles.samples=samples;scene.render.filepath=str(ROOT/name)
    status('rendering',file=name,width=width,height=height,samples=samples,device=scene.cycles.device)
    bpy.ops.render.render(write_still=True)
try:
    scene.render.engine='CYCLES'
    prefs=bpy.context.preferences.addons['cycles'].preferences
    gpu=False
    for backend in ['OPTIX','CUDA']:
        try:
            prefs.compute_device_type=backend;prefs.refresh_devices()
            good=[d for d in prefs.devices if d.type==backend]
            if good:
                for d in prefs.devices:d.use=d.type==backend
                gpu=True;print('RENDER_GPU',backend,[(d.name,d.type,d.use) for d in prefs.devices],flush=True);break
        except Exception as e:print('GPU_BACKEND_SKIP',backend,str(e),flush=True)
    scene.cycles.device='GPU' if gpu else 'CPU'
    if '--preview' in sys.argv:
        render('summit_preview.png',1050,820,24)
    else:
        render('summit_hero.png',1800,1400,64)
        scene.camera.location=(110,-130,160)
        scene.camera.rotation_euler=(Vector((5,8,65))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
        scene.camera.data.lens=55
        render('summit_detail.png',1400,1100,48)
    status('complete',seconds=round(time.time()-started,2),device=scene.cycles.device)
except Exception as e:
    status('failed',error=repr(e));traceback.print_exc();raise
