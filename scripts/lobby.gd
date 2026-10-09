extends "res://scripts/rainy_menu.gd"

var players_lab: Label
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
	var hint := UiKit.shadow_label("T  open chat   ·   ENTER send   ·   ESC close", 15, Color(0.72, 0.78, 0.84))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	layer.add_child(preload("res://scripts/mc_chat.gd").new())
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
	if GameState.typing:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if Net.hosting:
				_start()
		KEY_ESCAPE:
			Net.leave()
			get_tree().change_scene_to_file("res://scenes/mp_menu.tscn")
