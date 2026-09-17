import hashlib
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "dist/EvenTone.app"


class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with (APP / "Contents/Info.plist").open("rb") as source:
            cls.version = plistlib.load(source)["CFBundleShortVersionString"]

    def run_package(self, app, output, label, success=True):
        result = subprocess.run([str(ROOT / "scripts/package.sh"), str(app), str(output), label],
                                capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_zip_checksum_signature_spaces_and_no_overwrite(self):
        with tempfile.TemporaryDirectory(prefix="EvenTone package test ") as directory:
            root = Path(directory)
            copied = root / "input with spaces/EvenTone.app"
            subprocess.run(["ditto", str(APP), str(copied)], check=True)
            output = root / "output with spaces"
            label = self.version + "-preview.aaaaaaaaaaaa"
            self.run_package(copied, output, label)
            archive = output / f"EvenTone-{label}-macOS-arm64.zip"
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            self.assertEqual((output / "SHA256SUMS.txt").read_text(), f"{digest}  {archive.name}\n")
            unpacked = root / "unpacked"
            subprocess.run(["ditto", "-x", "-k", str(archive), str(unpacked)], check=True)
            subprocess.run(["codesign", "--verify", "--deep", "--strict",
                            str(unpacked / "EvenTone.app")], check=True)
            self.run_package(copied, output, label, success=False)
            self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), digest)

    def test_stable_package(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_package(APP, directory, self.version)
            self.assertTrue((Path(directory) / f"EvenTone-{self.version}-macOS-arm64.zip").is_file())

    def test_missing_app_and_invalid_labels_do_not_create_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output"
            for app, label in [(root / "missing.app", self.version), (APP, "../escape"),
                               (APP, "9999.9999.9999"), (APP, self.version + "\ninjected")]:
                with self.subTest(app=app, label=label):
                    self.run_package(app, output, label, success=False)
                    self.assertFalse(output.exists())

    def test_modified_app_signature_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            copied = root / "EvenTone.app"
            subprocess.run(["ditto", str(APP), str(copied)], check=True)
            with (copied / "Contents/MacOS/EvenTone").open("ab") as binary:
                binary.write(b"invalid signature")
            self.run_package(copied, root / "output", self.version, success=False)
            self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
