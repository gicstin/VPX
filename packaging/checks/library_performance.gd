extends SceneTree

const PanoramaFiles := preload("res://scripts/panorama_files.gd")
const Grid := preload("res://scripts/virtual_grid.gd")

var checks := 0
var failures := 0
var measurements := {}


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func measure(name: String, action: Callable, iterations := 1) -> void:
	action.call()
	var samples: Array[float] = []
	for sample in 7:
		var started := Time.get_ticks_usec()
		for i in iterations:
			action.call()
		samples.append((Time.get_ticks_usec() - started) / (1000.0 * iterations))
	samples.sort()
	measurements[name] = {"median_ms": samples[3], "samples_ms": samples}
	print("BENCH %s median=%.4f ms" % [name, samples[3]])


func _run() -> void:
	create_timer(30).timeout.connect(func() -> void: printerr("FAIL: library performance timeout"); quit(2))
	_panorama()
	_face_parsing()
	var scanner: Node = load("res://scripts/library_scanner.gd").new(["mp4"])
	_sorting(scanner)
	await _grid()
	await _scanning(scanner, OS.get_cmdline_user_args()[0])
	scanner.free()
	var file := FileAccess.open(OS.get_cmdline_user_args()[1], FileAccess.WRITE)
	check(file != null, "benchmark report opens")
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}, "\t"))
	print("RESULT: library_performance checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _panorama() -> void:
	var names: Array[String] = []
	for i in 1000:
		for face in PanoramaFiles.CUBE_ORDER:
			names.append("scene_%04d_%s.jpg" % [i, face])
		if i % 2 == 0:
			names.append("scene_%04d_360.jpg" % i)
	names.append_array(["incomplete_front.jpg", "incomplete_left.jpg", "holiday.jpg", "movie.mp4", "Ελληνικά_front.jpg"])
	var shown := PanoramaFiles.visible_images("", names)
	check(shown.size() == 1005, "complete cubes collapse, incomplete sets survive")
	check("scene_0000_front.jpg" not in shown and "scene_0000_360.jpg" in shown, "equirect replaces complete cube")
	check("scene_0001_front.jpg" in shown and "scene_0001_right.jpg" not in shown, "cube retains front face")
	measure("panorama_6505", func() -> void: PanoramaFiles.visible_images("", names))
	for extension in ["jpg", "JPG", "png", "webp", "jpeg"]:
		for suffix in ["", "_c", "-HDR", ".01"]:
			for prefix in ["set", "set.with.dots", "Ελληνικά", "a_b-c"]:
				var cube: Array[String] = []
				for face in ["front", "back", "left", "right", "top", "bottom"]:
					cube.append("%s_%s%s.%s" % [prefix, face, suffix, extension])
				check(PanoramaFiles.visible_images("", cube) == [cube[0]], "cube aliases, suffixes and extensions")
				cube.append(prefix + "_360." + extension)
				check(PanoramaFiles.visible_images("", cube) == [cube[-1]], "plain panorama suppresses matching cube")
	var letters: Array[String] = ["set_f.jpg", "set_b.jpg", "set_l.jpg", "set_r.jpg", "set_u.jpg", "set_d.jpg"]
	check(PanoramaFiles.visible_images("", letters) == [letters[0]], "single-letter face aliases")
	letters.append("set_f.jpg")
	check(PanoramaFiles.visible_images("", letters) == [letters[0], letters[0]], "duplicate fronts preserve input order")
	letters.append("set_front.mp4")
	check(PanoramaFiles.visible_images("", letters).size() == 3, "non-image face names do not suppress a cube")
	letters.append("set_overview.mp4")
	check(PanoramaFiles.visible_images("", letters) == ["set_front.mp4", "set_overview.mp4"], "plain media prefix retains existing suppression")
	var mixed: Array[String] = ["set_front.jpg", "set_back.jpg", "set_left.jpg", "set_right.jpg", "set_up.jpg", "set_down.png"]
	check(PanoramaFiles.visible_images("", mixed) == mixed, "mixed extensions cannot complete a cube")
	var plain: Array[String] = []
	for i in 10000:
		plain.append("movie_%05d.mp4" % i)
	measure("videos_10000", func() -> void: PanoramaFiles.visible_images("", plain))
	var copy := PanoramaFiles.visible_images("", plain)
	check(copy == plain, "plain video order preserved")
	copy[0] = "replacement"
	check(plain[0] == "movie_00000.mp4", "filter returns an independent array")
	check(PanoramaFiles.visible_images("", []).is_empty(), "empty panorama input")


func _face_reference(path: String) -> Dictionary:
	var base := path.get_file().get_basename()
	for regex in [PanoramaFiles.face_regex, PanoramaFiles.letter_regex]:
		var found: RegExMatch = regex.search(base)
		if found != null:
			return {
				"prefix": found.get_string("prefix"),
				"face": PanoramaFiles.FACE_NAMES[found.get_string("face").to_lower()],
				"suffix": found.get_string("suffix") if regex == PanoramaFiles.face_regex else "",
				"extension": path.get_extension().to_lower(),
			}
	return {}


func _face_parsing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2021021
	var paths: Array[String] = ["", "front.jpg", "_front.jpg", "set_front_front.jpg", "set_f_f.jpg", "set_front_12345.jpg", "set_Front.01.JPG", "folder.with.dots/set_back.webp", "folder_front.jpg/plain.png"]
	var faces: Array = PanoramaFiles.FACE_NAMES.keys() + ["frontier", "BACK", "FRONT", "Bottom", "U", ""]
	for i in 5000:
		var prefix: String = ["set", "set_front", "a.b.c", "Ελληνικά", "日本語", "", "_", "a_b-c"][rng.randi_range(0, 7)]
		var separator: String = ["_", "-", ".", " ", "", "/"][rng.randi_range(0, 5)]
		var suffix: String = ["", "_1", "-HDR", ".01", "_12345", " suffix", "_α", "_a_b"][rng.randi_range(0, 7)]
		paths.append("%s%s%s%s.%s" % [prefix, separator, faces[rng.randi_range(0, faces.size() - 1)], suffix, ["jpg", "JPG", "png", "mp4", ""][rng.randi_range(0, 4)]])
	for path in paths:
		check(PanoramaFiles.face_of(path) == _face_reference(path), "face parsing preserves aliases, paths, Unicode and rejected suffixes: " + path)
	measure("face_reference_5009", func() -> void:
		for path in paths:
			_face_reference(path))
	measure("face_optimized_5009", func() -> void:
		for path in paths:
			PanoramaFiles.face_of(path))


func _sorting(scanner: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var paths: Array[String] = []
	var keys := {}
	for i in 10000:
		var path := "/media/collection_%03d/Clip %d.MP4" % [i % 31, rng.randi_range(0, 99999)]
		paths.append(path)
		keys[path] = i % 17
	for count in [0, 1, 16, 400, 10000]:
		for mode in [[false, false], [false, true], [true, false], [true, true]]:
			var input: Array[String] = paths.slice(0, count)
			_compare_sort(scanner, input, keys, mode[0], mode[1])
			if count == 10000 and not (mode[0] and mode[1]):
				measure("sort_10000_%s_%s" % [mode[0], mode[1]], func() -> void:
					var copy := input.duplicate()
					scanner._sort(copy, keys, mode[0], mode[1]))
	var singleton: Array[String] = ["only.mp4"]
	scanner._sort(singleton, {}, true, false)
	check(singleton == ["only.mp4"], "single-item sort needs no comparison keys")
	for sample in 100:
		var input: Array[String] = []
		var values := {}
		for i in rng.randi_range(0, 500):
			var path := "/%d/%s%d.mp4" % [rng.randi_range(0, 20), "CLIP" if rng.randf() > 0.5 else "clip", rng.randi_range(0, 50)]
			input.append(path)
			values[path] = rng.randi_range(-5, 5)
		for mode in [[false, false], [false, true], [true, false], [true, true]]:
			_compare_sort(scanner, input, values, mode[0], mode[1])


func _compare_sort(scanner: Node, input: Array[String], keys: Dictionary, by_key: bool, by_file: bool) -> void:
	var expected := input.duplicate()
	expected.sort_custom(func(a: String, b: String) -> bool:
		if by_key:
			return a.naturalnocasecmp_to(b) < 0 if keys[a] == keys[b] else keys[a] > keys[b]
		return a.get_file().naturalnocasecmp_to(b.get_file()) < 0 if by_file else a.naturalnocasecmp_to(b) < 0)
	var actual := input.duplicate()
	scanner._sort(actual, keys, by_key, by_file)
	check(actual == expected, "sort preserves natural order, ties and duplicates")


func _grid() -> void:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(1200, 720)
	root.add_child(scroll)
	var grid := Grid.new()
	scroll.add_child(grid)
	grid.size = Vector2(1200, 720)
	var builds: Array[String] = []
	var budget := {"slow": false}
	grid.setup(scroll, 4, 12, 12, func(_width: float) -> float: return 180.0,
		func(key: String, parent: Control) -> Control:
			if budget["slow"]:
				OS.delay_usec(1600)
			builds.append(key)
			var control := Button.new()
			parent.add_child(control)
			return control,
		func(_key: String, _control: Control) -> void: pass)
	await process_frame
	scroll.size = Vector2(1200, 720)
	grid.size.x = 1200
	var items := PackedStringArray()
	for i in 10000:
		items.append("item_%d" % i)
	grid.set_items(items)
	_settle(grid)
	check(grid.built.size() <= 24 and not grid.pending(), "grid only builds visible rows")
	var count := builds.size()
	measure("grid_idle_sync", func() -> void: grid.sync(), 10000)
	check(builds.size() == count, "idle sync never rebuilds cards")
	var focused := grid.control_at(0)
	focused.grab_focus()
	grid.position.y = -2000
	_settle(grid)
	grid.sync()
	check(grid.built.has(0), "offscreen focused card survives repeated sync")
	focused.release_focus()
	grid.sync()
	check(not grid.built.has(0), "focus release drops cached offscreen card")
	grid.control_at(0)
	grid.sync()
	check(not grid.built.has(0), "explicit offscreen construction cannot bypass cleanup")
	var visible := grid._window().x
	var previous_id := grid.control_at(visible).get_instance_id()
	grid.rebuild(items[visible])
	_settle(grid)
	check(grid.control_at(visible).get_instance_id() != previous_id, "visible rebuild invalidates completed window")
	items = items.duplicate()
	items[visible] = "replacement"
	grid.set_items(items)
	_settle(grid)
	check(builds.has("replacement"), "same-sized item replacement rebuilds card")
	grid.hide()
	count = builds.size()
	grid.set_items(PackedStringArray(["only"]))
	grid.sync()
	check(builds.size() == count, "hidden grid does no work after replacement")
	grid.show()
	grid.position.y = 0
	_settle(grid)
	check(grid.built.size() == 1 and grid.built.has(0), "shrinking list releases old cards")
	grid.set_items(items)
	grid.columns = 2
	grid.size.x = 600
	grid._relayout()
	_settle(grid)
	check(grid.control_at(1).position.x > 0.0 and grid.control_at(2).position.x == 0.0, "column resize places cards correctly")
	scroll.size.y = 1100
	_settle(grid)
	scroll.size.y = 360
	_settle(grid)
	check(grid.built.size() == grid._window().y - grid._window().x, "viewport growth and shrink release extra cards")
	grid.clear()
	grid.sync()
	check(grid.built.is_empty() and grid.is_empty() and not grid.pending(), "empty grid clears cached state")
	check(grid.control_at(-1) == null and grid.control_at(0) == null, "invalid grid indices stay empty")
	budget["slow"] = true
	grid.set_items(items)
	grid.sync()
	check(grid.pending(), "build budget defers remaining cards")
	_settle(grid)
	check(not grid.pending(), "partial builds continue until visible window completes")
	scroll.free()


func _settle(grid: Control) -> void:
	for i in 100:
		grid.sync()
		if not grid.pending():
			grid.sync()
			return
	check(false, "grid finishes pending work")


func _scanning(scanner: Node, folder: String) -> void:
	var cover: Dictionary = scanner.folder_cover(folder)
	check(cover.get("cover", "").ends_with("clip_00000.mp4") and cover.get("count", 0) == 10000 and not cover.get("single", true), "large folder cover and count remain correct")
	measure("folder_cover_10000", func() -> void: scanner.folder_cover(folder))
	root.add_child(scanner)
	for sort in 3:
		var started := Time.get_ticks_usec()
		var serial: int = scanner.folder(folder, sort, PackedStringArray())
		while true:
			var result: Dictionary = await scanner.finished
			if result["serial"] != serial:
				continue
			if result["done"]:
				check(result["files"].size() == 10000 and result["folders"].size() == 32, "threaded large-folder listing completes")
				measurements["scanner_sort_%d" % sort] = {"total_ms": (Time.get_ticks_usec() - started) / 1000.0}
				break
	var obsolete: int = scanner.folder(folder, 0, PackedStringArray())
	var current: int = scanner.folder(folder.path_join("folder_007"), 0, PackedStringArray())
	while true:
		var result: Dictionary = await scanner.finished
		check(result["serial"] != obsolete, "superseded listing cannot escape")
		if result["serial"] == current and result["done"]:
			check(result["files"].size() == 1, "replacement listing completes")
			break
	await process_frame
	root.remove_child(scanner)
