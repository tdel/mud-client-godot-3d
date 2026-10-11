extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Town_of_Gludio.tscn (220 x 180 cases), la
## ville de départ, sur le modèle de la Town of Gludio de Lineage 2. Remplace l'ancienne
## Place du village (même id de carte : les personnages qui s'y trouvaient restent dans la
## ville de départ). Relancer ce script ÉCRASE la scène ; ensuite l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Town_of_Gludio.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - une grande enceinte octogonale (courtines crénelées, tours, poivrières aux angles)
##     percée de quatre portes gardées, une par point cardinal ;
##   - au centre, la grand-place ronde et pavée autour du monument (statue du héros sur sa
##     vasque), quatre avenues pavées qui en rayonnent vers les portes, trois rues en
##     diagonale et une rue de ronde au pied des remparts ;
##   - au nord-ouest de la place, le temple d'Einhasad et son parvis, dans l'axe de la place ;
##   - l'auberge (épicerie) sur l'avenue de l'ouest, la forge sur l'avenue de l'est, des
##     maisons alignées le long de toutes les rues ;
##   - hors les murs : prés, champs cultivés et fermes, puis la forêt vers les bords ; la
##     rivière descend du nord à l'est de la ville (rejointe par un affluent venu des marais),
##     franchie par le pont de pierre de la route de l'est ;
##   - quatre routes jusqu'aux téléporteurs des bords : au nord le château de Gludio, à
##     l'ouest les ruines d'Agonie, au sud les ruines du Désespoir, à l'est les marais de
##     Cruma.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_town_of_gludio.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")

const INNKEEPER_ID := "a3c8d0f2-5d5f-4d2c-9f2c-3f4e5d6c7b8a"
const BLACKSMITH_ID := "dcb67f1e-b178-4062-8393-26abca9b0d66"
const SKILL_LEARNER_ID := "b982da01-7dd0-4c8c-84d3-1ce6795fecee"
## Un PNJ serveur n'apparaît qu'une fois dans le monde : une fiche par garde (backend
## data/npc/others.xml, "Gate Guard" / "Village Guard").
const GATE_GUARD_IDS := ["318a4b28-4aae-46fa-ab99-2bc62738f1c3", "6fea25d2-5d6f-474e-adef-c11c1a903843",
		"a760adde-b995-4ab8-a073-ac5f4d4e5a23", "b748cda3-b7ed-4e50-863e-a31bc4815d9f"]
const VILLAGE_GUARD_IDS := ["b0362279-5a46-4461-9672-6f4e0b2cf7e0", "a38d3420-52b9-498a-ba7a-0248158c1acc",
		"f006ec9d-60f1-46e3-9dc8-e10c3fd43338", "7d014cb8-a199-484b-a7b8-24c086f6c797"]
## Services de la ville, comme dans les villes de Lineage 2 (backend data/npc/others.xml et
## npc/shops) : gardienne des portails, magasinier, prêtre d'Einhasad, marchands d'armes,
## d'armures et de magie, deux habitants.
const GATEKEEPER_ID := "6b6ab0bc-ff53-430c-bc32-30f330f37f07"
const WAREHOUSE_ID := "6132be62-3c93-4057-8054-75214f3dda20"
const PRIEST_ID := "5d3f1aee-8877-4399-bf8f-567b1ad2d242"
const WEAPON_MERCHANT_ID := "da89a3cf-d3a2-486b-96f2-0171130b4c9d"
const ARMOR_MERCHANT_ID := "36ad12c4-1a36-4ee4-9026-3a97accd736e"
const MAGISTER_ID := "41984f3b-9cb7-43f6-98be-fdee6c6483da"
const TOWNSWOMAN_ID := "7af55075-ef37-485d-a17b-a3ab7982d8bf"
const FARMER_ID := "4fb1d6bd-021b-44d2-8226-541c70b3486e"

const CENTER := Vector2(100.5, 92.5)
const PLAZA_R := 18.0
## Axe des courtines (octogone) et portes au milieu des quatre grands côtés.
const WALL := [Vector2(58, 40), Vector2(143, 40), Vector2(163, 60), Vector2(163, 125), Vector2(143, 145),
		Vector2(58, 145), Vector2(38, 125), Vector2(38, 60)]
const GATE_N := Vector2(100.5, 40.0)
const GATE_S := Vector2(100.5, 145.0)
const GATE_W := Vector2(38.0, 92.5)
const GATE_E := Vector2(163.0, 92.5)
## Rue de ronde, 12 m en dedans des courtines.
const RING := [Vector2(65, 52), Vector2(136, 52), Vector2(151, 67), Vector2(151, 118), Vector2(136, 133),
		Vector2(65, 133), Vector2(50, 118), Vector2(50, 67)]
const AVENUE_HALF := 3.0
const RING_HALF := 1.8
const LANE_HALF := 1.5
const ROAD_HALF := 2.5
## Temple dans l'axe nord-ouest de la place (vers le milieu du pan nord-ouest de la ronde).
const TEMPLE_DIST := 35.0
## Rivière (du nord vers le sud, à l'est de la ville) et son affluent venu du nord-est ;
## tronçon droit nord-sud au droit du pont de la route de l'est.
const RIVER := [Vector2(174, -12), Vector2(176, 14), Vector2(181, 40), Vector2(183, 62), Vector2(182, 80),
		Vector2(182.5, 92.5), Vector2(182, 105), Vector2(185, 125), Vector2(190, 150), Vector2(188, 192)]
const TRIBUTARY := [Vector2(234, 22), Vector2(214, 30), Vector2(196, 44), Vector2(183, 58)]
const BRIDGE_E := Vector2(182.5, 92.5)
## Champs cultivés hors les murs : [rectangle, clos ?].
const FIELDS := [[Rect2(9, 106, 22, 12), true], [Rect2(10, 122, 20, 14), false], [Rect2(62, 159, 24, 10), true],
		[Rect2(113, 151, 24, 12), false], [Rect2(16, 42, 14, 12), false]]

var _temple_dir := Vector2.ZERO
## Seuils de porte et points de PNJ : aucun arbre planté autour.
var _keep_free: Array = []


func _setup() -> void:
	W = R.GLUDIO_SIZE.x
	H = R.GLUDIO_SIZE.y
	SEED = 20261010
	MAP_ID = R.GLUDIO_ID
	MAP_NAME = R.GLUDIO
	DESCRIPTION = "La cité de Gludio, coeur du royaume : une grande enceinte gardée autour de la place du monument, le temple d'Einhasad, l'auberge et la forge. Ses quatre portes ouvrent sur le château de Gludio au nord, les ruines d'Agonie à l'ouest, les ruines du Désespoir au sud et, passé la rivière, les marais de Cruma à l'est."
	OUT_PATH = "res://scenes/maps/Town_of_Gludio.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = true
	IS_STARTING_MAP = true
	PLAYER_SPAWN = CENTER + Vector2(0.0, 13.0)
	# Positions actuelles de personnages sur cette carte (base de dev, ancienne Place du
	# village) : gardées praticables.
	KEEP_CLEAR = [Vector2(52.5, 17.5), Vector2(32.0, 60.5), Vector2(22.5, 67.5), Vector2(40.1, 20.9)]
	_temple_dir = (Vector2(57.5, 59.5) - CENTER).normalized()


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Intérieur de l'enceinte (champ "town" : négatif dedans) et pied des murs.
	for k in WALL.size():
		var a: Vector2 = WALL[k]
		var b: Vector2 = WALL[(k + 1) % WALL.size()]
		for p in _densify([a, b], 0.5):
			_stamp("wall", p, 0.0, 16.0)
	var town := Geometry2D.convex_hull(PackedVector2Array(WALL))
	var inside := _field("town")
	for z in H:
		for x in W:
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("wall", p)
			inside[z * W + x] = -d if Geometry2D.is_point_in_polygon(p, town) else d

	# Prés hors les murs, sol forestier vers les bords.
	for z in H:
		for x in W:
			var p := Vector2(x + 0.5, z + 0.5)
			var out := _dist("town", p)
			if out > 0.0 and _edge(x, z) < 22 + int(_noise.get_noise_2d(x, z) * 6.0) and out > 18.0:
				_terrain[z * W + x] = T.FOREST

	# Rivière et pont de la route de l'est (pont déclaré d'abord : la rivière s'y resserre).
	_bridge(BRIDGE_E, "x", true, "Pont_Est")
	_river(RIVER, 4.6)
	_river(TRIBUTARY, 3.0, 0.6)

	# Routes hors les murs, prolongées au-delà des bords (la route sort de la carte).
	_road([Vector2(100.5, -8), R.GLUDIO_PORTAL_N, GATE_N], ROAD_HALF, T.PAVED, 5.0)
	_road([GATE_S, R.GLUDIO_PORTAL_S, Vector2(100.5, H + 8)], ROAD_HALF, T.PAVED, 5.0)
	_road([Vector2(-8, 92.5), R.GLUDIO_PORTAL_W, GATE_W], ROAD_HALF, T.PAVED, 5.0)
	_road([GATE_E, BRIDGE_E, R.GLUDIO_PORTAL_E, Vector2(W + 8, 92.5)], ROAD_HALF, T.PAVED, 5.0)
	for portal in [R.GLUDIO_PORTAL_N, R.GLUDIO_PORTAL_S, R.GLUDIO_PORTAL_W, R.GLUDIO_PORTAL_E]:
		_paint_disc(portal, 4.2, T.PAVED, [T.WATER])
		_stamp("open", portal, 10.0, 20.0)
	# Chemins de terre vers les champs.
	_road([Vector2(33, 94), Vector2(33.5, 110), Vector2(32, 125), Vector2(31, 138)], 1.2, T.DIRT, 2.0, 0.35)
	_road([Vector2(100.5, 156), Vector2(90, 156.5), Vector2(74, 156)], 1.2, T.DIRT, 2.0, 0.35)
	_road([Vector2(100.5, 30), Vector2(80, 33), Vector2(52, 36), Vector2(30, 46)], 1.2, T.DIRT, 2.0, 0.35)
	for field in FIELDS:
		var rect: Rect2 = field[0]
		_paint_rect(rect, T.CROP, [T.PAVED, T.DIRT, T.WATER])
		_stamp_rect("open", rect, 12.0)

	# Ville : avenues, rue de ronde, rues diagonales, grand-place et parvis du temple.
	_road([GATE_N, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road([GATE_S, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road([GATE_W, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road([GATE_E, CENTER], AVENUE_HALF, T.PAVED, 1.5, 0.1)
	_road(_densify(RING, 3.0, true), RING_HALF, T.PAVED, 1.0, 0.1)
	for target in [Vector2(143.5, 59.5), Vector2(143.5, 125.5), Vector2(57.5, 125.5)]:
		_road([CENTER + (target - CENTER).normalized() * (PLAZA_R - 1.0), target], LANE_HALF, T.PAVED, 1.0, 0.1)
	_paint_disc(CENTER, PLAZA_R, T.PAVED)
	_stamp("open", CENTER, PLAZA_R, PLAZA_R + 6.0)
	var forecourt_end := CENTER + _temple_dir * (TEMPLE_DIST - 12.0)
	for p in _densify([CENTER, forecourt_end], 0.5):
		_stamp("_forecourt", p, 0.0, 8.0)
	_paint_field("_forecourt", 5.5, T.PAVED)
	_fields.erase("_forecourt")
	# Pas de forêt dans l'enceinte.
	var town_d: PackedFloat32Array = _fields["town"]
	for i in W * H:
		if town_d[i] < 0.0 and _terrain[i] == T.FOREST:
			_terrain[i] = T.GRASS

	_edge_band(7, T.THICKET, [T.GRASS, T.FOREST])


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	var ramparts := _add(_props, _node("Remparts"))
	var features := [
		[GATE_N, 6.5, "Gatehouse", "Porte_Nord"], [GATE_S, 6.5, "Gatehouse", "Porte_Sud"],
		[GATE_W, 6.5, "Gatehouse", "Porte_Ouest"], [GATE_E, 6.5, "Gatehouse", "Porte_Est"],
		[Vector2(79, 40), 3.0, "RampartTower"], [Vector2(122, 40), 3.0, "RampartTower"],
		[Vector2(79, 145), 3.0, "RampartTower"], [Vector2(122, 145), 3.0, "RampartTower"],
		[Vector2(38, 76), 3.0, "RampartTower"], [Vector2(38, 109), 3.0, "RampartTower"],
		[Vector2(163, 76), 3.0, "RampartTower"], [Vector2(163, 109), 3.0, "RampartTower"],
	]
	_fortification(ramparts, WALL, CENTER, features, "RampartTowerRoofed", 3.0, "RampartWall", 4.0)
	# Ni maison ni arbre contre les tours et les portes (elles débordent des courtines).
	for v in WALL:
		_reserve_disc(v, 5.0)
	for f in features:
		_reserve_disc(f[0], 9.0 if String(f[2]) == "Gatehouse" else 5.0)

	var monument := _instance("Monument", _props, CENTER, 0.0)
	monument.name = "Monument"
	_reserve_disc(CENTER, PLAZA_R + 1.5)

	var buildings := _add(_props, _node("Batiments"))
	var temple_pos := CENTER + _temple_dir * TEMPLE_DIST
	_building("Temple", buildings, temple_pos, -_temple_dir, "Temple_Einhasad")
	_reserve_cells(_rect_cells(temple_pos, -_temple_dir, Vector2(14.2, 26.2), 2.5))
	var inn_pos := Vector2(70.5, CENTER.y + AVENUE_HALF + 1.5 + 4.1)
	_building("Inn", buildings, inn_pos, Vector2(0, -1), "Auberge")
	_reserve_cells(_rect_cells(inn_pos, Vector2(0, -1), Vector2(12.2, 8.2), 1.5))
	var forge_pos := Vector2(129.5, CENTER.y - AVENUE_HALF - 1.5 - 3.1)
	_building("Forge", buildings, forge_pos, Vector2(0, 1), "Forge", T.FORGE)
	_reserve_cells(_rect_cells(forge_pos + Vector2(2.1, 0), Vector2(0, 1), Vector2(11.4, 6.2), 1.5))
	_place_npcs()
	_place_houses(buildings)
	_place_farms(buildings)
	_place_market()
	_place_services()
	_place_lamps()
	_place_signs()
	for portal in [[R.GLUDIO_PORTAL_N, "N", R.CASTLE_ID, R.CASTLE_PORTAL_S, R.CASTLE],
			[R.GLUDIO_PORTAL_W, "O", R.AGONY_ID, R.AGONY_PORTAL_E, R.AGONY],
			[R.GLUDIO_PORTAL_S, "S", R.DESPAIR_ID, R.DESPAIR_PORTAL_N, R.DESPAIR],
			[R.GLUDIO_PORTAL_E, "E", R.CRUMA_ID, R.CRUMA_PORTAL_W, R.CRUMA]]:
		_portal(portal[1], portal[0], portal[2], portal[3], portal[4])
	_peace_zone(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]))
	_checks["Porte nord (dehors)"] = GATE_N + Vector2(0, -5)
	_checks["Porte sud (dehors)"] = GATE_S + Vector2(0, 5)
	_checks["Porte ouest (dehors)"] = GATE_W + Vector2(-5, 0)
	_checks["Porte est (dehors)"] = GATE_E + Vector2(5, 0)
	_checks["Parvis du temple"] = CENTER + _temple_dir * (TEMPLE_DIST - 14.5)


func _place_npcs() -> void:
	var guards := [
		["Garde_PorteNord_O", GATE_GUARD_IDS[0], GATE_N + Vector2(-4.5, 6.5)],
		["Garde_PorteNord_E", GATE_GUARD_IDS[1], GATE_N + Vector2(4.5, 6.5)],
		["Garde_PorteSud_O", GATE_GUARD_IDS[2], GATE_S + Vector2(-4.5, -6.5)],
		["Garde_PorteSud_E", GATE_GUARD_IDS[3], GATE_S + Vector2(4.5, -6.5)],
		["Garde_PorteOuest_N", VILLAGE_GUARD_IDS[0], GATE_W + Vector2(6.5, -4.5)],
		["Garde_PorteOuest_S", VILLAGE_GUARD_IDS[1], GATE_W + Vector2(6.5, 4.5)],
		["Garde_PorteEst_N", VILLAGE_GUARD_IDS[2], GATE_E + Vector2(-6.5, -4.5)],
		["Garde_PorteEst_S", VILLAGE_GUARD_IDS[3], GATE_E + Vector2(-6.5, 4.5)],
		["Aubergiste", INNKEEPER_ID, Vector2(66.5, CENTER.y + AVENUE_HALF + 0.6)],
		["Forgeron", BLACKSMITH_ID, Vector2(125.5, CENTER.y - AVENUE_HALF - 0.6)],
		["MaitreCompetences", SKILL_LEARNER_ID, CENTER + Vector2(4.0, 14.5)],
	]
	for g in guards:
		_npc(g[0], g[1], g[2])
		_reserve_disc(g[2], 2.5)
		_keep_free.append(g[2])


## PNJ de service, posés après les maisons (qu'ils ne déplacent pas) : marchands devant les
## étals de la grand-place, gardienne des portails à l'entrée de l'avenue du nord, prêtre sur
## le parvis du temple, magasinier près de la forge, fermier au bord des champs de l'ouest.
func _place_services() -> void:
	var stall := func(deg: float, r: float) -> Vector2: return CENTER + Vector2.from_angle(deg_to_rad(deg)) * r
	var side := Vector2(-_temple_dir.y, _temple_dir.x)
	var services := [
		["MarchandArmes", WEAPON_MERCHANT_ID, stall.call(15.0, 11.0)],
		["MarchandArmures", ARMOR_MERCHANT_ID, stall.call(165.0, 11.0)],
		["Magister", MAGISTER_ID, stall.call(296.0, 11.0)],
		["Habitante", TOWNSWOMAN_ID, stall.call(116.0, 11.0)],
		["GardiennePortails", GATEKEEPER_ID, CENTER + Vector2(0.0, -PLAZA_R + 3.5)],
		["Pretre", PRIEST_ID, CENTER + _temple_dir * (TEMPLE_DIST - 16.0) + side * 2.5],
		["Magasinier", WAREHOUSE_ID, Vector2(133.5, CENTER.y - AVENUE_HALF - 0.6)],
		["Fermier", FARMER_ID, Vector2(33.0, 112.0)],
	]
	for s in services:
		_npc(s[0], s[1], s[2])
		_keep_free.append(s[2])


## Maisons le long des avenues, des rues diagonales puis de la rue de ronde (des deux côtés),
## dans l'enceinte uniquement et à distance des courtines.
func _place_houses(parent: Node) -> void:
	var kinds := ["HouseSmall", "HouseMedium", "HouseLarge"]
	var weights := [0.35, 0.4, 0.25]
	var allowed := [T.GRASS]
	var in_town := func(p: Vector2) -> bool: return _dist("town", p) < -2.2
	var count := 0
	var streets := [
		[Vector2(100.5, 55.0), Vector2(100.5, CENTER.y - PLAZA_R - 1.0), AVENUE_HALF],
		[Vector2(100.5, CENTER.y + PLAZA_R + 1.0), Vector2(100.5, 130.0), AVENUE_HALF],
		[Vector2(53.0, 92.5), Vector2(CENTER.x - PLAZA_R - 1.0, 92.5), AVENUE_HALF],
		[Vector2(CENTER.x + PLAZA_R + 1.0, 92.5), Vector2(148.0, 92.5), AVENUE_HALF],
	]
	for target in [Vector2(143.5, 59.5), Vector2(143.5, 125.5), Vector2(57.5, 125.5)]:
		streets.append([CENTER + (target - CENTER).normalized() * (PLAZA_R + 1.0), target, LANE_HALF])
	for k in RING.size():
		streets.append([RING[k], RING[(k + 1) % RING.size()], RING_HALF])
	for s in streets:
		for side in [1.0, -1.0]:
			count += _fill_lots(parent, s[0], s[1], side, s[2], kinds, weights, allowed, in_town, "Maison_%d" % count)
	for b in parent.get_children():
		_keep_free.append(Vector2(b.position.x, b.position.z) + Vector2(sin(b.rotation.y), cos(b.rotation.y)) * 4.5)
	print("Maisons : %d" % count)


## Fermes hors les murs, champs clos de barrières.
func _place_farms(parent: Node) -> void:
	_building("HouseMedium", parent, Vector2(25.0, 92.5 + ROAD_HALF + 1.5 + 3.1), Vector2(0, -1), "Ferme_Ouest")
	_building("HouseSmall", parent, Vector2(100.5 + ROAD_HALF + 1.5 + 2.6, 160.5), Vector2(-1, 0), "Ferme_Sud")
	var fences := _add(_props, _node("Clotures"))
	for field in FIELDS:
		if field[1]:
			_fence_rect(fences, field[0])


## Clôture sur le pourtour de `rect`, avec un portillon au milieu de chaque côté.
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
			var p := a + dir * (length / count) * (i + 0.5)
			var node := _instance("Fence", parent, p, atan2(-dir.y, dir.x))
			node.scale = Vector3(length / count / 2.0, 1.0, 1.0)


func _place_market() -> void:
	var group := _add(_props, _node("Marche"))
	var k := 0
	for deg in [15.0, 64.0, 116.0, 165.0, 296.0]:
		var dir := Vector2.from_angle(deg_to_rad(deg))
		var pos := CENTER + dir * 13.5
		var stall := _instance("MarketStallRed" if k % 2 == 0 else "MarketStallBlue", group, pos, atan2(-dir.x, -dir.y))
		stall.name = "Etal_%d" % k
		var side := Vector2(-dir.y, dir.x)
		_instance("Barrel" if k % 2 == 0 else "Crate", group, pos + side * 2.3 + dir * 0.3, _rng.randf() * TAU)
		k += 1


func _place_lamps() -> void:
	var lamps := _add(_props, _node("Lampadaires"))
	# Pourtour de la grand-place, sauf face aux rues qui y débouchent.
	var openings := [0.0, 90.0, 180.0, 270.0]
	for target in [Vector2(143.5, 59.5), Vector2(143.5, 125.5), Vector2(57.5, 125.5), CENTER + _temple_dir]:
		openings.append(fposmod(rad_to_deg((target - CENTER).angle()), 360.0))
	for k in 24:
		var deg := k * 15.0 + 7.5
		if openings.any(func(o: float) -> bool: return absf(angle_difference(deg_to_rad(deg), deg_to_rad(o))) < deg_to_rad(9.0)):
			continue
		if k % 2 == 1:
			continue
		var dir := Vector2.from_angle(deg_to_rad(deg))
		_lamp(lamps, CENTER + dir * (PLAZA_R - 1.2), -dir)
	# Avenues : alternance de part et d'autre, crosse vers la chaussée.
	for axis in [[GATE_N, Vector2(0, 1)], [GATE_S, Vector2(0, -1)], [GATE_W, Vector2(1, 0)], [GATE_E, Vector2(-1, 0)]]:
		var start: Vector2 = axis[0]
		var dir: Vector2 = axis[1]
		var side := Vector2(-dir.y, dir.x)
		var length := start.distance_to(CENTER) - PLAZA_R
		var t := 9.0
		var s := 1.0
		while t < length - 3.0:
			_lamp(lamps, start + dir * t + side * s * (AVENUE_HALF + 0.6), -side * s)
			t += 11.0
			s = -s
	# Routes hors les murs, aux abords des portes.
	for gate in [[GATE_N, Vector2(0, -1)], [GATE_S, Vector2(0, 1)], [GATE_W, Vector2(-1, 0)], [GATE_E, Vector2(1, 0)]]:
		var dir: Vector2 = gate[1]
		var side := Vector2(-dir.y, dir.x)
		for t in [8.0, 18.0]:
			for s in [-1.0, 1.0]:
				_lamp(lamps, gate[0] + dir * t + side * s * (ROAD_HALF + 0.8), -side * s)


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	var at := CENTER + Vector2(-5.5, 13.5)
	_sign(signs, "Place", at, [[R.CASTLE, 270.0], [R.AGONY, 180.0], [R.DESPAIR, 90.0], [R.CRUMA, 0.0],
			["Temple", _heading(at, CENTER + _temple_dir * TEMPLE_DIST)]])
	_sign(signs, "Teleporteur_N", R.GLUDIO_PORTAL_N + Vector2(-5.0, 6.0), [[R.CASTLE, 270.0], [R.GLUDIO, 90.0]])
	_sign(signs, "Teleporteur_O", R.GLUDIO_PORTAL_W + Vector2(6.0, -5.0), [[R.AGONY, 180.0], [R.GLUDIO, 0.0]])
	_sign(signs, "Teleporteur_S", R.GLUDIO_PORTAL_S + Vector2(5.0, -6.0), [[R.DESPAIR, 90.0], [R.GLUDIO, 270.0]])
	_sign(signs, "Teleporteur_E", R.GLUDIO_PORTAL_E + Vector2(-6.0, -5.0), [[R.CRUMA, 0.0], [R.GLUDIO, 180.0]])
	_sign(signs, "Pont", BRIDGE_E + Vector2(-11.0, -4.5), [[R.CRUMA, 0.0], [R.GLUDIO, 180.0]])


# ---------------------------------------------------------------------------
# 3. Arbres (une fois les emprises connues)
# ---------------------------------------------------------------------------

func _after_props(blocked: Dictionary) -> void:
	var trees := _scatter(T.TREE, [T.GRASS, T.FOREST], func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)) or _near_keep_clear(p, 3.0):
			return 0.0
		if _dist("road", p) < 2.5 or _dist("river", p) < 2.0 or _dist("open", p) < 0.0:
			return 0.0
		for k in _keep_free:
			if (k as Vector2).distance_to(p) < 3.0:
				return 0.0
		var town := _dist("town", p)
		if town < 0.0:
			# Quelques arbres dans les cours, jamais au pied des murs.
			return 0.025 if town < -4.0 else 0.0
		if town < 14.0:
			return 0.0
		var edge := float(_edge(x, z))
		return lerpf(0.05, 0.42, clampf(1.0 - (edge - 8.0) / 30.0, 0.0, 1.0)) * smoothstep(14.0, 30.0, town))
	print("Arbres : %d" % trees)


func _configure_ground(ground: TerrainGround) -> void:
	ground.paved_asset = "PavingStones151"
	ground.paved_tile = Vector2(3.6, 3.6)
	ground.paved_desaturate = 0.35
	ground.paved_tint = Color(0.76, 0.73, 0.69)


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.grass_density = 0.5
