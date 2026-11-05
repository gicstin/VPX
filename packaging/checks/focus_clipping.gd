extends SceneTree

var failures := 0
var checked := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func _reach(control: Control) -> float:
	var reach := 0.0
	for state in ["focus", "hover"]:
		var box := control.get_theme_stylebox(state) if control.has_theme_stylebox(state) else null
		if box is StyleBoxFlat:
			var flat := box as StyleBoxFlat
			reach = maxf(reach, maxf(maxf(flat.expand_margin_left, flat.expand_margin_right), maxf(flat.expand_margin_top, flat.expand_margin_bottom)))
	return reach


func _clipper(control: Control) -> Control:
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and (parent.clip_contents or parent is ScrollContainer):
			return parent
		parent = parent.get_parent()
	return null


func _scan(node: Node, page: String, offenders: Array[String]) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is Button or node is Range:
		var control := node as Control
		var clip := _clipper(control)
		if clip != null:
			checked += 1
			var reach := _reach(control)
			var inner := clip.get_global_rect()
			var rect := control.get_global_rect().grow(reach)
			if rect.position.x < inner.position.x - 0.5 or rect.end.x > inner.end.x + 0.5:
				offenders.append("%s: %s (%s) inside %s" % [page, control.name, control.theme_type_variation, clip.name])
	for child in node.get_children():
		_scan(child, page, offenders)


func _run() -> void:
	create_timer(60).timeout.connect(func() -> void: printerr("FAIL: test timeout"); quit(2))
	var settings := root.get_node("Settings")
	settings.hide_menu_on_play = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var ui: Control = main.get_node("UIViewport/UI")
	for combo in [[1.0, 1.0], [0.8, 1.0], [1.25, 1.5]]:
		settings.apply("ui_size", combo[0])
		settings.apply("text_size", combo[1])
		for page in ui.pages.get_children():
			ui.show_page(page)
			for i in 20:
				await process_frame
			var offenders: Array[String] = []
			_scan(ui, page.name, offenders)
			check(offenders.is_empty(), "focus and hover outlines stay inside their scroll area on %s at ui %.2f text %.1f %s" % [page.name, combo[0], combo[1], offenders.slice(0, 3)])
	for tab in ui.quick.TABS.size():
		ui.open_quick(tab)
		for i in 20:
			await process_frame
		var offenders: Array[String] = []
		_scan(ui, "quick %s" % ui.quick.TABS[tab][0], offenders)
		check(offenders.is_empty(), "focus and hover outlines stay inside their scroll area on quick panel %s %s" % [ui.quick.TABS[tab][0], offenders.slice(0, 3)])
	ui.show_main()
	ui.show_page(ui.pages.get_node("System"))
	for i in 20:
		await process_frame
	var focus_target: Button
	var view: Rect2 = ui.page_scroll.get_global_rect()
	for node in ui.pages.get_node("System").find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.focus_mode != Control.FOCUS_NONE and button.get_global_rect().end.y > view.end.y - 20.0:
			focus_target = button
			break
	check(focus_target != null, "a focusable control lies under the bottom fade")
	if focus_target != null:
		focus_target.grab_focus()
		for i in 12:
			await process_frame
		check(focus_target.get_global_rect().end.y <= view.end.y - 35.0, "focused control moves clear of the bottom fade")
	ui.show_page(ui.pages.get_node(NodePath(ui.MEDIA_PAGE)))
	var picker: Control = ui.pages.get_node(NodePath(ui.MEDIA_PAGE)).find_child("SoundVisualizer", true, false)
	picker.selected.button_pressed = true
	picker._toggle_gallery()
	for i in 20:
		await process_frame
	var gallery_offenders: Array[String] = []
	_scan(picker, "visualizer gallery", gallery_offenders)
	check(gallery_offenders.is_empty(), "focus and hover outlines stay inside the visualizer gallery %s" % [gallery_offenders.slice(0, 3)])
	ui.tabs.get_node("SettingsSearch").pressed.emit()
	for i in 20:
		await process_frame
	var search_offenders: Array[String] = []
	_scan(ui, "settings search", search_offenders)
	check(search_offenders.is_empty(), "focus and hover outlines stay inside the settings search results %s" % [search_offenders.slice(0, 3)])
	check(checked > 100, "clipping scan covered %d controls" % checked)
	quit(1 if failures else 0)
