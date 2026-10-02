#!/usr/bin/env python3
"""Independent-leg layers for baked Minecraft mobs.

Every native baker draws bones through ``cube(cube, ...)`` -> ``quad(...)`` into
``self.rgba`` / ``self.depth``. ``split_render`` re-runs the *same* render call
twice, once drawing only leg-bone cubes and once drawing everything else, so the
layers are pixel-identical to the shipped full frames and carry real depth.

Runtime (scripts/effects/我的世界/mc_legs.gd) composites
``upper_back -> legs(walk phase) -> upper_front`` so an attack / cast / drink
upper body keeps walking legs whose cadence comes from real displacement.
"""
import base64, io, math
import numpy as np
from PIL import Image


def leg_bone_set(bones, names):
    names = {n.lower() for n in names}
    children = {}
    for b in bones:
        if b.get('parent'):
            children.setdefault(b['parent'].lower(), []).append(b['name'].lower())
    out = set(); stack = list(names)
    while stack:
        n = stack.pop()
        if n in out: continue
        out.add(n); stack.extend(children.get(n, []))
    return out


def split_render(baker, bones, leg_names, call, trunk_names=('body',)):
    """Render the same pose in passes.

    returns {'legs': (rgba, depth), 'upper': (rgba, depth), 'trunk_depth': depth, 'full': rgba}
    ``legs`` is already occluded by the trunk (body/robe/torso) of this very pose, so the
    phase-dependent robe-vs-leg depth order is baked in. The trunk is then always drawn
    under the legs at runtime; only free limbs (arms, items) get a front/back split.
    """
    legs = leg_bone_set(bones, leg_names)
    trunk = {n.lower() for n in trunk_names} - legs
    by_group = {'legs': legs, 'trunk': trunk}
    cubes_of = lambda names: {id(c) for b in bones if b['name'].lower() in names for c in b.get('cubes', [])}
    leg_cubes = cubes_of(legs); trunk_cubes = cubes_of(trunk)
    cls_cube = type(baker).cube; cls_quad = type(baker).quad
    out = {}
    for mode in ('legs', 'trunk', 'upper'):
        flag = {'on': False}
        def allowed(c, _m=mode):
            if _m == 'legs': return id(c) in leg_cubes
            if _m == 'trunk': return id(c) in trunk_cubes
            return id(c) not in leg_cubes
        def cube(c, *a, _m=mode, **k):
            if not allowed(c): return None
            flag['on'] = True
            try: return cls_cube(baker, c, *a, **k)
            finally: flag['on'] = False
        def quad(*a, _m=mode, **k):
            # free-floating quads (held items, bows, swords) belong to the upper body
            if _m != 'upper' and not flag['on']: return None
            return cls_quad(baker, *a, **k)
        baker.cube = cube; baker.quad = quad
        try:
            im = call()
        finally:
            del baker.cube; del baker.quad
        rgba = np.array(im.convert('RGBA')) if hasattr(im, 'convert') else np.array(baker.rgba)
        out[mode] = (rgba.copy(), np.array(baker.depth).copy())
    lr, ld = out['legs']; tr, td = out['trunk']
    hidden = (lr[..., 3] > 10) & (tr[..., 3] > 10) & (td > ld + 1e-6)
    lr = lr.copy(); lr[hidden] = 0; ld = np.where(hidden, -1e10, ld)
    out['legs'] = (lr, ld)
    # which upper pixels are trunk pixels (always drawn under the legs)
    ur, ud = out['upper']
    out['upper_trunk'] = (tr[..., 3] > 10) & (np.abs(td - ud) < 1e-4) & (ur[..., 3] > 10)
    out['full'] = np.array(call().convert('RGBA'))
    return out


def over(dst, src):
    """Straight-alpha source-over (matches Image.blend_rect for our cut-out art)."""
    sa = src[..., 3:4].astype(np.float64) / 255.0
    da = dst[..., 3:4].astype(np.float64) / 255.0
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 0, (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-9), 0)
    return np.concatenate([np.clip(np.round(rgb), 0, 255), np.clip(np.round(oa * 255), 0, 255)], -1).astype(np.uint8)


class LayerSet:
    """Collects legs / upper layers for one runtime set and emits the GDScript data file."""

    def __init__(self, key, width, height):
        self.key = key; self.w = width; self.h = height
        self.legs = []          # [variant][phase] -> (rgba, depth)
        self.rest = []          # [variant] -> rgba of legs at rest (idle)
        self.upper = {}         # clip -> [ (rgba, depth, variant) ]
        self.walk_full = []     # shipped walk frames for verification
        self.neutral = []

    def add_walk(self, phases, rest_legs, variant=0):
        while len(self.legs) <= variant: self.legs.append([]); self.rest.append(None)
        self.legs[variant] = phases; self.rest[variant] = rest_legs

    def add_upper(self, clip, frames):
        self.upper[clip] = frames

    def find_neutral(self):
        phases = self.legs[0]; rest = self.rest[0]
        diffs = []
        for rgba, _ in phases:
            a = rgba[..., 3] > 10; b = rest[..., 3] > 10
            diffs.append(int((a ^ b).sum() + (np.abs(rgba.astype(int) - rest.astype(int)).sum(-1)[a & b] > 24).sum()))
        n = len(diffs); best = min(diffs)
        cand = [i for i, d in enumerate(diffs) if d <= best + max(6, best * 0.15)
                and d <= diffs[(i - 1) % n] and d <= diffs[(i + 1) % n]]
        # collapse neighbours, keep the minimum of each run
        out = []
        for i in cand:
            if out and (i - out[-1]) % n <= 2:
                if diffs[i] < diffs[out[-1]]: out[-1] = i
            else: out.append(i)
        if len(out) > 1 and (out[0] - out[-1]) % n <= 2:
            if diffs[out[0]] > diffs[out[-1]]: out[0] = out[-1]
            out.pop()
        self.neutral = sorted(out)
        self.neutral_diffs = diffs
        return self.neutral

    def _leg_depth_stack(self):
        """[n_phases, H, W] leg depth (nan where the leg layer is empty)."""
        stack = []
        for variant in self.legs:
            for rgba, depth in variant:
                stack.append(np.where(rgba[..., 3] > 10, depth, np.nan))
        return np.stack(stack)

    def build(self):
        legs_depth = self._leg_depth_stack()
        crops = []  # (key, rgba)
        self.leg_ids = []
        for v, variant in enumerate(self.legs):
            ids = []
            for p, (rgba, _) in enumerate(variant):
                ids.append(len(crops)); crops.append(rgba)
            self.leg_ids.append(ids)
        self.upper_ids = {}
        for clip, frames in self.upper.items():
            entries = []
            for rgba, depth, variant, trunk_mask in frames:
                covered = rgba[..., 3] > 10
                # Majority vote over every walk phase that has a leg on this pixel:
                # a robe edge stays in front of legs unless legs are in front most of the time.
                with np.errstate(invalid='ignore'):
                    nearer = np.nansum(legs_depth > depth[None] + 1e-6, axis=0)
                    farther = np.nansum(legs_depth <= depth[None] + 1e-6, axis=0)
                behind = covered & ((nearer > farther) | trunk_mask)
                front = rgba.copy(); front[behind] = 0
                back = rgba.copy(); back[~behind] = 0
                f = len(crops); crops.append(front)
                b = -1
                if behind.any(): b = len(crops); crops.append(back)
                entries.append((f, b, variant))
            self.upper_ids[clip] = entries
        # dedupe identical crops (e.g. catch == catch_empty)
        import hashlib
        seen = {}; alias = {}
        for i, rgba in enumerate(crops):
            h = hashlib.sha1(rgba.tobytes()).hexdigest()
            alias[i] = seen.setdefault(h, i)
        # crop + shelf pack
        rects = []
        for rgba in crops:
            ys, xs = np.nonzero(rgba[..., 3] > 0)
            if len(xs) == 0: rects.append(None); continue
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            rects.append((x0, y0, x1 - x0, y1 - y0))
        order = sorted([i for i, r in enumerate(rects) if r and alias[i] == i], key=lambda i: -rects[i][3])
        atlas_w = 1024; x = y = shelf = 0; place = {}
        for i in order:
            _, _, w, h = rects[i]
            if x + w > atlas_w: x = 0; y += shelf + 1; shelf = 0
            place[i] = (x, y); x += w + 1; shelf = max(shelf, h)
        atlas_h = y + shelf
        atlas = np.zeros((max(atlas_h, 1), atlas_w, 4), np.uint8)
        for i, (px, py) in place.items():
            x0, y0, w, h = rects[i]
            atlas[py:py + h, px:px + w] = crops[i][y0:y0 + h, x0:x0 + w]
        used_w = max([place[i][0] + rects[i][2] for i in place] + [1])
        self.atlas = atlas[:, :used_w]
        self.rect = {}
        for i in range(len(crops)):
            j = alias[i]
            self.rect[i] = [place[j][0], place[j][1], rects[j][2], rects[j][3], int(rects[j][0]), int(rects[j][1])] if rects[j] else []
        self.crops = crops
        return self

    def compose(self, clip, index, phase, variant=None):
        f, b, v = self.upper_ids[clip][index]
        v = v if variant is None else variant
        out = np.zeros((self.h, self.w, 4), np.uint8)
        if b >= 0: out = over(out, self.crops[b])
        out = over(out, self.crops[self.leg_ids[v][phase]])
        return over(out, self.crops[f])

    def gdscript(self, comment):
        buf = io.BytesIO(); Image.fromarray(self.atlas).save(buf, format='PNG', optimize=True)
        png = base64.b64encode(buf.getvalue()).decode()
        r = lambda i: self.rect[i] if i >= 0 else []
        legs = [[r(i) for i in ids] for ids in self.leg_ids]
        upper = {c: [[r(f), r(b), v] for f, b, v in e] for c, e in self.upper_ids.items()}
        def gd(v):
            if isinstance(v, dict): return '{' + ', '.join(f'&"{k}": {gd(x)}' for k, x in v.items()) + '}'
            if isinstance(v, (list, tuple)): return '[' + ', '.join(gd(x) for x in v) + ']'
            return str(int(v)) if isinstance(v, (int, np.integer)) else repr(v)
        lines = ['extends RefCounted', '## GENERATED by scripts/training/mc_leg_layers/bake_leg_layers.py - do not edit.',
                 '## ' + comment,
                 f'const SIZE := Vector2i({self.w}, {self.h})',
                 f'const WALK := {len(self.leg_ids[0])}',
                 f'const NEUTRAL := {gd(self.neutral)}',
                 '## [variant][phase] -> [atlas_x, atlas_y, w, h, dest_x, dest_y]',
                 f'const LEGS := {gd(legs)}',
                 '## clip -> per frame [front_rect, back_rect(or []), leg_variant]',
                 f'const UPPER := {gd(upper)}',
                 f'const PNG := "{png}"', '']
        return '\n'.join(lines), len(buf.getvalue())
