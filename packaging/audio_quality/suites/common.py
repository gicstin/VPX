import numpy as np

import signals

STEREO_MODES = {
    "speakers30": {"stereo_mode": 1},
    "speakers20": {"stereo_mode": 1, "stereo_angle": 20},
    "speakers60": {"stereo_mode": 1, "stereo_angle": 60},
    "speakers30_air6": {"stereo_mode": 1, "air_db": 6},
    "speakers30_half": {"stereo_mode": 1, "stereo_amount": 0.5},
    "crossfeed": {"stereo_mode": 2},
    "crossfeed_strong": {"stereo_mode": 2, "crossfeed_db": -3, "crossfeed_hz": 1000},
    "crossfeed_soft": {"stereo_mode": 2, "crossfeed_db": -10, "crossfeed_hz": 500},
    "crossfeed_air6": {"stereo_mode": 2, "air_db": 6},
    "upmix": {"stereo_mode": 3},
    "upmix_centre_only": {"stereo_mode": 3, "upmix_ambience": 0.0},
    "upmix_room": {"stereo_mode": 3, "room_amount": 0.6, "stereo_distance": 0.4},
    "speakers30_room": {"stereo_mode": 1, "room_amount": 0.6},
}

QUICK_MODES = ["speakers30", "speakers60", "crossfeed", "speakers30_air6", "upmix"]


def modes(context):
    return {name: STEREO_MODES[name] for name in QUICK_MODES} if context.quick else dict(STEREO_MODES)


def placements(x):
    zero = np.zeros_like(x)
    return {
        "hardL": signals.stereo(x, zero),
        "hardR": signals.stereo(zero, x),
        "centre": signals.stereo(x, x),
        "wide": signals.stereo(x, -0.6 * x),
    }


def render(context, params, x, layout="stereo", rate=48000, block=1024, **flags):
    renderer = context.engine.new(layout=layout, rate=rate, **flags, **params)
    return renderer.run(x, block=block)


def latency(context, params, layout="stereo", rate=48000):
    return context.engine.new(layout=layout, rate=rate, **params).latency()


def aligned(context, params, x, y):
    delay = latency(context, params)
    return x[:len(x) - delay], y[delay:]
