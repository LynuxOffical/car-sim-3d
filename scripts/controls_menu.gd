extends "res://scripts/rainy_menu.gd"

var list: VBoxContainer
var hint: Label
var rows: Dictionary = {}

func header_text() -> String:
	return "CONTROLS"


func chrome_kind() -> String:
	return "python"


func show_preview() -> bool:
	return false


func build_ui() -> void:
	var wrap := MarginContainer.new()
	wrap.set_anchors_preset(PRESET_FULL_RECT)
	wrap.offset_left = 80
	wrap.offset_right = -80
	wrap.offset_top = 100
	wrap.offset_bottom = -24
	add_child(wrap)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	wrap.add_child(root)
	hint = UiKit.shadow_label("Click a bind, then press a key. Esc cancels. Split uses P1 and P2.", 15, Color(0.82, 0.86, 0.9))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	root.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for b in Controls.BINDINGS:
		_row(str(b["id"]), str(b["label"]))
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	root.add_child(nav)
	_add(nav, UiKit.menu_btn("Reset defaults", Color(0.95, 0.55, 0.35), 16, 220), func() -> void:
		Controls.reset_defaults()
	)
	_add(nav, UiKit.menu_btn("Back", Color(0.95, 0.9, 0.55), 16, 180), _back)
	if not Controls.binds_changed.is_connected(_refresh):
		Controls.binds_changed.connect(_refresh)
	_refresh()


func _row(action_id: String, label: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lab := UiKit.shadow_label(label, 16, Color(0.86, 0.88, 0.9))
	lab.custom_minimum_size = Vector2(280, 0)
	row.add_child(lab)
	var btn := UiKit.menu_btn("—", Color(0.93, 0.76, 0.22), 16, 260)
	btn.pressed.connect(func() -> void:
		Controls.begin_rebind(action_id)
		_refresh()
	)
	row.add_child(btn)
	list.add_child(row)
	rows[action_id] = btn


func _refresh() -> void:
	if Controls.waiting != "":
		hint.text = "Press a key for  %s   ·   Esc cancel" % Controls.waiting.replace("_", " ").to_upper()
	else:
		hint.text = "Click a bind, then press a key. Esc cancels. Split uses P1 and P2."
	for id in rows.keys():
		var btn: Button = rows[id]
		btn.text = "  " + Controls.label_for(str(id))


func _back() -> void:
	Controls.cancel_rebind()
	get_tree().change_scene_to_file("res://scenes/options.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if Controls.waiting != "":
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE):
		_back()
