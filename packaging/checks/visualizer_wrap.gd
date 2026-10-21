extends "res://packaging/checks/studio_visualizers.gd"

var probe: MeshInstance3D
var probes: Dictionary = {}


func instrument(source: Shader, geometry: bool) -> Shader:
	var key := str(source.get_instance_id()) + str(geometry)
	if probes.has(key):
		return probes[key]
	var code := source.code
	if geometry:
		var declaration := RegEx.new()
		declaration.compile("varying\\s+(\\w+)\\s+(\\w+);")
		var parameters := PackedStringArray(["inout vec3 probe_point"])
		var arguments := PackedStringArray(["VERTEX"])
		var locals := ""
		var varyings := declaration.search_all(code)
		code = declaration.sub(code, "", true)
		for varying in varyings:
			var type: String = varying.get_string(1)
			var variable: String = varying.get_string(2)
			parameters.append("inout " + type + " probe_" + variable)
			arguments.append(variable)
			locals += type + " " + variable + ";\n"
			var references := RegEx.new()
			references.compile("\\b" + variable + "\\b")
			code = references.sub(code, "probe_" + variable, true)
		code = code.replace("void vertex()", "void probe_vertex(" + ", ".join(parameters) + ")")
		code = code.left(code.find("void fragment()"))
		code = code.replace("VERTEX", "probe_point")
		code = code.replace("INSTANCE_ID", "probe_instance")
		code = code.replace("INSTANCE_CUSTOM", "vec4(0.2, 0.4, 0.6, 0.8)")
		code = code.replace("shader_type spatial;", "shader_type spatial;\nuniform int probe_instance = 0;\nuniform float probe_side = 0.0;\nuniform float probe_offset = 0.0;\nvarying vec3 probe_error;")
		var wrapper := """
void vertex() {
	PROBE_LOCALS
	vec3 original = VERTEX;
	VERTEX = vec3(probe_offset, probe_side, 0.0);
	probe_vertex(PROBE_ARGUMENTS);
	vec3 first = VERTEX;
	vec3 first_tint = tint;
	float first_light = light;
	VERTEX = vec3(1.0 + probe_offset, probe_side, 0.0);
	probe_vertex(PROBE_ARGUMENTS);
	probe_error = vec3(length(first - VERTEX), length(first_tint - tint), abs(first_light - light));
	VERTEX = original;
}
void fragment() {
	ALBEDO = clamp(probe_error * 10.0, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}
"""
		if not "vec3 tint;" in locals:
			wrapper = wrapper.replace("vec3 first_tint = tint;", "vec3 first_tint = vec3(colour_phase);")
			wrapper = wrapper.replace("float first_light = light;", "float first_light = response * spark;")
			wrapper = wrapper.replace("first_tint - tint", "first_tint - vec3(colour_phase)")
			wrapper = wrapper.replace("first_light - light", "first_light - response * spark")
		code += wrapper.replace("PROBE_LOCALS", locals).replace("PROBE_ARGUMENTS", ", ".join(arguments))
	else:
		code = code.replace("cull_front", "cull_disabled")
		code = code.replace("shader_type spatial;", "shader_type spatial;\nuniform float probe_height = 0.0;")
		code = code.replace("void fragment()", "vec3 probe_sky(vec3 probe_direction)")
		code = code.replace("normalize(direction)", "normalize(probe_direction)")
		code = code.replace("ALBEDO =", "return")
		code += """
void fragment() {
	vec3 first = probe_sky(vec3(-0.000001, probe_height, 1.0));
	vec3 second = probe_sky(vec3(0.000001, probe_height, 1.0));
	ALBEDO = clamp(abs(first - second) * 100.0, vec3(0.0), vec3(1.0));
}
"""
	var shader := Shader.new()
	shader.code = code
	probes[key] = shader
	return shader


func bind_probe(source: ShaderMaterial, geometry: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = instrument(source.shader, geometry)
	for parameter in source.shader.get_shader_uniform_list():
		var value: Variant = source.get_shader_parameter(parameter.name)
		if value != null:
			material.set_shader_parameter(parameter.name, value)
	probe.material_override = material
	return material


func error_pixel() -> Color:
	var shot := await capture()
	return shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2)


func closed_layers(index: int) -> Array[int]:
	if index == 6:
		return [0, 2, 3]
	if index >= field.PROJECTM_START:
		match index - field.PROJECTM_START:
			0, 2: return [2]
			1, 4: return [0, 2]
	elif index >= field.LIVE_START:
		match index - field.LIVE_START:
			0: return [0, 2, 3]
			1: return [0, 2]
			2, 4: return [2]
			3, 5: return [2, 3]
	elif index >= field.MILKDROP_START:
		return [0, 2]
	return []


func run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(32, 32)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 2
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	root.add_child(field)
	field.set_process(false)
	field.active = true
	probe = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	probe.mesh = quad
	probe.position.z = -2.0
	root.add_child(probe)
	var bands := PackedFloat32Array()
	bands.resize(2400)
	for channel in 2:
		for band in 48:
			bands[channel * 48 + band] = 0.12 + pow(float(band) / 47.0, 2.0) * (0.8 if channel == 0 else 0.5)
	var wave := PackedFloat32Array()
	wave.resize(512)
	for sample in 256:
		wave[sample] = float(sample) / 255.0 - 0.5
		wave[256 + sample] = 0.4 * cos(float(sample) * 0.037)
	for frame in 120:
		field.feed(bands, {"channels": 2, "rms": 0.12})
		field._process(1.0 / 60.0)
	field.feed_waveform(wave)
	for index in settings.VISUALIZER_PRESETS.size():
		settings.apply("visualizer_preset", index)
		field._process(0.0)
		var title: String = settings.VISUALIZER_PRESETS[index]
		var sky_probe := bind_probe(field.sky_material, false)
		sky_probe.set_shader_parameter("dim", 1.0)
		sky_probe.set_shader_parameter("intensity", 1.0)
		var sky_error := 0.0
		for time in [0.0, 7.3]:
			sky_probe.set_shader_parameter("clock", time)
			for height in [-0.4, 0.0, 0.35]:
				sky_probe.set_shader_parameter("probe_height", height)
				var pixel := await error_pixel()
				sky_error = maxf(sky_error, maxf(pixel.r, maxf(pixel.g, pixel.b)))
		check(sky_error < 0.04, title + " sky crosses longitude seam smoothly (%.4f)" % sky_error)
		for kind in closed_layers(index):
			var material := bind_probe(field.materials[kind], true)
			var geometry_error := Vector3.ZERO
			for sample in 3:
				material.set_shader_parameter("probe_instance", [0, 1, field.layers[kind].multimesh.visible_instance_count - 1][sample])
				material.set_shader_parameter("probe_side", float(sample - 1))
				for offset in [-0.002, 0.0, 0.002]:
					material.set_shader_parameter("probe_offset", offset)
					var pixel := await error_pixel()
					geometry_error = geometry_error.max(Vector3(pixel.r, pixel.g, pixel.b))
			check(geometry_error.x < 0.04, title + " layer %d closes position and ribbon edges (%s)" % [kind, geometry_error])
			check(geometry_error.y < 0.04 and geometry_error.z < 0.04, title + " layer %d joins colour and brightness" % kind)
	print("VISUALIZER_WRAP checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
