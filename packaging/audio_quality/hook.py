import json
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
STAMP = ROOT / "build" / "audio_quality" / "hook.stamp"
WATCHED = re.compile(
    r"(addons/ffmpeg/(vpx|resonance|audio-downmix|spatial-presets|stereo-spatial|audio-quality|post192|music-analysis)\.patch"
    r"|build/[^/]+/EIRTeam\.FFmpeg/(vpx_spatial_audio\.(cpp|h)|video_decoder\.cpp|ffmpeg_video_stream\.cpp)"
    r"|packaging/audio_quality/(?!baseline\.json)[^/]+\.py|packaging/audio_quality/(suites|native)/.+)$")


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    path = (payload.get("tool_input") or {}).get("file_path", "")
    if not path:
        return 0
    try:
        relative = str(Path(path).resolve().relative_to(ROOT))
    except ValueError:
        return 0
    if not WATCHED.search(relative) or relative.endswith("hook.py"):
        return 0
    STAMP.parent.mkdir(parents=True, exist_ok=True)
    if STAMP.exists() and time.time() - STAMP.stat().st_mtime < 8:
        return 0
    command = [sys.executable, str(HERE / "run.py"), "--quick"]
    tree = re.match(r"(build/[^/]+/EIRTeam\.FFmpeg)/", relative)
    if tree:
        command += ["--source", str(ROOT / tree.group(1))]
    result = subprocess.run(command, capture_output=True, text=True)
    STAMP.write_text(str(time.time()))
    if result.returncode == 0:
        return 0
    lines = [line for line in result.stdout.splitlines() if line.startswith(("FAIL", "      FAIL", "checks="))]
    sys.stderr.write("Audio quality suite failed after editing %s (run python3 packaging/audio_quality/run.py -v for detail):\n%s\n%s" % (relative, "\n".join(lines[:40]), result.stderr[-800:]))
    return 2


if __name__ == "__main__":
    sys.exit(main())
