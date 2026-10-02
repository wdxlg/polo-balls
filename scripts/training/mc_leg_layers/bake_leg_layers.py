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


SETS = {
    'enderman': lambda: bake_native_mobs_set('enderman', ['attack', 'angry_attack']),
    'evoker': lambda: bake_native_mobs_set('evoker', ['cast', 'celebrate']),
    'spider': bake_spider,
    'drowned': bake_drowned,
}

COMMENTS = {
    'enderman': 'Enderman: walking legs under attack / angry_attack upper body.',
    'evoker': 'Evoker: walking legs under cast / celebrate upper body.',
    'spider': 'Spider: walking legs under the web-cast head/body. attack/lunge/land keep their own leg motion.',
    'drowned': 'Drowned (trident-free body layer): walking legs under splash / throw / windup / catch.',
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
