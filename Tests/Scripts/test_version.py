import importlib.util
from pathlib import Path
import unittest
import json
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("version", ROOT / "scripts/version.py")
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionTests(unittest.TestCase):
    def test_cli_defaults_to_patch_and_rejects_series_changes_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            script = root / "scripts/version.py"
            shutil.copy2(ROOT / "scripts/version.py", script)
            config = root / "Version.json"
            config.write_text(json.dumps({"version": "1.0.0", "build": 15, "minimumMacOS": "13.0"}))
            result = subprocess.run([sys.executable, str(script), "bump"], capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(config.read_text())["version"], "1.0.1")
            previous = config.read_bytes()
            for args in [["bump", "minor"], ["set", "2.0.0", "17"]]:
                result = subprocess.run([sys.executable, str(script), *args], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"--allow-series-change", result.stderr)
                self.assertEqual(config.read_bytes(), previous)

    def test_version_bumps_reset_lower_components_and_increase_build(self):
        value = {"version": "1.9.4", "build": 21, "minimumMacOS": "13.0"}
        for part, expected in [("patch", "1.9.5"), ("build", "1.9.4")]:
            changed = version.bump(value, part)
            self.assertEqual(changed["version"], expected)
            self.assertEqual(changed["build"], 22)
        self.assertEqual(value["version"], "1.9.4")

    def test_default_only_increases_last_component(self):
        value = {"version": "1.0.0", "build": 15, "minimumMacOS": "13.0"}
        self.assertEqual(version.bump(value)["version"], "1.0.1")
        self.assertEqual(version.bump(version.bump(value))["version"], "1.0.2")
        for part in ["major", "minor"]:
            with self.assertRaises(ValueError):
                version.bump(value, part)
        for text in ["1.1.0", "2.0.0"]:
            with self.assertRaises(ValueError):
                version.set_version(value, text, 16)
        self.assertEqual(version.set_version(value, "1.0.1", 16)["version"], "1.0.1")
        self.assertEqual(version.set_version(value, "2.0.0", 16, True)["version"], "2.0.0")
        self.assertEqual(version.bump(value, "minor", True)["version"], "1.1.0")
        with self.assertRaises(ValueError):
            version.set_version(value, "0.9.9", 16, True)
        with self.assertRaises(ValueError):
            version.set_version(value, "1.0.1", 15)

    def test_invalid_metadata_is_rejected(self):
        for text in ["1.2", "v1.2.3", "01.2.3", "1.2.3-01", "1.2.3+abc"]:
            with self.assertRaises(ValueError):
                version.validate({"version": text, "build": 1, "minimumMacOS": "13.0"})
        for build in [0, -1, True, "4"]:
            with self.assertRaises(ValueError):
                version.validate({"version": "1.0.0", "build": build, "minimumMacOS": "13.0"})

    def test_prerelease_and_source_version(self):
        self.assertEqual(version.validate({"version": "0.3.0-rc.1", "build": 15, "minimumMacOS": "13.0"})["version"], "0.3.0-rc.1")
        version.validate(__import__("json").loads((ROOT / "Version.json").read_text()))


if __name__ == "__main__":
    unittest.main()
