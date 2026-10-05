extends Node

signal peer_ready
signal peer_gone(id: int)

const PORT := 24567
const MAX_CLIENTS := 8

var active := false
var hosting := false
var status := "Offline"
var error := ""
var peer: ENetMultiplayerPeer
var join_ip := "127.0.0.1"

func host_lan() -> bool:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		error = "Could not host on port %d" % PORT
		status = "Host failed"
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	error = ""
	status = "LAN HOST  ·  %s" % primary_ip()
	peer_ready.emit()
	return true


func join_lan(ip: String) -> bool:
	leave()
	ip = ip.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	join_ip = ip
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		error = "Could not reach %s" % ip
		status = "Join failed"
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = false
	error = ""
	status = "LAN joining %s" % ip
	peer_ready.emit()
	return true


func leave() -> void:
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	active = false
	hosting = false
	status = "Offline"


func primary_ip() -> String:
	var addrs := addresses()
	if addrs.is_empty():
		return "127.0.0.1"
	return addrs[0]


func addresses() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for a in IP.get_local_addresses():
		if ":" in a:
			continue
		if a.begins_with("127.") or a.begins_with("0."):
			continue
		out.append(a)
	return out
