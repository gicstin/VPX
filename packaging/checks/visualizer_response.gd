extends SceneTree

const Stimulus := preload("res://packaging/checks/music_stimulus.gd")
const BASELINE_PATH := "res://packaging/checks/visualizer_baseline.json"
const FPS := 60.0
const SIZE := Vector2i(320, 180)
const STEP := 4
const TILES := 3
const LIMITS := {
	"latency_ms": 50.0,
	"beat_contrast": 0.05,
	"entrainment": 0.25,
	"audio_gain": 0.25,
	"pitch_rise": 0.02,
	"pitch_distinct": 0.004,
	"pan_shift": 0.02,
	"loudness_ratio": 1.15,
	"clip_fraction": 0.03,
	"build_rise": 1.05,
	"drop_impact": 1.1,
	"flash_rate": 3.0,
	"red_flash_rate": 3.0,
	"evolution": 0.0015,
	"coherence": 0.05,
	"rest_luma": 0.08,
}
const HIGHER_BETTER := ["beat_contrast", "entrainment", "audio_gain", "pitch_rise", "pitch_distinct", "pan_shift", "loudness_ratio", "build_rise", "drop_impact", "evolution"]

var failures := 0
var checks := 0
var warnings := 0
var settings: Node
var field: Node
var camera: Camera3D
var music := Stimulus.new()
var linear := PackedFloat32Array()
var time := 0.0
var shots := ""
var mapping_start := 0


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, label: String, gated := true) -> void:
	if not gated:
		if not ok:
			warnings += 1
			print("WARN: ", label)
		return
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func argument(name: String, fallback := "") -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback


func mute_everything() -> void:
	for bus in AudioServer.bus_count:
		AudioServer.set_bus_mute(bus, true)
		AudioServer.set_bus_volume_db(bus, -80.0)
	check(AudioServer.is_bus_mute(0), "master output muted for testing")


func trace(label: String) -> void:
	if "--trace" in OS.get_cmdline_user_args():
		var a = field.affect
		print("TRACE %s t=%.2f beats=%d bass=%.2f fast=%.2f slow=%.2f valley=%.2f tension=%.2f release=%.2f arousal=%.2f warmth=%.2f groove=%.2f period=%.3f" % [label, time, field.beat_count, field.bass, a.fast, a.slow, a.valley, a.tension, a.release, a.arousal, a.warmth, a.groove, a.period])


func step(build: Callable, mono := false) -> Dictionary:
	var dt := 1.0 / FPS
	build.call(time)
	var sound := music.frame(dt, mono)
	field.feed(sound["spectrum"], sound["features"])
	var wave: PackedFloat32Array = music.waveform(time, sound["spectrum"])
	field.feed_waveform(wave)
	field.feed_scope(wave)
	field.clock += dt
	field.beat_age = minf(4.0, field.beat_age + dt)
	field.preset_elapsed += dt
	field._process(dt)
	await process_frame
	RenderingServer.force_draw()
	var sample := measure(root.get_texture().get_image())
	sample["time"] = time
	if int(round(time * FPS)) % 15 == 0:
		trace("step")
	time += dt
	return sample


func idle_step() -> Dictionary:
	var dt := 1.0 / FPS
	field.silence()
	field.clock += dt
	field.beat_age = minf(4.0, field.beat_age + dt)
	field._process(dt)
	await process_frame
	RenderingServer.force_draw()
	var sample := measure(root.get_texture().get_image())
	sample["time"] = time
	time += dt
	return sample


func segment(seconds: float, build: Callable, mono := false) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for i in int(round(seconds * FPS)):
		frames.append(await step(build, mono))
	return frames


func measure(image: Image) -> Dictionary:
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var width := image.get_width()
	var height := image.get_height()
	var lumas := PackedFloat32Array()
	var tiles := PackedFloat32Array()
	var reds := PackedFloat32Array()
	tiles.resize(TILES * TILES)
	reds.resize(TILES * TILES)
	var tile_counts := PackedInt32Array()
	tile_counts.resize(TILES * TILES)
	var total := 0.0
	var clipped := 0
	var count := 0
	var stride := maxi(STEP, width / 80)
	for y in range(0, height, stride):
		for x in range(0, width, stride):
			var offset := (y * width + x) * 4
			var r := linear[data[offset]]
			var g := linear[data[offset + 1]]
			var b := linear[data[offset + 2]]
			var luma := 0.2126 * r + 0.7152 * g + 0.0722 * b
			lumas.append(luma)
			total += luma
			if data[offset] >= 250 or data[offset + 1] >= 250 or data[offset + 2] >= 250:
				clipped += 1
			var tile := mini(TILES - 1, x * TILES / width) + mini(TILES - 1, y * TILES / height) * TILES
			tiles[tile] += luma
			var sum := data[offset] + data[offset + 1] + data[offset + 2]
			if sum > 0 and float(data[offset]) / sum >= 0.8:
				reds[tile] += r
			tile_counts[tile] += 1
			count += 1
	for tile in tiles.size():
		tiles[tile] /= maxi(1, tile_counts[tile])
		reds[tile] /= maxi(1, tile_counts[tile])
	return {"luma": total / count, "lumas": lumas, "tiles": tiles, "reds": reds, "clip": float(clipped) / count, "columns": ceili(float(width) / stride), "rows": ceili(float(height) / stride)}


func mean_luma(frames: Array[Dictionary], from := 0.0, to := 1.0) -> float:
	var start := int(frames.size() * from)
	var finish := maxi(start + 1, int(frames.size() * to))
	var total := 0.0
	for i in range(start, finish):
		total += float(frames[i]["luma"])
	return total / (finish - start)


func average_image(frames: Array[Dictionary], from := 0.5, to := 1.0) -> PackedFloat32Array:
	var start := int(frames.size() * from)
	var finish := maxi(start + 1, int(frames.size() * to))
	var result := PackedFloat32Array()
	result.resize(frames[0]["lumas"].size())
	for i in range(start, finish):
		var lumas: PackedFloat32Array = frames[i]["lumas"]
		for j in lumas.size():
			result[j] += lumas[j] / (finish - start)
	return result


func difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var total := 0.0
	for i in a.size():
		total += absf(a[i] - b[i])
	return total / a.size()


func centroid(image: PackedFloat32Array, rest: PackedFloat32Array, columns: int, rows: int) -> Vector2:
	var weighted := Vector2.ZERO
	var total := 0.0
	for i in image.size():
		var gain := maxf(0.0, image[i] - rest[i])
		weighted += Vector2(float(i % columns) / (columns - 1), float(i / columns) / (rows - 1)) * gain
		total += gain
	return weighted / total if total > 0.000001 else Vector2(0.5, 0.5)


func flash_rate(frames: Array[Dictionary], key: String) -> float:
	var worst := 0.0
	for tile in TILES * TILES:
		var transitions: Array[float] = []
		var first: float = frames[0][key][tile]
		var low := first
		var high := first
		var anchor := first
		var state := 0
		for frame in frames:
			var value: float = frame[key][tile]
			var t: float = frame["time"]
			if state == 0:
				low = minf(low, value)
				high = maxf(high, value)
				if value - low >= 0.1 and low < 0.8:
					transitions.append(t)
					state = 1
					anchor = value
				elif high - value >= 0.1 and value < 0.8:
					transitions.append(t)
					state = -1
					anchor = value
			elif state == 1:
				if value > anchor:
					anchor = value
				elif anchor - value >= 0.1 and value < 0.8:
					transitions.append(t)
					state = -1
					anchor = value
			else:
				if value < anchor:
					anchor = value
				elif value - anchor >= 0.1 and anchor < 0.8:
					transitions.append(t)
					state = 1
					anchor = value
		for i in transitions.size():
			var within := 0
			for j in range(i, transitions.size()):
				if transitions[j] - transitions[i] < 1.0:
					within += 1
			worst = maxf(worst, floor(within / 2.0))
	return worst


func beat_metrics(frames: Array[Dictionary], kicks: Array[float]) -> Dictionary:
	var latencies: Array[float] = []
	var contrasts: Array[float] = []
	var envelope := PackedFloat32Array()
	var lumas := PackedFloat32Array()
	for frame in frames:
		var t: float = frame["time"]
		var e := 0.0
		for hit in kicks:
			if t >= hit:
				e = maxf(e, exp(-(t - hit) / 0.11))
		envelope.append(e)
		lumas.append(frame["luma"])
	for hit in kicks:
		var before := INF
		var peak := -INF
		var peak_time := 0.0
		var trough := INF
		var window: Array[Dictionary] = []
		for frame in frames:
			var dt: float = float(frame["time"]) - hit
			if dt >= -0.05 and dt < 0.0:
				before = minf(before, frame["luma"])
			if dt >= 0.0 and dt <= 0.2:
				window.append(frame)
				if frame["luma"] > peak:
					peak = frame["luma"]
					peak_time = dt
			if dt >= 0.3 and dt <= 0.45:
				trough = minf(trough, frame["luma"])
		if window.is_empty() or before == INF or trough == INF:
			continue
		var base := minf(before, float(window[0]["luma"]))
		var half := base + (peak - base) * 0.5
		var rise := peak_time
		for frame in window:
			if frame["luma"] >= half:
				rise = float(frame["time"]) - hit
				break
		latencies.append(rise * 1000.0)
		contrasts.append((peak - trough) / maxf(0.0001, peak))
	latencies.sort()
	contrasts.sort()
	return {
		"latency_ms": latencies[latencies.size() / 2] if not latencies.is_empty() else 999.0,
		"beat_contrast": contrasts[contrasts.size() / 2] if not contrasts.is_empty() else 0.0,
		"entrainment": pearson(detrend(envelope), detrend(lumas)),
	}


func detrend(series: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var radius := int(FPS * 0.25)
	for i in series.size():
		var total := 0.0
		var count := 0
		for j in range(maxi(0, i - radius), mini(series.size(), i + radius + 1)):
			total += series[j]
			count += 1
		result.append(series[i] - total / count)
	return result


func pearson(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var mean_a := 0.0
	var mean_b := 0.0
	for i in a.size():
		mean_a += a[i] / a.size()
		mean_b += b[i] / b.size()
	var top := 0.0
	var left := 0.0
	var right := 0.0
	for i in a.size():
		top += (a[i] - mean_a) * (b[i] - mean_b)
		left += (a[i] - mean_a) * (a[i] - mean_a)
		right += (b[i] - mean_b) * (b[i] - mean_b)
	return top / sqrt(left * right) if left * right > 0.0 else 0.0


func coherence(frames: Array[Dictionary]) -> float:
	var total := 0.0
	for i in range(1, frames.size()):
		total += difference(frames[i]["lumas"], frames[i - 1]["lumas"])
	return total / maxi(1, frames.size() - 1)


func audition(index: int) -> Dictionary:
	var name: String = settings.VISUALIZER_PRESETS[index]
	settings.apply("visualizer_preset", index)
	field.reset()
	time = 0.0
	var metrics := {}
	var rest_frames: Array[Dictionary] = []
	for i in 90:
		rest_frames.append(await idle_step())
	var rest := average_image(rest_frames)
	metrics["rest_luma"] = mean_luma(rest_frames, 0.5)
	var columns: int = rest_frames[0]["columns"]
	var rows: int = rest_frames[0]["rows"]

	music.clear()
	var origin := time
	music.bpm = 120.0
	var groove := await segment(10.0, func(t: float) -> void: music.groove(t - origin))
	var hits: Array[float] = []
	for hit in music.kicks:
		if hit + origin > origin + 1.0:
			hits.append(hit + origin)
	var beat := beat_metrics(groove, hits)
	metrics.merge(beat)
	metrics["audio_gain"] = (mean_luma(groove, 0.25) - metrics["rest_luma"]) / maxf(0.0005, metrics["rest_luma"])
	metrics["coherence"] = coherence(groove)
	var phrase := int(round(16.0 * 60.0 / music.bpm * FPS))
	var evolution := 0.0
	var compared := 0
	for offset in range(int(FPS), groove.size() - phrase, 6):
		evolution += difference(groove[offset]["lumas"], groove[offset + phrase]["lumas"])
		compared += 1
	metrics["evolution"] = evolution / maxi(1, compared)
	if not shots.is_empty():
		root.get_texture().get_image().save_png(shots.path_join("%02d-groove.png" % index))

	field.silence()
	for i in 30:
		await idle_step()
	var low := await segment(1.5, func(_t: float) -> void: music.add(Stimulus.band_of(70.0), 2.5, 0.5))
	for i in 30:
		await idle_step()
	var high := await segment(1.5, func(_t: float) -> void: music.add(Stimulus.band_of(7000.0), 2.5, 0.5))
	var low_image := average_image(low)
	var high_image := average_image(high)
	metrics["pitch_rise"] = centroid(low_image, rest, columns, rows).y - centroid(high_image, rest, columns, rows).y
	metrics["pitch_distinct"] = difference(low_image, high_image)

	for i in 30:
		await idle_step()
	var left := await segment(1.5, func(_t: float) -> void: music.add(Stimulus.band_of(800.0), 9.0, 0.45, -1.0))
	for i in 30:
		await idle_step()
	var right := await segment(1.5, func(_t: float) -> void: music.add(Stimulus.band_of(800.0), 9.0, 0.45, 1.0))
	metrics["pan_shift"] = centroid(average_image(right), rest, columns, rows).x - centroid(average_image(left), rest, columns, rows).x

	var levels: Array[float] = []
	var loudest: Array[Dictionary] = []
	for amplitude in [0.04, 0.16, 0.6]:
		var bed := await segment(1.2, func(t: float) -> void:
			for band in range(2, 46, 4):
				music.add(band, 3.0, amplitude * (1.0 + 0.1 * sin(t * 3.0 + band)), sin(band * 0.7) * 0.5))
		levels.append(mean_luma(bed, 0.55))
		loudest = bed
	metrics["loudness_ratio"] = (levels[2] - metrics["rest_luma"]) / maxf(0.0005, levels[0] - metrics["rest_luma"]) if levels[0] > metrics["rest_luma"] else levels[2] / maxf(0.0005, levels[0])
	metrics["monotonic"] = 1.0 if levels[0] < levels[1] and levels[1] < levels[2] else 0.0
	var clip := 0.0
	for frame in loudest:
		clip = maxf(clip, frame["clip"])

	field.silence()
	for i in 30:
		await idle_step()
	music.clear()
	origin = time
	var build := await segment(4.0, func(t: float) -> void:
		var progress := (t - origin) / 4.0
		music.hats(t - origin, 0.08 + progress * 0.25, 2.0 + floor(progress * 3.0) * 2.0)
		music.add(Stimulus.band_of(600.0 * pow(12.0, progress)), 2.0, 0.06 + progress * 0.3)
		music.pad(t - origin, 0.08 + progress * 0.1))
	var drop_origin := time
	var drop := await segment(2.0, func(t: float) -> void: music.groove(t - drop_origin, 1.15))
	metrics["build_rise"] = mean_luma(build, 0.85) / maxf(0.0005, mean_luma(build, 0.0, 0.15))
	var build_peak := 0.0
	for frame in build.slice(int(build.size() * 0.85)):
		build_peak = maxf(build_peak, frame["luma"])
	var drop_peak := 0.0
	for frame in drop.slice(0, int(0.6 * FPS)):
		drop_peak = maxf(drop_peak, frame["luma"])
	metrics["drop_impact"] = drop_peak / maxf(0.0005, build_peak)
	for frame in drop:
		clip = maxf(clip, frame["clip"])
	metrics["clip_fraction"] = clip
	if not shots.is_empty():
		root.get_texture().get_image().save_png(shots.path_join("%02d-drop.png" % index))

	music.clear()
	music.bpm = 180.0
	origin = time
	var strobe := await segment(4.0, func(t: float) -> void:
		music.kick(t - origin, 0.0, 1.0)
		music.hats(t - origin, 0.35, 4.0)
		music.snare(t - origin, 0.5)
		music.bass(t - origin, 0.5))
	var everything: Array[Dictionary] = []
	everything.append_array(groove)
	everything.append_array(build)
	everything.append_array(drop)
	everything.append_array(strobe)
	metrics["flash_rate"] = flash_rate(everything, "tiles")
	metrics["red_flash_rate"] = flash_rate(everything, "reds")
	var rid := root.get_viewport_rid()
	metrics["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	field.silence()
	for key in metrics:
		metrics[key] = snappedf(float(metrics[key]), 0.0001)
	print("METRICS %d %s %s" % [index, name, JSON.stringify(metrics)])
	return metrics


func benchmark(index: int) -> void:
	settings.apply("visualizer_preset", index)
	field.reset()
	var gpu: Array[float] = []
	var rid := root.get_viewport_rid()
	for frame in 240:
		var dt := 1.0 / FPS
		music.groove(time)
		var sound := music.frame(dt)
		field.feed(sound["spectrum"], sound["features"])
		field.clock += dt
		field.beat_age += dt
		field._process(dt)
		await process_frame
		RenderingServer.force_draw()
		if frame >= 60:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		time += dt
	gpu.sort()
	var vertices := 0
	for layer in field.layers:
		var mesh: Mesh = layer.multimesh.mesh
		vertices += mesh.surface_get_array_len(0) * layer.multimesh.visible_instance_count
	var previous := 304 * 514 + 5200 * 6
	print("BENCHMARK %s size=%s vertices=%d reduction=%.1f%% gpu_median=%.3fms gpu_p95=%.3fms" % [settings.VISUALIZER_PRESETS[index], root.size, vertices, 100.0 * (1.0 - float(vertices) / previous), gpu[gpu.size() / 2], gpu[int(gpu.size() * 0.95)]])
	check(vertices < previous / 2, "%s cuts vertex work by over half" % settings.VISUALIZER_PRESETS[index])
	check(gpu[int(gpu.size() * 0.95)] < 11.1, "%s GPU time fits 90 Hz desktop budget" % settings.VISUALIZER_PRESETS[index])


func judge(index: int, metrics: Dictionary, baseline: Dictionary) -> void:
	var name: String = settings.VISUALIZER_PRESETS[index]
	var mapped := index >= mapping_start
	check(metrics["flash_rate"] <= LIMITS["flash_rate"], "%s general flashes ≤ 3/s (%.0f)" % [name, metrics["flash_rate"]])
	check(metrics["red_flash_rate"] <= LIMITS["red_flash_rate"], "%s red flashes ≤ 3/s (%.0f)" % [name, metrics["red_flash_rate"]])
	check(metrics["audio_gain"] >= LIMITS["audio_gain"], "%s brightens with music (%.2f)" % [name, metrics["audio_gain"]])
	check(metrics["pitch_distinct"] >= LIMITS["pitch_distinct"], "%s separates low and high notes (%.4f)" % [name, metrics["pitch_distinct"]])
	check(metrics["clip_fraction"] <= LIMITS["clip_fraction"], "%s keeps highlight headroom (%.3f clipped)" % [name, metrics["clip_fraction"]], mapped)
	check(metrics["rest_luma"] <= LIMITS["rest_luma"], "%s rests dark in silence (%.4f)" % [name, metrics["rest_luma"]], mapped)
	check(metrics["latency_ms"] <= LIMITS["latency_ms"], "%s beat response within %d ms (%.0f)" % [name, LIMITS["latency_ms"], metrics["latency_ms"]], mapped)
	check(metrics["beat_contrast"] >= LIMITS["beat_contrast"], "%s beats visibly pulse (%.3f)" % [name, metrics["beat_contrast"]], mapped)
	check(metrics["entrainment"] >= LIMITS["entrainment"], "%s brightness follows the kick (%.2f)" % [name, metrics["entrainment"]], mapped)
	check(metrics["pitch_rise"] >= LIMITS["pitch_rise"], "%s high notes sit higher than low notes (%.3f)" % [name, metrics["pitch_rise"]], mapped)
	check(metrics["pan_shift"] >= LIMITS["pan_shift"], "%s left and right follow the mix (%.3f)" % [name, metrics["pan_shift"]], mapped)
	check(metrics["monotonic"] > 0.5 and metrics["loudness_ratio"] >= LIMITS["loudness_ratio"], "%s louder is brighter (%.2f)" % [name, metrics["loudness_ratio"]], mapped)
	check(metrics["build_rise"] >= LIMITS["build_rise"], "%s rises through build-ups (%.2f)" % [name, metrics["build_rise"]], mapped)
	check(metrics["drop_impact"] >= LIMITS["drop_impact"], "%s rewards the drop (%.2f)" % [name, metrics["drop_impact"]], mapped)
	check(metrics["evolution"] >= LIMITS["evolution"], "%s evolves across repeated bars (%.4f)" % [name, metrics["evolution"]], mapped)
	check(metrics["coherence"] <= LIMITS["coherence"], "%s frame-to-frame change stays comfortable (%.4f)" % [name, metrics["coherence"]], mapped)
	if not baseline.has(name):
		return
	var reference: Dictionary = baseline[name]
	for key in HIGHER_BETTER:
		if reference.has(key) and float(reference[key]) > 0.0:
			check(metrics[key] >= float(reference[key]) * 0.7, "%s %s holds baseline (%.4f vs %.4f)" % [name, key, metrics[key], reference[key]])
	if reference.has("latency_ms"):
		check(metrics["latency_ms"] <= float(reference["latency_ms"]) * 1.25 + 17.0, "%s latency holds baseline (%.0f vs %.0f ms)" % [name, metrics["latency_ms"], reference["latency_ms"]])


func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		if checks == 0:
			printerr("FAIL start")
			quit(2))
	for i in 256:
		var c := i / 255.0
		linear.append(c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4))
	settings = root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_quality = 3
	settings.visualizer_motion = 0.6
	settings.visualizer_intensity = 0.75
	settings.visualizer_sensitivity = 1.75
	settings.visualizer_starred_only = false
	mute_everything()
	shots = argument("--shots")
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shots)
	var start := int(argument("--from", str(load("res://scripts/resonance_field.gd").PSYCHE_START)))
	var finish := int(argument("--to", str(settings.VISUALIZER_PRESET_MAX)))
	if "--all" in OS.get_cmdline_user_args():
		start = 0
	var only := argument("--only")
	mapping_start = load("res://scripts/resonance_field.gd").PSYCHE_START
	create_timer(60.0 + 60.0 * (finish - start + 1)).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	var size := argument("--size", "%dx%d" % [SIZE.x, SIZE.y]).split("x")
	root.size = Vector2i(int(size[0]), int(size[1]))
	camera = Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	var baseline := {}
	if FileAccess.file_exists(BASELINE_PATH):
		baseline = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	var update := "--update-baseline" in OS.get_cmdline_user_args()
	var results := baseline.duplicate(true)
	for index in range(start, finish + 1):
		if not only.is_empty() and int(only) != index:
			continue
		if "--benchmark" in OS.get_cmdline_user_args():
			await benchmark(index)
			continue
		var metrics := await audition(index)
		judge(index, metrics, {} if update else baseline)
		results[settings.VISUALIZER_PRESETS[index]] = metrics
	if update:
		var file := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t", true) + "\n")
		file.close()
		print("BASELINE written ", ProjectSettings.globalize_path(BASELINE_PATH))
	check(AudioServer.is_bus_mute(0), "master output stayed muted")
	print("RESULT checks=%d failures=%d warnings=%d" % [checks, failures, warnings])
	quit(1 if failures else 0)
