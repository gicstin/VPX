class_name SpatialPresets
extends RefCounted

const PATH := "user://spatial_audio.cfg"
const CURRENT := "Current"
const MAX_NAME := 32
const MAX_USER := 64

const KEYS: Array[Dictionary] = [
	{"key": "lfe_gain", "default": 0.25, "min": 0.0, "max": 2.0},
	{"key": "bass_db", "default": 0.0, "min": -12.0, "max": 18.0},
	{"key": "bass_hz", "default": 120.0, "min": 40.0, "max": 400.0},
	{"key": "surround_level", "default": 1.9, "min": 0.5, "max": 4.0},
	{"key": "shadow_strength", "default": 1.0, "min": 0.0, "max": 1.5},
	{"key": "itd_scale", "default": 1.0, "min": 0.0, "max": 1.5},
	{"key": "rear_depth", "default": 0.5, "min": 0.0, "max": 1.0},
	{"key": "rear_cutoff", "default": 3000.0, "min": 500.0, "max": 12000.0},
	{"key": "ild", "default": 0.3, "min": 0.0, "max": 0.8},
	{"key": "classic_shadow", "default": false},
	{"key": "linear_delay", "default": false},
	{"key": "normalize_downmix", "default": false},
]

const BUILTIN := {
	"Current": {},
	"Classic": {"lfe_gain": 0.35, "surround_level": 1.41, "classic_shadow": true, "linear_delay": true, "normalize_downmix": true},
	"Bass boost": {"lfe_gain": 0.35, "bass_db": 3.0, "bass_hz": 120.0},
	"Heavy bass": {"lfe_gain": 0.5, "bass_db": 6.0, "bass_hz": 100.0},
}

static var _user: Dictionary = {}
static var _user_stamp := -1


static func spec(key: String) -> Dictionary:
	for entry: Dictionary in KEYS:
		if entry["key"] == key:
			return entry
	return {}


static func defaults() -> Dictionary:
	var values := {}
	for entry: Dictionary in KEYS:
		values[entry["key"]] = entry["default"]
	return values


static func clean_value(key: String, value: Variant) -> Variant:
	var entry := spec(key)
	if entry.is_empty():
		return null
	if entry["default"] is bool:
		if value is bool or value is int or value is float:
			return bool(value)
		return null
	if not (value is float or value is int) or not is_finite(float(value)):
		return null
	return clampf(float(value), entry["min"], entry["max"])


static func sanitize(raw: Variant) -> Dictionary:
	var values := {}
	if not raw is Dictionary:
		return values
	var source: Dictionary = raw
	for key: Variant in source:
		if key is String or key is StringName:
			var value: Variant = clean_value(String(key), source[key])
			if value != null:
				values[String(key)] = value
	return values


static func builtin_names() -> PackedStringArray:
	return PackedStringArray(BUILTIN.keys())


static func is_builtin(name: String) -> bool:
	return BUILTIN.has(name)


static func user_names() -> PackedStringArray:
	_load_user()
	var names := PackedStringArray(_user.keys())
	names.sort()
	return names


static func all_names() -> PackedStringArray:
	return builtin_names() + user_names()


static func exists(name: String) -> bool:
	_load_user()
	return BUILTIN.has(name) or _user.has(name)


static func preset_values(name: String) -> Dictionary:
	_load_user()
	var values := defaults()
	var layer: Variant = BUILTIN.get(name, _user.get(name, {}))
	values.merge(sanitize(layer), true)
	return values


static func resolve(name: String, overrides: Dictionary) -> Dictionary:
	var values := preset_values(name)
	values.merge(sanitize(overrides), true)
	return values


static func differs(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool:
		return bool(a) != bool(b)
	return not is_equal_approx(float(a), float(b))


static func valid_name(raw: String) -> String:
	var name := raw.strip_edges().replace("\n", " ").replace("\t", " ")
	if name.is_empty() or name.length() > MAX_NAME:
		return ""
	for character in "[]=;\"\\/#":
		if name.contains(character):
			return ""
	if name == "Custom":
		return ""
	return name


static func name_error(raw: String, allow_existing: bool) -> String:
	var name := valid_name(raw)
	if name.is_empty():
		return "Use 1 to %d characters, without [ ] = ; \" / \\ #" % MAX_NAME
	_load_user()
	if BUILTIN.has(name) or BUILTIN.keys().any(func(builtin: String) -> bool: return builtin.nocasecmp_to(name) == 0):
		return "That name belongs to a built-in preset"
	if not allow_existing and _user.size() >= MAX_USER:
		return "Too many saved presets. Delete one first"
	return ""


static func file_path() -> String:
	return ProjectSettings.globalize_path(PATH)


static func file_exists() -> bool:
	return FileAccess.file_exists(PATH)


static func file_stamp() -> int:
	return FileAccess.get_modified_time(PATH) if FileAccess.file_exists(PATH) else 0


static func save(name: String, values: Dictionary) -> Error:
	var clean := valid_name(name)
	if clean.is_empty() or BUILTIN.has(clean):
		return ERR_INVALID_PARAMETER
	_load_user(true)
	var config := ConfigFile.new()
	config.load(PATH)
	_write_section(config, clean, resolve_full(values))
	return _commit(config)


static func resolve_full(values: Dictionary) -> Dictionary:
	var full := defaults()
	full.merge(sanitize(values), true)
	return full


static func delete(name: String) -> Error:
	_load_user(true)
	if not _user.has(name):
		return ERR_DOES_NOT_EXIST
	var config := ConfigFile.new()
	config.load(PATH)
	config.erase_section(name)
	return _commit(config)


static func _write_section(config: ConfigFile, section: String, values: Dictionary) -> void:
	for entry: Dictionary in KEYS:
		config.set_value(section, entry["key"], values.get(entry["key"], entry["default"]))


static func _commit(config: ConfigFile) -> Error:
	var error := config.save(PATH + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH))
	_user_stamp = -1
	_load_user(true)
	return error


static func _load_user(force := false) -> void:
	var stamp := FileAccess.get_modified_time(PATH) if FileAccess.file_exists(PATH) else 0
	if not force and stamp == _user_stamp:
		return
	_user_stamp = stamp
	_user = {}
	var config := ConfigFile.new()
	if stamp == 0 or config.load(PATH) != OK:
		return
	for section in config.get_sections():
		if _user.size() >= MAX_USER or valid_name(section) != section or BUILTIN.has(section):
			continue
		var values := {}
		for key in config.get_section_keys(section):
			var value: Variant = clean_value(key, config.get_value(section, key))
			if value != null:
				values[key] = value
		_user[section] = values
