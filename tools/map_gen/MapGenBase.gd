extends SceneTree
## Base commune des générateurs de cartes décorées de la région de Gludio (façon Lineage 2) :
## Town of Gludio, Gludio Castle, Ruins of Agony, Ruins of Despair, Cruma Marshlands, Town
## of Dion. Chaque générateur (tools/map_gen/generate_*.gd) hérite de ce script et fournit :
##   - _setup()     : dimensions, graine, métadonnées (MapData), point d'apparition... ;
##   - _layout()    : le plan au sol (routes, rivières et ponts, places, forêts...) ;
##   - _decorate()  : props (bâtiments, remparts, lampadaires, panneaux) et marqueurs
##                    (portails, PNJ, zone de paix) ;
##   - _configure_ground() / _configure_vegetation() (facultatifs) : textures et densités.
## La base s'occupe du reste, comme les générateurs historiques (Orée, Place du village) :
## terrain peint sous les ouvrages (minimap, carte du monde), aucun arbre sous un prop,
## connexité (des passages sont percés dans les fourrés qui enclavent une zone praticable),
## vérification que portails, PNJ, portes et positions de personnages sont atteignables
## depuis le point d'apparition, puis écriture de la scène (GridMap + TerrainGround +
## Vegetation + Props + Objects). Relancer un générateur ÉCRASE sa scène ; ensuite, exporter
## vers le serveur avec tools/export_map_to_tmx.gd.
##
## Conventions : 1 case = 1 m, Vector2(x, z) = position sur la carte (x vers l'est, z vers
## le sud) ; un prop de rotation 0 a sa façade (porte) tournée vers +Z (le sud) ; un pont
## d'axe "x" a son tablier selon X (il franchit une rivière nord-sud), d'axe "z" selon Z.
## Portails au bord de la carte, au bout des routes ; l'arrivée depuis une autre carte se
## fait SUR le portail qui y ramène (convention des cartes existantes).

const LIBRARY_PATH := "res://assets/terrain/terrain_library.res"
const PROPS := "res://scenes/maps/props/"
const ZoneAssets := preload("res://autoload/ZoneAssets3D.gd")
const PIXELS_PER_TILE := 32.0

## Codes terrain internes -> noms d'items de la MeshLibrary.
enum T { GRASS, FOREST, DIRT, PAVED, TREE, WATER, THICKET, BRIDGE, RAMPART, BUILDING, FORGE, CROP,
		DARK_GRASS, TALL_GRASS, REEDS, RUBBLE, DEAD_TREE, DANGER }
const T_NAMES := ["grass", "forestFloor", "dirtPath", "pavedStone", "tree", "water", "thicket", "bridge",
		"rampart", "auberge", "forge", "fieldCrop", "darkGrass", "tallGrass", "denseTallGrass", "rubble",
		"deadTree", "dangerGround"]
## Terrains bloquants "végétaux" qu'on peut percer pour relier une poche isolée.
const SOFT_BLOCKERS := [T.TREE, T.THICKET, T.REEDS, T.RUBBLE, T.DEAD_TREE]
## Distance (m) entre le centre d'un bâtiment et le seuil de sa porte (façade +Z) : vérifié
## praticable et relié au point d'apparition.
const DOOR_DEPTH := {"Inn": 6.9, "Forge": 4.1, "HouseLarge": 4.3, "HouseMedium": 4.0, "HouseSmall": 3.5,
		"Temple": 13.9, "CastleKeep": 12.0}
## Emprise (largeur de façade, profondeur) des bâtiments posés par _fill_lots.
const BUILDING_SIZE := {"HouseSmall": Vector2(6.2, 5.2), "HouseMedium": Vector2(7.2, 6.2),
		"HouseLarge": Vector2(9.2, 6.7), "Inn": Vector2(12.2, 8.2)}

# --- Configuration (renseignée par _setup) ---------------------------------
var W := 100
var H := 100
var SEED := 1
var MAP_ID := ""
var MAP_NAME := ""
var DESCRIPTION := ""
var OUT_PATH := ""
var IS_TOWN := false
var IS_STARTING_MAP := false
var BIOME: int = MapData.Biome.NONE
var PLAYER_SPAWN := Vector2(50.5, 50.5)
## Positions de personnages existants (base de dev) : gardées praticables et reliées.
var KEEP_CLEAR: Array = []
## Terrain rendu aux cases percées dans un fourré / une roselière pour relier une poche.
var CARVE_TERRAIN: int = T.GRASS

# --- État -----------------------------------------------------------------
var _terrain := PackedByteArray()
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
## Champs de distance nommés (voir _field / _stamp).
var _fields := {}
## Ponts déclarés (voir _bridge) : [centre, axe, scène, longueur, largeur praticable, nom].
var _bridges: Array = []
var _root: MapData
var _props: Node3D
var _objects: Node3D
## [nœud, terrain] : terrain peint sous l'emprise du nœud une fois la scène dans l'arbre.
var _terrain_under: Array = []
## libellé -> position devant être praticable et reliée au point d'apparition.
var _checks := {}
## Cases réservées (bâtiments posés, abords de PNJ...) : refusées par _lot_ok.
var _reserved := {}
## Zones de chasse déclarées par _monster_zone, résolues par _place_monster_spawns.
var _hunting_zones: Array = []
## Distance minimale (m) entre un point de monstre et le point d'apparition / un portail /
## un PNJ.
const MONSTER_CLEARANCE := {"spawn": 30.0, "portal": 24.0, "npc": 12.0}
## Distance minimale (m) au bord d'une route : les monstres agressifs (rayon d'aggro de 6 cases)
## ne sautent pas sur qui reste sur la chaussée.
const MONSTER_ROAD_GAP := 7.0
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_setup()
		_rng.seed = SEED
		_noise.seed = SEED
		_noise.frequency = 0.1
		_terrain.resize(W * H)
		_terrain.fill(T.GRASS)
		_layout()
		_paint_bridges()
		_build_root()
		_decorate()
		root.add_child(_root)
		return false
	if _frames >= 2 and not _done and is_instance_valid(_root):
		_done = true
		_write_scene()
	return true


# ---------------------------------------------------------------------------
# À fournir par chaque générateur
# ---------------------------------------------------------------------------

func _setup() -> void:
	pass


func _layout() -> void:
	pass


func _decorate() -> void:
	pass


## Appelé une fois les emprises des props connues (cases bloquées), avant la connexité :
## plantations qui doivent éviter les props.
func _after_props(_blocked: Dictionary) -> void:
	pass


func _configure_ground(_ground: TerrainGround) -> void:
	pass


func _configure_vegetation(_vegetation: Vegetation) -> void:
	pass


# ---------------------------------------------------------------------------
# Terrain : accès, champs de distance, routes, rivières
# ---------------------------------------------------------------------------

func _in_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _t_at(p: Vector2) -> int:
	return _terrain[clampi(int(p.y), 0, H - 1) * W + clampi(int(p.x), 0, W - 1)]


func _set_t(x: int, z: int, t: int) -> void:
	if x >= 0 and z >= 0 and x < W and z < H:
		_terrain[z * W + x] = t


## Champ de distance `field_name` (créé à INF au premier appel).
func _field(field_name: String) -> PackedFloat32Array:
	if not _fields.has(field_name):
		var arr := PackedFloat32Array()
		arr.resize(W * H)
		arr.fill(INF)
		_fields[field_name] = arr
	return _fields[field_name]


func _dist(field_name: String, p: Vector2) -> float:
	if not _fields.has(field_name):
		return INF
	return _fields[field_name][clampi(int(p.y), 0, H - 1) * W + clampi(int(p.x), 0, W - 1)]


## field[i] = min(field[i], distance(case, p) - inner) pour les cases à moins de `reach` de p.
func _stamp(field_name: String, p: Vector2, inner: float, reach: float) -> void:
	var arr: PackedFloat32Array = _field(field_name)
	for z in range(maxi(0, floori(p.y - reach)), mini(H, ceili(p.y + reach) + 1)):
		for x in range(maxi(0, floori(p.x - reach)), mini(W, ceili(p.x + reach) + 1)):
			var d := Vector2(x + 0.5, z + 0.5).distance_to(p) - inner
			var i := z * W + x
			if d < arr[i]:
				arr[i] = d
	_fields[field_name] = arr


## Disque au bord irrégulier (rayon modulé par du bruit angulaire).
func _stamp_blob(field_name: String, c: Vector2, radius: float) -> void:
	var arr: PackedFloat32Array = _field(field_name)
	var reach := radius * 1.35 + 6.0
	for z in range(maxi(0, floori(c.y - reach)), mini(H, ceili(c.y + reach) + 1)):
		for x in range(maxi(0, floori(c.x - reach)), mini(W, ceili(c.x + reach) + 1)):
			var v := Vector2(x + 0.5, z + 0.5) - c
			var r := radius * (1.0 + 0.22 * _noise.get_noise_2d(cos(v.angle()) * 20.0 + c.x, sin(v.angle()) * 20.0 + c.y))
			var d := v.length() - r
			var i := z * W + x
			if d < arr[i]:
				arr[i] = d
	_fields[field_name] = arr


## Rectangle (axes alignés) : distance au bord, négative dedans.
func _stamp_rect(field_name: String, rect: Rect2, reach: float) -> void:
	var arr: PackedFloat32Array = _field(field_name)
	for z in range(maxi(0, floori(rect.position.y - reach)), mini(H, ceili(rect.end.y + reach) + 1)):
		for x in range(maxi(0, floori(rect.position.x - reach)), mini(W, ceili(rect.end.x + reach) + 1)):
			var p := Vector2(x + 0.5, z + 0.5)
			var dx := maxf(rect.position.x - p.x, p.x - rect.end.x)
			var dz := maxf(rect.position.y - p.y, p.y - rect.end.y)
			var d := Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0)
			var i := z * W + x
			if d < arr[i]:
				arr[i] = d
	_fields[field_name] = arr


## Points espacés de `step` le long d'une polyligne lissée (Catmull-Rom).
func _sample(points: Array, step: float) -> Array:
	var result := []
	for k in points.size() - 1:
		var p0: Vector2 = points[maxi(k - 1, 0)]
		var p1: Vector2 = points[k]
		var p2: Vector2 = points[k + 1]
		var p3: Vector2 = points[mini(k + 2, points.size() - 1)]
		var steps := maxi(2, int(p1.distance_to(p2) / step))
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	result.append(points[points.size() - 1])
	return result


## Points intermédiaires tous les ~`step` m le long d'une polyligne (ses côtés restent droits
## une fois lissés par _sample) ; `closed` : referme le polygone.
func _densify(points: Array, step: float, closed := false) -> Array:
	var pts := points.duplicate()
	if closed:
		pts.append(points[0])
	var result := []
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for s in n:
			result.append(a.lerp(b, float(s) / n))
	result.append(pts[pts.size() - 1])
	return result


## Chemin (route pavée, chemin de terre...) : terrain `t` sur une demi-largeur `half` (bord
## légèrement bruité), distance enregistrée dans le champ "road" (arbres tenus à l'écart) et,
## sur `clear` m de plus, dans le champ "open" (accotements dégagés).
func _road(points: Array, half: float, t: int, clear := 4.0, wobble := 0.25) -> void:
	var tmp := "_tmp_road"
	_fields.erase(tmp)
	for p in _sample(points, 0.5):
		_stamp(tmp, p, 0.0, half + 2.0)
		_stamp("road", p, half, half + 14.0)
		_stamp("open", p, half + clear, half + clear + 10.0)
	var arr: PackedFloat32Array = _fields[tmp]
	for i in W * H:
		if arr[i] <= half + _noise.get_noise_2d(i % W, i / W) * wobble:
			if _terrain[i] != T.WATER or t == T.WATER:
				_terrain[i] = t
	_fields.erase(tmp)


## Rivière (cases "water", lit creusé par TerrainGround) de demi-largeur `half` (± bruit),
## resserrée au droit des ponts déjà déclarés (_bridge) pour que les tabliers débordent sur
## les berges ; distance au bord dans le champ "river" (négative dans l'eau).
func _river(points: Array, half: float, variation := 0.9) -> void:
	var samples := _sample(points, 0.5)
	for k in samples.size():
		var p: Vector2 = samples[k]
		var hw := half + _noise.get_noise_1d(k * 0.6 + SEED % 97) * variation
		for bridge in _bridges:
			var narrow: float = bridge[3] / 2.0 - 3.6
			hw = lerpf(minf(narrow, hw), hw, smoothstep(9.0, 16.0, p.distance_to(bridge[0])))
		_stamp("river", p, hw, hw + 14.0)
		_stamp("open", p, hw + 1.0, hw + 8.0)
	var arr: PackedFloat32Array = _fields["river"]
	for i in W * H:
		if arr[i] <= 0.0:
			_terrain[i] = T.WATER


## Mare / étang au bord irrégulier.
func _pond(c: Vector2, radius: float) -> void:
	var tmp := "_tmp_pond"
	_fields.erase(tmp)
	_stamp_blob(tmp, c, radius)
	var arr: PackedFloat32Array = _fields[tmp]
	var river: PackedFloat32Array = _field("river")
	for i in W * H:
		if arr[i] <= 0.0:
			_terrain[i] = T.WATER
		river[i] = minf(river[i], arr[i])
	_fields.erase(tmp)


## Déclare un pont (À APPELER AVANT _river pour que la rivière s'y resserre). `axis` "x" :
## tablier selon X (franchit une rivière nord-sud), centre z au milieu d'une case ; "z" :
## l'inverse. Longueur / largeur praticable alignées sur tools/env_gen/build_bridges.py :
## BridgeStone 15 m / 5, BridgeWood 13 m / 3.
func _bridge(center: Vector2, axis: String, stone: bool, bridge_name: String) -> void:
	var scene := "BridgeStone" if stone else "BridgeWood"
	var length := 15.0 if stone else 13.0
	var walk := 5 if stone else 3
	_bridges.append([center, axis, scene, length, walk, bridge_name])


func _paint_bridges() -> void:
	for bridge in _bridges:
		var c: Vector2 = bridge[0]
		var along_x: bool = bridge[1] == "x"
		var half_len: float = bridge[3] / 2.0
		var half_walk: float = bridge[4] / 2.0
		var deck := T.PAVED if bridge[2] == "BridgeStone" else T.DIRT
		var hx := half_len if along_x else half_walk
		var hz := half_walk if along_x else half_len
		for z in range(floori(c.y - hz), ceili(c.y + hz)):
			for x in range(floori(c.x - hx), ceili(c.x + hx)):
				if not _in_map(Vector2i(x, z)) or absf(z + 0.5 - c.y) > hz or absf(x + 0.5 - c.x) > hx:
					continue
				var i := z * W + x
				_terrain[i] = T.BRIDGE if _terrain[i] == T.WATER else deck


func _near_bridge(p: Vector2, margin: float) -> bool:
	for bridge in _bridges:
		var c: Vector2 = bridge[0]
		var along_x: bool = bridge[1] == "x"
		var hx: float = (bridge[3] / 2.0 if along_x else bridge[4] / 2.0 + 1.5) + margin
		var hz: float = (bridge[4] / 2.0 + 1.5 if along_x else bridge[3] / 2.0) + margin
		if absf(p.x - c.x) < hx and absf(p.y - c.y) < hz:
			return true
	return false


## Remplit les cases dont le champ `field_name` vaut au plus `threshold` (± bruit) avec `t`,
## sans toucher aux terrains listés dans `keep`.
func _paint_field(field_name: String, threshold: float, t: int, wobble := 0.0, keep: Array = []) -> void:
	if not _fields.has(field_name):
		return
	var arr: PackedFloat32Array = _fields[field_name]
	for i in W * H:
		if keep.has(_terrain[i]):
			continue
		if arr[i] <= threshold + _noise.get_noise_2d((i % W) * 1.3, (i / W) * 1.3) * wobble:
			_terrain[i] = t


func _paint_disc(c: Vector2, radius: float, t: int, keep: Array = []) -> void:
	for z in range(maxi(0, floori(c.y - radius - 1)), mini(H, ceili(c.y + radius + 1))):
		for x in range(maxi(0, floori(c.x - radius - 1)), mini(W, ceili(c.x + radius + 1))):
			if Vector2(x + 0.5, z + 0.5).distance_to(c) <= radius and not keep.has(_terrain[z * W + x]):
				_terrain[z * W + x] = t


func _paint_rect(rect: Rect2, t: int, keep: Array = []) -> void:
	for z in range(maxi(0, floori(rect.position.y)), mini(H, ceili(rect.end.y))):
		for x in range(maxi(0, floori(rect.position.x)), mini(W, ceili(rect.end.x))):
			if rect.has_point(Vector2(x + 0.5, z + 0.5)) and not keep.has(_terrain[z * W + x]):
				_terrain[z * W + x] = t


## Plantation clairsemée : pour chaque case de terrain `on` (ordre pseudo-aléatoire), un
## arbre (`t`) avec la probabilité renvoyée par `prob.call(x, z)`, jamais collé à un autre.
func _scatter(t: int, on: Array, prob: Callable, spacing := 1) -> int:
	var order := range(W * H)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var count := 0
	for i in order:
		if not on.has(_terrain[i]):
			continue
		var x: int = i % W
		var z: int = i / W
		if _rng.randf() >= prob.call(x, z):
			continue
		if spacing > 0 and _has_within(Vector2i(x, z), spacing, [T.TREE, T.DEAD_TREE]):
			continue
		_terrain[i] = t
		count += 1
	return count


func _has_within(cell: Vector2i, radius: int, kinds: Array) -> bool:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := cell + Vector2i(dx, dz)
			if (dx != 0 or dz != 0) and _in_map(c) and kinds.has(_terrain[c.y * W + c.x]):
				return true
	return false


## Distance (cases) au bord de carte le plus proche.
func _edge(x: int, z: int) -> int:
	return mini(mini(x, z), mini(W - 1 - x, H - 1 - z))


## Lisière infranchissable le long des bords de la carte (fourré `t`, profondeur `depth` ±
## bruit), interrompue autour des routes, rivières et portails qui sortent de la carte.
func _edge_band(depth: int, t: int, on: Array) -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			if not on.has(_terrain[i]):
				continue
			var band := depth + int(roundf(_noise.get_noise_2d(x * 1.7, z * 1.7) * 2.5))
			if _edge(x, z) >= band:
				continue
			var p := Vector2(x + 0.5, z + 0.5)
			if _dist("road", p) < 5.0 or _dist("river", p) < 2.0 or _dist("open", p) < 1.0 or _near_keep_clear(p, 4.0):
				continue
			_terrain[i] = t


func _near_keep_clear(p: Vector2, radius: float) -> bool:
	for k in KEEP_CLEAR:
		if (k as Vector2).distance_to(p) < radius:
			return true
	return false


# ---------------------------------------------------------------------------
# Scène : racine, props, ouvrages
# ---------------------------------------------------------------------------

func _build_root() -> void:
	_root = MapData.new()
	_root.name = OUT_PATH.get_file().get_basename()
	_root.map_id = MAP_ID
	_root.map_name = MAP_NAME
	_root.description = DESCRIPTION
	_root.is_starting_map = IS_STARTING_MAP
	_root.is_town = IS_TOWN
	_root.biome = BIOME
	_root.render_obstacle_blocks = false
	var grid := GridMap.new()
	grid.name = "Terrain"
	grid.mesh_library = load(LIBRARY_PATH)
	grid.cell_size = Vector3.ONE
	grid.cell_center_y = false
	_add(_root, grid)
	_props = _add(_root, _node("Props"))
	_objects = _add(_root, _node("Objects"))
	_add(_objects, _marker("PlayerSpawn", "res://map_objects/PlayerSpawnMarker3D.gd", PLAYER_SPAWN))
	if not _bridges.is_empty():
		var group := _add(_props, _node("Ponts"))
		for bridge in _bridges:
			var yaw := 0.0 if bridge[1] == "x" else PI / 2.0
			_instance(bridge[2], group, bridge[0], yaw).name = bridge[5]


func _node(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	return n


func _add(parent: Node, child: Node) -> Node:
	parent.add_child(child, true)
	child.owner = _root
	return child


## Instance d'une scène de props (nom court = scenes/maps/props/<nom>.tscn, ou chemin).
func _instance(scene: String, parent: Node, pos: Vector2, yaw: float) -> Node3D:
	var path := scene if scene.begins_with("res://") else PROPS + scene + ".tscn"
	var inst: Node3D
	if ResourceLoader.exists(path):
		inst = (load(path) as PackedScene).instantiate()
	else:
		# Modèle pas encore construit : simple repère, pour tester la disposition.
		push_warning("Prop absent, remplacé par un repère vide : %s" % path)
		inst = Node3D.new()
		inst.name = scene.get_file().get_basename()
	inst.position = Vector3(pos.x, 0.0, pos.y)
	inst.rotation.y = yaw
	parent.add_child(inst, true)
	inst.owner = _root
	return inst


## Bâtiment : façade (porte) tournée vers `facing` (direction carte), terrain `t` peint sous
## son emprise ; le seuil de la porte est vérifié atteignable.
func _building(scene: String, parent: Node, pos: Vector2, facing: Vector2, node_name: String, t: int = T.BUILDING) -> Node3D:
	var yaw := atan2(facing.x, facing.y)
	var node := _instance(scene, parent, pos, yaw)
	node.name = node_name
	_terrain_under.append([node, t])
	if DOOR_DEPTH.has(scene):
		_checks["Porte " + node_name] = pos + facing.normalized() * DOOR_DEPTH[scene]
	return node


## Cases (centres) couvertes par un rectangle orienté : `size` = (largeur de façade,
## profondeur), façade tournée vers `facing`, agrandi de `margin` m de chaque côté.
func _rect_cells(center: Vector2, facing: Vector2, size: Vector2, margin: float) -> Array:
	var f := facing.normalized()
	var right := Vector2(f.y, -f.x)
	var hw := size.x / 2.0 + margin
	var hd := size.y / 2.0 + margin
	var reach := Vector2(hw, hd).length()
	var cells := []
	for z in range(floori(center.y - reach), ceili(center.y + reach) + 1):
		for x in range(floori(center.x - reach), ceili(center.x + reach) + 1):
			var v := Vector2(x + 0.5, z + 0.5) - center
			if absf(v.dot(right)) <= hw and absf(v.dot(f)) <= hd:
				cells.append(Vector2i(x, z))
	return cells


func _reserve_cells(cells: Array) -> void:
	for c in cells:
		_reserved[c] = true


func _reserve_disc(c: Vector2, radius: float) -> void:
	for z in range(floori(c.y - radius), ceili(c.y + radius) + 1):
		for x in range(floori(c.x - radius), ceili(c.x + radius) + 1):
			if Vector2(x + 0.5, z + 0.5).distance_to(c) <= radius:
				_reserved[Vector2i(x, z)] = true


## Vrai si toutes les cases sous le rectangle (marge comprise) sont dans la carte, libres
## (non réservées), d'un terrain de `allowed` et acceptées par `extra.call(Vector2)`.
func _lot_ok(center: Vector2, facing: Vector2, size: Vector2, margin: float, allowed: Array, extra: Callable) -> bool:
	for c in _rect_cells(center, facing, size, margin):
		if not _in_map(c) or _reserved.has(c) or not allowed.has(_terrain[c.y * W + c.x]):
			return false
		if not extra.call(Vector2(c.x + 0.5, c.y + 0.5)):
			return false
	return true


## Maisons alignées le long de la rue a -> b, du côté `side` (+1 : à gauche en allant de a
## vers b, vue de dessus x vers l'est / z vers le sud ; -1 : à droite), façade sur la rue, à
## `setback` m du bord de la chaussée (demi-largeur `street_half`). `kinds` : scènes tirées au
## hasard (poids `weights`). Renvoie le nombre de maisons posées.
func _fill_lots(parent: Node, a: Vector2, b: Vector2, side: float, street_half: float, kinds: Array,
		weights: Array, allowed: Array, extra: Callable, name_prefix: String, setback := 1.2) -> int:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var n := Vector2(dir.y, -dir.x) * side
	var t := 1.0
	var placed := 0
	var total := 0.0
	for w in weights:
		total += w
	while t < length - 3.0:
		var roll := _rng.randf() * total
		var k := 0
		while k < weights.size() - 1 and roll > weights[k]:
			roll -= weights[k]
			k += 1
		var scene: String = kinds[k]
		var size: Vector2 = BUILDING_SIZE[scene]
		if t + size.x > length:
			t += 1.0
			continue
		var center := a + dir * (t + size.x / 2.0) + n * (street_half + setback + size.y / 2.0)
		if _lot_ok(center, -n, size, 0.6, allowed, extra):
			_building(scene, parent, center, -n, "%s_%d" % [name_prefix, placed])
			_reserve_cells(_rect_cells(center, -n, size, 1.0))
			placed += 1
			t += size.x + _rng.randf_range(1.2, 3.0)
		else:
			t += 1.0
	return placed


## Enceinte fortifiée polygonale fermée (sommets dans l'ordre), tours aux sommets
## (`corner_scene`, demi-largeur `corner_half` le long du mur), ouvrages intermédiaires
## `features` = [[position sur un côté, demi-longueur le long du mur, scène], ...] (portes :
## scène contenant "Gatehouse", passage perpendiculaire au mur), courtines (`wall_scene`, de
## longueur nominale `wall_len`, étirées) entre deux ouvrages. Les ouvrages font face à
## `center`. Terrain RAMPART peint dessous.
func _fortification(parent: Node, vertices: Array, center: Vector2, features: Array, corner_scene: String,
		corner_half: float, wall_scene: String, wall_len: float, wall_overlap := 1.0) -> void:
	var walls := _add(parent, _node("Courtines"))
	var towers := _add(parent, _node("Tours"))
	var n := vertices.size()
	for k in n:
		var v: Vector2 = vertices[k]
		var node := _instance(corner_scene, towers, v, atan2(-(center - v).x, -(center - v).y))
		_terrain_under.append([node, T.RAMPART])
	for k in n:
		var a: Vector2 = vertices[k]
		var b: Vector2 = vertices[(k + 1) % n]
		var dir := (b - a).normalized()
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(center - (a + b) / 2.0) < 0.0:
			inward = -inward
		var on_edge := []
		for f in features:
			var p: Vector2 = f[0]
			var along := (p - a).dot(dir)
			var off := absf((p - a).dot(Vector2(-dir.y, dir.x)))
			if off < 0.6 and along > 0.0 and along < a.distance_to(b):
				on_edge.append([along, f])
		on_edge.sort_custom(func(l, r): return l[0] < r[0])
		var chain := [[a, corner_half]]
		for e in on_edge:
			var f: Array = e[1]
			var yaw := atan2(-inward.x, -inward.y)
			var node := _instance(f[2], parent if String(f[2]).contains("Gatehouse") else towers, f[0], yaw)
			if f.size() > 3:
				node.name = f[3]
			_terrain_under.append([node, T.RAMPART])
			chain.append([f[0], f[1]])
		chain.append([b, corner_half])
		for c in range(1, chain.size()):
			var p0: Vector2 = chain[c - 1][0]
			var p1: Vector2 = chain[c][0]
			_wall_run(walls, wall_scene, wall_len, p0 + dir * (chain[c - 1][1] - wall_overlap),
					p1 - dir * (chain[c][1] - wall_overlap))


## Tronçons de courtine de a à b (modèle de `wall_len` m étiré pour tomber juste).
func _wall_run(parent: Node, wall_scene: String, wall_len: float, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var count := maxi(1, roundi(length / wall_len))
	var seg := length / count
	var dir := (b - a) / length
	for i in count:
		var node := _instance(wall_scene, parent, a + dir * seg * (i + 0.5), atan2(-dir.y, dir.x))
		node.scale = Vector3(seg / wall_len, 1.0, 1.0)
		_terrain_under.append([node, T.RAMPART])


## Lampadaire : crosse (+X du modèle) orientée vers `arm_dir`.
func _lamp(parent: Node, pos: Vector2, arm_dir: Vector2) -> void:
	_instance("LampPost", parent, pos, atan2(-arm_dir.y, arm_dir.x))


## Poteau indicateur : entries = [[destination, cap en degrés (0 = est, 90 = sud)], ...].
func _sign(parent: Node, sign_name: String, pos: Vector2, entries: Array) -> void:
	var sign := _instance("Signpost", parent, pos, 0.0)
	sign.name = "Panneau_" + sign_name
	sign.scale = Vector3.ONE * 1.2
	var list := PackedStringArray()
	for e in entries:
		list.append("%s|%d" % [e[0], int(roundf(fposmod(e[1], 360.0)))])
	sign.destinations = list


## Cap (degrés : 0 = est, 90 = sud) de a vers b.
func _heading(a: Vector2, b: Vector2) -> float:
	return rad_to_deg((b - a).angle())


# ---------------------------------------------------------------------------
# Marqueurs serveur
# ---------------------------------------------------------------------------

func _marker(marker_name: String, script_path: String, pos: Vector2) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.set_script(load(script_path))
	m.position = Vector3(pos.x, 0.0, pos.y)
	return m


## Portail vers une autre carte, posé sur un socle de téléporteur ; `arrival` = case
## d'arrivée sur la carte cible (son portail de retour).
func _portal(direction: String, pos: Vector2, target_map_id: String, arrival: Vector2, label: String) -> void:
	var m := _marker("Portal_" + direction, "res://map_objects/PortalMarker3D.gd", pos)
	m.direction = direction
	m.target_map_id = target_map_id
	m.target_x = arrival.x * PIXELS_PER_TILE
	m.target_y = arrival.y * PIXELS_PER_TILE
	_add(_objects, m)
	var group: Node = _props.get_node_or_null("Teleporteurs")
	if group == null:
		group = _add(_props, _node("Teleporteurs"))
	_instance("Teleporter", group, pos, 0.0).name = "Teleporteur_" + label.validate_node_name().replace(" ", "_")
	_checks["Portail " + label] = pos


func _npc(npc_name: String, npc_id: String, pos: Vector2) -> void:
	var m := _marker("NpcSpawn_" + npc_name, "res://map_objects/NpcSpawnMarker3D.gd", pos)
	m.npc_id = npc_id
	_add(_objects, m)
	_checks["PNJ " + npc_name] = pos


## Zone de chasse : `count` points d'apparition de monstres tirés sur les cases praticables
## (reliées au point d'apparition) à moins de `radius` m de `center`, chacun d'un des
## `monsters` = [[templateId serveur, poids], ...] (backend data/monsters.xml), regroupés
## dans le groupe `group_id` (réapparition après `respawn` s). Les points sont tirés à la
## finalisation (praticabilité connue), à l'écart du point d'apparition, des portails et des
## PNJ, espacés d'au moins `spacing` m, jamais sur un pont ni sur une route.
func _monster_zone(group_id: String, center: Vector2, radius: float, monsters: Array, count: int,
		respawn := 30, spacing := 4.0) -> void:
	_hunting_zones.append({"group": group_id, "center": center, "radius": radius, "monsters": monsters,
			"count": count, "respawn": respawn, "spacing": spacing})


func _peace_zone(points: PackedVector2Array, zone_name := "Peace Zone") -> void:
	var peace := Node3D.new()
	peace.name = "Peace_Zone"
	peace.set_script(load("res://map_objects/PeaceZoneMarker3D.gd"))
	peace.zone_name = zone_name
	peace.polygon_points = points
	_add(_objects, peace)


# ---------------------------------------------------------------------------
# Finalisation (scène dans l'arbre : emprises des props calculables)
# ---------------------------------------------------------------------------

func _blocked_cells() -> Dictionary:
	var blocked := {}
	for node in _root.get_tree().get_nodes_in_group(ObstacleFootprint3D.GROUP):
		if not (node as ObstacleFootprint3D).blocks_movement:
			continue
		for cell in (node as ObstacleFootprint3D).blocked_cells():
			blocked[cell] = true
	return blocked


func _write_scene() -> void:
	var blocked := _blocked_cells()
	for entry in _terrain_under:
		for fp in (entry[0] as Node).find_children("*", "ObstacleFootprint3D", true, false):
			if not (fp as ObstacleFootprint3D).blocks_movement:
				continue
			for cell in (fp as ObstacleFootprint3D).blocked_cells():
				if _in_map(cell) and _terrain[cell.y * W + cell.x] != T.WATER:
					_terrain[cell.y * W + cell.x] = entry[1]
	for cell in blocked:
		if _in_map(cell) and SOFT_BLOCKERS.has(_terrain[cell.y * W + cell.x]):
			_terrain[cell.y * W + cell.x] = T.GRASS
	_after_props(blocked)
	_ensure_connectivity(blocked)
	if not _validate(blocked):
		_root.free()
		quit(1)
		return
	_place_monster_spawns(blocked)
	_write_grid(_root.get_node("Terrain"))

	var ground := TerrainGround.new()
	ground.name = "Ground"
	_configure_ground(ground)
	var vegetation := Vegetation.new()
	vegetation.name = "Vegetation"
	vegetation.seed = SEED
	_configure_vegetation(vegetation)
	root.remove_child(_root)
	_add(_root, ground)
	_root.move_child(ground, 1)
	_add(_root, vegetation)
	_root.move_child(vegetation, 2)

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		printerr("Échec de sauvegarde (%d)" % err)
		quit(1)
		return
	var counts := {}
	for t in _terrain:
		counts[T_NAMES[t]] = counts.get(T_NAMES[t], 0) + 1
	print("Scène écrite : %s (%dx%d, %d cases bloquées par des props)" % [OUT_PATH, W, H, blocked.size()])
	print("  cases par terrain : %s" % str(counts))
	_root.free()
	quit()


func _walkable(i: int, blocked: Dictionary) -> bool:
	return not ZoneAssets.BLOCKING_TERRAINS.has(T_NAMES[_terrain[i]]) and not blocked.has(Vector2i(i % W, i / W))


## Relie au point d'apparition toute poche praticable d'au moins 20 cases en perçant le
## plus court passage à travers les terrains bloquants "mous" (arbres, fourrés, roselières,
## éboulis) — jamais à travers l'eau ni un prop.
func _ensure_connectivity(blocked: Dictionary) -> void:
	var start := int(PLAYER_SPAWN.y) * W + int(PLAYER_SPAWN.x)
	var walkable := func(i: int) -> bool: return _walkable(i, blocked)
	var carved := 0
	var given_up := {}
	for pass_index in 120:
		var reached := _flood(start, walkable)
		var pocket: Array = []
		var seen := {}
		for i in W * H:
			if reached[i] == 1 or seen.has(i) or given_up.has(i) or not walkable.call(i):
				continue
			var cells := _flood_list(i, walkable)
			for c in cells:
				seen[c] = true
			if cells.size() >= 20:
				pocket = cells
				break
		if pocket.is_empty():
			break
		var dug := _carve_path(pocket, reached, blocked)
		if dug < 0:
			for c in pocket:
				given_up[c] = true
			print("  poche enclavée laissée autour de %s (%d cases)" % [Vector2i(pocket[0] % W, pocket[0] / W), pocket.size()])
		else:
			carved += dug
	print("Connexité : %d cases percées" % carved)


func _carve_path(pocket: Array, reached: PackedByteArray, blocked: Dictionary) -> int:
	var prev := {}
	var queue := []
	for c in pocket:
		prev[c] = -1
		queue.append(c)
	var head := 0
	var goal := -1
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		if reached[i] == 1:
			goal = i
			break
		var x := i % W
		var z := i / W
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W if z > 0 else -1, i + W if z < H - 1 else -1]:
			if nb < 0 or prev.has(nb) or blocked.has(Vector2i(nb % W, nb / W)):
				continue
			if _walkable(nb, blocked) or SOFT_BLOCKERS.has(_terrain[nb]):
				prev[nb] = i
				queue.append(nb)
	if goal < 0:
		return -1
	var dug := 0
	var i := goal
	while i >= 0:
		if SOFT_BLOCKERS.has(_terrain[i]):
			_terrain[i] = CARVE_TERRAIN
			dug += 1
		i = prev[i]
	return dug


func _validate(blocked: Dictionary) -> bool:
	var walkable := func(i: int) -> bool: return _walkable(i, blocked)
	var start := int(PLAYER_SPAWN.y) * W + int(PLAYER_SPAWN.x)
	if not walkable.call(start):
		printerr("Point d'apparition non praticable : %s" % PLAYER_SPAWN)
		return false
	var reached := _flood(start, walkable)
	for k in KEEP_CLEAR.size():
		_checks["Perso de dev %d" % k] = KEEP_CLEAR[k]
	var ok := true
	for label in _checks:
		var p: Vector2 = _checks[label]
		var i := int(p.y) * W + int(p.x)
		if not _in_map(Vector2i(int(p.x), int(p.y))) or reached[i] == 0:
			var cell := Vector2i(int(p.x), int(p.y))
			printerr("Inaccessible depuis le point d'apparition : %s (%.1f, %.1f) [terrain %s%s]" % [label, p.x, p.y,
					T_NAMES[_terrain[i]] if _in_map(cell) else "hors carte", ", sous un prop" if blocked.has(cell) else ""])
			ok = false
	var reach_count := 0
	for r in reached:
		reach_count += r
	print("Cases praticables reliées au spawn : %d / %d" % [reach_count, W * H])
	return ok


## Résout les zones de chasse (_monster_zone) en marqueurs MonsterSpawnMarker3D + un
## MonsterSpawnGroupMarker3D par zone. Tirage sur un générateur à part (graine dérivée de
## SEED) : ajouter ou retoucher une zone ne déplace ni les arbres ni les maisons.
func _place_monster_spawns(blocked: Dictionary) -> void:
	if _hunting_zones.is_empty():
		return
	var start := int(PLAYER_SPAWN.y) * W + int(PLAYER_SPAWN.x)
	var reached := _flood(start, func(i: int) -> bool: return _walkable(i, blocked))
	var avoid := [[PLAYER_SPAWN, MONSTER_CLEARANCE["spawn"]]]
	for label in _checks:
		if String(label).begins_with("Portail "):
			avoid.append([_checks[label], MONSTER_CLEARANCE["portal"]])
		elif String(label).begins_with("PNJ "):
			avoid.append([_checks[label], MONSTER_CLEARANCE["npc"]])
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 31 + 7
	var placed_all: Array = []
	var total := 0
	for zone in _hunting_zones:
		var center: Vector2 = zone["center"]
		var radius: float = zone["radius"]
		var candidates: Array = []
		for z in range(maxi(0, floori(center.y - radius)), mini(H, ceili(center.y + radius) + 1)):
			for x in range(maxi(0, floori(center.x - radius)), mini(W, ceili(center.x + radius) + 1)):
				var i := z * W + x
				var p := Vector2(x + 0.5, z + 0.5)
				if reached[i] == 0 or p.distance_to(center) > radius:
					continue
				if _terrain[i] == T.BRIDGE or _dist("road", p) < MONSTER_ROAD_GAP:
					continue
				if avoid.any(func(a: Array) -> bool: return (a[0] as Vector2).distance_to(p) < a[1]):
					continue
				candidates.append(p)
		for i in range(candidates.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = tmp
		var monsters: Array = zone["monsters"]
		var weight_total := 0.0
		for m in monsters:
			weight_total += float(m[1])
		var placed := 0
		for p in candidates:
			if placed >= int(zone["count"]):
				break
			if placed_all.any(func(q: Vector2) -> bool: return q.distance_to(p) < float(zone["spacing"])):
				continue
			# Un exemplaire de chaque espèce d'abord, puis tirage pondéré.
			var k := placed
			if placed >= monsters.size():
				var roll := rng.randf() * weight_total
				k = 0
				while k < monsters.size() - 1 and roll > float(monsters[k][1]):
					roll -= float(monsters[k][1])
					k += 1
			var m := _marker("Monstre_%s_%d" % [String(zone["group"]).validate_node_name().replace(" ", "_"), placed],
					"res://map_objects/MonsterSpawnMarker3D.gd", p)
			m.template_id = monsters[k][0]
			m.spawn_group = zone["group"]
			_add(_objects, m)
			placed_all.append(p)
			placed += 1
		if placed < int(zone["count"]):
			push_warning("Zone de chasse %s : %d points sur %d demandés" % [zone["group"], placed, zone["count"]])
		var g := Node3D.new()
		g.name = "Groupe_" + String(zone["group"]).validate_node_name().replace(" ", "_")
		g.set_script(load("res://map_objects/MonsterSpawnGroupMarker3D.gd"))
		g.group_id = zone["group"]
		g.max_monsters = placed
		g.respawn_delay_seconds = int(zone["respawn"])
		_add(_objects, g)
		total += placed
	print("Monstres : %d points dans %d zones de chasse" % [total, _hunting_zones.size()])


func _flood(start: int, walkable: Callable) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(W * H)
	var stack := [start]
	reached[start] = 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % W
		var z := i / W
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W if z > 0 else -1, i + W if z < H - 1 else -1]:
			if nb >= 0 and reached[nb] == 0 and walkable.call(nb):
				reached[nb] = 1
				stack.append(nb)
	return reached


func _flood_list(start: int, walkable: Callable) -> Array:
	var result := [start]
	var seen := {start: true}
	var head := 0
	while head < result.size():
		var i: int = result[head]
		head += 1
		var x := i % W
		var z := i / W
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W if z > 0 else -1, i + W if z < H - 1 else -1]:
			if nb >= 0 and not seen.has(nb) and walkable.call(nb):
				seen[nb] = true
				result.append(nb)
	return result


func _write_grid(grid: GridMap) -> void:
	var library: MeshLibrary = grid.mesh_library
	var ids := []
	for t_name in T_NAMES:
		var id := library.find_item_by_name(t_name)
		if id < 0:
			push_error("Terrain absent de la MeshLibrary : %s" % t_name)
		ids.append(id)
	grid.clear()
	for z in H:
		for x in W:
			grid.set_cell_item(Vector3i(x, 0, z), ids[_terrain[z * W + x]])
