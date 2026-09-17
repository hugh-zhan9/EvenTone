import importlib.util
import unittest
from pathlib import Path

path = Path(__file__).resolve().parents[2] / "scripts/release_metadata.py"
spec = importlib.util.spec_from_file_location("release_metadata", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseMetadataTests(unittest.TestCase):
    sha = "a" * 40

    def result(self, event="push", ref="refs/heads/main", version="0.2.0", sha=None):
        return module.metadata({"CFBundleShortVersionString": version}, event, ref, sha or self.sha)

    def test_main_push_is_commit_scoped_prerelease(self):
        value = self.result()
        self.assertEqual(value["tag"], "preview-aaaaaaaaaaaa")
        self.assertEqual(value["label"], "0.2.0-preview.aaaaaaaaaaaa")
        self.assertEqual(value["publish"], "true")
        self.assertEqual(value["prerelease"], "true")

    def test_matching_tag_is_stable(self):
        value = self.result(ref="refs/tags/v0.2.0")
        self.assertEqual(value["tag"], "v0.2.0")
        self.assertEqual(value["label"], "0.2.0")
        self.assertEqual(value["publish"], "true")
        self.assertEqual(value["prerelease"], "false")

    def test_pull_request_manual_and_other_branches_never_publish(self):
        for event, ref in [("pull_request", "refs/pull/1/merge"),
                           ("pull_request_target", "refs/heads/main"),
                           ("workflow_dispatch", "refs/tags/v0.2.0"),
                           ("push", "refs/heads/feature")]:
            with self.subTest(event=event, ref=ref):
                self.assertEqual(self.result(event=event, ref=ref)["publish"], "false")

    def test_mismatched_or_malformed_tag_fails(self):
        for ref in ["refs/tags/v0.3.0", "refs/tags/v0.2.0-rc.1", "refs/tags/v0.2.0\nextra=1"]:
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                self.result(ref=ref)

    def test_invalid_version_and_sha_cannot_enter_outputs(self):
        for version in [None, "", "1.0", "0.2.0\npublish=true"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.result(version=version)
        with self.assertRaises(ValueError):
            self.result(sha="$(echo injected)")


if __name__ == "__main__":
    unittest.main()
