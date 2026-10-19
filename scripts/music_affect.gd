class_name MusicAffect
extends RefCounted

const BANDS := 48
const BREATH_RATE := 0.1
const MIN_PERIOD := 0.25
const MAX_PERIOD := 1.5

var loudness_target := 0.0
var centroid_target := 0.5
var fast := 0.0
var slow := 0.0
var valley := 0.0
var bass_fast := 0.0
var bass_slow := 0.0
var arousal := 0.0
var tension := 0.0
var release := 0.0
var centroid := 0.5
var warmth := 0.4
var period := 0.5
var groove := 0.0
var since_beat := 4.0
var beat_phase := 0.0
var bar_phase := 0.0
var breath := 0.5
var breath_clock := 0.0
var last_beat := 0
var drop_ready := 0.0
var quiet_bass_time := 0.0


func feed(data: PackedFloat32Array, rms: float) -> void:
	var weighted := 0.0
	var total := 0.0
	for band in BANDS:
		var value := maxf(data[band], data[BANDS + band])
		if value <= 0.0:
			continue
		var power := db_to_linear(value * 60.0 - 60.0)
		weighted += power * band
		total += power
	if total > 0.000001:
		centroid_target = weighted / total / (BANDS - 1)
	loudness_target = clampf(rms * 5.0, 0.0, 1.0)


func silence() -> void:
	loudness_target = 0.0


func reset() -> void:
	for property in ["loudness_target", "fast", "slow", "valley", "bass_fast", "bass_slow", "arousal", "tension", "release", "groove", "beat_phase", "bar_phase", "breath_clock", "drop_ready", "quiet_bass_time"]:
		set(property, 0.0)
	centroid_target = 0.5
	centroid = 0.5
	warmth = 0.4
	period = 0.5
	since_beat = 4.0
	breath = 0.5
	last_beat = 0


func update(delta: float, beat_count: int, bass: float, motion: float) -> void:
	fast = lerpf(fast, loudness_target, 1.0 - exp(-delta * 20.0))
	slow = lerpf(slow, loudness_target, 1.0 - exp(-delta * 0.3))
	valley = fast if fast < valley else lerpf(valley, fast, 1.0 - exp(-delta * 0.12))
	bass_fast = lerpf(bass_fast, bass, 1.0 - exp(-delta * 12.0))
	bass_slow = lerpf(bass_slow, bass, 1.0 - exp(-delta * 0.5))
	centroid = lerpf(centroid, centroid_target, 1.0 - exp(-delta * 2.0))
	since_beat += delta
	if beat_count != last_beat:
		var interval := since_beat
		if beat_count == last_beat + 1 and interval >= MIN_PERIOD and interval <= MAX_PERIOD:
			var regular := 1.0 - clampf(absf(interval - period) / period * 4.0, 0.0, 1.0)
			groove = lerpf(groove, regular, 0.3)
			period = lerpf(period, interval, 0.35 if groove < 0.5 else 0.15)
		last_beat = beat_count
		since_beat = 0.0
	if since_beat > MAX_PERIOD * 2.0:
		groove = lerpf(groove, 0.0, 1.0 - exp(-delta * 1.5))
	beat_phase = fmod(since_beat / period, 1.0) if since_beat < period * 4.0 else 0.0
	bar_phase = fmod((float(posmod(beat_count, 4)) + beat_phase) / 4.0, 1.0)
	var tempo := clampf((1.0 / period - 1.0) / 2.0, 0.0, 1.0) * groove
	arousal = lerpf(arousal, clampf(fast * 0.75 + tempo * 0.35, 0.0, 1.0), 1.0 - exp(-delta * 2.4))
	var rising := clampf((fast - valley) * 3.0 - bass_slow * 1.5, 0.0, 1.0)
	tension = lerpf(tension, rising, 1.0 - exp(-delta * (1.2 if rising > tension else 3.0)))
	quiet_bass_time = quiet_bass_time + delta if bass_fast < 0.08 else 0.0
	drop_ready = maxf(drop_ready * exp(-delta * 0.4), clampf(tension * 1.5, 0.0, 1.0) if quiet_bass_time > 0.6 else 0.0)
	if bass_fast - bass_slow > 0.18 and bass_fast > 0.3 and drop_ready > 0.35:
		release = 1.0
		tension = 0.0
		drop_ready = 0.0
	release *= exp(-delta * 1.1)
	warmth = lerpf(warmth, clampf(0.15 + centroid * 0.6 + tempo * 0.35 + arousal * 0.2, 0.0, 1.0), 1.0 - exp(-delta * 0.4))
	breath_clock = fmod(breath_clock + delta * TAU * BREATH_RATE * maxf(motion, 0.0), TAU)
	breath = 0.5 + 0.5 * sin(breath_clock)


func apply(material: ShaderMaterial) -> void:
	material.set_shader_parameter("arousal", arousal)
	material.set_shader_parameter("tension", tension)
	material.set_shader_parameter("release", release)
	material.set_shader_parameter("centroid", centroid)
	material.set_shader_parameter("warmth", warmth)
	material.set_shader_parameter("groove", groove)
	material.set_shader_parameter("beat_phase", beat_phase)
	material.set_shader_parameter("bar_phase", bar_phase)
	material.set_shader_parameter("breath", breath)
