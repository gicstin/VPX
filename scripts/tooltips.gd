extends Node

const Overlay := preload("res://scripts/tooltip_overlay.gd")


func set_text(control: Control, value: String) -> void:
	control.set_meta("vpx_tooltip_text", value)
	control.tooltip_text = ""


func get_text(control: Control, position := Vector2.ZERO) -> String:
	if control.has_meta("vpx_tooltip_text"):
		return str(control.get_meta("vpx_tooltip_text"))
	return control.get_tooltip(position)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_node_added)
	_watch(get_tree().root)


func _watch(node: Node) -> void:
	_node_added(node)
	for child in node.get_children():
		_watch(child)


func _node_added(node: Node) -> void:
	if node is Viewport:
		_attach.call_deferred(node)


func _attach(viewport: Viewport) -> void:
	if not is_instance_valid(viewport) or not viewport.is_inside_tree() or viewport.has_meta("vpx_tooltips") or viewport.has_meta("vpx_text_size_exempt"):
		return
	viewport.set_meta("vpx_tooltips", true)
	var overlay := Overlay.new()
	overlay.name = "TooltipOverlay"
	viewport.add_child(overlay)
