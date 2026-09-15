"""Regenerate the export-safe catalog from translations.csv, or use --check in CI.
Run from any working directory. Standard-library Python 3 only.
"""
from pathlib import Path
import argparse
import csv
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
CSV = ROOT / "translations.csv"
CATALOG = ROOT / "global" / "translation_catalog.gd"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    with CSV.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != ["keys", "zh", "en"]:
            raise ValueError("Expected keys,zh,en header")
        rows = list(reader)
    seen = set()
    for row in rows:
        key = row["keys"]
        if not key or key in seen or None in row:
            raise ValueError("Empty/duplicate key or invalid CSV row: " + str(row))
        seen.add(key)
    table = {lang: {r["keys"]: r[lang] for r in rows} for lang in ("zh", "en")}
    missing = []
    for scene in sorted((ROOT / "scenes" / "characters").rglob("*.tscn")):
        name = scene.stem
        value = table["en"].get(name, "")
        if not value.strip() or any(0x3400 <= ord(c) <= 0x9FFF for c in value):
            missing.append(str(scene.relative_to(ROOT)))
    if missing:
        print("Missing character English translations:\n" + "\n".join(missing), file=sys.stderr)
        return 1
    prefix = CATALOG.read_text(encoding="utf-8-sig").split("const TABLE:Dictionary = ", 1)[0]
    expected = prefix + "const TABLE:Dictionary = " + json.dumps(table, ensure_ascii=False, indent="\t") + "\n"
    if args.check:
        if CATALOG.read_text(encoding="utf-8-sig") != expected:
            print("Catalog is out of sync; run this script without --check.", file=sys.stderr)
            return 1
    else:
        CATALOG.write_text(expected, encoding="utf-8", newline="\n")
    print(f"Translation catalog OK: {len(rows)} keys; all character scenes covered.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
