class_name MusicMap
extends RefCounted

const CURVES := ["loudness", "bass", "percussive", "harmonic", "brightness", "onset", "intensity"]
const FAR := 1.0e6

var data := {}
var rate := 0.0
var duration := 0.0
var analysed := 0.0
var tempo := 0.0
var beats := PackedFloat32Array()
var downbeats := PackedFloat32Array()
var sections := PackedFloat32Array()
var section_energy := PackedFloat32Array()
var section_group := PackedFloat32Array()
var drops := PackedFloat32Array()
var build_starts := PackedFloat32Array()
var curves := {}


static func from_dictionary(source: Dictionary) -> MusicMap:
	if source.is_empty() or float(source.get("rate", 0.0)) <= 0.0:
		return null
	var map := MusicMap.new()
	map.data = source
	map.rate = float(source.rate)
	map.duration = float(source.get("duration", 0.0))
	map.analysed = float(source.get("analysed", map.duration))
	map.tempo = float(source.get("tempo", 0.0))
	map.beats = source.get("beats", PackedFloat32Array())
	map.downbeats = source.get("downbeats", PackedFloat32Array())
	map.sections = source.get("sections", PackedFloat32Array([0.0]))
	map.section_energy = source.get("section_energy", PackedFloat32Array())
	map.section_group = source.get("section_group", PackedFloat32Array())
	map.drops = source.get("drops", PackedFloat32Array())
	map.build_starts = source.get("build_starts", PackedFloat32Array())
	for key in CURVES:
		map.curves[key] = source.get(key, PackedFloat32Array())
	return map


func covers(time: float) -> bool:
	return time >= 0.0 and time <= analysed


func sample(key: String, time: float) -> float:
	var curve: PackedFloat32Array = curves.get(key, PackedFloat32Array())
	if curve.is_empty():
		return 0.0
	var position := clampf(time * rate, 0.0, curve.size() - 1.0)
	var index := int(position)
	var next := mini(index + 1, curve.size() - 1)
	return lerpf(curve[index], curve[next], position - index)


func peak(key: String, from: float, to: float) -> float:
	var curve: PackedFloat32Array = curves.get(key, PackedFloat32Array())
	if curve.is_empty():
		return 0.0
	var top := 0.0
	for i in range(clampi(int(from * rate), 0, curve.size() - 1), clampi(int(ceil(to * rate)) + 1, 1, curve.size())):
		top = maxf(top, curve[i])
	return top


func has_beats() -> bool:
	return beats.size() >= 2


func beat_index(time: float) -> int:
	return beats.bsearch(time, false) - 1


func beat_period(time: float) -> float:
	if not has_beats():
		return 0.5
	var index := clampi(beat_index(time), 0, beats.size() - 2)
	return beats[index + 1] - beats[index]


func beat_phase(time: float) -> float:
	if not has_beats():
		return 0.0
	var index := beat_index(time)
	if index < 0:
		var period := beats[1] - beats[0]
		return fposmod((time - beats[0]) / period, 1.0)
	if index >= beats.size() - 1:
		var period := beats[beats.size() - 1] - beats[beats.size() - 2]
		return fposmod((time - beats[beats.size() - 1]) / period, 1.0)
	return clampf((time - beats[index]) / (beats[index + 1] - beats[index]), 0.0, 0.999999)


func beats_until(time: float) -> int:
	return beats.bsearch(time, false)


func bar_phase(time: float) -> float:
	if downbeats.size() < 2:
		return fposmod(float(maxi(beat_index(time), 0)) + beat_phase(time), 4.0) / 4.0
	var index := downbeats.bsearch(time, false) - 1
	var start: float
	var end: float
	if index < 0:
		end = downbeats[0]
		start = end - (downbeats[1] - downbeats[0])
	elif index >= downbeats.size() - 1:
		start = downbeats[downbeats.size() - 1]
		end = start + (start - downbeats[downbeats.size() - 2])
	else:
		start = downbeats[index]
		end = downbeats[index + 1]
	return fposmod((time - start) / maxf(end - start, 0.001), 1.0)


func section_index(time: float) -> int:
	return maxi(0, sections.bsearch(time, false) - 1)


func section_start(index: int) -> float:
	return sections[clampi(index, 0, sections.size() - 1)]


func section_end(index: int) -> float:
	return sections[index + 1] if index + 1 < sections.size() else duration


func section_progress(time: float) -> float:
	var index := section_index(time)
	var start := section_start(index)
	return clampf((time - start) / maxf(section_end(index) - start, 0.001), 0.0, 1.0)


func energy_of(index: int) -> float:
	return section_energy[index] if index >= 0 and index < section_energy.size() else 0.5


func group_of(index: int) -> int:
	return int(section_group[index]) if index >= 0 and index < section_group.size() else 0


func next_section_in(time: float) -> float:
	var index := section_index(time)
	return section_end(index) - time if index + 1 < sections.size() else FAR


func build_amount(time: float) -> float:
	for i in drops.size():
		var start := build_starts[i] if i < build_starts.size() else drops[i]
		if time >= start and time < drops[i]:
			return clampf((time - start) / maxf(drops[i] - start, 0.001), 0.0, 1.0)
	return 0.0


func drop_age(time: float) -> float:
	var index := drops.bsearch(time, false) - 1
	return time - drops[index] if index >= 0 else FAR


func next_drop_in(time: float) -> float:
	var index := drops.bsearch(time, true)
	return drops[index] - time if index < drops.size() else FAR


func to_dictionary() -> Dictionary:
	return data
