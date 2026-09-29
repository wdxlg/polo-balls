"""Offline mixed-audio descriptors, not instrument separation or exact transcription.
Profile = [low transient, mid transient, high transient, normalized pitch,
 pitch confidence, sustain seconds, beat salience, rest]. Existing peak times retained.
"""
import json,hashlib
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
from scipy.ndimage import gaussian_filter1d
src=Path('mc_jukebox3/music_channel_peaks.gd').read_text();data=json.loads(src.split('= ',1)[1]);report={}
for name,track in data.items():
 p=Path('mc_cactus_note')/(name+'.ogg');pcm,sr=sf.read(p,always_2d=True)
 mono=pcm.mean(axis=1); from math import gcd
 g=gcd(sr,24000);x=resample_poly(mono,24000//g,sr//g);sr=24000;hop=480;nfft=2048
 padded=np.pad(x,(nfft//2,nfft//2));frames=np.lib.stride_tricks.sliding_window_view(padded,nfft)[::hop];fft=np.fft.rfft(frames*np.hanning(nfft),axis=1);power=np.abs(fft)**2;freq=np.fft.rfftfreq(nfft,1/sr)
 bands=np.stack([np.sqrt(power[:,(freq>=a)&(freq<b)].sum(axis=1)) for a,b in [(35,180),(180,2500),(4500,11000)]],axis=1)
 flux=np.maximum(0,bands-np.roll(bands,1,axis=0));flux[0]=0
 sal=np.clip(flux/np.maximum(np.percentile(flux,94,axis=0),1e-9),0,1)
 env=gaussian_filter1d(np.sqrt(np.mean(frames**2,axis=1)),1)
 silence=max(float(env.max())*.012,1e-5)
 counts={'kick':0,'snare':0,'hat':0,'pitched':0,'sustain':0,'rest':0,'strong':0};profiles=[]
 for event in track['peaks']:
  i=min(len(frames)-1,round(event[0]/.02));sl=slice(max(0,i-2),min(len(frames),i+2))
  transient=sal[sl].max(axis=0);ratios=bands[i]/max(bands[i].sum(),1e-9)
  kick=float(transient[0]*min(1,ratios[0]/.25));snare=float(transient[1]*min(1,ratios[1]/.45));hat=float(transient[2]*min(1,ratios[2]/.1))
  # Autocorrelation estimates dominant periodicity of the MIX; confidence-gated visuals only.
  ac=np.fft.irfft(power[i],nfft);lo,hi=int(sr/1200),int(sr/70);lag=lo+int(np.argmax(ac[lo:hi]));confidence=float(np.clip(ac[lag]/max(ac[0],1e-9),0,1))
  hz=sr/lag;pitch=float(np.clip(np.log2(hz/70)/np.log2(1200/70),0,1)) if confidence>=.45 else .5
  j=i+1
  while j<min(len(env),i+51) and env[j]>=max(silence,env[i]*.60):j+=1
  hold=float(np.clip((j-i)*.02,.04,1)) if confidence>=.45 and kick<.65 and hat<.65 else .06
  beat=float(np.clip(.6*max(kick,snare)+.25*hat+.15*float(max(event[1:3])),0,1))
  rest=bool(env[i]<silence)
  profile=[round(v,3) for v in [kick,snare,hat,pitch,confidence,hold,beat]]+[rest]
  event.extend([profile,profile.copy()]);profiles.append(profile)
  for key,yes in [('kick',kick>=.55),('snare',snare>=.6),('hat',hat>=.55),('pitched',confidence>=.45),('sustain',hold>=.22),('rest',rest),('strong',beat>=.65)]:counts[key]+=int(yes)
 track['analysis']='mixed_audio_bands_autocorrelation_v1'
 report[name]={'sha1':hashlib.sha1(p.read_bytes()).hexdigest(),'source_channels':pcm.shape[1],'events':len(profiles),'counts':counts,'silence_rms':silence}
 print(name,counts)
 del frames,fft,power,padded,pcm
Path('mc_music5/music_features.gd').write_text('extends RefCounted\nconst DATA:Dictionary = '+json.dumps(data,separators=(',',':'))+'\n')
Path('mc_music5/analysis_report.json').write_text(json.dumps(report,indent=2));print('bytes',Path('mc_music5/music_features.gd').stat().st_size)
