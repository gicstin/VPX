extends VBoxContainer

signal results_changed
signal keyboard_requested(text: String)
signal link_requested

const Directory := preload("res://scripts/radio_directory.gd")
const GENRES := ["All genres", "Ambient", "Blues", "Chillout", "Classical", "Country", "Dance", "Electronic", "Jazz", "Metal", "News", "Pop", "Reggae", "Rock", "Soul", "Talk"]
const QUALITIES := [
	["All qualities", {}],
	["Up to 64 kbps", {"bitrateMin": 1, "bitrateMax": 64}],
	["128 kbps", {"bitrateMin": 128, "bitrateMax": 128}],
	["192 kbps", {"bitrateMin": 192, "bitrateMax": 192}],
	["256 kbps", {"bitrateMin": 256, "bitrateMax": 256}],
	["320 kbps", {"bitrateMin": 320, "bitrateMax": 320}],
	["192 kbps+", {"bitrateMin": 192}],
	["FLAC", {"codec": "FLAC"}],
	["MP3", {"codec": "MP3"}],
	["AAC", {"codec": "AAC"}],
	["Opus", {"codec": "OPUS"}],
	["Ogg", {"codec": "OGG"}],
]

var directory := Directory.new()
var field: LineEdit
var genre: OptionButton
var country: OptionButton
var language: OptionButton
var quality: OptionButton
var saved := false
var order := "clickcount"
var mode_buttons: Array[Button] = []


func _ready() -> void:
	add_child(directory)
	directory.changed.connect(results_changed.emit)
	directory.catalogs_changed.connect(_catalogs_changed)
	add_theme_constant_override("separation", 10)
	var search := HBoxContainer.new()
	search.add_theme_constant_override("separation", 10)
	add_child(search)
	field = LineEdit.new()
	field.placeholder_text = "Search stations by name…"
	field.max_length = 100
	field.clear_button_enabled = true
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.custom_minimum_size.y = 52
	field.text_submitted.connect(func(_text: String) -> void: submit())
	search.add_child(field)
	_button(search, "", "keyboard", func() -> void: keyboard_requested.emit(field.text)).tooltip_text = "Type with the on-screen keyboard"
	_button(search, "Search", "search", submit)
	_button(search, "Open stream URL", "link", link_requested.emit)
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 10)
	filters.add_theme_constant_override("v_separation", 8)
	add_child(filters)
	genre = _option(filters, "Genre")
	for name: String in GENRES:
		genre.add_item(name)
	genre.item_selected.connect(func(_index: int) -> void: submit())
	country = _option(filters, "Country")
	country.add_item("All countries")
	country.disabled = true
	country.item_selected.connect(func(_index: int) -> void: submit())
	language = _option(filters, "Language")
	language.add_item("All languages")
	language.disabled = true
	language.item_selected.connect(func(_index: int) -> void: submit())
	quality = _option(filters, "Quality")
	for preset: Array in QUALITIES:
		quality.add_item(preset[0])
		quality.set_item_metadata(quality.item_count - 1, preset[1])
	quality.item_selected.connect(func(_index: int) -> void: submit())
	_button(filters, "Reset", "close", reset)
	var modes := HFlowContainer.new()
	modes.add_theme_constant_override("h_separation", 10)
	modes.add_theme_constant_override("v_separation", 8)
	add_child(modes)
	for entry in [["Popular", "audio", "clickcount"], ["Trending", "recent", "clicktrend"], ["Surprise me", "shuffle", "random"], ["Saved stations", "star_outline", "saved"]]:
		var button := _button(modes, entry[0], entry[1], func() -> void: _mode(entry[2]))
		button.toggle_mode = true
		mode_buttons.append(button)
	_sync_modes()


func ensure_started() -> void:
	if not saved and not directory.started:
		submit()


func submit() -> void:
	saved = false
	_sync_modes()
	directory.search(query())


func query() -> Dictionary:
	var filters := {"name": field.text.strip_edges(), "tag": GENRES[genre.selected].to_lower() if genre.selected > 0 else "",
		"countrycode": country.get_item_metadata(country.selected) if country.selected > 0 else "",
		"language": language.get_item_metadata(language.selected) if language.selected > 0 else "", "order": order}
	filters.merge(quality.get_item_metadata(quality.selected))
	return filters


func set_search(text: String) -> void:
	field.text = text
	submit()


func reset() -> void:
	field.text = ""
	for option in [genre, country, language, quality]:
		option.select(0)
	order = "clickcount"
	submit()


func _mode(value: String) -> void:
	saved = value == "saved"
	if saved:
		directory.cancel()
		_sync_modes()
		results_changed.emit()
	else:
		order = value
		submit()


func _sync_modes() -> void:
	for i in mode_buttons.size():
		mode_buttons[i].set_pressed_no_signal(i == (3 if saved else ["clickcount", "clicktrend", "random"].find(order)))


func _catalogs_changed() -> void:
	_fill(country, directory.countries, "iso_3166_1")
	_fill(language, directory.languages, "name")


func _fill(option: OptionButton, rows: Array[Dictionary], key: String) -> void:
	if rows.is_empty() or option.item_count > 1:
		return
	option.disabled = false
	for row in rows:
		var value := str(row.get(key, ""))
		if value.is_empty():
			continue
		option.add_item(row["name"].capitalize() if key == "name" else row["name"])
		option.set_item_metadata(option.item_count - 1, value)


func _option(parent: Control, label: String) -> OptionButton:
	var option := OptionButton.new()
	option.theme_type_variation = &"CompactOption"
	option.custom_minimum_size = Vector2(220, 48)
	option.fit_to_longest_item = false
	option.tooltip_text = label
	option.get_popup().max_size = Vector2i(600, 600)
	parent.add_child(option)
	return option


func _button(parent: Control, text: String, icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	var tip: String = {
		"Popular": "Find stations with the most clicks",
		"Trending": "Find stations gaining clicks",
		"Surprise me": "Find a random selection of stations",
		"Saved stations": "Show saved favourite stations",
		"Reset": "Clear station search and filters",
		"Open stream URL": "Enter a radio or media stream URL",
	}.get(text, "")
	if not tip.is_empty():
		Tooltips.set_text(button, tip)
	button.icon = VpxTheme.icon(icon_name, 24)
	button.theme_type_variation = &"Chip"
	button.custom_minimum_size = Vector2(48, 48)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
