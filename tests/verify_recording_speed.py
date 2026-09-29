"""Measure actual encoded physics-driven flashes, not merely FPS/container lengths."""
import array, json, math, os, statistics, subprocess
from pathlib import Path
from recording_filename_check import filename_matches_title
root=Path(os.environ['APPDATA'])/'Godot/app_userdata/polo_balls/recordings/speed_test'
m=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
ffmpeg='C:/ffmpeg/bin/ffmpeg.exe';ffprobe='C:/ffmpeg/bin/ffprobe.exe'
checks=0;results=[]
def check(ok,label):
 global checks
 checks+=1
 if not ok: raise AssertionError(label)
 print('PASS:',label)
log=Path(os.environ.get('BATTLE_RECORD_GPU_LOG','tests/record_speed_gpu.log')).read_text(encoding='utf-8')
check(m['failures']==0 and f"RECORDING_SPEED: {m['checks']} checks / 0 failures" in log and 'SCRIPT ERROR' not in log,'latest physics-speed GPU run passes')
for run in m['runs']:
 paths=run['outputs']; audios={};flashes={};titles={}
 for lang,path in paths.items():
  info=json.loads(subprocess.check_output([ffprobe,'-v','error','-count_frames','-show_streams','-show_format','-of','json',path]))
  titles[lang]=info.get('format',{}).get('tags',{}).get('title','')
  v=next(s for s in info['streams'] if s['codec_type']=='video');a=next(s for s in info['streams'] if s['codec_type']=='audio')
  check((v['width'],v['height'],v['avg_frame_rate'],int(v['nb_read_frames']))==(1080,1920,'60/1',run['frames']),run['kind']+' '+lang+' all full-HD frames present')
  check(abs(float(v['duration'])-float(a['duration']))<.025,run['kind']+' '+lang+' audio/video duration agreement')
  probe=subprocess.run([ffmpeg,'-v','error','-i',path,'-f','null','-'],capture_output=True)
  check(probe.returncode==0 and not probe.stderr,run['kind']+' '+lang+' complete decode')
  pixels=subprocess.check_output([ffmpeg,'-v','error','-i',path,'-vf','crop=2:2:540:960,scale=1:1:flags=area','-pix_fmt','rgb24','-f','rawvideo','-'])
  edges=[];was=False
  for n,(r,g,b) in enumerate(zip(pixels[::3],pixels[1::3],pixels[2::3])):
   state=min(r,g,b)>230
   if state and not was and n/60 > run['pulse_video_start']+.25: edges.append(n/60)
   was=state
  intervals=[b-a for a,b in zip(edges,edges[1:])]
  check(len(intervals)>=2 and max(abs(i-.5) for i in intervals)<.085,run['kind']+' '+lang+' 0.5 physics-second flashes play every 0.5 VIDEO second')
  offsets=[e-(run['pulse_video_start']+p) for e,p in zip(edges,run['pulses'])]
  check(offsets and max(abs(x) for x in offsets)<.12,run['kind']+' '+lang+' encoded action follows measured physical progress')
  flashes[lang]=edges
  audios[lang]=subprocess.check_output([ffmpeg,'-v','error','-i',path,'-map','0:a:0','-ac','1','-ar','48000','-f','f32le','-'])
 check(audios['zh']==audios['en'],run['kind']+' language versions contain identical audio')
 check(flashes['zh']==flashes['en'],run['kind']+' language versions show identical action timing')
 data=array.array('f',audios['zh']);data=data[12000:36000]
 def power(f):
  co=si=0.
  for j,x in enumerate(data):
   w=.5-.5*math.cos(2*math.pi*j/(len(data)-1));phase=2*math.pi*f*j/48000
   co+=x*w*math.cos(phase);si+=x*w*math.sin(phase)
  return math.hypot(co,si)
 check(power(440)>10*max(power(110),power(1760),1e-6),run['kind']+' normal 440 Hz pitch, not quarter-speed or quadruple-speed audio')
 check(all(filename_matches_title(paths[lang],lang,titles[lang]) for lang in ['zh','en']),run['kind']+' localized filenames match full title metadata')
 results.append({'mode':run['kind'],'codec':run['codec'],'physics_per_wall_second':run['physics']/run['wall'],'physics_per_video_second':run['physics']/run['video'],'flash_times':flashes['zh'],'flash_intervals':[b-a for a,b in zip(flashes['zh'],flashes['zh'][1:])],'peak_queue_bytes_per_language':run['peak_bytes'],'audio_identical':True})
result={'checks':checks,'failures':0,'gpu_checks':m['checks'],'runs':results}
Path(os.environ.get('BATTLE_RECORD_MEDIA_REPORT','tests/recording_speed_validation.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result));print(f'RECORDING_SPEED_MEDIA: {checks} checks / 0 failures')
