extends Node3D

const REST_BELOW_GAZE := 11.0
const PITCH_LIMIT := 40.0
const REVEAL_RATE := 20.0
const REVEAL_SCALE := 0.97

@export var panel_size := Vector2(1.9425, 1.2)
@export var viewport: SubViewport

var base_opacity := 1.0
var reveal := 1.0
var closing := false

@onready var quad: MeshInstance3D = $Quad
@onready var shape: CollisionShape3D = $Area/Shape


func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = panel_size
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/ui_panel.gdshader")
	material.set_shader_parameter("panel_texture", viewport.get_texture())
	quad.material_override = material
	material.render_priority = 16
	var box := BoxShape3D.new()
	box.size = Vector3(panel_size.x, panel_size.y, 0.002)
	shape.shape = box


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
		if visible and is_node_ready():
			reveal = 0.0
			_apply_reveal()


func _process(delta: float) -> void:
	if not visible:
		return
	var target := 0.0 if closing else 1.0
	if is_equal_approx(reveal, target):
		return
	reveal = lerpf(reveal, target, 1.0 - exp(-delta * REVEAL_RATE))
	if absf(reveal - target) < 0.01:
		reveal = target
	_apply_reveal()
	if closing and reveal <= 0.0:
		closing = false
		visible = false


func open() -> void:
	closing = false
	visible = true


func close() -> void:
	if visible:
		closing = true


func is_open() -> bool:
	return visible and not closing


func _apply_reveal() -> void:
	(quad.material_override as ShaderMaterial).set_shader_parameter("opacity", base_opacity * reveal)
	quad.scale = Vector3.ONE * lerpf(REVEAL_SCALE, 1.0, reveal)


func place_in_front(camera: Camera3D, distance: float, follow_view := false) -> void:
	var gaze := (-camera.global_basis.z).normalized()
	var forward := gaze
	if not follow_view:
		var level := FloatPanel.level_forward(camera)
		var gaze_pitch := rad_to_deg(asin(clampf(gaze.y, -1.0, 1.0)))
		var pitch := clampf(gaze_pitch - REST_BELOW_GAZE, -PITCH_LIMIT, PITCH_LIMIT)
		var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z)
		if right.length_squared() < 0.001:
			right = Vector3.RIGHT
		forward = level.rotated(right.normalized(), deg_to_rad(pitch))
	global_position = camera.global_position + forward * distance
	# QuadMesh front is +Z. Point that at the camera so the panel cannot face away.
	var up := camera.global_basis.y if follow_view else FloatPanel.frame.y
	look_at(camera.global_position, up, true)


func set_opacity(opacity: float) -> void:
	base_opacity = opacity
	_apply_reveal()
