extends Node3D
class_name IslandWorld

const Kit := preload("res://scripts/scenery_kit.gd")

var islands: Array[Dictionary] = []
var spawn_points: Array[Vector3] = []
var spawn_yaws: Array[float] = []
var spawn_yaw := 0.0
var path: Array[Vector3] = []
var island_paths: Array = []
var wps2: Array[Vector2] = []
var dirs2: Array[Vector2] = []
var normals2: Array[Vector2] = []
var half_width := 8.0
var road_mat: ShaderMaterial
var theme: Dictionary = {}
var roam := false
var island_wps: Array = []
var island_dirs_local: Array = []
var island_norms_local: Array = []
var island_half: Array[float] = []
var island_ranges: Array[Vector2i] = []
var city_lanes: Array = []
var road_mats: Array[ShaderMaterial] = []
var open_city := false
var _batch: SurfaceTool

const MAPS := [
	{
		"name": "MEADOW CIRCUIT", "tag": "classic  -  flowing corners", "biome": "meadow", "width": 16.0, "samples": 14,
		"points": [Vector2(0, -85), Vector2(45, -88), Vector2(85, -70), Vector2(100, -30), Vector2(85, 5), Vector2(60, 25), Vector2(55, 55), Vector2(80, 80), Vector2(55, 105), Vector2(10, 95), Vector2(-30, 80), Vector2(-65, 95), Vector2(-100, 75), Vector2(-105, 35), Vector2(-85, 5), Vector2(-100, -35), Vector2(-75, -70), Vector2(-35, -80)],
		"ground": Color(0.29, 0.5, 0.23), "road": Color(0.55, 0.55, 0.58), "sky": Color(0.66, 0.8, 0.95), "stripe_a": Color(0.85, 0.15, 0.15), "stripe_b": Color(0.92, 0.92, 0.92), "scenery": "pine",
	},
	{
		"name": "SUNSET SPEEDWAY", "tag": "desert  -  flat out", "biome": "desert", "width": 18.0, "samples": 18,
		"points": [Vector2(0, -100), Vector2(60, -95), Vector2(110, -60), Vector2(125, 0), Vector2(110, 60), Vector2(60, 95), Vector2(0, 100), Vector2(-60, 95), Vector2(-110, 60), Vector2(-125, 0), Vector2(-110, -60), Vector2(-60, -95)],
		"ground": Color(0.78, 0.68, 0.44), "road": Color(0.6, 0.56, 0.54), "sky": Color(0.96, 0.74, 0.5), "stripe_a": Color(0.8, 0.25, 0.1), "stripe_b": Color(0.95, 0.9, 0.8), "scenery": "desert",
	},
	{
		"name": "ALPINE RUN", "tag": "snow  -  narrow and technical", "biome": "alpine", "width": 14.0, "samples": 14,
		"points": [Vector2(0, -70), Vector2(40, -75), Vector2(70, -50), Vector2(60, -15), Vector2(90, 10), Vector2(85, 50), Vector2(45, 65), Vector2(10, 45), Vector2(-25, 60), Vector2(-30, 95), Vector2(-70, 90), Vector2(-95, 55), Vector2(-75, 20), Vector2(-95, -15), Vector2(-70, -50), Vector2(-30, -45)],
		"ground": Color(0.86, 0.89, 0.93), "road": Color(0.42, 0.42, 0.48), "sky": Color(0.72, 0.78, 0.9), "stripe_a": Color(0.2, 0.35, 0.7), "stripe_b": Color(0.92, 0.92, 0.95), "scenery": "snow_pine",
	},
	{
		"name": "ROCKPORT CITY", "tag": "urban  -  police chase free play", "biome": "city", "width": 20.0, "samples": 12, "city": true,
		"points": [Vector2(0, -110), Vector2(55, -105), Vector2(105, -75), Vector2(115, -20), Vector2(105, 35), Vector2(70, 70), Vector2(25, 85), Vector2(-25, 85), Vector2(-70, 70), Vector2(-105, 35), Vector2(-115, -20), Vector2(-105, -75), Vector2(-55, -105)],
		"ground": Color(0.22, 0.23, 0.26), "road": Color(0.28, 0.28, 0.32), "sky": Color(0.38, 0.4, 0.46), "stripe_a": Color(0.9, 0.9, 0.92), "stripe_b": Color(0.55, 0.55, 0.58), "scenery": "city",
	},
	{
		"name": "HARBOR DISTRICT", "tag": "coastal  -  long straights", "biome": "harbor", "width": 17.0, "samples": 16,
		"points": [Vector2(0, -95), Vector2(70, -90), Vector2(120, -45), Vector2(115, 15), Vector2(80, 55), Vector2(30, 75), Vector2(-30, 70), Vector2(-80, 45), Vector2(-120, 0), Vector2(-115, -55), Vector2(-75, -90), Vector2(-20, -95)],
		"ground": Color(0.35, 0.42, 0.38), "road": Color(0.38, 0.38, 0.42), "sky": Color(0.55, 0.68, 0.82), "stripe_a": Color(0.85, 0.75, 0.2), "stripe_b": Color(0.9, 0.9, 0.92), "scenery": "pine",
	},
	{
		"name": "CANYON PASS", "tag": "mountain  -  tight hairpins", "biome": "canyon", "width": 15.0, "samples": 14,
		"points": [Vector2(0, -80), Vector2(35, -85), Vector2(75, -60), Vector2(90, -10), Vector2(75, 35), Vector2(40, 70), Vector2(0, 85), Vector2(-45, 75), Vector2(-80, 40), Vector2(-95, -5), Vector2(-80, -55), Vector2(-40, -78)],
		"ground": Color(0.48, 0.44, 0.36), "road": Color(0.4, 0.38, 0.36), "sky": Color(0.62, 0.7, 0.82), "stripe_a": Color(0.78, 0.55, 0.18), "stripe_b": Color(0.88, 0.88, 0.9), "scenery": "desert",
	},
	{
		"name": "MIDNIGHT METRO", "tag": "night city  -  max bounty zone", "biome": "city", "width": 19.0, "samples": 14, "city": true,
		"points": [Vector2(0, -100), Vector2(50, -95), Vector2(95, -60), Vector2(100, 0), Vector2(85, 55), Vector2(45, 90), Vector2(0, 100), Vector2(-45, 90), Vector2(-85, 55), Vector2(-100, 0), Vector2(-95, -60), Vector2(-50, -95)],
		"ground": Color(0.12, 0.13, 0.16), "road": Color(0.2, 0.2, 0.24), "sky": Color(0.08, 0.09, 0.14), "stripe_a": Color(0.95, 0.85, 0.25), "stripe_b": Color(0.35, 0.35, 0.4), "scenery": "city",
	},
	{
		"name": "PALM COAST", "tag": "tropical  -  sea breeze", "biome": "tropical", "width": 16.0, "samples": 10,
		"points": [Vector2(0, -90), Vector2(55, -85), Vector2(100, -45), Vector2(110, 10), Vector2(80, 55), Vector2(25, 80), Vector2(-30, 85), Vector2(-80, 50), Vector2(-110, 5), Vector2(-95, -50), Vector2(-50, -85)],
		"ground": Color(0.18, 0.52, 0.32), "road": Color(0.42, 0.4, 0.36), "sky": Color(0.35, 0.72, 0.88), "stripe_a": Color(0.95, 0.55, 0.15), "stripe_b": Color(0.95, 0.95, 0.9), "scenery": "palm",
	},
	{
		"name": "FOUNDRY LOOP", "tag": "industrial  -  smokestacks", "biome": "industrial", "width": 18.0, "samples": 8,
		"points": [Vector2(0, -88), Vector2(48, -92), Vector2(95, -50), Vector2(100, 5), Vector2(70, 55), Vector2(15, 85), Vector2(-40, 80), Vector2(-90, 40), Vector2(-100, -15), Vector2(-70, -70), Vector2(-20, -88)],
		"ground": Color(0.28, 0.26, 0.22), "road": Color(0.24, 0.24, 0.26), "sky": Color(0.42, 0.4, 0.36), "stripe_a": Color(0.95, 0.55, 0.1), "stripe_b": Color(0.2, 0.2, 0.22), "scenery": "factory",
	},
	{
		"name": "VOLCANO RIDGE", "tag": "volcanic  -  ash and heat", "biome": "volcanic", "width": 15.0, "samples": 10,
		"points": [Vector2(0, -78), Vector2(40, -82), Vector2(78, -48), Vector2(88, 0), Vector2(70, 48), Vector2(25, 78), Vector2(-30, 82), Vector2(-75, 45), Vector2(-88, -5), Vector2(-70, -52), Vector2(-28, -78)],
		"ground": Color(0.22, 0.12, 0.1), "road": Color(0.18, 0.16, 0.16), "sky": Color(0.45, 0.22, 0.16), "stripe_a": Color(0.95, 0.25, 0.08), "stripe_b": Color(0.35, 0.12, 0.08), "scenery": "lava",
	},
	{
		"name": "SALT FLATS", "tag": "desert  -  wide open", "biome": "desert", "width": 22.0, "samples": 8,
		"points": [Vector2(0, -120), Vector2(70, -110), Vector2(130, -50), Vector2(135, 20), Vector2(90, 80), Vector2(20, 115), Vector2(-60, 105), Vector2(-120, 50), Vector2(-135, -20), Vector2(-100, -85), Vector2(-40, -118)],
		"ground": Color(0.86, 0.82, 0.7), "road": Color(0.55, 0.52, 0.48), "sky": Color(0.9, 0.82, 0.62), "stripe_a": Color(0.2, 0.2, 0.22), "stripe_b": Color(0.95, 0.92, 0.85), "scenery": "desert",
	},
	{
		"name": "SWITCHBACK RIDGE", "tag": "forest  -  tight esses and hairpins", "biome": "meadow", "width": 13.5, "samples": 16,
		"points": [Vector2(0, -92), Vector2(28, -98), Vector2(62, -72), Vector2(48, -28), Vector2(82, -4), Vector2(58, 32), Vector2(92, 62), Vector2(48, 88), Vector2(8, 72), Vector2(-28, 96), Vector2(-68, 68), Vector2(-42, 28), Vector2(-92, 2), Vector2(-58, -38), Vector2(-88, -74), Vector2(-32, -90)],
		"ground": Color(0.18, 0.32, 0.16), "road": Color(0.36, 0.35, 0.34), "sky": Color(0.52, 0.68, 0.78), "stripe_a": Color(0.75, 0.55, 0.12), "stripe_b": Color(0.88, 0.88, 0.86), "scenery": "pine",
	},
	{
		"name": "LAGOON STRAITS", "tag": "tropical  -  wide sweep around the bay", "biome": "tropical", "width": 19.0, "samples": 12,
		"points": [Vector2(0, -118), Vector2(58, -112), Vector2(108, -78), Vector2(128, -18), Vector2(118, 42), Vector2(78, 88), Vector2(22, 112), Vector2(-42, 108), Vector2(-96, 72), Vector2(-124, 12), Vector2(-112, -52), Vector2(-72, -98), Vector2(-22, -116)],
		"ground": Color(0.16, 0.48, 0.38), "road": Color(0.40, 0.38, 0.34), "sky": Color(0.32, 0.70, 0.86), "stripe_a": Color(0.12, 0.62, 0.58), "stripe_b": Color(0.95, 0.94, 0.88), "scenery": "palm",
	},
]

const DEFS := MAPS


func build(only_index: int = -1, p_roam: bool = false) -> void:
	roam = p_roam
	islands.clear()
	spawn_points.clear()
	spawn_yaws.clear()
	path.clear()
	island_paths.clear()
	wps2.clear()
	dirs2.clear()
	normals2.clear()
	island_wps.clear()
	island_dirs_local.clear()
	island_norms_local.clear()
	island_half.clear()
	island_ranges.clear()
	city_lanes.clear()
	road_mats.clear()
	open_city = false
	if roam:
		expand_chain()
		return
	var idx := only_index
	if idx < 0:
		idx = 0
	idx = clampi(idx, 0, MAPS.size() - 1)
	_build_one(idx, Vector3.ZERO)
	theme = MAPS[idx]
	half_width = float(theme["width"]) * 0.5


func expand_chain() -> void:
	var n := MAPS.size()
	var radius := 420.0 + float(n) * 85.0
	var origins: Array[Vector3] = []
	for i in n:
		var ang := TAU * float(i) / float(n) - PI * 0.5
		origins.append(Vector3(cos(ang) * radius, 0.0, sin(ang) * radius))
	_ocean_ground(Color(0.16, 0.28, 0.34), radius * 2.8 + 500.0, -0.45)
	for i in n:
		_build_one(i, origins[i])
	theme = MAPS[3]
	half_width = float(theme["width"]) * 0.5
	_begin_batch()
	for i in n:
		_bridge(origins[i], origins[(i + 1) % n])
	_end_batch(false)
	if not spawn_points.is_empty():
		spawn_yaw = spawn_yaws[clampi(3, 0, spawn_yaws.size() - 1)]


func biome_at(world_pos: Vector3) -> Dictionary:
	if islands.is_empty():
		return MAPS[3]
	var best := 0
	var best_d := INF
	for i in islands.size():
		var d: float = Vector2(world_pos.x, world_pos.z).distance_to(Vector2(islands[i]["pos"].x, islands[i]["pos"].z))
		if d < best_d:
			best_d = d
			best = i
	return islands[best]


func spawn_for(index: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 0.6, 0)
	var i := clampi(index, 0, spawn_points.size() - 1)
	if roam:
		i = 0 if GameState.race_island < 0 else GameState.race_island
		i = clampi(i, 0, spawn_points.size() - 1)
	if i < spawn_yaws.size():
		spawn_yaw = spawn_yaws[i]
	return spawn_points[i]


func nearest_island(pos: Vector3) -> int:
	if islands.is_empty():
		return 0
	var best := 0
	var best_d := INF
	for i in islands.size():
		var ip: Vector3 = islands[i]["pos"]
		var d: float = Vector2(pos.x - ip.x, pos.z - ip.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func nearest_index(pos: Vector3, hint: int = -1) -> int:
	var n := wps2.size()
	if n == 0:
		return 0
	var start := 0
	var count := n
	if roam and not island_ranges.is_empty():
		var ii := nearest_island(pos)
		var rg: Vector2i = island_ranges[clampi(ii, 0, island_ranges.size() - 1)]
		start = rg.x
		count = rg.y
	var best := hint if hint >= 0 else start
	var best_d := INF
	if hint >= start and hint < start + count:
		for k in range(-8, 24):
			var i: int = start + posmod(hint - start + k, count)
			var d: float = pos.distance_squared_to(Vector3(wps2[i].x, pos.y, wps2[i].y))
			if d < best_d:
				best_d = d
				best = i
		return best
	for i in range(start, start + count):
		var d2: float = pos.distance_squared_to(Vector3(wps2[i].x, pos.y, wps2[i].y))
		if d2 < best_d:
			best_d = d2
			best = i
	return best


func heading_at(i: int) -> float:
	if dirs2.is_empty():
		return 0.0
	var d: Vector2 = dirs2[wrapi(i, 0, dirs2.size())]
	return atan2(-d.x, -d.y)


func clamp_arcade(car: ArcadeCar) -> void:
	if wps2.is_empty() or dirs2.is_empty():
		return
	var hw := half_width
	var i := car.wp_idx
	if roam and not island_ranges.is_empty():
		var ii := nearest_island(car.global_position)
		ii = clampi(ii, 0, island_ranges.size() - 1)
		var rg: Vector2i = island_ranges[ii]
		if i < rg.x or i >= rg.x + rg.y:
			i = nearest_index(car.global_position, rg.x)
		hw = island_half[ii] if ii < island_half.size() else hw
	i = clampi(i, 0, wps2.size() - 1)
	var wp: Vector2 = wps2[i]
	if roam:
		var away := Vector2(car.global_position.x, car.global_position.z).distance_to(wp)
		if away > hw + 28.0:
			return
	var d: Vector2 = dirs2[i]
	var nrm: Vector2 = normals2[i] if i < normals2.size() else Vector2(-d.y, d.x)
	var rx := car.global_position.x - wp.x
	var rz := car.global_position.z - wp.y
	var lat := rx * nrm.x + rz * nrm.y
	var lon := rx * d.x + rz * d.y
	var max_lat := hw - 1.1
	if absf(lat) > max_lat:
		lat = max_lat if lat > 0.0 else -max_lat
		car.global_position.x = wp.x + d.x * lon + nrm.x * lat
		car.global_position.z = wp.y + d.y * lon + nrm.y * lat
		car.speed *= 0.97


func is_city(pos: Vector3) -> bool:
	return bool(biome_at(pos).get("city", false)) or str(biome_at(pos).get("biome", "")) == "city"


func track_center() -> Vector3:
	if wps2.is_empty():
		return Vector3.ZERO
	var s := Vector2.ZERO
	for p in wps2:
		s += p
	s /= float(wps2.size())
	return Vector3(s.x, 0.0, s.y)


func track_span() -> float:
	if wps2.is_empty():
		return 200.0
	var minp := wps2[0]
	var maxp := wps2[0]
	for p in wps2:
		minp.x = minf(minp.x, p.x)
		minp.y = minf(minp.y, p.y)
		maxp.x = maxf(maxp.x, p.x)
		maxp.y = maxf(maxp.y, p.y)
	return maxf(40.0, maxf(maxp.x - minp.x, maxp.y - minp.y))


func _build_one(idx: int, origin: Vector3) -> void:
	var spec: Dictionary = MAPS[idx]
	if theme.is_empty():
		theme = spec
	half_width = float(spec["width"]) * 0.5
	var pts: Array = spec["points"]
	var samples: int = int(spec["samples"])
	var wps: Array[Vector2] = _catmull(pts, samples)
	var dirs: Array[Vector2] = []
	var norms: Array[Vector2] = []
	var local_path: Array[Vector3] = []
	var start := wps2.size()
	var local_wps2: Array[Vector2] = []
	for i in wps.size():
		var a: Vector2 = wps[i]
		var b: Vector2 = wps[(i + 1) % wps.size()]
		var d: Vector2 = (b - a)
		if d.length() < 0.001:
			d = Vector2(0, 1)
		d = d.normalized()
		dirs.append(d)
		norms.append(Vector2(-d.y, d.x))
		var wp := Vector3(a.x, 0.5, a.y) + origin
		path.append(wp)
		local_path.append(wp)
		var wp2 := Vector2(wp.x, wp.z)
		wps2.append(wp2)
		local_wps2.append(wp2)
	island_paths.append(local_path)
	island_wps.append(local_wps2)
	island_dirs_local.append(dirs)
	island_norms_local.append(norms)
	island_half.append(half_width)
	island_ranges.append(Vector2i(start, wps.size()))
	dirs2.append_array(dirs)
	normals2.append_array(norms)
	var d0: Vector2 = dirs[0]
	var yaw := atan2(-d0.x, -d0.y)
	spawn_yaws.append(yaw)
	if spawn_points.is_empty():
		spawn_yaw = yaw
	spawn_points.append(Vector3(wps[0].x, 0.18, wps[0].y) + origin)
	var isle := spec.duplicate()
	isle["pos"] = origin
	islands.append(isle)
	_ground_from_wps(wps, origin, spec["ground"])
	_road(wps, dirs, norms, origin, spec)
	_begin_batch()
	_curbs(wps, norms, origin, spec)
	_walls(wps, norms, origin, spec)
	_center_line(wps, dirs, norms, origin)
	_start_line(wps, dirs, norms, origin)
	_gantry_stand(wps, dirs, norms, origin, spec)
	_end_batch(false)
	_scenery(wps, origin, spec)


func _ocean_ground(col: Color, size: float, y: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mi.mesh = plane
	mi.position.y = y
	mi.material_override = Mats.solid(col, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func _ground_from_wps(wps: Array[Vector2], origin: Vector3, col: Color) -> void:
	var minp := wps[0]
	var maxp := wps[0]
	for p in wps:
		minp.x = minf(minp.x, p.x)
		minp.y = minf(minp.y, p.y)
		maxp.x = maxf(maxp.x, p.x)
		maxp.y = maxf(maxp.y, p.y)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(maxp.x - minp.x + 900.0, maxp.y - minp.y + 900.0)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mi.mesh = plane
	mi.position = origin + Vector3((minp.x + maxp.x) * 0.5, -0.05, (minp.y + maxp.y) * 0.5)
	mi.material_override = Mats.ground(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func _catmull(points: Array, samples: int) -> Array[Vector2]:
	var n := points.size()
	var out: Array[Vector2] = []
	for i in n:
		var p0: Vector2 = points[(i - 1 + n) % n]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		var p3: Vector2 = points[(i + 2) % n]
		for s in samples:
			var t := float(s) / float(samples)
			var t2 := t * t
			var t3 := t2 * t
			var x := 0.5 * ((2.0 * p1.x) + (-p0.x + p2.x) * t + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3)
			var y := 0.5 * ((2.0 * p1.y) + (-p0.y + p2.y) * t + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3)
			out.append(Vector2(x, y))
	return out


func _road(wps: Array[Vector2], _dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := half_width
	var n := wps.size()
	var oy := origin.y + 0.06
	var o := Vector3(origin.x, 0, origin.z)
	var vdist := 0.0
	for i in n:
		var j := (i + 1) % n
		var a: Vector2 = wps[i]
		var b: Vector2 = wps[j]
		var na: Vector2 = norms[i]
		var nb: Vector2 = norms[j]
		var seg := maxf(0.001, a.distance_to(b))
		var v0 := vdist / 7.0
		var v1 := (vdist + seg) / 7.0
		var left_a := Vector3(a.x + na.x * hw, oy, a.y + na.y * hw) + o
		var right_a := Vector3(a.x - na.x * hw, oy, a.y - na.y * hw) + o
		var right_b := Vector3(b.x - nb.x * hw, oy, b.y - nb.y * hw) + o
		var left_b := Vector3(b.x + nb.x * hw, oy, b.y + nb.y * hw) + o
		_tri_uv(st, right_a, left_a, left_b, Vector2(1, v0), Vector2(0, v0), Vector2(0, v1))
		_tri_uv(st, right_a, left_b, right_b, Vector2(1, v0), Vector2(0, v1), Vector2(1, v1))
		vdist += seg
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := Mats.asphalt(spec["road"])
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if road_mat == null:
		road_mat = mat
	road_mats.append(mat)
	add_child(mi)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color = Color.WHITE) -> void:
	st.set_color(col)
	st.set_uv(Vector2(a.x * 0.12, a.z * 0.12))
	st.add_vertex(a)
	st.set_color(col)
	st.set_uv(Vector2(b.x * 0.12, b.z * 0.12))
	st.add_vertex(b)
	st.set_color(col)
	st.set_uv(Vector2(c.x * 0.12, c.z * 0.12))
	st.add_vertex(c)


func _tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)


func _deco_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(_batch, a, b, c, col)
	_tri(_batch, a, c, d, col)


func _curbs(wps: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var hw := half_width
	var sa: Color = spec["stripe_a"]
	var sb: Color = spec["stripe_b"]
	var o := Vector3(origin.x, 0, origin.z)
	var n := wps.size()
	for side in [1.0, -1.0]:
		for i in n:
			var j := (i + 1) % n
			var colr: Color = sa if (i / 3) % 2 == 0 else sb
			var a: Vector2 = wps[i]
			var b: Vector2 = wps[j]
			var na: Vector2 = norms[i] * side
			var nb: Vector2 = norms[j] * side
			_deco_quad(
				Vector3(a.x + na.x * (hw - 1.3), 0.08, a.y + na.y * (hw - 1.3)) + o,
				Vector3(a.x + na.x * hw, 0.08, a.y + na.y * hw) + o,
				Vector3(b.x + nb.x * hw, 0.08, b.y + nb.y * hw) + o,
				Vector3(b.x + nb.x * (hw - 1.3), 0.08, b.y + nb.y * (hw - 1.3)) + o,
				colr
			)


func _walls(wps: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var hw := half_width
	var h := 1.1
	var inner := hw + 0.9
	var outer := hw + 1.7
	var sa: Color = spec["stripe_a"]
	var sb: Color = spec["stripe_b"]
	var o := Vector3(origin.x, 0, origin.z)
	var n := wps.size()
	for side in [1.0, -1.0]:
		for i in n:
			var j := (i + 1) % n
			var colr: Color = sa if (i / 4) % 2 == 0 else sb
			var a: Vector2 = wps[i]
			var b: Vector2 = wps[j]
			var na: Vector2 = norms[i] * side
			var nb: Vector2 = norms[j] * side
			var ain := Vector3(a.x + na.x * inner, 0, a.y + na.y * inner) + o
			var bin := Vector3(b.x + nb.x * inner, 0, b.y + nb.y * inner) + o
			var aout := Vector3(a.x + na.x * outer, 0, a.y + na.y * outer) + o
			var bout := Vector3(b.x + nb.x * outer, 0, b.y + nb.y * outer) + o
			_deco_quad(ain, bin, bin + Vector3(0, h, 0), ain + Vector3(0, h, 0), colr)
			_deco_quad(aout, aout + Vector3(0, h, 0), bout + Vector3(0, h, 0), bout, colr)
			_deco_quad(ain + Vector3(0, h, 0), bin + Vector3(0, h, 0), bout + Vector3(0, h, 0), aout + Vector3(0, h, 0), colr)


func _center_line(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3) -> void:
	var o := Vector3(origin.x, 0, origin.z)
	var col := Color(0.92, 0.92, 0.92)
	for i in range(0, wps.size(), 6):
		var p: Vector2 = wps[i]
		var d: Vector2 = dirs[i]
		var nrm: Vector2 = norms[i]
		_deco_quad(
			Vector3(p.x - nrm.x * 0.18, 0.09, p.y - nrm.y * 0.18) + o,
			Vector3(p.x + nrm.x * 0.18, 0.09, p.y + nrm.y * 0.18) + o,
			Vector3(p.x + nrm.x * 0.18 + d.x * 2.2, 0.09, p.y + nrm.y * 0.18 + d.y * 2.2) + o,
			Vector3(p.x - nrm.x * 0.18 + d.x * 2.2, 0.09, p.y - nrm.y * 0.18 + d.y * 2.2) + o,
			col
		)


func _start_line(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3) -> void:
	var wx: Vector2 = wps[0]
	var d: Vector2 = dirs[0]
	var nrm: Vector2 = norms[0]
	var o := Vector3(origin.x, 0, origin.z)
	var cols := 8
	var cw := (half_width - 1.3) * 2.0 / float(cols)
	for row in 2:
		for col in cols:
			var shade := 0.95 if (row + col) % 2 == 0 else 0.05
			var l0 := -(half_width - 1.3) + float(col) * cw
			var f0 := float(row) * 1.1
			var pts: Array[Vector3] = []
			for pair in [Vector2(l0, f0), Vector2(l0 + cw, f0), Vector2(l0 + cw, f0 + 1.1), Vector2(l0, f0 + 1.1)]:
				pts.append(Vector3(wx.x + nrm.x * pair.x + d.x * pair.y, 0.10, wx.y + nrm.y * pair.x + d.y * pair.y) + o)
			_deco_quad(pts[0], pts[1], pts[2], pts[3], Color(shade, shade, shade))


func _tw(wx: Vector2, d: Vector2, nrm: Vector2, origin: Vector3, lx: float, ly: float, lz: float) -> Vector3:
	return Vector3(wx.x + nrm.x * lx + d.x * ly, lz, wx.y + nrm.y * lx + d.y * ly) + Vector3(origin.x, 0, origin.z)


func _gantry_stand(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var wx: Vector2 = wps[0]
	var d: Vector2 = dirs[0]
	var nrm: Vector2 = norms[0]
	var span := half_width + 2.2
	var beam: Color = spec["stripe_a"]
	for sx in [-span, span]:
		_vis_box(_tw(wx, d, nrm, origin, sx, 0.0, 3.1), Vector3(0.45, 6.2, 0.45), Color(0.25, 0.25, 0.28), atan2(d.x, d.y))
	_vis_box(_tw(wx, d, nrm, origin, 0.0, 0.0, 6.55), Vector3(span * 2.0 + 0.45, 0.75, 0.75), beam, atan2(d.x, d.y))
	var off := half_width + 6.0
	var seats: Array[Color] = [
		Color(0.75, 0.15, 0.15), Color(0.15, 0.35, 0.75), Color(0.85, 0.70, 0.15),
		Color(0.20, 0.55, 0.25), Color(0.60, 0.60, 0.65),
	]
	var yaw := atan2(d.x, d.y)
	_vis_box(_tw(wx, d, nrm, origin, off + 2.9, 0.0, 0.35), Vector3(6.6, 0.7, 26.0), Color(0.35, 0.35, 0.38), yaw)
	for i in seats.size():
		_vis_box(_tw(wx, d, nrm, origin, off + 0.9 + float(i) * 1.05, 0.0, 0.78 + float(i) * 0.52), Vector3(1.05, 0.55, 26.0), seats[i], yaw)
	_vis_box(_tw(wx, d, nrm, origin, off + 6.1, 0.0, 2.3), Vector3(0.4, 4.6, 26.0), Color(0.30, 0.30, 0.33), yaw)
	for sy in [-12.5, 12.5]:
		for sx in [off + 0.7, off + 5.7]:
			_vis_box(_tw(wx, d, nrm, origin, sx, sy, 2.4), Vector3(0.30, 4.8, 0.30), Color(0.22, 0.22, 0.25), yaw)
	_vis_box(_tw(wx, d, nrm, origin, off + 3.2, 0.0, 4.85), Vector3(7.2, 0.28, 27.0), spec["stripe_a"], yaw)


func _bridge(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var dist := dir.length()
	if dist < 40.0:
		return
	var yaw := atan2(dir.x, dir.z)
	var mid := (a + b) * 0.5
	var span := maxf(60.0, dist - 310.0)
	_vis_box(mid + Vector3(0, 0.12, 0), Vector3(16.0, 0.42, span), Color(0.32, 0.3, 0.28), yaw)
	_vis_box(mid + Vector3(0, 1.05, 0) + Vector3(cos(yaw + PI * 0.5), 0, sin(yaw + PI * 0.5)) * 7.4, Vector3(0.35, 1.2, span), Color(0.75, 0.55, 0.12), yaw)
	_vis_box(mid + Vector3(0, 1.05, 0) - Vector3(cos(yaw + PI * 0.5), 0, sin(yaw + PI * 0.5)) * 7.4, Vector3(0.35, 1.2, span), Color(0.75, 0.55, 0.12), yaw)
	for t in [0.22, 0.5, 0.78]:
		var p := a.lerp(b, t)
		_vis_box(p + Vector3(0, 4.5, 0), Vector3(1.2, 9.0, 1.2), Color(0.42, 0.44, 0.48), yaw)
		_vis_box(p + Vector3(0, 9.2, 0), Vector3(16.0, 0.35, 0.8), Color(0.55, 0.56, 0.6), yaw)


func _scenery(wps: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = str(spec["name"]).hash()
	var kind: String = str(spec.get("scenery", "pine"))
	var shadows := GameState.quality > 0
	match kind:
		"city":
			_city_blocks(wps, origin, rng, shadows, false)
		"factory":
			_city_blocks(wps, origin, rng, shadows, true)
		"desert":
			_nature_belt(wps, origin, rng, Kit.CACTUS, 10.0, 16.0, shadows, true)
			_fill_scatter(wps, origin, rng, Kit.ROCKS, 8.0, 14.0, shadows, true, 28)
		"palm":
			_nature_belt(wps, origin, rng, Kit.PALMS, 11.0, 16.0, shadows, true)
		"lava":
			_nature_belt(wps, origin, rng, Kit.ROCKS, 10.0, 18.0, shadows, true)
			_fill_scatter(wps, origin, rng, Kit.ROCKS, 9.0, 16.0, shadows, true, 22)
		"snow_pine":
			_nature_belt(wps, origin, rng, Kit.SNOW_PINES, 11.0, 16.0, shadows, true)
			_fill_scatter(wps, origin, rng, Kit.SNOW_PINES, 10.0, 15.0, shadows, true, 36)
		_:
			_nature_belt(wps, origin, rng, Kit.PINES, 11.0, 16.0, shadows, true)
			_fill_scatter(wps, origin, rng, Kit.PINES, 10.0, 15.0, shadows, true, 40)
			_fill_scatter(wps, origin, rng, Kit.BUSHES, 7.0, 11.0, shadows, true, 16)


func _bbox(wps: Array[Vector2]) -> Rect2:
	var minp := wps[0]
	var maxp := wps[0]
	for p in wps:
		minp.x = minf(minp.x, p.x)
		minp.y = minf(minp.y, p.y)
		maxp.x = maxf(maxp.x, p.x)
		maxp.y = maxf(maxp.y, p.y)
	return Rect2(minp, maxp - minp)


func _near_track(p: Vector2, wps: Array[Vector2], clear: float) -> bool:
	var c2 := clear * clear
	var step := 2 if wps.size() > 90 else 1
	for i in range(0, wps.size(), step):
		if p.distance_squared_to(wps[i]) < c2:
			return true
	return false


func _inside_loop(p: Vector2, wps: Array[Vector2]) -> bool:
	var inside := false
	var n := wps.size()
	var j := n - 1
	for i in n:
		var a: Vector2 = wps[i]
		var b: Vector2 = wps[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / ((b.y - a.y) if absf(b.y - a.y) > 0.0001 else 0.0001) + a.x):
			inside = not inside
		j = i
	return inside


func _norm_at(wps: Array[Vector2], i: int) -> Vector2:
	var n := wps.size()
	var d: Vector2 = wps[(i + 1) % n] - wps[i]
	if d.length() < 0.001:
		d = Vector2(0, 1)
	d = d.normalized()
	return Vector2(-d.y, d.x)


func _city_blocks(wps: Array[Vector2], origin: Vector3, rng: RandomNumberGenerator, shadows: bool, factory: bool) -> void:
	var o := Vector3(origin.x, 0, origin.z)
	var step := 4 if GameState.quality >= 2 else (5 if GameState.quality == 1 else 7)
	if roam:
		step += 3
	for i in range(0, wps.size(), step):
		var nrm := _norm_at(wps, i)
		var d: Vector2 = wps[(i + 1) % wps.size()] - wps[i]
		var yaw := atan2(d.x, d.y)
		for side in [-1.0, 1.0]:
			var dist := half_width + rng.randf_range(14.0, 26.0)
			var p: Vector2 = wps[i] + nrm * side * dist
			var pos := Vector3(p.x, 0.0, p.y) + o
			var face := yaw + (PI if side > 0.0 else 0.0)
			if factory:
				Kit.spawn_fitted(self, Kit.pick(Kit.CITY, rng), pos, face, rng.randf_range(16.0, 28.0), 18.0, shadows)
			elif rng.randf() < 0.58:
				Kit.spawn_fitted(self, Kit.pick(Kit.CITY, rng), pos, face, rng.randf_range(14.0, 32.0), 16.0, shadows)
			else:
				Kit.spawn_fitted(self, Kit.pick(Kit.TOWERS, rng), pos, face, rng.randf_range(36.0, 72.0), 18.0, shadows)
			if GameState.quality > 0 and rng.randf() < 0.12:
				_street_lamp(Vector3(wps[i].x + nrm.x * side * (half_width + 3.4), 0.0, wps[i].y + nrm.y * side * (half_width + 3.4)) + o)
	var extra := 12 if GameState.quality >= 2 else (7 if GameState.quality == 1 else 4)
	if roam:
		extra = maxi(4, int(float(extra) * 0.4))
	var planted := 0
	var guard := 0
	var box := _bbox(wps)
	while planted < extra and guard < extra * 16:
		guard += 1
		var x := rng.randf_range(box.position.x - 80.0, box.position.x + box.size.x + 80.0)
		var z := rng.randf_range(box.position.y - 80.0, box.position.y + box.size.y + 80.0)
		if _near_track(Vector2(x, z), wps, half_width + 12.0):
			continue
		var pos2 := Vector3(x, 0.0, z) + o
		if factory:
			Kit.spawn_fitted(self, Kit.pick(Kit.CITY, rng), pos2, rng.randf() * TAU, rng.randf_range(14.0, 24.0), 16.0, shadows)
		elif rng.randf() < 0.4:
			Kit.spawn_fitted(self, Kit.pick(Kit.TOWERS, rng), pos2, rng.randf() * TAU, rng.randf_range(40.0, 80.0), 20.0, shadows)
		else:
			Kit.spawn_fitted(self, Kit.pick(Kit.CITY, rng), pos2, rng.randf() * TAU, rng.randf_range(12.0, 28.0), 16.0, shadows)
		planted += 1


func _street_lamp(pos: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.12
	cyl.height = 5.4
	pole.mesh = cyl
	pole.position = pos + Vector3(0, 2.7, 0)
	pole.material_override = Mats.solid(Color(0.18, 0.18, 0.2), 0.4, 0.45)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(pole)
	var bulb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.14
	sph.height = 0.28
	sph.radial_segments = 8
	sph.rings = 4
	bulb.mesh = sph
	bulb.position = pos + Vector3(0, 5.3, 0)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.0, 0.94, 0.78)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.92, 0.7)
	em.emission_energy_multiplier = 2.2
	bulb.material_override = em
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(bulb)


func _nature_belt(wps: Array[Vector2], origin: Vector3, rng: RandomNumberGenerator, kit: Array[String], smin: float, smax: float, shadows: bool, vcol: bool) -> void:
	var o := Vector3(origin.x, 0, origin.z)
	var step := 4 if GameState.quality >= 2 else 6
	if roam:
		step += 3
	for i in range(0, wps.size(), step):
		var nrm := _norm_at(wps, i)
		for side in [-1.0, 1.0]:
			var dist := half_width + rng.randf_range(10.0, 34.0)
			var p: Vector2 = wps[i] + nrm * side * dist
			var yaw := rng.randf() * TAU
			Kit.spawn(self, Kit.pick(kit, rng), Vector3(p.x, 0, p.y) + o, yaw, rng.randf_range(smin, smax), shadows, vcol)


func _fill_scatter(wps: Array[Vector2], origin: Vector3, rng: RandomNumberGenerator, kit: Array[String], smin: float, smax: float, shadows: bool, vcol: bool, count: int) -> void:
	var box := _bbox(wps)
	var pad := 70.0
	var o := Vector3(origin.x, 0, origin.z)
	var planted := 0
	var guard := 0
	var want := count
	if GameState.quality == 1:
		want = maxi(8, int(count * 0.5))
	elif GameState.quality == 0:
		want = maxi(6, int(count * 0.33))
	if roam:
		want = maxi(8, int(want * 0.5))
	while planted < want and guard < want * 12:
		guard += 1
		var x := rng.randf_range(box.position.x - pad, box.position.x + box.size.x + pad)
		var z := rng.randf_range(box.position.y - pad, box.position.y + box.size.y + pad)
		if _near_track(Vector2(x, z), wps, half_width + 14.0):
			continue
		Kit.spawn(self, Kit.pick(kit, rng), Vector3(x, 0, z) + o, rng.randf() * TAU, rng.randf_range(smin, smax), shadows, vcol)
		planted += 1


func _tree(p: Vector3, snow: bool) -> void:
	_vis_box(p + Vector3(0, 1.1, 0), Vector3(0.6, 2.2, 0.6), Color(0.42, 0.28, 0.14))
	if snow:
		_vis_box(p + Vector3(0, 2.6, 0), Vector3(3.2, 1.6, 3.2), Color(0.22, 0.38, 0.30))
		_vis_box(p + Vector3(0, 3.8, 0), Vector3(2.4, 1.4, 2.4), Color(0.45, 0.58, 0.52))
		_vis_box(p + Vector3(0, 4.9, 0), Vector3(1.4, 1.2, 1.4), Color(0.85, 0.90, 0.92))
	else:
		_vis_box(p + Vector3(0, 2.6, 0), Vector3(3.2, 1.6, 3.2), Color(0.10, 0.38, 0.12))
		_vis_box(p + Vector3(0, 3.8, 0), Vector3(2.4, 1.4, 2.4), Color(0.12, 0.44, 0.14))
		_vis_box(p + Vector3(0, 4.9, 0), Vector3(1.4, 1.2, 1.4), Color(0.15, 0.50, 0.17))


func _begin_batch() -> void:
	_batch = SurfaceTool.new()
	_batch.begin(Mesh.PRIMITIVE_TRIANGLES)


func _end_batch(_shadows: bool) -> void:
	if _batch == null:
		return
	_batch.generate_normals()
	var mesh := _batch.commit()
	_batch = null
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func _vis_box(pos: Vector3, size: Vector3, col: Color, yaw: float = 0.0) -> void:
	if _batch == null:
		return
	var b := Basis.from_euler(Vector3(0, yaw, 0))
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c: Array[Vector3] = []
	for o in [
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
	]:
		c.append(pos + b * o)
	_batch_quad(c[0], c[1], c[2], c[3], col)
	_batch_quad(c[5], c[4], c[7], c[6], col)
	_batch_quad(c[4], c[0], c[3], c[7], col)
	_batch_quad(c[1], c[5], c[6], c[2], col)
	_batch_quad(c[3], c[2], c[6], c[7], col)
	_batch_quad(c[4], c[5], c[1], c[0], col)


func _batch_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(_batch, a, b, c, col)
	_tri(_batch, a, c, d, col)
