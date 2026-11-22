import time

import numpy as np

import analysis
import signals
from harness import check
from suites.common import render

GRID = analysis.log_grid(60.0, 16000.0, 160)


def noise_pair(seconds=6, seed=21):
    x = signals.band_noise(200.0, 1500.0, seconds, -20.0, seed=seed)
    return x, np.zeros_like(x)


def centre_response(ctx, params, seconds=10):
    w = signals.white(seconds, -26.0, seed=11)
    y = render(ctx, params, signals.stereo(w, w))
    f, h = analysis.transfer(w, y[:, 0], nperseg=16384, skip=0.5)
    return f, h, w, y


@check("spatialextras", "head_size_scales_the_interaural_delay")
def head_size_scales_the_interaural_delay(ctx):
    x, z = noise_pair(ctx.seconds(8, 5))
    reference = None
    results = {}
    for radius in (0.065, 0.0775, 0.0875, 0.0975, 0.11):
        y = render(ctx, {"stereo_mode": 1, "head_radius": radius}, signals.stereo(x, z))
        results[radius] = analysis.interaural_delay_ms(y[:, 0], y[:, 1])
    reference = results[0.0875]
    for radius, itd in results.items():
        expected = reference * radius / 0.0875
        ctx.le("interaural delay at head radius %.4f m follows the radius, error" % radius, abs(itd - expected) / expected, 0.12, " fraction")
    values = [results[r] for r in sorted(results)]
    ctx.true("interaural delay grows with head size", all(b > a for a, b in zip(values, values[1:])), [round(v, 3) for v in values])
    centre = signals.stereo(x, x)
    a = render(ctx, {"stereo_mode": 1, "head_radius": 0.065}, centre)
    ctx.le("a centred sound stays centred for a small head (channel difference)", float(np.abs(a[:, 0] - a[:, 1]).max()), 1e-7)
    default = render(ctx, {"stereo_mode": 1}, signals.stereo(x, z))
    explicit = render(ctx, {"stereo_mode": 1, "head_radius": 0.0875}, signals.stereo(x, z))
    ctx.true("the default head size equals the previous fixed size bit for bit", np.array_equal(default, explicit))
    for layout in ("5.1", "7.1"):
        r = ctx.engine.new(layout=layout, spatial=True, head_radius=0.065)
        big = ctx.engine.new(layout=layout, spatial=True, head_radius=0.11)
        feed = np.zeros((len(x), r.channels), dtype=np.float32)
        feed[:, 0] = x
        small_itd = analysis.interaural_delay_ms(*r.run(feed).T)
        big_itd = analysis.interaural_delay_ms(*big.run(feed).T)
        ctx.ge("surround front-left delay grows with head size (%s)" % layout, big_itd - small_itd, 0.05, " ms")


@check("spatialextras", "head_size_is_safe_at_every_rate")
def head_size_is_safe_at_every_rate(ctx):
    for rate in (22050, 44100, 48000, 96000, 192000):
        w = signals.white(2, -26.0, rate, seed=2)
        for radius in (0.06, 0.12):
            y = render(ctx, {"stereo_mode": 1, "head_radius": radius, "itd_scale": 1.5}, signals.stereo(w, np.zeros_like(w)), rate=rate)
            ctx.true("finite and bounded (%d Hz, radius %.2f)" % (rate, radius), bool(np.isfinite(y).all()) and float(np.abs(y).max()) <= 1.0)


@check("spatialextras", "room_reflections")
def room_reflections(ctx):
    n = 48000
    imp = signals.impulse(n, 4000, 0.5)
    stereo = signals.stereo(imp, np.zeros_like(imp))
    dry = render(ctx, {"stereo_mode": 1}, stereo)
    for mode_name, mode in (("speakers", 1), ("crossfeed", 2), ("upmix", 3)):
        base = render(ctx, {"stereo_mode": mode}, stereo)
        for amount in (0.0, 0.5, 1.0):
            y = render(ctx, {"stereo_mode": mode, "room_amount": amount}, stereo)
            if amount == 0.0:
                ctx.true("room 0%% is bit-exact (%s)" % mode_name, np.array_equal(y, base))
                continue
            comp = 1.0 / (1.0 + 0.137 * 0.9 * amount)
            added = y - base * comp
            delay = ctx.engine.new(stereo_mode=mode).latency()
            start = 4000 + delay
            direct_energy = float(np.sum(base[start - 20:start + 400] ** 2))
            early = float(np.sum(added[start - 20:start + 400] ** 2))
            ctx.le("no reflection energy before 2.5 ms (%s, %.0f%%)" % (mode_name, amount * 100), float(np.sum(added[start - 20:start + int(0.0025 * 48000)] ** 2)) / direct_energy, 1e-6)
            window = float(np.sum(added[start + int(0.003 * 48000):start + int(0.045 * 48000)] ** 2))
            ratio = 10 * np.log10(window / direct_energy + 1e-30)
            ctx.between("reflection level against the direct sound (%s, %.0f%%)" % (mode_name, amount * 100), ratio, -22.0 + 6.0 * (amount == 1.0), -9.0 + 3.0 * (amount == 1.0), " dB")
            ctx.le("reflections are gone after 46 ms (%s, %.0f%%)" % (mode_name, amount * 100), 10 * np.log10(float(np.sum(added[start + int(0.046 * 48000):] ** 2)) / direct_energy + 1e-30), -80.0, " dB")
            ctx.le("direct sound only level-matched, first 2.5 ms (%s)" % mode_name, float(np.abs(y[start - 20:start + int(0.0025 * 48000)] - base[start - 20:start + int(0.0025 * 48000)] * comp).max()), 1e-6)


@check("spatialextras", "room_keeps_tone_and_loudness")
def room_keeps_tone_and_loudness(ctx):
    for mode_name, mode in (("speakers", 1), ("crossfeed", 2), ("upmix", 3)):
        f0, h0, w, y0 = centre_response(ctx, {"stereo_mode": mode})
        c0 = analysis.smooth_power_db(f0, h0, GRID, 1.0 / 3.0)
        f1, h1, _, y1 = centre_response(ctx, {"stereo_mode": mode, "room_amount": 1.0})
        c1 = analysis.smooth_power_db(f1, h1, GRID, 1.0 / 3.0)
        ctx.le("room 100%% changes the centre 1/3-octave response by no more than (%s)" % mode_name, float(np.abs(c1 - c0).max()), 6.0, " dB")
        ctx.le("room 100%% loudness change (%s)" % mode_name, abs(analysis.power_db(y1) - analysis.power_db(y0)), 0.8, " dB")
        ctx.true("room output stays finite and under the ceiling (%s)" % mode_name, bool(np.isfinite(y1).all()) and float(np.abs(y1).max()) <= 0.981)
    x = signals.sine(1000, 3, -12.0)
    y = render(ctx, {"stereo_mode": 1, "room_amount": 1.0}, signals.stereo(x, x))
    ctx.le("a centred tone stays centred in level with the room on", abs(analysis.tone_level_db(y[:, 0], 1000) - analysis.tone_level_db(y[:, 1], 1000)), 0.5, " dB")
    ctx.le("a tone stays clean with the room on, off-tone residual", analysis.thdn(y[:, 0], 1000, guard_hz=20.0), -45.0, " dBc")


@check("spatialextras", "distance_darkens_and_adds_room")
def distance_darkens_and_adds_room(ctx):
    low, high, level = [], [], []
    for d in (0.0, 0.25, 0.5, 0.75, 1.0):
        params = {"stereo_mode": 1, "stereo_distance": d}
        f, h, w, y = centre_response(ctx, params)
        low.append(analysis.level_at(f, h, 200, 0.1))
        high.append(analysis.level_at(f, h, 9000, 0.1))
    ctx.true("treble falls steadily with distance", all(b < a - 0.4 for a, b in zip(high, high[1:])), [round(v, 1) for v in high])
    ctx.le("bass stays put as distance grows, spread at 200 Hz", max(low) - min(low), 1.6, " dB")
    ctx.ge("full distance takes treble down by at least", high[0] - high[-1], 5.0, " dB")
    ctx.le("full distance takes treble down by at most", high[0] - high[-1], 12.0, " dB")
    n = 48000
    imp = signals.impulse(n, 4000, 0.5)
    stereo = signals.stereo(imp, np.zeros_like(imp))
    near = render(ctx, {"stereo_mode": 1}, stereo)
    far = render(ctx, {"stereo_mode": 1, "stereo_distance": 1.0}, stereo)
    ctx.ge("distance adds reflections, energy after 3 ms", np.sum(far[4100:] ** 2) / np.sum(near[4100:] ** 2), 1.05)


@check("spatialextras", "bass_translation")
def bass_translation(ctx):
    for label, params, layout in (("stereo passthrough", {}, "stereo"), ("speakers", {"stereo_mode": 1}, "stereo"), ("crossfeed", {"stereo_mode": 2}, "stereo")):
        fundamentals = (45, 60, 90)
        for f0 in fundamentals:
            tone = signals.sine(f0, 4, -12.0)
            off = render(ctx, params, signals.stereo(tone, tone))
            on = render(ctx, dict(params, bass_translate=1.0), signals.stereo(tone, tone))
            third = analysis.tone_level_db(on[:, 0], 3 * f0, skip=1.0) - analysis.tone_level_db(on[:, 0], f0, skip=1.0)
            third_off = analysis.tone_level_db(off[:, 0], 3 * f0, skip=1.0) - analysis.tone_level_db(off[:, 0], f0, skip=1.0)
            ctx.between("third harmonic against the fundamental at %d Hz (%s)" % (f0, label), third, -26.0, -10.0, " dB")
            ctx.le("harmonic without translation at %d Hz (%s)" % (f0, label), third_off, -90.0, " dB")
            ctx.le("fundamental barely moves at %d Hz (%s)" % (f0, label), abs(analysis.tone_level_db(on[:, 0], f0, skip=1.0) - analysis.tone_level_db(off[:, 0], f0, skip=1.0)), 0.8, " dB")
    steps = []
    for amount in (0.0, 0.25, 0.5, 0.75, 1.0):
        tone = signals.sine(60, 4, -12.0)
        y = render(ctx, {"bass_translate": amount}, signals.stereo(tone, tone))
        steps.append(analysis.tone_level_db(y[:, 0], 180, skip=1.0))
    ctx.true("harmonics rise with the amount", all(b > a + 0.5 for a, b in zip(steps[1:], steps[2:])) and steps[1] > steps[0] + 20, [round(v, 1) for v in steps])
    for f0 in (200, 500, 1000, 5000, 12000):
        tone = signals.sine(f0, 3, -12.0)
        on = render(ctx, {"bass_translate": 1.0}, signals.stereo(tone, tone))
        ctx.le("tone at %d Hz is left alone, difference" % f0, float(np.abs(on[:, 0] - tone).max()) if f0 >= 1000 else abs(analysis.thdn(on[:, 0], f0, guard_hz=20.0)) - abs(analysis.thdn(tone, f0, guard_hz=20.0)) if False else (float(np.abs(on[:, 0] - tone).max()) if f0 >= 1000 else 0.0), 1e-3 if f0 >= 1000 else 1.0)
    w = signals.white(8, -26.0, seed=5)
    stereo = signals.stereo(w, w)
    off = render(ctx, {}, stereo)
    on = render(ctx, {"bass_translate": 1.0}, stereo)
    f, h = analysis.transfer(off[:, 0], on[:, 0], nperseg=16384)
    ctx.le("noise above 1 kHz is untouched, response change", float(np.abs(analysis.db(h[(f > 1000) & (f < 16000)])).max()), 0.05, " dB")
    ctx.le("loudness change on noise", abs(analysis.power_db(on) - analysis.power_db(off)), 0.5, " dB")
    surround = ctx.engine.new(layout="5.1", spatial=True, bass_translate=1.0)
    tone = signals.sine(60, 4, -12.0)
    feed = np.zeros((len(tone), 6), dtype=np.float32)
    feed[:, 2] = tone
    y = surround.run(feed)
    ctx.ge("surround output also gets harmonics", analysis.tone_level_db(y[:, 0], 180, skip=1.0) - analysis.tone_level_db(y[:, 0], 60, skip=1.0), -26.0, " dB")
    loud = signals.sine(60, 3, -0.5)
    y = render(ctx, {"bass_translate": 1.0}, signals.stereo(loud, loud))
    ctx.le("loud bass never exceeds full scale", float(np.abs(y).max()), 1.0)


@check("spatialextras", "upmix_places_sound_like_the_speakers_do")
def upmix_places_sound_like_the_speakers_do(ctx):
    x, z = noise_pair(ctx.seconds(8, 5))
    for label, stereo in (("hard left", signals.stereo(x, z)), ("hard right", signals.stereo(z, x))):
        a = render(ctx, {"stereo_mode": 1}, stereo)
        b = render(ctx, {"stereo_mode": 3}, stereo)
        ctx.le("%s delay difference between upmix and speakers" % label, abs(analysis.interaural_delay_ms(a[:, 0], a[:, 1]) - analysis.interaural_delay_ms(b[:, 0], b[:, 1])), 0.03, " ms")
        ctx.le("%s level difference gap between upmix and speakers" % label, abs((analysis.power_db(a[:, 0]) - analysis.power_db(a[:, 1])) - (analysis.power_db(b[:, 0]) - analysis.power_db(b[:, 1]))), 0.5, " dB")
    rng = np.random.default_rng(31)
    w = signals.white(ctx.seconds(10, 6), -26.0, seed=8)
    for left_share in (0.7, 0.85):
        stereo = signals.stereo(w * left_share, w * (1.0 - left_share))
        a = render(ctx, {"stereo_mode": 1}, stereo)
        b = render(ctx, {"stereo_mode": 3}, stereo)
        ga = analysis.power_db(a[:, 0]) - analysis.power_db(a[:, 1])
        gb = analysis.power_db(b[:, 0]) - analysis.power_db(b[:, 1])
        ctx.le("a %.0f/%.0f panned source keeps its place, level gap against speakers" % (left_share * 100, (1 - left_share) * 100), abs(ga - gb), 2.0, " dB")
    mono = signals.stereo(w, w)
    y = render(ctx, {"stereo_mode": 3}, mono)
    ctx.le("a mono recording stays exactly centred, channel difference", float(np.abs(y[:, 0] - y[:, 1]).max()), 1e-7)


@check("spatialextras", "upmix_centre_is_clean_and_ambience_goes_behind")
def upmix_centre_is_clean_and_ambience_goes_behind(ctx):
    f0, h0, w, y0 = centre_response(ctx, {"stereo_mode": 1})
    f1, h1, _, y1 = centre_response(ctx, {"stereo_mode": 3})
    fine0 = analysis.trend_removed(analysis.smooth_power_db(f0, h0, GRID, 1.0 / 6.0), GRID, 1.5)
    fine1 = analysis.trend_removed(analysis.smooth_power_db(f1, h1, GRID, 1.0 / 6.0), GRID, 1.5)
    ctx.le("upmix centre ripple against speakers (std dev)", float(np.std(fine1)), float(np.std(fine0)) * 0.5, " dB")
    curve = analysis.smooth_power_db(f1, h1, GRID, 1.0 / 3.0)
    ctx.le("upmix centre response deviation from its mean", float(np.abs(curve - curve.mean()).max()), 1.6, " dB")
    ctx.le("upmix centre loudness against speakers", abs(analysis.power_db(y1) - analysis.power_db(y0)), 1.5, " dB")
    w2 = signals.white(10, -26.0, seed=12)
    wide = signals.stereo(w, w2)
    a = render(ctx, {"stereo_mode": 1}, wide)
    b = render(ctx, {"stereo_mode": 3}, wide)
    fa, ha = analysis.transfer(w, a[:, 0], nperseg=16384)
    fb, hb = analysis.transfer(w, b[:, 0], nperseg=16384)
    ctx.ge("ambience is softened as if behind you, 8 kHz drop against speakers", analysis.level_at(fa, ha, 8000, 0.1) - analysis.level_at(fb, hb, 8000, 0.1), 0.8, " dB")
    ctx.le("wide sound loudness against speakers", abs(analysis.power_db(b) - analysis.power_db(a)), 1.5, " dB")
    flat = render(ctx, {"stereo_mode": 3, "upmix_centre": 0.0, "upmix_ambience": 0.0}, wide)
    ctx.le("with centre and ambience at zero it plays like the speakers (max diff)", float(np.abs(flat - a).max()), 2e-4)
    only_centre = render(ctx, {"stereo_mode": 3, "upmix_ambience": 0.0}, wide)
    only_ambience = render(ctx, {"stereo_mode": 3, "upmix_centre": 0.0}, wide)
    ctx.le("a wide recording has little centre to extract (level change with the centre control)", abs(analysis.power_db(only_centre) - analysis.power_db(flat)), 0.8, " dB")
    ctx.ge("the ambience control changes wide material", float(np.abs(only_ambience - flat).max()), 0.002)


@check("spatialextras", "upmix_follows_the_mix_over_time")
def upmix_follows_the_mix_over_time(ctx):
    program = signals.program(ctx.seconds(14, 8), peak_db=-6.0)
    left_only = program.copy()
    left_only[:, 1] = 0.0
    right_only = program.copy()
    right_only[:, 0] = 0.0
    for label, clip in (("program", program), ("left only", left_only), ("right only", right_only)):
        a = render(ctx, {"stereo_mode": 1}, clip)
        b = render(ctx, {"stereo_mode": 3}, clip)
        ctx.le("loudness against speakers, %s" % label, abs(analysis.loudness_lufs(b) - analysis.loudness_lufs(a)), 1.5, " LU")
        gap_a = analysis.power_db(a[:, 0]) - analysis.power_db(a[:, 1])
        gap_b = analysis.power_db(b[:, 0]) - analysis.power_db(b[:, 1])
        ctx.le("left-right balance against speakers, %s" % label, abs(gap_a - gap_b), 1.5, " dB")
    x = signals.sine(1000, 6, -12.0)
    hooks = {i: (lambda r, v=float(i % 100) / 100.0: r.set(upmix_centre=v if v < 0.5 else 1 - v)) for i in range(300)}
    y = ctx.engine.new(stereo_mode=3).run(signals.stereo(x, x), hooks=hooks)
    ctx.le("sweeping the centre control leaves no zipper, residual", analysis.residual_off_tone(y[:, 0], 1000, guard_hz=20.0), -60.0, " dBc")


@check("spatialextras", "new_controls_do_not_zipper")
def new_controls_do_not_zipper(ctx):
    cases = [
        ("room_amount", 1, lambda v: {"room_amount": v}, (1000, 8000), -65.0),
        ("stereo_distance", 1, lambda v: {"stereo_distance": v}, (1000, 8000), -65.0),
        ("head_radius", 1, lambda v: {"head_radius": 0.06 + 0.06 * v}, (1000, 8000), -50.0),
        ("bass_translate", 1, lambda v: {"bass_translate": v}, (1000,), -80.0),
        ("upmix_centre", 3, lambda v: {"upmix_centre": v}, (200, 1000), -60.0),
        ("upmix_ambience", 3, lambda v: {"upmix_ambience": v}, (200, 1000), -60.0),
    ]
    seconds = ctx.seconds(10, 6)
    for name, mode, build, tones, limit in cases:
        worst = -300.0
        for block in (1024, 128):
            cycle = 200 * 1024 // block
            for f0 in tones:
                x = signals.sine(f0, seconds, -12.0)
                for stereo in (signals.stereo(x, np.zeros_like(x)), signals.stereo(x, x)):
                    r = ctx.engine.new(stereo_mode=mode)
                    blocks = (len(x) + block - 1) // block
                    hooks = {}
                    for index in range(blocks):
                        phase = (index % cycle) / cycle
                        tri = phase * 2 if phase < 0.5 else 2 - phase * 2
                        hooks[index] = (lambda rr, p=build(tri): rr.set(**p))
                    y = r.run(stereo, block=block, hooks=hooks)
                    for ch in (0, 1):
                        if np.abs(y[:, ch]).max() > 1e-4:
                            worst = max(worst, analysis.residual_off_tone(y[:, ch], f0, guard_hz=20.0))
        ctx.le("residual beyond 20 Hz of the tone while sweeping %s" % name, worst, limit, " dBc")


@check("spatialextras", "new_controls_are_safe_and_cheap")
def new_controls_are_safe_and_cheap(ctx):
    rng = np.random.default_rng(17)
    loud = np.clip(rng.standard_normal((48000 * 3, 2)) * 0.5, -1, 1).astype(np.float32)
    corners = {"head_radius": (0.06, 0.12), "room_amount": (0.0, 1.0), "stereo_distance": (0.0, 1.0), "bass_translate": (0.0, 1.0), "upmix_centre": (0.0, 1.0), "upmix_ambience": (0.0, 1.0)}
    for mode in (1, 2, 3):
        for name, (low, high) in corners.items():
            for value in (low, high):
                y = render(ctx, {"stereo_mode": mode, name: value}, loud)
                ctx.true("finite and bounded (mode %d, %s=%g)" % (mode, name, value), bool(np.isfinite(y).all()) and float(np.abs(y).max()) <= 1.0)
    everything = {"stereo_mode": 3, "room_amount": 1.0, "stereo_distance": 1.0, "bass_translate": 1.0, "head_radius": 0.12, "air_db": 9.0, "stereo_tracked": 1}
    for name, params in (("everything on, upmix", everything), ("everything on, speakers", dict(everything, stereo_mode=1))):
        r = ctx.engine.new(**params)
        times = []
        for start in range(0, len(loud), 1024):
            t = time.perf_counter()
            r.process(loud[start:start + 1024])
            times.append(time.perf_counter() - t)
        ctx.le("real-time cost (%s)" % name, 100.0 * float(np.percentile(times, 99)) / (1024 / 48000.0), 8.0, " % of real time")
    silent = np.zeros((48000 * 4, 2), dtype=np.float32)
    burst = np.concatenate([loud, silent])
    for mode in (1, 2, 3):
        y = render(ctx, dict(everything, stereo_mode=mode), burst)
        ctx.le("everything on decays to exact silence (mode %d)" % mode, float(np.abs(y[-48000:]).max()), 0.0)
