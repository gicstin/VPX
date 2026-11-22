extends VBoxContainer

const Rows := preload("res://scripts/rows.gd")
const HINTS := [
	"Stereo plays unchanged. Speakers, Crossfeed and Upmix ease the hard left and right separation of headphones.",
	"Places left and right as speakers in front of you, so each ear also hears the far side with a natural delay, level and softening.",
	"Blends a softened, slightly delayed copy of each side into the other ear. A light touch that keeps the original sound.",
	"Finds the centre (voices, bass, solos) and the ambience in the recording and plays them from five speakers: a real centre in front and the ambience behind you.",
]
const EAR_HINT := "Head width sets how far apart your ears are for all spatial sound. Bass translation adds harmonics so small headphones and speakers hint at deep bass."

var angled: VBoxContainer
var speakers_only: VBoxContainer
var upmix_only: VBoxContainer
var crossfeed: VBoxContainer
var shared: VBoxContainer
var hint: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	Rows.choice(self, "Stereo sound", &"stereo_mode", PackedStringArray(["Off", "Speakers", "Crossfeed", "Upmix"]))
	angled = _group()
	Rows.stepper(angled, "Speaker angle", &"stereo_angle", 20.0, 60.0, 5.0, {"suffix": "°"})
	Rows.toggle(angled, "Speakers stay put when you turn your head", &"stereo_tracked")
	speakers_only = _group()
	Rows.stepper(speakers_only, "Speaker effect", &"stereo_amount", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	upmix_only = _group()
	Rows.stepper(upmix_only, "Centre extraction", &"upmix_centre", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	Rows.stepper(upmix_only, "Ambience behind you", &"upmix_ambience", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	crossfeed = _group()
	Rows.stepper(crossfeed, "Crossfeed level", &"crossfeed_db", -12.0, -1.0, 0.5, {"decimals": 1, "suffix": " dB"})
	Rows.stepper(crossfeed, "Crossfeed cutoff", &"crossfeed_hz", 300.0, 2000.0, 50.0, {"suffix": " Hz"})
	shared = _group()
	Rows.stepper(shared, "Soften highs", &"air_db", 0.0, 9.0, 0.5, {"decimals": 1, "suffix": " dB"})
	Rows.stepper(shared, "Room reflections", &"room_amount", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	Rows.stepper(shared, "Virtual distance", &"stereo_distance", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	hint = Rows.hint(self, "")
	Rows.stepper(self, "Head width", &"head_width_cm", 13.0, 22.0, 0.5, {"decimals": 1, "suffix": " cm"})
	Rows.stepper(self, "Bass translation", &"bass_translate", 0.0, 1.0, 0.05, {"scale": 100.0, "suffix": "%"})
	Rows.hint(self, EAR_HINT)
	Settings.changed.connect(_sync)
	_sync()


func _group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	add_child(group)
	return group


func _sync() -> void:
	var mode: int = clampi(Settings.stereo_mode, 0, 3)
	angled.visible = mode == Settings.StereoMode.SPEAKERS or mode == Settings.StereoMode.UPMIX
	speakers_only.visible = mode == Settings.StereoMode.SPEAKERS
	upmix_only.visible = mode == Settings.StereoMode.UPMIX
	crossfeed.visible = mode == Settings.StereoMode.CROSSFEED
	shared.visible = mode != Settings.StereoMode.OFF
	hint.text = HINTS[mode]
