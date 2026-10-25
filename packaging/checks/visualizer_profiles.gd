extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)


func run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_quality = 1
	settings.visualizer_auto_change = false
	settings.visualizer_starred_only = false
	check(settings.VISUALIZER_PRESETS.size() == 113 and settings.VISUALIZER_PRESET_MAX == 112, "catalog includes eight immersive spectrogram scenes and three music worlds")
	check(settings.VISUALIZER_PRESETS[78] == "PM · Geiss Nautilus" and settings.VISUALIZER_PRESETS[79] == "PM · Geiss Cosmic Dust 2", "retained classic MilkDrop presets keep their indices")
	check(settings.VISUALIZER_STUDIO_GUIDES.size() == settings.VISUALIZER_PRESETS.size() - settings.VISUALIZER_STUDIO_START, "preset guides match the catalog")
	var field: Node = load("res://scripts/resonance_field.gd").new()
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var values: Dictionary = load("res://scripts/visualizer_response_profiles.gd").VALUES
	check(values.size() == settings.VISUALIZER_PRESETS.size(), "every preset has a response profile")
	var original := Vector3(settings.visualizer_intensity, settings.visualizer_sensitivity, settings.visualizer_motion)
	for index in settings.VISUALIZER_PRESETS.size():
		var name: String = settings.VISUALIZER_PRESETS[index]
		settings.apply("visualizer_preset", index)
		var profile: Vector3 = values.get(name, Vector3.ZERO)
		check(profile.is_finite() and profile.x >= 1.0 and profile.y >= 1.0 and profile.z >= 1.0, name + " has bounded positive tuning")
		check(profile.x <= 1.4001 and profile.y <= 1.7001 and profile.z <= 1.4001, name + " tuning stays within auditioned range")
		check(field.response_profile == profile, name + " selects its own tuning")
		field.clock = 2.0
		field._process(1.0 / 60.0)
		for kind in field.materials.size():
			if field.layers[kind].multimesh.visible_instance_count == 0:
				continue
			var material: ShaderMaterial = field.materials[kind]
			check(is_equal_approx(float(material.get_shader_parameter("intensity")), clampf(original.x * profile.x, 0.0, 1.5)), name + " applies profile intensity")
		check(is_equal_approx(float(field.sky_material.get_shader_parameter("intensity")), clampf(original.x * profile.x, 0.0, 1.5)), name + " sky matches geometry intensity")
		check(is_equal_approx(float(field.sky_material.get_shader_parameter("clock")), 2.0 * clampf(original.z * profile.z, 0.0, 1.0)), name + " sky uses the tuned motion clock")
	check(Vector3(settings.visualizer_intensity, settings.visualizer_sensitivity, settings.visualizer_motion) == original, "preset switching preserves user controls")
	settings.apply("visualizer_preset", 17)
	field.response_profile = Vector3(1.4, 1.7, 1.4)
	settings.visualizer_intensity = 0.0
	settings.visualizer_motion = 0.0
	field._process(1.0 / 60.0)
	check(is_zero_approx(float(field.materials[0].get_shader_parameter("intensity"))), "zero intensity remains zero")
	check(is_zero_approx(float(field.materials[0].get_shader_parameter("motion"))), "zero motion remains zero")
	settings.visualizer_intensity = 1.5
	settings.visualizer_sensitivity = 4.0
	settings.visualizer_motion = 1.0
	field._process(1.0 / 60.0)
	check(is_equal_approx(float(field.materials[0].get_shader_parameter("intensity")), 1.5), "intensity stays within limits")
	check(is_equal_approx(float(field.materials[0].get_shader_parameter("sensitivity")), 4.0), "sensitivity stays within limits")
	check(is_equal_approx(float(field.materials[0].get_shader_parameter("motion")), 1.0), "motion stays within limits")
	settings.apply("visualizer_preset", 22)
	check(field.response_profile == values.get(settings.VISUALIZER_PRESETS[22], Vector3.ZERO), "switching replaces previous profile")
	settings.apply("visualizer_preset", 999)
	check(settings.visualizer_preset == settings.VISUALIZER_PRESET_MAX and field.preset_index == settings.VISUALIZER_PRESET_MAX, "out-of-range selection clamps to the last preset")
	field.cycle_preset()
	check(field.preset_index == 0 and field.response_profile == values.get(settings.VISUALIZER_PRESETS[0], Vector3.ZERO), "preset cycling wraps with the correct response profile")
	print("VISUALIZER_PROFILES checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
