extends SceneTree

const Synth := preload("res://packaging/checks/music_synth.gd")

var checks := 0
var failures := 0
var only := ""
var map_script: GDScript
var timeline_script: GDScript
var store_script: GDScript


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find("--case")
	if index >= 0 and index + 1 < arguments.size():
		only = arguments[index + 1]
	map_script = load("res://scripts/music_map.gd")
	timeline_script = load("res://scripts/music_timeline.gd")
	store_script = load("res://scripts/music_map_store.gd")
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func make_map(duration := 64.0, bpm := 120.0, drop := 32.0, build_start := 24.0) -> RefCounted:
	var period := 60.0 / bpm
	var beats := PackedFloat32Array()
	var downbeats := PackedFloat32Array()
	var t := 0.0
	var index := 0
	while t < duration:
		beats.append(t)
		if index % 4 == 0:
			downbeats.append(t)
		t += period
		index += 1
	var rate := 22050.0 / 512.0
	var frames := int(duration * rate) + 1
	var data := {"version": 3, "rate": rate, "duration": duration, "analysed": duration, "tempo": bpm, "beats": beats, "downbeats": downbeats,
		"sections": PackedFloat32Array([0.0, 16.0, drop]), "section_energy": PackedFloat32Array([0.2, 0.3, 1.0]), "section_group": PackedFloat32Array([0, 1, 0]),
		"drops": PackedFloat32Array([drop]), "build_starts": PackedFloat32Array([build_start])}
	for key in map_script.CURVES:
		var curve := PackedFloat32Array()
		curve.resize(frames)
		for i in frames:
			curve[i] = 0.9 if i / rate >= drop else 0.2
		data[key] = curve
	return map_script.from_dictionary(data)


func step(timeline: RefCounted, from: float, to: float, fps := 90.0) -> void:
	var frames := int(round((to - from) * fps))
	for frame in frames:
		timeline.update(from + (frame + 1) / fps, 1.0 / fps, true, {})


func case_map_rejects_empty() -> void:
	check(map_script.from_dictionary({}) == null, "empty dictionary gives no map")


func case_beat_phase_exact() -> void:
	var map: RefCounted = make_map()
	var worst := 0.0
	for beat in range(1, 100):
		var time: float = map.beats[beat]
		worst = maxf(worst, minf(map.beat_phase(time + 0.0001), 1.0 - map.beat_phase(time + 0.0001)))
	check(worst < 0.001, "beat phase is 0 on every beat (worst %.4f)" % worst)
	check(absf(map.beat_phase(map.beats[10] + 0.25) - 0.5) < 0.001, "beat phase is 0.5 half way")


func case_bar_phase_exact() -> void:
	var map: RefCounted = make_map()
	check(absf(map.bar_phase(8.0001)) < 0.001 and absf(map.bar_phase(9.0) - 0.5) < 0.001, "bar phase follows downbeats (%.3f, %.3f)" % [map.bar_phase(8.0001), map.bar_phase(9.0)])


func case_build_ramp() -> void:
	var map: RefCounted = make_map()
	var previous := -1.0
	var monotonic := true
	for i in 80:
		var value: float = map.build_amount(24.0 + i * 0.1)
		monotonic = monotonic and value >= previous
		previous = value
	check(monotonic and map.build_amount(23.9) == 0.0 and map.build_amount(32.1) == 0.0, "build ramps only inside the build")
	check(absf(map.build_amount(28.0) - 0.5) < 0.001, "build is half way at the midpoint")


func case_drop_queries() -> void:
	var map: RefCounted = make_map()
	check(absf(map.next_drop_in(30.0) - 2.0) < 0.001 and absf(map.drop_age(33.0) - 1.0) < 0.001, "next drop and drop age")
	check(map.drop_age(10.0) >= map.FAR and map.next_drop_in(40.0) >= map.FAR, "no drop reported outside range")


func case_section_queries() -> void:
	var map: RefCounted = make_map()
	check(map.section_index(20.0) == 1 and absf(map.section_progress(24.0) - 0.5) < 0.001, "section index and progress")
	check(absf(map.next_section_in(30.0) - 2.0) < 0.001, "time to next section")


func case_beat_count_once_per_beat() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 0.0, 0.01)
	var start: int = timeline.beat_count
	step(timeline, 0.01, 10.01)
	check(timeline.beat_count - start == 20, "20 beats counted in 10 s at 120 BPM (%d)" % (timeline.beat_count - start))


func case_beat_pulse_on_beat() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 0.0, 4.49)
	var before: float = timeline.beat_pulse
	step(timeline, 4.49, 4.505)
	check(before < 0.05 and timeline.beat_pulse > 0.85, "beat pulse fires on the beat (%.2f -> %.2f)" % [before, timeline.beat_pulse])


func case_seek_no_pulse_storm() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 0.0, 2.0)
	var count: int = timeline.beat_count
	timeline.update(40.0, 1.0 / 90.0, true, {})
	check(timeline.beat_count - count <= 1 and timeline.drop_pulse < 0.5, "seeking past beats and the drop does not burst (beats +%d, drop %.2f)" % [timeline.beat_count - count, timeline.drop_pulse])
	timeline.update(10.0, 1.0 / 90.0, true, {})
	check(timeline.beat_count >= count, "seeking back keeps the beat count monotonic")


func case_drop_pulse_and_flash() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 20.0, 31.98)
	var flashes: int = timeline.flash_count
	step(timeline, 31.98, 32.02)
	check(timeline.drop_pulse > 0.9 and timeline.flash_count == flashes + 1, "drop fires a pulse and one flash")
	check(timeline.flash <= timeline_script.FLASH_LIMIT, "drop flash within limit")


func case_build_value() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 20.0, 28.0)
	check(absf(timeline.build - 0.5) < 0.02, "timeline build is eased mid-way (%.3f)" % timeline.build)
	step(timeline, 28.0, 31.9)
	check(timeline.build > 0.95, "timeline build near 1 before the drop (%.3f)" % timeline.build)


func case_anticipation_before_louder_section() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 20.0, 30.5)
	var early: float = timeline.anticipation
	step(timeline, 30.5, 31.6)
	check(early == 0.0 and timeline.anticipation > 0.6, "anticipation rises in the last beats before a louder section (%.2f -> %.2f)" % [early, timeline.anticipation])


func case_live_fallback() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.update(5.0, 1.0 / 90.0, true, {"beat_phase": 0.3, "tension": 0.7, "transients": Vector3(1, 0, 0)})
	check(not timeline.active and absf(timeline.beat_phase - 0.3) < 0.001 and absf(timeline.build - 0.7) < 0.001, "no map uses the live estimate")
	timeline.set_map(make_map(10.0))
	timeline.update(20.0, 1.0 / 90.0, true, {"beat_phase": 0.6})
	check(not timeline.active and absf(timeline.beat_phase - 0.6) < 0.001, "time past the analysed range falls back to live")


func case_live_release_flash() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.update(1.0, 1.0 / 90.0, true, {"release": 0.2})
	timeline.update(1.01, 1.0 / 90.0, true, {"release": 1.0})
	check(timeline.drop_pulse > 0.9 and timeline.flash_count == 1, "live drop detection still pulses")


func case_flash_rate_limit() -> void:
	var timeline: RefCounted = timeline_script.new()
	var granted := 0
	for frame in 900:
		if frame % 9 == 0 and timeline.request_flash(1.0):
			granted += 1
		timeline.update(-1.0, 1.0 / 90.0, true, {})
	check(granted <= 31, "flash requests at 10 Hz are granted at most 3 per second (%d in 10 s)" % granted)


func case_apply_overrides_affect() -> void:
	var timeline: RefCounted = timeline_script.new()
	timeline.set_map(make_map())
	step(timeline, 0.0, 9.25)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/resonance_world.gdshader")
	timeline.apply(material)
	check(absf(float(material.get_shader_parameter("beat_phase")) - 0.5) < 0.02, "mapped beat phase reaches shaders")
	check(float(material.get_shader_parameter("music_map")) == 1.0, "music_map uniform marks the mapped timeline")


func case_store_skips_streams() -> void:
	var store: RefCounted = store_script.new()
	check(store.request("https://example.com/track.mp3") == null and not store.is_pending(), "network paths are not analysed")
	check(store.request("/nonexistent/track.flac") == null and not store.is_pending(), "missing files are not analysed")


func wait_for(store: RefCounted, seconds: float) -> RefCounted:
	var waited := 0.0
	while waited < seconds:
		var map: RefCounted = store.poll()
		if map != null:
			return map
		await create_timer(0.05).timeout
		waited += 0.05
	return null


func case_store_analyses_and_caches() -> void:
	var synth := Synth.new(124.0, 12)
	synth.four_on_floor(0, 12)
	synth.offbeat_hats(0, 12)
	synth.normalise()
	var path := OS.get_user_data_dir().path_join("store_track.wav")
	synth.save_wav(path)
	var store: RefCounted = store_script.new()
	store.directory = "user://music_maps_check"
	check(store.request(path) == null and store.is_pending(), "first request starts analysis")
	var map: RefCounted = await wait_for(store, 15.0)
	check(map != null and absf(map.tempo - 124.0) < 1.0, "analysis completes with tempo %.2f" % (map.tempo if map != null else 0.0))
	var second: RefCounted = store_script.new()
	second.directory = "user://music_maps_check"
	var started := Time.get_ticks_usec()
	var cached: RefCounted = second.request(path)
	check(cached != null and not second.is_pending(), "second store loads the cached map")
	check((Time.get_ticks_usec() - started) / 1000.0 < 100.0, "cached map loads in %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	check(cached != null and cached.beats.size() == map.beats.size(), "cached map matches")


func case_store_invalidates_on_change() -> void:
	var synth := Synth.new(120.0, 8)
	synth.four_on_floor(0, 8)
	synth.normalise()
	var path := OS.get_user_data_dir().path_join("changing_track.wav")
	synth.save_wav(path)
	var store: RefCounted = store_script.new()
	store.directory = "user://music_maps_change"
	var key: String = store.cache_key(path)
	var longer := Synth.new(120.0, 10)
	longer.four_on_floor(0, 10)
	longer.normalise()
	longer.save_wav(path)
	check(store.cache_key(path) != key, "cache key changes when the file changes")


func case_store_switches_tracks() -> void:
	var synth := Synth.new(120.0, 16)
	synth.four_on_floor(0, 16)
	synth.normalise()
	var first := OS.get_user_data_dir().path_join("switch_a.wav")
	var second := OS.get_user_data_dir().path_join("switch_b.wav")
	synth.save_wav(first)
	synth.save_wav(second)
	var store: RefCounted = store_script.new()
	store.directory = "user://music_maps_switch"
	store.request(first)
	store.request(second)
	var map: RefCounted = await wait_for(store, 15.0)
	check(map != null and store.map_path == second, "switching tracks mid-analysis keeps the newest track")


func case_field_uses_map_beats() -> void:
	var field: Node = load("res://scripts/resonance_field.gd").new()
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	field.set_music_map(make_map())
	var spectrum := PackedFloat32Array()
	spectrum.resize(2400)
	field.music_time = 0.0
	field._process(1.0 / 90.0)
	var start: int = field.beat_count
	for frame in 900:
		field.music_time = (frame + 1) / 90.0
		field.feed(spectrum, {"channels": 2, "rms": 0.0})
		field._process(1.0 / 90.0)
	check(field.beat_count - start == 20, "field beat count follows the map (%d beats in 10 s)" % (field.beat_count - start))
	field.queue_free()


func case_field_floor_matches_vr() -> void:
	var origin := XROrigin3D.new()
	root.add_child(origin)
	var camera := XRCamera3D.new()
	origin.add_child(camera)
	camera.position = Vector3(0, 1.45, 0)
	var field: Node = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	field.vr_zoom = true
	root.add_child(field)
	field.set_process(false)
	root.get_node("Settings").apply("visualizer_preset", root.get_node("Settings").VISUALIZER_PRESETS.find("Valley of Sources"))
	field.set_active(true)
	check(absf(field.ground_level() + 1.45) < 0.01, "VR world floor sits on the real floor (%.2f)" % field.ground_level())
	camera.position = Vector3(0, 0.1, 0)
	field.place()
	check(absf(field.ground_level() - field.WORLD_GROUND[0]) < 0.01, "implausible floor falls back to the default height")
	field.vr_zoom = false
	check(absf(field.ground_level() - field.WORLD_GROUND[0]) < 0.01, "desktop uses the default floor height")
	field.queue_free()
	origin.queue_free()


func case_store_cancel_does_not_block() -> void:
	var synth := Synth.new(120.0, 96)
	synth.four_on_floor(0, 96)
	synth.normalise()
	var path := OS.get_user_data_dir().path_join("cancel_track.wav")
	synth.save_wav(path)
	var store: RefCounted = store_script.new()
	store.directory = "user://music_maps_cancel"
	store.request(path)
	var started := Time.get_ticks_usec()
	store.cancel()
	var blocked := (Time.get_ticks_usec() - started) / 1000.0
	check(blocked < 5.0 and not store.is_pending(), "cancel returns immediately (%.2f ms)" % blocked)
	var waited := 0.0
	while not store.retiring.is_empty() and waited < 5.0:
		store.poll()
		await create_timer(0.05).timeout
		waited += 0.05
	check(store.retiring.is_empty(), "cancelled analysis winds down in the background")


func run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	for method in get_method_list():
		var name: String = method.name
		if name.begins_with("case_") and (only.is_empty() or only.split(",").has(name.trim_prefix("case_"))):
			await call(name)
	print("MUSIC_TIMELINE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
