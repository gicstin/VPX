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


class LibraryPerformanceTests(unittest.TestCase):
    def test_library_performance(self):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not godot:
            self.skipTest("Godot required")
        with tempfile.TemporaryDirectory(prefix="vpx-library-performance-") as directory:
            work = Path(directory)
            library = work / "library"
            library.mkdir()
            for index in range(10000):
                (library / f"clip_{index:05d}.mp4").touch()
            for index in range(32):
                folder = library / f"folder_{index:03d}"
                folder.mkdir()
                (folder / "clip.mp4").touch()
            report_path = work / "measurements.json"
            command = [godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/library_performance.gd", "--", str(library), str(report_path)]
            result = subprocess.run(command, env=isolated_environment(directory), capture_output=True, text=True, timeout=45)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output, output)
            self.assertNotIn("FAIL:", output, output)
            report = json.loads(report_path.read_text())
            self.assertEqual(report["failures"], 0, output)
            self.assertGreaterEqual(report["checks"], 5600, output)
            self.assertEqual(len(report["measurements"]), 12, output)
            print(result.stdout, end="", flush=True)


if __name__ == "__main__":
    unittest.main()
