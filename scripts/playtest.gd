extends Node3D

func _ready() -> void:
	print("PLAYTEST_START")
	GameState.quality = 0
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.race_island = 3
	GameState.touch_enabled = false
	GameState.car_index = 0
	GameState.paint_index = 3
	var world_script: Script = load("res://scripts/world.gd")
	if world_script == null:
		print("PLAYTEST_FAIL world.gd did not load")
		get_tree().quit(1)
		return
	var world: Node = world_script.new()
	if world == null:
		print("PLAYTEST_FAIL world.gd new() failed")
		get_tree().quit(1)
		return
	world.name = "World"
	add_child(world)
	print("PLAYTEST_CHILDREN %d" % world.get_child_count())
	var player := world.get_node_or_null("Player") as PlayerCar
	if player == null:
		print("PLAYTEST_FAIL no Player")
		get_tree().quit(1)
		return
	var land := world.get("land") as IslandWorld
	var path_n := 0
	var map_name := "?"
	if land:
		path_n = land.path.size()
		map_name = str(land.theme.get("name", "?"))
	print("PLAYTEST_MAP %s path=%d pos=%s yaw=%.2f vmax=%.1f" % [
		map_name, path_n, str(player.global_position), land.spawn_yaw if land else 0.0, player.max_speed
	])
	var peds := get_tree().get_nodes_in_group("pedestrian").size()
	print("PLAYTEST_PEDS %d" % peds)
	var grade := false
	for c in world.get_children():
		var scr: Script = c.get_script()
		if scr and str(scr.resource_path).ends_with("nfs_overlay.gd"):
			grade = true
	print("PLAYTEST_SHADER %s" % grade)
	player.auto_throttle = 1.0
	var t0 := Time.get_ticks_msec()
	var max_kmh := 0.0
	while Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
		max_kmh = maxf(max_kmh, player.speed_kmh)
	print("PLAYTEST_SPEED_KMH %.1f y=%.2f" % [max_kmh, player.global_position.y])
	var ok := max_kmh >= 40.0 and peds == 0 and path_n > 20 and grade
	print("PLAYTEST_RESULT " + ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
