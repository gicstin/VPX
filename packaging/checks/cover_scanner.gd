extends "res://scripts/library_scanner.gd"

var requested_paths: Array[String] = []


func cover(path: String) -> void:
	requested_paths.append(path)
