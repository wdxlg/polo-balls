"""Read-only gate: every in-game energy/progress bar must be painted by the shared bar.
Run from the project root; no Godot needed. Exit code 0 = pass.

Shared bar: scripts/characters/我的世界/frontier/creeper_style_bar.gd::paint (Minecraft boss bar look).
Fails when a script outside it
  * declares its own bar frame palette/geometry (``*BAR*_OUTER/BORDER/SEPARATOR/BACKGROUND...``), or
  * has a function whose name contains "bar" that draws primitives or builds ColorRect/ProgressBar nodes
    without calling ``.paint(``, or
  * draws a rect whose width is scaled by a ratio/progress value (a hand-made fill) anywhere.
Bars that are a different UI element on purpose go in ALLOWED with the reason.
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

root = pathlib.Path(__file__).resolve().parents[1]
SHARED = "scripts/characters/我的世界/frontier/creeper_style_bar.gd"
ALLOWED = {
    "scripts/characters/三角洲/盾狗.gd": "vertical stamina gauge standing behind the dog, a different element",
    "scripts/ui/random_character_draw_overlay.gd": "menu experience bar built from vanilla experience_bar sprites",
}
own_palette = re.compile(r"^\s*(?:const|var)\s+(\w*BAR\w*_(?:OUTER|BORDER|SEPARATOR|BACKGROUND)\w*)\s*[:=]", re.M | re.I)
func_head = re.compile(r"^func\s+(\w+)\s*\(", re.M)
node_bar = re.compile(r"\b(?:ColorRect|ProgressBar|TextureProgressBar)\.new\(")
scaled_fill = re.compile(r"\bdraw_(?:rect|texture_rect|texture_rect_region)\s*\([^\n]*?(?:(?:size\.x|width)\s*\*\s*[\w.()]*(?:ratio|progress|percent)|\b\w*(?:progress|ratio|fill)\w*_width\b)", re.I)
draw_call = re.compile(r"\bdraw_(?:rect|line|polyline|polygon|colored_polygon|texture_rect|texture_rect_region|style_box|multiline)\s*\(")

problems = []
for folder in ("classes", "scripts", "global", "ui"):
    for path in sorted((root / folder).rglob("*.gd")):
        rel = path.relative_to(root).as_posix()
        if rel == SHARED or rel in ALLOWED or rel.startswith("scripts/training/"):
            continue
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        for match in own_palette.finditer(text):
            problems.append(f"{rel}: own bar palette/geometry '{match.group(1)}' (use the shared bar)")
        heads = list(func_head.finditer(text))
        for i, head in enumerate(heads):
            name = head.group(1)
            if "bar" not in name.lower():
                continue
            body = text[head.end():heads[i + 1].start() if i + 1 < len(heads) else len(text)]
            if (draw_call.search(body) or node_bar.search(body)) and ".paint(" not in body:
                problems.append(f"{rel}: {name}() draws a bar by hand (call the shared bar paint)")
        for match in scaled_fill.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"{rel}:{line}: hand-made progress fill (call the shared bar paint)")

for problem in problems:
    print("SHARED_BAR_FAIL", problem)
print(f"SHARED_BAR_RESULT problems={len(problems)}")
sys.exit(1 if problems else 0)
