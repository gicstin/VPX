import numpy as np

import analysis
import filterchain
import signals
from harness import check


def available():
    return filterchain.ffmpeg_binary() is not None


def uneven_program(ctx):
    program = signals.program(24, peak_db=-3.0)
    quarter = len(program) // 4
    gains = [-31, -9, -23, -5]
    return np.concatenate([program[i * quarter:(i + 1) * quarter] * signals.db_to_gain(g) for i, g in enumerate(gains)])


def sideband_width(x, fs=48000):
    segment = np.asarray(x[len(x) // 4:3 * len(x) // 4], dtype=np.float64)
    segment = segment * np.hanning(len(segment))
    spectrum = np.abs(np.fft.rfft(segment, len(segment) * 4))
    freqs = np.fft.rfftfreq(len(segment) * 4, 1 / fs)
    strong = freqs[spectrum > spectrum.max() * 0.1]
    return float(strong.max() - strong.min())


def loudness_spread(x, fs=48000):
    levels = []
    block = int(3.0 * fs)
    for start in range(0, len(x) - block, int(0.5 * fs)):
        levels.append(analysis.loudness_lufs(x[start:start + block], fs))
    levels = np.array([v for v in levels if v > -70])
    return float(np.percentile(levels, 95) - np.percentile(levels, 10))


@check("filters", "loudness_chains")
def loudness_chains(ctx):
    if not available():
        ctx.true("ffmpeg available for filter checks", False)
        return
    chains = filterchain.loudness_chains()
    ctx.true("both loudness chains found in the decoder patches", len(chains) == 2 and all(len(v) == 2 for v in chains.values()))
    limits = {"even_out": 0.95, "night": 0.9}
    program = uneven_program(ctx)
    stereo_program = signals.stereo(program, program)
    for name, parts in chains.items():
        chain = ",".join(parts + ["aformat=sample_fmts=flt"])
        for peak_db in (-18.0, -3.0, 0.0):
            x = signals.program(ctx.seconds(8, 5), peak_db=peak_db)
            y = filterchain.apply(x, chain)
            ctx.le("sample peak stays under the limiter (%s, input peak %g dBFS)" % (name, peak_db), float(np.abs(y).max()), limits[name] + 0.002)
            ctx.le("true peak stays near the limiter (%s, input peak %g dBFS)" % (name, peak_db), analysis.true_peak(y), limits[name] * 1.1)
        tone = signals.sine(1000, 10, -20.0)
        y = filterchain.apply(signals.stereo(tone, tone), chain)
        ctx.le("steady tone THD+N after the compressor settles (%s)" % name, analysis.thdn(y[:, 0], 1000, skip=4.0), -58.0, " dBc")
        y = filterchain.apply(signals.stereo(tone, np.zeros_like(tone)), chain)
        ctx.le("hard-left tone leaks to the right ear (%s)" % name, analysis.power_db(y[4 * 48000:, 1]) - analysis.power_db(y[4 * 48000:, 0]), -60.0, " dB")
        y = filterchain.apply(np.zeros((48000 * 3, 2), dtype=np.float32), chain)
        ctx.le("silence stays silent (%s)" % name, float(np.abs(y).max()), 1e-6)
        shaped = filterchain.apply(stereo_program, chain)
        ctx.golden("loudness spread ratio after %s" % name, loudness_spread(shaped) / loudness_spread(stereo_program), 0.08)
        quarter = len(shaped) // 4
        ctx.golden("quiet passage lift (LU) through %s" % name, analysis.loudness_lufs(shaped[:quarter]) - analysis.loudness_lufs(stereo_program[:quarter]), 0.8)
        ctx.le("shaped program stays clear of clipping (%s)" % name, float(np.abs(shaped).max()), limits[name] + 0.002)


@check("filters", "tempo_quality")
def tempo_quality(ctx):
    if not available():
        ctx.true("ffmpeg available for filter checks", False)
        return
    kinds = ["atempo"] + (["rubberband"] if filterchain.has_filter("rubberband") else [])
    tempos = (0.5, 0.75, 1.25, 1.5, 2.0) if not ctx.quick else (0.75, 1.5)
    n = 48000 * 8
    clicks = np.zeros(n, dtype=np.float32)
    for k in range(0, n, 9600):
        clicks[k:k + 8] = np.hanning(10)[1:9] * 0.6
    for kind in kinds:
        strict = kind == "atempo"
        for tempo in tempos:
            chain = filterchain.tempo_chain(kind, tempo)
            f0 = 1000
            tone = signals.sine(f0, 8, -12.0)
            y = filterchain.apply(signals.stereo(tone, tone), chain)
            expected = len(tone) / tempo
            ctx.le("duration error (%s tempo %g)" % (kind, tempo), abs(len(y) - expected) / expected * 100.0, 1.0 if kind == "rubberband" else 0.5, " %")
            body = y[len(y) // 4:3 * len(y) // 4, 0]
            spectrum = np.abs(np.fft.rfft(body * np.hanning(len(body))))
            pitch = abs(np.argmax(spectrum) * 48000.0 / len(body) - f0) / f0 * 100.0
            levels = [analysis.power_db(y[a:a + 4800, 0]) for a in range(48000, len(y) - 48000, 4800)]
            level_change = abs(np.mean(levels) - analysis.power_db(tone))
            metrics = {
                "pitch error %": (pitch, 0.3),
                "tone distortion dBc": (analysis.thdn(y[:, 0], f0, skip=1.0, guard_hz=60.0), -50.0),
                "tone level ripple dB": (max(levels) - min(levels), 0.2),
                "tone level change dB": (level_change, 0.2),
                "sideband width 1 kHz Hz": (sideband_width(y[:, 0]), 4.0),
            }
            for bass_hz in (60, 120, 3000):
                bass = signals.sine(bass_hz, 6, -12.0)
                z = filterchain.apply(signals.stereo(bass, bass), chain)
                metrics["sideband width %d Hz Hz" % bass_hz] = (sideband_width(z[:, 0]), 4.0)
            for label, (value, limit) in metrics.items():
                if strict:
                    ctx.le("%s (%s tempo %g)" % (label, kind, tempo), value, limit)
                else:
                    ctx.golden("%s (%s tempo %g)" % (label, kind, tempo), value, max(3.0, abs(value) * 0.4) if "dBc" not in label else 4.0)
            left = filterchain.apply(signals.stereo(tone, np.zeros_like(tone)), chain)
            ctx.le("stereo placement kept (%s tempo %g)" % (kind, tempo), analysis.power_db(left[48000:-48000, 1]) - analysis.power_db(left[48000:-48000, 0]), -40.0, " dB")
            z = filterchain.apply(signals.stereo(clicks, clicks), chain)
            envelope = np.abs(z[:, 0])
            idx = np.flatnonzero(envelope > 0.03)
            groups = [g for g in np.split(idx, np.flatnonzero(np.diff(idx) > 200) + 1) if len(g)]
            peak = float(np.mean([envelope[g].max() for g in groups])) if groups else 0.0
            width = float(np.mean([np.sum(envelope[max(g[0] - 300, 0):g[-1] + 300] > 0.1 * envelope[g].max()) for g in groups])) if groups else 999.0
            ctx.ge("click peak kept (%s tempo %g)" % (kind, tempo), peak / 0.6, 0.35 if kind == "rubberband" else 0.55)
            if strict:
                ctx.le("click smear in samples (%s tempo %g)" % (kind, tempo), width, 28.0)
            else:
                ctx.golden("click smear in samples (%s tempo %g)" % (kind, tempo), width, max(15.0, width * 0.3))
        program = signals.program(ctx.seconds(12, 8), peak_db=-6.0)
        clips = [("synthetic program", program)] + ctx.real()[:1]
        centres = [125, 250, 500, 1000, 2000, 4000, 8000]
        for clip_name, clip in clips:
            for tempo in (0.75, 1.25, 1.5):
                y = filterchain.apply(clip, filterchain.tempo_chain(kind, tempo))
                base = analysis.third_octave_levels(clip[:, 0], centres)
                out = analysis.third_octave_levels(y[:, 0], centres)
                ctx.le("spectral balance, %s %s at %gx" % (clip_name, kind, tempo), float(np.abs((out - out.mean()) - (base - base.mean())).max()), 5.0 if clip_name == "synthetic program" and kind == "rubberband" else 2.5, " dB")
                ctx.le("loudness change, %s %s at %gx" % (clip_name, kind, tempo), abs(analysis.loudness_lufs(y) - analysis.loudness_lufs(clip)), 1.8 if kind == "rubberband" else 0.7, " LU")


@check("filters", "resampling_quality")
def resampling_quality(ctx):
    if not available():
        ctx.true("ffmpeg available for filter checks", False)
        return
    options = filterchain.resample_options()
    ctx.true("resampler options come from the decoder patches", options != "", options)
    pairs = [(44100, 48000), (96000, 48000), (88200, 48000), (32000, 48000), (192000, 48000), (22050, 48000)]
    if ctx.quick:
        pairs = [(44100, 48000), (96000, 48000)]
    for src, dst in pairs:
        nyquist = min(src, dst) / 2.0
        edge = min(20000.0, 0.93 * nyquist)
        levels = []
        for f0 in (100, 1000, 5000, 10000, edge):
            tone = signals.sine(f0, 3, -12.0, fs=src)
            y = filterchain.apply(tone, "aresample=%d%s" % (dst, options), rate=src, out_rate=dst)
            levels.append(analysis.tone_level_db(y[:, 0], f0, fs=dst, skip=0.5) + 12.0)
        ctx.le("passband flatness up to %.0f Hz (%d to %d)" % (edge, src, dst), max(levels) - min(levels), 0.1, " dB")
        tone = signals.sine(1000, 3, -12.0, fs=src)
        y = filterchain.apply(tone, "aresample=%d%s" % (dst, options), rate=src, out_rate=dst)
        ctx.le("1 kHz THD+N (%d to %d)" % (src, dst), analysis.thdn(y[:, 0], 1000, fs=dst), -100.0, " dBc")
        if src > dst:
            stop = nyquist * 1.1
            tone = signals.sine(stop, 3, -12.0, fs=src)
            y = filterchain.apply(tone, "aresample=%d%s" % (dst, options), rate=src, out_rate=dst)
            ctx.le("rejection of %.0f Hz, above the new Nyquist (%d to %d)" % (stop, src, dst), analysis.power_db(y[int(0.5 * dst):, 0]) - analysis.power_db(tone), -55.0, " dB")
        else:
            high = min(20000.0, 0.9 * nyquist)
            tone = signals.sine(high, 3, -12.0, fs=src)
            y = filterchain.apply(tone, "aresample=%d%s" % (dst, options), rate=src, out_rate=dst)
            image = analysis.thdn(y[:, 0], high, fs=dst, skip=0.5, guard_hz=60.0)
            ctx.le("no images of a %.0f Hz tone (%d to %d)" % (high, src, dst), image, -80.0, " dBc")
