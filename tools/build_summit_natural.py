"""Derive natural summit peaks / varied spruce snow from the authored source.

Run in a separate Blender process, never in an artist's unsaved scene:
  blender --background --factory-startup --python-exit-code 7 \
      --python tools/build_summit_natural.py [-- --rebuild]

The original summit GLB and .blend remain untouched. The optional generator
profile preserves every terrain sample outside the old 9x9 landing, all tree
positions/heights/leaf blocks, and the exact original Minecraft PNG bytes.
"""
import hashlib
import importlib.util
import json
import pathlib
import shutil
import sys

import bpy

PROJECT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "art_sources/summit"
OUTPUT = PROJECT / "art_sources/summit_natural"
RUNTIME = PROJECT / "assets/maps/summit"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    protected = [SOURCE / "山巅.blend", SOURCE / "shandian.glb", RUNTIME / "shandian.glb"]
    original_hashes = {str(p.relative_to(PROJECT)): sha(p) for p in protected}
    if (OUTPUT / "山巅.blend").exists() and "--rebuild" not in sys.argv:
        raise RuntimeError("Derived scene exists; back up any edits before -- --rebuild")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / ".gdignore").touch()
    (OUTPUT / ".gitignore").write_text("*.blend1\nbuild_status.json\n", encoding="utf-8")
    (OUTPUT / "textures").mkdir(exist_ok=True)
    for texture in sorted((SOURCE / "textures").glob("*.png")):
        shutil.copy2(texture, OUTPUT / "textures" / texture.name)
    spec = importlib.util.spec_from_file_location("authored_summit", SOURCE / "build_summit.py")
    source = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source)
    source.ROOT = OUTPUT
    authored_terrain = source.terrain
    authored_forest = source.build_forest
    source.terrain = lambda x, y: authored_terrain(x, y, flatten_summit=False)
    source.build_forest = lambda: authored_forest(snow_style="varied")
    anchor = {}

    def natural_landmark():
        # A small marker sits on the actual apex, not on a leveled square pad.
        x, y = max(source.HEIGHT, key=lambda p: source.HEIGHT[p])
        h = source.HEIGHT[x, y]
        source.box("03 Summit landmark", "Worn trail", x, y, h, 1, 1, .125)
        source.box("03 Summit landmark", "Cairn", x + .125, y + .125, h + .125, .75, .75, .75)
        source.box("03 Summit landmark", "Cairn", x + .25, y + .25, h + .875, .5, .5, .875)
        source.box("03 Summit landmark", "Snow", x + .25, y + .25, h + 1.75, .5, .5, .125)
        point = bpy.data.objects.new("SUMMIT_ANCHOR - natural apex", None)
        bpy.context.scene.collection.objects.link(point)
        point.location = (x + .5, y + .5, h + .125)
        point.empty_display_type = "PLAIN_AXES"
        anchor.update(x=x + .5, y=y + .5, terrain_height=h, model_top=h + 1.875)

    source.build_summit = natural_landmark
    source.main()
    metrics = json.loads((OUTPUT / "model_metrics.json").read_text(encoding="utf-8"))
    metrics["profile"] = "natural_apex_varied_branch_snow"
    metrics["summit_anchor"] = [anchor["x"], anchor["y"], anchor["terrain_height"] + .125]
    metrics["model_top"] = anchor["model_top"]
    metrics["snow_tree_counts"] = {
        name: sum(t["load"] == name for t in source.FOREST_SNOW)
        for name in ["none", "light", "medium", "heavy"]
    }
    metrics["snow_patch_count"] = sum(len(t["patches"]) for t in source.FOREST_SNOW)
    (OUTPUT / "model_metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
    # Reuse the source provenance rather than granting new rights to its textures.
    provenance = {
        "asset": "山巅 / natural apex and varied branch snow",
        "profile": metrics["profile"],
        "generator": "tools/build_summit_natural.py",
        "shared_generator": "art_sources/summit/build_summit.py",
        "original_assets_sha256": original_hashes,
        "minecraft": "Java 1.21.1",
        "rights": "Original Minecraft textures copyright Mojang Studios / Microsoft. Local use at user request; no redistribution permission granted.",
        "texture_source_manifest": "art_sources/summit/SOURCE.json",
        "textures": {p.name: sha(p) for p in sorted((SOURCE / "textures").glob("*.png"))},
        "runtime_model": "assets/maps/summit/shandian_natural.glb",
        "runtime_model_sha256": sha(OUTPUT / "shandian.glb"),
        "bounds_blender": {"base": source.BASE, "top": anchor["model_top"]},
        "apex": anchor,
        "former_plateau": {
            "x_min": 4, "x_max": 12, "y_min": 11, "y_max": 19,
            "heights": [[source.HEIGHT[x, y] for x in range(4, 13)] for y in range(11, 20)],
        },
        "snow_summary": metrics["snow_tree_counts"],
        "forest": source.FOREST_SNOW,
    }
    (OUTPUT / "SOURCE.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2), encoding="utf-8")
    shutil.copy2(OUTPUT / "shandian.glb", RUNTIME / "shandian_natural.glb")
    (RUNTIME / "shandian_natural.SOURCE.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2), encoding="utf-8")
    for path in protected:
        assert sha(path) == original_hashes[str(path.relative_to(PROJECT))], "Original source changed"
    print("NATURAL_SUMMIT_RESULT", json.dumps(metrics, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
