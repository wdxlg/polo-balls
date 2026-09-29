"""Independent, stdlib-only checks of the actual exported summit GLB geometry."""
import ast
import collections
import hashlib
import json
import math
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKS = 0
FAILURES = 0


def check(ok, label):
    global CHECKS, FAILURES
    CHECKS += 1
    FAILURES += not ok
    print(("PASS " if ok else "FAIL ") + label)


class GLB:
    def __init__(self, path):
        raw = path.read_bytes()
        magic, version, length = struct.unpack_from("<4sII", raw)
        assert (magic, version, length) == (b"glTF", 2, len(raw))
        offset = 12
        while offset < len(raw):
            size, kind = struct.unpack_from("<II", raw, offset)
            chunk = raw[offset + 8:offset + 8 + size]
            if kind == 0x4E4F534A:
                self.doc = json.loads(chunk)
            elif kind == 0x004E4942:
                self.binary = chunk
            offset += 8 + size
        self.meshes = {m["name"]: m for m in self.doc["meshes"]}

    def accessor(self, index):
        a = self.doc["accessors"][index]
        view = self.doc["bufferViews"][a["bufferView"]]
        components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        code = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
        fmt = "<" + code * components
        stride = view.get("byteStride", struct.calcsize(fmt))
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return [struct.unpack_from(fmt, self.binary, start + i * stride) for i in range(a["count"])]

    def top_faces(self, prefix):
        # Each unit top quad consists of two triangles. Return unique cell/height.
        tops = set()
        for name, mesh in self.meshes.items():
            if not name.startswith(prefix):
                continue
            for primitive in mesh["primitives"]:
                positions = self.accessor(primitive["attributes"]["POSITION"])
                normals = self.accessor(primitive["attributes"]["NORMAL"])
                indices = [x[0] for x in self.accessor(primitive["indices"])]
                for i in range(0, len(indices), 3):
                    ids = indices[i:i + 3]
                    if not all(normals[j][1] > .999 for j in ids):
                        continue
                    vertices = [positions[j] for j in ids]
                    x = math.floor(sum(v[0] for v in vertices) / 3)
                    y = math.floor(-sum(v[2] for v in vertices) / 3)
                    h = round(vertices[0][1], 5)
                    tops.add((x, y, h))
        return tops

    def images(self):
        result = {}
        for image in self.doc["images"]:
            view = self.doc["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            result[image["name"]] = self.binary[start:start + view["byteLength"]]
        return result

    def triangles(self):
        return sum(self.doc["accessors"][p["indices"]]["count"] // 3
                   for m in self.doc["meshes"] for p in m["primitives"])


def main():
    old = GLB(ROOT / "assets/maps/summit/shandian.glb")
    new = GLB(ROOT / "assets/maps/summit/shandian_natural.glb")
    info = json.loads((ROOT / "assets/maps/summit/shandian_natural.SOURCE.json").read_text(encoding="utf-8"))
    check(len(old.meshes) == len(new.meshes) == 17, "17 original material batches retained")
    check(set(old.meshes) == set(new.meshes), "same mountain, forest and landmark mesh groups")
    for name, expected in info["original_assets_sha256"].items():
        check(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected,
              "original asset untouched: " + name)
    check(hashlib.sha256((ROOT / info["runtime_model"]).read_bytes()).hexdigest() == info["runtime_model_sha256"],
          "runtime GLB matches source manifest")
    check(new.images() == old.images(), "all 14 embedded original PNG files unchanged byte-for-byte")
    colors = lambda g: {m["name"]: m["pbrMetallicRoughness"].get("baseColorFactor", [1] * 4) for m in g.doc["materials"]}
    check(colors(old) == colors(new), "original material tint factors retained")
    check(all(s.get("magFilter") == 9728 for s in new.doc.get("samplers", [])), "nearest pixel texture magnification")
    check(new.triangles() <= old.triangles() * 1.10, "mesh triangle increase bounded below ten percent")
    # Tree trunks and foliage are exact authored geometry, not replacement trees.
    for suffix in ["Spruce bark", "Spruce end", "Spruce needles"]:
        name = "02 Alpine spruce / " + suffix
        a = old.meshes[name]["primitives"][0]
        b = new.meshes[name]["primitives"][0]
        for attr in ["POSITION", "NORMAL", "TEXCOORD_0"]:
            check(old.accessor(a["attributes"][attr]) == new.accessor(b["attributes"][attr]),
                  "unchanged " + suffix + " " + attr)
        check(old.accessor(a["indices"]) == new.accessor(b["indices"]), "unchanged " + suffix + " topology")
    old_top = {(x, y): h for x, y, h in old.top_faces("01 Mountain / ")}
    new_top = {(x, y): h for x, y, h in new.top_faces("01 Mountain / ")}
    check(old_top.keys() == new_top.keys(), "mountain footprint and terrain columns unchanged")
    roi = {(x, y) for x in range(4, 13) for y in range(11, 20)}
    check({old_top[p] for p in roi} == {96}, "reproduced original forced 9x9 plateau")
    check(all(old_top[p] == new_top[p] for p in old_top if p not in roi), "every terrain height outside former pad unchanged")
    heights = {new_top[p] for p in roi}
    check(len(heights) >= 12 and max(heights) - min(heights) >= 12, "former plateau is now a varied natural ridge")
    check(sum(h == max(new_top.values()) for h in new_top.values()) <= 2, "apex narrows to at most two columns, not a square cap")
    check(max(abs(new_top[x, y] - new_top[x + dx, y + dy])
              for x, y in roi for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]) <= 7,
          "natural peak joins surrounding slopes without a plateau cliff")
    # Evaluate only pure height functions, not Blender or the model generation main.
    source = ast.parse((ROOT / "art_sources/summit/build_summit.py").read_text(encoding="utf-8"))
    functions = [n for n in source.body if isinstance(n, ast.FunctionDef)
                 and n.name in {"hashnoise", "noise", "fbm", "terrain"}]
    namespace = {"math": math, "SEED": 9262026}
    exec(compile(ast.Module(body=functions, type_ignores=[]), "height-functions", "exec"), namespace)
    check(all(namespace["terrain"](x, y) == h for (x, y), h in old_top.items()), "default source profile still reproduces original terrain")
    check(all(namespace["terrain"](x, y, flatten_summit=False) == h for (x, y), h in new_top.items()), "exported natural terrain matches shared height function")
    needle_tops = new.top_faces("02 Alpine spruce / Spruce needles")
    exposed = {}
    for x, y, h in needle_tops:
        exposed[x, y] = max(h, exposed.get((x, y), -math.inf))
    snow_tops = new.top_faces("02 Alpine spruce / Snow")
    manifest_tops = {(p[0], p[1], p[2] + p[3]) for t in info["forest"] for p in t["patches"]}
    check(snow_tops == manifest_tops, "actual snow mesh equals all recorded branch patches")
    check(len(snow_tops) > 200, "snow is distributed across branches, not 62 identical tip blocks")
    check(all(exposed.get((p[0], p[1])) == p[2] for t in info["forest"] for p in t["patches"]), "every patch rests on an exposed leaf top, with no floating snow")
    check(all(p[3] in [.125, .25, .375] for t in info["forest"] for p in t["patches"]), "varied thin snow layers, no oversized full snow cubes")
    counts = collections.Counter(t["load"] for t in info["forest"])
    check(len(info["forest"]) == 62 and sum(counts.values()) == 62, "all 62 authored trees retained")
    check(counts == info["snow_summary"] and all(counts[k] > 5 for k in ["none", "light", "medium", "heavy"]), "snow-free, light, medium and heavy trees all present")
    check(all(not t["patches"] for t in info["forest"] if t["load"] == "none"), "snow-free trees have no snow geometry")
    check(all(len(t["patches"]) >= 3 and len({p[2] for p in t["patches"]}) >= 2
              for t in info["forest"] if t["load"] != "none"), "each snowy tree has multiple patches on multiple branch levels")
    averages = {k: sum(len(t["patches"]) for t in info["forest"] if t["load"] == k) / counts[k] for k in counts}
    check(averages["none"] < averages["light"] < averages["medium"] < averages["heavy"], "snow load visibly increases between profiles")
    print("NATURAL_SUMMIT_GEOMETRY", json.dumps({"triangles_before": old.triangles(), "triangles_after": new.triangles(),
          "peak_heights": sorted(heights), "snow_tree_counts": counts, "snow_patches": len(snow_tops), "average_snow_patches": averages}))
    print("SUMMIT_NATURAL_MODEL_RESULT checks=%d failures=%d" % (CHECKS, FAILURES))
    return int(bool(FAILURES))


if __name__ == "__main__":
    sys.exit(main())
