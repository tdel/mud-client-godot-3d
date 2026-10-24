extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Ruins_of_Agony.tscn (260 x 200 cases), les
## ruines d'Agonie, à l'ouest de Gludio, sur le modèle des Ruins of Agony de Lineage 2.
## Zone sauvage (ni ville ni zone de paix), sans PNJ ; monstres de Lineage 2 (voir _hunting_grounds). Relancer ce script ÉCRASE
## la scène ; ensuite l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Ruins_of_Agony.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - une lande d'herbe sombre ondulée, semée de bosquets, ceinte de forêt et de fourrés ;
##   - la vieille route pavée et moussue, sinueuse, du téléporteur de l'est (Gludio) à celui
##     de l'ouest (le lac de Fellmere) ;
##   - au nord de la route, la cité antique : une voie processionnelle bordée de colonnades
##     et d'arches brisées monte vers le sanctuaire du crâne géant (le repère des ruines sur
##     la carte de Lineage 2), entre des édifices effondrés et deux pans de l'ancienne
##     enceinte ; à l'ouest, le temple en ruine et son autel ;
##   - au sud-est de la route, la ville basse : maisons éventrées autour d'une placette et
##     de sa statue ;
##   - au sud-ouest, l'étang englouti, ses roseaux et deux colonnes englouties ;
##   - des chemins de terre vers le temple, la ville basse et le lac, des poteaux
##     indicateurs aux embranchements et près des téléporteurs.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_ruins_of_agony.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")

const ROAD_HALF := 2.5
const WAY_HALF := 3.0
## Vieille route, de l'est (Gludio) à l'ouest (le lac de Fellmere), prolongée au-delà des bords.
const ROAD := [Vector2(268, 100.5), Vector2(254.5, 100.5), Vector2(238, 100), Vector2(220, 96.5), Vector2(200, 93.5),
		Vector2(175, 94), Vector2(150, 97), Vector2(135, 98.5), Vector2(115, 101), Vector2(92, 107), Vector2(70, 109.5),
		Vector2(45, 104), Vector2(22, 100.5), Vector2(5.5, 100.5), Vector2(-8, 100.5)]
## Voie processionnelle (nord-sud) et sanctuaire du crâne.
const WAY_X := 135.5
const WAY_START := 96.0
const PLAZA := Vector2(135.5, 39.0)
const PLAZA_R := 13.0
const SKULL := Vector2(135.5, 25.5)
## Temple en ruine (ouest) et son autel.
const TEMPLE := Vector2(65.5, 58.0)
const TEMPLE_SIZE := Vector2(30, 22)
## Ville basse (sud-est) : placette.
const SQUARE := Vector2(189.5, 142.0)
## Étang englouti (sud-ouest).
const LAKE := Vector2(48.0, 161.0)
const LAKE_R := 18.5
## Bosquets : [centre, rayon].
const GROVES := [[Vector2(28, 38), 15.0], [Vector2(80, 20), 9.0], [Vector2(222, 172), 15.0], [Vector2(104, 160), 12.0],
		[Vector2(238, 40), 12.0], [Vector2(150, 178), 10.0], [Vector2(18, 135), 8.0], [Vector2(212, 22), 8.0]]

## Bruit de "taches" (dallages troués, herbe sombre).
var _patch := FastNoiseLite.new()
## Props posés : [position, rayon] (évitement mutuel des props épars).
var _occupied: Array = []


func _setup() -> void:
	W = R.AGONY_SIZE.x
	H = R.AGONY_SIZE.y
	SEED = 20261011
	MAP_ID = R.AGONY_ID
	MAP_NAME = R.AGONY
	DESCRIPTION = "Les ruines d'une cité antique, à l'ouest de Gludio : une lande sombre où la vieille route pavée serpente entre colonnades brisées, édifices effondrés et le sanctuaire du crâne géant. Au sud-ouest dort l'étang englouti ; la route mène à l'est vers Gludio, à l'ouest vers le lac de Fellmere."
	OUT_PATH = "res://scenes/maps/Ruins_of_Agony.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = false
	BIOME = MapData.Biome.FOREST
	# Sur la route, une douzaine de cases après le téléporteur venu de Gludio.
	PLAYER_SPAWN = Vector2(241.5, 100.5)
	_patch.seed = SEED + 3
	_patch.frequency = 0.16


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Lande : herbe sombre par grandes taches.
	var moor := FastNoiseLite.new()
	moor.seed = SEED + 11
	moor.frequency = 0.022
	for z in H:
		for x in W:
			if moor.get_noise_2d(x, z) > 0.12:
				_terrain[z * W + x] = T.DARK_GRASS

	# Étang englouti, roseaux et roselières sur ses rives.
	_pond(LAKE, LAKE_R)
	for z in H:
		for x in W:
			var i := z * W + x
			var d := _dist("river", Vector2(x + 0.5, z + 0.5))
			if d <= 0.0 or d > 4.5:
				continue
			var n := _patch.get_noise_2d(x * 1.4, z * 1.4)
			if d < 2.2 and n > 0.2:
				_terrain[i] = T.REEDS
			elif d < 2.5 + n * 2.0:
				_terrain[i] = T.TALL_GRASS

	# Bosquets (sol forestier ; arbres plantés après les props).
	for g in GROVES:
		_stamp_blob("grove", g[0], g[1])
	_paint_field("grove", 0.0, T.FOREST, 1.5, [T.WATER, T.REEDS, T.TALL_GRASS])

	# Vieille route, chemins de terre, voie processionnelle.
	_road(ROAD, ROAD_HALF, T.PAVED, 4.0, 0.35)
	for portal in [R.AGONY_PORTAL_E, R.AGONY_PORTAL_W]:
		_paint_disc(portal, 4.2, T.PAVED, [T.WATER])
		_stamp("open", portal, 10.0, 20.0)
	_road([Vector2(WAY_X, WAY_START), Vector2(WAY_X, PLAZA.y + PLAZA_R - 2.0)], WAY_HALF, T.PAVED, 1.5, 0.2)
	# Vers le temple (nord-ouest), la ville basse (sud-est) et l'étang (sud-ouest).
	_road([Vector2(69, 108), Vector2(68, 92), Vector2(66.5, 80), Vector2(TEMPLE.x, TEMPLE.y + TEMPLE_SIZE.y / 2.0 + 1.0)],
			1.3, T.DIRT, 2.0, 0.4)
	_road([Vector2(186, 95), Vector2(187.5, 110), Vector2(188.5, 124), SQUARE], 1.3, T.DIRT, 2.0, 0.4)
	_road([Vector2(84, 108), Vector2(80, 124), Vector2(72, 136), Vector2(64, 144), Vector2(60, 147)], 1.2, T.DIRT, 2.0, 0.4)
	# Chemin de ronde de la ville basse vers l'est (rejoint la route).
	_road([SQUARE, Vector2(212, 140), Vector2(226, 122), Vector2(231, 99)], 1.1, T.DIRT, 1.5, 0.4)

	_edge_band(7, T.THICKET, [T.GRASS, T.DARK_GRASS, T.FOREST])


# ---------------------------------------------------------------------------
# 2. Ruines, props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	var ruins := _add(_props, _node("Ruines"))
	_sanctuary(ruins)
	_city(ruins)
	_temple(ruins)
	_lower_town(ruins)
	_lake_ruins(ruins)
	_aqueduct(ruins)
	_stone_circle(ruins)
	_wilds()
	_place_signs()
	_portal("E", R.AGONY_PORTAL_E, R.GLUDIO_ID, R.GLUDIO_PORTAL_W, R.GLUDIO)
	_portal("O", R.AGONY_PORTAL_W, R.FELLMERE_ID, R.FELLMERE_PORTAL_E, R.FELLMERE)
	_hunting_grounds()


## Monstres des Ruins of Agony de Lineage 2 (niveaux 15-25) : morts-vivants dans la cité
## antique, le temple et la ville basse, bugbears Tumran dans les bois du nord-est, le boss
## Soul Scavenger au sanctuaire du crâne.
func _hunting_grounds() -> void:
	_monster_zone("Agony_VilleBasse", SQUARE, 24.0, M.mix([["Ruin Zombie", 3], ["Ruin Zombie Leader", 1], ["Skeleton Tracker", 2]]), 14)
	_monster_zone("Agony_Lande", Vector2(125, 150), 30.0, M.mix([["Ruin Zombie", 3], ["Skeleton Tracker", 2], ["Skeleton Scout", 1]]), 12)
	_monster_zone("Agony_Cite", Vector2(WAY_X, 64), 26.0, M.mix([["Skeleton Tracker", 2], ["Skeleton Tracker Leader", 1],
			["Skeleton Scout", 2], ["Skeleton Bowman", 2], ["Ruin Spartoi", 2]]), 18)
	_monster_zone("Agony_Sanctuaire", PLAZA, 18.0, M.mix([["Ruin Spartoi", 2], ["Raging Spartoi", 2], ["Skeleton Bowman", 1]]), 10)
	_monster_zone("Agony_Temple", TEMPLE, 24.0, M.mix([["Ruin Zombie Leader", 2], ["Skeleton Scout", 2], ["Raging Spartoi", 1]]), 12)
	_monster_zone("Agony_Lac", LAKE + Vector2(16, -22), 20.0, M.mix([["Ruin Zombie", 2], ["Ruin Zombie Leader", 1]]), 8)
	_monster_zone("Agony_Bugbears", Vector2(226, 40), 20.0, M.mix([["Tumran Bugbear Warrior", 1]]), 7)
	_monster_zone("Agony_SoulScavenger", PLAZA + Vector2(0, -6), 8.0, M.mix([["Soul Scavenger", 1]]), 1, 3600)


## Sanctuaire du crâne : place dallée au bout de la voie processionnelle, crâne géant au
## nord tourné vers la voie, statues et colonnes autour, arches à chaque bout de la voie.
func _sanctuary(parent: Node) -> void:
	var group := _add(parent, _node("Sanctuaire_du_Crane"))
	_ruin_floor_blob(PLAZA, PLAZA_R, 0.45)
	_stamp_blob("ruin", PLAZA, PLAZA_R + 1.0)
	_stamp("open", PLAZA, PLAZA_R + 2.0, PLAZA_R + 10.0)
	var skull := _instance("RuinSkull", group, SKULL, 0.0)
	skull.name = "Crane_Geant"
	_occupy(SKULL, 5.0)
	_checks["Devant le crâne géant"] = SKULL + Vector2(0, 7.5)
	for s in [-1.0, 1.0]:
		var st := PLAZA + Vector2(s * 9.5, -4.0)
		_instance("RuinStatue", group, st, atan2(-s, 0.0)).name = "Statue_%s" % ("Ouest" if s < 0 else "Est")
		_occupy(st, 2.4)
		# Couronne de colonnes autour de la place.
		for deg in [200.0, 230.0, 160.0, 130.0]:
			var a := deg_to_rad(deg if s < 0 else 180.0 - deg)
			var p := PLAZA + Vector2(cos(a), sin(a)) * (PLAZA_R - 1.5)
			_column(group, p, "RuinColumn" if _rng.randf() < 0.55 else "RuinColumnBroken")
	# Colonnes de chaque côté du crâne, un fût tombé au pied de l'une.
	_column(group, SKULL + Vector2(-7.0, 1.0), "RuinColumn")
	_column(group, SKULL + Vector2(7.0, 1.0), "RuinColumnBroken")
	var fallen := SKULL + Vector2(10.5, 4.5)
	_instance("RuinColumnFallen", group, fallen, 0.5)
	_occupy(fallen, 2.6)
	_instance("RuinRubble", group, SKULL + Vector2(-10.5, 3.0), 1.3)
	_occupy(SKULL + Vector2(-10.5, 3.0), 1.8)
	# Voie processionnelle : arches aux deux bouts, colonnades.
	_arch(group, Vector2(WAY_X, PLAZA.y + PLAZA_R + 1.5), Vector2(0, 1), "Arche_Sanctuaire")
	_arch(group, Vector2(WAY_X, WAY_START - 4.0), Vector2(0, 1), "Arche_Voie")
	_colonnade(group, Vector2(WAY_X, PLAZA.y + PLAZA_R + 6.0), Vector2(WAY_X, WAY_START - 9.0), 5.5, 6.0, "Colonnade")
	_stamp_rect("ruin", Rect2(WAY_X - 8.0, PLAZA.y, 16.0, WAY_START - PLAZA.y - 2.0), 4.0)
	_checks["Voie processionnelle"] = Vector2(WAY_X, 72.5)


## Cité antique de part et d'autre de la voie : édifices effondrés, palais, pans de
## l'enceinte, éboulis.
func _city(parent: Node) -> void:
	var group := _add(parent, _node("Cite"))
	_ruin_building(group, Vector2(114.5, 64.5), Vector2(14, 10), Vector2(1, 0), "Edifice_O1")
	_ruin_building(group, Vector2(112.5, 85.5), Vector2(12, 9), Vector2(0, 1), "Edifice_O2")
	_ruin_building(group, Vector2(108.5, 38.5), Vector2(12, 10), Vector2(1, 0), "Edifice_O3")
	_ruin_building(group, Vector2(158.5, 62.5), Vector2(16, 12), Vector2(-1, 0), "Edifice_E1")
	_ruin_building(group, Vector2(160.5, 82.5), Vector2(12, 10), Vector2(0, 1), "Edifice_E2")
	_ruin_building(group, Vector2(172.5, 36.5), Vector2(22, 16), Vector2(-1, 0), "Palais", 0.28)
	_ruin_building(group, Vector2(205.5, 50.5), Vector2(14, 10), Vector2(0, 1), "Edifice_NE1")
	_ruin_building(group, Vector2(226.5, 70.5), Vector2(10, 8), Vector2(-1, 0), "Edifice_NE2")
	# Dans le palais : statue au fond, colonnes.
	_instance("RuinStatue", group, Vector2(177.0, 36.5), atan2(-1.0, 0.0)).name = "Statue_Palais"
	_occupy(Vector2(177.0, 36.5), 2.4)
	for z in [30.5, 42.5]:
		_column(group, Vector2(170.5, z), "RuinColumn" if z < 35 else "RuinColumnBroken")
	# Pans de l'ancienne enceinte, flanqués de tours (colonnes brisées massives).
	var walls := _add(group, _node("Enceinte"))
	for x in [97.0, 188.0]:
		_broken_wall(walls, Vector2(x, 20.0), Vector2(x, 88.0), 0.4, "RuinWall")
		for z in [20.0, 54.0, 88.0]:
			_tower(walls, Vector2(x, z))
		_stamp_rect("ruin", Rect2(x - 1.0, 20.0, 2.0, 68.0), 2.0)
	# Éboulis au pied des ruines.
	for c in [Vector2(124, 47), Vector2(103, 72), Vector2(147, 73), Vector2(190, 66), Vector2(150, 30), Vector2(122, 90),
			Vector2(214, 62), Vector2(99, 46)]:
		_rubble_patch(c, _rng.randf_range(1.6, 2.6))
	for p in [Vector2(126, 57), Vector2(146, 50), Vector2(165, 74), Vector2(103, 30), Vector2(196, 40)]:
		if _spot_free(p, 1.6):
			_instance("RuinRubble", group, p, _rng.randf() * TAU)
			_occupy(p, 1.6)


## Temple en ruine à l'ouest : grande salle à deux rangs de colonnes, autel aux runes
## rouges au fond, statues de part et d'autre de l'entrée.
func _temple(parent: Node) -> void:
	var group := _add(parent, _node("Temple"))
	_ruin_building(group, TEMPLE, TEMPLE_SIZE, Vector2(0, 1), "Temple_en_ruine", 0.22)
	var altar := TEMPLE + Vector2(0, -5.0)
	_instance("RuinAltar", group, altar, 0.0).name = "Autel"
	_occupy(altar, 3.6)
	_checks["Devant l'autel du temple"] = altar + Vector2(0, 5.0)
	for z in [-6.0, -1.0, 4.0]:
		for s in [-1.0, 1.0]:
			if _rng.randf() < 0.8:
				_column(group, TEMPLE + Vector2(s * 8.0, z), "RuinColumn" if _rng.randf() < 0.5 else "RuinColumnBroken")
	var front := TEMPLE.y + TEMPLE_SIZE.y / 2.0
	for s in [-1.0, 1.0]:
		var st := Vector2(TEMPLE.x + s * 6.5, front + 4.0)
		_instance("RuinStatue", group, st, 0.0).name = "Statue_Entree_%s" % ("O" if s < 0 else "E")
		_occupy(st, 2.4)
	var fallen := Vector2(TEMPLE.x + 11.5, front + 6.5)
	_instance("RuinColumnFallen", group, fallen, 0.3)
	_occupy(fallen, 2.6)
	_rubble_patch(TEMPLE + Vector2(-17.5, -6.0), 2.4)
	_rubble_patch(TEMPLE + Vector2(16.5, 8.0), 2.0)


## Ville basse au sud-est de la route : maisons éventrées autour d'une placette.
func _lower_town(parent: Node) -> void:
	var group := _add(parent, _node("Ville_basse"))
	_ruin_floor_blob(SQUARE, 7.0, 0.35)
	_stamp_blob("ruin", SQUARE, 8.0)
	_instance("RuinStatue", group, SQUARE, PI).name = "Statue_Placette"
	_occupy(SQUARE, 2.4)
	_ruin_building(group, Vector2(171.5, 128.5), Vector2(10, 8), Vector2(1, 0), "Maison_1")
	_ruin_building(group, Vector2(205.5, 126.5), Vector2(12, 9), Vector2(-1, 0), "Maison_2")
	_ruin_building(group, Vector2(174.5, 153.5), Vector2(12, 10), Vector2(1, 0), "Maison_3")
	_ruin_building(group, Vector2(204.5, 156.5), Vector2(10, 8), Vector2(-1, 0), "Maison_4")
	_ruin_building(group, Vector2(189.5, 168.5), Vector2(14, 10), Vector2(0, -1), "Maison_5")
	_arch(group, Vector2(187.5, 114.0), Vector2(0.1, 1), "Arche_Ville_basse")
	for c in [Vector2(181, 141), Vector2(197, 146), Vector2(165, 141), Vector2(214, 145)]:
		_rubble_patch(c, _rng.randf_range(1.4, 2.2))
	_checks["Placette de la ville basse"] = SQUARE + Vector2(0, 4.5)


## Étang englouti : colonnes englouties, fût tombé sur la rive.
func _lake_ruins(parent: Node) -> void:
	var group := _add(parent, _node("Lac"))
	# Colonnes à demi englouties : posées sur le fond du lac (lit creusé par TerrainGround).
	for c in [[LAKE + Vector2(-3, -2), "RuinColumnBroken"], [LAKE + Vector2(6, 5), "RuinColumnBroken"],
			[LAKE + Vector2(1.0, -9.0), "RuinColumn"]]:
		var node := _instance(c[1], group, c[0], _rng.randf() * TAU)
		node.position.y = -1.7
		node.rotation.z = _rng.randf_range(-0.12, 0.12)
		_occupy(c[0], 1.0)
	_checks["Rive de l'étang"] = Vector2(62.5, 143.5)


## Aqueduc effondré au sud de la route : file d'arches dont une partie s'est écroulée.
func _aqueduct(parent: Node) -> void:
	var group := _add(parent, _node("Aqueduc"))
	var a := Vector2(98, 129)
	var b := Vector2(160, 139)
	var dir := (b - a).normalized()
	var n := int(a.distance_to(b) / 6.4)
	for i in n + 1:
		var p := a + dir * (i * 6.4)
		_stamp("ruin", p, 3.0, 9.0)
		if i % 4 == 2 or _rng.randf() < 0.18:
			# Arche écroulée : gravats et fût couché.
			if _rng.randf() < 0.6:
				_instance("RuinRubble", group, p, _rng.randf() * TAU)
				_occupy(p, 1.6)
			else:
				_instance("RuinColumnFallen", group, p + Vector2(-dir.y, dir.x) * 2.0, atan2(-dir.y, dir.x) + _rng.randf_range(-0.4, 0.4))
				_occupy(p + Vector2(-dir.y, dir.x) * 2.0, 2.6)
			continue
		var arch := _instance("RuinArch", group, p, atan2(-dir.y, dir.x))
		arch.name = "Arche_%d" % i
		_occupy(p + dir * 2.4, 1.0)
		_occupy(p - dir * 2.4, 1.0)
		if not _checks.has("Sous l'aqueduc"):
			_checks["Sous l'aqueduc"] = p


## Cercle de pierres levées autour d'une dalle, au sud de l'aqueduc.
func _stone_circle(parent: Node) -> void:
	var group := _add(parent, _node("Cercle_de_pierres"))
	var c := Vector2(132.5, 162.5)
	_ruin_floor_blob(c, 5.0, 0.3)
	_stamp_blob("ruin", c, 9.0)
	for k in 9:
		var a := TAU * k / 9.0 + 0.2
		if k == 3:
			continue
		var p := c + Vector2(cos(a), sin(a)) * 8.0
		_column(group, p, "RuinColumn" if k % 3 != 1 else "RuinColumnBroken")
	_instance("RuinRubble", group, c + Vector2(cos(0.2 + TAU * 3 / 9.0), sin(0.2 + TAU * 3 / 9.0)) * 10.5, 0.7)
	_checks["Cercle de pierres"] = c


## Lande : colonnes isolées, pans de murets, éboulis, rochers, troncs et souches.
func _wilds() -> void:
	var group := _add(_props, _node("Lande"))
	var area := Rect2(12, 12, W - 24, H - 24)
	var out_ruins := func(p: Vector2) -> bool: return _dist("ruin", p) > 6.0
	_scatter_props(group, ["RuinColumnBroken", "RuinColumn"], 12, area, 1.0, out_ruins)
	_scatter_props(group, ["RuinWallLow"], 8, area, 2.4, out_ruins)
	_scatter_props(group, ["RuinRubble"], 16, area, 1.7, out_ruins)
	_scatter_props(group, ["RuinColumnFallen"], 5, area, 2.7, out_ruins)
	_scatter_props(group, ["RockLarge", "RockMedium", "RockMedium"], 22, area, 1.3, out_ruins)
	var in_grove := func(p: Vector2) -> bool: return _dist("grove", p) < 3.0
	_scatter_props(group, ["LogFallen", "Stump", "TreeDead"], 14, area, 1.6, in_grove)
	_scatter_props(group, ["CartBroken"], 1, Rect2(150, 100, 60, 10), 2.5)


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	_sign_at(signs, "Teleporteur_E", R.AGONY_PORTAL_E + Vector2(-6.0, -5.5), [[R.GLUDIO, 0.0], [R.FELLMERE, 180.0]])
	_sign_at(signs, "Teleporteur_O", R.AGONY_PORTAL_W + Vector2(6.0, -5.5), [[R.FELLMERE, 180.0], [R.GLUDIO, 0.0]])
	_sign_at(signs, "Voie", Vector2(WAY_X - 6.0, 93.0), [[R.GLUDIO, 0.0], [R.FELLMERE, 180.0], ["Sanctuaire du crâne", 270.0]])
	_sign_at(signs, "Temple", Vector2(64.5, 104.5), [["Temple en ruine", 270.0], [R.GLUDIO, -10.0], [R.FELLMERE, 190.0]])
	_sign_at(signs, "Lac", Vector2(88.5, 112.5), [["Étang englouti", 115.0], [R.GLUDIO, -15.0], [R.FELLMERE, 170.0]])
	_sign_at(signs, "Ville_basse", Vector2(181.0, 99.0), [["Ville basse", 90.0], [R.GLUDIO, 0.0], [R.FELLMERE, 180.0]])


# ---------------------------------------------------------------------------
# Kit de ruines (même jeu d'outils que generate_ruins_of_despair.gd)
# ---------------------------------------------------------------------------

## Édifice en ruine : murs hauts ou arasés sur le pourtour d'un rectangle `size` (largeur
## de façade, profondeur) orienté façade vers `facing`, percés de brèches (part `broken`)
## et d'une porte au milieu de la façade ; dallage troué à l'intérieur, éboulis au pied.
func _ruin_building(parent: Node, center: Vector2, size: Vector2, facing: Vector2, node_name: String, broken := 0.3) -> void:
	var group := _add(parent, _node(node_name))
	var f := facing.normalized()
	var right := Vector2(-f.y, f.x)
	var hw := size.x / 2.0
	var hd := size.y / 2.0
	var corners := [center + f * hd - right * hw, center + f * hd + right * hw,
			center - f * hd + right * hw, center - f * hd - right * hw]
	for k in 4:
		_broken_wall(group, corners[k], corners[(k + 1) % 4], broken, "", k == 0)
	var door := center + f * hd
	_checks["Entrée " + node_name] = door + f * 2.0
	_checks["Intérieur " + node_name] = door - f * 2.5
	_occupy(door + f * 1.5, 2.0)
	_occupy(door - f * 1.5, 2.0)
	_ruin_floor_rect(center, f, size - Vector2(1.2, 1.2), 0.3)
	_stamp_orect("ruin", center, f, size, 4.0)
	_stamp_orect("open", center, f, size + Vector2(4, 4), 6.0)
	_reserve_cells(_rect_cells(center, f, size, 1.5))
	# Un tas de gravats ou un fût brisé dans un coin du fond.
	var back := center - f * (hd - 2.2) + right * (hw - 2.2) * (1.0 if _rng.randf() < 0.5 else -1.0)
	if _rng.randf() < 0.7:
		_instance("RuinRubble" if _rng.randf() < 0.6 else "RuinColumnBroken", group, back, _rng.randf() * TAU)
		_occupy(back, 1.6)


## Pan de mur en ruine de a à b, tronçons de ~4 m hauts ("RuinWall") ou arasés
## ("RuinWallLow") au hasard, une part `broken` effondrée (brèche) ; `door` : tronçon du
## milieu toujours ouvert ; `scene` : impose le modèle des tronçons debout.
func _broken_wall(parent: Node, a: Vector2, b: Vector2, broken: float, scene := "", door := false) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var n := maxi(1, roundi(length / 4.0))
	if door and n % 2 == 0:
		n += 1
	var seg := length / n
	var kinds := []
	for i in n:
		var r := _rng.randf()
		kinds.append(0 if r < broken else (1 if r < broken + (1.0 - broken) * 0.45 else 2))
	if door:
		kinds[n / 2] = 0
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and kinds[j + 1] == kinds[i]:
			j += 1
		if kinds[i] != 0:
			# Les tronçons d'angle débordent d'une demi-épaisseur pour fermer le coin.
			var pa := a + dir * (seg * i - (0.6 if i == 0 else 0.0))
			var pb := a + dir * (seg * (j + 1) + (0.6 if j == n - 1 else 0.0))
			var kind := scene if not scene.is_empty() else ("RuinWall" if kinds[i] == 2 else "RuinWallLow")
			_wall_run(parent, kind, 4.0, pa, pb)
		elif not door or i != n / 2:
			# Brèche : gravats tombés du mur, à côté du passage.
			if _rng.randf() < 0.35:
				var p := a + dir * (seg * (i + 0.5)) + Vector2(-dir.y, dir.x) * _rng.randf_range(-2.4, 2.4)
				if absf((p - a).dot(Vector2(-dir.y, dir.x))) > 1.8 and _spot_free(p, 1.6):
					_instance("RuinRubble", parent, p, _rng.randf() * TAU)
					_occupy(p, 1.6)
		i = j + 1


## Colonnade de part et d'autre de l'axe a -> b, à `offset` m de l'axe, une colonne tous
## les `spacing` m : debout, brisée (parfois son fût couché à côté, hors de l'allée) ou
## disparue.
func _colonnade(parent: Node, a: Vector2, b: Vector2, offset: float, spacing: float, node_name: String) -> void:
	var group := _add(parent, _node(node_name))
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var side := Vector2(-dir.y, dir.x)
	for i in int(length / spacing) + 1:
		for s in [-1.0, 1.0]:
			var p: Vector2 = a + dir * (i * spacing) + side * s * offset
			var r := _rng.randf()
			if r < 0.5:
				_column(group, p, "RuinColumn")
			elif r < 0.88:
				_column(group, p, "RuinColumnBroken")
				if _rng.randf() < 0.5:
					# Fût basculé vers l'extérieur, couché perpendiculairement à l'allée.
					var q: Vector2 = p + side * s * 3.3 + dir * _rng.randf_range(-0.6, 0.6)
					_instance("RuinColumnFallen", group, q, atan2(-side.y, side.x) + _rng.randf_range(-0.3, 0.3))
					_occupy(q, 2.6)


## Arche brisée : passage entre ses deux piliers selon `passage`.
func _arch(parent: Node, pos: Vector2, passage: Vector2, node_name: String) -> void:
	_instance("RuinArch", parent, pos, atan2(passage.x, passage.y)).name = node_name
	var side := Vector2(-passage.y, passage.x).normalized()
	_occupy(pos + side * 2.4, 1.0)
	_occupy(pos - side * 2.4, 1.0)
	_checks["Sous " + node_name] = pos


func _column(parent: Node, p: Vector2, scene: String) -> void:
	_instance(scene, parent, p, _rng.randf() * TAU)
	_occupy(p, 1.0)


## Tour d'enceinte effondrée : grosse colonne brisée, gravats au pied.
func _tower(parent: Node, p: Vector2) -> void:
	var node := _instance("RuinColumnBroken", parent, p, _rng.randf() * TAU)
	node.scale = Vector3.ONE * 1.7
	_occupy(p, 1.6)
	_terrain_under.append([node, T.RAMPART])


## Plaque d'éboulis infranchissable (terrain "rubble"), jamais sur une route ni un dallage.
func _rubble_patch(c: Vector2, radius: float) -> void:
	var tmp := "_tmp_rubble"
	_fields.erase(tmp)
	_stamp_blob(tmp, c, radius)
	var arr: PackedFloat32Array = _fields[tmp]
	for i in W * H:
		if arr[i] > 0.0 or [T.WATER, T.PAVED, T.DIRT, T.BRIDGE].has(_terrain[i]):
			continue
		var p := Vector2(i % W + 0.5, i / W + 0.5)
		if _dist("road", p) < 2.0 or _near_check(p, 2.5) or _reserved.has(Vector2i(i % W, i / W)):
			continue
		_terrain[i] = T.RUBBLE
	_fields.erase(tmp)


## Dallage ancien, troué d'herbe, dans un rectangle orienté.
func _ruin_floor_rect(center: Vector2, facing: Vector2, size: Vector2, holes: float) -> void:
	for c in _rect_cells(center, facing, size, 0.0):
		if _in_map(c) and _terrain[c.y * W + c.x] != T.WATER and _patch.get_noise_2d(c.x, c.y) > holes - 0.6:
			_terrain[c.y * W + c.x] = T.PAVED


## Dallage ancien, troué d'herbe, sur un disque au bord irrégulier.
func _ruin_floor_blob(c: Vector2, radius: float, holes: float) -> void:
	var tmp := "_tmp_floor"
	_fields.erase(tmp)
	_stamp_blob(tmp, c, radius)
	var arr: PackedFloat32Array = _fields[tmp]
	for i in W * H:
		if arr[i] <= 0.0 and _terrain[i] != T.WATER and _patch.get_noise_2d(i % W, i / W) > holes - 0.6 + arr[i] * -0.04:
			_terrain[i] = T.PAVED
	_fields.erase(tmp)


## Rectangle orienté (façade vers `facing`, `size` = largeur de façade, profondeur) dans le
## champ `field_name` : distance au bord, négative dedans.
func _stamp_orect(field_name: String, center: Vector2, facing: Vector2, size: Vector2, reach: float) -> void:
	var arr: PackedFloat32Array = _field(field_name)
	var f := facing.normalized()
	var right := Vector2(-f.y, f.x)
	var h := size / 2.0
	var r := h.length() + reach
	for z in range(maxi(0, floori(center.y - r)), mini(H, ceili(center.y + r) + 1)):
		for x in range(maxi(0, floori(center.x - r)), mini(W, ceili(center.x + r) + 1)):
			var v := Vector2(x + 0.5, z + 0.5) - center
			var dx := absf(v.dot(right)) - h.x
			var dz := absf(v.dot(f)) - h.y
			var d := Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0)
			var i := z * W + x
			if d < arr[i]:
				arr[i] = d
	_fields[field_name] = arr


## Note un prop posé (évitement des props épars) et réserve ses abords (pas d'arbre).
func _occupy(p: Vector2, radius: float) -> void:
	_occupied.append([p, radius])
	_reserve_disc(p, radius + 0.8)


func _near_check(p: Vector2, radius: float) -> bool:
	for c in _checks.values():
		if (c as Vector2).distance_to(p) < radius:
			return true
	return false


## Vrai si un prop de rayon `radius` peut se poser en p : dans la carte (hors lisière), au
## sec, loin des routes, des points vérifiés et des autres props.
func _spot_free(p: Vector2, radius: float) -> bool:
	var cell := Vector2i(int(p.x), int(p.y))
	if not _in_map(cell) or _edge(cell.x, cell.y) < 9:
		return false
	if [T.WATER, T.BRIDGE, T.THICKET, T.REEDS].has(_t_at(p)):
		return false
	if _dist("road", p) < radius + 1.5 or _dist("river", p) < radius + 1.0 or _near_check(p, radius + 2.5):
		return false
	for o in _occupied:
		if p.distance_to(o[0]) < radius + o[1] + 1.5:
			return false
	return true


## Pose `count` props tirés de `scenes` en des points libres de `area` (acceptés par
## `cond`), orientation au hasard ; renvoie le nombre posé.
func _scatter_props(parent: Node, scenes: Array, count: int, area: Rect2, radius: float, cond := Callable()) -> int:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 60:
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
		if _dist("road", p) < 2.5 or _dist("river", p) < 1.5 or _dist("open", p) < 0.0 or _dist("ruin", p) < 4.0:
			return 0.0
		if _near_check(p, 3.0):
			return 0.0
		var grove := _dist("grove", p)
		if grove < 0.0:
			return lerpf(0.18, 0.45, clampf(-grove / 6.0, 0.0, 1.0))
		var edge := float(_edge(x, z))
		return lerpf(0.006, 0.32, clampf(1.0 - (edge - 7.0) / 16.0, 0.0, 1.0)))
	print("Arbres : %d" % trees)


func _configure_ground(ground: TerrainGround) -> void:
	# Lande sombre ; pavés : vieille route moussue (réglage par défaut).
	ground.shader_overrides = {
		"grass_tint": Color(0.58, 0.60, 0.58),
		"dark_grass_tint": Color(0.44, 0.47, 0.44),
		"forest_tint": Color(0.66, 0.64, 0.57),
		"dirt_tint": Color(0.70, 0.63, 0.55),
	}
	ground.water_overrides = {
		"deep_color": Color(0.05, 0.12, 0.14),
		"shallow_color": Color(0.20, 0.30, 0.27),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.grass_density = 0.5
	vegetation.dead_tree_ratio = 0.1
	vegetation.rock_density = 0.02
	vegetation.outer_dead_ratio = 0.08
