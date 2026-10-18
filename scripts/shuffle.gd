extends RefCounted

const HISTORY_LIMIT := 10000

var items := PackedStringArray()
var items_hash := 0
var remaining: Array[String] = []
var slots := {}
var members := {}
var history: Array[String] = []
var cursor := -1
var upcoming := ""
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func sync(list: PackedStringArray, current: String) -> void:
	var list_hash := hash(list)
	if list_hash != items_hash or list.size() != items.size():
		items = list
		items_hash = list_hash
		members.clear()
		for path in items:
			members[path] = true
		history.clear()
		cursor = -1
		upcoming = ""
		_refill("")
	if members.has(current):
		visit(current)


func rekey(mapping: Dictionary) -> void:
	for i in items.size():
		items[i] = mapping.get(items[i], items[i])
	for i in remaining.size():
		remaining[i] = mapping.get(remaining[i], remaining[i])
	for i in history.size():
		history[i] = mapping.get(history[i], history[i])
	upcoming = mapping.get(upcoming, upcoming)
	members.clear()
	for path: String in items:
		members[path] = true
	slots.clear()
	for i in remaining.size():
		slots[remaining[i]] = i
	items_hash = hash(items)


func visit(path: String) -> void:
	if cursor >= 0 and history[cursor] == path:
		return
	if cursor + 1 < history.size() and history[cursor + 1] == path:
		cursor += 1
		return
	history.resize(cursor + 1)
	history.append(path)
	if history.size() > HISTORY_LIMIT + HISTORY_LIMIT / 4:
		history = history.slice(history.size() - HISTORY_LIMIT)
	cursor = history.size() - 1
	_take(path)
	if upcoming == path:
		upcoming = ""


func next() -> String:
	if cursor + 1 < history.size():
		cursor += 1
		return history[cursor]
	var path := peek_next()
	if path.is_empty():
		return ""
	upcoming = ""
	visit(path)
	return path


func previous() -> String:
	if cursor <= 0:
		return ""
	cursor -= 1
	return history[cursor]


func peek_next() -> String:
	if cursor + 1 < history.size():
		return history[cursor + 1]
	if not upcoming.is_empty() and slots.has(upcoming):
		return upcoming
	if items.size() < 2 and cursor >= 0:
		return ""
	if remaining.is_empty():
		_refill(history[cursor] if cursor >= 0 else "")
	if remaining.is_empty():
		return ""
	upcoming = remaining[rng.randi_range(0, remaining.size() - 1)]
	return upcoming


func peek_previous() -> String:
	return history[cursor - 1] if cursor > 0 else ""


func seen_count() -> int:
	return items.size() - remaining.size()


func _refill(skip: String) -> void:
	remaining.clear()
	slots.clear()
	for path in items:
		if path != skip:
			slots[path] = remaining.size()
			remaining.append(path)


func _take(path: String) -> void:
	var slot: int = slots.get(path, -1)
	if slot < 0:
		return
	var last: String = remaining[-1]
	remaining[slot] = last
	slots[last] = slot
	remaining.pop_back()
	slots.erase(path)
