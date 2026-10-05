class_name VehicleFactory
extends RefCounted

static func make_bike(paint: Color, style: String = "sport") -> Node3D:
	var root := Node3D.new()
	root.name = "BikeMesh"
	root.position = Vector3(0, -0.22, 0)
	var accent := paint.lightened(0.18)
	var dark := paint.darkened(0.5)
	var metal := Color(0.16, 0.17, 0.2)
	var rubber := Color(0.07, 0.07, 0.08)
	var carbon := Color(0.1, 0.1, 0.12)

	_box(root, Vector3(0.1, 0.12, 1.22), Vector3(0, 0.4, -0.02), carbon, 0.7, 0.28) # spine
	_box(root, Vector3(0.38, 0.26, 0.62), Vector3(0, 0.62, 0.1), paint, 0.55, 0.22) # tank
	_box(root, Vector3(0.34, 0.08, 0.48), Vector3(0, 0.74, 0.08), accent, 0.4, 0.2)
	_box(root, Vector3(0.3, 0.1, 0.5), Vector3(0, 0.54, -0.48), dark, 0.2, 0.55) # seat
	_box(root, Vector3(0.22, 0.08, 0.18), Vector3(0, 0.62, -0.72), dark, 0.15, 0.5) # tail
	_box(root, Vector3(0.09, 0.48, 0.09), Vector3(0.0, 0.58, 0.62), metal, 0.85, 0.2) # stem
	_box(root, Vector3(0.62, 0.045, 0.045), Vector3(0, 0.84, 0.6), metal, 0.9, 0.18) # bars
	_box(root, Vector3(0.08, 0.08, 0.12), Vector3(0.28, 0.84, 0.6), rubber)
	_box(root, Vector3(0.08, 0.08, 0.12), Vector3(-0.28, 0.84, 0.6), rubber)
	_box(root, Vector3(0.2, 0.16, 0.26), Vector3(0, 0.74, 0.82), Color(0.85, 0.9, 1.0), 0.2, 0.15) # lamp
	_box(root, Vector3(0.22, 0.14, 0.32), Vector3(0, 0.36, -0.88), metal, 0.8, 0.25) # swingarm
	_box(root, Vector3(0.08, 0.08, 0.55), Vector3(0.16, 0.32, -0.35), metal, 0.85, 0.2) # exhaust
	_box(root, Vector3(0.42, 0.04, 0.7), Vector3(0, 0.28, 0.05), metal, 0.6, 0.35) # belly

	if style == "dirt":
		_box(root, Vector3(0.26, 0.16, 0.5), Vector3(0, 0.78, -0.12), Color(0.82, 0.58, 0.1), 0.15, 0.55)
		_box(root, Vector3(0.5, 0.06, 0.22), Vector3(0, 0.48, 0.7), Color(0.12, 0.12, 0.12))
	elif style == "cafe":
		_box(root, Vector3(0.55, 0.05, 0.22), Vector3(0, 0.68, 0.52), paint, 0.5, 0.25)
		_box(root, Vector3(0.18, 0.18, 0.18), Vector3(0, 0.7, -0.55), dark)
	elif style == "cruiser":
		_box(root, Vector3(0.4, 0.14, 0.7), Vector3(0, 0.5, -0.35), dark, 0.1, 0.6)
		_box(root, Vector3(0.7, 0.05, 0.08), Vector3(0, 0.86, 0.55), metal, 0.9, 0.15)
	elif style == "naked":
		_box(root, Vector3(0.16, 0.2, 0.3), Vector3(0, 0.48, 0.22), Color(0.55, 0.12, 0.1), 0.3, 0.4)

	_disc(root, 0.34, Vector3(0.02, 0.32, 0.78), metal)
	_disc(root, 0.36, Vector3(0.02, 0.32, -0.78), metal)

	var wheel_scene: PackedScene = load("res://assets/cars/wheel-racing.glb")
	for z in [0.78, -0.78]:
		var w: Node3D
		if wheel_scene:
			w = wheel_scene.instantiate()
		else:
			w = Node3D.new()
			_sphere(w, 0.32, Vector3.ZERO, rubber)
		w.position = Vector3(0, 0.32, z)
		w.scale = Vector3(1.2, 1.2, 1.2)
		root.add_child(w)
	return root


static func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, metallic: float = 0.35, rough: float = 0.32) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = metallic
	mat.roughness = rough
	mat.clearcoat_enabled = metallic > 0.4
	mat.clearcoat = 0.25
	mi.material_override = mat
	parent.add_child(mi)


static func _disc(parent: Node3D, r: float, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.04
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 0, 90)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.9
	mat.roughness = 0.18
	mi.material_override = mat
	parent.add_child(mi)


static func _sphere(parent: Node3D, r: float, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	parent.add_child(mi)
