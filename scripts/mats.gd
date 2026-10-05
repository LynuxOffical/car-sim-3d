class_name Mats
extends RefCounted

static var _cache: Dictionary = {}

static func solid(col: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [col, rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m


static func paint_sky(env: Environment, sky_col: Color, ground_col: Color) -> void:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = sky_col.lightened(0.08)
	mat.sky_horizon_color = sky_col.lerp(ground_col, 0.28).lerp(Color(0.78, 0.82, 0.88), 0.25)
	mat.ground_bottom_color = ground_col
	mat.ground_horizon_color = ground_col.lerp(sky_col, 0.45)
	mat.sun_angle_max = 24.0
	mat.sky_curve = 0.11
	mat.ground_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.fog_light_color = sky_col.lerp(ground_col, 0.2)
	env.background_color = sky_col
	env.fog_sky_affect = 0.4
