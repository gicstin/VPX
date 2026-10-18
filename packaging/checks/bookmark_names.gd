extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS: " if ok else "FAIL: ", label)


func frames() -> void:
	for i in 3:
		await process_frame


func _run() -> void:
	create_timer(45).timeout.connect(func() -> void: quit(2))
	var settings := root.get_node("Settings")
	settings.last_file = ""
	settings.auto_crop = false
	var library := root.get_node("Library")
	library.entries = {}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	var player: Node = main.player
	var quick = main.ui.quick
	player.current_path = "bookmark-test.mp4"
	library.set_pref(player.current_path, "bookmarks", [24.0, 11.0])
	check(player.bookmarks() == [11.0, 24.0] and player.bookmark_name(11.0).is_empty(), "legacy timestamps stay compatible")
	check(player.rename_bookmark(11.0, "  Opening Ελληνικά  ") and player.bookmark_name(11.0) == "Opening Ελληνικά", "rename trims edges and preserves Unicode")
	check(player.bookmarks() == [11.0, 24.0] and player.mark_times() == [11.0, 24.0], "names preserve timeline and navigation")
	check(not player.rename_bookmark(99.0, "Missing"), "missing bookmark cannot gain a name")
	check(not player.rename_bookmark(11.0, "x".repeat(65)) and not player.rename_bookmark(11.0, "bad\nname"), "reject oversized and multiline names")
	check(player.bookmark_name(11.0) == "Opening Ελληνικά", "invalid rename keeps existing name")
	check(library.save() == OK, "save named bookmarks")
	library.entries = {}
	library._load()
	check(player.bookmark_name(11.0) == "Opening Ελληνικά" and player.bookmark_name_history().has("Opening Ελληνικά"), "name and presets survive library reload")
	player.rename_bookmark(11.0, "Action")
	player.rename_bookmark(24.0, "ACTION")
	check(player.bookmark_name_history() == PackedStringArray(["ACTION", "Opening Ελληνικά"]), "history deduplicates names ignoring case")
	player.remove_bookmark(11.0)
	check(player.bookmarks() == [24.0] and player.bookmark_name(11.0).is_empty() and player.bookmark_name_history().has("Opening Ελληνικά"), "delete removes label but retains previous names")
	player.current_path = "other-bookmark-test.mp4"
	library.set_pref(player.current_path, "bookmarks", [24.0])
	check(player.bookmark_name(24.0).is_empty() and player.bookmark_name_history().has("ACTION"), "labels stay per file and presets work across media")
	main.ui.open_quick(5)
	quick._rebuild_marks()
	await frames()
	quick.bookmark_list.get_child(0).get_child(1).pressed.emit()
	check(quick.bookmark_editor.visible and quick.bookmark_presets.item_count == 3, "Rename opens editor with history presets")
	quick.bookmark_presets.item_selected.emit(1)
	check(quick.bookmark_name_field.text == "ACTION", "preset fills editable name")
	quick._save_bookmark_name()
	await frames()
	check(not quick.bookmark_editor.visible and "ACTION" in quick.bookmark_list.get_child(0).get_child(0).text, "saving shows bookmark name beside timestamp")
	quick._edit_bookmark(24.0)
	quick.bookmark_name_requested.emit(quick.bookmark_name_field.text)
	check(main.ui.keyboard.visible and main.ui.keyboard_purpose == "bookmark_name", "VR keyboard opens for bookmark name")
	main.ui.keyboard.field.text = "Keyboard name"
	main.ui.keyboard._submit()
	check(quick.bookmark_name_field.text == "Keyboard name", "VR keyboard returns edited name")
	quick._save_bookmark_name()
	check(player.bookmark_name(24.0) == "Keyboard name", "VR name saves")
	quick._edit_bookmark(24.0)
	quick.bookmark_name_field.text = "Discard me"
	quick.bookmark_editor.get_child(2).get_child(2).pressed.emit()
	check(player.bookmark_name(24.0) == "Keyboard name" and not quick.bookmark_editor.visible, "cancel leaves saved name untouched")
	quick._edit_bookmark(24.0)
	player.current_path = "bookmark-test.mp4"
	quick._save_bookmark_name()
	check(player.bookmark_name(24.0) == "ACTION", "media switch cannot rename another file")
	check(player.rename_bookmark(24.0, "   ") and player.bookmark_name(24.0).is_empty() and player.bookmarks() == [24.0], "blank name restores unnamed bookmark")
	for i in 40:
		player.rename_bookmark(24.0, "Name %d" % i)
	check(player.bookmark_name_history().size() == player.BOOKMARK_HISTORY_MAX, "name history stays bounded")
	var photo = ClassDB.instantiate("VPXPanorama")
	player.image = photo
	player.current_path = "photo.jpg"
	player.music_path = "song.flac"
	library.set_pref(player.music_path, "bookmarks", [5.0])
	check(player.rename_bookmark(5.0, "Chorus") and library.get_pref("photo.jpg", "bookmark_names") == null, "background music labels belong to audio file")
	player.remove_bookmark(5.0)
	check(library.get_pref("song.flac", "bookmarks") == null and library.get_pref("song.flac", "bookmark_names") == null, "background music deletion uses audio file")
	player.add_bookmark()
	check(not player.bookmarks().is_empty() and library.get_pref("photo.jpg", "bookmarks") == null, "background music additions use audio file")
	player.image = null
	player.music_path = ""
	photo = null
	main.queue_free()
	await frames()
	print("bookmark names: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
