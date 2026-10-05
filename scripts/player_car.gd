extends ArcadeCar
class_name PlayerCar

func _ready() -> void:
	add_to_group("player")
	collision_layer = 0
	collision_mask = 0


func _physics_process(delta: float) -> void:
	var ctrl := read_player_controls()
	if not can_drive:
		ctrl = Vector2.ZERO
	arcade_step(delta, ctrl.x, ctrl.y)
