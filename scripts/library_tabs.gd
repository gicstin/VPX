extends HBoxContainer

const VIEW_KEYS := ["library_source", "library_view", "library_sort", "library_filter", "library_query", "library_flat_view", "library_favorites_only", "library_unplayed_only"]

var ui
var views: Array[Dictionary] = []
var active := 0
var bar: TabBar
var restore_serial := 0
var pending_scroll := -1


func setup(owner_ui) -> void:
	ui = owner_ui
	name = "LibraryTabs"
	bar = TabBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 48
	bar.max_tab_width = 220
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_changed.connect(select)
	bar.tab_close_pressed.connect(close)
	bar.tab_clicked.connect(func(_index: int) -> void: ui.fling = 0.0)
	bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			var index := bar.get_tab_idx_at_point(event.position)
			if index >= 0:
				close(index)
				bar.accept_event())
	add_child(bar)
	var add := Button.new()
	add.text = "+"
	add.custom_minimum_size = Vector2(48, 48)
	add.tooltip_text = "New Library tab (Ctrl+T)"
	add.pressed.connect(new_tab)
	add_child(add)
	views.append(_snapshot())
	_rebuild()
	ui.file_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void:
		if pending_scroll < 0:
			views[active] = _snapshot()
			_save())


func restore() -> void:
	var session: Dictionary = Settings.library_tab_session
	var saved: Variant = session.get("views", [])
	var restored: Array[Dictionary] = []
	if saved is Array:
		for entry in saved:
			if not entry is Dictionary:
				continue
			var state := _snapshot()
			var valid := true
			for key in state:
				if key == "library_unplayed_only" and not entry.has(key):
					state[key] = false
					continue
				if not entry.has(key) or typeof(entry[key]) != typeof(state[key]):
					valid = false
					break
				state[key] = entry[key]
			for key in ["library_source", "library_view", "library_sort", "library_filter"]:
				var limits := {"library_source": ui.SOURCES.size(), "library_view": Settings.LibraryView.size(), "library_sort": ui.SORTS.size(), "library_filter": ui.FILTERS.size()}
				valid = valid and int(state[key]) >= 0 and int(state[key]) < int(limits[key])
			if valid:
				state["scroll"] = maxi(state["scroll"], 0)
				restored.append(state)
	if restored.is_empty():
		ui.refresh_directory()
		return
	views = restored
	var selected: Variant = session.get("active", 0)
	active = clampi(selected if selected is int else 0, 0, views.size() - 1)
	_activate()


func _save() -> void:
	Settings.library_tab_session = {"views": views.duplicate(true), "active": active}
	Settings.save_config()


func _snapshot() -> Dictionary:
	var state := {"directory": ui.directory, "fallbacks": ui.directory_fallbacks, "scroll": pending_scroll if pending_scroll >= 0 else ui.file_scroll.scroll_vertical, "dlna": ui.dlna_stack.duplicate(true)}
	for key in VIEW_KEYS:
		state[key] = Settings.get(key)
	return state


func capture() -> void:
	views[active] = _snapshot()
	_rebuild()
	_save()


func _rebuild() -> void:
	bar.set_block_signals(true)
	while bar.tab_count > views.size():
		bar.remove_tab(bar.tab_count - 1)
	while bar.tab_count < views.size():
		bar.add_tab("")
	for index in views.size():
		var state := views[index]
		var source: int = state["library_source"]
		var path: String = state["directory"]
		var title: String = path.get_file() if source == Settings.LibrarySource.FOLDER else ui.SOURCE_TITLES[source]
		if title.is_empty():
			title = path
		bar.set_tab_title(index, title)
		bar.set_tab_tooltip(index, (path if source == Settings.LibrarySource.FOLDER else title) + "\nClose tab: Ctrl+W or middle click")
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS if views.size() > 1 else TabBar.CLOSE_BUTTON_SHOW_NEVER
	bar.current_tab = active
	bar.set_block_signals(false)


func new_tab() -> void:
	capture()
	views.append(views[active].duplicate(true))
	select(views.size() - 1)


func select(index: int) -> void:
	if index < 0 or index >= views.size() or index == active:
		return
	capture()
	active = index
	_activate()


func close(index: int) -> void:
	if views.size() <= 1 or index < 0 or index >= views.size():
		return
	capture()
	var was_active := index == active
	views.remove_at(index)
	if index < active:
		active -= 1
	elif active >= views.size():
		active = views.size() - 1
	if was_active:
		_activate()
	else:
		_rebuild()
		_save()


func _activate() -> void:
	var state := views[active].duplicate(true)
	pending_scroll = int(state["scroll"])
	ui.search_timer = -1.0
	ui.drag_armed = false
	ui.drag_active = false
	ui.directory = state["directory"]
	ui.directory_fallbacks = state["fallbacks"]
	ui.dlna_stack.assign(state["dlna"])
	for key in VIEW_KEYS:
		Settings.set(key, state[key])
	Settings.last_directory = ui.directory
	Settings.save_config()
	Settings.changed.emit()
	if Settings.library_source != Settings.LibrarySource.DISCOVER and ui.discovery.directory.busy:
		ui.discovery.directory.cancel()
		ui.discovery.directory.started = false
	ui.refresh_directory()
	_restore_scroll(int(state["scroll"]), ui.paths_serial)


func _restore_scroll(value: int, paths_serial: int) -> void:
	restore_serial += 1
	var serial := restore_serial
	while ui.scan_started_msec >= 0 or is_instance_valid(ui.paths_job):
		await get_tree().process_frame
		if serial != restore_serial:
			return
		if paths_serial != ui.paths_serial:
			pending_scroll = -1
			capture()
			return
	for frame in 2:
		await get_tree().process_frame
		if serial != restore_serial:
			return
		if paths_serial != ui.paths_serial:
			pending_scroll = -1
			capture()
			return
	ui.file_scroll.scroll_vertical = value
	pending_scroll = -1
	capture()


func handle_key(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or not event.is_command_or_control_pressed() or event.alt_pressed:
		return false
	match event.keycode:
		KEY_T:
			new_tab()
		KEY_W:
			close(active)
		KEY_TAB:
			select(posmod(active + (-1 if event.shift_pressed else 1), views.size()))
		_:
			return false
	return true
