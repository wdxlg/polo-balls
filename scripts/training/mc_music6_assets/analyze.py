from pathlib import Path
import json,numpy as np,soundfile as sf
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
B=Path('mc_music6');tracks={}
for n in ['creator','precipice','relic']:
 x,sr=sf.read(B/'assets'/(n+'.ogg'),always_2d=True);h=int(sr*.02);e=gaussian_filter1d(np.sqrt(np.mean(x[:len(x)//h*h].reshape(-1,h,x.shape[1])**2,axis=1)),1,axis=0);lo,hi=np.percentile(e,[10,98]);v=np.clip((e-lo)/(hi-lo),0,1);ix,_=find_peaks(v[:,0],distance=6,prominence=.035,height=.07)
 tracks[n]={'duration':len(x)/sr,'channels':x.shape[1],'peaks':[[round(i*h/sr,4),round(float(v[i,0]),4),round(float(v[i,0]),4)] for i in ix]}
(B/'new_channel_peaks.gd').write_text('extends RefCounted\nconst DATA:Dictionary = '+json.dumps(tracks,separators=(',',':'))+'\n')
code=Path('mc_music5/analyze_music.py').read_text().replace("mc_jukebox3/music_channel_peaks.gd","mc_music6/new_channel_peaks.gd").replace("Path('mc_cactus_note')","Path('mc_music6/assets')").replace("mc_music5/music_features.gd","mc_music6/all_features.gd").replace("mc_music5/analysis_report.json","mc_music6/analysis_report.json")
exec(compile(code,'music6_features','exec'))
data=json.loads((B/'all_features.gd').read_text().split('= ',1)[1])
for name,track in data.items():
 (B/('features_'+name+'.gd')).write_text('extends RefCounted\nconst DATA:Dictionary = '+json.dumps(track,separators=(',',':'))+'\n');print(name,'events',len(track['peaks']))
