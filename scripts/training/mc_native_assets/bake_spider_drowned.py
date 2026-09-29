#!/usr/bin/env python3
"""Pinned Bedrock bones -> full-frame SpriteFrames; no runtime Python/3D.
Spider walk and drowned humanoid/spear tracks are Mojang data. Spider cast/lunge
and spear attachment/release timing are explicitly 2D gameplay adaptations.
"""
import argparse, copy, hashlib, json, math, re, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image
from bake_native_mobs import Baker, ROOT, W, H, load_json, molang, rotation

COMMIT = '736072450c26a7c67f07b1661f29d9a5ebaa14b1'
CACHE = ROOT / 'mc16_resource_pack'
FILES = ['animations/spider.animation.json', 'animations/zombie.animation.json',
         'animations/drowned.animation.json', 'animations/humanoid.animation.json',
         'models/entity/spider.geo.json', 'models/entity/drowned.geo.json',
         'models/entity/trident.geo.json', 'textures/entity/spider/spider.tga',
         'textures/entity/zombie/drowned.tga', 'textures/entity/trident.png',
         'entity/spider.entity.json', 'entity/drowned.entity.json',
         'animation_controllers/drowned.animation_controllers.json']
CLIPS = {
    'spider': {'idle': (1, 1., True), 'walk': (24, 1., True),
               'cast': (12, .35, False), 'lunge': (12, .28, False)},
    'drowned': {'idle': (48, 360/103.2, True), 'walk': (24, 1., True),
                'splash': (16, .4, False), 'throw': (16, .4, False),
                'windup': (24, .75, False), 'idle_empty': (48, 360/103.2, True),
                'walk_empty': (24, 1., True), 'throw_empty': (16, .4, False)}
}

def fetch():
    records = []
    for name in FILES:
        url = f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{COMMIT}/resource_pack/{name}'
        path = CACHE / name
        if not path.exists():
            data = urllib.request.urlopen(url, timeout=45).read()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        records.append({'path': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'url': url})
    (ROOT/'sources_mc16.json').write_text(json.dumps({'commit': COMMIT, 'license': 'Minecraft EULA; see LICENSE.md and README.md', 'files': records}, indent=2), encoding='utf-8')


def evaluate(value, env):
    # Spider uses abs; keep the shared strict Molang evaluator unchanged.
    # Its abs arguments contain nested cos/sin calls, so replace balanced calls.
    if not isinstance(value, str): return molang(value, env)
    while 'math.abs(' in value:
        start = value.index('math.abs(')
        first = start + len('math.abs(')
        depth, end = 1, first
        while depth:
            if value[end] == '(': depth += 1
            elif value[end] == ')': depth -= 1
            end += 1
        value = value[:start] + 'math.sqrt(math.pow(' + value[first:end-1] + ', 2))' + value[end:]
    return molang(value, env)

class MC16Baker(Baker):
    def __init__(self):
        super().__init__(ROOT/'resource_pack')
        self.draw_item = True
        for name in ('spider', 'zombie', 'drowned', 'humanoid'):
            self.animations.update(load_json(CACHE/f'animations/{name}.animation.json')['animations'])
        for role in CLIPS:
            data = load_json(CACHE/f'models/entity/{role}.geo.json')
            geo = data['minecraft:geometry'][0] if 'minecraft:geometry' in data else next(v for k,v in data.items() if k.startswith('geometry.'))
            self.models[role] = copy.deepcopy(geo['bones'])
        for role,path in [('spider','spider/spider.tga'),('drowned','zombie/drowned.tga')]:
            self.skins[role] = np.array(Image.open(CACHE/'textures/entity'/path).convert('RGBA'))
        # TGA alpha encodes emissivity as well as cutout; keep red spider eyes.
        self.skins['spider'][:,:,3] = 255
        alpha = self.skins['drowned'][:,:,3]
        alpha[alpha > 0] = 255
        self.trident_skin = np.array(Image.open(CACHE/'textures/entity/trident.png').convert('RGBA'))
        pole = load_json(CACHE/'models/entity/trident.geo.json')['minecraft:geometry'][0]['bones'][0]
        # Adapter: place grip in rightItem space. Native trident geometry/UV retained.
        self.trident_cubes = copy.deepcopy(pole['cubes'])
        for cube in self.trident_cubes:
            cube['origin'] = (np.array(cube['origin']) + [-6, 5, 1]).tolist()
            cube['_mc16_trident'] = True
        self.scale.update(spider=3.6, drowned=4.15)
        self.foot.update(spider=151, drowned=196)

    def pose(self, role, state, t, peek=0):
        state = state.removesuffix('_empty')
        walk = state == 'walk'
        duration = CLIPS[role][state][1]
        progress = min(max(t/duration, 0), 1)
        spear = state in ('throw', 'windup')
        env = {'this': 0, 'query.life_time': t, 'query.anim_time': t*360/38.17,
               'query.target_x_rotation': 0, 'query.target_y_rotation': 0,
               'variable.tcos0': math.cos(t*math.tau)*28.65 if walk else 0,
               'variable.attack_time': progress if state in ('throw','splash') else 0,
               'variable.is_brandishing_spear': int(spear),
               'variable.is_holding_left': 0, 'variable.is_holding_right': 1,
               'variable.charge_amount': progress if state == 'windup' else 0}
        poses = {b['name'].lower(): {'position': np.zeros(3), 'rotation': np.array(b.get('rotation',[0,0,0]), dtype=float), 'scale': np.ones(3)} for b in self.models[role]}
        if role == 'spider':
            names = ['spider.default_leg_pose', 'spider.look_at_target']
            if walk: names += ['spider.walk']
        else:
            names = ['humanoid.move', 'humanoid.holding']
            names += ['drowned.attack.rotations' if spear else 'zombie.attack_bare_hand']
            if spear: names += ['humanoid.brandish_spear']
            names += ['humanoid.bob']
        for name in names:
            for bone,channels in self.animations['animation.'+name]['bones'].items():
                if bone.lower() not in poses: continue
                p = poses[bone.lower()]
                for channel,values in channels.items():
                    if channel not in p: continue
                    if isinstance(values,(int,float,str)): values = [values]*3
                    for i,value in enumerate(values):
                        env['this'] = p[channel][i]
                        result = evaluate(value,env)
                        if channel == 'scale': p[channel][i] = result
                        else: p[channel][i] += result
        if role == 'spider' and state in ('cast','lunge'):
            # No vanilla web-spitting track exists: animate bones, never the PNG.
            pulse = math.sin(progress*math.pi)
            poses['head']['rotation'][0] += (-12 if state == 'lunge' else 12)*pulse
            for i in range(8):
                poses[f'leg{i}']['rotation'][2] += (1 if i%2 == 0 else -1)*pulse*(20 if state == 'lunge' else 7)
        return poses

    def cube(self, cube, m, skin, role, mirror):
        if cube.get('_mc16_trident'):
            # Scale only the item around its grip; retain native UVs, body and hand track.
            pivot = np.array(next(b for b in self.models['drowned'] if b['name'] == 'rightItem')['pivot'])
            shrink = np.eye(4)
            shrink[:3, :3] *= 2.0/3.0
            shrink[:3, 3] = pivot*(1.0-2.0/3.0)
            m = m @ shrink
        super().cube(cube, m, self.trident_skin if cube.get('_mc16_trident') else skin, role, mirror)

    def render(self, role, state, t, peek=0):
        if role == 'drowned':
            item = next(b for b in self.models[role] if b['name'] == 'rightItem')
            # Release is visual only: projectile timing/damage is unchanged.
            visible = self.draw_item and not state.endswith('_empty') and not (state == 'throw' and t > .13)
            item['cubes'] = self.trident_cubes if visible else []
        return super().render(role,state,t,peek)


    def hand_anchor(self, state, t):
        bones = self.models['drowned']
        pose = self.pose('drowned',state,t)
        by_name = {b['name'].lower(): b for b in bones}
        world = {}
        def transform(name):
            name = name.lower()
            if name in world: return world[name]
            b, p = by_name[name], pose[name]
            pivot = np.array(b['pivot'],dtype=float)
            m = np.eye(4)
            m[:3,:3] = rotation(p['rotation']) @ np.diag(p['scale'])
            m[:3,3] = pivot+p['position']-m[:3,:3]@pivot
            if b.get('parent'): m = transform(b['parent']) @ m
            world[name] = m
            return m
        m = transform('rightitem')
        point = np.array(by_name['rightitem']['pivot']) @ m[:3,:3].T+m[:3,3]
        projected = point @ self.view.T
        return [float(projected[0]*self.scale['drowned']+W/2), float(projected[1]*self.scale['drowned']+self.foot['drowned'])]

def bake(output):
    b = MC16Baker()
    output.mkdir(parents=True,exist_ok=True)
    manifest = {'size': [W,H], 'source_commit': COMMIT, 'trident_visual_scale': 2.0/3.0, 'roles': {}}
    for role,clips in CLIPS.items():
        files, anims, dedup = [], [], {}
        data = {'clips': {}}
        preview = []
        hands = {}
        for state,(count,duration,loop) in clips.items():
            ids = []
            hands[state] = []
            for i in range(count):
                fraction = i/count if loop else i/max(count-1,1)
                image = b.render(role,state,fraction*duration)
                if role == 'drowned': hands[state].append(b.hand_anchor(state,fraction*duration))
                bounds = image.getbbox()
                assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<W and bounds[3]<H, (role,state,i,bounds)
                digest = hashlib.sha256(image.tobytes()).hexdigest()
                if digest not in dedup:
                    file = f'{role}_{len(files):03}.png'
                    image.save(output/file,optimize=True)
                    files.append(file)
                    dedup[digest] = len(files)
                ids.append(dedup[digest])
                if state == 'walk': preview.append(image)
            data['clips'][state] = {'count': count, 'duration': duration, 'loop': loop, 'unique': len(set(ids))}
            if count>1: assert len(set(ids))>1, (role,state,'static animation')
            entries = ', '.join('{"duration": 1.0, "texture": ExtResource("'+str(j)+'")}' for j in ids)
            anims.append('{"frames": ['+entries+'], "loop": '+str(loop).lower()+', "name": &"'+state+'", "speed": '+str(count/duration)+'}')
        b.draw_item = False
        data['neutral_bounds'] = list(b.render(role,'idle',0).getbbox())
        b.draw_item = True
        data['textures'] = len(files)
        manifest['roles'][role] = data
        resource = '[gd_resource type="SpriteFrames" format=3]\n\n'+'\n'.join('[ext_resource type="Texture2D" path="res://Images/characters/我的世界/native_frames/'+file+'" id="'+str(i+1)+'"]' for i,file in enumerate(files))+'\n\n[resource]\nanimations = ['+',\n'.join(anims)+']\n'
        (output/f'{role}.tres').write_text(resource,encoding='utf-8')
        # Review preview only, not used by runtime.
        pictures = []
        for frame in preview:
            bg = Image.new('RGBA',(W,H),(65,70,80,255)); bg.alpha_composite(frame); pictures.append(bg.convert('RGB'))
        pictures[0].save(ROOT/f'{role}_animation_preview.gif',save_all=True,append_images=pictures[1:],duration=42,loop=0)
        if role == 'drowned':
            tracks = ',\n'.join('"'+state+'": ['+', '.join('Vector2(%.4f,%.4f)' % tuple(point) for point in values)+']' for state,values in hands.items())
            (output/'drowned_hands.gd').write_text('extends RefCounted\n# Baked rightItem bone positions, in 160x224 frame pixels.\nconst TRACKS:Dictionary = {\n'+tracks+'\n}\n',encoding='utf-8')
        print(role,json.dumps(data),flush=True)
    (output/'manifest_mc16.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--fetch',action='store_true')
    parser.add_argument('--output',type=Path,default=ROOT.parents[2]/'Images/characters/我的世界/native_frames')
    args = parser.parse_args()
    if args.fetch: fetch()
    bake(args.output)
