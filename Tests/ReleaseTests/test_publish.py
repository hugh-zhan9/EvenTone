import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import Mock

path = Path(__file__).resolve().parents[2] / "scripts/publish_release.py"
spec = importlib.util.spec_from_file_location("publish_release", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublishTests(unittest.TestCase):
    sha = "a" * 40

    def ref(self, tag="v0.2.0", sha=None, kind="commit"):
        return [{"ref": f"refs/tags/{tag}", "object": {"sha": sha or self.sha, "type": kind}}]

    def release(self, draft=True):
        return {"id": 123, "tag_name": "v0.2.0", "draft": draft, "target_commitish": self.sha}

    def publish_api(self, moved=False):
        return Mock(side_effect=[[[]], self.ref(), [[self.release()]],
                                 self.ref(sha="b" * 40) if moved else self.ref()])

    def test_existing_lightweight_tag_matches(self):
        api = Mock(return_value=self.ref())
        module.ensure_tag("owner/repo", "v0.2.0", self.sha, False, api)
        self.assertEqual(api.call_count, 1)

    def test_annotated_tag_is_peeled(self):
        api = Mock(side_effect=[self.ref(sha="b" * 40, kind="tag"),
                               {"object": {"sha": self.sha, "type": "commit"}}])
        module.ensure_tag("owner/repo", "v0.2.0", self.sha, False, api)
        self.assertIn("git/tags/" + "b" * 40, api.call_args.args[0])

    def test_missing_preview_is_created_at_exact_commit_and_read_back(self):
        tag = "preview-aaaaaaaaaaaa"
        api = Mock(side_effect=[[], {}, self.ref(tag)])
        module.ensure_tag("owner/repo", tag, self.sha, True, api)
        self.assertIn(f"sha={self.sha}", api.call_args_list[1].args)
        self.assertEqual(api.call_count, 3)

    def test_missing_stable_or_wrong_commit_never_creates_tag(self):
        for refs in [[], self.ref(sha="b" * 40), self.ref(tag="v0.2.0-other")]:
            with self.subTest(refs=refs):
                api = Mock(return_value=refs)
                with self.assertRaises(ValueError):
                    module.ensure_tag("owner/repo", "v0.2.0", self.sha, False, api)
                self.assertEqual(api.call_count, 1)

    def test_api_failure_does_not_create_tag(self):
        api = Mock(side_effect=subprocess.CalledProcessError(1, "gh"))
        with self.assertRaises(subprocess.CalledProcessError):
            module.ensure_tag("owner/repo", "preview-aaaaaaaaaaaa", self.sha, True, api)
        self.assertEqual(api.call_count, 1)

    def test_success_uploads_as_draft_then_publishes(self):
        run = Mock()
        module.publish("owner/repo", "v0.2.0", "0.2.0", self.sha, False,
                       Path("assets"), self.publish_api(), run)
        self.assertIn("--draft", run.call_args_list[0].args[0])
        self.assertIn("--verify-tag", run.call_args_list[0].args[0])
        self.assertIn("repos/owner/repo/releases/123", run.call_args_list[1].args[0])
        self.assertIn("draft=false", run.call_args_list[1].args[0])

    def test_upload_failure_or_tag_movement_never_publishes(self):
        api = self.publish_api()
        run = Mock(side_effect=subprocess.CalledProcessError(1, "gh"))
        with self.assertRaises(subprocess.CalledProcessError):
            module.publish("owner/repo", "v0.2.0", "0.2.0", self.sha, False, Path("assets"), api, run)
        self.assertEqual(run.call_count, 1)
        api = self.publish_api(moved=True)
        run = Mock()
        with self.assertRaises(ValueError):
            module.publish("owner/repo", "v0.2.0", "0.2.0", self.sha, False, Path("assets"), api, run)
        self.assertEqual(run.call_count, 1)

    def test_existing_published_or_draft_on_later_page_blocks_creation(self):
        for draft in [False, True]:
            with self.subTest(draft=draft):
                api = Mock(return_value=[[], [self.release(draft)]])
                run = Mock()
                with self.assertRaises(ValueError):
                    module.publish("owner/repo", "v0.2.0", "0.2.0", self.sha, False, Path("assets"), api, run)
                run.assert_not_called()
                self.assertEqual(api.call_count, 1)

    def test_release_list_failure_blocks_creation(self):
        api = Mock(side_effect=subprocess.CalledProcessError(1, "gh"))
        run = Mock()
        with self.assertRaises(subprocess.CalledProcessError):
            module.publish("owner/repo", "v0.2.0", "0.2.0", self.sha, False, Path("assets"), api, run)
        run.assert_not_called()

    def test_ambiguous_new_draft_is_not_published(self):
        api = Mock(side_effect=[[[]], self.ref(), [[self.release(), self.release()]]])
        run = Mock()
        with self.assertRaises(ValueError):
            module.publish("owner/repo", "v0.2.0", "0.2.0", self.sha, False, Path("assets"), api, run)
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
