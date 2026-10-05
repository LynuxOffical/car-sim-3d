extends RefCounted

const PALETTE := "res://assets/cars/Textures/colormap.png"

static var _src: Image
static var _tex_cache: Dictionary = {}
static var _hue_cache: Dictionary = {}


static func apply(root: Node, car_id: String, paint: Color, paint_idx: int, police := false, length := 4.5) -> void:
	if root == null:
		return
	if root is Node3D:
		_fit_length(root as Node3D, length)
	if police:
		return
	var tex := texture_for(root, car_id, paint, paint_idx)
	if tex == null:
		_tint_fallback(root, paint)
		return
	_assign(root, tex)


static func texture_for(root: Node, car_id: String, paint: Color, paint_idx: int) -> Texture2D:
	var key := "%s_%d" % [car_id, paint_idx]
	if _tex_cache.has(key):
		return _tex_cache[key]
	if not _ensure_src():
		return null
	var hue := _body_hue(root, car_id)
	var painted := _recolor(paint, hue)
	var tex := ImageTexture.create_from_image(painted)
	_tex_cache[key] = tex
	return tex


static func _ensure_src() -> bool:
	if _src != null:
		return true
	var tex := load(PALETTE) as Texture2D
	if tex == null:
		return false
	_src = tex.get_image()
	if _src == null:
		return false
	if _src.is_compressed():
		_src.decompress()
	_src.convert(Image.FORMAT_RGBA8)
	return not _src.is_empty()


static func _recolor(paint: Color, body_h: float) -> Image:
	var img: Image = _src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var hgt: int = img.get_height()
	var vals: Array[float] = []
	for y in hgt:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.s < 0.30:
				continue
			var dh := minf(absf(c.h - body_h), 1.0 - absf(c.h - body_h))
			if dh < 0.048:
				vals.append(c.v)
	vals.sort()
	var body_v := 0.7
	if not vals.is_empty():
		body_v = maxf(0.12, vals[int(vals.size() / 2)])
	for y in hgt:
		for x in w:
			var c2: Color = img.get_pixel(x, y)
			if c2.s < 0.30:
				continue
			var dh2 := minf(absf(c2.h - body_h), 1.0 - absf(c2.h - body_h))
			if dh2 >= 0.048:
				continue
			var shade := clampf(c2.v / body_v, 0.35, 1.45)
			img.set_pixel(x, y, Color.from_hsv(paint.h, paint.s, clampf(paint.v * shade, 0.02, 1.0), c2.a))
	return img


static func _body_hue(root: Node, car_id: String) -> float:
	if _hue_cache.has(car_id):
		return _hue_cache[car_id]
	var bins := {}
	_collect_hues(root, bins)
	var best_h := 0.08
	var best_w := -1.0
	for k in bins.keys():
		if float(bins[k]) > best_w:
			best_w = float(bins[k])
			best_h = float(k)
	_hue_cache[car_id] = best_h
	return best_h


static func _collect_hues(n: Node, bins: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := mi.name.to_lower()
		if "wheel" in nm or "tire" in nm or "glass" in nm or "window" in nm:
			pass
		elif mi.mesh and _ensure_src():
			_sample_mesh(mi, bins)
	for c in n.get_children():
		_collect_hues(c, bins)


static func _sample_mesh(mi: MeshInstance3D, bins: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh.get_surface_count() < 1:
		return
	var arr: Array = mesh.surface_get_arrays(0)
	if arr.size() <= Mesh.ARRAY_TEX_UV:
		return
	var uvs: Variant = arr[Mesh.ARRAY_TEX_UV]
	if uvs == null:
		return
	var w: int = _src.get_width()
	var hgt: int = _src.get_height()
	var uv_count: int = uvs.size()
	var step := maxi(1, int(uv_count / 80.0))
	for i in range(0, uv_count, step):
		var uv: Vector2 = uvs[i]
		var px := clampi(int(fposmod(uv.x, 1.0) * float(w - 1)), 0, w - 1)
		var py := clampi(int(fposmod(uv.y, 1.0) * float(hgt - 1)), 0, hgt - 1)
		var c: Color = _src.get_pixel(px, py)
		if c.s < 0.35:
			continue
		var key := snappedf(c.h, 0.04)
		bins[key] = float(bins.get(key, 0.0)) + 1.0


static func _assign(n: Node, tex: Texture2D) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := mi.name.to_lower()
		if not ("wheel" in nm or "tire" in nm):
			var src_mat: Material = mi.get_active_material(0)
			var mat: StandardMaterial3D
			if src_mat is StandardMaterial3D:
				mat = (src_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE
			mat.metallic = 0.18
			mat.roughness = 0.38
			mi.material_override = mat
	for c in n.get_children():
		_assign(c, tex)


static func _tint_fallback(n: Node, paint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := mi.name.to_lower()
		if not ("wheel" in nm or "tire" in nm or "glass" in nm):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = paint
			mat.metallic = 0.22
			mat.roughness = 0.4
			mi.material_override = mat
	for c in n.get_children():
		_tint_fallback(c, paint)


static func _fit_length(root: Node3D, target: float) -> void:
	root.scale = Vector3.ONE
	var aabb := _aabb(root)
	var long := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if long < 0.05:
		return
	root.scale = Vector3.ONE * (target / long)


static func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	if n is VisualInstance3D:
		box = (n as VisualInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		var child := _aabb(c)
		if child.size.length() < 0.001:
			continue
		if first:
			box = child
			first = false
		else:
			box = box.merge(child)
	return box
