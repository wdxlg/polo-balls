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
    fade_in = round(.002 * RATE)
    y[:fade_in] *= np.linspace(0, 1, fade_in)
    n = min(len(y), round(fade * RATE))
    y[-n:] *= np.linspace(1, 0, n) ** 1.5
    y *= .76 / max(np.max(np.abs(y)), 1e-8)
    path = ROOT / name
    sf.write(path, y, RATE, format="OGG", subtype="VORBIS")
    decoded, _ = sf.read(path)
    for _ in range(3):
        if np.max(np.abs(decoded)) < .95: break
        y *= .88 / np.max(np.abs(decoded))
        sf.write(path, y, RATE, format="OGG", subtype="VORBIS")
        decoded, _ = sf.read(path)
    assert np.max(np.abs(decoded)) < .98, (name, "decoded clipping")
    return {"file": name, "duration_seconds": len(decoded) / RATE,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "decoded_peak": float(np.max(np.abs(decoded)))}

def build(manifest):
    sources = {r['cache_file'].removesuffix('.ogg'):read_source(r) for r in manifest['sources']}
    outputs=[]
    for i in (1,2):
        d=.46
        t=np.arange(round(d*RATE))/RATE
        # Strong midband attack translates on small speakers; no sub-bass dependence.
        y=layer(sources[f'item_mace_smash_air{i}'],d,1.35,220,8500)*1.10
        y+=layer(sources[f'entity_wind_charge_wind_burst{i}'],d,1.3,450,11000)*.90
        y+=layer(sources[f'block_amethyst_break{i}'],d,1.65,1400,10500)*.26*np.exp(-t/.13)
        y+=layer(sources[f'block_respawn_anchor_deplete{i}'],d,1.75,180,5000)*.35
        # Mild soft saturation lowers crest factor: an audible body, not one sample peak.
        y=np.tanh(3.6*y)*(0.95-0.35*t/d)
        outputs.append(finish(y,f'heaven_wave_punch_audible{i}.ogg',.10))
    return outputs

if __name__=='__main__':
    path=ROOT/'HEAVENFALL_AUDIBLE_SOUNDS.json'
    manifest=json.loads(path.read_text(encoding='utf-8'))
    manifest['derived_outputs']=build(manifest)
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for item in manifest['derived_outputs']: print(item)
