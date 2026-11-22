import numpy as np
from scipy import signal

FS = 48000


def db(value):
    return 20.0 * np.log10(np.maximum(np.abs(value), 1e-12))


def power_db(x):
    return 10.0 * np.log10(np.mean(np.square(np.asarray(x, dtype=np.float64))) + 1e-24)


def thdn(y, f0, fs=FS, skip=0.5, guard_hz=40.0):
    s = np.asarray(y[int(skip * fs):], dtype=np.float64)
    n = len(s)
    window = np.hanning(n)
    spectrum = np.abs(np.fft.rfft(s * window)) ** 2
    freqs = np.fft.rfftfreq(n, 1 / fs)
    band = np.abs(freqs - f0) <= guard_hz
    signal_power = spectrum[band].sum()
    noise = spectrum[~band].sum()
    if signal_power <= 0:
        return 0.0
    return 10.0 * np.log10(max(noise, 1e-30) / signal_power)


def residual_off_tone(y, f0, fs=FS, skip=0.5, guard_hz=20.0):
    return thdn(y, f0, fs, skip, guard_hz)


def tone_level_db(y, f0, fs=FS, skip=0.5):
    s = np.asarray(y[int(skip * fs):], dtype=np.float64)
    n = len(s)
    t = np.arange(n) / fs
    window = np.hanning(n)
    z = np.sum(s * window * np.exp(-2j * np.pi * f0 * t))
    amplitude = 2.0 * np.abs(z) / window.sum()
    return 20.0 * np.log10(max(amplitude, 1e-12))


def band_energy(y, f0, half_width, fs=FS, skip=0.5):
    s = np.asarray(y[int(skip * fs):], dtype=np.float64)
    n = len(s)
    spectrum = np.abs(np.fft.rfft(s * np.hanning(n))) ** 2
    freqs = np.fft.rfftfreq(n, 1 / fs)
    return spectrum[np.abs(freqs - f0) <= half_width].sum()


def imd_ratio_db(y, f1, f2, fs=FS, skip=0.5):
    s = np.asarray(y[int(skip * fs):], dtype=np.float64)
    n = len(s)
    spectrum = np.abs(np.fft.rfft(s * np.hanning(n))) ** 2
    freqs = np.fft.rfftfreq(n, 1 / fs)
    carriers = (np.abs(freqs - f1) <= 30) | (np.abs(freqs - f2) <= 30)
    total_other = spectrum[~carriers & (freqs > 20)].sum()
    return 10.0 * np.log10(max(total_other, 1e-30) / spectrum[carriers].sum())


def transfer(x, y, fs=FS, nperseg=16384, skip=0.5):
    s = int(skip * fs)
    f, pxy = signal.csd(x[s:], y[s:], fs, nperseg=nperseg)
    f, pxx = signal.welch(x[s:], fs, nperseg=nperseg)
    return f, pxy / pxx


def level_at(f, h, hz, width=0.08):
    mask = (f > hz * (1 - width)) & (f < hz * (1 + width))
    return float(np.mean(db(h[mask])))


def log_grid(low=60.0, high=16000.0, points=240):
    return np.geomspace(low, high, points)


def smooth_power_db(f, h, grid, octaves=1.0 / 3.0):
    power = np.abs(h) ** 2
    out = np.empty(len(grid))
    for i, g in enumerate(grid):
        mask = (f > g * 2 ** (-octaves / 2)) & (f < g * 2 ** (octaves / 2))
        out[i] = 10.0 * np.log10(np.mean(power[mask]) + 1e-18)
    return out


def trend_removed(curve, grid, octaves=1.5):
    per_octave = len(grid) / np.log2(grid[-1] / grid[0])
    k = max(int(per_octave * octaves) | 1, 3)
    padded = np.pad(curve, (k // 2, k // 2), mode="edge")
    trend = np.convolve(padded, np.ones(k) / k, mode="valid")
    return curve - trend


def group_delay_ms(f, h, fs=FS, low=100.0, high=10000.0, smooth_hz=200.0):
    mask = (f >= low) & (f <= high)
    phase = np.unwrap(np.angle(h[mask]))
    df = f[1] - f[0]
    gd = -np.gradient(phase, df) / (2 * np.pi)
    width = max(int(smooth_hz / df), 1)
    gd = np.convolve(gd, np.ones(width) / width, mode="same")
    return f[mask][width:-width], gd[width:-width] * 1000.0


def interaural_delay_ms(left, right, fs=FS, low=200.0, high=1500.0):
    sos = signal.butter(4, [low, high], btype="bandpass", fs=fs, output="sos")
    a = signal.sosfiltfilt(sos, np.asarray(left, dtype=np.float64))
    b = signal.sosfiltfilt(sos, np.asarray(right, dtype=np.float64))
    n = len(a)
    spectrum = np.fft.rfft(a, 2 * n) * np.conj(np.fft.rfft(b, 2 * n))
    corr = np.fft.irfft(spectrum)
    corr = np.concatenate([corr[-n:], corr[:n]])
    centre = n
    window = int(0.002 * fs)
    seg = corr[centre - window:centre + window + 1]
    k = int(np.argmax(seg))
    if 0 < k < len(seg) - 1:
        y0, y1, y2 = seg[k - 1], seg[k], seg[k + 1]
        shift = 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2 + 1e-30)
    else:
        shift = 0.0
    return -(k - window + shift) / fs * 1000.0


def k_weight(x, fs=FS):
    shelf = _biquad_high_shelf(fs)
    highpass = _biquad_rlb(fs)
    return signal.sosfilt(np.vstack([shelf, highpass]), x, axis=0)


def _biquad_high_shelf(fs):
    f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = np.tan(np.pi * f0 / fs)
    vh = 10 ** (g / 20.0)
    vb = vh ** 0.4996667741545416
    a0 = 1.0 + k / q + k * k
    b = [(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
    a = [1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
    return np.array(b + a)


def _biquad_rlb(fs):
    f0, q = 38.13547087602444, 0.5003270373238773
    k = np.tan(np.pi * f0 / fs)
    a0 = 1.0 + k / q + k * k
    b = [1.0, -2.0, 1.0]
    a = [1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
    return np.array(b + a)


def loudness_lufs(x, fs=FS):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    weighted = k_weight(x, fs)
    block = int(0.4 * fs)
    hop = int(0.1 * fs)
    if len(weighted) < block:
        return -70.0
    energies = []
    for start in range(0, len(weighted) - block + 1, hop):
        energies.append(np.mean(weighted[start:start + block] ** 2, axis=0).sum())
    energies = np.array(energies)
    loud = -0.691 + 10 * np.log10(energies + 1e-20)
    keep = loud > -70.0
    if not keep.any():
        return -70.0
    relative = -0.691 + 10 * np.log10(energies[keep].mean()) - 10.0
    keep = loud > max(relative, -70.0)
    if not keep.any():
        return -70.0
    return float(-0.691 + 10 * np.log10(energies[keep].mean()))


def true_peak(x, fs=FS):
    x = np.asarray(x, dtype=np.float64)
    over = signal.resample_poly(x, 4, 1, axis=0)
    return float(np.abs(over).max())


def correlation(a, b):
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-30))


def third_octave_levels(x, centres, fs=FS):
    f, p = signal.welch(np.asarray(x, dtype=np.float64), fs, nperseg=16384)
    out = []
    for c in centres:
        mask = (f > c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))
        out.append(10.0 * np.log10(p[mask].sum() + 1e-24))
    return np.array(out)


def max_step(x):
    return float(np.abs(np.diff(np.asarray(x, dtype=np.float64))).max())


def recurrence_residual_db(y, f0, fs=FS):
    y = np.asarray(y, dtype=np.float64)
    r = y[2:] - 2.0 * np.cos(2 * np.pi * f0 / fs) * y[1:-1] + y[:-2]
    amplitude = np.abs(y).max()
    if amplitude < 1e-9:
        return -300.0
    return 20.0 * np.log10(max(np.abs(r).max(), 1e-20) / amplitude)


def reduction_stats(output, linear, fs=FS, window=0.02):
    n = int(window * fs)
    count = min(len(output), len(linear)) // n
    values = []
    for i in range(count):
        p_out = np.mean(np.square(np.asarray(output[i * n:(i + 1) * n], dtype=np.float64))) + 1e-20
        p_lin = np.mean(np.square(np.asarray(linear[i * n:(i + 1) * n], dtype=np.float64))) + 1e-20
        if p_lin > 1e-8:
            values.append(10.0 * np.log10(p_out / p_lin))
    values = np.array(values)
    return float(-values.min()) if len(values) else 0.0, float(np.mean(values < -0.5)) if len(values) else 0.0
