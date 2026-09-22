"""One-time, reversible ShunCode Bridge project-context integration.
Only changes the MCP instructions expression and read_files description, plus
installs a small reader. Never restarts the editor or changes tunnel credentials.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, tempfile
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
HOOK = 'require("../runtime/project-context.cjs").appendProjectContext'
FILES = ('src/bridge-server.ts', 'dist/extension.js')

def sha(data): return hashlib.sha256(data).hexdigest()

def transform(raw, name):
    text = raw.decode('utf-8')
    if HOOK in text:
        if text.count(HOOK) != 2:
            raise RuntimeError('Partial/unexpected installation: ' + name)
        return raw
    match = re.search(r'if \(!([A-Za-z_$][\w$]*)\.workspace\.workspaceFolders\?\.length\)', text)
    if not match: raise RuntimeError('Cannot locate workspace API in ' + name)
    workspace = match.group(1) + '.workspace.workspaceFolders || []'
    old = 'instructions: BRIDGE_SERVER_INSTRUCTIONS'
    if text.count(old) != 1: raise RuntimeError('Unexpected initialize signature in ' + name)
    text = text.replace(old, f'instructions: {HOOK}(BRIDGE_SERVER_INSTRUCTIONS, {workspace})')
    pattern = r'tools: BRIDGE_TOOL_DEFINITIONS\.map\(\(tool\) => \(\{.*?\}\)\)'
    matches = list(re.finditer(pattern, text, re.S))
    if len(matches) != 1: raise RuntimeError('Unexpected tools/list signature in ' + name)
    original = matches[0].group(0)
    needle = 'description: tool.description,'
    if original.count(needle) != 1: raise RuntimeError('Unexpected tool description in ' + name)
    replacement = original.replace(needle, 'description: tool.description + (tool.name === "read_files" ? "\\n\\n" + ' + HOOK + '("", ' + workspace + ') : ""),')
    text = text[:matches[0].start()] + replacement + text[matches[0].end():]
    return text.encode('utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--extension', default='E:/ShunCode/resources/app/extensions/shuncode')
    parser.add_argument('--check', action='store_true', help='Verify installed files without modifying them')
    parser.add_argument('--verify-plan', action='store_true', help='Test the proposed patch in a temporary copy, without installation')
    args = parser.parse_args()
    extension = Path(args.extension).resolve()
    helper = HERE / 'project-context.cjs'
    runtime = extension / 'runtime/project-context.cjs'
    node = shutil.which('node')
    if not node: raise RuntimeError('Node.js is required for syntax and integration checks')
    subprocess.run([node, str(HERE / 'test-context.cjs')], check=True)
    originals = {}
    proposed = {}
    for relative in FILES:
        p = extension / relative
        raw = p.read_bytes()
        originals[p] = raw
        proposed[p] = transform(raw, relative)
    if args.verify_plan:
        with tempfile.TemporaryDirectory(prefix='shuncode-context-plan-') as td:
            staged = Path(td)
            (staged / 'dist').mkdir()
            (staged / 'runtime').mkdir()
            (staged / 'dist/extension.js').write_bytes(proposed[extension / 'dist/extension.js'])
            (staged / 'runtime/project-context.cjs').write_bytes(helper.read_bytes())
            subprocess.run([node, '--check', str(staged / 'dist/extension.js')], check=True)
            subprocess.run([node, str(HERE / 'test-installed.cjs'), str(staged), str(ROOT)], check=True)
        print('PATCH_PLAN_VERIFIED (no installed application files changed)')
        return
    if args.check:
        for p, data in proposed.items():
            if p.read_bytes() != data: raise RuntimeError('Not installed: ' + str(p))
        if not runtime.exists() or runtime.read_bytes() != helper.read_bytes(): raise RuntimeError('Helper missing or different')
        subprocess.run([node, '--check', str(extension / 'dist/extension.js')], check=True)
        subprocess.run([node, str(HERE / 'test-installed.cjs'), str(extension), str(ROOT)], check=True)
        print('INSTALLED_FILES_OK (running extension host still requires reload after initial install)')
        return
    # Syntax-check the proposed complete bundle before touching the live install.
    with tempfile.TemporaryDirectory(prefix='shuncode-context-') as td:
        checkfile = Path(td) / 'extension.cjs'
        checkfile.write_bytes(proposed[extension / 'dist/extension.js'])
        subprocess.run([node, '--check', str(checkfile)], check=True)
    backup = ROOT.parent / 'polo-balls-checkpoints' / ('mcp_context_bridge_' + datetime.now().strftime('%Y%m%d_%H%M%S'))
    backup.mkdir(parents=True, exist_ok=False)
    records = []
    for p, data in originals.items():
        relative = p.relative_to(extension)
        dest = backup / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)
        records.append({'file': str(relative), 'before_sha256': sha(data), 'after_sha256': sha(proposed[p])})
    previous_helper = runtime.read_bytes() if runtime.exists() else None
    if previous_helper is not None:
        (backup / 'runtime').mkdir(exist_ok=True)
        shutil.copy2(runtime, backup / 'runtime/project-context.cjs')
    (backup / 'manifest.json').write_text(json.dumps({'extension': str(extension), 'files': records, 'helper_existed': previous_helper is not None}, indent=2), encoding='utf-8')
    # Check nobody replaced the bundle while the backup was being made.
    for p, data in originals.items():
        if p.read_bytes() != data: raise RuntimeError('Extension changed concurrently: ' + str(p))
    changed = []
    helper_written = False
    try:
        runtime.write_bytes(helper.read_bytes())
        helper_written = True
        for p, data in proposed.items():
            staged = p.with_name(p.name + '.context-new')
            staged.write_bytes(data)
            os.replace(staged, p)
            changed.append(p)
        subprocess.run([node, '--check', str(extension / 'dist/extension.js')], check=True)
        subprocess.run([node, str(HERE / 'test-installed.cjs'), str(extension), str(ROOT)], check=True)
    except Exception:
        for p in changed: p.write_bytes(originals[p])
        if helper_written:
            if previous_helper is None: runtime.unlink(missing_ok=True)
            else: runtime.write_bytes(previous_helper)
        raise
    print('BRIDGE_CONTEXT_INSTALLED')
    print('BACKUP=' + str(backup))
    print('RELOAD_REQUIRED: reload/restart ShunCode once after saving your work. No editor restart was performed.')
    print('After reload, every new MCP initialize and tools/list reads the current MCP_CONTEXT.md automatically.')

if __name__ == '__main__': main()
