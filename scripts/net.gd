extends Node

signal room_updated
signal chat_received(text: String)

var api_key := ""
var db_url := ""
var configured := false
var uid := ""
var token := ""
var display_name := "RACER"
var room := ""
var hosting := false
var online := false
var status := "Offline"
var error := ""
var players: Dictionary = {}
var meta: Dictionary = {}
var chat: Array = []
var started := false

var _http: HTTPRequest
var _poll: HTTPRequest
var _write: HTTPRequest
var _poll_acc := 0.0
var _pose_acc := 0.0
var _pending: Dictionary = {}
var _write_busy := false
var _poll_busy := false
var _auth_done := false
var _last_status := 0

func _ready() -> void:
	_load_cfg()
	_http = HTTPRequest.new()
	_poll = HTTPRequest.new()
	_write = HTTPRequest.new()
	_http.timeout = 8.0
	_poll.timeout = 6.0
	_write.timeout = 4.0
	add_child(_http)
	add_child(_poll)
	add_child(_write)
	_poll.request_completed.connect(_on_poll)
	_write.request_completed.connect(_on_write)


func _load_cfg() -> void:
	var data: Dictionary = {}
	for path in ["res://firebase_config.json", "user://firebase_config.json"]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
			break
	api_key = str(data.get("apiKey", "")).strip_edges()
	db_url = str(data.get("databaseURL", "")).strip_edges().trim_suffix("/")
	configured = api_key != "" and db_url.begins_with("http") and "YOUR_" not in api_key
	if configured:
		status = "Firebase ready"
	else:
		status = "Missing firebase_config.json"


func connect_auth() -> bool:
	error = ""
	if uid != "":
		_auth_done = true
		return true
	if not configured:
		error = "Copy firebase_config.json with apiKey and databaseURL"
		status = "Offline"
		return false
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + api_key.uri_encode()
	var body := JSON.stringify({"returnSecureToken": true})
	var err := _http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		_guest()
		return true
	var done: Array = await _http.request_completed
	var code: int = done[1]
	var raw: PackedByteArray = done[3]
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if code == 200 and typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("idToken", "")) != "":
		token = str(parsed.get("idToken"))
		uid = str(parsed.get("localId"))
		display_name = "RACER-" + uid.substr(maxi(0, uid.length() - 4), 4).to_upper()
		_auth_done = true
		status = "Connected"
		return true
	_guest()
	return true


func _guest() -> void:
	token = ""
	uid = "G" + str(randi() % 100000000).pad_zeros(8)
	display_name = "RACER-" + uid.substr(uid.length() - 4, 4)
	_auth_done = true
	status = "Connected (guest)"


func host_room() -> bool:
	if not await connect_auth():
		return false
	for _i in 8:
		var code := str(randi_range(10000, 99999))
		var existing: Variant = await _rest(HTTPClient.METHOD_GET, "rooms/" + code)
		if existing != null:
			continue
		var payload := {
			"meta": {
				"host": uid,
				"created": int(Time.get_unix_time_from_system()),
				"started": false,
				"map_idx": GameState.race_island if GameState.race_island >= 0 else 0,
			},
			"players": {},
			"chat": {},
		}
		error = ""
		await _rest(HTTPClient.METHOD_PUT, "rooms/" + code, payload)
		if _last_status >= 400:
			continue
		room = code
		hosting = true
		online = true
		started = false
		meta = payload["meta"]
		status = "ROOM %s" % room
		_push_lobby()
		return true
	error = "Could not allocate a room code"
	return false


func join_room(code: String) -> bool:
	code = _digits(code)
	if code.length() != 5:
		error = "Room code must be 5 digits"
		return false
	if not await connect_auth():
		return false
	var data: Variant = await _rest(HTTPClient.METHOD_GET, "rooms/" + code)
	if typeof(data) != TYPE_DICTIONARY:
		error = "No room %s" % code
		return false
	room = code
	hosting = false
	online = true
	_ingest(data)
	status = "ROOM %s" % room
	_push_lobby()
	return true


func mark_started() -> void:
	if not (hosting and room):
		return
	meta["started"] = true
	started = true
	await _rest(HTTPClient.METHOD_PUT, "rooms/%s/meta" % room, meta)


func leave() -> void:
	var old_room := room
	var old_uid := uid
	room = ""
	online = false
	hosting = false
	started = false
	players = {}
	meta = {}
	chat = []
	status = "Offline"
	if old_room != "" and old_uid != "":
		_fire_and_forget(HTTPClient.METHOD_DELETE, "rooms/%s/players/%s" % [old_room, old_uid])


func set_player(payload: Dictionary) -> void:
	if not online or room == "" or uid == "":
		return
	payload["name"] = display_name
	payload["ts"] = Time.get_unix_time_from_system()
	_pending = payload


func send_chat(text: String) -> void:
	text = " ".join(text.split(" ")).substr(0, 120)
	if text.is_empty() or room == "":
		return
	var msg := {
		"uid": uid,
		"name": display_name,
		"text": text,
		"ts": int(Time.get_unix_time_from_system() * 1000.0),
	}
	_fire_and_forget(HTTPClient.METHOD_POST, "rooms/%s/chat" % room, msg)


func _push_lobby() -> void:
	var car: Dictionary = GameState.selected_car()
	display_name = str(car.get("name", "RACER")).split(" ")[0] + "-" + uid.substr(maxi(0, uid.length() - 3), 3).to_upper()
	set_player({
		"model": str(car.get("id")),
		"color": GameState.paint_index,
		"x": 0.0, "y": 0.8, "z": 0.0,
		"rx": 0.0, "ry": 0.0, "rz": 0.0,
		"s": 0.0,
		"lobby": true,
	})


func _process(delta: float) -> void:
	if not online or room == "":
		return
	_poll_acc += delta
	_pose_acc += delta
	if _poll_acc >= 0.09 and not _poll_busy:
		_poll_acc = 0.0
		_begin_poll()
	if _pose_acc >= 0.05 and not _write_busy and not _pending.is_empty():
		_pose_acc = 0.0
		_begin_write()


func _begin_poll() -> void:
	_poll_busy = true
	var url := _url("rooms/" + room)
	var err := _poll.request(url)
	if err != OK:
		_poll_busy = false


func _on_poll(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_poll_busy = false
	if code != 200:
		if code == 401 or code == 403:
			error = "Database rules blocked the room"
			status = "Error"
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		_ingest(parsed)
		room_updated.emit()


func _begin_write() -> void:
	if _pending.is_empty() or uid == "" or room == "":
		return
	_write_busy = true
	var url := _url("rooms/%s/players/%s" % [room, uid])
	var body := JSON.stringify(_pending)
	var err := _write.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_PUT, body)
	if err != OK:
		_write_busy = false


func _on_write(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_write_busy = false


func _ingest(data: Dictionary) -> void:
	players = data.get("players", {})
	if typeof(players) != TYPE_DICTIONARY:
		players = {}
	meta = data.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	started = bool(meta.get("started", false))
	var chat_raw: Variant = data.get("chat", {})
	var msgs: Array = []
	if typeof(chat_raw) == TYPE_DICTIONARY:
		for k in chat_raw.keys():
			var m: Variant = chat_raw[k]
			if typeof(m) == TYPE_DICTIONARY:
				msgs.append(m)
		msgs.sort_custom(func(a, b): return int(a.get("ts", 0)) < int(b.get("ts", 0)))
	chat = msgs.slice(maxi(0, msgs.size() - 16), msgs.size())


func _rest(method: int, path: String, payload: Variant = null) -> Variant:
	var url := _url(path)
	var body := "" if payload == null else JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(url, headers, method, body)
	if err != OK:
		error = "HTTP request failed"
		return null
	var done: Array = await _http.request_completed
	var code: int = done[1]
	var raw: PackedByteArray = done[3]
	_last_status = code
	if code >= 400:
		error = "HTTP %d" % code
		if code == 401 or code == 403:
			error = "Database rules blocked the room. Publish firebase_rules.json."
		return null
	if raw.is_empty():
		return null
	return JSON.parse_string(raw.get_string_from_utf8())


func _fire_and_forget(method: int, path: String, payload: Variant = null) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_a, _b, _c, _d): req.queue_free())
	var body := "" if payload == null else JSON.stringify(payload)
	req.request(_url(path), PackedStringArray(["Content-Type: application/json"]), method, body)


func _url(path: String) -> String:
	var url := "%s/%s.json" % [db_url, path.trim_prefix("/")]
	if token != "":
		url += "?auth=" + token.uri_encode()
	return url


func _digits(s: String) -> String:
	var out := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			out += ch
	return out
