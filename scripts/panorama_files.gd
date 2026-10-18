extends RefCounted

const IMAGE_EXTENSIONS := ["jpg", "jpeg", "png", "webp"]
const CUBE_ORDER := ["right", "left", "up", "down", "front", "back"]
const FACE_NAMES := {
	"front": "front", "back": "back", "left": "left", "right": "right", "up": "up", "down": "down",
	"top": "up", "bottom": "down", "f": "front", "b": "back", "l": "left", "r": "right", "u": "up", "d": "down",
}
const FACE_PATTERN := "(?i)^(?<prefix>.+?)[_\\-. ](?<face>front|back|left|right|up|down|top|bottom)(?<suffix>[_\\-. ][a-z0-9]{1,4})?$"
const LETTER_PATTERN := "(?i)^(?<prefix>.+)[_\\-](?<face>[fblrud])$"
const SEPARATORS := "_-. "
const EQUIRECT_ASPECT := 2.0
const ASPECT_TOLERANCE := 0.05

static var face_regex := RegEx.create_from_string(FACE_PATTERN)
static var letter_regex := RegEx.create_from_string(LETTER_PATTERN)


static func is_image(path: String) -> bool:
	return path.get_extension().to_lower() in IMAGE_EXTENSIONS


static func face_of(path: String) -> Dictionary:
	var base := path.get_file().get_basename()
	for regex in [face_regex, letter_regex]:
		var found: RegExMatch = regex.search(base)
		if found != null:
			return {
				"prefix": found.get_string("prefix"),
				"face": FACE_NAMES[found.get_string("face").to_lower()],
				"suffix": found.get_string("suffix") if regex == face_regex else "",
				"extension": path.get_extension().to_lower(),
			}
	return {}


static func cube_faces(path: String) -> PackedStringArray:
	var directory := path.get_base_dir()
	var own := face_of(path)
	var sets := _face_sets(directory)
	var key := ""
	if not own.is_empty():
		key = _set_key(own)
	else:
		var base := path.get_file().get_basename()
		var best := -1
		for candidate: String in sets:
			var prefix: String = sets[candidate]["prefix"]
			if _extends_prefix(base, prefix) and prefix.length() > best:
				best = prefix.length()
				key = candidate
	if not sets.has(key):
		return PackedStringArray()
	var faces: Dictionary = sets[key]["faces"]
	var ordered := PackedStringArray()
	for face in CUBE_ORDER:
		if not faces.has(face):
			return PackedStringArray()
		ordered.append(directory.path_join(faces[face]))
	return ordered


static func equirect_for(path: String) -> String:
	var own := face_of(path)
	if own.is_empty():
		return path
	var directory := path.get_base_dir()
	var best := ""
	var best_size := -1
	for name in DirAccess.get_files_at(directory):
		if not is_image(name) or not face_of(name).is_empty():
			continue
		if not _extends_prefix(name.get_basename(), own["prefix"]):
			continue
		var size := FileAccess.get_size(directory.path_join(name))
		if size > best_size:
			best_size = size
			best = directory.path_join(name)
	return best


static func visible_images(_directory: String, names: Array[String]) -> Array[String]:
	var sets := {}
	var plain_prefixes := {}
	var plain_names: Array[String] = []
	var faces := {}
	for name in names:
		if not is_image(name):
			plain_names.append(name)
			continue
		var face := face_of(name)
		if face.is_empty():
			plain_names.append(name)
		else:
			faces[name] = face
			var key := _set_key(face)
			if not sets.has(key):
				sets[key] = {"faces": {}}
			sets[key]["faces"][face["face"]] = name
	if sets.is_empty():
		return names.duplicate()
	for name in plain_names:
		if is_image(name) or face_of(name).is_empty():
			_add_prefixes(name.get_basename(), plain_prefixes)
	var shown: Array[String] = []
	for name in names:
		if not faces.has(name):
			shown.append(name)
			continue
		var face: Dictionary = faces[name]
		var entry: Dictionary = sets.get(_set_key(face), {})
		if entry.get("faces", {}).size() < CUBE_ORDER.size():
			shown.append(name)
			continue
		if face["face"] != "front":
			continue
		if not plain_prefixes.has(face["prefix"]):
			shown.append(name)
	return shown


static func _add_prefixes(base: String, prefixes: Dictionary) -> void:
	prefixes[base] = true
	for i in base.length():
		if SEPARATORS.contains(base[i]):
			prefixes[base.substr(0, i)] = true


static func is_equirect_size(size: Vector2i) -> bool:
	return size.y > 0 and absf(float(size.x) / float(size.y) - EQUIRECT_ASPECT) < ASPECT_TOLERANCE


static func probe_size(path: String) -> Vector2i:
	var info: Dictionary = VPXPanorama.probe(path)
	return Vector2i(int(info.get("width", 0)), int(info.get("height", 0)))


static func _face_sets(directory: String) -> Dictionary:
	return _face_sets_from(Array(DirAccess.get_files_at(directory)))


static func _face_sets_from(names: Array) -> Dictionary:
	var sets := {}
	for name: String in names:
		if not is_image(name):
			continue
		var face := face_of(name)
		if face.is_empty():
			continue
		var key := _set_key(face)
		if not sets.has(key):
			sets[key] = {"prefix": face["prefix"], "faces": {}}
		sets[key]["faces"][face["face"]] = name
	return sets


static func _set_key(face: Dictionary) -> String:
	return "%s|%s|%s" % [face["prefix"], face["suffix"].to_lower(), face["extension"]]


static func _extends_prefix(base: String, prefix: String) -> bool:
	if not base.begins_with(prefix):
		return false
	return base.length() == prefix.length() or SEPARATORS.contains(base[prefix.length()])
