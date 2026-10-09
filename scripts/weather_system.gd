extends Node3D
class_name WeatherSystem

var env: Environment
var sun: DirectionalLight3D
var rain: GPUParticles3D
var rain_close: GPUParticles3D
var snow: GPUParticles3D
var dust: GPUParticles3D
var event := "CLEAR"
var biome := "meadow"
var player: Node3D
var world: IslandWorld
var flash := 0.0
var next_strike := 2.4
var _applied := ""
var _sun_energy := 1.12
var _base_exposure := 0.96

func setup(p_env: Environment, p_sun: DirectionalLight3D, p_player: Node3D, p_world: IslandWorld) -> void:
	env = p_env
	sun = p_sun
	player = p_player
	world = p_world
	if env:
		_base_exposure = env.tonemap_exposure
	var q := GameState.quality
	var rain_n := 420 if q == 0 else (900 if q == 1 else 1600)
	var close_n := 220 if q == 0 else (480 if q == 1 else 900)
	var snow_n := 280 if q == 0 else (640 if q == 1 else 1100)
	var dust_n := 180 if q == 0 else (360 if q == 1 else 640)
	rain = _particles(Color(0.70, 0.80, 0.92, 0.55), rain_n, Vector3(6.0, -52.0, 2.0), Vector2(0.028, 0.72), true, true)
	rain_close = _particles(Color(0.78, 0.86, 0.96, 0.7), close_n, Vector3(8.0, -62.0, 3.0), Vector2(0.022, 0.95), true, true)
	snow = _particles(Color(0.95, 0.97, 1.0, 0.92), snow_n, Vector3(3.0, -9.0, 1.5), Vector2(0.11, 0.11), false, false)
	dust = _particles(Color(0.82, 0.58, 0.28, 0.55), dust_n, Vector3(22.0, -1.4, 8.0), Vector2(0.22, 0.16), false, false)
	add_child(rain)
	add_child(rain_close)
	add_child(snow)
	add_child(dust)
	_sync_from_menu()
	_apply()


func _particles(col: Color, amount: int, vel: Vector3, size: Vector2, streaks: bool, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.15 if streaks else 2.8
	p.preprocess = 1.0
	p.randomness = 0.55
	p.visibility_aabb = AABB(Vector3(-90, -50, -90), Vector3(180, 110, 180))
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ParticleProcessMaterial.new()
	mat.direction = vel.normalized()
	mat.spread = 9.0 if streaks else 28.0
	mat.initial_velocity_min = vel.length() * 0.75
	mat.initial_velocity_max = vel.length() * 1.35
	mat.gravity = Vector3(0.0, -8.0 if streaks else -2.2, 0.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_shape_scale = Vector3(36.0 if streaks else 28.0, 16.0, 36.0 if streaks else 28.0)
	mat.scale_min = 0.75
	mat.scale_max = 1.45
	mat.color = col
	if streaks:
		mat.particle_flag_align_y = true
	p.process_material = mat
	var draw := QuadMesh.new()
	draw.size = size
	var dm := StandardMaterial3D.new()
	dm.albedo_color = col
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if streaks else BaseMaterial3D.BILLBOARD_ENABLED
	if additive:
		dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw.material = dm
	p.draw_pass_1 = draw
	p.emitting = false
	return p


func _process(delta: float) -> void:
	if player:
		global_position = player.global_position + Vector3(0, 10, 0)
	if world:
		biome = str(world.biome_at(player.global_position if player else Vector3.ZERO).get("biome", "meadow"))
	_sync_from_menu()
	var w: Dictionary = GameState.weather()
	if bool(w.get("lightning", false)) or event == "STORM":
		next_strike -= delta
		if next_strike <= 0.0:
			flash = randf_range(0.16, 0.28)
			next_strike = randf_range(1.1, 3.6)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		if sun:
			sun.light_energy = 5.4 if flash > 0.10 else _sun_energy * 0.55
		if env:
			env.tonemap_exposure = _base_exposure + (0.18 if flash > 0.10 else 0.0)
		if flash <= 0.0 and randf() < 0.55:
			flash = randf_range(0.08, 0.16)
			if sun:
				sun.light_energy = _sun_energy
			if env:
				env.tonemap_exposure = _base_exposure
	GameState.grade_flash = flash
	if event != _applied:
		_apply()
		_applied = event


func _sync_from_menu() -> void:
	var w: Dictionary = GameState.weather()
	event = str(w.get("name", "CLEAR"))
	if biome == "desert" and event == "STORM":
		event = "DUST STORM"
	elif biome == "volcanic" and event == "STORM":
		event = "ASH"
	GameState.weather_grip = float(w.get("grip", 1.0))
	if event == "DUST STORM":
		GameState.weather_grip = minf(GameState.weather_grip, 0.76)
	GameState.set_weather(event)


func _apply() -> void:
	if env == null:
		return
	rain.emitting = event in ["RAIN", "STORM"]
	rain_close.emitting = event == "STORM" or event == "RAIN"
	rain.amount_ratio = 1.0 if event == "STORM" else 0.72
	rain_close.amount_ratio = 1.0 if event == "STORM" else 0.55
	snow.emitting = event == "SNOW"
	dust.emitting = event in ["DUST STORM", "ASH"]
	if rain.emitting:
		rain.restart()
		rain_close.restart()
	if snow.emitting:
		snow.restart()
	if dust.emitting:
		dust.restart()
	var wet := 0.0
	if event == "RAIN":
		wet = 0.85
	elif event == "STORM":
		wet = 1.0
	if world:
		if world.road_mat:
			world.road_mat.set_shader_parameter("wet", wet)
		for m in world.road_mats:
			if m:
				m.set_shader_parameter("wet", wet)
	var sky := Color(0.55, 0.70, 0.90)
	var ground := Color(0.29, 0.50, 0.23)
	if world and not world.theme.is_empty():
		sky = world.theme.get("sky", sky)
		ground = world.theme.get("ground", ground)
	var fog := 0.00115
	var fog_h := 0.0
	var energy := 1.12
	var tint := Color(1.0, 0.96, 0.88)
	var amb := 0.85
	var expos := _base_exposure
	match event:
		"CLEAR":
			fog = 0.00115
			energy = 1.12
		"RAIN":
			sky = sky.lerp(Color(0.28, 0.32, 0.38), 0.72)
			ground = ground.lerp(Color(0.16, 0.18, 0.16), 0.35)
			fog = 0.014
			fog_h = 0.85
			energy = 0.42
			tint = Color(0.72, 0.78, 0.88)
			amb = 0.55
			expos = _base_exposure * 0.90
		"STORM":
			sky = sky.lerp(Color(0.12, 0.13, 0.16), 0.82)
			ground = ground.lerp(Color(0.08, 0.09, 0.10), 0.5)
			fog = 0.026
			fog_h = 1.35
			energy = 0.22
			tint = Color(0.55, 0.62, 0.78)
			amb = 0.38
			expos = _base_exposure * 0.78
		"SNOW":
			sky = sky.lerp(Color(0.78, 0.84, 0.92), 0.62)
			ground = ground.lerp(Color(0.82, 0.86, 0.92), 0.4)
			fog = 0.018
			fog_h = 1.1
			energy = 0.58
			tint = Color(0.82, 0.88, 0.98)
			amb = 0.70
			expos = _base_exposure * 0.94
		"DUST STORM":
			sky = Color(0.72, 0.50, 0.24)
			ground = Color(0.62, 0.44, 0.22)
			fog = 0.032
			fog_h = 1.2
			energy = 0.28
			tint = Color(1.0, 0.72, 0.38)
			amb = 0.48
		"ASH":
			sky = Color(0.32, 0.20, 0.16)
			ground = Color(0.18, 0.10, 0.08)
			fog = 0.024
			fog_h = 1.0
			energy = 0.34
			tint = Color(1.0, 0.48, 0.28)
			amb = 0.42
	env.fog_enabled = true
	env.fog_density = fog
	env.fog_light_color = sky
	env.fog_aerial_perspective = 0.72 if event != "CLEAR" else 0.35
	env.fog_sky_affect = 0.78 if event != "CLEAR" else 0.4
	env.fog_height = 2.0
	env.fog_height_density = fog_h
	env.ambient_light_energy = amb
	env.tonemap_exposure = expos
	if env.glow_enabled:
		env.glow_intensity = 0.09 if event == "STORM" else 0.05
	Mats.paint_sky(env, sky, ground)
	env.fog_enabled = true
	env.fog_density = fog
	env.fog_light_color = sky
	env.fog_aerial_perspective = 0.72 if event != "CLEAR" else 0.35
	env.fog_sky_affect = 0.78 if event != "CLEAR" else 0.4
	env.fog_height = 2.0
	env.fog_height_density = fog_h
	env.ambient_light_energy = amb
	_sun_energy = energy
	if sun and flash <= 0.0:
		sun.light_energy = energy
		sun.light_color = tint
		if event == "STORM":
			sun.rotation_degrees = Vector3(-28, 48, 0)
		elif event == "RAIN":
			sun.rotation_degrees = Vector3(-38, 42, 0)
		else:
			sun.rotation_degrees = Vector3(-52, 38, 0)
