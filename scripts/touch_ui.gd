extends CanvasLayer

var stick_center := Vector2(150, 0)
var stick_radius := 110.0
var knob := Vector2.ZERO
var dragging := false
var throttle := 0.0
var steer := 0.0
var player: PlayerCar
var cam: Camera3D
var stick: _Stick

class _Stick extends Control:
	var owner_ui: Node
	func _draw() -> void:
		var ui = owner_ui
		draw_circle(ui.stick_center, ui.stick_radius + 8.0, Color(0, 0, 0, 0.4))
		draw_circle(ui.stick_center, ui.stick_radius, Color(1, 1, 1, 0.1))
		draw_arc(ui.stick_center, ui.stick_radius - 4.0, 0.0, TAU, 32, Color(0.85, 0.9, 1.0, 0.35), 3.0)
		draw_circle(ui.stick_center + ui.knob, 40, Color(0.9, 0.95, 1.0, 0.92))

func setup(p: PlayerCar, camera: Camera3D) -> void:
	player = p
	cam = camera
	layer = 30
	stick_center.y = get_viewport().get_visible_rect().size.y - 160.0
	stick = _Stick.new()
	stick.owner_ui = self
	stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stick)
	_btn("GAS", Vector2(-300, -250), Color(0.12, 0.52, 0.22), func(): throttle = 1.0, func(): throttle = 0.0)
	_btn("BRAKE", Vector2(-300, -140), Color(0.55, 0.16, 0.16), func(): throttle = -1.0, func(): throttle = 0.0)
	_btn("NITRO", Vector2(-158, -250), Color(0.12, 0.42, 0.85), func(): GameState.nitro_touch = true, func(): GameState.nitro_touch = false)
	_btn("FIRE", Vector2(-300, -360), Color(0.72, 0.22, 0.12), func(): GameState.fire_touch = true, func(): GameState.fire_touch = false)
	_btn("HAND", Vector2(-158, -360), Color(0.35, 0.32, 0.18), func(): GameState.handbrake_touch = true, func(): GameState.handbrake_touch = false)
	_btn("CAM", Vector2(-158, -140), Color(0.22, 0.24, 0.32), func():
		if cam and cam.has_method("cycle"):
			cam.cycle()
	, func(): pass)
	_btn("MENU", Vector2(-158, 28), Color(0.16, 0.16, 0.18), func():
		Net.leave()
		Lan.leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	, func(): pass)


func _btn(text: String, from_br: Vector2, col: Color, down: Callable, up: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(132, 92)
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = from_br.x
	b.offset_top = from_br.y
	b.offset_right = from_br.x + 132
	b.offset_bottom = from_br.y + 92
	b.add_theme_font_size_override("font_size", 22)
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.corner_radius_top_left = 16
	st.corner_radius_top_right = 16
	st.corner_radius_bottom_left = 16
	st.corner_radius_bottom_right = 16
	b.add_theme_stylebox_override("normal", st)
	var h := st.duplicate()
	h.bg_color = col.lightened(0.12)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.button_down.connect(down)
	b.button_up.connect(up)
	add_child(b)


func _process(_delta: float) -> void:
	if player:
		player.set_touch(throttle if not dragging else maxf(throttle, -1.0), steer if dragging else 0.0)
	if stick:
		stick.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed and e.position.distance_to(stick_center) < stick_radius * 1.5:
			dragging = true
			_update_knob(e.position)
		elif not e.pressed:
			dragging = false
			knob = Vector2.ZERO
			steer = 0.0
	elif event is InputEventScreenDrag and dragging:
		_update_knob((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var e := event as InputEventMouseButton
		if e.pressed and e.position.distance_to(stick_center) < stick_radius * 1.5:
			dragging = true
			_update_knob(e.position)
		elif not e.pressed:
			dragging = false
			knob = Vector2.ZERO
			steer = 0.0
	elif event is InputEventMouseMotion and dragging:
		_update_knob((event as InputEventMouseMotion).position)


func _update_knob(pos: Vector2) -> void:
	var v := pos - stick_center
	if v.length() > stick_radius:
		v = v.normalized() * stick_radius
	knob = v
	steer = clampf(v.x / stick_radius, -1.0, 1.0)
	if absf(v.y) > 10.0:
		throttle = clampf(-v.y / stick_radius, -1.0, 1.0)
