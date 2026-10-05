extends "res://scripts/rainy_menu.gd"

var ip_edit: LineEdit
var note: Label

func header_text() -> String:
	return "LAN PARTY"


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
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var ips := ", ".join(Lan.addresses())
	if ips.is_empty():
		ips = "127.0.0.1"
	note = UiKit.shadow_label("Same Wi-Fi. Host this PC, friends type the IPv4. Circuit race after car + track.", 16, Color(0.82, 0.86, 0.92))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	var ip_lab := UiKit.shadow_label("Your IP  ·  %s    port %d" % [ips, Lan.PORT], 16, Color(0.95, 0.9, 0.55))
	ip_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ip_lab)
	_add(col, UiKit.py_btn("H  -  HOST LAN", Color(0.5, 1.0, 0.55), 22), func() -> void: _host())
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IPv4  e.g. 192.168.1.20"
	ip_edit.text = Lan.join_ip
	ip_edit.custom_minimum_size = Vector2(420, 44)
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_edit.add_theme_font_size_override("font_size", 20)
	col.add_child(ip_edit)
	_add(col, UiKit.py_btn("J  -  JOIN LAN", Color(0.55, 0.95, 1.0), 20), func() -> void: _join())
	_add(col, UiKit.py_btn("ESC  -  BACK", Color(0.95, 0.9, 0.55), 18), func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)


func _host() -> void:
	if not Lan.host_lan():
		note.text = Lan.error
		return
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.split_screen = false
	if GameState.race_island < 0:
		GameState.race_island = 0
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _join() -> void:
	if not Lan.join_lan(ip_edit.text):
		note.text = Lan.error
		return
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.split_screen = false
	if GameState.race_island < 0:
		GameState.race_island = 0
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	if ip_edit and ip_edit.has_focus():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			ip_edit.release_focus()
		return
	match (event as InputEventKey).physical_keycode:
		KEY_H:
			_host()
		KEY_J:
			_join()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
