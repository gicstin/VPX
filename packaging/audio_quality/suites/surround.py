import numpy as np

import analysis
import signals
from harness import check

LAYOUTS = {
    "5.1": ["FL", "FR", "FC", "LFE", "SL", "SR"],
    "7.1": ["FL", "FR", "FC", "LFE", "BL", "BR", "SL", "SR"],
    "quad": ["FL", "FR", "BL", "BR"],
}
LEFT = {"FL", "BL", "SL"}
RIGHT = {"FR", "BR", "SR"}


def channel_feed(layout, channel, signal_):
    names = LAYOUTS[layout]
    feed = np.zeros((len(signal_), len(names)), dtype=np.float32)
    feed[:, names.index(channel)] = signal_
    return feed


def layouts(ctx):
    return ["5.1", "7.1"] if ctx.quick else ["5.1", "7.1", "quad"]


@check("surround", "silence_and_noise_floor")
def silence_and_noise_floor(ctx):
    for layout in layouts(ctx) + ["ambisonic 1"]:
        for spatial in (True, False):
            r = ctx.engine.new(layout=layout, spatial=spatial)
            y = r.run(np.zeros((48000 * 2, r.channels), dtype=np.float32))
            ctx.le("silence in, peak out (%s spatial=%s)" % (layout, spatial), float(np.abs(y).max()), 0.0)


@check("surround", "distortion_per_channel")
def distortion_per_channel(ctx):
    freqs = (100, 1000, 8000) if not ctx.quick else (1000, 8000)
    for layout in layouts(ctx):
        for spatial in (True, False):
            worst = -300.0
            for channel in LAYOUTS[layout]:
                for f0 in freqs:
                    if channel == "LFE" and f0 > 100:
                        continue
                    x = signals.sine(f0, 2, -18.0)
                    y = ctx.engine.new(layout=layout, spatial=spatial).run(channel_feed(layout, channel, x))
                    for ch in (0, 1):
                        if np.abs(y[:, ch]).max() > 1e-4:
                            worst = max(worst, analysis.thdn(y[:, ch], f0))
            ctx.le("worst THD+N at -18 dBFS (%s spatial=%s)" % (layout, spatial), worst, -100.0 if not spatial else -90.0, " dBc")


@check("surround", "channel_routing")
def channel_routing(ctx):
    for layout in layouts(ctx):
        for channel in LAYOUTS[layout]:
            x = signals.pink(2, -24.0)
            feed = channel_feed(layout, channel, x)
            down = ctx.engine.new(layout=layout, spatial=False).run(feed)
            binaural = ctx.engine.new(layout=layout, spatial=True).run(feed)
            ld = analysis.power_db(down[:, 0]) - analysis.power_db(down[:, 1])
            lb = analysis.power_db(binaural[:, 0]) - analysis.power_db(binaural[:, 1])
            if channel in LEFT:
                ctx.ge("downmix %s is left-dominant" % channel, ld, 20.0, " dB")
                ctx.ge("binaural %s is left-dominant (%s)" % (channel, layout), lb, 2.0, " dB")
            elif channel in RIGHT:
                ctx.le("downmix %s is right-dominant" % channel, ld, -20.0, " dB")
                ctx.le("binaural %s is right-dominant (%s)" % (channel, layout), lb, -2.0, " dB")
            else:
                ctx.le("downmix %s is centred" % channel, abs(ld), 0.05, " dB")
                ctx.le("binaural %s is centred (%s)" % (channel, layout), abs(lb), 0.5, " dB")


@check("surround", "mirror_symmetry")
def mirror_symmetry(ctx):
    for layout in layouts(ctx):
        names = LAYOUTS[layout]
        order = [names.index({"FL": "FR", "FR": "FL", "BL": "BR", "BR": "BL", "SL": "SR", "SR": "SL"}.get(n, n)) for n in names]
        rng = np.random.default_rng(6)
        feed = (rng.standard_normal((48000 * 2, len(names))) * 0.15).astype(np.float32)
        mirrored = feed[:, order]
        for spatial in (True, False):
            a = ctx.engine.new(layout=layout, spatial=spatial).run(feed)
            b = ctx.engine.new(layout=layout, spatial=spatial).run(mirrored)
            ctx.le("mirrored layout gives mirrored ears (%s spatial=%s)" % (layout, spatial), float(np.abs(a[:, ::-1] - b).max()), 2e-6)


@check("surround", "level_goldens")
def level_goldens(ctx):
    for layout in layouts(ctx):
        for spatial in (True, False):
            for channel in LAYOUTS[layout]:
                x = signals.pink(3, -24.0, seed=17)
                y = ctx.engine.new(layout=layout, spatial=spatial).run(channel_feed(layout, channel, x))
                level = analysis.power_db(y[:, 0] + y[:, 1])
                ctx.golden("surround %s %s spatial=%s" % (layout, channel, spatial), level, 0.02, " dB")
    for name, params in (("classic", {"lfe_gain": 0.35, "surround_level": 1.41, "classic_shadow": 1, "linear_delay": 1, "normalize_downmix": 1}), ("bass", {"bass_db": 6, "bass_hz": 100, "lfe_gain": 0.5})):
        x = signals.pink(3, -24.0, seed=19)
        y = ctx.engine.new(layout="5.1", spatial=True, **params).run(channel_feed("5.1", "FC", x))
        ctx.golden("surround preset %s 5.1 FC" % name, analysis.power_db(y[:, 0] + y[:, 1]), 0.02, " dB")


@check("surround", "head_tracking_smoothness")
def head_tracking_smoothness(ctx):
    for layout in ("5.1", "ambisonic 1"):
        r = ctx.engine.new(layout=layout, spatial=True)
        x = signals.sine(2000, ctx.seconds(8, 5), -18.0)
        feed = np.zeros((len(x), r.channels), dtype=np.float32)
        feed[:, 0] = x
        if layout == "ambisonic 1":
            feed[:, 0] = x * 0.7
            feed[:, 1] = x * 0.7
        hooks = {i: (lambda rr, v=i * 1024 / 48000.0 * 0.6: rr.listener_yaw(v)) for i in range(len(x) // 1024 + 1)}
        y = r.run(feed, block=1024, hooks=hooks)
        worst = max(analysis.residual_off_tone(y[:, ch], 2000, guard_hz=25.0) for ch in (0, 1) if np.abs(y[:, ch]).max() > 1e-4)
        ctx.le("residual while rotating the head (%s)" % layout, worst, -45.0, " dBc")


@check("surround", "head_turn_direction")
def head_turn_direction(ctx):
    x = signals.pink(2, -24.0)
    base = ctx.engine.new(layout="5.1", spatial=True)
    feed = channel_feed("5.1", "FL", x)
    ilds = {}
    for yaw in (-0.6, 0.0, 0.6):
        r = ctx.engine.new(layout="5.1", spatial=True)
        r.listener_yaw(yaw)
        y = r.run(feed)
        ilds[yaw] = analysis.power_db(y[:, 0]) - analysis.power_db(y[:, 1])
    ctx.true("turning toward a source reduces its level difference, away increases it", (ilds[-0.6] - ilds[0.0]) * (ilds[0.6] - ilds[0.0]) < 0, {k: round(v, 1) for k, v in ilds.items()})


@check("surround", "ambisonic_behaviour")
def ambisonic_behaviour(ctx):
    x = signals.pink(2, -24.0)
    results = {}
    for name, index in {"W": 0, "Y": 1, "Z": 2, "X": 3}.items():
        feed = np.zeros((len(x), 4), dtype=np.float32)
        feed[:, index] = x
        y = ctx.engine.new(layout="ambisonic 1", spatial=True).run(feed)
        results[name] = (analysis.power_db(y[:, 0]) - analysis.power_db(y[:, 1]), analysis.correlation(y[:, 0], y[:, 1]))
    ctx.le("W-only (omni) is centred", abs(results["W"][0]), 0.3, " dB")
    ctx.ge("W-only reaches both ears in phase", results["W"][1], 0.99)
    ctx.le("Z-only (up) is centred", abs(results["Z"][0]), 0.5, " dB")
    ctx.le("X-only (front) is centred", abs(results["X"][0]), 0.5, " dB")
    ctx.le("Y-only (left-right figure eight) reaches the ears in opposite polarity", results["Y"][1], -0.5)
    feed = np.zeros((len(x), 4), dtype=np.float32)
    feed[:, 0] = x * 0.5
    feed[:, 1] = x * 0.5
    ahead = ctx.engine.new(layout="ambisonic 1", spatial=True).run(feed)
    ctx.ge("a source on the left is louder in the left ear", analysis.power_db(ahead[:, 0]) - analysis.power_db(ahead[:, 1]), 3.0, " dB")
    r = ctx.engine.new(layout="ambisonic 1", spatial=True)
    r.listener_yaw(np.pi)
    behind = r.run(feed)
    ctx.le("turning around moves the left source to the right ear", analysis.power_db(behind[:, 0]) - analysis.power_db(behind[:, 1]), -3.0, " dB")
    plain = ctx.engine.new(layout="ambisonic 1", spatial=False).run(feed)
    ctx.ge("non-spatial ambisonic keeps a stereo left/right split", analysis.power_db(plain[:, 0]) - analysis.power_db(plain[:, 1]), 6.0, " dB")


@check("surround", "dialogue_boost")
def dialogue_boost(ctx):
    w = signals.white(ctx.seconds(10, 6), -26.0, seed=31)
    stereo = signals.stereo(w, w)
    for layout, feed in (("stereo", stereo),):
        off = ctx.engine.new(layout=layout).run(feed)
        on = ctx.engine.new(layout=layout, dialogue=1.0).run(feed)
        f, h = analysis.transfer(off[:, 0], on[:, 0])
        lift = analysis.level_at(f, h, 1000, 0.1)
        ctx.between("dialogue lift at 1 kHz on centred stereo", lift, 2.0, 9.0, " dB")
        ctx.le("dialogue leaves 60 Hz alone", abs(analysis.level_at(f, h, 60, 0.1) - analysis.level_at(f, h, 15000, 0.1)), 4.0, " dB")
        ctx.le("dialogue peak stays below full scale", float(np.abs(on).max()), 1.0)
    side = signals.stereo(w, -w)
    on = ctx.engine.new(dialogue=1.0).run(side)
    off = ctx.engine.new().run(side)
    ctx.le("dialogue reduces wide content", analysis.power_db(on) - analysis.power_db(off), 0.0, " dB")


@check("surround", "bass_shelf_and_lfe")
def bass_shelf_and_lfe(ctx):
    w = signals.white(ctx.seconds(14, 8), -26.0, seed=41)
    feed = channel_feed("5.1", "FC", w)
    flat = ctx.engine.new(layout="5.1", spatial=False).run(feed)
    shelf = ctx.engine.new(layout="5.1", spatial=False, bass_db=6.0, bass_hz=120.0).run(feed)
    f, h = analysis.transfer(flat[:, 0], shelf[:, 0])
    ctx.near("shelf gain at 40 Hz", analysis.level_at(f, h, 40, 0.1), 6.0, 0.7, " dB")
    ctx.near("shelf gain at 1 kHz", analysis.level_at(f, h, 1000, 0.1), 0.0, 0.15, " dB")
    ctx.near("shelf gain at 10 kHz", analysis.level_at(f, h, 10000, 0.1), 0.0, 0.15, " dB")
    cut = ctx.engine.new(layout="5.1", spatial=False, bass_db=-6.0, bass_hz=200.0).run(feed)
    f, h = analysis.transfer(flat[:, 0], cut[:, 0])
    ctx.near("shelf cut at 40 Hz", analysis.level_at(f, h, 40, 0.1), -6.0, 0.7, " dB")
    lfe = channel_feed("5.1", "LFE", signals.pink(3, -24.0))
    a = ctx.engine.new(layout="5.1", spatial=False, lfe_gain=0.25).run(lfe)
    b = ctx.engine.new(layout="5.1", spatial=False, lfe_gain=0.5).run(lfe)
    ctx.near("doubling LFE level adds 6.02 dB", analysis.power_db(b) - analysis.power_db(a), 6.02, 0.05, " dB")
    z = ctx.engine.new(layout="5.1", spatial=False, lfe_gain=0.0).run(lfe)
    ctx.le("zero LFE level silences the sub channel", float(np.abs(z).max()), 1e-9)


@check("surround", "mono_downmix")
def mono_downmix(ctx):
    rng = np.random.default_rng(12)
    x = (rng.standard_normal((48000 * 2, 6)) * 0.15).astype(np.float32)
    for spatial in (True, False):
        r = ctx.engine.new(layout="5.1", spatial=spatial, mono=True)
        y = r.run(x)
        ctx.le("mono output has identical ears (spatial=%s)" % spatial, float(np.abs(y[:, 0] - y[:, 1]).max()), 1e-7)
    y = ctx.engine.new(layout="stereo", mono=True).run(signals.program(2))
    ctx.le("stereo mono toggle gives identical ears", float(np.abs(y[:, 0] - y[:, 1]).max()), 1e-7)


@check("surround", "binaural_headroom")
def binaural_headroom(ctx):
    rng = np.random.default_rng(14)
    for layout in ("5.1", "7.1"):
        r = ctx.engine.new(layout=layout, spatial=True)
        feed = np.clip(rng.standard_normal((48000 * 2, r.channels)) * 0.8, -1, 1).astype(np.float32)
        y = r.run(feed)
        ctx.le("full-scale surround never exceeds full scale (%s)" % layout, float(np.abs(y).max()), 1.0)
    x = signals.sine(1000, 2, -3.0)
    y = ctx.engine.new(layout="5.1", spatial=True).run(channel_feed("5.1", "FC", x))
    ctx.golden("surround FC -3 dBFS 1 kHz THD+N", analysis.thdn(y[:, 0], 1000), 3.0, " dBc")
