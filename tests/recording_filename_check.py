"""Check real MP4 filenames against their full, localized title metadata."""
import hashlib
import re
from pathlib import Path


def filename_matches_title(path, locale, title):
    if not isinstance(title, str) or not title:
        return False
    if title.startswith(('Mc小球', '中文_', '英文_', 'English_')):
        return False
    file = Path(path)
    if file.suffix != '.mp4' or re.search(r'[<>:"/\\|?*\x00-\x1f]', file.name):
        return False
    safe = title.replace(':', '：').replace('*', '＊')
    safe = re.sub(r'[<>"/\\|?\x00-\x1f]', '-', safe).strip()
    while safe.endswith('.'):
        safe = safe[:-1].strip()
    device = safe.split('.', 1)[0].upper()
    if device in {'CON', 'PRN', 'AUX', 'NUL'} or re.fullmatch(r'(?:COM|LPT)[1-9¹²³]', device):
        safe = '_' + safe
    budget = min(160, 238 - len(str(file.parent)) - 16)
    suffixes = ['']
    collision = re.search(r' (\([1-9][0-9]*\))$', file.stem)
    if collision and int(collision[1][1:-1]) >= 2:
        suffixes.append(' ' + collision[1])
    for suffix in suffixes:
        limit = budget - len(suffix)
        if limit < 12:
            continue
        stem = safe if len(safe) <= limit else safe[:limit - 9] + '~' + hashlib.sha256(safe.encode('utf-8')).hexdigest()[:8]
        if file.name == stem + suffix + '.mp4':
            return True
    return False
