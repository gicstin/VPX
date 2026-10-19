extends SceneTree

var failures := 0

class TestUI extends Control:
	func handle_key(_event: InputEventKey) -> bool:
		return false

func _initialize() -> void:
	if not preload("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
	else:
		print("PASS: ", label)

func run() -> void:
	root.size = Vector2i(1280, 1000)
	var settings := root.get_node("Settings")
	settings.set_process(false)
	settings.visualizer_starred_only = false
	settings.visualizer_favorites = PackedStringArray()
	var main = load("res://scripts/main.gd").new()
	var player = load("res://scripts/player.gd").new()
	main.player = player
	var stream := FFmpegVideoStream.new()
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(88200)
	audio.data = samples
	var audio_path := "user://visualizer_check_%d.wav" % Time.get_ticks_usec()
	audio.save_to_wav(audio_path)
	stream.file = ProjectSettings.globalize_path(audio_path)
	root.add_child(player)
	player.stream = stream
	player.play()
	player.playback = stream.get_playback()
	check(player.playback != null, "audio fixture has playback")
	player.current_path = "test.flac"
	main.panel = load("res://scripts/panel.gd").new()
	main.ui = TestUI.new()
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	settings.visualizer_preset = 0
	main._handle_key(key)
	check(settings.visualizer_preset == 1, "F selects next music scene")
	key.shift_pressed = true
	main._handle_key(key)
	check(settings.visualizer_preset == 0, "Shift+F selects previous music scene")
	key.echo = true
	main._handle_key(key)
	check(settings.visualizer_preset == 0, "held F does not skip scenes")
	var projection: int = settings.projection
	var stereo: int = settings.stereo
	for action in main.FORMAT_ACTION_NAMES:
		settings.visualizer_preset = settings.VISUALIZER_PRESET_MAX
		main._step_action(action, 1)
		check(settings.visualizer_preset == 0, "format shortcut wraps music forward " + str(action))
		main._step_action(action, -1)
		check(settings.visualizer_preset == settings.VISUALIZER_PRESET_MAX, "format shortcut wraps music backward " + str(action))
		check(main.action_name(action) == "Music scene" and settings.VISUALIZER_PRESETS[settings.VISUALIZER_PRESET_MAX] in main.action_value(action), "music shortcut feedback " + str(action))
	check(settings.projection == projection and settings.stereo == stereo, "music shortcuts preserve video format")
	player.current_path = "test.mp4"
	player.music_path = "background.flac"
	main._step_action(settings.StickAction.FORMAT_ALL, 1)
	check(settings.visualizer_preset == 0, "background music uses scene shortcuts")
	player.current_path = ""
	main.panel.hide()
	main._cycle_visualizer_preset()
	check(settings.visualizer_preset == 1, "VR thumbstick cycles background music scenes")
	main.panel.show()
	main._cycle_visualizer_preset()
	check(settings.visualizer_preset == 1, "VR thumbstick leaves open menu alone")
	player.music_path = ""
	player.current_path = "test.mp4"
	settings.projection = 0
	settings.stereo = 0
	settings.visualizer_preset = 12
	main._step_action(settings.StickAction.FORMAT_ALL, 1)
	check(settings.stereo == 1 and settings.visualizer_preset == 12, "video still cycles formats")
	var desktop = load("res://scripts/photo_bar.gd").new()
	desktop.player = player
	desktop.set_process(false)
	root.add_child(desktop)
	var vr = load("res://scripts/music_panel.gd").new()
	vr.player = player
	vr.set_process(false)
	root.add_child(vr)
	check(desktop.root.scene_picker.tiles.size() == settings.VISUALIZER_PRESETS.size() and vr.view.scene_picker.tiles.size() == settings.VISUALIZER_PRESETS.size(), "desktop and VR music controls build thumbnail pickers")
	check(desktop.root.scene_picker.selected == desktop.root.immersive_button and vr.view.scene_picker.selected == vr.view.immersive_button, "desktop and VR reuse immersive button for scene dropdown")
	check(not desktop.root.scene_picker.visible and not vr.view.scene_picker.visible, "closed music scene dropdowns occupy no space")
	desktop.root.immersive_button.pressed.emit()
	check(desktop.root.scene_picker.menu.visible, "immersive button opens scene dropdown")
	desktop.root.show()
	desktop.root.size = desktop.root.wanted_size()
	await process_frame
	await process_frame
	check(is_equal_approx(desktop.root.scene_picker.gallery.size.x, desktop.root.rows.size.x), "scene dropdown fills mini player content width")
	var mini_preview: TextureRect = desktop.root.scene_picker.tiles[0].get_child(0).get_child(0)
	check(mini_preview.size.y > 100 and absf(mini_preview.size.x / mini_preview.size.y - 16.0 / 9.0) < 0.01, "mini player previews grow to full card width without cropping")
	check(desktop.root.scene_picker.gallery.size.y >= 180 and desktop.root.scene_picker.tuning.visible, "scene dropdown leaves preview space beneath pinned controls")

	check(is_equal_approx(desktop.root.scene_picker.disabled_button.get_parent().size.x, desktop.root.rows.size.x), "scene actions fill mini player content width")
	desktop.root.hide()

	desktop.root.scene_picker.disabled_button.pressed.emit()
	check(not settings.immersive_music_visualizer and not desktop.root.scene_picker.visible, "music selector disables immersive and releases gallery space")
	settings.apply("immersive_music_visualizer", true)

	settings.apply("visualizer_preset", 18)
	check(desktop.root.scene_picker.selected.tooltip_text.contains("Laser Show") and vr.view.scene_picker.selected.tooltip_text.contains("Laser Show"), "desktop and VR scene previews stay in sync")
	var host := Control.new()
	settings.apply("accent_color", Color.WHITE)
	host.theme = VpxTheme.build()
	root.add_child(host)
	var picker = load("res://scripts/visualizer_picker.gd").new()
	picker.setting = &"visualizer_preset"
	picker.options = PackedStringArray(settings.VISUALIZER_PRESETS)
	host.add_child(picker)
	await process_frame
	check(picker.tiles.size() == settings.VISUALIZER_PRESETS.size(), "all scene thumbnails available")
	check(picker.disabled_button.text == "Disable Visualisation", "disable action uses requested label")
	var caption: PanelContainer = picker.tiles[0].get_child(0).get_child(1)
	var caption_background: StyleBoxFlat = caption.get_theme_stylebox("panel")
	check(caption_background.bg_color.get_luminance() < 0.1 and caption.get_child(0).get_theme_color("font_color").get_luminance() > 0.7, "scene captions retain dark background and light text with white accent")

	check(picker.selected.icon == null and picker.selected.custom_minimum_size.y == 60, "closed selector has no image preview")
	picker.selected.pressed.emit()
	picker.disabled_button.pressed.emit()
	check(not settings.immersive_music_visualizer and picker.selected.text == "Disabled ▾" and not picker.menu.visible, "Disabled turns immersive off and closes dropdown")

	var regions_valid := true
	for i in settings.VISUALIZER_PRESETS.size():
		regions_valid = regions_valid and picker.thumbnail(i).region == Rect2((i % 8) * 160, (i / 8) * 90, 160, 90)
	check(regions_valid, "all thumbnails map to their scene")
	var last_preview: AtlasTexture = picker.thumbnail(settings.VISUALIZER_PRESET_MAX)
	check(last_preview.region.end.y <= last_preview.atlas.get_height(), "preview atlas includes final studio row")
	check(settings.VISUALIZER_STUDIO_GUIDES[-1] in picker.tiles[settings.VISUALIZER_PRESET_MAX].tooltip_text, "final thumbnail explains its audio response")
	var guides_valid := true
	for index in range(settings.VISUALIZER_STUDIO_START, settings.VISUALIZER_PRESETS.size()):
		var tile: Button = picker.tiles[index]
		var info: Control = tile._make_custom_tooltip(tile.tooltip_text)
		guides_valid = guides_valid and info.get_child_count() == 2 and info.get_child(0).text == settings.VISUALIZER_PRESETS[index] and info.get_child(1).autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and "\n" in info.get_child(1).text
		info.free()
	check(guides_valid, "every studio card builds a wrapped hover information box")
	picker.selected.pressed.emit()
	check(picker.gallery.visible, "picker opens")
	await process_frame
	await process_frame
	await process_frame
	var pinned_position: Vector2 = picker.tuning.global_position
	picker.gallery.scroll_vertical = 2000
	await process_frame
	check(picker.tuning.global_position == pinned_position and picker.tuning.get_parent() == picker.menu, "intensity controls stay pinned while previews scroll")
	var preset_before: int = settings.visualizer_preset
	picker.adjustments[&"visualizer_intensity"].value = 1.15
	check(is_equal_approx(settings.visualizer_intensity, 1.15) and is_equal_approx(desktop.root.scene_picker.adjustments[&"visualizer_intensity"].value, 1.15) and is_equal_approx(vr.view.scene_picker.adjustments[&"visualizer_intensity"].value, 1.15), "intensity edits synchronize desktop and VR controls")
	check(picker.gallery.visible and settings.visualizer_preset == preset_before, "tuning preserves scene selection and leaves dropdown open")
	picker.adjustments[&"visualizer_intensity"].get_parent().get_child(3).pressed.emit()
	check(is_equal_approx(settings.visualizer_intensity, float(settings.defaults[&"visualizer_intensity"])), "intensity reset button restores default")
	var resets_valid := true
	for setting_key: StringName in picker.adjustments:
		var slider: HSlider = picker.adjustments[setting_key]
		var row: HBoxContainer = slider.get_parent()
		slider.value = slider.min_value
		var reset: Button = row.get_child(3)
		resets_valid = resets_valid and row.get_child(2) is Label and reset.icon != null and "to default" in reset.tooltip_text
		reset.pressed.emit()
		resets_valid = resets_valid and is_equal_approx(float(settings.get(setting_key)), float(settings.defaults[setting_key]))
	check(resets_valid, "every visualiser slider has a separate reset button after its value")
	picker.tuning.get_child(3).pressed.emit()
	await process_frame
	await process_frame
	check(picker.more_controls.visible and picker.gallery.custom_minimum_size.y >= 180, "advanced options keep a scrollable preview area")
	picker.tuning.get_child(3).pressed.emit()

	picker.tiles[47].pressed.emit()
	check(settings.visualizer_preset == 47 and picker.selected.text == "Terrain Canyon ▾" and picker.gallery.visible, "thumbnail selects scene and keeps gallery open")
	settings.apply("visualizer_preset", 4)
	check(picker.selected.text == "Wave Architecture ▾" and picker.tiles[4].button_pressed and not picker.tiles[47].button_pressed, "picker tracks shortcut changes")
	picker.close()
	picker.selected.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	var chosen: Button = picker.tiles[4]
	check(picker.disabled_button.get_parent() == picker.starred_filter.get_parent() and picker.menu.get_child(0) == picker.disabled_button.get_parent(), "disable and compact starred filter share pinned action row")
	check(is_equal_approx(picker.disabled_button.position.y, picker.starred_filter.position.y) and picker.starred_filter.size.x <= 60.0, "starred filter uses one compact button beside disable")
	check(chosen.global_position.y >= picker.gallery.global_position.y and chosen.global_position.y + chosen.size.y <= picker.gallery.global_position.y + picker.gallery.size.y, "gallery opens with selected scene fully visible")
	var scene_selections := [0]
	picker.scene_selected.connect(func() -> void: scene_selections[0] += 1)
	var star: Button = picker.favorite_buttons[4]
	check(chosen.get_global_rect().encloses(star.get_global_rect()), "star button fits inside preset card")
	var click := InputEventMouseButton.new()
	click.position = star.global_position + star.size * 0.5
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	await process_frame
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	check(star.button_pressed and scene_selections[0] == 0, "star receives pointer click without selecting scene")
	picker.favorite_buttons[18].pressed.emit()
	check(settings.visualizer_favorites == PackedStringArray([settings.VISUALIZER_PRESETS[4], settings.VISUALIZER_PRESETS[18]]), "stars remember preset names")
	check(settings.visualizer_preset == 4 and picker.gallery.visible, "starring preserves selection and open gallery")
	check(desktop.root.scene_picker.favorite_buttons[4].button_pressed and vr.view.scene_picker.favorite_buttons[18].button_pressed, "stars synchronize desktop and VR")
	picker.starred_filter.button_pressed = true
	check(settings.visualizer_starred_only and desktop.root.scene_picker.starred_filter.button_pressed and vr.view.scene_picker.starred_filter.button_pressed, "starred filter is global")
	var visible_count := 0
	for tile: Button in picker.tiles:
		visible_count += int(tile.visible)
	check(visible_count == 2 and picker.tiles[4].visible and picker.tiles[18].visible, "starred filter hides other presets")
	if "--preview" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/vpx_starred_picker.png")
	player.current_path = "test.flac"
	desktop.root.next_style_button.pressed.emit()
	check(settings.visualizer_preset == 18, "desktop next button skips unstarred presets")
	vr.view.previous_style_button.pressed.emit()
	check(settings.visualizer_preset == 4, "VR previous button skips unstarred presets")
	main._step_action(settings.StickAction.FORMAT_ALL, 1)
	check(settings.visualizer_preset == 18, "forward shortcut skips unstarred presets")
	main._step_action(settings.StickAction.FORMAT_ALL, 1)
	check(settings.visualizer_preset == 4, "forward shortcut wraps starred presets")
	main._step_action(settings.StickAction.FORMAT_ALL, -1)
	check(settings.visualizer_preset == 18, "backward shortcut wraps starred presets")
	var field = load("res://scripts/resonance_field.gd").new()
	field.preset_elapsed = 95.0
	field.cycle_preset()
	check(settings.visualizer_preset == 4 and field.preset_elapsed == 0.0, "automatic scene cycling follows starred filter")
	field.free()
	settings.apply("visualizer_preset", 10)
	settings.cycle_visualizer_preset(-1)
	check(settings.visualizer_preset == 4, "cycling from unstarred preset finds nearest favorite")
	check(settings.flush() == OK, "favorite settings save successfully")
	settings.visualizer_favorites = PackedStringArray()
	settings.visualizer_starred_only = false
	settings.load_config()
	settings.changed.emit()
	check(settings.visualizer_starred_only and settings.visualizer_favorites.size() == 2 and picker.favorite_buttons[4].button_pressed, "favorites and filter restore from disk")
	var backup_path := "user://visualizer_favorites_backup.cfg"
	var backup = load("res://scripts/settings_backup.gd")
	check(backup.export_settings(backup_path).ok and backup.import_settings(backup_path).ok, "favorites survive settings backup round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	picker.favorite_buttons[4].pressed.emit()
	check(settings.visualizer_preset == 18 and not picker.tiles[4].visible, "unstarring current preset selects remaining favorite")
	settings.cycle_visualizer_preset(-1)
	check(settings.visualizer_preset == 18, "single favorite stays selected")
	picker.favorite_buttons[18].pressed.emit()
	settings.cycle_visualizer_preset(1)
	settings.cycle_visualizer_preset(-1)
	check(settings.visualizer_preset == 18 and picker.empty_favorites.visible, "empty favorites show guidance and stop cycling")
	picker.starred_filter.button_pressed = false
	check(picker.tiles[0].visible and not picker.empty_favorites.visible, "turning filter off restores all presets")
	settings.cycle_visualizer_preset(1)
	check(settings.visualizer_preset == 19, "unfiltered cycling restores full preset order")
	if "--preview" in OS.get_cmdline_user_args():
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/vpx_picker.png")
	host.queue_free()
	desktop.free()
	vr.free()
	main.panel.free()
	main.ui.free()
	main.free()
	player.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_path))
	await process_frame
	print("RESULT failures=", failures)
	quit(1 if failures else 0)
