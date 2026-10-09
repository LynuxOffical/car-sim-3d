extends Camera3D

## Chase / hood / top. Stays behind local -Z (arcade forward).

const BASE_DIST := 11.0
const BASE_HEIGHT := 4.6
const STIFFNESS := 5.0

var target: Node3D
var listen_input := true

func setup(who: Node3D) -> void:
	target = who
	current = true
	fov = GameState.fov
	near = 0.25
	far = 1800.0
	_snap()


func _unhandled_input(event: InputEvent) -> void:
	if not listen_input:
		return
	if event.is_action_pressed("camera_cycle"):
		GameState.cycle_camera()
		_snap()


func cycle() -> void:
	GameState.cycle_camera()
	_snap()


func _forward(h: float) -> Vector3:
	return Vector3(-sin(h), 0.0, -cos(h))


func _back(h: float) -> Vector3:
	return Vector3(sin(h), 0.0, cos(h))


func _target_pos() -> Vector3:
	var car := target as ArcadeCar
	if car == null:
		return global_position
	var h := car.heading
	var spd := absf(car.speed)
	match GameState.camera_mode:
		"HOOD":
			return car.global_position + _forward(h) * 0.45 + Vector3.UP * 1.25
		"TOP":
			return car.global_position + Vector3(0, 38.0 + spd * 0.04, 0)
		_:
			var d := BASE_DIST + spd * 0.035
			return car.global_position + _back(h) * d + Vector3.UP * (BASE_HEIGHT + spd * 0.012)


func _snap() -> void:
	if target:
		global_position = _target_pos()
		_look()


func _look() -> void:
	var car := target as ArcadeCar
	if car == null:
		return
	var h := car.heading
	match GameState.camera_mode:
		"HOOD":
			_safe_look(car.global_position + _forward(h) * 18.0 + Vector3.UP * 1.0)
		"TOP":
			rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
		_:
			_safe_look(car.global_position + Vector3.UP * 1.2)


func _safe_look(to: Vector3) -> void:
	if global_position.distance_squared_to(to) < 0.0008:
		return
	var dir := (to - global_position).normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.995:
		up = Vector3.FORWARD
	look_at(to, up)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	fov = lerp(fov, GameState.fov, delta * 3.2)
	var stiff := 12.0 if GameState.camera_mode == "HOOD" else (8.0 if GameState.camera_mode == "TOP" else STIFFNESS)
	var t := 1.0 - exp(-stiff * delta)
	global_position = global_position.lerp(_target_pos(), t)
	_look()
