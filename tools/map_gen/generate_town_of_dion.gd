extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Town_of_Dion.tscn (170 x 140 cases), la
## Town of Dion de Lineage 2 : une ville plus petite que Gludio, au sud-est, au-delà des
## marais de Cruma. Relancer ce script ÉCRASE la scène ; ensuite l'exporter vers le serveur
## avec tools/export_map_to_tmx.gd.
##
## Disposition (voir tools/map_gen/GludioRegion.gd) :
##   - une enceinte rectangulaire (remparts du village) à trois portes : au nord vers les
##     marais de Cruma, à l'ouest vers les ruines du Désespoir, à l'est vers le Chemin du
##     cimetière ; tours rondes sur le côté sud, aveugle ;
##   - au centre, la place carrée et sa fontaine, la chapelle d'Einhasad au sud de la place,
##     l'échoppe (auberge) au coin nord-ouest, des maisons le long des rues ;
##   - la rivière qui descend de Gludio coule à l'ouest de la ville, franchie par un pont de
##     pierre sur la route de l'ouest ;
##   - au sud, hors les murs, les champs et les fermes (les cultures de Floran, sur la carte
##     de Lineage 2).
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_town_of_dion.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")

## Fiches serveur propres à Dion (backend data/npc/others.xml et npc/shops).
const GUARD_IDS := ["ec36e6cb-b1ad-42a9-8d63-e3a4d4aa4b77", "c84a818f-805d-4427-863d-d5ff095b5a1f",
		"a06f057b-b604-4de0-871b-6169c2cb0691", "3273435f-ff91-46e5-b17f-ba77fa718421"]
const MERCHANT_ID := "f420cf7c-5fa8-4a14-b0ef-e6414a40bcd8"
## Services de la ville (comme à Gludio) : maîtresse des compétences, forgeron et magister aux
## étals de la place, prêtresse devant la chapelle, gardienne des portails, magasinier,
## fermière des champs du sud.
const SKILL_LEARNER_ID := "c303c33d-1c11-4ccf-b502-bea677e8cd5c"
const BLACKSMITH_ID := "5c63ff85-2055-44d3-9df6-ed12fea6fbc5"
const MAGISTER_ID := "5a13fda9-438d-4a0b-a79c-427fae6503c6"
const PRIEST_ID := "a4970e86-708e-4dd8-87b4-fd679a9d4051"
const GATEKEEPER_ID := "30a00cb4-dd8f-42a3-ba2f-c02a86dd181e"
const WAREHOUSE_ID := "d7df2469-1f0a-409d-978b-8eaf4b635ca8"
const FARMER_ID := "924e30ad-82f3-4c4f-8d1b-01b3b49028b7"

const CENTER := Vector2(85.5, 70.5)
const WALL := [Vector2(40, 30), Vector2(131, 30), Vector2(131, 113), Vector2(40, 113)]
const GATE_N := Vector2(85.5, 30.0)
const GATE_W := Vector2(40.0, 70.5)
const GATE_E := Vector2(131.0, 70.5)
const SQUARE := Rect2(69, 56, 33, 22)
const FOUNTAIN := Vector2(85.5, 67.0)
const RING := [Vector2(51, 41), Vector2(120, 41), Vector2(120, 102), Vector2(51, 102)]
const AVENUE_HALF := 2.6
const RING_HALF := 1.6
const ROAD_HALF := 2.5
## La chapelle : le temple de Gludio à 70 %, porte au nord, sur la place.
const CHAPEL_SCALE := 0.7
const CHAPEL := Vector2(85.5, 88.7)
const RIVER := [Vector2(26, -12), Vector2(23, 22), Vector2(21, 50), Vector2(21.5, 62), Vector2(21.5, 70.5),
		Vector2(21.5, 79), Vector2(23, 100), Vector2(29, 125), Vector2(27, 152)]
const BRIDGE_W := Vector2(21.5, 70.5)
const FIELDS := [[Rect2(50, 121, 26, 9), true], [Rect2(95, 121, 30, 9), false], [Rect2(138, 116, 20, 13), true],
		[Rect2(142, 84, 16, 22), false]]

var _keep_free: Array = []


func _setup() -> void:
	W = R.DION_SIZE.x
	H = R.DION_SIZE.y
	SEED = 20261012
	MAP_ID = R.DION_ID
	MAP_NAME = R.DION
	DESCRIPTION = "Dion, petite ville marchande entre les marais de Cruma et les champs de Floran : une place à la fontaine, sa chapelle et ses échoppes, à l'abri de remparts. La rivière venue de Gludio coule à ses portes."
	OUT_PATH = "res://scenes/maps/Town_of_Dion.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = true
	PLAYER_SPAWN = Vector2(85.5, 75.5)


func _layout() -> void:
	for k in WALL.size():
		for p in _densify([WALL[k], WALL[(k + 1) % WALL.size()]], 0.5):
			_stamp("wall", p, 0.0, 16.0)
	var inside := _field("town")
	for z in H:
		for x in W:
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("wall", p)
			inside[z * W + x] = -d if Geometry2D.is_point_in_polygon(p, PackedVector2Array(WALL)) else d
	for z in H:
		for x in W:
			if _dist("town", Vector2(x + 0.5, z + 0.5)) > 16.0 and _edge(x, z) < 18 + int(_noise.get_noise_2d(x, z) * 5.0):
				_terrain[z * W + x] = T.FOREST

	_bridge(BRIDGE_W, "x", true, "Pont_Ouest")
	_river(RIVER, 4.4)

	_road([Vector2(85.5, -8), R.DION_PORTAL_N, GATE_N], ROAD_HALF, T.PAVED, 5.0)
	_road([Vector2(-8, 70.5), R.DION_PORTAL_W, BRIDGE_W, GATE_W], ROAD_HALF, T.PAVED, 5.0)
	_road([GATE_E, R.DION_PORTAL_E, Vector2(W + 8, 70.5)], ROAD_HALF, T.PAVED, 5.0)
	for portal in [R.DION_PORTAL_N, R.DION_PORTAL_W, R.DION_PORTAL_E]:
		_paint_disc(portal, 4.2, T.PAVED, [T.WATER])
		_stamp("open", portal, 10.0, 20.0)
	# Chemins de terre vers les champs du sud, autour des remparts.
	_road([Vector2(131, 72), Vector2(138, 90), Vector2(137, 113), Vector2(120, 118), Vector2(60, 118), Vector2(36, 114),
			Vector2(33, 85), Vector2(40, 72)], 1.3, T.DIRT, 2.0, 0.35)
	for field in FIELDS:
		_paint_rect(field[0], T.CROP, [T.PAVED, T.DIRT, T.WATER])
		_stamp_rect("open", field[0], 10.0)

	_road([GATE_N, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road([GATE_W, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road([GATE_E, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road(_densify(RING, 3.0, true), RING_HALF, T.PAVED, 1.0, 0.1)
	_paint_rect(SQUARE, T.PAVED)
	_stamp_rect("open", SQUARE, 4.0)
	var town_d: PackedFloat32Array = _fields["town"]
	for i in W * H:
		if town_d[i] < 0.0 and _terrain[i] == T.FOREST:
			_terrain[i] = T.GRASS
	_edge_band(6, T.THICKET, [T.GRASS, T.FOREST])


func _decorate() -> void:
	var ramparts := _add(_props, _node("Remparts"))
	var features := [
		[GATE_N, 6.5, "Gatehouse", "Porte_Nord"], [GATE_W, 6.5, "Gatehouse", "Porte_Ouest"],
		[GATE_E, 6.5, "Gatehouse", "Porte_Est"],
		[Vector2(62, 30), 3.0, "RampartTower"], [Vector2(109, 30), 3.0, "RampartTower"],
		[Vector2(63, 113), 3.0, "RampartTower"], [Vector2(85.5, 113), 3.0, "RampartTowerRoofed"],
		[Vector2(108, 113), 3.0, "RampartTower"], [Vector2(40, 50), 3.0, "RampartTower"],
		[Vector2(40, 91), 3.0, "RampartTower"], [Vector2(131, 50), 3.0, "RampartTower"],
		[Vector2(131, 91), 3.0, "RampartTower"],
	]
	_fortification(ramparts, WALL, CENTER, features, "RampartTowerRoofed", 3.0, "RampartWall", 4.0)
	for v in WALL:
		_reserve_disc(v, 5.0)
	for f in features:
		_reserve_disc(f[0], 9.0 if String(f[2]) == "Gatehouse" else 5.0)

	_instance("Fountain", _props, FOUNTAIN, 0.0).name = "Fontaine"
	_reserve_cells(_rect_cells(SQUARE.get_center(), Vector2(0, 1), SQUARE.size, 1.0))
	var buildings := _add(_props, _node("Batiments"))
	var chapel := _building("Temple", buildings, CHAPEL, Vector2(0, -1), "Chapelle")
	chapel.scale = Vector3.ONE * CHAPEL_SCALE
	_checks.erase("Porte Chapelle")
	_checks["Porte Chapelle"] = CHAPEL + Vector2(0, -(13.9 * CHAPEL_SCALE))
	_reserve_cells(_rect_cells(CHAPEL, Vector2(0, -1), Vector2(14.2, 26.2) * CHAPEL_SCALE, 2.0))
	var inn_pos := Vector2(60.5, CENTER.y - AVENUE_HALF - 1.5 - 4.1)
	_building("Inn", buildings, inn_pos, Vector2(0, 1), "Echoppe")
	_reserve_cells(_rect_cells(inn_pos, Vector2(0, 1), Vector2(12.2, 8.2), 1.5))

	var npcs := [
		["Garde_PorteNord_O", GUARD_IDS[0], GATE_N + Vector2(-4.2, 6.5)],
		["Garde_PorteNord_E", GUARD_IDS[1], GATE_N + Vector2(4.2, 6.5)],
		["Garde_PorteOuest", GUARD_IDS[2], GATE_W + Vector2(6.5, -4.2)],
		["Garde_PorteEst", GUARD_IDS[3], GATE_E + Vector2(-6.5, 4.2)],
		["Marchand", MERCHANT_ID, Vector2(56.5, CENTER.y - AVENUE_HALF - 0.6)],
	]
	for n in npcs:
		_npc(n[0], n[1], n[2])
		_reserve_disc(n[2], 2.5)
		_keep_free.append(n[2])

	var kinds := ["HouseSmall", "HouseMedium", "HouseLarge"]
	var weights := [0.45, 0.4, 0.15]
	var in_town := func(p: Vector2) -> bool: return _dist("town", p) < -2.2
	var count := 0
	var streets := [
		[Vector2(85.5, 42.0), Vector2(85.5, SQUARE.position.y - 1.0), AVENUE_HALF],
		[Vector2(52.0, 70.5), Vector2(SQUARE.position.x - 1.0, 70.5), AVENUE_HALF],
		[Vector2(SQUARE.end.x + 1.0, 70.5), Vector2(119.0, 70.5), AVENUE_HALF],
	]
	for k in RING.size():
		streets.append([RING[k], RING[(k + 1) % RING.size()], RING_HALF])
	for s in streets:
		for side in [1.0, -1.0]:
			count += _fill_lots(buildings, s[0], s[1], side, s[2], kinds, weights, [T.GRASS], in_town, "Maison_%d" % count)
	# Abords de la place : façades tournées vers elle.
	for edge in [[Vector2(SQUARE.position.x, SQUARE.position.y), Vector2(SQUARE.end.x, SQUARE.position.y)],
			[Vector2(SQUARE.end.x, SQUARE.position.y), Vector2(SQUARE.end.x, SQUARE.end.y)],
			[Vector2(SQUARE.position.x, SQUARE.end.y), Vector2(SQUARE.position.x, SQUARE.position.y)]]:
		count += _fill_lots(buildings, edge[0], edge[1], 1.0, 0.0, kinds, weights, [T.GRASS], in_town, "Maison_%d" % count, 1.6)
	for b in buildings.get_children():
		_keep_free.append(Vector2(b.position.x, b.position.z) + Vector2(sin(b.rotation.y), cos(b.rotation.y)) * 4.5)
	print("Maisons : %d" % count)
	_building("HouseMedium", buildings, Vector2(88.5, 118 + 1.3 + 1.2 + 3.1), Vector2(0, -1), "Ferme_Sud")
	_building("HouseSmall", buildings, Vector2(138 + 1.3 + 1.2 + 2.6, 111.0), Vector2(-1, 0), "Ferme_Est")
	var fences := _add(_props, _node("Clotures"))
	for field in FIELDS:
		if field[1]:
			_fence_rect(fences, field[0])

	var market := _add(_props, _node("Marche"))
	_instance("MarketStallRed", market, Vector2(75.5, 62.5), 0.0)
	_instance("MarketStallBlue", market, Vector2(95.5, 62.5), 0.0)
	_instance("MarketStallBlue", market, Vector2(75.5, 75.0), PI)
	_instance("Crate", market, Vector2(73.2, 62.0), 0.3)
	_instance("Barrel", market, Vector2(97.8, 62.2), 0.0)
	_instance("Well", market, Vector2(97.0, 75.0), 0.2)
	# PNJ de service posés après les maisons (qui ne bougent donc pas) : devant les étals, autour
	# de la fontaine, au seuil de la chapelle.
	for s in [["MaitreCompetences", SKILL_LEARNER_ID, Vector2(77.5, 70.5)], ["Forgeron", BLACKSMITH_ID, Vector2(95.5, 65.0)],
			["Magister", MAGISTER_ID, Vector2(75.5, 65.0)], ["Pretresse", PRIEST_ID, Vector2(82.0, 77.0)],
			["GardiennePortails", GATEKEEPER_ID, Vector2(93.5, 70.5)], ["Magasinier", WAREHOUSE_ID, Vector2(99.5, 71.5)],
			["Fermiere", FARMER_ID, Vector2(79.0, 118.0)]]:
		_npc(s[0], s[1], s[2])
		_keep_free.append(s[2])

	var lamps := _add(_props, _node("Lampadaires"))
	for c in [Vector2(SQUARE.position.x + 1.0, SQUARE.position.y + 1.0), Vector2(SQUARE.end.x - 1.0, SQUARE.position.y + 1.0),
			Vector2(SQUARE.position.x + 1.0, SQUARE.end.y - 1.0), Vector2(SQUARE.end.x - 1.0, SQUARE.end.y - 1.0)]:
		_lamp(lamps, c, (CENTER - c).normalized())
	for k in 4:
		var dir := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
		_lamp(lamps, FOUNTAIN + dir * 6.0, -dir)
	for gate in [[GATE_N, Vector2(0, -1)], [GATE_W, Vector2(-1, 0)], [GATE_E, Vector2(1, 0)]]:
		var dir: Vector2 = gate[1]
		var side := Vector2(-dir.y, dir.x)
		for s in [-1.0, 1.0]:
			_lamp(lamps, gate[0] + dir * 8.0 + side * s * (ROAD_HALF + 0.8), -side * s)
			_lamp(lamps, gate[0] - dir * 9.0 + side * s * (AVENUE_HALF + 0.7), -side * s)

	var signs := _add(_props, _node("Panneaux"))
	var at := Vector2(SQUARE.position.x + 3.0, SQUARE.end.y - 2.5)
	_sign(signs, "Place", at, [[R.CRUMA, 270.0], [R.DESPAIR, 180.0], [R.CEMETERY_PATH, 0.0], ["Chapelle", 90.0]])
	_sign(signs, "Teleporteur_N", R.DION_PORTAL_N + Vector2(-5.0, 6.0), [[R.CRUMA, 270.0], [R.DION, 90.0]])
	_sign(signs, "Teleporteur_O", R.DION_PORTAL_W + Vector2(6.0, -5.0), [[R.DESPAIR, 180.0], [R.DION, 0.0]])
	_sign(signs, "Teleporteur_E", R.DION_PORTAL_E + Vector2(-6.0, -5.0), [[R.CEMETERY_PATH, 0.0], [R.DION, 180.0]])

	_portal("N", R.DION_PORTAL_N, R.CRUMA_ID, R.CRUMA_PORTAL_S, R.CRUMA)
	_portal("O", R.DION_PORTAL_W, R.DESPAIR_ID, R.DESPAIR_PORTAL_E, R.DESPAIR)
	_portal("E", R.DION_PORTAL_E, R.CEMETERY_PATH_ID, R.CEMETERY_PATH_PORTAL_W, R.CEMETERY_PATH)
	_peace_zone(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]))
	_checks["Porte nord (dehors)"] = GATE_N + Vector2(0, -5)
	_checks["Porte ouest (dehors)"] = GATE_W + Vector2(-5, 0)
	_checks["Porte est (dehors)"] = GATE_E + Vector2(5, 0)


func _fence_rect(parent: Node, rect: Rect2) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var length := a.distance_to(b)
		var count := roundi(length / 2.0)
		var dir := (b - a) / length
		for i in count:
			if i == count / 2:
				continue
			var node := _instance("Fence", parent, a + dir * (length / count) * (i + 0.5), atan2(-dir.y, dir.x))
			node.scale = Vector3(length / count / 2.0, 1.0, 1.0)


func _after_props(blocked: Dictionary) -> void:
	var trees := _scatter(T.TREE, [T.GRASS, T.FOREST], func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)):
			return 0.0
		if _dist("road", p) < 2.5 or _dist("river", p) < 2.0 or _dist("open", p) < 0.0:
			return 0.0
		for k in _keep_free:
			if (k as Vector2).distance_to(p) < 3.0:
				return 0.0
		var town := _dist("town", p)
		if town < 0.0:
			return 0.03 if town < -4.0 else 0.0
		if town < 12.0:
			return 0.0
		var edge := float(_edge(x, z))
		return lerpf(0.05, 0.42, clampf(1.0 - (edge - 6.0) / 24.0, 0.0, 1.0)) * smoothstep(12.0, 24.0, town))
	print("Arbres : %d" % trees)


func _configure_ground(ground: TerrainGround) -> void:
	ground.paved_asset = "PavingStones151"
	ground.paved_tile = Vector2(3.0, 3.0)
	ground.paved_desaturate = 0.3
	ground.paved_tint = Color(0.8, 0.74, 0.66)
