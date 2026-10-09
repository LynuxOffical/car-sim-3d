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
var _writers: Array[HTTPRequest] = []
var _writer_busy: Array[bool] = []
var _poll_acc := 0.0
var _pose_acc := 0.0
var _pending: Dictionary = {}
var _poll_busy := false
var _auth_done := false
var _last_status := 0
var _sse: HTTPClient
var _sse_phase := 0
var _sse_buf := ""
var _sse_host := ""
var _sse_path := ""
var _sse_tls := true
var _sse_ok := false
var _sse_retry := 0.0

func _ready() -> void:
	_load_cfg()
	_http = HTTPRequest.new()
	_poll = HTTPRequest.new()
	_http.timeout = 5.0
	_poll.timeout = 4.0
	add_child(_http)
	add_child(_poll)
	_poll.request_completed.connect(_on_poll)
	for i in 4:
		var w := HTTPRequest.new()
		w.timeout = 2.0
		add_child(w)
		_writers.append(w)
		_writer_busy.append(false)
		var idx := i
		w.request_completed.connect(func(_a, _b, _c, _d): _writer_busy[idx] = false)
	call_deferred("_boot")


func _boot() -> void:
	if configured:
		await connect_auth()


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
	var code := "%05d" % ((int(Time.get_unix_time_from_system()) * 17 + randi()) % 100000)
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
		error = "Could not allocate a room code"
		return false
	room = code
	hosting = true
	online = true
	started = false
	meta = payload["meta"]
	status = "ROOM %s" % room
	_push_lobby()
	_open_stream()
	return true


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
	_open_stream()
	return true


func mark_started() -> void:
	if not (hosting and room):
		return
	meta["started"] = true
	started = true
	_fire_and_forget(HTTPClient.METHOD_PUT, "rooms/%s/meta" % room, meta)


func leave() -> void:
	var old_room := room
	var old_uid := uid
	_close_stream()
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
	chat.append(msg)
	if chat.size() > 16:
		chat = chat.slice(chat.size() - 16, chat.size())
	chat_received.emit(text)
	room_updated.emit()
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
	_flush_write()


func _process(delta: float) -> void:
	if _sse != null:
		_poll_sse()
	elif online and room != "" and _sse_retry > 0.0:
		_sse_retry -= delta
		if _sse_retry <= 0.0:
			_open_stream()
	if not online or room == "":
		return
	_poll_acc += delta
	_pose_acc += delta
	if not _sse_ok and _poll_acc >= 0.08 and not _poll_busy:
		_poll_acc = 0.0
		_begin_poll()
	if _pose_acc >= 0.033 and not _pending.is_empty():
		_pose_acc = 0.0
		_flush_write()


func _open_stream() -> void:
	_close_stream()
	if db_url == "" or room == "":
		return
	var rest := db_url.trim_prefix("https://").trim_prefix("http://")
	_sse_tls = db_url.begins_with("https")
	_sse_host = rest.split("/")[0]
	_sse_path = "/rooms/%s.json" % room
	if token != "":
		_sse_path += "?auth=" + token.uri_encode()
	_sse = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if _sse_tls else null
	var err := _sse.connect_to_host(_sse_host, 443 if _sse_tls else 80, tls)
	if err != OK:
		_sse = null
		_sse_ok = false
		_sse_retry = 0.4
		return
	_sse_phase = 1
	_sse_buf = ""
	_sse_ok = false


func _close_stream() -> void:
	if _sse != null:
		_sse.close()
	_sse = null
	_sse_phase = 0
	_sse_buf = ""
	_sse_ok = false


func _poll_sse() -> void:
	if _sse == null:
		return
	_sse.poll()
	var st := _sse.get_status()
	if st == HTTPClient.STATUS_RESOLVING or st == HTTPClient.STATUS_CONNECTING:
		return
	if st == HTTPClient.STATUS_CONNECTED and _sse_phase == 1:
		_sse.request(HTTPClient.METHOD_GET, _sse_path, PackedStringArray([
			"Accept: text/event-stream",
			"Cache-Control: no-cache",
		]))
		_sse_phase = 2
		return
	if st == HTTPClient.STATUS_BODY:
		if not _sse_ok and _sse.has_response() and _sse.get_response_code() == 200:
			_sse_ok = true
		var chunk := _sse.read_response_body_chunk()
		if chunk.size() > 0:
			_sse_buf += chunk.get_string_from_utf8()
			_drain_sse()
		return
	if st == HTTPClient.STATUS_CONNECTION_ERROR or st == HTTPClient.STATUS_CANT_CONNECT or st == HTTPClient.STATUS_CANT_RESOLVE or st == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR or st == HTTPClient.STATUS_DISCONNECTED:
		_close_stream()
		if online and room != "":
			_sse_retry = 0.35


func _drain_sse() -> void:
	while true:
		var cut := _sse_buf.find("\n\n")
		if cut < 0:
			if _sse_buf.length() > 200000:
				_sse_buf = _sse_buf.substr(_sse_buf.length() - 8000)
			return
		var block := _sse_buf.substr(0, cut)
		_sse_buf = _sse_buf.substr(cut + 2)
		var ev := "put"
		var data_s := ""
		for line in block.split("\n"):
			if line.begins_with("event:"):
				ev = line.substr(6).strip_edges()
			elif line.begins_with("data:"):
				data_s += line.substr(5).strip_edges()
		if ev == "keep-alive" or data_s == "" or data_s == "null":
			continue
		if ev == "put" or ev == "patch":
			_apply_sse(ev, data_s)


func _apply_sse(_ev: String, raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var path := str(parsed.get("path", "/"))
	var data: Variant = parsed.get("data")
	if path == "/" or path == "":
		if typeof(data) == TYPE_DICTIONARY:
			_ingest(data)
			room_updated.emit()
		return
	var cur := {"players": players.duplicate(true), "meta": meta.duplicate(true), "chat": {}}
	var node: Variant = cur
	var parts := path.trim_prefix("/").split("/")
	for i in parts.size():
		var key := parts[i]
		if i == parts.size() - 1:
			if typeof(node) != TYPE_DICTIONARY:
				return
			if data == null:
				(node as Dictionary).erase(key)
			else:
				(node as Dictionary)[key] = data
		else:
			if typeof(node) != TYPE_DICTIONARY:
				return
			if not (node as Dictionary).has(key) or typeof((node as Dictionary)[key]) != TYPE_DICTIONARY:
				(node as Dictionary)[key] = {}
			node = (node as Dictionary)[key]
	_ingest(cur)
	room_updated.emit()


func _begin_poll() -> void:
	_poll_busy = true
	var err := _poll.request(_url("rooms/" + room))
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


func _flush_write() -> void:
	if _pending.is_empty() or uid == "" or room == "":
		return
	for i in _writers.size():
		if _writer_busy[i]:
			continue
		_writer_busy[i] = true
		var url := _url("rooms/%s/players/%s" % [room, uid])
		var body := JSON.stringify(_pending)
		var err := _writers[i].request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_PUT, body)
		if err != OK:
			_writer_busy[i] = false
			continue
		_pending = {}
		return


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
		_last_status = 0
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
		return {}
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
