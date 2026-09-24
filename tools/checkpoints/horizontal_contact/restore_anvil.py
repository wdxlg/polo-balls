"""Restore ONLY this task's anvil delta, preserving the pre-existing untracked file.
Defaults to validation/dry-run; actual writes require --apply. Refuses later edits.
"""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--state", required=True, choices=["before", "after"])
parser.add_argument("--apply", action="store_true", help="Write after all hashes validate")
parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
args = parser.parse_args()
data = json.loads(Path(__file__).with_name("anvil_delta.json").read_text(encoding="utf-8"))
path = args.root / data["path"]
raw = path.read_bytes()
normalized = raw.replace(b"\r\n", b"\n")
digest = hashlib.sha256(normalized).hexdigest()
destination = args.state
source = "after" if destination == "before" else "before"
if digest == data[destination]["normalized_sha256"]:
    print("Already at requested anvil state:", destination)
    raise SystemExit(0)
if digest != data[source]["normalized_sha256"]:
    raise SystemExit("REFUSED: anvil contains later edits. Back up and merge manually; nothing written.")
old, new = data["old_text"], data["new_text"]
if destination == "before":
    old, new = new, old
text = normalized.decode("utf-8")
if text.count(old) != 1:
    raise SystemExit("REFUSED: patch context is not unique; nothing written.")
result = text.replace(old, new, 1).encode("utf-8")
if hashlib.sha256(result).hexdigest() != data[destination]["normalized_sha256"]:
    raise SystemExit("REFUSED: resulting whole-file hash differs; nothing written.")
if data[destination]["newline"] == "CRLF":
    result = result.replace(b"\n", b"\r\n")
if hashlib.sha256(result).hexdigest() != data[destination]["raw_sha256"]:
    raise SystemExit("REFUSED: raw-byte restoration would differ; nothing written.")
if args.apply:
    path.write_bytes(result)
    print("Restored ONLY anvil task delta to", destination, "(byte-exact hash verified).")
else:
    print("DRY RUN OK: can restore anvil to", destination, "with --apply; nothing written.")
