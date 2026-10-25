extends SceneTree

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:
		failures += 1


func frames(count := 40) -> void:
	for frame in count:
		await process_frame


func run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(25).timeout.connect(func() -> void: quit(2))
	var phase := OS.get_cmdline_user_args()[0]
	var settings := root.get_node("Settings")
	settings.prefer_desktop = true
	settings.last_file = ""
	settings.resume_playback = false
	if phase == "seed":
		settings.window_session = {}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	var mini = main.desktop_view.mini_player
	var session = main.window_session
	if phase == "seed":
		check(not mini.active, "fresh session opens full player")
		await mini.enter()
		root.position = DisplayServer.screen_get_usable_rect().position + Vector2i(70, 80)
		session.pin_mini(false)
		mini.idle_fade = true
		session.state["mini_idle_fade"] = true
		mini.visualizer_mode = 0
		session.state["mini_visualizer"] = 0
		await frames()
		check(mini.active, "close saves active mini player")
	elif phase in ["mini", "nano"]:
		check(mini.active and mini.visible, "new process reopens compact player")
		check(mini.cover_mode == (phase == "nano"), "new process restores correct compact layout")
		check(not root.always_on_top and mini.idle_fade and mini.visualizer_mode == 0, "new process preserves pin, fade and visualizer preferences")
		var expected_position: Vector2i = session.state.get("check_target_position", DisplayServer.screen_get_usable_rect().position + Vector2i(70, 80))
		check(root.position == expected_position, "new process restores compact window position")
		if phase == "mini":
			mini._toggle_cover()
			session.state["check_target_position"] = root.position
			session._save_state()
			check(mini.cover_mode, "nano switch applies before close")
		else:
			await mini.leave()
			await frames()
			check(not bool(session.state.get("mini_active", true)), "expanding clears saved compact startup state")
	elif phase == "full":
		check(not mini.active and not root.borderless, "closing full player reopens full player")
		check(bool(session.state.get("mini_cover", false)), "full player retains last nano preference")
	print("RESULT failures=%d" % failures)
	quit(1 if failures else 0)
