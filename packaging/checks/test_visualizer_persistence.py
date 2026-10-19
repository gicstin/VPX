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


class VisualizerPersistenceTests(unittest.TestCase):
    def test_restart(self):
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        if not godot:
            self.skipTest("Godot required")
        with tempfile.TemporaryDirectory(prefix="vpx-preset-check-") as directory:
            environment = isolated_environment(directory)
            command = [godot, "--headless", "--path", str(ROOT), "--xr-mode", "off", "--audio-driver", "Dummy", "--script", "res://packaging/checks/visualizer_persistence.gd", "--"]
            for phase, preset in [("select", 73), ("restore", 73), ("cycle", 74), ("restore", 74), ("disable", 74), ("disabled", 74)]:
                result = subprocess.run(command + [phase, str(preset)], env=environment, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("SCRIPT ERROR", result.stderr)
            settings_path = Path(directory) / "xdg_data_home/godot/app_userdata/VPX/settings.cfg"
            if not settings_path.exists():
                settings_path = next(Path(directory).rglob("settings.cfg"))
            saved = settings_path.read_bytes()
            environment.pop("VPX_CHECK_DATA_ROOT")
            for script in ["checks/music_visualizer.gd", "checks/studio_visualizers.gd", "checks/visualizer_channels.gd", "checks/visualizer_volume.gd", "checks/visualizer_music.gd", "checks/visualizer_response.gd", "generate_visualizer_previews.gd"]:
                rejected = command[:command.index("--script")] + ["--script", "res://packaging/" + script]
                result = subprocess.run(rejected, env=environment, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("protect player settings", result.stderr)
                self.assertEqual(settings_path.read_bytes(), saved)


if __name__ == "__main__":
    unittest.main()
