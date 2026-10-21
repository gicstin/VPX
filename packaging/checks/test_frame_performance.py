import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_check import isolated_environment


ROOT = Path(__file__).resolve().parents[2]


class FramePerformanceTests(unittest.TestCase):
    def test_frame_performance(self):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not godot:
            self.skipTest("Godot required")
        with tempfile.TemporaryDirectory(prefix="vpx-frame-performance-") as directory:
            report_path = Path(directory) / "measurements.json"
            command = [godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/frame_performance.gd", "--", str(report_path), "--desktop"]
            result = subprocess.run(command, env=isolated_environment(directory), capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            report = json.loads(report_path.read_text())
            self.assertEqual(report["failures"], 0, output)
            self.assertGreaterEqual(report["checks"], 4800, output)
            self.assertEqual(len(report["measurements"]), 12, output)
            print(result.stdout, end="", flush=True)

    def test_audio_capture(self):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not godot:
            self.skipTest("Godot required")
        with tempfile.TemporaryDirectory(prefix="vpx-audio-performance-") as directory:
            report_path = Path(directory) / "measurements.json"
            command = [godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/audio_performance.gd", "--", str(report_path)]
            result = subprocess.run(command, env=isolated_environment(directory), capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            report = json.loads(report_path.read_text())
            self.assertEqual(report["failures"], 0, output)
            self.assertGreaterEqual(report["checks"], 4600, output)
            self.assertEqual(len(report["measurements"]), 4, output)
            print(result.stdout, end="", flush=True)

    def test_scope_render(self):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not godot:
            self.skipTest("Godot required")
        if sys.platform.startswith("linux") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            self.skipTest("Display required")
        with tempfile.TemporaryDirectory(prefix="vpx-scope-render-") as directory:
            command = [godot, "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/scope_render_performance.gd", "--", "--desktop"]
            result = subprocess.run(command, env=isolated_environment(directory), capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            self.assertIn("scope_render_performance checks=30 failures=0", output, output)
            print(result.stdout, end="", flush=True)


if __name__ == "__main__":
    unittest.main()
