extends Control

const UiKit := preload("res://scripts/ui_kit.gd")
const CarPaint := preload("res://scripts/car_paint.gd")
const Kit := preload("res://scripts/scenery_kit.gd")

var preview_host: Node3D
var cam: Camera3D
var title: Label
var subtitle: Label
var status: Label
var splash: Label
var land: IslandWorld
var vp_world: Node3D
var menu_env: Environment
var menu_vp: SubViewport
var menu_sun: DirectionalLight3D
var menu_time := 0.0
var _placeholder: ColorRect
var show_fill: OmniLight3D
var show_rim: OmniLight3D
var show_spot: SpotLight3D
var show_spot2: SpotLight3D
var show_ring: MeshInstance3D

func _ready() -> void:
	GameState.typing = false
	set_anchors_preset(PRESET_FULL_RECT)
	_placeholder = ColorRect.new()
	_placeholder.set_anchors_preset(PRESET_FULL_RECT)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.color = Color(0.05, 0.07, 0.10, 1)
	add_child(_placeholder)
	_build_chrome()
	build_ui()
	call_deferred("_build_world_behind")


func _build_world_behind() -> void:
	_build_world()
	if menu_vp:
		var wrap := menu_vp.get_parent()
		if wrap:
			move_child(wrap, 0)
	if _placeholder and is_instance_valid(_placeholder):
		_placeholder.queue_free()
		_placeholder = null
	refresh_preview()


func build_ui() -> void:
	pass


func header_text() -> String:
	return "CAR SIM 3D"


func header_px() -> int:
	return 36


func world_kind() -> String:
	return "forest"


func chrome_kind() -> String:
	return "sidebar"


func show_preview() -> bool:
	return world_kind() == "showroom"


func overlay_dim() -> Color:
	if chrome_kind() == "wanted":
		return Color(0, 0, 0, 0)
	if world_kind() == "track":
		if header_text() == "CHOOSE TRACK":
			return Color(0, 0, 0, 0.12)
		return Color(0.02, 0.03, 0.06, 0.34)
	if chrome_kind() == "python":
		return Color(0.02, 0.03, 0.06, 0.30)
	if world_kind() == "showroom":
		return Color(0.0, 0.0, 0.0, 0.12)
	return Color(0.02, 0.05, 0.06, 0.28)


func _build_world() -> void:
	var wrap := SubViewportContainer.new()
	wrap.set_anchors_preset(PRESET_FULL_RECT)
	wrap.stretch = true
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	var vp := SubViewport.new()
	menu_vp = vp
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	_apply_menu_quality()
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.use_taa = false
	wrap.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)

	var env_n := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.98
	env.glow_enabled = true
	env.glow_intensity = 0.06
	env.ssao_enabled = false
	env.sdfgi_enabled = false
	env.adjustment_enabled = false
	if world_kind() == "showroom":
		Mats.paint_sky(env, Color(0.10, 0.11, 0.14), Color(0.06, 0.07, 0.09))
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.38, 0.40, 0.46)
		env.ambient_light_energy = 0.70
		env.fog_enabled = false
		env.glow_enabled = true
		env.glow_intensity = 0.05
	elif world_kind() == "track":
		if chrome_kind() == "wanted":
			Mats.paint_sky(env, Color(0.18, 0.16, 0.14), Color(0.08, 0.08, 0.09))
			env.tonemap_exposure = 0.82
			env.fog_enabled = true
			env.fog_density = 0.0045
			env.fog_light_color = Color(0.42, 0.32, 0.18)
			env.fog_sky_affect = 0.55
			env.glow_intensity = 0.04
		else:
			Mats.paint_sky(env, Color(0.66, 0.80, 0.95), Color(0.29, 0.50, 0.23))
			env.fog_enabled = true
			env.fog_density = 0.00105
			env.fog_light_color = Color(0.70, 0.80, 0.90)
			env.fog_sky_affect = 0.45
	else:
		Mats.paint_sky(env, Color(0.42, 0.48, 0.52), Color(0.23, 0.42, 0.18))
		env.fog_enabled = true
		env.fog_density = 0.004
		env.fog_light_color = Color(0.5, 0.56, 0.6)
	env_n.environment = env
	world.add_child(env_n)

	var sun := DirectionalLight3D.new()
	menu_sun = sun
	sun.shadow_enabled = GameState.quality > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 280.0
	if world_kind() == "showroom":
		sun.rotation_degrees = Vector3(-38, 48, 0)
		sun.light_energy = 1.05
		sun.light_color = Color(0.96, 0.95, 0.92)
	elif world_kind() == "track":
		if chrome_kind() == "wanted":
			sun.rotation_degrees = Vector3(-18, 48, 0)
			sun.light_energy = 0.72
			sun.light_color = Color(1.0, 0.72, 0.42)
		else:
			sun.rotation_degrees = Vector3(-52, 38, 0)
			sun.light_energy = 1.15
			sun.light_color = Color(1.0, 0.95, 0.88)
	else:
		sun.rotation_degrees = Vector3(-50, 20, 0)
		sun.light_energy = 0.9
		sun.light_color = Color(0.85, 0.88, 0.92)
	world.add_child(sun)

	if world_kind() == "showroom":
		_dress_showroom(world)
	elif world_kind() == "track":
		vp_world = world
		menu_env = env
		rebuild_track(_track_index())
	else:
		_grass(world)
		Kit.spawn(world, Kit.PINES[0], Vector3(-7, 0, -4), 0.3, 12.0, true, true)
		Kit.spawn(world, Kit.PINES[1], Vector3(8, 0, -6), -0.4, 13.0, true, true)
		Kit.spawn(world, Kit.PINES[2], Vector3(-11, 0, 3), 1.1, 11.0, true, true)
		Kit.spawn(world, Kit.PINES[3], Vector3(11, 0, 2), 0.6, 12.5, true, true)
		_hill(world, Vector3(-18, 2, -16), Vector3(14, 8, 10))
		_hill(world, Vector3(20, 3, -18), Vector3(16, 10, 12))

	preview_host = Node3D.new()
	preview_host.position = Vector3(0.0, 0.12 if world_kind() == "showroom" else 0.05, 0.0)
	world.add_child(preview_host)

	cam = Camera3D.new()
	cam.current = true
	cam.near = 0.25
	cam.far = 4500.0
	cam.fov = 58.0
	world.add_child(cam)
	if world_kind() == "showroom":
		cam.fov = 52.0
		_orbit_showroom()
	elif world_kind() == "track":
		_orbit_camera()
	else:
		cam.position = Vector3(6.4, 2.2, 8.4)
		_safe_look(cam, Vector3(0.2, 0.85, 0.2))


func _track_index() -> int:
	if GameState.race_island >= 0:
		return clampi(GameState.race_island, 0, IslandWorld.DEFS.size() - 1)
	return 0


func rebuild_track(idx: int) -> void:
	if vp_world == null:
		return
	if land and is_instance_valid(land):
		vp_world.remove_child(land)
		land.free()
		land = null
	land = IslandWorld.new()
	vp_world.add_child(land)
	land.build(clampi(idx, 0, IslandWorld.DEFS.size() - 1), false)
	if menu_env:
		var sky: Color = land.theme.get("sky", Color(0.48, 0.62, 0.78))
		var ground: Color = land.theme.get("ground", Color(0.29, 0.50, 0.23))
		if chrome_kind() == "wanted":
			sky = sky.lerp(Color(0.16, 0.12, 0.10), 0.62)
			ground = ground.lerp(Color(0.08, 0.07, 0.07), 0.45)
		Mats.paint_sky(menu_env, sky, ground)
		menu_env.fog_light_color = sky
	_orbit_camera()
	_apply_menu_weather()


func _orbit_camera() -> void:
	if cam == null or land == null:
		return
	if chrome_kind() == "wanted":
		var spawn := land.spawn_for(0)
		var h := land.spawn_yaw
		var a := menu_time * 0.10
		var back := Vector3(sin(h), 0.0, cos(h))
		var side := Vector3(cos(h), 0.0, -sin(h))
		cam.far = 1800.0
		cam.fov = 44.0
		cam.global_position = spawn + back * (7.4 + sin(a) * 0.4) + side * (4.8 + cos(a) * 0.25) + Vector3(0, 1.85, 0)
		_safe_look(cam, spawn + Vector3(side.x * -0.4, 0.72, side.z * -0.4))
		if preview_host:
			preview_host.global_position = spawn
			preview_host.rotation.y = h
		return
	var a := menu_time * 0.15
	var c := land.track_center()
	var r := maxf(80.0, land.track_span() * 0.72)
	cam.far = maxf(5000.0, r * 16.0)
	cam.position = Vector3(c.x + sin(a) * r, r * 0.38, c.z + cos(a) * r)
	_safe_look(cam, c)


func _safe_look(node: Node3D, to: Vector3) -> void:
	if node == null:
		return
	if node.global_position.distance_squared_to(to) < 0.0008:
		return
	var dir := (to - node.global_position).normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.995:
		up = Vector3.FORWARD
	node.look_at(to, up)


func _grass(world: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor.mesh = plane
	floor.material_override = Mats.solid(Color(0.23, 0.42, 0.18), 1.0)
	world.add_child(floor)
	for i in 10:
		var patch := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(3, 7), 0.08, randf_range(3, 7))
		patch.mesh = box
		patch.position = Vector3(randf_range(-16, 16), 0.03, randf_range(-16, 16))
		patch.material_override = Mats.solid(Color(0.18, 0.34, 0.14) if i % 2 == 0 else Color(0.28, 0.46, 0.2), 1.0)
		world.add_child(patch)
	var dirt := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(6, 0.06, 18)
	dirt.mesh = dmesh
	dirt.position = Vector3(1.5, 0.02, 2)
	dirt.rotation_degrees = Vector3(0, 18, 0)
	dirt.material_override = Mats.solid(Color(0.38, 0.28, 0.16), 1.0)
	world.add_child(dirt)


func _mc_tree(world: Node3D, pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var t := BoxMesh.new()
	t.size = Vector3(0.7, 3.2, 0.7)
	trunk.mesh = t
	trunk.position = pos + Vector3(0, 1.6, 0)
	trunk.material_override = Mats.solid(Color(0.32, 0.2, 0.1), 1.0)
	world.add_child(trunk)
	var leaves := MeshInstance3D.new()
	var l := BoxMesh.new()
	l.size = Vector3(3.2, 3.0, 3.2)
	leaves.mesh = l
	leaves.position = pos + Vector3(0, 3.6, 0)
	leaves.material_override = Mats.solid(Color(0.16, 0.38, 0.14), 1.0)
	world.add_child(leaves)


func _hill(world: Node3D, pos: Vector3, size: Vector3) -> void:
	var h := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	h.mesh = b
	h.position = pos
	h.material_override = Mats.solid(Color(0.28, 0.38, 0.26), 1.0)
	world.add_child(h)


func _wanted_chrome() -> void:
	var gold := Color(0.93, 0.76, 0.22)
	var top := ColorRect.new()
	top.color = gold
	top.set_anchors_preset(PRESET_TOP_WIDE)
	top.offset_bottom = 2
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var bot := ColorRect.new()
	bot.color = gold
	bot.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bot.offset_top = -2
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot)
	title = UiKit.shadow_label(header_text(), header_px(), Color(0.98, 0.96, 0.88))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(PRESET_TOP_WIDE)
	title.offset_left = 0
	title.offset_right = 0
	title.offset_top = 16
	title.offset_bottom = 62
	add_child(title)
	splash = UiKit.shadow_label("MOST WANTED", 13, gold)
	splash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash.set_anchors_preset(PRESET_TOP_WIDE)
	splash.offset_top = 58
	splash.offset_bottom = 80
	add_child(splash)
	subtitle = UiKit.shadow_label("", 15, Color(0.86, 0.88, 0.90))
	subtitle.visible = false
	add_child(subtitle)
	status = UiKit.shadow_label("", 13, Color(0.70, 0.72, 0.74))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.set_anchors_preset(PRESET_TOP_RIGHT)
	status.anchor_left = 1.0
	status.offset_left = -420
	status.offset_right = -28
	status.offset_top = 22
	status.offset_bottom = 52
	add_child(status)


func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if chrome_kind() == "wanted":
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/mw_grade.gdshader")
		dim.material = mat
		dim.color = Color.WHITE
	else:
		dim.color = overlay_dim()
	add_child(dim)
	if chrome_kind() == "wanted":
		_wanted_chrome()
		return
	if chrome_kind() == "python":
		var topbar := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.04, 0.07, 0.58)
		sb.border_width_bottom = 1
		sb.border_color = Color(1, 1, 1, 0.10)
		topbar.add_theme_stylebox_override("panel", sb)
		topbar.set_anchors_preset(PRESET_TOP_WIDE)
		topbar.offset_bottom = 90
		topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(topbar)
	title = UiKit.shadow_label(header_text(), header_px(), Color(0.94, 0.96, 0.98))
	if chrome_kind() == "python":
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.set_anchors_preset(PRESET_TOP_WIDE)
		title.offset_left = 0
		title.offset_right = 0
		title.offset_top = 22
		title.offset_bottom = 86
	else:
		title.position = Vector2(48, 28)
	add_child(title)
	splash = UiKit.shadow_label(_splash(), 18, Color(1.0, 0.92, 0.35))
	splash.position = Vector2(54, 92)
	splash.rotation_degrees = -6
	splash.visible = chrome_kind() != "python"
	add_child(splash)
	subtitle = UiKit.shadow_label("", 20, Color(0.82, 0.88, 0.9))
	subtitle.position = Vector2(52, 128)
	subtitle.visible = chrome_kind() != "python"
	add_child(subtitle)
	status = UiKit.shadow_label("", 16, Color(0.75, 0.8, 0.78))
	status.position = Vector2(52, 160)
	status.visible = chrome_kind() != "python"
	add_child(status)


func _splash() -> String:
	var lines := PackedStringArray([
		"A storm is rolling in!",
		"Also try nitro on the bikes!",
		"Watch for puddles.",
		"Creeper? No. Cops.",
		"Rainy day driving.",
	])
	return lines[randi() % lines.size()]


func _add(parent: Control, b: Button, cb: Callable) -> void:
	b.pressed.connect(cb)
	parent.add_child(b)


func refresh_preview() -> void:
	if preview_host == null:
		return
	if not show_preview():
		for c in preview_host.get_children():
			preview_host.remove_child(c)
			c.free()
		_refresh_labels()
		return
	for c in preview_host.get_children():
		preview_host.remove_child(c)
		c.free()
	var v: Dictionary = GameState.selected_car()
	var paint: Color = GameState.selected_paint()
	var node: Node3D
	if str(v.get("kind")) == "bike":
		var style := "sport"
		if str(v.get("id")) == "raid":
			style = "dirt"
		elif str(v.get("id")) == "hawk":
			style = "cafe"
		elif str(v.get("id")) == "bagger":
			style = "cruiser"
		elif str(v.get("id")) == "specter":
			style = "naked"
		node = VehicleFactory.make_bike(paint, style)
		node.position.y = 0.05
	else:
		var packed: PackedScene = load(str(v.get("glb")))
		if packed == null:
			return
		node = packed.instantiate()
		node.position.y = 0.0
		preview_host.add_child(node)
		CarPaint.apply(node, str(v.get("id")), paint, GameState.paint_index, str(v.get("id")) == "interceptor", float(v.get("length", 4.5)))
		_refresh_labels()
		return
	preview_host.add_child(node)
	_refresh_labels()


func _refresh_labels() -> void:
	var v: Dictionary = GameState.selected_car()
	var paint: Dictionary = GameState.PAINTS[GameState.paint_index]
	var grades := PackedStringArray(["LOW", "MEDIUM", "HIGH"])
	var map_name := "ROAM WORLD"
	if GameState.mode == GameState.Mode.RACE or (GameState.mode == GameState.Mode.FREEPLAY and GameState.race_island >= 0):
		map_name = str(IslandWorld.DEFS[clampi(GameState.race_island, 0, IslandWorld.DEFS.size() - 1)]["name"])
	elif GameState.mode == GameState.Mode.ROAM:
		map_name = "BRIDGED ISLANDS"
	if subtitle:
		subtitle.text = "%s  ·  %s  ·  %s" % [v["name"], str(v["kind"]).to_upper(), str(v.get("tag", ""))]
	if status:
		status.text = "%s  ·  %s  ·  %s  ·  GUNS %s  ·  GFX %s  ·  TAA %s  ·  FOV %d" % [
			paint["name"], map_name, GameState.weather()["name"],
			"ON" if GameState.gun_enabled else "OFF",
			grades[clampi(GameState.quality, 0, 2)],
			"ON" if GameState.use_taa else "OFF", int(GameState.fov)
		]


func apply_menu_settings() -> void:
	_apply_menu_quality()
	_apply_menu_weather()


func _apply_menu_quality() -> void:
	if menu_vp == null:
		return
	match GameState.quality:
		0:
			menu_vp.msaa_3d = Viewport.MSAA_DISABLED
		1:
			menu_vp.msaa_3d = Viewport.MSAA_2X
		_:
			menu_vp.msaa_3d = Viewport.MSAA_4X
	if menu_sun:
		menu_sun.shadow_enabled = GameState.quality > 0


func _apply_menu_weather() -> void:
	if menu_env == null or world_kind() != "track":
		return
	var w: Dictionary = GameState.weather()
	var sky: Color = land.theme.get("sky", Color(0.66, 0.80, 0.95)) if land else Color(0.66, 0.80, 0.95)
	var ground: Color = land.theme.get("ground", Color(0.29, 0.50, 0.23)) if land else Color(0.29, 0.50, 0.23)
	if chrome_kind() == "wanted":
		sky = sky.lerp(Color(0.16, 0.12, 0.10), 0.62)
		ground = ground.lerp(Color(0.08, 0.07, 0.07), 0.45)
	var name := str(w.get("name", "CLEAR"))
	var fog := 0.00105
	var energy := 1.15
	match name:
		"RAIN":
			sky = sky.lerp(Color(0.38, 0.44, 0.52), 0.55)
			fog = 0.004
			energy = 0.72
		"STORM":
			sky = sky.lerp(Color(0.28, 0.32, 0.40), 0.7)
			fog = 0.006
			energy = 0.52
		"SNOW":
			sky = sky.lerp(Color(0.78, 0.84, 0.90), 0.45)
			fog = 0.007
			energy = 0.78
	Mats.paint_sky(menu_env, sky, ground)
	menu_env.fog_enabled = true
	menu_env.fog_density = fog
	menu_env.fog_light_color = sky
	if menu_sun:
		menu_sun.light_energy = energy


func _dress_showroom(world: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48, 48)
	floor.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.055, 0.06, 0.07)
	fmat.metallic = 0.72
	fmat.roughness = 0.16
	floor.material_override = fmat
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(floor)
	var plate := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.15
	cyl.bottom_radius = 3.15
	cyl.height = 0.08
	plate.mesh = cyl
	plate.position.y = 0.04
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.12, 0.13, 0.15)
	pmat.metallic = 0.85
	pmat.roughness = 0.18
	pmat.emission_enabled = true
	pmat.emission = Color(0.18, 0.22, 0.28)
	pmat.emission_energy_multiplier = 0.45
	plate.material_override = pmat
	world.add_child(plate)
	show_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.25
	torus.outer_radius = 3.52
	show_ring.mesh = torus
	show_ring.position.y = 0.06
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.85, 0.72, 0.28)
	rmat.metallic = 0.4
	rmat.roughness = 0.28
	rmat.emission_enabled = true
	rmat.emission = Color(0.95, 0.78, 0.22)
	rmat.emission_energy_multiplier = 0.9
	show_ring.material_override = rmat
	world.add_child(show_ring)
	for i in 6:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.06, 7.5)
		strip.mesh = box
		var ang := TAU * float(i) / 6.0
		strip.position = Vector3(sin(ang) * 7.4, 5.4, cos(ang) * 7.4)
		strip.rotation.y = ang
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.9, 0.92, 0.95)
		sm.emission_enabled = true
		sm.emission = Color(0.75, 0.82, 1.0)
		sm.emission_energy_multiplier = 1.4
		strip.material_override = sm
		world.add_child(strip)
		var ceil := OmniLight3D.new()
		ceil.position = Vector3(sin(ang) * 6.2, 4.6, cos(ang) * 6.2)
		ceil.light_energy = 0.85
		ceil.light_color = Color(0.85, 0.9, 1.0)
		ceil.omni_range = 9.0
		ceil.shadow_enabled = false
		world.add_child(ceil)
	show_fill = OmniLight3D.new()
	show_fill.position = Vector3(-3.2, 2.6, 2.4)
	show_fill.light_energy = 2.1
	show_fill.light_color = Color(0.55, 0.72, 1.0)
	show_fill.omni_range = 14.0
	show_fill.shadow_enabled = false
	world.add_child(show_fill)
	show_rim = OmniLight3D.new()
	show_rim.position = Vector3(3.4, 1.7, -2.6)
	show_rim.light_energy = 1.55
	show_rim.light_color = Color(1.0, 0.72, 0.42)
	show_rim.omni_range = 11.0
	show_rim.shadow_enabled = false
	world.add_child(show_rim)
	show_spot = SpotLight3D.new()
	show_spot.position = Vector3(0.0, 7.2, 0.0)
	show_spot.rotation_degrees = Vector3(-72, 0, 0)
	show_spot.spot_range = 16.0
	show_spot.spot_angle = 32.0
	show_spot.light_energy = 3.4
	show_spot.light_color = Color(1.0, 0.96, 0.88)
	show_spot.shadow_enabled = false
	world.add_child(show_spot)
	show_spot2 = SpotLight3D.new()
	show_spot2.position = Vector3(4.5, 5.8, -3.2)
	show_spot2.rotation_degrees = Vector3(-55, 40, 0)
	show_spot2.spot_range = 14.0
	show_spot2.spot_angle = 28.0
	show_spot2.light_energy = 2.2
	show_spot2.light_color = Color(0.55, 0.78, 1.0)
	show_spot2.shadow_enabled = false
	world.add_child(show_spot2)
	var parked := [1, 4, 7]
	for i in parked.size():
		var v: Dictionary = GameState.VEHICLES[parked[i]]
		var packed: PackedScene = load(str(v.get("glb", "")))
		if packed == null:
			continue
		var n: Node3D = packed.instantiate()
		var ang := TAU * float(i) / float(parked.size()) + 0.7
		n.position = Vector3(sin(ang) * 9.6, 0.0, cos(ang) * 9.6)
		n.rotation.y = ang + PI
		n.scale = Vector3.ONE * 0.92
		world.add_child(n)
		CarPaint.apply(n, str(v.get("id")), GameState.PAINTS[(i * 3 + 2) % GameState.PAINTS.size()]["color"], (i * 3 + 2) % GameState.PAINTS.size(), false, float(v.get("length", 4.5)))
	var haze := GPUParticles3D.new()
	haze.amount = 28
	haze.lifetime = 4.5
	haze.position = Vector3(0, 1.2, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_shape_scale = Vector3(8, 1.2, 8)
	pm.gravity = Vector3(0, 0.15, 0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.color = Color(0.7, 0.78, 0.9, 0.22)
	haze.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	haze.draw_pass_1 = quad
	world.add_child(haze)


func _orbit_showroom() -> void:
	if cam == null:
		return
	var a := menu_time * 0.18
	cam.position = Vector3(sin(a) * 11.2, 2.55 + sin(menu_time * 0.35) * 0.18, cos(a) * 12.0)
	_safe_look(cam, Vector3(0.0, 0.72, 0.0))


func _process(_delta: float) -> void:
	menu_time += _delta
	if world_kind() == "track":
		_orbit_camera()
	elif world_kind() == "showroom":
		_orbit_showroom()
		if show_spot:
			show_spot.rotation.y += _delta * 0.65
		if show_spot2:
			show_spot2.rotation.y -= _delta * 0.42
		if show_fill:
			show_fill.light_energy = 1.85 + sin(menu_time * 2.3) * 0.35
		if show_rim:
			show_rim.light_energy = 1.35 + sin(menu_time * 1.7 + 1.2) * 0.28
		if show_ring and show_ring.material_override is StandardMaterial3D:
			(show_ring.material_override as StandardMaterial3D).emission_energy_multiplier = 0.7 + sin(menu_time * 3.1) * 0.4
	if preview_host and show_preview() and chrome_kind() != "wanted":
		preview_host.rotation.y += _delta * 0.22
	if splash and splash.visible:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.04
		splash.scale = Vector2(pulse, pulse)
