extends FloatPanel

const MusicControls := preload("res://scripts/music_controls.gd")
const DENSITY := 1150.0

var player: VPXPlayer
var ui: Control
var menu: Node3D
var camera: Camera3D
var anchor: Node3D
var view: MusicControls
var shown := false
var placement := Transform3D.IDENTITY
var placed_by_user := false
var grab_offset := Transform3D.IDENTITY
var grab_controller: XRController3D


func _init() -> void:
	texture_density = DENSITY
	panel_size = Vector2(MusicControls.WIDTH, 300.0) / DENSITY
	distance = 1.3
	drop = 0.5
	tilt = -20.0


func _build() -> Control:
	view = MusicControls.new()
	view.player = player
	view.ui = ui
	return view


func interactive() -> bool:
	return visible and target_opacity > 0.0


func _process(delta: float) -> void:
	var wanted: bool = player.playback != null and (player.is_image() or player.is_music_mode()) and not menu.visible
	if wanted != shown:
		shown = wanted
		view.seeking = false
		if shown:
			present(camera)
		else:
			dismiss()
			grab_controller = null
	view.grabbed = grab_controller != null
	super._process(delta)
	if not visible:
		return
	view.refresh()
	var wanted_size := view.wanted_size() / texture_density
	if not wanted_size.is_equal_approx(panel_size):
		resize(wanted_size)
	if grab_controller != null:
		_follow_grab()


func place(target: Camera3D) -> void:
	if placed_by_user and anchor != null:
		global_transform = anchor.global_transform * placement
		return
	super.place(target)


func begin_grab(controller: XRController3D) -> void:
	grab_controller = controller
	grab_offset = (controller.aim_transform() as Transform3D).affine_inverse() * global_transform


func end_grab() -> void:
	if grab_controller == null:
		return
	grab_controller = null
	if anchor != null:
		placement = anchor.global_transform.affine_inverse() * global_transform
		placed_by_user = true


func reset_placement() -> void:
	placed_by_user = false
	if visible:
		place(camera)


func _follow_grab() -> void:
	var target: Transform3D = grab_controller.aim_transform() * grab_offset
	global_position = target.origin
	var away := global_position - camera.global_position
	if away.length_squared() > 0.0001:
		look_at(global_position + away, frame.y)
