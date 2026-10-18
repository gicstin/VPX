class_name AlphaProbe
extends Node

signal detected(mode: int)

const COLUMNS := 4
const FIRST_DELAY := 0.5
const FAST_INTERVAL := 1.0
const FAST_UNTIL := 20.0
const SLOW_INTERVAL := 5.0
const GIVE_UP := 120.0
const CONFIRMATIONS := 3
const MIN_MASK := 0.02
const MAX_MASK := 0.6
const MAX_OTHER := 0.02
const MIN_OVERLAP := 0.6
const RGBA8_FORMATS := [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB]
const BGRA8_FORMATS := [RenderingDevice.DATA_FORMAT_B8G8R8A8_UNORM, RenderingDevice.DATA_FORMAT_B8G8R8A8_SRGB]

var player: VPXPlayer
var material := ShaderMaterial.new()
var viewport: SubViewport
var elapsed := 0.0
var next_probe := FIRST_DELAY
var busy := false
var streak := 0
var streak_mode := Settings.AlphaMask.NONE
var probes := 0


func _ready() -> void:
	material.shader = preload("res://shaders/alpha_probe.gdshader")
	viewport = SubViewport.new()
	viewport.size = Vector2i(COLUMNS, 1)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	player.opened.connect(func(_path: String) -> void: restart())


func restart() -> void:
	elapsed = 0.0
	next_probe = FIRST_DELAY
	streak = 0
	streak_mode = Settings.AlphaMask.NONE
	probes = 0


func tick(delta: float, frame_bound: bool) -> void:
	if not player.probe_wanted or busy or not frame_bound or player.paused:
		return
	elapsed += delta
	if elapsed < next_probe:
		return
	if elapsed > GIVE_UP:
		player.probe_wanted = false
		Log.info("alpha probe: no packed mask found in %d probes" % probes)
		return
	next_probe = elapsed + (FAST_INTERVAL if elapsed < FAST_UNTIL else SLOW_INTERVAL)
	_run()


func _run() -> void:
	busy = true
	var serial := player.open_serial
	probes += 1
	material.set_shader_parameter("jitter", Vector2(randf() - 0.5, randf() - 0.5))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if serial != player.open_serial:
		busy = false
		return
	var rd := RenderingServer.get_rendering_device()
	var rd_texture := RenderingServer.texture_get_rd_texture(viewport.get_texture().get_rid()) if rd != null else RID()
	if rd_texture.is_valid():
		var format := rd.texture_get_format(rd_texture).format
		var swapped: bool = format in BGRA8_FORMATS
		if format in RGBA8_FORMATS or swapped:
			if rd.texture_get_data_async(rd_texture, 0, _on_bytes.bind(swapped, serial)) == OK:
				return
	var image := viewport.get_texture().get_image()
	if image == null:
		busy = false
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_on_bytes(image.get_data(), false, serial)


func _on_bytes(bytes: PackedByteArray, swapped: bool, serial: int) -> void:
	busy = false
	if serial != player.open_serial or bytes.size() < COLUMNS * 4 or not player.probe_wanted:
		return
	var columns: Array[Color] = []
	for i in COLUMNS:
		var r := bytes[i * 4 + (2 if swapped else 0)] / 255.0
		var g := bytes[i * 4 + 1] / 255.0
		var b := bytes[i * 4 + (0 if swapped else 2)] / 255.0
		var a := bytes[i * 4 + 3] / 255.0
		columns.append(Color(r, g, b, a))
	var mode := _judge(columns)
	if probes == 1 or mode != Settings.AlphaMask.NONE:
		Log.info("alpha probe %d: left %s right %s overlap %s -> %d" % [probes, _fmt(columns[0]), _fmt(columns[1]), _fmt(columns[2]), mode])
	if mode == Settings.AlphaMask.NONE or mode != streak_mode:
		streak = 0
		streak_mode = mode
	if mode == Settings.AlphaMask.NONE:
		return
	streak += 1
	if streak >= CONFIRMATIONS:
		detected.emit(mode)


func _judge(columns: Array[Color]) -> int:
	var left := columns[0]
	var right := columns[1]
	var overlap := columns[2]
	var aspect := player.aspect_ratio()
	if aspect < 1.8 or aspect > 2.2:
		return Settings.AlphaMask.NONE
	if left.b > MAX_OTHER or right.b > MAX_OTHER:
		return Settings.AlphaMask.NONE
	if left.r < MIN_MASK or right.r < MIN_MASK or left.r > MAX_MASK or right.r > MAX_MASK:
		return Settings.AlphaMask.NONE
	if overlap.r < MIN_OVERLAP:
		return Settings.AlphaMask.NONE
	return Settings.AlphaMask.PACKED_CORNERS


func _fmt(c: Color) -> String:
	return "(%.3f %.3f %.3f %.2f)" % [c.r, c.g, c.b, c.a]
