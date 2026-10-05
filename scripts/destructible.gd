extends RigidBody3D

func shatter(impulse: Vector3) -> void:
	freeze = false
	apply_impulse(impulse.normalized() * 18.0 + Vector3.UP * 4.0)
	await get_tree().create_timer(6.0).timeout
	queue_free()
