extends SceneTree

const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const WIDTH := 64
const HEIGHT := 32
const MID_GREY := 0.18
const HOT := 400.0

var failures := 0
var checks := 0
var directory := ""


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func _run() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(2))
	directory = OS.get_user_data_dir().path_join("hdr_check")
	DirAccess.make_dir_recursive_absolute(directory)
	var source := _source_image()
	var files := {
		"float.exr": _save_exr(source, Image.FORMAT_RGBF),
		"half.exr": _save_exr(source, Image.FORMAT_RGBH),
		"rle.hdr": _save_radiance(source, "rle.hdr", true, false),
		"flat.hdr": _save_radiance(source, "flat.hdr", false, false),
		"flipped.hdr": _save_radiance(source, "flipped.hdr", true, true),
	}
	check(PanoramaFiles.is_image("a.EXR") and PanoramaFiles.is_image("b.hdr") and "exr" in PanoramaFiles.HDR_EXTENSIONS, "EXR and HDR count as photos")
	for name: String in files:
		var path: String = files[name]
		var info: Dictionary = VPXPanorama.probe(path)
		check(int(info.get("width", 0)) == WIDTH and int(info.get("height", 0)) == HEIGHT and bool(info.get("hdr", false)), "%s header probe" % name)
		var preview := directory.path_join(name.get_basename() + "-preview.jpg")
		var error := VPXPanorama.write_hdr_preview(path, preview, 32, 1.0)
		var image := Image.load_from_file(preview) if error.is_empty() else null
		check(image != null and image.get_size() == Vector2i(32, 16), "%s preview decodes %s" % [name, error])
		if image == null:
			continue
		var grey := image.get_pixel(4, 12).r8
		var white := image.get_pixel(28, 12)
		var black := image.get_pixel(0, 0).r8
		check(absi(grey - 109) <= 6, "%s mid grey tone-maps to ~109 (got %d)" % [name, grey])
		check(white.r8 >= 250 and white.g8 >= 250 and white.b8 >= 250, "%s highlights roll off to white" % name)
		check(black <= 4, "%s negative and NaN samples clamp to black (got %d)" % [name, black])
		var red := image.get_pixel(28, 2)
		check(red.r8 > 150 and red.g8 < 60, "%s keeps channel order (top right is red)" % name)
	var dark := directory.path_join("dark.jpg")
	VPXPanorama.write_hdr_preview(files["half.exr"], dark, 32, 0.25)
	check(Image.load_from_file(dark).get_pixel(4, 12).r8 < 70, "exposure darkens the preview")
	await _check_panorama(files["half.exr"])
	await _check_panorama(files["rle.hdr"])
	_check_badges(files["half.exr"], files["rle.hdr"])
	_check_corrupt(files["float.exr"], "truncated.exr")
	_check_corrupt(files["rle.hdr"], "truncated.hdr")
	print("%d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func _source_image() -> Image:
	var image := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBF)
	for y in HEIGHT:
		for x in WIDTH:
			var color := Color(MID_GREY, MID_GREY, MID_GREY)
			if y < HEIGHT / 2:
				color = Color(-1.0, -1.0, -1.0) if x < WIDTH / 2 else Color(1.0, 0.02, 0.02)
			elif x >= WIDTH / 2:
				color = Color(HOT, HOT, HOT)
			image.set_pixel(x, y, color)
	image.set_pixel(1, 1, Color(NAN, NAN, NAN))
	return image


func _save_exr(source: Image, format: int) -> String:
	var image := source.duplicate() as Image
	image.convert(format)
	var path := directory.path_join("float.exr" if format == Image.FORMAT_RGBF else "half.exr")
	check(image.save_exr(path) == OK, "write %s" % path.get_file())
	return path


func _save_radiance(source: Image, name: String, rle: bool, flip: bool) -> String:
	var bytes := PackedByteArray()
	bytes.append_array(("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n%sY %d +X %d\n" % ["+" if flip else "-", HEIGHT, WIDTH]).to_ascii_buffer())
	for row in HEIGHT:
		var y := HEIGHT - 1 - row if flip else row
		var pixels := PackedByteArray()
		for x in WIDTH:
			pixels.append_array(_rgbe(source.get_pixel(x, y)))
		if not rle:
			bytes.append_array(pixels)
			continue
		bytes.append_array(PackedByteArray([2, 2, WIDTH >> 8, WIDTH & 0xff]))
		for channel in 4:
			var x := 0
			while x < WIDTH:
				var count := mini(128, WIDTH - x)
				var value := pixels[x * 4 + channel]
				var run := 1
				while run < 127 and x + run < WIDTH and pixels[(x + run) * 4 + channel] == value:
					run += 1
				if run >= 4:
					bytes.append_array(PackedByteArray([128 + run, value]))
					x += run
					continue
				bytes.append(count)
				for i in count:
					bytes.append(pixels[(x + i) * 4 + channel])
				x += count
	var path := directory.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path


func _rgbe(color: Color) -> PackedByteArray:
	var r := maxf(color.r, 0.0) if not is_nan(color.r) else 0.0
	var g := maxf(color.g, 0.0) if not is_nan(color.g) else 0.0
	var b := maxf(color.b, 0.0) if not is_nan(color.b) else 0.0
	var peak := maxf(r, maxf(g, b))
	if peak < 1e-32:
		return PackedByteArray([0, 0, 0, 0])
	var exponent := int(floor(log(peak) / log(2.0))) + 1
	var scale := 256.0 / pow(2.0, exponent)
	return PackedByteArray([mini(int(r * scale), 255), mini(int(g * scale), 255), mini(int(b * scale), 255), exponent + 128])


func _check_panorama(path: String) -> void:
	var loader := VPXPanorama.new()
	check(loader.start(PackedStringArray([path]), VPXPanorama.LAYOUT_TILED, true) == OK, "%s panorama load starts" % path.get_file())
	var status := VPXPanorama.STATUS_LOADING
	for i in 600:
		status = loader.poll()
		if status != VPXPanorama.STATUS_LOADING:
			break
		await process_frame
	var info := loader.get_info()
	check(status == VPXPanorama.STATUS_READY and bool(info["hdr"]) and bool(info["rgb"]) and int(info["width"]) == WIDTH, "%s loads as half-float RGB panorama %s" % [path.get_file(), loader.get_error()])
	check(loader.get_plane(0) != null and loader.get_plane(2) != null, "%s planes exist" % path.get_file())


func _check_corrupt(source: String, name: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(source)
	var path := directory.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes.slice(0, bytes.size() / 2))
	file.close()
	var error := VPXPanorama.write_hdr_preview(path, directory.path_join(name + ".jpg"), 32, 1.0)
	check(not error.is_empty(), "%s fails cleanly: %s" % [name, error])


func _check_badges(exr: String, hdr: String) -> void:
	var MediaCard := load("res://scripts/media_card.gd")
	var jpg := directory.path_join("plain.jpg")
	Image.create(64, 32, false, Image.FORMAT_RGB8).save_jpg(jpg)
	var expected := {exr: "EXR", hdr: "HDR", jpg: ""}
	for layout in [MediaCard.Layout.CARD, MediaCard.Layout.ROW]:
		for path: String in expected:
			var card: Button = MediaCard.new()
			root.add_child(card)
			card.setup(path, false, layout, func() -> bool: return true)
			card.refresh()
			var shown := ""
			if layout == MediaCard.Layout.CARD:
				shown = card.duration_label.text if card.duration_badge.visible else ""
			else:
				shown = card.side_label.text
			check(shown == expected[path], "%s %s badge shows \"%s\" (got \"%s\")" % ["card" if layout == MediaCard.Layout.CARD else "row", path.get_extension(), expected[path], shown])
			card.free()

