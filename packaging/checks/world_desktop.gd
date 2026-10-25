extends SceneTree

const Synth := preload("res://packaging/checks/music_synth.gd")

var checks := 0
var failures := 0
var settings: Node
var main: Node
var captures := ""


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func track(path: String, left: float, right: float) -> void:
	var synth := Synth.new(126.0, 24)
	synth.four_on_floor(0, 24)
	synth.offbeat_hats(0, 24)
	synth.backbeat(8, 24, 0.7)
	synth.pad(0, 24, [57, 60, 64], 0.12)
	synth.bass(8, 24, 33, 0.4)
	synth.normalise(0.7)
	synth.save_wav(path, left, right)


func lit_fraction(image: Image, region: Rect2i) -> float:
	var lit := 0
	var count := 0
	for y in range(region.position.y, region.end.y, 4):
		for x in range(region.position.x, region.end.x, 4):
			var c := image.get_pixel(x, y)
			lit += int(maxf(c.r, maxf(c.g, c.b)) > 0.05)
			count += 1
	return float(lit) / maxi(1, count)


func brightness(image: Image, region: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(region.position.y, region.end.y, 3):
		for x in range(region.position.x, region.end.x, 3):
			var c := image.get_pixel(x, y)
			total += c.r + c.g + c.b
			count += 1
	return total / maxi(1, count)


func capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(captures.path_join(label + ".png"))
	return image


func open_track(path: String) -> bool:
	var opened: bool = await main.player.open(ProjectSettings.globalize_path(path))
	for frame in 10:
		await process_frame
	return opened


func wait_for_map(seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if main.resonance_field.timeline.map != null and main.resonance_field.timeline.active:
			return true
		await process_frame
		waited += 1.0 / 60.0
	return false


func run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	captures = OS.get_environment("VPX_WORLD_CAPTURES")
	if captures.is_empty():
		captures = OS.get_user_data_dir().path_join("world-captures")
	DirAccess.make_dir_recursive_absolute(captures)
	root.size = Vector2i(1280, 720)
	settings = root.get_node("Settings")
	settings.set_process(false)
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = true
	settings.immersive_music_visualizer = true
	settings.visualizer_overlay = false
	settings.visualizer_auto_change = false
	settings.visualizer_preset = settings.VISUALIZER_PRESETS.find("Valley of Sources")
	settings.visualizer_quality = 3
	var centre := OS.get_user_data_dir().path_join("world_centre.wav")
	var left := OS.get_user_data_dir().path_join("world_left.wav")
	track(centre, 1.0, 1.0)
	track(left, 1.0, 0.0)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await open_track(centre), "music track opens in desktop mode")
	check(main.desktop_mode, "running in desktop mode")
	var field = main.resonance_field
	var started := Time.get_ticks_msec()
	var mapped := await wait_for_map(12.0)
	check(field.active and field.is_world_scene(), "world scene is active for music")
	check(mapped, "whole-track map loads while playing (%d ms)" % (Time.get_ticks_msec() - started))
	check(main.camera.fov > 30.0 and main.camera.fov < 120.0, "desktop camera uses the immersive field of view (%.1f)" % main.camera.fov)
	var beats_before: int = field.beat_count
	var position_before: float = main.player.stream_position
	var frame_times := PackedFloat32Array()
	for frame in 240:
		var tick := Time.get_ticks_usec()
		await process_frame
		frame_times.append((Time.get_ticks_usec() - tick) / 1000.0)
	var elapsed: float = main.player.stream_position - position_before
	var expected := elapsed * 126.0 / 60.0
	check(absf((field.beat_count - beats_before) - expected) <= 1.5, "beats follow the music in desktop mode (%d for %.1f expected)" % [field.beat_count - beats_before, expected])
	frame_times.sort()
	var median := frame_times[frame_times.size() / 2]
	check(median < 20.0, "desktop frame time median %.1f ms" % median)
	var view := await capture("desktop_centre")
	var w := view.get_width()
	var h := view.get_height()
	check(lit_fraction(view, Rect2i(0, 0, w, h)) > 0.05, "desktop world renders (lit %.3f)" % lit_fraction(view, Rect2i(0, 0, w, h)))
	check(lit_fraction(view, Rect2i(0, int(h * 0.75), w, int(h * 0.25))) > 0.02, "desktop view shows the ground")
	check(await open_track(left), "hard-left track opens")
	for frame in 150:
		await process_frame
	var panned := await capture("desktop_left")
	var left_side := brightness(panned, Rect2i(0, 0, w / 2, int(h * 0.7)))
	var right_side := brightness(panned, Rect2i(w / 2, 0, w / 2, int(h * 0.7)))
	check(left_side > right_side * 1.1, "hard-left music lights the left of the desktop view (L %.3f R %.3f)" % [left_side, right_side])
	for world in ["Sound Cathedral", "Deep Current"]:
		settings.apply("visualizer_preset", settings.VISUALIZER_PRESETS.find(world))
		for frame in 60:
			await process_frame
		var image := await capture("desktop_" + world.to_snake_case())
		check(lit_fraction(image, Rect2i(0, 0, w, h)) > 0.05, "%s renders in desktop mode" % world)
	print("WORLD_DESKTOP checks=%d failures=%d" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
