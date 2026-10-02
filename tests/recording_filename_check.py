"""Check real recordings: one folder named after the Chinese title, fixed short MP4 names inside."""
import hashlib
import re
from pathlib import Path


def filename_matches_title(path, locale, title):
    if not isinstance(title, str) or not title:
        return False
    if title.startswith(('Mc小球', '中文_', '英文_', 'English_')):
        return False
    file = Path(path)
    if file.name != ('中文.mp4' if locale == 'zh' else 'English.mp4'):
        return False
    if locale != 'zh':
        return True  # the shared folder is named after the Chinese title, checked on the Chinese file
    folder = file.parent
    if re.search(r'[<>:"/\\|?*\x00-\x1f]', folder.name):
        return False
    safe = title.replace(':', '：').replace('*', '＊')
    safe = re.sub(r'[<>"/\\|?\x00-\x1f]', '-', safe).strip()
    while safe.endswith('.'):
        safe = safe[:-1].strip()
    device = safe.split('.', 1)[0].upper()
    if device in {'CON', 'PRN', 'AUX', 'NUL'} or re.fullmatch(r'(?:COM|LPT)[1-9¹²³]', device):
        safe = '_' + safe
    budget = min(160, 238 - len(str(folder.parent)) - 19)
    suffixes = ['']
    collision = re.search(r' (\([1-9][0-9]*\))$', folder.name)
    if collision and int(collision[1][1:-1]) >= 2:
        suffixes.append(' ' + collision[1])
    for suffix in suffixes:
        limit = budget - len(suffix)
        if limit < 12:
            continue
        stem = safe if len(safe) <= limit else safe[:limit - 9] + '~' + hashlib.sha256(safe.encode('utf-8')).hexdigest()[:8]
        if folder.name == stem + suffix:
            return True
    return False
