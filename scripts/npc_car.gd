extends ArcadeCar
class_name NpcCar

enum Role { TRAFFIC, COP, HUNTER, RACER }

var role: Role = Role.TRAFFIC
var waypoints: Array[Vector3] = []
var player: Node3D
var land: IslandWorld

func setup(p_role: Role, mesh_path: String, pts: Array[Vector3], who: Node3D, skill := 0.9) -> void:
	role = p_role
	waypoints = pts
	player = who
	ai_skill = skill
	add_to_group("npc")
	var car: Dictionary
	if p_role == Role.COP:
		car = {
			"id": "police", "kind": "car", "glb": "res://assets/cars/police.glb",
			"length": 4.5, "max_speed": 125.0, "accel": 32.0, "brake": 50.0, "steer": 2.30, "nitro": 0.0,
		}
		is_police = true
		display_name = "PATROL"
	elif p_role == Role.RACER:
		car = GameState.VEHICLES[randi() % mini(11, GameState.VEHICLES.size())]
		display_name = "CPU"
		ai_skill = skill
	else:
		car = {
			"id": "npc", "kind": "car", "glb": mesh_path if mesh_path != "" else GameState.NPC_GLBS[randi() % GameState.NPC_GLBS.size()],
			"length": 4.4, "max_speed": 26.0 if p_role == Role.TRAFFIC else 44.0,
			"accel": 22.0, "brake": 48.0, "steer": 2.4, "nitro": 0.0,
		}
	var paint: Color = GameState.PAINTS[randi() % GameState.PAINTS.size()]["color"]
	configure(car, paint, display_name, p_role == Role.COP)
	if not waypoints.is_empty():
		global_position = waypoints[0] + Vector3(0, 0.2, 0)


func _physics_process(delta: float) -> void:
	if not can_drive:
		arcade_step(delta, 0.0, 0.0)
		return
	var ctrl := _ai(delta)
	arcade_step(delta, ctrl.x, ctrl.y)


func _ai(_delta: float) -> Vector2:
	var track: IslandWorld = land
	if track == null and player and player.get_parent() and player.get_parent().get("land"):
		track = player.get_parent().land
	if role == Role.COP or (role == Role.HUNTER and GameState.identified and GameState.bounty > 2200):
		return _chase_player(track)
	if role == Role.RACER:
		return _race_ai(track)
	return _traffic(track)


func _traffic(_track: IslandWorld) -> Vector2:
	if waypoints.is_empty():
		return Vector2.ZERO
	if global_position.distance_to(waypoints[wp_idx % waypoints.size()]) < 10.0:
		wp_idx = (wp_idx + 1) % waypoints.size()
	var tgt: Vector3 = waypoints[wp_idx % waypoints.size()]
	return _steer_toward(tgt.x, tgt.z, max_speed * 0.9)


func _race_ai(track: IslandWorld) -> Vector2:
	if track == null or track.wps2.is_empty():
		return _traffic(track)
	var n := track.wps2.size()
	var look := 4 + int(absf(speed) * 0.35)
	var ti := (wp_idx + look) % n
	var tx: float = track.wps2[ti].x
	var tz: float = track.wps2[ti].y
	var target_h := atan2(-(tx - global_position.x), -(tz - global_position.z))
	var err := wrapf(target_h - heading, -PI, PI)
	var steer := clampf(err * 2.4, -1.0, 1.0)
	var far := 10 + int(absf(speed) * 0.6)
	var curve := absf(wrapf(track.heading_at((wp_idx + far) % n) - track.heading_at(wp_idx), -PI, PI))
	var desired := max_speed * ai_skill * grip * clampf(1.35 - curve * 0.85, 0.45, 1.0)
	var throttle := 0.0
	if speed < desired - 1.0:
		throttle = 1.0
	elif speed > desired + 2.0:
		throttle = -1.0
	return Vector2(throttle, steer)


func _chase_player(track: IslandWorld) -> Vector2:
	if player == null:
		return _traffic(track)
	var tx := player.global_position.x
	var tz := player.global_position.z
	var target_h := atan2(-(tx - global_position.x), -(tz - global_position.z))
	if track and not track.dirs2.is_empty():
		var track_h := track.heading_at(wp_idx)
		var turn := absf(wrapf(target_h - heading, -PI, PI))
		if turn > 1.25:
			target_h = track_h
	var err := wrapf(target_h - heading, -PI, PI)
	var steer := clampf(err * 3.0, -1.0, 1.0)
	var dist := Vector2(tx - global_position.x, tz - global_position.z).length()
	var desired := max_speed * clampf(0.88 + dist * 0.004, 0.75, 1.0)
	var throttle := 0.3
	if speed < desired - 1.5:
		throttle = 1.0
	elif speed > desired + 4.0:
		throttle = -0.4
	return Vector2(throttle, steer)


func _steer_toward(tx: float, tz: float, desired: float) -> Vector2:
	var target_h := atan2(-(tx - global_position.x), -(tz - global_position.z))
	var err := wrapf(target_h - heading, -PI, PI)
	var steer := clampf(err * 2.4, -1.0, 1.0)
	var throttle := 1.0 if speed < desired - 1.0 else (-1.0 if speed > desired + 2.0 else 0.0)
	return Vector2(throttle, steer)


func wants_ai_fire(cars: Array) -> bool:
	if not GameState.gun_enabled or wreck_t > 0.0 or fire_cd > 0.0:
		return false
	if role == Role.COP and player is ArcadeCar:
		var tgt := player as ArcadeCar
		if tgt.wreck_t > 0.0:
			return false
		var d := global_position.distance_to(tgt.global_position)
		if d > 36.0:
			return false
		var aim := atan2(-(tgt.global_position.x - global_position.x), -(tgt.global_position.z - global_position.z))
		return absf(wrapf(aim - heading, -PI, PI)) < 0.28
	if role != Role.RACER:
		return false
	var best_d := 40.0
	var best: ArcadeCar = null
	for other in cars:
		if other == self or not (other is ArcadeCar):
			continue
		var o := other as ArcadeCar
		if o.wreck_t > 0.0:
			continue
		var d2 := global_position.distance_to(o.global_position)
		if d2 < best_d:
			best = o
			best_d = d2
	if best == null:
		return false
	var aim2 := atan2(-(best.global_position.x - global_position.x), -(best.global_position.z - global_position.z))
	if absf(wrapf(aim2 - heading, -PI, PI)) > 0.32:
		return false
	return randf() < (0.10 + 0.18 * ai_skill)
