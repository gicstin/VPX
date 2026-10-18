class_name SpiritLevel
extends Control

const LEVEL_TOLERANCE := 0.5
const HEADING_MIN := 0.2
const LEVEL_COLOR := Color("8fd694")
const BUBBLE_RANGE := 15.0

var screen: Node3D
var camera: Camera3D
var angles := Vector3.ZERO
var roll_available := true


func _init() -> void:
	custom_minimum_size = Vector2(600, 156)
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_IGNORE


static func applicable(player: Node, flat: bool) -> bool:
	return player != null and player.has_picture() and (player.is_image() or not player._audio_only_playing()) and not (player.is_image() and flat)


static func heading(world: Basis) -> Vector3:
	var forward := -world.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() < HEADING_MIN:
		var up := world.y * -signf(forward.y)
		flat = Vector3(up.x, 0.0, up.z)
	return flat.normalized()


static func measure(world: Basis, gaze: Basis) -> Vector3:
	world = world.orthonormalized()
	var direction := heading(world)
	var looking := heading(gaze.orthonormalized())
	var centre := wrapf(atan2(direction.x, -direction.z) - atan2(looking.x, -looking.z), -PI, PI)
	var roll := atan2(world.x.y, world.y.y) if Vector2(world.x.y, world.y.y).length() > 0.01 else 0.0
	return Vector3(rad_to_deg(roll), rad_to_deg(asin(clampf(-world.z.y, -1.0, 1.0))), rad_to_deg(centre))


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(screen) or not is_instance_valid(camera):
		return
	angles = measure(screen.global_basis, camera.global_basis)
	roll_available = Vector2(screen.global_basis.x.y, screen.global_basis.y.y).length() > 0.01
	queue_redraw()


func _draw() -> void:
	draw_style_box(VpxTheme.flat(VpxTheme.OVERLAY, 18, 0, 0), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var level := roll_available and absf(angles.x) <= LEVEL_TOLERANCE and absf(angles.y) <= LEVEL_TOLERANCE
	draw_string(font, Vector2(22, 30), "SPIRIT LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, VpxTheme.MUTED)
	var status := "Level" if level else "Adjust tilt / pitch"
	var status_width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, Vector2(size.x - status_width - 22, 30), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LEVEL_COLOR if level else VpxTheme.TEXT)
	var width := (size.x - 44.0) / 3.0
	_draw_axis(Rect2(22, 48, width, size.y - 58), "Tilt", angles.x, roll_available)
	_draw_axis(Rect2(22 + width, 48, width, size.y - 58), "Pitch", angles.y)
	_draw_axis(Rect2(22 + width * 2, 48, width, size.y - 58), "Centre", angles.z)


func _draw_axis(area: Rect2, title: String, value: float, available := true) -> void:
	var font := get_theme_default_font()
	var centred := available and absf(value) <= LEVEL_TOLERANCE
	var color := LEVEL_COLOR if centred else VpxTheme.ACCENT
	var text := "—" if not available else ("0.0°" if absf(value) < 0.05 else "%+.1f°" % value)
	if title == "Centre":
		text = "Ahead" if centred else "%.1f° %s" % [absf(value), "→" if value > 0.0 else "←"]
	draw_string(font, area.position + Vector2(0, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, VpxTheme.MUTED)
	draw_string(font, area.position + Vector2(0, 50), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color if centred else VpxTheme.TEXT)
	var start := area.position + Vector2(10, 76)
	var end := start + Vector2(area.size.x - 40, 0)
	var middle := (start + end) * 0.5
	draw_line(start, end, VpxTheme.TRACK, 4.0, true)
	var zone := (end.x - start.x) * LEVEL_TOLERANCE / BUBBLE_RANGE * 0.5
	draw_style_box(VpxTheme.flat(Color(LEVEL_COLOR, 0.25), 4, 0, 0), Rect2(middle - Vector2(maxf(zone, 5), 10), Vector2(maxf(zone, 5) * 2, 20)))
	draw_line(middle - Vector2(0, 13), middle + Vector2(0, 13), VpxTheme.TEXT, 2.0, true)
	if available:
		var bubble := middle + Vector2(clampf(value / BUBBLE_RANGE, -1.0, 1.0) * (end.x - start.x) * 0.5, 0)
		draw_circle(bubble, 9.0, color, true, -1, true)
