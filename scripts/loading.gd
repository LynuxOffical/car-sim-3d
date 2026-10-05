extends Control

const UiKit := preload("res://scripts/ui_kit.gd")

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
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/world.tscn")
