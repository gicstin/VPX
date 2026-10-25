class_name MusicTimeline
extends RefCounted

const FLASH_INTERVAL := 1.0 / 3.0
const FLASH_LIMIT := 0.6
const FLASH_DECAY := 7.0
const SEEK_JUMP := 1.5
const ANTICIPATION_BEATS := 2.0

var map: MusicMap
var active := false
var time := -1.0
var beat_phase := 0.0
var bar_phase := 0.0
var period := 0.5
var beat_count := 0
var beat_age := 4.0
var beat_pulse := 0.0
var bar_pulse := 0.0
var percussive := 0.0
var harmonic := 0.0
var intensity := 0.0
var brightness := 0.0
var build := 0.0
var drop_pulse := 0.0
var drop_age := MusicMap.FAR
var section := 0
var section_progress := 0.0
var section_energy := 0.5
var next_energy := 0.5
var section_change := 0.0
var palette_group := 0.0
var anticipation := 0.0
var flash := 0.0
var flash_clock := 0.0
var last_flash := -INF
var flash_count := 0
var _beats_before := -1
var _bars_before := -1
var _drops_before := -1
var _live_release := 0.0


func set_map(value: MusicMap) -> void:
	map = value
	_beats_before = -1
	_bars_before = -1
	_drops_before = -1
	time = -1.0
	active = false


func reset() -> void:
	beat_pulse = 0.0
	bar_pulse = 0.0
	drop_pulse = 0.0
	section_change = 0.0
	anticipation = 0.0
	flash = 0.0
	build = 0.0
	percussive = 0.0
	harmonic = 0.0
	intensity = 0.0
	_beats_before = -1
	_bars_before = -1
	_drops_before = -1
	time = -1.0


func request_flash(strength: float) -> bool:
	if flash_clock - last_flash < FLASH_INTERVAL:
		return false
	last_flash = flash_clock
	flash_count += 1
	flash = maxf(flash, clampf(strength, 0.0, 1.0) * FLASH_LIMIT)
	return true


func update(now: float, delta: float, playing: bool, live: Dictionary) -> void:
	flash_clock += delta
	beat_pulse *= exp(-delta * 9.0)
	bar_pulse *= exp(-delta * 4.0)
	drop_pulse *= exp(-delta * 1.2)
	section_change *= exp(-delta * 2.0)
	flash *= exp(-delta * FLASH_DECAY)
	beat_age = minf(4.0, beat_age + (delta if playing else 0.0))
	var mapped := map != null and map.covers(now) and map.has_beats()
	if mapped != active:
		active = mapped
		_beats_before = -1
	if active:
		_update_mapped(now, delta, live)
	else:
		_update_live(delta, live)
	time = now


func _update_mapped(now: float, delta: float, live: Dictionary) -> void:
	var jumped := time < 0.0 or absf(now - time) > SEEK_JUMP or now < time
	var beats := map.beats_until(now)
	var bars := map.downbeats.bsearch(now, false)
	var drops := map.drops.bsearch(now, false)
	var index := map.section_index(now)
	if jumped or _beats_before < 0:
		if _beats_before >= 0 and beats != _beats_before:
			beat_count += 1
	else:
		if beats > _beats_before:
			beat_count += beats - _beats_before
			beat_pulse = 1.0
			beat_age = now - map.beats[beats - 1]
		if bars > _bars_before:
			bar_pulse = 1.0
		if drops > _drops_before:
			drop_pulse = 1.0
			request_flash(1.0)
		if index != section:
			section_change = 1.0
			if map.energy_of(index) > map.energy_of(section) + 0.2 and drops == _drops_before:
				request_flash(0.5)
	_beats_before = beats
	_bars_before = bars
	_drops_before = drops
	section = index
	beat_phase = map.beat_phase(now)
	bar_phase = map.bar_phase(now)
	period = map.beat_period(now)
	percussive = maxf(map.sample("percussive", now), percussive * exp(-delta * 10.0))
	harmonic = lerpf(harmonic, map.sample("harmonic", now), 1.0 - exp(-delta * 6.0))
	intensity = lerpf(intensity, map.sample("intensity", now), 1.0 - exp(-delta * 4.0))
	brightness = lerpf(brightness, map.sample("brightness", now), 1.0 - exp(-delta * 6.0))
	var ramp := map.build_amount(now)
	build = ramp * ramp * (3.0 - 2.0 * ramp) if not map.drops.is_empty() else clampf(float(live.get("tension", 0.0)), 0.0, 1.0)
	drop_age = map.drop_age(now)
	section_progress = map.section_progress(now)
	section_energy = lerpf(section_energy, map.energy_of(index), 1.0 - exp(-delta * 1.5))
	next_energy = map.energy_of(index + 1) if index + 1 < map.sections.size() else map.energy_of(index)
	palette_group = float(map.group_of(index))
	var remaining := map.next_section_in(now)
	var window := ANTICIPATION_BEATS * period
	anticipation = clampf(1.0 - remaining / window, 0.0, 1.0) if remaining < window and next_energy > map.energy_of(index) + 0.15 else 0.0


func _update_live(delta: float, live: Dictionary) -> void:
	var transients: Vector3 = live.get("transients", Vector3.ZERO)
	percussive = maxf(clampf(transients.x * 0.6 + transients.z * 0.5 + float(live.get("impulse", 0.0)) * 0.5, 0.0, 1.0), percussive * exp(-delta * 10.0))
	harmonic = lerpf(harmonic, clampf(float(live.get("mids", 0.0)) * 1.4, 0.0, 1.0), 1.0 - exp(-delta * 4.0))
	intensity = lerpf(intensity, clampf(float(live.get("arousal", 0.0)), 0.0, 1.0), 1.0 - exp(-delta * 2.0))
	brightness = lerpf(brightness, clampf(float(live.get("centroid", 0.5)), 0.0, 1.0), 1.0 - exp(-delta * 3.0))
	beat_phase = float(live.get("beat_phase", 0.0))
	bar_phase = float(live.get("bar_phase", 0.0))
	period = float(live.get("period", 0.5))
	build = clampf(float(live.get("tension", 0.0)), 0.0, 1.0)
	var release := float(live.get("release", 0.0))
	if release > 0.95 and _live_release <= 0.95:
		drop_pulse = 1.0
		drop_age = 0.0
		request_flash(0.8)
	_live_release = release
	drop_age = minf(MusicMap.FAR, drop_age + delta)
	section_energy = lerpf(section_energy, intensity, 1.0 - exp(-delta * 0.5))
	next_energy = section_energy
	section_progress = 0.0
	anticipation = 0.0


func apply(material: ShaderMaterial) -> void:
	material.set_shader_parameter("music_map", 1.0 if active else 0.0)
	material.set_shader_parameter("beat_pulse", beat_pulse)
	material.set_shader_parameter("bar_pulse", bar_pulse)
	material.set_shader_parameter("percussive", percussive)
	material.set_shader_parameter("harmonic", harmonic)
	material.set_shader_parameter("map_intensity", intensity)
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("build", build)
	material.set_shader_parameter("drop_pulse", drop_pulse)
	material.set_shader_parameter("drop_age", minf(drop_age, 1000.0))
	material.set_shader_parameter("section_energy", section_energy)
	material.set_shader_parameter("next_energy", next_energy)
	material.set_shader_parameter("section_progress", section_progress)
	material.set_shader_parameter("section_change", section_change)
	material.set_shader_parameter("palette_group", palette_group)
	material.set_shader_parameter("anticipation", anticipation)
	material.set_shader_parameter("flash", flash)
	if active:
		material.set_shader_parameter("beat_phase", beat_phase)
		material.set_shader_parameter("bar_phase", bar_phase)
		material.set_shader_parameter("groove", 1.0)
		if not map.drops.is_empty():
			material.set_shader_parameter("tension", build)
			material.set_shader_parameter("release", drop_pulse)
