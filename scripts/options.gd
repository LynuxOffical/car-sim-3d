extends "res://scripts/rainy_menu.gd"

func header_text() -> String:
	return "OPTIONS"


func chrome_kind() -> String:
	return "python"


func show_preview() -> bool:
	return false


func build_ui() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(PRESET_FULL_RECT)
	col.offset_top = 110
	col.offset_bottom = -24
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_add(col, UiKit.py_btn("TAA  %s" % ("ON" if GameState.use_taa else "OFF"), Color(0.87, 0.63, 1.0), 22), func() -> void:
		GameState.use_taa = not GameState.use_taa
		get_tree().reload_current_scene()
	)
	_add(col, UiKit.py_btn("VSYNC  %s" % ("ON" if GameState.vsync else "OFF"), Color(0.87, 0.63, 1.0), 22), func() -> void:
		GameState.vsync = not GameState.vsync
		get_tree().reload_current_scene()
	)
	_add(col, UiKit.py_btn("FOV  %d" % int(GameState.fov), Color(0.7, 0.85, 1.0), 22), func() -> void:
		if GameState.fov < 65.0:
			GameState.fov = 70.0
		elif GameState.fov < 75.0:
			GameState.fov = 80.0
		else:
			GameState.fov = 60.0
		get_tree().reload_current_scene()
	)
	_add(col, UiKit.py_btn("TOUCH CONTROLS  %s" % ("ON" if GameState.touch_enabled else "OFF"), Color(0.8, 0.85, 0.9), 20), func() -> void:
		GameState.touch_enabled = not GameState.touch_enabled
		get_tree().reload_current_scene()
	)
	_add(col, UiKit.py_btn("BACK", Color(0.95, 0.9, 0.55), 22), func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	var hint := UiKit.shadow_label("Graphics quality is G on the main menu (LOW / MEDIUM / HIGH).", 16, Color(0.7, 0.72, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
