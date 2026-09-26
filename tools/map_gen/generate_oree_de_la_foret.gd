extends SceneTree
## Outil hors-ligne : génère la scène res://scenes/maps/Orée_de_la_forêt.tscn (450 x 270
## cases) — point de départ de la carte, à retoucher ensuite librement dans l'éditeur Godot
## (pinceau GridMap, props déplaçables), puis à exporter vers le serveur avec
## tools/export_map_to_tmx.gd. Relancer ce script ÉCRASE la scène.
##
## Disposition :
##   - portail vers la Clairière à l'extrême ouest, portail vers la Place du village à
##     l'extrême est (ville à droite de la carte), reliés par une vieille route pavée
##     sinueuse, bordée de lampadaires ;
##   - au milieu de la route, une place pavée avec une fontaine ;
##   - partout ailleurs, la forêt (chênes, sapins, bouleaux en lisière ; fourrés
##     infranchissables le long des bords), percée de clairières reliées par des chemins de
##     terre en boucles ; une scierie abandonnée au nord, au bout d'un chemin de terre ;
##   - des panneaux indicateurs à chaque embranchement ;
##   - 300 points de spawn de monstres (Fox / Brown Keltir) en forêt et dans les clairières,
##     jamais sur la route, la place ou près des portails.
## Toute zone praticable d'une certaine taille est garantie accessible depuis le point de
## spawn joueur (une trouée est creusée dans les arbres vers les grandes poches enclavées) ;
## les petites poches isolées restent telles quelles (inaccessibles, sans spawn).
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_oree_de_la_foret.gd

const OUT_PATH := "res://scenes/maps/Orée_de_la_forêt.tscn"
const LIBRARY_PATH := "res://assets/terrain/terrain_library.res"
const W := 450
const H := 270
const SEED := 20260926

const MAP_ID := "9a884ac7-b954-4cd6-ab67-c677d472cb0f"
const MAP_NAME := "Orée de la forêt"
const DESCRIPTION := "Une vieille route pavée traverse la forêt, de la Clairière jusqu'aux portes du village. Une fontaine en marque le milieu ; des sentiers de terre s'enfoncent sous les arbres, jusqu'à une scierie abandonnée."
const CLAIRIERE_ID := "7f55fd0c-23f8-4a3b-82a2-95a79bdbf2b5"
const VILLAGE_ID := "5e4ada37-37e1-438c-9233-581f10c055c7"
const FOX_ID := "0a88e27c-5487-40d5-b494-b7ea49148171"
const KELTIR_ID := "de87e00a-eb3f-4885-b6a4-922c426d5fb8"
const SPAWN_GROUP := "Orée_de_la_forêt"
const MONSTER_SPAWNS := 300

const PORTAL_WEST := Vector2(8.0, 135.0)
const PORTAL_EAST := Vector2(442.0, 135.0)
const FOUNTAIN := Vector2(225.0, 135.0)
const PLAYER_SPAWN := Vector2(225.5, 144.5)
const SAWMILL := Vector2(168.0, 46.0)
const SAWMILL_YAW_DEG := 56.0

## Positions actuelles de personnages sur cette carte (base de dev) : gardées praticables.
const KEEP_CLEAR := [Vector2(128.15, 106.89), Vector2(27.75, 15.82), Vector2(22, 10), Vector2(38, 26),
		Vector2(23, 11), Vector2(54, 18), Vector2(50, 92)]

## Codes terrain internes -> noms d'items de la MeshLibrary.
enum T { GRASS, FOREST, DIRT, PAVED, TREE }
const T_NAMES := ["grass", "forestFloor", "dirtPath", "pavedStone", "tree"]

## Prolongée au-delà des deux bords : la route sort visuellement de la carte (voir
## TerrainGround.margin / Vegetation.outer_margin) vers la Clairière et le village.
const ROAD := [Vector2(-6, 135), Vector2(8, 135), Vector2(30, 134), Vector2(58, 129), Vector2(90, 126), Vector2(122, 131),
		Vector2(156, 141), Vector2(190, 139), Vector2(225, 135), Vector2(258, 130), Vector2(292, 124),
		Vector2(330, 129), Vector2(368, 141), Vector2(404, 140), Vector2(442, 135), Vector2(456, 135)]

## Chemins de terre : [nom, points]. Le premier point est sur la route/la place.
var DIRT_PATHS := [
	["sawmill", [Vector2(225, 126), Vector2(222, 110), Vector2(209, 96), Vector2(213, 81), Vector2(199, 69), Vector2(186, 60)]],
	["south_loop", [Vector2(225, 144), Vector2(232, 163), Vector2(222, 184), Vector2(237, 204), Vector2(262, 220),
			Vector2(290, 214), Vector2(317, 199), Vector2(337, 179), Vector2(344, 158), Vector2(338, 131)]],
	["west", [Vector2(94, 126), Vector2(92, 109), Vector2(80, 92), Vector2(86, 73), Vector2(72, 55)]],
	["west_sawmill", [Vector2(86, 73), Vector2(108, 64), Vector2(132, 58), Vector2(150, 55)]],
	["south_west", [Vector2(60, 129), Vector2(64, 152), Vector2(52, 174), Vector2(62, 198), Vector2(50, 222)]],
	["east_north", [Vector2(384, 140), Vector2(388, 120), Vector2(399, 100), Vector2(391, 80), Vector2(402, 60)]],
	["east_south", [Vector2(410, 139), Vector2(415, 160), Vector2(405, 181), Vector2(420, 203)]],
	["glade_link", [Vector2(262, 220), Vector2(240, 236), Vector2(205, 232), Vector2(180, 214), Vector2(160, 196)]],
]
## Clairières : [centre, rayon, nom affiché sur les panneaux].
var GLADES := [
	[SAWMILL, 21.0, "Scierie abandonnée"],
	[Vector2(263, 222), 12.0, "Clairière du Vieux Chêne"],
	[Vector2(70, 52), 13.0, "Bois des Renards"],
	[Vector2(49, 225), 11.0, "Vallon moussu"],
	[Vector2(401, 57), 14.0, "Rochers de l'Est"],
	[Vector2(421, 206), 10.0, "Sous-bois"],
	[Vector2(158, 194), 10.0, "Mare aux Keltirs"],
]

var _terrain := PackedByteArray()
var _road_d := PackedFloat32Array()
var _dirt_d := PackedFloat32Array()
var _open_d := PackedFloat32Array()  # distance hors des zones à garder sans arbre
var _plaza_d := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _density := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _root: MapData
var _props: Node3D
var _objects: Node3D
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
# 1. Plan de la carte (champs de distance + terrain + arbres)
# ---------------------------------------------------------------------------

func _generate_layout() -> void:
	_rng.seed = SEED
	_noise.seed = SEED
	_noise.frequency = 0.09
	_density.seed = SEED + 1
	_density.frequency = 0.02
	_density.fractal_octaves = 3
	var n := W * H
	_terrain.resize(n)
	for arr in [_road_d, _dirt_d, _open_d, _plaza_d]:
		arr.resize(n)
		arr.fill(INF)

	# Route pavée : bande dégagée large (accotements d'herbe, lampadaires).
	for p in _sample(ROAD, 0.5):
		_stamp(_road_d, p, 0.0, 12.0)
		_stamp(_open_d, p, 6.5, 14.0)
	_stamp(_plaza_d, FOUNTAIN, 0.0, 26.0)
	_stamp(_open_d, FOUNTAIN, 20.0, 30.0)
	for portal in [PORTAL_WEST, PORTAL_EAST]:
		_stamp(_plaza_d, portal, 0.0, 12.0)
		_stamp(_open_d, portal, 13.0, 22.0)
	for path in DIRT_PATHS:
		for p in _sample(path[1], 0.5):
			_stamp(_dirt_d, p, 0.0, 6.0)
			_stamp(_open_d, p, 2.8, 8.0)
	for glade in GLADES:
		_stamp_blob(_open_d, glade[0], glade[1])
	for i in 14:
		var c := _random_forest_point(30.0)
		_stamp_blob(_open_d, c, _rng.randf_range(4.0, 8.0))
	for p in KEEP_CLEAR:
		_stamp(_open_d, p, 1.6, 4.0)

	# Terrain au sol.
	for z in H:
		for x in W:
			var i := z * W + x
			var wobble := _noise.get_noise_2d(x, z)
			var d := _density_at(x, z)
			var t := T.FOREST if d > 0.42 + wobble * 0.08 else T.GRASS
			if _open_d[i] <= 0.0:
				t = T.GRASS
			if _dirt_d[i] <= 1.35 + wobble * 0.3:
				t = T.DIRT
			var plaza := _plaza_d[i]
			var fountain_r := 9.5 + wobble * 0.8
			if _road_d[i] <= 2.25 + wobble * 0.25 or (plaza <= fountain_r and FOUNTAIN.distance_to(Vector2(x, z)) < 27.0) \
					or (plaza <= 5.5 + wobble and _is_near_portal(x, z)):
				t = T.PAVED
			_terrain[i] = t
	# Terre battue devant la scierie (chantier).
	var front := Vector2(sin(deg_to_rad(SAWMILL_YAW_DEG)), cos(deg_to_rad(SAWMILL_YAW_DEG)))
	_paint_blob(SAWMILL + front * 6.0, 7.0, T.DIRT)
	_paint_blob(SAWMILL, 7.5, T.DIRT)

	_place_trees()


func _place_trees() -> void:
	var order := range(W * H)
	# Ordre pseudo-aléatoire déterministe (Fisher-Yates) : aucun biais de balayage.
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in order:
		var x: int = i % W
		var z: int = i / W
		if _terrain[i] == T.PAVED or _terrain[i] == T.DIRT:
			continue
		var open := _open_d[i]
		if open <= 0.0:
			continue
		var edge := mini(mini(x, z), mini(W - 1 - x, H - 1 - z))
		var d := _density_at(x, z)
		var thicket := edge < 7 or d > 0.8
		var p := 0.1 + 0.34 * d
		if edge < 7:
			p = 0.9
		elif edge < 12:
			p = maxf(p, 0.45)
		p *= smoothstep(0.0, 5.0, open)
		if _rng.randf() >= p:
			continue
		if not thicket and _has_tree_neighbour(x, z):
			continue
		_terrain[i] = T.TREE


# ---------------------------------------------------------------------------
# 2. Scène : GridMap, props, marqueurs
# ---------------------------------------------------------------------------

func _build_scene() -> void:
	_root = MapData.new()
	_root.name = "Orée_de_la_forêt"
	_root.map_id = MAP_ID
	_root.map_name = MAP_NAME
	_root.description = DESCRIPTION
	_root.biome = MapData.Biome.FOREST
	_root.render_obstacle_blocks = false

	var grid := GridMap.new()
	grid.name = "Terrain"
	grid.mesh_library = load(LIBRARY_PATH)
	grid.cell_size = Vector3.ONE
	grid.cell_center_y = false
	_add(_root, grid)
	_write_grid(grid)

	_props = _add(_root, _node("Props"))
	_objects = _add(_root, _node("Objects"))

	var fountain := _instance("res://scenes/maps/props/Fountain.tscn", _props, FOUNTAIN, 0.0)
	fountain.name = "Fontaine"
	# Socles de téléporteur sous les deux portails (bords de la carte).
	var teleporters := _add(_props, _node("Teleporteurs"))
	_instance("res://scenes/maps/props/Teleporter.tscn", teleporters, PORTAL_WEST, 0.0).name = "Teleporteur_Clairiere"
	_instance("res://scenes/maps/props/Teleporter.tscn", teleporters, PORTAL_EAST, 0.0).name = "Teleporteur_Village"
	_place_lamps()
	_place_signs()
	_place_sawmill()
	_place_forest_props()
	_place_markers_static()


func _place_lamps() -> void:
	var lamps := _add(_props, _node("Lamps"))
	var samples := _sample(ROAD, 0.5)
	var travelled := 0.0
	var side := 1.0
	var next_at := 10.0
	for k in range(1, samples.size()):
		var a: Vector2 = samples[k - 1]
		var b: Vector2 = samples[k]
		travelled += a.distance_to(b)
		if travelled < next_at:
			continue
		next_at += 15.0
		if b.distance_to(FOUNTAIN) < 16.0 or b.distance_to(PORTAL_WEST) < 9.0 or b.distance_to(PORTAL_EAST) < 9.0:
			continue
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x) * side
		side = -side
		_lamp(lamps, b + normal * 3.4, -normal)
	# Place de la fontaine : quatre lampadaires aux diagonales.
	for k in 4:
		var ang := PI / 4.0 + k * PI / 2.0
		var dir := Vector2(cos(ang), sin(ang))
		_lamp(lamps, FOUNTAIN + dir * 10.6, -dir)
	# Encadrement des portails.
	for portal in [PORTAL_WEST, PORTAL_EAST]:
		for s in [-1.0, 1.0]:
			_lamp(lamps, portal + Vector2(2.5 if portal == PORTAL_WEST else -2.5, s * 5.2), Vector2(0.0, -s))
	# Début du chemin de la scierie (le reste, abandonné, n'est plus éclairé).
	var saw_samples := _sample(DIRT_PATHS[0][1], 0.5)
	for k in [16, 48]:
		var a: Vector2 = saw_samples[k - 1]
		var b: Vector2 = saw_samples[k]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x) * (1.0 if k == 16 else -1.0)
		_lamp(lamps, b + normal * 2.4, -normal)


func _lamp(parent: Node3D, pos: Vector2, arm_dir: Vector2) -> void:
	_clear_trees_around(pos, 1.5)
	# +X du modèle (la crosse) orienté vers arm_dir : rotation Y = atan2(-dz, dx).
	_instance("res://scenes/maps/props/LampPost.tscn", parent, pos, atan2(-arm_dir.y, arm_dir.x))


func _place_signs() -> void:
	var signs := _add(_props, _node("Signs"))
	var paths := {}
	for path in DIRT_PATHS:
		paths[path[0]] = path[1]
	var saw: Array = paths["sawmill"]
	var loop: Array = paths["south_loop"]
	_sign(signs, "Fontaine", FOUNTAIN + Vector2(-5.5, -7.2), [
		["Place du village", 0.0], ["Clairière", 180.0],
		["Scierie abandonnée", _heading(FOUNTAIN, saw[1])], ["Clairière du Vieux Chêne", _heading(FOUNTAIN, loop[1])]])
	_sign(signs, "PortailEst", PORTAL_EAST + Vector2(-9.0, -4.5), [["Place du village", 0.0], ["Fontaine", 180.0]])
	_sign(signs, "PortailOuest", PORTAL_WEST + Vector2(9.0, -4.5), [["Clairière", 180.0], ["Fontaine", 0.0]])
	# Embranchements sur la route : destination du chemin + les deux sens de la route.
	for entry in [["west", "Bois des Renards"], ["south_west", "Vallon moussu"],
			["east_north", "Rochers de l'Est"], ["east_south", "Sous-bois"]]:
		var pts: Array = paths[entry[0]]
		var start: Vector2 = pts[0]
		var east_label := "Place du village" if start.x > FOUNTAIN.x else "Fontaine"
		var west_label := "Fontaine" if start.x > FOUNTAIN.x else "Clairière"
		_sign(signs, entry[0], _beside(start, pts[1]), [[entry[1], _heading(start, pts[1])],
				[east_label, _road_heading_toward(start, PORTAL_EAST)], [west_label, _road_heading_toward(start, PORTAL_WEST)]])
	var loop_end: Vector2 = loop[loop.size() - 1]
	_sign(signs, "BoucleSud", _beside(loop_end, loop[loop.size() - 2]), [
		["Clairière du Vieux Chêne", _heading(loop_end, loop[loop.size() - 2])],
		["Place du village", _road_heading_toward(loop_end, PORTAL_EAST)], ["Fontaine", _road_heading_toward(loop_end, PORTAL_WEST)]])
	# Carrefours en forêt.
	var ws: Array = paths["west_sawmill"]
	var west: Array = paths["west"]
	_sign(signs, "CarrefourOuest", _beside(ws[0], ws[1]), [["Scierie abandonnée", _heading(ws[0], ws[1])],
			["Bois des Renards", _heading(ws[0], west[4])], ["Fontaine", _heading(ws[0], west[2])]])
	var saw_end: Vector2 = saw[saw.size() - 1]
	_sign(signs, "Scierie", _beside(saw_end, saw[saw.size() - 2]), [["Fontaine", _heading(saw_end, saw[saw.size() - 2])],
			["Bois des Renards", _heading(saw_end, ws[ws.size() - 2])]])
	var link: Array = paths["glade_link"]
	_sign(signs, "VieuxChene", _beside(link[0], link[1]), [["Mare aux Keltirs", _heading(link[0], link[1])],
			["Fontaine", _heading(loop[4], loop[3])], ["Place du village", _heading(loop[4], loop[5])]])
	var link_end: Vector2 = link[link.size() - 1]
	_sign(signs, "Mare", _beside(link_end, link[link.size() - 2]), [
		["Clairière du Vieux Chêne", _heading(link_end, link[link.size() - 2])]])


## Emplacement d'un panneau à l'entrée d'un chemin : un peu engagé dans le chemin, sur le côté.
func _beside(start: Vector2, toward: Vector2) -> Vector2:
	var dir := (toward - start).normalized()
	return start + dir * 4.0 + Vector2(-dir.y, dir.x) * 3.0


func _sign(parent: Node3D, sign_name: String, pos: Vector2, entries: Array) -> void:
	_clear_trees_around(pos, 1.5)
	var sign := _instance("res://scenes/maps/props/Signpost.tscn", parent, pos, 0.0)
	sign.name = "Panneau_" + sign_name
	sign.scale = Vector3.ONE * 1.3
	var list := PackedStringArray()
	for e in entries:
		list.append("%s|%d" % [e[0], int(roundf(fposmod(e[1], 360.0)))])
	sign.destinations = list


func _place_sawmill() -> void:
	var group := _add(_props, _node("Scierie"))
	var sawmill := _instance("res://scenes/maps/props/Sawmill.tscn", group, SAWMILL, deg_to_rad(SAWMILL_YAW_DEG))
	sawmill.name = "Sawmill"
	# Souches tout autour : la forêt a été exploitée ici.
	for k in 14:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(12.0, 20.0)
		var p := SAWMILL + Vector2(cos(ang), sin(ang)) * r
		if _is_on_path(p, 2.5):
			continue
		_clear_trees_around(p, 1.0)
		_instance("res://scenes/maps/props/Stump.tscn", group, p, _rng.randf() * TAU)
	for p in [SAWMILL + Vector2(-15, 8), SAWMILL + Vector2(14, -12)]:
		_clear_trees_around(p, 1.0)
		_instance("res://scenes/maps/props/TreeDead.tscn", group, p, _rng.randf() * TAU)
	_instance("res://scenes/maps/props/LogFallen.tscn", group, SAWMILL + Vector2(-12, -9), 0.4)


func _place_forest_props() -> void:
	var rocks := _add(_props, _node("Rochers"))
	var east_glade: Vector2 = GLADES[4][0]
	for k in 7:
		var ang := k / 7.0 * TAU + _rng.randf_range(-0.3, 0.3)
		var p: Vector2 = east_glade + Vector2(cos(ang), sin(ang)) * _rng.randf_range(5.0, 10.0)
		if _is_on_path(p, 3.0):
			continue
		_instance("res://scenes/maps/props/RockLarge.tscn" if k % 2 == 0 else "res://scenes/maps/props/RockMedium.tscn",
				rocks, p, _rng.randf() * TAU)
	var logs := _add(_props, _node("Troncs"))
	var placed := 0
	var tries := 0
	while placed < 40 and tries < 2000:
		tries += 1
		var p := _random_forest_point(8.0)
		var i := int(p.y) * W + int(p.x)
		if _terrain[i] == T.TREE or _is_on_path(p, 4.0) or _open_d[i] <= 0.0:
			continue
		var kind := placed % 3
		var path: String = ["res://scenes/maps/props/RockMedium.tscn", "res://scenes/maps/props/LogFallen.tscn",
				"res://scenes/maps/props/RockLarge.tscn"][kind]
		_clear_trees_around(p, 2.0 if kind == 1 else 1.3)
		_instance(path, rocks if kind != 1 else logs, p, _rng.randf() * TAU)
		placed += 1


func _place_markers_static() -> void:
	var spawn := _marker("PlayerSpawn", "res://map_objects/PlayerSpawnMarker3D.gd", PLAYER_SPAWN)
	_add(_objects, spawn)
	var west := _marker("Portal_O", "res://map_objects/PortalMarker3D.gd", PORTAL_WEST)
	west.direction = "O"
	west.target_map_id = CLAIRIERE_ID
	west.target_x = 1984.0
	west.target_y = 576.0
	_add(_objects, west)
	var east := _marker("Portal_E", "res://map_objects/PortalMarker3D.gd", PORTAL_EAST)
	east.direction = "E"
	east.target_map_id = VILLAGE_ID
	east.target_x = 160.0
	east.target_y = 1472.0
	_add(_objects, east)
	var group := Node3D.new()
	group.name = "MonsterSpawnGroup_" + SPAWN_GROUP
	group.set_script(load("res://map_objects/MonsterSpawnGroupMarker3D.gd"))
	group.group_id = SPAWN_GROUP
	group.max_monsters = MONSTER_SPAWNS
	group.respawn_delay_seconds = 30
	_add(_objects, group)


# ---------------------------------------------------------------------------
# 3. Finalisation (scène dans l'arbre : emprises des props calculables)
# ---------------------------------------------------------------------------

func _write_scene() -> void:
	var blocked := {}
	for node in _root.get_tree().get_nodes_in_group(ObstacleFootprint3D.GROUP):
		for cell in (node as ObstacleFootprint3D).blocked_cells():
			blocked[cell] = true
	# Aucun arbre sous un prop.
	for cell in blocked:
		var i: int = cell.y * W + cell.x
		if cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H and _terrain[i] == T.TREE:
			_terrain[i] = T.FOREST
	_ensure_connectivity(blocked)
	_place_monster_spawns(blocked)
	_write_grid(_root.get_node("Terrain"))

	var ground := TerrainGround.new()
	ground.name = "Ground"
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


func _ensure_connectivity(blocked: Dictionary) -> void:
	var walkable := func(i: int) -> bool:
		return _terrain[i] != T.TREE and not blocked.has(Vector2i(i % W, i / W))
	var start := int(PLAYER_SPAWN.y) * W + int(PLAYER_SPAWN.x)
	var carved := 0
	var small_pockets := 0
	for pass_index in 50:
		var reached := _flood(start, walkable)
		# Poches non atteintes.
		var pocket_seed := -1
		var pocket_size := 0
		var seen := {}
		for i in W * H:
			if reached[i] == 1 or not walkable.call(i) or seen.has(i):
				continue
			var pocket := _flood_list(i, walkable, reached)
			for c in pocket:
				seen[c] = true
			if pocket.size() < 25:
				small_pockets += 1
			elif pocket_seed == -1:
				pocket_seed = i
				pocket_size = pocket.size()
		if pocket_seed == -1:
			break
		carved += _carve_to(pocket_seed, reached, blocked)
	print("Connexité : %d cases d'arbres creusées, %d petites poches isolées laissées" % [carved, small_pockets])


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


func _flood_list(start: int, walkable: Callable, reached: PackedByteArray) -> Array:
	var result := [start]
	var seen := {start: true}
	var k := 0
	while k < result.size():
		var i: int = result[k]
		k += 1
		var x := i % W
		var z := i / W
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W if z > 0 else -1, i + W if z < H - 1 else -1]:
			if nb >= 0 and not seen.has(nb) and reached[nb] == 0 and walkable.call(nb):
				seen[nb] = true
				result.append(nb)
	return result


## Creuse le plus court chemin (en traversant les arbres, jamais les props) d'une poche vers
## la zone atteinte, et retire les arbres rencontrés.
func _carve_to(from: int, reached: PackedByteArray, blocked: Dictionary) -> int:
	var prev := {from: -1}
	var queue := [from]
	var k := 0
	var target := -1
	while k < queue.size():
		var i: int = queue[k]
		k += 1
		if reached[i] == 1:
			target = i
			break
		var x := i % W
		var z := i / W
		for nb in [i - 1 if x > 1 else -1, i + 1 if x < W - 2 else -1, i - W if z > 1 else -1, i + W if z < H - 2 else -1]:
			if nb >= 0 and not prev.has(nb) and not blocked.has(Vector2i(nb % W, nb / W)):
				prev[nb] = i
				queue.append(nb)
	var carved := 0
	var c := target
	while c != -1:
		if _terrain[c] == T.TREE:
			_terrain[c] = T.FOREST
			carved += 1
		c = prev[c]
	return carved


func _place_monster_spawns(blocked: Dictionary) -> void:
	var reached := _flood(int(PLAYER_SPAWN.y) * W + int(PLAYER_SPAWN.x), func(i: int) -> bool:
		return _terrain[i] != T.TREE and not blocked.has(Vector2i(i % W, i / W)))
	var candidates_glade: Array[Vector2i] = []
	var candidates_forest: Array[Vector2i] = []
	for z in range(4, H - 4):
		for x in range(4, W - 4):
			var i := z * W + x
			if reached[i] == 0 or _terrain[i] == T.PAVED:
				continue
			if _road_d[i] < 11.0 or _plaza_d[i] < 20.0 and FOUNTAIN.distance_to(Vector2(x, z)) < 22.0:
				continue
			if PORTAL_WEST.distance_to(Vector2(x, z)) < 18.0 or PORTAL_EAST.distance_to(Vector2(x, z)) < 18.0:
				continue
			if SAWMILL.distance_to(Vector2(x, z)) < 9.0:
				continue
			if _open_d[i] <= 0.0 and _dirt_d[i] > 2.0:
				candidates_glade.append(Vector2i(x, z))
			elif _dirt_d[i] > 2.0:
				candidates_forest.append(Vector2i(x, z))
	var chosen: Array[Vector2i] = []
	var min_spacing := 3.5
	var glade_quota := int(MONSTER_SPAWNS * 0.35)
	for pool in [candidates_glade, candidates_forest]:
		var quota := glade_quota if pool == candidates_glade else MONSTER_SPAWNS
		var tries := 0
		while chosen.size() < quota and tries < 40000 and not pool.is_empty():
			tries += 1
			var c: Vector2i = pool[_rng.randi() % pool.size()]
			var ok := true
			for o in chosen:
				if absi(o.x - c.x) < min_spacing and absi(o.y - c.y) < min_spacing:
					ok = false
					break
			if ok:
				chosen.append(c)
	for k in chosen.size():
		var c := chosen[k]
		var template := FOX_ID if (c.x < W / 2) == (_rng.randf() < 0.65) else KELTIR_ID
		var m := _marker("MonsterSpawn_%03d" % k, "res://map_objects/MonsterSpawnMarker3D.gd", Vector2(c.x + 0.5, c.y + 0.5))
		m.template_id = template
		m.spawn_group = SPAWN_GROUP
		_add(_objects, m)
	print("Spawns de monstres : %d" % chosen.size())


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


func _node(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	return n


func _add(parent: Node, child: Node) -> Node:
	parent.add_child(child, true)
	child.owner = _root
	return child


func _instance(path: String, parent: Node, pos: Vector2, yaw: float) -> Node3D:
	var inst: Node3D = (load(path) as PackedScene).instantiate()
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


## arr[i] = min(arr[i], distance(case, p) - inner) pour les cases à moins de `reach` de p.
func _stamp(arr: PackedFloat32Array, p: Vector2, inner: float, reach: float) -> void:
	for z in range(maxi(0, floori(p.y - reach)), mini(H, ceili(p.y + reach) + 1)):
		for x in range(maxi(0, floori(p.x - reach)), mini(W, ceili(p.x + reach) + 1)):
			var d := Vector2(x + 0.5, z + 0.5).distance_to(p) - inner
			var i := z * W + x
			if d < arr[i]:
				arr[i] = d


## Disque au bord irrégulier (rayon modulé par du bruit angulaire).
func _stamp_blob(arr: PackedFloat32Array, c: Vector2, radius: float) -> void:
	var reach := radius * 1.35 + 6.0
	for z in range(maxi(0, floori(c.y - reach)), mini(H, ceili(c.y + reach) + 1)):
		for x in range(maxi(0, floori(c.x - reach)), mini(W, ceili(c.x + reach) + 1)):
			var v := Vector2(x + 0.5, z + 0.5) - c
			var r := radius * (1.0 + 0.22 * _noise.get_noise_2d(cos(v.angle()) * 20.0 + c.x, sin(v.angle()) * 20.0 + c.y))
			var d := v.length() - r
			var i := z * W + x
			if d < arr[i]:
				arr[i] = d


func _paint_blob(c: Vector2, radius: float, t: int) -> void:
	for z in range(maxi(0, floori(c.y - radius - 2)), mini(H, ceili(c.y + radius + 2))):
		for x in range(maxi(0, floori(c.x - radius - 2)), mini(W, ceili(c.x + radius + 2))):
			var r := radius * (1.0 + 0.25 * _noise.get_noise_2d(x * 2.0, z * 2.0))
			if Vector2(x + 0.5, z + 0.5).distance_to(c) <= r:
				var i := z * W + x
				if _terrain[i] != T.PAVED:
					_terrain[i] = t


func _density_at(x: int, z: int) -> float:
	return clampf(_density.get_noise_2d(x, z) * 0.8 + 0.5, 0.0, 1.0)


func _has_tree_neighbour(x: int, z: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if (dx != 0 or dz != 0) and nx >= 0 and nz >= 0 and nx < W and nz < H and _terrain[nz * W + nx] == T.TREE:
				return true
	return false


func _clear_trees_around(p: Vector2, radius: float) -> void:
	for z in range(maxi(0, floori(p.y - radius)), mini(H, ceili(p.y + radius) + 1)):
		for x in range(maxi(0, floori(p.x - radius)), mini(W, ceili(p.x + radius) + 1)):
			var i := z * W + x
			if _terrain[i] == T.TREE and Vector2(x + 0.5, z + 0.5).distance_to(p) <= radius + 0.8:
				_terrain[i] = T.FOREST


func _is_on_path(p: Vector2, margin: float) -> bool:
	var x := clampi(int(p.x), 0, W - 1)
	var z := clampi(int(p.y), 0, H - 1)
	var i := z * W + x
	return _road_d[i] < 2.5 + margin or _dirt_d[i] < 1.5 + margin or _plaza_d[i] < 11.0 + margin \
			and FOUNTAIN.distance_to(p) < 12.0 + margin


func _is_near_portal(x: int, z: int) -> bool:
	return PORTAL_WEST.distance_to(Vector2(x, z)) < 8.0 or PORTAL_EAST.distance_to(Vector2(x, z)) < 8.0


func _random_forest_point(margin: float) -> Vector2:
	return Vector2(_rng.randf_range(margin, W - margin), _rng.randf_range(margin, H - margin))


## Direction carte (degrés : 0 = est, 90 = sud) de a vers b.
func _heading(a: Vector2, b: Vector2) -> float:
	return rad_to_deg((b - a).angle())


## Direction (degrés carte) de la route au point le plus proche de p, dans le sens qui mène
## vers `target` (un des deux portails).
func _road_heading_toward(p: Vector2, target: Vector2) -> float:
	var samples := _sample(ROAD, 1.0)
	var best := 0
	for k in samples.size():
		if (samples[k] as Vector2).distance_to(p) < (samples[best] as Vector2).distance_to(p):
			best = k
	var step := 4 if target.x > p.x else -4
	var b: Vector2 = samples[clampi(best + step, 0, samples.size() - 1)]
	return _heading(samples[best], b)
