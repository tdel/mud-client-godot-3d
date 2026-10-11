extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Gludio_Castle.tscn (240 x 220 cases), le
## château de Gludio de Lineage 2, juste au nord de la ville : la grande zone de combat entre
## joueurs (aucune zone de paix) ; garnison de PNJ, monstres dans les bois au-delà de la
## rivière seulement (voir _hunting_grounds). Relancer ce script ÉCRASE la scène ;
## ensuite l'exporter vers le serveur avec tools/export_map_to_tmx.gd.
##
## Disposition (voir tools/map_gen/GludioRegion.gd) :
##   - la rivière descend du nord et se sépare en deux bras qui enserrent une grande île,
##     puis se rejoignent au sud-est (comme sur la carte de Lineage 2) ;
##   - au milieu de l'île, le château : courtines hautes, grosses tours rondes, châtelet au
##     sud (entrée principale), poterne au nord ; dans la cour, le donjon face au châtelet, la
##     caserne, l'armurerie et un puits ;
##   - autour des murs, un glacis d'herbe semé de couverts (rochers, chariots brisés, piles de
##     caisses et de bois) pour les assauts ;
##   - la route pavée vient du téléporteur du sud (vers Gludio), franchit le bras sud sur un
##     pont de pierre et monte au châtelet ; deux passerelles de bois sur les bras est et
##     ouest mènent aux bois de part et d'autre (prises à revers).
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_gludio_castle.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")
## Garnison du château (backend data/npc/others.xml et npc/shops) : gardes du châtelet et du
## donjon, intendant, armurier, capitaine des mercenaires.
const CASTLE_GUARD_IDS := ["398d224a-9d99-48a5-bdc9-b6c58f77ecee", "b4fc367b-a548-4c5e-ab22-498bbd89eca3",
		"701aaf3a-d298-4d02-bde4-f0772309b0e7", "a0794050-4aab-408a-abc4-4289d7851716"]
const CHAMBERLAIN_ID := "bfe9bed7-4db0-4f01-9036-08a666866b0e"
const CASTLE_BLACKSMITH_ID := "1fd6bc54-02da-4d17-995a-b3f177790f22"
const MERCENARY_ID := "fafba5b9-40b3-40fb-8660-506ba3373506"

const CENTER := Vector2(120.5, 95.0)
## Axe des courtines (rectangle) ; châtelet au sud, poterne au nord.
const WALL := [Vector2(80, 55), Vector2(161, 55), Vector2(161, 135), Vector2(80, 135)]
const GATE_S := Vector2(120.5, 135.0)
const GATE_N := Vector2(120.5, 55.0)
const KEEP := Vector2(120.5, 84.0)
const ROAD_HALF := 2.5
## Bras de la rivière (le bras sud passe en ligne droite est-ouest sous le pont de la route).
const RIVER_MAIN := [Vector2(123, -12), Vector2(121, 10), Vector2(120, 24)]
const ARM_WEST := [Vector2(120, 24), Vector2(92, 29), Vector2(58, 40), Vector2(41, 68), Vector2(39, 90.5),
		Vector2(41, 112), Vector2(48, 148), Vector2(72, 170), Vector2(100, 176.5), Vector2(120.5, 176.5),
		Vector2(141, 176.5), Vector2(168, 180), Vector2(190, 184)]
const ARM_EAST := [Vector2(120, 24), Vector2(150, 29), Vector2(184, 42), Vector2(199, 72), Vector2(201, 92.5),
		Vector2(200, 116), Vector2(196, 152), Vector2(190, 184), Vector2(186, 204), Vector2(178, 232)]
const BRIDGE_S := Vector2(120.5, 176.5)
const BRIDGE_W := Vector2(39.5, 90.5)
const BRIDGE_E := Vector2(201.5, 92.5)


func _setup() -> void:
	W = R.CASTLE_SIZE.x
	H = R.CASTLE_SIZE.y
	SEED = 20261011
	MAP_ID = R.CASTLE_ID
	MAP_NAME = R.CASTLE
	DESCRIPTION = "Le château de Gludio, sur son île entre les deux bras de la rivière : hautes courtines, grosses tours et donjon. Ici, nul refuge : les clans s'y disputent la place, les armes à la main."
	OUT_PATH = "res://scenes/maps/Gludio_Castle.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	BIOME = MapData.Biome.FOREST
	PLAYER_SPAWN = R.CASTLE_PORTAL_S + Vector2(0.0, -12.0)


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	for k in WALL.size():
		for p in _densify([WALL[k], WALL[(k + 1) % WALL.size()]], 0.5):
			_stamp("wall", p, 0.0, 20.0)
	var inside := _field("castle")
	for z in H:
		for x in W:
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("wall", p)
			inside[z * W + x] = -d if Geometry2D.is_point_in_polygon(p, PackedVector2Array(WALL)) else d

	# Bois hors de l'île, glacis d'herbe sur l'île.
	for z in H:
		for x in W:
			if _edge(x, z) < 34 + int(_noise.get_noise_2d(x, z) * 8.0):
				_terrain[z * W + x] = T.FOREST

	_bridge(BRIDGE_S, "z", true, "Pont_Sud")
	_bridge(BRIDGE_W, "x", false, "Passerelle_Ouest")
	_bridge(BRIDGE_E, "x", false, "Passerelle_Est")
	_river(RIVER_MAIN, 5.0, 0.6)
	_river(ARM_WEST, 4.4)
	_river(ARM_EAST, 4.4)

	_road([Vector2(120.5, H + 8), R.CASTLE_PORTAL_S, BRIDGE_S, Vector2(120.5, 150), GATE_S], ROAD_HALF, T.PAVED, 5.0)
	_paint_disc(R.CASTLE_PORTAL_S, 4.2, T.PAVED, [T.WATER])
	_stamp("open", R.CASTLE_PORTAL_S, 10.0, 20.0)
	# Chemin de ronde extérieur (terre battue) au pied des murs, chemins vers les passerelles.
	_road(_densify([Vector2(70, 45), Vector2(171, 45), Vector2(171, 146), Vector2(70, 146)], 3.0, true), 1.6, T.DIRT, 6.0, 0.4)
	_road([Vector2(70, 92), Vector2(56, 91), BRIDGE_W, Vector2(22, 90.5), Vector2(8, 86)], 1.3, T.DIRT, 3.0, 0.35)
	_road([Vector2(171, 93), Vector2(186, 92.5), BRIDGE_E, Vector2(218, 92.5), Vector2(232, 98)], 1.3, T.DIRT, 3.0, 0.35)
	_road([GATE_N, Vector2(120.5, 45)], 2.0, T.DIRT, 3.0, 0.2)
	# Cour du château en terre battue ; allée pavée du châtelet au donjon, parvis du donjon.
	_paint_field("castle", -1.0, T.DIRT, 0.6, [T.WATER])
	_paint_rect(Rect2(115.5, 92, 10, 44), T.PAVED)
	_paint_rect(Rect2(104, 94, 33, 6), T.PAVED)
	_stamp_rect("open", Rect2(70, 45, 101, 101), 8.0)
	# Bosquets sur l'île (couverts pour les assauts), loin des murs et des routes.
	for c in [Vector2(58, 60), Vector2(182, 60), Vector2(60, 140), Vector2(181, 140), Vector2(86, 162), Vector2(152, 160)]:
		_stamp_blob("grove", c, _rng.randf_range(5.0, 8.0))
	_edge_band(7, T.THICKET, [T.GRASS, T.FOREST])


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	var castle := _add(_props, _node("Chateau"))
	var features := [
		[GATE_S, 8.0, "CastleGatehouse", "Chatelet_Sud"],
		[GATE_N, 6.5, "Gatehouse", "Poterne_Nord"],
		[Vector2(100, 55), 4.6, "CastleTower"], [Vector2(141, 55), 4.6, "CastleTower"],
		[Vector2(100, 135), 4.6, "CastleTower"], [Vector2(141, 135), 4.6, "CastleTower"],
		[Vector2(80, 95), 4.6, "CastleTower"], [Vector2(161, 95), 4.6, "CastleTower"],
	]
	_fortification(castle, WALL, CENTER, features, "CastleTower", 4.6, "CastleWall", 4.0, 1.4)
	_building("CastleKeep", castle, KEEP, Vector2(0, 1), "Donjon")
	var inner := _add(castle, _node("Cour"))
	_building("HouseLarge", inner, Vector2(92.5, 112.5), Vector2(1, 0), "Caserne")
	_building("HouseLarge", inner, Vector2(92.5, 76.5), Vector2(1, 0), "Caserne_Nord")
	_building("Forge", inner, Vector2(149.0, 112.5), Vector2(-1, 0), "Armurerie", T.FORGE)
	_building("HouseMedium", inner, Vector2(149.0, 76.5), Vector2(-1, 0), "Ecuries")
	_instance("Well", inner, Vector2(108.5, 114.5), 0.0)
	for entry in [["Barrel", Vector2(96.5, 104.0)], ["Barrel", Vector2(97.4, 104.6)], ["Crate", Vector2(96.6, 121.5)],
			["Crate", Vector2(97.6, 121.0)], ["LogPile", Vector2(152.5, 104.0)], ["Crate", Vector2(145.5, 121.5)],
			["Barrel", Vector2(144.4, 121.8)], ["CartBroken", Vector2(145.0, 68.0)]]:
		_instance(entry[0], inner, entry[1], _rng.randf() * TAU)
	_place_cover()
	_place_lamps()
	var signs := _add(_props, _node("Panneaux"))
	_sign(signs, "Teleporteur", R.CASTLE_PORTAL_S + Vector2(5.0, -6.0), [[R.GLUDIO, 90.0], [R.CASTLE, 270.0]])
	_sign(signs, "Pont", BRIDGE_S + Vector2(-4.5, -11.0), [[R.CASTLE, 270.0], [R.GLUDIO, 90.0]])
	_portal("S", R.CASTLE_PORTAL_S, R.GLUDIO_ID, R.GLUDIO_PORTAL_N, R.GLUDIO)
	_checks["Châtelet (dehors)"] = GATE_S + Vector2(0, 7)
	_checks["Poterne (dehors)"] = GATE_N + Vector2(0, -6)
	_checks["Cour"] = Vector2(120.5, 118.5)
	_checks["Bois de l'ouest"] = Vector2(14.5, 90.5)
	_checks["Bois de l'est"] = Vector2(225.5, 95.5)
	_garrison()
	_hunting_grounds()


func _garrison() -> void:
	var npcs := [
		["GardeChatelet_O", CASTLE_GUARD_IDS[0], GATE_S + Vector2(-4.5, 8.5)],
		["GardeChatelet_E", CASTLE_GUARD_IDS[1], GATE_S + Vector2(4.5, 8.5)],
		["GardeDonjon_O", CASTLE_GUARD_IDS[2], KEEP + Vector2(-4.0, 14.0)],
		["GardeDonjon_E", CASTLE_GUARD_IDS[3], KEEP + Vector2(4.0, 14.0)],
		["Intendant", CHAMBERLAIN_ID, KEEP + Vector2(0.0, 15.5)],
		["Armurier", CASTLE_BLACKSMITH_ID, Vector2(143.0, 112.5)],
		["CapitaineMercenaires", MERCENARY_ID, Vector2(98.5, 112.5)],
	]
	for n in npcs:
		_npc(n[0], n[1], n[2])


## Pas de monstre sur l'île du château (comme dans Lineage 2), mais les bois au-delà des bras
## de la rivière reprennent les terrains de chasse voisins du château : à l'ouest les lézards
## Maille et les araignées (Araneid), à l'est le repaire des hommes-rats (Evil Hunting
## Grounds) et leur chef Sukar.
func _hunting_grounds() -> void:
	_monster_zone("Chateau_Lezards", Vector2(18, 62), 26.0, M.mix([["Maille Lizardman", 3], ["Maille Lizardman Scout", 2],
			["Maille Lizardman Guard", 1], ["Maille Lizardman Warrior", 1], ["Maille Lizardman Shaman", 1],
			["Maille Lizardman Matriarch", 1]]), 16)
	_monster_zone("Chateau_Araneides", Vector2(20, 160), 26.0, M.mix([["Giant Araneid", 2], ["Poison Araneid", 2],
			["King of the Araneid", 1]]), 11)
	_monster_zone("Chateau_HommesRats", Vector2(222, 62), 24.0, M.mix([["Ratman Spy", 2], ["Ratman Hunter", 2], ["Pinrul", 1],
			["Ratman Sub Chieftain", 1], ["Ratman Chieftain", 1]]), 14)
	_monster_zone("Chateau_Bugbears", Vector2(222, 150), 22.0, M.mix([["Bugbear Raider", 2], ["Pinrul", 1], ["Ratman Hunter", 1]]), 9)
	_monster_zone("Chateau_Sukar", Vector2(226, 48), 8.0, M.mix([["Sukar Wererat Chief", 1]]), 1, 3600)


## Couverts sur le glacis : rochers, chariots brisés, piles de caisses et de bois, troncs.
func _place_cover() -> void:
	var group := _add(_props, _node("Couverts"))
	var kinds := ["RockLarge", "RockMedium", "CartBroken", "LogPile", "LogFallen", "Crate", "Barrel", "RockMedium"]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 3000:
		tries += 1
		var p := Vector2(_rng.randf_range(46, 196), _rng.randf_range(32, 172))
		var d := _dist("castle", p)
		if d < 14.0 or _dist("river", p) < 4.0 or _dist("road", p) < 3.0 or p.distance_to(GATE_S) < 22.0:
			continue
		if _t_at(p) != T.GRASS and _t_at(p) != T.FOREST:
			continue
		if _reserved.has(Vector2i(int(p.x), int(p.y))):
			continue
		_instance(kinds[placed % kinds.size()], group, p, _rng.randf() * TAU)
		_reserve_disc(p, 7.0)
		placed += 1


func _place_lamps() -> void:
	var lamps := _add(_props, _node("Lampadaires"))
	for t in [14.0, 26.0]:
		for s in [-1.0, 1.0]:
			_lamp(lamps, GATE_S + Vector2(s * (ROAD_HALF + 1.2), t), Vector2(-s, 0))
	for z in [190.0, 204.0]:
		for s in [-1.0, 1.0]:
			_lamp(lamps, Vector2(120.5 + s * (ROAD_HALF + 0.8), z), Vector2(-s, 0))
	# Cour : de part et d'autre de l'allée du châtelet au donjon.
	for z in [101.0, 112.0, 123.0]:
		for s in [-1.0, 1.0]:
			_lamp(lamps, Vector2(120.5 + s * 6.0, z), Vector2(-s, 0))


func _after_props(blocked: Dictionary) -> void:
	var trees := _scatter(T.TREE, [T.GRASS, T.FOREST], func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)):
			return 0.0
		if _dist("road", p) < 3.0 or _dist("river", p) < 2.0 or _dist("open", p) < 0.0:
			return 0.0
		var castle := _dist("castle", p)
		if castle < 18.0:
			return 0.0
		var edge := float(_edge(x, z))
		var island := x > 40 and x < 200 and z > 24 and z < 178
		if island:
			return 0.3 if _dist("grove", p) < 0.0 else 0.008
		return lerpf(0.08, 0.45, clampf(1.0 - (edge - 8.0) / 30.0, 0.0, 1.0)))
	print("Arbres : %d" % trees)


func _configure_ground(ground: TerrainGround) -> void:
	ground.paved_asset = "PavingStones151"
	ground.paved_tile = Vector2(3.2, 3.2)
	ground.paved_desaturate = 0.45
	ground.paved_tint = Color(0.7, 0.68, 0.66)
