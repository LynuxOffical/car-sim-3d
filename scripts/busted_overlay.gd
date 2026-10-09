extends CanvasLayer

var root: Control
var shown := false

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.0, 0.0, 0.72)
	root.add_child(dim)
	var top := ColorRect.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 92
	top.color = Color(0.55, 0.04, 0.04, 0.92)
	root.add_child(top)
	var bot := ColorRect.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_top = -110
	bot.color = Color(0.55, 0.04, 0.04, 0.92)
	root.add_child(bot)
	var title := Label.new()
	title.text = "BUSTED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -420
	title.offset_right = 420
	title.offset_top = -70
	title.offset_bottom = 20
	title.add_theme_font_size_override("font_size", 86)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.22))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	root.add_child(title)
	var sub := Label.new()
	sub.name = "Sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.offset_left = -400
	sub.offset_right = 400
	sub.offset_top = 28
	sub.offset_bottom = 88
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	root.add_child(sub)
	var hint := Label.new()
	hint.text = "ENTER  retry     ESC  menu"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -72
	hint.offset_bottom = -28
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	root.add_child(hint)


func _process(_delta: float) -> void:
	if not GameState.busted:
		if shown:
			shown = false
			root.visible = false
		return
	if not shown:
		shown = true
		root.visible = true
		var sub := root.get_node_or_null("Sub") as Label
		if sub:
			sub.text = "BOUNTY  $%s     HEAT  %d     %s" % [
				_comma(GameState.bounty),
				GameState.stars(),
				GameState.last_crime if GameState.last_crime != "" else "EVADING POLICE",
			]


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.busted or event.is_echo() or not event.is_pressed():
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
		GameState.busted = false
		GameState.reset_wanted()
		get_tree().change_scene_to_file("res://scenes/loading.tscn")
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE:
		GameState.busted = false
		Net.leave()
		Lan.leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		get_viewport().set_input_as_handled()


func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		if c > 0 and c % 3 == 0:
			out = "," + out
		out = s[i] + out
		c += 1
	return out
