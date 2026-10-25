extends SceneTree

const Synth := preload("res://packaging/checks/music_synth.gd")

var checks := 0
var failures := 0
var only := ""


func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find("--case")
	if index >= 0 and index + 1 < arguments.size():
		only = arguments[index + 1]
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", message)


func analyse(synth: Synth) -> Dictionary:
	return VPXMusicAnalysis.new().analyze_samples(synth.samples, Synth.RATE)


func beat_errors(result: Dictionary, synth: Synth, from_beat: int, to_beat: int) -> PackedFloat32Array:
	var beats: PackedFloat32Array = result.get("beats", PackedFloat32Array())
	var errors := PackedFloat32Array()
	for beat in range(from_beat, to_beat):
		var truth := synth.beat_time(beat)
		var nearest := INF
		for detected in beats:
			if absf(detected - truth) < absf(nearest):
				nearest = detected - truth
		errors.append(nearest)
	return errors


func top(values: PackedFloat32Array) -> float:
	var best := -INF
	for value in values:
		best = maxf(best, value)
	return best


func bottom(values: PackedFloat32Array) -> float:
	var best := INF
	for value in values:
		best = minf(best, value)
	return best


func median(values: PackedFloat32Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else INF


func house(bpm: float, bars: int) -> Synth:
	var synth := Synth.new(bpm, bars)
	synth.four_on_floor(0, bars)
	synth.offbeat_hats(0, bars)
	synth.backbeat(0, bars, 0.7)
	synth.pad(0, bars, [57, 60, 64])
	synth.normalise()
	return synth


func case_tempo_120_clicks() -> void:
	var synth := Synth.new(120.0, 16)
	for beat in 64:
		synth.click(beat)
	var result := analyse(synth)
	check(absf(result.tempo - 120.0) < 1.0, "120 BPM clicks tempo %.2f" % result.tempo)


func case_tempo_90_groove() -> void:
	var synth := Synth.new(90.0, 16)
	for bar in 16:
		synth.kick(bar * 4)
		synth.kick(bar * 4 + 2.5, 0.8)
		synth.snare(bar * 4 + 1)
		synth.snare(bar * 4 + 3)
		for eighth in 8:
			synth.hat(bar * 4 + eighth * 0.5, 0.6)
	synth.normalise()
	var result := analyse(synth)
	check(absf(result.tempo - 90.0) < 1.5, "90 BPM groove tempo %.2f" % result.tempo)


func case_tempo_140_house() -> void:
	var result := analyse(house(140.0, 24))
	check(absf(result.tempo - 140.0) < 1.5, "140 BPM house tempo %.2f" % result.tempo)


func case_tempo_174_breaks() -> void:
	var synth := Synth.new(174.0, 32)
	for bar in 32:
		synth.kick(bar * 4)
		synth.kick(bar * 4 + 2.5, 0.9)
		synth.snare(bar * 4 + 1)
		synth.snare(bar * 4 + 3)
		for eighth in 8:
			synth.hat(bar * 4 + eighth * 0.5, 0.5)
	synth.normalise()
	var result := analyse(synth)
	var tempo: float = result.tempo
	check(absf(tempo - 174.0) < 2.0 or absf(tempo - 87.0) < 1.0, "174 BPM breaks tempo %.2f (or half)" % tempo)


func case_beat_alignment_clicks() -> void:
	var synth := Synth.new(120.0, 16)
	for beat in 64:
		synth.click(beat)
	var errors := beat_errors(analyse(synth), synth, 2, 60)
	var absolute := PackedFloat32Array()
	for error in errors:
		absolute.append(absf(error))
	check(median(absolute) < 0.012, "click beats median error %.1f ms" % (median(absolute) * 1000.0))
	check(absolute[absolute.size() - 1] < 0.03 and top(absolute) < 0.03, "click beats max error %.1f ms" % (top(absolute) * 1000.0))


func case_beat_alignment_house() -> void:
	var synth := house(128.0, 16)
	var errors := beat_errors(analyse(synth), synth, 2, 60)
	var absolute := PackedFloat32Array()
	var signed := 0.0
	for error in errors:
		absolute.append(absf(error))
		signed += error
	check(median(absolute) < 0.015, "house beats median error %.1f ms (mean signed %.1f ms)" % [median(absolute) * 1000.0, signed / errors.size() * 1000.0])
	check(top(absolute) < 0.035, "house beats max error %.1f ms" % (top(absolute) * 1000.0))


func case_beat_coverage() -> void:
	var synth := house(124.0, 16)
	var errors := beat_errors(analyse(synth), synth, 1, 63)
	var matched := 0
	for error in errors:
		matched += int(absf(error) < 0.05)
	check(matched >= int(errors.size() * 0.95), "house beats matched %d / %d" % [matched, errors.size()])


func case_beat_continues_through_breakdown() -> void:
	var synth := Synth.new(120.0, 24)
	synth.four_on_floor(0, 8)
	synth.offbeat_hats(0, 8)
	synth.pad(0, 24, [57, 60, 64])
	synth.four_on_floor(16, 24)
	synth.offbeat_hats(16, 24)
	synth.normalise()
	var result := analyse(synth)
	var errors := beat_errors(result, synth, 66, 90)
	var late := 0.0
	for error in errors:
		late = maxf(late, absf(error))
	check(late < 0.04, "beats after an 8-bar breakdown stay on grid (max %.1f ms)" % (late * 1000.0))


func case_downbeat_accent() -> void:
	var synth := Synth.new(120.0, 16)
	for bar in 16:
		synth.kick(bar * 4, 1.0)
		synth.snare(bar * 4 + 1)
		synth.snare(bar * 4 + 3)
		for beat in 4:
			synth.hat(bar * 4 + beat, 0.6)
	synth.normalise()
	var result := analyse(synth)
	var downbeats: PackedFloat32Array = result.downbeats
	var aligned := 0
	for time in downbeats:
		var beat := time / synth.beat_length()
		aligned += int(absf(beat - round(beat / 4.0) * 4.0) < 0.15)
	check(downbeats.size() >= 12 and aligned >= downbeats.size() - 1, "kick-accented downbeats aligned %d / %d" % [aligned, downbeats.size()])


func case_downbeat_chord_change() -> void:
	var synth := Synth.new(120.0, 16)
	synth.four_on_floor(0, 16)
	synth.offbeat_hats(0, 16)
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
	for bar in 16:
		synth.pad(bar, bar + 1, chords[bar % 4], 0.16)
	synth.normalise()
	var result := analyse(synth)
	var downbeats: PackedFloat32Array = result.downbeats
	var aligned := 0
	for time in downbeats:
		var beat := time / synth.beat_length()
		aligned += int(absf(beat - round(beat / 4.0) * 4.0) < 0.15)
	check(downbeats.size() >= 12 and aligned >= downbeats.size() - 1, "chord-change downbeats aligned %d / %d" % [aligned, downbeats.size()])


func curve_mean(result: Dictionary, key: String, from: float, to: float) -> float:
	var curve: PackedFloat32Array = result[key]
	var rate: float = result.rate
	var total := 0.0
	var count := 0
	for i in range(int(from * rate), mini(curve.size(), int(to * rate))):
		total += curve[i]
		count += 1
	return total / maxi(1, count)


func case_separation_tone() -> void:
	var synth := Synth.new(120.0, 8)
	synth.pad(0, 8, [57, 60, 64], 0.2)
	var result := analyse(synth)
	var harmonic := curve_mean(result, "harmonic", 1.0, 14.0)
	var percussive := curve_mean(result, "percussive", 1.0, 14.0)
	check(harmonic > percussive + 0.25, "sustained chord is harmonic (h %.2f p %.2f)" % [harmonic, percussive])


func case_separation_drums() -> void:
	var synth := Synth.new(120.0, 8)
	for beat in 32:
		synth.snare(beat)
		synth.hat(beat + 0.5)
	synth.normalise()
	var result := analyse(synth)
	var harmonic := curve_mean(result, "harmonic", 1.0, 14.0)
	var percussive := curve_mean(result, "percussive", 1.0, 14.0)
	check(percussive > harmonic + 0.1, "drums are percussive (h %.2f p %.2f)" % [harmonic, percussive])


func case_separation_mix_tracks_hits() -> void:
	var synth := Synth.new(120.0, 8)
	synth.pad(0, 8, [57, 60, 64], 0.15)
	for beat in 32:
		synth.snare(beat)
	synth.normalise()
	var result := analyse(synth)
	var on := 0.0
	var off := 0.0
	for beat in range(2, 30):
		on += curve_mean(result, "percussive", synth.beat_time(beat), synth.beat_time(beat) + 0.05)
		off += curve_mean(result, "percussive", synth.beat_time(beat) + 0.3, synth.beat_time(beat) + 0.4)
	check(on > off * 1.5 + 0.5, "percussive curve peaks on hits over a pad (on %.2f off %.2f)" % [on / 28.0, off / 28.0])


func sections_near(result: Dictionary, time: float, tolerance: float) -> bool:
	for start in result.sections:
		if absf(start - time) <= tolerance:
			return true
	return false


func case_section_boundary() -> void:
	var synth := Synth.new(120.0, 64)
	synth.four_on_floor(0, 64)
	synth.offbeat_hats(0, 32)
	synth.pad(0, 32, [57, 60, 64])
	synth.backbeat(32, 64)
	synth.pad(32, 64, [53, 58, 62], 0.14)
	synth.bass(32, 64, 34, 0.3)
	synth.normalise()
	var result := analyse(synth)
	check(sections_near(result, synth.bar_time(32), synth.beat_length() * 0.6), "section starts at bar 32 (sections %s)" % str(result.sections))


func case_section_none_when_steady() -> void:
	var result := analyse(house(120.0, 48))
	check(result.sections.size() <= 1, "steady track has one section (sections %s)" % str(result.sections))


func case_section_groups_repeat() -> void:
	var synth := Synth.new(120.0, 64)
	synth.four_on_floor(0, 64)
	for part in 4:
		var from := part * 16
		if part % 2 == 0:
			synth.offbeat_hats(from, from + 16)
			synth.pad(from, from + 16, [57, 60, 64])
		else:
			synth.backbeat(from, from + 16)
			synth.pad(from, from + 16, [50, 53, 57], 0.14)
			synth.bass(from, from + 16, 38, 0.3)
	synth.normalise()
	var result := analyse(synth)
	var groups: PackedFloat32Array = result.section_group
	var ok: bool = result.sections.size() == 4 and groups.size() == 4 and groups[0] == groups[2] and groups[1] == groups[3] and groups[0] != groups[1]
	check(ok, "A B A B sections get repeating groups (sections %s groups %s)" % [str(result.sections), str(groups)])


func edm(bpm := 126.0) -> Synth:
	var synth := Synth.new(bpm, 48)
	synth.four_on_floor(0, 16, 0.8)
	synth.offbeat_hats(0, 16)
	synth.pad(0, 24, [57, 60, 64], 0.08)
	synth.riser(16, 24, 0.3)
	for bar in range(20, 24):
		var hits := 16 if bar >= 22 else 8
		for hit in hits:
			synth.snare(bar * 4 + hit * 4.0 / hits, 0.25 + 0.1 * (bar - 20))
	synth.four_on_floor(24, 48, 1.0)
	synth.offbeat_hats(24, 48)
	synth.backbeat(24, 48, 0.8)
	synth.bass(24, 48, 33, 0.55)
	synth.pad(24, 48, [57, 60, 64], 0.08)
	synth.normalise()
	return synth


func case_drop_detected() -> void:
	var synth := edm()
	var result := analyse(synth)
	var drops: PackedFloat32Array = result.drops
	var hit := false
	for drop in drops:
		hit = hit or absf(drop - synth.bar_time(24)) < synth.beat_length() * 0.6
	check(hit and drops.size() == 1, "drop at bar 24 (drops %s, truth %.2f)" % [str(drops), synth.bar_time(24)])


func case_build_start() -> void:
	var synth := edm()
	var result := analyse(synth)
	var builds: PackedFloat32Array = result.build_starts
	var ok := builds.size() == 1 and absf(builds[0] - synth.bar_time(16)) <= synth.beat_length() * 0.6
	check(ok, "build starts near bar 16 (builds %s, truth %.2f)" % [str(builds), synth.bar_time(16)])


func case_build_after_breakdown() -> void:
	var synth := Synth.new(126.0, 56)
	synth.four_on_floor(0, 16)
	synth.offbeat_hats(0, 16)
	synth.bass(0, 16, 33, 0.4)
	synth.pad(0, 32, [57, 60, 64], 0.1)
	synth.riser(26, 32, 0.35)
	for bar in range(28, 32):
		for hit in 8:
			synth.snare(bar * 4 + hit * 0.5, 0.2 + 0.08 * (bar - 28))
	synth.four_on_floor(32, 56)
	synth.offbeat_hats(32, 56)
	synth.bass(32, 56, 33, 0.55)
	synth.normalise()
	var result := analyse(synth)
	var drops: PackedFloat32Array = result.drops
	var builds: PackedFloat32Array = result.build_starts
	var drop_ok := drops.size() == 1 and absf(drops[0] - synth.bar_time(32)) < synth.beat_length() * 0.6
	check(drop_ok, "drop after breakdown at bar 32 (drops %s)" % str(drops))
	var build_ok := builds.size() == 1 and builds[0] >= synth.bar_time(23.5) and builds[0] <= synth.bar_time(26.5)
	check(build_ok, "build skips the calm breakdown and starts near the riser (builds %s, riser %.2f)" % [str(builds), synth.bar_time(26)])


func case_drop_none_when_steady() -> void:
	var result := analyse(house(126.0, 48))
	check(result.drops.is_empty(), "steady track has no drops (drops %s)" % str(result.drops))


func case_section_energy_order() -> void:
	var synth := Synth.new(120.0, 48)
	synth.pad(0, 16, [57, 60, 64], 0.05)
	synth.four_on_floor(0, 16, 0.2)
	synth.four_on_floor(16, 48)
	synth.offbeat_hats(16, 48)
	synth.backbeat(16, 48)
	synth.bass(16, 48, 33, 0.5)
	synth.pad(16, 48, [57, 60, 64], 0.15)
	synth.normalise()
	var result := analyse(synth)
	var energy: PackedFloat32Array = result.section_energy
	check(energy.size() >= 2 and energy[0] < energy[energy.size() - 1] - 0.3, "quiet intro has lower section energy (%s)" % str(energy))


func case_silence() -> void:
	var samples := PackedFloat32Array()
	samples.resize(Synth.RATE * 10)
	var result: Dictionary = VPXMusicAnalysis.new().analyze_samples(samples, Synth.RATE)
	check(result.beats.is_empty() and result.sections.size() == 1 and result.drops.is_empty(), "silence has no beats, one section, no drops")
	check(top(result.loudness) == 0.0 and top(result.onset) == 0.0, "silence curves stay at zero")


func case_short_clip() -> void:
	var samples := PackedFloat32Array()
	samples.resize(Synth.RATE)
	for i in samples.size():
		samples[i] = sin(i * 0.05) * 0.3
	var result: Dictionary = VPXMusicAnalysis.new().analyze_samples(samples, Synth.RATE)
	check(not result.is_empty() and result.beats.is_empty() and absf(result.duration - 1.0) < 0.01, "1 s clip analyses without beats")


func case_empty_input() -> void:
	var result: Dictionary = VPXMusicAnalysis.new().analyze_samples(PackedFloat32Array(), Synth.RATE)
	check(not result.is_empty() and result.beats.is_empty(), "empty input returns an empty map")


func case_curves_shape() -> void:
	var synth := house(120.0, 8)
	var result := analyse(synth)
	var expected := int(synth.samples.size() / 512) + 1
	var ok := true
	for key in ["loudness", "bass", "percussive", "harmonic", "brightness", "onset", "intensity"]:
		var curve: PackedFloat32Array = result[key]
		ok = ok and curve.size() == expected and bottom(curve) >= 0.0 and top(curve) <= 1.0
	check(ok, "all curves have one value per hop within 0..1")
	check(absf(result.rate - 22050.0 / 512.0) < 0.001, "curve rate is 43.07 Hz")


func case_resampled_input() -> void:
	var synth := house(120.0, 12)
	var doubled := PackedFloat32Array()
	doubled.resize(synth.samples.size() * 2)
	for i in doubled.size():
		doubled[i] = synth.samples[i / 2]
	var result: Dictionary = VPXMusicAnalysis.new().analyze_samples(doubled, Synth.RATE * 2)
	check(absf(result.tempo - 120.0) < 1.0 and absf(result.duration - synth.duration()) < 0.05, "44.1 kHz input resamples (tempo %.2f)" % result.tempo)


func case_file_thread() -> void:
	var synth := house(122.0, 16)
	var path := OS.get_cache_dir().path_join("vpx_music_analysis_test_%d.wav" % OS.get_process_id())
	synth.save_wav(path)
	var analysis := VPXMusicAnalysis.new()
	check(analysis.start(path), "file analysis starts")
	var waited := 0.0
	while not analysis.is_done() and waited < 15.0:
		await create_timer(0.05).timeout
		waited += 0.05
	var result: Dictionary = analysis.get_result()
	check(analysis.is_done() and analysis.get_error().is_empty(), "file analysis finishes without error (%s)" % analysis.get_error())
	check(not result.is_empty() and absf(result.tempo - 122.0) < 1.0, "file analysis tempo %.2f" % float(result.get("tempo", 0.0)))
	check(absf(float(result.get("duration", 0.0)) - synth.duration()) < 0.05, "file analysis duration %.2f" % float(result.get("duration", 0.0)))
	check(analysis.get_progress() >= 0.999, "progress reaches 1")
	DirAccess.remove_absolute(path)


func case_file_missing() -> void:
	var analysis := VPXMusicAnalysis.new()
	analysis.start("/nonexistent/vpx/track.flac")
	var waited := 0.0
	while not analysis.is_done() and waited < 5.0:
		await create_timer(0.02).timeout
		waited += 0.02
	check(analysis.is_done() and not analysis.get_error().is_empty() and analysis.get_result().is_empty(), "missing file reports an error")


func case_file_cancel() -> void:
	var synth := house(120.0, 64)
	var path := OS.get_cache_dir().path_join("vpx_music_cancel_test_%d.wav" % OS.get_process_id())
	synth.save_wav(path)
	var analysis := VPXMusicAnalysis.new()
	analysis.start(path)
	var started := Time.get_ticks_msec()
	analysis.cancel()
	check(Time.get_ticks_msec() - started < 500 and analysis.get_result().is_empty(), "cancel stops promptly without a result")
	check(analysis.start(path), "analysis restarts after cancel")
	analysis = null
	DirAccess.remove_absolute(path)


func case_performance() -> void:
	var synth := house(128.0, 160)
	var started := Time.get_ticks_usec()
	var result := analyse(synth)
	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	check(seconds < 2.0 and not result.beats.is_empty(), "5 minute track analyses in %.2f s" % seconds)


func run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: printerr("FAIL timeout"); quit(2))
	var cases: Array[String] = []
	for method in get_method_list():
		var name: String = method.name
		if name.begins_with("case_") and (only.is_empty() or name == "case_" + only or only.split(",").has(name.trim_prefix("case_"))):
			cases.append(name)
	for name in cases:
		var started := Time.get_ticks_msec()
		await call(name)
		print("  %s %d ms" % [name, Time.get_ticks_msec() - started])
	print("MUSIC_ANALYSIS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
