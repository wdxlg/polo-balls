"""Bounded one-shot runner for the Jujutsu Kaisen characters. Does not touch running Godot processes."""
import argparse, subprocess, sys
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('--gpu', action='store_true')
p.add_argument('--engine', default='E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe')
args = p.parse_args()
root = Path(__file__).resolve().parents[1]
script = 'res://tests/test_jjk_gpu.gd' if args.gpu else 'res://tests/test_jjk.gd'
cmd = [args.engine, '--path', str(root), '--audio-driver', 'Dummy', '--script', script]
if args.gpu: cmd.extend(['--rendering-method', 'gl_compatibility', '--resolution', '800x600', '--position', '100,100'])
else: cmd.insert(1, '--headless')
result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180, cwd=root)
log = root / ('.backups/jjk_20260928/' + ('gpu' if args.gpu else 'headless') + '.log')
log.parent.mkdir(parents=True, exist_ok=True)
log.write_bytes(result.stdout)
text = result.stdout.decode('utf-8', errors='replace')
keys = ['SCRIPT ERROR', 'Parse Error', 'Compile Error', 'JJK_FAIL', 'JJK_RESULT', 'JJK_BATTLE', 'JJK_SHOT']
print('\n'.join(l for l in text.splitlines() if any(k in l for k in keys))[:18000])
print('ENGINE_EXIT', result.returncode, 'LOG', log)
sys.exit(result.returncode if result.returncode in range(256) else 1)
