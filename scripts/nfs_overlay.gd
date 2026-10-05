extends CanvasLayer

var overlay: ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	layer = 8
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color.WHITE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/nfs_grade.gdshader")
	overlay.material = mat
	add_child(overlay)


func _process(_delta: float) -> void:
	if mat:
		mat.set_shader_parameter("flash", GameState.grade_flash)
