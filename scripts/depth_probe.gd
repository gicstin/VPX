class_name DepthProbe
extends Node

const COLUMNS := 16
const INTERVAL := 0.2
const D_MIN := -0.08
const D_MAX := 0.03
const MIN_COLUMNS := 2
const MIN_ROW_SHARE := 0.25
const STALE_AFTER := 1.5

var material := ShaderMaterial.new()
var viewport: SubViewport
var wanted := false
var disparity := 0.0
var valid := false
var busy := false
var elapsed := 0.0
var probed_serial := -1
var probed_at := 0.0


func _ready() -> void:
	material.shader = preload("res://shaders/depth_probe.gdshader")
	viewport = SubViewport.new()
	viewport.size = Vector2i(COLUMNS, 1)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)


func configure(swapped: bool) -> void:
	material.set_shader_parameter("stereo_layout", Settings.stereo)
	material.set_shader_parameter("swap_eyes", swapped)
	material.set_shader_parameter("crop", Settings.crop_rect())
	probed_serial = -1


func tick(delta: float, serial: int) -> void:
	elapsed += delta
	if not wanted:
		valid = false
		probed_serial = -1
		return
	if valid and elapsed - probed_at > STALE_AFTER:
		valid = false
	if busy or serial < 0 or serial == probed_serial or elapsed < probed_at + INTERVAL:
		return
	probed_serial = serial
	_run()


func _run() -> void:
	busy = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	AlphaProbe.read_pixels(viewport, _on_bytes)


func _on_bytes(bytes: PackedByteArray, swapped: bool) -> void:
	busy = false
	probed_at = elapsed
	if bytes.size() < COLUMNS * 4 or not wanted:
		return
	var found := PackedFloat32Array()
	for i in COLUMNS:
		if bytes[i * 4 + 1] / 255.0 >= MIN_ROW_SHARE:
			found.append(D_MIN + (D_MAX - D_MIN) * bytes[i * 4 + (2 if swapped else 0)] / 255.0)
	found.sort()
	valid = found.size() >= MIN_COLUMNS
	if valid:
		disparity = found[1]
