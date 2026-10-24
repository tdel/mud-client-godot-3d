extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Dion_Castle.tscn (260 x 240 cases), le château
## de Dion de Lineage 2, au sud de la ville de Dion, dans les plaines de Dion, près des cultures
## de Floran : zone de combat entre joueurs (aucune zone de paix) ; garnison de PNJ au château,
## monstres dans les champs, les plaines et le repaire des hommes-lézards Delu seulement (voir
## _hunting_grounds). Relancer ce script ÉCRASE la scène ; ensuite l'exporter vers le serveur
## avec tools/export_map_to_tmx.gd.
##
## Disposition (voir tools/map_gen/GludioRegion.gd) :
##   - au centre d'une plaine ouverte, le château : enceinte octogonale (pans coupés aux quatre
##     coins), onze grosses tours, châtelet au nord face à la route de Dion, poterne à l'ouest
##     vers les champs ; tout autour, des douves en anneau franchies par un pont de pierre
##     (châtelet) et une passerelle de bois (poterne) ; un chemin de ronde en terre longe les
##     douves ;
##   - dans la cour : allée pavée du châtelet au parvis du donjon (tourné vers le nord), la
##     caserne et son aire d'exercice, les écuries et leur enclos à l'ouest, l'armurerie
##     (forge) et l'entrepôt à l'est, un puits ;
##   - la route pavée descend du téléporteur du nord (vers Dion) au pont du châtelet ; à son
##     embranchement, des chemins de terre partent vers les cultures de Floran (ouest : champs
##     clôturés, fermes, moulin au bord d'une mare) et vers les plaines de l'est ;
##   - à l'est et au sud-est, des collines rocheuses (affleurements, éboulis) ; çà et là des
##     bosquets ; au sud, le repaire palissadé des hommes-lézards Delu (tentes, feu de camp,
##     tour de guet) et un camp de ravitaillement plus à l'est ; fourrés aux bords de la carte.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_dion_castle.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")
## Garnison du château de Dion (backend data/npc/others.xml et npc/shops).
const OUTER_DOORMAN_IDS := ["16e4b9fa-d800-496b-98d4-a7b0c7c97a38", "eca5f0d6-eb04-4ab4-97c7-0a991b610655"]
const INNER_DOORMAN_IDS := ["60f8ff14-718d-4cdb-a718-e7bfd02f9f88", "6f108b2c-1275-48d2-a2ed-3ebfaeef5065"]
const CHAMBERLAIN_ID := "d41b67ba-1546-4a84-9caa-50d42ea5dfa6"
const MERCENARY_ID := "764b97b5-9400-4f3c-b51f-9740b55fc60d"
const CASTLE_BLACKSMITH_ID := "99356390-f92d-4b8f-9db9-823f56040404"
const WAREHOUSE_ID := "7f930559-ca67-451f-88dd-6020fdf0458d"
const HERALD_ID := "29687d1d-82cf-4f22-a9af-daa6043c2ff7"
const WYVERN_MANAGER_ID := "1d0060d9-7de8-41d4-9a16-f8692d2bcc64"
const MASS_GATEKEEPER_ID := "bf0a92ae-432d-47e3-8288-98bc631b0ba3"

const CENTER := Vector2(130.5, 113.5)
## Axe des courtines : octogone (pans coupés aux coins) ; châtelet au nord, poterne à l'ouest.
const WALL := [Vector2(98, 72), Vector2(163, 72), Vector2(178, 87), Vector2(178, 140), Vector2(163, 155),
		Vector2(98, 155), Vector2(83, 140), Vector2(83, 87)]
const GATE_N := Vector2(130.5, 72.0)
const GATE_W := Vector2(83.0, 113.5)
const KEEP := Vector2(130.5, 122.5)
## Parvis du donjon et allée pavée.
const PLAZA := Rect2(112, 97, 37, 14)
## Cours en terre battue (aire d'exercice, abords des bâtiments, parvis) ; le reste de la cour
## est en herbe.
const YARDS := [Rect2(102, 79, 17, 26), Rect2(94, 85, 13, 14), Rect2(152, 85, 14, 17), Rect2(153, 127, 14, 14),
		Rect2(93, 129, 13, 12), Rect2(110, 95, 41, 18), Rect2(117, 109, 27, 27)]
## Pelouses plantées de quelques arbres (jardin derrière le donjon, pelouse de la fontaine).
const LAWNS := [Rect2(137, 78, 13, 15), Rect2(120, 138, 21, 10)]
const FOUNTAIN := Vector2(143.5, 85.5)
const ROAD_HALF := 2.5
## Douves : anneau d'eau entre ces distances (m) à l'axe des courtines.
const MOAT_IN := 14.0
const MOAT_OUT := 21.0
## Chemin de ronde extérieur, à cette distance des courtines.
const RING_D := 27.0
const BRIDGE_N := Vector2(130.5, 54.5)
const BRIDGE_W := Vector2(65.5, 113.5)
## Embranchement des chemins de terre sur la route du téléporteur.
const FORK := Vector2(130.5, 34.0)
const FARM_ROAD := [Vector2(128.5, 34), Vector2(110, 36.5), Vector2(90, 39.5), Vector2(70, 44), Vector2(50, 51),
		Vector2(35, 64), Vector2(27.5, 85), Vector2(26.5, 113.5), Vector2(28.5, 136), Vector2(36, 160), Vector2(50, 182),
		Vector2(66, 199)]
const EAST_ROAD := [Vector2(132.5, 34), Vector2(150, 36), Vector2(172, 40.5), Vector2(195, 48), Vector2(213, 59),
		Vector2(224, 78), Vector2(229, 96)]
## Cultures de Floran : [rectangle, clôturé].
const FIELDS := [[Rect2(72, 14, 22, 13), true], [Rect2(40, 22, 24, 14), false], [Rect2(36, 66, 14, 21), true],
		[Rect2(9, 68, 12, 26), false], [Rect2(34, 122, 15, 25), false], [Rect2(9, 124, 12, 20), true],
		[Rect2(62, 150, 13, 18), true]]
const MILL_POND := Vector2(44.0, 95.0)
const MILL := Vector2(40.0, 107.0)
## Repaire des hommes-lézards Delu (palissade, porte au nord) et camp de ravitaillement.
const LAIR := Vector2(138.5, 208.0)
const LAIR_R := 14.0
const SUPPLY_CAMP := Vector2(184.0, 210.0)
## Collines rocheuses : [centre, rayon].
const HILLS := [[Vector2(221, 110), 11.0], [Vector2(228, 152), 9.0], [Vector2(212, 182), 9.0], [Vector2(222, 70), 7.0],
		[Vector2(92, 222), 6.0]]
## Bosquets : [centre, rayon].
const GROVES := [[Vector2(30, 182), 9.0], [Vector2(96, 200), 7.0], [Vector2(212, 216), 8.0], [Vector2(238, 30), 9.0],
		[Vector2(184, 18), 6.0], [Vector2(56, 222), 6.0], [Vector2(240, 196), 7.0], [Vector2(206, 132), 6.0],
		[Vector2(14, 34), 7.0], [Vector2(78, 186), 5.0]]

## Props épars posés : [position, rayon] (évitement mutuel).
var _occupied: Array = []
## Abords de PNJ et de seuils gardés sans arbre.
var _keep_free: Array = []


func _setup() -> void:
	W = R.DION_CASTLE_SIZE.x
	H = R.DION_CASTLE_SIZE.y
	SEED = 20261023
	MAP_ID = R.DION_CASTLE_ID
	MAP_NAME = R.DION_CASTLE
	DESCRIPTION = "Le château de Dion, ceint de douves au milieu des plaines, entre les cultures de Floran et les collines rocheuses. Nul refuge ici : les clans s'en disputent les murs, et les hommes-lézards Delu rôdent au sud."
	OUT_PATH = "res://scenes/maps/Dion_Castle.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	BIOME = MapData.Biome.FOREST
	# Sur la route, une douzaine de cases après le téléporteur venu de Dion.
	PLAYER_SPAWN = R.DION_CASTLE_PORTAL_N + Vector2(0.0, 12.0)


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	for k in WALL.size():
		for p in _densify([WALL[k], WALL[(k + 1) % WALL.size()]], 0.5):
			_stamp("wall", p, 0.0, 40.0)
	var inside := _field("castle")
	var poly := PackedVector2Array(WALL)
	for z in H:
		for x in W:
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("wall", p)
			inside[z * W + x] = -d if Geometry2D.is_point_in_polygon(p, poly) else d

	# Lisière boisée (sol forestier) le long des bords ; herbe sombre par taches dans la plaine.
	var meadow := FastNoiseLite.new()
	meadow.seed = SEED + 5
	meadow.frequency = 0.03
	for z in H:
		for x in W:
			var i := z * W + x
			if _edge(x, z) < 14 + int(_noise.get_noise_2d(x, z) * 6.0):
				_terrain[i] = T.FOREST
			elif meadow.get_noise_2d(x, z) > 0.3 and inside[i] > MOAT_OUT + 4.0:
				_terrain[i] = T.DARK_GRASS

	# Douves (pont et passerelle déclarés avant l'eau).
	_bridge(BRIDGE_N, "z", true, "Pont_Chatelet")
	_bridge(BRIDGE_W, "x", false, "Passerelle_Poterne")
	_moat()

	# Route pavée du téléporteur au châtelet, puis allée de la cour jusqu'au parvis du donjon.
	_road([Vector2(130.5, -8), R.DION_CASTLE_PORTAL_N, Vector2(130.5, 20), FORK, Vector2(130.5, 44), BRIDGE_N, GATE_N,
			Vector2(130.5, PLAZA.position.y + 1.0)], ROAD_HALF, T.PAVED, 4.0, 0.2)
	_paint_disc(R.DION_CASTLE_PORTAL_N, 4.2, T.PAVED, [T.WATER])
	_stamp("open", R.DION_CASTLE_PORTAL_N, 10.0, 20.0)
	# Chemin de ronde au-delà des douves.
	var ring: Array = Array(Geometry2D.offset_polygon(poly, RING_D, Geometry2D.JOIN_ROUND)[0])
	ring.append(ring[0])
	_road(ring, 1.5, T.DIRT, 3.0, 0.35)
	# Chemins de terre : cultures de Floran (ouest), plaines de l'est, poterne, repaire.
	_road(FARM_ROAD, 1.7, T.DIRT, 2.5, 0.4)
	_road(EAST_ROAD, 1.5, T.DIRT, 2.5, 0.4)
	_road([Vector2(97, 113.5), GATE_W, BRIDGE_W, Vector2(48, 113.5), Vector2(27, 113.5)], 1.5, T.DIRT, 2.5, 0.25)
	_road([Vector2(130.5, WALL[4].y + RING_D), Vector2(134, 192), LAIR + Vector2(0, -LAIR_R - 1.0)],
			1.3, T.DIRT, 2.0, 0.4)
	_road([Vector2(151, 203), Vector2(166, 207), SUPPLY_CAMP], 1.2, T.DIRT, 1.5, 0.4)

	# Cour : terre battue au pied des murs et devant les bâtiments, pelouses (jardin derrière le
	# donjon, pelouse de la fontaine, aire des wyvernes), parvis du donjon, sentier de la poterne.
	_paint_field("castle", -1.0, T.DIRT, 0.6, [T.WATER])
	for yard in YARDS:
		_stamp_rect("yard", yard, 6.0)
	for lawn in LAWNS:
		_stamp_rect("lawn", lawn, 4.0)
	var castle: PackedFloat32Array = _fields["castle"]
	var yards: PackedFloat32Array = _fields["yard"]
	for i in W * H:
		var n := _noise.get_noise_2d((i % W) * 1.3, (i / W) * 1.3) * 1.5
		if castle[i] < -6.0 + n and yards[i] > 0.5 - n and _terrain[i] == T.DIRT:
			_terrain[i] = T.GRASS
	_paint_rect(PLAZA, T.PAVED)
	_road([Vector2(96, 113.5), Vector2(108, 113.5), Vector2(114, PLAZA.end.y - 1.0)], 1.2, T.PAVED, 0.5, 0.15)
	_stamp_rect("open", Rect2(WALL[7].x, WALL[0].y, WALL[2].x - WALL[7].x, WALL[4].y - WALL[0].y), 6.0)

	# Cultures de Floran, mare du moulin.
	for f in FIELDS:
		_paint_rect(f[0], T.CROP, [T.PAVED, T.DIRT, T.WATER])
		_stamp_rect("open", f[0], 3.0)
	_pond(MILL_POND, 4.6)
	_stamp("open", MILL_POND, 6.0, 12.0)

	# Bosquets, collines rocheuses, repaire.
	for g in GROVES:
		_stamp_blob("grove", g[0], g[1])
	_paint_field("grove", 0.0, T.FOREST, 1.5, [T.WATER, T.PAVED, T.DIRT, T.CROP])
	for h in HILLS:
		_stamp_blob("hill", h[0], h[1])
		_rubble_core(h[0], h[1] * 0.4)
	_paint_field("hill", 1.0, T.DARK_GRASS, 1.5, [T.WATER, T.PAVED, T.DIRT, T.CROP, T.RUBBLE])
	_stamp_blob("lair", LAIR, LAIR_R + 2.0)
	_paint_field("lair", -3.0, T.DIRT, 1.2, [T.WATER])
	_paint_field("lair", 1.5, T.DARK_GRASS, 1.2, [T.WATER, T.DIRT])
	_stamp_blob("lair", SUPPLY_CAMP, 7.0)
	_paint_disc(SUPPLY_CAMP, 5.0, T.DIRT, [T.WATER])

	_edge_band(7, T.THICKET, [T.GRASS, T.FOREST, T.DARK_GRASS])


## Douves en anneau autour des courtines (bord extérieur légèrement irrégulier, net au droit
## des ponts) ; champ "river" (négatif dans l'eau).
func _moat() -> void:
	var river := _field("river")
	var castle: PackedFloat32Array = _fields["castle"]
	for z in H:
		for x in W:
			var i := z * W + x
			var p := Vector2(x + 0.5, z + 0.5)
			var d := castle[i]
			if d < MOAT_IN - 10.0 or d > MOAT_OUT + 12.0:
				continue
			var outer := MOAT_OUT
			if not _near_bridge(p, 3.0):
				outer += _noise.get_noise_2d(x * 0.8, z * 0.8) * 1.2
			var v := maxf(MOAT_IN - d, d - outer)
			river[i] = minf(river[i], v)
			if v <= 0.0:
				_terrain[i] = T.WATER
	_fields["river"] = river


## Cœur d'une colline : éboulis infranchissables (rochers) au bord irrégulier.
func _rubble_core(c: Vector2, radius: float) -> void:
	var tmp := "_tmp_rubble"
	_fields.erase(tmp)
	_stamp_blob(tmp, c, radius)
	var arr: PackedFloat32Array = _fields[tmp]
	for i in W * H:
		if arr[i] <= 0.0 and not [T.WATER, T.PAVED, T.DIRT, T.CROP].has(_terrain[i]):
			if _dist("road", Vector2(i % W + 0.5, i / W + 0.5)) > 2.5:
				_terrain[i] = T.RUBBLE
	_fields.erase(tmp)


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	var castle := _add(_props, _node("Chateau"))
	var features := [
		[GATE_N, 8.0, "CastleGatehouse", "Chatelet_Nord"],
		[GATE_W, 6.5, "Gatehouse", "Poterne_Ouest"],
		[Vector2(178, 113.5), 4.6, "CastleTower"],
		[Vector2(115, 155), 4.6, "CastleTower"], [Vector2(146, 155), 4.6, "CastleTower"],
	]
	_fortification(castle, WALL, CENTER, features, "CastleTower", 4.6, "CastleWall", 4.0, 1.4)
	for v in WALL:
		_reserve_disc(v, 6.0)
	for f in features:
		_reserve_disc(f[0], 9.0 if String(f[2]).contains("Gatehouse") else 6.0)
	_building("CastleKeep", castle, KEEP, Vector2(0, -1), "Donjon")
	_reserve_cells(_rect_cells(KEEP, Vector2(0, -1), Vector2(22.2, 22.2), 1.5))
	_courtyard(castle)
	_garrison()
	_floran(_add(_props, _node("Floran")))
	_lair(_add(_props, _node("Repaire_Delu")))
	_hills(_add(_props, _node("Collines")))
	_place_cover()
	_place_lamps()
	_place_signs()
	_portal("N", R.DION_CASTLE_PORTAL_N, R.DION_ID, R.DION_PORTAL_S, R.DION)
	_checks["Châtelet (dehors)"] = GATE_N + Vector2(0, -7)
	_checks["Poterne (dehors)"] = GATE_W + Vector2(-6, 0)
	_checks["Cour"] = Vector2(130.5, 88.5)
	_checks["Derrière le donjon"] = Vector2(130.5, 143.5)
	_checks["Chemin de ronde (sud)"] = Vector2(130.5, WALL[4].y + RING_D)
	_checks["Chemin de ronde (est)"] = Vector2(WALL[2].x + RING_D, 113.5)
	_checks["Champs de Floran"] = Vector2(27.5, 100.5)
	_checks["Plaines de l'est"] = Vector2(226.5, 88.5)
	_hunting_grounds()


## Cour : caserne et aire d'exercice, écuries et enclos (ouest), armurerie et entrepôt (est),
## puits, caisses et tonneaux.
func _courtyard(castle: Node) -> void:
	var inner := _add(castle, _node("Cour"))
	_house(inner, "HouseLarge", Vector2(100.5, 92.0), Vector2(1, 0), "Caserne")
	_house(inner, "HouseMedium", Vector2(99.5, 135.0), Vector2(1, 0), "Ecuries")
	_house(inner, "Forge", Vector2(161.0, 93.0), Vector2(-1, 0), "Armurerie", T.FORGE)
	_house(inner, "HouseLarge", Vector2(161.5, 134.0), Vector2(-1, 0), "Entrepot")
	_fence_rect(inner, Rect2(105, 139, 11, 9))
	_reserve_cells(_rect_cells(Vector2(110.5, 143.5), Vector2(0, 1), Vector2(11, 9), 0.5))
	_prop(inner, "Well", Vector2(114.5, 88.5), 0.0, 1.6)
	_prop(inner, "Fountain", FOUNTAIN, 0.0, 3.0)
	_checks["Fontaine de la cour"] = FOUNTAIN + Vector2(0, 4.5)
	_prop(inner, "WeaponRack", Vector2(110.5, 84.0), PI / 2.0, 1.4)
	_prop(inner, "WeaponRack", Vector2(110.5, 99.5), PI / 2.0, 1.4)
	for entry in [["Barrel", Vector2(96.0, 99.5)], ["Barrel", Vector2(97.0, 100.2)], ["Crate", Vector2(96.4, 84.0)],
			["LogPile", Vector2(166.0, 102.0)], ["Crate", Vector2(155.0, 101.5)], ["Barrel", Vector2(154.0, 101.0)],
			["Crate", Vector2(166.5, 126.0)], ["Crate", Vector2(167.2, 126.9)], ["Barrel", Vector2(155.0, 141.5)],
			["PlankPile", Vector2(98.0, 126.0)], ["CartBroken", Vector2(118.0, 147.5)], ["LogPile", Vector2(146.0, 147.0)],
			["Crate", Vector2(150.5, 112.0)], ["Barrel", Vector2(151.2, 113.0)]]:
		_prop(inner, entry[0], entry[1], _rng.randf() * TAU, 0.9)


func _garrison() -> void:
	var npcs := [
		["Portier_Exterieur_O", OUTER_DOORMAN_IDS[0], GATE_N + Vector2(-4.5, -7.5)],
		["Portier_Exterieur_E", OUTER_DOORMAN_IDS[1], GATE_N + Vector2(4.5, -7.5)],
		["Portier_Interieur_O", INNER_DOORMAN_IDS[0], KEEP + Vector2(-4.0, -14.0)],
		["Portier_Interieur_E", INNER_DOORMAN_IDS[1], KEEP + Vector2(4.0, -14.0)],
		["Intendant_Crosby", CHAMBERLAIN_ID, KEEP + Vector2(0.0, -15.5)],
		["Mercenaires_Sanford", MERCENARY_ID, Vector2(107.0, 95.5)],
		["Armurier", CASTLE_BLACKSMITH_ID, Vector2(155.5, 93.0)],
		["Magasinier", WAREHOUSE_ID, Vector2(155.0, 131.0)],
		["Heraut_Gibbson", HERALD_ID, Vector2(125.0, 84.5)],
		["Wyvernes_Hodler", WYVERN_MANAGER_ID, Vector2(148.5, 118.5)],
		["Gardien_Portails", MASS_GATEKEEPER_ID, R.DION_CASTLE_PORTAL_N + Vector2(5.0, 7.0)],
	]
	for n in npcs:
		_npc(n[0], n[1], n[2])
		_reserve_disc(n[2], 2.5)
		_keep_free.append(n[2])


## Cultures de Floran : champs (clôturés pour certains), fermes, moulin au bord de la mare,
## chariots, bois et planches.
func _floran(parent: Node) -> void:
	var fences := _add(parent, _node("Clotures"))
	for f in FIELDS:
		if f[1]:
			_fence_rect(fences, f[0])
		_reserve_cells(_rect_cells((f[0] as Rect2).get_center(), Vector2(0, 1), (f[0] as Rect2).size, 1.0))
	_house(parent, "HouseMedium", Vector2(103.0, 25.0), Vector2(0, 1), "Ferme_Nord")
	_house(parent, "HouseSmall", Vector2(66.0, 55.0), Vector2(0.3, -1), "Ferme_Chemin")
	_house(parent, "HouseMedium", Vector2(14.5, 104.0), Vector2(1, 0), "Ferme_Ouest")
	_house(parent, "HouseSmall", Vector2(50.0, 165.0), Vector2(-1, 0.2), "Ferme_Sud")
	_house(parent, "Sawmill", MILL, Vector2(0, 1), "Moulin")
	for entry in [["LogPile", Vector2(110.5, 24.0)], ["CartBroken", Vector2(96.0, 30.0)], ["Barrel", Vector2(108.5, 28.5)],
			["PlankPile", Vector2(73.0, 52.0)], ["Crate", Vector2(60.5, 57.0)], ["LogPile", Vector2(14.0, 112.0)],
			["CartBroken", Vector2(20.0, 98.0)], ["Barrel", Vector2(19.5, 109.5)], ["PlankPile", Vector2(50.0, 104.0)],
			["LogPile", Vector2(33.0, 104.0)], ["CartBroken", Vector2(56.0, 158.0)], ["Crate", Vector2(55.0, 172.0)],
			["CartBroken", Vector2(56.0, 30.0)], ["Barrel", Vector2(52.0, 88.0)]]:
		_prop(parent, entry[0], entry[1], _rng.randf() * TAU, 1.2)


## Repaire des hommes-lézards Delu : palissade en anneau (porte au nord, une brèche à l'est),
## tentes autour d'un feu de camp, tour de guet, cage, râteliers ; camp de ravitaillement à
## l'est.
func _lair(parent: Node) -> void:
	_palisade_ring(parent, LAIR, LAIR_R, 11, -PI / 2.0, 3)
	_reserve_disc(LAIR, LAIR_R + 2.5)
	_lair_prop(parent, "TentLarge", LAIR + Vector2(0, 7.0), Vector2(0, -1), 3.6, "Grande_Tente")
	_lair_prop(parent, "Tent", LAIR + Vector2(-8.0, 1.0), Vector2(1, 0), 2.4, "Tente_O")
	_lair_prop(parent, "Tent", LAIR + Vector2(8.0, 1.5), Vector2(-1, 0), 2.4, "Tente_E")
	_lair_prop(parent, "Campfire", LAIR + Vector2(0, -2.0), Vector2(0, 1), 1.2, "Feu_de_camp")
	_lair_prop(parent, "WatchTowerWood", LAIR + Vector2(-6.0, -5.0), Vector2(0, -1), 2.4, "Tour_de_guet")
	_lair_prop(parent, "Cage", LAIR + Vector2(7.5, 8.0), Vector2(-1, -1), 1.6, "Cage")
	_lair_prop(parent, "WeaponRack", LAIR + Vector2(6.0, -6.5), Vector2(-1, 1), 1.2, "Ratelier")
	_lair_prop(parent, "Crate", LAIR + Vector2(-4.0, 10.5), Vector2(0, 1), 0.6, "Caisse")
	_lair_prop(parent, "Barrel", LAIR + Vector2(-5.0, 9.8), Vector2(0, 1), 0.5, "Tonneau")
	_checks["Repaire Delu (porte)"] = LAIR + Vector2(0, -LAIR_R - 3.0)
	_checks["Repaire Delu (feu de camp)"] = LAIR + Vector2(0, -5.5)
	# Camp de ravitaillement (sans palissade).
	var camp := _add(parent, _node("Camp_Ravitaillement"))
	_lair_prop(camp, "Tent", SUPPLY_CAMP + Vector2(-3.5, 2.5), Vector2(0.5, -1), 2.4, "Tente_1")
	_lair_prop(camp, "Tent", SUPPLY_CAMP + Vector2(4.0, 2.0), Vector2(-0.6, -1), 2.4, "Tente_2")
	_lair_prop(camp, "Campfire", SUPPLY_CAMP + Vector2(0, -2.0), Vector2(0, 1), 1.2, "Feu")
	for e in [["Crate", Vector2(-1.5, -6.0)], ["Crate", Vector2(-0.7, -6.6)], ["Barrel", Vector2(1.5, -6.2)],
			["CartBroken", Vector2(7.5, -4.0)]]:
		_prop(camp, e[0], SUPPLY_CAMP + e[1], _rng.randf() * TAU, 1.0)
	_checks["Camp de ravitaillement"] = SUPPLY_CAMP + Vector2(0, -4.0)


func _lair_prop(parent: Node, scene: String, pos: Vector2, facing: Vector2, radius: float, node_name: String) -> void:
	_instance(scene, parent, pos, atan2(facing.x, facing.y)).name = node_name
	_occupy(pos, radius)


## Palissade en anneau (polygone à `sides` côtés) : porte (PalisadeGate) centrée sur l'angle
## `gate_angle`, côté `breach` laissé ouvert (brèche, un tronc tombé à côté).
func _palisade_ring(parent: Node, c: Vector2, radius: float, sides: int, gate_angle: float, breach: int) -> void:
	var group := _add(parent, _node("Palissade"))
	var verts := []
	for k in sides:
		var a := gate_angle + TAU * (k + 0.5) / sides
		verts.append(c + Vector2(cos(a), sin(a)) * radius)
	for k in sides:
		var a: Vector2 = verts[(k - 1 + sides) % sides]
		var b: Vector2 = verts[k]
		var dir := (b - a).normalized()
		if k == 0:
			var gate := _instance("PalisadeGate", group, (a + b) / 2.0, atan2(-dir.y, dir.x))
			gate.name = "Porte_Palissade"
			gate.scale = Vector3(a.distance_to(b) / 7.0, 1.0, 1.0)
			_terrain_under.append([gate, T.RAMPART])
		elif k == breach:
			var mid := (a + b) / 2.0 + ((a + b) / 2.0 - c).normalized() * 2.2
			_instance("LogFallen", group, mid, atan2(-dir.y, dir.x) + 0.4)
		else:
			_wall_run(group, "Palisade", 4.0, a - dir * 0.3, b + dir * 0.3)


## Collines rocheuses : amas de gros rochers sur les éboulis, pierres éparses autour ; arbres
## morts et souches dans les bosquets ; rochers isolés dans la plaine.
func _hills(parent: Node) -> void:
	for h in HILLS:
		var c: Vector2 = h[0]
		var r: float = h[1]
		var group := _add(parent, _node("Colline_%d_%d" % [int(c.x), int(c.y)]))
		for k in int(r / 1.8):
			var a := _rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * _rng.randf_range(0.0, r * 0.36)
			var rock := _instance("RockLarge", group, p, _rng.randf() * TAU)
			rock.scale = Vector3.ONE * _rng.randf_range(1.5, 2.5)
			_occupy(p, 1.2)
		for k in int(r / 1.4):
			var a := _rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * _rng.randf_range(r * 0.42, r * 0.8)
			if _spot_free(p, 1.0) or [T.RUBBLE].has(_t_at(p)):
				var rock := _instance("RockLarge" if _rng.randf() < 0.4 else "RockMedium", group, p, _rng.randf() * TAU)
				rock.scale = Vector3.ONE * _rng.randf_range(1.0, 1.7)
				_occupy(p, 1.2)
		_scatter_props(group, ["RockMedium"], int(r / 2.0), Rect2(c - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), 0.8,
				func(p: Vector2) -> bool: return _dist("hill", p) < 3.0)
	var area := Rect2(12, 12, W - 24, H - 24)
	var plain := func(p: Vector2) -> bool:
		return _dist("castle", p) > RING_D + 5.0 and _dist("lair", p) > 4.0 and _t_at(p) != T.CROP
	_scatter_props(parent, ["RockMedium", "RockMedium", "RockLarge"], 18, area, 1.0, plain)
	var in_grove := func(p: Vector2) -> bool: return _dist("grove", p) < 2.0
	_scatter_props(parent, ["LogFallen", "Stump", "TreeDead"], 12, area, 1.6, in_grove)


## Couverts sur le glacis au-delà des douves : rochers, chariots brisés, piles de bois.
func _place_cover() -> void:
	var group := _add(_props, _node("Couverts"))
	var kinds := ["RockLarge", "CartBroken", "LogPile", "RockMedium", "LogFallen", "Crate", "RockMedium"]
	var placed := 0
	var tries := 0
	while placed < 24 and tries < 4000:
		tries += 1
		var p := Vector2(_rng.randf_range(50, 210), _rng.randf_range(40, 190))
		var d := _dist("castle", p)
		if d < MOAT_OUT + 3.0 or d > RING_D + 14.0 or absf(d - RING_D) < 3.0:
			continue
		if not _spot_free(p, 1.6) or p.distance_to(GATE_N) < 26.0:
			continue
		if not [T.GRASS, T.DARK_GRASS].has(_t_at(p)):
			continue
		_instance(kinds[placed % kinds.size()], group, p, _rng.randf() * TAU)
		_occupy(p, 1.6)
		placed += 1


func _place_lamps() -> void:
	var lamps := _add(_props, _node("Lampadaires"))
	# Route du téléporteur et tête du pont.
	for z in [24.0, 40.0]:
		for s in [-1.0, 1.0]:
			_lamp(lamps, Vector2(130.5 + s * (ROAD_HALF + 1.0), z), Vector2(-s, 0))
	for s in [-1.0, 1.0]:
		_lamp(lamps, Vector2(130.5 + s * (ROAD_HALF + 1.0), 45.0), Vector2(-s, 0))
		_lamp(lamps, GATE_N + Vector2(s * 8.0, -6.5), Vector2(-s, 0))
	# Allée de la cour et coins du parvis.
	for z in [80.0, 90.0]:
		for s in [-1.0, 1.0]:
			_lamp(lamps, Vector2(130.5 + s * (ROAD_HALF + 1.5), z), Vector2(-s, 0))
	for c in [PLAZA.position + Vector2(1, 1), Vector2(PLAZA.end.x - 1, PLAZA.position.y + 1)]:
		_lamp(lamps, c, (KEEP - c).normalized())
	_lamp(lamps, GATE_W + Vector2(9.0, -3.0), Vector2(0, 1))


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	_sign_at(signs, "Teleporteur", R.DION_CASTLE_PORTAL_N + Vector2(-5.5, 6.5), [[R.DION, 270.0], [R.DION_CASTLE, 90.0]])
	_sign_at(signs, "Embranchement", FORK + Vector2(-4.5, 4.0), [[R.DION, 270.0], [R.DION_CASTLE, 90.0],
			["Cultures de Floran", 175.0], ["Plaines de Dion", 5.0]])
	_sign_at(signs, "Poterne", Vector2(51.5, 117.5), [[R.DION_CASTLE, 0.0], ["Cultures de Floran", 180.0]])
	_sign_at(signs, "Floran", Vector2(31.5, 109.0), [[R.DION_CASTLE, 0.0], ["Moulin", -70.0], [R.DION, -60.0]])
	_sign_at(signs, "Repaire", Vector2(127.5, 189.0), [["Repaire des Delu", 80.0], [R.DION_CASTLE, 270.0]])


## Pas de monstre au château ni sur ses abords (douves, chemin de ronde), comme dans Lineage 2 ;
## dans la plaine, les monstres des plaines de Dion et des cultures de Floran : loups et
## bugbears dans les champs et les bosquets (plus faibles au nord), yeux et guetteurs sur les
## collines avec les golems de pierre, hommes-lézards Delu dans leur repaire au sud.
func _hunting_grounds() -> void:
	var zones := [
		["DionChateau_ChampsNord", Vector2(60, 28), 22.0, [["Tumran Bugbear", 2], ["Dire Wolf", 1]], 8],
		["DionChateau_ChampsOuest", Vector2(22, 100), 20.0, [["Dire Wolf", 2], ["Tumran Bugbear", 2], ["Watchman of the Plains", 1]], 10],
		["DionChateau_ChampsSud", Vector2(30, 155), 21.0, [["Dire Wolf", 2], ["Watchman of the Plains", 2], ["Monster Eye Gazer", 1]], 10],
		["DionChateau_BosquetsNE", Vector2(202, 30), 22.0, [["Tumran Bugbear", 2], ["Dire Wolf", 2], ["Monster Eye Gazer", 1]], 10],
		["DionChateau_CollinesEst", Vector2(230, 110), 21.0, [["Roughly Hewn Rock Golem", 3], ["Monster Eye Gazer", 2],
				["Watchman of the Plains", 1]], 13],
		["DionChateau_CollinesSE", Vector2(216, 180), 22.0, [["Roughly Hewn Rock Golem", 2], ["Watchman of the Plains", 2],
				["Cursed Seer", 1]], 11],
		["DionChateau_PlaineSO", Vector2(70, 212), 20.0, [["Cursed Seer", 2], ["Watchman of the Plains", 1],
				["Monster Eye Gazer", 1], ["Delu Lizardman Supplier", 1]], 10],
		["DionChateau_RepaireDelu", LAIR, 16.0, [["Delu Lizardman Supplier", 2], ["Delu Lizardman Special Agent", 2],
				["Delu Lizardman Shaman", 2], ["Delu Lizardman Commander", 1]], 14],
		["DionChateau_CampDelu", SUPPLY_CAMP + Vector2(2, 0), 16.0, [["Delu Lizardman Supplier", 2],
				["Delu Lizardman Special Agent", 1], ["Cursed Seer", 1]], 8],
	]
	for zone in zones:
		_check_zone_clear(zone[0], zone[1], zone[2])
		_monster_zone(zone[0], zone[1], zone[2], M.mix(zone[3]), zone[4])


## Avertit si une zone de chasse empiète sur les abords du château (douves, chemin de ronde).
func _check_zone_clear(group: String, c: Vector2, radius: float) -> void:
	for z in range(maxi(0, floori(c.y - radius)), mini(H, ceili(c.y + radius) + 1)):
		for x in range(maxi(0, floori(c.x - radius)), mini(W, ceili(c.x + radius) + 1)):
			var p := Vector2(x + 0.5, z + 0.5)
			if p.distance_to(c) <= radius and _dist("castle", p) < RING_D + 3.0:
				push_warning("Zone de chasse %s trop près du château (%s)" % [group, p])
				return


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

## Bâtiment (porte vers `facing`) dont l'emprise et le seuil sont réservés.
func _house(parent: Node, scene: String, pos: Vector2, facing: Vector2, node_name: String, t: int = T.BUILDING) -> void:
	_building(scene, parent, pos, facing, node_name, t)
	var size: Vector2 = BUILDING_SIZE.get(scene, Vector2(11.4, 6.4))
	_reserve_cells(_rect_cells(pos, facing, size, 1.2))
	if DOOR_DEPTH.has(scene):
		_keep_free.append(pos + facing.normalized() * (DOOR_DEPTH[scene] + 1.0))


func _prop(parent: Node, scene: String, pos: Vector2, yaw: float, radius: float) -> void:
	_instance(scene, parent, pos, yaw)
	_occupy(pos, radius)


## Clôture autour d'un rectangle, une ouverture au milieu de chaque côté.
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


func _occupy(p: Vector2, radius: float) -> void:
	_occupied.append([p, radius])
	_reserve_disc(p, radius + 0.8)


func _near_check(p: Vector2, radius: float) -> bool:
	for c in _checks.values():
		if (c as Vector2).distance_to(p) < radius:
			return true
	for k in _keep_free:
		if (k as Vector2).distance_to(p) < radius:
			return true
	return false


## Vrai si un prop de rayon `radius` peut se poser en p : hors lisière, au sec, loin des
## routes, des points vérifiés, des réservations et des autres props.
func _spot_free(p: Vector2, radius: float) -> bool:
	var cell := Vector2i(int(p.x), int(p.y))
	if not _in_map(cell) or _edge(cell.x, cell.y) < 9 or _reserved.has(cell):
		return false
	if [T.WATER, T.BRIDGE, T.THICKET, T.REEDS, T.CROP, T.RUBBLE, T.PAVED, T.DIRT].has(_t_at(p)):
		return false
	if _dist("road", p) < radius + 1.5 or _dist("river", p) < radius + 1.5 or _near_check(p, radius + 2.5):
		return false
	for o in _occupied:
		if p.distance_to(o[0]) < radius + o[1] + 1.5:
			return false
	return true


func _scatter_props(parent: Node, scenes: Array, count: int, area: Rect2, radius: float, cond := Callable()) -> int:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 80:
		tries += 1
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if not _spot_free(p, radius) or (cond.is_valid() and not cond.call(p)):
			continue
		_instance(scenes[_rng.randi() % scenes.size()], parent, p, _rng.randf() * TAU)
		_occupy(p, radius)
		placed += 1
	return placed


## Poteau indicateur au bord du chemin (jamais sur la chaussée).
func _sign_at(parent: Node, sign_name: String, pos: Vector2, entries: Array) -> void:
	if _dist("road", pos) < 0.5:
		push_warning("Panneau %s sur la chaussée (%s)" % [sign_name, pos])
	_sign(parent, sign_name, pos, entries)
	_occupy(pos, 0.8)


# ---------------------------------------------------------------------------
# 3. Arbres (une fois les emprises connues)
# ---------------------------------------------------------------------------

func _after_props(blocked: Dictionary) -> void:
	var trees := _scatter(T.TREE, [T.GRASS, T.DARK_GRASS, T.FOREST], func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)):
			return 0.0
		if _dist("road", p) < 2.5 or _dist("river", p) < 2.0 or _dist("open", p) < 0.0:
			return 0.0
		if _dist("lair", p) < 3.0 or _near_check(p, 3.0):
			return 0.0
		var castle := _dist("castle", p)
		if castle < -8.0 and _dist("lawn", p) < -1.5:
			return 0.05
		if castle < RING_D + 6.0:
			return 0.0
		var grove := _dist("grove", p)
		if grove < 0.0:
			return lerpf(0.2, 0.45, clampf(-grove / 5.0, 0.0, 1.0))
		if _dist("hill", p) < 0.0:
			return 0.015
		var edge := float(_edge(x, z))
		return lerpf(0.004, 0.4, clampf(1.0 - (edge - 7.0) / 16.0, 0.0, 1.0)))
	print("Arbres : %d" % trees)


func _configure_ground(ground: TerrainGround) -> void:
	ground.paved_asset = "PavingStones151"
	ground.paved_tile = Vector2(3.2, 3.2)
	ground.paved_desaturate = 0.4
	ground.paved_tint = Color(0.76, 0.72, 0.66)
	# Plaine ensoleillée : herbe claire et chaude, terre blonde des champs.
	ground.shader_overrides = {
		"grass_tint": Color(0.76, 0.78, 0.6),
		"dark_grass_tint": Color(0.56, 0.62, 0.46),
		"dirt_tint": Color(0.86, 0.77, 0.64),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.grass_density = 0.6
	vegetation.bush_density = 0.025
	vegetation.rock_density = 0.016
	vegetation.dead_tree_ratio = 0.04
