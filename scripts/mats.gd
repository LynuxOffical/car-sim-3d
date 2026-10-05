class_name Mats
extends RefCounted

const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const ASPHALT_SHADER := preload("res://shaders/asphalt.gdshader")

static var _cache: Dictionary = {}

static func solid(col: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [col, rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if metal <= 0.001 else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache[key] = m
	return m


static func ground(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("albedo", col)
	return m


static func asphalt(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ASPHALT_SHADER
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("roughness", 0.72)
	m.set_shader_parameter("wet", 0.0)
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
