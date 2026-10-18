extends RefCounted

const PROJECTION_NAMES := {"equirectangular": 0, "cubemap": 1, "tiled equirectangular": 2, "half equirectangular": 3, "rectilinear": 4, "fisheye": 5, "parametric immersive": 6}
const STEREO_NAMES := {"2d": 0, "side by side": 1, "top and bottom": 2, "frame alternate": 3, "checkerboard": 4, "side by side (quincunx subsampling)": 5, "interleaved lines": 6, "interleaved columns": 7, "unspecified": 8}
const STEREO_MODES := {"mono": [0, false], "left_right": [1, false], "right_left": [1, true], "top_bottom": [2, false], "bottom_top": [2, true], "checkerboard_rl": [4, true], "checkerboard_lr": [4, false], "row_interleaved_rl": [6, true], "row_interleaved_lr": [6, false], "col_interleaved_rl": [7, true], "col_interleaved_lr": [7, false], "block_lr": [3, false], "block_rl": [3, true]}
const STEREO_TAGS := {"LR": 1, "RL": 1, "SBS": 1, "HSBS": 1, "FSBS": 1, "3DH": 1, "SIDEBYSIDE": 1, "TB": 2, "BT": 2, "OU": 2, "HOU": 2, "FOU": 2, "HTB": 2, "FTB": 2, "3DV": 2, "OVERUNDER": 2, "TOPBOTTOM": 2, "MONO": 0, "2D": 0}
const CUBE_TAGS := {"EAC": 4, "CUBEMAP": 5, "C3X2": 5}
const LENS_TAGS := {"MKX200": 200.0, "MKX220": 220.0, "RF52": 190.0, "FISHEYE": 180.0, "F180": 180.0}
const FILENAME_EXAMPLES := [
	["clip_180_OU.mp4", "180° equirectangular, over-under 3D"],
	["clip_180_MONO.mp4", "180° equirectangular, mono"],
	["clip_FISHEYE_OU.mp4", "Fisheye, over-under 3D"],
	["clip_FISHEYE190_SBS.mp4", "190° fisheye, side-by-side 3D"],
	["photo_360_MONO.jpg", "360° equirectangular, mono"],
	["clip_360_SBS.mp4", "360° equirectangular, side-by-side 3D"],
	["clip_FLAT_SBS.mp4", "Flat side-by-side 3D"],
	["clip_EAC_MONO.mp4", "360° equi-angular cubemap"],
]
const MEDIA_EXTENSIONS := ["mp4", "mkv", "mov", "webm", "avi", "m4v", "mpg", "mpeg", "ts", "m2ts", "mts", "ogv", "wmv", "flv", "jpg", "jpeg", "png", "webp"]

static var token_regex := RegEx.create_from_string("[\\p{L}\\p{N}]+")
static var compound_regex := RegEx.create_from_string("^(?:VR)?(180|360)(LR|RL|SBS|HSBS|FSBS|TB|BT|OU|HOU|HTB|MONO|3D|3DH|3DV)?$")
static var lens_regex := RegEx.create_from_string("^FISHEYE([0-9]{3})$")
static var phrase_regex := RegEx.create_from_string("(?<![A-Z0-9])(?:SIDE[ _.-]+BY[ _.-]+SIDE|OVER[ _.-]+UNDER|TOP[ _.-]+(?:AND[ _.-]+)?BOTTOM|HALF[ _.-]+SBS|FULL[ _.-]+SBS|HALF[ _.-]+(?:OU|TB)|FULL[ _.-]+(?:OU|TB))(?![A-Z0-9])")


static func _number(value: Variant, fallback := 0.0) -> float:
	if not (value is int or value is float or value is String):
		return fallback
	if value is String and not value.is_valid_float():
		return fallback
	var number := float(value)
	return number if is_finite(number) else fallback


static func _angle(value: Variant) -> float:
	return wrapf(_number(value), -180.0, 180.0)


static func _flag(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value == 1
	return value is String and value.to_lower() in ["true", "1", "yes"]


static func _enum_value(value: Variant, names: Dictionary) -> int:
	if value is String and names.has(value.to_lower()):
		return names[value.to_lower()]
	var number := _number(value, -1.0)
	return int(number) if number == floorf(number) else -1


static func _unique(values: Array, fallback: Variant) -> Variant:
	if values.is_empty():
		return fallback
	for value in values:
		if value != values[0]:
			return fallback
	return values[0]


static func tags_from_name(path: String) -> Dictionary:
	var clean := path.replace("\\", "/")
	if clean.contains("://"):
		clean = clean.get_slice("?", 0).get_slice("#", 0)
	var name := clean.get_file().uri_decode().to_upper()
	if name.get_extension().to_lower() in MEDIA_EXTENSIONS:
		name = name.get_basename()
	for found in phrase_regex.search_all(name):
		var phrase := found.get_string()
		var token := "OVERUNDER"
		if phrase.begins_with("SIDE"):
			token = "SIDEBYSIDE"
		elif phrase.ends_with("SBS"):
			token = "HSBS" if phrase.begins_with("HALF") else "FSBS"
		elif phrase.begins_with("HALF"):
			token = "HOU"
		name = name.replace(phrase, token)
	var projections: Array = []
	var spherical: Array = []
	var stereos: Array = []
	var orders: Array = []
	var fovs: Array = []
	var alpha := false
	var half := false
	var wants_3d := false
	var equirect := false
	for found in token_regex.search_all(name):
		var token := found.get_string()
		var compound := compound_regex.search(token)
		if compound != null:
			spherical.append(1 if compound.get_string(1) == "360" else 2)
			if not compound.get_string(2).is_empty():
				token = compound.get_string(2)
		if STEREO_TAGS.has(token):
			stereos.append(STEREO_TAGS[token])
			if STEREO_TAGS[token] != 0:
				orders.append(token in ["RL", "BT"])
			half = half or token in ["HSBS", "HOU", "HTB"]
		if token == "3D":
			wants_3d = true
		if CUBE_TAGS.has(token):
			projections.append(CUBE_TAGS[token])
		if token in ["FLAT", "RECTILINEAR"]:
			projections.append(0)
		if token in ["EQUIRECT", "EQUIRECTANGULAR"]:
			equirect = true
		var lens := lens_regex.search(token)
		if LENS_TAGS.has(token) or lens != null:
			var fov := float(lens.get_string(1)) if lens != null else float(LENS_TAGS[token])
			if fov >= 90.0 and fov <= 270.0:
				projections.append(3)
				fovs.append(fov)
		if token == "ALPHA":
			alpha = true
	var projection := int(_unique(projections, -1)) if not projections.is_empty() else int(_unique(spherical, -1))
	var projection_conflict := (not projections.is_empty() and projection < 0) or (projections.is_empty() and not spherical.is_empty() and projection < 0)
	var stereo := int(_unique(stereos, -1))
	var stereo_conflict := not stereos.is_empty() and stereo < 0
	if projection < 0 and not projection_conflict and equirect:
		projection = 1
	if alpha and projection < 0 and not projection_conflict:
		projection = 3
		if stereo < 0 and not stereo_conflict:
			stereo = 1
	return {"projection": projection, "stereo": stereo, "fov": float(_unique(fovs, 180.0)) if not fovs.is_empty() else 0.0, "alpha": alpha, "swap": bool(_unique(orders, false)), "half": half, "wants_3d": wants_3d, "projection_conflict": projection_conflict, "stereo_conflict": stereo_conflict}


static func format_from_metadata(metadata: Dictionary) -> Dictionary:
	var result := {"projection": -1, "stereo": -1, "swap": false, "fov": 0.0, "equirect_fov": 0.0, "rotation": Vector3.ZERO, "padding": 0.0, "unsupported_stereo": false}
	var spherical: Variant = metadata.get("spherical")
	if spherical is Dictionary:
		var kind := _enum_value(spherical.get("projection", -1), PROJECTION_NAMES)
		match kind:
			0:
				result["projection"] = 1
			1:
				result["projection"] = 5
				result["padding"] = maxf(_number(spherical.get("padding")), 0.0)
			2:
				var left := _number(spherical.get("bound_left", 0.0), -1.0)
				var right := _number(spherical.get("bound_right", 0.0), -1.0)
				var top := _number(spherical.get("bound_top", 0.0), -1.0)
				var bottom := _number(spherical.get("bound_bottom", 0.0), -1.0)
				var span := 1.0 - left - right
				if left >= 0.0 and right >= 0.0 and top >= 0.0 and bottom >= 0.0 and span > 0.0 and top + bottom < 1.0:
					result["projection"] = 1 if span >= 0.999 else 2
					if result["projection"] == 2:
						result["equirect_fov"] = clampf(snappedf(span * 360.0, 1.0), 90.0, 270.0)
			3:
				result["projection"] = 2
			4:
				result["projection"] = 0
			5, 6:
				result["projection"] = 3
				result["fov"] = 180.0
		if result["projection"] >= 0:
			result["rotation"] = Vector3(_angle(spherical.get("yaw")), _angle(spherical.get("pitch")), _angle(spherical.get("roll")))
	var stereo3d: Variant = metadata.get("stereo3d")
	var mode := str(metadata.get("stereo_mode", "")).to_lower()
	if not stereo3d is Dictionary and STEREO_MODES.has(mode):
		stereo3d = {"type": STEREO_MODES[mode][0], "inverted": STEREO_MODES[mode][1]}
	if stereo3d is Dictionary:
		var kind := _enum_value(stereo3d.get("type", -1), STEREO_NAMES)
		var view: Variant = stereo3d.get("view", 0)
		if kind >= 0 and (view in [1, 2, "left", "right"]):
			result["stereo"] = 0
		elif kind in [0, 1, 2]:
			result["stereo"] = kind
		elif kind >= 3:
			result["stereo"] = 0
			result["unsupported_stereo"] = true
		if result["stereo"] > 0:
			result["swap"] = _flag(stereo3d.get("inverted", false))
		var hfov := _number(stereo3d.get("hfov"))
		if hfov >= 90.0 and hfov <= 270.0 and result["projection"] == 3:
			result["fov"] = hfov
	if _flag(metadata.get("multiview", false)):
		if result["projection"] < 0:
			result["projection"] = 0
		result["stereo"] = 1
		result["swap"] = false
		result["unsupported_stereo"] = false
	return result


static func guess_projection(stereo: int, aspect: float) -> int:
	if not is_finite(aspect) or aspect <= 0.0:
		return 0
	if stereo == 1:
		if _near(aspect, 4.0):
			return 1
		if _near(aspect, 2.0):
			return 2
	elif stereo == 2:
		if _near(aspect, 1.0):
			return 1
		if _near(aspect, 0.5):
			return 2
	return 0


static func _near(aspect: float, target: float) -> bool:
	return is_finite(aspect) and aspect > 0.0 and absf(aspect / target - 1.0) <= 0.050001


static func guess_stereo(projection: int, aspect: float) -> int:
	match projection:
		2, 3:
			if _near(aspect, 2.0):
				return 1
			if _near(aspect, 0.5):
				return 2
		1:
			if _near(aspect, 4.0):
				return 1
			if _near(aspect, 1.0):
				return 2
		4, 5:
			if _near(aspect, 3.0):
				return 1
			if _near(aspect, 0.75):
				return 2
	return 0


static func guess_format(path: String, aspect: float, metadata := {}, title := "") -> Dictionary:
	var tags := tags_from_name(path)
	if not title.is_empty():
		var title_tags := tags_from_name(title)
		for field in ["projection", "stereo"]:
			if title_tags[field] >= 0:
				tags[field] = title_tags[field]
				tags[field + "_conflict"] = false
		if title_tags["fov"] > 0.0:
			tags["fov"] = title_tags["fov"]
		if title_tags["stereo"] >= 0:
			tags["swap"] = title_tags["swap"]
			tags["half"] = title_tags["half"]
		tags["alpha"] = tags["alpha"] or title_tags["alpha"]
		tags["wants_3d"] = tags["wants_3d"] or title_tags["wants_3d"]
	var result := format_from_metadata(metadata)
	var projection: int = result["projection"]
	var stereo: int = result["stereo"]
	var tagged: bool = projection >= 0 or stereo >= 0 or tags["projection"] >= 0 or tags["stereo"] >= 0
	if projection < 0:
		projection = tags["projection"]
		result["fov"] = tags["fov"]
	if stereo < 0:
		stereo = tags["stereo"]
		result["swap"] = tags["swap"]
	if projection < 0:
		if tags["projection_conflict"] or tags["half"]:
			projection = 0
		elif stereo >= 0:
			projection = guess_projection(stereo, aspect)
		elif path.get_extension().to_lower() in ["jpg", "jpeg", "png", "webp"] and is_finite(aspect) and absf(aspect - 2.0) < 0.05:
			projection = 1
		else:
			projection = 0
	if stereo < 0:
		stereo = 0 if tags["stereo_conflict"] else guess_stereo(projection, aspect)
		if tags["wants_3d"] and stereo == 0 and projection in [2, 3] and _near(aspect, 1.0):
			stereo = 1
	result["projection"] = projection
	result["stereo"] = stereo
	result["swap"] = result["swap"] if stereo != 0 else false
	result["swap_eyes"] = result["swap"]
	result["tagged"] = tagged
	result["alpha"] = tags["alpha"]
	return result


static func metadata_from_side_data(side_data: Array, width: int, height := 0) -> Dictionary:
	var metadata := {}
	for item in side_data:
		if not item is Dictionary:
			continue
		match str(item.get("side_data_type", "")):
			"Spherical Mapping":
				var kind := _enum_value(item.get("projection", -1), PROJECTION_NAMES)
				if kind < 0 or kind > 6:
					continue
				var spherical := {"projection": kind, "padding": _number(item.get("padding")), "yaw": _number(item.get("yaw")), "pitch": _number(item.get("pitch")), "roll": _number(item.get("roll"))}
				if kind == 2:
					var left := _number(item.get("bound_left", 0), -1.0)
					var right := _number(item.get("bound_right", 0), -1.0)
					var top := _number(item.get("bound_top", 0), -1.0)
					var bottom := _number(item.get("bound_bottom", 0), -1.0)
					if width <= 0 or minf(left, right) < 0.0 or minf(top, bottom) < 0.0:
						continue
					var full_width := float(width) + left + right
					var full_height := float(height) + top + bottom
					if not is_finite(full_width) or not is_finite(full_height):
						continue
					if (top > 0.0 or bottom > 0.0) and height <= 0:
						continue
					spherical.merge({"bound_left": left / full_width, "bound_right": right / full_width, "bound_top": top / full_height if full_height > 0.0 else 0.0, "bound_bottom": bottom / full_height if full_height > 0.0 else 0.0})
				metadata["spherical"] = spherical
			"Stereo 3D":
				var kind := _enum_value(item.get("type", -1), STEREO_NAMES)
				if kind < 0:
					continue
				var hfov := _number(item.get("horizontal_field_of_view"))
				var ratio: Variant = item.get("horizontal_field_of_view")
				if ratio is String:
					var parts: PackedStringArray = ratio.split("/")
					if parts.size() == 2 and _number(parts[1]) != 0.0:
						hfov = _number(parts[0]) / _number(parts[1])
				metadata["stereo3d"] = {"type": kind, "inverted": _flag(item.get("inverted", false)), "view": item.get("view", 0), "hfov": hfov}
	return metadata


static func metadata_from_probe(stream: Dictionary, frames: Array) -> Dictionary:
	var width := int(_number(stream.get("width")))
	var height := int(_number(stream.get("height")))
	var side_data: Variant = stream.get("side_data_list", [])
	var metadata := metadata_from_side_data(side_data if side_data is Array else [], width, height)
	var sources: Array = [stream]
	sources.append_array(frames)
	for source in sources:
		if not source is Dictionary:
			continue
		var frame_side_data: Variant = source.get("side_data_list", [])
		var frame_metadata := metadata_from_side_data(frame_side_data if frame_side_data is Array else [], width, height)
		metadata.merge(frame_metadata)
		var tags: Variant = source.get("tags", {})
		if not metadata.has("stereo3d") and tags is Dictionary:
			var mode := str(tags.get("stereo_mode", "")).to_lower()
			if STEREO_MODES.has(mode):
				metadata["stereo3d"] = {"type": STEREO_MODES[mode][0], "inverted": STEREO_MODES[mode][1]}
	return metadata
