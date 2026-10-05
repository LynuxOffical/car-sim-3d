extends "res://scripts/rainy_menu.gd"

var name_lab: Label
var tag_lab: Label

func header_text() -> String:
	return "CHOOSE TRACK"


func header_px() -> int:
	return 32


func chrome_kind() -> String:
	return "python"


func world_kind() -> String:
	return "track"


func show_preview() -> bool:
	return false


func build_ui() -> void:
	if GameState.race_island < 0:
		GameState.race_island = 0
	var top := VBoxContainer.new()
	top.set_anchors_preset(PRESET_TOP_WIDE)
	top.offset_top = 100
	top.offset_bottom = 240
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)
	name_lab = UiKit.shadow_label("", 24, Color(1.0, 0.9, 0.45))
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(name_lab)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 20)
	top.add_child(nav)
	_add(nav, UiKit.py_btn("<  PREV", Color(0.85, 0.88, 0.9), 22, 200), func() -> void:
		_step(-1)
	)
	_add(nav, UiKit.py_btn("ENTER  START", Color(0.5, 1.0, 0.55), 24, 280), _start)
	_add(nav, UiKit.py_btn("NEXT  >", Color(0.85, 0.88, 0.9), 22, 200), func() -> void:
		_step(1)
	)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bottom.offset_top = -140
	bottom.offset_bottom = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	add_child(bottom)
	tag_lab = UiKit.shadow_label("", 22, Color(0.82, 0.85, 0.92))
	tag_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(tag_lab)
	var hint := UiKit.shadow_label("LEFT/RIGHT browse    ENTER start    ESC back", 16, Color(0.7, 0.72, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	rebuild_track(GameState.race_island)
	_sync()


func _step(dir: int) -> void:
	var n := IslandWorld.DEFS.size()
	GameState.race_island = posmod(GameState.race_island + dir, n)
	rebuild_track(GameState.race_island)
	_sync()


func _sync() -> void:
	var i := clampi(GameState.race_island, 0, IslandWorld.DEFS.size() - 1)
	var spec: Dictionary = IslandWorld.DEFS[i]
	if name_lab:
		name_lab.text = "<   %s   >" % str(spec["name"])
	if tag_lab:
		tag_lab.text = str(spec.get("tag", ""))


func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/loading.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("ui_accept"):
		_start()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/garage.tscn")
