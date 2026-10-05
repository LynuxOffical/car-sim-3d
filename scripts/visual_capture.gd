extends Node

const OUT := "D:/cursor/car-sim-3d/playtest_shots"

func _ready() -> void:
	print("CAPTURE_START")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GameState.quality = 2
	GameState.touch_enabled = false
	DirAccess.make_dir_recursive_absolute(OUT)
	await _wait(2)
	await _capture_maps()
	await _capture_main()
	await _capture_world()
	print("CAPTURE_DONE")
	get_tree().quit(0)


func _capture_maps() -> void:
	GameState.race_island = 0
	var ui: Control = load("res://scenes/map_select.tscn").instantiate()
	get_tree().root.add_child(ui)
	ui.menu_time = 6.5
	ui._orbit_camera()
	await _wait(16)
	await _shot("map_meadow", ui)
	GameState.race_island = 3
	ui.rebuild_track(3)
	ui._sync()
	ui.menu_time = 9.0
	ui._orbit_camera()
	await _wait(16)
	await _shot("map_rockport", ui)
	ui.queue_free()
	await _wait(2)


func _capture_main() -> void:
	GameState.race_island = 0
	var ui: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(ui)
	ui.menu_time = 6.5
	ui._orbit_camera()
	await _wait(16)
	await _shot("main_menu", ui)
	ui.queue_free()
	await _wait(2)


func _capture_world() -> void:
	GameState.mode = GameState.Mode.FREEPLAY
	GameState.race_island = 0
	GameState.quality = 1
	var world: Node = load("res://scripts/world.gd").new()
	world.name = "World"
	get_tree().root.add_child(world)
	await _wait(40)
	await _shot("hud_meadow", world)
	world.queue_free()
	await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(label: String, from: Node = null) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, label]
	img.save_png(path)
	print("CAPTURE %s root=%dx%d mean=%.3f" % [label, img.get_width(), img.get_height(), _mean(img)])
	if from:
		var sv := _find_sv(from)
		if sv:
			await RenderingServer.frame_post_draw
			var tex: ViewportTexture = sv.get_texture()
			if tex:
				var img2: Image = tex.get_image()
				if img2:
					img2.save_png("%s/%s_3d.png" % [OUT, label])
					print("CAPTURE %s_3d %dx%d mean=%.3f" % [label, img2.get_width(), img2.get_height(), _mean(img2)])


func _find_sv(n: Node) -> SubViewport:
	if n is SubViewport:
		return n
	for c in n.get_children():
		var f := _find_sv(c)
		if f:
			return f
	return null


func _mean(img: Image) -> float:
	var acc := 0.0
	var n := 0
	var step := maxi(8, img.get_width() / 40)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			acc += (c.r + c.g + c.b) * 0.333
			n += 1
	return acc / float(maxi(n, 1))
