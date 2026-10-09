extends "res://scripts/rainy_menu.gd"

var players_lab: Label
var chat_lab: Label
var chat_edit: LineEdit
var _launching := false

func header_text() -> String:
	return "ROOM  %s" % Net.room


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
	players_lab = UiKit.shadow_label("players …", 20, Color(0.9, 0.93, 0.95))
	players_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(players_lab)
	if Net.hosting:
		_add(col, UiKit.py_btn("ENTER  -  START SESSION", Color(0.5, 1.0, 0.55), 22), func() -> void: _start())
	chat_lab = UiKit.shadow_label("", 16, Color(0.8, 0.85, 0.9))
	chat_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(chat_lab)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Chat  -  ENTER to send"
	chat_edit.custom_minimum_size = Vector2(520, 40)
	chat_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_edit.text_submitted.connect(func(t):
		Net.send_chat(t)
		chat_edit.text = ""
	)
	col.add_child(chat_edit)
	_add(col, UiKit.py_btn("ESC  -  LEAVE", Color(0.95, 0.9, 0.55), 18), func() -> void:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/mp_menu.tscn")
	)
	Net.room_updated.connect(_refresh)
	_refresh()


func _add(parent: Control, b: Button, cb: Callable) -> void:
	b.pressed.connect(cb)
	parent.add_child(b)


func _refresh() -> void:
	if _launching:
		return
	if title:
		title.text = "ROOM  %s" % Net.room
	var names: PackedStringArray = PackedStringArray()
	for uid in Net.players.keys():
		var p: Variant = Net.players[uid]
		if typeof(p) == TYPE_DICTIONARY:
			names.append(str(p.get("name", uid)))
	if players_lab:
		players_lab.text = "PLAYERS  %d\n%s" % [names.size(), "   ·   ".join(names)]
	var lines: PackedStringArray = PackedStringArray()
	for m in Net.chat:
		lines.append("%s: %s" % [str(m.get("name", "?")), str(m.get("text", ""))])
	if chat_lab:
		chat_lab.text = "\n".join(lines)
	if Net.started and not Net.hosting:
		_go_drive()


func _start() -> void:
	if _launching or not Net.hosting:
		return
	Net.mark_started()
	_go_drive()


func _go_drive() -> void:
	if _launching:
		return
	_launching = true
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.split_screen = false
	var idx := 0
	if typeof(Net.meta.get("map_idx")) != TYPE_NIL:
		idx = int(Net.meta.get("map_idx", 0))
	GameState.race_island = maxi(idx, 0)
	GameState.change_scene("res://scenes/loading.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	if chat_edit and chat_edit.has_focus():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			chat_edit.release_focus()
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if Net.hosting:
				_start()
		KEY_ESCAPE:
			Net.leave()
			get_tree().change_scene_to_file("res://scenes/mp_menu.tscn")
