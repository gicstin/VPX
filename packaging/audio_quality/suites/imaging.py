import numpy as np

import analysis
import signals
from harness import check
from suites.common import latency, modes, render

BAND = None


def noise_pair(seconds, level=-20.0, seed=21):
    x = signals.band_noise(200.0, 1500.0, seconds, level, seed=seed)
    return x, np.zeros_like(x)


def low_frequency_itd_ms(angle_deg):
    return 3.0 * 0.0875 / 343.0 * np.sin(np.radians(angle_deg)) * 1000.0


@check("imaging", "itd_matches_head_model")
def itd_matches_head_model(ctx):
    x, z = noise_pair(ctx.seconds(8, 5))
    reference = analysis.interaural_delay_ms(np.roll(x, 0), np.roll(x, 10))
    ctx.near("estimator sign and scale (10 sample delay on right)", reference, 10 / 48.0, 0.01, " ms")
    previous = 0.0
    for angle in (20, 30, 45, 60):
        y = render(ctx, {"stereo_mode": 1, "stereo_angle": angle}, signals.stereo(x, z))
        itd = analysis.interaural_delay_ms(y[:, 0], y[:, 1])
        ctx.near("low-frequency ITD at %d deg (hard left)" % angle, itd, low_frequency_itd_ms(angle), 0.08, " ms")
        ctx.ge("ITD grows with angle at %d deg" % angle, itd, previous - 1e-6, " ms")
        previous = itd
    y = render(ctx, {"stereo_mode": 1}, signals.stereo(z, x))
    ctx.near("ITD mirrored for hard right", analysis.interaural_delay_ms(y[:, 0], y[:, 1]), -low_frequency_itd_ms(30), 0.08, " ms")
    y = render(ctx, {"stereo_mode": 2}, signals.stereo(x, z))
    ctx.between("crossfeed ITD (hard left)", analysis.interaural_delay_ms(y[:, 0], y[:, 1]), 0.2, 0.6, " ms")


@check("imaging", "ild_by_band_and_angle")
def ild_by_band_and_angle(ctx):
    results = {}
    for angle in (20, 30, 45, 60):
        for hz in (500, 2000, 6000):
            x = signals.sine(hz, 2, -12.0)
            y = render(ctx, {"stereo_mode": 1, "stereo_angle": angle}, signals.stereo(x, np.zeros_like(x)))
            results[(angle, hz)] = analysis.tone_level_db(y[:, 0], hz) - analysis.tone_level_db(y[:, 1], hz)
    ctx.ge("ILD 500 Hz at 30 deg", results[(30, 500)], 2.0, " dB")
    ctx.ge("ILD 2 kHz at 30 deg", results[(30, 2000)], 5.0, " dB")
    ctx.ge("ILD 6 kHz at 30 deg", results[(30, 6000)], 9.0, " dB")
    ctx.le("ILD 500 Hz at 30 deg stays natural", results[(30, 500)], 9.0, " dB")
    for hz in (500, 2000, 6000):
        values = [results[(a, hz)] for a in (20, 30, 45, 60)]
        ctx.true("ILD grows with angle at %d Hz" % hz, all(b > a for a, b in zip(values, values[1:])), [round(v, 1) for v in values])
    for hz in (500, 2000, 6000):
        values = [results[(30, h)] for h in (500, 2000, 6000)]
    ctx.true("ILD grows with frequency at 30 deg", values[0] < values[1] < values[2], [round(v, 1) for v in values])


@check("imaging", "centre_stays_centred")
def centre_stays_centred(ctx):
    x = signals.program(ctx.seconds(6, 3))
    centre = signals.stereo(x[:, 0], x[:, 0])
    for name, params in modes(ctx).items():
        if "room" in name:
            continue
        y = render(ctx, params, centre)
        ctx.le("centre channel difference (%s)" % name, float(np.abs(y[:, 0] - y[:, 1]).max()), 1e-7)
        ctx.ge("centre inter-channel correlation (%s)" % name, analysis.correlation(y[:, 0], y[:, 1]), 0.99999)


@check("imaging", "mono_compatibility")
def mono_compatibility(ctx):
    x = signals.program(ctx.seconds(8, 4), peak_db=-6.0)
    mono_in = (x[:, 0] + x[:, 1]) / 2.0
    for name, params in modes(ctx).items():
        y = render(ctx, params, x)
        mono_out = (y[:, 0] + y[:, 1]) / 2.0
        if "crossfeed" in name and "air" not in name:
            delay = latency(ctx, params)
            ctx.le("mono sum unchanged apart from the %d sample limiter delay, residual (%s)" % (delay, name), analysis.power_db(mono_out[delay:] - mono_in[:len(mono_in) - delay]) - analysis.power_db(mono_in), -120.0, " dB")
        if "room" in name:
            continue
        anti = signals.stereo(x[:, 0], -x[:, 0])
        yy = render(ctx, params, anti)
        ctx.le("anti-phase content stays out of the mono sum (%s)" % name, float(np.abs(yy[:, 0] + yy[:, 1]).max()), 1e-6)


@check("imaging", "effect_controls_monotonic")
def effect_controls_monotonic(ctx):
    x = signals.sine(2000, 2, -12.0)
    stereo = signals.stereo(x, np.zeros_like(x))
    far = []
    for amount in (0.0, 0.25, 0.5, 0.75, 1.0):
        y = render(ctx, {"stereo_mode": 1, "stereo_amount": amount}, stereo)
        far.append(analysis.tone_level_db(y[:, 1], 2000) if np.abs(y[:, 1]).max() > 1e-6 else -200.0)
    ctx.true("far-ear level rises with speaker effect", all(b > a for a, b in zip(far, far[1:])), [round(v, 1) for v in far])
    far = []
    for db in (-12, -9, -6, -3, -1):
        y = render(ctx, {"stereo_mode": 2, "crossfeed_db": db}, stereo)
        far.append(analysis.tone_level_db(y[:, 1], 2000))
    ctx.true("far-ear level rises with crossfeed level", all(b > a for a, b in zip(far, far[1:])), [round(v, 1) for v in far])
    far = []
    for hz in (300, 500, 1000, 1500, 2000):
        y = render(ctx, {"stereo_mode": 2, "crossfeed_hz": hz}, stereo)
        far.append(analysis.tone_level_db(y[:, 1], 2000))
    ctx.true("far-ear level at 2 kHz rises with crossfeed cutoff", all(b > a for a, b in zip(far, far[1:])), [round(v, 1) for v in far])
    levels = []
    for air in (0, 3, 6, 9):
        y = render(ctx, {"stereo_mode": 1, "air_db": air}, signals.stereo(signals.sine(10000, 2, -12.0), signals.sine(10000, 2, -12.0)))
        levels.append(analysis.tone_level_db(y[:, 0], 10000))
    ctx.true("treble softening lowers 10 kHz in steps", all(b < a - 0.5 for a, b in zip(levels, levels[1:])), [round(v, 1) for v in levels])
    low = []
    for air in (0, 9):
        y = render(ctx, {"stereo_mode": 1, "air_db": air}, signals.stereo(signals.sine(300, 2, -12.0), signals.sine(300, 2, -12.0)))
        low.append(analysis.tone_level_db(y[:, 0], 300))
    ctx.le("treble softening leaves 300 Hz alone", abs(low[1] - low[0]), 0.15, " dB")


@check("imaging", "head_tracking_option")
def head_tracking_option(ctx):
    x, z = noise_pair(ctx.seconds(6, 4))
    stereo = signals.stereo(x, z)
    results = {}
    for tracked in (0, 1):
        for yaw in (-0.9, 0.0, 0.9):
            r = ctx.engine.new(stereo_mode=1, stereo_tracked=tracked)
            r.listener_yaw(yaw)
            y = r.run(stereo)
            results[(tracked, yaw)] = (analysis.interaural_delay_ms(y[:, 0], y[:, 1]), y)
    ctx.le("head-locked output ignores head yaw (max diff)", float(max(np.abs(results[(0, -0.9)][1] - results[(0, 0.0)][1]).max(), np.abs(results[(0, 0.9)][1] - results[(0, 0.0)][1]).max())), 1e-7)
    ctx.true("world-locked ITD changes with head yaw", abs(results[(1, 0.9)][0] - results[(1, -0.9)][0]) > 0.2, [round(results[(1, y)][0], 3) for y in (-0.9, 0.0, 0.9)])
    ctx.near("world-locked at yaw 0 equals head-locked ITD", results[(1, 0.0)][0], results[(0, 0.0)][0], 0.005, " ms")
