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


class PipelinePerformanceTests(unittest.TestCase):
    def test_pipeline_performance(self):
        self.run_case(True)

    def test_pipeline_rendering(self):
        if sys.platform.startswith("linux") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            self.skipTest("Display required")
        self.run_case(False)

    def run_case(self, headless):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not godot:
            self.skipTest("Godot required")
        with tempfile.TemporaryDirectory(prefix="vpx-pipeline-performance-") as directory:
            report_path = Path(directory) / "measurements.json"
            command = [godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/pipeline_performance.gd", "--", str(report_path)]
            if not headless:
                command.remove("--headless")
            result = subprocess.run(command, env=isolated_environment(directory), capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            report = json.loads(report_path.read_text())
            self.assertEqual(report["failures"], 0, output)
            self.assertGreaterEqual(report["checks"], 4700, output)
            self.assertEqual(len(report["measurements"]), 10, output)
            for name, tolerance in [("spectral", 0.75), ("history", 1.15), ("stereo_rows", 1.15), ("stereo_update", 1.15), ("remote_idle", 0.6)]:
                reference = report["measurements"][f"{name}_reference"]["median_usec"]
                optimized = report["measurements"][f"{name}_optimized"]["median_usec"]
                self.assertLess(optimized, reference * tolerance, output)
            print(result.stdout, end="", flush=True)


if __name__ == "__main__":
    unittest.main()
