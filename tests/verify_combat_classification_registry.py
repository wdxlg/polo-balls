"""Read-only registry coverage gate. Run from the project root; no Godot needed.
New gameplay resources must register explicitly; this script never auto-labels them.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
text = (root / "classes/combat_classification_catalog.gd").read_text(encoding="utf-8-sig")
scene_marker = "const SCENES:Dictionary = "
script_marker = "const SCRIPTS:Dictionary = "
scenes = json.loads(text.split(scene_marker, 1)[1].split(script_marker, 1)[0].strip())
scripts = json.loads(text.split(script_marker, 1)[1].strip())
excluded_name = re.compile(r"(?:test_|preview_|benchmark_|bench_|profile_|visual_|probe_)")
actual_scripts = set()
for folder in ("classes", "scripts", "global", "ui", "Images/characters"):
    for path in (root / folder).rglob("*.gd"):
        if path.relative_to(root).as_posix().startswith("scripts/training/") and excluded_name.match(path.name):
            continue
        actual_scripts.add("res://" + path.relative_to(root).as_posix())
actual_scenes = {
    "res://" + path.relative_to(root).as_posix()
    for folder in ("scenes", "global", "ui")
    for path in (root / folder).rglob("*.tscn")
}
missing = sorted((actual_scripts - scripts.keys()) | (actual_scenes - scenes.keys()))
stale = sorted((scripts.keys() - actual_scripts) | (scenes.keys() - actual_scenes))
valid_kinds = {"character", "combat_entity", "subentity", "projectile", "obstacle", "terrain", "hazard", "status", "effect", "visual", "system", "component"}
invalid = [key for key, row in {**scenes, **scripts}.items() if row.get("entity_kind") not in valid_kinds]
# Status polarity/cleanup are mandatory for future identities and stages.
def has_gd_method(path, method, seen=None):
    seen = set() if seen is None else seen
    if not path or path in seen:
        return False
    seen.add(path)
    file = root / path.removeprefix("res://")
    if not file.is_file():
        return False
    text = file.read_text(encoding="utf-8-sig")
    if re.search(r"^func\s+" + re.escape(method) + r"\s*\(", text, re.M):
        return True
    parent = re.search(r'^extends\s+"(res://[^"\n]+)"', text, re.M)
    return has_gd_method(parent.group(1), method, seen) if parent else False

invalid_status_policies = []
for key, row in {**scenes, **scripts}.items():
    for stage, profile in [("base", row)] + [(str(k), {**row, **v}) for k, v in row.get("stages", {}).items()]:
        if profile.get("entity_kind") != "status":
            continue
        if profile.get("status_polarity") not in {"negative", "positive", "neutral", "dynamic"} or not profile.get("status_cleanup"):
            invalid_status_policies.append(key + "#" + stage)
        script = key if key.endswith(".gd") else row.get("root_script", "")
        if profile.get("status_polarity") == "dynamic" and not has_gd_method(script, "get_status_effect_polarity"):
            invalid_status_policies.append(key + "#" + stage + ":missing_dynamic_query")
        cleanup = profile.get("status_cleanup", "detach")
        if cleanup != "detach" and not has_gd_method(script, cleanup):
            invalid_status_policies.append(key + "#" + stage + ":missing_cleanup_method")
buff_text = (root / "classes/buff.gd").read_text(encoding="utf-8-sig")
buff_names = [x.strip() for x in buff_text.split("enum Buff_types {", 1)[1].split("}", 1)[0].split(",") if x.strip()]
missing_buff_polarity = [name for name in buff_names if "Buff_types." + name + ":" not in buff_text]
result = {"scenes": len(actual_scenes), "scripts": len(actual_scripts), "missing": missing, "stale": stale, "invalid_kinds": invalid, "invalid_status_policies": invalid_status_policies, "missing_buff_polarity": missing_buff_polarity}
print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(1 if missing or stale or invalid or invalid_status_policies or missing_buff_polarity else 0)
