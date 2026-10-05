extends CanvasLayer

var flash_rect: ColorRect
var _last_flash := -1.0

func _ready() -> void:
	layer = 8
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/nfs_grade.gdshader")
	overlay.material = mat
	add_child(overlay)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	add_child(flash_rect)


func _process(_delta: float) -> void:
	if flash_rect == null:
		return
	var f := GameState.grade_flash
	if is_equal_approx(f, _last_flash):
		return
	_last_flash = f
	flash_rect.color.a = clampf(f * 0.55, 0.0, 0.55)
