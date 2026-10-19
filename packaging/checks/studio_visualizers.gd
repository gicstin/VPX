extends SceneTree

var failures := 0
var checks := 0
var field: Node
var captures := "/tmp/vpx-studio-captures"

func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func audition(mode: int) -> void:
	field.reset()
	for frame in 240:
		var data := PackedFloat32Array()
		data.resize(2400)
		for band in 48:
			var level := 0.35 + 0.45 * pow(maxf(0.0, sin(band * 0.25 + frame * 0.045)), 3.0)
			data[band] = level if mode == 1 else level * 0.7
			data[48 + band] = level * 0.7 if mode == 1 else level
		field.feed(data, {"channels": 2, "rms": 0.2, "correlation": 1.0 if mode == 1 else -1.0})
		var wave := PackedFloat32Array()
		wave.resize(512)
		for sample in 256:
			wave[sample] = sin(sample * 0.08 + frame * 0.03) * 0.5
			wave[256 + sample] = wave[sample] * (1.0 if mode == 1 else -1.0)
		field.feed_scope(wave)
		field._process(1.0 / 60.0)

func capture() -> Image:
	await process_frame
	RenderingServer.force_draw()
	return root.get_texture().get_image()

func difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
			count += 1
	return total / count

func run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(captures)
	root.size = Vector2i(1280, 720)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	settings.visualizer_motion = 0.6
	settings.visualizer_intensity = 0.75
	check(settings.VISUALIZER_PRESET_MAX == settings.VISUALIZER_PRESETS.size() - 1, "preset bounds match catalog")
	check(settings.VISUALIZER_PRESETS.size() - settings.VISUALIZER_STUDIO_START == settings.VISUALIZER_STUDIO_GUIDES.size(), "each studio scene has an axis guide")
	var previews := load("res://assets/visualizer_previews.png") as Texture2D
	check(previews.get_width() == 1280 and previews.get_height() == ceili(settings.VISUALIZER_PRESETS.size() / 8.0) * 90, "picker atlas covers every scene")
	var camera := Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var previous: Image
	for index in range(settings.VISUALIZER_STUDIO_START, settings.VISUALIZER_PRESETS.size()):
		settings.apply("visualizer_preset", index)
		var title: String = settings.VISUALIZER_PRESETS[index]
		check(field.find_children("*", "Label3D", true, false).is_empty(), title + " has no permanent labels")
		for quality in 3:
			field.quality = quality
			field._apply_quality()
			if index < field.PSYCHE_START:
				check(field.layers[0].multimesh.visible_instance_count >= 96, title + " retains all frequency bands at quality " + str(quality))
			else:
				var valid := true
				for layer in field.layers:
					valid = valid and layer.multimesh.visible_instance_count >= 0 and layer.multimesh.visible_instance_count <= layer.multimesh.instance_count
				check(valid and field.layers[0].multimesh.visible_instance_count > 0, title + " retains valid geometry at quality " + str(quality))
		field.reset()
		field._process(1.0)
		var silent := await capture()
		audition(1)
		var first := await capture()
		first.save_png(captures.path_join("%02d.png" % index))
		check(difference(first, silent) > 0.003, title + " responds to audio")
		audition(2)
		var second := await capture()
		second.save_png(captures.path_join("%02d-alternate.png" % index))
		if index != 56:
			check(difference(first, second) > 0.001, title + " distinguishes stereo inputs")
		if index == 53:
			check(field.correlation == -1.0 and field.materials[0].get_shader_parameter("correlation") == -1.0, "antiphase correlation reaches shader")
		if index == 59:
			var ring = field.stereo.correlation_ring
			check(ring.head >= 0 and ring.image.get_pixel(0, ring.head).r < -0.95, "correlation history preserves negative phase")
			check(field.materials[0].get_shader_parameter("correlation_texture") == ring.texture, "correlation history reaches causeway shader")
		if index >= 64:
			for quality in 3:
				field.quality = quality
				field._apply_quality()
				var quality_frame := await capture()
				check(difference(quality_frame, silent) > 0.003, title + " renders reactive geometry at quality " + str(quality))
			settings.visualizer_motion = 0.0
			field._process(0.0)
			for material in field.materials:
				material.set_shader_parameter("palette", 0.0)
			var frozen := await capture()
			field.clock += 10.0
			field._process(0.0)
			for material in field.materials:
				material.set_shader_parameter("palette", 0.0)
			var later := await capture()
			check(difference(frozen, later) < 0.0001, title + " freezes ambient movement at zero motion")
			settings.visualizer_motion = 0.6
			settings.visualizer_intensity = 0.0
			field._process(0.0)
			var dark := await capture()
			check(difference(second, dark) > 0.003, title + " respects intensity control")
			settings.visualizer_intensity = 0.75
			field._process(0.0)
			for turn in 3:
				camera.rotation.y = (turn + 1) * PI * 0.5
				var side := await capture()
				side.save_png(captures.path_join("%02d-view-%d.png" % [index, turn + 1]))
			camera.rotation.y = 0.0
		if previous != null:
			check(difference(first, previous) > 0.01, title + " has distinct geometry")
		previous = first
		field.silence()
		field._process(1.0)
		check(field.stereo.band_ring.head == -1 and field.stereo.correlation_ring.head == -1 and not field.stereo.scope_active and field.correlation == 1.0, title + " clears stale analysis")
	settings.apply("visualizer_preset", settings.VISUALIZER_PRESET_MAX)
	field.cycle_preset()
	check(settings.visualizer_preset == 0, "cycling wraps through expanded catalog")
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
