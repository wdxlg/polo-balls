"""Generate attack peaks from installed, unmodified original music.
Usage: python analyze_music.py PROJECT_ROOT
Requires numpy, scipy, soundfile. Output is a preload-able GDScript constant,
so exported games do not depend on an unlisted external JSON file.
"""
import sys,json
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import find_peaks
from scipy.ndimage import gaussian_filter1d
root=Path(sys.argv[1]);data={}
for name in ['pigstep','otherside','cat']:
    pcm,sr=sf.read(root/'audio/characters/我的世界/音符盒'/f'{name}.ogg')
    mono=pcm.mean(axis=1) if pcm.ndim>1 else pcm
    hop=int(sr*.02)
    rms=np.sqrt(np.mean(mono[:len(mono)//hop*hop].reshape(-1,hop)**2,axis=1))
    envelope=gaussian_filter1d(rms,1.0)
    low,high=np.percentile(envelope,[10,98])
    normalized=np.clip((envelope-low)/(high-low),0,1)
    peaks,_=find_peaks(normalized,distance=6,prominence=.035,height=.07)
    data[name]={'duration':len(mono)/sr,'peaks':[[round(float(i*hop/sr),4),round(float(normalized[i]),4)] for i in peaks]}
path=root/'scripts/characters/我的世界/cactus_note/music_peaks.gd'
path.write_text('extends RefCounted\nconst DATA:Dictionary = '+json.dumps(data,separators=(',',':'))+'\n',encoding='utf-8')
print({name:len(track['peaks']) for name,track in data.items()})
