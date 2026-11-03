import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError


spec = importlib.util.spec_from_file_location(
    "honk_versions", Path(__file__).with_name("resolve-honk-versions.py")
)
versions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versions)


class HonkVersionsTest(unittest.TestCase):
    def test_release_order_includes_prereleases_but_excludes_drafts_and_debug(self):
        releases = [{"tag_name": tag} for tag in (
            "v0.1.0-beta.9", "v0.1.0-beta.10", "debug.2099.1.1", "Debug"
        )]
        releases.append({"tag_name": "v99.0.0", "draft": True})
        self.assertEqual(versions.choose_release(releases), "v0.1.0-beta.10")
        releases.extend([{"tag_name": "v0.1.0-rc.1"}, {"tag_name": "v0.1.0"}])
        self.assertEqual(versions.choose_release(releases), "v0.1.0")
        releases.append({"tag_name": "v0.2.0-alpha.1"})
        self.assertEqual(versions.choose_release(releases), "v0.2.0-alpha.1")

    def test_no_versioned_release_fails_instead_of_using_debug(self):
        with self.assertRaises(ValueError):
            versions.choose_release([{"tag_name": "Debug"}])

    def test_release_api_pagination(self):
        with patch.object(versions, "fetch", side_effect=[
            versions.json.dumps([{"tag_name": "v0.1.0-beta.1"}] * 100),
            versions.json.dumps([{"tag_name": "v0.1.0-rc.1", "prerelease": True}]),
        ]) as fetch:
            self.assertEqual(versions.latest_release("owner/repo"), "v0.1.0-rc.1")
            self.assertIn("page=2", fetch.call_args.args[0])

    def test_rate_limit_uses_published_atom_tags(self):
        feed = '''<feed xmlns="http://www.w3.org/2005/Atom">
          <entry><title>Version with a descriptive title</title>
            <link href="https://github.com/owner/repo/releases/tag/v0.1.0-rc.4"/>
          </entry>
          <entry><link href="https://github.com/owner/repo/releases/tag/Debug"/></entry>
          <entry><link href="https://github.com/other/repo/releases/tag/v99.0.0"/></entry>
        </feed>'''
        error = HTTPError("https://api.github.com", 403, "rate limited", {}, None)
        with patch.object(versions, "fetch", side_effect=[error, feed]):
            self.assertEqual(versions.latest_release("owner/repo"), "v0.1.0-rc.4")

    def test_annotated_tag_resolves_to_commit_not_tag_object(self):
        tag_sha, commit_sha = "a" * 40, "b" * 40
        stdout = (f"{tag_sha}\trefs/tags/v0.1.0\n"
                  f"{commit_sha}\trefs/tags/v0.1.0^{{}}\n")
        with patch.object(versions.subprocess, "run", return_value=SimpleNamespace(stdout=stdout)):
            self.assertEqual(versions.tag_revision("owner/repo", "v0.1.0"), commit_sha)

    def test_checksum_requires_exact_filename_and_unique_valid_digest(self):
        filename, digest = "doona-0.1.0.tar.gz", "a" * 64
        sums = f"{'b' * 64}  doona-lite-0.1.0.tar.gz\n{digest} *./{filename}\n"
        self.assertEqual(versions.checksum_for(sums, filename), digest)
        for invalid in ("", f"bad  {filename}", sums + sums):
            with self.subTest(manifest=invalid), self.assertRaises(ValueError):
                versions.checksum_for(invalid, filename)

    def test_resolved_versions_include_matching_ui_assets_and_package_version(self):
        sums = (f"{'a' * 64}  doona-0.1.0-rc.4.tar.gz\n"
                f"{'b' * 64}  doona-lite-0.1.0-rc.4.tar.gz\n")
        with patch.object(versions, "latest_release", side_effect=["v0.1.0-beta.4", "v0.1.0-rc.4"]), \
             patch.object(versions, "fetch", return_value=sums), \
             patch.object(versions, "tag_revision", side_effect=["c" * 40, "d" * 40]):
            result = versions.resolve_versions()
        self.assertEqual(result["honk"]["package_version"], "0.1.0_beta4")
        self.assertEqual(result["doona"]["version"], "0.1.0-rc.4")
        self.assertEqual(result["doona"]["sha256"], "a" * 64)
        self.assertEqual(result["doona"]["lite_sha256"], "b" * 64)


if __name__ == "__main__":
    unittest.main()
