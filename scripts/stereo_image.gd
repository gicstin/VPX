class_name StereoImage
extends RefCounted

const BANDS := 48
const PAN_BINS := 64
const SLOTS := 8
const RATE := 45.0
const HISTORY := 192
const SOURCE_HISTORY := 64
const SCOPE_SAMPLES := 256
const SCOPE_FRAMES := 48
const SCOPE_RATE := 30.0
const FLOOR := 0.15
const SOURCE_THRESHOLD := 0.2
const SOURCE_PAN_STEP := 0.25
const MATCH_DISTANCE := 0.45

var correlation_ring := Ring.new(1, HISTORY, RATE)
var correlation := 1.0
var band_ring := Ring.new(BANDS, HISTORY, RATE)
var field_ring := Ring.new(PAN_BINS, HISTORY, RATE)
var source_ring := Ring.new(SLOTS, SOURCE_HISTORY, RATE)
var scope_image: Image
var scope_texture: ImageTexture
var scope_head := 0
var scope_elapsed := 0.0
var scope_delta := 0.0
var scope_gain := 1.0
var scope_active := false
var left_targets := PackedFloat32Array()
var right_targets := PackedFloat32Array()
var left_levels := PackedFloat32Array()
var right_levels := PackedFloat32Array()
var pans := PackedFloat32Array()
var levels := PackedFloat32Array()
var slots: Array[Slot] = []
var identities := 0
var mono := false
var active := false
var width := 0.0
var balance := 0.0
var channel_balance := Vector2.ZERO
var sources := PackedVector4Array()
var source_info := PackedVector4Array()
var source_bursts := PackedVector4Array()


class Ring extends RefCounted:
	var image: Image
	var texture: ImageTexture
	var columns := 0
	var rows := 0
	var rate := 0.0
	var head := -1
	var elapsed := 0.0
	var row := PackedColorArray()

	func _init(column_count: int, row_count: int, frequency: float) -> void:
		columns = column_count
		rows = row_count
		rate = frequency
		row.resize(columns)
		image = Image.create_empty(columns, rows, false, Image.FORMAT_RGBAF)
		image.fill(Color(0, 0, 0, 0))
		texture = ImageTexture.create_from_image(image)

	func clear() -> void:
		image.fill(Color(0, 0, 0, 0))
		texture.update(image)
		head = -1
		elapsed = 0.0

	func due(delta: float) -> int:
		elapsed += delta
		var count := int(floor((elapsed + 0.00000001) * rate))
		elapsed = maxf(0.0, elapsed - count / rate)
		return count

	func write() -> void:
		head = (head + 1) % rows
		for i in columns:
			image.set_pixel(i, head, row[i])

	func bind(material: ShaderMaterial, prefix: String) -> void:
		material.set_shader_parameter(prefix + "_head", float(head))
		material.set_shader_parameter(prefix + "_fraction", elapsed * rate)


class Slot extends RefCounted:
	var pan := 0.0
	var band := 0.0
	var span := 0.0
	var level := 0.0
	var target := 0.0
	var hue := 0.0
	var alive := false
	var age := 0.0
	var reference := 0.0
	var burst := Vector4(0, 0, 9.0, 0)
	var flash := 0.0


func _init() -> void:
	for array in [left_targets, right_targets, left_levels, right_levels, pans, levels]:
		array.resize(BANDS)
	for i in SLOTS:
		slots.append(Slot.new())
	sources.resize(SLOTS)
	source_info.resize(SLOTS)
	source_bursts.resize(SLOTS)
	scope_image = Image.create_empty(SCOPE_SAMPLES, SCOPE_FRAMES * 2, false, Image.FORMAT_RF)
	scope_image.fill(Color(0, 0, 0, 0))
	scope_texture = ImageTexture.create_from_image(scope_image)


func feed(data: PackedFloat32Array, single: bool, phase := 1.0) -> void:
	correlation = clampf(phase, -1.0, 1.0)
	mono = single
	for band in BANDS:
		left_targets[band] = data[band]
		right_targets[band] = data[band] if single else data[BANDS + band]
	active = true


func feed_scope(data: PackedFloat32Array) -> void:
	var peak := 0.0001
	for value in data:
		peak = maxf(peak, absf(value))
	var speed := -log(0.92 if 0.85 / peak < scope_gain else 0.98) * 90.0
	scope_gain = lerpf(scope_gain, clampf(0.85 / peak, 1.0, 300.0), 1.0 - exp(-scope_delta * speed))
	var scaled := PackedFloat32Array()
	scaled.resize(data.size())
	for i in data.size():
		scaled[i] = clampf(data[i] * scope_gain, -1.2, 1.2)
	var frame := Image.create_from_data(SCOPE_SAMPLES, 2, false, Image.FORMAT_RF, scaled.to_byte_array())
	while scope_elapsed >= 1.0 / SCOPE_RATE:
		scope_elapsed -= 1.0 / SCOPE_RATE
		scope_head = (scope_head + 1) % SCOPE_FRAMES
		scope_image.blit_rect(frame, Rect2i(0, 0, SCOPE_SAMPLES, 2), Vector2i(0, scope_head * 2))
	scope_image.blit_rect(frame, Rect2i(0, 0, SCOPE_SAMPLES, 2), Vector2i(0, scope_head * 2))
	scope_texture.update(scope_image)
	scope_active = true
	scope_delta = 0.0


func clear_scope() -> void:
	if not scope_active:
		return
	scope_active = false
	scope_image.fill(Color(0, 0, 0, 0))
	scope_texture.update(scope_image)
	scope_gain = 1.0
	scope_elapsed = 0.0
	scope_delta = 0.0
	scope_head = 0


func clear() -> void:
	active = false
	left_targets.fill(0.0)
	right_targets.fill(0.0)
	left_levels.fill(0.0)
	right_levels.fill(0.0)
	levels.fill(0.0)
	pans.fill(0.0)
	correlation_ring.clear()
	correlation = 1.0
	band_ring.clear()
	field_ring.clear()
	source_ring.clear()
	for slot in slots:
		slot.level = 0.0
		slot.target = 0.0
		slot.alive = false
		slot.burst.z = 9.0
		slot.flash = 0.0
	width = 0.0
	balance = 0.0
	channel_balance = Vector2.ZERO
	_publish()


func update(delta: float) -> void:
	scope_elapsed += delta
	scope_delta += delta
	var attack := 1.0 - exp(-delta * 35.0)
	var release := 1.0 - exp(-delta * 9.0)
	var steer := 1.0 - exp(-delta * 10.0)
	var sum := Vector2.ZERO
	for band in BANDS:
		left_levels[band] = lerpf(left_levels[band], left_targets[band], attack if left_targets[band] > left_levels[band] else release)
		right_levels[band] = lerpf(right_levels[band], right_targets[band], attack if right_targets[band] > right_levels[band] else release)
		levels[band] = maxf(left_levels[band], right_levels[band])
		var left := _power(left_levels[band])
		var right := _power(right_levels[band])
		if left + right > 0.000001:
			pans[band] = lerpf(pans[band], 0.0 if mono else _expand((right - left) / (right + left)), steer * clampf(levels[band] * 3.0, 0.2, 1.0))
		sum += Vector2(left_levels[band], right_levels[band]) / BANDS
	channel_balance = sum
	for slot in slots:
		slot.level = lerpf(slot.level, slot.target, 1.0 - exp(-delta * (20.0 if slot.target > slot.level else 5.0)))
		slot.burst.z = minf(9.0, slot.burst.z + delta)
		slot.flash *= exp(-delta * 8.0)
		if slot.alive:
			slot.age += delta
		elif slot.level < 0.01:
			slot.level = 0.0
	if active:
		var ticks := band_ring.due(delta)
		correlation_ring.elapsed = band_ring.elapsed
		field_ring.elapsed = band_ring.elapsed
		source_ring.elapsed = band_ring.elapsed
		for tick in ticks:
			_identify()
			_write_rows()
		if ticks > 0:
			correlation_ring.texture.update(correlation_ring.image)
			band_ring.texture.update(band_ring.image)
			field_ring.texture.update(field_ring.image)
			source_ring.texture.update(source_ring.image)
	_publish()


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("correlation_texture", correlation_ring.texture)
	material.set_shader_parameter("band_texture", band_ring.texture)
	material.set_shader_parameter("field_texture", field_ring.texture)
	material.set_shader_parameter("source_texture", source_ring.texture)
	material.set_shader_parameter("scope_texture", scope_texture)


func apply(material: ShaderMaterial) -> void:
	correlation_ring.bind(material, "correlation")
	band_ring.bind(material, "band")
	field_ring.bind(material, "field")
	source_ring.bind(material, "source")
	material.set_shader_parameter("scope_head", float(scope_head))
	material.set_shader_parameter("sources", sources)
	material.set_shader_parameter("source_info", source_info)
	material.set_shader_parameter("source_bursts", source_bursts)
	material.set_shader_parameter("channel_balance", channel_balance)
	material.set_shader_parameter("balance", balance)
	material.set_shader_parameter("width", width)


func _expand(pan: float) -> float:
	return signf(pan) * pow(absf(pan), 0.65)


func _power(value: float) -> float:
	if value <= 0.0:
		return 0.0
	var magnitude := db_to_linear(value * 60.0 - 60.0)
	return magnitude * magnitude


func _weight(level: float) -> float:
	return pow(maxf(0.0, level - FLOOR) / (1.0 - FLOOR), 1.5)


func _write_rows() -> void:
	var energy := PackedFloat32Array()
	energy.resize(PAN_BINS)
	var tone := PackedFloat32Array()
	tone.resize(PAN_BINS)
	var side := 0.0
	var total := 0.0
	var pan_sum := 0.0
	for band in BANDS:
		var left := sqrt(_power(left_levels[band]))
		var right := sqrt(_power(right_levels[band]))
		side += absf(right - left)
		total += right + left
		var weight := _weight(levels[band])
		band_ring.row[band] = Color(pans[band], levels[band], left_levels[band], right_levels[band])
		if weight <= 0.0:
			continue
		pan_sum += pans[band] * weight
		var centre := (pans[band] * 0.5 + 0.5) * (PAN_BINS - 1)
		for bin in range(maxi(0, int(centre) - 6), mini(PAN_BINS - 1, int(centre) + 7) + 1):
			var spread := (bin - centre) / 2.2
			var share := exp(-spread * spread) * weight
			energy[bin] += share
			tone[bin] += share * band / float(BANDS - 1)
	width = lerpf(width, side / maxf(total, 0.000001), 0.25)
	var weights := 0.0
	for band in BANDS:
		weights += _weight(levels[band])
	balance = lerpf(balance, pan_sum / weights if weights > 0.0 else 0.0, 0.2)
	for bin in PAN_BINS:
		field_ring.row[bin] = Color(energy[bin], tone[bin] / energy[bin] if energy[bin] > 0.0 else 0.5, 0.0, width)
	for i in SLOTS:
		var slot := slots[i]
		source_ring.row[i] = Color(slot.pan, slot.band, slot.level, slot.hue)
	correlation_ring.row[0] = Color(correlation, maxf(channel_balance.x, channel_balance.y), 0.0, 0.0)
	correlation_ring.write()
	band_ring.write()
	field_ring.write()
	source_ring.write()


func _identify() -> void:
	var runs: Array[Vector4] = []
	var start := -1
	var weight_sum := 0.0
	var pan_sum := 0.0
	var band_sum := 0.0
	var peak := 0.0
	var last := 0.0
	for band in BANDS + 1:
		var level := levels[band] if band < BANDS else 0.0
		var pan := pans[band] if band < BANDS else 0.0
		var on := level > SOURCE_THRESHOLD
		if start >= 0 and (not on or absf(pan - last) > SOURCE_PAN_STEP):
			runs.append(Vector4(pan_sum / weight_sum, band_sum / weight_sum / (BANDS - 1), peak, float(band - start) / BANDS))
			start = -1
		if on:
			if start < 0:
				start = band
				weight_sum = 0.0
				pan_sum = 0.0
				band_sum = 0.0
				peak = 0.0
			var weight := level * level
			weight_sum += weight
			pan_sum += pan * weight
			band_sum += band * weight
			peak = maxf(peak, level)
			last = pan
	runs.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.z * sqrt(a.w) > b.z * sqrt(b.w))
	runs = runs.slice(0, SLOTS)
	var claimed: Array[bool] = []
	claimed.resize(runs.size())
	claimed.fill(false)
	for slot in slots:
		if not slot.alive:
			continue
		var best := -1
		var best_distance := MATCH_DISTANCE
		for i in runs.size():
			if claimed[i]:
				continue
			var distance := absf(runs[i].x - slot.pan) + absf(runs[i].y - slot.band) * 2.0
			if distance < best_distance:
				best_distance = distance
				best = i
		if best < 0:
			slot.target = 0.0
			if slot.level < 0.04:
				slot.alive = false
			continue
		claimed[best] = true
		_assign(slot, runs[best], 0.35)
	for i in runs.size():
		if claimed[i]:
			continue
		for slot in slots:
			if not slot.alive and slot.level < 0.04:
				identities += 1
				slot.alive = true
				slot.age = 0.0
				slot.hue = fmod(identities * 0.61803398875, 1.0)
				slot.reference = 0.0
				slot.pan = runs[i].x
				slot.band = runs[i].y
				_assign(slot, runs[i], 1.0)
				break


func _assign(slot: Slot, run: Vector4, blend: float) -> void:
	slot.pan = lerpf(slot.pan, run.x, blend)
	slot.band = lerpf(slot.band, run.y, blend)
	slot.span = lerpf(slot.span, run.w, blend)
	slot.target = run.z
	if run.z > slot.reference + 0.1 and slot.burst.z > 0.3:
		slot.burst = Vector4(slot.pan, slot.band, 0.0, run.z)
		slot.flash = 1.0
	slot.reference = lerpf(slot.reference, run.z, 0.25)


func _publish() -> void:
	for i in SLOTS:
		var slot := slots[i]
		sources[i] = Vector4(slot.pan, slot.band, slot.level, slot.span)
		source_info[i] = Vector4(slot.hue, slot.age, slot.flash, 1.0 if slot.alive else 0.0)
		source_bursts[i] = slot.burst
