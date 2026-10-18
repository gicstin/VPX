extends "res://scripts/ui.gd"

var selected_paths: Array[String] = []


func open_media(path: String, _extra := {}) -> void:
	selected_paths.append(path)
