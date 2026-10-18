extends MeshInstance3D

const ROOM_SIZE := Vector3(22.0, 8.0, 26.0)
const EYE_HEIGHT := 1.2
const FORWARD_SHIFT := 5.0
const GLOW_CELLS := 3.0

var screen: MeshInstance3D
var player: VPXPlayer
var anchor: Node3D
var resonance: ResonanceField
var room_material := ShaderMaterial.new()


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = ROOM_SIZE
	mesh = box
	room_material.shader = preload("res://shaders/cinema_room.gdshader")
	room_material.render_priority = -32
	material_override = room_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.glow_materials.append(room_material)
	visible = false


func _process(_delta: float) -> void:
	visible = (resonance == null or not resonance.active) and Settings.background == Settings.Background.CINEMA and Settings.projection == Settings.ProjectionMode.FLAT
	if not visible:
		return
	var forward := -anchor.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var floor_y := anchor.global_position.y - EYE_HEIGHT
	global_basis = Basis.looking_at(forward, Vector3.UP)
	global_position = anchor.global_position + forward * FORWARD_SHIFT
	global_position.y = floor_y + ROOM_SIZE.y * 0.5
	var quad := screen.mesh as QuadMesh
	var half := quad.size * 0.5 if quad != null else Vector2(1.7, 1.0)
	room_material.set_shader_parameter("screen_center", screen.global_position)
	room_material.set_shader_parameter("screen_right", screen.global_basis.x.normalized())
	room_material.set_shader_parameter("screen_up", screen.global_basis.y.normalized())
	room_material.set_shader_parameter("screen_half", half)
	room_material.set_shader_parameter("stereo_layout", Settings.stereo)
	room_material.set_shader_parameter("room_floor", floor_y)
	room_material.set_shader_parameter("brightness", float(Settings.brightness) * (0.35 if player.paused else 1.0))
	var texture := player.get_video_texture() if not player.is_image() else null
	var glowing := screen.visible and texture != null and texture.get_width() > 0
	room_material.set_shader_parameter("video_glow", glowing)
	room_material.set_shader_parameter("fallback_glow", Color(0.3, 0.3, 0.34) if screen.visible else Color(0.05, 0.05, 0.06))
	if glowing:
		var eye_width := texture.get_width() * (0.5 if Settings.stereo == Settings.Stereo.SIDE_BY_SIDE else 1.0)
		room_material.set_shader_parameter("glow_lod", maxf(log(eye_width / GLOW_CELLS) / log(2.0), 0.0))
