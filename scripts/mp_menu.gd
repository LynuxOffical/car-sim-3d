extends "res://scripts/rainy_menu.gd"

var code_edit: LineEdit
var note: Label

func header_text() -> String:
	return "ONLINE MULTIPLAYER"


func chrome_kind() -> String:
	return "python"


func world_kind() -> String:
	return "track"


func show_preview() -> bool:
	return false


func build_ui() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(PRESET_FULL_RECT)
	col.offset_top = 96
	col.offset_bottom = -16
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	note = UiKit.shadow_label("Firebase rooms. Host a 5-digit code, friends join. Same as the Python game.", 16, Color(0.82, 0.86, 0.92))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	_add(col, UiKit.py_btn("H  -  HOST A ROOM", Color(0.5, 1.0, 0.55), 22), func() -> void: _host())
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "5-digit room code"
	code_edit.max_length = 5
	code_edit.custom_minimum_size = Vector2(420, 44)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_size_override("font_size", 24)
	col.add_child(code_edit)
	_add(col, UiKit.py_btn("J  -  JOIN WITH CODE", Color(0.55, 0.95, 1.0), 20), func() -> void: _join())
	_add(col, UiKit.py_btn("ESC  -  BACK", Color(0.95, 0.9, 0.55), 18), func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	if Net.configured:
		note.text = "Firebase Realtime Database ready. Share the room code."
	else:
		note.text = "Missing firebase_config.json (apiKey + databaseURL)"


func _add(parent: Control, b: Button, cb: Callable) -> void:
	b.pressed.connect(cb)
	parent.add_child(b)


func _host() -> void:
	note.text = "Creating room…"
	var ok: bool = await Net.host_room()
	if not ok:
		note.text = Net.error if Net.error != "" else Net.status
		return
	if is_inside_tree():
		GameState.change_scene("res://scenes/lobby.tscn")


func _join() -> void:
	note.text = "Joining…"
	var ok: bool = await Net.join_room(code_edit.text)
	if not ok:
		note.text = Net.error if Net.error != "" else "Join failed"
		return
	if is_inside_tree():
		GameState.change_scene("res://scenes/lobby.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	if code_edit and code_edit.has_focus():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			code_edit.release_focus()
		return
	match (event as InputEventKey).physical_keycode:
		KEY_H:
			_host()
		KEY_J:
			_join()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
