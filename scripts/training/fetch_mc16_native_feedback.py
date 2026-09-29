"""Fetch/verify pinned vanilla assets. Never transcode or replace an existing file silently."""
import argparse, hashlib, json, urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT/'MC16_NATIVE_FEEDBACK_ASSETS.json'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    plan = json.loads(MANIFEST.read_text(encoding='utf-8'))
    def get(record):
        path = ROOT/record['file']
        if path.exists():
            data = path.read_bytes()
        elif args.verify_only:
            raise RuntimeError('Missing: '+record['file'])
        else:
            data = urllib.request.urlopen(record['url'], timeout=45).read()
        algorithm = 'sha1' if 'sha1' in record else 'sha256'
        if hashlib.new(algorithm, data).hexdigest() != record[algorithm] or len(data) != record['size']:
            raise RuntimeError('Hash/size mismatch (existing files are NOT overwritten): '+record['file'])
        if path.suffix == '.ogg' and not data.startswith(b'OggS'):
            raise RuntimeError('Not OGG: '+record['file'])
        if path.suffix == '.png' and not data.startswith(b'\x89PNG\r\n\x1a\n'):
            raise RuntimeError('Not PNG: '+record['file'])
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        return record['file']
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(get,plan['files']))
    print('MC16_NATIVE_ASSETS: %d/%d files match official bytes; no synthesized/repainted assets.' % (len(results),len(plan['files'])))
if __name__ == '__main__': main()
