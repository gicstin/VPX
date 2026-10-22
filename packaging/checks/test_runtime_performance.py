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


class RuntimePerformanceTests(unittest.TestCase):
    def test_runtime_performance(self):
        self.run_case(True)

    def test_runtime_rendering(self):
        if sys.platform.startswith("linux") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            self.skipTest("Display required")
        self.run_case(False)

    def run_case(self, headless):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        ffmpeg = shutil.which("ffmpeg")
        if not godot or not ffmpeg:
            self.skipTest("Godot and FFmpeg required")
        with tempfile.TemporaryDirectory(prefix="vpx-runtime-performance-") as directory:
            report_path = Path(directory) / "measurements.json"
            fixture = Path(directory) / "video.mkv"
            subprocess.run([ffmpeg, "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=10", "-f", "lavfi", "-i", "sine=frequency=220", "-t", "3", "-c:v", "mpeg4", "-c:a", "pcm_s16le", str(fixture)], check=True, timeout=15)
            command = [godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/runtime_performance.gd", "--", str(report_path), str(fixture), "--desktop"]
            if not headless:
                command.remove("--headless")
            result = subprocess.run(command, env=isolated_environment(directory), capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            report = json.loads(report_path.read_text())
            self.assertEqual(report["failures"], 0, output)
            self.assertGreaterEqual(report["checks"], 18000, output)
            self.assertEqual(len(report["measurements"]), 12, output)
            for name in ["panel", "smoothing", "search"]:
                suffix = "_1000" if name == "search" else ""
                reference = report["measurements"][f"{name}_reference{suffix}"]["median_usec"]
                optimized = report["measurements"][f"{name}_optimized{suffix}"]["median_usec"]
                self.assertLess(optimized, reference, output)
            for name in ["player", "tracks", "screen"]:
                reference = report["measurements"][f"{name}_reference_idle"]["median_usec"]
                optimized = report["measurements"][f"{name}_idle"]["median_usec"]
                self.assertLess(optimized, reference * 1.15, output)
            print(result.stdout, end="", flush=True)


if __name__ == "__main__":
    unittest.main()
