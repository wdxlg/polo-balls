# Stage exactly one inserted line per file on top of HEAD's blob, leaving
# every other (foreign) working-tree change unstaged.
import subprocess, sys

def blob(path):
    return subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, check=True).stdout

def stage(path, data):
    h = subprocess.run(["git", "hash-object", "-w", "--stdin"], input=data, capture_output=True, check=True).stdout.decode().strip()
    subprocess.run(["git", "update-index", "--cacheinfo", "100644," + h + "," + path], check=True)
    print("staged", path, h)

def insert_after_line(path, after_index, new_lines):
    raw = blob(path)
    nl = b"\r\n" if b"\r\n" in raw[:4096] else b"\n"
    parts = raw.split(nl)
    insert = [l.encode("utf-8") for l in new_lines]
    parts[after_index + 1:after_index + 1] = insert
    stage(path, nl.join(parts))

work_ctx = open("MCP_CONTEXT.md", encoding="utf-8").read().split("\n")
haochen_line = next(l for l in work_ctx if l.startswith("- 皓宸（2026-09-28）"))
assert blob("MCP_CONTEXT.md").split(b"\n")[0].decode("utf-8") == "# polo-balls 项目规则与接入说明"
insert_after_line("MCP_CONTEXT.md", 1, [haochen_line, ""])
assert blob("translations.csv").split(b"\n")[0].rstrip(b"\r") == b"keys,zh,en"
insert_after_line("translations.csv", 0, ["皓宸,皓宸,Haochen"])
