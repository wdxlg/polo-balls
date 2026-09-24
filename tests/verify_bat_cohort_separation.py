"""Run the real Godot crowd-separation test and fail on engine log errors.

The GDScript test can report all gameplay checks as passing while Object.get_meta
logs thousands of missing-key errors; the external stderr check is essential.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot executable (or set GODOT_BIN)")
    args = parser.parse_args()
    bundled = Path("E:/godot/polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe")
    godot = args.godot or os.environ.get("GODOT_BIN")
    if not godot:
        godot = str(bundled) if bundled.is_file() else (shutil.which("godot") or shutil.which("godot4"))
    if not godot:
        parser.error("Godot not found; pass --godot or set GODOT_BIN")

    project = Path(__file__).resolve().parents[1]
    command = [godot, "--headless", "--path", str(project), "--script", "res://tests/test_bat_cohort_separation_guard.gd"]
    try:
        result = subprocess.run(command, cwd=project, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=80, check=False)
    except subprocess.TimeoutExpired:
        print("BAT_COHORT_SEPARATION: Godot timed out", file=sys.stderr)
        return 2

    summary = re.search(r"BAT_COHORT_SEPARATION: (\d+) checks / (\d+) failures", result.stdout)
    missing_meta = result.stderr.count("The object does not have any 'meta' values with the key 'mc_bat_cohort'")
    engine_errors = [line for line in result.stderr.splitlines() if line.lstrip().startswith(("ERROR:", "SCRIPT ERROR:"))]
    passed = (result.returncode == 0 and summary is not None and int(summary.group(1)) >= 14
              and int(summary.group(2)) == 0 and missing_meta == 0 and not engine_errors)
    print(summary.group(0) if summary else result.stdout[-3000:])
    print(f"MISSING_COHORT_META_ERRORS={missing_meta} ENGINE_ERRORS={len(engine_errors)} GODOT_EXIT={result.returncode}")
    if not passed:
        print(result.stderr[-8000:], file=sys.stderr)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
