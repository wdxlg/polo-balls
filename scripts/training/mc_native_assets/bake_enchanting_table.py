#!/usr/bin/env python3
"""附魔台: Java 1.21.1 enchanting table block + floating book -> orthographic PNGs.
Block: models/block/enchanting_table.json (16x12x16 slab), same projection as the
frontier moss block / 三废石 (yaw 30, pitch 25, fixed face lighting).
Book: vanilla BookModel geometry and setupAnim(), placed like EnchantTableRenderer
(0.75 + 0.1 block above the table base, Z tilt 80 degrees), rasterized by
bake_native_mobs.Baker.quad. Runtime has no Python dependency.
Frames: book_open_0..6 = openness 0..1; book_flip_0..7 = fully open, one page-flip cycle;
book_spin_0..11 = closed book turning a full circle (30 degrees apart, spin_0 == open_0).
"""
from pathlib import Path
import argparse, importlib.util, json, math, hashlib
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('enchanting_table_rasterizer', ROOT/'bake_native_mobs.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
SIZE = 128
SCALE = 4.25
FOOT = 99
BOOK_SIZE = 96
BOOK_CENTER = (48, 48)
BOOK_HEIGHT = 13.6  # block pixels above the table base (0.75 + 0.1 blocks)
OPEN_FRAMES = 7
FLIP_FRAMES = 8
SPIN_FRAMES = 12


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


class TableBaker(m.Baker):
    def __init__(self, textures, facing):
        yaw, pitch = np.radians([30, 25])
        self.camera = np.array([math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch)])
        self.right = np.array([math.cos(yaw), 0, math.sin(yaw)])
        self.view = np.array([self.right, -np.cross(self.right, self.camera), self.camera])
        self.scale = {'block': SCALE, 'book': SCALE}
        self.foot = {'block': FOOT, 'book': BOOK_CENTER[1]}  # W/2 == BOOK_CENTER[0]
        self.textures = textures
        self.facing = facing

    def _canvas(self, w, h):
        m.W, m.H = w, h
        self.rgba = np.zeros((h, w, 4), np.uint8)
        self.depth = np.full((h, w), -1e10)

    def _skin(self, name):
        return np.array(Image.open(self.textures/(name+'.png')).convert('RGBA'))

    def block(self):
        self._canvas(SIZE, SIZE)
        x, y, z, X, Y, Z = -8, 0, -8, 8, 12, 8
        side = self._skin('enchanting_table_side')
        top = self._skin('enchanting_table_top')
        faces = [([[x, Y, z], [X, Y, z], [X, y, z], [x, y, z]], [0, 0, -1], side, [[0, 4], [16, 4], [16, 16], [0, 16]]),
                 ([[X, Y, z], [X, Y, Z], [X, y, Z], [X, y, z]], [1, 0, 0], side, [[0, 4], [16, 4], [16, 16], [0, 16]]),
                 ([[x, Y, Z], [X, Y, Z], [X, Y, z], [x, Y, z]], [0, 1, 0], top, [[0, 0], [16, 0], [16, 16], [0, 16]])]
        for points, normal, skin, uv in faces:
            if np.dot(normal, self.camera) < 0:
                continue
            lighting = .72+.28*max(0, np.dot(normal, [-.35, .8, -.48]))
            self.quad(np.array(points, float), np.eye(4), np.array(uv, float), skin, 'block', lighting)
        return Image.fromarray(self.rgba)

    # Java ModelPart.Cube with box UV; vertices in model pixels (y down).
    def java_cube(self, origin, size, tex, world, skin):
        x0, y0, z0 = origin
        dx, dy, dz = size
        x1, y1, z1 = x0+dx, y0+dy, z0+dz
        u, v = tex
        V = {7: (x0, y0, z0), 0: (x1, y0, z0), 1: (x1, y1, z0), 2: (x0, y1, z0),
             3: (x0, y0, z1), 4: (x1, y0, z1), 5: (x1, y1, z1), 6: (x0, y1, z1)}
        fu = [u, u+dz, u+dz+dx, u+dz+dx+dx, u+dz+dx+dz, u+dz+dx+dz+dx]
        fv = [v, v+dz, v+dz+dy]
        polys = [((4, 3, 7, 0), fu[1], fv[0], fu[2], fv[1], (0, -1, 0)),
                 ((1, 2, 6, 5), fu[2], fv[1], fu[3], fv[0], (0, 1, 0)),
                 ((7, 3, 6, 2), fu[0], fv[1], fu[1], fv[2], (-1, 0, 0)),
                 ((0, 7, 2, 1), fu[1], fv[1], fu[2], fv[2], (0, 0, -1)),
                 ((4, 0, 1, 5), fu[2], fv[1], fu[4], fv[2], (1, 0, 0)),
                 ((3, 4, 5, 6), fu[4], fv[1], fu[5], fv[2], (0, 0, 1))]
        for ids, u1, v1, u2, v2, normal in polys:
            if abs(u2-u1) < 0.5 or abs(v2-v1) < 0.5:
                continue
            pts = np.array([V[i] for i in ids], float)
            n = world[:3, :3] @ np.array(normal, float)
            n = n/max(np.linalg.norm(n), 1e-9)
            if np.dot(n, self.camera) < -.001:
                continue
            uv = np.array([[u2, v1], [u1, v1], [u1, v2], [u2, v2]], float)
            uv[:, 0] = np.clip(uv[:, 0], 0, skin.shape[1]-0.01)
            uv[:, 1] = np.clip(uv[:, 1], 0, skin.shape[0]-0.01)
            lighting = .76+.24*max(0, float(np.dot(n, np.array([-.35, .8, -.48]))))
            self.quad(pts, world, uv, skin, 'book', lighting)

    def book(self, openness, right_flip, left_flip, time=0.0):
        self._canvas(BOOK_SIZE, BOOK_SIZE)
        skin = self._skin('enchanting_table_book')
        f = (math.sin(time*0.02)*0.1+1.25)*openness
        sf = math.sin(f)
        parts = [  # name, tex, origin, size, offset, (xRot, yRot, zRot)
            ((0, 0), (-6, -5, -0.005), (6, 10, 0.005), (0, 0, -1), (0, math.pi+f, 0)),
            ((16, 0), (0, -5, -0.005), (6, 10, 0.005), (0, 0, 1), (0, -f, 0)),
            ((12, 0), (-1, -5, 0), (2, 10, 0.005), (0, 0, 0), (0, math.pi/2, 0)),
            ((0, 10), (0, -4, -0.99), (5, 8, 1), (sf, 0, 0), (0, f, 0)),
            ((12, 10), (0, -4, -0.01), (5, 8, 1), (sf, 0, 0), (0, -f, 0)),
            ((24, 10), (0, -4, 0), (5, 8, 0.005), (sf, 0, 0), (0, f-f*2*right_flip, 0)),
            ((24, 10), (0, -4, 0), (5, 8, 0.005), (sf, 0, 0), (0, f-f*2*left_flip, 0)),
        ]
        # EnchantTableRenderer: translate to the book point, face the viewer, tilt 80 degrees on Z.
        base = ry(-self.facing) @ rz(math.radians(80))
        # The book point lands on BOOK_CENTER; the in-game node sits BOOK_HEIGHT above the base.
        for tex, origin, size, offset, rot in parts:
            local = np.eye(4)
            local[:3, :3] = rz(rot[2]) @ ry(rot[1]) @ rx(rot[0])
            local[:3, 3] = offset
            world = np.eye(4)
            world[:3, :3] = base
            world = world @ local
            self.java_cube(origin, size, tex, world, skin)
        return Image.fromarray(self.rgba)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--textures', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--facing', type=float, default=-60.0, help='book facing in degrees (EnchantTableRenderer Y rotation)')
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    baker = TableBaker(args.textures, math.radians(args.facing))
    report = {}

    def save(img, name):
        path = args.output/name
        img.save(path, optimize=True)
        report[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    save(baker.block(), 'table_block.png')
    for i in range(OPEN_FRAMES):
        save(baker.book(i/(OPEN_FRAMES-1), 0.0, 0.0), 'book_open_%d.png' % i)
    for i in range(FLIP_FRAMES):
        flip = i/FLIP_FRAMES
        right = min(max((flip+0.25) % 1.0*1.6-0.3, 0.0), 1.0)
        left = min(max((flip+0.75) % 1.0*1.6-0.3, 0.0), 1.0)
        save(baker.book(1.0, right, left), 'book_flip_%d.png' % i)
    facing = baker.facing
    for i in range(SPIN_FRAMES):
        baker.facing = facing + math.tau*i/SPIN_FRAMES
        save(baker.book(0.0, 0.0, 0.0), 'book_spin_%d.png' % i)
    baker.facing = facing
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
