import numpy as np

import analysis
import filterchain
import signals
from harness import check
from suites.common import latency, modes, render

CENTRES = [63, 125, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000]
BALANCE_LIMIT = {"speakers30": 3.0, "speakers60": 4.3, "crossfeed": 2.5, "speakers30_half": 2.4, "upmix": 3.6, "upmix_centre_only": 3.6}


def normalised(clip, peak_db):
    return clip * (signals.db_to_gain(peak_db) / np.abs(clip).max())


@check("realmusic", "tracks_available")
def tracks_available(ctx):
    clips = ctx.real()
    ctx.ge("real tracks cached (run with --music FOLDER to set them)", len(clips), 2 if ctx.quick else 6)
    for name, clip in clips:
        ctx.ge("clip length in seconds (%s)" % name, len(clip) / 48000.0, 18.0)


@check("realmusic", "limiter_on_real_masters")
def limiter_on_real_masters(ctx):
    for name, clip in ctx.real():
        for mode_name, params in modes(ctx).items():
            if "air" in mode_name or "half" in mode_name:
                continue
            reference = render(ctx, params, clip * 0.125) * 8.0
            for peak_db, depth_limit in ((-1.0, 2.0), (0.0, 3.5)):
                scaled = normalised(clip, peak_db)
                y = render(ctx, params, scaled)
                linear = reference * (signals.db_to_gain(peak_db) / np.abs(clip).max())
                depth, share = analysis.reduction_stats(y[:, 0], linear[:, 0])
                limit = depth_limit + (2.5 if "60" in mode_name else 0.0)
                ctx.le("deepest gain reduction at %g dBFS peak (%s, %s)" % (peak_db, mode_name, name), depth, limit, " dB")
                ctx.le("share of time limited at %g dBFS peak (%s, %s)" % (peak_db, mode_name, name), share, 0.3)
                ctx.le("output stays below the ceiling (%s, %s, %g dBFS)" % (mode_name, name, peak_db), float(np.abs(y).max()), 0.981)


@check("realmusic", "tonal_balance_and_loudness")
def tonal_balance_and_loudness(ctx):
    for name, clip in ctx.real():
        base = (analysis.third_octave_levels(clip[:, 0], CENTRES) + analysis.third_octave_levels(clip[:, 1], CENTRES)) / 2.0
        reference = analysis.loudness_lufs(clip)
        for mode_name, params in modes(ctx).items():
            if mode_name not in BALANCE_LIMIT:
                continue
            y = render(ctx, params, clip)
            levels = (analysis.third_octave_levels(y[:, 0], CENTRES) + analysis.third_octave_levels(y[:, 1], CENTRES)) / 2.0
            ctx.le("long-term spectrum deviation (%s, %s)" % (mode_name, name), float(np.abs(levels - base).max()), BALANCE_LIMIT[mode_name], " dB")
            ctx.le("loudness change (%s, %s)" % (mode_name, name), abs(analysis.loudness_lufs(y) - reference), 1.6 if "30" in mode_name or mode_name in ("crossfeed", "upmix", "upmix_centre_only") else 2.2, " LU")
            ctx.le("true-peak growth (%s, %s)" % (mode_name, name), 20 * np.log10(analysis.true_peak(y) / analysis.true_peak(clip)), 3.6 if "60" in mode_name else 1.6, " dB")


@check("realmusic", "mono_compatibility")
def mono_compatibility(ctx):
    for name, clip in ctx.real():
        clip = normalised(clip, -6.0)
        mono_in = (clip[:, 0] + clip[:, 1]) / 2.0
        y = render(ctx, {"stereo_mode": 2}, clip)
        delay = latency(ctx, {"stereo_mode": 2})
        ctx.le("crossfeed leaves the mono sum untouched (%s)" % name, analysis.power_db((y[delay:, 0] + y[delay:, 1]) / 2.0 - mono_in[:len(mono_in) - delay]) - analysis.power_db(mono_in), -90.0, " dB")
        for label, mode in (("speakers", 1), ("upmix", 3)):
            y = render(ctx, {"stereo_mode": mode}, clip)
            mono_out = (y[:, 0] + y[:, 1]) / 2.0
            f, h = analysis.transfer(mono_in, mono_out, nperseg=16384, skip=1.0)
            grid = analysis.log_grid(80.0, 14000.0, 120)
            curve = analysis.smooth_power_db(f, h, grid, 1.0 / 3.0)
            ctx.le("%s mono-sum response deviation (%s)" % (label, name), float(np.abs(curve).max()), 4.5 if mode == 1 else 5.5, " dB")


@check("realmusic", "stereo_width_is_reduced_gently")
def stereo_width_is_reduced_gently(ctx):
    def side_to_mid(x):
        mid = (x[:, 0] + x[:, 1]) / 2.0
        side = (x[:, 0] - x[:, 1]) / 2.0
        return analysis.power_db(side) - analysis.power_db(mid)
    for name, clip in ctx.real():
        before = side_to_mid(clip)
        for mode_name, params in (("crossfeed", {"stereo_mode": 2}), ("speakers30", {"stereo_mode": 1}), ("upmix", {"stereo_mode": 3})):
            change = side_to_mid(render(ctx, params, clip)) - before
            ctx.between("side-to-mid change (%s, %s)" % (mode_name, name), change, -12.0, 0.0, " dB")


@check("realmusic", "mode_switching_on_music")
def mode_switching_on_music(ctx):
    for name, clip in ctx.real():
        r = ctx.engine.new()
        plan = [(100, 1), (150, 3), (200, 2), (250, 3), (300, 0), (400, 1)]
        hooks = {block: (lambda rr, m=mode: rr.set(stereo_mode=m)) for block, mode in plan}
        y = r.run(clip[:48000 * 10], block=1024, hooks=hooks)
        steady = np.abs(np.diff(y[:90 * 1024], axis=0)).max()
        worst = 0.0
        for block, _ in plan:
            a = block * 1024
            worst = max(worst, float(np.abs(np.diff(y[a - 200:a + 3000], axis=0)).max()))
        ctx.le("largest step around mode switches vs normal playback (%s)" % name, worst / max(steady, 1e-9), 1.6, " x")
        ctx.le("peak after switching (%s)" % name, float(np.abs(y).max()), 1.0)


@check("realmusic", "parameter_moves_on_music")
def parameter_moves_on_music(ctx):
    for name, clip in ctx.real():
        piece = clip[:48000 * 8]
        for label, mode, setter in (("angle", 1, lambda r, t: r.set(stereo_angle=20 + 40 * t)),
                                    ("crossfeed level", 2, lambda r, t: r.set(crossfeed_db=-12 + 11 * t)),
                                    ("treble softening", 1, lambda r, t: r.set(air_db=9 * t))):
            r = ctx.engine.new(stereo_mode=mode)
            blocks = len(piece) // 1024
            hooks = {i: (lambda rr, v=(i % 150) / 150.0: setter(rr, v if v < 0.5 else 1 - v)) for i in range(blocks)}
            moving = r.run(piece, block=1024, hooks=hooks)
            still = ctx.engine.new(stereo_mode=mode).run(piece, block=1024)
            ctx.le("sweeping %s keeps the step size normal (%s)" % (label, name), float(np.abs(np.diff(moving, axis=0)).max() / max(np.abs(np.diff(still, axis=0)).max(), 1e-9)), 1.6, " x")
            ctx.true("sweeping %s stays finite and bounded (%s)" % (label, name), bool(np.isfinite(moving).all()) and float(np.abs(moving).max()) <= 1.0)


@check("realmusic", "long_playback_on_music", quick=False)
def long_playback_on_music(ctx):
    for name, clip in ctx.real():
        for mode_name, params in (("speakers30", {"stereo_mode": 1}), ("crossfeed", {"stereo_mode": 2})):
            r = ctx.engine.new(**params)
            levels = []
            for _ in range(4):
                y = r.run(clip, block=1024)
                levels.append(analysis.power_db(y))
                if not np.isfinite(y).all():
                    ctx.true("finite (%s, %s)" % (mode_name, name), False)
                    break
            ctx.le("level drift over four passes (%s, %s)" % (mode_name, name), max(levels) - min(levels), 0.05, " dB")


@check("realmusic", "speed_and_loudness_filters")
def speed_and_loudness_filters(ctx):
    if filterchain.ffmpeg_binary() is None:
        ctx.true("ffmpeg available", False)
        return
    chains = filterchain.loudness_chains()
    limits = {"even_out": 0.95, "night": 0.9}
    for name, clip in ctx.real():
        for chain_name, parts in chains.items():
            y = filterchain.apply(clip, ",".join(parts + ["aformat=sample_fmts=flt"]))
            ctx.le("%s peak ceiling (%s)" % (chain_name, name), float(np.abs(y).max()), limits[chain_name] + 0.002)
            ctx.le("%s true peak (%s)" % (chain_name, name), analysis.true_peak(y), limits[chain_name] * 1.15)
            ctx.ge("%s keeps the music audible, loudness (%s)" % (chain_name, name), analysis.loudness_lufs(y), -30.0, " LUFS")
        for kind in ("atempo", "rubberband"):
            if kind == "rubberband" and not filterchain.has_filter("rubberband"):
                continue
            for tempo in ((0.75, 1.5) if ctx.quick else (0.5, 0.75, 1.25, 1.5, 2.0)):
                y = filterchain.apply(clip, filterchain.tempo_chain(kind, tempo))
                ctx.le("loudness change (%s %gx, %s)" % (kind, tempo, name), abs(analysis.loudness_lufs(y) - analysis.loudness_lufs(clip)), 1.8 if kind == "rubberband" else 0.9, " LU")
                out = analysis.third_octave_levels(y[:, 0], [125, 250, 500, 1000, 2000, 4000, 8000])
                base = analysis.third_octave_levels(clip[:, 0], [125, 250, 500, 1000, 2000, 4000, 8000])
                ctx.le("spectral balance (%s %gx, %s)" % (kind, tempo, name), float(np.abs((out - out.mean()) - (base - base.mean())).max()), 4.5 if kind == "atempo" else 4.2, " dB")
                ctx.le("peak after stretching (%s %gx, %s)" % (kind, tempo, name), float(np.abs(y).max()), 1.0 if kind == "rubberband" else 1.2)


@check("realmusic", "spatial_extras_on_music")
def spatial_extras_on_music(ctx):
    for name, clip in ctx.real():
        clip = normalised(clip, -3.0)
        base = {}
        for label, mode in (("speakers", 1), ("upmix", 3)):
            base[label] = render(ctx, {"stereo_mode": mode}, clip)
        for label, mode in (("speakers", 1), ("upmix", 3)):
            plain = base[label]
            room = render(ctx, {"stereo_mode": mode, "room_amount": 1.0}, clip)
            far = render(ctx, {"stereo_mode": mode, "stereo_distance": 1.0}, clip)
            ctx.le("room 100%% loudness change (%s, %s)" % (label, name), abs(analysis.loudness_lufs(room) - analysis.loudness_lufs(plain)), 0.8, " LU")
            ctx.le("room 100%% peak (%s, %s)" % (label, name), float(np.abs(room).max()), 0.981)
            ctx.between("virtual distance 100%% loudness change (%s, %s)" % (label, name), analysis.loudness_lufs(far) - analysis.loudness_lufs(plain), -3.0, 1.0, " LU")
            ctx.ge("virtual distance 100%% takes the 8 kHz band down (%s, %s)" % (label, name), float((analysis.third_octave_levels(plain[:, 0], [8000]) - analysis.third_octave_levels(far[:, 0], [8000]))[0]), 4.0, " dB")
            ctx.le("virtual distance leaves the bass alone, 63-250 Hz change (%s, %s)" % (label, name), float(np.abs(analysis.third_octave_levels(far[:, 0], [63, 125, 250]) - analysis.third_octave_levels(plain[:, 0], [63, 125, 250])).max()), 1.6, " dB")
        speakers = base["speakers"]
        upmix = base["upmix"]
        ctx.le("upmix against speakers, loudness (%s)" % name, abs(analysis.loudness_lufs(upmix) - analysis.loudness_lufs(speakers)), 1.6, " LU")
        ctx.le("upmix against speakers, left-right balance (%s)" % name, abs((analysis.power_db(upmix[:, 0]) - analysis.power_db(upmix[:, 1])) - (analysis.power_db(speakers[:, 0]) - analysis.power_db(speakers[:, 1]))), 1.0, " dB")
        ctx.le("upmix peak (%s)" % name, float(np.abs(upmix).max()), 0.981)
        off = render(ctx, {}, clip)
        on = render(ctx, {"bass_translate": 1.0}, clip)
        ctx.le("bass translation loudness change (%s)" % name, abs(analysis.loudness_lufs(on) - analysis.loudness_lufs(off)), 0.8, " LU")
        high = analysis.third_octave_levels(on[:, 0], [1000, 2000, 4000, 8000]) - analysis.third_octave_levels(off[:, 0], [1000, 2000, 4000, 8000])
        ctx.le("bass translation leaves 1-8 kHz alone (%s)" % name, float(np.abs(high).max()), 0.05, " dB")
        added = analysis.third_octave_levels(on[:, 0], [160, 200, 250]) - analysis.third_octave_levels(off[:, 0], [160, 200, 250])
        ctx.between("bass translation adds low-mid harmonics, 160-250 Hz change (%s)" % name, float(added.max()), 0.0, 4.0, " dB")
        ctx.le("bass translation peak (%s)" % name, float(np.abs(on).max()), 1.0)
