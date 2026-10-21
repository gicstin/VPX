extends SceneTree

var checks := 0
var failures := 0
var views: Array[SubViewport] = []
var canvases: Array[Control] = []


class ReferenceCanvas extends Control:
	var wave := PackedFloat32Array()

	func _draw() -> void:
		var area := Rect2(16, 10, size.x - 32, size.y - 16)
		var middle := area.get_center().y
		var half := area.size.y * 0.5
		draw_line(Vector2(area.position.x, middle), Vector2(area.end.x, middle), Color(VpxTheme.ACCENT, 0.3), 1.0, true)
		if wave.size() < 2:
			return
		var points := PackedVector2Array()
		for i in wave.size():
			points.append(Vector2(area.position.x + float(i) * area.size.x / (wave.size() - 1), middle - wave[i] * half))
		var colors := _gradient(points, area, 1.0)
		for i in points.size() - 1:
			var shade := PackedColorArray([Color(colors[i], 0.4), Color(colors[i + 1], 0.4), Color(colors[i + 1], 0.0), Color(colors[i], 0.0)])
			draw_primitive(PackedVector2Array([points[i], points[i + 1], Vector2(points[i + 1].x, middle), Vector2(points[i].x, middle)]), shade, PackedVector2Array())
		draw_polyline_colors(points, _gradient(points, area, 0.14), 8.0, true)
		draw_polyline_colors(points, _gradient(points, area, 0.3), 4.0, true)
		draw_polyline_colors(points, colors, 2.0, true)


	func _gradient(points: PackedVector2Array, area: Rect2, alpha: float) -> PackedColorArray:
		var colors := PackedColorArray()
		for point in points:
			colors.append(Color(VpxTheme.ACCENT.lerp(VpxTheme.SPECTRUM_END, clampf((point.x - area.position.x) / area.size.x, 0.0, 1.0)), alpha))
		return colors


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: scope render timeout"); quit(2))
	var script: GDScript = load("res://scripts/music_visualizer.gd")
	for index in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640, 180)
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var canvas: Control = ReferenceCanvas.new() if index == 0 else script.SpectrumCanvas.new()
		if index == 1:
			canvas.embedded = true
			canvas.oscilloscope = true
		viewport.add_child(canvas)
		views.append(viewport)
		canvases.append(canvas)
	var accent := VpxTheme.ACCENT
	var end := VpxTheme.SPECTRUM_END
	for size in [Vector2i(640, 180), Vector2i(128, 128), Vector2i(800, 240)]:
		for count in [320, 189, 16, 2, 0]:
			var wave := PackedFloat32Array()
			for i in count:
				wave.append(sin(i * 0.13) * 0.7 + sin(i * 0.037) * 0.2)
			for i in 2:
				views[i].size = size
				canvases[i].size = size
				canvases[i].wave = wave
				canvases[i].queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var reference := views[0].get_texture().get_image()
			var actual := views[1].get_texture().get_image()
			var error := 0.0
			var maximum := 0.0
			var lit_alpha := 0.0
			for y in reference.get_height():
				for x in reference.get_width():
					var a := reference.get_pixel(x, y)
					var b := actual.get_pixel(x, y)
					var delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
					error += delta
					maximum = maxf(maximum, delta)
					lit_alpha += a.a
			var mean: float = error / (size.x * size.y * 4.0)
			print("RENDER scope %s samples=%d mean=%.8f worst=%.5f" % [size, count, mean, maximum])
			check(mean < 0.00005 and maximum < 0.03, "batched scope matches reference pixels")
			check(lit_alpha > 10.0, "scope render comparison contains visible output")
			VpxTheme.ACCENT = Color(0.9, 0.2, 0.4)
			VpxTheme.SPECTRUM_END = Color(0.2, 0.8, 0.3)
	VpxTheme.ACCENT = accent
	VpxTheme.SPECTRUM_END = end
	print("RESULT: scope_render_performance checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
