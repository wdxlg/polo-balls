#!/usr/bin/env python3
"""Pinned Mojang textures / Warden bones -> offline 2D resources.
No runtime network/Python dependency. Native source hashes are verified before use.
Block projections, lighting, clip timing and layered emissivity are 2D adapters,
not a claim of pixel-identical Minecraft engine rendering or redistribution rights.
"""
from pathlib import Path
import argparse, concurrent.futures, copy, hashlib, importlib.util, json, math
import shutil, urllib.request
import numpy as np
from PIL import Image

B = Path(__file__).resolve().parent
ROOT = B.parents[2]
OUT = ROOT / 'Images/characters/我的世界/frontier'
SOUND_OUT = ROOT / 'audio/characters/我的世界/frontier'
LOCK = json.loads((B / 'assets.lock.json').read_text(encoding='utf-8'))
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()


def valid(data, entry):
    if 'git_sha1' in entry:
        return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest() == entry['git_sha1']
    return hashlib.sha1(data).hexdigest() == entry['sha1']


def acquire(entry):
    path = B / entry['path']
    if path.exists() and valid(path.read_bytes(), entry):
        return
    if args.check:
        raise RuntimeError('Missing or changed original: '+entry['path'])
    request = urllib.request.Request(entry['url'], headers={'User-Agent': 'MinecraftArenaAssetBaker/1.0'})
    with urllib.request.urlopen(request, timeout=40) as response:
        data = response.read()
    if not valid(data, entry):
        raise RuntimeError('Original hash mismatch: '+entry['path'])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    list(pool.map(acquire, LOCK['files']))
print('SOURCE HASHES OK:', len(LOCK['files']), flush=True)
if args.check:
    manifest = json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    for name, digest in manifest['outputs'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, name
    print('OUTPUT HASHES OK:', len(manifest['outputs']), flush=True)
    raise SystemExit(0)

OUT.mkdir(parents=True, exist_ok=True)
SOUND_OUT.mkdir(parents=True, exist_ok=True)
source = B / 'resource_pack'
textures = {
    'moss_tile': 'blocks/moss_block.png', 'wood_sword': 'items/wood_sword.png',
    'stick': 'items/stick.png', 'bone_meal': 'items/dye_powder_white.png',
    'grass': 'blocks/grass_carried.png', 'sculk_top': 'blocks/sculk_shrieker_top.png',
    'sculk_inner': 'blocks/sculk_shrieker_can_summon_inner_top.png',
    'table_top': 'blocks/crafting_table_top.png', 'planks': 'blocks/planks_oak.png',
    'sonic': 'particle/sonic_explosion.png',
}
for name, filename in textures.items():
    shutil.copyfile(source/'textures'/filename, OUT/(name+'.png'))
for entry in LOCK['files']:
    if 'cue' in entry:
        shutil.copyfile(B/entry['path'], SOUND_OUT/(entry['cue']+'.ogg'))

spec = importlib.util.spec_from_file_location('frontier_native_rasterizer', B.parent/'mc_native_assets/bake_native_mobs.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def vector(value, env, direction='post'):
    if isinstance(value, dict):
        value = value.get(direction, value.get('post', value.get('pre')))
    if not isinstance(value, (list, tuple, np.ndarray)):
        value = [value]*3
    return np.array([m.molang(item, env) for item in value], float)


def sample(value, t, env):
    if not isinstance(value, dict):
        return vector(value, env)
    keys = sorted((float(k), v) for k, v in value.items())
    if t <= keys[0][0]:
        return vector(keys[0][1], env, 'pre')
    if t >= keys[-1][0]:
        return vector(keys[-1][1], env)
    for i in range(len(keys)-1):
        start, va = keys[i]; end, vb = keys[i+1]
        if start <= t <= end:
            p1 = vector(va, env); p2 = vector(vb, env, 'pre')
            u = (t-start)/(end-start)
            cubic = any(isinstance(v, dict) and v.get('lerp_mode') == 'catmullrom' for v in (va,vb))
            if cubic:
                p0 = vector(keys[max(0,i-1)][1], env)
                p3 = vector(keys[min(len(keys)-1,i+2)][1], env, 'pre')
                return .5*((2*p1)+(-p0+p2)*u+(2*p0-5*p1+4*p2-p3)*u*u+(-p0+3*p1-3*p2+p3)*u*u*u)
            return p1+(p2-p1)*u
    raise RuntimeError('Unsampled keyframe')


class WardenBaker(m.Baker):
    def __init__(self):
        geometry = m.load_json(source/'models/entity/warden.geo.json')['minecraft:geometry'][0]
        self.models = {'warden': copy.deepcopy(geometry['bones'])}
        self.animations = m.load_json(source/'animations/warden.animation.json')['animations']
        skin = Image.open(source/'textures/entity/warden/warden.png').convert('RGBA')
        # Original overlay pixels are composited as a fixed readable baked layer.
        skin.alpha_composite(Image.open(source/'textures/entity/warden/warden_bioluminescent_layer.png').convert('RGBA'))
        skin.alpha_composite(Image.open(source/'textures/entity/warden/warden_heart.png').convert('RGBA'))
        self.skins = {'warden': np.array(skin)}
        yaw, pitch = np.radians([25,12])
        self.right = np.array([math.cos(yaw),0,math.sin(yaw)])
        self.camera = np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
        self.up = np.cross(self.right,self.camera)
        self.view = np.array([self.right,-self.up,self.camera])
        self.scale = {'warden': 3.0}; self.foot = {'warden': 213}

    def pose(self, role, state, t, peek=0):
        walk = state == 'walk'
        phase = t*math.tau
        speed = .32 if walk else 0.0
        bob = t*20
        env = {
            'variable.head_x_rot': 68.7549*math.cos(phase+math.pi/2)*min(.35,speed)+math.sin(math.radians(bob*5.72958))*.06,
            'variable.head_z_rot': 17.1887*math.sin(phase)*speed+math.cos(math.radians(bob*5.72958))*.06,
            'variable.body_x_rot': 57.2958*math.cos(phase)*min(.35,speed)+math.cos(math.radians(bob*5.72958))*.025,
            'variable.body_z_rot': 5.72958*math.sin(phase)*speed+math.sin(math.radians(bob*5.72958))*.025,
            'variable.left_leg_x_rot': 57.2958*math.cos(phase)*speed,
            'variable.right_leg_x_rot': 57.2958*math.cos(phase+math.pi)*speed,
            'variable.left_arm_x_rot': -45.8366*math.cos(phase)*speed,
            'variable.right_arm_x_rot': -45.8366*math.sin(phase)*speed,
            'variable.modified_bob_sin': math.sin(t*2),
            'variable.modified_bob_cos': math.cos(t*2),
            'variable.left_tendril_x_rot': math.cos(math.radians(bob*128.9155))*18,
            'variable.right_tendril_x_rot': -math.cos(math.radians(bob*128.9155))*18,
            'query.target_x_rotation': 0, 'query.target_y_rotation': 0, 'this': 0,
        }
        poses = {bone['name'].lower(): {'position': np.zeros(3), 'rotation': np.array(bone.get('rotation',[0,0,0]),float), 'scale': np.ones(3)} for bone in self.models[role]}
        names = ([] if state in ('emerge','dig') else ['move'])+['bob','shiver']
        if state not in ('idle','walk'):
            names.append('sonic_boom' if state == 'sonic' else state)
        for name in names:
            animation = self.animations['animation.warden.'+name]
            for bone, channels in animation['bones'].items():
                pose = poses[bone.lower()]
                for channel, value in channels.items():
                    if channel not in pose:
                        continue
                    values = sample(value,t,env)
                    if channel == 'scale':
                        pose[channel] *= values
                    else:
                        pose[channel] += values
        return poses


m.W, m.H = 192,240
baker = WardenBaker()
clips = {'idle':(12,math.pi,True),'walk':(16,1.0,True),'emerge':(24,6.64,False),'attack':(10,.33333,False),'sonic':(24,3.0,False),'dig':(20,5.0,False),'sniff':(12,3.32,False)}
count = sum(v[0] for v in clips.values())
columns = 12
atlas = Image.new('RGBA',(192*columns,240*math.ceil(count/columns)))
frames = []
for clip,(number,length,loop) in clips.items():
    for i in range(number):
        t = length*i/(number if loop else max(1,number-1))
        image = baker.render('warden',clip,t)
        slot = len(frames); x = slot%columns*192; y = slot//columns*240
        atlas.alpha_composite(image,(x,y))
        filename = 'warden_%s_%02d.png' % (clip,i)
        image.save(OUT/filename)
        frames.append({'clip':clip,'index':i,'slot':slot,'x':x,'y':y,'file':filename,'bounds':image.getbbox(),'pixel_sha256':hashlib.sha256(image.tobytes()).hexdigest()})
        if clip == 'idle' and i == 0:
            image.save(OUT/'warden_preview.png')
    print('BAKED WARDEN:',clip,number,flush=True)
atlas.save(OUT/'warden_frames.png',optimize=True)
# Full frame textures match the existing mc_native_animation renderer contract.
# The shared soft-body/mirror shader cannot safely remap arbitrary atlas subrect UVs.
resource = '[gd_resource type="SpriteFrames" load_steps=%d format=3]\n' % (count+1)
for frame in frames:
    resource += '\n[ext_resource type="Texture2D" path="res://Images/characters/我的世界/frontier/%s" id="f%d"]\n' % (frame['file'],frame['slot'])
resource += '\n[resource]\nanimations = [\n'
entries = []
for clip,(number,length,loop) in clips.items():
    values = ','.join('{"duration":1.0,"texture":ExtResource("f%d")}' % f['slot'] for f in frames if f['clip']==clip)
    entries.append('{"name":&"%s","loop":%s,"speed":%.6f,"frames":[%s]}' % (clip,str(loop).lower(),number/length,values))
resource += ',\n'.join(entries)+'\n]\n'
(OUT/'warden_frames.tres').write_text(resource,encoding='utf-8')


class BlockBaker(m.Baker):
    def __init__(self):
        yaw,pitch = np.radians([30,25])
        self.camera = np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
        self.right = np.array([math.cos(yaw),0,math.sin(yaw)])
        self.view = np.array([self.right,-np.cross(self.right,self.camera),self.camera])
        self.scale = {'block':4.25}; self.foot = {'block':99}

    def textured_box(self, low, high, top, side):
        x,y,z = low; X,Y,Z = high
        faces = [([[x,Y,z],[X,Y,z],[X,y,z],[x,y,z]],side,[0,0,-1]),
                 ([[X,Y,z],[X,Y,Z],[X,y,Z],[X,y,z]],side,[1,0,0]),
                 ([[x,Y,Z],[X,Y,Z],[X,Y,z],[x,Y,z]],top,[0,1,0])]
        for points,texture,normal in faces:
            if np.dot(normal,self.camera)<0:
                continue
            im = Image.open(source/'textures/blocks'/texture).convert('RGBA')
            im = im.crop((0,0,16,16))
            uv = np.array([[0,0],[16,0],[16,16],[0,16]],float)
            lighting = .72+.28*max(0,np.dot(normal,[-.35,.8,-.48]))
            self.quad(np.array(points,float),np.eye(4),uv,np.array(im),'block',lighting)

    def block(self, kind):
        self.rgba = np.zeros((m.H,m.W,4),np.uint8); self.depth = np.full((m.H,m.W),-1e10)
        if kind == 'moss':
            self.textured_box([-8,0,-8],[8,16,8],'moss_block.png','moss_block.png')
        elif kind == 'table':
            self.textured_box([-8,0,-8],[8,16,8],'crafting_table_top.png','crafting_table_side.png')
        else:
            self.textured_box([-8,0,-8],[8,8,8],'sculk_shrieker_top.png','sculk_shrieker_side.png')
            self.textured_box([-5,8.01,-5],[5,8.02,5],'sculk_shrieker_can_summon_inner_top.png','sculk_shrieker_side.png')
        return Image.fromarray(self.rgba)


m.W=m.H=128
blocks=BlockBaker()
for kind in ('moss','shrieker','table'):
    blocks.block(kind).save(OUT/(kind+'_block.png'))
outputs = list(OUT.glob('*.png'))+list(OUT.glob('*.tres'))+list(SOUND_OUT.glob('*.ogg'))
manifest = {
    'source_commit':LOCK['bedrock_commit'],'java_version':LOCK['java_version'],
    'license_notice':LOCK['license_notice'], 'frame_size':[192,240], 'warden_frames':frames,
    'adapter_notes':'Native Warden bones and keyframes (including Catmull-Rom), resampled to 2D state durations. Native entity movement constants with a synthetic one-second stride. Fixed emissive-layer composite, fixed camera/lighting. Moss/crafting/shrieker block-face projection is an arena icon adapter; it is not an exported block mesh. No vanilla rendering engine is embedded.',
    'outputs':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in outputs},
}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('FRONTIER ASSETS READY:',len(outputs),'resources;',count,'native Warden frames',flush=True)
