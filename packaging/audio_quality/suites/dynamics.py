import numpy as np

import analysis
import signals
from harness import check
from suites.common import render

ZIPPER_LIMIT_DB = {"angle": -52.0, "amount": -70.0, "air": -75.0, "crossfeed_db": -75.0, "crossfeed_hz": -70.0, "yaw": -50.0}


def sweep_hooks(kind, blocks, cycle=200, block=1024):
    hooks = {}
    for index in range(0, blocks):
        phase = (index % cycle) / cycle
        tri = phase * 2 if phase < 0.5 else 2 - phase * 2
        if kind == "angle":
            hooks[index] = lambda r, v=20 + 40 * tri: r.set(stereo_angle=v)
        elif kind == "amount":
            hooks[index] = lambda r, v=tri: r.set(stereo_amount=v)
        elif kind == "air":
            hooks[index] = lambda r, v=9 * tri: r.set(air_db=v)
        elif kind == "crossfeed_db":
            hooks[index] = lambda r, v=-12 + 11 * tri: r.set(crossfeed_db=v)
        elif kind == "crossfeed_hz":
            hooks[index] = lambda r, v=300 + 1700 * tri: r.set(crossfeed_hz=v)
        elif kind == "yaw":
            hooks[index] = lambda r, v=index * block / 48000.0 * 0.5: r.listener_yaw(v)
    return hooks


@check("dynamics", "zipper_noise")
def zipper_noise(ctx):
    kinds = {"angle": 1, "amount": 1, "air": 1, "crossfeed_db": 2, "crossfeed_hz": 2, "yaw": 1}
    tones = (200, 1000, 8000) if not ctx.quick else (1000, 8000)
    seconds = ctx.seconds(12, 8)
    for kind, mode in kinds.items():
        worst = -300.0
        for block in (1024, 128):
            for f0 in tones:
                x = signals.sine(f0, seconds, -12.0)
                for stereo in (signals.stereo(x, np.zeros_like(x)), signals.stereo(x, x)):
                    r = ctx.engine.new(stereo_mode=mode, stereo_tracked=1 if kind == "yaw" else 0)
                    blocks = (len(x) + block - 1) // block
                    y = r.run(stereo, block=block, hooks=sweep_hooks(kind, blocks, 200 * 1024 // block, block))
                    for ch in (0, 1):
                        if np.abs(y[:, ch]).max() > 1e-4:
                            worst = max(worst, analysis.residual_off_tone(y[:, ch], f0, guard_hz=20.0))
        ctx.le("residual beyond 20 Hz of tone while sweeping %s" % kind, worst, ZIPPER_LIMIT_DB[kind], " dBc")


@check("dynamics", "parameter_jumps_do_not_click")
def parameter_jumps_do_not_click(ctx):
    f0 = 3000
    x = signals.sine(f0, 4, -12.0)
    cases = [
        ("angle 20 to 60", {"stereo_mode": 1, "stereo_angle": 20}, {"stereo_angle": 60}),
        ("angle 60 to 20", {"stereo_mode": 1, "stereo_angle": 60}, {"stereo_angle": 20}),
        ("amount 0 to 1", {"stereo_mode": 1, "stereo_amount": 0.0}, {"stereo_amount": 1.0}),
        ("air 0 to 9", {"stereo_mode": 1}, {"air_db": 9.0}),
        ("air 9 to 0", {"stereo_mode": 1, "air_db": 9.0}, {"air_db": 0.0}),
        ("crossfeed level -12 to -1", {"stereo_mode": 2, "crossfeed_db": -12}, {"crossfeed_db": -1}),
        ("crossfeed cutoff 300 to 2000", {"stereo_mode": 2, "crossfeed_hz": 300}, {"crossfeed_hz": 2000}),
    ]
    for label, start, change in cases:
        worst = -300.0
        for stereo in (signals.stereo(x, np.zeros_like(x)), signals.stereo(x, 0.5 * x)):
            r = ctx.engine.new(**start)
            y = r.run(stereo, block=1024, hooks={100: lambda rr, c=change: rr.set(**c)})
            for ch in (0, 1):
                if np.abs(y[:, ch]).max() > 1e-4:
                    worst = max(worst, analysis.recurrence_residual_db(y[100 * 1024 - 2000:100 * 1024 + 30000, ch], f0))
        ctx.le("click residual after jump (%s)" % label, worst, -50.0, " dB re tone")


@check("dynamics", "mode_switching_is_click_free")
def mode_switching_is_click_free(ctx):
    for f0 in (200, 3000, 9000):
        x = signals.sine(f0, 6, -12.0)
        worst = -300.0
        peak = 0.0
        step_worst = 0.0
        for stereo in (signals.stereo(x, np.zeros_like(x)), signals.stereo(x, 0.5 * x), signals.stereo(x, x)):
            r = ctx.engine.new()
            plan = [(40, 1), (80, 2), (120, 0), (160, 2), (200, 1), (240, 0)]
            hooks = {block: (lambda rr, m=mode: rr.set(stereo_mode=m)) for block, mode in plan}
            y = r.run(stereo, block=1024, hooks=hooks)
            for ch in (0, 1):
                if np.abs(y[:, ch]).max() > 1e-4:
                    worst = max(worst, analysis.recurrence_residual_db(y[36000:, ch], f0))
                    steady = 2 * np.pi * f0 / 48000.0 * float(np.abs(y[:, ch]).max())
                    jump = max(analysis.max_step(y[block * 1024 - 100:block * 1024 + 4000, ch]) for block, _ in plan)
                    step_worst = max(step_worst, jump / max(steady, 1e-9))
            peak = max(peak, float(np.abs(y).max()))
        ctx.le("smoothness residual over mode switches (%d Hz)" % f0, worst, -22.0, " dB re tone")
        ctx.le("largest step over mode switches vs steady playback (%d Hz)" % f0, step_worst, 1.15, " x")
        ctx.le("peak level over mode switches (%d Hz)" % f0, peak, 0.5)


@check("dynamics", "seek_and_reset")
def seek_and_reset(ctx):
    x = signals.program(4, peak_db=-6.0)
    layouts = [("stereo", {"stereo_mode": 1}), ("stereo", {"stereo_mode": 2}), ("5.1", {}), ("7.1", {}), ("ambisonic 1", {})]
    for layout, params in layouts:
        channels = ctx.engine.new(layout=layout).channels
        rng = np.random.default_rng(5)
        feed = (rng.standard_normal((48000 * 2, channels)) * 0.2).astype(np.float32)
        r = ctx.engine.new(layout=layout, spatial=True, **params)
        r.run(feed[:48000])
        r.seek()
        y = r.process(feed[48000:48000 + 2048])
        ctx.le("first sample after seek (%s %s)" % (layout, params.get("stereo_mode", "")), float(np.abs(y[0]).max()), 1e-6)
        envelope = np.abs(y[:1500]).max(axis=1)
        ctx.true("seek fades in without overshoot (%s %s)" % (layout, params.get("stereo_mode", "")), envelope[:200].max() < envelope[1000:1500].max() * 1.5 + 1e-6)


@check("dynamics", "settle_time")
def settle_time(ctx):
    x = signals.sine(6000, 4, -12.0)
    stereo = signals.stereo(x, np.zeros_like(x))
    r = ctx.engine.new(stereo_mode=1, stereo_angle=20)
    y = r.run(stereo, block=1024, hooks={20: lambda rr: rr.set(stereo_angle=60)})
    far = np.array([analysis.tone_level_db(y[a:a + 4096, 1], 6000, skip=0.0) for a in range(0, len(y) - 4096, 1024)])
    final = far[-4:].mean()
    start = far[15]
    reached = None
    for index in range(20, len(far)):
        if abs(far[index] - final) <= 0.1 * abs(final - start):
            reached = (index - 20) * 1024 / 48000.0
            break
    ctx.le("time to settle within 10% after an angle jump", reached if reached is not None else 99.0, 0.5, " s")
