class_name MapAtlas
extends RefCounted
## Atlas des régions pour la carte (WorldMapWindow) : terrain, taille et téléporteurs de
## chaque scène res://scenes/maps/*.tscn, plus la composition de la carte du monde qui les
## réunit toutes (masques de terrain réduits, routes entre téléporteurs, forêts, monts et
## collines dans l'entre-deux).
##
## Tout est lu en tâche de fond (load_all_async, WorkerThreadPool) sur l'état empaqueté des
## scènes (PackedScene.get_state) : ni instanciation ni nœud ajouté à l'arbre. Le chargement
## d'une grande carte coûte ~100-200 ms, d'où le thread ; le décodage du GridMap est négligeable.

## Terrain (nom d'item de la MeshLibrary) -> masque : 0 pavés, 1 chemin de terre, 2 forêt,
## 3 bâti (canaux RGBA de mask_a), 4 eau, 5 roche (canaux RG de mask_b). Voir world_map.gdshader.
const CHANNEL_BY_TERRAIN := {
	"pavedStone": 0, "gate": 0, "ironGate": 0,
	"dirtPath": 1,
	"tree": 2, "deadTree": 2, "forestFloor": 2, "bramble": 2, "thicket": 2, "denseTallGrass": 2, "bridge": 1,
	"rampart": 3, "auberge": 3, "forge": 3, "mausoleum": 3,
	"fountain": 4, "water": 4,
	"rockWall": 5, "rubble": 5,
}

## Résolution de la carte du monde : mètres par texel des masques composés.
const WORLD_TEXEL := 2
## Parchemin (m) laissé autour de l'ensemble des régions.
const WORLD_MARGIN := 90.0
## Seuil du bruit (0-1) sous lequel l'entre-deux des régions est boisé.
const FOREST_LEVEL := 0.31
## Pas (m) du semis des monts et collines de l'entre-deux.
const RELIEF_SPACING := 30.0
## Écart (m) entre deux régions placées automatiquement (voir _auto_place).
const REGION_GAP := 60.0
## Coin haut-gauche (m) de chaque région sur la carte du monde, à l'échelle (1 case = 1 m),
## calé pour que les téléporteurs se fassent face d'une région à l'autre (voir
## tools/map_gen/GludioRegion.gd) : le château au nord de Gludio et la Neutral Zone au-delà,
## Agonie à l'ouest puis le lac de Fellmere, le Désespoir au sud, Cruma à l'est, Dion au
## sud-est avec les Execution Grounds à l'est et son château au sud. Une carte absente d'ici
## est placée à côté d'une voisine (voir _auto_place).
const WORLD_ORIGINS := {
	"Town of Gludio": Vector2(0, 0),
	"Gludio Castle": Vector2(-20, -270),
	"Ruins of Agony": Vector2(-310, -8),
	"Ruins of Despair": Vector2(-20, 230),
	"Cruma Marshlands": Vector2(270, -28),
	"Town of Dion": Vector2(330, 270),
	"Neutral Zone": Vector2(-120, -590),
	"Fellmere Lake": Vector2(-650, -28),
	"Execution Grounds": Vector2(580, 220),
	"Dion Castle": Vector2(285, 470),
}

## Région : {name, id, is_town, size: Vector2i, mask_a, mask_b (PackedByteArray RGBA8, une
## texel par case), portals: [{position: Vector2 (cases), target_map_id}], origin: Vector2 (m,
## carte du monde), outline: PackedVector2Array (m, frontière dessinée)}, par nom de carte.
var regions: Dictionary = {}
## Carte du monde, remplie par load_all_async : bounds (Rect2, m), tiles (Vector2i, texels),
## mask_a/mask_b (Image), roads ([PackedVector2Array], m), reliefs ([{kind, position, scale}]).
var world: Dictionary = {}

var _task_id := -1
var _paths: Array = []


## Lance la lecture de toutes les cartes en tâche de fond. `paths` : chemins des scènes
## (ZoneAssets3D). Sans effet si déjà lancée.
func load_all_async(paths: Array) -> void:
	if _task_id != -1:
		return
	_paths = paths.duplicate()
	_task_id = WorkerThreadPool.add_task(_load_all, false, "MapAtlas")


func is_started() -> bool:
	return _task_id != -1


## true une fois la tâche terminée (et attendue) : regions et world sont alors utilisables.
func is_ready() -> bool:
	if _task_id == -2:
		return true
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -2
	return true


## Bloque jusqu'à la fin de la tâche (sortie de l'arbre de la fenêtre).
func wait() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -2


func is_loaded() -> bool:
	return _task_id == -2


## Rectangle (m) d'une région sur la carte du monde.
func region_rect(region: Dictionary) -> Rect2:
	return Rect2(region["origin"], Vector2(region["size"]))


## Région de `map_id`, ou {} si inconnue.
func region_by_id(map_id: String) -> Dictionary:
	for region in regions.values():
		if region["id"] == map_id:
			return region
	return {}


func _load_all() -> void:
	var loaded := {}
	for path in _paths:
		var region := read_region(path)
		if not region.is_empty():
			loaded[region["name"]] = region
	_layout(loaded)
	world = _build_world(loaded)
	regions = loaded


# ---------------------------------------------------------------------------
# Lecture d'une scène de carte
# ---------------------------------------------------------------------------

static func read_region(path: String) -> Dictionary:
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		return {}
	var state := packed.get_state()
	var region := {"name": "", "id": "", "is_town": false, "portals": []}
	var cells := PackedInt32Array()
	var library: MeshLibrary = null
	for node in state.get_node_count():
		var props := {}
		for p in state.get_node_property_count(node):
			props[state.get_node_property_name(node, p)] = state.get_node_property_value(node, p)
		if node == 0:
			region["name"] = str(props.get("map_name", ""))
			region["id"] = str(props.get("map_id", ""))
			region["is_town"] = bool(props.get("is_town", false))
		elif state.get_node_name(node) == &"Terrain" and props.has("data"):
			var data: Dictionary = props["data"]
			cells = data.get("cells", PackedInt32Array())
			library = props.get("mesh_library") as MeshLibrary
		elif props.has("target_map_id"):
			var transform: Transform3D = props.get("transform", Transform3D())
			region["portals"].append({
				"position": Vector2(transform.origin.x, transform.origin.z),
				"target_map_id": str(props["target_map_id"]),
			})
	if str(region["name"]).is_empty():
		return {}
	_decode_terrain(region, cells, library)
	return region


## GridMap.data["cells"] : triplets d'int32 (x | y << 16, z, item | orientation << 16).
static func _decode_terrain(region: Dictionary, cells: PackedInt32Array, library: MeshLibrary) -> void:
	var width := 1
	var height := 1
	for i in range(0, cells.size(), 3):
		width = maxi(width, (cells[i] & 0xFFFF) + 1)
		height = maxi(height, (cells[i + 1] & 0xFFFF) + 1)
	var channel_by_item := {}
	if library != null:
		for item in library.get_item_list():
			channel_by_item[item] = CHANNEL_BY_TERRAIN.get(library.get_item_name(item), -1)
	var data_a := PackedByteArray()
	var data_b := PackedByteArray()
	data_a.resize(width * height * 4)
	data_b.resize(width * height * 4)
	for i in range(0, cells.size(), 3):
		var x := cells[i] & 0xFFFF
		var z := cells[i + 1] & 0xFFFF
		var channel: int = channel_by_item.get(cells[i + 2] & 0xFFFF, -1)
		if channel < 0 or x >= width or z >= height:
			continue
		var index := (z * width + x) * 4
		if channel < 4:
			data_a[index + channel] = 255
		else:
			data_b[index + channel - 4] = 255
	region["size"] = Vector2i(width, height)
	region["mask_a"] = data_a
	region["mask_b"] = data_b


## Masques de la carte courante d'après la grille de terrain lue par Game3D (noms [y][x]) ;
## les cases sans terrain connu bloquées côté serveur deviennent de la roche.
static func masks_from_grid(terrain_grid: Array, walkable_rows: Array, width: int, height: int) -> Array:
	var data_a := PackedByteArray()
	var data_b := PackedByteArray()
	data_a.resize(width * height * 4)
	data_b.resize(width * height * 4)
	for y in height:
		var terrain_row: Array = terrain_grid[y] if y < terrain_grid.size() else []
		var walkable_row: String = walkable_rows[y] if y < walkable_rows.size() else ""
		for x in width:
			var terrain_name: String = terrain_row[x] if x < terrain_row.size() else ""
			var channel: int = CHANNEL_BY_TERRAIN.get(terrain_name, -1)
			if terrain_name.is_empty() and x < walkable_row.length() and walkable_row[x] == "0":
				channel = 5
			if channel < 0:
				continue
			var index := (y * width + x) * 4
			if channel < 4:
				data_a[index + channel] = 255
			else:
				data_b[index + channel - 4] = 255
	return [data_a, data_b]


## Texture d'un masque de région, agrandie en bicubique (x3, plafonnée à 2048 px) : contours
## arrondis plutôt qu'en escalier.
static func mask_texture(data: PackedByteArray, width: int, height: int) -> ImageTexture:
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	var factor := clampi(2048 / maxi(width, height), 1, 3)
	if factor > 1:
		image.resize(width * factor, height * factor, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(image)


# ---------------------------------------------------------------------------
# Disposition des régions
# ---------------------------------------------------------------------------

func _layout(loaded: Dictionary) -> void:
	var pending: Array = []
	for region in loaded.values():
		if WORLD_ORIGINS.has(region["name"]):
			region["origin"] = WORLD_ORIGINS[region["name"]]
		else:
			pending.append(region)
	_auto_place(loaded, pending)
	for region in loaded.values():
		region["outline"] = _outline(region_rect(region), hash(region["name"]))


## Place chaque carte hors de WORLD_ORIGINS en face d'un téléporteur d'une voisine déjà
## placée (du côté du bord le plus proche de ce téléporteur), sinon en rangée sous le reste.
func _auto_place(loaded: Dictionary, pending: Array) -> void:
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for region in pending.duplicate():
			for portal in region["portals"]:
				var neighbour := _find_by_id(loaded, portal["target_map_id"])
				if neighbour.is_empty() or not neighbour.has("origin"):
					continue
				var anchor := Vector2.ZERO
				var normal := Vector2.RIGHT
				for back in neighbour["portals"]:
					if back["target_map_id"] == region["id"]:
						anchor = neighbour["origin"] + back["position"]
						normal = _edge_normal(back["position"], neighbour["size"])
				if anchor == Vector2.ZERO:
					anchor = Rect2(neighbour["origin"], Vector2(neighbour["size"])).get_center()
				var arrival: Vector2 = portal["position"]
				region["origin"] = (anchor + normal * REGION_GAP - arrival).round()
				pending.erase(region)
				progress = true
				break
	var bottom := 0.0
	for region in loaded.values():
		if region.has("origin"):
			bottom = maxf(bottom, region_rect(region).end.y)
	var x := 0.0
	for region in pending:
		region["origin"] = Vector2(x, bottom + REGION_GAP)
		x += region["size"].x + REGION_GAP


static func _find_by_id(loaded: Dictionary, map_id: String) -> Dictionary:
	for region in loaded.values():
		if region["id"] == map_id:
			return region
	return {}


## Normale sortante du bord de la carte le plus proche de `position` (cases).
static func _edge_normal(position: Vector2, size: Vector2i) -> Vector2:
	var distances := [position.x, position.y, size.x - position.x, size.y - position.y]
	var normals := [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN]
	var best := 0
	for i in 4:
		if distances[i] < distances[best]:
			best = i
	return normals[best]


## Frontière d'une région : son rectangle, coins adoucis, bords légèrement tremblés comme
## tracés à la main.
static func _outline(rect: Rect2, seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points := PackedVector2Array()
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var step := 9.0
	var cut := minf(10.0, minf(rect.size.x, rect.size.y) * 0.2)
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var direction := (b - a).normalized()
		var normal := direction.orthogonal()
		var length := a.distance_to(b) - cut * 2.0
		var count := maxi(int(length / step), 1)
		for i in count + 1:
			var jitter := rng.randf_range(-1.6, 1.6) if i > 0 and i < count else 0.0
			points.append(a + direction * (cut + length * i / count) + normal * jitter)
	points.append(points[0])
	return points


# ---------------------------------------------------------------------------
# Composition de la carte du monde
# ---------------------------------------------------------------------------

func _build_world(loaded: Dictionary) -> Dictionary:
	if loaded.is_empty():
		return {}
	var bounds := Rect2()
	var first := true
	for region in loaded.values():
		bounds = region_rect(region) if first else bounds.merge(region_rect(region))
		first = false
	bounds = bounds.grow(WORLD_MARGIN)
	bounds.position = (bounds.position / WORLD_TEXEL).floor() * WORLD_TEXEL
	var tiles := Vector2i((bounds.size / WORLD_TEXEL).ceil())
	bounds.size = Vector2(tiles * WORLD_TEXEL)

	var mask_a := Image.create_empty(tiles.x, tiles.y, false, Image.FORMAT_RGBA8)
	var mask_b := Image.create_empty(tiles.x, tiles.y, false, Image.FORMAT_RGBA8)
	# Cases libres pour les forêts de l'entre-deux : hors des régions et loin des routes.
	var free := Image.create_empty(tiles.x, tiles.y, false, Image.FORMAT_L8)
	free.fill(Color.WHITE)
	for region in loaded.values():
		var size: Vector2i = region["size"]
		var at := Vector2i(((region["origin"] - bounds.position) / WORLD_TEXEL).round())
		var reduced := (Vector2(size) / WORLD_TEXEL).ceil()
		for pair in [[mask_a, region["mask_a"]], [mask_b, region["mask_b"]]]:
			var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, pair[1])
			image.resize(int(reduced.x), int(reduced.y), Image.INTERPOLATE_BILINEAR)
			(pair[0] as Image).blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		var keep_out := ((region_rect(region).grow(14.0).position - bounds.position) / WORLD_TEXEL).floor()
		free.fill_rect(Rect2i(Vector2i(keep_out), Vector2i(reduced) + Vector2i(14, 14)), Color.BLACK)

	var roads := _build_roads(loaded)
	for road in roads:
		for point in road:
			var texel := Vector2i(((point - bounds.position) / WORLD_TEXEL).round())
			free.fill_rect(Rect2i(texel - Vector2i(5, 5), Vector2i(11, 11)), Color.BLACK)

	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = 7
	forest_noise.frequency = 0.045
	forest_noise.fractal_octaves = 3
	var noise_image := forest_noise.get_image(tiles.x, tiles.y)
	var noise_data := noise_image.get_data()
	var free_data := free.get_data()
	var data_a := mask_a.get_data()
	for i in free_data.size():
		if free_data[i] > 128 and noise_data[i] < FOREST_LEVEL * 255.0:
			data_a[i * 4 + 2] = 255
	mask_a = Image.create_from_data(tiles.x, tiles.y, false, Image.FORMAT_RGBA8, data_a)

	return {
		"bounds": bounds,
		"tiles": tiles,
		"mask_a": mask_a,
		"mask_b": mask_b,
		"roads": roads,
		"reliefs": _build_reliefs(loaded, bounds, roads, noise_image),
	}


## Routes entre régions : une par paire de téléporteurs qui se répondent, courbe de Bézier
## qui quitte chaque région perpendiculairement à son bord.
func _build_roads(loaded: Dictionary) -> Array:
	var roads: Array = []
	var done := {}
	for region in loaded.values():
		for portal in region["portals"]:
			var other := _find_by_id(loaded, portal["target_map_id"])
			if other.is_empty():
				continue
			var key := [region["name"], other["name"]]
			key.sort()
			if done.has(str(key)):
				continue
			done[str(key)] = true
			var start: Vector2 = region["origin"] + portal["position"]
			var start_normal := _edge_normal(portal["position"], region["size"])
			var end := Rect2(other["origin"], Vector2(other["size"])).get_center()
			var end_normal := Vector2.ZERO
			for back in other["portals"]:
				if back["target_map_id"] == region["id"]:
					end = other["origin"] + back["position"]
					end_normal = _edge_normal(back["position"], other["size"])
			var reach := start.distance_to(end) * 0.4
			var c1 := start + start_normal * reach
			var c2 := end + end_normal * reach
			var points := PackedVector2Array()
			var count := maxi(int(start.distance_to(end) / 4.0), 6)
			for i in count + 1:
				var t := float(i) / count
				var u := 1.0 - t
				points.append(start * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + end * t * t * t)
			roads.append(points)
	return roads


## Monts et collines dessinés dans l'entre-deux (voir WorldMapWindow._draw_relief) : semis
## sur une grille jitterée, plus montagneux loin des régions, jamais sur une région, une route
## ou une forêt.
func _build_reliefs(loaded: Dictionary, bounds: Rect2, roads: Array, forest_image: Image) -> Array:
	var relief_noise := FastNoiseLite.new()
	relief_noise.seed = 21
	relief_noise.frequency = 0.006
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var reliefs: Array = []
	var spacing := RELIEF_SPACING
	var y := bounds.position.y + spacing * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + spacing * 0.5
		while x < bounds.end.x:
			var position := Vector2(x, y) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * spacing
			x += spacing
			var nearest := INF
			for region in loaded.values():
				nearest = minf(nearest, _rect_distance(region_rect(region), position))
			if nearest < 30.0:
				continue
			if _near_road(roads, position, 20.0):
				continue
			var texel := Vector2i(((position - bounds.position) / WORLD_TEXEL).floor())
			if forest_image.get_pixelv(texel.clamp(Vector2i.ZERO, forest_image.get_size() - Vector2i.ONE)).r < FOREST_LEVEL:
				continue
			var relief := relief_noise.get_noise_2dv(position) + clampf((nearest - 90.0) / 260.0, 0.0, 0.4)
			if relief > 0.4:
				reliefs.append({"kind": "mountain", "position": position, "scale": rng.randf_range(0.85, 1.3)})
			elif relief > 0.1 and rng.randf() < 0.45:
				reliefs.append({"kind": "hill", "position": position, "scale": rng.randf_range(0.8, 1.15)})
		y += spacing
	# Dessinés de l'arrière vers l'avant : chaque sommet cache le pied de celui de derrière.
	reliefs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["position"].y < b["position"].y)
	return reliefs


static func _rect_distance(rect: Rect2, point: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


static func _near_road(roads: Array, point: Vector2, distance: float) -> bool:
	for road in roads:
		for p in road:
			if (p as Vector2).distance_squared_to(point) < distance * distance:
				return true
	return false
