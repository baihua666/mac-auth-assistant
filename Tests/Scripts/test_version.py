import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("version", ROOT / "scripts/version.py")
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionTests(unittest.TestCase):
    def test_version_bumps_reset_lower_components_and_increase_build(self):
        value = {"version": "1.9.4", "build": 21, "minimumMacOS": "13.0"}
        for part, expected in [("major", "2.0.0"), ("minor", "1.10.0"), ("patch", "1.9.5"), ("build", "1.9.4")]:
            changed = version.bump(value, part)
            self.assertEqual(changed["version"], expected)
            self.assertEqual(changed["build"], 22)
        self.assertEqual(value["version"], "1.9.4")

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
