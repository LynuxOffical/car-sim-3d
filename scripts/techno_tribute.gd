extends CanvasLayer

var LINES: Array[String] = [
	"He was a brave man.",
	"He was a kind man.",
	"He gave joy to us in the darkest of times.",
	"He used math and trigonometry to make us better at pvp.",
	"May his beautiful soul rest in peace.",
]

var root: Control
var dim: ColorRect
var crown: Control
var title: Label
var never: Label
var body: Label
var sign: Label
var hint: Label
var dust: CPUParticles2D
var t := 0.0
var line_i := -1
var closing := false
var skippable := false

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.tribute_hold = true
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.01, 0.07, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dust = CPUParticles2D.new()
	dust.emitting = true
	dust.amount = 48
	dust.lifetime = 4.2
	dust.preprocess = 0.4
	dust.explosiveness = 0.05
	dust.randomness = 0.7
	dust.direction = Vector2(0, -1)
	dust.spread = 80.0
	dust.gravity = Vector2(0, 18)
	dust.initial_velocity_min = 12.0
	dust.initial_velocity_max = 38.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.4
	dust.color = Color(0.95, 0.55, 0.78, 0.55)
	root.add_child(dust)
	crown = Control.new()
	crown.set_anchors_preset(Control.PRESET_CENTER_TOP)
	crown.anchor_left = 0.5
	crown.anchor_right = 0.5
	crown.offset_left = -90
	crown.offset_right = 90
	crown.offset_top = 36
	crown.offset_bottom = 130
	crown.draw.connect(_draw_crown)
	root.add_child(crown)
	crown.queue_redraw()
	title = _lab(64, Color(0.98, 0.82, 0.28))
	title.text = "TECHNOBLADE"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -420
	title.offset_right = 420
	title.offset_top = 118
	title.offset_bottom = 188
	never = _lab(26, Color(0.95, 0.58, 0.78))
	never.text = "never dies"
	never.set_anchors_preset(Control.PRESET_CENTER_TOP)
	never.offset_left = -280
	never.offset_right = 280
	never.offset_top = 176
	never.offset_bottom = 214
	body = _lab(22, Color(0.94, 0.90, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.set_anchors_preset(Control.PRESET_CENTER)
	body.offset_left = -420
	body.offset_right = 420
	body.offset_top = -70
	body.offset_bottom = 160
	sign = _lab(18, Color(0.86, 0.78, 0.62))
	sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sign.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sign.offset_left = -400
	sign.offset_right = 400
	sign.offset_top = -170
	sign.offset_bottom = -70
	sign.modulate.a = 0.0
	hint = _lab(16, Color(0.72, 0.68, 0.74))
	hint.text = "ENTER  continue"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -48
	hint.offset_bottom = -16
	hint.modulate.a = 0.0


func _lab(px: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _draw_crown() -> void:
	var gold := Color(0.95, 0.78, 0.22, 0.95)
	var dark := Color(0.55, 0.32, 0.08, 0.95)
	var r := Rect2(Vector2(18, 58), Vector2(144, 28))
	crown.draw_rect(r, dark)
	crown.draw_rect(Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8)), gold)
	crown.draw_colored_polygon(PackedVector2Array([Vector2(26, 62), Vector2(40, 14), Vector2(54, 62)]), gold)
	crown.draw_colored_polygon(PackedVector2Array([Vector2(70, 62), Vector2(90, 6), Vector2(110, 62)]), gold)
	crown.draw_colored_polygon(PackedVector2Array([Vector2(126, 62), Vector2(140, 18), Vector2(154, 62)]), gold)
	crown.draw_circle(Vector2(40, 16), 6.0, Color(0.85, 0.22, 0.45))
	crown.draw_circle(Vector2(90, 8), 7.0, Color(0.95, 0.35, 0.55))
	crown.draw_circle(Vector2(140, 20), 6.0, Color(0.85, 0.22, 0.45))


func _process(delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	dust.position = Vector2(vs.x * 0.5, vs.y * 0.92)
	if closing:
		t += delta
		var a := clampf(1.0 - t * 1.6, 0.0, 1.0)
		root.modulate.a = a
		if a <= 0.02:
			GameState.tribute_hold = false
			GameState.techno_seen = true
			queue_free()
		return
	t += delta
	var start_lines := 1.35
	if t > start_lines:
		var idx := mini(int((t - start_lines) / 0.75) + 1, LINES.size())
		if idx != line_i:
			line_i = idx
			var shown := ""
			for i in idx:
				if i > 0:
					shown += "\n\n"
				shown += LINES[i]
			body.text = shown
	if t > start_lines + float(LINES.size()) * 0.75 + 0.25:
		sign.text = "Warm regards,\nThe creator of this random game.\nHope he is resting in peace."
		sign.modulate.a = clampf((t - (start_lines + float(LINES.size()) * 0.75 + 0.25)) * 1.4, 0.0, 1.0)
		skippable = true
		hint.modulate.a = 0.55 + sin(t * 3.0) * 0.25
	if t > 2.4:
		skippable = true


func _close() -> void:
	if closing:
		return
	closing = true
	t = 0.0
	dust.emitting = false


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	var go := false
	if event is InputEventKey:
		var key := (event as InputEventKey).physical_keycode
		go = key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE or key == KEY_ESCAPE
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		go = true
	if go and (skippable or t > 2.4):
		_close()
		get_viewport().set_input_as_handled()
