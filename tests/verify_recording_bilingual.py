"""Verify independently decodable bilingual files, shared audio and matching action."""
import array, hashlib, json, math, os, re, subprocess
from pathlib import Path
from recording_filename_check import filename_matches_title
folder=Path(os.environ['APPDATA'])/'Godot/app_userdata/polo_balls/recordings'
m=json.loads((folder/'bilingual_test/manifest.json').read_text(encoding='utf-8'))
ffmpeg='C:/ffmpeg/bin/ffmpeg.exe';ffprobe='C:/ffmpeg/bin/ffprobe.exe'
checks=0; results=[]
def check(ok,label):
 global checks
 checks+=1
 if not ok: raise AssertionError(label)
 print('PASS:',label)
def raw(path,args):
 return subprocess.check_output([ffmpeg,'-v','error','-i',str(path),*args])
pairs=[('bilingual_live',m['outputs'],m['frames'])]
original=json.loads((folder/'test_recording_manifest.json').read_text(encoding='utf-8'))
for index,item in enumerate(original):
 check(set(item.get('outputs',{}))=={'zh','en'},'current regression manifest records explicit same-session bilingual paths; rerun GPU fixture if missing')
 pairs.append((['original_live','sim_abort','sim_finish'][index],item['outputs'],item['frames']))
check(m['failures']==0,'bilingual GPU suite passes')
log=Path(os.environ.get('BATTLE_RECORD_GPU_LOG','tests/record_bilingual_gpu.log')).read_text(encoding='utf-8')
check(f"BILINGUAL: {m['checks']} checks / 0 failures" in log and 'SCRIPT ERROR' not in log and 'ERROR:' not in log,'latest GPU log is successful, not a stale manifest')
for label,paths,count in pairs:
 infos={};audios={};battle={}
 for lang,path in paths.items():
  info=json.loads(subprocess.check_output([ffprobe,'-v','error','-count_frames','-show_streams','-show_format','-of','json',path]))
  v=next(s for s in info['streams'] if s['codec_type']=='video');a=next(s for s in info['streams'] if s['codec_type']=='audio')
  check((v['width'],v['height'],v['avg_frame_rate'],int(v['nb_read_frames']))==(1080,1920,'60/1',count),label+' '+lang+' native dimensions and identical frame count')
  check(v['codec_name']=='h264' and a['codec_name']=='aac',label+' '+lang+' H264 + AAC')
  check(v.get('tags',{}).get('language')==('zho' if lang=='zh' else 'eng') and filename_matches_title(path,lang,info['format'].get('tags',{}).get('title')),label+' '+lang+' video metadata and localized filename preserve language and full title')
  check(abs(float(v['duration'])-float(a['duration']))<.025,label+' '+lang+' audio and video durations agree')
  decode=subprocess.run([ffmpeg,'-v','error','-i',path,'-f','null','-'],capture_output=True,timeout=40)
  check(decode.returncode==0 and not decode.stderr,label+' '+lang+' full decode clean')
  audios[lang]=raw(path,['-map','0:a:0','-ac','1','-ar','48000','-f','f32le','-'])
  battle[lang]=raw(path,['-an','-vf','crop=384:384:348:768,scale=48:48:flags=area','-pix_fmt','rgb24','-f','rawvideo','-'])
  infos[lang]={'frames':int(v['nb_read_frames']),'duration':float(v['duration'])}
 check(audios['zh']==audios['en'],label+' both languages have bit-identical decoded audio')
 pcm=array.array('f',audios['zh']);rms=math.sqrt(sum(x*x for x in pcm)/len(pcm))
 check(rms>.005,label+' common game audio is not silent')
 check(len(battle['zh'])==len(battle['en']),label+' battle crops cover the same timeline')
 errors=[abs(a-b) for a,b in zip(battle['zh'],battle['en'])];mean=sum(errors)/len(errors)
 check(mean<2,label+' all encoded battle frames match (compression tolerance)')
 results.append({'mode':label,'frames':count,'video_duration':infos['zh']['duration'],'audio_identical':True,'audio_rms':rms,'battle_mean_rgb_error_255':mean})
for name,region in [('matchup','1080:420:0:220'),('watermark','600:300:240:1290')]:
 crops=[raw(m['outputs'][lang],['-vf',f'select=eq(n\\,10),crop={region}','-frames:v','1','-pix_fmt','rgb24','-f','rawvideo','-']) for lang in ['zh','en']]
 changed=sum(abs(a-b)>12 for a,b in zip(*crops))/len(crops[0])
 check(changed>.0005,name+' differs in actual encoded Chinese and English pictures')
result={'checks':checks,'failures':0,'gpu_checks':m['checks'],'pairs':results}
Path(os.environ.get('BATTLE_RECORD_MEDIA_REPORT','tests/recording_bilingual_validation.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result));print(f'BILINGUAL_MEDIA: {checks} checks / 0 failures')
