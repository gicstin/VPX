extends RefCounted

const LIST := [
	["English", "en", "eng"],
	["Arabic", "ar", "ara"],
	["Bulgarian", "bg", "bul"],
	["Chinese", "zh", "chi", "zho", "cmn"],
	["Croatian", "hr", "hrv"],
	["Czech", "cs", "cze", "ces"],
	["Danish", "da", "dan"],
	["Dutch", "nl", "dut", "nld"],
	["Estonian", "et", "est"],
	["Finnish", "fi", "fin"],
	["French", "fr", "fre", "fra"],
	["German", "de", "ger", "deu"],
	["Greek", "el", "gre", "ell"],
	["Hebrew", "he", "heb"],
	["Hindi", "hi", "hin"],
	["Hungarian", "hu", "hun"],
	["Icelandic", "is", "ice", "isl"],
	["Indonesian", "id", "ind"],
	["Italian", "it", "ita"],
	["Japanese", "ja", "jpn"],
	["Korean", "ko", "kor"],
	["Latvian", "lv", "lav"],
	["Lithuanian", "lt", "lit"],
	["Malay", "ms", "may", "msa"],
	["Norwegian", "no", "nor", "nob", "nno", "nb", "nn"],
	["Persian", "fa", "per", "fas"],
	["Polish", "pl", "pol"],
	["Portuguese", "pt", "por"],
	["Romanian", "ro", "rum", "ron"],
	["Russian", "ru", "rus"],
	["Serbian", "sr", "srp"],
	["Slovak", "sk", "slo", "slk"],
	["Slovenian", "sl", "slv"],
	["Spanish", "es", "spa"],
	["Swedish", "sv", "swe"],
	["Thai", "th", "tha"],
	["Turkish", "tr", "tur"],
	["Ukrainian", "uk", "ukr"],
	["Vietnamese", "vi", "vie"],
]


static func names() -> PackedStringArray:
	var result := PackedStringArray()
	for entry in LIST:
		result.append(entry[0])
	return result


static func index_of(code: String) -> int:
	var lower := code.strip_edges().to_lower()
	if lower.is_empty():
		return -1
	for i in LIST.size():
		var entry: Array = LIST[i]
		if lower == entry[0].to_lower() or entry.slice(1).has(lower):
			return i
	return -1


static func matches(code: String, language: int) -> bool:
	return language >= 0 and index_of(code) == language


static func display_name(code: String) -> String:
	var index := index_of(code)
	if index >= 0:
		return LIST[index][0]
	return "" if code in ["", "und"] else code.capitalize()


static func system_language() -> int:
	var index := index_of(OS.get_locale_language())
	return index if index >= 0 else 0
