extends Node3D
class_name Bullet

var owner_car: ArcadeCar
var heading := 0.0
var life := 1.35
var shot_id := ""

func setup(p_owner: ArcadeCar, p_id: String, p_heading: float, pos: Vector3) -> void:
	owner_car = p_owner
	shot_id = p_id
	heading = p_heading
	life = GameState.BULLET_LIFE
	global_position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.9)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.4, 1.1, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	rotation.y = heading


func step(delta: float) -> bool:
	var fx := -sin(heading)
	var fz := -cos(heading)
	global_position += Vector3(fx, 0, fz) * GameState.BULLET_SPEED * delta
	rotation.y = heading
	life -= delta
	return life > 0.0
