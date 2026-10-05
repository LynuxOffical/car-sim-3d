extends Node3D

const CarPaint := preload("res://scripts/car_paint.gd")

var goal_pos := Vector3.ZERO
var goal_rot := Vector3.ZERO
var speed_kmh := 0.0
var visual: Node3D
var tag: Label3D
var car_id := ""
var paint_index := -1

func _ready() -> void:
	tag = Label3D.new()
	tag.position = Vector3(0, 2.4, 0)
	tag.font_size = 48
	tag.modulate = Color(0.9, 0.95, 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(tag)
	goal_pos = global_position


func apply_net(d: Dictionary) -> void:
	goal_pos = Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.8)), float(d.get("z", 0.0)))
	goal_rot = Vector3(float(d.get("rx", 0.0)), float(d.get("ry", 0.0)), float(d.get("rz", 0.0)))
	speed_kmh = float(d.get("s", 0.0))
	if tag:
		tag.text = str(d.get("name", "RACER"))
	var mid := str(d.get("model", "corolla"))
	var pidx := int(d.get("color", 0))
	if mid != car_id or pidx != paint_index:
		car_id = mid
		paint_index = pidx
		_rebuild(mid, pidx)


func _rebuild(mid: String, pidx: int) -> void:
	if visual:
		visual.queue_free()
		visual = null
	var car: Dictionary = GameState.VEHICLES[0]
	for v in GameState.VEHICLES:
		if str(v.get("id")) == mid:
			car = v
			break
	var paint: Color = GameState.PAINTS[clampi(pidx, 0, GameState.PAINTS.size() - 1)]["color"]
	if str(car.get("kind")) == "bike":
		var style := "sport"
		if str(car.get("id")) == "raid":
			style = "dirt"
		elif str(car.get("id")) == "hawk":
			style = "cafe"
		elif str(car.get("id")) == "bagger":
			style = "cruiser"
		elif str(car.get("id")) == "specter":
			style = "naked"
		visual = VehicleFactory.make_bike(paint, style)
	else:
		var packed: PackedScene = load(str(car.get("glb", "")))
		if packed:
			visual = packed.instantiate()
			visual.rotation.y = PI
			add_child(visual)
			CarPaint.apply(visual, str(car.get("id")), paint, pidx, str(car.get("id")) == "interceptor", float(car.get("length", 4.5)))
			return
		visual = _box_car(paint)
	add_child(visual)


func _box_car(paint: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.6, 0.7, 3.4)
	mi.mesh = mesh
	mi.position.y = 0.5
	mi.material_override = Mats.solid(paint, 0.45, 0.2)
	return mi


func _process(delta: float) -> void:
	global_position = global_position.lerp(goal_pos, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, goal_rot.y, clampf(delta * 10.0, 0.0, 1.0))
	rotation.x = lerp_angle(rotation.x, goal_rot.x, clampf(delta * 6.0, 0.0, 1.0))
	rotation.z = lerp_angle(rotation.z, goal_rot.z, clampf(delta * 6.0, 0.0, 1.0))
