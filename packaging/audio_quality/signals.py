import os
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal

FS = 48000


def db_to_gain(db):
    return 10.0 ** (db / 20.0)


def sine(freq, seconds, level_db=-12.0, fs=FS, phase=0.0):
    t = np.arange(int(seconds * fs)) / fs
    return (db_to_gain(level_db) * np.sin(2 * np.pi * freq * t + phase)).astype(np.float32)


def white(seconds, level_rms_db=-30.0, fs=FS, seed=1):
    rng = np.random.default_rng(seed)
    x = rng.standard_normal(int(seconds * fs))
    return (x / x.std() * db_to_gain(level_rms_db)).astype(np.float32)


def pink(seconds, level_rms_db=-24.0, fs=FS, seed=2):
    n = int(seconds * fs)
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / fs)
    freqs[0] = freqs[1]
    spectrum /= np.sqrt(freqs)
    x = np.fft.irfft(spectrum, n)
    return (x / x.std() * db_to_gain(level_rms_db)).astype(np.float32)


def band_noise(low, high, seconds, level_rms_db=-24.0, fs=FS, seed=3):
    x = white(seconds, 0.0, fs, seed)
    sos = signal.butter(8, [low, high], btype="bandpass", fs=fs, output="sos")
    x = signal.sosfiltfilt(sos, x)
    return (x / x.std() * db_to_gain(level_rms_db)).astype(np.float32)


def two_tone(f1, f2, seconds, ratio=4.0, peak_db=-6.0, fs=FS):
    t = np.arange(int(seconds * fs)) / fs
    x = ratio * np.sin(2 * np.pi * f1 * t) + np.sin(2 * np.pi * f2 * t)
    return (x / (ratio + 1.0) * db_to_gain(peak_db)).astype(np.float32)


def log_sweep(f0, f1, seconds, level_db=-12.0, fs=FS):
    t = np.arange(int(seconds * fs)) / fs
    k = (f1 / f0) ** (1.0 / seconds)
    phase = 2 * np.pi * f0 * (k ** t - 1.0) / np.log(k)
    return (db_to_gain(level_db) * np.sin(phase)).astype(np.float32)


def impulse(n, position, amplitude=0.5):
    x = np.zeros(n, dtype=np.float32)
    x[position] = amplitude
    return x


def stereo(left, right=None):
    if right is None:
        right = left
    return np.stack([left, right], axis=1).astype(np.float32)


def _env(n, attack, decay, fs):
    t = np.arange(n) / fs
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def program(seconds, fs=FS, seed=7, peak_db=-3.0):
    n = int(seconds * fs)
    t = np.arange(n) / fs
    rng = np.random.default_rng(seed)
    notes = [196.0, 220.0, 246.9, 261.6, 293.7, 329.6, 293.7, 246.9]
    lead = np.zeros(n)
    for i, start in enumerate(np.arange(0.0, seconds, 0.5)):
        f0 = notes[i % len(notes)] * (1.0 + 0.004 * np.sin(2 * np.pi * 5.5 * t))[int(start * fs) if int(start * fs) < n else 0]
        length = min(int(0.48 * fs), n - int(start * fs))
        if length <= 0:
            continue
        tt = np.arange(length) / fs
        voice = sum(np.sin(2 * np.pi * f0 * h * tt) / h ** 1.3 for h in range(1, 18) if f0 * h < fs / 2 - 500)
        voice *= _env(length, 0.02, 0.35, fs)
        lead[int(start * fs):int(start * fs) + length] += voice
    formant = signal.butter(2, [600, 3200], btype="bandpass", fs=fs, output="sos")
    lead = signal.sosfilt(formant, lead) * 0.55 + lead * 0.15
    bass = np.zeros(n)
    for start in np.arange(0.0, seconds, 0.5):
        length = min(int(0.45 * fs), n - int(start * fs))
        if length <= 0:
            continue
        tt = np.arange(length) / fs
        f = 55.0 * (1.0 if int(start / 2) % 2 == 0 else 1.2)
        bass[int(start * fs):int(start * fs) + length] += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)) * _env(length, 0.005, 0.3, fs)
    kick = np.zeros(n)
    for start in np.arange(0.0, seconds, 0.5):
        length = min(int(0.2 * fs), n - int(start * fs))
        if length <= 0:
            continue
        tt = np.arange(length) / fs
        kick[int(start * fs):int(start * fs) + length] += np.sin(2 * np.pi * (45.0 * tt + 60.0 * (1 - np.exp(-tt * 30)) / 30.0)) * np.exp(-tt / 0.07)
    hats = np.zeros(n)
    hat_noise = signal.sosfilt(signal.butter(4, 7000, btype="highpass", fs=fs, output="sos"), rng.standard_normal(n))
    for start in np.arange(0.25, seconds, 0.25):
        length = min(int(0.05 * fs), n - int(start * fs))
        if length <= 0:
            continue
        hats[int(start * fs):int(start * fs) + length] += hat_noise[:length] * np.exp(-np.arange(length) / fs / 0.012)
    guitar = np.zeros(n)
    for i, start in enumerate(np.arange(0.0, seconds, 0.25)):
        length = min(int(0.4 * fs), n - int(start * fs))
        if length <= 0:
            continue
        tt = np.arange(length) / fs
        f = [329.6, 392.0, 440.0, 392.0][i % 4]
        guitar[int(start * fs):int(start * fs) + length] += sum(np.sin(2 * np.pi * f * h * tt) / h for h in range(1, 10)) * np.exp(-tt / 0.15)
    pad_l = signal.sosfilt(signal.butter(2, [200, 4000], btype="bandpass", fs=fs, output="sos"), rng.standard_normal(n))
    pad_r = signal.sosfilt(signal.butter(2, [200, 4000], btype="bandpass", fs=fs, output="sos"), rng.standard_normal(n))
    left = lead * 0.9 + bass * 0.8 + kick * 0.9 + guitar * 0.55 + hats * 0.04 + pad_l * 0.05
    right = lead * 0.9 + bass * 0.8 + kick * 0.9 + guitar * 0.12 + hats * 0.32 + pad_r * 0.05
    x = np.stack([left, right], axis=1)
    x /= np.abs(x).max()
    return (x * db_to_gain(peak_db)).astype(np.float32)


CACHE = Path(__file__).resolve().parent.parent.parent / "build" / "audio_quality" / "music_cache"
EXTENSIONS = (".flac", ".wav", ".mp3", ".ogg", ".opus", ".m4a")
CLIP_SECONDS = 24
CLIP_COUNT = 6


def configured_folder():
    folder = os.environ.get("VPX_AUDIO_TEST_MUSIC")
    if folder:
        return folder
    saved = CACHE / "folder.txt"
    return saved.read_text().strip() if saved.exists() else None


def _decode(path):
    for start in (45, 20, 5, 0):
        raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(CLIP_SECONDS), "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(FS), "-"],
                             capture_output=True)
        if raw.returncode == 0 and len(raw.stdout) >= 8 * FS * (CLIP_SECONDS - 4):
            return np.frombuffer(raw.stdout, dtype=np.float32).reshape(-1, 2).copy()
    return None


def build_music_cache(folder):
    found = []
    for root, _, names in os.walk(folder):
        for name in sorted(names):
            if name.lower().endswith(EXTENSIONS):
                found.append(os.path.join(root, name))
    found.sort()
    if not found:
        raise RuntimeError("no audio files in " + folder)
    picks = [found[int(i * len(found) / CLIP_COUNT)] for i in range(min(CLIP_COUNT, len(found)))]
    CACHE.mkdir(parents=True, exist_ok=True)
    for old in CACHE.glob("clip_*.npy"):
        old.unlink()
    names = []
    for index, path in enumerate(picks):
        clip = _decode(path)
        if clip is None:
            continue
        np.save(CACHE / ("clip_%d.npy" % len(names)), clip)
        names.append(os.path.basename(path)[:28])
    (CACHE / "folder.txt").write_text(folder)
    (CACHE / "names.txt").write_text("\n".join(names))
    return names


def real_clips(limit=CLIP_COUNT):
    folder = configured_folder()
    names_file = CACHE / "names.txt"
    if folder and os.path.isdir(folder) and (not names_file.exists() or (CACHE / "folder.txt").read_text().strip() != folder):
        build_music_cache(folder)
    if not names_file.exists():
        return []
    names = [n for n in names_file.read_text().split("\n") if n]
    return [(names[i], np.load(CACHE / ("clip_%d.npy" % i))) for i in range(min(limit, len(names)))]
