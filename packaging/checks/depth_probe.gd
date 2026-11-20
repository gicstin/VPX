extends SceneTree

const EYE_WIDTH := 1024
const EYE_HEIGHT := 512

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:
		failures += 1


func _noise(seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var small := Image.create(96, 48, false, Image.FORMAT_R8)
	for y in 48:
		for x in 96:
			small.set_pixel(x, y, Color.from_hsv(0.0, 0.0, rng.randf()))
	small.resize(EYE_WIDTH, EYE_HEIGHT, Image.INTERPOLATE_BILINEAR)
	return small


func _stereo(shift_pixels: int, flat := false) -> ImageTexture:
	var left := _noise(7)
	if flat:
		left.fill(Color(0.4, 0.4, 0.4))
	var right := Image.create(EYE_WIDTH, EYE_HEIGHT, false, Image.FORMAT_R8)
	for y in EYE_HEIGHT:
		for x in EYE_WIDTH:
			right.set_pixel(x, y, left.get_pixel(clampi(x - shift_pixels, 0, EYE_WIDTH - 1), y))
	var packed := Image.create(EYE_WIDTH * 2, EYE_HEIGHT, false, Image.FORMAT_R8)
	packed.blit_rect(left, Rect2i(0, 0, EYE_WIDTH, EYE_HEIGHT), Vector2i.ZERO)
	packed.blit_rect(right, Rect2i(0, 0, EYE_WIDTH, EYE_HEIGHT), Vector2i(EYE_WIDTH, 0))
	packed.generate_mipmaps()
	return ImageTexture.create_from_image(packed)


func _measure(probe: Node, texture: Texture2D, swapped := false) -> Array:
	probe.material.set_shader_parameter("plane_y", texture)
	probe.material.set_shader_parameter("packed_rgb", false)
	probe.material.set_shader_parameter("sample_scale", 1.0)
	probe.material.set_shader_parameter("stereo_layout", Settings.Stereo.SIDE_BY_SIDE)
	probe.material.set_shader_parameter("swap_eyes", swapped)
	probe.material.set_shader_parameter("crop", Vector4.ZERO)
	probe.valid = false
	probe.probed_serial = -1
	probe.probed_at = -10.0
	probe.tick(0.5, 1)
	while probe.busy:
		await process_frame
	return [probe.valid, probe.disparity]


func _run() -> void:
	var subtitle_view: GDScript = load("res://scripts/subtitle_view.gd")
	var probe: Node = load("res://scripts/depth_probe.gd").new()
	probe.wanted = true
	root.add_child(probe)
	await process_frame
	await process_frame
	for shift in [-31, -12, 0, 8]:
		var result: Array = await _measure(probe, _stereo(shift))
		var expected := float(shift) / EYE_WIDTH
		check(result[0] and absf(result[1] - expected) < 0.004, "disparity %d px detected (got %s %.4f, want %.4f)" % [shift, result[0], result[1], expected])
	var swapped: Array = await _measure(probe, _stereo(-31), true)
	check(swapped[0] and absf(swapped[1] - 31.0 / EYE_WIDTH) < 0.004, "swapped eyes flip sign (got %.4f)" % swapped[1])
	var blank: Array = await _measure(probe, _stereo(0, true))
	check(not blank[0], "textureless picture reports no depth")
	check(is_equal_approx(subtitle_view.scene_lift(0.01, 3.0), 0.0), "behind screen needs no lift")
	var lift: float = subtitle_view.scene_lift(-0.03, 3.0)
	check(absf(lift - 3.0 * 0.03 / 0.093) < 0.001, "pop-out lift matches vergence depth (%.3f)" % lift)
	quit(1 if failures > 0 else 0)
