extends Node3D
## Outil de développement (hors jeu) : affiche une scène de carte avec la caméra
## isométrique, l'ambiance jour/nuit et les astres de Game3D, un mannequin pour l'échelle,
## puis enregistre une capture PNG et quitte. Sert à régler le décor des cartes sans
## serveur.
##
## Usage :
##   Godot_console.exe --path . res://tools/map_preview/MapPreview.tscn -- \
##       --map=res://scenes/maps/Orée_de_la_forêt.tscn --at=225,140 --time=day \
##       --size=16 --yaw=0 --out=C:/tmp/oree.png
## --time : day (13h), dusk (21h30), night (1h) ; --size : taille de la caméra orthographique
## (zoom, 6..30 en jeu) ; --top : vue du dessus de toute la carte (plan) ; --hero=0 : sans
## mannequin ; --portals=0 : sans effet de portail. Les portails (marqueurs PortalMarker3D) reçoivent l'effet PortalVfx du jeu.
## Sans --out, la scène reste ouverte.

const CHARACTER_SCENE := preload("res://scenes/game/entities/Character.tscn")
const PORTAL_MARKER_SCRIPT := preload("res://map_objects/PortalMarker3D.gd")
const CAMERA_DISTANCE := 60.0
## Reprises de Game3D (ambiance jour/nuit).
const NIGHT_BACKGROUND_COLOR := Color(0.04, 0.05, 0.11, 1.0)
const NIGHT_AMBIENT_COLOR := Color(0.16, 0.18, 0.30, 1.0)
const NIGHT_AMBIENT_ENERGY := 0.22
const NIGHT_SUN_ENERGY := 0.05
const NIGHT_SUN_COLOR := Color(0.55, 0.60, 0.85, 1.0)
const DAY_BACKGROUND_COLOR := Color(0.29, 0.33, 0.40, 1.0)
const DAY_AMBIENT_COLOR := Color(0.55, 0.58, 0.65, 1.0)
const DAY_AMBIENT_ENERGY := 0.7
const DAY_SUN_ENERGY := 1.15
const DAY_SUN_COLOR := Color(1.0, 0.96, 0.88, 1.0)
const MOON_MAX_ENERGY := 0.35

var _map_path := "res://scenes/maps/Orée_de_la_forêt.tscn"
var _at := Vector2(225, 140)
var _time := "day"
var _size := 16.0
var _yaw := 0.0
var _out := ""
var _top := false
var _hero := true
var _portals := true
var _frames := 0
var _camera: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var value := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"map": _map_path = value
			"at":
				var p := value.split(",")
				_at = Vector2(float(p[0]), float(p[1]))
			"time": _time = value
			"size": _size = float(value)
			"yaw": _yaw = deg_to_rad(float(value))
			"out": _out = value
			"top": _top = true
			"hero": _hero = value != "0"
			"portals": _portals = value != "0"
	var t0 := Time.get_ticks_msec()
	var map: Node3D = (load(_map_path) as PackedScene).instantiate()
	print("MapPreview: scène chargée en %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	add_child(map)
	print("MapPreview: carte prête (_ready) en %d ms" % (Time.get_ticks_msec() - t0))
	# Effet de portail tel que Game3D le pose (PortalAppeared) sur chaque marqueur de portail.
	for marker in map.find_children("*", "Marker3D", true, false):
		if _portals and marker.get_script() == PORTAL_MARKER_SCRIPT:
			var vfx := PortalVfx.new()
			add_child(vfx)
			vfx.global_position = (marker as Node3D).global_position

	var t: float = {"day": 1.0, "dusk": 0.35, "night": 0.0}.get(_time, 1.0)
	var minutes: float = {"day": 13 * 60, "dusk": 21 * 60 + 30, "night": 60}.get(_time, 780)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = NIGHT_BACKGROUND_COLOR.lerp(DAY_BACKGROUND_COLOR, t)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(DAY_AMBIENT_COLOR, t)
	env.environment.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, t)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := _directional(lerpf(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, t), NIGHT_SUN_COLOR.lerp(DAY_SUN_COLOR, t))
	sun.basis = Basis.looking_at(_celestial_direction(clampf((minutes - 420.0) / 900.0, 0.0, 1.0)), Vector3.FORWARD)
	var moon := _directional((1.0 - t) * MOON_MAX_ENERGY, Color(0.75, 0.8, 1.0))
	moon.basis = Basis.looking_at(_celestial_direction(clampf(fposmod(minutes - 1320.0, 1440.0) / 540.0, 0.0, 1.0)), Vector3.FORWARD)
	get_tree().call_group(LampPost.NIGHT_GROUP, "set_night_factor", 1.0 - t)

	var hero_pos := Vector3(_at.x, 0.0, _at.y)
	if _hero and not _top:
		var hero: Node3D = CHARACTER_SCENE.instantiate()
		add_child(hero)
		hero.position = hero_pos
		hero.rotation.y = PI * 0.25
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = 400.0
	add_child(_camera)
	if _top:
		# Cadrage sur toute la carte (dimensions lues sur le GridMap "Terrain").
		var extent := _grid_extent(map)
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var aspect := viewport_size.x / viewport_size.y
		_camera.size = maxf(extent.y, extent.x / aspect) * 1.05
		_camera.far = 500.0
		_camera.position = Vector3(extent.x / 2.0, 200, extent.y / 2.0)
		_camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	else:
		_camera.size = _size
		_camera.near = 20.0
		var base := Vector3.ONE.normalized() * CAMERA_DISTANCE
		var radius := Vector2(base.x, base.z).length()
		var angle := atan2(base.z, base.x) + _yaw
		_camera.position = hero_pos + Vector3(radius * cos(angle), base.y, radius * sin(angle))
		_camera.look_at(hero_pos, Vector3.UP)
	_camera.current = true
	var veil := MapBoundsVeil.new()
	_camera.add_child(veil)
	veil.set_map_size(_grid_extent(map))
	RenderingServer.global_shader_parameter_set(&"player_world_position", hero_pos if _hero else Vector3(0, -1000, 0))
	RenderingServer.global_shader_parameter_set(&"main_camera_direction", -_camera.global_basis.z)


## Dimensions de la carte (tuiles) lues sur son GridMap "Terrain".
func _grid_extent(map: Node3D) -> Vector2:
	var grid := map.get_node_or_null("Terrain") as GridMap
	if grid == null:
		return Vector2(450, 270)
	var extent := Vector2.ZERO
	for cell in grid.get_used_cells():
		extent = extent.max(Vector2(cell.x + 1, cell.z + 1))
	return extent


func _directional(energy: float, color: Color) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_energy = energy
	light.light_color = color
	light.shadow_enabled = energy > 0.03
	light.directional_shadow_max_distance = 110.0
	add_child(light)
	return light


func _celestial_direction(frac: float) -> Vector3:
	var azimuth := deg_to_rad(lerpf(90.0, -90.0, frac))
	var elevation := deg_to_rad(sin(frac * PI) * 78.0)
	return -Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames <= 3 or _frames % 10 == 0:
		print("MapPreview: frame %d à %d ms" % [_frames, Time.get_ticks_msec()])
	if _out.is_empty() or _frames < 40:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	get_tree().quit()
