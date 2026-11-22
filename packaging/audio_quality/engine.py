import ctypes
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PATCHES = ROOT / "addons" / "ffmpeg"
PATCH_ORDER = ["vpx.patch", "resonance.patch", "audio-downmix.patch", "spatial-presets.patch", "stereo-spatial.patch"]
SOURCE_FILES = ["vpx_spatial_audio.cpp", "vpx_spatial_audio.h"]
BUILD = ROOT / "build" / "audio_quality"


def find_ffmpeg_prefix():
    candidates = []
    if os.environ.get("VPX_FFMPEG_PREFIX"):
        candidates.append(Path(os.environ["VPX_FFMPEG_PREFIX"]))
    candidates.append(ROOT / "build" / "linux" / "ffmpeg")
    for candidate in candidates:
        if (candidate / "include" / "libavutil" / "channel_layout.h").exists():
            return candidate
    result = subprocess.run(["pkg-config", "--variable=prefix", "libavutil"], capture_output=True, text=True)
    if result.returncode == 0:
        prefix = Path(result.stdout.strip())
        if (prefix / "include" / "libavutil" / "channel_layout.h").exists():
            return prefix
    raise RuntimeError("libavutil headers not found; set VPX_FFMPEG_PREFIX")


def _sections(text):
    lines = text.splitlines(keepends=True)
    starts = []
    for i, line in enumerate(lines):
        if line.startswith("diff --git "):
            starts.append(i)
        elif line.startswith("--- ") and i + 1 < len(lines) and lines[i + 1].startswith("+++ ") and not (starts and starts[-1] == i - 0 or (starts and i - starts[-1] <= 4 and any(l.startswith("diff --git ") for l in lines[starts[-1]:i]))):
            starts.append(i)
    starts.append(len(lines))
    for begin, end in zip(starts, starts[1:]):
        chunk = lines[begin:end]
        name = None
        for line in chunk:
            if line.startswith("+++ "):
                name = line[4:].strip().split("\t")[0]
                name = name[2:] if name.startswith("b/") else name
                break
        yield name, "".join(chunk)


def assemble_source(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name in SOURCE_FILES:
        target = directory / name
        if target.exists():
            target.unlink()
    for patch in PATCH_ORDER:
        wanted = "".join(chunk for name, chunk in _sections((PATCHES / patch).read_text()) if name in SOURCE_FILES)
        if not wanted:
            continue
        patch_file = directory / ("_" + patch)
        patch_file.write_text(wanted)
        result = subprocess.run(["patch", "-p1", "-N", "-s", "-d", str(directory), "-i", str(patch_file)], capture_output=True, text=True)
        patch_file.unlink()
        if result.returncode != 0:
            raise RuntimeError("cannot apply %s: %s%s" % (patch, result.stdout.strip(), result.stderr.strip()))
    for name in SOURCE_FILES:
        for leftover in directory.glob(name + ".*"):
            leftover.unlink()
    return directory


def source_digest(directory):
    digest = hashlib.sha256()
    for name in SOURCE_FILES:
        digest.update((directory / name).read_bytes())
    for path in sorted((HERE / "native").rglob("*")):
        if path.is_file():
            digest.update(path.read_bytes())
    return digest.hexdigest()[:16]


def compile_shared(source_dir, sanitize=False):
    prefix = find_ffmpeg_prefix()
    tag = source_digest(source_dir) + ("-san" if sanitize else "")
    out_dir = BUILD / tag
    library = out_dir / "libvsa.so"
    if library.exists():
        return library
    out_dir.mkdir(parents=True, exist_ok=True)
    command = ["g++", "-std=c++17", "-O2", "-fPIC", "-shared", "-DGDEXTENSION", "-Wall",
               "-I" + str(HERE / "native" / "stubs"), "-I" + str(source_dir), "-I" + str(prefix / "include"),
               str(HERE / "native" / "vsa.cpp"), str(source_dir / "vpx_spatial_audio.cpp"),
               "-o", str(library), "-L" + str(prefix / "lib"), "-lavutil", "-Wl,-rpath," + str(prefix / "lib")]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("harness build failed:\n" + result.stderr[-3000:])
    return library


def compile_fuzz(source_dir):
    prefix = find_ffmpeg_prefix()
    out_dir = BUILD / (source_digest(source_dir) + "-fuzz")
    binary = out_dir / "fuzz"
    if binary.exists():
        return binary
    out_dir.mkdir(parents=True, exist_ok=True)
    command = ["g++", "-std=c++17", "-O1", "-g", "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined", "-DGDEXTENSION",
               "-I" + str(HERE / "native" / "stubs"), "-I" + str(source_dir), "-I" + str(prefix / "include"),
               str(HERE / "native" / "fuzz.cpp"), str(source_dir / "vpx_spatial_audio.cpp"),
               "-o", str(binary), "-L" + str(prefix / "lib"), "-lavutil", "-Wl,-rpath," + str(prefix / "lib")]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("fuzz build failed:\n" + result.stderr[-3000:])
    return binary


class Engine:
    def __init__(self, source_dir=None):
        if source_dir is None:
            source_dir = assemble_source(BUILD / "source")
        self.source_dir = Path(source_dir)
        self.library_path = compile_shared(self.source_dir)
        self.lib = ctypes.CDLL(str(self.library_path))
        c_void_p, c_int, c_float, c_double, c_char_p = ctypes.c_void_p, ctypes.c_int, ctypes.c_float, ctypes.c_double, ctypes.c_char_p
        self.lib.vsa_new.restype = c_void_p
        self.lib.vsa_free.argtypes = [c_void_p]
        self.lib.vsa_configure.argtypes = [c_void_p, c_char_p, c_int]
        self.lib.vsa_set_param.argtypes = [c_void_p, c_char_p, c_double]
        self.lib.vsa_apply.argtypes = [c_void_p]
        self.lib.vsa_set_spatial.argtypes = [c_void_p, c_int]
        self.lib.vsa_set_mono.argtypes = [c_void_p, c_int]
        self.lib.vsa_set_dialogue.argtypes = [c_void_p, c_float]
        self.lib.vsa_set_listener.argtypes = [c_void_p, ctypes.POINTER(c_float)]
        self.lib.vsa_note_seek.argtypes = [c_void_p]
        self.lib.vsa_process.argtypes = [c_void_p, ctypes.POINTER(c_float), c_int, ctypes.POINTER(c_float)]
        self.lib.vsa_input_channels.argtypes = [c_void_p]
        self.lib.vsa_stereo_mode.argtypes = [c_void_p]
        self.lib.vsa_latency.argtypes = [c_void_p]
        self.lib.vsa_spatial_active.argtypes = [c_void_p]
        self.lib.vsa_describe.argtypes = [c_void_p]
        self.lib.vsa_describe.restype = c_char_p

    def new(self, layout="stereo", rate=48000, spatial=None, mono=None, dialogue=0.0, **params):
        return Renderer(self, layout, rate, spatial, mono, dialogue, params)


class Renderer:
    def __init__(self, engine, layout, rate, spatial, mono, dialogue, params):
        self.engine = engine
        self.lib = engine.lib
        self.handle = ctypes.c_void_p(self.lib.vsa_new())
        self.layout = layout
        self.rate = rate
        self.dirty = False
        for key, value in params.items():
            self._param(key, value)
        if params:
            self.lib.vsa_apply(self.handle)
        if spatial is not None:
            self.lib.vsa_set_spatial(self.handle, int(spatial))
        if mono is not None:
            self.lib.vsa_set_mono(self.handle, int(mono))
        if dialogue:
            self.lib.vsa_set_dialogue(self.handle, dialogue)
        self.channels = self.lib.vsa_configure(self.handle, layout.encode(), rate)
        if self.channels < 0:
            raise ValueError("bad layout " + layout)

    def __del__(self):
        handle = getattr(self, "handle", None)
        if handle is not None and getattr(self, "lib", None) is not None:
            self.lib.vsa_free(handle)

    def _param(self, key, value):
        if self.lib.vsa_set_param(self.handle, key.encode(), float(value)) != 0:
            raise KeyError(key)

    def set(self, **params):
        for key, value in params.items():
            self._param(key, value)
        self.lib.vsa_apply(self.handle)

    def spatial(self, on):
        self.lib.vsa_set_spatial(self.handle, int(on))

    def mono(self, on):
        self.lib.vsa_set_mono(self.handle, int(on))

    def dialogue(self, amount):
        self.lib.vsa_set_dialogue(self.handle, amount)

    def seek(self):
        self.lib.vsa_note_seek(self.handle)

    def listener_yaw(self, radians):
        c, s = np.cos(radians), np.sin(radians)
        rows = np.array([c, 0, s, 0, 1, 0, -s, 0, c], dtype=np.float32)
        self.lib.vsa_set_listener(self.handle, rows.ctypes.data_as(ctypes.POINTER(ctypes.c_float)))

    def describe(self):
        return self.lib.vsa_describe(self.handle).decode()

    def latency(self):
        return self.lib.vsa_latency(self.handle)

    def stereo_mode(self):
        return self.lib.vsa_stereo_mode(self.handle)

    def process(self, block):
        block = np.ascontiguousarray(block, dtype=np.float32)
        frames = block.shape[0]
        out = np.empty((frames, 2), dtype=np.float32)
        self.lib.vsa_process(self.handle, block.ctypes.data_as(ctypes.POINTER(ctypes.c_float)), frames,
                             out.ctypes.data_as(ctypes.POINTER(ctypes.c_float)))
        return out

    def run(self, x, block=1024, hooks=None):
        x = np.asarray(x, dtype=np.float32)
        if x.ndim == 1:
            x = x[:, None]
        if x.shape[1] == 1 and self.channels == 2:
            x = np.repeat(x, 2, axis=1)
        if x.shape[1] != self.channels:
            raise ValueError("input has %d channels, renderer expects %d" % (x.shape[1], self.channels))
        out = np.empty((x.shape[0], 2), dtype=np.float32)
        index = 0
        for start in range(0, x.shape[0], block):
            if hooks and index in hooks:
                hooks[index](self)
            stop = min(start + block, x.shape[0])
            out[start:stop] = self.process(x[start:stop])
            index += 1
        return out


def run_fuzz(source_dir, seeds, operations):
    binary = compile_fuzz(source_dir)
    failures = []
    for seed in seeds:
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:abort_on_error=0", UBSAN_OPTIONS="print_stacktrace=1")
        result = subprocess.run([str(binary), str(seed), str(operations)], capture_output=True, text=True, env=env)
        if result.returncode != 0:
            failures.append((seed, (result.stdout + result.stderr)[-1500:]))
    return failures
