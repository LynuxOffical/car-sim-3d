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

const WIDTH_SCALE := 1.52

const MAPS := [
	{
		"name": "MEADOW CIRCUIT", "tag": "classic  -  chicane and decreasing hairpin", "biome": "meadow", "width": 16.0, "samples": 28,
		"points": [Vector2(0, -92), Vector2(34, -98), Vector2(72, -86), Vector2(96, -52), Vector2(100, -14), Vector2(78, 10), Vector2(94, 24), Vector2(72, 40), Vector2(46, 46), Vector2(38, 72), Vector2(68, 92), Vector2(52, 118), Vector2(10, 116), Vector2(-22, 98), Vector2(-8, 72), Vector2(-32, 50), Vector2(-68, 66), Vector2(-102, 52), Vector2(-114, 16), Vector2(-92, -12), Vector2(-110, -42), Vector2(-88, -76), Vector2(-46, -90), Vector2(-14, -88)],
		"ground": Color(0.29, 0.5, 0.23), "road": Color(0.55, 0.55, 0.58), "sky": Color(0.66, 0.8, 0.95), "stripe_a": Color(0.85, 0.15, 0.15), "stripe_b": Color(0.92, 0.92, 0.92), "scenery": "pine",
	},
	{
		"name": "SUNSET SPEEDWAY", "tag": "desert  -  kinked speedbowl", "biome": "desert", "width": 17.5, "samples": 18,
		"points": [Vector2(0, -112), Vector2(48, -110), Vector2(92, -86), Vector2(118, -42), Vector2(108, -4), Vector2(128, 28), Vector2(102, 64), Vector2(58, 78), Vector2(72, 110), Vector2(22, 122), Vector2(-32, 112), Vector2(-78, 86), Vector2(-52, 48), Vector2(-98, 36), Vector2(-124, -2), Vector2(-110, -52), Vector2(-72, -96), Vector2(-24, -112)],
		"ground": Color(0.78, 0.68, 0.44), "road": Color(0.6, 0.56, 0.54), "sky": Color(0.96, 0.74, 0.5), "stripe_a": Color(0.8, 0.25, 0.1), "stripe_b": Color(0.95, 0.9, 0.8), "scenery": "desert",
	},
	{
		"name": "ALPINE RUN", "tag": "snow  -  stacked switchbacks", "biome": "alpine", "width": 13.5, "samples": 28,
		"points": [Vector2(0, -78), Vector2(28, -86), Vector2(62, -70), Vector2(72, -36), Vector2(48, -18), Vector2(82, 0), Vector2(70, 32), Vector2(96, 52), Vector2(68, 78), Vector2(28, 70), Vector2(8, 42), Vector2(-18, 58), Vector2(-12, 92), Vector2(-48, 102), Vector2(-82, 78), Vector2(-70, 42), Vector2(-98, 18), Vector2(-86, -18), Vector2(-108, -42), Vector2(-72, -70), Vector2(-32, -62), Vector2(-8, -74)],
		"ground": Color(0.86, 0.89, 0.93), "road": Color(0.42, 0.42, 0.48), "sky": Color(0.72, 0.78, 0.9), "stripe_a": Color(0.2, 0.35, 0.7), "stripe_b": Color(0.92, 0.92, 0.95), "scenery": "snow_pine",
	},
	{
		"name": "ROCKPORT CITY", "tag": "urban  -  blocky chase streets", "biome": "city", "width": 18.5, "samples": 16, "city": true,
		"points": [Vector2(0, -118), Vector2(42, -122), Vector2(88, -98), Vector2(78, -58), Vector2(112, -42), Vector2(118, 2), Vector2(86, 28), Vector2(108, 62), Vector2(72, 92), Vector2(28, 82), Vector2(8, 112), Vector2(-36, 108), Vector2(-28, 68), Vector2(-72, 78), Vector2(-108, 48), Vector2(-92, 8), Vector2(-118, -28), Vector2(-88, -72), Vector2(-108, -102), Vector2(-52, -118)],
		"ground": Color(0.22, 0.23, 0.26), "road": Color(0.28, 0.28, 0.32), "sky": Color(0.38, 0.4, 0.46), "stripe_a": Color(0.9, 0.9, 0.92), "stripe_b": Color(0.55, 0.55, 0.58), "scenery": "city",
	},
	{
		"name": "HARBOR DISTRICT", "tag": "coastal  -  dock chicane", "biome": "harbor", "width": 16.5, "samples": 18,
		"points": [Vector2(0, -102), Vector2(48, -108), Vector2(96, -82), Vector2(118, -38), Vector2(92, -8), Vector2(112, 22), Vector2(84, 52), Vector2(48, 42), Vector2(22, 72), Vector2(-18, 88), Vector2(-58, 70), Vector2(-42, 32), Vector2(-88, 18), Vector2(-122, -8), Vector2(-108, -52), Vector2(-78, -42), Vector2(-92, -82), Vector2(-48, -104), Vector2(-12, -96)],
		"ground": Color(0.35, 0.42, 0.38), "road": Color(0.38, 0.38, 0.42), "sky": Color(0.55, 0.68, 0.82), "stripe_a": Color(0.85, 0.75, 0.2), "stripe_b": Color(0.9, 0.9, 0.92), "scenery": "pine",
	},
	{
		"name": "CANYON PASS", "tag": "mountain  -  double hairpin gorge", "biome": "canyon", "width": 14.5, "samples": 28,
		"points": [Vector2(0, -86), Vector2(32, -94), Vector2(70, -74), Vector2(88, -32), Vector2(62, -8), Vector2(92, 18), Vector2(74, 52), Vector2(38, 42), Vector2(18, 74), Vector2(-16, 92), Vector2(-52, 78), Vector2(-38, 42), Vector2(-72, 28), Vector2(-98, -8), Vector2(-76, -38), Vector2(-102, -62), Vector2(-68, -86), Vector2(-28, -70), Vector2(-8, -84)],
		"ground": Color(0.48, 0.44, 0.36), "road": Color(0.4, 0.38, 0.36), "sky": Color(0.62, 0.7, 0.82), "stripe_a": Color(0.78, 0.55, 0.18), "stripe_b": Color(0.88, 0.88, 0.9), "scenery": "desert",
	},
	{
		"name": "MIDNIGHT METRO", "tag": "night city  -  downtown maze", "biome": "city", "width": 17.5, "samples": 18, "city": true,
		"points": [Vector2(0, -108), Vector2(38, -114), Vector2(82, -90), Vector2(70, -52), Vector2(108, -38), Vector2(102, 8), Vector2(68, 18), Vector2(88, 52), Vector2(52, 82), Vector2(12, 68), Vector2(-8, 102), Vector2(-48, 96), Vector2(-32, 58), Vector2(-78, 62), Vector2(-108, 28), Vector2(-86, -8), Vector2(-112, -42), Vector2(-78, -78), Vector2(-98, -108), Vector2(-42, -112)],
		"ground": Color(0.12, 0.13, 0.16), "road": Color(0.2, 0.2, 0.24), "sky": Color(0.08, 0.09, 0.14), "stripe_a": Color(0.95, 0.85, 0.25), "stripe_b": Color(0.35, 0.35, 0.4), "scenery": "city",
	},
	{
		"name": "PALM COAST", "tag": "tropical  -  seaside esses", "biome": "tropical", "width": 15.5, "samples": 18,
		"points": [Vector2(0, -98), Vector2(42, -104), Vector2(86, -78), Vector2(104, -32), Vector2(78, -6), Vector2(98, 28), Vector2(64, 52), Vector2(28, 38), Vector2(-4, 72), Vector2(-48, 88), Vector2(-88, 58), Vector2(-62, 22), Vector2(-102, 2), Vector2(-112, -38), Vector2(-78, -58), Vector2(-96, -88), Vector2(-48, -102), Vector2(-12, -92)],
		"ground": Color(0.18, 0.52, 0.32), "road": Color(0.42, 0.4, 0.36), "sky": Color(0.35, 0.72, 0.88), "stripe_a": Color(0.95, 0.55, 0.15), "stripe_b": Color(0.95, 0.95, 0.9), "scenery": "palm",
	},
	{
		"name": "FOUNDRY LOOP", "tag": "industrial  -  90-degree yards", "biome": "industrial", "width": 16.5, "samples": 16,
		"points": [Vector2(0, -96), Vector2(40, -102), Vector2(88, -86), Vector2(102, -40), Vector2(74, -18), Vector2(108, 8), Vector2(96, 48), Vector2(52, 62), Vector2(62, 96), Vector2(12, 102), Vector2(-28, 82), Vector2(-18, 46), Vector2(-68, 52), Vector2(-104, 18), Vector2(-90, -28), Vector2(-108, -68), Vector2(-64, -94), Vector2(-18, -90)],
		"ground": Color(0.28, 0.26, 0.22), "road": Color(0.24, 0.24, 0.26), "sky": Color(0.42, 0.4, 0.36), "stripe_a": Color(0.95, 0.55, 0.1), "stripe_b": Color(0.2, 0.2, 0.22), "scenery": "factory",
	},
	{
		"name": "VOLCANO RIDGE", "tag": "volcanic  -  crater rim esses", "biome": "volcanic", "width": 14.5, "samples": 26,
		"points": [Vector2(0, -84), Vector2(30, -92), Vector2(68, -70), Vector2(86, -28), Vector2(58, -6), Vector2(88, 22), Vector2(66, 56), Vector2(24, 48), Vector2(4, 82), Vector2(-36, 90), Vector2(-72, 62), Vector2(-48, 28), Vector2(-88, 8), Vector2(-98, -32), Vector2(-70, -52), Vector2(-92, -78), Vector2(-46, -90), Vector2(-12, -80)],
		"ground": Color(0.22, 0.12, 0.1), "road": Color(0.18, 0.16, 0.16), "sky": Color(0.45, 0.22, 0.16), "stripe_a": Color(0.95, 0.25, 0.08), "stripe_b": Color(0.35, 0.12, 0.08), "scenery": "lava",
	},
	{
		"name": "SALT FLATS", "tag": "desert  -  high-speed infield cut", "biome": "desert", "width": 20.0, "samples": 16,
		"points": [Vector2(0, -128), Vector2(58, -124), Vector2(112, -86), Vector2(132, -28), Vector2(108, 18), Vector2(128, 62), Vector2(82, 98), Vector2(28, 88), Vector2(8, 122), Vector2(-48, 118), Vector2(-28, 72), Vector2(-92, 82), Vector2(-132, 28), Vector2(-118, -32), Vector2(-138, -78), Vector2(-86, -118), Vector2(-28, -124)],
		"ground": Color(0.86, 0.82, 0.7), "road": Color(0.55, 0.52, 0.48), "sky": Color(0.9, 0.82, 0.62), "stripe_a": Color(0.2, 0.2, 0.22), "stripe_b": Color(0.95, 0.92, 0.85), "scenery": "desert",
	},
	{
		"name": "SWITCHBACK RIDGE", "tag": "forest  -  packed hairpins", "biome": "meadow", "width": 13.0, "samples": 28,
		"points": [Vector2(0, -96), Vector2(26, -104), Vector2(62, -82), Vector2(48, -44), Vector2(82, -22), Vector2(58, 8), Vector2(92, 28), Vector2(64, 58), Vector2(96, 82), Vector2(48, 98), Vector2(12, 78), Vector2(-18, 102), Vector2(-58, 86), Vector2(-36, 52), Vector2(-78, 38), Vector2(-52, 8), Vector2(-96, -8), Vector2(-64, -42), Vector2(-98, -72), Vector2(-52, -94), Vector2(-16, -88)],
		"ground": Color(0.18, 0.32, 0.16), "road": Color(0.36, 0.35, 0.34), "sky": Color(0.52, 0.68, 0.78), "stripe_a": Color(0.75, 0.55, 0.12), "stripe_b": Color(0.88, 0.88, 0.86), "scenery": "pine",
	},
	{
		"name": "LAGOON STRAITS", "tag": "tropical  -  bay in-and-out", "biome": "tropical", "width": 17.5, "samples": 18,
		"points": [Vector2(0, -122), Vector2(48, -124), Vector2(98, -96), Vector2(122, -48), Vector2(100, -8), Vector2(118, 36), Vector2(82, 72), Vector2(42, 58), Vector2(8, 96), Vector2(-42, 108), Vector2(-88, 78), Vector2(-58, 38), Vector2(-108, 18), Vector2(-128, -28), Vector2(-102, -68), Vector2(-118, -102), Vector2(-68, -122), Vector2(-18, -116)],
		"ground": Color(0.16, 0.48, 0.38), "road": Color(0.40, 0.38, 0.34), "sky": Color(0.32, 0.70, 0.86), "stripe_a": Color(0.12, 0.62, 0.58), "stripe_b": Color(0.95, 0.94, 0.88), "scenery": "palm",
	},
]

const DEFS := MAPS


func _lane_half(spec: Dictionary) -> float:
	return float(spec.get("width", 16.0)) * 0.5 * WIDTH_SCALE


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
	half_width = _lane_half(theme)


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
	half_width = _lane_half(theme)
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
	half_width = _lane_half(spec)
	var pts: Array = spec["points"]
	var samples: int = int(spec["samples"])
	var wps: Array[Vector2] = _clean_wps(_catmull(pts, samples))
	var frame: Dictionary = _frames(wps)
	var dirs: Array[Vector2] = []
	var norms: Array[Vector2] = []
	dirs.assign(frame["dirs"])
	norms.assign(frame["norms"])
	var local_path: Array[Vector3] = []
	var start := wps2.size()
	var local_wps2: Array[Vector2] = []
	for i in wps.size():
		var a: Vector2 = wps[i]
		var d: Vector2 = dirs[i]
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
	_curbs(wps, dirs, norms, origin, spec)
	_walls(wps, dirs, norms, origin, spec)
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
	mi.position = origin + Vector3((minp.x + maxp.x) * 0.5, -0.10, (minp.y + maxp.y) * 0.5)
	mi.material_override = Mats.ground(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func _clean_wps(wps: Array[Vector2], min_dist := 1.35) -> Array[Vector2]:
	if wps.size() < 12:
		return wps
	var out: Array[Vector2] = []
	for p in wps:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= min_dist:
			out.append(p)
	if out.size() > 8 and out[0].distance_to(out[out.size() - 1]) < min_dist:
		out.pop_back()
	return out if out.size() >= 12 else wps


func _frames(wps: Array[Vector2]) -> Dictionary:
	var n := wps.size()
	var dirs: Array[Vector2] = []
	var norms: Array[Vector2] = []
	dirs.resize(n)
	norms.resize(n)
	for i in n:
		var d: Vector2 = wps[(i + 1) % n] - wps[i]
		if d.length_squared() < 0.0002:
			d = wps[(i + 1) % n] - wps[(i - 1 + n) % n]
		if d.length_squared() < 0.0002:
			d = Vector2(0, 1)
		dirs[i] = d.normalized()
	for i in n:
		var prev: Vector2 = dirs[(i - 1 + n) % n]
		var nxt: Vector2 = dirs[(i + 1) % n]
		var acc: Vector2 = prev + dirs[i] * 2.0 + nxt
		if acc.dot(dirs[i]) < 0.05 or acc.length_squared() < 0.0002:
			continue
		dirs[i] = acc.normalized()
	for i in n:
		norms[i] = Vector2(-dirs[i].y, dirs[i].x)
	return {"dirs": dirs, "norms": norms}


func _cj(ti: float, a: Vector2, b: Vector2) -> float:
	return ti + pow(maxf(a.distance_squared_to(b), 0.000001), 0.25)


func _cu(t: float, a: float, b: float) -> float:
	var d := b - a
	if absf(d) < 0.0000001:
		return 0.0
	return (t - a) / d


func _cpt(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t0: float, t1: float, t2: float, t3: float, t: float) -> Vector2:
	var a1 := p0.lerp(p1, _cu(t, t0, t1))
	var a2 := p1.lerp(p2, _cu(t, t1, t2))
	var a3 := p2.lerp(p3, _cu(t, t2, t3))
	var b1 := a1.lerp(a2, _cu(t, t0, t2))
	var b2 := a2.lerp(a3, _cu(t, t1, t3))
	return b1.lerp(b2, _cu(t, t1, t2))


func _catmull(points: Array, samples: int) -> Array[Vector2]:
	var n := points.size()
	var out: Array[Vector2] = []
	var smp := maxi(samples, 12)
	for i in n:
		var p0: Vector2 = points[(i - 1 + n) % n]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		var p3: Vector2 = points[(i + 2) % n]
		var t0 := 0.0
		var t1 := _cj(t0, p0, p1)
		var t2 := _cj(t1, p1, p2)
		var t3 := _cj(t2, p2, p3)
		if t2 - t1 < 0.000001:
			out.append(p1)
			continue
		for s in smp:
			var t := lerpf(t1, t2, float(s) / float(smp))
			out.append(_cpt(p0, p1, p2, p3, t0, t1, t2, t3, t))
	return out


func _edges(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], hw: float) -> Dictionary:
	var n := wps.size()
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	left.resize(n)
	right.resize(n)
	for i in n:
		var d_prev: Vector2 = dirs[(i - 1 + n) % n]
		var d: Vector2 = dirs[i]
		var nrm: Vector2 = norms[i]
		var n_prev := Vector2(-d_prev.y, d_prev.x)
		var m: Vector2 = n_prev + nrm
		if m.length_squared() < 0.0001 or m.dot(nrm) < 0.12:
			m = nrm
		else:
			m = m.normalized()
		var den := maxf(absf(m.dot(nrm)), 0.48)
		var scale := minf(hw / den, hw * 1.18)
		var ang := absf(d_prev.angle_to(d))
		var seg := maxf(wps[i].distance_to(wps[(i + 1) % n]), 0.35)
		var curve := clampf((ang / maxf(seg, 1.0)) * 7.0, 0.0, 1.0)
		scale *= lerpf(1.0, 0.64, curve)
		left[i] = wps[i] + m * scale
		right[i] = wps[i] - m * scale
		var span := left[i].distance_to(right[i])
		var min_span := hw * 1.12
		if span < min_span:
			left[i] = wps[i] + nrm * (min_span * 0.5)
			right[i] = wps[i] - nrm * (min_span * 0.5)
	return {"left": left, "right": right}


func _road(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := half_width
	var n := wps.size()
	var oy := origin.y + 0.09
	var o := Vector3(origin.x, 0, origin.z)
	var edges: Dictionary = _edges(wps, dirs, norms, hw)
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	left.assign(edges["left"])
	right.assign(edges["right"])
	var vdist := 0.0
	for i in n:
		var j := (i + 1) % n
		var a: Vector2 = wps[i]
		var b: Vector2 = wps[j]
		var seg := maxf(0.001, a.distance_to(b))
		var v0 := vdist / 7.0
		var v1 := (vdist + seg) / 7.0
		var left_a := Vector3(left[i].x, oy, left[i].y) + o
		var right_a := Vector3(right[i].x, oy, right[i].y) + o
		var right_b := Vector3(right[j].x, oy, right[j].y) + o
		var left_b := Vector3(left[j].x, oy, left[j].y) + o
		_tri_uv(st, right_a, left_a, left_b, Vector2(1, v0), Vector2(0, v0), Vector2(0, v1))
		_tri_uv(st, right_a, left_b, right_b, Vector2(1, v0), Vector2(0, v1), Vector2(1, v1))
		vdist += seg
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


func _face_n(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.000001:
		return Vector3.UP
	n = n.normalized()
	if n.y < -0.15:
		n = -n
	if n.y > 0.82:
		return Vector3.UP
	return n


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color = Color.WHITE) -> void:
	var n := _face_n(a, b, c)
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(Vector2(a.x * 0.12, a.z * 0.12))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(Vector2(b.x * 0.12, b.z * 0.12))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(Vector2(c.x * 0.12, c.z * 0.12))
	st.add_vertex(c)


func _tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.set_uv(uc)
	st.add_vertex(c)


func _deco_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(_batch, a, b, c, col)
	_tri(_batch, a, c, d, col)


func _curbs(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var sa: Color = spec["stripe_a"]
	var sb: Color = spec["stripe_b"]
	var o := Vector3(origin.x, 0, origin.z)
	var n := wps.size()
	var edges: Dictionary = _edges(wps, dirs, norms, half_width)
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	left.assign(edges["left"])
	right.assign(edges["right"])
	for i in n:
		var j := (i + 1) % n
		var colr: Color = sa if (i / 3) % 2 == 0 else sb
		var in_a := (right[i] - left[i]).normalized()
		var in_b := (right[j] - left[j]).normalized()
		if in_a.length_squared() < 0.0001:
			in_a = -norms[i]
		if in_b.length_squared() < 0.0001:
			in_b = -norms[j]
		_deco_quad(
			Vector3(left[i].x + in_a.x * 1.15, 0.125, left[i].y + in_a.y * 1.15) + o,
			Vector3(left[i].x - in_a.x * 0.06, 0.125, left[i].y - in_a.y * 0.06) + o,
			Vector3(left[j].x - in_b.x * 0.06, 0.125, left[j].y - in_b.y * 0.06) + o,
			Vector3(left[j].x + in_b.x * 1.15, 0.125, left[j].y + in_b.y * 1.15) + o,
			colr
		)
		_deco_quad(
			Vector3(right[i].x - in_a.x * 1.15, 0.125, right[i].y - in_a.y * 1.15) + o,
			Vector3(right[i].x + in_a.x * 0.06, 0.125, right[i].y + in_a.y * 0.06) + o,
			Vector3(right[j].x + in_b.x * 0.06, 0.125, right[j].y + in_b.y * 0.06) + o,
			Vector3(right[j].x - in_b.x * 1.15, 0.125, right[j].y - in_b.y * 1.15) + o,
			colr
		)


func _walls(wps: Array[Vector2], dirs: Array[Vector2], norms: Array[Vector2], origin: Vector3, spec: Dictionary) -> void:
	var h := 1.1
	var sa: Color = spec["stripe_a"]
	var sb: Color = spec["stripe_b"]
	var o := Vector3(origin.x, 0, origin.z)
	var n := wps.size()
	var edges: Dictionary = _edges(wps, dirs, norms, half_width)
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	left.assign(edges["left"])
	right.assign(edges["right"])
	for i in n:
		var j := (i + 1) % n
		var colr: Color = sa if (i / 4) % 2 == 0 else sb
		var in_a := (right[i] - left[i]).normalized()
		var in_b := (right[j] - left[j]).normalized()
		if in_a.length_squared() < 0.0001:
			in_a = -norms[i]
		if in_b.length_squared() < 0.0001:
			in_b = -norms[j]
		var ain := Vector3(left[i].x - in_a.x * 0.45, 0, left[i].y - in_a.y * 0.45) + o
		var bin := Vector3(left[j].x - in_b.x * 0.45, 0, left[j].y - in_b.y * 0.45) + o
		var aout := Vector3(left[i].x - in_a.x * 1.35, 0, left[i].y - in_a.y * 1.35) + o
		var bout := Vector3(left[j].x - in_b.x * 1.35, 0, left[j].y - in_b.y * 1.35) + o
		_deco_quad(ain, bin, bin + Vector3(0, h, 0), ain + Vector3(0, h, 0), colr)
		_deco_quad(aout, aout + Vector3(0, h, 0), bout + Vector3(0, h, 0), bout, colr)
		_deco_quad(ain + Vector3(0, h, 0), bin + Vector3(0, h, 0), bout + Vector3(0, h, 0), aout + Vector3(0, h, 0), colr)
		ain = Vector3(right[i].x + in_a.x * 0.45, 0, right[i].y + in_a.y * 0.45) + o
		bin = Vector3(right[j].x + in_b.x * 0.45, 0, right[j].y + in_b.y * 0.45) + o
		aout = Vector3(right[i].x + in_a.x * 1.35, 0, right[i].y + in_a.y * 1.35) + o
		bout = Vector3(right[j].x + in_b.x * 1.35, 0, right[j].y + in_b.y * 1.35) + o
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
			Vector3(p.x - nrm.x * 0.18, 0.14, p.y - nrm.y * 0.18) + o,
			Vector3(p.x + nrm.x * 0.18, 0.14, p.y + nrm.y * 0.18) + o,
			Vector3(p.x + nrm.x * 0.18 + d.x * 2.2, 0.14, p.y + nrm.y * 0.18 + d.y * 2.2) + o,
			Vector3(p.x - nrm.x * 0.18 + d.x * 2.2, 0.14, p.y - nrm.y * 0.18 + d.y * 2.2) + o,
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
				pts.append(Vector3(wx.x + nrm.x * pair.x + d.x * pair.y, 0.145, wx.y + nrm.y * pair.x + d.y * pair.y) + o)
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
