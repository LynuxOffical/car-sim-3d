extends Node

signal binds_changed

const SAVE_PATH := "user://controls.json"

const BINDINGS: Array[Dictionary] = [
	{"id": "accelerate", "label": "P1  ACCELERATE", "key": KEY_W},
	{"id": "brake", "label": "P1  BRAKE / REVERSE", "key": KEY_S},
	{"id": "steer_left", "label": "P1  STEER LEFT", "key": KEY_A},
	{"id": "steer_right", "label": "P1  STEER RIGHT", "key": KEY_D},
	{"id": "handbrake", "label": "P1  HANDBRAKE", "key": KEY_SPACE},
	{"id": "nitro", "label": "P1  NITRO", "key": KEY_SHIFT},
	{"id": "fire", "label": "P1  FIRE", "key": KEY_CTRL},
	{"id": "camera_cycle", "label": "CAMERA", "key": KEY_C},
	{"id": "pause", "label": "PAUSE / MENU", "key": KEY_ESCAPE},
	{"id": "restart", "label": "RESTART", "key": KEY_R},
	{"id": "chat", "label": "OPEN CHAT", "key": KEY_T},
	{"id": "p2_accelerate", "label": "P2  ACCELERATE", "key": KEY_UP},
	{"id": "p2_brake", "label": "P2  BRAKE / REVERSE", "key": KEY_DOWN},
	{"id": "p2_steer_left", "label": "P2  STEER LEFT", "key": KEY_LEFT},
	{"id": "p2_steer_right", "label": "P2  STEER RIGHT", "key": KEY_RIGHT},
	{"id": "p2_handbrake", "label": "P2  HANDBRAKE", "key": KEY_KP_0},
	{"id": "p2_nitro", "label": "P2  NITRO", "key": KEY_KP_ENTER},
	{"id": "p2_fire", "label": "P2  FIRE", "key": KEY_Q},
]

var waiting := ""
var keys: Dictionary = {}

func _ready() -> void:
	for b in BINDINGS:
		if not InputMap.has_action(str(b["id"])):
			InputMap.add_action(str(b["id"]), 0.2)
		keys[str(b["id"])] = int(b["key"])
	_load()
	apply_all()


func apply_all() -> void:
	for b in BINDINGS:
		_set_key(str(b["id"]), int(keys.get(str(b["id"]), int(b["key"]))), false)
	binds_changed.emit()


func reset_defaults() -> void:
	waiting = ""
	for b in BINDINGS:
		keys[str(b["id"])] = int(b["key"])
	apply_all()
	_save()


func begin_rebind(action_id: String) -> void:
	waiting = action_id


func cancel_rebind() -> void:
	waiting = ""
	binds_changed.emit()


func label_for(action_id: String) -> String:
	if waiting == action_id:
		return "PRESS KEY…"
	return key_name(int(keys.get(action_id, 0)))


func key_name(code: int) -> String:
	if code <= 0:
		return "—"
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	var t := ev.as_text_physical_keycode()
	if t.is_empty():
		t = OS.get_keycode_string(code as Key)
	return t.to_upper()


func _set_key(action_id: String, code: int, steal: bool) -> void:
	if steal:
		for k in keys.keys():
			if str(k) != action_id and int(keys[k]) == code:
				keys[k] = 0
				_write_map(str(k), 0)
	keys[action_id] = code
	_write_map(action_id, code)
	if action_id == "nitro":
		var jb := InputEventJoypadButton.new()
		jb.button_index = JOY_BUTTON_A
		InputMap.action_add_event(action_id, jb)
	elif action_id == "fire":
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(action_id, mb)


func _write_map(action_id: String, code: int) -> void:
	if not InputMap.has_action(action_id):
		InputMap.add_action(action_id, 0.2)
	InputMap.action_erase_events(action_id)
	if code <= 0:
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	InputMap.action_add_event(action_id, ev)


func _unhandled_input(event: InputEvent) -> void:
	if waiting == "" or event.is_echo() or not event.is_pressed():
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_ESCAPE:
		cancel_rebind()
		get_viewport().set_input_as_handled()
		return
	_set_key(waiting, int(key.physical_keycode), true)
	waiting = ""
	_save()
	binds_changed.emit()
	get_viewport().set_input_as_handled()


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(keys))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in parsed.keys():
		keys[str(k)] = int(parsed[k])
