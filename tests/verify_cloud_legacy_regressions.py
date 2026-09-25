"""Run existing graphics assertions with clouds off (legacy visual baseline).
Only the temporary harness is adapted: stop unrelated background resource warming
before its deferred start, and use force_draw instead of the old frame_post_draw
wait (which can stall in the offline runtime). Original test files are untouched.
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
engine = root.parent / 'polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe'
remove_cloud = '--remove-cloud-node' in sys.argv
names = [a for a in sys.argv[1:] if a != '--remove-cloud-node'] or ['test_day_night_cycle', 'test_day_night_visual', 'test_map_wall_tooltips']
for name in names:
    assert name in ['test_day_night_cycle', 'test_day_night_visual', 'test_map_wall_tooltips']
    source = (root / 'tests' / (name + '.gd')).read_text(encoding='utf8')
    anchor = '\troot.add_child(world)'
    assert source.count(anchor) == 1
    source = source.replace(anchor, '\tgame.Game_Settings.Minecraft_Clouds = false\n' + anchor + '\n\tif is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()')
    if remove_cloud:
        source = source.replace(anchor, anchor + '\n\tworld.minecraft_clouds.free()\n\tworld.minecraft_clouds = null')
    source = source.replace('\tawait RenderingServer.frame_post_draw', '\tRenderingServer.force_draw(false)')
    temp = root / 'tests' / ('_cloud_harness_' + name + '.gd')
    assert not temp.exists()
    log = root / 'tests' / (name + ('_cloud_removed_harness.log' if remove_cloud else '_cloud_harness.log'))
    try:
        temp.write_text(source, encoding='utf8')
        args = [str(engine), '--path', str(root), '--script', 'res://tests/' + temp.name]
        args += ['--headless'] if name == 'test_day_night_cycle' else ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
        with log.open('wb') as output:
            result = subprocess.run(args, stdout=output, stderr=subprocess.STDOUT, timeout=100)
        print(name, 'EXIT', result.returncode, flush=True)
        text = log.read_text(encoding='utf8', errors='replace')
        for line in text.splitlines():
            if any(key in line for key in ['ERROR', 'FAIL', 'checks', 'RESULT', 'ObjectDB', 'DAY_NIGHT_PIXEL', 'OpenGL']):
                print(line[:800], flush=True)
    finally:
        temp.unlink(missing_ok=True)
        temp.with_suffix('.gd.uid').unlink(missing_ok=True)
