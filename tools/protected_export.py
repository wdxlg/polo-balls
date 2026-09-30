"""Build and verify the project's keyed Windows release; never fall back to plaintext."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime

PROJECT = Path(__file__).resolve().parents[1]
ENGINE_ROOT = PROJECT.parent / "polo-balls-tools" / "offline-engine"
SOURCE = ENGINE_ROOT / "godot-ed1daf0bf"
EDITOR = ENGINE_ROOT / "runtime" / "Godot.4.7.2.offline.exe"
TEMPLATES = PROJECT.parent / "polo-balls-tools" / "protected-export"
RELEASE = TEMPLATES / "windows_release_x86_64.exe"
PRESET = "Windows Desktop"
EXCLUDED = ('addons/csvedit/*', 'addons/com.timothyqiu.animation-resetter/*', 'addons/gdfxr/*', 'addons/offline_record_launcher/*', "tests/*", "tools/*", "rl_env/*", "rl_training/*", "art_sources/*", "sources/*", "export_presets.cfg", "export_credentials.cfg", "*.py", "*.ps1", "*.cmd", "*.bat", "*.key", "*.pdb", "*.log", "*.bak", "*.before", "AGENTS.md", "MCP_CONTEXT.md")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def private_key_path():
    require(os.name == "nt", "The keyed export is configured for Windows only.")
    return Path(os.environ["LOCALAPPDATA"]) / "PoloBalls" / "ProtectedExport" / "windows-aes256.key"


def read_key(path=None):
    path = Path(path) if path else private_key_path()
    require(path.is_file(), "Private export key missing. Restore it; do not silently generate a different key.")
    key = path.read_text(encoding="ascii").strip()
    require(bool(re.fullmatch(r"[0-9a-fA-F]{64}", key)) and int(key, 16) != 0, "Invalid private export key.")
    return key.lower()


def initialize_key():
    path = private_key_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    user = subprocess.check_output(["whoami"], text=True).strip()
    subprocess.run(["icacls", str(path.parent), "/inheritance:r", "/grant:r", user + ":(OI)(CI)F", "*S-1-5-18:(OI)(CI)F"], check=True, stdout=subprocess.DEVNULL)
    if not path.exists():
        with path.open("x", encoding="ascii") as stream:
            stream.write(secrets.token_hex(32))
    return read_key(path)


def section_values(text, name):
    match = re.search(r"(?ms)^\[" + re.escape(name) + r"\]\s*\n(.*?)(?=^\[|\Z)", text)
    require(match is not None, "Missing configuration section: " + name)
    return dict(re.findall(r"(?m)^([^;\s][^=\n]*)=(.*)$", match[1]))


def validate_preset(text):
    config = section_values(text, "preset.0")
    options = section_values(text, "preset.0.options")
    expected = {"name": '"Windows Desktop"', "platform": '"Windows Desktop"', "encrypt_pck": "true", "encrypt_directory": "true", "encryption_include_filters": '"*"', "encryption_exclude_filters": '""', "script_export_mode": "2", "seed": "0"}
    for name, value in expected.items():
        require(config.get(name) == value, "Unsafe or unsupported export setting: " + name)
    filters = {x.strip() for x in config.get("exclude_filter", "").strip('"').split(",")}
    require(set(EXCLUDED) <= filters, "Development files are not excluded from export.")
    require(options.get("binary_format/embed_pck") == "false", "The verifier requires a separate encrypted PCK.")
    require(options.get("custom_template/release") == '"../polo-balls-tools/protected-export/windows_release_x86_64.exe"', "Wrong release template.")
    require(options.get("binary_format/architecture") == '"x86_64"', "Wrong template architecture.")


def command(args, env=None, cwd=PROJECT, timeout=None):
    result = subprocess.run([str(x) for x in args], cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    text = result.stdout.decode("utf-8", errors="replace")
    if env:
        for name in ("SCRIPT_AES256_ENCRYPTION_KEY", "GODOT_SCRIPT_ENCRYPTION_KEY"):
            if env.get(name):
                text = text.replace(env[name], "[REDACTED]")
    return result.returncode, text


def install_template(key):
    compiled = SOURCE / "bin" / "godot.windows.template_release.x86_64.exe"
    require(compiled.exists(), "Build the release template first.")
    require(bytes.fromhex(key) in compiled.read_bytes(), "Compiled template does not contain this project's key.")
    TEMPLATES.mkdir(parents=True, exist_ok=True)
    shutil.copy2(compiled, RELEASE)
    # The custom-template exporter expects architecture-suffixed SDK names.
    for name in ("D3D12Core", "d3d12SDKLayers"):
        shutil.copy2(SOURCE / "bin" / (name + ".dll"), TEMPLATES / (name + ".x86_64.dll"))
    for name in ("LICENSE.txt", "COPYRIGHT.txt"):
        shutil.copy2(SOURCE / name, TEMPLATES / name)
    files = [RELEASE.name, "D3D12Core.x86_64.dll", "d3d12SDKLayers.x86_64.dll", "LICENSE.txt", "COPYRIGHT.txt"]
    metadata = {"key_fingerprint": hashlib.sha256(bytes.fromhex(key)).hexdigest(), "engine_patch_sha256": sha(PROJECT / "tools/offline_engine/engine.patch"), "target": "template_release", "files": {name: sha(TEMPLATES / name) for name in files}}
    (TEMPLATES / "template_manifest.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("Installed keyed Windows release template (key is not printed).")


def validate_template(key):
    path = TEMPLATES / "template_manifest.json"
    require(path.is_file(), "Keyed template missing. Run the build command first.")
    metadata = json.loads(path.read_text(encoding="utf-8"))
    require(metadata["key_fingerprint"] == hashlib.sha256(bytes.fromhex(key)).hexdigest(), "Key/template mismatch; rebuild rather than exporting an unusable game.")
    require(metadata["engine_patch_sha256"] == sha(PROJECT / "tools/offline_engine/engine.patch"), "Offline recording engine patch changed; rebuild the template.")
    require(RELEASE.name in metadata["files"], "Missing template hash.")
    for name, digest in metadata["files"].items():
        require(Path(name).name == name, "Invalid template manifest path.")
        require((TEMPLATES / name).is_file() and sha(TEMPLATES / name) == digest, "Template file mismatch: " + name)


def configure_editor_credentials(key):
    # Godot stores secrets here, separately from the tracked export preset.
    path = PROJECT / ".godot/export_credentials.cfg"
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    match = re.search(r"(?ms)^\[preset\.0\]\s*\n(.*?)(?=^\[|\Z)", old)
    value = 'script_encryption_key="' + key + '"\n'
    if match:
        body = re.sub(r"(?m)^script_encryption_key=.*\n?", "", match[1])
        new = old[:match.start(1)] + body.rstrip() + "\n" + value + "\n" + old[match.end(1):]
    else:
        new = old.rstrip() + "\n\n[preset.0]\n" + value
    path.parent.mkdir(parents=True, exist_ok=True)
    require(not path.exists() or path.read_text(encoding="utf-8") == old, "Credentials changed concurrently.")
    path.write_text(new, encoding="utf-8")


def build(jobs):
    key = initialize_key()
    require(SOURCE.is_dir(), "Install the pinned offline engine source using tools/offline_engine/build.ps1 first.")
    subprocess.run(["git", "apply", "--reverse", "--check", str(PROJECT / "tools/offline_engine/engine.patch")], cwd=SOURCE, check=True)
    env = os.environ.copy()
    env["SCRIPT_AES256_ENCRYPTION_KEY"] = key
    env["PYTHONPATH"] = str(ENGINE_ROOT / "python")
    args = [sys.executable, "-m", "SCons", "platform=windows", "target=template_release", "arch=x86_64", "d3d12=yes", "production=yes", "lto=none", "debug_symbols=no", "disable_path_overrides=yes", "accesskit=no", "-j" + str(jobs)]
    with subprocess.Popen(args, cwd=SOURCE, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
        for line in iter(process.stdout.readline, b""):
            print(line.decode("utf-8", errors="replace").replace(key, "[REDACTED]"), end="", flush=True)
        require(process.wait() == 0, "Template compilation failed.")
    install_template(key)
    configure_editor_credentials(key)


VERIFY_GD = r'''extends SceneTree
var failed := false
var scratch := ""
var key := PackedByteArray()
func check(value:bool, message:String) -> bool:
    if not value:
        failed = true
        printerr("VERIFY_FAIL: "+message)
    return value
func decrypt(file:FileAccess, offset:int) -> PackedByteArray:
    file.seek(offset)
    var digest:PackedByteArray = file.get_buffer(16)
    var size:int = file.get_64()
    var iv:PackedByteArray = file.get_buffer(16)
    if not check(size>=0 and size<file.get_length(), "invalid encrypted length"): return PackedByteArray()
    var padded:int = size + ((16-size%16)%16)
    var output := FileAccess.open(scratch,FileAccess.WRITE)
    output.store_32(0x43454447)
    output.store_buffer(digest)
    output.store_64(size)
    output.store_buffer(iv)
    output.store_buffer(file.get_buffer(padded))
    output.close()
    var decoded := FileAccess.open_encrypted(scratch,FileAccess.READ,key)
    if not check(decoded!=null,"encrypted payload integrity"): return PackedByteArray()
    var data := decoded.get_buffer(decoded.get_length())
    decoded.close()
    return data
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if not check(args.size()==2,"pack and private key path required"):
        quit(1)
        return
    scratch = get_script().resource_path.get_base_dir().path_join("encrypted-payload.tmp")
    key = FileAccess.get_file_as_string(args[1]).strip_edges().hex_decode()
    var file := FileAccess.open(args[0],FileAccess.READ)
    if not check(file!=null,"open pack"):
        quit(1)
        return
    check(file.get_32()==0x43504447,"PCK magic")
    var version:int = file.get_32()
    check(version==4 or version==3,"supported PCK version")
    file.get_32(); file.get_32(); file.get_32()
    check((file.get_32()&1)!=0,"encrypted directory flag")
    var base:int = file.get_64()
    var directory:int = file.get_64()
    file.seek(directory)
    var count:int = file.get_32()
    check(count>0 and count<1000000,"directory count")
    var stream := StreamPeerBuffer.new()
    stream.data_array = decrypt(file,directory+4)
    if failed:
        quit(1)
        return
    var scripts := 0
    var samples := 0
    var has_game := false
    var has_project := false
    for i in count:
        var length:int = stream.get_u32()
        if not check(length>0 and length<65536,"path length"): break
        var path:String = stream.get_utf8_string(length)
        var offset:int = stream.get_u64()
        var size:int = stream.get_u64()
        stream.get_data(16)
        var flags:int = stream.get_u32()
        check((flags&1)!=0,"unencrypted entry: "+path)
        check(not path.begins_with("tests/") and not path.begins_with("tools/") and not path.begins_with("rl_env/") and not path.begins_with("rl_training/"),"development directory exported")
        check(not path.ends_with(".gd") and not path.ends_with(".py") and not path.ends_with(".key") and not path.ends_with(".pdb"),"source/private file exported: "+path)
        if path.ends_with(".gdc"): scripts+=1
        if path=="global/game.gdc":
            var data := decrypt(file,base+offset)
            has_game = check(data.size()==size and data.size()>4 and data.slice(0,4).get_string_from_ascii()=="GDSC","compiled game script")
            samples+=1
        if path=="project.binary":
            var data := decrypt(file,base+offset)
            has_project = check(data.size()==size and size>0,"project settings payload")
            samples+=1
        if path.ends_with("wither_boss.geo.json"):
            var data := decrypt(file,base+offset)
            check(JSON.parse_string(data.get_string_from_utf8()) is Dictionary,"runtime Bedrock JSON")
            samples+=1
    check(scripts>0 and has_game and has_project and samples>=3,"required encrypted runtime payloads")
    DirAccess.remove_absolute(scratch)
    if not failed: print("PACK_VERIFIED entries=%d scripts=%d samples=%d"%[count,scripts,samples])
    quit(1 if failed else 0)
'''


def verify_pack(pack, key_path=None):
    pack = Path(pack).resolve()
    require(pack.is_file(), "Encrypted PCK was not produced.")
    with pack.open("rb") as stream:
        header = stream.read(40)
    require(len(header) == 40 and header[:4] == b"GDPC", "Not a standalone PCK.")
    require(struct.unpack_from("<I", header, 20)[0] & 1, "PCK directory is not encrypted.")
    with tempfile.TemporaryDirectory(prefix="polo-pack-check-") as folder:
        temp = Path(folder)
        (temp / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        script = temp / "verify.gd"
        script.write_text(VERIFY_GD, encoding="utf-8")
        rc, text = command([EDITOR, "--headless", "--path", temp, "--script", script, "--", pack, key_path or private_key_path()], cwd=temp, timeout=180)
        require(rc == 0 and "PACK_VERIFIED" in text and "SCRIPT ERROR" not in text, "Pack verification failed:\n" + text[-10000:])
        print(next(line for line in text.splitlines() if "PACK_VERIFIED" in line))
        rc, text = command([EDITOR, "--headless", "--path", temp, "--main-pack", pack, "--quit-after", "1"], cwd=temp, timeout=30)
        # Godot may return 0 after rejecting a pack and falling back to an empty project.
        require("Can't open encrypted pack directory" in text and "Cannot open resource pack" in text, "Unkeyed engine did not reject this pack as expected (exit=" + str(rc) + "):\n" + text[-5000:])
        print("UNKEYED_ENGINE_REJECTED")


def copy_notices(output):
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=PROJECT).decode("utf-8").split("\0")
    for relative in files:
        name = Path(relative).name.upper()
        if name in ("SOURCE.JSON", "SOURCE_MANIFEST.JSON") or name.startswith(("LICENSE", "NOTICE", "COPYRIGHT")):
            source = PROJECT / relative
            if source.is_file():
                destination = output / "attributions" / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)


def export_release(output=None):
    key = read_key()
    validate_preset((PROJECT / "export_presets.cfg").read_text(encoding="utf-8"))
    validate_template(key)
    configure_editor_credentials(key)
    output = Path(output).resolve() if output else PROJECT.parent / "polo-balls-releases" / ("windows-protected-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    require(not output.exists(), "Output already exists; choose a new folder to avoid overwriting a release.")
    require(not output.is_relative_to(PROJECT), "Release output must stay outside the source project.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".protected-export-", dir=output.parent) as stage:
        work = Path(stage) / "game"
        work.mkdir()
        exe = work / "polo_balls.exe"
        env = os.environ.copy()
        env["GODOT_SCRIPT_ENCRYPTION_KEY"] = key
        rc, text = command([EDITOR, "--headless", "--path", PROJECT, "--export-release", PRESET, exe], env=env, timeout=1800)
        require(rc == 0 and exe.is_file() and "SCRIPT ERROR" not in text and "ERROR:" not in text, "Export failed; do not distribute this output folder:\n" + text[-14000:])
        verify_pack(exe.with_suffix(".pck"))
        for name in ("LICENSE.txt", "COPYRIGHT.txt"):
            shutil.copy2(TEMPLATES / name, work / ("GODOT_" + name))
        with tempfile.TemporaryDirectory(prefix="polo-startup-check-") as folder:
            runtime_env = os.environ.copy()
            runtime_env["APPDATA"] = str(Path(folder) / "Roaming")
            runtime_env["LOCALAPPDATA"] = str(Path(folder) / "Local")
            # Prewarming is asynchronous; avoid exiting before its resource workers finish.
            rc, text = command([exe, "--headless", "--max-fps", "60", "--quit-after", "1200"], env=runtime_env, cwd=work, timeout=180)
            require(rc == 0 and "SCRIPT ERROR" not in text and "ERROR:" not in text, "Release startup failed:\n" + text[-14000:])
        copy_notices(work)
        work.rename(output)
    print("RELEASE_STARTUP_OK")
    print("Encrypted Windows release: " + str(output))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "install", "export", "verify"))
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pack", type=Path)
    args = parser.parse_args()
    require(os.name == "nt", "This tool runs on the project's Windows build machine.")
    require(1 <= args.jobs <= 32, "Jobs must be between 1 and 32.")
    if args.action == "build":
        build(args.jobs)
    elif args.action == "install":
        key = read_key()
        install_template(key)
        configure_editor_credentials(key)
    elif args.action == "verify":
        require(args.pack is not None, "Pass --pack to verify.")
        verify_pack(args.pack)
    else:
        export_release(args.output)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print("Protected export stopped: " + str(exc), file=sys.stderr)
        sys.exit(1)
