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


def read_click_request(path):
    # Godot's replace-on-rename can briefly remove the destination on Windows.
    # A transient file/JSON race is not a recording failure or a reason to click elsewhere.
    deadline = time.monotonic() + 2.0
    while True:
        try:
            return json.loads(path.read_text(encoding='utf8'))
        except (FileNotFoundError, PermissionError, json.JSONDecodeError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)


def click_recording_button(request_path, evidence_path, editor_pid):
    """Use real mouse input, but only over the test game's own native window."""
    request = read_click_request(request_path)
    user32 = ctypes.windll.user32
    class Point(ctypes.Structure):
        _fields_ = [('x', ctypes.c_long), ('y', ctypes.c_long)]
    user32.WindowFromPoint.argtypes = [Point]
    user32.WindowFromPoint.restype = ctypes.c_void_p
    user32.GetAncestor.argtypes = [ctypes.c_void_p, ctypes.c_uint]
    user32.GetAncestor.restype = ctypes.c_void_p
    point = Point(round(request['x']), round(request['y']))
    class Rect(ctypes.Structure):
        _fields_ = [('left', ctypes.c_long), ('top', ctypes.c_long),
                    ('right', ctypes.c_long), ('bottom', ctypes.c_long)]
    user32.GetWindowRect.argtypes = [ctypes.c_void_p, ctypes.POINTER(Rect)]
    candidates = {}
    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def child(hwnd, _):
        pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == request['pid'] and user32.IsWindowVisible(hwnd):
            rect = Rect()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            if rect.right-rect.left > 100 and rect.bottom-rect.top > 100:
                candidates[int(hwnd)] = (rect.left, rect.top, rect.right, rect.bottom)
        return True
    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def visit(hwnd, _):
        child(hwnd, 0)
        pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == editor_pid:
            user32.EnumChildWindows(hwnd, child, 0)
        return True
    user32.EnumWindows(visit, 0)
    if not candidates:
        raise RuntimeError('Owned game window not found; no click sent.')
    target = max(candidates, key=lambda h: (candidates[h][2]-candidates[h][0])*(candidates[h][3]-candidates[h][1]))
    top = user32.GetAncestor(target, 2)
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x12, 0, 2, 0)
    current = ctypes.windll.kernel32.GetCurrentThreadId()
    foreground = user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), None)
    attached = user32.AttachThreadInput(current, foreground, True)
    try:
        user32.ShowWindow(top, 9)
        user32.SetForegroundWindow(top)
        user32.SetFocus(target)
        time.sleep(0.2)  # Foreground activation crosses the editor/game GUI thread.
        if user32.GetForegroundWindow() != top:
            raise RuntimeError('Test game could not gain foreground focus; no click sent.')
        time.sleep(0.1)
        user32.ClientToScreen.argtypes = [ctypes.c_void_p, ctypes.POINTER(Point)]
        if not user32.ClientToScreen(target, ctypes.byref(point)):
            raise RuntimeError('Cannot convert owned client coordinates; no click sent.')
        hit = user32.WindowFromPoint(point)
        pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hit, ctypes.byref(pid))
        if pid.value != request['pid']:
            raise RuntimeError('Button point is outside the owned game window; no click sent: ' + str((request, candidates)))
        # Toolbar parallax responds to the mouse. Re-evaluate its live center,
        # and require Godot's actual hover hit-test before the physical click.
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            request = read_click_request(request_path)
            point = Point(round(request['x']), round(request['y']))
            user32.ClientToScreen(target, ctypes.byref(point))
            user32.SetPhysicalCursorPos(point.x, point.y)
            if request.get('hovered', False):
                break
            time.sleep(0.04)
        else:
            raise RuntimeError('Recording button hover never confirmed; no click sent.')
        from PIL import ImageGrab
        rect = Rect()
        user32.GetWindowRect(target, ctypes.byref(rect))
        ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom)).save(evidence_path.with_suffix('.png'))
        user32.SetPhysicalCursorPos(point.x, point.y)
        hit = user32.WindowFromPoint(point)
        pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hit, ctypes.byref(pid))
        if user32.GetForegroundWindow() != top or pid.value != request['pid']:
            raise RuntimeError('Focus or hit window changed before click; no mouse button input sent.')
        user32.mouse_event(0x0002, 0, 0, 0, 0)
        time.sleep(0.08)
        user32.mouse_event(0x0004, 0, 0, 0, 0)
    finally:
        if attached:
            user32.AttachThreadInput(current, foreground, False)
    evidence_path.write_text(json.dumps(dict(request=request, hwnd=int(target), foreground=int(top)),
                                         ensure_ascii=False, indent=2), encoding='utf8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--editor-pid', type=int, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', choices=('both', 'warden', 'armor'), default='both')
    parser.add_argument('--mouse-click', action='store_true',
                        help='Use a real foreground mouse click after two seconds of battle.')
    parser.add_argument('--tail-seconds', type=float, default=100.0)
    parser.add_argument('--frame-cap', type=int, default=0, help='Diagnostic render cap; zero leaves the normal policy unchanged.')
    parser.add_argument('--start-delay', type=float, default=0.0,
                        help='Seconds to let the normal scene warm up before the recording click.')
    parser.add_argument('--skip-prewarmer', action='store_true',
                        help='Diagnostic control only; default retains normal background preparation.')
    args = parser.parse_args()
    if not 1.0 <= args.tail_seconds <= 100.0:
        parser.error('--tail-seconds must be between 1 and 100 for this fixture')
    if os.name != 'nt':
        raise RuntimeError('This harness explicitly tests the Windows editor embedding path.')
    ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    root = Path(__file__).resolve().parents[1]
    evidence = args.evidence.resolve()
    output = args.output.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=False)
    user32 = ctypes.windll.user32
    user32.GetForegroundWindow.restype = ctypes.c_void_p
    user32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    user32.SetForegroundWindow.argtypes = [ctypes.c_void_p]
    user32.SetFocus.argtypes = [ctypes.c_void_p]
    user32.SetFocus.restype = ctypes.c_void_p
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
    # Godot consumes engine flags such as --editor-pid before get_cmdline_args().
    # The unique armed file and this controller's chosen editor gate this one-shot hook.
    hook = f'''
func _recording_editor_test_once() -> void:
	var flag:String = {flag_literal}
	if _is_variant or not FileAccess.file_exists(flag): return
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
        cases = (False, True) if args.case == 'both' else (args.case == 'armor',)
        for armor in cases:
            label = 'editor-long-' + ('armor' if armor else 'warden')
            flag.write_text(json.dumps(dict(root=evidence.as_posix(), output_root=output.as_posix(),
                                           label=label, armor=armor, tail_seconds=args.tail_seconds,
                                           mouse_click=args.mouse_click,
                                           frame_cap=args.frame_cap,
                                           start_delay=max(0.0, args.start_delay),
                                           skip_prewarmer=args.skip_prewarmer), ensure_ascii=False), encoding='utf8')
            user32.keybd_event(0x12, 0, 0, 0)
            user32.keybd_event(0x12, 0, 2, 0)
            current = ctypes.windll.kernel32.GetCurrentThreadId()
            foreground = user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), None)
            attached = user32.AttachThreadInput(current, foreground, True)
            try:
                user32.ShowWindow(hwnd, 9)
                user32.BringWindowToTop(hwnd)
                user32.SetForegroundWindow(hwnd)
                user32.SetFocus(hwnd)
                time.sleep(0.2)
                if user32.GetForegroundWindow() != hwnd:
                    raise RuntimeError('Editor did not gain focus; refusing to send F6 to another application.')
                user32.keybd_event(0x75, 0x40, 0, 0)
                time.sleep(0.1)
                user32.keybd_event(0x75, 0x40, 2, 0)
            finally:
                if attached:
                    user32.AttachThreadInput(current, foreground, False)
            result = evidence / (label + '.json')
            click_request = evidence / (label + '.click.json')
            clicked = False
            deadline = time.monotonic() + 300
            while not result.exists() and time.monotonic() < deadline:
                if args.mouse_click and not clicked and click_request.exists():
                    click_recording_button(click_request, evidence / (label + '.click-handled.json'), args.editor_pid)
                    clicked = True
                time.sleep(0.1)
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
