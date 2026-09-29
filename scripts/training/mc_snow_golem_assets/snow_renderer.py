"""Shared offline renderer for the original Bedrock Snow Golem geometry and texels.
No downloads or file writes occur on import. Existing resource acquisition and
new full-heading views use this one native cube/UV renderer.
"""
from pathlib import Path
import math, sys
import numpy as np
from PIL import Image
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
sys.path.insert(0,str(PROJECT/'scripts/training/mc_native_assets'))
from bake_native_mobs import Baker,load_json,molang

class SnowBaker(Baker):
    def __init__(self, source=None):
        source = Path(source) if source is not None else HERE / 'resource_pack'
        bones = load_json(source / 'models/entity/snow_golem.v1.0.geo.json')['geometry.snowgolem']['bones']
        bones.append({'name': 'pumpkin', 'parent': 'head', 'pivot': [0, 20, 0],
                      'cubes': [{'origin': [-5, 19, -5], 'size': [10, 10, 10], 'block': 'pumpkin'}]})
        self.models = {'snow': bones, 'pumpkin_block': [{'name': 'cube', 'pivot': [0, 0, 0], 'cubes': [{'origin': [-8, 0, -8], 'size': [16, 16, 16], 'block': 'pumpkin'}]}],
                       'snow_block': [{'name': 'cube', 'pivot': [0, 0, 0], 'cubes': [{'origin': [-8, 0, -8], 'size': [16, 16, 16], 'block': 'snow'}]}]}
        skin = np.array(Image.open(source / 'textures/entity/snow_golem.png').convert('RGBA'))
        self.skins = {role: skin for role in self.models}
        self.blocks = {name: np.array(Image.open(source / f'textures/blocks/{name}.png').convert('RGBA')) for name in ['snow', 'pumpkin_face_off', 'pumpkin_side', 'pumpkin_top']}
        self.animations = load_json(source / 'animations/snow_golem.animations.v1.0.json')['animations']
        yaw, pitch = np.radians([30, 12])
        self.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.camera = np.array([math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch)])
        self.up = np.cross(self.right, self.camera)
        self.view = np.array([self.right, -self.up, self.camera])
        self.scale = {'snow': 5.1, 'pumpkin_block': 5.0, 'snow_block': 5.0}
        self.foot = {'snow': 202, 'pumpkin_block': 166, 'snow_block': 166}

    def pose(self, role, state, t, peek=0):
        poses = {b['name'].lower(): {'position': np.zeros(3), 'rotation': np.array(b.get('rotation', [0, 0, 0]), float), 'scale': np.ones(3)} for b in self.models[role]}
        if role != 'snow': return poses
        env = {'query.target_y_rotation': t, 'this': 0.0}
        for name in ['animation.snowgolem.move', 'animation.snowgolem.arms']:
            for bone, channels in self.animations[name]['bones'].items():
                for channel, values in channels.items():
                    for i, value in enumerate(values):
                        env['this'] = poses[bone][channel][i]
                        poses[bone][channel][i] += molang(value, env)
        poses['head']['rotation'][1] = t
        if state == 'bare': poses['pumpkin']['scale'] = np.zeros(3)
        return poses

    def cube(self, cube, matrix, skin, role, mirror):
        if 'block' not in cube: return super().cube(cube, matrix, skin, role, mirror)
        x, y, z = cube['origin']; dx, dy, dz = cube['size']
        verts = np.array([[x,y,z],[x+dx,y,z],[x+dx,y+dy,z],[x,y+dy,z], [x,y,z+dz],[x+dx,y,z+dz],[x+dx,y+dy,z+dz],[x,y+dy,z+dz]])
        for ids, normal, face in [([3,2,1,0],[0,0,-1],'front'),([6,7,4,5],[0,0,1],'side'),([7,3,0,4],[-1,0,0],'side'),([2,6,5,1],[1,0,0],'side'),([7,6,2,3],[0,1,0],'top'),([0,1,5,4],[0,-1,0],'top')]:
            n = matrix[:3,:3] @ normal; n = n / max(np.linalg.norm(n), 1e-8)
            if np.dot(n, self.camera) < -.001: continue
            texture_name = 'snow' if cube['block'] == 'snow' else {'front':'pumpkin_face_off','side':'pumpkin_side','top':'pumpkin_top'}[face]
            light = .76 + .24 * max(0, float(np.dot(n, np.array([-.35,.8,-.48]))))
            self.quad(verts[ids], matrix, np.array([[0,0],[16,0],[16,16],[0,16]]), self.blocks[texture_name], role, light)
