"""Keep lifetime-sensitive native body exceptions behind the shared registry."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / "classes/body_collision_exclusions.gd"
FORBIDDEN = re.compile(r"\b(?:add_collision_exception_with|remove_collision_exception_with|get_collision_exceptions|body_add_collision_exception|body_remove_collision_exception)\s*\(")
errors = []
for directory in ("classes", "scripts", "global"):
    for path in (ROOT / directory).rglob("*.gd"):
        if path == OWNER or "training" in path.parts:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            code = line.split("#", 1)[0]
            if FORBIDDEN.search(code):
                errors.append(f"{path.relative_to(ROOT)}:{number}: use body_collision_exclusions")
assert "get_collision_exceptions(" not in OWNER.read_text(encoding="utf-8"), "registry must never enumerate potentially freed native body RIDs as Nodes"
print("\n".join(errors) if errors else "Body collision exception registry: PASS")
raise SystemExit(bool(errors))
