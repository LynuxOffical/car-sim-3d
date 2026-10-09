extends "res://scripts/rainy_menu.gd"

var tag_lab: Label
var _items: Array[Button] = []
var _sel := 0

func header_text() -> String:
	return "CAR-SIM-3D"


func header_px() -> int:
	return 34


func chrome_kind() -> String:
	return "wanted"


func world_kind() -> String:
	return "track"


func show_preview() -> bool:
	return true


func build_ui() -> void:
	var rail := VBoxContainer.new()
	rail.set_anchors_preset(PRESET_CENTER_LEFT)
	rail.anchor_top = 0.5
	rail.anchor_bottom = 0.5
	rail.anchor_right = 0.0
	rail.offset_left = 56
	rail.offset_right = 420
	rail.offset_top = -170
	rail.offset_bottom = 210
	rail.add_theme_constant_override("separation", 0)
	add_child(rail)
	_mw(rail, "QUICK RACE", _start_single)
	_mw(rail, "SPLIT SCREEN", _start_split)
	_mw(rail, "FREE ROAM", _start_free)
	_mw(rail, "MULTIPLAYER", func() -> void:
		get_tree().change_scene_to_file("res://scenes/mp_menu.tscn")
	)
	_mw(rail, "GUN COMBAT", _start_guns)
	_mw(rail, "WORLD TOUR", _start_roam)
	_mw(rail, "LAN PARTY", func() -> void:
		get_tree().change_scene_to_file("res://scenes/lan_menu.tscn")
	)
	_mw(rail, "OPTIONS", func() -> void:
		get_tree().change_scene_to_file("res://scenes/options.tscn")
	)
	_mw(rail, "QUIT", func() -> void:
		get_tree().quit()
	)
	_paint_sel()

	var streak := ""
	if GameState.win_streak > 0:
		streak = "   ·   WIN STREAK x%d" % GameState.win_streak
	tag_lab = UiKit.shadow_label("ENTER  ·  1-9  ·  L O T G U  OPTIONS%s" % streak, 13, Color(0.70, 0.72, 0.74))
	tag_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lab.set_anchors_preset(PRESET_BOTTOM_WIDE)
	tag_lab.offset_left = 24
	tag_lab.offset_right = -24
	tag_lab.offset_top = -28
	tag_lab.offset_bottom = -8
	add_child(tag_lab)
	_sync_features()


func _mw(parent: Control, text: String, cb: Callable) -> void:
	var idx := _items.size()
	var b := UiKit.mw_btn(text, false, 340)
	b.set_meta("mw_name", text)
	b.set_meta("mw_cb", cb)
	b.pressed.connect(func() -> void:
		_sel = idx
		_paint_sel()
		cb.call()
	)
	parent.add_child(b)
	_items.append(b)


func _paint_sel() -> void:
	for i in _items.size():
		var on := i == _sel
		var name := str(_items[i].get_meta("mw_name"))
		_items[i].text = (">  " + name) if on else name
		UiKit.mw_style(_items[i], on)


func _activate() -> void:
	if _sel < 0 or _sel >= _items.size():
		return
	var cb: Variant = _items[_sel].get_meta("mw_cb")
	if cb is Callable:
		(cb as Callable).call()


func _sync_features() -> void:
	apply_menu_settings()
	if status:
		var car: Dictionary = GameState.selected_car()
		status.text = "%s\n%s   ·   %s" % [
			str(car.get("name", "RACER")),
			str(GameState.weather().get("name", "CLEAR")),
			GameState.quality_name(),
		]


func _go_car_select() -> void:
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _start_single() -> void:
	GameState.mode = GameState.Mode.RACE
	GameState.split_screen = false
	GameState.gun_enabled = false
	_go_car_select()


func _start_split() -> void:
	GameState.mode = GameState.Mode.RACE
	GameState.split_screen = true
	GameState.gun_enabled = false
	_go_car_select()


func _start_free() -> void:
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.split_screen = GameState.freeplay_split
	_go_car_select()


func _start_guns() -> void:
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.split_screen = false
	GameState.gun_enabled = true
	_go_car_select()


func _start_roam() -> void:
	GameState.mode = GameState.Mode.ROAM
	GameState.race_island = -1
	GameState.split_screen = false
	_go_car_select()


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_G:
			GameState.cycle_quality()
			_sync_features()
			get_viewport().set_input_as_handled()
		KEY_T:
			GameState.cycle_weather()
			_sync_features()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_UP, KEY_W:
			_sel = posmod(_sel - 1, _items.size())
			_paint_sel()
		KEY_DOWN, KEY_S:
			_sel = posmod(_sel + 1, _items.size())
			_paint_sel()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate()
		KEY_1:
			_start_single()
		KEY_2:
			_start_split()
		KEY_3:
			_start_free()
		KEY_4:
			get_tree().change_scene_to_file("res://scenes/mp_menu.tscn")
		KEY_5:
			_start_guns()
		KEY_6:
			_start_roam()
		KEY_7:
			get_tree().change_scene_to_file("res://scenes/lan_menu.tscn")
		KEY_8:
			get_tree().change_scene_to_file("res://scenes/options.tscn")
		KEY_9:
			get_tree().quit()
		KEY_N:
			get_tree().change_scene_to_file("res://scenes/lan_menu.tscn")
		KEY_L:
			GameState.cycle_laps()
			_sync_features()
		KEY_O:
			GameState.cycle_opponents()
			_sync_features()
		KEY_P:
			GameState.police_enabled = not GameState.police_enabled
			_sync_features()
		KEY_F:
			GameState.freeplay_split = not GameState.freeplay_split
			_sync_features()
		KEY_U:
			GameState.gun_enabled = not GameState.gun_enabled
			_sync_features()
		KEY_ESCAPE:
			get_tree().quit()
