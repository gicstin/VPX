import numpy as np

import analysis
import signals
from harness import check
from suites.common import modes, render

GRID = analysis.log_grid(60.0, 16000.0, 200)


def responses(ctx, params, seconds=None, rate=48000, angle_params=None):
    seconds = seconds or ctx.seconds(14, 8)
    w = signals.white(seconds, -26.0, rate, seed=11)
    zero = np.zeros_like(w)
    yl = render(ctx, params, signals.stereo(w, zero), rate=rate)
    yc = render(ctx, params, signals.stereo(w, w), rate=rate)
    f, near = analysis.transfer(w, yl[:, 0], rate, 16384, 0.5)
    _, far = analysis.transfer(w, yl[:, 1], rate, 16384, 0.5)
    _, centre = analysis.transfer(w, yc[:, 0], rate, 16384, 0.5)
    return f, near, far, centre


@check("response", "centre_flatness")
def centre_flatness(ctx):
    limits = {"crossfeed": 0.05, "crossfeed_strong": 0.05, "crossfeed_soft": 0.05, "crossfeed_air6": 7.0,
              "speakers20": 5.5, "speakers30": 4.5, "speakers60": 4.5, "speakers30_air6": 7.0, "speakers30_half": 4.5,
              "upmix": 3.0, "upmix_centre_only": 3.0, "upmix_room": 7.0, "speakers30_room": 7.0}
    for name, params in modes(ctx).items():
        f, near, far, centre = responses(ctx, params)
        curve = analysis.smooth_power_db(f, centre, GRID, 1.0 / 3.0)
        if "air6" in name or "room" in name:
            reference = analysis.smooth_power_db(f, centre, GRID, 1.0 / 3.0)
            mid = (GRID > 200) & (GRID < 2000)
            ctx.le("centre deviation 200-2000 Hz (%s)" % name, np.abs(curve[mid] - curve[mid].mean()).max(), 4.5, " dB")
            continue
        ctx.le("centre 1/3-octave deviation from 0 dB, 60-16k (%s)" % name, np.abs(curve).max(), limits[name], " dB")


@check("response", "centre_ripple")
def centre_ripple(ctx):
    for name in ("speakers30", "speakers60", "speakers20"):
        f, near, far, centre = responses(ctx, modes(ctx).get(name) or {"stereo_mode": 1, "stereo_angle": int(name[8:])})
        fine = analysis.smooth_power_db(f, centre, GRID, 1.0 / 6.0)
        dev = analysis.trend_removed(fine, GRID, 1.5)
        ctx.le("centre ripple std dev, 1/6 octave (%s)" % name, float(np.std(dev)), 1.6, " dB")
        ctx.le("centre ripple peak-to-peak, 1/6 octave (%s)" % name, float(dev.max() - dev.min()), 8.0, " dB")


@check("response", "near_far_ear")
def near_far_ear(ctx):
    for name, params in modes(ctx).items():
        if "half" in name or "room" in name:
            continue
        f, near, far, centre = responses(ctx, params)
        near_db = analysis.smooth_power_db(f, near, GRID, 1.0 / 3.0)
        far_db = analysis.smooth_power_db(f, far, GRID, 1.0 / 3.0)
        dev = analysis.trend_removed(near_db, GRID, 1.5)
        if "crossfeed" in name:
            ctx.le("near ear ripple (%s)" % name, float(np.abs(dev).max()), 1.8, " dB")
        else:
            ctx.le("near ear smoothness (%s)" % name, float(np.abs(dev).max()), 0.9, " dB")
        high = GRID > 1500
        slope = np.diff(far_db[high])
        ctx.le("far ear never rises above 1.5 kHz, worst rise (%s)" % name, float(slope.max()), 0.6, " dB per step")
        ctx.ge("near-far separation at 6 kHz (%s)" % name, near_db[np.argmin(abs(GRID - 6000))] - far_db[np.argmin(abs(GRID - 6000))], 4.0 if "air" not in name else 3.0, " dB")
        ctx.ge("HF extension, near ear 16 kHz vs 1 kHz (%s)" % name, near_db[-1] - near_db[np.argmin(abs(GRID - 1000))], -3.0 if "air" not in name else -8.0, " dB")


@check("response", "channel_symmetry")
def channel_symmetry(ctx):
    x = signals.program(ctx.seconds(6, 3))
    swapped = x[:, ::-1].copy()
    for name, params in modes(ctx).items():
        if "room" in name:
            continue
        a = render(ctx, params, x)
        b = render(ctx, params, swapped)
        ctx.le("mirror input gives mirrored output, max diff (%s)" % name, float(np.abs(a[:, ::-1] - b).max()), 2e-6)


@check("response", "latency_and_ringing")
def latency_and_ringing(ctx):
    n = 48000
    for name, params in modes(ctx).items():
        if "room" in name:
            continue
        imp = signals.impulse(n, 5000, 0.5)
        y = render(ctx, params, signals.stereo(imp, np.zeros_like(imp)))
        for ear in (0, 1):
            h = y[:, ear].astype(np.float64)
            peak = int(np.argmax(np.abs(h)))
            energy = np.cumsum(h ** 2)
            total = energy[-1]
            tail = (total - energy[min(peak + 240, n - 1)]) / total
            if ear == 0:
                ctx.le("near-ear latency (%s)" % name, (peak - 5000) / 48.0, 2.3, " ms")
            lobe = float(np.abs(h[4990:peak][np.sign(h[4990:peak]) != np.sign(h[peak])]).max()) if peak > 4990 and np.any(np.sign(h[4990:peak]) != np.sign(h[peak])) else 0.0
            ctx.le("opposite-sign lobe before the main peak, ear %d (%s)" % (ear, name), lobe / np.abs(h).max(), 0.1)
            ctx.le("energy after +5 ms ear %d (%s)" % (ear, name), 10 * np.log10(tail + 1e-30), -60.0, " dB")


@check("response", "group_delay_smooth")
def group_delay_smooth(ctx):
    for name in ("speakers30", "crossfeed"):
        f, near, far, centre = responses(ctx, modes(ctx)[name] if name in modes(ctx) else {"stereo_mode": 2})
        fg, gd = analysis.group_delay_ms(f, centre, low=100.0, high=8000.0)
        ctx.le("centre group-delay excursion (%s)" % name, float(np.abs(gd - np.median(gd)).max()), 0.45 if name == "speakers30" else 0.02, " ms")
        fg, gd = analysis.group_delay_ms(f, near, low=100.0, high=8000.0)
        ctx.le("near-ear group-delay excursion (%s)" % name, float(np.abs(gd - np.median(gd)).max()), 0.35 if name == "speakers30" else 0.25, " ms")


@check("response", "program_balance")
def program_balance(ctx):
    clips = [("synthetic program", signals.program(ctx.seconds(20, 10), peak_db=-6.0))] + ctx.real()[:2]
    centres = [63, 125, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000]
    limits = {"speakers30": 3.0, "speakers60": 4.3, "speakers30_air6": 6.0, "crossfeed": 0.9, "speakers30_half": 2.2}
    for clip_name, clip in clips:
        base = (analysis.third_octave_levels(clip[:, 0], centres) + analysis.third_octave_levels(clip[:, 1], centres)) / 2.0
        reference = analysis.loudness_lufs(clip)
        for name, params in modes(ctx).items():
            if name not in limits:
                continue
            y = render(ctx, params, clip)
            levels = (analysis.third_octave_levels(y[:, 0], centres) + analysis.third_octave_levels(y[:, 1], centres)) / 2.0
            diff = levels - base
            if "air" in name:
                diff = diff[:6]
            ctx.le("long-term spectrum deviation, %s (%s)" % (clip_name, name), float(np.abs(diff).max()), limits[name], " dB")
            if "air" not in name:
                ctx.le("loudness change, %s (%s)" % (clip_name, name), abs(analysis.loudness_lufs(y) - reference), 1.3, " LU")
            ctx.le("true-peak growth, %s (%s)" % (clip_name, name), 20 * np.log10(analysis.true_peak(y) / analysis.true_peak(clip)), 3.6 if "60" in name else 1.4, " dB")


@check("response", "sample_rate_invariance", quick=False)
def sample_rate_invariance(ctx):
    results = {}
    for rate in (44100, 48000, 96000, 192000):
        for name in ("speakers30", "crossfeed"):
            f, near, far, centre = responses(ctx, modes(ctx)[name] if name in modes(ctx) else {"stereo_mode": 2}, seconds=10, rate=rate)
            for label, h in (("near", near), ("far", far), ("centre", centre)):
                results[(name, label, rate)] = [analysis.level_at(f, h, hz, 0.06) for hz in (100, 1000, 3000, 8000)]
    for name in ("speakers30", "crossfeed"):
        for label in ("near", "far", "centre"):
            reference = np.array(results[(name, label, 48000)])
            for rate in (44100, 96000, 192000):
                ctx.le("response at %d Hz matches 48 kHz (%s %s)" % (rate, name, label), float(np.abs(np.array(results[(name, label, rate)]) - reference).max()), 0.5, " dB")


@check("response", "block_size_invariance")
def block_size_invariance(ctx):
    x = signals.program(ctx.seconds(6, 3))
    for name in ("speakers30", "crossfeed", "speakers30_air6"):
        params = modes(ctx).get(name) or {"stereo_mode": 2}
        reference = render(ctx, params, x, block=1024)
        for block in (1, 7, 64, 480, 4801, 16384):
            y = render(ctx, params, x[:48000] if block == 1 else x, block=block)
            span = len(y)
            ctx.le("block %d vs 1024 max diff (%s)" % (block, name), float(np.abs(y - reference[:span]).max()), 1e-6)


@check("response", "response_signature")
def response_signature(ctx):
    hertz = (100, 500, 1000, 2000, 4000, 8000, 12000)
    for name, params in modes(ctx).items():
        f, near, far, centre = responses(ctx, params, seconds=10)
        for label, h in (("near", near), ("far", far), ("centre", centre)):
            for hz in hertz:
                ctx.golden("signature %s %s %d Hz" % (name, label, hz), analysis.level_at(f, h, hz, 0.06), 0.25, " dB")
