extends RefCounted

const INVALID := -1.0

static var units := RegEx.create_from_string("^(?:(\\d+(?:\\.\\d+)?)\\s*h)?\\s*(?:(\\d+(?:\\.\\d+)?)\\s*m)?\\s*(?:(\\d+(?:\\.\\d+)?)\\s*s?)?$")


static func parse(text: String, position: float, length: float) -> float:
	var body := text.strip_edges().to_lower().replace(",", ".")
	if body.is_empty():
		return INVALID
	var sign := 0.0
	if body[0] == "+" or body[0] == "-":
		sign = 1.0 if body[0] == "+" else -1.0
		body = body.substr(1).strip_edges()
	var seconds := INVALID
	if body.ends_with("%") and sign == 0.0:
		var percent := body.trim_suffix("%").strip_edges()
		if percent.is_valid_float() and length > 0.0:
			seconds = float(percent) / 100.0 * length
	elif ":" in body:
		seconds = _clock(body)
	else:
		seconds = _units(body)
	if seconds < 0.0:
		return INVALID
	if sign != 0.0:
		seconds = position + sign * seconds
	if length > 0.0:
		seconds = minf(seconds, length)
	return maxf(seconds, 0.0)


static func _clock(body: String) -> float:
	var parts := body.split(":")
	if parts.size() > 3:
		return INVALID
	var total := 0.0
	for part in parts:
		var value := part.strip_edges()
		if not value.is_valid_float() or value.begins_with("-") or value.begins_with("+"):
			return INVALID
		total = total * 60.0 + float(value)
	return total


static func _units(body: String) -> float:
	var match := units.search(body)
	if match == null:
		return INVALID
	var scales := [3600.0, 60.0, 1.0]
	if not match.get_string(1).is_empty() and match.get_string(2).is_empty() and not match.get_string(3).is_empty() and body[-1].is_valid_int():
		scales[2] = 60.0
	var total := 0.0
	var found := false
	for group in 3:
		var value := match.get_string(group + 1)
		if not value.is_empty():
			total += float(value) * scales[group]
			found = true
	return total if found else INVALID
