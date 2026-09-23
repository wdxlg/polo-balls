"""Fetch ONLY this character's pinned vanilla textures; never overwrite different files.
Run from any cwd with Python 3. No runtime game dependency.
Source and expected SHA-256 values: MC_COPPER_SWORD_ASSETS.json.
"""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[3]
manifest = json.loads((ROOT / "MC_COPPER_SWORD_ASSETS.json").read_text(encoding="utf-8"))
staged = []
for asset in manifest["assets"]:
    path = ROOT / asset["path"]
    data = path.read_bytes() if path.exists() else urlopen(asset["source"], timeout=30).read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != asset["sha256"]:
        raise RuntimeError("Unexpected bytes; refusing to overwrite: " + asset["path"])
    staged.append((path, data))
for path, data in staged:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        with path.open("xb") as output:
            output.write(data)
    print("VERIFIED", path.name, hashlib.sha256(data).hexdigest())
print("COPPER_NATIVE_ASSETS_OK", len(staged))
