"""Inspect the actual filenames and MP4 tags produced by the current GPU fixtures.
Run test_battle_recording.gd, test_recording_bilingual.gd and test_recording_offline.gd first.
This validates naming/output metadata, not the unrelated color or flash-timing assertions.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from recording_filename_check import filename_matches_title

parser = argparse.ArgumentParser()
parser.add_argument('--report', type=Path)
args = parser.parse_args()
root = Path(os.environ['APPDATA']) / 'Godot/app_userdata/polo_balls/recordings'
ffprobe = shutil.which('ffprobe') or 'C:/ffmpeg/bin/ffprobe.exe'
bilingual = json.loads((root / 'bilingual_test/manifest.json').read_text(encoding='utf-8'))
base = json.loads((root / 'test_recording_manifest.json').read_text(encoding='utf-8'))
offline = json.loads((root / 'offline_test/manifest.json').read_text(encoding='utf-8'))
checks = 0
results = []


def check(ok, label):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(label)
    print('PASS:', label)


check(bilingual['failures'] == 0 and offline['failures'] == 0, 'current bilingual and offline GPU manifests passed')
pairs = [('quantities_live', bilingual['outputs'])]
pairs += [(label, item['outputs']) for label, item in zip(['base_live', 'sim_abort', 'sim_finish'], base)]
pairs += [('offline_' + str(run['delay_ms']), run['outputs']) for run in offline['runs']]
for label, paths in pairs:
    check(set(paths) == {'zh', 'en'}, label + ': both explicitly paired language paths')
    pair = {'case': label, 'files': {}}
    for locale, filename in paths.items():
        path = Path(filename)
        check(path.is_file() and path.stat().st_size > 1000, label + ' ' + locale + ': actual nonempty MP4 exists')
        info = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)]))
        title = info.get('format', {}).get('tags', {}).get('title', '')
        video = next(stream for stream in info['streams'] if stream['codec_type'] == 'video')
        audio = next(stream for stream in info['streams'] if stream['codec_type'] == 'audio')
        check(filename_matches_title(path, locale, title), label + ' ' + locale + ': safe filename exactly matches localized full-title metadata')
        check((video['width'], video['height'], video['avg_frame_rate'], video['codec_name'], audio['codec_name']) == (1080, 1920, '60/1', 'h264', 'aac'), label + ' ' + locale + ': original video/audio output format retained')
        check(video.get('tags', {}).get('language') == ('zho' if locale == 'zh' else 'eng'), label + ' ' + locale + ': language metadata retained')
        pair['files'][locale] = {'path': str(path), 'title': title, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
    results.append(pair)
quantities = results[0]['files']
check(quantities['zh']['title'] == '3个钻石剑 vs 2个木剑 vs 牛', 'actual Chinese movie stores the exact requested count format')
check(quantities['en']['title'] == 'Diamond Sword * 3 vs Wooden Sword * 2 vs Cow', 'actual English movie stores translated name-star-number format')
check(Path(quantities['zh']['path']).name.startswith('3个钻石剑 vs 2个木剑 vs 牛'), 'Chinese movie filename has no branding prefix')
check(Path(quantities['en']['path']).name.startswith('Diamond Sword ＊ 3 vs Wooden Sword ＊ 2 vs Cow'), 'Windows English filename retains both quantity stars visually')
base_paths = [str(path) for item in base for path in item['outputs'].values()]
check(len(base_paths) == 6 and len(set(base_paths)) == 6 and all(Path(path).is_file() for path in base_paths), 'repeated live/simulated sessions retain six distinct files without overwriting earlier ones')
report = {'checks': checks, 'failures': 0, 'pairs': results}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('RECORDING_NAMES_MEDIA: %d checks / 0 failures' % checks)
