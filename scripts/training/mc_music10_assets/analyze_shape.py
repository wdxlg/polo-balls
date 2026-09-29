from pathlib import Path
from math import gcd
import json,hashlib
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
from scipy.ndimage import gaussian_filter1d

TRACKS={
 'pigstep':'mc_cactus_note/pigstep.ogg',
 'otherside':'mc_cactus_note/otherside.ogg',
 'cat':'mc_cactus_note/cat.ogg',
 'creator':'mc_music6/assets/creator.ogg',
 'precipice':'mc_music6/assets/precipice.ogg',
 'relic':'mc_music6/assets/relic.ogg',
}
SR=24000; HOP=1440; SECONDS=HOP/SR; NFFT=2048
out={}; report={}
for name,path in TRACKS.items():
    pcm,sr=sf.read(path,always_2d=True)
    x=pcm.mean(axis=1)
    g=gcd(sr,SR); x=resample_poly(x,SR//g,sr//g)
    padded=np.pad(x,(NFFT//2,NFFT//2))
    frames=np.lib.stride_tricks.sliding_window_view(padded,NFFT)[::HOP]
    fft=np.fft.rfft(frames*np.hanning(NFFT),axis=1)
    power=np.abs(fft)**2
    freq=np.fft.rfftfreq(NFFT,1/SR)
    bands=np.stack([
        np.sqrt(power[:,(freq>=35)&(freq<180)].sum(axis=1)),
        np.sqrt(power[:,(freq>=180)&(freq<2500)].sum(axis=1)),
        np.sqrt(power[:,(freq>=4500)&(freq<11000)].sum(axis=1)),
    ],axis=1)
    flux=np.maximum(0,bands-np.roll(bands,1,axis=0));flux[0]=0
    norms=flux/np.maximum(np.percentile(flux,94,axis=0),1e-9)
    kick=np.clip(norms[:,0],0,1);snare=np.clip(norms[:,1],0,1);hat=np.clip(norms[:,2],0,1)
    # Dominant mixed-audio periodicity at 60ms cadence. It is approximate by design.
    lo,hi=int(SR/1200),int(SR/70)
    pitches=np.full(len(frames),.5);confidence=np.zeros(len(frames))
    for i in range(len(frames)):
        ac=np.fft.irfft(power[i],NFFT)
        lag=lo+int(np.argmax(ac[lo:hi]))
        confidence[i]=np.clip(ac[lag]/max(ac[0],1e-9),0,1)
        hz=SR/lag
        if confidence[i]>=.30:
            pitches[i]=np.clip(np.log2(hz/70)/np.log2(1200/70),0,1)
    melodic=(pitches-.5)*2
    percussive=np.clip((hat-kick-.12*snare)/np.maximum(hat+kick+snare+1e-6,1),-1,1)
    pw=np.clip((confidence-.30)/.30,0,1)
    raw=melodic*pw+percussive*(1-pw)*.72
    env=np.sqrt(np.mean(frames**2,axis=1))
    energy=np.clip(env/max(np.percentile(env,98),1e-9),0,1)
    gate=np.clip((energy-.025)/.10,0,1)
    raw*=gate
    raw=gaussian_filter1d(raw,1.15,mode='nearest')
    scale=max(float(np.percentile(np.abs(raw),95)),.22)
    shape=np.clip(raw/scale,-1,1)
    energy=np.clip(gaussian_filter1d(energy,1,mode='nearest')/max(np.percentile(energy,98),.05),0,1)
    points=[]
    for i,(sh,en) in enumerate(zip(shape,energy)):
        # Quantized enough for animation while keeping script size bounded.
        points.append([round(i*SECONDS,2),round(float(sh),2),round(float(en),2)])
    out[name]=points
    report[name]={
      'sha1':hashlib.sha1(Path(path).read_bytes()).hexdigest(),
      'frames':len(points),'step_seconds':SECONDS,
      'shape_min':round(float(shape.min()),3),'shape_max':round(float(shape.max()),3),
      'shape_mean':round(float(shape.mean()),3),'shape_std':round(float(shape.std()),3),
      'shape_changes_abs_gt_0_25':int((np.abs(np.diff(shape))>.25).sum()),
      'active_fraction':round(float((gate>0).mean()),3),
    }
    print(name,report[name])
    del frames,fft,power,padded,x,pcm,bands,flux,norms,energy,shape,raw
text='extends RefCounted\n'
text+='const ANALYSIS := "continuous_mixed_audio_pitch_shape_60ms_v1"\n'
text+='const DATA:Dictionary = '+json.dumps(out,separators=(',',':'))+'\n'
Path('mc_music10/music_shape_features.gd').write_text(text)
Path('mc_music10/shape_report.json').write_text(json.dumps(report,indent=2))
print('bytes',Path('mc_music10/music_shape_features.gd').stat().st_size)
