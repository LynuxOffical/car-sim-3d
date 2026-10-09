extends Control
class_name McChat

const FADE_AFTER := 9.0
const MAX_LINES := 12

var lines: Array[Dictionary] = []
var log_lab: RichTextLabel
var input: LineEdit
var bar: ColorRect
var open := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_BOTTOM_LEFT)
	offset_left = 8
	offset_top = -280
	offset_right = 520
	offset_bottom = -12
	log_lab = RichTextLabel.new()
	log_lab.bbcode_enabled = true
	log_lab.scroll_active = false
	log_lab.scroll_following = true
	log_lab.fit_content = true
	log_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_lab.set_anchors_preset(PRESET_FULL_RECT)
	log_lab.offset_bottom = -28
	log_lab.add_theme_font_size_override("normal_font_size", 15)
	log_lab.add_theme_color_override("default_color", Color(1, 1, 1, 0.92))
	add_child(log_lab)
	bar = ColorRect.new()
	bar.color = Color(0, 0, 0, 0.45)
	bar.visible = false
	bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bar.offset_top = -26
	add_child(bar)
	input = LineEdit.new()
	input.visible = false
	input.max_length = 120
	input.placeholder_text = "Message"
	input.set_anchors_preset(PRESET_BOTTOM_WIDE)
	input.offset_top = -26
	input.add_theme_font_size_override("font_size", 15)
	input.text_submitted.connect(_submit)
	add_child(input)
	if not Net.room_updated.is_connected(_pull):
		Net.room_updated.connect(_pull)
	_pull()


func _process(_delta: float) -> void:
	visible = Net.online
	if not visible:
		return
	var now := Time.get_ticks_msec() * 0.001
	var bits: PackedStringArray = PackedStringArray()
	for m in lines:
		var age: float = now - float(m.get("born", now))
		if not open and age > FADE_AFTER:
			continue
		var a := 1.0 if open else clampf(1.0 - (age - (FADE_AFTER - 2.0)) / 2.0, 0.0, 1.0)
		if a <= 0.02:
			continue
		var nm := str(m.get("name", "?"))
		var tx := str(m.get("text", "")).replace("[", "").replace("]", "")
		var name_col := Color(0.5, 0.75, 1.0, a)
		var body_col := Color(1, 1, 1, a)
		bits.append("[color=#%s]%s[/color][color=#%s]%s[/color]" % [
			name_col.to_html(true),
			nm.xml_escape() + ": ",
			body_col.to_html(true),
			tx.xml_escape(),
		])
	log_lab.text = "\n".join(bits)


func _pull() -> void:
	var keep: Dictionary = {}
	for m in lines:
		keep[str(m.get("key", ""))] = float(m.get("born", 0.0))
	lines.clear()
	var now := Time.get_ticks_msec() * 0.001
	var start := maxi(0, Net.chat.size() - MAX_LINES)
	for i in range(start, Net.chat.size()):
		var m: Variant = Net.chat[i]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var key := "%s|%s|%s" % [str(m.get("ts", i)), str(m.get("name", "")), str(m.get("text", ""))]
		lines.append({
			"key": key,
			"name": str(m.get("name", "?")),
			"text": str(m.get("text", "")),
			"born": keep.get(key, now),
		})


func open_chat() -> void:
	if not Net.online:
		return
	open = true
	GameState.typing = true
	bar.visible = true
	input.visible = true
	input.text = ""
	input.grab_focus()


func close_chat() -> void:
	open = false
	GameState.typing = false
	bar.visible = false
	input.visible = false
	input.release_focus()


func _submit(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		Net.send_chat(text)
	close_chat()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed() or not (event is InputEventKey):
		return
	if Controls.waiting != "":
		return
	var key := event as InputEventKey
	if open:
		if key.physical_keycode == KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		return
	if not Net.online:
		return
	if event.is_action_pressed("chat"):
		open_chat()
		get_viewport().set_input_as_handled()
