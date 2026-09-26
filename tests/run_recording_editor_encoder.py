"""Windows real-editor recording regression (not a standalone --script substitute).
Save/select scenes/world.tscn in an idle editor, then run with --editor-pid,
--evidence NEW_FOLDER and --output NEW_MOVIE_FOLDER. Does not change saved prefs.
Uses a temporary, one-shot recorder hook; hash-guarded restoration runs in finally.
On a watchdog timeout, stop only the test's game window before rerunning.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--editor-pid', type=int, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if os.name != 'nt':
        raise RuntimeError('This harness explicitly tests the Windows editor embedding path.')
    root = Path(__file__).resolve().parents[1]
    evidence = args.evidence.resolve()
    output = args.output.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=False)
    user32 = ctypes.windll.user32
    windows = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def visit(hwnd, _):
        pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == args.editor_pid:
            title = ctypes.create_unicode_buffer(1024)
            user32.GetWindowTextW(hwnd, title, 1024)
            if title.value.startswith('world.tscn - ') and title.value.endswith('Godot Engine'):
                windows.append(int(hwnd))
        return True

    user32.EnumWindows(visit, 0)
    if len(windows) != 1:
        raise RuntimeError('Select/save world.tscn in the specified idle editor first.')
    hwnd = windows[0]
    source = root / 'scripts/ui/battle_recorder.gd'
    original = source.read_bytes()
    (evidence / 'recorder-before.gd').write_bytes(original)
    text = original.decode('utf8')
    anchor = 'func _ready() -> void:\n'
    assert text.count(anchor) == 1 and '_recording_editor_test_once' not in text
    flag = evidence / 'armed.json'
    flag_literal = json.dumps(flag.as_posix(), ensure_ascii=False)
    hook = f'''
func _recording_editor_test_once() -> void:
	var flag:String = {flag_literal}
	if _is_variant or not OS.get_cmdline_args().has("--editor-pid") or not FileAccess.file_exists(flag): return
	var options:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(flag))
	DirAccess.remove_absolute(flag)
	var driver:Node = load("res://tests/test_recording_editor_encoder.gd").new()
	get_tree().root.add_child.call_deferred(driver)
	driver.call_deferred("run", self, options)
'''
    patched = text.replace(anchor, anchor + '\tcall_deferred("_recording_editor_test_once")\n', 1) + hook
    source.write_bytes(patched.encode('utf8'))
    fingerprint = hashlib.sha256(source.read_bytes()).hexdigest()
    results = []
    try:
        for armor in (False, True):
            label = 'editor-long-' + ('armor' if armor else 'warden')
            flag.write_text(json.dumps(dict(root=evidence.as_posix(), output_root=output.as_posix(),
                                           label=label, armor=armor), ensure_ascii=False), encoding='utf8')
            current = ctypes.windll.kernel32.GetCurrentThreadId()
            foreground = user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), None)
            user32.AttachThreadInput(current, foreground, True)
            try:
                user32.ShowWindow(hwnd, 9)
                user32.SetForegroundWindow(hwnd)
                user32.SetFocus(hwnd)
            finally:
                user32.AttachThreadInput(current, foreground, False)
            user32.PostMessageW(hwnd, 0x100, 0x75, 1 | (0x40 << 16))
            user32.PostMessageW(hwnd, 0x101, 0x75, 1 | (0x40 << 16) | (3 << 30))
            result = evidence / (label + '.json')
            deadline = time.monotonic() + 200
            while not result.exists() and time.monotonic() < deadline:
                time.sleep(1)
            if not result.exists():
                raise TimeoutError('Editor test watchdog: ' + label)
            data = json.loads(result.read_text(encoding='utf8'))
            results.append(data)
            (evidence / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf8')
            print(label, json.dumps(data, ensure_ascii=False), flush=True)
            assert not data['failures'], data
            time.sleep(3)
    finally:
        if hashlib.sha256(source.read_bytes()).hexdigest() != fingerprint:
            raise RuntimeError('Concurrent source edit; refusing to overwrite it. Backup: ' + str(evidence / 'recorder-before.gd'))
        source.write_bytes(original)
        flag.unlink(missing_ok=True)
        print('Temporary editor hook removed; original recorder source restored.', flush=True)


if __name__ == '__main__':
    main()
