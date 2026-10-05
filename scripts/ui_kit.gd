extends RefCounted

static func stone(text: String, size := Vector2(380, 56), fill := Color(0.16, 0.18, 0.16, 0.92)) -> Button:
	if GameState.touch_enabled:
		size = Vector2(maxf(size.x, 420), maxf(size.y, 72))
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 22 if GameState.touch_enabled else 20)
	b.add_theme_color_override("font_color", Color(0.92, 0.93, 0.88))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.75))
	var n := _box(fill)
	var h := _box(Color(0.28, 0.42, 0.26, 0.95))
	var p := _box(Color(0.12, 0.28, 0.14, 0.98))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", h)
	return b


static func py_btn(text: String, color: Color, px := 28, min_w := 720.0) -> Button:
	return menu_btn(text, color, px, min_w)


static func menu_btn(text: String, accent: Color, px := 20, min_w := 420.0) -> Button:
	var b := Button.new()
	b.text = "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var h := 44.0 if px < 22 else 50.0
	b.custom_minimum_size = Vector2(min_w, h)
	if GameState.touch_enabled:
		b.custom_minimum_size = Vector2(maxf(min_w, 280.0), 56)
	b.add_theme_font_size_override("font_size", px if not GameState.touch_enabled else px + 2)
	b.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent.lightened(0.25))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 1)
	var n := _card(Color(0.05, 0.06, 0.09, 0.78), accent)
	var hv := _card(Color(0.12, 0.16, 0.22, 0.92), accent.lightened(0.15))
	var pr := _card(Color(0.08, 0.12, 0.16, 0.96), accent)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", hv)
	return b


static func pill(text: String, on: bool, min_w := 140.0) -> Button:
	var accent := Color(0.35, 0.78, 0.95) if on else Color(0.45, 0.48, 0.52)
	var b := menu_btn(text, accent, 16, min_w)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.text = text
	return b


static func play_btn(text: String, size := Vector2(380, 62)) -> Button:
	return stone(text, size, Color(0.18, 0.42, 0.2, 0.95))


static func _box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.05, 0.07, 0.05, 0.9)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 3
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func _card(fill: Color, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = accent
	sb.border_width_left = 5
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.78)
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func stat_bar(width := 300.0) -> Array:
	var bg := Panel.new()
	bg.custom_minimum_size = Vector2(width, 16)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	bg_sb.corner_radius_top_left = 8
	bg_sb.corner_radius_top_right = 8
	bg_sb.corner_radius_bottom_left = 8
	bg_sb.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", bg_sb)
	var fill := ColorRect.new()
	fill.color = Color(0.38, 0.82, 0.74)
	fill.position = Vector2(2, 2)
	fill.size = Vector2(width - 4, 12)
	bg.add_child(fill)
	return [bg, fill]


static func shadow_label(text: String, px: int, col := Color(0.93, 0.95, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.04, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l
