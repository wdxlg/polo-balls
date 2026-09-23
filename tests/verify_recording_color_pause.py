"""Validate actual color/pause test MP4, not just recorder counters (stdlib only)."""
import json
import os
from pathlib import Path
import shutil
import subprocess

folder = Path(os.environ.get('APPDATA', '.')) / 'Godot/app_userdata/polo_balls/recordings/color_pause_test'
m = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
path = m['output']['path']
ffmpeg = shutil.which('ffmpeg') or 'C:/ffmpeg/bin/ffmpeg.exe'
ffprobe = shutil.which('ffprobe') or 'C:/ffmpeg/bin/ffprobe.exe'
checks = 0

def check(ok, label):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(label)
    print('PASS:', label)

check(m['failures'] == 0, 'GPU color and real Escape regression passed')
d = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-count_frames', '-show_streams', '-of', 'json', path]))
v = next(s for s in d['streams'] if s['codec_type'] == 'video')
a = next(s for s in d['streams'] if s['codec_type'] == 'audio')
check((v['width'], v['height'], v['avg_frame_rate']) == (1080, 1920, '60/1'), 'native 1080x1920 / 60 fps')
check(v['codec_name'] == 'h264' and a['codec_name'] == 'aac', 'H264 and AAC present')
check(int(v['nb_read_frames']) == m['output']['frames'], 'every reported frame decodes')
check(abs(float(v['duration']) - float(a['duration'])) < 0.025, 'audio/video durations agree')
check(0 <= m['game_time'] - float(v['duration']) < 1 / 60 + 0.002, 'encoded duration equals active capture clock')
check(m['wall_seconds'] - float(v['duration']) > 1.6, 'pause and countdown waiting not padded into output')
p = subprocess.run([ffmpeg, '-v', 'error', '-i', path, '-f', 'null', '-'], capture_output=True, timeout=40)
check(p.returncode == 0 and not p.stderr, 'full audiovisual decode without errors')
# The world center is painted red only during Esc pause, cyan once resume starts.
center = subprocess.check_output([ffmpeg, '-v', 'error', '-i', path, '-vf', 'crop=2:2:540:960,scale=1:1:flags=area', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'])
reds = sum(1 for r, g, b in zip(center[::3], center[1::3], center[2::3]) if r > 180 and r > g + 80 and r > b + 80)
check(reds == 0, 'zero encoded frames contain the paused-only red world marker')
# Compare the encoded frame with the matching pre-encode GPU sRGB reference.
rgb = subprocess.check_output([ffmpeg, '-v', 'error', '-i', path, '-vf', f"select=eq(n\\,{m['reference_frame']})", '-frames:v', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'])
png = subprocess.check_output([ffmpeg, '-v', 'error', '-i', str(folder / 'capture.png'), '-frames:v', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'])
check(len(rgb) == len(png) == 1080 * 1920 * 3, 'full-resolution reference and encoded RGB available')
differences = []
for y in range(2, 20):
    for x in range(1, 12):
        offset = (int(y / 20 * 1920) * 1080 + int(x / 12 * 1080)) * 3
        differences.extend(abs(rgb[offset + c] - png[offset + c]) for c in range(3))
mean_error = sum(differences) / len(differences)
# YUV420 may bleed at one-pixel color edges; bound both bulk and worst error.
p95_error = sorted(differences)[int(len(differences) * 0.95)]
check(mean_error < 3 and p95_error < 5 and max(differences) < 32, 'H264/BT709 color conversion adds only small compression error')
result = {'checks':checks, 'failures':0, 'gpu_checks':m['checks'], 'main_viewport_match':m['color'], 'codec_mean_rgb_error_255':mean_error, 'codec_max_rgb_error_255':max(differences), 'codec_p95_rgb_error_255':p95_error, 'paused_marker_frames':reds, 'frames':m['output']['frames'], 'video_duration':float(v['duration']), 'audio_duration':float(a['duration']), 'wall_seconds':m['wall_seconds']}
Path('tests/recording_color_pause_validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
print(f'COLOR_PAUSE_MEDIA: {checks} checks / 0 failures')
