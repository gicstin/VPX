extends RefCounted

const GRID := 24.0
const STROKE := 2.0
const HEADER := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"%s\" stroke-linecap=\"round\" stroke-linejoin=\"round\">%s</svg>"
const SOLID := "fill=\"#ffffff\" stroke=\"none\""
const SHAPES := {
	"play": "<path d=\"M7.5 4.8v14.4a.9.9 0 0 0 1.4.8l11.2-7.2a.9.9 0 0 0 0-1.6L8.9 4a.9.9 0 0 0-1.4.8z\" fill=\"#ffffff\" stroke=\"none\"/>",
	"pause": "<rect x=\"5.5\" y=\"4.5\" width=\"4.5\" height=\"15\" rx=\"1.2\" fill=\"#ffffff\" stroke=\"none\"/><rect x=\"14\" y=\"4.5\" width=\"4.5\" height=\"15\" rx=\"1.2\" fill=\"#ffffff\" stroke=\"none\"/>",
	"prev": "<path d=\"M18.5 5.5v13a.8.8 0 0 1-1.3.6L9 12.6a.8.8 0 0 1 0-1.2l8.2-6.5a.8.8 0 0 1 1.3.6z\" fill=\"#ffffff\" stroke=\"none\"/><path d=\"M6 5v14\"/>",
	"next": "<path d=\"M5.5 5.5v13a.8.8 0 0 0 1.3.6l8.2-6.5a.8.8 0 0 0 0-1.2L6.8 4.9a.8.8 0 0 0-1.3.6z\" fill=\"#ffffff\" stroke=\"none\"/><path d=\"M18 5v14\"/>",
	"back": "<path d=\"M10 4.5h2a8 8 0 1 1-8 8\"/><path d=\"M12.5 1.8L9.8 4.5l2.7 2.7\"/><path d=\"M8.6 11.2l1.4-1v6\" stroke-width=\"1.7\"/><ellipse cx=\"14.2\" cy=\"13.2\" rx=\"1.9\" ry=\"3\" stroke-width=\"1.7\"/>",
	"forward": "<path d=\"M14 4.5h-2a8 8 0 1 0 8 8\"/><path d=\"M11.5 1.8l2.7 2.7-2.7 2.7\"/><path d=\"M8.6 11.2l1.4-1v6\" stroke-width=\"1.7\"/><ellipse cx=\"14.2\" cy=\"13.2\" rx=\"1.9\" ry=\"3\" stroke-width=\"1.7\"/>",
	"volume": "<path d=\"M4 9.2h3.2L12 5.2v13.6l-4.8-4H4z\" fill=\"#ffffff\"/><path d=\"M15.5 9a4.2 4.2 0 0 1 0 6\"/><path d=\"M18.3 6.3a8 8 0 0 1 0 11.4\"/>",
	"volume_off": "<path d=\"M4 9.2h3.2L12 5.2v13.6l-4.8-4H4z\" fill=\"#ffffff\"/><path d=\"M16 9.5l5 5M21 9.5l-5 5\"/>",
	"folder": "<path d=\"M3 7a2 2 0 0 1 2-2h4.2l2.1 2.3H19a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z\"/>",
	"folder_solid": "<path d=\"M3 7a2 2 0 0 1 2-2h4.2l2.1 2.3H19a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z\" fill=\"#ffffff\" stroke=\"none\"/>",
	"up": "<path d=\"M12 19.5V5\"/><path d=\"M5.8 11.2L12 5l6.2 6.2\"/>",
	"home": "<path d=\"M3.5 11L12 4l8.5 7\"/><path d=\"M6 9.3V19.5h12V9.3\"/><path d=\"M10 19.5v-5h4v5\"/>",
	"drive": "<rect x=\"3\" y=\"12.5\" width=\"18\" height=\"7\" rx=\"1.8\"/><path d=\"M5 12.5L7.3 5.5h9.4l2.3 7\"/><circle cx=\"16.8\" cy=\"16\" r=\"1\" fill=\"#ffffff\" stroke=\"none\"/>",
	"grid": "<rect x=\"4\" y=\"4\" width=\"6.5\" height=\"6.5\" rx=\"1.4\"/><rect x=\"13.5\" y=\"4\" width=\"6.5\" height=\"6.5\" rx=\"1.4\"/><rect x=\"4\" y=\"13.5\" width=\"6.5\" height=\"6.5\" rx=\"1.4\"/><rect x=\"13.5\" y=\"13.5\" width=\"6.5\" height=\"6.5\" rx=\"1.4\"/>",
	"list": "<path d=\"M9 6.5h11M9 12h11M9 17.5h11\"/><circle cx=\"4.8\" cy=\"6.5\" r=\"1.1\" fill=\"#ffffff\" stroke=\"none\"/><circle cx=\"4.8\" cy=\"12\" r=\"1.1\" fill=\"#ffffff\" stroke=\"none\"/><circle cx=\"4.8\" cy=\"17.5\" r=\"1.1\" fill=\"#ffffff\" stroke=\"none\"/>",
	"sort": "<path d=\"M7 4.5v15\"/><path d=\"M3.8 16.3L7 19.5l3.2-3.2\"/><path d=\"M13 6.5h8M13 12h6M13 17.5h4\"/>",
	"recent": "<circle cx=\"12\" cy=\"12\" r=\"8.5\"/><path d=\"M12 7.5V12l3.2 2\"/>",
	"recenter": "<circle cx=\"12\" cy=\"12\" r=\"6.5\"/><circle cx=\"12\" cy=\"12\" r=\"2\" fill=\"#ffffff\" stroke=\"none\"/><path d=\"M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3\"/>",
	"close": "<path d=\"M6.5 6.5l11 11M17.5 6.5l-11 11\"/>",
	"power": "<path d=\"M12 3.5v8\"/><path d=\"M6.6 6.9a7.8 7.8 0 1 0 10.8 0\"/>",
	"library": "<rect x=\"3\" y=\"5\" width=\"18\" height=\"14\" rx=\"2.4\"/><path d=\"M10.2 9.3v5.4a.4.4 0 0 0 .6.3l4.3-2.7a.4.4 0 0 0 0-.6l-4.3-2.7a.4.4 0 0 0-.6.3z\" fill=\"#ffffff\" stroke=\"none\"/>",
	"format": "<path d=\"M5.5 6.5h13A2.5 2.5 0 0 1 21 9v6.5A2.5 2.5 0 0 1 18.5 18h-3.3l-1.8-2.4h-2.8L8.8 18H5.5A2.5 2.5 0 0 1 3 15.5V9a2.5 2.5 0 0 1 2.5-2.5z\"/><circle cx=\"8\" cy=\"11.8\" r=\"1.6\"/><circle cx=\"16\" cy=\"11.8\" r=\"1.6\"/>",
	"picture": "<circle cx=\"12\" cy=\"12\" r=\"4\"/><path d=\"M12 2.8v2M12 19.2v2M2.8 12h2M19.2 12h2M5.5 5.5l1.4 1.4M17.1 17.1l1.4 1.4M5.5 18.5l1.4-1.4M17.1 6.9l1.4-1.4\"/>",
	"angles": "<path d=\"M12 3v18M3 12h18\"/><path d=\"M9.2 5.8L12 3l2.8 2.8M9.2 18.2L12 21l2.8-2.8M5.8 9.2L3 12l2.8 2.8M18.2 9.2L21 12l-2.8 2.8\"/>",
	"passthrough": "<path d=\"M2.5 12S6 5.8 12 5.8 21.5 12 21.5 12 18 18.2 12 18.2 2.5 12 2.5 12z\"/><circle cx=\"12\" cy=\"12\" r=\"3\"/>",
	"tune": "<path d=\"M6 4v6M6 14v6M12 4v2M12 10v10M18 4v9M18 17v3\"/><circle cx=\"6\" cy=\"12\" r=\"2\"/><circle cx=\"12\" cy=\"8\" r=\"2\"/><circle cx=\"18\" cy=\"15\" r=\"2\"/>",
	"subtitles": "<rect x=\"3\" y=\"5\" width=\"18\" height=\"14\" rx=\"2.5\"/><path d=\"M7 12.5h3.5M13 12.5h4M7 15.5h6M15.5 15.5H17\"/>",
	"audio": "<path d=\"M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2\"/>",
	"screen": "<path d=\"M3 6.5c6-2 12-2 18 0v11c-6-2-12-2-18 0z\"/>",
	"system": "<path d=\"M4 7h9.5M17.5 7H20M4 17h2.5M10.5 17H20\"/><circle cx=\"15.5\" cy=\"7\" r=\"2\"/><circle cx=\"8.5\" cy=\"17\" r=\"2\"/>",
	"controls": "<path d=\"M7.2 7h9.6a4.6 4.6 0 0 1 4.4 5.9l-1.1 3.8a2.4 2.4 0 0 1-4 1L14 15.8h-4l-2.1 1.9a2.4 2.4 0 0 1-4-1l-1.1-3.8A4.6 4.6 0 0 1 7.2 7z\"/><path d=\"M8 9.8v3.6M6.2 11.6h3.6\"/><circle cx=\"15.4\" cy=\"10.6\" r=\"1\" fill=\"#ffffff\" stroke=\"none\"/><circle cx=\"17.4\" cy=\"12.6\" r=\"1\" fill=\"#ffffff\" stroke=\"none\"/>",
	"shuffle": "<path d=\"M3 7h3c4.5 0 5.5 10 10 10h4.5\"/><path d=\"M3 17h3c1.7 0 2.8-1.4 3.7-3.2M14.3 10.2C15.2 8.4 16.3 7 18 7h2.5\"/><path d=\"M18 4l3 3-3 3M18 14l3 3-3 3\"/>",
	"repeat": "<path d=\"M4 11.5V10a3.5 3.5 0 0 1 3.5-3.5H20\"/><path d=\"M17 3.5l3 3-3 3\"/><path d=\"M20 12.5V14a3.5 3.5 0 0 1-3.5 3.5H4\"/><path d=\"M7 20.5l-3-3 3-3\"/>",
	"stop_end": "<rect x=\"6\" y=\"6\" width=\"12\" height=\"12\" rx=\"2\"/>",
	"playlist": "<path d=\"M4 6.5h12M4 12h12M4 17.5h7\"/><path d=\"M15 14.5v6l5-3z\" fill=\"#ffffff\"/>",
	"photo": "<rect x=\"3\" y=\"4.5\" width=\"18\" height=\"15\" rx=\"2.2\"/><circle cx=\"8.5\" cy=\"9.5\" r=\"1.7\"/><path d=\"M21 15.5l-5-5-9.5 9\"/>",
	"film": "<rect x=\"3\" y=\"4.5\" width=\"18\" height=\"15\" rx=\"2.2\"/><path d=\"M7.5 4.5v15M16.5 4.5v15M3 9.5h4.5M3 14.5h4.5M16.5 9.5H21M16.5 14.5H21\"/>",
	"search": "<circle cx=\"10.5\" cy=\"10.5\" r=\"6\"/><path d=\"M15 15l5 5\"/>",
	"keyboard": "<rect x=\"2\" y=\"5\" width=\"20\" height=\"14\" rx=\"2\"/><path d=\"M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 12h.01M10 12h.01M14 12h.01M18 12h.01M7 16h10\"/>",
	"network": "<rect x=\"9\" y=\"3.5\" width=\"6\" height=\"5\" rx=\"1\"/><rect x=\"3\" y=\"15.5\" width=\"6\" height=\"5\" rx=\"1\"/><rect x=\"15\" y=\"15.5\" width=\"6\" height=\"5\" rx=\"1\"/><path d=\"M12 8.5v3.5M6 15.5V12h12v3.5\"/>",
	"link": "<path d=\"M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1\"/><path d=\"M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1\"/>",
	"download": "<path d=\"M12 4v11\"/><path d=\"M7 10.5l5 5 5-5\"/><path d=\"M5 19.5h14\"/>",
	"crop": "<path d=\"M7 3v14h14\"/><path d=\"M3 7h14v14\"/>",
	"plus": "<path d=\"M12 5v14M5 12h14\"/>",
	"trash": "<path d=\"M4.5 7h15M9.5 7V4.8h5V7\"/><path d=\"M6.5 7l.9 12.2a1.5 1.5 0 0 0 1.5 1.3h6.2a1.5 1.5 0 0 0 1.5-1.3L17.5 7\"/>",
	"bookmark": "<path d=\"M6.5 3.5h11v17l-5.5-4-5.5 4z\"/>",
	"loop": "<path d=\"M4 12a5 5 0 0 1 5-5h9\"/><path d=\"M15.5 4.5L18 7l-2.5 2.5\"/><path d=\"M20 12a5 5 0 0 1-5 5H6\"/><path d=\"M8.5 19.5L6 17l2.5-2.5\"/>",
	"sleep": "<path d=\"M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z\"/>",
	"hand": "<path d=\"M8 12V5.5a1.5 1.5 0 0 1 3 0V11M11 10V4a1.5 1.5 0 0 1 3 0v6M14 10V5.5a1.5 1.5 0 0 1 3 0V13c0 4-2.5 7-6 7-2.5 0-4-1.2-5.5-3.5L3.8 13.2a1.4 1.4 0 0 1 2.3-1.6L8 14\"/>",
	"speed": "<path d=\"M4.5 17a8 8 0 1 1 15 0\"/><path d=\"M12 13l4-4\"/>",
	"radio_unchecked": "<circle cx=\"12\" cy=\"12\" r=\"6\"/>",
	"unchecked": "<rect x=\"5\" y=\"5\" width=\"14\" height=\"14\" rx=\"2\"/>",
	"check": "<path d=\"M5 12.5l4.5 4.5L19 7.5\"/>",
	"pick": "<path d=\"M4 20l1.3-.4 9.4-9.4-2-2-9.4 9.4z\"/><path d=\"M11.6 6.7l5.7 5.7\"/><path d=\"M14 5.5l2.2-2.2a2.1 2.1 0 0 1 3 0l1.5 1.5a2.1 2.1 0 0 1 0 3L18.5 10\"/>",
	"reset": "<path d=\"M10 4.5h2a7.5 7.5 0 1 1-7.5 7.5\"/><path d=\"M12.5 1.8L9.8 4.5l2.7 2.7\"/>",
	"chevron_down": "<path d=\"M6 9.5l6 6 6-6\"/>",
	"chevron_right": "<path d=\"M9.5 6l6 6-6 6\"/>",
	"chevron_left": "<path d=\"M14.5 6l-6 6 6 6\"/>",
	"info": "<circle cx=\"12\" cy=\"12\" r=\"8.5\"/><path d=\"M12 11v5.5\"/><circle cx=\"12\" cy=\"7.8\" r=\"1.1\" fill=\"#ffffff\" stroke=\"none\"/>",
	"logo": "<path d=\"M3.5 8.5A2.5 2.5 0 0 1 6 6h12a2.5 2.5 0 0 1 2.5 2.5v6.2a2.5 2.5 0 0 1-2.5 2.5h-3.1l-1.7-2.2h-2.4l-1.7 2.2H6a2.5 2.5 0 0 1-2.5-2.5z M10.5 9.4v3.8l3.2-1.9z\" fill=\"#ffffff\" fill-rule=\"evenodd\" stroke=\"none\"/>",
}

const COLORED := {
	"switch_on": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"44\" height=\"24\" viewBox=\"0 0 44 24\"><rect x=\"1\" y=\"1\" width=\"42\" height=\"22\" rx=\"11\" fill=\"#{track}\" stroke=\"#{border}\"/><circle cx=\"31\" cy=\"12\" r=\"8.2\" fill=\"#{thumb}\"/></svg>",
	"switch_off": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"44\" height=\"24\" viewBox=\"0 0 44 24\"><rect x=\"1.5\" y=\"1.5\" width=\"41\" height=\"21\" rx=\"10.5\" fill=\"#{track}\" stroke=\"#{border}\" stroke-width=\"1.5\"/><circle cx=\"13\" cy=\"12\" r=\"8.2\" fill=\"#{thumb}\"/></svg>",
}

static var cache := {}


static func texture(name: String, size: int, colors: Dictionary = {}) -> Texture2D:
	var key := "%s@%d:%s" % [name, size, str(colors)]
	if cache.has(key):
		return cache[key]
	var image := Image.new()
	if image.load_svg_from_string(_svg(name, colors), size / GRID) != OK:
		return null
	var result := ImageTexture.create_from_image(image)
	cache[key] = result
	return result


static func _svg(name: String, colors: Dictionary) -> String:
	if COLORED.has(name):
		return COLORED[name].format(colors)
	match name:
		"star":
			return HEADER % [STROKE, "<path d=\"%s\" %s/>" % [_star_path(), SOLID]]
		"star_outline":
			return HEADER % [STROKE, "<path d=\"%s\"/>" % _star_path()]
	return HEADER % [STROKE, SHAPES.get(name, SHAPES["info"])]


static func _star_path() -> String:
	var points := PackedStringArray()
	for i in 10:
		var radius := 9.2 if i % 2 == 0 else 4.1
		var angle := -PI * 0.5 + i * PI / 5.0
		points.append("%.2f %.2f" % [12.0 + cos(angle) * radius, 12.8 + sin(angle) * radius])
	return "M" + " L".join(points) + "z"
