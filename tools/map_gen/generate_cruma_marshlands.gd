extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Cruma_Marshlands.tscn (300 x 240 cases), les
## marais de Cruma de Lineage 2, à l'est de Gludio — sans la tour de Cruma ni PNJ ;
## monstres de Lineage 2 sur les zones de chasse (voir _hunting_grounds). Relancer ce script ÉCRASE la scène ; ensuite
## l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Cruma_Marshlands.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - un grand marais lugubre : mares et étangs au bord irrégulier, chenaux étroits et
##     sinueux, eau croupie vert-brun ; roselières infranchissables et franges de roseaux
##     autour de l'eau, herbe sombre détrempée, plaques de boue, arbres morts partout (cases
##     "deadTree" et arbres tordus du marais MarshTree / MarshTreeSmall), quelques bosquets
##     malingres ;
##   - trois chenaux découpent le marais : le chenal ouest (du bord nord jusqu'à l'étang
##     central), le chenal sud (de l'étang central jusqu'au bord est) et le chenal des
##     rochers (du bord nord jusqu'à une mare) ; ils se franchissent sur des pontons de bois ;
##   - une vieille chaussée de terre serpente du téléporteur de l'ouest (Town of Gludio) au
##     téléporteur du sud (Town of Dion), par deux pontons ; à la fourche, un sentier part
##     vers le nord-est : il mène, par un troisième ponton, au pied d'une avancée rocheuse
##     sombre (éboulis, gros rochers, deux colonnes brisées) qui regarde vers la tour de
##     Cruma, hors carte ; une branche du sentier rejoint, par un quatrième ponton, l'îlot des
##     ruines (colonnes brisées, pans de mur, éboulis : vestiges de l'ancienne Cruma), cerné
##     d'un chenal en anneau qui s'ouvre au nord sur un étang ;
##   - une lisière de roselières, de fourrés et d'arbres morts le long des bords (éboulis au
##     nord-est), interrompue là où la chaussée et les chenaux sortent de la carte.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_cruma_marshlands.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")

## Point d'apparition : sur la chaussée, une douzaine de cases à l'est du téléporteur ouest.
const SPAWN := Vector2(18.5, 120.5)
## Pontons (BridgeWood) : chenal ouest (tablier selon X), chenal sud (selon Z), chenal des
## rochers (selon X), anneau de l'îlot (selon Z).
const BRIDGE_W := Vector2(95.0, 108.5)
const BRIDGE_S := Vector2(176.5, 166.0)
const BRIDGE_ROCKS := Vector2(212.0, 72.5)
const BRIDGE_ISLET := Vector2(150.5, 76.0)
const FORK := Vector2(130.0, 121.0)
const ISLET := Vector2(150.5, 62.0)
const ROCKS := Vector2(258.0, 42.0)
## Vieille route pavée des rochers vers l'angle nord-est (vers la tour de Cruma).
const OLD_ROAD := [Vector2(258, 42), Vector2(268, 32), Vector2(279, 21)]
const ROAD_HALF := 2.0
const PATH_HALF := 1.4

## Chaussée : téléporteur ouest -> ponton ouest -> fourche -> ponton sud -> téléporteur sud
## (prolongée au-delà des bords : la route sort de la carte).
const CAUSEWAY := [Vector2(-8, 120.5), R.CRUMA_PORTAL_W, SPAWN, Vector2(34, 118), Vector2(52, 111),
		Vector2(70, 108.5), Vector2(82, 108.5), BRIDGE_W, Vector2(108, 108.5), Vector2(120, 114), FORK,
		Vector2(148, 132), Vector2(164, 142), Vector2(176.5, 152), BRIDGE_S, Vector2(176.5, 179),
		Vector2(186, 196), Vector2(198, 212), Vector2(200.5, 224), R.CRUMA_PORTAL_S, Vector2(200.5, 248)]
## Sentier de la fourche vers les rochers du nord-est.
const PATH_ROCKS := [FORK, Vector2(142, 112), Vector2(158, 104), Vector2(175, 92), Vector2(190, 80),
		Vector2(199, 72.5), BRIDGE_ROCKS, Vector2(225, 72.5), Vector2(238, 64), Vector2(249, 52), ROCKS]
## Branche vers l'îlot des ruines.
const PATH_ISLET := [Vector2(158, 104), Vector2(152, 96), Vector2(150.5, 86), BRIDGE_ISLET, ISLET]

## Chenaux : [points, demi-largeur, variation]. Tronçons droits de ±10 m au droit des pontons.
const CHANNELS := [
	# Chenal ouest : du bord nord à l'étang central.
	[[Vector2(92, -10), Vector2(97, 18), Vector2(89, 48), Vector2(93, 78), Vector2(95, 96), BRIDGE_W,
			Vector2(95, 121), Vector2(99, 138), Vector2(104, 150)], 2.4, 0.8],
	# Chenal sud : de l'étang central au bord est.
	[[Vector2(116, 162), Vector2(136, 168), Vector2(163, 166), BRIDGE_S, Vector2(190, 166),
			Vector2(212, 160), Vector2(236, 168), Vector2(262, 162), Vector2(285, 167), Vector2(312, 165)], 2.6, 0.8],
	# Chenal des rochers : du bord nord à une mare.
	[[Vector2(206, -10), Vector2(209, 20), Vector2(203, 42), Vector2(212, 60), BRIDGE_ROCKS,
			Vector2(212, 85), Vector2(220, 104), Vector2(232, 122)], 2.2, 0.7],
	# Petits chenaux qui relient des mares.
	[[Vector2(95, 170), Vector2(86, 183), Vector2(72, 192), Vector2(60, 196)], 1.8, 0.6],
	[[Vector2(32, -10), Vector2(35, 14), Vector2(46, 32), Vector2(57, 42)], 1.8, 0.6],
	[[Vector2(238, 168), Vector2(244, 185), Vector2(250, 203)], 1.8, 0.6],
]
## Chenal en anneau autour de l'îlot des ruines (octogone, côté sud droit pour le ponton).
const ISLET_RING := [Vector2(140, 48), Vector2(161, 48), Vector2(166, 53), Vector2(166, 71), Vector2(161, 76),
		Vector2(140, 76), Vector2(135, 71), Vector2(135, 53)]
## Étangs posés à la main : [centre, rayon].
const PONDS := [[Vector2(105, 160), 15.0], [Vector2(150, 33), 12.0], [Vector2(235, 130), 10.0],
		[Vector2(58, 196), 8.0], [Vector2(60, 46), 9.0], [Vector2(252, 212), 9.0]]
## Bosquets malingres : [centre, rayon].
const GROVES := [[Vector2(32, 74), 11.0], [Vector2(125, 215), 10.0], [Vector2(275, 105), 10.0],
		[Vector2(180, 28), 8.0]]
## Terrains praticables "naturels" du marais.
const LAND := [T.DARK_GRASS, T.GRASS, T.DIRT, T.TALL_GRASS, T.FOREST, T.PAVED]

## Distance (cases, chanfrein) à l'eau la plus proche, calculée une fois l'eau posée.
var _wet := PackedFloat32Array()
var _grass_noise := FastNoiseLite.new()
var _mud_noise := FastNoiseLite.new()
var _reed_noise := FastNoiseLite.new()
var _rock_noise := FastNoiseLite.new()
## Points d'échantillonnage des chemins (calculés avant qu'ils ne soient tracés).
var _road_pts: Array = []
var _path_pts: Array = []
## Props posés : [position, rayon de garde].
var _spots: Array = []
## Contrôles d'accessibilité de zones : recalés sur la case praticable la plus proche une fois
## la végétation posée.
var _area_checks := {}


func _setup() -> void:
	W = R.CRUMA_SIZE.x
	H = R.CRUMA_SIZE.y
	SEED = 20261012
	MAP_ID = R.CRUMA_ID
	MAP_NAME = R.CRUMA
	DESCRIPTION = "Les marais de Cruma, à l'est de Gludio : un dédale d'étangs croupis, de chenaux et de roselières sous les arbres morts. Une vieille chaussée les traverse sur des pontons, de la route de Gludio à celle de Dion ; au nord-est, au-delà des rochers, se dresse la tour de Cruma."
	OUT_PATH = "res://scenes/maps/Cruma_Marshlands.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = false
	IS_STARTING_MAP = false
	BIOME = MapData.Biome.FOREST
	PLAYER_SPAWN = SPAWN
	CARVE_TERRAIN = T.DARK_GRASS


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	_init_noises()
	_road_pts = _sample(CAUSEWAY, 2.0)
	_path_pts = _sample(PATH_ROCKS, 2.0) + _sample(PATH_ISLET, 2.0)
	_paint_base()
	_paint_rocky_ground()

	# Pontons d'abord : les chenaux s'y resserrent.
	_bridge(BRIDGE_W, "x", false, "Ponton_Ouest")
	_bridge(BRIDGE_S, "z", false, "Ponton_Sud")
	_bridge(BRIDGE_ROCKS, "x", false, "Ponton_Rochers")
	_bridge(BRIDGE_ISLET, "z", false, "Ponton_Ilot")
	for ch in CHANNELS:
		_river(ch[0], ch[1], ch[2])
	_river(_densify(ISLET_RING, 3.0, true), 2.6, 0.9)
	# Anses qui cassent l'octogone du chenal de l'îlot.
	for cove in [[Vector2(170, 60), 5.0], [Vector2(131, 66), 4.5], [Vector2(163, 46), 4.0]]:
		_pond(cove[0], cove[1])
	for pond in PONDS:
		if pond[0] == Vector2(150, 33):
			_pond(pond[0], pond[1])
		else:
			_marsh_pond(pond[0], pond[1])
	_random_ponds()
	_paint_groves()

	# Chaussée et sentiers, clairières des téléporteurs, de la fourche et de l'îlot.
	_road(CAUSEWAY, ROAD_HALF, T.DIRT, 4.0, 0.35)
	_road(PATH_ROCKS, PATH_HALF, T.DIRT, 2.5, 0.35)
	_road(PATH_ISLET, 1.3, T.DIRT, 2.0, 0.3)
	for portal in [R.CRUMA_PORTAL_W, R.CRUMA_PORTAL_S]:
		_paint_disc(portal, 4.2, T.DIRT, [T.WATER])
		_stamp("open", portal, 10.0, 20.0)
	_paint_disc(FORK, 3.5, T.DIRT, [T.WATER])
	_paint_disc(ISLET, 4.0, T.DIRT, [T.WATER])
	_paint_disc(ROCKS, 5.0, T.DIRT, [T.WATER])
	_paint_outcrops()

	_compute_wet()
	_paint_shores()
	_edge_band(9, T.REEDS, LAND)
	_dress_edge_band()


func _init_noises() -> void:
	var k := 0
	for n in [_grass_noise, _mud_noise, _reed_noise, _rock_noise]:
		k += 1
		n.seed = SEED + k * 131
	_grass_noise.frequency = 0.028
	_mud_noise.frequency = 0.045
	_reed_noise.frequency = 0.09
	_rock_noise.frequency = 0.07


## Sol de base : herbe sombre détrempée, clairières d'herbe plus claire, plaques de boue
## (canal "sol forestier", texturé en vase sombre : distinct de la terre de la chaussée),
## îlots de roseaux épars et quelques roselières isolées.
func _paint_base() -> void:
	for z in H:
		for x in W:
			var t := T.DARK_GRASS
			var g := _grass_noise.get_noise_2d(x, z)
			var m := _mud_noise.get_noise_2d(x, z)
			var r := _reed_noise.get_noise_2d(x * 0.7, z * 0.7)
			if g > 0.3:
				t = T.GRASS
			if m > 0.28:
				t = T.FOREST
			elif r > 0.52:
				t = T.TALL_GRASS
			_terrain[z * W + x] = t


## Avancée rocheuse du nord-est : sol de vase sombre et d'herbe rase, sans roseaux.
func _paint_rocky_ground() -> void:
	_stamp_blob("rocks", ROCKS, 44.0)
	for z in H:
		for x in W:
			var d := _dist("rocks", Vector2(x + 0.5, z + 0.5))
			if d >= 4.0:
				continue
			var n := _rock_noise.get_noise_2d(x * 0.5, z * 0.5)
			if d > -5.0 and n < (d + 5.0) / 9.0 - 0.6:
				continue
			_terrain[z * W + x] = T.FOREST if n < 0.0 else T.DARK_GRASS


## Vieille route pavée (dalles disjointes) qui file des rochers vers l'angle nord-est, vers
## la tour de Cruma, et se perd sous un éboulement ; éboulis infranchissables sur l'avancée,
## de plus en plus serrés vers l'angle, qui finissent en chaos de pierres.
func _paint_outcrops() -> void:
	_road(OLD_ROAD, 1.8, T.PAVED, 2.0, 0.3)
	for z in H:
		for x in W:
			var i := z * W + x
			if _terrain[i] == T.PAVED and _rock_noise.get_noise_2d(x * 2.3, z * 2.3) < -0.2:
				_terrain[i] = T.FOREST
	var corner_dir := Vector2(1, -1).normalized()
	var end_proj: float = ((OLD_ROAD[OLD_ROAD.size() - 1] as Vector2) - ROCKS).dot(corner_dir)
	for z in H:
		for x in W:
			var p := Vector2(x + 0.5, z + 0.5)
			var i := z * W + x
			if _dist("rocks", p) > -2.0 or not LAND.has(_terrain[i]):
				continue
			var proj := (p - ROCKS).dot(corner_dir)
			if proj > end_proj + 1.5 + _noise.get_noise_2d(x * 2.0, z * 2.0) * 3.0:
				_terrain[i] = T.RUBBLE
				continue
			if _dist("road", p) < 3.0 or p.distance_to(ROCKS) < 10.0:
				continue
			var corner := clampf(proj / 30.0, 0.0, 1.0)
			if _rock_noise.get_noise_2d(x * 1.6, z * 1.6) > 0.36 - 0.4 * corner:
				_terrain[i] = T.RUBBLE


## Mares semées au hasard, à l'écart des chemins, des pontons, des téléporteurs, de l'îlot
## et des rochers.
func _random_ponds() -> void:
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 2500:
		tries += 1
		var r := _rng.randf_range(3.5, 8.5)
		var c := Vector2(_rng.randf_range(12.0, W - 12.0), _rng.randf_range(12.0, H - 12.0))
		var reach := r * 1.9
		if _edge(int(c.x), int(c.y)) < reach + 10.0:
			continue
		if _poly_dist(c, _road_pts) < reach + 7.0 or _poly_dist(c, _path_pts) < reach + 5.0:
			continue
		if _dist("rocks", c) < reach + 4.0 or c.distance_to(ISLET) < reach + 22.0:
			continue
		var ok := true
		for b in [BRIDGE_W, BRIDGE_S, BRIDGE_ROCKS, BRIDGE_ISLET]:
			if c.distance_to(b) < reach + 15.0:
				ok = false
		for hub in [R.CRUMA_PORTAL_W, R.CRUMA_PORTAL_S, SPAWN, FORK]:
			if c.distance_to(hub) < reach + 14.0:
				ok = false
		for g in GROVES:
			if c.distance_to(g[0]) < g[1] + reach + 3.0:
				ok = false
		if not ok:
			continue
		_marsh_pond(c, r)
		placed += 1
	# Flaques : petites mares semées partout où il reste de la place.
	var puddles := 0
	tries = 0
	while puddles < 45 and tries < 3000:
		tries += 1
		var r := _rng.randf_range(1.6, 3.2)
		var c := Vector2(_rng.randf_range(14.0, W - 14.0), _rng.randf_range(14.0, H - 14.0))
		if _poly_dist(c, _road_pts) < r + 6.0 or _poly_dist(c, _path_pts) < r + 4.5 or _dist("rocks", c) < r + 2.0:
			continue
		if c.distance_to(ISLET) < 20.0 or _near_hub(c, 14.0) or _near_bridge(c, 8.0) or _dist("river", c) < 4.0:
			continue
		if GROVES.any(func(g: Array) -> bool: return c.distance_to(g[0]) < g[1] + r + 3.0):
			continue
		_pond(c, r)
		puddles += 1
	print("Mares : %d, flaques : %d" % [placed, puddles])


## Mare au contour tourmenté : un étang principal et deux ou trois lobes accolés.
func _marsh_pond(c: Vector2, r: float) -> void:
	_pond(c, r)
	for k in _rng.randi_range(2, 3):
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_pond(c + dir * r * _rng.randf_range(0.6, 0.95), r * _rng.randf_range(0.4, 0.7))


## Bosquets malingres : arbres serrés (en bonne part morts, voir dead_tree_ratio) sur un sol
## forestier.
func _paint_groves() -> void:
	for g in GROVES:
		_stamp_blob("grove", g[0], g[1])
	for z in H:
		for x in W:
			var i := z * W + x
			var d := _dist("grove", Vector2(x + 0.5, z + 0.5))
			if d >= 3.5 or _terrain[i] == T.WATER:
				continue
			_terrain[i] = T.TREE if d < -2.0 else T.FOREST


## Rives : roselières (bloquantes) au ras de l'eau, coupées de berges de boue qui laissent
## approcher l'eau, puis franges de roseaux épars (praticables) et boue.
func _paint_shores() -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			var t := _terrain[i]
			if not (t == T.DARK_GRASS or t == T.GRASS or t == T.DIRT or t == T.TALL_GRASS or t == T.FOREST):
				continue
			var d := _wet[i]
			if d > 6.0:
				continue
			var p := Vector2(x + 0.5, z + 0.5)
			if _dist("road", p) < 1.0 or _near_bridge(p, 2.5) or _near_hub(p, 12.0) or p.distance_to(ISLET) < 6.5:
				continue
			if _dist("rocks", p) < 0.0 or _dist("grove", p) < 0.0:
				continue
			var n := _reed_noise.get_noise_2d(x, z)
			if d <= 1.6 + n * 1.4 and n > -0.2:
				_terrain[i] = T.REEDS
			elif d <= 3.0 and n <= -0.2:
				_terrain[i] = T.FOREST
			elif d <= 3.8 + n * 2.0 and n > -0.4:
				_terrain[i] = T.TALL_GRASS
			elif _mud_noise.get_noise_2d(x * 1.5, z * 1.5) > 0.0:
				_terrain[i] = T.FOREST


## Lisière : roselière percée de fourrés et d'arbres morts ; éboulis vers les rochers.
func _dress_edge_band() -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			if _terrain[i] != T.REEDS or _edge(x, z) >= 12:
				continue
			var p := Vector2(x + 0.5, z + 0.5)
			var n := _rock_noise.get_noise_2d(x * 2.0, z * 2.0)
			if p.distance_to(ROCKS) < 75.0 or (x > W - 50 and z < 70):
				_terrain[i] = T.DEAD_TREE if _rng.randf() < 0.08 else T.RUBBLE
			elif n > 0.45:
				_terrain[i] = T.THICKET
			elif n < -0.1 and _rng.randf() < 0.4:
				_terrain[i] = T.DEAD_TREE


## Distance (cases, chanfrein 1 / 1.414) à la case d'eau la plus proche.
func _compute_wet() -> void:
	_wet.resize(W * H)
	for i in W * H:
		_wet[i] = 0.0 if _terrain[i] == T.WATER else 1.0e6
	for z in H:
		for x in W:
			var i := z * W + x
			var v := _wet[i]
			if x > 0:
				v = minf(v, _wet[i - 1] + 1.0)
			if z > 0:
				v = minf(v, _wet[i - W] + 1.0)
				if x > 0:
					v = minf(v, _wet[i - W - 1] + 1.414)
				if x < W - 1:
					v = minf(v, _wet[i - W + 1] + 1.414)
			_wet[i] = v
	for z in range(H - 1, -1, -1):
		for x in range(W - 1, -1, -1):
			var i := z * W + x
			var v := _wet[i]
			if x < W - 1:
				v = minf(v, _wet[i + 1] + 1.0)
			if z < H - 1:
				v = minf(v, _wet[i + W] + 1.0)
				if x < W - 1:
					v = minf(v, _wet[i + W + 1] + 1.414)
				if x > 0:
					v = minf(v, _wet[i + W - 1] + 1.414)
			_wet[i] = v


func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for q in pts:
		best = minf(best, p.distance_to(q))
	return best


## Vrai près d'un téléporteur, du point d'apparition ou de la fourche.
func _near_hub(p: Vector2, radius: float) -> bool:
	for hub in [R.CRUMA_PORTAL_W, R.CRUMA_PORTAL_S, SPAWN, FORK]:
		if p.distance_to(hub) < radius:
			return true
	return false


func _wet_at(p: Vector2) -> float:
	return _wet[clampi(int(p.y), 0, H - 1) * W + clampi(int(p.x), 0, W - 1)]


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	_place_ruins()
	_place_rocks()
	_place_wrecks()
	_place_marsh_trees()
	_place_signs()
	_portal("O", R.CRUMA_PORTAL_W, R.GLUDIO_ID, R.GLUDIO_PORTAL_E, R.GLUDIO)
	_portal("S", R.CRUMA_PORTAL_S, R.DION_ID, R.DION_PORTAL_N, R.DION)
	_checks["Fourche"] = FORK
	_checks["Ilot des ruines"] = ISLET
	_checks["Rochers du nord-est"] = ROCKS
	_checks["Ponton ouest (rive est)"] = BRIDGE_W + Vector2(9.0, 0.0)
	_checks["Ponton sud (rive sud)"] = BRIDGE_S + Vector2(0.0, 9.0)
	_checks["Ponton des rochers (rive est)"] = BRIDGE_ROCKS + Vector2(9.0, 0.0)
	# Grandes zones de chasse, recalées sur une case praticable proche (voir _after_props).
	_area_checks = {
		"Marais nord-ouest": Vector2(40, 30), "Marais ouest": Vector2(30, 160),
		"Marais sud-ouest": Vector2(40, 222), "Rive sud de l'étang central": Vector2(105, 190),
		"Marais du sud": Vector2(160, 215), "Marais du sud-est": Vector2(280, 215),
		"Marais de l'est": Vector2(275, 140), "Entre les chenaux": Vector2(185, 125),
		"Marais du nord": Vector2(120, 20), "Nord de l'étang de l'îlot": Vector2(150, 14),
		"Rive est du chenal des rochers": Vector2(240, 95),
	}
	_hunting_grounds()


## Monstres des Cruma Marshlands de Lineage 2 (niveaux 25-35) sur les zones de chasse
## ci-dessus : sangsues et fourmis à l'ouest (près de Gludio), crapauds autour de l'étang,
## spectres sur l'îlot et entre les chenaux, la ruche des stakatos à l'est (et leur reine
## Zyrnna), guêpes et araignées vers les rochers du nord-est.
func _hunting_grounds() -> void:
	_monster_zone("Cruma_NordOuest", Vector2(40, 30), 22.0, M.mix([["Gray Ant", 2], ["Giant Crimson Ant", 1]]), 10)
	_monster_zone("Cruma_Ouest", Vector2(30, 160), 22.0, M.mix([["Giant Mist Leech", 3], ["Gray Ant", 1]]), 10)
	_monster_zone("Cruma_SudOuest", Vector2(40, 222), 18.0, M.mix([["Giant Mist Leech", 2], ["Toad Lord", 1]]), 8)
	_monster_zone("Cruma_Etang", Vector2(105, 190), 20.0, M.mix([["Toad Lord", 2], ["Giant Crimson Ant", 1]]), 9)
	_monster_zone("Cruma_Nord", Vector2(120, 20), 20.0, M.mix([["Gray Ant", 1], ["Giant Mist Leech", 1], ["Horror Mist Ripper", 1]]), 9)
	_monster_zone("Cruma_EtangIlot", Vector2(150, 14), 16.0, M.mix([["Giant Crimson Ant", 1], ["Horror Mist Ripper", 1]]), 6)
	_monster_zone("Cruma_Ilot", ISLET, 13.0, M.mix([["Horror Mist Ripper", 2], ["Marsh Stakato Soldier", 1]]), 6)
	_monster_zone("Cruma_Chenaux", Vector2(185, 125), 20.0, M.mix([["Horror Mist Ripper", 1], ["Marsh Stakato", 2], ["Marsh Stakato Soldier", 1]]), 10)
	_monster_zone("Cruma_Sud", Vector2(160, 215), 18.0, M.mix([["Marsh Stakato", 2], ["Marsh Stakato Worker", 2]]), 8)
	_monster_zone("Cruma_SudEst", Vector2(280, 215), 20.0, M.mix([["Stinger Wasp", 2], ["Marsh Stakato Worker", 1]]), 8)
	_monster_zone("Cruma_Ruche", Vector2(275, 140), 24.0, M.mix([["Marsh Stakato", 3], ["Marsh Stakato Worker", 3],
			["Marsh Stakato Soldier", 2], ["Marsh Stakato Drone", 1]]), 16)
	_monster_zone("Cruma_ChenalRochers", Vector2(240, 95), 18.0, M.mix([["Marsh Spider", 2], ["Stinger Wasp", 1], ["Marsh Stakato Drone", 1]]), 9)
	_monster_zone("Cruma_Rochers", ROCKS, 16.0, M.mix([["Marsh Spider", 2], ["Marsh Stakato Drone", 1]]), 7)
	_monster_zone("Cruma_ReineZyrnna", Vector2(278, 150), 8.0, M.mix([["Stakato Queen Zyrnna", 1]]), 1, 3600)


## Vrai si un prop de rayon `radius` peut se poser en `p` : terrain praticable naturel sous
## lui (et `margin` m autour), loin des chemins, pontons, téléporteurs et autres props.
func _spot_ok(p: Vector2, radius: float, margin: float, spacing: float, road_clear := 2.5) -> bool:
	if _edge(int(p.x), int(p.y)) < 3:
		return false
	var reach := radius + margin
	for z in range(floori(p.y - reach), ceili(p.y + reach) + 1):
		for x in range(floori(p.x - reach), ceili(p.x + reach) + 1):
			if Vector2(x + 0.5, z + 0.5).distance_to(p) > reach:
				continue
			if not _in_map(Vector2i(x, z)) or not LAND.has(_terrain[z * W + x]):
				return false
	if _dist("road", p) < radius + road_clear or _near_bridge(p, radius + 2.0) or _near_hub(p, 9.0):
		return false
	for s in _spots:
		if (s[0] as Vector2).distance_to(p) < s[1] + radius + spacing:
			return false
	return true


func _put(scene: String, parent: Node, p: Vector2, radius: float, yaw: float) -> Node3D:
	var node := _instance(scene, parent, p, yaw)
	_spots.append([p, radius])
	_reserve_disc(p, radius + 1.0)
	return node


## Îlot des ruines : colonnes brisées en cercle (ouvert au sud, côté ponton), pans de mur
## bas, éboulis — vestiges de l'ancienne Cruma.
func _place_ruins() -> void:
	var group := _add(_props, _node("Ruines"))
	for deg in [-15.0, 30.0, 75.0, 120.0, 165.0, 210.0]:
		var dir := Vector2.from_angle(deg_to_rad(deg - 90.0))
		var node := _put("RuinColumnBroken", group, ISLET + dir * 6.5, 0.8, _rng.randf() * TAU)
		node.name = "Colonne_%d" % int(deg + 15.0)
	_put("RuinWallLow", group, ISLET + Vector2(-8.5, -3.0), 2.0, PI / 2.0 + 0.2).name = "Mur_Ouest"
	_put("RuinWallLow", group, ISLET + Vector2(5.5, -8.5), 2.0, -0.35).name = "Mur_Nord"
	_put("RuinRubble", group, ISLET + Vector2(8.0, 3.5), 1.6, _rng.randf() * TAU).name = "Eboulis_Est"
	_put("RuinRubble", group, ISLET + Vector2(-6.0, 6.5), 1.6, _rng.randf() * TAU).name = "Eboulis_SudOuest"
	_put("RuinColumnFallen", group, ISLET + Vector2(1.5, -2.0), 2.6, 0.5).name = "Colonne_Couchee"
	# Deux colonnes brisées marquent le départ de la vieille route pavée vers la tour ; au
	# bout, colonne couchée, pan de mur et éboulis : la route se perd sous l'éboulement.
	var dir: Vector2 = (OLD_ROAD[1] - OLD_ROAD[0]).normalized()
	var side := Vector2(-dir.y, dir.x)
	_put("RuinColumnBroken", group, ROCKS + dir * 3.0 + side * 3.3, 0.8, 0.7).name = "Colonne_Rochers_N"
	_put("RuinColumnBroken", group, ROCKS + dir * 3.0 - side * 3.3, 0.8, 2.1).name = "Colonne_Rochers_S"
	var end: Vector2 = OLD_ROAD[OLD_ROAD.size() - 1]
	_put("RuinColumnFallen", group, end - dir * 7.0 + side * 3.6, 2.6, atan2(-dir.y, dir.x) + 0.15).name = "Colonne_Couchee_Route"
	_put("RuinWall", group, end + dir * 1.5 - side * 1.0, 2.0, atan2(-side.y, side.x) + 0.3).name = "Mur_Effondre"
	_put("RuinRubble", group, end + side * 1.6, 1.6, 0.4).name = "Eboulis_Route"


## Gros rochers sur l'avancée du nord-est (plus serrés vers l'angle), quelques pierres
## éparses dans le marais.
func _place_rocks() -> void:
	var group := _add(_props, _node("Rochers"))
	var large := 0
	var medium := 0
	var tries := 0
	while (large < 40 or medium < 50) and tries < 8000:
		tries += 1
		var p := ROCKS + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * 48.0
		if _dist("rocks", p) > -1.0 or p.distance_to(ROCKS) < 8.0:
			continue
		var big := large < 40 and (medium >= 50 or _rng.randf() < 0.45)
		var radius := 1.15 if big else 0.7
		if not _spot_ok(p, radius, 0.6, 2.5, 2.0):
			continue
		var node := _put("RockLarge" if big else "RockMedium", group, p, radius, _rng.randf() * TAU)
		node.scale = Vector3.ONE * _rng.randf_range(0.85, 1.3)
		if big:
			large += 1
		else:
			medium += 1
	tries = 0
	var loose := 0
	while loose < 14 and tries < 3000:
		tries += 1
		var p := Vector2(_rng.randf_range(10, W - 10), _rng.randf_range(10, H - 10))
		if _dist("rocks", p) < 6.0 or not _spot_ok(p, 0.7, 0.8, 6.0):
			continue
		_put("RockMedium", group, p, 0.7, _rng.randf() * TAU)
		loose += 1


## Épaves : charrette abandonnée au bord de la chaussée, troncs couchés, souches.
func _place_wrecks() -> void:
	var group := _add(_props, _node("Epaves"))
	_put("CartBroken", group, Vector2(60.0, 103.5), 1.7, 0.35).name = "Charrette"
	_put("Barrel", group, Vector2(63.5, 102.0), 0.5, 0.0)
	_put("Crate", group, Vector2(57.5, 101.5), 0.6, 0.6)
	var logs := 0
	var stumps := 0
	var tries := 0
	while (logs < 16 or stumps < 22) and tries < 6000:
		tries += 1
		var p := Vector2(_rng.randf_range(10, W - 10), _rng.randf_range(10, H - 10))
		var is_log := logs < 16 and (stumps >= 22 or _rng.randf() < 0.45)
		var radius := 1.7 if is_log else 0.5
		if _dist("rocks", p) < 0.0 or not _spot_ok(p, radius, 0.6, 4.0):
			continue
		_put("LogFallen" if is_log else "Stump", group, p, radius, _rng.randf() * TAU)
		if is_log:
			logs += 1
		else:
			stumps += 1


## Arbres tordus du marais (mousse pendante), surtout au bord de l'eau ; quelques-uns
## piqués dans la lisière.
func _place_marsh_trees() -> void:
	var group := _add(_props, _node("ArbresDuMarais"))
	var big := 0
	var small := 0
	var tries := 0
	while (big < 130 or small < 150) and tries < 40000:
		tries += 1
		var p := Vector2(_rng.randf_range(6.0, W - 6.0), _rng.randf_range(6.0, H - 6.0))
		if _rng.randf() > 0.2 + 0.8 * (1.0 - smoothstep(2.0, 14.0, _wet_at(p))):
			continue
		if _dist("rocks", p) < -8.0:
			continue
		var want_big := big < 130 and (small >= 150 or _rng.randf() < 0.47)
		var radius := 0.45 if want_big else 0.35
		if not _spot_ok(p, radius, 0.8, 3.2 if want_big else 2.2):
			continue
		var node := _put("MarshTree" if want_big else "MarshTreeSmall", group, p, radius, _rng.randf() * TAU)
		node.scale = Vector3.ONE * _rng.randf_range(0.85, 1.15)
		if want_big:
			big += 1
		else:
			small += 1
	# Lisière : arbres morts du marais dans la roselière des bords.
	var band := 0
	tries = 0
	while band < 70 and tries < 8000:
		tries += 1
		var p := Vector2(_rng.randf_range(2.0, W - 2.0), _rng.randf_range(2.0, H - 2.0))
		var t := _t_at(p)
		if _edge(int(p.x), int(p.y)) > 8 or not (t == T.REEDS or t == T.DEAD_TREE or t == T.THICKET):
			continue
		if _spots.any(func(s: Array) -> bool: return (s[0] as Vector2).distance_to(p) < 5.0):
			continue
		_put("MarshTree" if _rng.randf() < 0.6 else "MarshTreeSmall", group, p, 0.45, _rng.randf() * TAU)
		band += 1
	print("Arbres du marais : %d grands, %d petits, %d en lisière" % [big, small, band])


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	var west := R.CRUMA_PORTAL_W + Vector2(6.0, -5.0)
	_sign(signs, "Teleporteur_O", west, [[R.GLUDIO, 180.0], [R.DION, 0.0]])
	var fork := FORK + Vector2(-4.0, 5.0)
	_sign(signs, "Fourche", fork, [[R.GLUDIO, _heading(fork, Vector2(108, 108.5))],
			[R.DION, _heading(fork, Vector2(164, 142))]])
	var south := R.CRUMA_PORTAL_S + Vector2(5.0, -6.0)
	_sign(signs, "Teleporteur_S", south, [[R.DION, 90.0], [R.GLUDIO, _heading(south, Vector2(186, 196))]])
	for s in [west, fork, south]:
		_spots.append([s, 1.0])


# ---------------------------------------------------------------------------
# 3. Arbres morts (une fois les emprises connues), contrôles de zones
# ---------------------------------------------------------------------------

func _after_props(blocked: Dictionary) -> void:
	var dead := _scatter(T.DEAD_TREE, [T.DARK_GRASS, T.GRASS, T.DIRT, T.TALL_GRASS, T.FOREST], func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)):
			return 0.0
		if _dist("road", p) < 2.5 or _near_bridge(p, 3.0) or _near_hub(p, 9.0) or p.distance_to(ISLET) < 9.0:
			return 0.0
		if _dist("rocks", p) < 0.0:
			return 0.006
		return lerpf(0.012, 0.035, 1.0 - smoothstep(2.0, 10.0, _wet[z * W + x])), 2)
	print("Arbres morts : %d" % dead)
	for label in _area_checks:
		_checks[label] = _nearest_open(_area_checks[label], blocked)


## Case praticable la plus proche de `p` (à 10 m au plus), sinon `p`.
func _nearest_open(p: Vector2, blocked: Dictionary) -> Vector2:
	var best := p
	var best_d := INF
	for z in range(int(p.y) - 10, int(p.y) + 11):
		for x in range(int(p.x) - 10, int(p.x) + 11):
			if not _in_map(Vector2i(x, z)) or not _walkable(z * W + x, blocked):
				continue
			var d := Vector2(x + 0.5, z + 0.5).distance_to(p)
			if d < best_d:
				best_d = d
				best = Vector2(x + 0.5, z + 0.5)
	return best


func _configure_ground(ground: TerrainGround) -> void:
	ground.grass_asset = "Grass004"
	ground.forest_asset = "Ground037"
	ground.dirt_asset = "Ground067"
	ground.paved_asset = "PavingStones138"
	ground.paved_desaturate = 0.6
	ground.paved_tint = Color(0.5, 0.5, 0.47)
	ground.shader_overrides = {
		"grass_tint": Color(0.5, 0.54, 0.38),
		"dark_grass_tint": Color(0.34, 0.4, 0.27),
		"forest_tint": Color(0.34, 0.3, 0.23),
		"dirt_tint": Color(0.5, 0.42, 0.33),
		"wet_tint": Color(0.3, 0.27, 0.2),
		"pebble_tint": Color(0.34, 0.32, 0.26),
	}
	# Marais : eau peu profonde, berges en pente douce.
	ground.river_depth = 1.3
	ground.water_level = -0.55
	ground.bank_width = 1.9
	ground.water_overrides = {
		"deep_color": Color(0.06, 0.08, 0.04),
		"shallow_color": Color(0.22, 0.24, 0.13),
		"foam_color": Color(0.44, 0.45, 0.34),
		"flow": Vector2(0.01, 0.05),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.foliage_tint = Color(0.6, 0.6, 0.4)
	vegetation.dead_tree_ratio = 0.55
	vegetation.outer_density = 0.38
	vegetation.outer_dead_ratio = 0.6
	vegetation.grass_density = 0.38
	vegetation.forest_grass_density = 0.1
	vegetation.bush_density = 0.012
	vegetation.rock_density = 0.01
