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
    assert np.max(np.abs(decoded)) < .98, (name, "decoded clipping")
    return {"file": name, "duration_seconds": len(decoded) / RATE,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "decoded_peak": float(np.max(np.abs(decoded)))}

def build(manifest):
    sources = {r["cache_file"].removesuffix(".ogg"): read_source(r) for r in manifest["sources"]}
    outputs = []
    for i in (1, 2):
        bow = sources["random_bow"]
        crystal = sources[f"block_amethyst_break{i}"]
        crack = sources[f"block_respawn_anchor_deplete{i}"]
        charge = sources[f"block_respawn_anchor_charge{i}"]
        portal = sources["mob_endermen_portal" + ("2" if i == 2 else "")]
        # Dominant accelerated bow transient; restrained crystalline spatial edge.
        d = .24
        y = (layer(bow, d, 1.65 + .05 * (i-1), 350, 13000) * .82
             + layer(crystal, d, 1.8, 1600, 13000, offset=.008) * .16
             + layer(crack, d, 2.2, 700, 6000) * .08)
        outputs.append(finish(y, f"heaven_shot{i}.ogg", .065, ((.025, .09),)))
        # Shorter/lighter for seven separate rain launches, not seven long tails.
        d = .16
        y = (layer(bow, d, 2.15 + .08 * (i-1), 550, 14500) * .88
             + layer(crystal, d, 2.1, 2000, 14000) * .13)
        outputs.append(finish(y, f"heaven_rain_shot{i}.ogg", .055))
        # Fast inward dimensional suction. No bow sample in this event.
        d = .24
        y = (layer(portal, d, 2.0, 250, 9500) * .65
             + layer(crack[:int(.16*RATE)], d, 1.5, 450, 8000, reverse=True) * .32
             + layer(crystal, d, 2.5, 1800, 12000, offset=.035) * .10)
        outputs.append(finish(y, f"heaven_transit{i}.ogg", .075))
        # Outward energy release with crystal rim; no generic explosive sample.
        d = .46
        y = (layer(charge, d, 1.6, 100, 6000) * .55
             + layer(crack, d, 1.8, 180, 6500) * .30
             + layer(crystal, d, 1.3, 1200, 11500) * .22)
        outputs.append(finish(y, f"heaven_wave{i}.ogg", .17, ((.045,.12),(.085,.065))))
    return outputs

if __name__ == "__main__":
    path = ROOT / "HEAVENFALL_STYLE_SOUNDS.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["derived_outputs"] = build(manifest)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    for item in manifest["derived_outputs"]: print(item)
