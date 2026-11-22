import re
import shutil
import subprocess
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PATCHES = ROOT / "addons" / "ffmpeg"


def ffmpeg_binary():
    project = ROOT / "build" / "linux" / "ffmpeg" / "bin" / "ffmpeg"
    if project.exists():
        return str(project)
    return shutil.which("ffmpeg")


def patch_text(*names):
    return "".join((PATCHES / name).read_text() for name in names if (PATCHES / name).exists())


def loudness_chains():
    text = patch_text("vpx.patch", "post192.patch")
    compressors = re.findall(r'chain\.push_back\("(acompressor=[^"]+)"\)', text)
    limiters = re.findall(r'chain\.push_back\("(alimiter=[^"]+)"\)', text)
    return {"even_out": [compressors[0], limiters[0]], "night": [compressors[1], limiters[1]]}


def tempo_chain(kind, tempo, loudness_filter=0):
    text = patch_text("vpx.patch", "post192.patch", "audio-quality.patch")
    if kind == "atempo":
        return "atempo=%f" % tempo
    template = re.findall(r'"(rubberband=tempo=%f[^"]*)"', text)[-1]
    parts = [template.replace("%f", "%f" % tempo)]
    extra = patch_text("audio-quality.patch")
    volume = re.search(r'chain\.push_back\("(volume=[^"]+)"\)', extra)
    if volume:
        parts.append(volume.group(1))
    limiter = re.search(r'chain\.push_back\("(alimiter=limit=0\.98[^"]*)"\)', extra)
    if limiter and loudness_filter == 0:
        parts.append(limiter.group(1))
    return ",".join(parts)


def resample_options():
    extra = patch_text("audio-quality.patch")
    size = re.search(r'"filter_size", (\d+)', extra)
    cutoff = re.search(r'"cutoff", ([0-9.]+)', extra)
    options = ""
    if size:
        options += ":filter_size=" + size.group(1)
    if cutoff:
        options += ":cutoff=" + cutoff.group(1)
    return options


def has_filter(name):
    result = subprocess.run([ffmpeg_binary(), "-hide_banner", "-filters"], capture_output=True, text=True)
    return re.search(r"\b%s\b" % name, result.stdout) is not None


def apply(x, chain, rate=48000, out_rate=None):
    x = np.ascontiguousarray(x, dtype=np.float32)
    if x.ndim == 1:
        x = x[:, None]
    channels = x.shape[1]
    command = [ffmpeg_binary(), "-v", "error", "-f", "f32le", "-ar", str(rate), "-ac", str(channels), "-i", "-",
               "-af", chain, "-f", "f32le", "-ar", str(out_rate or rate), "-ac", str(channels), "-"]
    result = subprocess.run(command, input=x.tobytes(), capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode()[-500:])
    return np.frombuffer(result.stdout, dtype=np.float32).reshape(-1, channels).copy()
