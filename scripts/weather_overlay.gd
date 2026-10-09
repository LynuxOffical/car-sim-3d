extends ColorRect

var menu_bolts := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/weather_fx.gdshader")
	material = mat


func _process(_delta: float) -> void:
	var sm := material as ShaderMaterial
	if sm == null:
		return
	var label := GameState.weather_label
	if label == "" or label == "CLEAR":
		label = str(GameState.weather().get("name", "CLEAR"))
	var rain := 0.0
	var storm := 0.0
	var snow := 0.0
	var dust := 0.0
	match label:
		"STORM":
			rain = 1.0
			storm = 1.0
		"RAIN":
			rain = 0.78
		"SNOW":
			snow = 1.0
		"DUST STORM", "ASH":
			dust = 1.0
	sm.set_shader_parameter("rain", rain)
	sm.set_shader_parameter("storm", storm)
	sm.set_shader_parameter("snow", snow)
	sm.set_shader_parameter("dust", dust)
	var bolt := clampf(GameState.grade_flash * 2.4, 0.0, 1.0)
	if menu_bolts and storm > 0.5 and bolt <= 0.01:
		var t := Time.get_ticks_msec() * 0.001
		var h := fposmod(sin(floor(t * 1.55) * 12.9898) * 43758.5453, 1.0)
		if h > 0.86:
			bolt = 0.65 * (1.0 - fposmod(t * 5.0, 1.0))
	sm.set_shader_parameter("lightning", bolt)
