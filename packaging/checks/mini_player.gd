extends SceneTree

var failures := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:
		failures += 1


func frames(count := 8) -> void:
	for frame in count:
		await process_frame


func key(code: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()


func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	if control.get_viewport() == main.ui_viewport:
		var rect: Rect2 = main.desktop_view.menu_rect.get_rect()
		point = rect.position + point / Vector2(main.ui_viewport.size_2d_override) * rect.size
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await frames(2)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("/tmp/vpx-mini-" + name + ".png")


func _run() -> void:
	if not load("res://packaging/checks/isolated_data.gd").verify():
		quit(2)
		return
	create_timer(80).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.prefer_desktop = true
	settings.resume_playback = false
	settings.hide_menu_on_play = false
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	check(main.desktop_mode, "mini player belongs to desktop mode")
	var mini = main.desktop_view.mini_player
	check(not mini.active and not mini.visible, "normal startup keeps full window")
	check(main.ui.find_child("MiniPlayerButton", true, false) == null, "sidebar has no mini-player entry")
	check(main.desktop_view.mini_button.icon != null and main.desktop_view.mini_button.text.is_empty(), "mini-player entry is one icon button")
	check(main.desktop_view.mini_button.get_parent() == main.ui.get_node("%VolumeLabel").get_parent() and main.desktop_view.mini_button.get_index() == main.ui.get_node("%VolumeLabel").get_index() + 1, "desktop launch button sits after volume controls")
	var session = main.window_session
	if DisplayServer.get_name() == "headless":
		check(not await session.enter_mini(), "headless window cannot enter native mini mode")
		main.free()
		quit(1 if failures else 0)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 640))
	await frames(20)
	session.capture()
	var bounds: Rect2i = session.state["bounds"]
	var menu_open: bool = main.panel.is_open()
	await capture("launch")
	await click(main.desktop_view.mini_button)
	await frames(20)
	check(mini.active and mini.visible and root.borderless, "mini mode opens borderless compact window")
	check(DisplayServer.window_get_size().x / mini.ui_factor < 640, "mini mode bypasses full window minimum width")
	check(root.get_visible_rect().size == Vector2(DisplayServer.window_get_size()), "mini canvas follows compact native window size")
	check(is_equal_approx(mini.ui_factor, mini.UI_SCALE * settings.ui_size * settings.text_size) and is_equal_approx(mini.ui_factor, 1.6), "mini controls use stable readable scale")
	check(root.unresizable and root.min_size == root.max_size, "mini window has fixed native dimensions")
	check(mini.artwork.size == Vector2(mini.ART_SIZE, mini.ART_SIZE), "album artwork gets a large square area")
	check(absf(float(root.size.x) / root.size.y - mini.GOLDEN_RATIO) < 0.005, "mini window uses golden-ratio proportions")
	check(mini.pin_button.position.y < mini.progress.position.y and mini.more_button.position.y == mini.pin_button.position.y, "window actions group above stationary bottom timeline")
	check(main.desktop_view.mini_button.size == Vector2(60, 60), "launch button matches existing UI button size")
	check(not mini.play_button.visible and not mini.transport_overlay.visible, "transport stays hidden away from artwork")
	check(mini.spectrum_button.position.y < mini.progress.position.y, "visualizer selection sits in grouped bottom toolbar")
	check(not main.photo_bar.root.visible and not main.desktop_view.menu_rect.visible, "full interface hides in mini mode")
	check(root.disable_3d and not main.resonance_field.is_processing(), "music mini suspends 3D rendering and scene animation")
	check(session.state["bounds"] == bounds, "mini polling preserves normal window bounds")
	for button in [mini.pin_button, mini.restore_button, mini.previous_button, mini.play_button, mini.next_button, mini.mute_button]:
		check(button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER and button.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER, "mini icon centers in button: " + str(button.get_meta("mini_icon")))
		check(button.get_theme_stylebox("disabled").get_content_margin(SIDE_LEFT) == 0, "disabled button keeps centered padding: " + str(button.get_meta("mini_icon")))
	check(mini.hint.visible and mini.hint_remaining > 0, "first compact entry explains hover and keyboard controls")
	await capture("first-use")
	await key(KEY_TAB)
	check(not mini.hint.visible and bool(session.state.get("mini_controls_hint_seen", false)), "using keyboard dismisses and remembers first-use hint")
	await capture("empty")
	var pinned: bool = root.always_on_top
	await click(mini.pin_button)
	check(root.always_on_top != pinned, "pin button toggles native always-on-top state")
	await mini.leave()
	await frames(20)
	check(not mini.active and not root.borderless and not root.disable_3d and not root.unresizable and root.max_size == session.mini_restore["maximum"], "restore returns window chrome and renderer")
	check(DisplayServer.window_get_size() == bounds.size, "restore returns exact normal window size")
	check(DisplayServer.window_get_position() == bounds.position, "restore returns exact normal window position")
	check(main.panel.is_open() == menu_open, "restore returns previous menu state")
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 44100
	var samples := PackedByteArray()
	var second := PackedByteArray()
	second.resize(44100 * 2)
	for sample in 44100:
		second.encode_s16(sample * 2, int(sin(TAU * 220.0 * sample / 44100.0) * 11000))
	for second_index in 120:
		samples.append_array(second)
	audio.data = samples
	var path := "user://02 Prophecy at 1420MHz — Live Session with a Very Long Descriptive Title that Continues Beyond the Visible Two Line Area.wav"
	audio.save_to_wav(path)
	var tagged := ProjectSettings.globalize_path("user://tagged.wav")
	check(OS.execute("ffmpeg", ["-v", "error", "-y", "-i", ProjectSettings.globalize_path(path), "-metadata", "title=" + path.get_file().get_basename(), "-metadata", "artist=Boards of Canada", "-metadata", "album=Inferno", "-c:a", "copy", tagged]) == 0, "tagged local audio fixture generated")
	DirAccess.rename_absolute(tagged, ProjectSettings.globalize_path(path))
	check(await main.player.open(ProjectSettings.globalize_path(path)), "audio fixture opens")
	main.player.paused = false
	await frames(10)
	var cover := Image.new()
	cover.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><defs><linearGradient id="sky" x2="0" y2="1"><stop stop-color="#47244f"/><stop offset="1" stop-color="#111f38"/></linearGradient><linearGradient id="sun" x2="0" y2="1"><stop stop-color="#ffd296"/><stop offset="1" stop-color="#e56979"/></linearGradient></defs><rect width="512" height="512" fill="url(#sky)"/><circle cx="256" cy="211" r="117" fill="url(#sun)"/><path d="M0 356 140 230 245 356 367 264 512 356V512H0" fill="#151b35"/><path d="M0 410 172 310 304 410 406 344 512 410V512H0" fill="#0b1426"/><path d="m224 512 23-146h18l23 146" fill="#79c9d3" opacity=".7"/><path d="M256 381v18m0 24v25m0 29v35" stroke="#ecf6f2" stroke-width="4"/><circle cx="70" cy="76" r="2" fill="#d8e6ef"/><circle cx="420" cy="113" r="2" fill="#d8e6ef"/></svg>')
	root.get_node("MediaInfo").textures[ProjectSettings.globalize_path(path)] = ImageTexture.create_from_image(cover)
	settings.apply("music_visualizer_mode", 2)
	await key(KEY_M, true, true)
	await frames(15)
	check(mini.active, "Ctrl+Shift+M opens mini mode")
	var position: float = main.player.stream_position
	await create_timer(0.3).timeout
	check(main.player.stream_position > position, "playback continues across mini transition")
	await key(KEY_SPACE)
	check(main.player.paused, "Space pauses music in mini mode")
	await click(mini.play_button)
	check(not main.player.paused, "transport resumes same playback")
	mini.progress.value = 40
	mini.progress.drag_ended.emit(true)
	check(main.player.stream_position >= 39, "mini seek uses existing playback")
	settings.apply("volume", 60)
	mini.volume.value = 35
	check(settings.volume == 35, "mini volume updates shared audio setting")
	mini.mute_button.pressed.emit()
	check(settings.muted, "mini mute updates shared audio setting")
	mini.mute_button.pressed.emit()
	await frames()
	await frames(25)
	check(main.music_visualizer.analysing and main.music_visualizer.capturing, "mini oscilloscope captures live audio")
	check(mini.spectrum.visible and mini.spectrum.wave.size() > 10, "mini oscilloscope receives real waveform samples")
	check(mini.spectrum.wave.size() > 0 and Array(mini.spectrum.wave).max() > 0.01, "waveform reacts to fixture audio")
	check(mini.artwork.texture != null and mini.artwork.visible, "large album art uses media artwork")
	check(mini.details.text == "Boards of Canada\nInferno" and mini.details.visible, "local artist and album appear above technical metadata")
	check(mini.details.get_global_rect().end.y <= mini.quality.get_global_rect().position.y, "artist and album remain clear of technical metadata")
	check(mini.title.get_line_count() >= 2, "long track title exercises wrapped layout")
	check(mini.title_clip.get_global_rect().end.y <= mini.quality.get_global_rect().position.y, "title viewport clears media format row")
	check("WAV" in mini.quality.text and "kbps" in mini.quality.text and "kHz" in mini.quality.text, "media format, average bitrate and sample rate are shown")
	check(mini.title_scroll_distance > 0 and mini.title_clip.clip_contents, "long titles retain full text in scrolling viewport")
	mini.title_scroll_time = 2.8
	mini._scroll_title()
	check(mini.title.position.y < 0, "overflowing title scrolls after reading pause")
	mini.title_scroll_time = 0
	mini._scroll_title()
	check(mini.spectrum.position.y >= mini.metadata.position.y + mini.metadata.size.y + 10, "visualizer clears metadata block")
	check(mini.spectrum.get_rect().end.y < mini.progress.position.y, "visualizer clears timeline")
	var away := InputEventMouseMotion.new()
	away.position = Vector2(10, root.size.y - 10)
	Input.parse_input_event(away)
	await frames()
	await create_timer(0.16).timeout
	check(not mini.play_button.visible and not mini.transport_overlay.visible, "transport fades out when pointer leaves artwork")
	await capture("music")
	RenderingServer.force_draw()
	var rounded := root.get_texture().get_image()
	var charcoal := rounded.get_pixel(10, 100)
	check(absf(charcoal.r - charcoal.g) < 0.003 and absf(charcoal.g - charcoal.b) < 0.003, "float background uses neutral charcoal")
	check(rounded.get_pixel(0, 0).a < 0.05 and rounded.get_pixel(30, 30).a > 0.95, "rounded float corners are genuinely transparent")
	check(root.transparent and root.transparent_bg, "mini mode enables native window transparency")
	check(is_equal_approx(mini.pin_button.position.x - mini.fade_button.position.x, 40) and mini.fade_button.position.y == mini.pin_button.position.y, "idle opacity toggle groups beside pin button")
	check(mini.favorite_button.is_visible_in_tree(), "favourite action is available beside expanded song title")
	check(mini.title_clip.get_global_rect().end.x <= mini.favorite_button.get_global_rect().position.x, "favourite button does not overlap title")
	await click(mini.favorite_button)
	check(root.get_node("Library").is_favorite(ProjectSettings.globalize_path(path)) and mini.favorite_button.button_pressed, "title favourite action updates shared library")
	var active_art_bounds: Rect2 = mini.artwork.get_rect()
	var active_title_height: float = mini.title_clip.size.y
	var active_scope_end: float = mini.spectrum.get_rect().end.y
	var seek_bounds: Rect2 = mini.progress.get_rect()
	var time_bounds: Rect2 = mini.clock.get_rect()
	var duration_bounds: Rect2 = mini.duration.get_rect()
	root.mouse_exited.emit()
	await create_timer(2.3).timeout
	check(not mini.pin_button.visible and not mini.spectrum_button.visible and not mini.cover_button.visible, "secondary toolbar hides after pointer leaves float")
	check(mini.progress.visible and mini.clock.visible and mini.duration.visible, "timeline and timestamps stay visible while idle")
	check(mini.progress.get_rect() == seek_bounds and mini.clock.get_rect() == time_bounds and mini.duration.get_rect() == duration_bounds, "idle toolbar never moves timeline or timestamps")
	check(not root.get_node("TooltipOverlay").panel.visible, "idle float dismisses tooltips when pointer leaves window")
	check(mini.artwork.size.x > active_art_bounds.size.x + 45 and is_equal_approx(mini.artwork.size.x, mini.artwork.size.y), "idle artwork expands into hidden toolbar space without cropping its square")
	check(mini.title_clip.size.y > active_title_height + 15, "idle title gains another readable line")
	check(mini.spectrum.get_rect().end.y > active_scope_end + 45 and mini.spectrum.get_rect().end.y < mini.progress.position.y, "idle visualizer fills freed height while clearing fixed timeline")
	check(mini.metadata.position.x >= mini.artwork.get_rect().end.x + 20 and mini.metadata.get_rect().end.x <= mini.size.x - 19, "expanded artwork and metadata keep clean separate columns")
	await capture("quiet")
	var toolbar_hover := InputEventMouseMotion.new()
	toolbar_hover.position = Vector2(root.size.x - 30, root.size.y - 30)
	Input.parse_input_event(toolbar_hover)
	await frames()
	check(mini.cover_button.visible and mini.pin_button.visible, "float hover immediately restores toolbar controls")
	check(mini.artwork.get_rect() == active_art_bounds and mini.spectrum.get_rect().end.y <= mini.more_button.position.y, "hover restores content before toolbar can overlap artwork or visualizer")
	await click(mini.fade_button)
	check(mini.idle_fade, "idle transparency toggle enables fading")
	root.mouse_exited.emit()
	await create_timer(0.8).timeout
	RenderingServer.force_draw()
	var faded := root.get_texture().get_image()
	check(absf(mini.current_opacity - 0.4) < 0.01, "whole float fades to 40 percent opacity away from pointer")
	check(absf(faded.get_pixel(10, 80).a - 0.4) < 0.03, "native framebuffer alpha follows idle opacity")
	await capture("idle")
	var inside := InputEventMouseMotion.new()
	inside.position = Vector2(root.size.x - 30, root.size.y - 30)
	Input.parse_input_event(inside)
	await create_timer(0.4).timeout
	check(mini.current_opacity > 0.99, "hover anywhere over float restores full opacity")
	await mini.leave()
	await frames()
	check(root.transparent == session.mini_restore["transparent"] and root.transparent_bg == session.mini_restore["transparent_bg"], "full window restores previous transparency flags")
	await mini.enter()
	await frames()
	check(mini.idle_fade, "idle opacity preference survives full-player round trip")
	await click(mini.fade_button)
	await create_timer(0.4).timeout
	check(not mini.idle_fade and mini.current_opacity > 0.99, "turning idle mode off keeps float opaque")
	var hover := InputEventMouseMotion.new()
	hover.position = mini.artwork.get_global_rect().get_center()
	Input.parse_input_event(hover)
	await create_timer(0.04).timeout
	check(mini.hover_alpha > 0 and mini.hover_alpha < 1, "artwork controls fade in through intermediate opacity")
	await create_timer(0.13).timeout
	check(is_equal_approx(mini.hover_alpha, 1), "artwork controls settle at full opacity")
	await frames()
	check(mini.play_button.visible and mini.transport_overlay.visible, "artwork hover reveals transport overlay")
	check(mini.artwork.get_global_rect().encloses(mini.play_button.get_global_rect()), "play button stays within artwork")
	await capture("hover")
	root.mouse_exited.emit()
	await create_timer(0.16).timeout
	check(not mini.play_button.visible, "leaving native window clears artwork hover")
	await click(mini.play_button)
	check(main.player.paused, "hover playback button pauses without dragging window")
	await click(mini.play_button)
	check(not main.player.paused, "hover playback button resumes")
	await click(mini.spectrum_button)
	check(mini.visualizer_menu.visible, "visualizer button opens explicit mode choices")
	await click(mini.more_button)
	check(mini.window_menu.visible and not mini.visualizer_menu.visible, "opening window actions dismisses visualizer choices")
	await click(mini.spectrum_button)
	check(mini.visualizer_menu.visible and not mini.window_menu.visible, "opening visualizer choices dismisses window actions")
	check(mini.visualizer_options[2].modulate != mini.visualizer_options[0].modulate, "visualizer choices distinguish selected mode")
	await click(mini.visualizer_options[0])
	await frames(20)
	check(mini.visualizer_mode == 0 and not mini.spectrum.visible, "visualizer toggle includes Disabled")
	check(not main.music_visualizer.analysing and not main.music_visualizer.capturing, "Disabled stops compact audio analysis and capture")
	await create_timer(0.16).timeout
	check(not mini.play_button.visible, "bottom-bar interaction keeps transport hidden")
	await capture("disabled")
	await mini.leave()
	await frames()
	await mini.enter()
	await frames()
	check(mini.visualizer_mode == 0 and not mini.spectrum.visible and not main.music_visualizer.analysing, "Disabled mode survives full-player round trip")
	await click(mini.spectrum_button)
	await click(mini.visualizer_options[1])
	await frames(20)
	check(mini.visualizer_mode == 1 and settings.music_visualizer_mode == 0 and not mini.spectrum.oscilloscope, "visualizer toggle enables spectrum after Disabled")
	check(mini.spectrum.levels.size() > 0 and Array(mini.spectrum.levels).max() > 0.01, "spectrum reacts to fixture audio")
	await capture("spectrum")
	await click(mini.spectrum_button)
	await capture("visualizer-menu")
	await click(mini.visualizer_options[2])
	await frames(20)
	check(mini.visualizer_mode == 2 and settings.music_visualizer_mode == 2 and mini.spectrum.oscilloscope, "visualizer toggle selects oscilloscope directly")
	check(mini.progress.size.x > 300 and mini.volume.size.x >= 80, "timeline and volume fit compact layout")
	await click(mini.more_button)
	check(mini.window_menu.visible and mini.minimize_button.is_visible_in_tree() and mini.close_button.is_visible_in_tree(), "overflow groups Minimize and Quit away from routine controls")
	await capture("window-menu")
	await key(KEY_ESCAPE)
	check(mini.active and not mini.window_menu.visible, "Escape dismisses window actions before leaving mini mode")
	await key(KEY_TAB)
	check(mini.keyboard_mode and mini.play_button.has_focus() and mini.play_button.visible, "Tab reveals artwork controls and focuses primary playback action")
	check(mini.play_button.get_theme_stylebox("focus").border_width_left == 2, "keyboard controls have visible focus outlines")
	await key(KEY_SPACE)
	check(main.player.paused, "focused playback activates with Space")
	await key(KEY_ENTER)
	check(not main.player.paused, "focused playback activates with Enter")
	mini.favorite_button.grab_focus()
	var favorite_before: bool = mini.favorite_button.button_pressed
	await key(KEY_SPACE)
	check(mini.favorite_button.button_pressed != favorite_before and not main.player.paused, "focused favourite activates without toggling playback")
	await key(KEY_SPACE)
	mini.spectrum_button.grab_focus()
	await key(KEY_ENTER)
	check(mini.visualizer_menu.visible and mini.visualizer_options[2].has_focus(), "keyboard opens visualizer choices focused on current mode")
	await key(KEY_UP)
	check(mini.visualizer_options[1].has_focus(), "arrow keys move through visualizer choices")
	await key(KEY_ESCAPE)
	check(mini.active and mini.spectrum_button.has_focus(), "Escape closes choices and returns keyboard focus to trigger")
	root.focus_exited.emit()
	check(not mini.keyboard_mode and not mini.visualizer_menu.visible and not mini.play_button.has_focus(), "switching apps clears keyboard reveal and transient menus")
	await key(KEY_TAB)
	mini.volume.grab_focus()
	mini.volume.value = 50
	await key(KEY_LEFT)
	check(settings.volume == 45, "focused volume slider responds to arrow keys")
	await key(KEY_TAB, false, true)
	check(mini.mute_button.has_focus(), "Shift+Tab follows logical reverse focus order")
	check(mini.progress.position.y > mini.more_button.get_rect().end.y and mini.progress.get_rect().end.y > mini.size.y - 24, "timeline anchors bottom without empty idle strip beneath it")
	var expanded_size: Vector2i = root.size
	var motion_position_before: float = main.player.stream_position
	mini._toggle_cover()
	check(mini.cover_mode and root.size == Vector2i((Vector2.ONE * mini.COVER_SIZE * mini.ui_factor).round()) and root.min_size == root.max_size, "mini-to-nano switches instantly to locked nano dimensions")
	await frames()
	await capture("switch-to-nano")
	mini._toggle_cover()
	check(not mini.cover_mode and root.size == expanded_size and root.min_size == root.max_size, "nano-to-mini switches instantly to locked mini dimensions")
	await frames()
	check(main.player.stream_position > motion_position_before and main.player.is_playing(), "mode switch preserves continuous playback")
	await capture("switch-to-mini")
	mini._toggle_cover()
	await mini.leave()
	check(not session.mini_transition and not mini.active, "restoring full player from nano is clean")
	await mini.enter()
	await frames()
	mini._toggle_cover()
	await frames()
	check(not mini.cover_mode and root.size == expanded_size, "reentering compact mode restores mini dimensions")
	var pinned_before: bool = root.always_on_top
	var fade_before: bool = mini.idle_fade
	var position_before: float = main.player.stream_position
	await click(mini.cover_button)
	await frames(15)
	check(mini.cover_mode and root.size.x == root.size.y and root.size.x < expanded_size.x, "Cover mode opens a smaller square window")
	check(root.unresizable and root.min_size == root.max_size, "Cover mode keeps fixed native dimensions")
	check(main.player.stream_position > position_before and main.player.is_playing(), "entering Cover mode keeps playback running")
	check(root.disable_3d and not main.music_visualizer.analysing, "Cover mode suspends hidden rendering and visualizer analysis")
	root.mouse_exited.emit()
	await create_timer(0.16).timeout
	check(mini.artwork.visible and not mini.metadata.is_visible_in_tree() and not mini.play_button.visible and not mini.volume.visible, "idle Cover mode shows only artwork")
	check(not mini.progress.visible and not mini.close_button.is_visible_in_tree(), "Cover mode omits timeline and accidental quit action")
	await capture("cover")
	await key(KEY_TAB)
	check(mini.keyboard_mode and mini.play_button.has_focus() and mini.volume.visible and mini.favorite_button.is_visible_in_tree(), "nano keyboard navigation reveals all essential controls without mouse hover")
	await capture("cover-keyboard")
	await key(KEY_C, true, true)
	check(not mini.cover_mode and mini.play_button.has_focus(), "keyboard expansion retains primary control focus")
	await key(KEY_C, true, true)
	check(mini.cover_mode and mini.play_button.has_focus(), "keyboard nano transition retains primary control focus")
	var cover_hover := InputEventMouseMotion.new()
	cover_hover.position = Vector2(root.size) * 0.5
	Input.parse_input_event(cover_hover)
	await frames()
	check(mini.play_button.visible and mini.volume.visible and mini.cover_button.visible, "Cover hover reveals playback, volume and expand controls")
	check(mini.details.text == "Boards of Canada" and mini.details.is_visible_in_tree(), "nano hover prioritizes artist alongside title")
	check(mini.favorite_button.is_visible_in_tree() and mini.favorite_button.button_pressed, "Cover mode shares expanded favourite state")
	await capture("cover-hover")
	await click(mini.favorite_button)
	check(not root.get_node("Library").is_favorite(ProjectSettings.globalize_path(path)), "Cover favourite button removes shared favourite")
	await click(mini.favorite_button)
	check(root.get_node("Library").is_favorite(ProjectSettings.globalize_path(path)), "Cover favourite button adds shared favourite")
	mini.volume.value = 42
	check(settings.volume == 42, "Cover volume controls shared output")
	await click(mini.play_button)
	check(main.player.paused, "Cover transport pauses playback")
	await click(mini.play_button)
	check(not main.player.paused, "Cover transport resumes playback")
	await click(mini.cover_button)
	await frames(15)
	check(not mini.cover_mode and root.size == expanded_size, "Cover expand restores golden-ratio float dimensions")
	check(mini.favorite_button.button_pressed and root.always_on_top == pinned_before and mini.idle_fade == fade_before and settings.volume == 42, "Cover round trip preserves favourites, pin, fade and volume")
	check(main.music_visualizer.analysing, "expanding Cover mode resumes visualizer analysis")
	await key(KEY_C, true, true)
	check(mini.cover_mode, "Ctrl+Shift+C enters Cover mode")
	await mini.leave()
	await frames()
	await mini.enter()
	await frames()
	check(mini.cover_mode and root.size.x == root.size.y, "Cover mode preference survives full-player round trip")
	await key(KEY_ESCAPE)
	check(mini.active and not mini.cover_mode and root.size == expanded_size, "Escape expands Cover mode without leaving float")
	settings.apply("immersive_music_visualizer", true)
	await frames()
	await mini.leave()
	await frames()
	check(main.resonance_field.active, "full mode resumes immersive music scene")
	await mini.enter()
	await frames()
	check(not main.resonance_field.active and main.music_visualizer.analysing, "mini mode suspends 3D scene and keeps compact analysis live")
	check(not mini.title.text.is_empty() and mini.title.size.x > 100, "music title has usable layout")
	await key(KEY_ESCAPE)
	check(not mini.active and main.player.is_playing(), "Escape restores without interrupting playback")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	await frames(30)
	await mini.enter()
	await frames(10)
	await mini.leave()
	await frames(30)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED, "maximized state survives mini round trip")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await frames(30)
	await mini.enter()
	await frames(10)
	await mini.leave()
	await frames(30)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen state survives mini round trip")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await frames(20)
	var video := "/tmp/vpx-mini-fixture.mp4"
	if FileAccess.file_exists(video):
		check(await main.player.open(video), "video fixture opens")
		await frames(15)
		await mini.enter()
		await frames(20)
		check(mini.picture and not root.disable_3d, "video mini preserves picture renderer")
		check(not main.resonance_field.active and main.screen.visible, "music-to-video mini transition shows video without immersive world")
		check(absf(DisplayServer.window_get_size().y / mini.ui_factor - mini.VIDEO_HEIGHT) < 1.0, "video mini expands picture area")
		check(mini.metadata.get_rect().end.y < mini.progress.position.y, "video title clears timeline")
		await capture("video")
		check(await main.player.open(ProjectSettings.globalize_path(path)), "music opens while mini stays active")
		await frames(20)
		check(not mini.picture and root.disable_3d, "video-to-music transition suspends renderer")
		check(absf(DisplayServer.window_get_size().y / mini.ui_factor - mini.MUSIC_HEIGHT) < 1.0, "video-to-music transition restores compact height")
		await mini.leave()
		await frames(10)
	check(main.resonance_field.is_processing() and main.music_visualizer.is_processing(), "visualizer processing restores after mini mode")
	main.desktop_mode = false
	await frames()
	check(not main.desktop_view.mini_button.visible, "launch control stays hidden outside desktop mode")
	await mini.enter()
	check(not mini.active and not mini.visible, "VR mode rejects mini-player activation")
	main.desktop_mode = true
	main.player.stop()
	main.free()
	print("RESULT failures=%d" % failures)
	quit(1 if failures else 0)
