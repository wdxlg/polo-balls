"""Validate test_battle_recording.gd outputs using ffprobe/ffmpeg (stdlib only)."""
import argparse
import array
import json
import math
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--manifest', default=str(Path(os.environ.get('APPDATA', '.')) / 'Godot/app_userdata/polo_balls/recordings/test_recording_manifest.json'))
parser.add_argument('--output', default='tests/recording_output_validation.json')
args = parser.parse_args()
ffmpeg = shutil.which('ffmpeg') or 'C:/ffmpeg/bin/ffmpeg.exe'
ffprobe = shutil.which('ffprobe') or 'C:/ffmpeg/bin/ffprobe.exe'
items = json.loads(Path(args.manifest).read_text(encoding='utf-8'))
results = []
checks = 0

def check(ok, reason):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(reason)

def magnitude(data, frequency):
    # Hann window avoids leakage from the simultaneously playing other test tone.
    n = len(data)
    co = si = total = 0.0
    for j, value in enumerate(data):
        w = 0.5 - 0.5 * math.cos(2 * math.pi * j / max(1, n - 1))
        phase = 2 * math.pi * frequency * j / 48000
        co += value * w * math.cos(phase)
        si += value * w * math.sin(phase)
        total += w
    return math.hypot(co, si) / max(total, 1e-9)

def edges(values, threshold, spacing):
    result = []
    active = False
    for i, v in enumerate(values):
        state = v > threshold
        if state and not active:
            result.append(i * spacing)
        active = state
    return result

for index, item in enumerate(items):
    path = item['path']
    d = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-count_frames', '-show_streams', '-show_format', '-of', 'json', path]))
    videos = [s for s in d['streams'] if s['codec_type'] == 'video']
    audios = [s for s in d['streams'] if s['codec_type'] == 'audio']
    check(len(videos) == 1 and len(audios) == 1, 'one video and one audio track required')
    v, a = videos[0], audios[0]
    check((v['width'], v['height']) == (1080, 1920), 'native Full HD')
    check(v['codec_name'] == 'h264' and a['codec_name'] == 'aac', 'H.264 + AAC')
    check(v.get('color_space') == 'bt709', 'correct color-space metadata')
    check(v['avg_frame_rate'] == '60/1', '60 fps')
    check(int(v['nb_read_frames']) == item['frames'], 'all frames preserved')
    check(a['channels'] == 2 and int(a['sample_rate']) == 48000, '48k stereo test output')
    check(abs(float(v['duration']) - float(a['duration'])) < 0.025, 'audio/video duration agreement')
    decode = subprocess.run([ffmpeg, '-v', 'error', '-i', path, '-f', 'null', '-'], capture_output=True, timeout=40)
    check(decode.returncode == 0 and not decode.stderr, 'complete decode without errors')
    pcm = array.array('f', subprocess.check_output([ffmpeg, '-v', 'error', '-i', path, '-map', '0:a:0', '-ac', '1', '-ar', '48000', '-f', 'f32le', '-']))
    rms = math.sqrt(sum(x*x for x in pcm) / max(len(pcm), 1))
    check(rms > 0.02, 'non-silent gameplay audio')
    windows = [pcm[i:i+4800] for i in range(2400, len(pcm)-4800, 4800)]
    levels = {f: sum(magnitude(w, f) for w in windows) / max(len(windows), 1) for f in [110, 440, 1760]}
    rejection = 20 * math.log10(max(levels[440], 1e-9) / max(levels[1760], 1e-9))
    check(rejection > 35.0, 'UI tone excluded from gameplay recording')
    check(levels[440] > max(0.04, levels[110] * 10), 'SIM restores normal pitch, not quarter-speed audio')
    entry = {'name': Path(path).name, 'width': 1080, 'height': 1920, 'fps': 60, 'frames': item['frames'], 'video_duration': v['duration'], 'audio_duration': a['duration'], 'audio_rms': rms, 'ui_rejection_db': round(rejection, 2), 'decoded_all_frames': True, 'codecs': ['h264', 'aac']}
    if index == 0:
        pixels = subprocess.check_output([ffmpeg, '-v', 'error', '-i', path, '-map', '0:v:0', '-vf', 'crop=8:8:536:956,scale=1:1,format=gray', '-f', 'rawvideo', '-'])
        flashes = edges(pixels, 230, 1/60)
        tone = [magnitude(pcm[i:i+960], 880) for i in range(0, len(pcm)-960, 240)]
        beeps = edges(tone, 0.04, 240/48000)
        check(len(flashes) == 2 and len(beeps) == 2, 'both sync beacons detected across pause/resume')
        offsets = [round(beeps[i] - flashes[i], 4) for i in range(2)]
        check(max(abs(x) for x in offsets) < 0.12, 'beep/flash sync error below 120 ms')
        check(abs(offsets[1] - offsets[0]) < 0.06, 'pause/resume does not add cumulative AV drift')
        entry.update(flash_times=flashes, beep_times=beeps, sync_offsets_seconds=offsets)
    print(json.dumps(entry))
    results.append(entry)
Path(args.output).write_text(json.dumps({'checks': checks, 'failures': 0, 'results': results}, indent=2), encoding='utf-8')
print(f'RECORDING_MEDIA: {checks} checks / 0 failures')
