#!/usr/bin/env python3
"""Bake independent-leg layer data for every walking Minecraft mob.

usage: python bake_leg_layers.py --output <dir> [--only enderman,evoker] [--verify]

For every set it renders, with the original baker and the original clip timing:
  * legs-only frames for every walk phase (+ rest legs from the idle pose)
  * upper-body-only frames for each upper-body action clip
and writes ``<set>.gd`` (atlas + rect tables) consumed by mc_legs.gd.
"""
import argparse, sys, json
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
TRAINING = HERE.parent
REPO = TRAINING.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(TRAINING / 'mc_native_assets'))
from leg_layers import LayerSet, split_render, over


def clip_times(count, duration, loop):
    return [(i / (count - 1) if (not loop and count > 1) else i / count) * duration for i in range(count)]


HUMANOID_LEGS = ('leftLeg', 'rightLeg')


def bake_generic(key, baker, bones, leg_names, trunk_names, walk_render, walk_times, rest_render, uppers):
    """walk_render(t) / rest_render() / uppers = {clip: [render_callable per frame]}"""
    ls = LayerSet(key, 160, 224)
    phases = []; walk_full = []
    for t in walk_times:
        r = split_render(baker, bones, leg_names, lambda t=t: walk_render(t), trunk_names)
        phases.append(r['legs']); walk_full.append((r['upper'], r['upper_trunk'], r['full']))
    ls.w, ls.h = walk_full[0][2].shape[1], walk_full[0][2].shape[0]
    rest = split_render(baker, bones, leg_names, rest_render, trunk_names)
    ls.add_walk(phases, rest['legs'][0])
    for clip, calls in uppers.items():
        frames = []
        for call in calls:
            r = split_render(baker, bones, leg_names, call, trunk_names)
            frames.append((r['upper'][0], r['upper'][1], 0, r['upper_trunk']))
        ls.add_upper(clip, frames)
    ls.add_upper('__walk', [(u[0], u[1], 0, m) for u, m, _ in walk_full])
    ls.walk_full = [f for _, _, f in walk_full]
    return ls


def bake_native_mobs_set(role, upper_clips):
    import bake_native_mobs as nm
    b = nm.Baker(nm.ROOT / 'resource_pack')
    clips = nm.CLIPS[role]
    uppers = {c: [lambda t=t, c=c: b.render(role, c, t) for t in clip_times(*clips[c])] for c in upper_clips}
    return bake_generic(role, b, b.models[role], HUMANOID_LEGS, ('body',),
                        lambda t: b.render(role, 'walk', t), clip_times(*clips['walk']),
                        lambda: b.render(role, 'idle', 0), uppers)


def mc16_times(count, duration, loop):
    return [(i / count if loop else i / max(count - 1, 1)) * duration for i in range(count)]


def bake_spider():
    import bake_spider_drowned as sd
    b = sd.MC16Baker(); clips = sd.CLIPS['spider']
    legs = tuple(f'leg{i}' for i in range(8))
    uppers = {'cast': [lambda t=t: b.render('spider', 'cast', t) for t in mc16_times(*clips['cast'])]}
    return bake_generic('spider', b, b.models['spider'], legs, ('body0', 'body1'),
                        lambda t: b.render('spider', 'walk', t), mc16_times(*clips['walk']),
                        lambda: b.render('spider', 'idle', 0), uppers)


def bake_drowned():
    import os
    cwd = os.getcwd(); os.chdir(str(TRAINING / 'mc_native_assets'))
    try:
        import bake_catch_recoil as cr          # module-level: solves the catch peak pose
    finally:
        os.chdir(cwd)
    import bake_spider_drowned as sd
    b = cr.b                                     # Catch(Layers) with .peak solved
    b.mode = 'body'                              # runtime shows trident-free body frames
    clips = sd.CLIPS['drowned']
    uppers = {}
    for c in ('splash', 'throw', 'windup', 'throw_empty'):
        uppers[c] = [lambda t=t, c=c: b.render('drowned', c, t) for t in mc16_times(*clips[c])]
    catch = [lambda t=t: b.render('drowned', 'catch', t) for t in [i / 18 * .36 for i in range(19)]]
    uppers['catch'] = catch; uppers['catch_empty'] = catch
    return bake_generic('drowned', b, b.models['drowned'], HUMANOID_LEGS, ('body', 'jacket', 'waist'),
                        lambda t: b.render('drowned', 'walk', t), mc16_times(*clips['walk']),
                        lambda: b.render('drowned', 'idle', 0), uppers)


def bake_batch2_set(role, legs, trunk, upper_clips):
    import bake_native_batch2 as b2
    b = b2.BatchBaker(); clips = b2.CLIPS[role]
    uppers = {c: [lambda t=t, c=c: b.render(role, c, t) for t in mc16_times(*clips[c])] for c in upper_clips}
    return bake_generic(role, b, b.models[role], legs, trunk,
                        lambda t: b.render(role, 'walk', t), mc16_times(*clips['walk']),
                        lambda: b.render(role, 'idle', 0), uppers)


CREEPER_SWELL = {False: [0.0, 0.72, 0.86, 0.95, 1.0], True: [0.0, 0.86, 1.0]}  # charged shell is ~5x heavier


def bake_creeper():
    """Swelling scales the whole body (legs included): leg variants per swell level x charged."""
    import bake_native_batch2 as b2

    class Mix(b2.BatchBaker):
        mix = None   # (fuse progress, leg time)
        def pose(self, role, state, t, peek=0):
            if role != 'creeper' or self.mix is None: return super().pose(role, state, t, peek)
            progress, leg_t = self.mix
            legs = super().pose(role, 'walk', leg_t, peek)
            swell = super().pose(role, 'fuse', progress, peek)
            legs['body']['scale'] = swell['body']['scale'].copy()
            return legs

    b = Mix(); clips = b2.CLIPS['creeper']; bones = b.models['creeper']
    legs = tuple(f'leg{i}' for i in range(4)); trunk = ('body',)
    walk_t = mc16_times(*clips['walk'])
    ls = bake_generic('creeper', b, bones, legs, trunk, lambda t: b.render('creeper', 'walk', t), walk_t,
                      lambda: b.render('creeper', 'idle', 0), {})
    variants = []
    for charged in (False, True):
        for level in CREEPER_SWELL[charged]:
            phases = []
            for t in walk_t:
                b.mix = (level, t)
                r = split_render(b, bones, legs, lambda t=t: b.render('creeper', 'fuse_walk_charged' if charged else 'fuse_walk', t), trunk)
                phases.append(r['legs'])
            b.mix = None
            variants.append(phases)
    ls.legs = variants; ls.rest = [ls.rest[0]] * len(variants)
    def nearest(progress, charged):
        scale = lambda p: p ** 4 * .4 + 1
        levels = CREEPER_SWELL[charged]
        base = len(CREEPER_SWELL[False]) if charged else 0
        return base + min(range(len(levels)), key=lambda i: abs(scale(levels[i]) - scale(progress)))
    for charged in (False, True):
        clip = 'fuse_charged' if charged else 'fuse'
        count, duration, loop = clips[clip]
        frames = []
        for t in mc16_times(count, duration, loop):
            r = split_render(b, bones, legs, lambda t=t: b.render('creeper', clip, t), trunk)
            frames.append((r['upper'][0], r['upper'][1], nearest(min(max(t / duration, 0), 1), charged), r['upper_trunk']))
        ls.add_upper(clip, frames)
    return ls


def _pair_module():
    """golem_pair/bake_pair.py bakes + downloads at import; load only its PairBaker class."""
    import os
    path = TRAINING / 'golem_pair' / 'bake_pair.py'
    src = path.read_text(encoding='utf8')
    ns = {'__file__': str(path), '__name__': 'bake_pair_classes'}
    exec(compile(src[:src.index("b=PairBaker();folder=")], str(path), 'exec'), ns)
    return ns


GOLEM_CROUCH = [i / 7 for i in range(8)]  # one exact crouch level per baked charge frame (f = i/7)


def bake_golem(stage):
    """Iron golem crack stage `stage`. Variant 0 = baked walk legs (body sway, verify only);
    variants 1.. = walk leg swing on an un-swayed body at charge crouch levels (swing uses level 0)."""
    import math
    from PIL import Image
    ns = _pair_module(); n = ns['n']; SRC = ns['SRC']

    class Mix(ns['PairBaker']):
        mix = None   # (state, action t, leg t)
        def pose(self, role, state, t, peek=0):
            if self.mix is None: return super().pose(role, state, t, peek)
            st, at, lt = self.mix
            p = super().pose(role, st, at, peek)
            v = math.cos(lt * math.tau) * 6
            p['leg0']['rotation'][0] = v * 6; p['leg1']['rotation'][0] = -v * 6
            return p

    b = Mix()
    n.W, n.H = 448, 384; b.foot['golem'] = 275
    skin = Image.fromarray(b.skins['golem'])
    if stage:
        skin = Image.alpha_composite(skin, Image.open(SRC / f'textures/entity/iron_golem/cracked_{["", "low", "medium", "high"][stage]}.png').convert('RGBA'))
    b.skins['golem'] = np.array(skin)
    bones = b.models['golem']; legs = ('leg0', 'leg1'); trunk = ('body',)
    walk_t = mc16_times(16, 1, True)
    ls = bake_generic(f'golem_{stage}', b, bones, legs, trunk, lambda t: b.render('golem', 'walk', t), walk_t,
                      lambda: b.render('golem', 'idle', 0), {})
    for level in GOLEM_CROUCH:
        phases = []
        for t in walk_t:
            b.mix = ('charge', level * .38, t)
            phases.append(split_render(b, bones, legs, lambda: b.render('golem', 'charge', 0), trunk)['legs'])
        b.mix = None
        ls.legs.append(phases); ls.rest.append(ls.rest[0])
    for clip, (count, duration, loop) in {'charge': (8, .38, False), 'swing': (24, .48, False)}.items():
        frames = []
        for t in mc16_times(count, duration, loop):
            r = split_render(b, bones, legs, lambda t=t: b.render('golem', clip, t), trunk)
            level = 0 if clip == 'swing' else min(range(len(GOLEM_CROUCH)), key=lambda i: abs(GOLEM_CROUCH[i] - t / .38))
            frames.append((r['upper'][0], r['upper'][1], 1 + level, r['upper_trunk']))
        ls.add_upper(clip, frames)
    return ls


def bake_villager():
    """Golem-pair toolsmith villager: walking legs under the iron-ingot throw."""
    import math
    from PIL import Image
    ns = _pair_module(); n = ns['n']; SRC = ns['SRC']
    b = ns['PairBaker']()
    n.W, n.H = 160, 224; b.foot['villager'] = 195
    ingot = Image.open(SRC / 'textures/items/iron_ingot.png').convert('RGBA').resize((30, 30), Image.Resampling.NEAREST)
    def throw(t):
        im = b.render('villager', 'throw', t)
        mode = b.__dict__['cube'].__kwdefaults__.get('_m') if 'cube' in b.__dict__ else None
        if mode in (None, 'upper'):
            # ingot is pasted after the 3D render: upper layer only, in front of everything
            y = 123 - int(7 * math.sin(t / .36 * math.pi))
            im.alpha_composite(ingot, (51, y))
            mask = np.zeros(np.array(b.depth).shape, bool)
            a = np.array(ingot)[..., 3] > 0
            mask[y:y + 30, 51:81] = a[:max(0, min(30, mask.shape[0] - y)), :]
            b.depth = np.where(mask, 1e9, b.depth)
        return im
    uppers = {'throw': [lambda t=t: throw(t) for t in mc16_times(10, .36, False)]}
    return bake_generic('villager', b, b.models['villager'], ('leg0', 'leg1'), ('body',),
                        lambda t: b.render('villager', 'walk', t), mc16_times(16, 1, True),
                        lambda: b.render('villager', 'idle', 0), uppers)


def _frontier_module():
    """mc_frontier_assets/build_assets.py downloads + bakes at import: exec only the Warden rig."""
    path = TRAINING / 'mc_frontier_assets' / 'build_assets.py'
    src = path.read_text(encoding='utf8')
    head = ("from pathlib import Path\nimport copy, importlib.util, json, math\nimport numpy as np\nfrom PIL import Image\n"
            "B = Path(__file__).resolve().parent\nsource = B / 'resource_pack'\n"
            "spec = importlib.util.spec_from_file_location('frontier_native_rasterizer', B.parent/'mc_native_assets/bake_native_mobs.py')\n"
            "m = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(m)\n")
    body = src[src.index("def vector("):src.index("\nm.W, m.H = 192,240")]
    ns = {'__file__': str(path), '__name__': 'frontier_warden_rig'}
    exec(compile(head + body, str(path), 'exec'), ns)
    return ns


def bake_warden():
    """Warden legs hang from `root` (not `body`); attack / sonic_boom never move them,
    so the plain walk legs are exact under both actions."""
    ns = _frontier_module(); m = ns['m']
    m.W, m.H = 192, 240
    b = ns['WardenBaker']()
    clips = {'attack': (10, .33333, False), 'sonic': (24, 3.0, False)}
    uppers = {c: [lambda t=t, c=c: b.render('warden', c, t) for t in mc16_times(*v)] for c, v in clips.items()}
    ls = bake_generic('warden', b, b.models['warden'], ('left_leg', 'right_leg'), ('body',),
                      lambda t: b.render('warden', 'walk', t), mc16_times(16, 1.0, True),
                      lambda: b.render('warden', 'idle', 0), uppers)
    ls.neutral_tolerance = 48   # phase 4 differs from idle only by body-sway hip shading (32 px)
    return ls


def bake_trader():
    """Wandering trader (villager_v2 rig): walking legs under the looping potion/milk drink."""
    import bake_wandering_trader as wt
    b = wt.Baker(wt.ROOT / 'resource_pack_trader'); clips = wt.CLIPS['trader']
    uppers = {'drink': [lambda t=t: b.render('trader', 'drink', t, 'trader') for t in mc16_times(*clips['drink'])]}
    return bake_generic('trader', b, b.models['trader'], ('leg0', 'leg1'), ('body',),
                        lambda t: b.render('trader', 'walk', t, 'trader'), mc16_times(*clips['walk']),
                        lambda: b.render('trader', 'idle', 0, 'trader'), uppers)


def bake_llama(skin):
    """Trader llama. Variant 0 = walk-amplitude legs, variant 1 = run-amplitude legs (same 24-phase
    gait; the runtime picks 1 while the run clip would play). Spit composites over either."""
    import math
    import bake_wandering_trader as wt

    class Mix(wt.Baker):
        weight = None
        def pose(self, role, state, t):
            p = super().pose(role, state, t)
            if self.weight is not None:
                c = math.cos(math.radians(t * 360 / 38.17 * 38.17))
                for leg, sign in (('leg0', 1), ('leg1', -1), ('leg2', -1), ('leg3', 1)):
                    p[leg]['rotation'][0] = c * 80.0 * sign * self.weight
            return p

    b = Mix(wt.ROOT / 'resource_pack_trader'); clips = wt.CLIPS['llama']
    bones = b.models['llama']; legs = tuple(f'leg{i}' for i in range(4)); trunk = ('body',)
    walk_t = mc16_times(*clips['walk'])
    uppers = {'spit': [lambda t=t: b.render('llama', 'spit', t, skin) for t in mc16_times(*clips['spit'])]}
    ls = bake_generic(skin, b, bones, legs, trunk, lambda t: b.render('llama', 'walk', t, skin), walk_t,
                      lambda: b.render('llama', 'idle', 0, skin), uppers)
    phases = []
    for t in walk_t:
        b.weight = 0.75
        phases.append(split_render(b, bones, legs, lambda t=t: b.render('llama', 'walk', t, skin), trunk)['legs'])
    b.weight = None
    ls.legs.append(phases); ls.rest.append(ls.rest[0])
    return ls


def _wither_baker():
    """tools/build_wither_skeleton_assets.py builds its rig inside bake(): exec only that set-up."""
    import importlib.util
    path = REPO / 'tools' / 'build_wither_skeleton_assets.py'
    spec = importlib.util.spec_from_file_location('wither_skeleton_assets', path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    src = path.read_text(encoding='utf8')
    body = src[src.index('def bake():'):src.index(' files=[];clips=[]')].replace('def bake():', 'def _rig():', 1) + ' return b\n'
    exec(compile(body, str(path), 'exec'), mod.__dict__)
    b = mod.__dict__['_rig']()
    # BatchBaker later gained the plain skeleton's held bow; the wither art never had one.
    b.bows = {k: np.zeros_like(v) for k, v in b.bows.items()}
    return b


def bake_wither_skeleton():
    """Wither skeleton: the combo shows the arm-less attack body + a separately aimed sword arm,
    and the attack pose keeps the legs still, so walking legs go under the arm-less attack body."""
    import copy
    b = _wither_baker()
    full = b.models['skeleton']
    ls = bake_generic('wither_skeleton', b, full, HUMANOID_LEGS, ('body', 'waist'),
                      lambda t: b.render('skeleton', 'walk', t), mc16_times(16, 1.0, True),
                      lambda: b.render('skeleton', 'idle', 0), {})
    armless = copy.deepcopy(full)
    for bone in armless:
        if bone['name'].lower() == 'rightarm': bone['cubes'] = []
    b.models['skeleton'] = armless
    frames = []
    for t in mc16_times(50, .98, False):
        r = split_render(b, armless, HUMANOID_LEGS, lambda t=t: b.render('skeleton', 'attack', t), ('body', 'waist'))
        frames.append((r['upper'][0], r['upper'][1], 0, r['upper_trunk']))
    b.models['skeleton'] = full
    ls.add_upper('attack', frames)
    return ls


SETS = {
    'enderman': lambda: bake_native_mobs_set('enderman', ['attack', 'angry_attack']),
    'evoker': lambda: bake_native_mobs_set('evoker', ['cast', 'celebrate']),
    'spider': bake_spider,
    'drowned': bake_drowned,
    'witch': lambda: bake_batch2_set('witch', ('leg0', 'leg1'), ('body',), ['hold', 'drink']),
    'skeleton': lambda: bake_batch2_set('skeleton', HUMANOID_LEGS, ('body', 'waist'), ['shoot']),
    'creeper': bake_creeper,
    'golem_0': lambda: bake_golem(0),
    'golem_1': lambda: bake_golem(1),
    'golem_2': lambda: bake_golem(2),
    'golem_3': lambda: bake_golem(3),
    'villager': bake_villager,
    'warden': bake_warden,
    'trader': bake_trader,
    'llama_creamy': lambda: bake_llama('llama_creamy'),
    'llama_brown': lambda: bake_llama('llama_brown'),
    'wither_skeleton': bake_wither_skeleton,
}

COMMENTS = {
    'enderman': 'Enderman: walking legs under attack / angry_attack upper body.',
    'evoker': 'Evoker: walking legs under cast / celebrate upper body.',
    'spider': 'Spider: walking legs under the web-cast head/body. attack/lunge/land keep their own leg motion.',
    'drowned': 'Drowned (trident-free body layer): walking legs under splash / throw / windup / catch.',
    'witch': 'Witch: walking legs under hold / drink upper body.',
    'skeleton': 'Skeleton: walking legs under the bow shoot upper body.',
    'creeper': 'Creeper: fuse upper body + swollen walking legs; variants 0-4 plain swell levels, 5-7 charged.',
    'golem_0': 'Iron golem (intact): charge / swing upper body over un-swayed walking legs (variants 1-8 = crouch, per charge frame).',
    'golem_1': 'Iron golem (cracked low): charge / swing upper body over un-swayed walking legs (variants 1-8 = crouch, per charge frame).',
    'golem_2': 'Iron golem (cracked medium): charge / swing upper body over un-swayed walking legs (variants 1-8 = crouch, per charge frame).',
    'golem_3': 'Iron golem (cracked high): charge / swing upper body over un-swayed walking legs (variants 1-8 = crouch, per charge frame).',
    'villager': 'Golem-pair villager: walking legs under the iron-ingot throw.',
    'warden': 'Warden: walking legs under the melee attack / sonic boom upper body.',
    'trader': 'Wandering trader: walking legs under the looping drink upper body.',
    'llama_creamy': 'Trader llama (creamy): spit over walking legs; variant 0 walk amplitude, 1 run amplitude.',
    'llama_brown': 'Trader llama (brown): spit over walking legs; variant 0 walk amplitude, 1 run amplitude.',
    'wither_skeleton': 'Wither skeleton: walking legs under the arm-less attack body (the sword arm stays a separate aimed sprite).',
}


def verify(ls):
    worst = 0
    for i, full in enumerate(ls.walk_full):
        comp = ls.compose('__walk', i, i)
        diff = np.abs(comp.astype(int) - full.astype(int)).max(-1)
        worst = max(worst, int((diff > 8).sum()))
    return worst


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--only', default=''); ap.add_argument('--verify', action='store_true')
    a = ap.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
    only = [s for s in a.only.split(',') if s] or list(SETS)
    report = {}
    for key in only:
        ls = SETS[key]()
        ls.find_neutral()
        ls.build(); bad = verify(ls)
        del ls.upper['__walk']
        ls.build()
        text, png_bytes = ls.gdscript(COMMENTS[key])
        (a.output / f'{key}.gd').write_text(text, encoding='utf-8')
        report[key] = {'neutral': ls.neutral, 'walk': len(ls.legs[0]), 'verify_bad_px': bad,
                       'png_bytes': png_bytes, 'atlas': list(ls.atlas.shape[:2]),
                       'clips': {c: len(v) for c, v in ls.upper.items()}}
        print(key, json.dumps(report[key]), flush=True)


if __name__ == '__main__':
    main()
