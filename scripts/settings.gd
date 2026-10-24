extends Node

signal changed
signal zoom_changed(snap: bool)
signal screen_size_changed

enum ProjectionMode { FLAT, EQUIRECT_360, EQUIRECT_180, FISHEYE, EAC, CUBEMAP }
enum VisualizerGrab { DEFAULT, SCENE_AND_AUDIO, AUDIO_ONLY }
enum Stereo { MONO, SIDE_BY_SIDE, OVER_UNDER }
enum AlphaMask { NONE, PACKED_CORNERS, STACKED_BELOW }
enum Background { CHROMA_KEY, PASSTHROUGH, BLACK, CINEMA }
enum DecodeMode { AUTO, HARDWARE, SOFTWARE }
enum EndAction { STOP, REPEAT, NEXT_FILE }
enum PlaybackPriority { SMOOTH, SHARP }
enum PanoramaSource { SINGLE, CUBE }
enum StickAction { SCREEN_SIZE, BRIGHTNESS, GAMMA, SATURATION, SHARPNESS, VOLUME, FORMAT_2D, FORMAT_3D, FORMAT_ALL, SUBTITLE_TRACK, AUDIO_TRACK, SCREEN_CURVE, STEREO_DEPTH, PICTURE_ZOOM, PLAYBACK_SPEED, CHAPTER }
enum LibraryView { GRID, LIST }
enum SubtitleAuto { OFF, FOREIGN, ALWAYS }
enum LibrarySort { NAME, DATE, SIZE, PLAY_COUNT }
enum LibrarySource { FOLDER, RECENT, FAVORITES, PLACES, NETWORK, DISCOVER }
enum SleepTimer { OFF, MIN_15, MIN_30, MIN_45, MIN_60, MIN_90, END_OF_VIDEO }
enum LibraryFilter { ALL, FLAT_2D, FLAT_3D, VR_180, VR_360, PHOTOS }
enum AudioFilter { OFF, LEVEL, NIGHT }
enum Deband { OFF, LOW, MEDIUM, HIGH }

const CONFIG_PATH := "user://settings.cfg"
const VISUALIZER_PRESET_MAX := 109
const VISUALIZER_PRESETS := [
	"Resonance Field", "Resonant Architecture", "Particle Cosmos",
	"Bass Strings", "Wave Architecture", "Aurora Cosmos", "Stereo Speakers",
	"Stereo Waterfall", "Spectral River", "Delay Curtains", "Spectral Tunnel",
	"Spectral Canyon", "Ribbon Canopy", "Braided Ribbons", "Harmonic Arches",
	"Stereo Wings", "Spectral Chamber", "Warp Tunnel", "Laser Show",
	"Sub Pulse", "Nebula Storm", "Kaleidosphere", "Source Stage", "Vectorscope",
	"Lissajous Tunnel", "Source Constellation", "Stereo Terrain", "Source Fireworks",
	"Source Planets", "Pan Aurora", "Ripple Pool", "Light Harp", "Sound Radar",
	"Pan Analyzer Ring", "Source Comets", "Stereo Bloom", "Width Tunnel", "Surround Choir",
	"Stereo Point Cloud", "Binary Stars", "Tesla Arcs", "Pendulum Wave", "Phosphor Dome",
	"Polar Scope", "Scope Halo", "Scope Kaleidoscope", "Stereo Helix", "Terrain Canyon",
	"Pan Ridges", "Terrain Tunnel", "Neon Mirror", "Crystal City",
	"Spectrum Observatory", "Phase Cathedral", "Stereo Ribbonfall",
	"Pan Meridian", "Transient Loom", "Stereo Difference",
	"Mid Side Atrium", "Correlation Causeway", "Stereo Spectrogram", "Pan Trails",
	"Dual Waveform", "Spectral Balance",
	"Celestial Orrery", "Abyssal Garden", "Prism Sanctuary", "Solar Crucible",
	"Awe Horizon", "Fractal Canopy", "Phyllotaxis Bloom", "Heartbeat Tide",
	"Frisson Aurora", "Synesthesia", "Groove Lattice", "Tension Vortex",
	"PM · Geiss Swirl 1", "PM · Geiss Starfish 1", "PM · Geiss Nautilus", "PM · Geiss Cosmic Dust 2",
	"Aftershock", "Chromatic Riptide", "Prismatic Overdrive",
	"Velvet Supernova", "Liquid Voltage", "Event Horizon",
	"PM · Interwoven", "PM · Tokamak", "PM · Lattice",
	"PM · Rolling Oceans", "PM · Solarized Space", "PM · Ether Storm",
	"PM · Clockwork Halo", "PM · Jellyfish Jam", "PM · Glass Serpents",
	"PM · Hexa Vault", "PM · Peacock Pavilion", "PM · Folded Infinity",
	"PM · Sierpinski Shrine", "PM · Chladni Plates", "PM · Prism Shards",
	"PM · Spirograph Choir",
	"Spectrogram Atlas", "Vocal Detail", "Bass Observatory", "Transient Scanner",
	"Stereo Balance Hall", "Noise Floor Vault", "Harmonic Ridgeway", "Spectral Panorama"
]
const VISUALIZER_ZOOM_MIN := 0.5
const VISUALIZER_ZOOM_MAX := 3.0
const VISUALIZER_STUDIO_START := 52
const VISUALIZER_STUDIO_GUIDES := [
	"30 Hz → 18 kHz · Cyan L / Pink R · Height −60 → 0 dB · 10 dB rings",
	"Side ↔ / Mid ↕ · Vertical = mono · Horizontal = phase opposition · Auto gain",
	"Centre → edges: 30 Hz → 18 kHz · Cyan L / Pink R · 3.8 s history · Height −60 → 0 dB",
	"Left ↔ Right · Bottom → top: 30 Hz → 18 kHz · Depth = 2.5 s pan history",
	"Left → right: 30 Hz → 18 kHz · Depth = 3.8 s history · Gold = rising spectral energy",
	"30 Hz → 18 kHz · Cyan below = L louder / Pink above = R louder · Centre = equal magnitude",
	"Cyan lower rings = Mid (L+R) / Gold upper rings = Side (R−L) · Waveform displaces rings · Depth = 0.8 s history · Shared auto gain",
	"Left red = −1 phase opposition / Centre amber = 0 / Right green = +1 mono compatibility · Depth = 3.8 s correlation history",
	"Left → right: 30 Hz → 18 kHz · Upper panel L / Lower panel R · Top of each panel = now, bottom = 3.8 s ago · Dark → bright: −60 → 0 dB",
	"Left ↔ Right = frequency pan · Low → high elevation: 30 Hz → 18 kHz · Near → far = 3.8 s history · Colour = frequency",
	"Left → right: 256 captured samples · Cyan upper = L / Pink lower = R · Shared auto gain · Centre lines = zero · Outer rails = ±1 after gain · Depth = 0.8 s persistence",
	"Left → right: 30 Hz → 18 kHz · Height = R minus L, −24 → +24 dB · Cyan below = L louder / Pink above = R louder · Centre = equal magnitude · 6 dB grid · Depth = 3.8 s history",
	"Layered orbital filaments and star swarms · Cyan L / Gold R · Frequency shapes orbit radius · Bass expands the armillary crown",
	"Bioluminescent fronds and drifting plankton · Cyan L / Violet R · Spectral history bends each frond · Bass ripples the seabed",
	"Nested crystal vaults and suspended spectral dust · Cyan L / Rose R · Frequency lights each facet · Stereo width opens the crown",
	"Spiralling plasma, magnetic loops and solar ejecta · Gold L / Magenta R · Bass swells the corona · Treble ignites particles",
	"Vast spectral horizon and star belt · Low notes sit low and near, high notes high and far · Left / right follow the mix · Drops open the sky gate",
	"Self-similar light tree · Deeper, finer branches carry higher frequencies · Energy and build-ups grow the canopy · Treble lights the leaves",
	"Golden-angle seed sphere · Bottom = bass, top = treble · Left / right halves follow the channels · Beats breathe, drops scatter seeds",
	"Rhythmic light sea · Near waves = bass, horizon = treble · Kicks send ripples · Quiet passages breathe at a calm slow pace",
	"Stereo aurora curtains · Position = pan, glow height = pitch · Build-ups shimmer · Sudden swells after quiet send a wave of light",
	"One glowing orb per frequency · Height = pitch, size shrinks as pitch rises · Left / right = pan · Threads link sounding neighbours",
	"Beat-locked light lattice · Rows = pitch, columns = pan · Every beat ripples outward, bar downbeats bounce higher · Settles ahead of steady beats",
	"Rising spectral spire · Build-ups tighten and spin the vortex · Drops fling it open · Base = bass, tip = treble",
	"Native 3D adaptation of Geiss — Swirl 1 · Radial twist and colour equations · Stereo waveform ribbons with depth trails",
	"Native 3D adaptation of Geiss — Starfish 1 · Fivefold angular zoom equation · Expanding stereo waveform petals",
	"Native 3D adaptation of Geiss — Nautilus · Rotation-driven zoom equation · Coiled waveform shell with bass warp",
	"Native 3D adaptation of Geiss — Cosmic Dust 2 · Moving centre and colour equations · Stereo dust streams and orbital trails",
	"Bass blows open concentric pressure waves · Percussion fractures the edges · Stereo waveform rings carry the sound into depth",
	"Flowing colour sheets surround you · Vocals bend the currents · Bass drives rolling crests · Treble sheds sparks",
	"Immersive prismatic light architecture · Transients open the facets · Bass punches through the structure · Stereo steers the light",
	"Swirling clouds and luminous ejecta · Bass throws the nebula outward · Percussion ignites the dust · Quiet passages settle into darkness",
	"Liquid light above and below · Bass sends waves through the surface · Vocals sculpt the flow · Treble lifts droplets",
	"Spiralling light through deep space · Bass opens the passage · Energy accelerates the flow · Waveforms ripple through the tunnel",
	"From Krash — Interwoven (Nightmare Weft Mix) · Three drifting light wefts surround you · Stereo waveform bends the threads · Percussion lifts the weave",
	"From Flexi, Geiss and Rovastar — chaos layered tokamak · Magnetic coils encircle you · Bass expands the reactor · Treble energises the field particles",
	"From shifter — lattice · Angular crystal cells fill the room · Spectrum grows the edges · Stereo separates the facets · Beats fracture the grid",
	"From Rovastar and Telek — Altars of Madness (Rolling Oceans Mix) · Rolling spectral sea beneath a wide horizon · Bass raises swells · Waveform ripples the water",
	"From Rovastar — Solarized Space · A solar globe and tilted planetary orbits · Bass expands the sun · Stereo waveform sculpts the orbital trails",
	"From Zylot — Ether Storm · Opposing vertical currents and falling sparks · Upper and lower flows shear in opposite directions · Percussion disturbs the storm",
	"Inspired by martin — open machinery hazard · Counter-rotating toothed halos · Bass expands the gears · Stereo waveform cuts the teeth",
	"Inspired by Flexi — jellyfish jam · Pulsing translucent bells and trailing tentacles · Bass pumps the bells · Treble lights drifting plankton",
	"Inspired by shifter — glassworms multi · Iridescent tubular creatures weave around you · Waveform flexes their bodies · Percussion sends light along their spines",
	"Inspired by suksma / yin — Organic circuits · Staggered hexagonal vaults · Spectrum opens each cell · Stereo and percussion animate the honeycomb",
	"Inspired by TonyMilkdrop / Flexi — Dawning The Peacocks · Four feathered fans with luminous eyes · Bass spreads the plumage · Stereo ripples the vanes",
	"Inspired by EVET — The Ringer · Suspended Möbius bands with a continuous half twist · Waveform folds the surfaces · Bass opens the loops",
	"Inspired by Flexi — disruptor / rule 90 · Four recursive tetrahedral shrines · Frequency lights the nested cells · Percussion separates the fractal tiers",
	"Inspired by amandio c — interference pattern · Suspended vibrating membranes · Stereo waveform drives standing waves · Spectral energy reveals the nodal lines",
	"Inspired by amandio c — embrace 07 · Floating triangular glass sails · Percussion splays the shards · Stereo waveform folds their facets",
	"Inspired by EVET — Fractronica · Spatial hypotrochoid choirs with depth trails · Bass changes the lobes · Stereo waveform ripples the tubular paths",
	"Full-band stereo inspection · Left → right: 30 Hz → 18 kHz logarithmic bands · Cyan upper = L / Rose lower = R · Top of each panel = now, bottom = 3.8 s ago · Dark → gold: −60 → 0 dB · Repeated around you",
	"Vocal and dialogue detail · Bottom → top: 120 Hz → 8 kHz · Cyan left wall = L / Rose right wall = R · Near → far = 3.8 s history · Brightness = −60 → 0 dB · Inspect formants and sibilance",
	"Low-end inspection · Centre → edges: 30 → 300 Hz · Cyan left bank = L / Rose right bank = R · Near → far = 3.8 s history · Height and colour = −60 → 0 dB · Inspect bass decay and rumble",
	"Attack and percussion inspection · Left → right: 30 Hz → 18 kHz · Cyan upper = L / Rose lower = R · Near → far = 3.8 s history · Gold = positive level change over 67 ms, up to +18 dB · Steady tones stay dark",
	"Channel balance by frequency · Left → right: 30 Hz → 18 kHz · Near → far = 3.8 s history · Cyan below = L louder / Rose above = R louder · Centre = equal magnitude · Height = R minus L, −24 → +24 dB · Magnitudes only, not phase",
	"Quiet-tail and noise inspection · Left → right: 30 Hz → 18 kHz · Cyan upper = L / Rose lower = R · Top = now, bottom = 3.8 s ago · Expanded −60 → −24 dB colour range · Gold saturates above −24 dB · Display floor is −60 dB",
	"Harmonic and resonance inspection · Centre → edges: 30 Hz → 18 kHz · Cyan left terrain = L / Rose right terrain = R · Near → far = 3.8 s history · Height = −60 → 0 dB · Contours every 10 dB · Native 48 frequency bands",
	"360° spectral history terraces · Each quadrant repeats 30 Hz → 18 kHz from left to right · Cyan upper terrace = L / Rose lower terrace = R · Inner edge = now, outer edge = 3.8 s ago · Height and colour = −60 → 0 dB",
]
const SCREEN_PLACEMENT_VERSION := 1
const SCREEN_DISTANCE := 3.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 8.0
const ZOOM_RATE := 0.8
const SCREEN_SIZE_RATE := 30.0
const FORMAT_PRESETS := [
	["2D flat", ProjectionMode.FLAT, Stereo.MONO],
	["3D SBS", ProjectionMode.FLAT, Stereo.SIDE_BY_SIDE],
	["3D OU", ProjectionMode.FLAT, Stereo.OVER_UNDER],
	["180 SBS", ProjectionMode.EQUIRECT_180, Stereo.SIDE_BY_SIDE],
	["180 OU", ProjectionMode.EQUIRECT_180, Stereo.OVER_UNDER],
	["180 mono", ProjectionMode.EQUIRECT_180, Stereo.MONO],
	["360 mono", ProjectionMode.EQUIRECT_360, Stereo.MONO],
	["360 SBS", ProjectionMode.EQUIRECT_360, Stereo.SIDE_BY_SIDE],
	["360 OU", ProjectionMode.EQUIRECT_360, Stereo.OVER_UNDER],
	["Fisheye SBS", ProjectionMode.FISHEYE, Stereo.SIDE_BY_SIDE],
]
const FORMAT_PROPERTIES := ["projection", "stereo", "swap_eyes", "fisheye_fov", "alpha_mask", "stereo_depth", "stereo_vertical", "picture_zoom", "single_eye", "photo_pan_x", "photo_pan_y", "equirect_fov", "eye_roll", "lens_k1", "lens_k2", "crop_left", "crop_top", "crop_right", "crop_bottom"]
const VIEW_ADJUST := {"stereo_depth": 0.0, "stereo_vertical": 0.0, "picture_zoom": 1.0, "single_eye": false, "photo_pan_x": 0.0, "photo_pan_y": 0.0, "equirect_fov": 180.0, "eye_roll": 0.0, "lens_k1": 0.0, "lens_k2": 0.0, "crop_left": 0.0, "crop_top": 0.0, "crop_right": 0.0, "crop_bottom": 0.0}
const CALIBRATION := ["equirect_fov", "eye_roll", "lens_k1", "lens_k2", "crop_left", "crop_top", "crop_right", "crop_bottom"]
const DEBAND_PARAMS := [Vector2(0.0, 0.0), Vector2(1.6 / 255.0, 10.0), Vector2(2.6 / 255.0, 16.0), Vector2(4.0 / 255.0, 24.0)]
const REMOTE_PORT := 23554
const SLEEP_MINUTES := [0, 15, 30, 45, 60, 90, 0]
const SHARPNESS_LEVELS := ["Off", "Low", "Medium", "High", "Extra", "Max"]
const SHARPNESS_GAINS := [0.0, 0.5, 1.0, 1.6, 2.4, 3.2]
const RESUME_MIN_SECONDS := 5.0
const RESUME_END_MARGIN := 10.0
const SAVE_DELAY := 0.5
const SUBTITLE_COLORS := [Color(1.0, 1.0, 1.0), Color(1.0, 0.9, 0.3), Color(0.8, 0.8, 0.8)]
const Languages := preload("res://scripts/languages.gd")

var projection := ProjectionMode.FLAT
var stereo := Stereo.MONO
var swap_eyes := false
var fisheye_fov := 180.0
var alpha_mask := AlphaMask.NONE
var stereo_depth := 0.0
var stereo_vertical := 0.0
var picture_zoom := 1.0
var single_eye := false
var flat_image_repeat := 0
var flat_video_pan := false
var photo_pan_x := 0.0
var photo_pan_y := 0.0
var equirect_fov := 180.0
var eye_roll := 0.0
var lens_k1 := 0.0
var lens_k2 := 0.0
var crop_left := 0.0
var crop_top := 0.0
var crop_right := 0.0
var crop_bottom := 0.0
var auto_crop := true
var deband := Deband.OFF
var dither := true
var compositor_layer := false
var music_visualizer := true
var music_visualizer_mode := 0
var immersive_music_visualizer := true
var visualizer_overlay := false
var visualizer_overlay_opacity := 0.65
var visualizer_background_dim := 0.15
var visualizer_atmosphere := 0.15
var visualizer_preset := 0
var visualizer_favorites := PackedStringArray()
var visualizer_starred_only := false
var visualizer_shuffle := false
var _visualizer_random_seen: Array[int] = []
var visualizer_quality := 0
var visualizer_intensity := 0.75
var visualizer_sensitivity := 1.75
var visualizer_motion := 0.6
var visualizer_zoom := 1.0
var visualizer_sync := 0.0
var visualizer_auto_change := false
var visualizer_grab_mode := VisualizerGrab.DEFAULT
var ui_size := 1.0
var text_size := 1.0
var accent_color := VpxTheme.DEFAULT_ACCENT
var spatial_audio := true
var dialogue_boost := false
var audio_filter := AudioFilter.OFF
var audio_stretch_quality := 0
var remote_control := false
var sleep_timer := SleepTimer.OFF
var playback_speed := 1.0
var background := Background.PASSTHROUGH
var chroma_key_color := Color8(0, 30, 60)
var cut_enabled := false
var cut_invert := false
var cut_similarity := 0.08
var cut_feather := 0.08
var mask_threshold := 0.5
var mask_trim := 0.0
var mask_darken := 2.0
var edge_fade := 0.1
var screen_size := 67.0
var screen_curve := 0.0
var brightness := 1.0
var sharpness_level := 0
var gamma := 1.0
var saturation := 1.0
var angle_yaw := 0.0
var angle_pitch := 0.0
var angle_roll := 0.0
var match_refresh_rate := true
var prefer_desktop := false
var muted := false
var volume := 100
var decode_mode := DecodeMode.AUTO
var playback_priority := PlaybackPriority.SMOOTH
var panorama_source := PanoramaSource.CUBE
var photo_supersampling := true
var shuffle := false
var auto_detect := true
var hide_menu_on_play := true
var end_action := EndAction.STOP
var resume_playback := true
var seek_previews := true
var drag_speed := 1.0
var menu_translucent := false
var lock_horizon := false
var show_level := true
var laser_menu_only := false
var follow_posture := false
var look_gain := 1.0
var grip_action := StickAction.SCREEN_SIZE
var trigger_action := StickAction.VOLUME
var chord_action := StickAction.BRIGHTNESS
var legacy_positions := {}
var legacy_formats := {}
var dim_behind_menu := true
var menu_follow := true
var video_follow := false
var pause_when_removed := true
var hover_haptics := true
var show_clock := true
var auto_swap_eyes := true
var face_on_open := false
var audio_language := 0
var subtitle_auto := SubtitleAuto.FOREIGN
var subtitle_language := 0
var subtitle_size := 1.0
var subtitle_size_by_format := {}
var subtitle_offset := 0.0
var subtitle_color := 0
var subtitle_box := false
var subtitle_distance := 2.5
var audio_delay := 0.0
var subtitle_delay := 0.0
var format_path := ""
var detecting := false
var session_format := {}
const SESSION_FORMAT_PROPERTIES := ["projection", "stereo", "swap_eyes", "fisheye_fov", "equirect_fov"]
var last_directory := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
var last_file := ""
var library_view := LibraryView.GRID
var library_flat_view := false
var library_favorites_only := false
var library_unplayed_only := false
var library_sort := LibrarySort.NAME
var library_source := LibrarySource.FOLDER
var library_filter := LibraryFilter.ALL
var library_query := ""
var library_tab_session := {}
var window_session := {}
var network_servers: Array = []
var defaults := {}
var profiles = preload("res://scripts/view_profiles.gd").new()
var save_pending := false
var save_timer := 0.0
var subtitle_size_format := ""


func _ready() -> void:
	subtitle_language = Languages.system_language()
	for property in _persisted() + PackedStringArray(["audio_delay", "subtitle_delay", "playback_speed", "sleep_timer"]) + PackedStringArray(VIEW_ADJUST.keys()):
		defaults[property] = get(property)
	load_config()
	picture_zoom = clampf(picture_zoom, ZOOM_MIN, ZOOM_MAX) if is_finite(picture_zoom) else 1.0
	_validate_visualizer()
	ui_size = clampf(ui_size, 0.8, 1.25) if is_finite(ui_size) else 1.0
	text_size = clampf(text_size, 1.0, 1.5) if is_finite(text_size) else 1.0
	profiles.load_store()
	_sync_accent()
	changed.connect(_sync_accent)
	changed.connect(_sync_subtitle_size)
	_sync_subtitle_size()
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Control:
			VpxTheme.scale_control.call_deferred(node))


func _sync_subtitle_size() -> void:
	var key := "%d:%d" % [projection, stereo]
	if key == subtitle_size_format:
		return
	subtitle_size_format = key
	if subtitle_size_by_format.has(key):
		apply("subtitle_size", float(subtitle_size_by_format[key]))


func _sync_accent() -> void:
	VpxTheme.set_accent(accent_color)
	VpxTheme.set_text_size(text_size, get_tree().root)


func _process(delta: float) -> void:
	if not save_pending:
		return
	save_timer += delta
	if save_timer >= SAVE_DELAY:
		flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush()


func visualizer_advance_limit() -> float:
	return minf(0.25, floorf(maxf(0.0, AudioServer.get_output_latency()) / 0.005) * 0.005)


func toggle_visualizer_favorite(index: int) -> void:
	if index < 0 or index > VISUALIZER_PRESET_MAX:
		return
	var favorites := visualizer_favorites.duplicate()
	var name: String = VISUALIZER_PRESETS[index]
	if name in favorites:
		favorites.remove_at(favorites.find(name))
	else:
		favorites.append(name)
	apply("visualizer_favorites", favorites)


func next_visualizer_preset(direction: int) -> int:
	var step := 1 if direction > 0 else -1
	for offset in range(1, VISUALIZER_PRESETS.size() + 1):
		var index := posmod(visualizer_preset + offset * step, VISUALIZER_PRESETS.size())
		if not visualizer_starred_only or VISUALIZER_PRESETS[index] in visualizer_favorites:
			return index
	return visualizer_preset


func cycle_visualizer_preset(direction: int) -> void:
	if direction != 0:
		if visualizer_shuffle:
			random_visualizer_preset()
		else:
			apply("visualizer_preset", next_visualizer_preset(direction))


func random_visualizer_preset() -> void:
	if _visualizer_random_seen.is_empty():
		_visualizer_random_seen.append(visualizer_preset)
	var candidates: Array[int] = []
	var remaining: Array[int] = []
	for index in VISUALIZER_PRESETS.size():
		if not visualizer_starred_only or VISUALIZER_PRESETS[index] in visualizer_favorites:
			candidates.append(index)
			if index not in _visualizer_random_seen:
				remaining.append(index)
	if candidates.size() < 2:
		return
	if remaining.is_empty():
		_visualizer_random_seen.clear()
		remaining = candidates
		remaining.erase(visualizer_preset)
	apply("visualizer_preset", remaining.pick_random())


func _validate_visualizer() -> void:
	music_visualizer_mode = clampi(music_visualizer_mode, 0, 2)
	if music_visualizer_mode == 1:
		music_visualizer_mode = 0
	visualizer_preset = clampi(visualizer_preset, 0, VISUALIZER_PRESET_MAX)
	visualizer_quality = clampi(visualizer_quality, 0, 3)
	visualizer_grab_mode = clampi(visualizer_grab_mode, VisualizerGrab.DEFAULT, VisualizerGrab.AUDIO_ONLY)
	visualizer_intensity = clampf(visualizer_intensity, 0.0, 1.5) if is_finite(visualizer_intensity) else 0.75
	visualizer_sensitivity = clampf(visualizer_sensitivity, 0.5, 4.0) if is_finite(visualizer_sensitivity) else 1.75
	visualizer_motion = clampf(visualizer_motion, 0.0, 1.0) if is_finite(visualizer_motion) else 0.6
	visualizer_zoom = clampf(visualizer_zoom, VISUALIZER_ZOOM_MIN, VISUALIZER_ZOOM_MAX) if is_finite(visualizer_zoom) else 1.0
	for key in [&"visualizer_overlay_opacity", &"visualizer_background_dim", &"visualizer_atmosphere"]:
		var amount: float = get(key)
		set(key, clampf(amount, 0.0, 1.0) if is_finite(amount) else defaults.get(key, 0.15))
	visualizer_sync = clampf(visualizer_sync, -0.25, visualizer_advance_limit()) if is_finite(visualizer_sync) else 0.0


func apply(property: StringName, value: Variant) -> void:
	if property == &"visualizer_favorites":
		if not value is PackedStringArray:
			return
		var favorites := PackedStringArray()
		for name: String in value:
			if name in VISUALIZER_PRESETS and name not in favorites:
				favorites.append(name)
		value = favorites
	if property in [&"ui_size", &"text_size"]:
		if not (value is float or value is int) or not is_finite(float(value)):
			return
		value = clampf(float(value), 0.8, 1.25) if property == &"ui_size" else clampf(float(value), 1.0, 1.5)
	if property in [&"music_visualizer_mode", &"visualizer_preset", &"visualizer_quality", &"visualizer_grab_mode", &"visualizer_intensity", &"visualizer_sensitivity", &"visualizer_motion", &"visualizer_zoom", &"visualizer_sync", &"visualizer_overlay_opacity", &"visualizer_background_dim", &"visualizer_atmosphere"]:
		if not (value is int or value is float) or not is_finite(float(value)):
			return
		var limits := {&"music_visualizer_mode": Vector2(0, 2), &"visualizer_preset": Vector2(0, VISUALIZER_PRESET_MAX), &"visualizer_quality": Vector2(0, 3), &"visualizer_grab_mode": Vector2(0, 2), &"visualizer_intensity": Vector2(0, 1.5), &"visualizer_sensitivity": Vector2(0.5, 4), &"visualizer_motion": Vector2(0, 1), &"visualizer_zoom": Vector2(VISUALIZER_ZOOM_MIN, VISUALIZER_ZOOM_MAX), &"visualizer_sync": Vector2(-0.25, 0.25), &"visualizer_overlay_opacity": Vector2(0, 1), &"visualizer_background_dim": Vector2(0, 1), &"visualizer_atmosphere": Vector2(0, 1)}
		if property == &"visualizer_sync":
			limits[property].y = visualizer_advance_limit()
		value = clampf(float(value), limits[property].x, limits[property].y)
		if property in [&"music_visualizer_mode", &"visualizer_preset", &"visualizer_quality", &"visualizer_grab_mode"]:
			value = int(value)
		if property == &"music_visualizer_mode" and value == 1:
			value = 0
	if property == &"picture_zoom":
		if not (value is float or value is int) or not is_finite(float(value)):
			return
		value = clampf(float(value), ZOOM_MIN, ZOOM_MAX)
	if get(property) == value:
		return
	set(property, value)
	if property in [&"visualizer_favorites", &"visualizer_starred_only"] and visualizer_starred_only and VISUALIZER_PRESETS[visualizer_preset] not in visualizer_favorites:
		visualizer_preset = next_visualizer_preset(1)
	if property in [&"visualizer_starred_only", &"visualizer_shuffle"] or (property == &"visualizer_favorites" and visualizer_starred_only):
		_visualizer_random_seen.clear()
		_visualizer_random_seen.append(visualizer_preset)
	elif property == &"visualizer_preset" and visualizer_preset not in _visualizer_random_seen:
		_visualizer_random_seen.append(visualizer_preset)
	if property == &"picture_zoom":
		zoom_changed.emit(is_equal_approx(float(value), 1.0))
	Log.note_setting(property, value)
	if property in SESSION_FORMAT_PROPERTIES and not detecting:
		for key: String in SESSION_FORMAT_PROPERTIES:
			session_format[key] = get(key)
	if property in FORMAT_PROPERTIES and not detecting and not format_path.is_empty():
		remember_format()
	save_config()
	changed.emit()


func preview_zoom(value: float) -> void:
	if not is_finite(value):
		return
	picture_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	save_config()
	zoom_changed.emit(false)


func preview_visualizer_zoom(value: float) -> void:
	if not is_finite(value):
		return
	visualizer_zoom = clampf(value, VISUALIZER_ZOOM_MIN, VISUALIZER_ZOOM_MAX)
	save_config()


func commit_zoom() -> void:
	if not detecting and not format_path.is_empty():
		remember_format()
	commit()


func preview_screen_size(value: float) -> void:
	if not is_finite(value):
		return
	screen_size = clampf(value, 20.0, 140.0)
	save_config()
	screen_size_changed.emit()


func apply_viewing_values(values: Dictionary) -> bool:
	var validator = load("res://scripts/settings_backup.gd")
	for key: String in values:
		if key not in profiles.KEYS or not validator._valid_setting(key, values[key]):
			return false
	var previous := profiles.capture()
	for key: String in values:
		var value: Variant = values[key]
		set(key, value.duplicate(true) if value is Dictionary or value is Array else value)
	save_config()
	if flush() != OK:
		for key: String in previous:
			set(key, previous[key])
		return false
	changed.emit()
	return true


func commit() -> void:
	save_config()
	changed.emit()


func reset(properties: PackedStringArray) -> void:
	var format_changed := false
	for property in properties:
		set(property, defaults[property])
		format_changed = format_changed or property in FORMAT_PROPERTIES
	if not detecting:
		for property: String in properties:
			if property in SESSION_FORMAT_PROPERTIES:
				for key: String in SESSION_FORMAT_PROPERTIES:
					session_format[key] = get(key)
				break
	if "picture_zoom" in properties:
		zoom_changed.emit(true)
	if format_changed and not format_path.is_empty():
		remember_format()
	Log.info("reset %s" % ", ".join(properties))
	save_config()
	changed.emit()


func flat_screen_width() -> float:
	return 2.0 * SCREEN_DISTANCE * tan(deg_to_rad(screen_size) * 0.5)


func flat_image_tiles() -> int:
	return 1 + clampi(flat_image_repeat, 0, 2) * 2 if projection == ProjectionMode.FLAT else 1


func pan_photo(delta: Vector2) -> void:
	var next_x := clampf(photo_pan_x + delta.x, -0.5, 0.5)
	var next_y := clampf(photo_pan_y + delta.y, -0.5, 0.5)
	if is_equal_approx(next_x, photo_pan_x) and is_equal_approx(next_y, photo_pan_y):
		return
	photo_pan_x = next_x
	photo_pan_y = next_y
	changed.emit()


func commit_photo_pan() -> void:
	if not format_path.is_empty():
		remember_format()
	commit()


func matching_preset() -> int:
	for i in FORMAT_PRESETS.size():
		if FORMAT_PRESETS[i][1] == projection and FORMAT_PRESETS[i][2] == stereo:
			return i
	return -1


func presets_for(action: StickAction) -> Array:
	var indexes := []
	for i in FORMAT_PRESETS.size():
		var mono: bool = FORMAT_PRESETS[i][2] == Stereo.MONO
		if action == StickAction.FORMAT_ALL or (action == StickAction.FORMAT_2D) == mono:
			indexes.append(i)
	return indexes


func cycle_preset(action: StickAction, direction: int) -> void:
	var indexes := presets_for(action)
	var position := indexes.find(matching_preset())
	position = wrapi(position + direction, 0, indexes.size()) if position >= 0 else 0
	select_format(FORMAT_PRESETS[indexes[position]][1], FORMAT_PRESETS[indexes[position]][2])


func remember_format() -> void:
	var saved := {}
	for property in FORMAT_PROPERTIES:
		saved[property] = get(property)
	Library.set_pref(format_path, "format", saved)


func restore_format(path: String) -> bool:
	var saved: Variant = Library.get_pref(path, "format")
	if not saved is Dictionary:
		return false
	detecting = true
	apply("projection", int(saved.get("projection", projection)))
	apply("stereo", int(saved.get("stereo", stereo)))
	apply("swap_eyes", bool(saved.get("swap_eyes", swap_eyes)))
	apply("fisheye_fov", float(saved.get("fisheye_fov", fisheye_fov)))
	apply("alpha_mask", int(saved.get("alpha_mask", AlphaMask.NONE)))
	for property: String in VIEW_ADJUST:
		apply(property, type_convert(saved.get(property, VIEW_ADJUST[property]), typeof(VIEW_ADJUST[property])))
	detecting = false
	return true


func has_crop() -> bool:
	return crop_left + crop_top + crop_right + crop_bottom > 0.0001


func crop_rect() -> Vector4:
	return Vector4(crop_left, crop_top, crop_right, crop_bottom)


func apply_crop(rect: Vector4) -> void:
	apply("crop_left", rect.x)
	apply("crop_top", rect.y)
	apply("crop_right", rect.z)
	apply("crop_bottom", rect.w)


func clear_view_adjust() -> void:
	var was_detecting := detecting
	detecting = true
	for property: String in VIEW_ADJUST:
		apply(property, VIEW_ADJUST[property])
	detecting = was_detecting


func remember_position(path: String, seconds: float, length: float) -> void:
	if path.is_empty():
		return
	if length > 0.0 and seconds > length - RESUME_END_MARGIN:
		Library.erase_pref(path, "position")
	elif seconds < RESUME_MIN_SECONDS:
		Library.erase_pref(path, "position")
	else:
		Library.set_pref(path, "position", seconds)


func resume_position(path: String) -> float:
	return float(Library.get_pref(path, "position", 0.0)) if resume_playback else 0.0


func load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var saved_window: Variant = config.get_value("window", "session", {})
	window_session = saved_window if saved_window is Dictionary else {}
	for property in _persisted():
		set(property, config.get_value("player", property, get(property)))
	if not config.has_section_key("player", "immersive_music_visualizer"):
		immersive_music_visualizer = music_visualizer and int(config.get_value("player", "music_visualizer_mode", 1)) == 1
	_validate_visualizer()
	if int(config.get_value("player", "screen_placement_version", 0)) < SCREEN_PLACEMENT_VERSION:
		face_on_open = false
		save_config()
	if not config.has_section_key("player", "screen_size") and config.has_section_key("player", "screen_width"):
		var legacy_width := float(config.get_value("player", "screen_width"))
		var legacy_distance := float(config.get_value("player", "screen_distance", SCREEN_DISTANCE))
		screen_size = clampf(snappedf(rad_to_deg(2.0 * atan(legacy_width * 0.5 / maxf(legacy_distance, 0.1))), 5.0), 20.0, 140.0)
	if config.has_section_key("player", "screen_distance"):
		for property in ["grip_action", "trigger_action", "chord_action"]:
			set(property, maxi(int(get(property)) - 1, 0))
	if not config.has_section_key("player", "library_source") and bool(config.get_value("player", "show_favorites", false)):
		library_source = LibrarySource.FAVORITES
	legacy_positions = config.get_value("player", "resume_positions", {})
	legacy_formats = config.get_value("player", "file_formats", {})


func save_config() -> void:
	save_pending = true
	save_timer = 0.0


func flush() -> Error:
	if not save_pending:
		return OK
	var config := ConfigFile.new()
	config.set_value("window", "session", window_session)
	for property in _persisted():
		config.set_value("player", property, get(property))
	config.set_value("player", "screen_placement_version", SCREEN_PLACEMENT_VERSION)
	var error := config.save(CONFIG_PATH + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(CONFIG_PATH + ".tmp"), ProjectSettings.globalize_path(CONFIG_PATH))
	if error != OK:
		save_timer = 0.0
		Log.warn("settings: cannot save: " + error_string(error))
		return error
	save_pending = false
	return OK


func _persisted() -> PackedStringArray:
	return PackedStringArray([
		"projection", "stereo", "swap_eyes", "fisheye_fov", "alpha_mask", "background",
		"chroma_key_color", "cut_enabled", "cut_invert", "cut_similarity",
		"cut_feather", "mask_threshold", "mask_trim", "mask_darken", "edge_fade", "screen_size", "screen_curve", "brightness",
		"sharpness_level", "gamma", "saturation", "angle_yaw", "angle_pitch", "angle_roll",
		"match_refresh_rate", "prefer_desktop",
		"muted", "volume", "decode_mode", "playback_priority", "panorama_source", "photo_supersampling", "shuffle", "auto_detect", "hide_menu_on_play",
		"end_action", "resume_playback", "seek_previews", "drag_speed", "menu_translucent", "lock_horizon", "follow_posture", "look_gain", "grip_action", "trigger_action", "chord_action",
		"show_level", "laser_menu_only", "dim_behind_menu", "menu_follow", "video_follow", "pause_when_removed", "hover_haptics", "show_clock", "face_on_open", "auto_swap_eyes",
		"audio_language", "subtitle_auto", "subtitle_language", "subtitle_size", "subtitle_size_by_format", "subtitle_offset", "subtitle_color", "subtitle_box", "subtitle_distance",
		"last_directory", "last_file", "library_view", "library_flat_view", "library_favorites_only", "library_unplayed_only", "library_sort", "library_source", "library_filter", "library_tab_session", "network_servers",
		"stereo_depth", "stereo_vertical", "picture_zoom", "single_eye", "flat_image_repeat", "photo_pan_x", "photo_pan_y",
		"auto_crop", "deband", "dither", "compositor_layer", "spatial_audio", "dialogue_boost", "audio_filter",
		"remote_control", "flat_video_pan", "music_visualizer", "audio_stretch_quality", "accent_color", "ui_size", "text_size",
		"music_visualizer_mode", "immersive_music_visualizer", "visualizer_overlay", "visualizer_overlay_opacity", "visualizer_background_dim", "visualizer_atmosphere", "visualizer_preset", "visualizer_favorites", "visualizer_starred_only", "visualizer_shuffle", "visualizer_quality", "visualizer_intensity", "visualizer_sensitivity", "visualizer_motion", "visualizer_zoom", "visualizer_sync", "visualizer_auto_change", "visualizer_grab_mode",
	])


func restore_session_format() -> bool:
	if session_format.is_empty():
		return false
	var was_detecting := detecting
	detecting = true
	for key: String in session_format:
		apply(key, session_format[key])
	detecting = was_detecting
	return true


func select_format(mode: int, layout: int) -> void:
	apply("projection", mode)
	apply("stereo", layout)
	if not format_path.is_empty():
		remember_format()
	for key: String in SESSION_FORMAT_PROPERTIES:
		session_format[key] = get(key)
