import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET


PACKAGING = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGING))
from release_version import latest_version, stamp_project

SPEC = importlib.util.spec_from_file_location("publish_release", PACKAGING / "publish-release.py")
PUBLISH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLISH)


class PublishReleaseTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root / "scripts").mkdir()
        (self.root / "scripts/log.gd").write_text("const BUILD := 202\n")
        self.changelog = self.root / "CHANGELOG.md"
        self.changelog.write_text(
            "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- Future work.\n\n"
            "## [0.0.1] - 2026-10-18\n\nInitial public release.\n\n### Added\n\n- Player.\n"
        )
        self.output = io.StringIO()
        self.addCleanup(patch.stopall)
        patch.object(PUBLISH, "ROOT", self.root).start()
        patch.object(PUBLISH.sys, "platform", "linux").start()
        patch.object(PUBLISH.os, "uname", return_value=type("Host", (), {"machine": "x86_64"})()).start()
        self.run = patch.object(PUBLISH.subprocess, "run", side_effect=self.command).start()
        self.source = patch.object(PUBLISH, "source_commit", return_value="a" * 40).start()
        self.preflight = patch.object(PUBLISH, "github_preflight").start()
        patch.object(PUBLISH.shutil, "which", return_value="/usr/bin/gh").start()
        self.upload = None

    def command(self, command, **kwargs):
        if command[0] == "bash":
            env = kwargs["env"]
            self.assertEqual(env["VPX_VERSION"], "0.0.1")
            self.assertEqual(env["VPX_BUILD_NUMBER"], "202")
            self.assertNotIn("VPX_BUILD_DIR", env)
            dist = Path(env["VPX_DIST_DIR"])
            if "windows" in command[1]:
                (dist / "VPX-0.0.1-windows-x86_64.exe").write_bytes(b"MZwindows")
            else:
                (dist / "VPX-0.0.1-x86_64.AppImage").write_bytes(b"\x7fELFlinux")
        elif command[:3] == ["gh", "release", "create"]:
            self.upload = command
            assets = [Path(path) for path in command[4:7]]
            self.assertEqual([path.name for path in assets], [*PUBLISH.ASSETS.values(), "SHA256SUMS.txt"])
            self.assertEqual(assets[0].read_bytes(), b"MZwindows")
            self.assertEqual(assets[1].read_bytes(), b"\x7fELFlinux")
            self.assertIn("VPX-linux-x86_64.AppImage", assets[2].read_text())
            notes = Path(command[command.index("--notes-file") + 1]).read_text()
            self.assertIn("Initial public release.", notes)
            self.assertNotIn("Future work", notes)
        return subprocess.CompletedProcess(command, 0)

    def invoke(self, *options):
        with contextlib.redirect_stdout(self.output), contextlib.redirect_stderr(self.output):
            return PUBLISH.main(["--changelog", str(self.changelog), "--dist", str(self.root / "dist"), *options])

    def test_build_and_publish_uses_changelog_and_exact_commit(self):
        with patch.dict(os.environ, {"VPX_BUILD_DIR": "/wrong/shared/cache"}):
            self.assertEqual(self.invoke("--build", "-j", "3"), 0, self.output.getvalue())
        self.preflight.assert_called_once_with("gicstin/VPX", "v0.0.1", "a" * 40)
        self.assertEqual(self.source.call_count, 2)
        self.assertEqual(self.upload[3], "v0.0.1")
        self.assertEqual(self.upload[self.upload.index("--target") + 1], "a" * 40)
        self.assertIn("--latest", self.upload)
        self.assertNotIn("--verify-tag", self.upload)
        self.assertTrue((self.root / "dist/v0.0.1/VPX-0.0.1-windows-x86_64.exe").exists())
        self.assertEqual(self.run.call_args_list[0].args[0][-2:], ["-j", "3"])

    def test_preview_neither_builds_nor_contacts_github(self):
        self.assertEqual(self.invoke("--build", "--dry-run"), 0)
        self.run.assert_not_called()
        self.preflight.assert_not_called()
        self.source.assert_not_called()
        self.assertFalse((self.root / "dist").exists())

    def test_local_build_does_not_require_clean_sources_or_github(self):
        self.assertEqual(self.invoke("--build-only"), 0)
        self.preflight.assert_not_called()
        self.source.assert_not_called()
        self.assertIsNone(self.upload)
        self.assertEqual(self.run.call_count, 2)

    def test_compile_failure_stops_before_upload(self):
        self.run.side_effect = subprocess.CalledProcessError(1, ["bash", "build"])
        self.assertEqual(self.invoke("--build"), 1)
        self.assertIsNone(self.upload)
        self.assertEqual(self.run.call_count, 1)

    def test_missing_build_output_cannot_reuse_stale_package(self):
        dist = self.root / "dist/v0.0.1"
        dist.mkdir(parents=True)
        stale = dist / "VPX-0.0.1-windows-x86_64.exe"
        stale.write_bytes(b"MZstale")
        self.run.side_effect = lambda command, **kwargs: subprocess.CompletedProcess(command, 0)
        self.assertEqual(self.invoke("--build"), 1)
        self.assertFalse(stale.exists())
        self.assertIsNone(self.upload)

    def test_source_change_aborts_upload(self):
        self.source.side_effect = ["a" * 40, "b" * 40]
        self.assertEqual(self.invoke("--build"), 1)
        self.assertIsNone(self.upload)

    def test_preflight_failure_prevents_expensive_build(self):
        self.preflight.side_effect = ValueError("wrong tag")
        self.assertEqual(self.invoke("--build"), 1)
        self.run.assert_not_called()

    def test_draft_keeps_latest_release(self):
        self.assertEqual(self.invoke("--build", "--draft"), 0)
        self.assertIn("--draft", self.upload)
        self.assertIn("--latest=false", self.upload)

    def test_real_changelog_initial_release_is_valid(self):
        notes = PUBLISH.release_notes(PACKAGING.parent / "CHANGELOG.md", "0.0.1")
        self.assertIn("Initial public release.", notes)
        self.assertIn("### Added", notes)

    def test_version_ignores_unreleased_notes(self):
        self.assertEqual(latest_version(self.changelog), "0.0.1")

    def test_stamp_changes_only_staged_application_version(self):
        project = self.root / "project.godot"
        project.write_text('[application]\nconfig/name="VPX"\nconfig/version="old"\n\n[other]\nconfig/version="other"\n')
        stamp_project(self.root, "0.0.1-rc.1+build.202")
        stamp_project(self.root, "0.0.1")
        text = project.read_text()
        self.assertEqual(text.count('config/version="0.0.1"'), 1)
        self.assertNotIn('config/version="old"', text)
        self.assertIn('[other]\nconfig/version="other"', text)

    def test_rider_configurations_call_wrapper(self):
        if not (PACKAGING.parent / ".run").is_dir():
            self.skipTest("Local Rider configurations are absent")
        for name, options in [("Publish VPX release", ""), ("Preview VPX release", "--dry-run"), ("Build VPX release locally", "--build-only")]:
            xml = ET.parse(PACKAGING.parent / ".run" / f"{name}.run.xml")
            settings = {item.attrib["name"]: item.attrib["value"] for item in xml.findall(".//option")}
            self.assertEqual(settings["SCRIPT_PATH"], "$PROJECT_DIR$/packaging/publish.sh")
            self.assertEqual(settings["SCRIPT_OPTIONS"], options)


class GitHubPreflightTest(unittest.TestCase):
    def test_checks_commit_and_accepts_matching_annotated_tag(self):
        commit = "a" * 40
        refs = f"{'b' * 40}\trefs/tags/v0.0.1\n{commit}\trefs/tags/v0.0.1^{{}}\n"
        with patch.object(PUBLISH.subprocess, "run"), patch.object(PUBLISH.subprocess, "check_output", side_effect=[commit, refs, ""]):
            PUBLISH.github_preflight("gicstin/VPX", "v0.0.1", commit)

    def test_rejects_conflicting_tag(self):
        with patch.object(PUBLISH.subprocess, "run"), patch.object(PUBLISH.subprocess, "check_output", side_effect=["a" * 40, f"{'b' * 40}\trefs/tags/v0.0.1\n"]):
            with self.assertRaisesRegex(ValueError, "another commit"):
                PUBLISH.github_preflight("gicstin/VPX", "v0.0.1", "a" * 40)

    def test_rejects_existing_release(self):
        with patch.object(PUBLISH.subprocess, "run"), patch.object(PUBLISH.subprocess, "check_output", side_effect=["a" * 40, "", "v0.0.1\n"]):
            with self.assertRaisesRegex(ValueError, "already exists"):
                PUBLISH.github_preflight("gicstin/VPX", "v0.0.1", "a" * 40)

    def test_dirty_tree_rejected(self):
        with patch.object(PUBLISH, "git_output", return_value=" M CHANGELOG.md"):
            with self.assertRaisesRegex(ValueError, "working tree"):
                PUBLISH.source_commit()


if __name__ == "__main__":
    unittest.main()
