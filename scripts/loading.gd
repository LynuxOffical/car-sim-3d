extends Control

const UiKit := preload("res://scripts/ui_kit.gd")

var _ticks := 0

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.18, 0.24, 0.28)
	add_child(bg)
	var l := UiKit.shadow_label("Loading race…", 32, Color(0.92, 0.95, 0.9))
	l.position = Vector2(64, 280)
	add_child(l)
	var s := UiKit.shadow_label("Kenney cars, circuit walls, weather, guns.", 18, Color(0.8, 0.86, 0.82))
	s.position = Vector2(64, 330)
	add_child(s)
	set_process(true)


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks < 2:
		return
	set_process(false)
	var t := get_tree()
	if t:
		t.change_scene_to_file("res://scenes/world.tscn")
