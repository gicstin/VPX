import time

import numpy as np

import analysis
import engine as engine_module
import signals
from harness import check
from suites.common import modes, render


@check("robustness", "deterministic")
def deterministic(ctx):
    x = signals.program(ctx.seconds(6, 3))
    for name, params in modes(ctx).items():
        a = render(ctx, params, x)
        b = render(ctx, params, x)
        ctx.true("identical output on repeat (%s)" % name, np.array_equal(a, b))


@check("robustness", "survives_corrupt_samples")
def survives_corrupt_samples(ctx):
    x = signals.program(8, peak_db=-6.0)
    cases = {"nan": np.nan, "inf": np.inf, "-inf": -np.inf, "huge": 3.0e38}
    for name, params in modes(ctx).items():
        for label, bad in cases.items():
            corrupt = x.copy()
            corrupt[48000 * 2, 0] = bad
            corrupt[48000 * 2 + 1, 1] = bad
            y = render(ctx, params, corrupt)
            finite = bool(np.isfinite(y).all())
            recovered = float(np.abs(y[48000 * 4:] - render(ctx, params, x)[48000 * 4:]).max()) if finite else 99.0
            ctx.true("output stays finite after %s sample (%s)" % (label, name), finite)
            ctx.le("recovers within 2 s after %s sample, max diff (%s)" % (label, name), recovered, 1e-3)
    for layout, channels in (("5.1", 6), ("7.1", 8), ("ambisonic 1", 4)):
        rng = np.random.default_rng(3)
        feed = (rng.standard_normal((48000 * 6, channels)) * 0.2).astype(np.float32)
        clean = ctx.engine.new(layout=layout, spatial=True).run(feed)
        feed[48000, 1] = np.nan
        y = ctx.engine.new(layout=layout, spatial=True).run(feed)
        ctx.true("output stays finite after NaN sample (%s)" % layout, bool(np.isfinite(y).all()))
        ctx.le("recovers within 2 s after NaN sample (%s)" % layout, float(np.abs(y[48000 * 4:] - clean[48000 * 4:]).max()), 1e-3)


@check("robustness", "cpu_cost_and_denormals")
def cpu_cost_and_denormals(ctx):
    rng = np.random.default_rng(9)
    loud = (rng.standard_normal((48000 * 4, 2)) * 0.2).astype(np.float32)
    silent = np.zeros((48000 * 12, 2), dtype=np.float32)
    for name, params in modes(ctx).items():
        r = ctx.engine.new(**params)
        times = []
        for start in range(0, len(loud), 1024):
            t = time.perf_counter()
            r.process(loud[start:start + 1024])
            times.append(time.perf_counter() - t)
        active = np.median(times)
        tail = []
        for start in range(0, len(silent), 1024):
            t = time.perf_counter()
            r.process(silent[start:start + 1024])
            tail.append(time.perf_counter() - t)
        late = np.median(tail[len(tail) // 2:])
        ctx.le("tail block time vs loud block time (%s)" % name, late / max(active, 1e-9), 1.5, " x")
        ctx.le("real-time cost per stereo stream (%s)" % name, 100.0 * float(np.percentile(times, 99)) / (1024 / 48000.0), 3.0, " % of real time")
    for layout in ("5.1", "7.1", "ambisonic 1"):
        r = ctx.engine.new(layout=layout, spatial=True)
        feed = (rng.standard_normal((48000 * 3, r.channels)) * 0.2).astype(np.float32)
        times = []
        for start in range(0, len(feed), 1024):
            t = time.perf_counter()
            r.process(feed[start:start + 1024])
            times.append(time.perf_counter() - t)
        ctx.le("real-time cost, %s binaural" % layout, 100.0 * float(np.percentile(times, 99)) / (1024 / 48000.0), 6.0, " % of real time")


@check("robustness", "long_run_stability", quick=False)
def long_run_stability(ctx):
    rng = np.random.default_rng(13)
    for name, params in modes(ctx).items():
        r = ctx.engine.new(**params)
        levels = []
        total = np.zeros(2)
        count = 0
        for chunk in range(20):
            x = (rng.standard_normal((48000 * 6, 2)) * 0.12).astype(np.float32)
            y = r.run(x)
            levels.append(analysis.power_db(y))
            total += y.sum(axis=0)
            count += len(y)
            if not np.isfinite(y).all():
                ctx.true("finite throughout (%s)" % name, False)
                break
        ctx.le("level drift over 2 minutes (%s)" % name, max(levels) - min(levels), 0.1, " dB")
        ctx.le("DC offset over 2 minutes (%s)" % name, float(np.abs(total / count).max()), 3e-4)


@check("robustness", "sample_rates")
def sample_rates(ctx):
    rates = [8000, 11025, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000]
    for rate in rates:
        w = signals.white(2, -26.0, rate, seed=2)
        stereo = signals.stereo(w, np.zeros_like(w))
        for mode in (1, 2):
            y = render(ctx, {"stereo_mode": mode}, stereo, rate=rate)
            ctx.true("finite and bounded at %d Hz (mode %d)" % (rate, mode), bool(np.isfinite(y).all()) and float(np.abs(y).max()) <= 1.0)
        y = render(ctx, {"stereo_mode": 1}, stereo, rate=rate)
        ctx.ge("far ear is quieter than near ear at %d Hz" % rate, analysis.power_db(y[:, 0]) - analysis.power_db(y[:, 1]), 2.0, " dB")


@check("robustness", "sanitizer_fuzz")
def sanitizer_fuzz(ctx):
    seeds = range(1, 4 if ctx.quick else 13)
    operations = 1500 if ctx.quick else 5000
    try:
        failures = engine_module.run_fuzz(ctx.source_dir, seeds, operations)
    except RuntimeError as error:
        ctx.true("fuzz harness builds with sanitizers", False, str(error)[:200])
        return
    ctx.true("random operation sequences are clean under ASan/UBSan", not failures, failures[0][1][-400:] if failures else "")


@check("robustness", "layout_changes_mid_stream")
def layout_changes_mid_stream(ctx):
    rng = np.random.default_rng(8)
    r = ctx.engine.new(layout="stereo", stereo_mode=1)
    for layout in ("5.1", "stereo", "7.1", "ambisonic 1", "mono", "stereo"):
        channels = ctx.engine.new(layout=layout).channels
        r.lib.vsa_configure(r.handle, layout.encode(), 48000)
        r.channels = channels
        x = (rng.standard_normal((4800, channels)) * 0.2).astype(np.float32)
        y = r.run(x)
        ctx.true("finite after switching to %s" % layout, bool(np.isfinite(y).all()))
