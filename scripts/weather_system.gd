extends Node3D
class_name WeatherSystem

var env: Environment
var sun: DirectionalLight3D
var rain: GPUParticles3D
var snow: GPUParticles3D
var dust: GPUParticles3D
var event := "CLEAR"
var biome := "meadow"
var player: Node3D
var world: IslandWorld
var flash := 0.0
var next_strike := 4.0
var _applied := ""

func setup(p_env: Environment, p_sun: DirectionalLight3D, p_player: Node3D, p_world: IslandWorld) -> void:
	env = p_env
	sun = p_sun
	player = p_player
	world = p_world
	var q := GameState.quality
	rain = _particles(Color(0.62, 0.7, 0.82, 0.65), 90 if q == 0 else (180 if q == 1 else 280), Vector3(0.15, -34, 0.05), 0.045)
	snow = _particles(Color(0.92, 0.95, 1.0, 0.85), 60 if q == 0 else (120 if q == 1 else 180), Vector3(0, -8, 0), 0.08)
	dust = _particles(Color(0.78, 0.58, 0.28, 0.62), 50 if q == 0 else (90 if q == 1 else 140), Vector3(18, -1.2, 6), 0.16)
	add_child(rain)
	add_child(snow)
	add_child(dust)
	_sync_from_menu()
	_apply()


func _particles(col: Color, amount: int, vel: Vector3, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.5
	p.visibility_aabb = AABB(Vector3(-50, -12, -50), Vector3(100, 50, 100))
	var mat := ParticleProcessMaterial.new()
	mat.direction = vel.normalized()
	mat.initial_velocity_min = vel.length() * 0.8
	mat.initial_velocity_max = vel.length() * 1.2
	mat.gravity = Vector3.ZERO
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(22, 10, 22)
	mat.color = col
	p.process_material = mat
	var draw := QuadMesh.new()
	draw.size = Vector2(size, size * 5.0 if vel.y < -10.0 else size)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = col
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.material = dm
	p.draw_pass_1 = draw
	p.emitting = false
	return p


func _process(delta: float) -> void:
	if player:
		global_position = player.global_position + Vector3(0, 12, 0)
	if world:
		biome = str(world.biome_at(player.global_position if player else Vector3.ZERO).get("biome", "meadow"))
	_sync_from_menu()
	var w: Dictionary = GameState.weather()
	if bool(w.get("lightning", false)):
		next_strike -= delta
		if next_strike <= 0.0:
			flash = 0.22
			next_strike = randf_range(3.0, 8.0)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		if sun:
			sun.light_energy = 3.6 if flash > 0.12 else 0.7
		if flash <= 0.0 and randf() < 0.45 and bool(w.get("lightning", false)):
			flash = 0.18
	GameState.grade_flash = flash
	if event != _applied or flash > 0.0:
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
		GameState.weather_grip = minf(GameState.weather_grip, 0.80)
	GameState.set_weather(event)


func _apply() -> void:
	if env == null:
		return
	rain.emitting = event in ["RAIN", "STORM"]
	snow.emitting = event == "SNOW"
	dust.emitting = event in ["DUST STORM", "ASH"]
	var wet := 1.0 if bool(GameState.weather().get("wet", false)) else 0.0
	if world:
		if world.road_mat:
			world.road_mat.set_shader_parameter("wet", wet)
		for m in world.road_mats:
			if m:
				m.set_shader_parameter("wet", wet)
	var fog := 0.0011
	var albedo := Color(0.55, 0.7, 0.9)
	var energy := float(GameState.weather().get("sun", 1.0)) * 1.12
	var tint := Color(1.0, 0.95, 0.88)
	match event:
		"DUST STORM":
			fog = 0.018
			albedo = Color(0.78, 0.58, 0.28)
			energy = 0.42
			tint = Color(1.0, 0.78, 0.45)
		"SNOW":
			fog = 0.008
			albedo = Color(0.82, 0.88, 0.95)
		"STORM", "RAIN":
			fog = 0.0055 if event == "STORM" else 0.004
			albedo = Color(0.35, 0.4, 0.48)
			energy = 0.55 if event == "STORM" else 0.7
		"ASH":
			fog = 0.012
			albedo = Color(0.4, 0.32, 0.28)
			energy = 0.5
	env.fog_enabled = true
	env.fog_density = fog
	env.fog_light_color = albedo
	Mats.paint_sky(env, albedo, world.theme.get("ground", Color(0.29, 0.50, 0.23)) if world else Color(0.29, 0.50, 0.23))
	if sun and flash <= 0.0:
		sun.light_energy = energy
		sun.light_color = tint
