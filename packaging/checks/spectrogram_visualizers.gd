extends "res://packaging/checks/studio_visualizers.gd"


func signal_history(swapped := false, mono := false, steady := false) -> void:
	field.reset()
	for frame in 270:
		var data := PackedFloat32Array()
		data.resize(2400)
		for band in 48:
			var sweep := 0.3 + 0.35 * pow(maxf(0.0, sin(band * 0.27 + frame * 0.05)), 4.0)
			var attack := 0.25 if frame % 30 < 3 else 0.0
			var left := 0.45 if steady else clampf(sweep + attack, 0.0, 1.0)
			var right := left if mono else left * 0.55
			data[band] = right if swapped else left
			data[48 + band] = left if swapped else right
		field.feed(data, {"channels": 1 if mono else 2, "rms": 0.15})
		field._process(1.0 / 60.0)


func probe_sample(expected: Vector2, label: String) -> void:
	var shot := await capture()
	var value := shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2).srgb_to_linear()
	var actual := Vector2((value.r - 0.5) * 2.0, value.g)
	check(actual.distance_to(expected) < 0.025, label + " actual=" + str(actual))


func verify_measurements() -> void:
	field.hide()
	var probe := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 3.0)
	probe.mesh = quad
	probe.position.z = -2.0
	root.add_child(probe)
	var source: String = field.SPECTROGRAM_SHADER.code
	var shader := Shader.new()
	shader.code = source.left(source.find("void vertex()")).replace("blend_add", "blend_mix") + """
uniform vec2 probe_uv = vec2(0.5, 0.0);
uniform float probe_channel = 0.0;
void fragment() {
	vec2 data = measurement(probe_uv, probe_channel);
	ALBEDO = vec3(data.x * 0.5 + 0.5, data.y, 0.0);
	if (OUTPUT_IS_SRGB) {
		ALBEDO = mix(1.055 * pow(ALBEDO, vec3(1.0 / 2.4)) - 0.055, ALBEDO * 12.92, lessThan(ALBEDO, vec3(0.0031308)));
	}
	ALPHA = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	probe.material_override = material
	var history := Image.create_empty(48, 384, false, Image.FORMAT_RF)
	history.fill(Color(0.2, 0.0, 0.0))
	history.fill_rect(Rect2i(0, 192, 48, 192), Color(0.6, 0.0, 0.0))
	var texture := ImageTexture.create_from_image(history)
	material.set_shader_parameter("spectral_history_texture", texture)
	material.set_shader_parameter("spectral_history_head", 191)
	material.set_shader_parameter("spectral_history_valid", 1.0)
	await probe_sample(Vector2(0.2, 0.2), "history reads left channel")
	material.set_shader_parameter("probe_channel", 1.0)
	await probe_sample(Vector2(0.6, 0.6), "history reads right channel without row bleed")
	material.set_shader_parameter("spectral_channel_count", 1)
	await probe_sample(Vector2(0.2, 0.2), "mono duplicates left into right")
	material.set_shader_parameter("spectral_channel_count", 2)
	material.set_shader_parameter("spectrogram_style", 4)
	await probe_sample(Vector2(1.0, 0.6), "balance maps +24 dB to upper rail")
	history.fill(Color(0.6, 0.0, 0.0))
	history.fill_rect(Rect2i(0, 192, 48, 192), Color(0.2, 0.0, 0.0))
	texture.update(history)
	await probe_sample(Vector2(-1.0, 0.6), "balance maps -24 dB to lower rail")
	material.set_shader_parameter("spectral_channel_count", 1)
	await probe_sample(Vector2(0.0, 0.6), "mono balance remains centred")
	material.set_shader_parameter("spectral_channel_count", 2)
	material.set_shader_parameter("probe_channel", 0.0)
	history.fill(Color(0.2, 0.0, 0.0))
	texture.update(history)
	material.set_shader_parameter("spectrogram_style", 5)
	await probe_sample(Vector2.ONE / 3.0, "noise view expands -48 dB within -60 to -24 dB")
	material.set_shader_parameter("spectrogram_style", 3)
	await probe_sample(Vector2.ZERO, "steady spectral energy produces no transient")
	history.fill_rect(Rect2i(0, 191, 48, 1), Color(0.26, 0.0, 0.0))
	texture.update(history)
	await probe_sample(Vector2(0.2, 0.2), "transient measures +3.6 dB over 67 ms")
	material.set_shader_parameter("spectral_history_valid", 0.01)
	await probe_sample(Vector2.ZERO, "transient ignores missing earlier samples")
	material.set_shader_parameter("spectral_history_valid", 1.0)
	material.set_shader_parameter("spectrogram_style", 0)
	material.set_shader_parameter("spectral_history_head", 1)
	history.fill_rect(Rect2i(0, 190, 48, 1), Color(0.7, 0.0, 0.0))
	texture.update(history)
	material.set_shader_parameter("probe_uv", Vector2(0.5, 3.0 / 45.0 / 3.8))
	await probe_sample(Vector2(0.7, 0.7), "history wraps at row zero")
	history.fill_rect(Rect2i(0, 1, 48, 1), Color(0.8, 0.0, 0.0))
	texture.update(history)
	material.set_shader_parameter("spectral_history_fraction", 0.5)
	material.set_shader_parameter("probe_uv", Vector2(0.5, 1.0 / 45.0 / 3.8))
	await probe_sample(Vector2(0.5, 0.5), "history interpolates between captured rows")
	material.set_shader_parameter("spectral_history_head", -1)
	await probe_sample(Vector2.ZERO, "empty history produces no signal")

	material.set_shader_parameter("spectral_history_head", 191)
	material.set_shader_parameter("spectral_history_fraction", 0.0)
	for band in 48:
		history.fill_rect(Rect2i(band, 0, 1, 384), Color((band + 0.5) / 48.0, 0.0, 0.0))
	texture.update(history)
	material.set_shader_parameter("spectrogram_style", 1)
	material.set_shader_parameter("probe_uv", Vector2.ZERO)
	var vocal_low := log(120.0 / 30.0) / log(600.0)
	await probe_sample(Vector2(vocal_low, vocal_low), "vocal view starts at 120 Hz")
	material.set_shader_parameter("probe_uv", Vector2(1.0, 0.0))
	var vocal_high := log(8000.0 / 30.0) / log(600.0)
	await probe_sample(Vector2(vocal_high, vocal_high), "vocal view ends at 8 kHz")
	material.set_shader_parameter("spectrogram_style", 2)
	var bass_high := log(300.0 / 30.0) / log(600.0)
	await probe_sample(Vector2(bass_high, bass_high), "bass view ends at 300 Hz")
	probe.queue_free()


func run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(800, 450)
	captures = "/tmp/vpx-spectrogram-captures"
	DirAccess.make_dir_recursive_absolute(captures)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	settings.visualizer_motion = 0.6
	settings.visualizer_intensity = 0.75
	var camera := Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var frames: Array[Image] = []
	for index in range(field.SPECTROGRAM_START, field.WORLD_START):
		settings.apply("visualizer_preset", index)
		var title: String = settings.VISUALIZER_PRESETS[index]
		field.quality = 2
		field._apply_quality()
		check(field.materials[0].shader == field.SPECTROGRAM_SHADER, title + " selects spectrogram geometry")
		field.reset()
		field._process(1.0)
		var silent := await capture()
		signal_history()
		var first := await capture()
		first.save_png(captures.path_join("%03d.png" % index))
		frames.append(first)
		check(difference(first, silent) > 0.003, title + " renders spectral history")
		for quality in 3:
			field.quality = quality
			field._apply_quality()
			var valid := true
			for layer in field.layers:
				valid = valid and layer.multimesh.visible_instance_count <= layer.multimesh.instance_count
			check(valid and difference(await capture(), silent) > 0.003, title + " renders at quality " + str(quality))
		signal_history(true)
		var swapped := await capture()
		check(difference(first, swapped) > 0.001, title + " distinguishes swapped channels")
		settings.visualizer_intensity = 0.0
		field._process(0.0)
		check(difference(swapped, await capture()) > 0.003, title + " respects intensity")
		settings.visualizer_intensity = 0.75
		settings.visualizer_motion = 0.0
		field._process(0.0)
		var frozen := await capture()
		field.clock += 10.0
		field._process(0.0)
		check(difference(frozen, await capture()) < 0.0001, title + " keeps analysis stationary")
		settings.visualizer_motion = 0.6
		for turn in range(1, 4):
			camera.rotation.y = turn * PI * 0.5
			check(difference(await capture(), silent) > 0.003, title + " surrounds listener at turn " + str(turn))
		camera.rotation.y = 0.0
		camera.position.x = -0.032
		var left_eye := await capture()
		camera.position.x = 0.032
		check(difference(left_eye, await capture()) > 0.0005, title + " has stereo parallax")
		camera.position.x = 0.0
		signal_history(false, true)
		check(difference(await capture(), silent) > 0.003, title + " renders mono history")
		check(int(field.materials[0].get_shader_parameter("spectral_channel_count")) == 1, title + " binds mono source correctly")
		field.silence()
		field._process(1.0)
		check(field.spectral_history_position == 0 and field.spectral_history_duration == 0.0, title + " clears history on silence")
		check(difference(silent, await capture()) < 0.0001, title + " clears stale visuals")
	for first in frames.size():
		for second in first:
			check(difference(frames[first], frames[second]) > 0.01, "spectrogram layouts %d and %d differ" % [first, second])
	settings.apply("visualizer_preset", field.SPECTROGRAM_START + 3)
	signal_history(false, false, true)
	var steady := await capture()
	signal_history()
	check(difference(steady, await capture()) > 0.003, "transient scanner distinguishes attacks from steady tones")
	settings.apply("visualizer_preset", settings.VISUALIZER_PRESET_MAX)
	field.cycle_preset()
	check(settings.visualizer_preset == 0, "new catalog wraps to first preset")
	await verify_measurements()
	print("SPECTROGRAM_VISUALIZERS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
