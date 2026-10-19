import os
from pathlib import Path
import subprocess
import sys
import tempfile


def isolated_environment(directory):
    environment = dict(os.environ)
    for name in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "APPDATA", "LOCALAPPDATA"]:
        path = Path(directory) / name.lower()
        path.mkdir(parents=True, exist_ok=True)
        environment[name] = str(path)
    (Path(environment["XDG_STATE_HOME"]) / "wivrn/wivrn-dashboard").mkdir(parents=True, exist_ok=True)
    environment["VPX_CHECK_DATA_ROOT"] = str(Path(directory).resolve())
    for name in ["VPX_DECODE", "VPX_DECODE_SETTING", "VPX_MODE_SESSION", "VPX_WANT_XR", "VPX_XR_FALLBACK"]:
        environment.pop(name, None)
    return environment


def main():
    if len(sys.argv) == 1:
        sys.exit("Usage: python3 packaging/run_check.py <Godot arguments>")
    with tempfile.TemporaryDirectory(prefix="vpx-check-") as directory:
        result = subprocess.run([os.environ.get("GODOT", "godot"), *sys.argv[1:]], env=isolated_environment(directory))
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
