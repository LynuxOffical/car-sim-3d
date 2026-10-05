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
var menu_time := 0.0

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_build_world()
	_build_chrome()
	build_ui()
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
	if world_kind() == "track":
		if header_text() == "CHOOSE TRACK":
			return Color(0, 0, 0, 0.12)
		return Color(0.02, 0.03, 0.06, 0.34)
	if chrome_kind() == "python":
		return Color(0.02, 0.03, 0.06, 0.38)
	if world_kind() == "showroom":
		return Color(0.0, 0.0, 0.0, 0.18)
	return Color(0.02, 0.05, 0.06, 0.28)


func _build_world() -> void:
	var wrap := SubViewportContainer.new()
	wrap.set_anchors_preset(PRESET_FULL_RECT)
	wrap.stretch = true
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
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
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 420.0
	if world_kind() == "showroom":
		sun.rotation_degrees = Vector3(-38, 48, 0)
		sun.light_energy = 1.05
		sun.light_color = Color(0.96, 0.95, 0.92)
	elif world_kind() == "track":
		sun.rotation_degrees = Vector3(-52, 38, 0)
		sun.light_energy = 1.4
		sun.light_color = Color(1.0, 0.95, 0.88)
	else:
		sun.rotation_degrees = Vector3(-50, 20, 0)
		sun.light_energy = 0.9
		sun.light_color = Color(0.85, 0.88, 0.92)
	world.add_child(sun)

	if world_kind() == "showroom":
		var floor := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(40, 40)
		floor.mesh = plane
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.07, 0.075, 0.085)
		fmat.metallic = 0.55
		fmat.roughness = 0.22
		fmat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		floor.material_override = fmat
		floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(floor)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 3.2
		torus.outer_radius = 3.45
		ring.mesh = torus
		ring.position.y = 0.02
		ring.material_override = Mats.solid(Color(0.22, 0.24, 0.28), 0.35, 0.4)
		world.add_child(ring)
		var fill := OmniLight3D.new()
		fill.position = Vector3(-3.5, 2.4, 2.2)
		fill.light_energy = 1.6
		fill.light_color = Color(0.55, 0.70, 0.95)
		fill.omni_range = 12.0
		fill.shadow_enabled = false
		world.add_child(fill)
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
	preview_host.position = Vector3(0.0, 0.05, 0.0)
	world.add_child(preview_host)

	cam = Camera3D.new()
	cam.current = true
	cam.near = 0.25
	cam.far = 4500.0
	cam.fov = 58.0
	world.add_child(cam)
	if world_kind() == "showroom":
		cam.position = Vector3(4.2, 1.7, 5.6)
		cam.fov = 46.0
		cam.look_at(Vector3(0.0, 0.55, 0.0))
	elif world_kind() == "track":
		_orbit_camera()
	else:
		cam.position = Vector3(6.4, 2.2, 8.4)
		cam.look_at(Vector3(0.2, 0.85, 0.2))


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
		Mats.paint_sky(menu_env, sky, ground)
		menu_env.fog_light_color = sky
	_orbit_camera()


func _orbit_camera() -> void:
	if cam == null or land == null:
		return
	var a := menu_time * 0.15
	var c := land.track_center()
	var r := maxf(80.0, land.track_span() * 0.72)
	cam.far = maxf(5000.0, r * 16.0)
	cam.position = Vector3(c.x + sin(a) * r, r * 0.38, c.z + cos(a) * r)
	cam.look_at(c)


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


func _build_chrome() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = overlay_dim()
	add_child(dim)
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


func _process(_delta: float) -> void:
	menu_time += _delta
	if world_kind() == "track":
		_orbit_camera()
	if preview_host and show_preview():
		preview_host.rotation.y += _delta * 0.35
	if splash and splash.visible:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.04
		splash.scale = Vector2(pulse, pulse)
