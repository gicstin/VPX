extends Node

const PIXELS_PER_DEGREE := 32.0
const MAX_SIZE := 8192
const MIN_SIZE := 256
const REFRESH_INTERVAL := 0.5
const OUTPUT_FLAT := 1
const OUTPUT_EQUIRECT := 2

var player: VPXPlayer
var screen: MeshInstance3D
var menu_panel: Node3D
var origin: XROrigin3D
var xr_active := false
var force_offscreen := false
var layers: Array[OpenXRCompositionLayer] = []
var viewports: Array[SubViewport] = []
var quads: Array[MeshInstance3D] = []
var config_key := ""
var last_serial := -1
var refresh_timer := 0.0
var dirty := true
var active := false


func _ready() -> void:
	Settings.changed.connect(func() -> void: dirty = true)


func is_active() -> bool:
	return active


func _wanted() -> bool:
	if menu_panel != null and menu_panel.visible:
		return false
	if not Settings.compositor_layer or (not xr_active and not force_offscreen):
		return false
	if player.is_immersive_visualizer_active():
		return false
	if player.playback == null or player.is_image() or player.current_path.is_empty():
		return false
	var texture := player.get_video_texture()
	return texture != null and texture.get_height() > 0


func _process(delta: float) -> void:
	var wanted := _wanted()
	if not wanted:
		if active:
			_teardown()
		return
	var sizes := _layer_sizes()
	var eyes := 2 if Settings.stereo != Settings.Stereo.MONO and not Settings.single_eye else 1
	var key := "%s %d %s %s" % [_kind(), eyes, sizes, Settings.background]
	if key != config_key:
		_teardown()
		_build(eyes, sizes)
		config_key = key
		active = true
	_place()
	var serial: int = screen.bound_serial
	refresh_timer += delta
	if serial != last_serial or dirty or refresh_timer >= REFRESH_INTERVAL:
		last_serial = serial
		dirty = false
		refresh_timer = 0.0
	for viewport in viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _kind() -> String:
	match Settings.projection:
		Settings.ProjectionMode.FLAT:
			return "cylinder" if screen.curve_inverse_radius() > 0.0001 else "quad"
	return "equirect"


func _span_degrees() -> float:
	match Settings.projection:
		Settings.ProjectionMode.EQUIRECT_180:
			return clampf(Settings.equirect_fov, 90.0, 360.0)
		Settings.ProjectionMode.FISHEYE:
			return clampf(Settings.fisheye_fov, 90.0, 360.0)
	return 360.0


func _source_eye_size() -> Vector2:
	var texture := player.get_video_texture()
	var size := Vector2(texture.get_width(), texture.get_height())
	match Settings.stereo:
		Settings.Stereo.SIDE_BY_SIDE:
			size.x *= 0.5
		Settings.Stereo.OVER_UNDER:
			size.y *= 0.5
	if Settings.alpha_mask == Settings.AlphaMask.STACKED_BELOW:
		size.y *= 0.5
	size.x *= maxf(1.0 - Settings.crop_left - Settings.crop_right, 0.05)
	size.y *= maxf(1.0 - Settings.crop_top - Settings.crop_bottom, 0.05)
	return size


func _layer_sizes() -> Vector2i:
	var source := _source_eye_size()
	if Settings.projection == Settings.ProjectionMode.FLAT:
		var width := minf(source.x, Settings.screen_size * PIXELS_PER_DEGREE)
		var height := width / maxf(player.content_aspect() / (2.0 if Settings.stereo == Settings.Stereo.SIDE_BY_SIDE else (0.5 if Settings.stereo == Settings.Stereo.OVER_UNDER else 1.0)), 0.1)
		return _clamp_size(Vector2(width, height))
	var span := _span_degrees()
	var source_density := source.x / span
	match Settings.projection:
		Settings.ProjectionMode.EAC, Settings.ProjectionMode.CUBEMAP:
			source_density = source.x / 3.0 / 90.0
		Settings.ProjectionMode.EQUIRECT_360:
			source_density = source.x / 360.0
	var density := minf(PIXELS_PER_DEGREE, source_density * 1.1)
	return _clamp_size(Vector2(span * density, 180.0 * density))


func _clamp_size(size: Vector2) -> Vector2i:
	var scale := minf(1.0, float(MAX_SIZE) / maxf(size.x, size.y))
	return Vector2i(maxi(int(size.x * scale) & ~1, MIN_SIZE), maxi(int(size.y * scale) & ~1, MIN_SIZE))


func _build(eyes: int, size: Vector2i) -> void:
	var kind := _kind()
	var alpha := Settings.background == Settings.Background.PASSTHROUGH
	for eye in eyes:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.own_world_3d = true
		viewport.transparent_bg = alpha
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.0
		camera.position = Vector3(0, 0, 1)
		camera.near = 0.1
		camera.far = 4.0
		viewport.add_child(camera)
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(float(size.x) / float(size.y), 1.0)
		quad.mesh = mesh
		quad.material_override = screen.material
		quad.set_instance_shader_parameter("layer_output", OUTPUT_FLAT if kind != "equirect" else OUTPUT_EQUIRECT)
		quad.set_instance_shader_parameter("layer_eye", (eye + 1) if eyes == 2 else 1)
		var span := deg_to_rad(_span_degrees())
		quad.set_instance_shader_parameter("layer_angles", Vector4(span, PI * 0.5, PI * 0.5, 0.0))
		viewport.add_child(quad)
		add_child(viewport)
		viewports.append(viewport)
		quads.append(quad)
		if not xr_active:
			continue
		var layer: OpenXRCompositionLayer
		match kind:
			"quad":
				layer = OpenXRCompositionLayerQuad.new()
			"cylinder":
				layer = OpenXRCompositionLayerCylinder.new()
			_:
				layer = OpenXRCompositionLayerEquirect.new()
		layer.layer_viewport = viewport
		layer.sort_order = -1
		layer.enable_hole_punch = true
		layer.alpha_blend = alpha
		layer.eye_visibility = (OpenXRCompositionLayer.EYE_VISIBILITY_LEFT if eye == 0 else OpenXRCompositionLayer.EYE_VISIBILITY_RIGHT) if eyes == 2 else OpenXRCompositionLayer.EYE_VISIBILITY_BOTH
		layer.swapchain_state_min_filter = OpenXRCompositionLayer.FILTER_LINEAR
		layer.swapchain_state_mag_filter = OpenXRCompositionLayer.FILTER_LINEAR
		origin.add_child(layer)
		layers.append(layer)
	var native := xr_active and not layers.is_empty() and layers[0].is_natively_supported()
	screen.hidden_by_layer = native
	Log.info("compositor layer %s, %d eye image(s) %dx%d%s" % [kind, eyes, size.x, size.y, "" if native else " (screen mesh stays)"])
	if xr_active and not native:
		Log.warn("runtime has no native %s layer, keeping the screen mesh" % kind)


func _teardown() -> void:
	for layer in layers:
		layer.queue_free()
	for viewport in viewports:
		viewport.queue_free()
	layers.clear()
	viewports.clear()
	quads.clear()
	config_key = ""
	active = false
	if screen != null:
		screen.hidden_by_layer = false


func _place() -> void:
	if layers.is_empty():
		return
	var to_origin := origin.global_transform.affine_inverse()
	var target := screen.global_transform
	for layer in layers:
		if layer is OpenXRCompositionLayerQuad:
			var quad_mesh := screen.mesh as QuadMesh
			if quad_mesh != null:
				(layer as OpenXRCompositionLayerQuad).quad_size = quad_mesh.size
			layer.transform = to_origin * target
		elif layer is OpenXRCompositionLayerCylinder:
			var cylinder := layer as OpenXRCompositionLayerCylinder
			var bend: float = screen.curve_inverse_radius()
			var radius := 1.0 / maxf(bend, 0.0001)
			var width := Settings.flat_screen_width()
			var quad_mesh := screen.mesh as QuadMesh
			var height := quad_mesh.size.y if quad_mesh != null else width * 9.0 / 16.0
			cylinder.radius = radius
			cylinder.central_angle = minf(width * bend, TAU)
			cylinder.aspect_ratio = width / maxf(height, 0.01)
			layer.transform = to_origin * target * Transform3D(Basis.IDENTITY, Vector3(0, 0, radius))
		elif layer is OpenXRCompositionLayerEquirect:
			var equirect := layer as OpenXRCompositionLayerEquirect
			equirect.radius = 0.0
			equirect.central_horizontal_angle = deg_to_rad(_span_degrees())
			equirect.upper_vertical_angle = PI * 0.5
			equirect.lower_vertical_angle = PI * 0.5
			layer.transform = to_origin * target


func eye_image(eye: int) -> Image:
	if eye >= viewports.size():
		return null
	return viewports[eye].get_texture().get_image()
