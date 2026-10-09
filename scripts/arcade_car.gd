extends CharacterBody3D
class_name ArcadeCar

## Panda3D `Car.update` port: arcade speed + heading, Kenney mesh on top.

const CarPaint := preload("res://scripts/car_paint.gd")
const REVERSE_ACCEL := 14.0
const MAX_REVERSE_SPEED := -18.0
const ROLL_DECAY := 0.15
const DRAG := 0.0042
const HP_MAX := 100
const HANDLING := 1.32
const SPEED_MULT := 1.14

var display_name := "P1"
var kind := "car"
var max_speed := 115.0
var accel := 30.0
var brake_rate := 50.0
var steer_rate := 2.35
var grip := 1.0
var nitro_mult := 0.7
var speed := 0.0
var heading := 0.0
var visual_steer := 0.0
var speed_kmh := 0.0
var nitro_tank := 1.0
var nitro_active := false
var visual: Node3D
var gun_node: Node3D
var is_police := false
var hp := HP_MAX
var kills := 0
var wreck_t := 0.0
var fire_cd := 0.0
var hit_flash := 0.0
var lap := 0
var wp_idx := 0
var race_pos := 1
var checkpoint := 0
var checkpoints_hit := 0
var finished := false
var can_drive := true
var auto_throttle := 0.0
var ai_skill := 0.0
var linear_damp := 0.0
var _touch_throttle := 0.0
var _touch_steer := 0.0
var _use_touch := false
var car_id := "corolla"
var wheel_radius := 0.32
var _wheel_roll := 0.0
var _spin_nodes: Array[Node3D] = []
var player_slot := 0

func configure(car: Dictionary, paint: Color, p_name := "P1", police := false) -> void:
	display_name = p_name
	kind = str(car.get("kind", "car"))
	car_id = str(car.get("id", "corolla"))
	max_speed = float(car.get("max_speed", car.get("speed", 115.0))) * SPEED_MULT
	accel = float(car.get("accel", 30.0)) * 1.08
	if accel <= 3.0:
		accel = 30.0 * maxf(accel, 0.5)
	brake_rate = float(car.get("brake", 50.0))
	steer_rate = float(car.get("steer", 2.35)) * HANDLING
	nitro_mult = float(car.get("nitro", 0.7))
	is_police = police or str(car.get("id")) == "police"
	hp = HP_MAX
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var length := float(car.get("length", 4.5))
	if kind == "bike":
		var style := "sport"
		if car_id == "raid":
			style = "dirt"
		elif car_id == "hawk":
			style = "cafe"
		elif car_id == "bagger":
			style = "cruiser"
		elif car_id == "specter":
			style = "naked"
		visual = VehicleFactory.make_bike(paint, style)
		visual.rotation.y = PI
		add_child(visual)
	else:
		var packed: PackedScene = load(str(car.get("glb", "res://assets/cars/sedan.glb")))
		if packed:
			visual = packed.instantiate()
			visual.rotation.y = PI
			add_child(visual)
			CarPaint.apply(visual, car_id, paint, GameState.paint_index, is_police or car_id == "interceptor", length)
	if GameState.gun_enabled:
		attach_gun()
	_collect_wheels(self)


func attach_gun() -> void:
	if gun_node:
		return
	gun_node = Node3D.new()
	gun_node.name = "Gun"
	var base := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.42, 0.22, 0.42)
	base.mesh = bmesh
	base.position = Vector3(0, 1.28, 0.15)
	base.material_override = Mats.solid(Color(0.16, 0.16, 0.18), 0.7, 0.25)
	gun_node.add_child(base)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = Vector3(0.16, 0.16, 0.85)
	barrel.mesh = barrel_mesh
	barrel.position = Vector3(0, 1.34, -0.55)
	barrel.material_override = Mats.solid(Color(0.1, 0.1, 0.12), 0.85, 0.2)
	gun_node.add_child(barrel)
	add_child(gun_node)


func set_touch(throttle: float, steer: float) -> void:
	_use_touch = absf(throttle) > 0.08 or absf(steer) > 0.08
	_touch_throttle = throttle
	_touch_steer = steer


func place(pos: Vector3, p_heading: float, p_wp: int = 0) -> void:
	heading = p_heading
	rotation = Vector3(0, heading, 0)
	speed = 0.0
	velocity = Vector3.ZERO
	global_position = Vector3(pos.x, 0.22, pos.z)
	wp_idx = p_wp
	lap = 0
	checkpoint = 0
	checkpoints_hit = 0
	finished = false
	hp = HP_MAX
	wreck_t = 0.0
	hit_flash = 0.0


func respawn_at(pos: Vector3, p_heading: float, p_wp: int) -> void:
	place(pos, p_heading, p_wp)
	hp = HP_MAX
	wreck_t = 0.0
	if visual:
		visual.visible = true


func take_hit(attacker: ArcadeCar) -> void:
	if wreck_t > 0.0:
		return
	hp -= GameState.GUN_DAMAGE
	hit_flash = 0.25
	if hp > 0:
		speed *= 0.82
		return
	hp = 0
	wreck_t = GameState.WRECK_TIME
	speed *= 0.15
	if attacker and attacker != self:
		attacker.kills += 1
		GameState.kill_text = "%s  WRECKED  %s" % [attacker.display_name, display_name]
		GameState.kill_flash = 1.6


func arcade_step(delta: float, throttle: float, steer: float) -> void:
	grip = GameState.weather_grip * 1.12
	if wreck_t > 0.0:
		throttle *= 0.12
		steer *= 0.35
		wreck_t = maxf(0.0, wreck_t - delta)
	if fire_cd > 0.0:
		fire_cd = maxf(0.0, fire_cd - delta)
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta)
	nitro_active = throttle > 0.1 and nitro_tank > 0.05 and (
		(ai_skill == 0.0 and not is_police and _held("nitro"))
		or (is_police and ai_skill > 0.0)
	)
	if nitro_active:
		nitro_tank = maxf(0.0, nitro_tank - delta * 0.38)
	else:
		nitro_tank = minf(1.0, nitro_tank + delta * 0.12)
	var top := max_speed * (1.35 if nitro_active else 1.0)
	var acc := accel * (1.0 + 0.55 * nitro_mult if nitro_active else 1.0)
	if throttle > 0.0:
		speed += acc * grip * throttle * delta
	elif throttle < 0.0:
		if speed > 0.5:
			speed += brake_rate * grip * throttle * delta
		else:
			speed += REVERSE_ACCEL * throttle * delta
	if ai_skill == 0.0 and not is_police and _held("handbrake"):
		speed *= exp(-2.8 * delta)
	speed *= exp(-ROLL_DECAY * delta)
	speed -= DRAG * speed * absf(speed) * delta
	if absf(speed) < 0.02 and is_zero_approx(throttle):
		speed = 0.0
	speed = clampf(speed, MAX_REVERSE_SPEED, top)
	if not is_zero_approx(steer) and absf(speed) > 0.1:
		var ratio := minf(absf(speed) / maxf(max_speed, 1.0), 1.0)
		var effect := sin(minf(ratio * 1.72, 1.0) * PI * 0.5)
		effect *= (1.0 - 0.08 * ratio)
		var direction := 1.0 if speed >= 0.0 else -1.0
		heading += steer * steer_rate * grip * effect * direction * delta
	visual_steer = lerpf(visual_steer, steer, minf(1.0, delta * 12.0))
	_wheel_roll += speed * delta / wheel_radius
	# Godot vehicles drive toward local -Z (same as the old VehicleBody3D setup).
	var fx := -sin(heading)
	var fz := -cos(heading)
	var p := global_position
	p.x += fx * speed * delta
	p.z += fz * speed * delta
	p.y = 0.22
	global_position = p
	velocity = Vector3(fx, 0.0, fz) * speed
	rotation = Vector3(0, heading, 0)
	speed_kmh = absf(speed) * 3.6
	if visual:
		var lean := visual_steer * minf(absf(speed) / 38.0, 1.0)
		if kind == "bike":
			visual.rotation.z = lerp_angle(visual.rotation.z, -lean * 0.52, delta * 8.0)
		else:
			visual.rotation.z = lerp_angle(visual.rotation.z, -lean * 0.10, delta * 7.0)
		if wreck_t > 0.0:
			visual.visible = int(wreck_t * 8.0) % 2 == 0
		else:
			visual.visible = GameState.camera_mode != "HOOD" or ai_skill > 0.0 or is_police
	for w in _spin_nodes:
		w.rotation.x = -_wheel_roll


func _prefix() -> String:
	return "p2_" if player_slot == 1 else ""


func _held(action_id: String) -> bool:
	if GameState.typing:
		return false
	if Input.is_action_pressed(_prefix() + action_id):
		return true
	if player_slot == 0:
		if action_id == "nitro" and GameState.nitro_touch:
			return true
		if action_id == "handbrake" and GameState.handbrake_touch:
			return true
		if action_id == "fire" and GameState.fire_touch:
			return true
	return false


func read_player_controls() -> Vector2:
	if GameState.typing:
		return Vector2.ZERO
	var p := _prefix()
	var throttle := Input.get_axis(p + "brake", p + "accelerate")
	var steer := Input.get_axis(p + "steer_right", p + "steer_left")
	if player_slot == 0 and not GameState.split_screen:
		if absf(throttle) < 0.08:
			throttle = Input.get_axis("p2_brake", "p2_accelerate")
		if absf(steer) < 0.08:
			steer = Input.get_axis("p2_steer_right", "p2_steer_left")
	if auto_throttle != 0.0:
		throttle = auto_throttle
	if player_slot == 0 and absf(throttle) < 0.08 and absf(steer) < 0.08 and Input.get_connected_joypads().size() > 0:
		var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
		var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		if absf(jx) > 0.25:
			steer = -jx
		if rt > 0.25 or lt > 0.25:
			throttle = clampf(rt, 0.0, 1.0) - clampf(lt, 0.0, 1.0)
	if player_slot == 0 and _use_touch and (absf(_touch_throttle) > 0.08 or absf(_touch_steer) > 0.08):
		throttle = _touch_throttle
		steer = -_touch_steer
	return Vector2(throttle, steer)


func wants_fire() -> bool:
	if not GameState.gun_enabled or wreck_t > 0.0 or fire_cd > 0.0:
		return false
	return _held("fire")


func muzzle() -> Vector3:
	var fx := -sin(heading)
	var fz := -cos(heading)
	return global_position + Vector3(fx, 0.95, fz) * 3.2


func _collect_wheels(n: Node) -> void:
	if n is Node3D:
		var nm := n.name.to_lower()
		if "wheel" in nm or "tire" in nm:
			_spin_nodes.append(n as Node3D)
	for c in n.get_children():
		_collect_wheels(c)
