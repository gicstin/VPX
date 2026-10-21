extends SceneTree

var checks := 0
var failures := 0
var measurements := {}
var main: Node


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func measure(name: String, action: Callable, iterations := 100) -> void:
	action.call()
	var samples: Array[float] = []
	for sample in 7:
		var started := Time.get_ticks_usec()
		for i in iterations:
			action.call()
		samples.append((Time.get_ticks_usec() - started) / (1000.0 * iterations))
	samples.sort()
	measurements[name] = {"median_ms": samples[3], "samples_ms": samples}
	print("BENCH %s median=%.5f ms" % [name, samples[3]])


func run() -> void:
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: frame performance timeout"); quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.last_directory = ""
	settings.prefer_desktop = true
	settings.music_visualizer = false
	settings.immersive_music_visualizer = false
	settings.visualizer_quality = 1
	settings.visualizer_auto_change = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	_ui()
	_directions()
	_gradients()
	_spectrum()
	_field()
	var report := {"checks": checks, "failures": failures, "measurements": measurements}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		check(file != null, "frame benchmark report opens")
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	main.free()
	print("RESULT: frame_performance checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _ui() -> void:
	var settings := root.get_node("Settings")
	var controls: Node = main.photo_bar.root
	var picker: Node = controls.scene_picker
	measure("music_controls_refresh", controls.refresh)
	measure("picker_pull", picker._pull)
	measure("favorite_refresh", controls._refresh_favorite)
	var themes := [0]
	controls.favorite_button.theme_changed.connect(func() -> void: themes[0] += 1)
	for i in 20:
		controls.refresh()
	check(themes[0] == 0, "unchanged music controls do not invalidate their theme")
	check(controls.favorite_button.disabled, "empty music path disables favourite")
	main.player.current_path = "user://frame-performance.wav"
	controls.refresh()
	check(not controls.favorite_button.disabled and not controls.favorite_button.button_pressed, "new music path enables favourite without starring it")
	root.get_node("Library").set_favorite(main.player.current_path, true)
	controls.refresh()
	check(controls.favorite_button.button_pressed and controls.favorite_button.tooltip_text == "Remove music from favourites", "favourite changes update cached icon and tooltip")
	root.get_node("Library").set_favorite(main.player.current_path, false)
	controls.refresh()
	check(not controls.favorite_button.button_pressed and controls.favorite_button.tooltip_text == "Add music to favourites", "removing favourite restores cached presentation")
	settings.immersive_music_visualizer = true
	settings.visualizer_preset = 3
	picker._pull()
	check(picker.tiles[3].button_pressed and picker.selected.button_pressed, "picker follows selection and enablement")
	picker.selected.set_pressed_no_signal(false)
	picker.tiles[3].set_pressed_no_signal(false)
	picker._pull()
	check(picker.tiles[3].button_pressed and picker.selected.button_pressed, "reselecting active scene restores toggled buttons")
	settings.visualizer_favorites = PackedStringArray([settings.VISUALIZER_PRESETS[3]])
	settings.visualizer_starred_only = true
	picker._pull()
	check(picker.tiles[3].visible and not picker.tiles[4].visible and picker.favorite_buttons[3].button_pressed, "favourite filtering updates cached gallery")
	settings.visualizer_favorites[0] = settings.VISUALIZER_PRESETS[4]
	picker._pull()
	check(not picker.tiles[3].visible and picker.tiles[4].visible and picker.favorite_buttons[4].button_pressed, "in-place favourite edits invalidate gallery snapshot")
	settings.visualizer_favorites.clear()
	picker._pull()
	check(picker.empty_favorites.visible, "empty favourites display follows filtering")
	settings.visualizer_starred_only = false
	settings.visualizer_overlay = true
	picker._pull()
	check(picker.mix_controls.visible and picker.overlay_toggle.button_pressed and picker.selected.tooltip_text.contains("Overlay on media"), "overlay changes update picker controls")
	settings.immersive_music_visualizer = false
	picker._pull()
	check(picker.disabled_button.button_pressed and not picker.selected.button_pressed and not picker.tiles[3].button_pressed, "disabled scene clears cached selection")
	settings.visualizer_overlay = false
	settings.visualizer_preset = 0
	main.player.current_path = ""
	controls.refresh()
	check(controls.favorite_button.disabled, "clearing media disables cached favourite")


func _directions() -> void:
	var viz: Node = main.music_visualizer
	var rng := RandomNumberGenerator.new()
	rng.seed = 20210
	var magnitudes := PackedVector2Array()
	magnitudes.resize(48)
	for sample in 120:
		var correlation := rng.randf_range(-1.0, 1.0)
		for band in 48:
			var magnitude := Vector2(rng.randf(), rng.randf()) * pow(10.0, rng.randf_range(-7.0, 1.0))
			if sample % 5 == 0:
				magnitude.x = 0.0
			elif sample % 5 == 1:
				magnitude.y = 0.0
			elif sample % 5 == 2:
				magnitude.y = magnitude.x
			elif sample % 5 == 3:
				magnitude = Vector2.ZERO
			magnitudes[band] = magnitude
		var expected := _levels(magnitudes)
		var actual := expected.duplicate()
		_reference_directions(viz, expected, magnitudes, correlation)
		viz._fill_directions(actual, magnitudes, correlation)
		check(_difference(actual, expected) < 0.000001, "directional projection matches reference for silence, stereo, floor and loud input")
		var spatial := PackedFloat32Array()
		spatial.resize(2400)
		for i in spatial.size():
			spatial[i] = rng.randf() if i % 5 != 0 else 0.0
		expected = _levels(magnitudes)
		actual = expected.duplicate()
		_reference_directions(viz, expected, magnitudes, correlation, spatial)
		viz._fill_directions(actual, magnitudes, correlation, spatial)
		check(_difference(actual, expected) < 0.000001, "surround calibration preserves every native direction")
	for band in 48:
		magnitudes[band] = Vector2(0.02 + band * 0.01, 0.5 - band * 0.009)
	var data := _levels(magnitudes)
	measure("directions_reference_music", func() -> void: _reference_directions(viz, data, magnitudes, -0.3))
	measure("directions_optimized_music", func() -> void:
		data.fill(0.0)
		viz._fill_directions(data, magnitudes, -0.3))
	magnitudes.fill(Vector2.ZERO)
	measure("directions_reference_silence", func() -> void: _reference_directions(viz, data, magnitudes, 1.0))
	measure("directions_optimized_silence", func() -> void:
		data.fill(0.0)
		viz._fill_directions(data, magnitudes, 1.0))


func _levels(magnitudes: PackedVector2Array) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(2400)
	for band in 48:
		data[band] = clampf((linear_to_db(maxf(magnitudes[band].x, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
		data[48 + band] = clampf((linear_to_db(maxf(magnitudes[band].y, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)
	return data


func _reference_directions(viz: Node, data: PackedFloat32Array, magnitudes: PackedVector2Array, correlation: float, spatial := PackedFloat32Array()) -> void:
	var axes: PackedVector3Array = viz.fallback_axes
	var native := not spatial.is_empty()
	for band in 48:
		var magnitude := magnitudes[band]
		var pan := (magnitude.y * magnitude.y - magnitude.x * magnitude.x) / maxf(0.000000000001, magnitude.length_squared())
		var direction := Vector3(pan, 0, -sqrt(maxf(0.0, 1.0 - pan * pan)))
		var diffuse := (1.0 - correlation) * 0.35
		for cell in 48:
			var index := (cell + 2) * 48 + band
			if native:
				var native_peak := maxf(spatial[band], spatial[48 + band])
				data[index] = clampf(spatial[index] + maxf(data[band], data[48 + band]) - native_peak, 0.0, 1.0) if spatial[index] > 0.0 else 0.0
			else:
				var dot := maxf(0.0, axes[cell].dot(direction))
				var weight := pow(dot, 10.0) * (1.0 - diffuse) + dot * dot * diffuse
				data[index] = clampf((linear_to_db(maxf(maxf(magnitude.x, magnitude.y) * weight, 0.000001)) + 60.0) / 60.0, 0.0, 1.0)


func _difference(actual: PackedFloat32Array, expected: PackedFloat32Array) -> float:
	var error := 0.0
	for i in actual.size():
		error = maxf(error, absf(actual[i] - expected[i]))
	return error


func _gradients() -> void:
	var canvas: Control = main.music_visualizer.spectrum
	var accent := VpxTheme.ACCENT
	var end := VpxTheme.SPECTRUM_END
	for color in [accent, Color(0.9, 0.2, 0.4)]:
		VpxTheme.ACCENT = color
		VpxTheme.SPECTRUM_END = Color(0.2, 0.8, 0.3)
		for scope in [false, true]:
			canvas.oscilloscope = scope
			for count in [2, 48, 189, 320]:
				for area in [Rect2(16, 10, 608, 164), Rect2(16, 44, 96, 72)]:
					var points := PackedVector2Array()
					for i in count:
						points.append(Vector2(area.position.x + i * area.size.x / (count - 1), area.position.y + sin(i)))
					for alpha in [1.0, 0.45, 0.14, 0.3]:
						var expected := PackedColorArray()
						for point in points:
							expected.append(Color(VpxTheme.ACCENT.lerp(VpxTheme.SPECTRUM_END, clampf((point.x - area.position.x) / area.size.x, 0.0, 1.0)), alpha))
						var actual: PackedColorArray = canvas._gradient(points, area, alpha)
						check(actual == expected, "gradient cache follows palette, size, mode and opacity")
						actual.append(Color.WHITE)
						actual[0] = Color.BLACK
						check(canvas._gradient(points, area, alpha) == expected, "cached gradients cannot be mutated by polygon fills")
	VpxTheme.ACCENT = accent
	VpxTheme.SPECTRUM_END = end
	var points := PackedVector2Array([Vector2(16, 10), Vector2(64, 24), Vector2(112, 10)])
	var area := Rect2(16, 10, 96, 72)
	var before: PackedColorArray = canvas._gradient(points, area, 1.0)
	VpxTheme.ACCENT = Color(0.9, 0.2, 0.4)
	var recolored: PackedColorArray = canvas._gradient(points, area, 1.0)
	check(recolored[0] == VpxTheme.ACCENT and recolored != before, "palette change alone invalidates gradient cache")
	VpxTheme.SPECTRUM_END = Color(0.2, 0.8, 0.3)
	var endpoint: PackedColorArray = canvas._gradient(points, area, 1.0)
	check(endpoint[-1].is_equal_approx(VpxTheme.SPECTRUM_END) and endpoint != recolored, "gradient endpoint change alone invalidates cache")
	VpxTheme.ACCENT = accent
	VpxTheme.SPECTRUM_END = end


func _field() -> void:
	var settings := root.get_node("Settings")
	var field: Node = main.resonance_field
	settings.visualizer_overlay = false
	field.set_active(true)
	var data := PackedFloat32Array()
	data.resize(2400)
	for i in data.size():
		data[i] = 0.25 + 0.2 * sin(i * 0.1)
	field.feed(data, {"rms": 0.1, "correlation": 0.4, "channels": 2})
	for preset in [0, 7, 22, 76]:
		settings.visualizer_preset = preset
		field._settings_changed()
		measure("field_preset_%d" % preset, func() -> void: field._process(1.0 / 90.0))
	for quality in [1, 3, 2]:
		settings.visualizer_quality = quality
		for preset in settings.VISUALIZER_PRESETS.size():
			settings.visualizer_preset = preset
			field._settings_changed()
			for material in field.materials:
				material.set_shader_parameter("clock", -1000000.0)
				material.set_shader_parameter("bass", -1000000.0)
			field._process(1.0 / 90.0)
			for kind in field.layers.size():
				if field.layers[kind].multimesh.visible_instance_count > 0:
					check(is_equal_approx(float(field.materials[kind].get_shader_parameter("clock")), field.clock), "visible layer receives current time after preset and quality change")
					check(is_equal_approx(float(field.materials[kind].get_shader_parameter("bass")), field.bass), "visible layer receives current audio after preset and quality change")
	field.set_active(false)
	settings.visualizer_preset = 0
	settings.visualizer_quality = 1
	field._settings_changed()


func _reference_spectrum(levels: PackedFloat32Array, targets: PackedFloat32Array, delta: float) -> void:
	var attack := 1.0 - exp(-delta * 45.0)
	var release := 1.0 - exp(-delta * 14.0)
	for i in levels.size():
		var value := lerpf(levels[i], targets[i], attack if targets[i] > levels[i] else release)
		levels[i] = 0.0 if value < 0.00001 else value


func _spectrum() -> void:
	var field: Node = main.resonance_field
	field._clear_spectrum()
	var expected: PackedFloat32Array = field.spectrum_levels.duplicate()
	var targets := PackedFloat32Array()
	targets.resize(2400)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2021021
	for phase in 4:
		for i in targets.size():
			targets[i] = rng.randf() if phase < 2 else 0.0
		var replaced: bool = field.spectrum_targets != targets
		field.feed(targets, {})
		if replaced:
			check(not field.spectrum_settled, "new spectrum wakes smoothing")
			field._smooth_spectrum(0.0)
			check(not field.spectrum_settled, "zero delta cannot stop pending smoothing")
		for frame in 320:
			var delta: float = [0.0, 1.0 / 144.0, 1.0 / 90.0, 1.0 / 30.0, 0.1][frame % 5]
			_reference_spectrum(expected, targets, delta)
			field._smooth_spectrum(delta)
			check(field.spectrum_levels == expected, "spectrum smoothing preserves every float32 value across attack, release, silence and frame rates")
			check(field.image.get_data().to_float32_array() == expected, "spectrum texture follows the smoothed values")
		check(field.spectrum_settled, "sustained tone and silence settle after float32 rounding")
	check(field.spectrum_settled, "unchanged float32 spectrum settles")
	field.feed(targets, {})
	check(field.spectrum_settled, "unchanged spectrum does not restart settled smoothing")
	targets[0] = 0.8
	check(field.spectrum_targets[0] == 0.0, "spectrum input cannot mutate cached targets")
	field.feed(targets, {})
	_reference_spectrum(expected, targets, 0.000000001)
	field._smooth_spectrum(0.000000001)
	_reference_spectrum(expected, targets, 0.1)
	field._smooth_spectrum(0.1)
	check(field.spectrum_levels == expected, "larger delta resumes smoothing after a tiny frame")
	field.silence()
	check(field.spectrum_settled and field.spectrum_levels.count(0.0) == 2400, "silence clears settled spectrum")
	measure("spectrum_steady", func() -> void: field._smooth_spectrum(1.0 / 90.0))
	field._clear_spectrum()
