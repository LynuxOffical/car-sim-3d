extends RefCounted
class_name SceneryKit

const PINES: Array[String] = [
	"res://assets/kenney/trees/tree_pineTallA.glb",
	"res://assets/kenney/trees/tree_pineTallB.glb",
	"res://assets/kenney/trees/tree_pineTallC.glb",
	"res://assets/kenney/trees/tree_pineTallD.glb",
	"res://assets/kenney/trees/tree_pineTallA_detailed.glb",
	"res://assets/kenney/trees/tree_pineRoundA.glb",
	"res://assets/kenney/trees/tree_pineDefaultA.glb",
	"res://assets/kenney/trees/tree_tall.glb",
]

const SNOW_PINES: Array[String] = [
	"res://assets/kenney/trees/tree_oak_dark.glb",
	"res://assets/kenney/trees/tree_pineRoundC.glb",
	"res://assets/kenney/trees/tree_detailed.glb",
]

const PALMS: Array[String] = [
	"res://assets/kenney/trees/tree_palmTall.glb",
	"res://assets/kenney/trees/tree_palmDetailedTall.glb",
	"res://assets/kenney/trees/tree_palm.glb",
	"res://assets/kenney/trees/tree_palmShort.glb",
]

const CACTUS: Array[String] = [
	"res://assets/kenney/trees/cactus_tall.glb",
	"res://assets/kenney/trees/cactus_short.glb",
]

const ROCKS: Array[String] = [
	"res://assets/kenney/trees/rock_largeA.glb",
	"res://assets/kenney/trees/rock_largeB.glb",
	"res://assets/kenney/trees/rock_largeC.glb",
	"res://assets/kenney/trees/rock_tallA.glb",
	"res://assets/kenney/trees/rock_tallB.glb",
]

const BUSHES: Array[String] = [
	"res://assets/kenney/trees/plant_bushLarge.glb",
	"res://assets/kenney/trees/plant_bush.glb",
]

const CITY: Array[String] = [
	"res://assets/kenney/city/building-a.glb",
	"res://assets/kenney/city/building-b.glb",
	"res://assets/kenney/city/building-c.glb",
	"res://assets/kenney/city/building-d.glb",
	"res://assets/kenney/city/building-e.glb",
	"res://assets/kenney/city/building-f.glb",
	"res://assets/kenney/city/building-g.glb",
	"res://assets/kenney/city/building-h.glb",
	"res://assets/kenney/city/building-i.glb",
	"res://assets/kenney/city/building-j.glb",
	"res://assets/kenney/city/building-k.glb",
	"res://assets/kenney/city/building-l.glb",
	"res://assets/kenney/city/building-m.glb",
	"res://assets/kenney/city/building-n.glb",
]

const TOWERS: Array[String] = [
	"res://assets/kenney/city/building-skyscraper-a.glb",
	"res://assets/kenney/city/building-skyscraper-b.glb",
	"res://assets/kenney/city/building-skyscraper-c.glb",
	"res://assets/kenney/city/building-skyscraper-d.glb",
	"res://assets/kenney/city/building-skyscraper-e.glb",
]

const HOUSES: Array[String] = [
	"res://assets/kenney/houses/building-type-a.glb",
	"res://assets/kenney/houses/building-type-b.glb",
	"res://assets/kenney/houses/building-type-c.glb",
	"res://assets/kenney/houses/building-type-e.glb",
	"res://assets/kenney/houses/building-type-g.glb",
	"res://assets/kenney/houses/building-type-i.glb",
	"res://assets/kenney/houses/building-type-k.glb",
	"res://assets/kenney/houses/building-type-m.glb",
	"res://assets/kenney/houses/building-type-p.glb",
	"res://assets/kenney/houses/building-type-r.glb",
	"res://assets/kenney/houses/building-type-t.glb",
	"res://assets/kenney/houses/building-type-u.glb",
]


static func spawn(parent: Node3D, path: String, pos: Vector3, yaw: float, scl: float, shadows: bool, vertex_color := true) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var node: Node3D = packed.instantiate()
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3(scl, scl, scl)
	_prep(node, shadows, vertex_color)
	parent.add_child(node)


static func spawn_fitted(parent: Node3D, path: String, pos: Vector3, yaw: float, target_h: float, max_foot: float, shadows: bool) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var node: Node3D = packed.instantiate()
	_prep(node, shadows, false)
	var box := mesh_aabb(node, Transform3D.IDENTITY)
	var h := maxf(box.size.y, 0.05)
	var foot := maxf(box.size.x, box.size.z)
	var scl := target_h / h
	if foot * scl > max_foot and foot > 0.05:
		scl = max_foot / foot
	node.scale = Vector3(scl, scl, scl)
	node.rotation.y = yaw
	node.position = Vector3(pos.x, pos.y - box.position.y * scl, pos.z)
	parent.add_child(node)


static func mesh_aabb(n: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var has := false
	if n is VisualInstance3D:
		var a: AABB = xform * (n as VisualInstance3D).get_aabb()
		out = a
		has = true
	for c in n.get_children():
		if c is Node3D:
			var child := mesh_aabb(c, xform * (c as Node3D).transform)
			if child.size.length() < 0.0001:
				continue
			if has:
				out = out.merge(child)
			else:
				out = child
				has = true
	return out


static func pick(list: Array[String], rng: RandomNumberGenerator) -> String:
	if list.is_empty():
		return ""
	return list[rng.randi() % list.size()]


static func _prep(n: Node, shadows: bool, vertex_color: bool) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src: Material = mi.get_surface_override_material(i)
				if src == null:
					src = mi.mesh.surface_get_material(i)
				if src is StandardMaterial3D:
					var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
					var painted := vertex_color and m.albedo_texture == null
					m.vertex_color_use_as_albedo = painted
					m.vertex_color_is_srgb = painted
					m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					m.metallic = minf(m.metallic, 0.12)
					m.roughness = maxf(m.roughness, 0.42)
					m.cull_mode = BaseMaterial3D.CULL_BACK
					mi.set_surface_override_material(i, m)
	elif n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is CollisionObject3D:
		n.collision_layer = 0
		n.collision_mask = 0
	for c in n.get_children():
		_prep(c, shadows, vertex_color)
