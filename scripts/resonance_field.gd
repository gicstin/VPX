class_name ResonanceField
extends Node3D

signal activity_changed

const BANDS := 48
const ROWS := 50
const COUNTS := [Vector4i(24, 900, 12, 4), Vector4i(40, 2400, 20, 6), Vector4i(64, 5200, 32, 8)]
const LEGACY_COUNTS := [Vector4i(12, 900, 8, 0), Vector4i(20, 2400, 14, 0), Vector4i(32, 5200, 24, 0)]
const DEPTH_COUNTS := [Vector4i(48, 0, 2, 0), Vector4i(72, 0, 2, 0), Vector4i(96, 0, 2, 0)]
const PULSE_COUNTS := [Vector4i(64, 1600, 32, 3), Vector4i(96, 3200, 48, 3), Vector4i(128, 5200, 64, 3)]
const PULSE_START := 17
const STEREO_COUNTS := [Vector4i(96, 2000, 48, 16), Vector4i(128, 3600, 64, 16), Vector4i(160, 5200, 96, 16)]
const STEREO_START := 22
const SPECTRAL_HISTORY_RATE := 45.0
const WAVE_SAMPLES := 256
const HISTORY_SAMPLES := 192
const HISTORY_RATE := 90.0
const SHADER := preload("res://shaders/resonance.gdshader")
const LEGACY_SHADER := preload("res://shaders/resonance_legacy.gdshader")
const LEGACY_SKY_SHADER := preload("res://shaders/resonance_sky_legacy.gdshader")
const DEPTH_SHADER := preload("res://shaders/resonance_depth.gdshader")
const SKY_SHADER := preload("res://shaders/resonance_sky.gdshader")
const PULSE_SHADER := preload("res://shaders/resonance_pulse.gdshader")
const PULSE_SKY_SHADER := preload("res://shaders/resonance_pulse_sky.gdshader")
const STEREO_SHADER := preload("res://shaders/resonance_stereo.gdshader")
const STEREO_SKY_SHADER := preload("res://shaders/resonance_stereo_sky.gdshader")

var camera: Camera3D
var anchor: Node3D
var audio_anchor: Node3D
var menu: Node3D
var player: VPXPlayer
var active := false
var texture: ImageTexture
var layers: Array[MultiMeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var sky_material: ShaderMaterial
var clock := 0.0
var presence := 0.0
var bass := 0.0
var mids := 0.0
var treble := 0.0
var impulse := 0.0
var stereo_width := 0.0
var preset := Vector3(1, 0, 0)
var preset_index := 0
var selected_preset := -1
var has_audio := false
var preset_elapsed := 0.0
var quality := 1
var quality_elapsed := 0.0
var slow_frames := 0.0
var fast_frames := 0.0
var audio_basis := Basis.IDENTITY
var wave_image: Image
var wave_texture: ImageTexture
var wave_active := false
var domain_targets := Vector3.ZERO
var transients := Vector3.ZERO
var beat_age := 4.0
var beat_count := 0
var travel := 0.0
var spin := 0.0
var surge := 0.0
var desired_presence := 0.0
var image: Image
var spectrum_targets := PackedFloat32Array()
var spectrum_levels := PackedFloat32Array()
var source_count := 2
var channel_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var channel_levels: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var history_image: Image
var history_texture: ImageTexture
var history_position := 0
var history_elapsed := 0.0
var spectral_history_image: Image
var spectral_history_texture: ImageTexture
var spectral_history_position := 0
var spectral_history_elapsed := 0.0
var spectral_history_duration := 0.0
var scene_opacity := 1.0
var strip_mesh: ArrayMesh
var surface_mesh: ArrayMesh
var stereo := StereoImage.new()


func _ready() -> void:
	name = "ResonanceField"
	visible = false
	var empty := PackedByteArray()
	empty.resize(BANDS * ROWS * 4)
	image = Image.create_from_data(BANDS, ROWS, false, Image.FORMAT_RF, empty)
	texture = ImageTexture.create_from_image(image)
	spectrum_targets.resize(BANDS * ROWS)
	spectrum_levels.resize(BANDS * ROWS)
	history_image = Image.create_empty(HISTORY_SAMPLES, 2, false, Image.FORMAT_RGBAF)
	history_image.fill(Color(0, 0, 0, 0))
	history_texture = ImageTexture.create_from_image(history_image)
	spectral_history_image = Image.create_empty(BANDS, HISTORY_SAMPLES * 2, false, Image.FORMAT_RF)
	spectral_history_image.fill(Color(0, 0, 0, 0))
	spectral_history_texture = ImageTexture.create_from_image(spectral_history_image)
	var wave_empty := PackedByteArray()
	wave_empty.resize(WAVE_SAMPLES * 2 * 4)
	wave_image = Image.create_from_data(WAVE_SAMPLES, 2, false, Image.FORMAT_RF, wave_empty)
	wave_texture = ImageTexture.create_from_image(wave_image)
	var sky := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 65.0
	sphere.height = 130.0
	sphere.radial_segments = 32
	sphere.rings = 16
	sky.mesh = sphere
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky.material_override = sky_material
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)
	strip_mesh = _strip(256)
	surface_mesh = _surface(48, 192)
	for kind in 4:
		var layer := MultiMeshInstance3D.new()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_custom_data = true
		instances.mesh = _octahedron() if kind == 1 else strip_mesh
		instances.instance_count = maxi(maxi(COUNTS[2][kind], DEPTH_COUNTS[2][kind]), maxi(PULSE_COUNTS[2][kind], STEREO_COUNTS[2][kind]))
		instances.custom_aabb = AABB(Vector3.ONE * -40.0, Vector3.ONE * 80.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x52534E43 + kind
		for i in instances.instance_count:
			instances.set_instance_transform(i, Transform3D.IDENTITY)
			instances.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.03, 0.98), rng.randf(), fmod(float(i) * 0.61803398875, 1.0)))
		layer.multimesh = instances
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("shape", kind)
		material.set_shader_parameter("spectrum_texture", texture)
		material.set_shader_parameter("wave_texture", wave_texture)
		material.set_shader_parameter("history_texture", history_texture)
		layer.material_override = material
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.extra_cull_margin = 40.0
		add_child(layer)
		layers.append(layer)
		materials.append(material)
	Settings.changed.connect(_settings_changed)
	_settings_changed()


func _settings_changed() -> void:
	if selected_preset != Settings.visualizer_preset:
		selected_preset = Settings.visualizer_preset
		preset_index = selected_preset
		preset_elapsed = 0.0
		_apply_preset()
	if Settings.visualizer_quality > 0:
		quality = Settings.visualizer_quality - 1
	_apply_quality()


func cycle_preset() -> void:
	Settings.apply("visualizer_preset", (preset_index + 1) % Settings.VISUALIZER_PRESETS.size())


func _apply_preset() -> void:
	var pulse := preset_index >= PULSE_START and preset_index < STEREO_START
	var image_scene := preset_index >= STEREO_START
	var shader := LEGACY_SHADER if preset_index < 3 else (STEREO_SHADER if image_scene else (PULSE_SHADER if pulse else (DEPTH_SHADER if preset_index >= 7 else SHADER)))
	for kind in materials.size():
		var material := materials[kind]
		material.shader = shader
		material.set_shader_parameter("shape", kind)
		material.set_shader_parameter("spectrum_texture", texture)
		material.set_shader_parameter("wave_texture", wave_texture)
		material.set_shader_parameter("history_texture", history_texture)
		material.set_shader_parameter("spectral_history_texture", spectral_history_texture)
		material.set_shader_parameter("depth_style", maxi(0, preset_index - 7))
		material.set_shader_parameter("pulse_style", maxi(0, preset_index - PULSE_START))
		material.set_shader_parameter("stereo_style", maxi(0, preset_index - STEREO_START))
		stereo.bind(material)
	layers[2].multimesh.mesh = surface_mesh if preset_index >= 7 and preset_index < PULSE_START else strip_mesh
	sky_material.shader = LEGACY_SKY_SHADER if preset_index < 3 else (STEREO_SKY_SHADER if image_scene else (PULSE_SKY_SHADER if pulse else SKY_SHADER))
	sky_material.set_shader_parameter("pulse_style", maxi(0, preset_index - PULSE_START))
	sky_material.set_shader_parameter("stereo_style", maxi(0, preset_index - STEREO_START))
	stereo.bind(sky_material)
	sky_material.set_shader_parameter("spectrum_texture", texture)
	scene_opacity = 0.0


func _apply_quality() -> void:
	var counts: Array = LEGACY_COUNTS if preset_index < 3 else (STEREO_COUNTS if preset_index >= STEREO_START else (PULSE_COUNTS if preset_index >= PULSE_START else (DEPTH_COUNTS if preset_index >= 7 else COUNTS)))
	for kind in layers.size():
		layers[kind].multimesh.visible_instance_count = counts[clampi(quality, 0, 2)][kind]
		materials[kind].set_shader_parameter("instance_count", layers[kind].multimesh.visible_instance_count)
	if active:
		apply_render_quality()


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	visible = value
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), value)
	if active:
		place()
	else:
		silence()
	activity_changed.emit()


func apply_render_quality() -> void:
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(quality, 0, 2)]


func feed(data: PackedFloat32Array, features: Dictionary) -> void:
	if data.size() != BANDS * ROWS:
		return
	has_audio = true
	spectrum_targets = data.duplicate()
	var channels := int(features.get("channels", 2))
	var spatial := bool(features.get("spatial", Settings.spatial_audio))
	source_count = 0
	if channels == 1:
		source_count = 1
	elif (channels == 2 and not features.get("ambisonic", false)) or not spatial:
		source_count = 2
	stereo.feed(data, source_count == 1)
	for channel in 2:
		var power := Vector3.ZERO
		for band in BANDS:
			var value := data[channel * BANDS + band]
			var magnitude := db_to_linear(value * 60.0 - 60.0) if value > 0.0 else 0.0
			var domain := 0 if band < 14 else (1 if band < 34 else 2)
			power[domain] += magnitude * magnitude / (20.0 if domain == 1 else 14.0)
		channel_targets[channel] = Vector3(sqrt(power.x), sqrt(power.y), sqrt(power.z)) * 5.0
	desired_presence = clampf(float(features.get("rms", 0.0)) * 5.0, 0.0, 1.0)
	impulse = maxf(impulse, clampf(float(features.get("onset", 0.0)) * 8.0, 0.0, 1.0))
	stereo_width = float(features.get("width", 0.0))
	var energy := Vector3.ZERO
	for band in BANDS:
		var value := maxf(data[band], data[BANDS + band])
		if band < 14:
			energy.x += value / 14.0
		elif band < 34:
			energy.y += value / 20.0
		else:
			energy.z += value / 14.0
	energy.x = maxf(energy.x, clampf(float(features.get("lfe", 0.0)) * 4.0, 0.0, 1.0))
	var rise := (energy - domain_targets).max(Vector3.ZERO)
	transients = transients.max(rise * Vector3(4.0, 5.0, 6.0)).min(Vector3.ONE)
	if rise.x > 0.045 and energy.x > 0.08 and beat_age > 0.16:
		beat_age = 0.0
		beat_count += 1
	domain_targets = energy


func silence() -> void:
	if has_audio:
		_clear_spectrum()
		stereo.clear()
		channel_targets = [Vector3.ZERO, Vector3.ZERO]
		channel_levels = [Vector3.ZERO, Vector3.ZERO]
		history_image.fill(Color(0, 0, 0, 0))
		history_texture.update(history_image)
		history_position = 0
		history_elapsed = 0.0
		spectral_history_image.fill(Color(0, 0, 0, 0))
		spectral_history_texture.update(spectral_history_image)
		spectral_history_position = 0
		spectral_history_elapsed = 0.0
		spectral_history_duration = 0.0
	desired_presence = 0.0
	domain_targets = Vector3.ZERO
	clear_waveform()


func reset() -> void:
	silence()
	presence = 0.0
	impulse = 0.0
	transients = Vector3.ZERO
	beat_age = 4.0
	beat_count = 0
	travel = 0.0
	spin = 0.0
	surge = 0.0
	bass = 0.0
	mids = 0.0
	treble = 0.0
	clock = 0.0
	spectrum_levels.fill(0.0)
	preset_elapsed = 0.0
	_clear_spectrum()


func _clear_spectrum() -> void:
	has_audio = false
	spectrum_targets.fill(0.0)
	spectrum_levels.fill(0.0)
	var empty := PackedByteArray()
	empty.resize(BANDS * ROWS * 4)
	image.set_data(BANDS, ROWS, false, Image.FORMAT_RF, empty)
	texture.update(image)


func feed_waveform(data: PackedFloat32Array) -> void:
	if data.size() != WAVE_SAMPLES * 2:
		return
	wave_image.set_data(WAVE_SAMPLES, 2, false, Image.FORMAT_RF, data.to_byte_array())
	wave_texture.update(wave_image)
	wave_active = true


func feed_scope(data: PackedFloat32Array) -> void:
	if data.size() == WAVE_SAMPLES * 2:
		stereo.feed_scope(data)


func clear_waveform() -> void:
	stereo.clear_scope()
	if not wave_active or wave_image == null:
		return
	var empty := PackedByteArray()
	empty.resize(WAVE_SAMPLES * 2 * 4)
	wave_image.set_data(WAVE_SAMPLES, 2, false, Image.FORMAT_RF, empty)
	wave_texture.update(wave_image)
	wave_active = false


func place() -> void:
	if camera == null:
		return
	global_position = camera.global_position
	global_basis = anchor.global_basis.orthonormalized() if anchor != null else Basis.IDENTITY
	var source_basis := audio_anchor.global_basis if audio_anchor != null else global_basis
	audio_basis = source_basis.orthonormalized().inverse() * global_basis.orthonormalized()


func _process(delta: float) -> void:
	visible = active
	if not active:
		return
	var playing := player != null and not player.paused and player.is_playing()
	if playing:
		clock += minf(delta, 0.1)
		beat_age = minf(4.0, beat_age + delta)
		preset_elapsed += delta
	if Settings.visualizer_auto_change and preset_elapsed >= 90.0:
		cycle_preset()
	var target := Vector3.ZERO
	target[preset_index % 3 if preset_index < 6 else 0] = 1.0
	preset = preset.lerp(target, 1.0 - exp(-delta * 1.4))
	presence = lerpf(presence, desired_presence, 1.0 - exp(-delta * (45.0 if desired_presence > presence else 5.0)))
	impulse *= exp(-delta * 12.0)
	transients *= exp(-delta * 9.0)
	var energies := Vector3(bass, mids, treble)
	for domain in 3:
		var speed := 45.0 if domain_targets[domain] > energies[domain] else 12.0
		energies[domain] = lerpf(energies[domain], domain_targets[domain], 1.0 - exp(-delta * speed))
	bass = energies.x
	mids = energies.y
	treble = energies.z
	var drive := (0.6 + bass * 2.2 + impulse * 2.5 + transients.x * 1.5) * Settings.visualizer_motion
	surge = lerpf(surge, drive if playing else 0.0, 1.0 - exp(-delta * 10.0))
	travel = fmod(travel + surge * delta, 1000.0)
	spin += (0.5 + mids * 1.6 + transients.y) * Settings.visualizer_motion * delta * (1.0 if playing else 0.0)
	_smooth_spectrum(delta)
	_update_history(delta)
	_update_spectral_history(delta)
	stereo.update(delta)
	scene_opacity = lerpf(scene_opacity, 1.0, 1.0 - exp(-delta * 8.0))
	var dim := (0.2 if menu != null and menu.visible else 1.0) * scene_opacity
	var palette := clock * 0.0025 + preset.dot(Vector3(0.0, 0.17, 0.38))
	for material in materials:
		material.set_shader_parameter("source_count", source_count if preset_index == 6 else 0)
		material.set_shader_parameter("spectral_history_head", spectral_history_position - 1)
		material.set_shader_parameter("spectral_history_fraction", spectral_history_elapsed * SPECTRAL_HISTORY_RATE)
		material.set_shader_parameter("spectral_channel_count", 1 if source_count == 1 else 2)
		material.set_shader_parameter("spectral_history_valid", minf(1.0, spectral_history_duration / 3.8))
		material.set_shader_parameter("history_head", float(history_position - 1) / HISTORY_SAMPLES)
		material.set_shader_parameter("history_fraction", history_elapsed * HISTORY_RATE)
		material.set_shader_parameter("audio_basis", audio_basis)
		material.set_shader_parameter("clock", clock)
		material.set_shader_parameter("intensity", Settings.visualizer_intensity)
		material.set_shader_parameter("sensitivity", Settings.visualizer_sensitivity)
		material.set_shader_parameter("motion", Settings.visualizer_motion)
		material.set_shader_parameter("presence", 0.35 + presence * 0.65)
		material.set_shader_parameter("bass", bass)
		material.set_shader_parameter("mids", mids)
		material.set_shader_parameter("treble", treble)
		material.set_shader_parameter("impulse", impulse)
		material.set_shader_parameter("transients", transients)
		material.set_shader_parameter("beat_age", beat_age)
		material.set_shader_parameter("beat_count", float(beat_count))
		material.set_shader_parameter("travel", travel)
		material.set_shader_parameter("spin", spin)
		material.set_shader_parameter("surge", surge)
		material.set_shader_parameter("stereo_width", stereo_width)
		material.set_shader_parameter("palette", palette)
		material.set_shader_parameter("preset", preset)
		material.set_shader_parameter("dim", dim)
		stereo.apply(material)
	sky_material.set_shader_parameter("source_count", source_count if preset_index >= 6 else 0)
	sky_material.set_shader_parameter("channel_left", channel_levels[0])
	sky_material.set_shader_parameter("channel_right", channel_levels[1])
	sky_material.set_shader_parameter("clock", clock * Settings.visualizer_motion)
	sky_material.set_shader_parameter("bass", bass)
	sky_material.set_shader_parameter("mids", mids)
	sky_material.set_shader_parameter("treble", treble)
	sky_material.set_shader_parameter("transients", transients)
	sky_material.set_shader_parameter("palette", palette)
	sky_material.set_shader_parameter("beat_age", beat_age)
	sky_material.set_shader_parameter("beat_count", float(beat_count))
	sky_material.set_shader_parameter("travel", travel)
	sky_material.set_shader_parameter("spin", spin)
	sky_material.set_shader_parameter("sensitivity", Settings.visualizer_sensitivity)
	sky_material.set_shader_parameter("intensity", Settings.visualizer_intensity)
	sky_material.set_shader_parameter("dim", dim)
	stereo.apply(sky_material)
	_auto_quality(delta)


func _smooth_spectrum(delta: float) -> void:
	var attack := 1.0 - exp(-delta * 45.0)
	var release := 1.0 - exp(-delta * 14.0)
	var changed := false
	for i in spectrum_levels.size():
		var value := lerpf(spectrum_levels[i], spectrum_targets[i], attack if spectrum_targets[i] > spectrum_levels[i] else release)
		if value < 0.00001:
			value = 0.0
		changed = changed or value != spectrum_levels[i]
		spectrum_levels[i] = value
	if changed:
		image.set_data(BANDS, ROWS, false, Image.FORMAT_RF, spectrum_levels.to_byte_array())
		texture.update(image)


func _update_history(delta: float) -> void:
	var previous := channel_levels.duplicate()
	for channel in 2:
		for domain in 3:
			var speed := 45.0 if channel_targets[channel][domain] > channel_levels[channel][domain] else 14.0
			channel_levels[channel][domain] = lerpf(channel_levels[channel][domain], channel_targets[channel][domain], 1.0 - exp(-delta * speed))
	if not has_audio:
		return
	history_elapsed += delta
	var wrote := false
	while history_elapsed >= 1.0 / HISTORY_RATE:
		history_elapsed -= 1.0 / HISTORY_RATE
		for channel in 2:
			var energy: Vector3 = previous[channel].lerp(channel_levels[channel], clampf(1.0 - history_elapsed / maxf(delta, 0.00001), 0.0, 1.0))
			history_image.set_pixel(history_position, channel, Color(energy.x, energy.y, energy.z, maxf(energy.x, maxf(energy.y, energy.z))))
		history_position = (history_position + 1) % HISTORY_SAMPLES
		wrote = true
	if wrote:
		history_texture.update(history_image)


func _update_spectral_history(delta: float) -> void:
	if not has_audio:
		return
	spectral_history_duration = minf(4.2, spectral_history_duration + delta)
	spectral_history_elapsed += delta
	var wrote := false
	while spectral_history_elapsed >= 1.0 / SPECTRAL_HISTORY_RATE:
		spectral_history_elapsed -= 1.0 / SPECTRAL_HISTORY_RATE
		for channel in 2:
			for band in BANDS:
				spectral_history_image.set_pixel(band, channel * HISTORY_SAMPLES + spectral_history_position, Color(spectrum_levels[channel * BANDS + band], 0, 0, 0))
		spectral_history_position = (spectral_history_position + 1) % HISTORY_SAMPLES
		wrote = true
	if wrote:
		spectral_history_texture.update(spectral_history_image)


func _auto_quality(delta: float) -> void:
	if Settings.visualizer_quality != 0:
		return
	quality_elapsed += delta
	if quality_elapsed < 3.0:
		return
	var refresh := 90.0
	if DisplayServer.get_name() != "headless":
		refresh = maxf(60.0, DisplayServer.screen_get_refresh_rate())
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized() and xr.has_method("get_display_refresh_rate"):
		refresh = maxf(60.0, xr.get_display_refresh_rate())
	var budget := 1.0 / refresh
	var rid := get_viewport().get_viewport_rid()
	var measured := maxf(RenderingServer.viewport_get_measured_render_time_gpu(rid), RenderingServer.viewport_get_measured_render_time_cpu(rid)) * 0.001
	if measured <= 0.0:
		return
	slow_frames = slow_frames + delta if measured > budget * 0.75 else maxf(0.0, slow_frames - delta * 0.5)
	fast_frames = fast_frames + delta if measured < budget * 0.45 else 0.0
	if slow_frames > 1.0 and quality > 0:
		quality -= 1
		slow_frames = 0.0
		fast_frames = 0.0
		_apply_quality()
	elif fast_frames > 15.0 and quality < 2:
		quality += 1
		fast_frames = 0.0
		_apply_quality()


static func _strip(segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		vertices.append(Vector3(float(i) / segments, -1.0, 0.0))
		vertices.append(Vector3(float(i) / segments, 1.0, 0.0))
		if i < segments:
			var a := i * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _surface(frequency_segments: int, time_segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in time_segments + 1:
		for column in frequency_segments + 1:
			vertices.append(Vector3(float(column) / frequency_segments, float(row) / time_segments, 0.0))
			if row < time_segments and column < frequency_segments:
				var a := row * (frequency_segments + 1) + column
				var b := a + frequency_segments + 1
				indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _octahedron() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 4, 2, 1, 3, 4, 1, 5, 3, 1, 2, 5])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
