extends SceneTree
## Outil hors-ligne : génère la scène res://scenes/maps/Place_du_village.tscn (132 x 92
## cases) — point de départ de la carte, à retoucher ensuite librement dans l'éditeur Godot
## (pinceau GridMap, props déplaçables), puis à exporter vers le serveur avec
## tools/export_map_to_tmx.gd. Relancer ce script ÉCRASE la scène.
##
## Disposition :
##   - une enceinte fortifiée rectangulaire (courtines crénelées, tours rondes, poivrières aux
##     angles), percée d'une porte à l'ouest (route pavée vers l'Orée de la forêt) et d'une
##     porte à l'est (chemin de terre vers le cimetière), chacune gardée ;
##   - au bout de chaque route, au bord de la carte, un téléporteur (le portail vers la carte
##     voisine, point de passage entre les cartes) ;
##   - au centre, une place pavée autour de la fontaine, traversée par la grand-rue
##     (ouest-est) et une rue nord-sud, avec quatre étals de marché ;
##   - l'auberge et la forge sur la grand-rue, une dizaine de maisons à colombages, un
##     verger, un potager clos, un puits, des ruelles de terre au pied des remparts ;
##   - des gardes aux portes, aux téléporteurs et dans la rue nord-sud ;
##   - hors les murs, une bande de prés puis la forêt jusqu'au bord de la carte.
## Terrain peint sous les ouvrages (minimap) : "rampart" sous remparts/tours/portes,
## "auberge" sous l'auberge et les maisons, "forge" sous la forge.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_place_du_village.gd

const OUT_PATH := "res://scenes/maps/Place_du_village.tscn"
const LIBRARY_PATH := "res://assets/terrain/terrain_library.res"
const PROPS := "res://scenes/maps/props/"
const W := 132
const H := 92
const SEED := 20260927

const MAP_ID := "5e4ada37-37e1-438c-9233-581f10c055c7"
const MAP_NAME := "Place du village"
const DESCRIPTION := "Le coeur fortifié du village : une place pavée autour d'une fontaine, entre l'auberge et la forge, à l'abri de hauts remparts gardés. Deux téléporteurs y mènent à l'Orée de la forêt et au Chemin du cimetière."
const OREE_ID := "9a884ac7-b954-4cd6-ab67-c677d472cb0f"
const CEMETERY_PATH_ID := "4dae9974-45f7-46c9-8e66-12cdac759860"
const INNKEEPER_ID := "a3c8d0f2-5d5f-4d2c-9f2c-3f4e5d6c7b8a"
const BLACKSMITH_ID := "dcb67f1e-b178-4062-8393-26abca9b0d66"
## Un PNJ serveur n'apparaît qu'une fois dans le monde : une fiche par garde (backend
## data/npc/others.xml, "Gate Guard" / "Village Guard").
const GATE_GUARD_IDS := ["318a4b28-4aae-46fa-ab99-2bc62738f1c3", "6fea25d2-5d6f-474e-adef-c11c1a903843",
		"a760adde-b995-4ab8-a073-ac5f4d4e5a23", "b748cda3-b7ed-4e50-863e-a31bc4815d9f"]
const VILLAGE_GUARD_IDS := ["b0362279-5a46-4461-9672-6f4e0b2cf7e0", "a38d3420-52b9-498a-ba7a-0248158c1acc",
		"f006ec9d-60f1-46e3-9dc8-e10c3fd43338", "7d014cb8-a199-484b-a7b8-24c086f6c797"]
## Maître des compétences (backend NpcType SKILL_LEARNER), au sud de la fontaine, face à
## l'arrivée des joueurs.
const SKILL_LEARNER_ID := "b982da01-7dd0-4c8c-84d3-1ce6795fecee"

## Axe des courtines.
const WALL_X0 := 26.0
const WALL_X1 := 118.0
const WALL_Z0 := 12.0
const WALL_Z1 := 80.0
const AVENUE_Z := 46.0
const STREET_X := 72.0
const FOUNTAIN := Vector2(72.0, 46.0)
## Place pavée (coins abattus de SQUARE_CHAMFER m).
const SQUARE := Rect2(57.0, 35.0, 30.0, 22.0)
const SQUARE_CHAMFER := 5.0
## Portails au bord de la carte, au bout de la grand-rue.
const PORTAL_OREE := Vector2(5.0, AVENUE_Z)
const PORTAL_CEMETERY := Vector2(127.0, AVENUE_Z)
## Arrivées depuis les autres cartes : sur leur portail vers le village (même convention que
## l'Orée), soit le portail est de l'Orée et le portail ouest du Chemin du cimetière.
const OREE_ARRIVAL := Vector2(442.0, 135.0)
const CEMETERY_ARRIVAL := Vector2(6.0, 18.0)
const PLAYER_SPAWN := Vector2(72.5, 52.5)
const WELL := Vector2(103.5, 23.0)

## Positions actuelles de personnages sur cette carte (base de dev) : gardées praticables.
const KEEP_CLEAR := [Vector2(52.5, 17.5), Vector2(32.0, 60.5), Vector2(22.5, 67.5), Vector2(40.1, 20.9)]

## Codes terrain internes -> noms d'items de la MeshLibrary.
enum T { GRASS, FOREST, DIRT, PAVED, TREE, RAMPART, BUILDING, FORGE, CROP }
const T_NAMES := ["grass", "forestFloor", "dirtPath", "pavedStone", "tree", "rampart", "auberge", "forge", "fieldCrop"]

## Bâtiments : [scène, position, orientation (degrés, 0 = porte au sud), terrain, nom].
var BUILDINGS := [
	["Inn", Vector2(40.0, 35.9), 0.0, T.BUILDING, "Auberge"],
	["Forge", Vector2(101.5, 36.9), 0.0, T.FORGE, "Forge"],
	["HouseLarge", Vector2(39.5, 24.5), 0.0, T.BUILDING, "Maison_NO"],
	["HouseMedium", Vector2(55.5, 25.0), 0.0, T.BUILDING, "Maison_N1"],
	["HouseSmall", Vector2(64.0, 24.5), 0.0, T.BUILDING, "Maison_N2"],
	["HouseSmall", Vector2(80.0, 24.5), 0.0, T.BUILDING, "Maison_N3"],
	["HouseMedium", Vector2(88.5, 25.0), 0.0, T.BUILDING, "Maison_N4"],
	["HouseLarge", Vector2(39.5, 55.5), 180.0, T.BUILDING, "Maison_SO"],
	["HouseMedium", Vector2(56.0, 64.0), 180.0, T.BUILDING, "Maison_S1"],
	["HouseSmall", Vector2(64.5, 64.5), 180.0, T.BUILDING, "Maison_S2"],
	["HouseSmall", Vector2(79.5, 64.5), 180.0, T.BUILDING, "Maison_S3"],
	["HouseMedium", Vector2(88.0, 64.0), 180.0, T.BUILDING, "Maison_S4"],
	["HouseLarge", Vector2(104.5, 55.5), 180.0, T.BUILDING, "Corps_de_garde"],
]
## Jardins : [rectangle, nombre d'arbres, clos et cultivé (potager) ?, nom].
var GARDENS := [
	[Rect2(34.0, 63.0, 12.0, 9.0), 6, false, "Verger"],
	[Rect2(98.0, 63.0, 12.0, 9.0), 0, true, "Potager"],
	[Rect2(97.0, 18.0, 13.0, 10.0), 3, false, "Jardin_du_puits"],
]

var _terrain := PackedByteArray()
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _root: MapData
var _props: Node3D
var _objects: Node3D
## [nœud, terrain] : le terrain est peint sous l'emprise du nœud une fois la scène dans l'arbre.
var _terrain_under: Array = []
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_generate_layout()
		_build_scene()
		root.add_child(_root)
		return false
	if _frames >= 2 and not _done and is_instance_valid(_root):
		_done = true
		_write_scene()
	return true


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _generate_layout() -> void:
	_rng.seed = SEED
	_noise.seed = SEED
	_noise.frequency = 0.12
	_terrain.resize(W * H)
	for z in H:
		for x in W:
			_terrain[z * W + x] = _ground_at(x, z)


func _ground_at(x: int, z: int) -> int:
	var p := Vector2(x + 0.5, z + 0.5)
	var wobble := _noise.get_noise_2d(x, z)
	var inside := p.x > WALL_X0 + 1.2 and p.x < WALL_X1 - 1.2 and p.y > WALL_Z0 + 1.2 and p.y < WALL_Z1 - 1.2
	# Dalle sous les téléporteurs ; grand-rue pavée de bout en bout dans l'enceinte et vers
	# l'ouest (route de l'Orée), chemin de terre à l'est (vers le cimetière).
	if p.distance_to(PORTAL_OREE) <= 3.6 or p.distance_to(PORTAL_CEMETERY) <= 3.6:
		return T.PAVED
	if absf(p.y - AVENUE_Z) <= 2.5:
		if p.x <= WALL_X1 + 1.3:
			return T.PAVED
		if absf(p.y - AVENUE_Z) <= 1.6 + wobble * 0.4:
			return T.DIRT
	if not inside:
		var edge := mini(mini(x, z), mini(W - 1 - x, H - 1 - z))
		if absf(p.y - AVENUE_Z) <= 4.0 and (p.x < WALL_X0 or p.x > WALL_X1):
			return T.GRASS
		return T.FOREST if edge < 10 + int(wobble * 3.0) else T.GRASS
	if _in_square(p) or (absf(p.x - STREET_X) <= 2.0 and p.y > WALL_Z0 and p.y < WALL_Z1):
		return T.PAVED
	# Ruelles de terre au pied des remparts et entre les îlots.
	var ring := minf(minf(absf(p.x - (WALL_X0 + 5.0)), absf(p.x - (WALL_X1 - 5.0))),
			minf(absf(p.y - (WALL_Z0 + 5.0)), absf(p.y - (WALL_Z1 - 5.0))))
	var cross := minf(absf(p.x - 49.0), absf(p.x - 95.0))
	if ring <= 1.4 + wobble * 0.35 or cross <= 1.3 + wobble * 0.3:
		return T.DIRT
	return T.GRASS


func _in_square(p: Vector2) -> bool:
	if not SQUARE.has_point(p):
		return false
	var dx := minf(p.x - SQUARE.position.x, SQUARE.end.x - p.x)
	var dz := minf(p.y - SQUARE.position.y, SQUARE.end.y - p.y)
	return dx + dz >= SQUARE_CHAMFER


# ---------------------------------------------------------------------------
# 2. Scène : GridMap, props, marqueurs
# ---------------------------------------------------------------------------

func _build_scene() -> void:
	_root = MapData.new()
	_root.name = "Place_du_village"
	_root.map_id = MAP_ID
	_root.map_name = MAP_NAME
	_root.description = DESCRIPTION
	_root.is_starting_map = true
	_root.is_town = true
	_root.render_obstacle_blocks = false

	var grid := GridMap.new()
	grid.name = "Terrain"
	grid.mesh_library = load(LIBRARY_PATH)
	grid.cell_size = Vector3.ONE
	grid.cell_center_y = false
	_add(_root, grid)

	_props = _add(_root, _node("Props"))
	_objects = _add(_root, _node("Objects"))

	_place_ramparts()
	var fountain := _instance("Fountain", _props, FOUNTAIN, 0.0)
	fountain.name = "Fontaine"
	# Obélisques aux diagonales : la route passe entre eux jusqu'au centre du portail.
	var teleporters := _add(_props, _node("Teleporteurs"))
	_instance("Teleporter", teleporters, PORTAL_OREE, 0.0).name = "Teleporteur_Oree"
	_instance("Teleporter", teleporters, PORTAL_CEMETERY, 0.0).name = "Teleporteur_Cimetiere"
	_place_buildings()
	_place_gardens()
	_place_market()
	_place_lamps()
	_place_signs()
	_place_markers()


func _place_ramparts() -> void:
	var group := _add(_props, _node("Remparts"))
	var walls := _add(group, _node("Courtines"))
	var towers := _add(group, _node("Tours"))
	var nw := Vector2(WALL_X0, WALL_Z0)
	var ne := Vector2(WALL_X1, WALL_Z0)
	var se := Vector2(WALL_X1, WALL_Z1)
	var sw := Vector2(WALL_X0, WALL_Z1)
	var center := Vector2((WALL_X0 + WALL_X1) / 2.0, (WALL_Z0 + WALL_Z1) / 2.0)
	# Ouvrages de chaque côté, dans l'ordre : [position, demi-longueur le long du mur, scène].
	var sides := [
		[[nw, 3.0, ""], [Vector2(49, WALL_Z0), 3.0, "RampartTower"], [Vector2(72, WALL_Z0), 3.0, "RampartTowerRoofed"],
				[Vector2(95, WALL_Z0), 3.0, "RampartTower"], [ne, 3.0, ""]],
		[[ne, 3.0, ""], [Vector2(WALL_X1, 29), 3.0, "RampartTower"], [Vector2(WALL_X1, AVENUE_Z), 6.5, "Gatehouse"],
				[Vector2(WALL_X1, 63), 3.0, "RampartTower"], [se, 3.0, ""]],
		[[se, 3.0, ""], [Vector2(95, WALL_Z1), 3.0, "RampartTower"], [Vector2(72, WALL_Z1), 3.0, "RampartTower"],
				[Vector2(49, WALL_Z1), 3.0, "RampartTower"], [sw, 3.0, ""]],
		[[sw, 3.0, ""], [Vector2(WALL_X0, 63), 3.0, "RampartTower"], [Vector2(WALL_X0, AVENUE_Z), 6.5, "Gatehouse"],
				[Vector2(WALL_X0, 29), 3.0, "RampartTower"], [nw, 3.0, ""]],
	]
	for corner in [nw, ne, se, sw]:
		_rampart(towers, "RampartTowerRoofed", corner, center)
	for side in sides:
		for k in side.size():
			var feature: Array = side[k]
			if not (feature[2] as String).is_empty():
				var node := _rampart(towers if feature[2] != "Gatehouse" else group, feature[2], feature[0], center)
				if feature[2] == "Gatehouse":
					node.name = "Porte_Ouest" if (feature[0] as Vector2).x < center.x else "Porte_Est"
			if k == 0:
				continue
			var prev: Array = side[k - 1]
			var a: Vector2 = prev[0]
			var b: Vector2 = feature[0]
			var dir := (b - a).normalized()
			_wall_run(walls, a + dir * (prev[1] - 1.0), b - dir * (feature[1] - 1.0))


## Tour ou porte, face intérieure (+Y Blender = -Z Godot du modèle) tournée vers `center`.
func _rampart(parent: Node, scene: String, pos: Vector2, center: Vector2) -> Node3D:
	var inward := center - pos
	if scene == "Gatehouse":
		inward = Vector2(signf(inward.x), 0.0)
	elif absf(pos.x - WALL_X0) > 0.1 and absf(pos.x - WALL_X1) > 0.1:
		inward = Vector2(0.0, signf(inward.y))
	elif absf(pos.y - WALL_Z0) > 0.1 and absf(pos.y - WALL_Z1) > 0.1:
		inward = Vector2(signf(inward.x), 0.0)
	var node := _instance(scene, parent, pos, atan2(-inward.x, -inward.y))
	_terrain_under.append([node, T.RAMPART])
	return node


## Tronçons de courtine de a à b (modèle de 4 m étiré pour tomber juste).
func _wall_run(parent: Node, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var count := maxi(1, roundi(length / 4.0))
	var seg := length / count
	var dir := (b - a) / length
	for i in count:
		var node := _instance("RampartWall", parent, a + dir * seg * (i + 0.5), atan2(-dir.y, dir.x))
		node.scale = Vector3(seg / 4.0, 1.0, 1.0)
		_terrain_under.append([node, T.RAMPART])


func _place_buildings() -> void:
	var group := _add(_props, _node("Batiments"))
	for b in BUILDINGS:
		var node := _instance(b[0], group, b[1], deg_to_rad(b[2]))
		node.name = b[4]
		_terrain_under.append([node, b[3]])
	# Abords : tonneaux et caisses de l'auberge, bois de chauffe et caisses de la forge.
	var clutter := _add(_props, _node("Abords"))
	for entry in [["Barrel", Vector2(33.0, 39.2)], ["Barrel", Vector2(33.1, 38.3)], ["Crate", Vector2(33.2, 37.2)],
			["Barrel", Vector2(46.9, 39.3)], ["LogPile", Vector2(111.0, 36.0)], ["Crate", Vector2(110.6, 39.4)],
			["Crate", Vector2(110.8, 40.3)], ["Barrel", Vector2(97.2, 41.0)], ["Crate", Vector2(68.2, 29.6)],
			["Barrel", Vector2(45.4, 58.9)], ["Crate", Vector2(108.9, 59.5)], ["Barrel", Vector2(109.9, 59.4)]]:
		var yaw := PI / 2.0 if entry[0] == "LogPile" else _rng.randf() * TAU
		_instance(entry[0], clutter, entry[1], yaw)


func _place_gardens() -> void:
	var group := _add(_props, _node("Jardins"))
	for garden in GARDENS:
		var rect: Rect2 = garden[0]
		var node := _add(group, _node(garden[3]))
		var planted := 0
		var tries := 0
		while planted < garden[1] and tries < 400:
			tries += 1
			var p := Vector2(_rng.randf_range(rect.position.x + 1.5, rect.end.x - 1.5),
					_rng.randf_range(rect.position.y + 1.5, rect.end.y - 1.5))
			var cell := Vector2i(int(p.x), int(p.y))
			if _near_keep_clear(p, 2.0) or _has_tree_within(cell, 2) or p.distance_to(WELL) < 4.5:
				continue
			_terrain[cell.y * W + cell.x] = T.TREE
			planted += 1
		if garden[2]:
			_fence_rect(node, rect)
			# Planches de culture, une allée au milieu.
			for z in range(int(rect.position.y) + 1, int(rect.end.y) - 1):
				for x in range(int(rect.position.x) + 1, int(rect.end.x) - 1):
					if absf(x + 0.5 - rect.get_center().x) > 1.0:
						_terrain[z * W + x] = T.CROP
	# Puits au milieu du jardin nord-est ; quelques arbres isolés au pied des remparts.
	_instance("Well", group, WELL, 0.3)
	for p in [Vector2(35.5, 19.6), Vector2(46.5, 29.5), Vector2(93.3, 29.5), Vector2(110.5, 31.5),
			Vector2(111.0, 70.5), Vector2(50.6, 71.5), Vector2(92.5, 71.5), Vector2(33.5, 60.5)]:
		var cell := Vector2i(int(p.x), int(p.y))
		if _terrain[cell.y * W + cell.x] == T.GRASS:
			_terrain[cell.y * W + cell.x] = T.TREE


## Clôture sur le pourtour de `rect`, avec un portillon au milieu du côté nord.
func _fence_rect(parent: Node, rect: Rect2) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var length := a.distance_to(b)
		var count := roundi(length / 2.0)
		var dir := (b - a) / length
		for i in count:
			if k == 0 and i == count / 2:
				continue
			var p := a + dir * (length / count) * (i + 0.5)
			var node := _instance("Fence", parent, p, atan2(-dir.y, dir.x))
			node.scale = Vector3(length / count / 2.0, 1.0, 1.0)


func _place_market() -> void:
	var group := _add(_props, _node("Marche"))
	_instance("MarketStallRed", group, Vector2(62.0, 54.3), PI)
	_instance("MarketStallBlue", group, Vector2(82.0, 54.3), PI)
	_instance("MarketStallBlue", group, Vector2(62.5, 38.8), 0.0)
	_instance("MarketStallRed", group, Vector2(81.5, 38.8), 0.0)
	_instance("Barrel", group, Vector2(60.2, 37.8), 0.0)
	_instance("Crate", group, Vector2(83.8, 37.9), 0.4)
	_instance("Crate", group, Vector2(64.3, 55.2), 0.3)
	_instance("Barrel", group, Vector2(59.6, 55.4), 0.0)
	_instance("Crate", group, Vector2(84.4, 55.0), -0.2)
	_instance("Crate", group, Vector2(84.5, 55.9), 0.5)


func _place_lamps() -> void:
	var lamps := _add(_props, _node("Lampadaires"))
	# Grand-rue : alternance nord/sud, crosse vers la chaussée.
	for x in [35.0, 46.0, 98.0, 109.0]:
		_lamp(lamps, Vector2(x, AVENUE_Z - 3.6), Vector2(0, 1))
	for x in [34.0, 52.0, 92.0, 110.0]:
		_lamp(lamps, Vector2(x, AVENUE_Z + 3.6), Vector2(0, -1))
	# Autour de la fontaine.
	for k in 4:
		var ang := PI / 4.0 + k * PI / 2.0
		var dir := Vector2(cos(ang), sin(ang))
		_lamp(lamps, FOUNTAIN + dir * 7.5, -dir)
	# Rue nord-sud.
	for entry in [[20.0, -1.0], [30.0, 1.0], [62.0, -1.0], [72.0, 1.0]]:
		_lamp(lamps, Vector2(STREET_X + entry[1] * 2.6, entry[0]), Vector2(-entry[1], 0))
	# Portes : de part et d'autre du passage, dedans et dehors.
	for gate_x in [WALL_X0, WALL_X1]:
		var inward := 1.0 if gate_x == WALL_X0 else -1.0
		for out in [-1.0, 1.0]:
			for s in [-1.0, 1.0]:
				_lamp(lamps, Vector2(gate_x + inward * out * 3.4, AVENUE_Z + s * 4.2), Vector2(0, -s))


func _lamp(parent: Node3D, pos: Vector2, arm_dir: Vector2) -> void:
	# +X du modèle (la crosse) orienté vers arm_dir : rotation Y = atan2(-dz, dx).
	_instance("LampPost", parent, pos, atan2(-arm_dir.y, arm_dir.x))


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	var at := Vector2(69.0, 53.6)
	_sign(signs, "Place", at, [["Orée de la forêt", _heading(at, Vector2(WALL_X0, AVENUE_Z))],
			["Chemin du cimetière", _heading(at, Vector2(WALL_X1, AVENUE_Z))], ["Auberge", _heading(at, Vector2(40, 42))],
			["Forge", _heading(at, Vector2(104, 42))]])
	_sign(signs, "TeleporteurOuest", Vector2(9.0, AVENUE_Z - 4.9), [["Orée de la forêt", 180.0], ["Place du village", 0.0]])
	_sign(signs, "TeleporteurEst", Vector2(123.0, AVENUE_Z - 4.9), [["Chemin du cimetière", 0.0], ["Place du village", 180.0]])
	_sign(signs, "PorteOuest", Vector2(WALL_X0 + 5.5, AVENUE_Z - 4.4), [["Place du village", 0.0],
			["Auberge", _heading(Vector2(WALL_X0 + 5.5, AVENUE_Z - 4.4), Vector2(40, 42))]])
	_sign(signs, "PorteEst", Vector2(WALL_X1 - 5.5, AVENUE_Z - 4.4), [["Place du village", 180.0],
			["Forge", _heading(Vector2(WALL_X1 - 5.5, AVENUE_Z - 4.4), Vector2(104, 42))]])


func _sign(parent: Node3D, sign_name: String, pos: Vector2, entries: Array) -> void:
	var sign := _instance("Signpost", parent, pos, 0.0)
	sign.name = "Panneau_" + sign_name
	sign.scale = Vector3.ONE * 1.2
	var list := PackedStringArray()
	for e in entries:
		list.append("%s|%d" % [e[0], int(roundf(fposmod(e[1], 360.0)))])
	sign.destinations = list


func _place_markers() -> void:
	_add(_objects, _marker("PlayerSpawn", "res://map_objects/PlayerSpawnMarker3D.gd", PLAYER_SPAWN))
	var west := _marker("Portal_O", "res://map_objects/PortalMarker3D.gd", PORTAL_OREE)
	west.direction = "O"
	west.target_map_id = OREE_ID
	west.target_x = OREE_ARRIVAL.x * 32.0
	west.target_y = OREE_ARRIVAL.y * 32.0
	_add(_objects, west)
	var east := _marker("Portal_E", "res://map_objects/PortalMarker3D.gd", PORTAL_CEMETERY)
	east.direction = "E"
	east.target_map_id = CEMETERY_PATH_ID
	east.target_x = CEMETERY_ARRIVAL.x * 32.0
	east.target_y = CEMETERY_ARRIVAL.y * 32.0
	_add(_objects, east)
	var npcs := [
		["Aubergiste", INNKEEPER_ID, Vector2(40.5, 43.4)],
		["Forgeron", BLACKSMITH_ID, Vector2(106.5, 42.4)],
		["GardePorte_O1", GATE_GUARD_IDS[0], Vector2(30.5, 43.8)],
		["GardePorte_O2", GATE_GUARD_IDS[1], Vector2(30.5, 48.2)],
		["GardePorte_E1", GATE_GUARD_IDS[2], Vector2(113.5, 43.8)],
		["GardePorte_E2", GATE_GUARD_IDS[3], Vector2(113.5, 48.2)],
		["Garde_PlaceO", VILLAGE_GUARD_IDS[0], Vector2(57.6, 44.0)],
		["Garde_PlaceE", VILLAGE_GUARD_IDS[1], Vector2(86.4, 44.0)],
		["Garde_RueNord", VILLAGE_GUARD_IDS[2], Vector2(71.0, 21.5)],
		["Garde_RueSud", VILLAGE_GUARD_IDS[3], Vector2(73.0, 70.5)],
		["MaitreCompetences", SKILL_LEARNER_ID, Vector2(75.5, 55.4)],
	]
	for entry in npcs:
		var m := _marker("NpcSpawn_" + entry[0], "res://map_objects/NpcSpawnMarker3D.gd", entry[2])
		m.npc_id = entry[1]
		_add(_objects, m)
	var peace := Node3D.new()
	peace.name = "Peace_Zone"
	peace.set_script(load("res://map_objects/PeaceZoneMarker3D.gd"))
	peace.zone_name = "Peace Zone"
	peace.polygon_points = PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)])
	_add(_objects, peace)


# ---------------------------------------------------------------------------
# 3. Finalisation (scène dans l'arbre : emprises des props calculables)
# ---------------------------------------------------------------------------

func _write_scene() -> void:
	var blocked := {}
	for node in _root.get_tree().get_nodes_in_group(ObstacleFootprint3D.GROUP):
		if not (node as ObstacleFootprint3D).blocks_movement:
			continue
		for cell in (node as ObstacleFootprint3D).blocked_cells():
			blocked[cell] = true
	# Terrain sous les ouvrages (minimap), aucun arbre sous un prop.
	for entry in _terrain_under:
		for fp in (entry[0] as Node).find_children("*", "ObstacleFootprint3D", true, false):
			for cell in (fp as ObstacleFootprint3D).blocked_cells():
				if _in_map(cell):
					_terrain[cell.y * W + cell.x] = entry[1]
	for cell in blocked:
		if _in_map(cell) and _terrain[cell.y * W + cell.x] == T.TREE:
			_terrain[cell.y * W + cell.x] = T.GRASS
	_plant_outer_forest(blocked)
	if not _validate(blocked):
		_root.free()
		quit(1)
		return
	_write_grid(_root.get_node("Terrain"))

	var ground := TerrainGround.new()
	ground.name = "Ground"
	ground.paved_asset = "PavingStones151"
	ground.paved_tile = Vector2(3.6, 3.6)
	ground.paved_desaturate = 0.35
	ground.paved_tint = Color(0.74, 0.72, 0.7)
	var vegetation := Vegetation.new()
	vegetation.name = "Vegetation"
	vegetation.seed = SEED
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
	var trees := 0
	for t in _terrain:
		if t == T.TREE:
			trees += 1
	print("Scène écrite : %s (%dx%d, %d arbres, %d cases bloquées par des props)" % [OUT_PATH, W, H, trees, blocked.size()])
	_root.free()
	quit()


## Hors les murs : forêt dense sur les bords de la carte, qui s'éclaircit vers les remparts ;
## jamais sur la route ni à moins de 4 m du pied des murs.
func _plant_outer_forest(blocked: Dictionary) -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			var t := _terrain[i]
			if t != T.GRASS and t != T.FOREST:
				continue
			var p := Vector2(x + 0.5, z + 0.5)
			var wall_d := _distance_outside_walls(p)
			if wall_d <= 4.0 or blocked.has(Vector2i(x, z)) or absf(p.y - AVENUE_Z) <= 4.5:
				continue
			# Prés dégagés devant les portes et autour des téléporteurs.
			if p.distance_to(Vector2(WALL_X0 - 3.0, AVENUE_Z)) < 11.0 or p.distance_to(Vector2(WALL_X1 + 3.0, AVENUE_Z)) < 11.0:
				continue
			if p.distance_to(PORTAL_OREE) < 8.0 or p.distance_to(PORTAL_CEMETERY) < 8.0 or _near_keep_clear(p, 2.0):
				continue
			var edge := mini(mini(x, z), mini(W - 1 - x, H - 1 - z))
			var prob := 0.05
			if edge < 5:
				prob = 0.85
			elif edge < 9:
				prob = 0.4
			if _rng.randf() < prob and (edge < 5 or not _has_tree_within(Vector2i(x, z), 1)):
				_terrain[i] = T.TREE


func _distance_outside_walls(p: Vector2) -> float:
	var dx := maxf(WALL_X0 - p.x, p.x - WALL_X1)
	var dz := maxf(WALL_Z0 - p.y, p.y - WALL_Z1)
	if dx <= 0.0 and dz <= 0.0:
		return -1.0
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


## Tous les points importants doivent être praticables et reliés au point d'apparition.
func _validate(blocked: Dictionary) -> bool:
	var walkable := func(i: int) -> bool:
		return not ZoneAssets3D.BLOCKING_TERRAINS.has(T_NAMES[_terrain[i]]) and not blocked.has(Vector2i(i % W, i / W))
	var reached := _flood(int(PLAYER_SPAWN.y) * W + int(PLAYER_SPAWN.x), walkable)
	var checks := {"Portail Orée": PORTAL_OREE, "Portail cimetière": PORTAL_CEMETERY,
			"Porte ouest (dehors)": Vector2(WALL_X0 - 4.0, AVENUE_Z), "Porte est (dehors)": Vector2(WALL_X1 + 4.0, AVENUE_Z)}
	for m in _objects.get_children():
		if m.get_script() == load("res://map_objects/NpcSpawnMarker3D.gd"):
			checks[String(m.name)] = Vector2(m.position.x, m.position.z)
	for b in BUILDINGS:
		var yaw := deg_to_rad(b[2])
		var depth: float = {"Inn": 6.9, "Forge": 4.1, "HouseLarge": 4.3, "HouseMedium": 4.0, "HouseSmall": 3.5}[b[0]]
		checks["Porte " + b[4]] = (b[1] as Vector2) + Vector2(sin(yaw), cos(yaw)) * depth
	for k in KEEP_CLEAR.size():
		checks["Perso de dev %d" % k] = KEEP_CLEAR[k]
	var ok := true
	for label in checks:
		var p: Vector2 = checks[label]
		var i := int(p.y) * W + int(p.x)
		if reached[i] == 0:
			printerr("Inaccessible depuis le point d'apparition : %s (%.1f, %.1f)" % [label, p.x, p.y])
			ok = false
	var reach_count := 0
	for r in reached:
		reach_count += r
	print("Cases praticables reliées au spawn : %d" % reach_count)
	return ok


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _write_grid(grid: GridMap) -> void:
	var library: MeshLibrary = grid.mesh_library
	var ids := []
	for t_name in T_NAMES:
		ids.append(library.find_item_by_name(t_name))
	grid.clear()
	for z in H:
		for x in W:
			grid.set_cell_item(Vector3i(x, 0, z), ids[_terrain[z * W + x]])


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


func _in_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _has_tree_within(cell: Vector2i, radius: int) -> bool:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := cell + Vector2i(dx, dz)
			if (dx != 0 or dz != 0) and _in_map(c) and _terrain[c.y * W + c.x] == T.TREE:
				return true
	return false


func _near_keep_clear(p: Vector2, radius: float) -> bool:
	for k in KEEP_CLEAR:
		if (k as Vector2).distance_to(p) < radius:
			return true
	return false


func _node(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	return n


func _add(parent: Node, child: Node) -> Node:
	parent.add_child(child, true)
	child.owner = _root
	return child


func _instance(scene: String, parent: Node, pos: Vector2, yaw: float) -> Node3D:
	var inst: Node3D = (load(PROPS + scene + ".tscn") as PackedScene).instantiate()
	inst.position = Vector3(pos.x, 0.0, pos.y)
	inst.rotation.y = yaw
	parent.add_child(inst, true)
	inst.owner = _root
	return inst


func _marker(marker_name: String, script_path: String, pos: Vector2) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.set_script(load(script_path))
	m.position = Vector3(pos.x, 0.0, pos.y)
	return m


## Direction carte (degrés : 0 = est, 90 = sud) de a vers b.
func _heading(a: Vector2, b: Vector2) -> float:
	return rad_to_deg((b - a).angle())
