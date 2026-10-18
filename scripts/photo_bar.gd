extends CanvasLayer

const MusicControls := preload("res://scripts/music_controls.gd")
const MARGIN := 20.0

var main: Node3D
var player: VPXPlayer:
	set(value):
		player = value
		root.player = value
var ui: Control:
	set(value):
		ui = value
		root.ui = value
var camera: Camera3D
var root: MusicControls


func _init() -> void:
	root = MusicControls.new()
	root.visible = false
	root.collapsed_changed.connect(_layout)


func _ready() -> void:
	layer = 12
	add_child(root)


func _process(_delta: float) -> void:
	var show_bar: bool = player != null and player.playback != null and (player.is_image() or player.is_music_mode()) and main != null and main.desktop_mode and not main.panel.visible
	root.visible = show_bar
	if not show_bar:
		root.seeking = false
		return
	root.refresh()
	_layout()
	if root.seeking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		root.seeking = false


func _layout() -> void:
	if main == null or main.desktop_view == null:
		return
	var window := get_viewport().get_visible_rect().size
	var scale: float = main.desktop_view.ui_scale(window)
	var margin := MARGIN * scale
	root.size = root.wanted_size()
	var available_height := window.y - margin * 2.0
	if main.desktop_view.osd_rect.visible:
		available_height = minf(available_height, main.desktop_view.osd_rect.position.y - margin * 2.0)
	root.scale = Vector2.ONE * maxf(0.001, minf(scale, minf((window.x - margin * 2.0) / root.size.x, available_height / root.size.y)))
	root.position = Vector2(margin, margin).round()
