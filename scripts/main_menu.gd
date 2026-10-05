extends "res://scripts/rainy_menu.gd"

var laps_btn: Button
var opp_btn: Button
var police_btn: Button
var fpsplit_btn: Button
var gfx_btn: Button
var weather_btn: Button
var gun_btn: Button
var tag_lab: Label

func header_text() -> String:
	return "car-sim-3d"


func header_px() -> int:
	return 40


func chrome_kind() -> String:
	return "python"


func world_kind() -> String:
	return "track"


func show_preview() -> bool:
	return false


func build_ui() -> void:
	var wrap := MarginContainer.new()
	wrap.set_anchors_preset(PRESET_FULL_RECT)
	wrap.offset_left = 48
	wrap.offset_right = -48
	wrap.offset_top = 96
	wrap.offset_bottom = -28
	add_child(wrap)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	wrap.add_child(root)
	var streak := ""
	if GameState.win_streak > 0:
		streak = "   ·   win streak x%d" % GameState.win_streak
	tag_lab = UiKit.shadow_label("arcade circuits  ·  kenney cars  ·  first across the line wins%s" % streak, 16, Color(0.78, 0.82, 0.88))
	tag_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tag_lab)

	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var play := UiKit.panel()
	play.custom_minimum_size = Vector2(460, 0)
	cols.add_child(play)
	var play_col := VBoxContainer.new()
	play_col.add_theme_constant_override("separation", 8)
	play.add_child(play_col)
	var play_h := UiKit.shadow_label("PLAY", 14, Color(0.55, 0.72, 0.82))
	play_col.add_child(play_h)
	_add(play_col, UiKit.menu_btn("1   Single player", Color(0.42, 0.86, 0.52), 20, 400), _start_single)
	_add(play_col, UiKit.menu_btn("2   Split screen race", Color(0.42, 0.72, 1.0), 20, 400), _start_split)
	_add(play_col, UiKit.menu_btn("3   Free play", Color(0.95, 0.72, 0.38), 20, 400), _start_free)
	_add(play_col, UiKit.menu_btn("4   Online multiplayer", Color(0.38, 0.86, 0.92), 18, 400), func() -> void:
		get_tree().change_scene_to_file("res://scenes/mp_menu.tscn")
	)
	_add(play_col, UiKit.menu_btn("5   Gun combat", Color(0.95, 0.38, 0.32), 18, 400), _start_guns)
	_add(play_col, UiKit.menu_btn("6   Roam the world", Color(0.55, 0.86, 0.55), 18, 400), _start_roam)
	_add(play_col, UiKit.menu_btn("N   LAN multiplayer", Color(0.55, 0.82, 0.78), 16, 400), func() -> void:
		get_tree().change_scene_to_file("res://scenes/lan_menu.tscn")
	)

	var opt := UiKit.panel()
	opt.custom_minimum_size = Vector2(460, 0)
	cols.add_child(opt)
	var opt_col := VBoxContainer.new()
	opt_col.add_theme_constant_override("separation", 8)
	opt.add_child(opt_col)
	var opt_h := UiKit.shadow_label("SETTINGS", 14, Color(0.55, 0.72, 0.82))
	opt_col.add_child(opt_h)
	laps_btn = UiKit.menu_btn("", Color(0.92, 0.82, 0.38), 16, 400)
	opp_btn = UiKit.menu_btn("", Color(0.92, 0.82, 0.38), 16, 400)
	police_btn = UiKit.menu_btn("", Color(0.55, 0.75, 1.0), 16, 400)
	fpsplit_btn = UiKit.menu_btn("", Color(0.55, 0.75, 1.0), 16, 400)
	gfx_btn = UiKit.menu_btn("", Color(0.78, 0.55, 0.95), 16, 400)
	weather_btn = UiKit.menu_btn("", Color(0.45, 0.78, 0.95), 16, 400)
	gun_btn = UiKit.menu_btn("", Color(0.95, 0.48, 0.38), 16, 400)
	_add(opt_col, laps_btn, func() -> void:
		GameState.cycle_laps()
		_sync_features()
	)
	_add(opt_col, opp_btn, func() -> void:
		GameState.cycle_opponents()
		_sync_features()
	)
	_add(opt_col, police_btn, func() -> void:
		GameState.police_enabled = not GameState.police_enabled
		_sync_features()
	)
	_add(opt_col, fpsplit_btn, func() -> void:
		GameState.freeplay_split = not GameState.freeplay_split
		_sync_features()
	)
	_add(opt_col, gfx_btn, func() -> void:
		GameState.cycle_quality()
		_sync_features()
	)
	_add(opt_col, weather_btn, func() -> void:
		GameState.cycle_weather()
		_sync_features()
	)
	_add(opt_col, gun_btn, func() -> void:
		GameState.gun_enabled = not GameState.gun_enabled
		_sync_features()
	)
	_add(opt_col, UiKit.menu_btn("Options", Color(0.7, 0.74, 0.78), 16, 400), func() -> void:
		get_tree().change_scene_to_file("res://scenes/options.tscn")
	)
	var hint := UiKit.shadow_label("keys 1-6  ·  C camera in race  ·  split: P1 arrows  P2 WASD  ·  ESC quit", 14, Color(0.62, 0.66, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	_sync_features()


func _sync_features() -> void:
	laps_btn.text = "  L   Laps: %d" % GameState.total_laps()
	opp_btn.text = "  O   Opponents: %d" % GameState.opponent_count()
	police_btn.text = "  P   Free-play police: %s" % ("ON" if GameState.police_enabled else "OFF")
	fpsplit_btn.text = "  F   Free-play split: %s" % ("ON" if GameState.freeplay_split else "OFF")
	gfx_btn.text = "  G   Graphics: %s" % GameState.quality_name()
	weather_btn.text = "  T   Weather: %s" % str(GameState.weather().get("name", "CLEAR"))
	gun_btn.text = "  U   Guns: %s" % ("ON" if GameState.gun_enabled else "OFF")


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	match (event as InputEventKey).physical_keycode:
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
		KEY_G:
			GameState.cycle_quality()
			_sync_features()
		KEY_T:
			GameState.cycle_weather()
			_sync_features()
		KEY_U:
			GameState.gun_enabled = not GameState.gun_enabled
			_sync_features()
		KEY_ESCAPE:
			get_tree().quit()
