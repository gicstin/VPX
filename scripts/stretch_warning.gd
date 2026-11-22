extends Label

const GOOD := "Audio stretching is on: any speed other than 1× lowers sound quality. Tones can waver and sharp sounds soften. 1× plays the original sound."
const FAST := "Audio stretching is on in Fast mode: any speed other than 1× lowers sound quality, with more echo and a rough, hollow tone. 1× plays the original sound."


func _ready() -> void:
	name = "StretchWarning"
	theme_type_variation = &"Warning"
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Settings.changed.connect(_sync)
	_sync()


func _sync() -> void:
	visible = not is_equal_approx(Settings.playback_speed, 1.0)
	text = FAST if Settings.audio_stretch_quality == 1 else GOOD
