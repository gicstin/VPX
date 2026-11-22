import numpy as np

import analysis
import signals
from harness import check
from suites.common import modes, placements, render


@check("transparency", "passthrough_bit_exact")
def passthrough_bit_exact(ctx):
    x = signals.program(ctx.seconds(6, 3))
    y = render(ctx, {}, x)
    ctx.true("stereo passthrough equals input", np.array_equal(x, y), float(np.abs(x - y).max()))
    mono = signals.white(2, -20)
    y = render(ctx, {}, mono[:, None], layout="mono")
    ctx.true("mono input duplicated to both ears", np.array_equal(y[:, 0], mono) and np.array_equal(y[:, 1], mono))
    y = render(ctx, {"stereo_mode": 1, "stereo_amount": 0.0}, x)
    f, h = analysis.transfer(x[:, 0], y[:, 0], nperseg=8192, skip=0.3)
    mask = (f > 50) & (f < 12000)
    ctx.le("speakers at 0% effect keeps the tone, response deviation 50 Hz to 12 kHz", float(np.abs(analysis.db(h[mask])).max()), 0.3, " dB")
    lag = int(np.argmax(np.correlate(y[:20000, 0], x[:20000, 0], "full"))) - 19999
    ctx.between("speakers at 0% effect only delays the left channel slightly", lag / 48.0, 0.0, 2.3, " ms")
    renderer = ctx.engine.new(stereo_mode=1)
    renderer.run(x[:48000])
    renderer.set(stereo_mode=0)
    y = renderer.run(x[48000:48000 * 3])
    ctx.le("stereo off after on settles to input (max abs diff)", np.abs(y[-24000:] - x[48000 * 3 - 24000:48000 * 3]).max(), 1e-7)


@check("transparency", "silence_exact")
def silence_exact(ctx):
    silent = np.zeros((48000 * 2, 2), dtype=np.float32)
    for name, params in modes(ctx).items():
        ctx.le("silence in, peak out (%s)" % name, np.abs(render(ctx, params, silent)).max(), 0.0)
    rng = np.random.default_rng(4)
    burst = (rng.standard_normal((48000, 2)) * 0.3).astype(np.float32)
    tail = np.concatenate([burst, np.zeros((48000 * 6, 2), dtype=np.float32)])
    for name, params in modes(ctx).items():
        y = render(ctx, params, tail)
        ctx.le("burst then silence decays to exact zero (%s)" % name, np.abs(y[-48000:]).max(), 0.0)


@check("transparency", "thdn_static")
def thdn_static(ctx):
    freqs = [60, 440, 1000, 6000, 13000, 19000] if not ctx.quick else [100, 1000, 7000, 19000]
    worst = {}
    for name, params in modes(ctx).items():
        for f0 in freqs:
            x = signals.sine(f0, ctx.seconds(3, 2), -12.0)
            for place, stereo in placements(x).items():
                y = render(ctx, params, stereo)
                value = max(analysis.thdn(y[:, c], f0) for c in (0, 1) if np.abs(y[:, c]).max() > 1e-4)
                worst[(name, place)] = max(worst.get((name, place), -200.0), value)
    for (name, place), value in sorted(worst.items()):
        ctx.le("worst THD+N %s %s" % (name, place), value, -100.0, " dBc")


@check("transparency", "imd")
def imd(ctx):
    for name, params in modes(ctx).items():
        smpte = signals.two_tone(60, 7000, ctx.seconds(4, 2), 4.0, -6.0)
        ccif = signals.two_tone(19000, 20000, ctx.seconds(4, 2), 1.0, -6.0)
        for label, x, f1, f2 in (("SMPTE 60+7k", smpte, 60, 7000), ("CCIF 19k+20k", ccif, 19000, 20000)):
            for place, stereo in placements(x).items():
                if place in ("hardR", "wide"):
                    continue
                y = render(ctx, params, stereo)
                value = max(analysis.imd_ratio_db(y[:, c], f1, f2) for c in (0, 1) if np.abs(y[:, c]).max() > 1e-4)
                ctx.le("IMD %s %s %s" % (label, name, place), value, -90.0, " dB")


@check("transparency", "linearity")
def linearity(ctx):
    levels = [-90, -70, -50, -30, -12, -6]
    for name, params in modes(ctx).items():
        gains = []
        for level in levels:
            x = signals.sine(1000, 2, level)
            y = render(ctx, params, signals.stereo(x, 0.4 * x))
            gains.append(analysis.tone_level_db(y[:, 0], 1000) - level)
        ctx.le("gain variation across -90..-6 dBFS (%s)" % name, max(gains) - min(gains), 0.02, " dB")


@check("transparency", "limiter_transparency")
def limiter_transparency(ctx):
    program = signals.program(ctx.seconds(8, 4), peak_db=0.0)
    depth_limits = {-6.0: 0.01, -3.0: 0.3, -1.0: 1.6, 0.0: 3.2}
    for name, params in modes(ctx).items():
        reference = render(ctx, params, program * 0.125) * 8.0
        for peak_db, depth_limit in depth_limits.items():
            scaled = program * signals.db_to_gain(peak_db)
            y = render(ctx, params, scaled)
            linear = reference * signals.db_to_gain(peak_db)
            depth, share = analysis.reduction_stats(y[:, 0], linear[:, 0])
            ctx.le("deepest gain reduction at %g dBFS program peak (%s)" % (peak_db, name), depth, depth_limit + (1.5 if "60" in name else 0.0), " dB")
            ctx.le("share of time limited at %g dBFS program peak (%s)" % (peak_db, name), share, 0.0 if peak_db <= -6.0 else 0.25)
            ctx.le("output peak at %g dBFS program peak (%s)" % (peak_db, name), float(np.abs(y).max()), 0.981)


@check("transparency", "peak_safety")
def peak_safety(ctx):
    seconds = 2
    t = np.arange(48000 * seconds) / 48000
    adversarial = {
        "square": np.sign(np.sin(2 * np.pi * 100 * t)),
        "dc": np.ones_like(t),
        "clicks": (np.arange(len(t)) % 4800 == 0) * 1.0,
        "noise": np.clip(np.random.default_rng(1).standard_normal(len(t)) * 0.6, -1, 1),
        "sine": np.sin(2 * np.pi * 997 * t),
    }
    for name, params in modes(ctx).items():
        worst = 0.0
        for label, signal_ in adversarial.items():
            for stereo in (signals.stereo(signal_, signal_), signals.stereo(signal_, -signal_), signals.stereo(signal_, 0 * signal_)):
                y = render(ctx, params, stereo.astype(np.float32))
                worst = max(worst, float(np.abs(y).max()))
        ctx.le("peak out for full-scale input (%s)" % name, worst, 1.0)


@check("transparency", "limiter_is_clean")
def limiter_is_clean(ctx):
    for name, params in modes(ctx).items():
        if "half" in name:
            continue
        for f0, level in ((100, -0.3), (1000, -0.3), (5000, -0.3), (1000, 3.0)):
            x = signals.sine(f0, 3, level)
            y = render(ctx, params, signals.stereo(x, x))
            reduction = float(np.abs(y).max())
            value = max(analysis.thdn(y[:, c], f0, skip=1.0, guard_hz=60.0) for c in (0, 1))
            ctx.le("THD+N while limiting a %g dBFS %d Hz centred tone (%s)" % (level, f0, name), value, -50.0 if f0 > 100 else -40.0, " dBc")
            ctx.le("limited output peak (%s %d Hz %g dBFS)" % (name, f0, level), reduction, 0.981)
