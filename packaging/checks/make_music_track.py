import json
import sys
import wave

import numpy as np

RATE = 48000
BPM = 120.0
BEAT = 60.0 / BPM
LENGTH = 20.0
GROOVE = (2.0, 10.0)
BUILD = (10.0, 14.0)
DROP = (14.0, 18.0)


def envelope(length, decay):
    t = np.arange(int(RATE * length)) / RATE
    return t, np.exp(-t / decay)


def place(track, start, left, right=None):
    begin = int(start * RATE)
    if begin >= track.shape[0]:
        return
    right = left if right is None else right
    end = min(track.shape[0], begin + left.shape[0])
    track[begin:end, 0] += left[: end - begin]
    track[begin:end, 1] += right[: end - begin]


def kick(level):
    t, e = envelope(0.4, 0.11)
    sweep = 45.0 + 75.0 * np.exp(-t / 0.03)
    phase = 2 * np.pi * np.cumsum(sweep) / RATE
    return np.sin(phase) * e * level


def snare(level, rng):
    t, e = envelope(0.3, 0.12)
    noise = rng.standard_normal(t.shape[0])
    noise = np.convolve(noise, np.ones(4) / 4, mode="same")
    return (noise * 0.6 + np.sin(2 * np.pi * 190.0 * t) * np.exp(-t / 0.05)) * e * level


def hat(level, rng):
    t, e = envelope(0.12, 0.03)
    noise = rng.standard_normal(t.shape[0])
    return np.diff(noise, prepend=0.0) * 0.5 * e * level


def bass_note(frequency, length, level):
    t = np.arange(int(RATE * length)) / RATE
    tone = sum(np.sin(2 * np.pi * frequency * k * t) / k for k in range(1, 5))
    fade = np.minimum(1.0, np.minimum(t / 0.01, (length - t) / 0.02))
    return tone * fade * level * (0.7 + 0.3 * np.exp(-t / 0.15))


def main(path):
    rng = np.random.default_rng(7)
    track = np.zeros((int(RATE * LENGTH), 2))
    t = np.arange(track.shape[0]) / RATE
    pad = sum(np.sin(2 * np.pi * f * t + i) for i, f in enumerate([220.0, 277.2, 329.6]))
    pad_level = 0.03 * np.clip((t - 0.2) / 1.5, 0.0, 1.0) * (t < DROP[1])
    track[:, 0] += pad * pad_level * (1.0 + 0.2 * np.sin(t * 0.7))
    track[:, 1] += pad * pad_level * (1.0 + 0.2 * np.cos(t * 0.9))
    kicks = []
    notes = [55.0, 55.0, 65.4, 49.0]
    for section, level in [(GROOVE, 1.0), (DROP, 1.2)]:
        beat = section[0]
        index = 0
        while beat < section[1] - 0.001:
            kicks.append(round(beat, 4))
            place(track, beat, kick(0.55 * level))
            if index % 2 == 1:
                place(track, beat, snare(0.16 * level, rng))
            for half in range(2):
                pan = 0.35 if half == 0 else -0.35
                h = hat(0.12 * level, rng)
                place(track, beat + half * BEAT / 2, h * (1.0 - pan), h * (1.0 + pan))
            note = notes[(index // 4) % len(notes)]
            place(track, beat, bass_note(note, BEAT * 0.9, 0.12 * level))
            beat += BEAT
            index += 1
    progress_start, progress_end = BUILD
    hit = progress_start
    while hit < progress_end:
        progress = (hit - progress_start) / (progress_end - progress_start)
        h = hat(0.06 + 0.12 * progress, rng)
        place(track, hit, h * 0.8, h * 1.2)
        place(track, hit, snare(0.03 + 0.12 * progress, rng))
        hit += BEAT / (2.0 + np.floor(progress * 3.0) * 2.0)
    span = (t >= BUILD[0]) & (t < BUILD[1])
    rise = (t[span] - BUILD[0]) / (BUILD[1] - BUILD[0])
    sweep = 400.0 * np.power(16.0, rise)
    riser = np.sin(2 * np.pi * np.cumsum(sweep) / RATE) * (0.02 + 0.12 * rise)
    track[span, 0] += riser
    track[span, 1] += riser
    peak = np.max(np.abs(track))
    track = track / peak * 0.8
    with wave.open(path, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes((track * 32767).astype("<i2").tobytes())
    print(json.dumps({"kicks": kicks, "groove": GROOVE, "build": BUILD, "drop": DROP, "length": LENGTH, "bpm": BPM}))


if __name__ == "__main__":
    main(sys.argv[1])
