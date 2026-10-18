extends FloatPanel

var strip: SpiritLevel


func _init() -> void:
	panel_size = Vector2(0.86, 0.16)
	texture_density = 1100.0
	tilt = 0.0


func _build() -> Control:
	strip = SpiritLevel.new()
	return strip
