extends MeshInstance3D

const SPHERE_RADIUS := 50.0
const SPHERE_SEGMENTS := 96
const SPHERE_RINGS := 48
const CURVE_SEGMENTS := 96
const PLANE_COUNT := 4
const PLANE_PARAMS := [&"plane_y", &"plane_c", &"plane_c2", &"plane_a"]
const PICTURE_TILE_PARAMS := [&"tile_y", &"tile_cb", &"tile_cr"]
const PICTURE_CUBE_PARAMS := [&"cube_y", &"cube_cb", &"cube_cr"]
const SPC_BT709 := 1
const SPC_BT470BG := 5
const SPC_SMPTE170M := 6
const SPC_SMPTE240M := 7
const SPC_BT2020_NCL := 9
const SPC_BT2020_CL := 10
const RANGE_JPEG := 2
const TRC_PQ := 16
const TRC_HLG := 18
const PRI_BT2020 := 9
const CHROMA_LEFT := 1
const CHROMA_CENTER := 2
const CHROMA_TOPLEFT := 3
const CHROMA_TOP := 4
const CHROMA_BOTTOMLEFT := 5
const CHROMA_BOTTOM := 6
const EAC_FACES := [
	[Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, Vector2(2, 0)],
	[Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN, Vector2(0, 0)],
	[Vector3.UP, Vector3.FORWARD, Vector3.LEFT, Vector2(2, 1)],
	[Vector3.DOWN, Vector3.BACK, Vector3.LEFT, Vector2(0, 1)],
	[Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN, Vector2(1, 0)],
	[Vector3.BACK, Vector3.UP, Vector3.LEFT, Vector2(1, 1)],
]
const CUBE_FACES := [
	[Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, Vector2(0, 0)],
	[Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN, Vector2(1, 0)],
	[Vector3.UP, Vector3.RIGHT, Vector3.BACK, Vector2(2, 0)],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, Vector2(0, 1)],
	[Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN, Vector2(1, 1)],
	[Vector3.BACK, Vector3.LEFT, Vector3.DOWN, Vector2(2, 1)],
]

const AUTO_SWAP_PROJECTIONS := [Settings.ProjectionMode.EQUIRECT_180, Settings.ProjectionMode.FISHEYE]
const AUTO_SWAP_HYSTERESIS := 0.26
const ZOOM_HOLD_DEGREES := 8.0
const ZOOM_RAMP_DEGREES := 6.0
const ZOOM_FOLLOW_RATE := 3.0

@export var player: VPXPlayer

var refreshes_since_frame := 0
var view_yaw := 0.0
var zoom_forward := Vector3.FORWARD
var displayed_zoom := 1.0
var zoom_snap := true
var view_origin: Node3D
var material := ShaderMaterial.new()
var pick_viewport: SubViewport
var pick_material := ShaderMaterial.new()
var probe: AlphaProbe
var bound_playback: FFmpegVideoStreamPlayback
var bound_serial := -1
var last_frame_time := -1.0
var last_seek_serial := 0
var bound_image: VPXPanorama
var geometry_key := ""
var glow_materials: Array[ShaderMaterial] = []
var hidden_by_layer := false
var auto_swapped := false
var flat_desktop := false
var menu_dim_value := 1.0
var media_dim_value := -1.0


func _ready() -> void:
	material.shader = preload("res://shaders/screen.gdshader")
	displayed_zoom = Settings.picture_zoom
	Settings.changed.connect(refresh)
	Settings.zoom_changed.connect(_on_zoom_changed)
	Settings.screen_size_changed.connect(apply_angles)
	player.opened.connect(func(_path: String) -> void:
		displayed_zoom = Settings.picture_zoom
		zoom_snap = true
		bound_serial = -1
		last_frame_time = -1.0
		player.shown_period_msec = 0.0
		player.shown_last_msec = 0
		refresh())
	_make_picker()
	probe = AlphaProbe.new()
	probe.player = player
	probe.detected.connect(player.apply_probe)
	add_child(probe)
	refresh()


func _process(delta: float) -> void:
	var media_dim := 1.0 - Settings.visualizer_background_dim if player.is_visualizer_overlay_active() else 1.0
	if media_dim != media_dim_value:
		media_dim_value = media_dim
		material.set_shader_parameter("visualizer_media_dim", media_dim)
	_update_zoom(delta)
	if Settings.projection != Settings.ProjectionMode.FLAT and is_instance_valid(view_origin):
		global_position = view_origin.global_position
	if player.is_image():
		visible = true
		if bound_image != player.image:
			_bind_image(player.image, player.image_info)
		return
	if bound_image != null:
		bound_image = null
		material.set_shader_parameter("picture_source", 0)
		refresh()
	var playback := player.playback
	var texture := player.get_video_texture()
	var has_video := playback != null and texture != null and texture.get_height() > 0
	var immersive_music := player.is_immersive_visualizer_active() and not player.is_visualizer_overlay_active()
	visible = has_video and not hidden_by_layer and not immersive_music
	if not has_video:
		return
	var state: Dictionary = playback.get_frame_state()
	var serial := int(state.get("serial", 0))
	refreshes_since_frame += 1
	if playback != bound_playback or serial != bound_serial:
		if playback == bound_playback and not player.paused:
			Log.note_cadence(refreshes_since_frame)
		refreshes_since_frame = 0
		_bind_frame(playback, int(state.get("set", 0)))
		_track_video_frame(playback, float(state.get("time_msec", 0.0)))
		bound_playback = playback
		bound_serial = serial
		material.set_shader_parameter("frame_seed", float(bound_serial % 997) * 0.618)
		if _geometry_key() != geometry_key:
			refresh()
	probe.tick(delta, bound_serial >= 0)


func _geometry_key() -> String:
	if Settings.projection != Settings.ProjectionMode.FLAT:
		return "sphere"
	return "flat %d %.5f %s %d" % [Settings.stereo, player.content_aspect(), Settings.screen_curve > 0.001, _flat_tiles()]


func _flat_tiles() -> int:
	return Settings.flat_image_tiles() if player.is_image() else 1


func refresh() -> void:
	var key := _geometry_key()
	if key != geometry_key or mesh == null:
		geometry_key = key
		if key == "sphere":
			mesh = _sphere_mesh()
		else:
			mesh = _flat_mesh(player.content_aspect())
	apply_angles()
	mesh.surface_set_material(0, material)
	material.render_priority = -16
	material.set_shader_parameter("projection", Settings.projection)
	material.set_shader_parameter("stereo_layout", Settings.stereo)
	material.set_shader_parameter("swap_eyes", eyes_swapped())
	material.set_shader_parameter("single_eye", Settings.single_eye)
	material.set_shader_parameter("fisheye_fov", Settings.fisheye_fov)
	material.set_shader_parameter("brightness", Settings.brightness)
	material.set_shader_parameter("picture_supersample", Settings.photo_supersampling)
	material.set_shader_parameter("sharpness", Settings.SHARPNESS_GAINS[clampi(Settings.sharpness_level, 0, Settings.SHARPNESS_GAINS.size() - 1)])
	material.set_shader_parameter("gamma", float(Settings.gamma))
	material.set_shader_parameter("saturation", float(Settings.saturation))
	material.set_shader_parameter("background_mode", Settings.background)
	material.set_shader_parameter("cut_color", Settings.chroma_key_color)
	material.set_shader_parameter("cut_enabled", Settings.cut_enabled and Settings.background == Settings.Background.CHROMA_KEY)
	material.set_shader_parameter("cut_invert", Settings.cut_invert)
	material.set_shader_parameter("cut_similarity", float(Settings.cut_similarity))
	material.set_shader_parameter("cut_feather", float(Settings.cut_feather))
	material.set_shader_parameter("edge_fade", 0.0 if flat_desktop or _flat_tiles() > 1 else float(Settings.edge_fade))
	material.set_shader_parameter("stereo_depth", float(Settings.stereo_depth))
	material.set_shader_parameter("stereo_vertical", float(Settings.stereo_vertical))
	material.set_shader_parameter("picture_zoom", displayed_zoom)
	material.set_shader_parameter("flat_repeat", _flat_tiles())
	material.set_shader_parameter("photo_pan", Vector2(Settings.photo_pan_x, Settings.photo_pan_y))
	material.set_shader_parameter("alpha_mask", Settings.AlphaMask.NONE if player.is_image() else Settings.alpha_mask)
	material.set_shader_parameter("mask_threshold", float(Settings.mask_threshold))
	material.set_shader_parameter("mask_trim", float(Settings.mask_trim))
	material.set_shader_parameter("mask_darken", float(Settings.mask_darken))
	material.set_shader_parameter("equirect_fov", float(Settings.equirect_fov))
	material.set_shader_parameter("eye_roll", float(Settings.eye_roll))
	material.set_shader_parameter("lens_k", Vector2(Settings.lens_k1, Settings.lens_k2))
	material.set_shader_parameter("crop", Settings.crop_rect())
	material.set_shader_parameter("content_rotation", player.content_rotation)
	material.set_shader_parameter("cube_padding", player.cube_padding)
	material.set_shader_parameter("deband", Settings.DEBAND_PARAMS[clampi(Settings.deband, 0, Settings.DEBAND_PARAMS.size() - 1)])
	material.set_shader_parameter("dither", Settings.dither)
	material.set_shader_parameter("menu_dim", menu_dim_value)


func _flat_mesh(aspect: float) -> QuadMesh:
	var quad := QuadMesh.new()
	if Settings.stereo == Settings.Stereo.SIDE_BY_SIDE:
		aspect *= 0.5
	elif Settings.stereo == Settings.Stereo.OVER_UNDER:
		aspect *= 2.0
	quad.size = Vector2(Settings.flat_screen_width(), Settings.flat_screen_width() / aspect) * float(_flat_tiles())
	if Settings.screen_curve > 0.001 and _flat_tiles() == 1:
		quad.subdivide_width = CURVE_SEGMENTS
	return quad


func _sphere_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = SPHERE_RADIUS
	sphere.height = SPHERE_RADIUS * 2.0
	sphere.radial_segments = SPHERE_SEGMENTS
	sphere.rings = SPHERE_RINGS
	return sphere


func set_menu_dim(amount: float) -> void:
	menu_dim_value = amount
	material.set_shader_parameter("menu_dim", amount)


func eyes_swapped() -> bool:
	return Settings.swap_eyes != auto_swapped


func update_auto_swap(head: Basis) -> void:
	var swapped := auto_swapped
	if not Settings.auto_swap_eyes or Settings.stereo == Settings.Stereo.MONO or Settings.projection not in AUTO_SWAP_PROJECTIONS:
		swapped = false
	else:
		var alignment := global_basis.orthonormalized().x.dot(head.orthonormalized().x)
		if alignment < -AUTO_SWAP_HYSTERESIS:
			swapped = true
		elif alignment > AUTO_SWAP_HYSTERESIS:
			swapped = false
	if swapped == auto_swapped:
		return
	auto_swapped = swapped
	Log.info("auto eye swap %s" % ("on" if swapped else "off"))
	material.set_shader_parameter("swap_eyes", eyes_swapped())


func set_view_yaw(yaw: float) -> void:
	if is_equal_approx(yaw, view_yaw):
		return
	view_yaw = yaw
	_place()


func _place() -> void:
	var rotation_basis := Basis(Vector3.UP, view_yaw) * Basis.from_euler(Vector3(deg_to_rad(Settings.angle_pitch), deg_to_rad(Settings.angle_yaw), deg_to_rad(Settings.angle_roll)))
	basis = rotation_basis
	position = rotation_basis * Vector3(0, 0, -Settings.SCREEN_DISTANCE) if Settings.projection == Settings.ProjectionMode.FLAT else (get_parent().to_local(view_origin.global_position) if is_instance_valid(view_origin) else Vector3.ZERO)


func apply_angles() -> void:
	_place()
	if Settings.projection == Settings.ProjectionMode.FLAT:
		var quad := mesh as QuadMesh
		var width := Settings.flat_screen_width() * float(_flat_tiles())
		if quad != null and quad.size.x > 0.0 and not is_equal_approx(quad.size.x, width):
			quad.size *= width / quad.size.x
		var bend := curve_inverse_radius()
		material.set_shader_parameter("flat_curve", bend)
		if quad != null and quad.size.x > 0.0:
			material.set_shader_parameter("flat_angles", Vector2(Settings.screen_size, Settings.screen_size * quad.size.y / quad.size.x))
		if quad != null:
			var depth := (1.0 - cos(minf(width * 0.5 * bend, PI))) / bend if bend > 0.0 else 0.0
			quad.custom_aabb = AABB(Vector3(-width * 0.5, -quad.size.y * 0.5, 0.0), Vector3(width, quad.size.y, maxf(depth, 0.01)))
	else:
		material.set_shader_parameter("flat_curve", 0.0)


func curve_inverse_radius() -> float:
	return Settings.screen_curve / Settings.SCREEN_DISTANCE if Settings.projection == Settings.ProjectionMode.FLAT and not flat_desktop and _flat_tiles() == 1 else 0.0


func _bind_frame(playback: FFmpegVideoStreamPlayback, current: int) -> void:
	var info: Dictionary = playback.get_frame_info()
	var rgb := int(info.get("format", -1)) == 0
	var chroma := playback.get_plane_texture(1, current)
	var picture: Texture2D = player.get_video_texture() if rgb else chroma
	if picture == null:
		return
	for target in [material, pick_material, probe.material] + glow_materials:
		target.set_shader_parameter("packed_rgb", rgb)
		if rgb:
			target.set_shader_parameter("plane_y", picture)
			target.set_shader_parameter("has_alpha", bool(info.get("has_alpha", false)))
			target.set_shader_parameter("sample_scale", 1.0)
			target.set_shader_parameter("full_range", true)
			target.set_shader_parameter("transfer_function", 0)
			target.set_shader_parameter("wide_gamut", false)
		else:
			for plane in PLANE_COUNT:
				target.set_shader_parameter(PLANE_PARAMS[plane], playback.get_plane_texture(plane, current))
			_apply_format(target, info, chroma)


func _bind_image(image: VPXPanorama, info: Dictionary) -> void:
	bound_image = image
	bound_playback = null
	bound_serial = -1
	var cube: bool = info["layout"] == VPXPanorama.LAYOUT_CUBE
	var luma: Dictionary = info["planes"][0]
	material.set_shader_parameter("picture_source", 2 if cube else 1)
	for plane in 3:
		material.set_shader_parameter((PICTURE_CUBE_PARAMS if cube else PICTURE_TILE_PARAMS)[plane], image.get_plane(plane))
	material.set_shader_parameter("tile_geometry", Vector4(luma["width"], luma["core"], luma["gutter"], luma["tile_width"]))
	material.set_shader_parameter("tile_count", int(info["tiles"]))
	material.set_shader_parameter("picture_size", Vector2(luma["width"], luma["height"]))
	material.set_shader_parameter("rgb_planes", bool(info["rgb"]))
	material.set_shader_parameter("color_matrix", 0)
	material.set_shader_parameter("full_range", true)
	material.set_shader_parameter("transfer_function", 0)
	material.set_shader_parameter("wide_gamut", false)
	refresh()


func _apply_format(target: ShaderMaterial, info: Dictionary, chroma: Texture2D) -> void:
	var height := int(info.get("height", 0))
	var space := int(info.get("color_space", 2))
	var transfer := int(info.get("color_transfer", 2))
	var primaries := int(info.get("color_primaries", 2))
	var hdr := transfer == TRC_PQ or transfer == TRC_HLG
	var matrix := 1
	match space:
		SPC_BT470BG, SPC_SMPTE170M, SPC_SMPTE240M:
			matrix = 0
		SPC_BT2020_NCL, SPC_BT2020_CL:
			matrix = 2
		SPC_BT709:
			matrix = 1
		_:
			matrix = 2 if hdr else (1 if height >= 720 else 0)
	var transfer_function := 0
	if transfer == TRC_PQ:
		transfer_function = 1
	elif transfer == TRC_HLG:
		transfer_function = 2
	target.set_shader_parameter("semiplanar", bool(info.get("semiplanar", false)))
	target.set_shader_parameter("chroma_in_alpha", RenderingServer.texture_get_format(chroma.get_rid()) == Image.FORMAT_LA8)
	target.set_shader_parameter("has_alpha", bool(info.get("has_alpha", false)))
	target.set_shader_parameter("sample_scale", float(info.get("sample_scale", 1.0)))
	target.set_shader_parameter("color_matrix", matrix)
	target.set_shader_parameter("full_range", int(info.get("color_range", 0)) == RANGE_JPEG)
	target.set_shader_parameter("transfer_function", transfer_function)
	target.set_shader_parameter("wide_gamut", primaries == PRI_BT2020 or hdr)
	target.set_shader_parameter("chroma_offset", _chroma_offset(info))


func _chroma_offset(info: Dictionary) -> Vector2:
	var width := maxi(int(info.get("width", 2)), 2)
	var height := maxi(int(info.get("height", 2)), 2)
	var chroma := Vector2(0.25 / float((width + 1) / 2), 0.25 / float((height + 1) / 2))
	match int(info.get("chroma_location", 0)):
		CHROMA_CENTER:
			return Vector2.ZERO
		CHROMA_TOPLEFT:
			return chroma
		CHROMA_TOP:
			return Vector2(0.0, chroma.y)
		CHROMA_BOTTOMLEFT:
			return Vector2(chroma.x, -chroma.y)
		CHROMA_BOTTOM:
			return Vector2(0.0, -chroma.y)
		_:
			return Vector2(chroma.x, 0.0)


func _track_video_frame(playback: FFmpegVideoStreamPlayback, frame_time: float) -> void:
	if last_seek_serial != Log.seek_serial:
		last_seek_serial = Log.seek_serial
		last_frame_time = -1.0
	if bound_playback == playback and bound_serial >= 0:
		Log.note_video_frame()
		player.note_shown_frame()
		var period := 1000.0 / maxf(player.playback_fps(), 1.0)
		if last_frame_time >= 0.0 and frame_time > last_frame_time + period * 1.5 and frame_time - last_frame_time < 1000.0:
			Log.video_drops += int(round((frame_time - last_frame_time) / period)) - 1
	last_frame_time = frame_time


func _make_picker() -> void:
	pick_material.shader = preload("res://shaders/pick.gdshader")
	pick_viewport = SubViewport.new()
	pick_viewport.size = Vector2i(2, 2)
	pick_viewport.disable_3d = true
	pick_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.material = pick_material
	pick_viewport.add_child(rect)
	add_child(pick_viewport)


func hit_from_ray(world_origin: Vector3, world_dir: Vector3) -> Dictionary:
	if mesh == null:
		return {"ok": false}
	var origin := to_local(world_origin)
	var tip := to_local(world_origin + world_dir.normalized() * 200.0)
	var direction := tip - origin
	var local := Vector3.ZERO
	var view_uv := Vector2.ZERO
	if Settings.projection == Settings.ProjectionMode.FLAT:
		var size := Vector2(Settings.flat_screen_width(), Settings.flat_screen_width() * 9.0 / 16.0)
		if mesh is QuadMesh:
			size = (mesh as QuadMesh).size
		var bend := curve_inverse_radius()
		if bend > 0.0:
			var radius := 1.0 / bend
			var flat_origin := Vector2(origin.x, origin.z - radius)
			var flat_direction := Vector2(direction.x, direction.z)
			var a := flat_direction.length_squared()
			if a < 1e-8:
				return {"ok": false}
			var b := flat_origin.dot(flat_direction)
			var disc := b * b - a * (flat_origin.length_squared() - radius * radius)
			if disc < 0.0:
				return {"ok": false}
			var t := (-b + sqrt(disc)) / a
			if t < 0.0 or t > 1.0:
				return {"ok": false}
			local = origin + direction * t
			var arc := atan2(local.x, radius - local.z) * radius
			view_uv = Vector2(arc / size.x + 0.5, (size.y * 0.5 - local.y) / size.y)
		else:
			if absf(direction.z) < 0.0001:
				return {"ok": false}
			var t := -origin.z / direction.z
			if t < 0.0 or t > 1.0:
				return {"ok": false}
			local = origin + direction * t
			view_uv = Vector2((local.x + size.x * 0.5) / size.x, (size.y * 0.5 - local.y) / size.y)
	else:
		var d := direction.normalized()
		var b := origin.dot(d)
		var disc := b * b - origin.dot(origin) + SPHERE_RADIUS * SPHERE_RADIUS
		if disc < 0.0:
			return {"ok": false}
		var t := -b + sqrt(disc)
		if t < 0.0:
			return {"ok": false}
		local = origin + d * t
		view_uv = _project_direction(player.content_rotation * zoom_direction(d))
	if view_uv.x < 0.0 or view_uv.x > 1.0 or view_uv.y < 0.0 or view_uv.y > 1.0:
		return {"ok": false}
	return {"ok": true, "point": to_global(local), "uv": _packed_uv(view_uv)}


func sample_color(packed_uv: Vector2) -> Color:
	if player.playback == null or pick_viewport == null or bound_serial < 0:
		return Color.BLACK
	pick_material.set_shader_parameter("sample_uv", packed_uv)
	pick_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := pick_viewport.get_texture().get_image()
	if image == null:
		return Color.BLACK
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image.get_pixel(0, 0)


func _project_direction(d: Vector3) -> Vector2:
	match Settings.projection:
		Settings.ProjectionMode.EQUIRECT_360:
			return _equirect(d)
		Settings.ProjectionMode.EQUIRECT_180:
			var e := _equirect(d)
			return Vector2(0.5 + (e.x - 0.5) * 360.0 / maxf(Settings.equirect_fov, 1.0), e.y)
		Settings.ProjectionMode.FISHEYE:
			var theta := acos(clampf(-d.z, -1.0, 1.0))
			var x := theta / maxf(deg_to_rad(Settings.fisheye_fov) * 0.5, 0.0001)
			var shaped := x * (1.0 + Settings.lens_k1 * x * x + Settings.lens_k2 * x * x * x * x)
			var r := 0.5 * shaped / maxf(1.0 + Settings.lens_k1 + Settings.lens_k2, 0.05)
			var phi := atan2(d.y, d.x)
			return Vector2(0.5 + r * cos(phi), 0.5 - r * sin(phi))
		Settings.ProjectionMode.EAC, Settings.ProjectionMode.CUBEMAP:
			return cube_uv(d, Settings.projection == Settings.ProjectionMode.EAC, player.cube_padding)
		_:
			return Vector2(0.5, 0.5)


static func cube_uv(d: Vector3, eac: bool, padding: float) -> Vector2:
	var a := d.abs()
	var face := 0
	if a.x >= a.y and a.x >= a.z:
		face = 0 if d.x > 0.0 else 1
	elif a.y >= a.z:
		face = 2 if d.y > 0.0 else 3
	else:
		face = 4 if d.z < 0.0 else 5
	var frames := EAC_FACES if eac else CUBE_FACES
	var entry: Array = frames[face]
	var n: Vector3 = entry[0]
	var depth := maxf(d.dot(n), 1e-5)
	var st := Vector2(d.dot(entry[1]), d.dot(entry[2])) / depth
	if eac:
		st = Vector2(atan(st.x), atan(st.y)) * (4.0 / PI)
	var local := (st * 0.5 + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	local = Vector2(padding, padding) + local * (1.0 - 2.0 * padding)
	return (entry[3] + local) / Vector2(3.0, 2.0)


func _equirect(d: Vector3) -> Vector2:
	return Vector2(0.5 + atan2(d.x, -d.z) / TAU, 0.5 - asin(clampf(d.y, -1.0, 1.0)) / PI)


func _packed_uv(uv: Vector2) -> Vector2:
	var right := eyes_swapped()
	var crop := Settings.crop_rect()
	var packed := Vector2(crop.x, crop.y) + uv * (Vector2.ONE - Vector2(crop.x, crop.y) - Vector2(crop.z, crop.w))
	uv = packed
	match Settings.stereo:
		Settings.Stereo.SIDE_BY_SIDE:
			packed = Vector2(uv.x * 0.5 + (0.5 if right else 0.0), uv.y)
		Settings.Stereo.OVER_UNDER:
			packed = Vector2(uv.x, uv.y * 0.5 + (0.5 if right else 0.0))
	if Settings.alpha_mask == Settings.AlphaMask.STACKED_BELOW:
		packed.y *= 0.5
	return packed


func _on_zoom_changed(snap: bool) -> void:
	if snap:
		displayed_zoom = Settings.picture_zoom
		material.set_shader_parameter("picture_zoom", displayed_zoom)


func _update_zoom(delta: float) -> void:
	if is_equal_approx(displayed_zoom, Settings.picture_zoom):
		return
	displayed_zoom = exp(lerpf(log(displayed_zoom), log(Settings.picture_zoom), 1.0 - exp(-delta * 24.0)))
	if absf(displayed_zoom - Settings.picture_zoom) < 0.0001:
		displayed_zoom = Settings.picture_zoom
	material.set_shader_parameter("picture_zoom", displayed_zoom)


func update_zoom_direction(head: Basis, delta := 0.0, stabilize := false) -> void:
	var direction := (global_basis.inverse() * -head.z).normalized()
	if stabilize and not zoom_snap and not is_equal_approx(displayed_zoom, 1.0):
		direction = _stabilized_zoom_direction(direction, delta)
	zoom_snap = false
	if zoom_forward.is_equal_approx(direction):
		return
	zoom_forward = direction
	material.set_shader_parameter("zoom_forward", zoom_forward)


func _stabilized_zoom_direction(gaze: Vector3, delta: float) -> Vector3:
	var angle := zoom_forward.angle_to(gaze)
	var hold := deg_to_rad(ZOOM_HOLD_DEGREES)
	var axis := zoom_forward.cross(gaze)
	if angle <= hold or axis.length_squared() < 1e-12:
		return zoom_forward
	var magnification := maxf(displayed_zoom, 1.0)
	var excess := angle - hold
	var ramp := minf(excess / deg_to_rad(ZOOM_RAMP_DEGREES), 1.0)
	var step := excess * ramp * (1.0 - exp(-delta * ZOOM_FOLLOW_RATE / magnification))
	return zoom_forward.rotated(axis.normalized(), step).normalized()


func zoom_direction(direction: Vector3) -> Vector3:
	var center := zoom_forward if Settings.projection in [Settings.ProjectionMode.EQUIRECT_360, Settings.ProjectionMode.EAC, Settings.ProjectionMode.CUBEMAP] else Vector3.FORWARD
	var cosine := clampf(direction.dot(center), -1.0, 1.0)
	var zoom := maxf(displayed_zoom, 0.01)
	var denominator := maxf(zoom * zoom * (1.0 + cosine) + 1.0 - cosine, 0.00001)
	return center * ((zoom * zoom * (1.0 + cosine) - 1.0 + cosine) / denominator) + (direction - center * cosine) * (2.0 * zoom / denominator)
