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
	var card := UiKit.panel()
	card.set_anchors_preset(PRESET_BOTTOM_WIDE)
	card.offset_left = 80
	card.offset_right = -80
	card.offset_top = -210
	card.offset_bottom = -22
	add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	name_lab = UiKit.shadow_label("", 26, Color(0.96, 0.97, 0.99))
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lab)
	tag_lab = UiKit.shadow_label("", 16, Color(0.72, 0.80, 0.88))
	tag_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag_lab)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 14)
	col.add_child(nav)
	_add(nav, UiKit.menu_btn("<  Prev", Color(0.70, 0.74, 0.80), 16, 150), func() -> void:
		_step(-1)
	)
	_add(nav, UiKit.menu_btn("Enter  Race", Color(0.42, 0.86, 0.52), 16, 220), _start)
	_add(nav, UiKit.menu_btn("Next  >", Color(0.70, 0.74, 0.80), 16, 150), func() -> void:
		_step(1)
	)
	var hint := UiKit.shadow_label("LEFT / RIGHT browse    ENTER start    ESC garage", 13, Color(0.62, 0.66, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
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
		tag_lab.text = "%s    ·    %d / %d" % [str(spec.get("tag", "")), i + 1, IslandWorld.DEFS.size()]


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
