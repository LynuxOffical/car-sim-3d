extends Node

signal bounty_changed(amount: int)
signal heat_changed(stars: float)
signal crime_reported(text: String)
signal weather_changed(label: String)

enum Mode { MENU, RACE, FREEPLAY, ROAM }

const HP_MAX := 100
const GUN_DAMAGE := 24
const GUN_COOLDOWN := 0.20
const BULLET_SPEED := 92.0
const BULLET_LIFE := 1.35
const WRECK_TIME := 3.2
const CHECKPOINT_COUNT := 4
const LAP_OPTIONS: Array[int] = [1, 3, 5, 7]
const OPPONENT_OPTIONS: Array[int] = [1, 2, 3, 4, 5]
const CAMERA_MODES: Array[String] = ["CHASE", "HOOD", "TOP"]
const STAT_TOP := {"max_speed": 159.0, "accel": 41.0, "steer": 2.90}
const QUALITY_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]
const TECHNO_CAR_ID := "phantom"
const TECHNO_ISLAND := 9

const WEATHERS := [
	{"name": "CLEAR", "grip": 1.00, "precip": "", "lightning": false, "wet": false, "sun": 1.0, "fog": 1.0},
	{"name": "RAIN", "grip": 0.82, "precip": "rain", "lightning": false, "wet": true, "sun": 0.42, "fog": 0.48},
	{"name": "STORM", "grip": 0.72, "precip": "rain", "lightning": true, "wet": true, "sun": 0.28, "fog": 0.32},
	{"name": "SNOW", "grip": 0.68, "precip": "snow", "lightning": false, "wet": false, "sun": 0.58, "fog": 0.42},
]

const VEHICLES := [
	{"id": "corolla", "name": "COROLLA GT", "tag": "balanced sedan", "kind": "car", "glb": "res://assets/cars/sedan.glb", "length": 4.5, "max_speed": 115.0, "accel": 30.0, "brake": 50.0, "steer": 2.35, "nitro": 0.7},
	{"id": "supra", "name": "SUPRA RZ", "tag": "rear-wing rocket", "kind": "car", "glb": "res://assets/cars/sedan-sports.glb", "length": 4.6, "max_speed": 139.0, "accel": 35.0, "brake": 52.0, "steer": 1.95, "nitro": 0.85},
	{"id": "yaris", "name": "YARIS LE", "tag": "limited edition pocket rocket", "kind": "car", "glb": "res://assets/cars/hatchback-sports.glb", "length": 3.9, "max_speed": 105.0, "accel": 33.0, "brake": 48.0, "steer": 2.75, "nitro": 0.75},
	{"id": "velocity", "name": "VELOCITY GT", "tag": "track-day missile", "kind": "car", "glb": "res://assets/cars/race.glb", "length": 4.2, "max_speed": 139.0, "accel": 38.0, "brake": 48.0, "steer": 1.85, "nitro": 1.0},
	{"id": "cruiser", "name": "CRUISER XL", "tag": "heavy street SUV", "kind": "car", "glb": "res://assets/cars/suv.glb", "length": 4.8, "max_speed": 108.0, "accel": 26.0, "brake": 55.0, "steer": 2.15, "nitro": 0.55},
	{"id": "cab", "name": "CITY CAB", "tag": "durable daily driver", "kind": "car", "glb": "res://assets/cars/taxi.glb", "length": 4.4, "max_speed": 112.0, "accel": 28.0, "brake": 50.0, "steer": 2.40, "nitro": 0.5},
	{"id": "vanish", "name": "VANISH V6", "tag": "getaway van", "kind": "car", "glb": "res://assets/cars/van.glb", "length": 5.2, "max_speed": 98.0, "accel": 24.0, "brake": 52.0, "steer": 2.50, "nitro": 0.6},
	{"id": "phantom", "name": "PHANTOM R", "tag": "future prototype", "kind": "car", "glb": "res://assets/cars/race-future.glb", "length": 4.3, "max_speed": 135.0, "accel": 36.0, "brake": 50.0, "steer": 1.90, "nitro": 1.05},
	{"id": "luxe", "name": "LUXE SUV", "tag": "executive hauler", "kind": "car", "glb": "res://assets/cars/suv-luxury.glb", "length": 5.0, "max_speed": 118.0, "accel": 27.0, "brake": 54.0, "steer": 2.05, "nitro": 0.58},
	{"id": "courier", "name": "COURIER", "tag": "express delivery", "kind": "car", "glb": "res://assets/cars/delivery.glb", "length": 5.4, "max_speed": 102.0, "accel": 25.0, "brake": 50.0, "steer": 2.20, "nitro": 0.4},
	{"id": "interceptor", "name": "INTERCEPTOR", "tag": "stolen black-and-white", "kind": "car", "glb": "res://assets/cars/police.glb", "length": 4.5, "max_speed": 128.0, "accel": 34.0, "brake": 52.0, "steer": 2.25, "nitro": 0.9},
	{"id": "rig", "name": "BIG RIG", "tag": "highway hauler", "kind": "car", "glb": "res://assets/cars/truck.glb", "length": 7.4, "max_speed": 92.0, "accel": 18.0, "brake": 55.0, "steer": 1.90, "nitro": 0.32},
	{"id": "medic", "name": "MEDIC UNIT", "tag": "city ambulance", "kind": "car", "glb": "res://assets/cars/ambulance.glb", "length": 5.6, "max_speed": 122.0, "accel": 32.0, "brake": 50.0, "steer": 2.20, "nitro": 0.7},
	{"id": "ladder", "name": "LADDER 12", "tag": "heavy fire truck", "kind": "car", "glb": "res://assets/cars/firetruck.glb", "length": 7.0, "max_speed": 88.0, "accel": 20.0, "brake": 55.0, "steer": 2.00, "nitro": 0.35},
	{"id": "dump", "name": "DUMP KING", "tag": "refuse rumbler", "kind": "car", "glb": "res://assets/cars/garbage-truck.glb", "length": 6.6, "max_speed": 86.0, "accel": 19.0, "brake": 54.0, "steer": 2.05, "nitro": 0.3},
	{"id": "oozi", "name": "OOZI KART", "tag": "arcade nitro kart", "kind": "kart", "glb": "res://assets/cars/kart-oozi.glb", "length": 3.2, "max_speed": 128.0, "accel": 42.0, "brake": 48.0, "steer": 3.10, "nitro": 1.25},
	{"id": "nitro1", "name": "NITRO S1", "tag": "1500cc sport bike", "kind": "bike", "glb": "", "length": 2.1, "max_speed": 198.0, "accel": 55.0, "brake": 48.0, "steer": 2.80, "nitro": 1.8},
	{"id": "hawk", "name": "STREET HAWK", "tag": "cafe racer", "kind": "bike", "glb": "", "length": 2.0, "max_speed": 176.0, "accel": 50.0, "brake": 46.0, "steer": 2.70, "nitro": 1.45},
	{"id": "raid", "name": "RAID 900", "tag": "dirt-legal supermoto", "kind": "bike", "glb": "", "length": 2.05, "max_speed": 164.0, "accel": 48.0, "brake": 50.0, "steer": 2.90, "nitro": 1.35},
	{"id": "specter", "name": "SPECTER EV", "tag": "silent streetfighter", "kind": "bike", "glb": "", "length": 2.05, "max_speed": 210.0, "accel": 62.0, "brake": 48.0, "steer": 2.65, "nitro": 1.9},
	{"id": "bagger", "name": "BAGGER KING", "tag": "touring cruiser", "kind": "bike", "glb": "", "length": 2.35, "max_speed": 152.0, "accel": 40.0, "brake": 52.0, "steer": 2.45, "nitro": 1.1},
]

const PAINTS := [
	{"name": "RACING RED", "color": Color(0.82, 0.1, 0.1)},
	{"name": "PEARL WHITE", "color": Color(0.92, 0.92, 0.94)},
	{"name": "MIDNIGHT BLACK", "color": Color(0.1, 0.1, 0.12)},
	{"name": "STREET BLUE", "color": Color(0.15, 0.35, 0.88)},
	{"name": "SUNBURST YELLOW", "color": Color(0.95, 0.8, 0.12)},
	{"name": "BLAZE ORANGE", "color": Color(0.93, 0.48, 0.1)},
	{"name": "RALLY GREEN", "color": Color(0.1, 0.45, 0.2)},
	{"name": "TITAN SILVER", "color": Color(0.68, 0.7, 0.74)},
	{"name": "NEON PINK", "color": Color(0.95, 0.2, 0.62)},
	{"name": "ROYAL PURPLE", "color": Color(0.42, 0.18, 0.72)},
	{"name": "SKY CYAN", "color": Color(0.2, 0.82, 0.9)},
	{"name": "ARMY MATTE", "color": Color(0.32, 0.36, 0.24)},
]

const NPC_GLBS: Array[String] = [
	"res://assets/cars/sedan.glb",
	"res://assets/cars/taxi.glb",
	"res://assets/cars/hatchback-sports.glb",
	"res://assets/cars/suv.glb",
	"res://assets/cars/van.glb",
	"res://assets/cars/delivery.glb",
	"res://assets/cars/truck.glb",
	"res://assets/cars/ambulance.glb",
]

var mode: Mode = Mode.MENU
var car_index: int = 0
var paint_index: int = 0
var race_island: int = -1
var quality: int = 2
var use_taa: bool = false
var split_screen: bool = false
var freeplay_split: bool = false
var fov: float = 68.0
var vsync: bool = true
var bounty: int = 0
var heat: float = 0.0
var identified: bool = false
var last_crime: String = ""
var weather_idx: int = 0
var weather_label: String = "CLEAR"
var weather_grip: float = 1.0
var nitro_touch: bool = false
var handbrake_touch: bool = false
var fire_touch: bool = false
var touch_enabled: bool = false
var grade_flash: float = 0.0
var gun_enabled: bool = false
var police_enabled: bool = true
var lap_option_idx: int = 1
var opponent_option_idx: int = 2
var camera_mode: String = "CHASE"
var race_time: float = 0.0
var cp_flash: float = 0.0
var kill_flash: float = 0.0
var kill_text: String = ""
var win_streak: int = 0
var chase_bonus: float = 0.0
var p2_car_index: int = 1
var p2_paint_index: int = 3
var typing := false
var busted := false
var bust_progress := 0.0
var tribute_hold := false
var techno_pending := false
var techno_seen := false

func _ready() -> void:
	quality = clampi(quality, 0, QUALITY_NAMES.size() - 1)
	touch_enabled = OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")
	apply_weather_idx(weather_idx)


func techno_combo() -> bool:
	if split_screen:
		return false
	if not gun_enabled:
		return false
	if mode != Mode.FREEPLAY:
		return false
	if race_island != TECHNO_ISLAND:
		return false
	return str(selected_car().get("id", "")).to_lower() == TECHNO_CAR_ID


func selected_car() -> Dictionary:
	return VEHICLES[clampi(car_index, 0, VEHICLES.size() - 1)]


func p2_car() -> Dictionary:
	return VEHICLES[clampi(p2_car_index, 0, VEHICLES.size() - 1)]


func selected_paint() -> Color:
	return PAINTS[clampi(paint_index, 0, PAINTS.size() - 1)]["color"]


func p2_paint() -> Color:
	return PAINTS[clampi(p2_paint_index, 0, PAINTS.size() - 1)]["color"]


func total_laps() -> int:
	return LAP_OPTIONS[clampi(lap_option_idx, 0, LAP_OPTIONS.size() - 1)]


func opponent_count() -> int:
	return OPPONENT_OPTIONS[clampi(opponent_option_idx, 0, OPPONENT_OPTIONS.size() - 1)]


func cycle_laps() -> void:
	lap_option_idx = (lap_option_idx + 1) % LAP_OPTIONS.size()


func cycle_opponents() -> void:
	opponent_option_idx = (opponent_option_idx + 1) % OPPONENT_OPTIONS.size()


func cycle_weather() -> void:
	apply_weather_idx((weather_idx + 1) % WEATHERS.size())


func cycle_quality() -> void:
	quality = (quality + 1) % QUALITY_NAMES.size()


func quality_name() -> String:
	return QUALITY_NAMES[clampi(quality, 0, QUALITY_NAMES.size() - 1)]


func apply_weather_idx(idx: int) -> void:
	weather_idx = clampi(idx, 0, WEATHERS.size() - 1)
	var w: Dictionary = WEATHERS[weather_idx]
	weather_grip = float(w.get("grip", 1.0))
	set_weather(str(w.get("name", "CLEAR")))


func weather() -> Dictionary:
	return WEATHERS[clampi(weather_idx, 0, WEATHERS.size() - 1)]


func cycle_camera() -> void:
	var i := CAMERA_MODES.find(camera_mode)
	camera_mode = CAMERA_MODES[(i + 1) % CAMERA_MODES.size()]


func reset_wanted() -> void:
	bounty = 0
	heat = 0.0
	identified = false
	last_crime = ""
	chase_bonus = 0.0
	kill_flash = 0.0
	cp_flash = 0.0
	busted = false
	bust_progress = 0.0
	bounty_changed.emit(bounty)
	heat_changed.emit(heat)


func add_crime(kind: String, cash: int, heat_add: float) -> void:
	bounty += cash
	heat = clampf(heat + heat_add, 0.0, 5.0)
	identified = true
	last_crime = kind
	bounty_changed.emit(bounty)
	heat_changed.emit(heat)
	crime_reported.emit(kind)


func decay_heat(delta: float) -> void:
	if heat <= 0.0:
		return
	heat = maxf(0.0, heat - delta * 0.03)
	if heat <= 0.05:
		heat = 0.0
		identified = bounty > 4000
	heat_changed.emit(heat)


func stars() -> int:
	return int(round(heat))


func set_weather(label: String) -> void:
	if label == weather_label:
		return
	weather_label = label
	weather_changed.emit(label)


func change_scene(path: String) -> void:
	call_deferred("_change_scene_now", path)


func _change_scene_now(path: String) -> void:
	var t := get_tree()
	if t:
		t.change_scene_to_file(path)
