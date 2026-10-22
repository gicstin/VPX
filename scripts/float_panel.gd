class_name FloatPanel
extends Node3D

const TEXTURE_DENSITY := 1000.0
const FADE_IN_RATE := 22.0
const FADE_OUT_RATE := 28.0
const FADE_SNAP := 0.004
const SLIDE := 0.025
const SUPERSAMPLE := 2.0
const START_SCALE := 0.96

static var frame := Basis.IDENTITY

var panel_size := Vector2(1.0, 0.15)
var texture_density := TEXTURE_DENSITY
var distance := 1.4
var drop := 0.32
var tilt := -15.0
var viewport: SubViewport
var content: Control
var quad: MeshInstance3D
var material: ShaderMaterial
var opacity := 0.0
var target_opacity := 0.0


func _ready() -> void:
	viewport = SubViewport.new()
	_size_viewport()
	viewport.size_2d_override_stretch = true
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	content = _build()
	content.theme = VpxTheme.build()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(content)
	quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = panel_size
	quad.mesh = mesh
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/ui_panel.gdshader")
	material.set_shader_parameter("panel_texture", viewport.get_texture())
	material.render_priority = 15
	quad.material_override = material
	add_child(quad)
	visible = false
	scale = Vector3.ONE * Settings.ui_size
	Settings.changed.connect(func() -> void: scale = Vector3.ONE * Settings.ui_size)


func resize(size: Vector2) -> void:
	panel_size = size
	_size_viewport()
	(quad.mesh as QuadMesh).size = size


func _size_viewport() -> void:
	viewport.size_2d_override = Vector2i(panel_size * texture_density)
	viewport.size = Vector2i(panel_size * texture_density * SUPERSAMPLE)


func _build() -> Control:
	return Control.new()


func present(camera: Camera3D) -> void:
	if opacity <= 0.0:
		place(camera)
		_apply_opacity()
	target_opacity = 1.0
	visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func dismiss() -> void:
	target_opacity = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	if opacity != target_opacity:
		var rate := FADE_IN_RATE if target_opacity > opacity else FADE_OUT_RATE
		opacity = lerpf(opacity, target_opacity, 1.0 - exp(-delta * rate))
		if absf(opacity - target_opacity) < FADE_SNAP:
			opacity = target_opacity
		_apply_opacity()
	if opacity <= 0.0 and target_opacity <= 0.0:
		visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _apply_opacity() -> void:
	material.set_shader_parameter("opacity", opacity)
	quad.position.y = -SLIDE * (1.0 - opacity)
	quad.scale = Vector3.ONE * lerpf(START_SCALE, 1.0, opacity)


func place_below(other: FloatPanel, gap := 0.02) -> void:
	global_transform = other.global_transform
	translate_object_local(Vector3(0, -(other.panel_size.y + panel_size.y) * 0.5 - gap, 0))


func place_above(other: FloatPanel, gap := 0.02) -> void:
	global_transform = other.global_transform
	translate_object_local(Vector3(0, (other.panel_size.y + panel_size.y) * 0.5 + gap, 0))


func place(camera: Camera3D) -> void:
	var forward := level_forward(camera)
	global_position = camera.global_position + forward * distance - frame.y * drop
	look_at(global_position + forward, frame.y)
	rotate_object_local(Vector3.RIGHT, deg_to_rad(tilt))


static func level_forward(camera: Node3D) -> Vector3:
	return level(-camera.global_basis.z)


static func level(direction: Vector3) -> Vector3:
	var flat := direction - frame.y * direction.dot(frame.y)
	if flat.length_squared() < 0.001:
		return -frame.z
	return flat.normalized()


static func card(color: Color, radius := 24, margin_h := 32, margin_v := 18) -> StyleBoxFlat:
	return VpxTheme.flat(Color(color, VpxTheme.OVERLAY_ALPHA), radius, margin_h, margin_v)
