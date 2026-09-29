"""Decode physics beacons and native offline PCM; a 40ms/step load must not slow the film."""
import array,json,math,os,subprocess
from pathlib import Path
from recording_filename_check import filename_matches_title
root=Path(os.environ['APPDATA'])/'Godot/app_userdata/polo_balls/recordings/offline_test'
m=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
ffmpeg='C:/ffmpeg/bin/ffmpeg.exe';ffprobe='C:/ffmpeg/bin/ffprobe.exe';checks=0;results=[]
def check(ok,label):
 global checks
 checks+=1
 if not ok:raise AssertionError(label)
 print('PASS:',label)
log=Path(os.environ.get('BATTLE_RECORD_GPU_LOG','tests/record_offline_gpu.log')).read_text(encoding='utf-8')
check(m['failures']==0 and f"RECORDING_OFFLINE: {m['checks']} checks / 0 failures" in log and 'SCRIPT ERROR' not in log,'latest offline GPU tests pass')
for run in m['runs']:
 audio={};flashes={};titles={}
 for lang,path in run['outputs'].items():
  info=json.loads(subprocess.check_output([ffprobe,'-v','error','-count_frames','-show_streams','-show_format','-of','json',path]));streams=info['streams']
  titles[lang]=info.get('format',{}).get('tags',{}).get('title','')
  v=next(x for x in streams if x['codec_type']=='video');a=next(x for x in streams if x['codec_type']=='audio')
  check((v['width'],v['height'],v['avg_frame_rate'],int(v['nb_read_frames']))==(1080,1920,'60/1',run['frames']),f'{run["delay_ms"]}ms {lang} all full-HD frames encoded')
  check(abs(float(v['duration'])-run['video'])<.001,'container duration equals fixed game-frame count, not wall time')
  check(abs(float(a['duration'])-float(v['duration']))<.025,'audio and video duration match')
  check(run['audio_samples']==round(run['frames']*run['sample_rate']/60),'native mixer emits exactly one video-frame worth of samples per step')
  result=subprocess.run([ffmpeg,'-v','error','-i',path,'-f','null','-'],capture_output=True)
  check(result.returncode==0 and not result.stderr,'complete file decode without errors')
  pixels=subprocess.check_output([ffmpeg,'-v','error','-i',path,'-vf','crop=2:2:540:960,scale=1:1:flags=area','-pix_fmt','rgb24','-f','rawvideo','-'])
  edges=[];old=False
  for i,(r,g,b) in enumerate(zip(pixels[::3],pixels[1::3],pixels[2::3])):
   state=min(r,g,b)>230
   if state and not old:edges.append(i/60)
   old=state
  intervals=[b-a for a,b in zip(edges,edges[1:])]
  check(len(intervals)>=2 and max(abs(x-.5) for x in intervals)<.04,'0.5 game-second flashes remain 0.5 seconds apart in exported video')
  check(abs(edges[0]-.5)<.04,'first flash starts from the clicked current state, not a pre-roll/rematch')
  flashes[lang]=edges
  audio[lang]=subprocess.check_output([ffmpeg,'-v','error','-i',path,'-map','0:a:0','-ac','1','-ar','48000','-f','f32le','-'])
 check(audio['zh']==audio['en'],'language versions have identical PCM')
 check(flashes['zh']==flashes['en'],'language versions have identical action timing')
 data=array.array('f',audio['zh'])[12000:60000]
 def power(freq):
  co=si=0.
  for i,x in enumerate(data):
   phase=2*math.pi*freq*i/48000;w=.5-.5*math.cos(2*math.pi*i/(len(data)-1))
   co+=x*w*math.cos(phase);si+=x*w*math.sin(phase)
  return math.hypot(co,si)
 suppression=20*math.log10(max(power(440),1e-9)/max(power(1760),1e-9))
 check(suppression>35,'game tone retained; UI bus tone excluded')
 check(power(440)>10*max(power(110),power(220),1e-8),'normal pitch regardless of how fast/slow computation ran')
 full=array.array('f',audio['zh']);beeps=[];was=False
 for begin in range(0,len(full)-960,480):
  co=si=0.
  for j,x in enumerate(full[begin:begin+960]):
   phase=2*math.pi*880*j/48000;co+=x*math.cos(phase);si+=x*math.sin(phase)
  active=2*math.hypot(co,si)/960 > .055
  if active and not was:beeps.append((begin+480)/48000)
  was=active
 edges=flashes['zh'];sync=[b-f for b,f in zip(beeps,edges)]
 check(len(beeps)==len(edges) and sync and max(abs(t) for t in sync)<.045,'physics-triggered sound and flash stay synchronized in the exported file')
 paths=run['outputs'];check(all(filename_matches_title(paths[lang],lang,titles[lang]) for lang in ['zh','en']),'localized filenames match full title metadata and collision numbering')
 results.append({'delay_ms':run['delay_ms'],'wall_seconds':run['wall'],'video_seconds':run['video'],'physics_seconds':run['physics'],'frames':run['frames'],'flash_times':flashes['zh'],'ui_rejection_db':suppression,'audio_samples':run['audio_samples'],'audio_identical':True,'beep_times':beeps,'sync_offsets_seconds':sync})
check(results[1]['wall_seconds']>2*results[1]['video_seconds'],'slow compute demonstration verified against a real wall clock')
report={'checks':checks,'failures':0,'gpu_checks':m['checks'],'runs':results}
Path(os.environ.get('BATTLE_RECORD_MEDIA_REPORT','tests/recording_offline_validation.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report));print(f'OFFLINE_MEDIA: {checks} checks / 0 failures')
