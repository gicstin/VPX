class_name ResonanceField
extends Node3D

signal activity_changed

const RESPONSE_PROFILES := preload("res://scripts/visualizer_response_profiles.gd")
const BANDS := 48
const ROWS := 50
const COUNTS := [Vector4i(24, 900, 12, 4), Vector4i(40, 2400, 20, 6), Vector4i(64, 5200, 32, 8)]
const LEGACY_COUNTS := [Vector4i(12, 900, 8, 0), Vector4i(20, 2400, 14, 0), Vector4i(32, 5200, 24, 0)]
const DEPTH_COUNTS := [Vector4i(48, 0, 2, 0), Vector4i(72, 0, 2, 0), Vector4i(96, 0, 2, 0)]
const PULSE_COUNTS := [Vector4i(64, 1600, 32, 3), Vector4i(96, 3200, 48, 3), Vector4i(128, 5200, 64, 3)]
const PULSE_START := 17
const STEREO_COUNTS := [Vector4i(96, 2000, 48, 16), Vector4i(128, 3600, 64, 16), Vector4i(160, 5200, 96, 16)]
const STEREO_START := 22
const PSYCHE_COUNTS := [Vector4i(127, 900, 24, 24), Vector4i(191, 1400, 32, 32), Vector4i(255, 2000, 48, 48)]
const PSYCHE_LIMITS := [Vector4i(160, 2000, 6, 20), Vector4i(255, 1400, 10, 0), Vector4i(55, 1600, 7, 48), Vector4i(96, 1400, 24, 4), Vector4i(128, 1400, 6, 0), Vector4i(47, 2000, 48, 48), Vector4i(72, 1728, 6, 0), Vector4i(96, 1400, 5, 0)]
const PSYCHE_SEGMENTS := [96, 8, 192, 96, 64, 32, 48, 96]
const PSYCHE_START := 68
const LIVE_START := 80
const SPECTROGRAM_START := 102
const SPECTROGRAM_COUNTS := [Vector4i(8, 0, 192, 0), Vector4i(8, 0, 384, 0), Vector4i(8, 0, 384, 0)]
const SPECTROGRAM_SHADER := preload("res://shaders/resonance_spectrogram.gdshader")
const SPECTROGRAM_SKY_SHADER := preload("res://shaders/resonance_spectrogram_sky.gdshader")
const WORLD_START := 110
const WORLD_COUNTS := [Vector4i(1, 1400, 24, 40), Vector4i(1, 2800, 24, 40), Vector4i(1, 4600, 24, 40)]
const WORLD_STRUCTURES := [24, 32, 40]
const WORLD_GROUND := [-1.5, -1.6, -4.0]
const WORLD_SHADER := preload("res://shaders/resonance_world.gdshader")
const WORLD_GROUND_SHADER := preload("res://shaders/resonance_world_ground.gdshader")
const WORLD_SKY_SHADER := preload("res://shaders/resonance_world_sky.gdshader")
const WORLD_PALETTES := [
	[[Color(0.12, 0.42, 1.0), Color(0.95, 0.3, 0.75), Color(1.0, 0.78, 0.32)], [Color(0.1, 0.85, 0.65), Color(0.3, 0.35, 1.0), Color(0.95, 0.95, 0.6)], [Color(1.0, 0.35, 0.15), Color(0.65, 0.15, 0.9), Color(1.0, 0.85, 0.5)], [Color(0.3, 0.6, 1.0), Color(0.15, 1.0, 0.8), Color(1.0, 0.5, 0.75)]],
	[[Color(1.0, 0.62, 0.22), Color(0.55, 0.25, 1.0), Color(1.0, 0.92, 0.7)], [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.45), Color(0.85, 0.95, 1.0)], [Color(0.95, 0.85, 0.35), Color(0.2, 0.75, 0.9), Color(1.0, 0.55, 0.3)], [Color(0.75, 0.2, 0.55), Color(1.0, 0.7, 0.3), Color(0.6, 0.85, 1.0)]],
	[[Color(0.05, 0.55, 0.9), Color(0.25, 1.0, 0.75), Color(0.75, 0.4, 1.0)], [Color(0.1, 0.35, 0.85), Color(1.0, 0.45, 0.75), Color(0.3, 1.0, 0.9)], [Color(0.0, 0.7, 0.75), Color(0.6, 0.95, 0.3), Color(1.0, 0.65, 0.4)], [Color(0.2, 0.25, 0.9), Color(0.15, 0.9, 1.0), Color(1.0, 0.95, 0.6)]],
]
const IMMERSIVE_START := 92
const IMMERSIVE_COUNTS := [Vector4i(64, 240, 96, 0), Vector4i(64, 480, 144, 0), Vector4i(64, 900, 192, 0)]
const IMMERSIVE_LIMITS := [Vector2i(18, 36), Vector2i(12, 96), Vector2i(12, 48), Vector2i(54, 108), Vector2i(28, 56), Vector2i(8, 16), Vector2i(64, 128), Vector2i(8, 32), Vector2i(48, 96), Vector2i(16, 64)]
const IMMERSIVE_SHADER := preload("res://shaders/resonance_immersive.gdshader")
const IMMERSIVE_SKY_SHADER := preload("res://shaders/resonance_immersive_sky.gdshader")
const PROJECTM_START := 86
const PROJECTM_COUNTS := [Vector4i(48, 480, 12, 0), Vector4i(72, 900, 18, 0), Vector4i(96, 1500, 24, 0)]
const PROJECTM_SHADER := preload("res://shaders/resonance_projectm.gdshader")
const PROJECTM_SKY_SHADER := preload("res://shaders/resonance_projectm_sky.gdshader")
const LIVE_COUNTS := [Vector4i(48, 900, 12, 4), Vector4i(72, 1700, 20, 6), Vector4i(96, 2800, 28, 8)]
const LIVE_SKY_SHADER := preload("res://shaders/resonance_live_sky.gdshader")
const LIVE_SHADER := preload("res://shaders/resonance_live.gdshader")
const MILKDROP_START := 76
const MILKDROP_COUNTS := [Vector4i(32, 700, 8, 0), Vector4i(48, 1400, 12, 0), Vector4i(64, 2000, 16, 0)]
const MILKDROP_SHADER := preload("res://shaders/resonance_milkdrop.gdshader")
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
const PSYCHE_SHADER := preload("res://shaders/resonance_psyche.gdshader")
const PSYCHE_SKY_SHADER := preload("res://shaders/resonance_psyche_sky.gdshader")

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
var sky: MeshInstance3D
var vr_zoom := false
var clock := 0.0
var presence := 0.0
var bass := 0.0
var mids := 0.0
var treble := 0.0
var impulse := 0.0
var stereo_width := 0.0
var correlation := 1.0
var preset := Vector3(1, 0, 0)
var response_profile := Vector3.ONE
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
var spectrum_settled := true
var spectrum_settled_delta := INF
var source_count := 2
var channel_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var channel_levels: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var history_image: Image
var history_texture: ImageTexture
var history_position := 0
var history_elapsed := 0.0
var spectral_history_image: Image
var spectral_history_row: Image
var spectral_history_texture: ImageTexture
var spectral_history_position := 0
var spectral_history_elapsed := 0.0
var spectral_history_duration := 0.0
var scene_opacity := 1.0
var compositing_overlay := false
var overlay_shaders: Dictionary = {}
var live_particle_mesh: QuadMesh
var particle_mesh: ArrayMesh
var live_mesh: ArrayMesh
var strip_mesh: ArrayMesh
var surface_mesh: ArrayMesh
var spectrogram_meshes: Array[ArrayMesh] = []
var immersive_mesh: ArrayMesh
var projectm_sun_mesh: SphereMesh
var psyche_meshes: Array[ArrayMesh] = []
var ring_mesh: ArrayMesh
var psyche_bass := 0.0
var stereo := StereoImage.new()
var affect := MusicAffect.new()
var timeline := MusicTimeline.new()
var music_time := -1.0
var timeline_beats := 0
var world_ground_mesh: ArrayMesh
var world_colours: Array[Color] = [Color(0.12, 0.42, 1.0), Color(0.95, 0.3, 0.75), Color(1.0, 0.78, 0.32)]


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
	spectral_history_row = Image.create_empty(BANDS, 2, false, Image.FORMAT_RF)
	var wave_empty := PackedByteArray()
	wave_empty.resize(WAVE_SAMPLES * 2 * 4)
	wave_image = Image.create_from_data(WAVE_SAMPLES, 2, false, Image.FORMAT_RF, wave_empty)
	wave_texture = ImageTexture.create_from_image(wave_image)
	sky = MeshInstance3D.new()
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
	live_mesh = _strip(160)
	particle_mesh = _octahedron()
	live_particle_mesh = QuadMesh.new()
	live_particle_mesh.size = Vector2(2, 2)
	ring_mesh = _strip(64)
	for segments in PSYCHE_SEGMENTS:
		psyche_meshes.append(_strip(segments))
	surface_mesh = _surface(48, 192)
	immersive_mesh = _surface(128, 12)
	spectrogram_meshes.resize(3)
	spectrogram_meshes[1] = surface_mesh
	projectm_sun_mesh = SphereMesh.new()
	projectm_sun_mesh.radius = 1.0
	projectm_sun_mesh.height = 2.0
	projectm_sun_mesh.radial_segments = 64
	projectm_sun_mesh.rings = 32
	for kind in 4:
		var layer := MultiMeshInstance3D.new()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_custom_data = true
		instances.mesh = particle_mesh if kind == 1 else strip_mesh
		instances.instance_count = maxi(WORLD_COUNTS[2][kind], maxi(SPECTROGRAM_COUNTS[2][kind], maxi(IMMERSIVE_COUNTS[2][kind], maxi(maxi(maxi(COUNTS[2][kind], DEPTH_COUNTS[2][kind]), maxi(PULSE_COUNTS[2][kind], STEREO_COUNTS[2][kind])), PSYCHE_COUNTS[2][kind]))))
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
	_apply_compositing()


func cycle_preset() -> void:
	preset_elapsed = 0.0
	Settings.cycle_visualizer_preset(1)


func _apply_preset() -> void:
	response_profile = RESPONSE_PROFILES.VALUES.get(Settings.VISUALIZER_PRESETS[preset_index], Vector3.ONE)
	var pulse := preset_index >= PULSE_START and preset_index < STEREO_START
	var world_scene := is_world_scene()
	var spectrogram_scene := preset_index >= SPECTROGRAM_START and not world_scene
	var immersive_scene := preset_index >= IMMERSIVE_START and preset_index < SPECTROGRAM_START
	var projectm_scene := preset_index >= PROJECTM_START and preset_index < IMMERSIVE_START
	var live_scene := preset_index >= LIVE_START and preset_index < PROJECTM_START
	var milkdrop := preset_index >= MILKDROP_START and preset_index < LIVE_START
	var psyche := preset_index >= PSYCHE_START and preset_index < MILKDROP_START
	var image_scene := preset_index >= STEREO_START and preset_index < PSYCHE_START
	var shader := WORLD_SHADER if world_scene else SPECTROGRAM_SHADER if spectrogram_scene else IMMERSIVE_SHADER if immersive_scene else PROJECTM_SHADER if projectm_scene else LIVE_SHADER if live_scene else MILKDROP_SHADER if milkdrop else LEGACY_SHADER if preset_index < 3 else (PSYCHE_SHADER if psyche else (STEREO_SHADER if image_scene else (PULSE_SHADER if pulse else (DEPTH_SHADER if preset_index >= 7 else SHADER))))
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
		material.set_shader_parameter("psyche_style", maxi(0, preset_index - PSYCHE_START))
		material.set_shader_parameter("live_style", maxi(0, preset_index - LIVE_START))
		material.set_shader_parameter("projectm_style", maxi(0, preset_index - PROJECTM_START))
		material.set_shader_parameter("spectrogram_style", maxi(0, preset_index - SPECTROGRAM_START))
		material.set_shader_parameter("immersive_style", maxi(0, preset_index - IMMERSIVE_START))
		material.set_shader_parameter("object_count", IMMERSIVE_LIMITS[preset_index - IMMERSIVE_START].x if immersive_scene else 0)
		material.set_shader_parameter("milkdrop_style", maxi(0, preset_index - MILKDROP_START))
		material.set_shader_parameter("world_style", world_style())
		stereo.bind(material)
	if world_scene:
		materials[0].shader = WORLD_GROUND_SHADER
	layers[1].multimesh.mesh = live_particle_mesh if live_scene else particle_mesh
	for kind in [0, 2, 3]:
		layers[kind].multimesh.mesh = (live_mesh if kind == 0 else ring_mesh) if live_scene else (psyche_meshes[preset_index - PSYCHE_START] if kind == 0 else ring_mesh) if psyche else (surface_mesh if kind == 2 and preset_index >= 7 and preset_index < PULSE_START else strip_mesh)
	if spectrogram_scene:
		layers[0].multimesh.mesh = _spectrogram_mesh()
		layers[2].multimesh.mesh = live_mesh
	if immersive_scene:
		layers[0].multimesh.mesh = immersive_mesh
		layers[2].multimesh.mesh = live_mesh
	if world_scene:
		if world_ground_mesh == null:
			world_ground_mesh = _surface(192, 96)
		layers[0].multimesh.mesh = world_ground_mesh
		layers[1].multimesh.mesh = live_particle_mesh
		layers[2].multimesh.mesh = strip_mesh
		layers[3].multimesh.mesh = strip_mesh
		world_colours = _world_palette(0)
	if projectm_scene:
		layers[3].multimesh.mesh = projectm_sun_mesh if preset_index == PROJECTM_START + 4 else surface_mesh
	sky_material.shader = WORLD_SKY_SHADER if world_scene else SPECTROGRAM_SKY_SHADER if spectrogram_scene else IMMERSIVE_SKY_SHADER if immersive_scene else PROJECTM_SKY_SHADER if projectm_scene else LIVE_SKY_SHADER if live_scene else PSYCHE_SKY_SHADER if milkdrop else LEGACY_SKY_SHADER if preset_index < 3 else (PSYCHE_SKY_SHADER if psyche else (STEREO_SKY_SHADER if image_scene else (PULSE_SKY_SHADER if pulse else SKY_SHADER)))
	sky_material.set_shader_parameter("spectrogram_style", maxi(0, preset_index - SPECTROGRAM_START))
	sky_material.set_shader_parameter("world_style", world_style())
	sky_material.set_shader_parameter("live_style", maxi(0, preset_index - LIVE_START))
	sky_material.set_shader_parameter("projectm_style", maxi(0, preset_index - PROJECTM_START))
	sky_material.set_shader_parameter("immersive_style", maxi(0, preset_index - IMMERSIVE_START))
	sky_material.set_shader_parameter("pulse_style", maxi(0, preset_index - PULSE_START))
	sky_material.set_shader_parameter("stereo_style", maxi(0, preset_index - STEREO_START))
	sky_material.set_shader_parameter("psyche_style", 0 if live_scene else 1 if milkdrop else maxi(0, preset_index - PSYCHE_START))
	stereo.bind(sky_material)
	sky_material.set_shader_parameter("spectrum_texture", texture)
	scene_opacity = 0.0
	_apply_compositing(true)


func _overlay_shader(source: Shader, atmosphere: bool) -> Shader:
	if overlay_shaders.has(source):
		return overlay_shaders[source]
	var shader := Shader.new()
	var code := source.code.replace("render_mode unshaded,", "render_mode unshaded, depth_test_disabled,")
	if atmosphere:
		code = code.replace("cull_front,", "depth_draw_never, cull_front,")
		code = code.replace("shader_type spatial;", "shader_type spatial;\nuniform float overlay_opacity = 1.0;")
		var end := code.rfind("}")
		code = code.insert(end, "\tALPHA = overlay_opacity;\n")
	shader.code = code
	overlay_shaders[source] = shader
	return shader


func _apply_compositing(force := false) -> void:
	var overlay := player != null and player.is_visualizer_overlay_active()
	if overlay == compositing_overlay and not force:
		return
	compositing_overlay = overlay
	if is_world_scene() and not force:
		_apply_quality()
	for material in materials:
		if overlay:
			material.shader = _overlay_shader(material.shader, false)
		else:
			for source: Shader in overlay_shaders:
				if material.shader == overlay_shaders[source]:
					material.shader = source
		material.render_priority = -14 if overlay else 0
	if overlay:
		sky_material.shader = _overlay_shader(sky_material.shader, true)
	else:
		for source: Shader in overlay_shaders:
			if sky_material.shader == overlay_shaders[source]:
				sky_material.shader = source
	sky_material.render_priority = -15 if overlay else 0


func _spectrogram_mesh() -> ArrayMesh:
	var tier := clampi(quality, 0, 2)
	if spectrogram_meshes[tier] == null:
		spectrogram_meshes[tier] = _surface(96 if tier == 2 else 48, 96 if tier == 0 else 192)
	return spectrogram_meshes[tier]


func _apply_quality() -> void:
	var world_scene := is_world_scene()
	if preset_index >= SPECTROGRAM_START and not world_scene:
		layers[0].multimesh.mesh = _spectrogram_mesh()
	var counts: Array = WORLD_COUNTS if world_scene else SPECTROGRAM_COUNTS if preset_index >= SPECTROGRAM_START else IMMERSIVE_COUNTS if preset_index >= IMMERSIVE_START else PROJECTM_COUNTS if preset_index >= PROJECTM_START else LIVE_COUNTS if preset_index >= LIVE_START else MILKDROP_COUNTS if preset_index >= MILKDROP_START else LEGACY_COUNTS if preset_index < 3 else (PSYCHE_COUNTS if preset_index >= PSYCHE_START else (STEREO_COUNTS if preset_index >= STEREO_START else (PULSE_COUNTS if preset_index >= PULSE_START else (DEPTH_COUNTS if preset_index >= 7 else COUNTS))))
	for kind in layers.size():
		var count: int = counts[clampi(quality, 0, 2)][kind]
		if world_scene:
			if kind == 0 and compositing_overlay:
				count = 0
			elif kind == 3:
				count = WORLD_STRUCTURES[world_style()]
		elif preset_index >= SPECTROGRAM_START:
			if preset_index == SPECTROGRAM_START + 4:
				count /= 2
		elif preset_index >= IMMERSIVE_START:
			if kind == 0 or kind == 2:
				count = mini(count, IMMERSIVE_LIMITS[preset_index - IMMERSIVE_START][0 if kind == 0 else 1])
		elif preset_index >= PROJECTM_START:
			if kind == 3:
				count = 1 if preset_index in [PROJECTM_START + 3, PROJECTM_START + 4] else 0
			elif kind == 2 and preset_index == PROJECTM_START + 5:
				count = 0
		elif preset_index >= MILKDROP_START and preset_index < LIVE_START:
			if kind == 1 and preset_index != MILKDROP_START + 3:
				count = 0
		elif preset_index >= PSYCHE_START and preset_index < MILKDROP_START:
			var limit: int = PSYCHE_LIMITS[preset_index - PSYCHE_START][kind]
			count = mini(count, limit)
			if kind == 0 and preset_index == PSYCHE_START + 1:
				count = [127, 191, 255][clampi(quality, 0, 2)]
		layers[kind].multimesh.visible_instance_count = count
		materials[kind].set_shader_parameter("seed_count", mini(counts[clampi(quality, 0, 2)][1], 1600))
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
	if spectrum_targets != data:
		spectrum_targets = data.duplicate()
		spectrum_settled = false
	var channels := int(features.get("channels", 2))
	var spatial := bool(features.get("spatial", Settings.spatial_audio))
	source_count = 0
	if channels == 1:
		source_count = 1
	elif (channels == 2 and not features.get("ambisonic", false)) or not spatial:
		source_count = 2
	stereo.feed(data, source_count == 1, float(features.get("correlation", 1.0)))
	affect.feed(data, float(features.get("rms", 0.0)))
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
	correlation = clampf(float(features.get("correlation", 1.0)), -1.0, 1.0)
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
	var beat_rise := rise.x
	var beat_energy := energy.x
	if preset_index >= PSYCHE_START:
		var low_power := 0.0
		for band in 10:
			var value := maxf(data[band], data[BANDS + band])
			var magnitude := db_to_linear(value * 60.0 - 60.0) if value > 0.0 else 0.0
			low_power += magnitude * magnitude / 10.0
		beat_energy = sqrt(low_power) * 5.0
		psyche_bass = beat_energy
	if not timeline.active and beat_rise > 0.045 and beat_energy > (0.1 if preset_index >= PSYCHE_START else 0.08) and beat_age > 0.16:
		beat_age = 0.0
		beat_count += 1
	domain_targets = energy


func silence() -> void:
	if has_audio:
		_clear_spectrum()
		stereo.clear()
		affect.silence()
		psyche_bass = 0.0
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
	correlation = 1.0
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
	affect.reset()
	timeline.reset()
	psyche_bass = 0.0
	bass = 0.0
	mids = 0.0
	treble = 0.0
	clock = 0.0
	spectrum_levels.fill(0.0)
	preset_elapsed = 0.0
	_clear_spectrum()


func _clear_spectrum() -> void:
	has_audio = false
	spectrum_settled = true
	spectrum_settled_delta = INF
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


func rotate_scene(rotation: Basis) -> void:
	global_basis = (rotation * global_basis).orthonormalized()
	var source_basis := audio_anchor.global_basis if audio_anchor != null else global_basis
	audio_basis = source_basis.orthonormalized().inverse() * global_basis


func _process(delta: float) -> void:
	visible = active
	if not active:
		return
	_apply_compositing()
	_update_zoom()
	var response_intensity := clampf(Settings.visualizer_intensity * response_profile.x, 0.0, 1.5)
	var response_sensitivity := clampf(Settings.visualizer_sensitivity * response_profile.y, 0.5, 4.0)
	var response_motion := clampf(Settings.visualizer_motion * response_profile.z, 0.0, 1.0)
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
	var drive := (0.6 + bass * 2.2 + impulse * 2.5 + transients.x * 1.5) * response_motion
	surge = lerpf(surge, drive if playing else 0.0, 1.0 - exp(-delta * 10.0))
	travel = fmod(travel + surge * delta, 1000.0)
	spin += (0.5 + mids * 1.6 + transients.y) * response_motion * delta * (1.0 if playing else 0.0)
	_smooth_spectrum(delta)
	_update_history(delta)
	_update_spectral_history(delta)
	stereo.update(delta)
	affect.update(delta, beat_count, psyche_bass, response_motion)
	_update_timeline(delta, playing)
	scene_opacity = lerpf(scene_opacity, 1.0, 1.0 - exp(-delta * 8.0))
	var dim := (0.2 if menu != null and menu.visible else 1.0) * scene_opacity
	var palette := clock * 0.0025 + preset.dot(Vector3(0.0, 0.17, 0.38))
	var world := is_world_scene()
	if world:
		_update_world_palette(delta)
	for kind in materials.size():
		if layers[kind].multimesh.visible_instance_count == 0:
			continue
		var material := materials[kind]
		material.set_shader_parameter("source_count", source_count if preset_index == 6 else 0)
		material.set_shader_parameter("spectral_history_head", posmod(spectral_history_position - 1, HISTORY_SAMPLES) if spectral_history_duration >= 1.0 / SPECTRAL_HISTORY_RATE else -1)
		material.set_shader_parameter("spectral_history_fraction", spectral_history_elapsed * SPECTRAL_HISTORY_RATE)
		material.set_shader_parameter("spectral_channel_count", 1 if source_count == 1 else 2)
		material.set_shader_parameter("spectral_history_valid", minf(1.0, spectral_history_duration / 3.8))
		material.set_shader_parameter("history_head", float(history_position - 1) / HISTORY_SAMPLES)
		material.set_shader_parameter("history_fraction", history_elapsed * HISTORY_RATE)
		material.set_shader_parameter("audio_basis", audio_basis)
		material.set_shader_parameter("clock", clock)
		material.set_shader_parameter("intensity", response_intensity)
		material.set_shader_parameter("sensitivity", response_sensitivity)
		material.set_shader_parameter("motion", response_motion)
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
		material.set_shader_parameter("correlation", correlation)
		material.set_shader_parameter("palette", palette)
		material.set_shader_parameter("preset", preset)
		material.set_shader_parameter("dim", dim * (Settings.visualizer_overlay_opacity if compositing_overlay else 1.0))
		stereo.apply(material)
		affect.apply(material)
		timeline.apply(material)
		if world:
			_apply_world(material)
	sky_material.set_shader_parameter("source_count", source_count if preset_index >= 6 else 0)
	sky_material.set_shader_parameter("channel_left", channel_levels[0])
	sky_material.set_shader_parameter("channel_right", channel_levels[1])
	sky_material.set_shader_parameter("clock", clock * response_motion)
	sky_material.set_shader_parameter("bass", bass)
	sky_material.set_shader_parameter("mids", mids)
	sky_material.set_shader_parameter("treble", treble)
	sky_material.set_shader_parameter("transients", transients)
	sky_material.set_shader_parameter("palette", palette)
	sky_material.set_shader_parameter("beat_age", beat_age)
	sky_material.set_shader_parameter("beat_count", float(beat_count))
	sky_material.set_shader_parameter("travel", travel)
	sky_material.set_shader_parameter("spin", spin)
	sky_material.set_shader_parameter("sensitivity", response_sensitivity)
	sky_material.set_shader_parameter("intensity", response_intensity)
	sky_material.set_shader_parameter("dim", dim)
	if compositing_overlay:
		sky_material.set_shader_parameter("overlay_opacity", Settings.visualizer_atmosphere * Settings.visualizer_overlay_opacity)
	stereo.apply(sky_material)
	affect.apply(sky_material)
	timeline.apply(sky_material)
	if world:
		_apply_world(sky_material)
		sky_material.set_shader_parameter("motion", response_motion)
	_auto_quality(delta)


func is_world_scene() -> bool:
	return preset_index >= WORLD_START


func world_style() -> int:
	return clampi(preset_index - WORLD_START, 0, WORLD_STRUCTURES.size() - 1)


func set_music_map(map: MusicMap) -> void:
	timeline.set_map(map)


func _update_timeline(delta: float, playing: bool) -> void:
	timeline.update(music_time, delta, playing, {"transients": transients, "impulse": impulse, "mids": mids, "arousal": affect.arousal, "centroid": affect.centroid, "beat_phase": affect.beat_phase, "bar_phase": affect.bar_phase, "period": affect.period, "tension": affect.tension, "release": affect.release})
	if timeline.active:
		beat_count += maxi(0, timeline.beat_count - timeline_beats)
		beat_age = timeline.beat_age
	timeline_beats = timeline.beat_count


func _world_palette(group: int) -> Array[Color]:
	var choices: Array = WORLD_PALETTES[world_style()]
	var chosen: Array = choices[posmod(group, choices.size())]
	var colours: Array[Color] = []
	for colour: Color in chosen:
		colours.append(colour)
	return colours


func _update_world_palette(delta: float) -> void:
	var target := _world_palette(int(timeline.palette_group))
	var blend := 1.0 - exp(-delta * 0.8)
	for i in world_colours.size():
		world_colours[i] = world_colours[i].lerp(target[i], blend)


func _apply_world(material: ShaderMaterial) -> void:
	material.set_shader_parameter("world_style", world_style())
	material.set_shader_parameter("ground_level", ground_level())
	material.set_shader_parameter("colour_a", world_colours[0])
	material.set_shader_parameter("colour_b", world_colours[1])
	material.set_shader_parameter("colour_c", world_colours[2])
	material.set_shader_parameter("breath", affect.breath)
	material.set_shader_parameter("source_spread", source_spread())


func ground_level() -> float:
	var level: float = WORLD_GROUND[world_style()]
	var origin := camera.get_parent() as XROrigin3D if camera != null else null
	if not vr_zoom or origin == null:
		return level
	var floor_offset := origin.global_position.y - global_position.y
	if floor_offset < -2.1 or floor_offset > -0.8:
		return level
	return floor_offset + (level - WORLD_GROUND[0])


func source_spread() -> float:
	if vr_zoom or camera == null:
		return 0.9
	var size := get_viewport().get_visible_rect().size
	var half := atan(tan(deg_to_rad(camera.fov) * 0.5) * size.x / maxf(size.y, 1.0))
	return clampf(half * 0.72, 0.45, 0.9)


func _update_zoom() -> void:
	var transform := Transform3D.IDENTITY
	if (vr_zoom or compositing_overlay) and camera != null and not is_equal_approx(Settings.visualizer_zoom, 1.0):
		var view := global_basis.inverse() * camera.global_basis.orthonormalized()
		var depth := view * Basis.from_scale(Vector3(1.0, 1.0, 1.0 / Settings.visualizer_zoom)) * view.inverse()
		var origin := to_local(camera.global_position)
		transform = Transform3D(depth, origin - depth * origin)
	for layer in layers:
		if not layer.transform.is_equal_approx(transform):
			layer.transform = transform
	if not sky.transform.is_equal_approx(transform):
		sky.transform = transform


func _smooth_spectrum(delta: float) -> void:
	if (spectrum_settled and delta <= spectrum_settled_delta) or delta == 0.0:
		return
	var attack := 1.0 - exp(-delta * 45.0)
	var release := 1.0 - exp(-delta * 14.0)
	var changed := false
	for i in spectrum_levels.size():
		var previous := spectrum_levels[i]
		var target := spectrum_targets[i]
		var value := lerpf(previous, target, attack if target > previous else release)
		spectrum_levels[i] = 0.0 if value < 0.00001 else value
		changed = changed or spectrum_levels[i] != previous
	spectrum_settled = not changed
	spectrum_settled_delta = delta
	if changed:
		image.set_data(BANDS, ROWS, false, Image.FORMAT_RF, spectrum_levels.to_byte_array())
		texture.update(image)


func _update_history(delta: float) -> void:
	var previous_left := channel_levels[0]
	var previous_right := channel_levels[1]
	var attack := 1.0 - exp(-delta * 45.0)
	var release := 1.0 - exp(-delta * 14.0)
	for channel in 2:
		for domain in 3:
			channel_levels[channel][domain] = lerpf(channel_levels[channel][domain], channel_targets[channel][domain], attack if channel_targets[channel][domain] > channel_levels[channel][domain] else release)
	if not has_audio:
		return
	history_elapsed += delta
	var wrote := false
	while history_elapsed >= 1.0 / HISTORY_RATE:
		history_elapsed -= 1.0 / HISTORY_RATE
		for channel in 2:
			var previous := previous_left if channel == 0 else previous_right
			var energy: Vector3 = previous.lerp(channel_levels[channel], clampf(1.0 - history_elapsed / maxf(delta, 0.00001), 0.0, 1.0))
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
	if spectral_history_elapsed < 1.0 / SPECTRAL_HISTORY_RATE:
		return
	spectral_history_row.set_data(BANDS, 2, false, Image.FORMAT_RF, spectrum_levels.slice(0, BANDS * 2).to_byte_array())
	var wrote := false
	while spectral_history_elapsed >= 1.0 / SPECTRAL_HISTORY_RATE:
		spectral_history_elapsed -= 1.0 / SPECTRAL_HISTORY_RATE
		for channel in 2:
			spectral_history_image.blit_rect(spectral_history_row, Rect2i(0, channel, BANDS, 1), Vector2i(0, channel * HISTORY_SAMPLES + spectral_history_position))
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
