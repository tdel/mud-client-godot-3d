extends WindowFrame
## Carte (touche M), façon carte de Tolkien — parchemin aux bords brûlés, encre sépia, forêts
## en petits arbres, routes pavées cernées d'un double trait. Deux vues :
##  - REGION : une carte entière, à l'échelle (une case = un mètre), avec ses téléporteurs
##    et la position du joueur. S'ouvre sur la carte courante ; un clic sur un téléporteur
##    affiche la région de destination.
##  - WORLD : toutes les régions à leur place (MapAtlas.WORLD_ORIGINS), reliées par des routes,
##    monts, collines et forêts dans l'entre-deux. Clic droit (ou molette arrière) sur une
##    région pour y arriver en dézoomant ; une région survolée s'éclaire, un clic gauche (ou
##    molette avant) zoome dessus et l'affiche en vue REGION.
## Fenêtre redimensionnable par le coin bas-droit (%Grip) : la carte garde ses proportions et
## se cale au mieux dans le parchemin ; la taille est mémorisée dans user://windows.cfg comme
## la position (voir WindowFrame).
##
## Le fond (parchemin + terrain) est dessiné par world_map.gdshader à partir de deux textures
## de masques (une texel par case en REGION, par MapAtlas.WORLD_TEXEL mètres en WORLD) : net à
## toutes les tailles sans régénérer d'image. Les annotations (cadre, titre, téléporteurs,
## routes, reliefs, noms, joueur, rose des vents, échelle) sont tracées par-dessus dans
## _on_overlay_draw. La carte courante vient de Game3D._rebuild_map (set_map) et
## Game3D._update_minimap (set_player, fenêtre ouverte seulement) ; les autres régions de
## MapAtlas, lu en tâche de fond à la première ouverture.

const SHADER := preload("res://scenes/game/hud/world_map.gdshader")
const SIZES_SECTION := "sizes"
const MIN_CANVAS_SIZE := Vector2(320, 220)
## Parchemin laissé autour de la carte (px) : le titre dans la marge du haut, l'aide en bas.
const MARGIN_TOP := 42.0
const MARGIN_SIDE := 22.0
const MARGIN_BOTTOM := 26.0
const GRIP_SIZE := 16.0
## Taille visée (px) d'un petit arbre de forêt : le pas de la grille d'arbres en découle.
const TREE_GLYPH_PX := 14.0
## Longueurs possibles de la barre d'échelle (m), voir _draw_scale_bar.
const SCALE_STEPS := [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
const WORLD_TITLE := "Carte du monde"
const ZOOM_DURATION := 0.5
## Zone de survol minimale (px) d'une petite région sur la carte du monde.
const MIN_HIT_PX := 26.0
const PORTAL_RADIUS := 7.0

const INK := Color(0.24, 0.15, 0.08)
const INK_RED := Color(0.52, 0.12, 0.07)
const ROAD_INK := Color(0.50, 0.30, 0.13)
const PORTAL_INK := Color(0.15, 0.30, 0.52)
const PORTAL_FILL := Color(0.72, 0.83, 0.88)
const PAPER := Color(0.92, 0.85, 0.68)
## Aplat des monts et collines : ton moyen du parchemin, pour masquer ce qui passe derrière.
const RELIEF_FILL := Color(0.87, 0.78, 0.59, 0.94)

enum View { REGION, WORLD }

var _canvas: ColorRect
var _overlay: Control
## Calque du seul marqueur du joueur, redessiné à chaque pas sans retracer toute la carte.
var _marker: Control
var _veil: ColorRect
var _grip: Control
var _material: ShaderMaterial
var _label_font: SystemFont

var _atlas := MapAtlas.new()
var _view := View.REGION
var _world_tex_a: ImageTexture
var _world_tex_b: ImageTexture
## Cadrage (m) de la carte du monde en vue WORLD : toute la carte, ou une région en cours de zoom.
var _world_view := Rect2(0, 0, 1, 1)

## Carte courante, nom tel qu'envoyé par le serveur (= MapData.map_name de sa scène).
var _current_name := ""
## Données brutes de la carte courante (voir set_map), mises en vue par _region_view.
var _current_raw: Dictionary = {}
## Vues de région prêtes à afficher, par nom de carte : {name, title, size: Vector2i, tex_a,
## tex_b, portals: [{position: Vector2 (cases), target_map_name}], is_current}.
var _region_cache: Dictionary = {}
## Région affichée en vue REGION (une entrée de _region_cache), {} avant la première carte.
var _shown: Dictionary = {}

var _hovered_region := ""
var _hovered_portal := -1
var _transition: Tween
var _focus_tween: Tween
var _veil_tween: Tween

## null tant que Game3D n'a pas encore donné de position (voir set_player).
var _player_position = null
var _player_facing := Vector2.ZERO

var _canvas_size := Vector2(720, 460)
## Taille du parchemin propre à chaque vue (View -> Vector2), la carte du monde étant bien
## plus large qu'une région ; restaurée de user://windows.cfg au premier passage.
var _view_sizes: Dictionary = {}
var _resizing := false
var _resize_start_mouse := Vector2.ZERO
var _resize_start_size := Vector2.ZERO


func _ready() -> void:
	_label_font = SystemFont.new()
	_label_font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
	_label_font.font_italic = true
	_label_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("focus_amount", 0.0)
	_canvas = ColorRect.new()
	_canvas.name = "MapCanvas"
	_canvas.material = _material
	_canvas.custom_minimum_size = _canvas_size
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.mouse_exited.connect(_set_hover.bind("", -1))
	get_body().add_child(_canvas)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_on_overlay_draw)
	_canvas.add_child(_overlay)

	_marker = Control.new()
	_marker.name = "PlayerMarker"
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.draw.connect(_on_marker_draw)
	_canvas.add_child(_marker)

	# Voile de parchemin qui adoucit le passage d'une vue à l'autre (voir _flash_veil).
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(PAPER, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_veil)

	_grip = Control.new()
	_grip.name = "Grip"
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.tooltip_text = "Redimensionner"
	_grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_grip.offset_left = -GRIP_SIZE
	_grip.offset_top = -GRIP_SIZE
	_grip.draw.connect(_on_grip_draw)
	_grip.gui_input.connect(_on_grip_gui_input)
	_canvas.add_child(_grip)
	_canvas.resized.connect(_on_canvas_resized)

	super._ready()
	set_window_title("Carte")
	set_process(false)


func _exit_tree() -> void:
	_atlas.wait()


## Attend la fin de la lecture de l'atlas (voir _start_atlas), puis prépare la carte du monde.
func _process(_delta: float) -> void:
	if not _atlas.is_ready():
		return
	set_process(false)
	var world: Dictionary = _atlas.world
	if world.is_empty():
		return
	_world_tex_a = ImageTexture.create_from_image(world["mask_a"])
	_world_tex_b = ImageTexture.create_from_image(world["mask_b"])
	if _view == View.WORLD:
		_world_view = world["bounds"]
		_flash_veil(0.6)
		_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_M or get_viewport().gui_get_focus_owner() != null:
		return
	if visible:
		close_window()
	else:
		open()
	get_viewport().set_input_as_handled()


## Ouvre la carte sur la région courante.
func open() -> void:
	_start_atlas()
	_show_region(_current_name, false)
	show_window()


func close_window() -> void:
	if visible:
		_save_canvas_size()
	super.close_window()


## Appelé par Game3D._rebuild_map à chaque (changement de) carte. `terrain_grid` : noms de
## terrain [y][x] (Game3D._terrain_grid) ; `walkable_rows` : grille serveur, utilisée pour les
## cases sans terrain connu (carte sans scène) ; `portals` : téléporteurs lus sur la scène.
func set_map(map_name: String, width: int, height: int, terrain_grid: Array,
		walkable_rows: Array, portals: Array) -> void:
	_region_cache.erase(_current_name)
	_current_name = map_name
	_region_cache.erase(_current_name)
	_current_raw = {
		"size": Vector2i(maxi(width, 1), maxi(height, 1)),
		"terrain_grid": terrain_grid,
		"walkable_rows": walkable_rows,
		"portals": portals,
	}
	_player_position = null
	if visible:
		_show_region(_current_name, false)


## Appelé par Game3D._update_minimap à chaque frame tant que la fenêtre est ouverte, avec la
## position (cases) et la direction de regard au sol du joueur.
func set_player(tile_position: Vector2, facing: Vector2) -> void:
	if _player_position is Vector2 and (_player_position as Vector2).distance_squared_to(tile_position) < 0.0004 \
			and _player_facing.is_equal_approx(facing):
		return
	_player_position = tile_position
	_player_facing = facing
	_marker.queue_redraw()


# ---------------------------------------------------------------------------
# Régions et atlas
# ---------------------------------------------------------------------------

func _start_atlas() -> void:
	if not _atlas.is_started():
		_atlas.load_all_async(ZoneAssets3D.get_map_scene_paths())
		set_process(true)


## Vue de la région `map_name` (voir _region_cache) : la carte courante d'après les données de
## Game3D, les autres d'après l'atlas ; {} si inconnue ou atlas pas encore lu.
func _region_view(map_name: String) -> Dictionary:
	if _region_cache.has(map_name):
		return _region_cache[map_name]
	var view := {}
	if map_name == _current_name and not _current_raw.is_empty():
		var current_size: Vector2i = _current_raw["size"]
		var masks := MapAtlas.masks_from_grid(_current_raw["terrain_grid"], _current_raw["walkable_rows"],
				current_size.x, current_size.y)
		view = {"size": current_size, "masks": masks, "portals": _current_raw["portals"], "is_current": true}
	elif _atlas.is_loaded() and _atlas.regions.has(map_name):
		var region: Dictionary = _atlas.regions[map_name]
		var portals: Array = []
		for portal in region["portals"]:
			portals.append({
				"position": portal["position"],
				"target_map_name": ZoneAssets3D.get_map_name_by_id(portal["target_map_id"]),
			})
		view = {"size": region["size"], "masks": [region["mask_a"], region["mask_b"]], "portals": portals,
				"is_current": false}
	else:
		return {}
	var size: Vector2i = view["size"]
	view["name"] = map_name
	view["title"] = map_name.replace("_", " ")
	view["tex_a"] = MapAtlas.mask_texture(view["masks"][0], size.x, size.y)
	view["tex_b"] = MapAtlas.mask_texture(view["masks"][1], size.x, size.y)
	view.erase("masks")
	_region_cache[map_name] = view
	return view


## Affiche la région `map_name` en vue REGION (sans effet si elle n'est pas encore connue).
func _show_region(map_name: String, veil: bool) -> void:
	var view := _region_view(map_name)
	if view.is_empty() and not _shown.is_empty():
		return
	_stop_transition()
	_view = View.REGION
	_shown = view
	_set_hover("", -1)
	_resize_for_view()
	_apply_view()
	if veil:
		_flash_veil(0.65)


## Région -> carte du monde : part du cadrage de la région affichée et dézoome sur l'ensemble.
func _zoom_out() -> void:
	_set_hover("", -1)
	_view = View.WORLD
	_resize_for_view()
	if not _atlas.is_loaded():
		_apply_view()
		return
	var world_bounds: Rect2 = _atlas.world["bounds"]
	var region: Dictionary = _atlas.regions.get(_shown.get("name", ""), {})
	_world_view = _atlas.region_rect(region) if not region.is_empty() else world_bounds
	_apply_view()
	_flash_veil(0.5)
	_zoom_to(world_bounds, Callable())


## Carte du monde -> région : zoome sur son rectangle, puis bascule sur sa vue REGION.
func _zoom_in(map_name: String) -> void:
	var region: Dictionary = _atlas.regions.get(map_name, {})
	if region.is_empty():
		return
	_set_hover("", -1)
	_zoom_to(_atlas.region_rect(region), _show_region.bind(map_name, true))


func _zoom_to(target: Rect2, on_done: Callable) -> void:
	_stop_transition()
	var from := _world_view
	_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(_zoom_step.bind(from, target), 0.0, 1.0, ZOOM_DURATION)
	if on_done.is_valid():
		_transition.tween_callback(on_done)


## Taille interpolée en géométrique : le zoom paraît régulier du début à la fin.
func _zoom_step(t: float, from: Rect2, target: Rect2) -> void:
	var framed := Vector2(from.size.x * pow(target.size.x / from.size.x, t),
			from.size.y * pow(target.size.y / from.size.y, t))
	_world_view = Rect2(from.get_center().lerp(target.get_center(), t) - framed / 2.0, framed)
	_apply_view()


func _stop_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _is_transitioning() -> bool:
	return _transition != null and _transition.is_running()


func _flash_veil(alpha: float) -> void:
	if _veil_tween != null and _veil_tween.is_valid():
		_veil_tween.kill()
	_veil.color = Color(PAPER, alpha)
	_veil_tween = create_tween()
	_veil_tween.tween_property(_veil, "color:a", 0.0, 0.35).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Souris
# ---------------------------------------------------------------------------

func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return
	if not event is InputEventMouseButton:
		return
	# Relâchements compris : le clic droit ne doit pas finir dans la rotation caméra de Game3D.
	_canvas.accept_event()
	if not event.pressed:
		return
	if _is_transitioning():
		return
	match event.button_index:
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
			if _view == View.REGION:
				_zoom_out()
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP:
			if _view == View.WORLD and not _hovered_region.is_empty():
				_zoom_in(_hovered_region)
			elif _view == View.REGION and _hovered_portal >= 0 and event.button_index == MOUSE_BUTTON_LEFT:
				_show_region(_portal_target(_shown["portals"][_hovered_portal]), true)


func _update_hover(mouse: Vector2) -> void:
	if _is_transitioning():
		return
	var region_name := ""
	var portal_index := -1
	if _view == View.WORLD and _atlas.is_loaded() and _map_rect().has_point(mouse):
		var at := _to_canvas_inverse(mouse)
		var min_size := MIN_HIT_PX / _px_per_meter()
		var best_area := INF
		for region in _atlas.regions.values():
			var rect := _atlas.region_rect(region)
			rect = rect.grow_individual(maxf(0.0, (min_size - rect.size.x) / 2.0), maxf(0.0, (min_size - rect.size.y) / 2.0),
					maxf(0.0, (min_size - rect.size.x) / 2.0), maxf(0.0, (min_size - rect.size.y) / 2.0))
			if rect.has_point(at) and rect.get_area() < best_area:
				best_area = rect.get_area()
				region_name = region["name"]
	elif _view == View.REGION and not _shown.is_empty():
		var portals: Array = _shown["portals"]
		for i in portals.size():
			if _portal_target(portals[i]).is_empty():
				continue
			var label := _portal_label(portals[i], _map_rect())
			if _to_canvas(portals[i]["position"]).distance_to(mouse) <= PORTAL_RADIUS + 5.0 \
					or (label["rect"] as Rect2).grow(3.0).has_point(mouse):
				portal_index = i
	_set_hover(region_name, portal_index)


func _set_hover(region_name: String, portal_index: int) -> void:
	if region_name == _hovered_region and portal_index == _hovered_portal:
		return
	var region_changed := region_name != _hovered_region
	_hovered_region = region_name
	_hovered_portal = portal_index
	var clickable := not region_name.is_empty() or portal_index >= 0
	_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	if region_changed:
		if not region_name.is_empty():
			_update_focus_rect()
		if _focus_tween != null and _focus_tween.is_valid():
			_focus_tween.kill()
		var focus_from: float = _material.get_shader_parameter("focus_amount")
		_focus_tween = create_tween()
		_focus_tween.tween_method(_set_focus_amount, focus_from, 0.0 if region_name.is_empty() else 1.0, 0.18)
	_overlay.queue_redraw()


func _set_focus_amount(amount: float) -> void:
	_material.set_shader_parameter("focus_amount", amount)


## Destination d'un téléporteur affichable (région connue), ou "".
func _portal_target(portal: Dictionary) -> String:
	var target: String = portal.get("target_map_name", "")
	if target.is_empty() or not (target == _current_name or (_atlas.is_loaded() and _atlas.regions.has(target))):
		return ""
	return target


# ---------------------------------------------------------------------------
# Mise en page
# ---------------------------------------------------------------------------

func _available_rect() -> Rect2:
	var canvas := _canvas.size
	return Rect2(MARGIN_SIDE, MARGIN_TOP, maxf(canvas.x - MARGIN_SIDE * 2.0, 1.0),
			maxf(canvas.y - MARGIN_TOP - MARGIN_BOTTOM, 1.0))


## Taille (cases en REGION, mètres en WORLD) de ce qui est cadré dans le parchemin.
func _framed_size() -> Vector2:
	if _view == View.WORLD:
		return _world_view.size
	return Vector2(_shown.get("size", Vector2i.ONE))


## Rectangle (px, repère du parchemin) occupé par la carte : même échelle sur les deux axes.
func _map_rect() -> Rect2:
	var available := _available_rect()
	var framed := _framed_size().max(Vector2(0.01, 0.01))
	var scale := minf(available.size.x / framed.x, available.size.y / framed.y)
	var map_size := framed * scale
	return Rect2(available.position + (available.size - map_size) / 2.0, map_size)


## Pixels par case (REGION) ou par mètre (WORLD), les deux échelles étant 1 case = 1 m.
func _px_per_meter() -> float:
	return _map_rect().size.x / maxf(_framed_size().x, 0.01)


## Position sur la carte (cases en REGION, mètres du monde en WORLD) -> pixels du parchemin.
func _to_canvas(map_position: Vector2) -> Vector2:
	var origin := _world_view.position if _view == View.WORLD else Vector2.ZERO
	return _map_rect().position + (map_position - origin) * _px_per_meter()


func _to_canvas_inverse(canvas_position: Vector2) -> Vector2:
	var origin := _world_view.position if _view == View.WORLD else Vector2.ZERO
	return origin + (canvas_position - _map_rect().position) / _px_per_meter()


func _on_canvas_resized() -> void:
	_apply_view()


## Pousse au shader les masques et le cadrage de la vue courante, puis redessine.
func _apply_view() -> void:
	var px_per_meter := _px_per_meter()
	var frame := _map_rect()
	var tiles := Vector2(_shown.get("size", Vector2i.ONE))
	var px_per_tile := px_per_meter
	var terrain_rect := frame
	var clip := Rect2(-100000, -100000, 200000, 200000)
	if _view == View.WORLD:
		if _atlas.is_loaded() and _world_tex_a != null:
			var bounds: Rect2 = _atlas.world["bounds"]
			tiles = Vector2(_atlas.world["tiles"])
			px_per_tile = px_per_meter * MapAtlas.WORLD_TEXEL
			terrain_rect = Rect2(_to_canvas(bounds.position), bounds.size * px_per_meter)
			clip = frame
			_material.set_shader_parameter("mask_a", _world_tex_a)
			_material.set_shader_parameter("mask_b", _world_tex_b)
		else:
			clip = Rect2()
	elif not _shown.is_empty():
		_material.set_shader_parameter("mask_a", _shown["tex_a"])
		_material.set_shader_parameter("mask_b", _shown["tex_b"])
	else:
		clip = Rect2()
	# Pas de la grille d'arbres arrondi à une puissance de √2 : la densité de la forêt ne
	# "grouille" pas pendant un redimensionnement continu.
	var tree_cell := TREE_GLYPH_PX / maxf(px_per_tile, 0.01)
	tree_cell = maxf(pow(2.0, roundf(log(tree_cell) / log(2.0) * 2.0) / 2.0), 1.0)
	_material.set_shader_parameter("canvas_size", _canvas.size)
	_material.set_shader_parameter("map_rect", Vector4(terrain_rect.position.x, terrain_rect.position.y,
			terrain_rect.size.x, terrain_rect.size.y))
	_material.set_shader_parameter("map_tiles", tiles)
	_material.set_shader_parameter("px_per_tile", px_per_tile)
	_material.set_shader_parameter("tree_cell", tree_cell)
	_material.set_shader_parameter("clip_rect", Vector4(clip.position.x, clip.position.y, clip.size.x, clip.size.y))
	_update_focus_rect()
	_overlay.queue_redraw()
	_marker.queue_redraw()


func _update_focus_rect() -> void:
	if _view != View.WORLD or _hovered_region.is_empty() or not _atlas.regions.has(_hovered_region):
		return
	var rect := _atlas.region_rect(_atlas.regions[_hovered_region])
	var top_left := _to_canvas(rect.position)
	var size := rect.size * _px_per_meter()
	_material.set_shader_parameter("focus_rect", Vector4(top_left.x, top_left.y, size.x, size.y))


func _max_canvas_size() -> Vector2:
	# Place prise par le cadre de fenêtre (barre de titre, bordures) autour du parchemin.
	var chrome := size - _canvas.size if visible else Vector2(20, 40)
	return (get_viewport_rect().size - chrome - Vector2(8, 8)).max(MIN_CANVAS_SIZE)


## Applique la taille de parchemin de la vue courante ; la fenêtre garde son centre et reste
## entière à l'écran quand elle change de taille en passant d'une vue à l'autre.
func _resize_for_view() -> void:
	if not _view_sizes.has(_view):
		_view_sizes[_view] = _restored_canvas_size(_view)
	var wanted: Vector2 = _view_sizes[_view]
	if wanted.is_equal_approx(_canvas_size) and _canvas.custom_minimum_size.is_equal_approx(wanted):
		return
	var center := get_global_rect().get_center()
	_set_canvas_size(wanted)
	if visible:
		var viewport_size := get_viewport_rect().size
		global_position = (center - size / 2.0).clamp(Vector2.ZERO, (viewport_size - size).max(Vector2.ZERO))


func _set_canvas_size(wanted: Vector2) -> void:
	_canvas_size = wanted.clamp(MIN_CANVAS_SIZE, _max_canvas_size()).round()
	_view_sizes[_view] = _canvas_size
	_canvas.custom_minimum_size = _canvas_size
	# Rétrécir : WindowFrame._fit_to_content ne suit que les agrandissements du contenu.
	size = Vector2.ZERO
	_fit_to_content()


func _on_grip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resizing = true
			_resize_start_mouse = get_global_mouse_position()
			_resize_start_size = _canvas_size
			_bring_to_front()
		elif _resizing:
			_resizing = false
			_save_canvas_size()
		_grip.accept_event()
	elif event is InputEventMouseMotion and _resizing:
		_set_canvas_size(_resize_start_size + get_global_mouse_position() - _resize_start_mouse)
		_grip.accept_event()


func _size_key(view: View) -> String:
	return name if view == View.REGION else "%sWorld" % name


## Taille mémorisée pour `view`, sinon la carte entière dans ~70 % de l'écran (85 % de large
## pour la carte du monde).
func _restored_canvas_size(view: View) -> Vector2:
	var config := WindowFrame._positions_config()
	if persist_positions and config.has_section_key(SIZES_SECTION, _size_key(view)):
		var saved = config.get_value(SIZES_SECTION, _size_key(view))
		if saved is Vector2:
			return saved
	var framed := Vector2(_current_raw.get("size", Vector2i(3, 2)))
	var share := Vector2(0.62, 0.7)
	if view == View.WORLD:
		framed = (_atlas.world["bounds"] as Rect2).size if _atlas.is_loaded() else Vector2(2.4, 1.0)
		share = Vector2(0.85, 0.75)
	var margins := Vector2(MARGIN_SIDE * 2.0, MARGIN_TOP + MARGIN_BOTTOM)
	var available := get_viewport_rect().size * share - margins
	var scale := minf(available.x / framed.x, available.y / framed.y)
	return framed * scale + margins


func _save_canvas_size() -> void:
	if not persist_positions:
		return
	var config := WindowFrame._positions_config()
	for view in _view_sizes:
		config.set_value(SIZES_SECTION, _size_key(view), _view_sizes[view])
	config.save(POSITIONS_PATH)


# ---------------------------------------------------------------------------
# Annotations
# ---------------------------------------------------------------------------

func _on_overlay_draw() -> void:
	var rect := _map_rect()
	if _view == View.WORLD:
		_draw_world(rect)
	else:
		_draw_region(rect)
	# Double filet d'encre autour de la carte.
	_overlay.draw_rect(rect.grow(3.0), Color(INK, 0.9), false, 1.6)
	_overlay.draw_rect(rect.grow(6.0), Color(INK, 0.7), false, 0.8)
	_draw_title(rect, WORLD_TITLE if _view == View.WORLD else str(_shown.get("title", "")))
	_draw_scale_bar(rect)
	_draw_compass(rect)
	_draw_hint(rect)


func _draw_region(rect: Rect2) -> void:
	if _shown.is_empty():
		return
	var portals: Array = _shown["portals"]
	for i in portals.size():
		_draw_portal(portals[i], rect, i == _hovered_portal)


func _draw_world(rect: Rect2) -> void:
	if not _atlas.is_loaded():
		_draw_ink_text("Le cartographe déroule ses cartes…", rect.get_center(), 16, true, INK, _label_font)
		return
	var px_per_meter := _px_per_meter()
	var inner := rect.grow(-2.0)
	var relief_px := clampf(MapAtlas.RELIEF_SPACING * px_per_meter * 1.2, 9.0, 30.0)
	for relief in _atlas.world["reliefs"]:
		var center := _to_canvas(relief["position"])
		if inner.grow(-relief_px * 0.5).has_point(center):
			_draw_relief(relief["kind"], center, relief_px * float(relief["scale"]), hash(relief["position"]))
	for road in _atlas.world["roads"]:
		_draw_road(road, inner)
	for region in _atlas.regions.values():
		_draw_frontier(region, inner, region["name"] == _hovered_region)
	for region in _atlas.regions.values():
		for portal in region["portals"]:
			var center := _to_canvas(region["origin"] + portal["position"])
			if inner.has_point(center):
				_draw_portal_glyph(center, clampf(px_per_meter * 6.0, 3.0, PORTAL_RADIUS))
	# Les noms trop larges pour leur région passent dessus/dessous, en alternance d'ouest en est.
	var outside_index := 0
	var regions: Array = _atlas.regions.values()
	regions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["origin"].x < b["origin"].x)
	for region in regions:
		var label := _region_label(region)
		_draw_region_label(region, label, inner, outside_index)
		if label["outside"]:
			outside_index += 1


## Mont (triangle irrégulier, flanc droit hachuré) ou colline (dôme), à l'encre.
func _draw_relief(kind: String, base: Vector2, width: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var half := width * 0.5
	if kind == "mountain":
		var height := width * rng.randf_range(0.7, 0.95)
		var peak := base + Vector2(rng.randf_range(-0.12, 0.12) * width, -height)
		var left := base + Vector2(-half, 0.0)
		var right := base + Vector2(half, 0.0)
		var shoulder := peak.lerp(right, 0.45) + Vector2(0.0, height * 0.08)
		_overlay.draw_colored_polygon(PackedVector2Array([left, peak, shoulder, right]), RELIEF_FILL)
		# Flanc à l'ombre : lavis brun et traits parallèles descendant du versant droit.
		var foot := base + Vector2(rng.randf_range(0.0, 0.15) * width, 0.0)
		_overlay.draw_colored_polygon(PackedVector2Array([peak, shoulder, right, foot]), Color(0.55, 0.40, 0.24, 0.28))
		var hatches := maxi(int(width / 3.5), 3)
		for i in hatches:
			var t := (i + 0.5) / hatches
			var on_ridge := peak.lerp(shoulder, t / 0.45) if t < 0.45 else shoulder.lerp(right, (t - 0.45) / 0.55)
			_overlay.draw_line(on_ridge, on_ridge.lerp(foot.lerp(right, t), 0.8), Color(INK, 0.7), 0.9, true)
		_overlay.draw_line(peak, foot, Color(INK, 0.75), 0.9, true)
		_overlay.draw_polyline(PackedVector2Array([left, peak, shoulder, right]), INK, 1.3, true)
	else:
		var height := width * rng.randf_range(0.28, 0.38)
		var points := PackedVector2Array()
		for i in 13:
			var angle := PI + PI * i / 12.0
			points.append(base + Vector2(cos(angle) * half, sin(angle) * height))
		_overlay.draw_colored_polygon(points, RELIEF_FILL)
		_overlay.draw_polyline(points, Color(INK, 0.85), 1.1, true)
		for i in 2:
			var from := base + Vector2(half * (0.2 + 0.25 * i), -height * (0.55 - 0.2 * i))
			_overlay.draw_line(from, from + Vector2(width * 0.08, height * 0.3), Color(INK, 0.5), 0.8, true)


## Route entre deux régions : chaussée claire et double trait tireté brun.
func _draw_road(road: PackedVector2Array, clip: Rect2) -> void:
	var points := PackedVector2Array()
	for point in road:
		points.append(_to_canvas(point))
	var dash := 7.0
	var gap := 4.0
	var walked := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if clip.has_point(a) and clip.has_point(b):
			_overlay.draw_line(a, b, Color(PAPER, 0.85), 5.0, true)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.001 or not (clip.has_point(a) and clip.has_point(b)):
			continue
		var direction := (b - a) / length
		var normal := direction.orthogonal() * 1.6
		var at := 0.0
		while at < length:
			var phase := fmod(walked + at, dash + gap)
			var step := minf((dash - phase) if phase < dash else (dash + gap - phase), length - at)
			if phase < dash:
				var from := a + direction * at
				var to := a + direction * (at + step)
				_overlay.draw_line(from + normal, to + normal, ROAD_INK, 1.0, true)
				_overlay.draw_line(from - normal, to - normal, ROAD_INK, 1.0, true)
			at += maxf(step, 0.01)
		walked += length


## Frontière d'une région : tireté d'encre, ou trait rouge plein si survolée.
func _draw_frontier(region: Dictionary, clip: Rect2, hovered: bool) -> void:
	var outline: PackedVector2Array = region["outline"]
	var color := INK_RED if hovered else Color(INK, 0.7)
	for i in outline.size() - 1:
		if not hovered and i % 2 == 1:
			continue
		var a := _to_canvas(outline[i])
		var b := _to_canvas(outline[i + 1])
		if clip.has_point(a) and clip.has_point(b):
			_overlay.draw_line(a, b, color, 2.2 if hovered else 1.1, true)


## Mise en page du nom d'une région sur la carte du monde : {lines, font_size, outside},
## coupé en deux lignes s'il déborde, sorti de la région s'il déborde encore.
func _region_label(region: Dictionary) -> Dictionary:
	var region_width := _atlas.region_rect(region).size.x * _px_per_meter()
	var hovered: bool = region["name"] == _hovered_region
	var font: Font = UITheme.font_display
	var font_size := int(clampf(region_width / 9.0, 12.0, 19.0)) + (2 if hovered else 0)
	var text := str(region["name"]).replace("_", " ")
	var lines := PackedStringArray([text])
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > region_width * 1.1 and text.contains(" "):
		var cut := text.find(" ", text.length() / 2 - 2)
		if cut < 0:
			cut = text.rfind(" ")
		lines = PackedStringArray([text.substr(0, cut), text.substr(cut + 1)])
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return {"lines": lines, "font_size": font_size, "outside": widest > region_width * 1.25}


## Nom d'une région : en son centre, ou au-dessus/en dessous (en alternance) s'il est trop
## large ; une petite tour au-dessus des villes.
func _draw_region_label(region: Dictionary, label: Dictionary, clip: Rect2, outside_index: int) -> void:
	var rect := _atlas.region_rect(region)
	var region_px := Rect2(_to_canvas(rect.position), rect.size * _px_per_meter())
	var lines: PackedStringArray = label["lines"]
	var font_size: int = label["font_size"]
	var line_height := font_size * 1.05
	var center := region_px.get_center()
	if label["outside"]:
		center.y = region_px.position.y - 6.0 - line_height * lines.size() / 2.0 if outside_index % 2 == 0 				else region_px.end.y + 6.0 + line_height * lines.size() / 2.0
	if not clip.has_point(center):
		return
	var color := INK_RED if region["name"] == _hovered_region else INK
	var y := center.y - line_height * (lines.size() - 1) / 2.0 + font_size * 0.35
	for line in lines:
		_draw_ink_text(line, Vector2(center.x, y), font_size, true, color, UITheme.font_display, 5)
		y += line_height
	if region.get("is_town", false):
		_draw_town_glyph(Vector2(center.x, center.y - line_height * lines.size() / 2.0 - 4.0), color)


## Petite tour crénelée au-dessus du nom des villes.
func _draw_town_glyph(base: Vector2, color: Color) -> void:
	var body := Rect2(base + Vector2(-5.0, -9.0), Vector2(10.0, 9.0))
	_overlay.draw_rect(body, Color(PAPER, 0.95))
	_overlay.draw_rect(body, color, false, 1.1)
	for i in 3:
		_overlay.draw_rect(Rect2(body.position + Vector2(i * 4.0 - 0.5, -3.0), Vector2(3.0, 3.0)), color)
	_overlay.draw_rect(Rect2(base + Vector2(-1.5, -4.0), Vector2(3.0, 4.0)), color)


func _draw_title(rect: Rect2, title: String) -> void:
	var font: Font = UITheme.font_display
	var font_size := int(clampf(_canvas.size.y / 22.0, 15.0, 24.0))
	var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := MARGIN_TOP - 14.0
	var center_x := _canvas.size.x / 2.0
	_overlay.draw_string(font, Vector2(center_x - text_width / 2.0, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
	# Filets de part et d'autre, terminés par un petit losange.
	var y := baseline - font_size * 0.33
	var half_gap := text_width / 2.0 + 12.0
	var reach := minf(rect.size.x * 0.3, 160.0)
	for side in [-1.0, 1.0]:
		var start := Vector2(center_x + side * half_gap, y)
		var end := Vector2(center_x + side * (half_gap + reach), y)
		_overlay.draw_line(start, end, Color(INK, 0.8), 1.0, true)
		_overlay.draw_line(start + Vector2(0, 3), end + Vector2(-side * 14.0, 3), Color(INK, 0.5), 0.8, true)
		_draw_diamond(end, 3.5, INK_RED)


## Aide dans un petit cartouche à cheval sur le bas du cadre (hors de la carte, pour ne pas
## masquer un téléporteur au bord) : comment passer d'une vue à l'autre.
func _draw_hint(rect: Rect2) -> void:
	var text := "Clic gauche sur une région : l'afficher" if _view == View.WORLD \
			else "Clic droit : carte du monde"
	var font_size := 13
	var text_size := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if text_size.x + 260.0 > rect.size.x:
		return
	var box := Rect2(Vector2(rect.get_center().x - text_size.x / 2.0 - 10.0, rect.end.y + 1.0),
			Vector2(text_size.x + 20.0, text_size.y + 4.0))
	_overlay.draw_rect(box, Color(PAPER, 0.88))
	_overlay.draw_rect(box, Color(INK, 0.7), false, 1.0)
	_overlay.draw_rect(box.grow(-2.0), Color(INK, 0.35), false, 0.6)
	_overlay.draw_string(_label_font, Vector2(box.position.x + 10.0, box.end.y - 6.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	_overlay.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)


## Barre d'échelle graduée en bas à gauche : la plus longue longueur "ronde" tenant en ~120 px.
func _draw_scale_bar(rect: Rect2) -> void:
	var px_per_meter := _px_per_meter()
	var meters: int = SCALE_STEPS[0]
	for step in SCALE_STEPS:
		if step * px_per_meter <= minf(120.0, rect.size.x * 0.3):
			meters = step
	var length := meters * px_per_meter
	if length < 24.0:
		return
	var origin := rect.position + Vector2(14.0, rect.size.y - 16.0)
	var segments := 4
	for i in segments:
		var segment := Rect2(origin + Vector2(length * i / segments, -3.0), Vector2(length / segments, 5.0))
		_overlay.draw_rect(segment, Color(INK, 0.9) if i % 2 == 0 else Color(PAPER, 0.95))
	_overlay.draw_rect(Rect2(origin + Vector2(0, -3.0), Vector2(length, 5.0)), INK, false, 1.0)
	_draw_ink_text("0", origin + Vector2(0.0, -7.0), 12)
	var label := "%d m" % meters
	_draw_ink_text(label, origin + Vector2(length, -7.0), 12)


## Rose des vents en bas à droite : quatre grandes pointes mi-pleines, quatre petites, "N".
func _draw_compass(rect: Rect2) -> void:
	var radius := clampf(minf(rect.size.x, rect.size.y) * 0.09, 16.0, 34.0)
	if rect.size.y < radius * 4.0:
		return
	var center := rect.end - Vector2(radius + 14.0, radius + 18.0)
	_overlay.draw_arc(center, radius * 0.62, 0.0, TAU, 48, Color(INK, 0.8), 1.0, true)
	_overlay.draw_arc(center, radius * 0.7, 0.0, TAU, 48, Color(INK, 0.5), 0.7, true)
	for i in 8:
		var angle := -PI / 2.0 + i * PI / 4.0
		var length := radius if i % 2 == 0 else radius * 0.55
		var dir := Vector2(cos(angle), sin(angle))
		var side := dir.orthogonal() * radius * (0.16 if i % 2 == 0 else 0.11)
		var tip := center + dir * length
		var fill := INK_RED if i == 0 else INK
		_overlay.draw_colored_polygon(PackedVector2Array([center, tip, center + side]), fill)
		_overlay.draw_colored_polygon(PackedVector2Array([center, tip, center - side]), Color(PAPER, 0.95))
		_overlay.draw_polyline(PackedVector2Array([center + side, tip, center - side, center + side]), INK, 0.8, true)
	_draw_ink_text("N", center + Vector2(0, -radius - 3.0), 13, true, INK_RED)


## Texte et cadre (px) de l'étiquette "vers X" d'un téléporteur en vue REGION.
func _portal_label(portal: Dictionary, rect: Rect2) -> Dictionary:
	var target: String = portal.get("target_map_name", "")
	if target.is_empty():
		return {"text": "", "rect": Rect2()}
	var center := _to_canvas(portal["position"])
	var text := "vers %s" % target.replace("_", " ")
	var font_size := 14
	var text_size := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y - PORTAL_RADIUS - 7.0
	if baseline - text_size.y < rect.position.y + 4.0:
		baseline = center.y + PORTAL_RADIUS + 6.0 + text_size.y * 0.75
	var x := clampf(center.x - text_size.x / 2.0, rect.position.x + 4.0, rect.end.x - text_size.x - 4.0)
	return {"text": text, "baseline": Vector2(x, baseline), "font_size": font_size,
			"rect": Rect2(x, baseline - text_size.y * 0.75, text_size.x, text_size.y)}


## Téléporteur : cercle de runes à l'encre bleue, destination écrite à côté (soulignée au
## survol : un clic affiche la région de destination).
func _draw_portal(portal: Dictionary, rect: Rect2, hovered: bool) -> void:
	_draw_portal_glyph(_to_canvas(portal["position"]), PORTAL_RADIUS)
	var label := _portal_label(portal, rect)
	if str(label["text"]).is_empty():
		return
	var color := INK if hovered else INK_RED
	_overlay.draw_string_outline(_label_font, label["baseline"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1,
			label["font_size"], 4, Color(PAPER, 0.85))
	_overlay.draw_string(_label_font, label["baseline"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1,
			label["font_size"], color)
	if hovered:
		var label_rect: Rect2 = label["rect"]
		var underline_y: float = label["baseline"].y + 3.0
		_overlay.draw_line(Vector2(label_rect.position.x, underline_y), Vector2(label_rect.end.x, underline_y), color, 1.0, true)


func _draw_portal_glyph(center: Vector2, radius: float) -> void:
	_overlay.draw_circle(center, radius, PORTAL_FILL)
	_overlay.draw_arc(center, radius, 0.0, TAU, 32, PORTAL_INK, 1.6 if radius > 5.0 else 1.1, true)
	_overlay.draw_arc(center, radius * 0.45, 0.0, TAU, 24, PORTAL_INK, 1.0, true)
	if radius < 5.0:
		return
	for i in 8:
		var dir := Vector2.from_angle(i * PI / 4.0)
		_overlay.draw_line(center + dir * (radius + 1.5), center + dir * (radius + (4.0 if i % 2 == 0 else 2.5)),
				PORTAL_INK, 1.2, true)


## Joueur, sur la région courante ou à sa place sur la carte du monde.
func _on_marker_draw() -> void:
	if not _player_position is Vector2:
		return
	var center := Vector2.ZERO
	if _view == View.WORLD:
		var current: Dictionary = _atlas.regions.get(_current_name, {}) if _atlas.is_loaded() else {}
		if current.is_empty():
			return
		center = _to_canvas(current["origin"] + _player_position)
	elif not _shown.is_empty() and _shown["is_current"]:
		center = _to_canvas(_player_position)
	else:
		return
	if _map_rect().has_point(center):
		_draw_player(center)


## Joueur : flèche rouge pointant dans sa direction de regard (point simple à défaut).
func _draw_player(center: Vector2) -> void:
	_marker.draw_circle(center, 9.0, Color(INK_RED, 0.18))
	if _player_facing.is_zero_approx():
		_marker.draw_circle(center, 4.5, INK_RED)
		_marker.draw_arc(center, 4.5, 0.0, TAU, 20, INK, 1.2, true)
		return
	var dir := _player_facing.normalized()
	var side := dir.orthogonal()
	var points := PackedVector2Array([
		center + dir * 8.0, center - dir * 5.0 + side * 5.5, center - dir * 2.0, center - dir * 5.0 - side * 5.5])
	_marker.draw_colored_polygon(points, INK_RED)
	points.append(points[0])
	_marker.draw_polyline(points, INK, 1.2, true)


func _draw_ink_text(text: String, anchor: Vector2, font_size: int, centered := true, color := INK,
		font: Font = null, outline := 3) -> void:
	if font == null:
		font = UITheme.font_display
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := anchor - Vector2(width / 2.0 if centered else 0.0, 0.0)
	_overlay.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(PAPER, 0.8))
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _on_grip_draw() -> void:
	for i in 3:
		var offset := 4.0 + i * 4.0
		_grip.draw_line(Vector2(offset, GRIP_SIZE - 2.0), Vector2(GRIP_SIZE - 2.0, offset), Color(INK, 0.75), 1.3, true)
