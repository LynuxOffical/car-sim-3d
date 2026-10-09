extends Node3D

const RemoteCarScene := preload("res://scripts/remote_car.gd")

var land: IslandWorld
var player: PlayerCar
var player2: PlayerCar
var cam: Camera3D
var cam2: Camera3D
var remotes: Dictionary = {}
var sync_acc := 0.0
var racers: Array[ArcadeCar] = []
var bullets: Array[Bullet] = []
var checkpoint_indices: Array[int] = []
var checkpoint_markers: Array[Node3D] = []
var finish_order: Array[ArcadeCar] = []
var shot_seq := 0

func _ready() -> void:
	GameState.typing = false
	GameState.reset_wanted()
	Engine.physics_ticks_per_second = 60
	get_tree().physics_interpolation = false
	var vp := get_viewport()
	vp.disable_3d = false
	match GameState.quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.use_taa = false
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.use_taa = GameState.use_taa
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if GameState.vsync else DisplayServer.VSYNC_DISABLED)
	_lighting()
	land = IslandWorld.new()
	add_child(land)
	if GameState.mode == GameState.Mode.ROAM:
		land.build(-1, true)
	else:
		var idx := 0
		if GameState.race_island >= 0:
			idx = GameState.race_island
		land.build(idx, false)
	_apply_theme()
	_spawn_player()
	call_deferred("_spawn_life")
	var weather := WeatherSystem.new()
	add_child(weather)
	var env := $WorldEnvironment.environment as Environment
	weather.setup(env, $Sun, player, land)
	add_child(preload("res://scripts/nfs_overlay.gd").new())
	if GameState.split_screen and player2 and cam2:
		_setup_split_views()
	else:
		_attach_hud(player)
	_attach_chat()
	if GameState.touch_enabled and not GameState.split_screen:
		var touch: Node = preload("res://scripts/touch_ui.gd").new()
		add_child(touch)
		touch.call("setup", player, cam)
	if cam and is_instance_valid(cam):
		cam.current = true
	if cam2 and is_instance_valid(cam2):
		cam2.current = true
	if Net.online:
		if not Net.room_updated.is_connected(_sync_firebase):
			Net.room_updated.connect(_sync_firebase)
		call_deferred("_sync_firebase")
	if Lan.active:
		multiplayer.peer_connected.connect(func(_id): pass)
		multiplayer.peer_disconnected.connect(_lan_drop)
	call_deferred("_ensure_view")


func _ensure_view() -> void:
	var vp := get_viewport()
	if vp:
		vp.disable_3d = false
	if cam and is_instance_valid(cam):
		cam.current = true
	if cam2 and is_instance_valid(cam2):
		cam2.current = true


func _lighting() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.glow_enabled = GameState.quality >= 2
	env.glow_intensity = 0.05
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.fog_enabled = true
	env.fog_density = 0.00115
	env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = false
	Mats.paint_sky(env, Color(0.48, 0.62, 0.78), Color(0.29, 0.50, 0.23))
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.12
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = GameState.quality > 0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if GameState.quality < 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 150.0 if GameState.quality >= 2 else 90.0
	add_child(sun)


func _apply_theme() -> void:
	if land == null or land.theme.is_empty():
		return
	var env := $WorldEnvironment.environment as Environment
	var sky: Color = land.theme.get("sky", Color(0.48, 0.62, 0.78))
	var ground: Color = land.theme.get("ground", Color(0.29, 0.50, 0.23))
	Mats.paint_sky(env, sky, ground)
	env.fog_light_color = sky


func _spawn_player() -> void:
	var spawn := land.spawn_for(0)
	var head := land.heading_at(0)
	player = PlayerCar.new()
	player.name = "Player"
	player.player_slot = 0
	player.display_name = "P1"
	player.configure(GameState.selected_car(), GameState.selected_paint(), "P1")
	add_child(player)
	player.place(spawn, head, 0)
	racers.append(player)
	cam = _make_cam(player, spawn, head)
	if GameState.split_screen:
		player2 = PlayerCar.new()
		player2.name = "Player2"
		player2.player_slot = 1
		player2.display_name = "P2"
		player2.configure(GameState.p2_car(), GameState.p2_paint(), "P2")
		add_child(player2)
		var nrm := Vector2(cos(head), -sin(head))
		player2.place(spawn + Vector3(nrm.x * 6.0, 0, nrm.y * 6.0), head, 0)
		racers.append(player2)
		cam2 = _make_cam(player2, player2.global_position, head)
		cam2.set("listen_input", false)
	var racing := GameState.mode == GameState.Mode.RACE
	GameState.race_time = 1.0 if (GameState.mode == GameState.Mode.FREEPLAY or GameState.mode == GameState.Mode.ROAM) else -3.0
	player.can_drive = not racing
	if player2:
		player2.can_drive = not racing
	if racing:
		_build_checkpoints()


func _make_cam(who: Node3D, spawn: Vector3, head: float) -> Camera3D:
	var c := Camera3D.new()
	c.set_script(preload("res://scripts/chase_cam.gd"))
	c.position = spawn + Vector3(sin(head) * 11.0, 4.6, cos(head) * 11.0)
	add_child(c)
	c.call("setup", who)
	c.fov = GameState.fov
	c.far = 1800.0 if not land.roam else 2800.0
	return c


func _setup_split_views() -> void:
	if cam:
		cam.current = false
	if cam2:
		cam2.current = false
	var layer := CanvasLayer.new()
	layer.layer = 1
	layer.name = "SplitLayer"
	add_child(layer)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 2)
	layer.add_child(row)
	row.add_child(_split_pane(cam, player))
	row.add_child(_split_pane(cam2, player2))


func _split_pane(camera: Camera3D, who: PlayerCar) -> Control:
	var wrap := Control.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = false
	vp.handle_input_locally = false
	vp.audio_listener_enable_3d = who == player
	var root_vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if root_vp.msaa_3d > Viewport.MSAA_2X else root_vp.msaa_3d
	vp.use_taa = false
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var half := Vector2i(maxi(2, int(root_vp.get_visible_rect().size.x * 0.5)), maxi(2, int(root_vp.get_visible_rect().size.y)))
	vp.size = half
	svc.add_child(vp)
	vp.world_3d = get_world_3d()
	if camera and is_instance_valid(camera):
		camera.current = false
		var old := camera.get_parent()
		if old:
			old.remove_child(camera)
		vp.add_child(camera)
		camera.current = true
	_attach_hud(who, wrap)
	return wrap


func _attach_hud(who: PlayerCar, overlay: Control = null) -> void:
	var hud: Control = preload("res://scripts/hud.gd").new()
	if overlay:
		overlay.add_child(hud)
	else:
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		layer.add_child(hud)
	hud.call("setup", who, land)


func _attach_chat() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.name = "ChatLayer"
	add_child(layer)
	var chat: Control = preload("res://scripts/mc_chat.gd").new()
	chat.name = "McChat"
	layer.add_child(chat)


func _spawn_life() -> void:
	if land == null or player == null or land.path.is_empty():
		return
	var n := land.wps2.size()
	if GameState.mode == GameState.Mode.RACE or (GameState.gun_enabled and GameState.mode != GameState.Mode.ROAM):
		var skills := [0.97, 0.94, 0.90, 0.86, 0.82]
		var count := GameState.opponent_count()
		for i in count:
			var npc := NpcCar.new()
			npc.land = land
			npc.setup(NpcCar.Role.RACER, "", land.path, player, skills[i % skills.size()])
			npc.display_name = "CPU %d" % (i + 1)
			add_child(npc)
			var slot := i
			var idx := (n - 8 - slot * 4) % maxi(n, 1)
			var wp: Vector2 = land.wps2[idx] if n > 0 else Vector2.ZERO
			var nrm: Vector2 = land.normals2[idx] if idx < land.normals2.size() else Vector2.RIGHT
			var side := 3.0 if slot % 2 == 0 else -3.0
			npc.place(Vector3(wp.x + nrm.x * side, 0.2, wp.y + nrm.y * side), land.heading_at(idx), idx)
			npc.can_drive = GameState.race_time >= 0.0
			racers.append(npc)
		if n > 0:
			var pidx := (n - 8 - count * 4) % n
			var wp2: Vector2 = land.wps2[pidx]
			var nrm2: Vector2 = land.normals2[pidx] if pidx < land.normals2.size() else Vector2.RIGHT
			player.place(Vector3(wp2.x + nrm2.x * -3.0, 0.2, wp2.y + nrm2.y * -3.0), land.heading_at(pidx), pidx)
			if player2:
				player2.place(Vector3(wp2.x + nrm2.x * 3.0, 0.2, wp2.y + nrm2.y * 3.0), land.heading_at(pidx), pidx)
	if GameState.mode == GameState.Mode.FREEPLAY and GameState.police_enabled and land.is_city(player.global_position):
		for i in 3:
			_spawn_cop_at(i)
	var traffic_n := 0
	if GameState.mode != GameState.Mode.RACE and not (GameState.mode == GameState.Mode.FREEPLAY and GameState.police_enabled):
		traffic_n = 0 if GameState.quality == 0 else (2 if land.roam else 3)
	for i in traffic_n:
		var npc := NpcCar.new()
		var pts: Array[Vector3] = land.path
		if land.island_paths.size() > 0:
			pts = []
			var ring: Array = land.island_paths[i % land.island_paths.size()]
			for p in ring:
				pts.append(p)
		if pts.is_empty():
			continue
		npc.land = land
		var idx := int(float(i + 1) / float(traffic_n + 1) * pts.size()) % pts.size()
		npc.setup(NpcCar.Role.TRAFFIC, str(GameState.NPC_GLBS[i % GameState.NPC_GLBS.size()]), pts, player)
		add_child(npc)
		npc.place(pts[idx] + Vector3(0, 0.2, 0), land.heading_at(idx % maxi(land.dirs2.size(), 1)), idx)
		racers.append(npc)


func _process(delta: float) -> void:
	_update_race(delta)
	if GameState.kill_flash > 0.0:
		GameState.kill_flash = maxf(0.0, GameState.kill_flash - delta)
	if GameState.cp_flash > 0.0:
		GameState.cp_flash = maxf(0.0, GameState.cp_flash - delta)
	if Net.online and player:
		sync_acc += delta
		if sync_acc >= 0.05:
			sync_acc = 0.0
			var p := player.global_position
			var r := player.global_rotation
			var car: Dictionary = GameState.selected_car()
			var tail := Net.uid.substr(maxi(0, Net.uid.length() - 3), 3).to_upper()
			Net.display_name = str(car.get("name", "RACER")).split(" ")[0] + "-" + tail
			Net.set_player({
				"model": str(car.get("id")),
				"color": GameState.paint_index,
				"x": snappedf(p.x, 0.01),
				"y": snappedf(p.y, 0.01),
				"z": snappedf(p.z, 0.01),
				"rx": snappedf(r.x, 0.01),
				"ry": snappedf(r.y, 0.01),
				"rz": snappedf(r.z, 0.01),
				"s": snappedf(player.speed_kmh, 0.1),
				"lobby": false,
			})
	if Lan.active and player:
		sync_acc += delta
		if sync_acc >= 0.04:
			sync_acc = 0.0
			_lan_send()
	if GameState.mode == GameState.Mode.FREEPLAY:
		_update_bounty(delta)
	if GameState.typing:
		return
	if Input.is_action_just_pressed("pause"):
		Net.leave()
		Lan.leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if Input.is_action_just_pressed("restart") and not Net.online and not Lan.active:
		get_tree().change_scene_to_file("res://scenes/loading.tscn")


func _lan_send() -> void:
	if not Lan.active or player == null:
		return
	var p := player.global_position
	var r := player.global_rotation
	var car: Dictionary = GameState.selected_car()
	lan_pose.rpc(p, r, str(car.get("id")), GameState.paint_index, str(car.get("name", "RACER")), player.speed_kmh)


@rpc("any_peer", "call_remote", "unreliable")
func lan_pose(pos: Vector3, rot: Vector3, model: String, color: int, pname: String, spd: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	if not remotes.has(id):
		var node = RemoteCarScene.new()
		node.name = "Lan_%d" % id
		add_child(node)
		remotes[id] = node
	remotes[id].apply_net({
		"x": pos.x, "y": pos.y, "z": pos.z,
		"rx": rot.x, "ry": rot.y, "rz": rot.z,
		"model": model, "color": color, "name": pname, "s": spd,
	})


func _lan_drop(id: int) -> void:
	if remotes.has(id):
		(remotes[id] as Node).queue_free()
		remotes.erase(id)


func _sync_firebase() -> void:
	if not Net.online:
		return
	var seen := {}
	for id in Net.players.keys():
		if str(id) == Net.uid:
			continue
		var data: Variant = Net.players[id]
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if bool(data.get("lobby", false)):
			continue
		seen[id] = true
		if not remotes.has(id):
			var r = RemoteCarScene.new()
			r.name = "Net_%s" % str(id)
			add_child(r)
			remotes[id] = r
		remotes[id].apply_net(data)
	var drop: Array = []
	for id in remotes.keys():
		if not seen.has(id):
			drop.append(id)
	for id in drop:
		(remotes[id] as Node).queue_free()
		remotes.erase(id)


func _spawn_cop_at(slot: int) -> void:
	if player == null or land == null:
		return
	var start := 0
	var count := maxi(land.wps2.size(), 1)
	if land.roam and not land.island_ranges.is_empty():
		var ii := land.nearest_island(player.global_position)
		var rg: Vector2i = land.island_ranges[clampi(ii, 0, land.island_ranges.size() - 1)]
		start = rg.x
		count = maxi(rg.y, 1)
	var idx := start + posmod(count / 3 + slot * 11, count)
	idx = clampi(idx, 0, land.wps2.size() - 1)
	var cop := NpcCar.new()
	cop.land = land
	cop.setup(NpcCar.Role.COP, "res://assets/cars/police.glb", land.path, player)
	cop.display_name = "PURSUIT %d" % (slot + 1)
	add_child(cop)
	var wp: Vector2 = land.wps2[idx]
	var nrm: Vector2 = land.normals2[idx] if idx < land.normals2.size() else Vector2(1, 0)
	var side := 4.5 if slot % 2 == 0 else -4.5
	cop.place(Vector3(wp.x + nrm.x * side, 0.2, wp.y + nrm.y * side), land.heading_at(idx), idx)
	cop.can_drive = true
	racers.append(cop)


func _build_checkpoints() -> void:
	checkpoint_indices.clear()
	for n in checkpoint_markers:
		n.queue_free()
	checkpoint_markers.clear()
	if GameState.mode != GameState.Mode.RACE or land.wps2.is_empty():
		return
	var n := land.wps2.size()
	var hw := land.half_width
	for i in GameState.CHECKPOINT_COUNT:
		var idx := int((float(i) + 0.5) * float(n) / float(GameState.CHECKPOINT_COUNT)) % n
		checkpoint_indices.append(idx)
		var wp: Vector2 = land.wps2[idx]
		var nrm: Vector2 = land.normals2[idx] if idx < land.normals2.size() else Vector2(1, 0)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.18
			cyl.bottom_radius = 0.18
			cyl.height = 3.2
			post.mesh = cyl
			post.position = Vector3(wp.x + nrm.x * side * (hw - 0.5), 1.6, wp.y + nrm.y * side * (hw - 0.5))
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 1.0, 0.75)
			mat.emission_enabled = true
			mat.emission = Color(0.15, 0.8, 0.55)
			post.material_override = mat
			add_child(post)
			checkpoint_markers.append(post)


func _update_race(delta: float) -> void:
	GameState.race_time += delta
	var green := GameState.race_time >= 0.0
	if player:
		player.can_drive = green
	if player2:
		player2.can_drive = green
	for n in get_tree().get_nodes_in_group("npc"):
		if n is ArcadeCar:
			(n as ArcadeCar).can_drive = green or GameState.mode != GameState.Mode.RACE
	if GameState.gun_enabled and green:
		_update_combat(delta)
	_resolve_car_collisions()
	if land == null or land.wps2.is_empty():
		return
	var npts := land.wps2.size()
	for car in racers:
		if car == null or not is_instance_valid(car):
			continue
		var old_idx := car.wp_idx
		var new_idx := land.nearest_index(car.global_position, car.wp_idx)
		if car == player or car == player2 or (car is NpcCar and (car as NpcCar).role == NpcCar.Role.RACER):
			_update_checkpoints(car, old_idx, new_idx)
		if not land.roam:
			if old_idx > npts * 0.8 and new_idx < npts * 0.2:
				if GameState.mode != GameState.Mode.RACE or car.checkpoints_hit >= GameState.CHECKPOINT_COUNT:
					car.lap += 1
					car.checkpoints_hit = 0
					car.checkpoint = 0
					if GameState.mode == GameState.Mode.RACE and car.lap > GameState.total_laps() and car not in finish_order:
						finish_order.append(car)
						if finish_order.size() == 1:
							if car == player:
								GameState.win_streak += 1
							else:
								GameState.win_streak = 0
			elif new_idx > npts * 0.8 and old_idx < npts * 0.2:
				car.lap -= 1
		car.wp_idx = new_idx
		land.clamp_arcade(car)
	var order: Array[ArcadeCar] = []
	for c in racers:
		if c and is_instance_valid(c) and not c.is_police:
			order.append(c)
	order.sort_custom(func(a: ArcadeCar, b: ArcadeCar) -> bool:
		return (a.lap * npts + a.wp_idx) > (b.lap * npts + b.wp_idx)
	)
	for i in order.size():
		order[i].race_pos = i + 1


func _crossed_checkpoint(old_idx: int, new_idx: int, cp_idx: int) -> bool:
	if old_idx == new_idx:
		return false
	if old_idx < new_idx:
		return old_idx < cp_idx and cp_idx <= new_idx
	return old_idx < cp_idx or cp_idx <= new_idx


func _update_checkpoints(car: ArcadeCar, old_idx: int, new_idx: int) -> void:
	if GameState.mode != GameState.Mode.RACE or checkpoint_indices.is_empty():
		return
	var target := car.checkpoint % GameState.CHECKPOINT_COUNT
	var cp_wp: int = checkpoint_indices[target]
	if _crossed_checkpoint(old_idx, new_idx, cp_wp):
		car.checkpoints_hit = mini(GameState.CHECKPOINT_COUNT, car.checkpoints_hit + 1)
		car.checkpoint = (car.checkpoint + 1) % GameState.CHECKPOINT_COUNT
		if car == player or car == player2:
			GameState.cp_flash = 0.9


func _update_combat(delta: float) -> void:
	if player and player.wants_fire() and GameState.race_time >= 0.0:
		_try_fire(player)
	if player2 and player2.wants_fire() and GameState.race_time >= 0.0:
		_try_fire(player2)
	for n in get_tree().get_nodes_in_group("npc"):
		if n is NpcCar and (n as NpcCar).wants_ai_fire(racers):
			_try_fire(n)
	var alive: Array[Bullet] = []
	for b in bullets:
		if b == null or not is_instance_valid(b):
			continue
		if not b.step(delta):
			b.queue_free()
			continue
		var hit := false
		for car in racers:
			if car == null or not is_instance_valid(car) or car == b.owner_car or car.wreck_t > 0.0:
				continue
			var dx := car.global_position.x - b.global_position.x
			var dz := car.global_position.z - b.global_position.z
			if dx * dx + dz * dz > 14.5:
				continue
			hit = true
			car.take_hit(b.owner_car)
			break
		if hit:
			b.queue_free()
		else:
			alive.append(b)
	bullets = alive
	for car in racers:
		if car and is_instance_valid(car) and car.wreck_t <= 0.001 and car.hp <= 0:
			pass
		if car and is_instance_valid(car) and car.hp <= 0 and car.wreck_t <= 0.0:
			var idx := land.nearest_index(car.global_position, car.wp_idx)
			var wp: Vector2 = land.wps2[idx]
			var nrm: Vector2 = land.normals2[idx] if idx < land.normals2.size() else Vector2(1, 0)
			car.respawn_at(Vector3(wp.x + nrm.x * 2.0, 0.2, wp.y + nrm.y * 2.0), land.heading_at(idx), idx)


func _try_fire(car: ArcadeCar) -> void:
	if not GameState.gun_enabled or car.wreck_t > 0.0 or car.fire_cd > 0.0:
		return
	shot_seq += 1
	var b := Bullet.new()
	add_child(b)
	b.setup(car, str(shot_seq), car.heading, car.muzzle())
	bullets.append(b)
	car.fire_cd = GameState.GUN_COOLDOWN


func _resolve_car_collisions() -> void:
	var radius := 2.5
	for i in racers.size():
		for j in range(i + 1, racers.size()):
			var a: ArcadeCar = racers[i]
			var b: ArcadeCar = racers[j]
			if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
				continue
			var dx := b.global_position.x - a.global_position.x
			var dz := b.global_position.z - a.global_position.z
			var d2 := dx * dx + dz * dz
			if d2 < radius * radius and d2 > 0.0001:
				var d := sqrt(d2)
				var push := (radius - d) * 0.5
				var ux := dx / d
				var uz := dz / d
				a.global_position.x -= ux * push
				a.global_position.z -= uz * push
				b.global_position.x += ux * push
				b.global_position.z += uz * push
				a.speed *= 0.97
				b.speed *= 0.97
				if a == player or b == player:
					if maxf(absf(a.speed), absf(b.speed)) > 12.0:
						GameState.add_crime("TRAFFIC COLLISION", 2400, 0.85)


func _update_bounty(delta: float) -> void:
	if player == null or land == null:
		return
	if not GameState.police_enabled or not land.is_city(player.global_position):
		GameState.decay_heat(delta)
		return
	var kmh := player.speed_kmh
	if kmh > 80.0:
		GameState.heat += delta * 0.07
	if kmh > 150.0:
		GameState.heat += delta * 0.11
	if kmh > 250.0:
		GameState.heat += delta * 0.16
	var police_near := false
	var police_close := false
	var police_count := 0
	for n in get_tree().get_nodes_in_group("npc"):
		if n is NpcCar and (n as NpcCar).role == NpcCar.Role.COP:
			police_count += 1
			var d: float = n.global_position.distance_to(player.global_position)
			if d < 50.0:
				police_near = true
			if d < 20.0:
				police_close = true
	if police_near:
		GameState.heat += delta * 0.20
	if police_close:
		GameState.bounty += int(delta * 90.0)
		GameState.heat += delta * 0.28
	if GameState.heat > 0.5:
		GameState.bounty += int(GameState.heat * delta * 40.0)
	if kmh < 45.0 and not police_near:
		GameState.heat = maxf(0.0, GameState.heat - delta * 0.15)
	if GameState.heat > 1.0 and not police_near:
		GameState.chase_bonus += delta
		if GameState.chase_bonus > 5.0:
			GameState.bounty += int(GameState.heat * 300.0)
			GameState.heat = maxf(0.0, GameState.heat - 1.5)
			GameState.chase_bonus = 0.0
	else:
		GameState.chase_bonus = 0.0
	GameState.heat = clampf(GameState.heat, 0.0, 5.0)
	GameState.heat_changed.emit(GameState.heat)
	GameState.bounty_changed.emit(GameState.bounty)
	if GameState.heat >= 4.0 and police_count < 5:
		_spawn_cop_at(police_count)
