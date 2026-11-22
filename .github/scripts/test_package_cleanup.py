"""Exercise feed replacement in disposable trees without cloning packages."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT_DIR = Path(__file__).resolve().parents[2]
BASH = shutil.which("bash")
if sys.platform == "win32":
    git = shutil.which("git")
    git_bash = Path(git).resolve().parents[1] / "bin/bash.exe" if git else None
    BASH = str(git_bash) if git_bash and git_bash.is_file() else None


@unittest.skipUnless(BASH, "Bash is required (Git Bash on Windows)")
class PackageCleanupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openwrt-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("feeds/luci", "feeds/packages", "package"):
            (self.root / directory).mkdir(parents=True)
        # Load the real function without running the production package list.
        source = (PROJECT_DIR / "Scripts/Packages.sh").read_text(encoding="utf-8")
        (self.root / "update-package.sh").write_text(
            source.split("# 调用示例", 1)[0], encoding="utf-8", newline="\n"
        )

    def directories(self, *paths):
        for path in paths:
            (self.root / path).mkdir(parents=True)

    def update(self, *args, git_exit=0):
        script = '''source ./update-package.sh
git() { printf '%s\\n' "$*" >> ./git-calls.txt; return "$TEST_GIT_EXIT"; }
UPDATE_PACKAGE "$@"
printf 'completed\\n'
'''
        return subprocess.run(
            [BASH, "-c", script, "package-test", *args], cwd=self.root,
            env={**os.environ, "TEST_GIT_EXIT": str(git_exit)},
            capture_output=True, text=True, encoding="utf-8", timeout=30,
        )

    def test_dae_replacement_keeps_unrelated_dependencies(self):
        replaced = (
            "feeds/packages/net/dae", "feeds/packages/net/daed",
            "feeds/packages/libs/vmlinux-btf", "feeds/luci/applications/luci-app-dae",
            "feeds/luci/applications/luci-app-daed", "feeds/luci/applications/luci-app-daede",
        )
        retained = (
            "feeds/packages/libs/libdaemon", "feeds/packages/lang/perl/perl-http-daemon",
            "feeds/packages/net/daemontools", "feeds/packages/net/dae-extra",
            "feeds/luci/applications/luci-app-daed-extra",
        )
        self.directories(*replaced, *retained)
        result = self.update(
            "luci-app-daede", "kenzok8/openwrt-daede", "main", "",
            "dae daed luci-app-dae luci-app-daed vmlinux-btf",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in replaced:
            self.assertFalse((self.root / path).exists(), path)
        for path in retained:
            self.assertTrue((self.root / path).is_dir(), path)

    def test_short_name_still_replaces_the_full_theme_directory(self):
        replaced = "feeds/luci/themes/luci-theme-vantage"
        retained = "feeds/luci/themes/luci-theme-vantage-extra"
        self.directories(replaced, retained)
        result = self.update("vantage", "anothaDev/luci-theme-vantage", "main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / replaced).exists())
        self.assertTrue((self.root / retained).is_dir())

    def test_explicit_aliases_replace_openappfilter_components(self):
        replaced = (
            "feeds/packages/net/open-app-filter", "feeds/packages/net/oaf",
            "feeds/luci/applications/luci-app-oaf", "feeds/luci/applications/luci-app-appfilter",
        )
        self.directories(*replaced)
        result = self.update(
            "destan19", "destan19/OpenAppFilter", "master", "",
            "luci-app-oaf luci-app-appfilter oaf open-app-filter",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in replaced:
            self.assertFalse((self.root / path).exists(), path)

    def test_clone_failure_stops_the_script_and_reports_the_command(self):
        result = self.update("quickfile", "sbwml/luci-app-quickfile", "main", git_exit=17)
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertNotIn("completed", result.stdout)
        self.assertIn("Packages: failed at", result.stderr)
        self.assertIn("exit 17", result.stderr)


if __name__ == "__main__":
    unittest.main()
