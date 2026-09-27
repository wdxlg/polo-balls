"""Bounded one-shot runner. Does not touch the user's existing Godot processes."""
import argparse,subprocess,os,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--gpu',action='store_true');p.add_argument('--engine',default='E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe');p.add_argument('--script',default='res://tests/test_wither_skeleton.gd');args=p.parse_args()
root=Path(__file__).resolve().parents[1]
cmd=[args.engine,'--path',str(root),'--audio-driver','Dummy','--script',args.script]
if not args.gpu:cmd.insert(1,'--headless')
else:cmd.extend(['--rendering-method','gl_compatibility','--resolution','800x600','--position','100,100'])
result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90,cwd=root)
log=root/('.backups/wither_skeleton_20260927/'+('gpu' if args.gpu else 'headless')+'.log');log.parent.mkdir(parents=True,exist_ok=True);log.write_bytes(result.stdout)
text=result.stdout.decode('utf-8',errors='replace')
# Keep full logs; report focused output without thousands of old UID warnings.
lines=text.splitlines();selected=[]
for i,line in enumerate(lines):
 if any(k in line for k in ['SCRIPT ERROR','Parse Error','Compile Error','WITHER_SKELETON','ERROR:','at: GDScript']):selected.extend(lines[max(0,i-1):min(len(lines),i+5)])
print('\n'.join(selected)[:18000]);print('ENGINE_EXIT',result.returncode,'LOG',log)
sys.exit(result.returncode if result.returncode in range(256) else 1)
