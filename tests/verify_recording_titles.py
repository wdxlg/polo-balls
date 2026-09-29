"""Decode the current test_recording_titles.gd outputs, not historical MP4s."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from recording_filename_check import filename_matches_title
import shutil
import subprocess

from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser()
parser.add_argument('--folder', type=Path, default=Path(os.environ.get('APPDATA', str(Path.home()))) / 'Godot/app_userdata/polo_balls/recordings/title_layout_after')
args = parser.parse_args()
folder = args.folder
ffmpeg = shutil.which('ffmpeg') or 'C:/ffmpeg/bin/ffmpeg.exe'
ffprobe = shutil.which('ffprobe') or 'C:/ffmpeg/bin/ffprobe.exe'
manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
checks = 0
results = []


def check(ok, label):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(label)
    print('PASS:', label)


required_checks = 20 if len(manifest['outputs']) == 1 else 119
check(manifest['failures'] == 0 and manifest['checks'] >= required_checks, 'current GPU layout suite passed')
for item in manifest['outputs']:
    label = item['case']
    audio = {}
    titles = {}
    pair = {'case': label, 'frames': item['frames'], 'files': {}}
    for locale, filename in item['files'].items():
        path = Path(filename)
        info = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-count_frames', '-show_streams', '-show_format', '-of', 'json', str(path)]))
        titles[locale] = info.get('format', {}).get('tags', {}).get('title', '')
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        sound = next(s for s in info['streams'] if s['codec_type'] == 'audio')
        check((video['width'], video['height'], video['avg_frame_rate'], int(video['nb_read_frames'])) == (1080, 1920, '60/1', item['frames']), f'{label} {locale}: native dimensions and shared frame count')
        check(video['codec_name'] == 'h264' and sound['codec_name'] == 'aac', f'{label} {locale}: H264 video and AAC audio retained')
        check(video.get('tags', {}).get('language') == ('zho' if locale == 'zh' else 'eng'), f'{label} {locale}: correct language metadata')
        decoded = subprocess.run([ffmpeg, '-v', 'error', '-i', str(path), '-f', 'null', '-'], capture_output=True, timeout=40)
        check(decoded.returncode == 0 and not decoded.stderr, f'{label} {locale}: complete MP4 decodes without errors')
        frame = folder / f'{label}_{locale}_decoded.png'
        subprocess.run([ffmpeg, '-v', 'error', '-y', '-i', str(path), '-vf', f'select=eq(n\\,{item["frames"] - 1})', '-frames:v', '1', str(frame)], check=True, timeout=40)
        check(frame.is_file() and Image.open(frame).size == (1080, 1920), f'{label} {locale}: actual encoded final frame extracted')
        audio[locale] = subprocess.check_output([ffmpeg, '-v', 'error', '-i', str(path), '-map', '0:a:0', '-ac', '1', '-ar', '48000', '-f', 'f32le', '-'])
        pair['files'][locale] = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'decoded_frame': str(frame)}
    check(audio['zh'] == audio['en'], f'{label}: both languages retain identical audio')
    check(all(filename_matches_title(item['files'][locale], locale, titles[locale]) for locale in ['zh', 'en']), f'{label}: localized filenames match full title metadata')
    results.append(pair)

# Static long-name witness: compare the encoded World VS area with the GPU
# image whose text bounds were checked. Only lossy H264 differences allowed.
for locale in ['zh', 'en']:
    original = Image.open(folder / f'zh_long_duel_live_{locale}.png').convert('RGB').crop((0, 50, 1080, 525))
    encoded = Image.open(folder / f'zh_long_duel_live_{locale}_decoded.png').convert('RGB').crop((0, 50, 1080, 525))
    mean = sum(ImageStat.Stat(ImageChops.difference(original, encoded)).mean) / 3
    check(mean < 2.0, f'long duel {locale}: encoded clean header/VS match verified GPU frame (mean RGB error {mean:.4f}/255)')
    # The blue-background fixture is vertically uniform at these positions.
    # The removed full-width dark banner covered y=76..288; check real MP4
    # pixels, not just the viewport node tree or an unencoded PNG.
    frame = Image.open(folder / f'zh_long_duel_live_{locale}_decoded.png').convert('RGB')
    for x in (100, 540, 900):
        top_green = frame.getpixel((x, 120))[1]
        clear_green = frame.getpixel((x, 330))[1]
        check(top_green >= clear_green - 20, f'long duel {locale}: no dark header in encoded video at x={x}')

report = {'checks': checks, 'failures': 0, 'gpu_checks': manifest['checks'], 'pairs': results}
(folder / 'media_validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'RECORDING_TITLES_MEDIA: {checks} checks / 0 failures')
