extends Control

## NFS HUD from the Panda3D build: gauge, minimap, laps, bounty / HP.

const MAX_DIAL_KMH := 500.0

var player: PlayerCar
var world: IslandWorld
var speed_lab: Label
var lap_lab: Label
var bounty_lab: Label
var heat_lab: Label
var cp_lab: Label
var streak_lab: Label
var cam_lab: Label
var banner: Label
var name_lab: Label
var gauge: Control
var map: Control
var nitro_fill: ColorRect
var hud_root: Control
var kmh_show := 0.0

func setup(p: PlayerCar, w: IslandWorld) -> void:
	player = p
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)
	_gauge()
	_minimap()
	lap_lab = _lab(Vector2(28, 18), 22)
	name_lab = _lab(Vector2(28, 18), 22)
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lab.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	name_lab.offset_left = -280
	name_lab.offset_right = -24
	name_lab.offset_top = 18
	name_lab.offset_bottom = 48
	name_lab.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	cp_lab = _lab(Vector2(28, 48), 18)
	cp_lab.add_theme_color_override("font_color", Color(0.55, 0.95, 0.85))
	streak_lab = _lab(Vector2(28, 48), 18)
	streak_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	streak_lab.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	streak_lab.offset_left = -280
	streak_lab.offset_right = -24
	streak_lab.offset_top = 48
	streak_lab.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	bounty_lab = _lab(Vector2(28, 86), 20)
	bounty_lab.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
	heat_lab = _lab(Vector2(28, 112), 18)
	heat_lab.add_theme_color_override("font_color", Color(1.0, 0.35, 0.30))
	cam_lab = _lab(Vector2(28, 0), 16)
	cam_lab.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cam_lab.anchor_left = 1.0
	cam_lab.anchor_top = 1.0
	cam_lab.offset_left = -200
	cam_lab.offset_top = -36
	cam_lab.offset_right = -24
	cam_lab.offset_bottom = -12
	cam_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -280
	banner.offset_right = 280
	banner.offset_top = -40
	banner.offset_bottom = 40
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 48)
	banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 3)
	hud_root.add_child(banner)
	var nitro_lab := _lab(Vector2(28, 138), 13)
	nitro_lab.text = "NITRO"
	nitro_lab.add_theme_color_override("font_color", Color(0.70, 0.82, 0.90))
	var nitro := ColorRect.new()
	nitro.color = Color(0.02, 0.03, 0.05, 0.70)
	nitro.position = Vector2(28, 158)
	nitro.size = Vector2(180, 12)
	hud_root.add_child(nitro)
	nitro_fill = ColorRect.new()
	nitro_fill.color = Color(0.2, 0.75, 1.0)
	nitro_fill.position = Vector2(30, 160)
	nitro_fill.size = Vector2(176, 8)
	hud_root.add_child(nitro_fill)


func _gauge() -> void:
	gauge = Control.new()
	gauge.anchor_left = 1.0
	gauge.anchor_right = 1.0
	gauge.anchor_top = 1.0
	gauge.anchor_bottom = 1.0
	gauge.offset_left = -210
	gauge.offset_top = -210
	gauge.offset_right = -24
	gauge.offset_bottom = -24
	gauge.draw.connect(_draw_gauge)
	hud_root.add_child(gauge)
	speed_lab = Label.new()
	speed_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_lab.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	speed_lab.offset_left = -70
	speed_lab.offset_top = -48
	speed_lab.offset_right = 70
	speed_lab.offset_bottom = -12
	speed_lab.add_theme_font_size_override("font_size", 22)
	speed_lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	speed_lab.add_theme_constant_override("shadow_offset_x", 2)
	gauge.add_child(speed_lab)


func _draw_gauge() -> void:
	var c := gauge.size * 0.5
	var r := minf(gauge.size.x, gauge.size.y) * 0.40
	gauge.draw_circle(c, r + 10.0, Color(0.02, 0.02, 0.04, 0.62))
	var v := 0
	while v <= int(MAX_DIAL_KMH):
		var f := float(v) / MAX_DIAL_KMH
		var a := deg_to_rad(210.0 - 240.0 * f)
		var r0 := r * (0.74 if v % 100 == 0 else 0.84)
		var a0 := c + Vector2(cos(a), -sin(a)) * r0
		var a1 := c + Vector2(cos(a), -sin(a)) * r * 0.93
		gauge.draw_line(a0, a1, Color(1, 1, 1, 0.9), 2.5)
		v += 50
	var nf := clampf(kmh_show / MAX_DIAL_KMH, 0.0, 1.0)
	var ang := deg_to_rad(210.0 - 240.0 * nf)
	var tip := c + Vector2(cos(ang), -sin(ang)) * r * 0.80
	gauge.draw_line(c, tip, Color(0.95, 0.15, 0.15), 4.0)
	gauge.draw_circle(c, 6.0, Color(0.9, 0.9, 0.88))


func _minimap() -> void:
	map = Control.new()
	map.anchor_left = 0.0
	map.anchor_right = 0.0
	map.anchor_top = 1.0
	map.anchor_bottom = 1.0
	map.offset_left = 20
	map.offset_top = -196
	map.offset_right = 196
	map.offset_bottom = -20
	map.custom_minimum_size = Vector2(176, 176)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.draw.connect(_draw_map)
	hud_root.add_child(map)


func _draw_map() -> void:
	if map.size.x < 8.0 or map.size.y < 8.0:
		return
	map.draw_rect(Rect2(Vector2.ZERO, map.size), Color(0.03, 0.04, 0.07, 0.80))
	map.draw_rect(Rect2(Vector2.ZERO, map.size), Color(1, 1, 1, 0.12), false, 1.5)
	if world == null or world.wps2.is_empty():
		return
	var pts: Array = world.wps2
	if world.roam and player and not world.island_wps.is_empty():
		var ii := world.nearest_island(player.global_position)
		ii = clampi(ii, 0, world.island_wps.size() - 1)
		pts = world.island_wps[ii]
	if pts.is_empty():
		return
	var minp: Vector2 = pts[0]
	var maxp: Vector2 = pts[0]
	for p in pts:
		var pv: Vector2 = p
		minp.x = minf(minp.x, pv.x)
		minp.y = minf(minp.y, pv.y)
		maxp.x = maxf(maxp.x, pv.x)
		maxp.y = maxf(maxp.y, pv.y)
	var span := maxf(24.0, maxf(maxp.x - minp.x, maxp.y - minp.y))
	var pad := 14.0
	var map_scale := (minf(map.size.x, map.size.y) - pad * 2.0) / span
	var prev := Vector2.ZERO
	var first := Vector2.ZERO
	var step := 2 if pts.size() > 80 else 1
	var drawn := 0
	for i in range(0, pts.size(), step):
		var xy := _map_xy(pts[i], minp, map_scale, pad)
		if drawn == 0:
			first = xy
		else:
			map.draw_line(prev, xy, Color(0.95, 0.95, 0.98, 0.85), 2.5)
		prev = xy
		drawn += 1
	if drawn > 1:
		map.draw_line(prev, first, Color(0.95, 0.95, 0.98, 0.85), 2.5)
	var host := player.get_parent() if player else get_parent()
	if host == null:
		return
	for n in host.get_children():
		if n is ArcadeCar:
			var car := n as ArcadeCar
			var me := _map_xy(Vector2(car.global_position.x, car.global_position.z), minp, map_scale, pad)
			if car == player:
				map.draw_circle(me, 6.0, Color(1, 1, 1))
			var col := Color(0.25, 0.45, 0.95) if car.is_police else (Color(1.0, 0.35, 0.2) if car == player else Color(0.9, 0.9, 0.55))
			map.draw_circle(me, 4.0 if car == player else 3.0, col)


func _map_xy(p: Vector2, minp: Vector2, map_scale: float, pad: float) -> Vector2:
	return Vector2(
		pad + (p.x - minp.x) * map_scale,
		map.size.y - (pad + (p.y - minp.y) * map_scale)
	)


func _lab(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	hud_root.add_child(l)
	return l


func _process(_delta: float) -> void:
	if player == null:
		return
	kmh_show = player.speed_kmh
	speed_lab.text = "%d km/h" % int(kmh_show)
	gauge.queue_redraw()
	name_lab.text = player.display_name
	var room := ""
	if Lan.active:
		room = "   ROOM LAN"
	elif Net.online and Net.room != "":
		room = "   ROOM %s" % Net.room
	if GameState.mode == GameState.Mode.RACE:
		var total := GameState.total_laps()
		var racers := 0
		var host := player.get_parent() if player else get_parent()
		if host:
			for n in host.get_children():
				if n is ArcadeCar and not (n as ArcadeCar).is_police:
					racers += 1
		lap_lab.text = "LAP %d/%d   POS %d/%d%s" % [clampi(player.lap, 1, total), total, player.race_pos, maxi(racers, 1), room]
		cp_lab.text = "CP %d/%d" % [player.checkpoints_hit, GameState.CHECKPOINT_COUNT]
	elif GameState.gun_enabled:
		lap_lab.text = "LAP %d   GUN COMBAT%s" % [maxi(player.lap, 1), room]
		cp_lab.text = ""
	else:
		var tag := "ROAM WORLD" if GameState.mode == GameState.Mode.ROAM else "FREE PLAY"
		lap_lab.text = "LAP %d   %s%s" % [maxi(player.lap, 1), tag, room]
		cp_lab.text = ""
	if GameState.gun_enabled:
		bounty_lab.text = "HP  %d    KILLS  %d" % [clampi(player.hp, 0, GameState.HP_MAX), player.kills]
		if player.wreck_t > 0.0:
			heat_lab.text = "WRECKED"
		elif GameState.kill_flash > 0.0:
			heat_lab.text = GameState.kill_text
		else:
			heat_lab.text = ""
	elif GameState.mode != GameState.Mode.RACE and GameState.police_enabled:
		bounty_lab.text = "BOUNTY  $%s" % _comma(GameState.bounty)
		var stars := ""
		for i in 5:
			stars += "*" if i < GameState.stars() else "."
		heat_lab.text = "HEAT  " + stars
		if GameState.bust_progress > 0.12 and not GameState.busted:
			heat_lab.text += "   BUSTING  %d%%" % int(GameState.bust_progress * 100.0)
			heat_lab.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
		else:
			heat_lab.add_theme_color_override("font_color", Color(1.0, 0.35, 0.30))
	else:
		bounty_lab.text = ""
		heat_lab.text = ""
	streak_lab.text = ("WIN STREAK x%d" % GameState.win_streak) if GameState.win_streak > 0 else ""
	cam_lab.text = "" if GameState.touch_enabled else ("C  %s" % GameState.camera_mode)
	if GameState.race_time < 0.0:
		banner.text = str(ceili(-GameState.race_time))
	elif GameState.race_time < 1.0:
		banner.text = "GO!"
	elif player.finished or (GameState.mode == GameState.Mode.RACE and player.lap > GameState.total_laps()):
		banner.text = "FINISHED  -  P%d" % player.race_pos
	elif player.wreck_t > 0.0 and GameState.gun_enabled:
		banner.text = "WRECKED"
	elif GameState.kill_flash > 0.6:
		banner.text = GameState.kill_text
	elif GameState.cp_flash > 0.0:
		banner.text = "CHECKPOINT"
	else:
		banner.text = ""
	nitro_fill.size.x = 176.0 * player.nitro_tank
	nitro_fill.color = Color(1.0, 0.55, 0.15) if player.nitro_active else Color(0.2, 0.75, 1.0)
	if map:
		map.queue_redraw()


func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		if c > 0 and c % 3 == 0:
			out = "," + out
		out = s[i] + out
		c += 1
	return out
