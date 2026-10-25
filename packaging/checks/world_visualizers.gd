extends SceneTree

const WORLDS := ["Valley of Sources", "Sound Cathedral", "Deep Current"]

var checks := 0
var failures := 0
var only := ""
var settings: Node
var camera: Camera3D
var field
var captures := ""


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find("--case")
	if index >= 0 and index + 1 < arguments.size():
		only = arguments[index + 1]
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func setup() -> void:
	root.size = Vector2i(960, 540)
	settings = root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 3
	settings.visualizer_motion = 0.6
	settings.visualizer_intensity = 0.75
	settings.visualizer_sensitivity = 1.0
	camera = Camera3D.new()
	camera.fov = 90.0
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	captures = OS.get_environment("VPX_WORLD_CAPTURES")
	if captures.is_empty():
		captures = OS.get_user_data_dir().path_join("world-captures")
	DirAccess.make_dir_recursive_absolute(captures)


func world_index(world: int) -> int:
	return settings.VISUALIZER_PRESETS.find(WORLDS[world])


func select(world: int) -> void:
	settings.apply("visualizer_preset", world_index(world))
	field.reset()
	field.set_music_map(null)
	field.music_time = -1.0
	field.clock = 6.0


func spectrum(left: float, right: float) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(2400)
	for band in 48:
		data[band] = left * (0.75 + 0.25 * sin(band * 0.4))
		data[48 + band] = right * (0.75 + 0.25 * sin(band * 0.4))
	return data


func play(seconds: float, left: float, right: float, start_time := -1.0, fps := 60.0) -> void:
	for frame in int(seconds * fps):
		field.feed(spectrum(left, right), {"channels": 2, "rms": (left + right) * 0.15, "width": 0.4, "onset": 0.1 if frame % 30 == 0 else 0.0})
		if start_time >= 0.0:
			field.music_time = start_time + frame / fps
		field.clock += 1.0 / fps
		field._process(1.0 / fps)


func capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(captures.path_join(label + ".png"))
	return image


func luminance(image: Image, region: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(region.position.y, region.end.y, 3):
		for x in range(region.position.x, region.end.x, 3):
			var c := image.get_pixel(x, y)
			total += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			count += 1
	return total / maxi(1, count)


func lit_fraction(image: Image, threshold := 0.06) -> float:
	var lit := 0
	var count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var c := image.get_pixel(x, y)
			lit += int(maxf(c.r, maxf(c.g, c.b)) > threshold)
			count += 1
	return float(lit) / count


func centroid_x(a: Image, b: Image) -> float:
	var weighted := 0.0
	var total := 0.0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var gain := maxf(0.0, (ca.r + ca.g + ca.b) - (cb.r + cb.g + cb.b))
			weighted += gain * x
			total += gain
	return weighted / maxf(total, 0.000001) / a.get_width()


func make_map(duration := 60.0, bpm := 120.0, drop := 32.0, build_start := 24.0) -> RefCounted:
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
	var curves := {}
	for key in load("res://scripts/music_map.gd").CURVES:
		var curve := PackedFloat32Array()
		curve.resize(frames)
		for i in frames:
			var time := i / rate
			var after := 1.0 if time >= drop else 0.0
			curve[i] = clampf(0.3 + after * 0.6 + (0.2 if key == "percussive" and fmod(time, period) < 0.08 else 0.0), 0.0, 1.0)
		curves[key] = curve
	var data := {"version": 3, "rate": rate, "duration": duration, "analysed": duration, "tempo": bpm, "beats": beats, "downbeats": downbeats,
		"sections": PackedFloat32Array([0.0, build_start, drop]), "section_energy": PackedFloat32Array([0.3, 0.4, 1.0]), "section_group": PackedFloat32Array([0, 1, 2]),
		"drops": PackedFloat32Array([drop]), "build_starts": PackedFloat32Array([build_start])}
	data.merge(curves)
	return load("res://scripts/music_map.gd").from_dictionary(data)


func case_worlds_render() -> void:
	for world in WORLDS.size():
		select(world)
		play(2.0, 0.6, 0.6)
		var image := await capture("render_%d" % world)
		var lit := lit_fraction(image)
		check(lit > 0.04 and lit < 0.9, "%s renders a lit, non-saturated scene (lit %.3f)" % [WORLDS[world], lit])


func case_ground_below_horizon() -> void:
	for world in WORLDS.size():
		select(world)
		play(1.5, 0.5, 0.5)
		var image := await capture("ground_%d" % world)
		var w := image.get_width()
		var h := image.get_height()
		var floor_band := luminance(image, Rect2i(0, int(h * 0.82), w, int(h * 0.18)))
		var grounded := floor_band > 0.002
		check(grounded, "%s shows lit ground below the horizon (floor %.4f)" % [WORLDS[world], floor_band])


func case_left_source_on_left() -> void:
	for world in WORLDS.size():
		select(world)
		play(1.5, 0.0, 0.0)
		var silent := await capture("silent_%d" % world)
		field.reset()
		play(2.5, 0.85, 0.0)
		var left := await capture("left_%d" % world)
		var centre := centroid_x(left, silent)
		check(centre < 0.4, "%s puts a hard-left source on the left (new light centred at %.2f of the width)" % [WORLDS[world], centre])


func case_right_source_on_right() -> void:
	for world in WORLDS.size():
		select(world)
		play(1.5, 0.0, 0.0)
		var silent := await capture("silent_r_%d" % world)
		field.reset()
		play(2.5, 0.0, 0.85)
		var right := await capture("right_%d" % world)
		var centre := centroid_x(right, silent)
		check(centre > 0.6, "%s puts a hard-right source on the right (new light centred at %.2f of the width)" % [WORLDS[world], centre])


func case_build_brightens_front() -> void:
	for world in WORLDS.size():
		select(world)
		field.set_music_map(make_map())
		play(1.0, 0.4, 0.4, 14.0)
		var calm := await capture("calm_%d" % world)
		field.reset()
		field.set_music_map(make_map())
		play(1.0, 0.4, 0.4, 30.5)
		var building := await capture("build_%d" % world)
		var w := calm.get_width()
		var h := calm.get_height()
		var region := Rect2i(int(w * 0.3), int(h * 0.3), int(w * 0.4), int(h * 0.4))
		var edge := Rect2i(0, 0, int(w * 0.12), h)
		var front_gain := luminance(building, region) - luminance(calm, region)
		var edge_gain := luminance(building, edge) - luminance(calm, edge)
		check(field.timeline.build > 0.6, "%s timeline is deep in the build (%.2f)" % [WORLDS[world], field.timeline.build])
		check(front_gain > 0.0 and front_gain > edge_gain, "%s build draws light to the front (front %+.4f edge %+.4f)" % [WORLDS[world], front_gain, edge_gain])


func case_drop_lifts_scene() -> void:
	for world in WORLDS.size():
		select(world)
		field.set_music_map(make_map())
		play(1.0, 0.5, 0.5, 30.0)
		var before := await capture("predrop_%d" % world)
		play(1.2, 0.5, 0.5, 31.0)
		var after := await capture("drop_%d" % world)
		var full := Rect2i(0, 0, before.get_width(), before.get_height())
		check(field.timeline.drop_age < 0.5 and field.timeline.drop_pulse > 0.4, "%s timeline registers the drop" % WORLDS[world])
		check(luminance(after, full) > luminance(before, full), "%s scene lifts after the drop (%.4f -> %.4f)" % [WORLDS[world], luminance(before, full), luminance(after, full)])


func case_flash_is_limited() -> void:
	select(0)
	var peaks := 0
	var previous := 0.0
	var rising := false
	var top := 0.0
	for frame in 600:
		if frame % 6 == 0:
			field.timeline.request_flash(1.0)
		field.timeline.update(-1.0, 1.0 / 60.0, true, {})
		var value: float = field.timeline.flash
		top = maxf(top, value)
		if value > previous + 0.05 and not rising:
			peaks += 1
			rising = true
		elif value < previous:
			rising = false
		previous = value
	check(peaks <= 31, "10 Hz flash requests give at most 3 flashes per second (%d in 10 s)" % peaks)
	check(top <= load("res://scripts/music_timeline.gd").FLASH_LIMIT + 0.001, "flash never exceeds %.2f (%.3f)" % [load("res://scripts/music_timeline.gd").FLASH_LIMIT, top])


func case_flash_luminance_bounded() -> void:
	for world in WORLDS.size():
		select(world)
		field.set_music_map(make_map())
		play(1.0, 0.5, 0.5, 31.0)
		play(0.05, 0.5, 0.5, 32.0)
		var peak := await capture("flash_peak_%d" % world)
		play(0.9, 0.5, 0.5, 32.05)
		var settled := await capture("flash_settled_%d" % world)
		var full := Rect2i(0, 0, peak.get_width(), peak.get_height())
		var transient := luminance(peak, full) - luminance(settled, full)
		check(transient < 0.05, "%s drop flash transient stays gentle (mean luminance %+.4f over the settled scene)" % [WORLDS[world], transient])


func case_overlay_hides_ground() -> void:
	select(0)
	field.compositing_overlay = true
	field._apply_quality()
	check(field.layers[0].multimesh.visible_instance_count == 0, "ground hidden when composited over video")
	field.compositing_overlay = false
	field._apply_quality()
	check(field.layers[0].multimesh.visible_instance_count == 1, "ground returns without compositing")


func case_quality_tiers() -> void:
	for world in WORLDS.size():
		select(world)
		var counts := []
		for tier in 3:
			settings.apply("visualizer_quality", tier + 1)
			counts.append(field.layers[1].multimesh.visible_instance_count)
		settings.apply("visualizer_quality", 3)
		check(counts[0] < counts[1] and counts[1] < counts[2], "%s mote count scales with quality %s" % [WORLDS[world], str(counts)])
		check(field.layers[3].multimesh.visible_instance_count == field.WORLD_STRUCTURES[world], "%s structure count %d" % [WORLDS[world], field.layers[3].multimesh.visible_instance_count])


func case_frame_time() -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for world in WORLDS.size():
		select(world)
		play(1.0, 0.6, 0.5)
		var worst := 0.0
		var total := 0.0
		for frame in 90:
			field.feed(spectrum(0.6, 0.5), {"channels": 2, "rms": 0.15})
			field.clock += 1.0 / 60.0
			field._process(1.0 / 60.0)
			await process_frame
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			total += gpu
			if frame > 10:
				worst = maxf(worst, gpu)
		check(total / 90.0 < 4.0, "%s GPU time %.2f ms average (worst %.2f) at 960x540" % [WORLDS[world], total / 90.0, worst])


func case_distinct_worlds() -> void:
	var images: Array[Image] = []
	for world in WORLDS.size():
		select(world)
		play(2.0, 0.6, 0.4)
		images.append(await capture("distinct_%d" % world))
	for a in WORLDS.size():
		for b in range(a + 1, WORLDS.size()):
			var changed := 0
			var occupied := 0
			for y in range(0, images[a].get_height(), 4):
				for x in range(0, images[a].get_width(), 4):
					var first := images[a].get_pixel(x, y)
					var second := images[b].get_pixel(x, y)
					var first_lit := maxf(first.r, maxf(first.g, first.b)) > 0.08
					var second_lit := maxf(second.r, maxf(second.g, second.b)) > 0.08
					changed += int(first_lit != second_lit)
					occupied += int(first_lit or second_lit)
			var distance := float(changed) / maxi(1, occupied)
			check(distance > 0.3, "%s and %s look different (%.3f)" % [WORLDS[a], WORLDS[b], distance])


func run() -> void:
	create_timer(240.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	setup()
	for method in get_method_list():
		var name: String = method.name
		if name.begins_with("case_") and (only.is_empty() or only.split(",").has(name.trim_prefix("case_"))):
			await call(name)
	print("WORLD_VISUALIZERS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
