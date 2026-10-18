extends Control

const RADIUS := 9.0
const HIDE_AFTER := 0.25

var pointer := Vector2.ZERO
var last_motion := -10.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer = event.position
		last_motion = Time.get_ticks_msec() / 1000.0
		queue_redraw()


func _process(_delta: float) -> void:
	var shown := Time.get_ticks_msec() / 1000.0 - last_motion < HIDE_AFTER
	if shown != visible:
		visible = shown


func _draw() -> void:
	draw_circle(pointer, RADIUS + 3.0, VpxTheme.SCRIM)
	draw_circle(pointer, RADIUS, VpxTheme.TEXT)
	draw_circle(pointer, RADIUS * 0.4, VpxTheme.ACCENT)
