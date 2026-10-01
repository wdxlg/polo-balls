#!/usr/bin/env python3
"""三废石: Java 1.21.1 granite / diorite / andesite block textures -> orthographic cube PNGs.
Same block projection as the frontier moss block (yaw 30, pitch 25, fixed face lighting),
rasterized by bake_native_mobs.Baker.quad. Runtime has no Python dependency.
Textures copied unchanged from minecraft_1.21.1_client.jar (see sources_useless_stones.json).
"""
from pathlib import Path
import argparse, importlib.util, json, math, hashlib
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('useless_stones_rasterizer', ROOT/'bake_native_mobs.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
SIZE = 128
KINDS = ('granite', 'diorite', 'andesite')


class CubeBaker(m.Baker):
    def __init__(self, textures):
        yaw, pitch = np.radians([30, 25])
        self.camera = np.array([math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch)])
        self.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.view = np.array([self.right, -np.cross(self.right, self.camera), self.camera])
        self.scale = {'block': 4.25}
        self.foot = {'block': 99}
        self.textures = textures

    def cube(self, kind):
        m.W = m.H = SIZE
        self.rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
        self.depth = np.full((SIZE, SIZE), -1e10)
        skin = np.array(Image.open(self.textures/(kind+'.png')).convert('RGBA'))
        x, y, z = -8, 0, -8
        X, Y, Z = 8, 16, 8
        faces = [([[x, Y, z], [X, Y, z], [X, y, z], [x, y, z]], [0, 0, -1]),
                 ([[X, Y, z], [X, Y, Z], [X, y, Z], [X, y, z]], [1, 0, 0]),
                 ([[x, Y, Z], [X, Y, Z], [X, Y, z], [x, Y, z]], [0, 1, 0])]
        uv = np.array([[0, 0], [16, 0], [16, 16], [0, 16]], float)
        for points, normal in faces:
            if np.dot(normal, self.camera) < 0:
                continue
            lighting = .72+.28*max(0, np.dot(normal, [-.35, .8, -.48]))
            self.quad(np.array(points, float), np.eye(4), uv, skin, 'block', lighting)
        return Image.fromarray(self.rgba)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--textures', type=Path, required=True, help='folder with granite.png, diorite.png, andesite.png')
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    baker = CubeBaker(args.textures)
    report = {}
    for kind in KINDS:
        image = baker.cube(kind)
        path = args.output/(kind+'_block.png')
        image.save(path, optimize=True)
        report[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    print(json.dumps(report, indent=2))
