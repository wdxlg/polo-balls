"""Stage one file as HEAD content with lines starting with PREFIX replaced by the working-tree line(s) with that prefix.
Usage: python stage_replace_line.py <path> <prefix>. Other people's working-tree edits stay unstaged."""
import subprocess, sys
path, prefix = sys.argv[1], sys.argv[2]
head = subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, check=True).stdout.decode("utf-8")
work = open(path, encoding="utf-8", newline="").read()
new_lines = [l for l in work.splitlines(keepends=True) if l.startswith(prefix)]
old = [l for l in head.splitlines(keepends=True) if l.startswith(prefix)]
assert len(new_lines) == 1 and len(old) == 1, (len(new_lines), len(old))
out = head.replace(old[0], new_lines[0], 1)
assert out != head
blob = subprocess.run(["git", "hash-object", "-w", "--stdin"], input=out.encode("utf-8"), capture_output=True, check=True).stdout.decode().strip()
mode = subprocess.run(["git", "ls-files", "-s", "--", path], capture_output=True, check=True).stdout.decode().split()[0]
subprocess.run(["git", "update-index", "--cacheinfo", mode + "," + blob + "," + path], check=True)
print("staged", path, blob)
