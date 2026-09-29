extends WindowFrame
## Carte (touche M) : la carte courante en entier, à l'échelle (une case = un mètre), façon
## carte de Tolkien — parchemin aux bords brûlés, encre sépia, forêts en petits arbres, routes
## pavées cernées d'un double trait, téléporteurs avec leur destination et position du joueur.
## Fenêtre redimensionnable par le coin bas-droit (%Grip) : la carte garde ses proportions et
## se cale au mieux dans le parchemin ; la taille est mémorisée dans user://windows.cfg comme
## la position (voir WindowFrame).
##
## Le fond (parchemin + terrain) est dessiné par world_map.gdshader à partir de deux petites
## textures de masques à une texel par case (voir _rebuild_masks) : net à toutes les tailles de
## fenêtre sans régénérer d'image. Les annotations (cadre, titre, téléporteurs, joueur, rose des
## vents, échelle) sont tracées par-dessus dans _on_overlay_draw. Données poussées par
## Game3D._rebuild_map (set_map) et Game3D._update_minimap (set_player, fenêtre ouverte seulement).

const SHADER := preload("res://scenes/game/hud/world_map.gdshader")
const SIZES_SECTION := "sizes"
const MIN_CANVAS_SIZE := Vector2(320, 220)
## Parchemin laissé autour de la carte (px), le titre prenant place dans la marge du haut.
const MARGIN_TOP := 42.0
const MARGIN_SIDE := 22.0
const GRIP_SIZE := 16.0
## Taille visée (px) d'un petit arbre de forêt : le pas de la grille d'arbres en découle.
const TREE_GLYPH_PX := 14.0
## Longueurs possibles de la barre d'échelle (m), voir _draw_scale_bar.
const SCALE_STEPS := [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]

const INK := Color(0.24, 0.15, 0.08)
const INK_RED := Color(0.52, 0.12, 0.07)
const PORTAL_INK := Color(0.15, 0.30, 0.52)
const PORTAL_FILL := Color(0.72, 0.83, 0.88)
const PAPER := Color(0.92, 0.85, 0.68)

## Terrain (nom d'item de la MeshLibrary) -> masque : 0 pavés, 1 chemin de terre, 2 forêt,
## 3 bâti (canaux RGBA de mask_a), 4 eau, 5 roche (canaux RG de mask_b).
const CHANNEL_BY_TERRAIN := {
	"pavedStone": 0, "gate": 0, "ironGate": 0,
	"dirtPath": 1,
	"tree": 2, "deadTree": 2, "forestFloor": 2, "bramble": 2, "thicket": 2, "bridge": 1,
	"rampart": 3, "auberge": 3, "forge": 3, "mausoleum": 3,
	"fountain": 4, "water": 4,
	"rockWall": 5, "rubble": 5,
}

var _canvas: ColorRect
var _overlay: Control
var _grip: Control
var _material: ShaderMaterial
var _label_font: SystemFont

var _map_name := ""
var _map_tiles := Vector2i(1, 1)
var _terrain_grid: Array = []
var _walkable_rows: Array = []
## [{position: Vector2 (cases), target_map_name: String}], voir set_map.
var _portals: Array = []
var _masks_dirty := false
## null tant que Game3D n'a pas encore donné de position (voir set_player).
var _player_position = null
var _player_facing := Vector2.ZERO

var _canvas_size := Vector2(720, 460)
var _size_restored := false
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
	_canvas = ColorRect.new()
	_canvas.name = "MapCanvas"
	_canvas.material = _material
	_canvas.custom_minimum_size = _canvas_size
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	get_body().add_child(_canvas)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_on_overlay_draw)
	_canvas.add_child(_overlay)

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


func open() -> void:
	if not _size_restored:
		_size_restored = true
		_restore_canvas_size()
	_set_canvas_size(_canvas_size)
	if _masks_dirty:
		_rebuild_masks()
	show_window()
	_overlay.queue_redraw()


func close_window() -> void:
	if visible:
		_save_canvas_size()
	super.close_window()


## Appelé par Game3D._rebuild_map à chaque (changement de) carte. `terrain_grid` : noms de
## terrain [y][x] (Game3D._terrain_grid) ; `walkable_rows` : grille serveur, utilisée pour les
## cases sans terrain connu (carte sans scène) ; `portals` : téléporteurs lus sur la scène.
func set_map(map_name: String, width: int, height: int, terrain_grid: Array,
		walkable_rows: Array, portals: Array) -> void:
	_map_name = map_name.replace("_", " ")
	_map_tiles = Vector2i(maxi(width, 1), maxi(height, 1))
	_terrain_grid = terrain_grid
	_walkable_rows = walkable_rows
	_portals = portals
	_player_position = null
	_masks_dirty = true
	if visible:
		_rebuild_masks()
		_update_shader_params()
		_overlay.queue_redraw()


## Appelé par Game3D._update_minimap à chaque frame tant que la fenêtre est ouverte, avec la
## position (cases) et la direction de regard au sol du joueur.
func set_player(tile_position: Vector2, facing: Vector2) -> void:
	if _player_position is Vector2 and (_player_position as Vector2).distance_squared_to(tile_position) < 0.0004 \
			and _player_facing.is_equal_approx(facing):
		return
	_player_position = tile_position
	_player_facing = facing
	_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Masques de terrain (voir world_map.gdshader)
# ---------------------------------------------------------------------------

func _rebuild_masks() -> void:
	_masks_dirty = false
	var width := _map_tiles.x
	var height := _map_tiles.y
	var data_a := PackedByteArray()
	var data_b := PackedByteArray()
	data_a.resize(width * height * 4)
	data_b.resize(width * height * 4)
	for y in height:
		var terrain_row: Array = _terrain_grid[y] if y < _terrain_grid.size() else []
		var walkable_row: String = _walkable_rows[y] if y < _walkable_rows.size() else ""
		for x in width:
			var terrain_name: String = terrain_row[x] if x < terrain_row.size() else ""
			var channel: int = CHANNEL_BY_TERRAIN.get(terrain_name, -1)
			# Carte sans scène : les cases bloquées du serveur deviennent de la roche.
			if terrain_name.is_empty() and x < walkable_row.length() and walkable_row[x] == "0":
				channel = 5
			if channel < 0:
				continue
			var index := (y * width + x) * 4
			if channel < 4:
				data_a[index + channel] = 255
			else:
				data_b[index + channel - 4] = 255
	_material.set_shader_parameter("mask_a", _mask_texture(data_a, width, height))
	_material.set_shader_parameter("mask_b", _mask_texture(data_b, width, height))
	_update_shader_params()


## Agrandie en bicubique (x3, plafonnée à 2048 px) : contours arrondis plutôt qu'en escalier.
func _mask_texture(data: PackedByteArray, width: int, height: int) -> ImageTexture:
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	var factor := clampi(2048 / maxi(width, height), 1, 3)
	if factor > 1:
		image.resize(width * factor, height * factor, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(image)


# ---------------------------------------------------------------------------
# Mise en page et redimensionnement
# ---------------------------------------------------------------------------

## Rectangle (px, repère du parchemin) occupé par la carte : même échelle sur les deux axes.
func _map_rect() -> Rect2:
	var canvas := _canvas.size
	var available := Rect2(MARGIN_SIDE, MARGIN_TOP,
			maxf(canvas.x - MARGIN_SIDE * 2.0, 1.0), maxf(canvas.y - MARGIN_TOP - MARGIN_SIDE, 1.0))
	var scale := minf(available.size.x / _map_tiles.x, available.size.y / _map_tiles.y)
	var map_size := Vector2(_map_tiles) * scale
	return Rect2(available.position + (available.size - map_size) / 2.0, map_size)


func _px_per_tile() -> float:
	return _map_rect().size.x / _map_tiles.x


func _to_canvas(tile_position: Vector2) -> Vector2:
	var rect := _map_rect()
	return rect.position + tile_position * _px_per_tile()


func _on_canvas_resized() -> void:
	_update_shader_params()
	_overlay.queue_redraw()


func _update_shader_params() -> void:
	var rect := _map_rect()
	var px_per_tile := _px_per_tile()
	# Pas de la grille d'arbres arrondi à une puissance de √2 : la densité de la forêt ne
	# "grouille" pas pendant un redimensionnement continu.
	var tree_cell := TREE_GLYPH_PX / maxf(px_per_tile, 0.01)
	tree_cell = maxf(pow(2.0, roundf(log(tree_cell) / log(2.0) * 2.0) / 2.0), 1.0)
	_material.set_shader_parameter("canvas_size", _canvas.size)
	_material.set_shader_parameter("map_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_material.set_shader_parameter("map_tiles", Vector2(_map_tiles))
	_material.set_shader_parameter("px_per_tile", px_per_tile)
	_material.set_shader_parameter("tree_cell", tree_cell)


func _max_canvas_size() -> Vector2:
	# Place prise par le cadre de fenêtre (barre de titre, bordures) autour du parchemin.
	var chrome := size - _canvas.size if visible else Vector2(20, 40)
	return (get_viewport_rect().size - chrome - Vector2(8, 8)).max(MIN_CANVAS_SIZE)


func _set_canvas_size(wanted: Vector2) -> void:
	_canvas_size = wanted.clamp(MIN_CANVAS_SIZE, _max_canvas_size()).round()
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


## Première ouverture sans taille mémorisée : la carte entière dans ~70 % de l'écran.
func _restore_canvas_size() -> void:
	var config := WindowFrame._positions_config()
	if persist_positions and config.has_section_key(SIZES_SECTION, name):
		var saved = config.get_value(SIZES_SECTION, name)
		if saved is Vector2:
			_canvas_size = saved
			return
	var available := get_viewport_rect().size * Vector2(0.62, 0.7) - Vector2(MARGIN_SIDE * 2.0, MARGIN_TOP + MARGIN_SIDE)
	var scale := minf(available.x / _map_tiles.x, available.y / _map_tiles.y)
	_canvas_size = Vector2(_map_tiles) * scale + Vector2(MARGIN_SIDE * 2.0, MARGIN_TOP + MARGIN_SIDE)


func _save_canvas_size() -> void:
	if not persist_positions:
		return
	var config := WindowFrame._positions_config()
	config.set_value(SIZES_SECTION, name, _canvas_size)
	config.save(POSITIONS_PATH)


# ---------------------------------------------------------------------------
# Annotations
# ---------------------------------------------------------------------------

func _on_overlay_draw() -> void:
	var rect := _map_rect()
	# Double filet d'encre autour de la carte.
	_overlay.draw_rect(rect.grow(3.0), Color(INK, 0.9), false, 1.6)
	_overlay.draw_rect(rect.grow(6.0), Color(INK, 0.7), false, 0.8)
	_draw_title(rect)
	_draw_scale_bar(rect)
	_draw_compass(rect)
	for portal in _portals:
		_draw_portal(rect, portal)
	if _player_position is Vector2:
		_draw_player(_to_canvas(_player_position))


func _draw_title(rect: Rect2) -> void:
	var font: Font = UITheme.font_display
	var font_size := int(clampf(_canvas.size.y / 22.0, 15.0, 24.0))
	var text_width := font.get_string_size(_map_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := MARGIN_TOP - 14.0
	var center_x := _canvas.size.x / 2.0
	_overlay.draw_string(font, Vector2(center_x - text_width / 2.0, baseline), _map_name,
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


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	_overlay.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)


## Barre d'échelle graduée en bas à gauche : la plus longue longueur "ronde" tenant en ~120 px.
func _draw_scale_bar(rect: Rect2) -> void:
	var px_per_tile := _px_per_tile()
	var meters: int = SCALE_STEPS[0]
	for step in SCALE_STEPS:
		if step * px_per_tile <= minf(120.0, rect.size.x * 0.3):
			meters = step
	var length := meters * px_per_tile
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


## Téléporteur : cercle de runes à l'encre bleue, destination écrite à côté.
func _draw_portal(rect: Rect2, portal: Dictionary) -> void:
	var center := _to_canvas(portal["position"])
	var radius := 7.0
	_overlay.draw_circle(center, radius, PORTAL_FILL)
	_overlay.draw_arc(center, radius, 0.0, TAU, 32, PORTAL_INK, 1.6, true)
	_overlay.draw_arc(center, radius * 0.45, 0.0, TAU, 24, PORTAL_INK, 1.0, true)
	for i in 8:
		var dir := Vector2.from_angle(i * PI / 4.0)
		_overlay.draw_line(center + dir * (radius + 1.5), center + dir * (radius + (4.0 if i % 2 == 0 else 2.5)),
				PORTAL_INK, 1.2, true)
	var target: String = portal.get("target_map_name", "")
	if target.is_empty():
		return
	var text := "vers %s" % target
	var font_size := 14
	var text_size := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y - radius - 7.0
	if baseline - text_size.y < rect.position.y + 4.0:
		baseline = center.y + radius + 6.0 + text_size.y * 0.75
	var x := clampf(center.x - text_size.x / 2.0, rect.position.x + 4.0, rect.end.x - text_size.x - 4.0)
	_overlay.draw_string_outline(_label_font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, 4, Color(PAPER, 0.85))
	_overlay.draw_string(_label_font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, INK_RED)


## Joueur : flèche rouge pointant dans sa direction de regard (point simple à défaut).
func _draw_player(center: Vector2) -> void:
	_overlay.draw_circle(center, 9.0, Color(INK_RED, 0.18))
	if _player_facing.is_zero_approx():
		_overlay.draw_circle(center, 4.5, INK_RED)
		_overlay.draw_arc(center, 4.5, 0.0, TAU, 20, INK, 1.2, true)
		return
	var dir := _player_facing.normalized()
	var side := dir.orthogonal()
	var points := PackedVector2Array([
		center + dir * 8.0, center - dir * 5.0 + side * 5.5, center - dir * 2.0, center - dir * 5.0 - side * 5.5])
	_overlay.draw_colored_polygon(points, INK_RED)
	points.append(points[0])
	_overlay.draw_polyline(points, INK, 1.2, true)


func _draw_ink_text(text: String, anchor: Vector2, font_size: int, centered := true, color := INK) -> void:
	var font: Font = UITheme.font_display
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := anchor - Vector2(width / 2.0 if centered else 0.0, 0.0)
	_overlay.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(PAPER, 0.8))
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _on_grip_draw() -> void:
	for i in 3:
		var offset := 4.0 + i * 4.0
		_grip.draw_line(Vector2(offset, GRIP_SIZE - 2.0), Vector2(GRIP_SIZE - 2.0, offset), Color(INK, 0.75), 1.3, true)
