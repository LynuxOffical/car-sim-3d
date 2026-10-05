extends CharacterBody3D

var wander_dir := Vector3.FORWARD
var alive := true
var timer := 0.0

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2
	add_to_group("pedestrian")
	motion_mode = MOTION_MODE_GROUNDED
	var cap := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.6
	cap.shape = shape
	cap.position.y = 0.8
	add_child(cap)
	var body := MeshInstance3D.new()
	var cyl := CapsuleMesh.new()
	cyl.radius = 0.28
	cyl.height = 1.6
	body.mesh = cyl
	body.position.y = 0.8
	body.material_override = Mats.solid(Color(randf_range(0.2, 0.9), randf_range(0.15, 0.5), randf_range(0.1, 0.4)))
	add_child(body)
	wander_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()


func _physics_process(delta: float) -> void:
	if not alive:
		velocity.y -= 18.0 * delta
		move_and_slide()
		return
	timer -= delta
	if timer <= 0.0:
		timer = randf_range(1.5, 3.5)
		wander_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	velocity.x = wander_dir.x * 1.6
	velocity.z = wander_dir.z * 1.6
	velocity.y -= 18.0 * delta
	move_and_slide()
	if wander_dir.length() > 0.1:
		look_at(global_position + wander_dir, Vector3.UP)


func knock_down(dir: Vector3) -> void:
	if not alive:
		return
	alive = false
	velocity = dir.normalized() * 12.0 + Vector3.UP * 6.0
	collision_layer = 0
	await get_tree().create_timer(8.0).timeout
	queue_free()
