extends SceneTree

const TOLERANCE := 0.07

var failures := 0
var checks := 0
var output: VideoStreamPlayer
var playback
var field: Node


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func mute_everything() -> void:
	for bus in AudioServer.bus_count:
		AudioServer.set_bus_mute(bus, true)
		AudioServer.set_bus_volume_db(bus, -80.0)
	check(AudioServer.get_driver_name() == "Dummy", "audio driver is Dummy so nothing reaches speakers")
	check(AudioServer.is_bus_mute(0), "master output muted")


func make_track(path: String) -> Dictionary:
	var lines := []
	var code := OS.execute("python3", ["-I", ProjectSettings.globalize_path("res://packaging/checks/make_music_track.py"), path], lines, true)
	check(code == 0 and FileAccess.file_exists(path), "synthetic music track generated")
	if code != 0:
		print(lines)
		return {}
	var text: String = lines[0].strip_edges().split("\n")[-1]
	return JSON.parse_string(text)


func within(times: Array, start: float, finish: float) -> Array:
	return times.filter(func(t: float) -> bool: return t >= start and t < finish)


func f_measure(detected: Array, truth: Array) -> Dictionary:
	var used := {}
	var hits := 0
	var offsets: Array[float] = []
	for t in truth:
		var best := -1
		for i in detected.size():
			if used.has(i):
				continue
			if absf(detected[i] - t) <= TOLERANCE and (best < 0 or absf(detected[i] - t) < absf(detected[best] - t)):
				best = i
		if best >= 0:
			used[best] = true
			hits += 1
			offsets.append(detected[best] - t)
	var precision := float(hits) / maxi(1, detected.size())
	var recall := float(hits) / maxi(1, truth.size())
	var mean := 0.0
	for o in offsets:
		mean += absf(o) / offsets.size()
	return {"f": 2.0 * precision * recall / maxf(0.0001, precision + recall), "offset": mean, "precision": precision, "recall": recall}


func run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	mute_everything()
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_auto_change = false
	settings.visualizer_motion = 0.6
	var path := OS.get_user_data_dir().path_join("visualizer-music-track.wav")
	var plan := make_track(path)
	if plan.is_empty():
		quit(1)
		return
	root.size = Vector2i(320, 180)
	var camera := Camera3D.new()
	camera.fov = 85
	root.add_child(camera)
	camera.current = true
	field = load("res://scripts/resonance_field.gd").new()
	field.camera = camera
	root.add_child(field)
	field.set_process(false)
	field.set_active(true)
	settings.apply("visualizer_preset", field.PSYCHE_START)
	output = VideoStreamPlayer.new()
	output.volume_db = -80.0
	root.add_child(output)
	var stream := FFmpegVideoStream.new()
	stream.set_file(path)
	output.stream = stream
	playback = stream.get_playback()
	check(playback != null and playback.has_method("get_visualizer_state"), "decoder exposes native analysis")
	if playback == null:
		quit(1)
		return
	playback.set_visualizer_enabled(true)
	output.play()
	var length: float = plan["length"]
	var last_time := -1.0
	var last_beats := 0
	var beats: Array[float] = []
	var samples: Array[Dictionary] = []
	var previous := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + int((length + 8.0) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := minf(0.1, (now - previous) * 0.000001)
		previous = now
		var state: Dictionary = playback.get_visualizer_state(0.0)
		var audio_time := float(state.get("time", -1.0))
		if audio_time >= length - 0.05 or (not output.is_playing() and audio_time > 1.0):
			break
		if state.is_empty() or audio_time == last_time:
			continue
		var step := audio_time - last_time if last_time >= 0.0 else delta
		last_time = audio_time
		field.feed(state["spectrum"], state)
		field.clock += step
		field.beat_age = minf(4.0, field.beat_age + step)
		field._process(step)
		if field.beat_count != last_beats:
			beats.append(audio_time)
			if "--trace" in OS.get_cmdline_user_args():
				print("BEAT time=%.3f bass=%.3f" % [audio_time, field.psyche_bass])
			last_beats = field.beat_count
		var a = field.affect
		samples.append({"time": audio_time, "tension": a.tension, "release": a.release, "centroid": a.centroid, "period": a.period, "groove": a.groove, "arousal": a.arousal, "presence": field.desired_presence})
	check(samples.size() > 200, "analysis followed playback (%d frames)" % samples.size())
	if samples.size() < 50:
		print("RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var kicks: Array = plan["kicks"]
	var groove: Array = plan["groove"]
	var build: Array = plan["build"]
	var drop: Array = plan["drop"]
	var score := f_measure(within(beats, groove[0], groove[1] + 0.2), within(kicks, groove[0], groove[1]))
	print("BEATS groove f=%.2f precision=%.2f recall=%.2f offset=%.0f ms" % [score["f"], score["precision"], score["recall"], score["offset"] * 1000.0])
	check(score["f"] >= 0.9, "groove beats detected (F %.2f within ±70 ms)" % score["f"])
	check(score["offset"] <= 0.05, "beat timing within 50 ms (%.0f ms)" % (score["offset"] * 1000.0))
	var drop_score := f_measure(within(beats, drop[0], drop[1] + 0.2), within(kicks, drop[0], drop[1]))
	check(drop_score["f"] >= 0.9, "drop beats detected (F %.2f)" % drop_score["f"])
	var false_beats := within(beats, build[0] + 0.3, build[1] - 0.05).size() + within(beats, drop[1] + 0.5, length).size()
	check(false_beats <= 2, "build-up hats and silence do not fake kicks (%d)" % false_beats)
	var at_groove_end: Dictionary = {}
	var build_tension := 0.0
	var groove_tension := 0.0
	var groove_release := 0.0
	var drop_release := 0.0
	var build_centroid := 0.0
	var groove_centroid := 0.0
	var build_count := 0
	var groove_count := 0
	var outro_presence := 1.0
	for sample in samples:
		var t: float = sample["time"]
		if t >= groove[0] + 3.0 and t < groove[1]:
			groove_tension = maxf(groove_tension, sample["tension"])
			groove_release = maxf(groove_release, sample["release"])
			groove_centroid += sample["centroid"]
			groove_count += 1
			at_groove_end = sample
		if t >= build[0] + 1.0 and t < build[1]:
			build_tension = maxf(build_tension, sample["tension"])
			build_centroid += sample["centroid"]
			build_count += 1
		if t >= drop[0] and t < drop[0] + 0.4:
			drop_release = maxf(drop_release, sample["release"])
		if t >= drop[1] + 1.2:
			outro_presence = minf(outro_presence, sample["presence"])
	print("AFFECT period=%.3f groove=%.2f groove_tension=%.2f build_tension=%.2f groove_release=%.2f drop_release=%.2f" % [at_groove_end.get("period", 0.0), at_groove_end.get("groove", 0.0), groove_tension, build_tension, groove_release, drop_release])
	check(absf(float(at_groove_end.get("period", 0.0)) - 60.0 / float(plan["bpm"])) <= 0.025, "tempo locks to 120 BPM (%.3f s)" % at_groove_end.get("period", 0.0))
	check(float(at_groove_end.get("groove", 0.0)) >= 0.6, "steady beat reads as groove (%.2f)" % at_groove_end.get("groove", 0.0))
	check(build_tension >= 0.3 and build_tension > groove_tension + 0.15, "build-up raises tension (%.2f vs %.2f)" % [build_tension, groove_tension])
	check(drop_release >= 0.7, "drop triggers release within 400 ms (%.2f)" % drop_release)
	check(groove_release <= 0.35, "steady groove does not fake drops (%.2f)" % groove_release)
	check(build_count > 0 and groove_count > 0 and build_centroid / build_count > groove_centroid / groove_count, "bright build-up raises spectral centroid")
	check(outro_presence < 0.1, "silence after the track settles (%.2f)" % outro_presence)
	check(AudioServer.is_bus_mute(0), "master output stayed muted")
	output.stop()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
