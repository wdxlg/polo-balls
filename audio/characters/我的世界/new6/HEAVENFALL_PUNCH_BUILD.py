"""Build ONLY Heavenfall's derived SFX from SHA1-verified Mojang assets.
Requires Python 3, numpy, scipy, soundfile. Run beside HEAVENFALL_STYLE_SOUNDS.json.
Original assets and derivatives remain subject to Minecraft/Mojang terms, not CC0.
No other characters' original audio files are modified.
"""
import hashlib, json, pathlib, urllib.request
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly, resample, butter, sosfilt

ROOT = pathlib.Path(__file__).resolve().parent
RATE = 48000

def read_source(record):
    cache = ROOT / "heavenfall_source_cache" / record["cache_file"]
    cache.parent.mkdir(exist_ok=True)
    if not cache.exists():
        cache.write_bytes(urllib.request.urlopen(record["url"]).read())
    assert hashlib.sha1(cache.read_bytes()).hexdigest() == record["sha1"]
    y, sr = sf.read(cache)
    if y.ndim == 2: y = y.mean(axis=1)
    y = resample_poly(y, RATE, sr)
    onset = np.flatnonzero(np.abs(y) > max(np.max(np.abs(y)) * .025, 1e-6))
    if len(onset): y = y[max(0, onset[0] - int(.002 * RATE)):]
    return y

def layer(y, duration, speed=1.0, high=100, low=12000, reverse=False, offset=0.0):
    if reverse: y = y[::-1]
    y = resample(y, max(1, round(len(y) / speed)))
    y = sosfilt(butter(2, [high, low], btype="bandpass", fs=RATE, output="sos"), y)
    n = round(duration * RATE)
    out = np.zeros(n)
    shift = round(offset * RATE)
    take = min(len(y), n - shift)
    if take <= 0: return out
    part = y[:take].copy()
    level = np.sqrt(np.mean(part * part))
    if level > 1e-8: part *= .12 / level
    out[shift:shift + take] = part
    return out

def finish(y, name, fade, tail_delays=()):
    dry = y.copy()
    for delay, gain in tail_delays:
        samples = round(delay * RATE)
        y[samples:] += dry[:-samples] * gain
    fade_in = round(.0007 * RATE)
    y[:fade_in] *= np.linspace(0, 1, fade_in)
    n = min(len(y), round(fade * RATE))
    y[-n:] *= np.linspace(1, 0, n) ** 1.5
    y *= .84 / max(np.max(np.abs(y)), 1e-8)
    path = ROOT / name
    sf.write(path, y, RATE, format="OGG", subtype="VORBIS")
    decoded, _ = sf.read(path)
    assert np.max(np.abs(decoded)) < .98, (name, "decoded clipping")
    return {"file": name, "duration_seconds": len(decoded) / RATE,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "decoded_peak": float(np.max(np.abs(decoded)))}

def thump(duration, start, end, decay):
    t = np.arange(round(duration * RATE)) / RATE
    sweep = .024
    phase = 2*np.pi*(end*t+(start-end)*sweep*(1-np.exp(-t/sweep)))
    # Upper harmonics let the impulse remain audible on small speakers.
    wave = np.sin(phase) + .36*np.sin(2*phase) + .16*np.sin(3*phase)
    return np.tanh(wave*1.35)/1.35 * (1-np.exp(-t/.0005))*np.exp(-t/decay)

def snap(duration, seed, high, low, decay):
    t = np.arange(round(duration*RATE))/RATE
    noise = np.random.default_rng(seed).standard_normal(len(t))
    noise = sosfilt(butter(2,[high,low],btype='bandpass',fs=RATE,output='sos'),noise)
    noise /= max(np.sqrt(np.mean(noise**2)),1e-8)
    return noise*(1-np.exp(-t/.0005))*np.exp(-t/decay)

def build(manifest):
    sources = {r['cache_file'].removesuffix('.ogg'):read_source(r) for r in manifest['sources']}
    outputs=[]
    for i in (1,2):
        bow=sources['random_bow']; crystal=sources[f'block_amethyst_break{i}']
        crack=sources[f'block_respawn_anchor_deplete{i}']; charge=sources[f'block_respawn_anchor_charge{i}']
        for rain in (False,True):
            d=.16 if rain else .24
            t=np.arange(round(d*RATE))/RATE
            speed=(2.35 if rain else 1.95)+.07*(i-1)
            y=layer(bow,d,speed,850,14500)*.65*np.exp(-t/.10)
            y+=layer(bow,d,speed,2700,9500)*.85*np.exp(-t/.042)
            y+=snap(d,100+i+int(rain)*10,2600,11500,.008)*(.16 if rain else .22)
            y+=thump(d,340 if rain else 300,180 if rain else 145,.022)*(.12 if rain else .30)
            y+=layer(crystal,d,2.25,1600,12000)*.11*np.exp(-t/.065)
            name=f'heaven_rain_shot_punch{i}.ogg' if rain else f'heaven_shot_punch{i}.ogg'
            outputs.append(finish(y,name,.04 if rain else .07))
        d=.46
        t=np.arange(round(d*RATE))/RATE
        # Immediate physical impact first; cosmic texture is the decay, not the attack.
        y=thump(d,175+4*(i-1),62+2*(i-1),.085)*.68
        y+=snap(d,200+i,600,10000,.017)*.26
        y+=layer(crystal,d,1.65,1400,12000)*.28*np.exp(-t/.055)
        y+=layer(charge,d,1.6,120,4800)*.20*np.exp(-t/.25)
        y+=layer(crack,d,1.8,280,6500)*.21*np.exp(-t/.23)
        outputs.append(finish(y,f'heaven_wave_punch{i}.ogg',.14,((.055,.055),)))
    return outputs

if __name__=='__main__':
    path=ROOT/'HEAVENFALL_PUNCH_SOUNDS.json'
    manifest=json.loads(path.read_text(encoding='utf-8'))
    manifest['derived_outputs']=build(manifest)
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for item in manifest['derived_outputs']: print(item)
