extends "res://scripts/rainy_menu.gd"

var name_lab: Label
var tag_lab: Label
var paint_lab: Label
var bar_fills: Array[ColorRect] = []
var swatch_row: HBoxContainer
var tab_row: HBoxContainer
var tab := 0
var picking_p2 := false
var _p1_car := 0
var _p1_paint := 0

func header_text() -> String:
	return "P2  ·  garage" if picking_p2 else "P1  ·  garage"


func header_px() -> int:
	return 28


func chrome_kind() -> String:
	return "python"


func world_kind() -> String:
	return "showroom"


func show_preview() -> bool:
	return true


func build_ui() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_preset(PRESET_TOP_WIDE)
	top.offset_left = 40
	top.offset_right = -40
	top.offset_top = 92
	top.offset_bottom = 250
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	name_lab = UiKit.shadow_label("", 30, Color(0.96, 0.97, 0.99))
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(name_lab)
	tag_lab = UiKit.shadow_label("", 16, Color(0.72, 0.78, 0.86))
	tag_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(tag_lab)
	tab_row = HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 12)
	top.add_child(tab_row)
	_rebuild_tabs()

	var stats_panel := UiKit.panel()
	stats_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stats_panel.anchor_right = 0.0
	stats_panel.offset_left = 36
	stats_panel.offset_right = 400
	stats_panel.offset_top = 268
	stats_panel.offset_bottom = -230
	add_child(stats_panel)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 16)
	stats_panel.add_child(stats)
	var stats_h := UiKit.shadow_label("STATS", 13, Color(0.55, 0.72, 0.82))
	stats.add_child(stats_h)
	for label in ["SPEED", "ACCEL", "GRIP"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var lab := UiKit.shadow_label(label, 13, Color(0.78, 0.80, 0.84))
		row.add_child(lab)
		var pair: Array = UiKit.stat_bar(300)
		bar_fills.append(pair[1] as ColorRect)
		row.add_child(pair[0])
		stats.add_child(row)

	var bottom := UiKit.panel()
	bottom.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bottom.offset_left = 48
	bottom.offset_right = -48
	bottom.offset_top = -188
	bottom.offset_bottom = -18
	add_child(bottom)
	var bottom_col := VBoxContainer.new()
	bottom_col.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_col.add_theme_constant_override("separation", 10)
	bottom.add_child(bottom_col)
	paint_lab = UiKit.shadow_label("", 16, Color(0.90, 0.92, 0.94))
	paint_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_col.add_child(paint_lab)
	swatch_row = HBoxContainer.new()
	swatch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	swatch_row.add_theme_constant_override("separation", 8)
	bottom_col.add_child(swatch_row)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	bottom_col.add_child(nav)
	_add(nav, UiKit.menu_btn("<  Prev", Color(0.7, 0.74, 0.8), 16, 150), func() -> void:
		_step(-1)
		_refresh_car()
	)
	_add(nav, UiKit.menu_btn("Enter  Confirm", Color(0.42, 0.86, 0.52), 16, 220), _confirm)
	_add(nav, UiKit.menu_btn("Next  >", Color(0.7, 0.74, 0.8), 16, 150), func() -> void:
		_step(1)
		_refresh_car()
	)
	var hint := UiKit.shadow_label("LEFT / RIGHT car    UP / DOWN paint    ENTER confirm    ESC back", 13, Color(0.62, 0.66, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_col.add_child(hint)
	_rebuild_swatches()
	_refresh_car()


func _rebuild_tabs() -> void:
	if tab_row == null:
		return
	for c in tab_row.get_children():
		tab_row.remove_child(c)
		c.free()
	_add(tab_row, UiKit.pill("CARS", tab == 0, 160), func() -> void:
		tab = 0
		_first_of_kind()
		_rebuild_tabs()
		_refresh_car()
	)
	_add(tab_row, UiKit.pill("BIKES", tab == 1, 160), func() -> void:
		tab = 1
		_first_of_kind()
		_rebuild_tabs()
		_refresh_car()
	)


func _refresh_car() -> void:
	refresh_preview()
	_update_car_ui()


func _update_car_ui() -> void:
	var v: Dictionary = GameState.selected_car()
	if name_lab:
		name_lab.text = "<   %s   >" % str(v.get("name", ""))
	if tag_lab:
		tag_lab.text = str(v.get("tag", ""))
	if paint_lab:
		paint_lab.text = str(GameState.PAINTS[GameState.paint_index]["name"])
	var fracs := [
		float(v.get("max_speed", 100.0)) / float(GameState.STAT_TOP["max_speed"]),
		float(v.get("accel", 30.0)) / float(GameState.STAT_TOP["accel"]),
		float(v.get("steer", 2.0)) / float(GameState.STAT_TOP["steer"]),
	]
	for i in bar_fills.size():
		var f := clampf(fracs[i], 0.05, 1.0)
		bar_fills[i].size = Vector2((300.0 - 4.0) * f, 12.0)


func _rebuild_swatches() -> void:
	if swatch_row == null:
		return
	for c in swatch_row.get_children():
		c.queue_free()
	for i in GameState.PAINTS.size():
		var idx := i
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = GameState.PAINTS[i]["color"]
		var sel := i == GameState.paint_index
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.border_width_left = 3 if sel else 1
		sb.border_width_top = sb.border_width_left
		sb.border_width_right = sb.border_width_left
		sb.border_width_bottom = sb.border_width_left
		sb.border_color = Color(0.95, 0.97, 1.0) if sel else Color(0.12, 0.12, 0.14)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func() -> void:
			GameState.paint_index = idx
			_rebuild_swatches()
			_refresh_car()
		)
		swatch_row.add_child(b)


func _confirm() -> void:
	if GameState.split_screen and not picking_p2:
		_p1_car = GameState.car_index
		_p1_paint = GameState.paint_index
		picking_p2 = true
		GameState.car_index = GameState.p2_car_index
		GameState.paint_index = GameState.p2_paint_index
		if title:
			title.text = header_text()
		_refresh_car()
		return
	if picking_p2:
		GameState.p2_car_index = GameState.car_index
		GameState.p2_paint_index = GameState.paint_index
		GameState.car_index = _p1_car
		GameState.paint_index = _p1_paint
	if GameState.mode == GameState.Mode.ROAM:
		get_tree().change_scene_to_file("res://scenes/loading.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/map_select.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed("ui_left"):
		_step(-1)
		_refresh_car()
	elif event.is_action_pressed("ui_right"):
		_step(1)
		_refresh_car()
	elif event.is_action_pressed("ui_up"):
		GameState.paint_index = (GameState.paint_index - 1 + GameState.PAINTS.size()) % GameState.PAINTS.size()
		_rebuild_swatches()
		_refresh_car()
	elif event.is_action_pressed("ui_down"):
		GameState.paint_index = (GameState.paint_index + 1) % GameState.PAINTS.size()
		_rebuild_swatches()
		_refresh_car()
	elif event.is_action_pressed("ui_accept"):
		_confirm()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE):
		if picking_p2:
			GameState.car_index = _p1_car
			GameState.paint_index = _p1_paint
			picking_p2 = false
			if title:
				title.text = header_text()
			_refresh_car()
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _refresh_labels() -> void:
	_update_car_ui()


func _matches(i: int) -> bool:
	var k := str(GameState.VEHICLES[i].get("kind"))
	if tab == 1:
		return k == "bike"
	return k != "bike"


func _first_of_kind() -> void:
	for i in GameState.VEHICLES.size():
		if _matches(i):
			GameState.car_index = i
			return


func _step(dir: int) -> void:
	var n := GameState.VEHICLES.size()
	for _i in n:
		GameState.car_index = (GameState.car_index + dir + n) % n
		if _matches(GameState.car_index):
			return
