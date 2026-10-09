extends "res://scripts/rainy_menu.gd"

var laps_btn: Button
var opp_btn: Button
var police_btn: Button
var fpsplit_btn: Button
var gfx_btn: Button
var weather_btn: Button
var gun_btn: Button
var tag_lab: Label
var _items: Array[Button] = []
var _sel := 0

func header_text() -> String:
	return "CAR-SIM-3D"


func header_px() -> int:
	return 36


func chrome_kind() -> String:
	return "wanted"


func world_kind() -> String:
	return "track"


func show_preview() -> bool:
	return true


func build_ui() -> void:
	var rail := VBoxContainer.new()
	rail.set_anchors_preset(PRESET_LEFT_WIDE)
	rail.offset_left = 40
	rail.offset_right = 500
	rail.offset_top = 138
	rail.offset_bottom = -86
	rail.add_theme_constant_override("separation", 2)
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

	var card := UiKit.mw_panel()
	card.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	card.anchor_left = 1.0
	card.anchor_top = 1.0
	card.offset_left = -420
	card.offset_top = -236
	card.offset_right = -36
	card.offset_bottom = -28
	add_child(card)
	var opt := VBoxContainer.new()
	opt.add_theme_constant_override("separation", 2)
	card.add_child(opt)
	var head := UiKit.shadow_label("TRANSMISSION", 12, UiKit.GOLD())
	opt.add_child(head)
	laps_btn = UiKit.mw_btn("", false, 360)
	opp_btn = UiKit.mw_btn("", false, 360)
	police_btn = UiKit.mw_btn("", false, 360)
	fpsplit_btn = UiKit.mw_btn("", false, 360)
	gfx_btn = UiKit.mw_btn("", false, 360)
	weather_btn = UiKit.mw_btn("", false, 360)
	gun_btn = UiKit.mw_btn("", false, 360)
	for b in [laps_btn, opp_btn, police_btn, fpsplit_btn, gfx_btn, weather_btn, gun_btn]:
		b.custom_minimum_size = Vector2(360, 26)
		b.add_theme_font_size_override("font_size", 14)
	_add(opt, laps_btn, func() -> void:
		GameState.cycle_laps()
		_sync_features()
	)
	_add(opt, opp_btn, func() -> void:
		GameState.cycle_opponents()
		_sync_features()
	)
	_add(opt, police_btn, func() -> void:
		GameState.police_enabled = not GameState.police_enabled
		_sync_features()
	)
	_add(opt, fpsplit_btn, func() -> void:
		GameState.freeplay_split = not GameState.freeplay_split
		_sync_features()
	)
	_add(opt, gfx_btn, func() -> void:
		GameState.cycle_quality()
		_sync_features()
	)
	_add(opt, weather_btn, func() -> void:
		GameState.cycle_weather()
		_sync_features()
	)
	_add(opt, gun_btn, func() -> void:
		GameState.gun_enabled = not GameState.gun_enabled
		_sync_features()
	)

	var streak := ""
	if GameState.win_streak > 0:
		streak = "   WIN STREAK x%d" % GameState.win_streak
	tag_lab = UiKit.shadow_label("1-9 SELECT   ENTER CONFIRM   ESC QUIT%s" % streak, 13, Color(0.62, 0.66, 0.70))
	tag_lab.set_anchors_preset(PRESET_BOTTOM_WIDE)
	tag_lab.offset_left = 48
	tag_lab.offset_right = -48
	tag_lab.offset_top = -26
	tag_lab.offset_bottom = -6
	add_child(tag_lab)
	_sync_features()


func _mw(parent: Control, text: String, cb: Callable) -> void:
	var idx := _items.size()
	var b := UiKit.mw_btn("%d   %s" % [idx + 1, text], false, 440)
	b.pressed.connect(func() -> void:
		_sel = idx
		_paint_sel()
		cb.call()
	)
	parent.add_child(b)
	_items.append(b)
	b.set_meta("mw_cb", cb)


func _paint_sel() -> void:
	for i in _items.size():
		UiKit.mw_style(_items[i], i == _sel)


func _activate() -> void:
	if _sel < 0 or _sel >= _items.size():
		return
	var cb: Variant = _items[_sel].get_meta("mw_cb")
	if cb is Callable:
		(cb as Callable).call()


func _sync_features() -> void:
	laps_btn.text = "LAPS            %d" % GameState.total_laps()
	opp_btn.text = "FIELD           %d" % GameState.opponent_count()
	police_btn.text = "POLICE          %s" % ("ON" if GameState.police_enabled else "OFF")
	fpsplit_btn.text = "FREE-PLAY SPLIT %s" % ("ON" if GameState.freeplay_split else "OFF")
	gfx_btn.text = "GRAPHICS        %s" % GameState.quality_name()
	weather_btn.text = "WEATHER         %s" % str(GameState.weather().get("name", "CLEAR"))
	gun_btn.text = "WEAPONS         %s" % ("ON" if GameState.gun_enabled else "OFF")
	apply_menu_settings()
	if subtitle:
		var car: Dictionary = GameState.selected_car()
		subtitle.text = "%s   ·   BLACKLIST OPEN" % str(car.get("name", "RACER"))
	if status:
		status.text = "13 CIRCUITS   ·   KENNEY GARAGE   ·   FIREBASE / LAN"


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
