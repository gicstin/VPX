extends SceneTree

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1


func frames(count := 3) -> void:
	for frame in count:
		await process_frame


func hover(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	viewport.push_input(motion, true)
	await frames()
	await create_timer(0.65).timeout
	await frames()


func run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(2))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var button := Button.new()
	button.position = Vector2(480, 260)
	button.size = Vector2(140, 60)
	button.tooltip_text = "Custom tooltip with a long description that must wrap inside the viewport."
	viewport.add_child(button)
	await frames()
	var overlay := viewport.get_node("TooltipOverlay")
	viewport.notify_mouse_entered()
	await hover(viewport, Vector2(550, 290))
	check(overlay.panel.visible, "hover shows custom tooltip")
	check(overlay.content.text == button.tooltip_text, "tooltip reads current control text")
	check(overlay.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and overlay.content.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tooltip does not intercept pointer input")
	check(Rect2(Vector2.ZERO, Vector2(640, 360)).encloses(overlay.panel.get_global_rect()), "tooltip fits near viewport edges")
	check(viewport.get_embedded_subwindows().is_empty(), "tooltip creates no popup window")
	var click := InputEventMouseButton.new()
	click.position = Vector2(550, 290)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	viewport.push_input(click, true)
	await frames()
	check(not overlay.panel.visible, "click dismisses tooltip")
	click.pressed = false
	viewport.push_input(click, true)
	await hover(viewport, Vector2(560, 290))
	check(overlay.panel.visible, "movement restores tooltip after click")
	button.tooltip_text = "Changed tooltip"
	await create_timer(0.65).timeout
	await frames()
	check(overlay.content.text == "Changed tooltip", "dynamic text replaces previous content")
	VpxTheme.set_text_size(1.5, root)
	await create_timer(0.65).timeout
	await frames()
	check(overlay.content.get_theme_font_size("font_size") == roundi(VpxTheme.SMALL_FONT_SIZE * 1.5), "tooltip follows text size setting")
	var popup := PopupPanel.new()
	viewport.add_child(popup)
	popup.popup(Rect2i(100, 100, 100, 100))
	await frames()
	check(not overlay.panel.visible, "opening a popup dismisses tooltip")
	popup.hide()
	await hover(viewport, Vector2(550, 290))
	button.hide()
	await frames()
	check(not overlay.panel.visible, "hidden source dismisses tooltip")
	button.show()
	await hover(viewport, Vector2(550, 290))
	viewport.notify_mouse_exited()
	await frames()
	check(not overlay.panel.visible, "pointer exit dismisses tooltip")
	button.queue_free()
	var tabs := TabBar.new()
	tabs.position = Vector2(20, 20)
	tabs.add_tab("Library")
	tabs.set_tab_tooltip(0, "Library folder path")
	viewport.add_child(tabs)
	viewport.notify_mouse_entered()
	await frames()
	await hover(viewport, tabs.position + tabs.get_tab_rect(0).get_center())
	check(overlay.panel.visible and overlay.content.text == "Library folder path", "tab-specific tooltips use shared renderer")
	tabs.queue_free()
	var tile: Button = load("res://scripts/visualizer_picker.gd").SceneTile.new()
	tile.position = Vector2(480, 260)
	tile.size = Vector2(140, 60)
	tile.tooltip_text = "Visualizer\n" + "A long visualizer description · ".repeat(40)
	viewport.add_child(tile)
	await hover(viewport, Vector2(550, 290))
	check(overlay.panel.visible and overlay.content is ScrollContainer, "visualizer tooltip uses custom content inside shared renderer")
	check(Rect2(Vector2.ZERO, Vector2(640, 360)).encloses(overlay.panel.get_global_rect()), "long visualizer guide stays within viewport")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		viewport.get_texture().get_image().save_png("/tmp/vpx-tooltip-preview.png")
	VpxTheme.set_text_size(1.0, root)
	viewport.free()
	root.size = Vector2i(1920, 1080)
	root.grab_focus()
	var music_layer := CanvasLayer.new()
	music_layer.layer = 12
	root.add_child(music_layer)
	var controls = load("res://scripts/music_controls.gd").new()
	music_layer.add_child(controls)
	controls.position = Vector2(20, 20)
	controls.scale = Vector2.ONE * 2.0
	controls.size = controls.wanted_size()
	controls._refresh_volume()
	await frames()
	var native_texts: Array[String] = []
	for control: Control in controls.find_children("*", "Control", true, false):
		if not control.tooltip_text.is_empty():
			native_texts.append(control.tooltip_text)
	check(native_texts.is_empty(), "entire mini player subtree has no native tooltip text: " + str(native_texts))
	var desktop_overlay := root.get_node("TooltipOverlay")
	var tooltips := root.get_node("Tooltips")
	await hover(root, controls.cover_button.get_global_rect().get_center())
	check(desktop_overlay.panel.visible and desktop_overlay.content.text == "Collapse music player", "desktop mini player uses custom overlay")
	check(desktop_overlay.panel.scale.is_equal_approx(controls.scale), "desktop tooltip follows mini player display scale")
	check(is_equal_approx(desktop_overlay.content.get_theme_font_size("font_size") * desktop_overlay.panel.scale.x, VpxTheme.SMALL_FONT_SIZE * 2.0), "desktop tooltip font renders at the player scale")
	check(controls.cover_button.get_tooltip().is_empty(), "mini player has no native tooltip text")
	await hover(root, controls.volume_button.get_global_rect().get_center())
	check(desktop_overlay.panel.visible and desktop_overlay.content.text == tooltips.get_text(controls.volume_button), "mini player volume tooltip uses custom text")
	check(controls.volume_button.get_tooltip().is_empty(), "dynamic volume tooltip cannot spawn a native popup")
	tooltips.set_text(controls.volume_button, "Updated mini player volume")
	await create_timer(0.65).timeout
	await frames()
	check(desktop_overlay.content.text == "Updated mini player volume", "mini player updates tooltip without native fallback")
	check(root.get_visible_rect().encloses(desktop_overlay.panel.get_global_rect()), "scaled desktop tooltip stays inside window")
	controls.rows.hide()
	controls.preview_button.show()
	controls.panel.add_theme_stylebox_override("panel", VpxTheme.flat(VpxTheme.OVERLAY, 18, 0, 0))
	controls.custom_minimum_size = Vector2.ONE * controls.PREVIEW_SIZE
	controls.size = Vector2.ONE * controls.PREVIEW_SIZE
	tooltips.set_text(controls.preview_button, "Expand music player · Test track")
	await frames()
	await hover(root, controls.preview_button.get_global_rect().get_center())
	check(desktop_overlay.panel.visible and desktop_overlay.content.text == "Expand music player · Test track", "collapsed mini player uses custom tooltip")
	check(controls.preview_button.get_tooltip().is_empty(), "collapsed mini player has no native tooltip text")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/vpx-mini-tooltip-preview.png")
	music_layer.free()
	await frames()
	print("tooltip checks: %s" % ("PASS" if failures == 0 else "%d FAIL" % failures))
	quit(1 if failures else 0)
