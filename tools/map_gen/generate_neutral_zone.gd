extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Neutral_Zone.tscn (300 x 240 cases), la
## Neutral Zone de Lineage 2 : la terre de personne au nord du château de Gludio, entre les
## terres des humains, des elfes et des elfes noirs (niveaux 15-20). Zone sauvage (ni ville
## ni zone de paix) ; un PNJ, Prias, à la halte abandonnée du carrefour ; monstres de
## Lineage 2 (voir _hunting_grounds). Relancer ce script ÉCRASE la scène ; ensuite
## l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Neutral_Zone.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - des collines herbeuses ondulées (herbe claire et sombre par grandes taches), semées
##     de bosquets et d'affleurements rocheux ;
##   - la rivière descend des marais du nord (bord nord, x ≈ 72), coule vers le sud-est et
##     quitte la carte par le bord sud (x ≈ 223) : elle se poursuit sur la carte du château
##     de Gludio, où elle se sépare autour de l'île du château. Les deux téléporteurs du sud
##     sont sur sa rive ouest ; elle se franchit par un pont de pierre (route du nord) et une
##     passerelle de bois (sentier des bois de l'est) ;
##   - deux vieilles routes pavées montent des téléporteurs du bord sud (à l'ouest vers
##     Gludio, au milieu vers le château) et se rejoignent au carrefour ; de là, la route du
##     nord franchit la rivière et sort par le bord nord (vers les terres des elfes et des
##     elfes noirs, sans portail) ;
##   - au nord-ouest du carrefour, la halte abandonnée de Prias (tentes, feu de camp,
##     charrette brisée, caisses, clôture) ;
##   - au nord-ouest, l'autel des rites (cercle de colonnes autour d'un autel ancien, pans de
##     murs) puis la colline de la Roche noire (éboulis sombres, gros rochers, arbres morts),
##     reliés à la route du nord par un chemin de terre ;
##   - au nord-est, au-delà de la rivière, la lisière d'une forêt elfique dense ; au sud-est,
##     les bois de l'est, par la passerelle ;
##   - des poteaux indicateurs près des téléporteurs et aux embranchements.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_neutral_zone.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")
## Prias, voyageur solitaire de la Neutral Zone (backend data/npc).
const PRIAS_ID := "e9a4c850-1a05-4707-ae86-ab630282208e"

const ROAD_HALF := 2.5
const NORTH_HALF := 2.2
const PATH_HALF := 1.3
## Point d'apparition : sur la route, une douzaine de cases au nord du téléporteur du château.
const SPAWN := Vector2(195.5, 222.5)
const CROSS := Vector2(112.5, 170.5)
## Pont de pierre de la route du nord (tablier selon Z : la rivière y coule d'ouest en est).
const BRIDGE_N := Vector2(140.5, 82.5)
## Passerelle de bois vers les bois de l'est (tablier selon X : rivière nord-sud).
const BRIDGE_E := Vector2(206.5, 152.5)
## Halte abandonnée (Prias), autel des rites, colline de la Roche noire.
const CAMP := Vector2(96.5, 156.5)
const ALTAR := Vector2(50.5, 110.5)
const BLACK_ROCK := Vector2(44.0, 48.0)
const BLACK_ROCK_FOOT := Vector2(50.5, 76.5)
const EAST_GLADE := Vector2(247.5, 139.5)

const ROAD_GLUDIO := [Vector2(30.5, 252), R.NEUTRAL_PORTAL_SW, Vector2(30.5, 222), Vector2(37, 206),
		Vector2(53, 192), Vector2(75, 182), Vector2(96, 175.5), CROSS]
const ROAD_CASTLE := [Vector2(195.5, 252), R.NEUTRAL_PORTAL_S, SPAWN, Vector2(194, 208), Vector2(184, 196),
		Vector2(166, 186), Vector2(146, 179), Vector2(128, 174), CROSS]
const ROAD_NORTH := [CROSS, Vector2(113, 155), Vector2(117, 136), Vector2(124, 118), Vector2(133, 104),
		Vector2(140.5, 94), BRIDGE_N, Vector2(140.5, 71), Vector2(146, 56), Vector2(153, 38), Vector2(158, 20),
		Vector2(161, 2), Vector2(162, -12)]
## Chemin de l'autel puis de la Roche noire (embranché sur la route du nord).
const PATH_ALTAR := [Vector2(117, 136), Vector2(100, 130), Vector2(82, 121), Vector2(69, 112), ALTAR + Vector2(11, 0)]
const PATH_ROCK := [ALTAR + Vector2(-2, -10), Vector2(48, 92), BLACK_ROCK_FOOT]
## Sentier des bois de l'est (embranché sur la route du château), par la passerelle.
const PATH_EAST := [Vector2(184, 196), Vector2(190, 180), Vector2(196, 165), Vector2(198.5, 152.5), BRIDGE_E,
		Vector2(214.5, 152.5), Vector2(229, 146), EAST_GLADE]
## Chemin de la halte, depuis le carrefour.
const PATH_CAMP := [CROSS + Vector2(-1, -2), Vector2(104, 163), CAMP + Vector2(3, 3)]
## Rivière : du bord nord au bord sud, droite au droit des deux ponts.
const RIVER := [Vector2(72, -12), Vector2(76, 14), Vector2(88, 40), Vector2(104, 62), Vector2(118, 80),
		Vector2(126, 82.5), BRIDGE_N, Vector2(155, 82.5), Vector2(163, 85), Vector2(178, 97), Vector2(192, 116),
		Vector2(202, 133), Vector2(206.5, 143), BRIDGE_E, Vector2(206.5, 161), Vector2(211, 177),
		Vector2(218, 199), Vector2(222, 220), Vector2(223, 252)]

## Bosquets : [centre, rayon].
const GROVES := [[Vector2(62, 212), 15.0], [Vector2(18, 178), 11.0], [Vector2(24, 132), 13.0],
		[Vector2(150, 213), 10.0], [Vector2(112, 28), 13.0], [Vector2(252, 198), 22.0], [Vector2(272, 150), 17.0],
		[Vector2(176, 136), 7.0], [Vector2(70, 145), 8.0], [Vector2(128, 140), 6.0], [Vector2(190, 58), 8.0]]
## Forêt elfique dense du nord-est : [centre, rayon].
const ELVEN := [[Vector2(245, 40), 44.0], [Vector2(284, 96), 22.0], [Vector2(205, 18), 20.0]]
## Affleurements rocheux des collines : [centre, rayon].
const OUTCROPS := [[Vector2(160, 150), 3.0], [Vector2(48, 168), 2.6], [Vector2(85, 98), 2.8],
		[Vector2(232, 105), 2.6], [Vector2(130, 205), 2.4], [Vector2(176, 160), 2.2], [Vector2(20, 98), 2.6]]

## Bruits : taches d'herbe sombre, éboulis de la Roche noire, berges.
var _patch := FastNoiseLite.new()
var _rock_noise := FastNoiseLite.new()
## Props posés : [position, rayon] (évitement mutuel des props épars).
var _occupied: Array = []


func _setup() -> void:
	W = R.NEUTRAL_SIZE.x
	H = R.NEUTRAL_SIZE.y
	SEED = 20261020
	MAP_ID = R.NEUTRAL_ID
	MAP_NAME = R.NEUTRAL
	DESCRIPTION = "La Neutral Zone, terre de personne au nord du château de Gludio : des collines herbeuses que traverse la rivière descendue des marais, de vieilles routes qui se croisent près d'une halte abandonnée. Au nord-ouest se dressent l'autel des rites et la Roche noire ; au nord-est commence la forêt des elfes."
	OUT_PATH = "res://scenes/maps/Neutral_Zone.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = false
	IS_STARTING_MAP = false
	BIOME = MapData.Biome.FOREST
	PLAYER_SPAWN = SPAWN
	_patch.seed = SEED + 3
	_patch.frequency = 0.16
	_rock_noise.seed = SEED + 7
	_rock_noise.frequency = 0.12


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Collines : herbe sombre par grandes taches (versants à l'ombre).
	var hills := FastNoiseLite.new()
	hills.seed = SEED + 11
	hills.frequency = 0.018
	for z in H:
		for x in W:
			if hills.get_noise_2d(x, z) > 0.18:
				_terrain[z * W + x] = T.DARK_GRASS

	# Bosquets et forêt elfique (sol forestier ; arbres plantés après les props).
	for g in GROVES:
		_stamp_blob("grove", g[0], g[1])
	for e in ELVEN:
		_stamp_blob("elven", e[0], e[1])
	_paint_field("grove", 0.0, T.FOREST, 1.5)
	_paint_field("elven", 2.0, T.FOREST, 2.0)

	# Roche noire : sol sombre et pierreux (éboulis posés plus bas).
	_stamp_blob("rocks", BLACK_ROCK, 27.0)
	for z in H:
		for x in W:
			var d := _dist("rocks", Vector2(x + 0.5, z + 0.5))
			if d < 3.0:
				_terrain[z * W + x] = T.FOREST if _rock_noise.get_noise_2d(x, z) < -0.1 else T.DARK_GRASS

	# Ponts d'abord : la rivière s'y resserre.
	_bridge(BRIDGE_N, "z", true, "Pont_du_Nord")
	_bridge(BRIDGE_E, "x", false, "Passerelle_Est")
	_river(RIVER, 4.2, 0.9)

	# Routes pavées, chemins de terre, clairières.
	_road(ROAD_GLUDIO, ROAD_HALF, T.PAVED, 4.0, 0.35)
	_road(ROAD_CASTLE, ROAD_HALF, T.PAVED, 4.0, 0.35)
	_road(ROAD_NORTH, NORTH_HALF, T.PAVED, 3.5, 0.35)
	_road(PATH_ALTAR, PATH_HALF, T.DIRT, 2.0, 0.4)
	_road(PATH_ROCK, PATH_HALF, T.DIRT, 2.0, 0.4)
	_road(PATH_EAST, PATH_HALF, T.DIRT, 2.0, 0.4)
	_road(PATH_CAMP, 1.2, T.DIRT, 1.5, 0.3)
	_worn_paving()
	for portal in [R.NEUTRAL_PORTAL_SW, R.NEUTRAL_PORTAL_S]:
		_paint_disc(portal, 4.2, T.PAVED, [T.WATER])
		_stamp("open", portal, 10.0, 20.0)
	_paint_disc(CROSS, 4.5, T.PAVED, [T.WATER])
	_stamp("open", CROSS, 8.0, 16.0)
	_paint_disc(EAST_GLADE, 4.0, T.DIRT, [T.WATER])
	_stamp("open", EAST_GLADE, 6.0, 14.0)
	_paint_disc(BLACK_ROCK_FOOT, 4.5, T.DIRT, [T.WATER])
	_stamp("open", BLACK_ROCK_FOOT, 6.0, 14.0)
	# Halte : terre battue piétinée.
	_dirt_blob(CAMP + Vector2(0, -2), 11.0)
	_stamp("open", CAMP, 11.0, 20.0)
	_stamp("camp", CAMP, 0.0, 30.0)

	_paint_banks()
	_paint_black_rock()
	for o in OUTCROPS:
		_rubble_patch(o[0], o[1])
	_edge_band(7, T.THICKET, [T.GRASS, T.DARK_GRASS, T.FOREST])


## Dalles disjointes : l'herbe reprend par endroits sur les vieilles routes (jamais au
## droit des téléporteurs, du carrefour ni des ponts).
func _worn_paving() -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			if _terrain[i] != T.PAVED:
				continue
			var p := Vector2(x + 0.5, z + 0.5)
			if p.distance_to(CROSS) < 8.0 or _near_bridge(p, 3.0):
				continue
			if p.distance_to(R.NEUTRAL_PORTAL_SW) < 7.0 or p.distance_to(R.NEUTRAL_PORTAL_S) < 7.0:
				continue
			var n := _patch.get_noise_2d(x * 2.2, z * 2.2)
			if n < -0.42:
				_terrain[i] = T.GRASS
			elif n < -0.3:
				_terrain[i] = T.DIRT


## Berges : roseaux épars (praticables), quelques roselières (bloquantes) à l'écart des
## routes et des ponts.
func _paint_banks() -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			if not [T.GRASS, T.DARK_GRASS, T.FOREST].has(_terrain[i]):
				continue
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("river", p)
			if d <= 0.0 or d > 4.0 or _dist("road", p) < 3.0 or _near_bridge(p, 4.0):
				continue
			var n := _patch.get_noise_2d(x * 1.4, z * 1.4)
			if d < 1.8 and n > 0.32:
				_terrain[i] = T.REEDS
			elif d < 2.0 + n * 2.5:
				_terrain[i] = T.TALL_GRASS


## Colline de la Roche noire : éboulis sombres infranchissables, de plus en plus serrés vers
## le sommet (au nord-ouest), jamais sur le chemin ni à son pied.
func _paint_black_rock() -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("rocks", p)
			if d > -1.0 or not [T.GRASS, T.DARK_GRASS, T.FOREST].has(_terrain[i]):
				continue
			if _dist("road", p) < 3.0 or p.distance_to(BLACK_ROCK_FOOT) < 9.0:
				continue
			var core := clampf(-d / 22.0, 0.0, 1.0)
			if _rock_noise.get_noise_2d(x * 1.5, z * 1.5) > 0.3 - 0.45 * core:
				_terrain[i] = T.RUBBLE


func _dirt_blob(c: Vector2, radius: float) -> void:
	var tmp := "_tmp_dirt"
	_fields.erase(tmp)
	_stamp_blob(tmp, c, radius)
	var arr: PackedFloat32Array = _fields[tmp]
	for i in W * H:
		if arr[i] <= 0.0 and _terrain[i] != T.WATER and _terrain[i] != T.PAVED:
			_terrain[i] = T.DIRT if arr[i] < -1.5 or _patch.get_noise_2d(i % W, i / W) > -0.1 else T.GRASS
	_fields.erase(tmp)


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	_waystation()
	_altar_of_rites()
	_black_rock()
	_wilds()
	_place_signs()
	_portal("SO", R.NEUTRAL_PORTAL_SW, R.GLUDIO_ID, R.GLUDIO_PORTAL_NW, R.GLUDIO)
	_portal("S", R.NEUTRAL_PORTAL_S, R.CASTLE_ID, R.CASTLE_PORTAL_N, R.CASTLE)
	_checks["Carrefour"] = CROSS
	_checks["Au-delà du pont du nord"] = BRIDGE_N + Vector2(0, -12)
	_checks["Route du nord (bord)"] = Vector2(161.5, 9.5)
	_checks["Clairière des bois de l'est"] = EAST_GLADE
	_checks["Pied de la Roche noire"] = BLACK_ROCK_FOOT
	_checks["Forêt elfique"] = Vector2(214.5, 70.5)
	_hunting_grounds()


## Monstres de la Neutral Zone de Lineage 2 (niveaux 15-20) : araignées charognardes dans
## les bois du sud, bêtes de pierre de lune sur les collines dégagées, hommes-rats le long
## des berges, araignées pisteuses dans la forêt elfique et les bois de l'est, lycanthropes
## au nord, autour de l'autel des rites et de la Roche noire. Les plus faibles près des
## téléporteurs du sud.
func _hunting_grounds() -> void:
	_monster_zone("Neutre_BoisSud", Vector2(62, 208), 20.0, M.mix([["Scavenger Spider", 1]]), 10)
	_monster_zone("Neutre_CollinesOuest", Vector2(38, 158), 22.0, M.mix([["Moonstone Beast", 2], ["Scavenger Spider", 1]]), 10)
	_monster_zone("Neutre_CollinesCentre", Vector2(166, 140), 20.0, M.mix([["Moonstone Beast", 3], ["Scavenger Wererat", 1]]), 10)
	_monster_zone("Neutre_BergesCentre", Vector2(176, 104), 18.0, M.mix([["Scavenger Wererat", 1]]), 9)
	_monster_zone("Neutre_BergesSud", Vector2(214, 178), 16.0, M.mix([["Scavenger Wererat", 2], ["Scavenger Spider", 1]]), 7)
	_monster_zone("Neutre_BoisEst", Vector2(256, 172), 26.0, M.mix([["Scavenger Spider", 2], ["Arachnid Tracker", 2]]), 11)
	_monster_zone("Neutre_ForetElfique", Vector2(226, 58), 30.0, M.mix([["Arachnid Tracker", 3], ["Lycanthrope", 1]]), 12)
	_monster_zone("Neutre_Autel", ALTAR, 22.0, M.mix([["Lycanthrope", 3], ["Arachnid Tracker", 1]]), 10)
	_monster_zone("Neutre_RocheNoire", BLACK_ROCK + Vector2(4, 8), 24.0, M.mix([["Lycanthrope", 2], ["Moonstone Beast", 1]]), 9)
	_monster_zone("Neutre_Nord", Vector2(114, 30), 18.0, M.mix([["Lycanthrope", 2], ["Arachnid Tracker", 1]]), 7)


## Halte abandonnée de Prias, au nord-ouest du carrefour : feu de camp entre deux tentes,
## charrette brisée et sa cargaison, tas de bois, râtelier, clôture côté ouest.
func _waystation() -> void:
	var group := _add(_props, _node("Halte_de_Prias"))
	_prop(group, "Campfire", CAMP, 0.0, 1.4).name = "Feu_de_camp"
	_prop(group, "Tent", CAMP + Vector2(-6.0, -4.0), atan2(0.8, 0.6), 2.6).name = "Tente_Ouest"
	_prop(group, "TentLarge", CAMP + Vector2(2.5, -9.0), 0.0, 4.4).name = "Tente_Nord"
	_prop(group, "CartBroken", CAMP + Vector2(7.0, -1.5), 1.9, 2.0)
	_prop(group, "Crate", CAMP + Vector2(6.5, 2.5), 0.3, 0.9)
	_prop(group, "Crate", CAMP + Vector2(7.6, 3.3), 1.1, 0.9)
	_prop(group, "Barrel", CAMP + Vector2(5.0, 3.9), 0.0, 0.7)
	_prop(group, "LogPile", CAMP + Vector2(-5.0, 6.0), 0.4, 1.6)
	_prop(group, "LogFallen", CAMP + Vector2(-0.5, 3.4), 0.15, 1.2)
	_prop(group, "WeaponRack", CAMP + Vector2(-8.0, 1.5), PI / 2.0, 1.2)
	# Clôture de piquets à l'ouest et au nord-ouest de la halte.
	var fence := _add(group, _node("Cloture"))
	for seg in [[CAMP + Vector2(-10.5, 7.0), CAMP + Vector2(-10.5, -7.0)], [CAMP + Vector2(-10.5, -7.0), CAMP + Vector2(-4.5, -13.0)]]:
		_fence_run(fence, seg[0], seg[1])
	_npc("Prias", PRIAS_ID, CAMP + Vector2(2.5, 1.0))
	_reserve_disc(CAMP + Vector2(2.5, 1.0), 1.5)
	_checks["Halte (entrée)"] = CAMP + Vector2(3.0, 4.5)


## Autel des rites : dallage ancien troué d'herbe, autel au centre, cercle de colonnes
## (debout, brisées, une tombée), deux statues et des pans de mur arasés.
func _altar_of_rites() -> void:
	var group := _add(_props, _node("Autel_des_Rites"))
	_ruin_floor_blob(ALTAR, 8.0, 0.4)
	_stamp_blob("ruin", ALTAR, 11.0)
	_stamp("open", ALTAR, 12.0, 20.0)
	_instance("RuinAltar", group, ALTAR, PI / 2.0).name = "Autel"
	_occupy(ALTAR, 3.6)
	_checks["Devant l'autel des rites"] = ALTAR + Vector2(5.5, 0)
	for k in 10:
		var a := TAU * k / 10.0 + 0.15
		var p := ALTAR + Vector2(cos(a), sin(a)) * 10.0
		# Ouverture du cercle à l'est (arrivée du chemin) et au nord (vers la Roche noire).
		if absf(wrapf(a, -PI, PI)) < 0.35 or absf(wrapf(a + PI / 2.0, -PI, PI)) < 0.35:
			continue
		if k == 6:
			var q := p + Vector2(cos(a), sin(a)) * 2.6
			_instance("RuinColumnFallen", group, q, -a + PI / 2.0)
			_occupy(q, 2.6)
			continue
		_column(group, p, "RuinColumn" if k % 3 != 1 else "RuinColumnBroken")
	for s in [-1.0, 1.0]:
		var st := ALTAR + Vector2(14.0, s * 5.5)
		_instance("RuinStatue", group, st, atan2(1.0, 0.0)).name = "Statue_%s" % ("Nord" if s < 0 else "Sud")
		_occupy(st, 2.4)
	var walls := _add(group, _node("Murs"))
	for seg in [[ALTAR + Vector2(-16, -6), ALTAR + Vector2(-16, 8)], [ALTAR + Vector2(-8, 16), ALTAR + Vector2(6, 16)]]:
		_wall_run(walls, "RuinWallLow", 4.0, seg[0], seg[1])
		_stamp_rect("ruin", Rect2(seg[0] - Vector2(1, 1), seg[1] - seg[0] + Vector2(2, 2)), 2.0)
	_wall_run(walls, "RuinWall", 4.0, ALTAR + Vector2(-16, -14), ALTAR + Vector2(-10, -18))
	_instance("RuinRubble", group, ALTAR + Vector2(-12.5, -12.0), 0.8)
	_occupy(ALTAR + Vector2(-12.5, -12.0), 1.6)
	for p in [ALTAR + Vector2(-20, 2), ALTAR + Vector2(9, 21), ALTAR + Vector2(-4, -22)]:
		_column(group, p, "RuinColumnBroken")


## Roche noire : gros rochers sombres sur la colline, arbres morts, souches.
func _black_rock() -> void:
	var group := _add(_props, _node("Roche_Noire"))
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 2000:
		tries += 1
		var p := BLACK_ROCK + Vector2(_rng.randf_range(-26, 26), _rng.randf_range(-24, 26))
		if _dist("rocks", p) > -2.0 or _t_at(p) == T.RUBBLE or not _spot_free(p, 1.8):
			continue
		var big := _rng.randf() < 0.6
		var node := _instance("RockLarge" if big else "RockMedium", group, p, _rng.randf() * TAU)
		node.scale = Vector3.ONE * (_rng.randf_range(1.3, 2.1) if big else _rng.randf_range(1.0, 1.5))
		_occupy(p, 2.6 if big else 1.6)
		placed += 1
	var in_rock := func(p: Vector2) -> bool: return _dist("rocks", p) < 2.0
	_scatter_props(group, ["TreeDead", "TreeDead", "Stump"], 10, Rect2(BLACK_ROCK - Vector2(30, 30), Vector2(60, 62)), 1.4, in_rock)
	_checks["Sur la Roche noire"] = BLACK_ROCK_FOOT + Vector2(0, -6)


## Collines : affleurements rocheux, troncs, souches, une charrette abandonnée au bord de la
## route.
func _wilds() -> void:
	var group := _add(_props, _node("Collines"))
	var area := Rect2(12, 12, W - 24, H - 24)
	var open_land := func(p: Vector2) -> bool:
		return _dist("ruin", p) > 6.0 and _dist("rocks", p) > 4.0 and _dist("camp", p) > 14.0
	for o in OUTCROPS:
		for k in 3:
			var p: Vector2 = o[0] + Vector2.from_angle(_rng.randf() * TAU) * (o[1] + _rng.randf_range(1.5, 3.5))
			if _spot_free(p, 1.6):
				var node := _instance("RockLarge" if k == 0 else "RockMedium", group, p, _rng.randf() * TAU)
				node.scale = Vector3.ONE * _rng.randf_range(1.0, 1.5)
				_occupy(p, 2.0)
	_scatter_props(group, ["RockLarge", "RockMedium", "RockMedium"], 30, area, 1.4, open_land)
	var in_wood := func(p: Vector2) -> bool: return (_dist("grove", p) < 3.0 or _dist("elven", p) < 3.0) and open_land.call(p)
	_scatter_props(group, ["LogFallen", "Stump", "Stump"], 22, area, 1.6, in_wood)
	_scatter_props(group, ["CartBroken"], 1, Rect2(60, 176, 30, 12), 2.5)
	_scatter_props(group, ["RuinColumnBroken", "RuinWallLow"], 4, Rect2(20, 60, 100, 60), 2.0, open_land)


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	var north := 270.0
	_sign_at(signs, "Teleporteur_Gludio", R.NEUTRAL_PORTAL_SW + Vector2(6.5, -6.0),
			[[R.GLUDIO, 90.0], [R.CASTLE, -20.0], ["Elven Village", 290.0]])
	_sign_at(signs, "Teleporteur_Chateau", R.NEUTRAL_PORTAL_S + Vector2(-6.5, -6.0),
			[[R.CASTLE, 90.0], [R.GLUDIO, 200.0], ["Elven Village", 255.0]])
	_sign_at(signs, "Carrefour", CROSS + Vector2(6.5, -6.0),
			[[R.GLUDIO, _heading(CROSS, Vector2(96, 175.5))], [R.CASTLE, _heading(CROSS, Vector2(128, 174))],
			["Elven Village", north + 8.0], ["Dark Elf Village", north - 8.0]])
	_sign_at(signs, "Autel", Vector2(122.5, 139.0),
			[["Altar of Rites", 195.0], ["Black Rock Hill", 215.0], ["Elven Village", 290.0], [R.GLUDIO, 100.0]])
	_sign_at(signs, "Pont_du_Nord", BRIDGE_N + Vector2(6.0, 13.0),
			[["Elven Village", 280.0], ["Dark Elf Village", 260.0], [R.CASTLE, 110.0]])
	_sign_at(signs, "Bois_Est", Vector2(178.0, 199.5),
			[["Bois de l'est", 300.0], [R.CASTLE, 70.0], [R.GLUDIO, 190.0]])
	_sign_at(signs, "Roche_Noire", ALTAR + Vector2(4.5, -12.0),
			[["Black Rock Hill", 260.0], ["Altar of Rites", 110.0]])


# ---------------------------------------------------------------------------
# Kit (props épars, ruines ; même jeu d'outils que generate_ruins_of_agony.gd)
# ---------------------------------------------------------------------------

## Prop de la halte : abords réservés (rien ne pousse dessous, même pour les modèles pas
## encore construits).
func _prop(parent: Node, scene: String, pos: Vector2, yaw: float, radius: float) -> Node3D:
	var node := _instance(scene, parent, pos, yaw)
	_occupy(pos, radius)
	return node


## Clôture de a à b (tronçons de 2,1 m).
func _fence_run(parent: Node, a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var count := maxi(1, roundi(length / 2.1))
	for i in count:
		var p := a + dir * (length / count) * (i + 0.5)
		_instance("Fence", parent, p, atan2(-dir.y, dir.x))
		_reserve_disc(p, 1.4)


func _column(parent: Node, p: Vector2, scene: String) -> void:
	_instance(scene, parent, p, _rng.randf() * TAU)
	_occupy(p, 1.0)


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
		if _dist("road", p) < 3.0 or _dist("river", p) < 2.0 or _reserved.has(Vector2i(i % W, i / W)):
			continue
		_terrain[i] = T.RUBBLE
	_fields.erase(tmp)
	_occupied.append([c, radius + 0.5])


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
	if [T.WATER, T.BRIDGE, T.THICKET, T.REEDS, T.RUBBLE].has(_t_at(p)):
		return false
	if _dist("road", p) < radius + 1.5 or _dist("river", p) < radius + 1.0 or _near_check(p, radius + 2.5):
		return false
	for portal in [R.NEUTRAL_PORTAL_SW, R.NEUTRAL_PORTAL_S, SPAWN]:
		if p.distance_to(portal) < 10.0:
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
		if _near_check(p, 3.0) or _dist("rocks", p) < 3.0 or _near_bridge(p, 3.0):
			return 0.0
		var elven := _dist("elven", p)
		if elven < 0.0:
			return lerpf(0.2, 0.42, clampf(-elven / 10.0, 0.0, 1.0))
		var grove := _dist("grove", p)
		if grove < 0.0:
			return lerpf(0.16, 0.42, clampf(-grove / 6.0, 0.0, 1.0))
		if elven < 6.0 or grove < 3.0:
			return 0.06
		var edge := float(_edge(x, z))
		return lerpf(0.004, 0.3, clampf(1.0 - (edge - 7.0) / 16.0, 0.0, 1.0)))
	# Arbres morts sur la Roche noire.
	var dead_prob := func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)) or _dist("road", p) < 3.0 or _near_check(p, 3.0):
			return 0.0
		return 0.06 if _dist("rocks", p) < 0.0 else 0.0
	var dead := _scatter(T.DEAD_TREE, [T.GRASS, T.DARK_GRASS, T.FOREST], dead_prob, 2)
	print("Arbres : %d (morts : %d)" % [trees, dead])


func _configure_ground(ground: TerrainGround) -> void:
	# Collines verdoyantes ; vieilles routes de dalles grises.
	ground.paved_asset = "PavingStones151"
	ground.paved_tile = Vector2(3.2, 3.2)
	ground.paved_desaturate = 0.5
	ground.paved_tint = Color(0.68, 0.67, 0.64)
	ground.shader_overrides = {
		"grass_tint": Color(0.72, 0.78, 0.62),
		"dark_grass_tint": Color(0.52, 0.6, 0.46),
		"forest_tint": Color(0.62, 0.6, 0.52),
		"dirt_tint": Color(0.72, 0.64, 0.54),
	}
	ground.water_overrides = {
		"deep_color": Color(0.05, 0.13, 0.15),
		"shallow_color": Color(0.22, 0.34, 0.30),
		"flow": Vector2(0.15, 0.4),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.foliage_tint = Color(0.95, 1.0, 0.88)
	vegetation.grass_density = 0.55
	vegetation.forest_grass_density = 0.2
	vegetation.bush_density = 0.03
	vegetation.rock_density = 0.018
	vegetation.dead_tree_ratio = 0.04
	vegetation.outer_density = 0.45
	vegetation.outer_dead_ratio = 0.05
