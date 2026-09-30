"""Release guard tests; integration fixtures stay in the system temporary directory."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import secrets
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("protected_export", ROOT / "tools/protected_export.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ExportGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")

    def test_current_preset(self):
        release.validate_preset(self.preset)

    def test_no_plain_pack(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace("encrypt_pck=true", "encrypt_pck=false"))

    def test_no_plain_directory(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace("encrypt_directory=true", "encrypt_directory=false"))

    def test_all_resources_encrypted(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace('encryption_include_filters="*"', 'encryption_include_filters="*.gd"'))

    def test_no_encryption_exceptions(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace('encryption_exclude_filters=""', 'encryption_exclude_filters="*.png"'))

    def test_no_text_scripts(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace("script_export_mode=2", "script_export_mode=0"))

    def test_no_development_files(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace("tests/*,", ""))

    def test_no_default_template(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace('../polo-balls-tools/protected-export/windows_release_x86_64.exe', ''))

    def test_no_seeded_repeated_iv(self):
        with self.assertRaises(RuntimeError):
            release.validate_preset(self.preset.replace("seed=0", "seed=42"))

    def test_missing_key_does_not_regenerate(self):
        with tempfile.TemporaryDirectory() as folder:
            key = Path(folder) / "missing.key"
            with self.assertRaises(RuntimeError):
                release.read_key(key)
            self.assertFalse(key.exists())

    def test_invalid_keys(self):
        with tempfile.TemporaryDirectory() as folder:
            key = Path(folder) / "test.key"
            for value in ("", "0" * 64, "z" * 64, "a" * 63):
                key.write_text(value, encoding="ascii")
                with self.subTest(length=len(value)):
                    with self.assertRaises(RuntimeError):
                        release.read_key(key)
            key.write_text("Ab" * 32, encoding="ascii")
            self.assertEqual(release.read_key(key), "ab" * 32)

    def test_credentials_preserve_other_presets(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / ".godot/export_credentials.cfg"
            path.parent.mkdir()
            path.write_text('[preset.0]\nother="keep"\nscript_encryption_key="old"\n\n[preset.1]\nother="also_keep"\n', encoding="utf-8")
            with patch.object(release, "PROJECT", root):
                release.configure_editor_credentials("ab" * 32)
                first = path.read_text(encoding="utf-8")
                release.configure_editor_credentials("ab" * 32)
                self.assertEqual(first, path.read_text(encoding="utf-8"))
                self.assertIn('other="keep"', first)
                self.assertIn('[preset.1]\nother="also_keep"', first)
                self.assertEqual(first.count("script_encryption_key="), 1)

    def test_reject_plain_pack_before_launching_engine(self):
        with tempfile.TemporaryDirectory() as folder:
            pack = Path(folder) / "test.pck"
            pack.write_bytes(b"GDPC" + struct.pack("<9I", 4, 4, 7, 2, 0, 0, 0, 0, 0))
            with self.assertRaisesRegex(RuntimeError, "not encrypted"):
                release.verify_pack(pack)

    def test_missing_template_stops(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(release, "TEMPLATES", Path(folder)):
            with self.assertRaisesRegex(RuntimeError, "template missing"):
                release.validate_template("ab" * 32)

    def test_template_mismatch_and_corruption(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            patch_file = root / "tools/offline_engine/engine.patch"
            patch_file.parent.mkdir(parents=True)
            patch_file.write_bytes(b"fixture patch")
            template = root / "windows_release_x86_64.exe"
            template.write_bytes(b"fixture template")
            metadata = {"key_fingerprint": hashlib.sha256(bytes.fromhex("ab"*32)).hexdigest(), "engine_patch_sha256": release.sha(patch_file), "files": {template.name:release.sha(template)}}
            (root / "template_manifest.json").write_text(json.dumps(metadata), encoding="utf-8")
            with patch.object(release,"TEMPLATES",root), patch.object(release,"PROJECT",root), patch.object(release,"RELEASE",template):
                release.validate_template("ab"*32)
                with self.assertRaisesRegex(RuntimeError,"Key/template mismatch"):
                    release.validate_template("cd"*32)
                template.write_bytes(b"changed")
                with self.assertRaisesRegex(RuntimeError,"file mismatch"):
                    release.validate_template("ab"*32)

    def test_failed_export_never_publishes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            project = root / "source"
            project.mkdir()
            (project / "export_presets.cfg").write_text(self.preset,encoding="utf-8")
            destination = root / "release"
            with patch.object(release,"PROJECT",project), patch.object(release,"read_key",return_value="ab"*32), patch.object(release,"validate_template"), patch.object(release,"configure_editor_credentials"), patch.object(release,"command",return_value=(1,"export failed")):
                with self.assertRaisesRegex(RuntimeError,"Export failed"):
                    release.export_release(destination)
            self.assertFalse(destination.exists())
            self.assertEqual(list(root.glob(".protected-export-*")),[])

    @unittest.skipUnless(os.name == "nt" and release.EDITOR.exists(), "Windows engine integration")
    def test_encrypted_pack_roundtrip_and_wrong_key(self):
        with tempfile.TemporaryDirectory(prefix="polo-pack-fixture-") as folder:
            temp = Path(folder)
            (temp / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            key = temp / "fixture.key"
            key.write_text(secrets.token_hex(32), encoding="ascii")
            script = temp / "fixture.gd"
            script.write_text('''extends SceneTree
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var folder := args[0]
    var key := FileAccess.get_file_as_string(folder.path_join("fixture.key")).strip_edges()
    var pck := PCKPacker.new()
    if pck.pck_start(folder.path_join("fixture.pck"),32,key,true)!=OK:
        quit(1)
        return
    var files := {"global/game.gdc":"GDSCfixture", "project.binary":"fixture", "Images/characters/我的世界/wither/bedrock/wither_boss.geo.json":"{}"}
    for path:String in files:
        var temporary := folder.path_join("payload.tmp")
        var file := FileAccess.open(temporary,FileAccess.WRITE)
        file.store_string(files[path])
        file.close()
        if pck.add_file(path,temporary,true)!=OK:
            quit(1)
            return
    quit(0 if pck.flush()==OK else 1)
''', encoding="utf-8")
            code, text = release.command([release.EDITOR, "--headless", "--path", temp, "--script", script, "--", temp], cwd=temp, timeout=90)
            self.assertEqual(code, 0, text)
            self.assertNotIn("SCRIPT ERROR", text)
            release.verify_pack(temp / "fixture.pck", key)
            key.write_text(secrets.token_hex(32), encoding="ascii")
            with self.assertRaisesRegex(RuntimeError, "verification failed"):
                release.verify_pack(temp / "fixture.pck", key)


if __name__ == "__main__":
    unittest.main(verbosity=2)
