"""Offline original-OGG analysis. Shared normalization preserves stereo balance.
Columns: time, left amplitude, right amplitude; -1 means no peak on that side.
Mono sources mirror each actual peak, without inventing a stereo pan.
"""
from pathlib import Path
import hashlib,json
import numpy as np
import soundfile as sf
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
out={};proof={}
for name in ['pigstep','otherside','cat']:
 p=Path('mc_cactus_note')/(name+'.ogg');pcm,sr=sf.read(p,always_2d=True);channels=pcm.shape[1];hop=int(sr*.02)
 env=gaussian_filter1d(np.sqrt(np.mean(pcm[:len(pcm)//hop*hop].reshape(-1,hop,channels)**2,axis=1)),1,axis=0)
 lo,hi=np.percentile(env,[10,98]);norm=np.clip((env-lo)/max(hi-lo,1e-9),0,1)
 events=[]
 if channels==1:
  ix,_=find_peaks(norm[:,0],distance=6,prominence=.035,height=.07)
  events=[[round(float(i*hop/sr),4),round(float(norm[i,0]),4),round(float(norm[i,0]),4)] for i in ix]
 else:
  peaks=[]
  for c in range(2):
   ix,_=find_peaks(norm[:,c],distance=6,prominence=.035,height=.07)
   peaks.extend((int(i),c,float(norm[i,c])) for i in ix)
  group=[]
  for i,c,a in sorted(peaks):
   if group and (i-group[0][0]>3 or c in [x[1] for x in group]):
    row=[round(group[0][0]*hop/sr,4),-1,-1]
    for j,k,v in group:row[k+1]=round(v,4)
    events.append(row);group=[]
   group.append((i,c,a))
  if group:
   row=[round(group[0][0]*hop/sr,4),-1,-1]
   for j,k,v in group:row[k+1]=round(v,4)
   events.append(row)
 out[name]={'duration':len(pcm)/sr,'channels':channels,'peaks':events}
 proof[name]={'sha1':hashlib.sha1(p.read_bytes()).hexdigest(),'channels':channels,'sample_rate':sr,'events':len(events)}
Path('mc_jukebox3/music_channel_peaks.gd').write_text('extends RefCounted\nconst DATA:Dictionary = '+json.dumps(out,separators=(',',':'))+'\n')
Path('mc_jukebox3/source_channels.json').write_text(json.dumps(proof,indent=2));print(proof)
