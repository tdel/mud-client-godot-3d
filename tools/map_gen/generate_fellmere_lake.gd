extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Fellmere_Lake.tscn (280 x 240 cases), le lac
## de Fellmere de Lineage 2, à l'ouest des ruines d'Agonie : le lac, les champs de moisson
## de Fellmere au nord et le camp abandonné des Ol Mahum au sud (niveaux 14-25). Zone
## sauvage (ni ville ni zone de paix), sans PNJ, cul-de-sac (un seul téléporteur) ; monstres
## de Lineage 2 (voir _hunting_grounds). Relancer ce script ÉCRASE la scène ; ensuite
## l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Fellmere_Lake.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - la vieille route pavée vient du téléporteur de l'est (Ruins of Agony) et se divise à
##     la fourche : au nord-ouest, la route des moissons monte vers la ferme en ruine ; au
##     sud-ouest, un chemin de terre descend vers le camp abandonné ; à l'ouest, un sentier
##     mène à l'embarcadère de la rive est (ponton de bois, piles de planches et de bois) ;
##   - au milieu et à l'ouest, le grand lac de Fellmere, aux rives découpées frangées de
##     roseaux et de hautes herbes ; à l'ouest, une île boisée où se dresse un vieil autel,
##     reliée à la rive ouest par une passerelle (repaire de la princesse Molrang) ;
##   - au nord du lac, les champs de moisson de Fellmere : parcelles à demi abandonnées
##     (blé clairsemé, friches de hautes herbes), clôtures effondrées, la ferme en ruine
##     (maison, remise, grange écroulée, puits, charrette brisée, bûches) ; un chemin de
##     terre file vers l'ouest, le long de la rive nord, jusqu'à la passerelle de l'île ;
##   - au nord-ouest, les bois sombres (araignées) ; ailleurs des bosquets, et une lisière
##     de forêt et de fourrés le long des bords ;
##   - au sud du lac, le camp abandonné des Ol Mahum : palissade de pieux, tours de guet de
##     bois aux angles, porte à l'est (chemin de la fourche) et poterne à l'ouest (sentier de
##     la rive sud vers l'île) ; dans la cour de terre battue, la grande tente du chef,
##     des rangs de tentes, feux de camp, râteliers d'armes, cages, caisses et tonneaux ; un
##     bivouac de traînards à l'ouest, hors les murs ;
##   - des poteaux indicateurs près du téléporteur et aux embranchements.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_fellmere_lake.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")

const ROAD_HALF := 2.4
const PATH_HALF := 1.3
const SPAWN := Vector2(262.5, 120.5)
## Fourche de la vieille route.
const FORK := Vector2(224.0, 117.0)
## Vieille route pavée : du téléporteur (prolongée au-delà du bord est) à la fourche.
const ROAD := [Vector2(290, 120.5), R.FELLMERE_PORTAL_E, SPAWN, Vector2(248, 120.5), Vector2(236, 118.5), FORK]
## Route des moissons (pavés moussus) : de la fourche à la cour de la ferme.
const FARM := Vector2(172.0, 56.0)
const HARVEST_ROAD := [FORK, Vector2(216, 101), Vector2(207, 84), Vector2(193, 68), FARM]
## Chemin de terre de la ferme vers la rive ouest et la passerelle de l'île.
const NORTH_TRACK := [FARM, Vector2(158, 60), Vector2(138, 64), Vector2(114, 68), Vector2(90, 74), Vector2(68, 83),
		Vector2(52, 96), Vector2(42, 110), Vector2(41.5, 122.5), Vector2(46, 122.5)]
## Camp abandonné des Ol Mahum : enceinte rectangulaire (axe de la palissade).
const CAMP := Vector2(140.0, 198.0)
const CAMP_WALL := [Vector2(112, 178), Vector2(168, 178), Vector2(168, 218), Vector2(112, 218)]
const CAMP_GATE_E := Vector2(168.0, 198.0)
const CAMP_GATE_W := Vector2(112.0, 205.0)
## Chemin de terre de la fourche à la porte est du camp.
const CAMP_ROAD := [FORK, Vector2(220, 133), Vector2(211, 152), Vector2(198, 172), Vector2(185, 190),
		Vector2(174, 198), CAMP_GATE_E]
## Sentier de la poterne ouest, le long de la rive sud, jusqu'à la rive ouest.
const SOUTH_TRAIL := [CAMP_GATE_W, Vector2(100, 203), Vector2(84, 194), Vector2(66, 180), Vector2(50, 162),
		Vector2(41, 144), Vector2(40, 130), Vector2(41.5, 122.5)]
## Lac : lobes [centre, rayon] ; île et passerelle (tablier selon X) vers la rive ouest.
const LAKE_LOBES := [[Vector2(78, 122), 29.0], [Vector2(110, 116), 24.0], [Vector2(140, 126), 22.0],
		[Vector2(118, 142), 16.0], [Vector2(160, 120), 11.0], [Vector2(96, 96), 11.0], [Vector2(72, 148), 11.0],
		[Vector2(146, 104), 9.0], [Vector2(150, 146), 9.0], [Vector2(168, 128), 7.0]]
const ISLAND := Vector2(65.0, 122.0)
const ISLAND_R := 8.0
const ISLAND_BRIDGE := Vector2(52.0, 122.5)
## Parcelles des champs de moisson : [rectangle, part laissée en friche (0..1)].
const FIELDS := [[Rect2(182, 24, 28, 18), 0.25], [Rect2(140, 22, 26, 22), 0.35], [Rect2(104, 30, 28, 22), 0.6],
		[Rect2(216, 56, 22, 18), 0.4], [Rect2(118, 75, 24, 11), 0.7], [Rect2(76, 44, 20, 16), 0.8]]
## Bois : [centre, rayon] ; bois sombres au nord-ouest.
const WOODS := [[Vector2(236, 34), 18.0], [Vector2(252, 172), 20.0], [Vector2(214, 218), 14.0],
		[Vector2(60, 214), 16.0], [Vector2(22, 188), 14.0], [Vector2(196, 140), 9.0], [Vector2(244, 80), 10.0],
		[Vector2(94, 162), 8.0], [Vector2(201, 96), 8.0], [Vector2(178, 160), 7.0], [Vector2(60, 156), 7.0],
		[Vector2(240, 140), 9.0], [Vector2(148, 86), 6.0]]
const DARK_WOODS := [[Vector2(38, 44), 24.0], [Vector2(70, 22), 16.0], [Vector2(20, 84), 13.0], [Vector2(56, 62), 12.0]]

## Bruit de "taches" (friches, terre battue).
var _patch := FastNoiseLite.new()
## Props posés : [position, rayon] (évitement mutuel des props épars).
var _occupied: Array = []
## Embarcadère de la rive est (calculé d'après la rive).
var _pier := Vector2.ZERO


func _setup() -> void:
	W = R.FELLMERE_SIZE.x
	H = R.FELLMERE_SIZE.y
	SEED = 20261021
	MAP_ID = R.FELLMERE_ID
	MAP_NAME = R.FELLMERE
	DESCRIPTION = "Le grand lac de Fellmere, à l'ouest des ruines d'Agonie, ses roseaux et son île où rôde la princesse des hommes-lézards. Au nord, les champs de moisson abandonnés ; au sud, le camp palissadé des Ol Mahum."
	OUT_PATH = "res://scenes/maps/Fellmere_Lake.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = false
	BIOME = MapData.Biome.FOREST
	# Sur la route, une douzaine de cases après le téléporteur venu des ruines d'Agonie.
	PLAYER_SPAWN = SPAWN
	_patch.seed = SEED + 3
	_patch.frequency = 0.16


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Prairie : herbe sombre par grandes taches.
	var meadow := FastNoiseLite.new()
	meadow.seed = SEED + 11
	meadow.frequency = 0.02
	for z in H:
		for x in W:
			if meadow.get_noise_2d(x, z) > 0.22:
				_terrain[z * W + x] = T.DARK_GRASS

	# Bois et bois sombres (arbres plantés après les props).
	for g in WOODS:
		_stamp_blob("wood", g[0], g[1])
	_paint_field("wood", 0.0, T.FOREST, 1.5)
	for g in DARK_WOODS:
		_stamp_blob("darkwood", g[0], g[1])
	var dark: PackedFloat32Array = _field("darkwood")
	for i in W * H:
		if dark[i] <= 2.0:
			_terrain[i] = T.FOREST if _patch.get_noise_2d(i % W, i / W) > -0.1 else T.DARK_GRASS

	_lake()
	_shore_reeds()
	_fields_ground()
	_camp_ground()

	# Routes et chemins.
	_road(ROAD, ROAD_HALF, T.PAVED, 4.0, 0.35)
	_road(HARVEST_ROAD, 2.0, T.PAVED, 3.0, 0.4)
	_paint_disc(R.FELLMERE_PORTAL_E, 4.2, T.PAVED, [T.WATER])
	_stamp("open", R.FELLMERE_PORTAL_E, 10.0, 20.0)
	_paint_disc(FARM, 8.0, T.DIRT, [T.WATER])
	_stamp_blob("yard", FARM, 9.0)
	_road(NORTH_TRACK, PATH_HALF, T.DIRT, 2.0, 0.4)
	_road(CAMP_ROAD, 1.7, T.DIRT, 2.5, 0.4)
	_road(SOUTH_TRAIL, PATH_HALF, T.DIRT, 2.0, 0.4)
	# Sentier de la fourche à l'embarcadère.
	_road([FORK, Vector2(210, 119), Vector2(194, 123), _pier + Vector2(8.5, 0)], PATH_HALF, T.DIRT, 2.0, 0.4)
	_stamp("open", _pier + Vector2(10, 0), 3.0, 10.0)
	# Rive ouest : petite esplanade au débouché de la passerelle.
	_paint_disc(Vector2(41.5, 122.5), 3.0, T.DIRT, [T.WATER])
	_stamp("open", Vector2(41.5, 122.5), 4.0, 10.0)

	_edge_band(7, T.THICKET, [T.GRASS, T.DARK_GRASS, T.FOREST, T.TALL_GRASS])


## Lac de Fellmere : union de lobes au bord irrégulier, moins l'île ; chenal étroit et rives
## franches au droit de la passerelle ; ponton de l'embarcadère sur la rive est.
func _lake() -> void:
	for lobe in LAKE_LOBES:
		_stamp_blob("lake", lobe[0], lobe[1])
	_stamp_blob("island", ISLAND, ISLAND_R)
	var lake: PackedFloat32Array = _field("lake")
	var isl: PackedFloat32Array = _field("island")
	var river: PackedFloat32Array = _field("river")
	for z in H:
		for x in W:
			var i := z * W + x
			var d := maxf(lake[i], -isl[i])
			# Chenal de 8 m sous la passerelle, rives franches de part et d'autre.
			if z >= 119 and z <= 125:
				if x >= 48 and x <= 55:
					d = minf(d, -0.5)
				elif x >= 56 and x <= 60:
					d = maxf(d, 0.5)
			if z >= 112 and z <= 132 and x >= 36 and x <= 47:
				d = maxf(d, 0.5 + (47 - x) * 0.5)
			river[i] = d
			if d <= 0.0:
				_terrain[i] = T.WATER
	_fields["river"] = river
	_bridge(ISLAND_BRIDGE, "x", false, "Passerelle_Ile")
	# Embarcadère : rive est du lac sur la ligne z = 124.5, 3 m de tablier à terre.
	var z_pier := 124
	var shore := 200
	while shore > 150 and _terrain[z_pier * W + shore - 1] != T.WATER:
		shore -= 1
	_pier = Vector2(shore - 3.5, z_pier + 0.5)
	_bridge(_pier, "x", false, "Ponton_Embarcadere")


## Roselières et hautes herbes sur les rives (pas au droit des passerelles).
func _shore_reeds() -> void:
	for z in H:
		for x in W:
			var i := z * W + x
			var p := Vector2(x + 0.5, z + 0.5)
			var d := _dist("river", p)
			if d <= 0.0 or d > 5.0 or _near_bridge(p, 3.0):
				continue
			var n := _patch.get_noise_2d(x * 1.4, z * 1.4)
			if d < 2.2 and n > 0.15 and _dist("island", p) > 0.0:
				_terrain[i] = T.REEDS
			elif d < 2.8 + n * 2.2:
				_terrain[i] = T.TALL_GRASS


## Parcelles à demi abandonnées : blé clairsemé, friches de hautes herbes.
func _fields_ground() -> void:
	for f in FIELDS:
		var rect: Rect2 = f[0]
		var wild: float = f[1]
		_stamp_rect("field", rect, 8.0)
		for z in range(int(rect.position.y), int(rect.end.y)):
			for x in range(int(rect.position.x), int(rect.end.x)):
				if _terrain[z * W + x] == T.WATER:
					continue
				var n := _patch.get_noise_2d(x * 1.1 + 40.0, z * 1.1)
				_terrain[z * W + x] = T.CROP if n > wild * 1.1 - 0.55 else (T.TALL_GRASS if n > wild - 0.95 else T.GRASS)


## Camp : cour de terre battue, abords piétinés.
func _camp_ground() -> void:
	_stamp_rect("camp", Rect2(CAMP_WALL[0], CAMP_WALL[2] - CAMP_WALL[0]), 30.0)
	var camp: PackedFloat32Array = _field("camp")
	for i in W * H:
		if _terrain[i] == T.WATER:
			continue
		var n := _patch.get_noise_2d((i % W) * 0.8, (i / W) * 0.8)
		var n2 := _patch.get_noise_2d((i % W) * 2.2 + 90.0, (i / W) * 2.2)
		if camp[i] < -3.0 and n2 > 0.42:
			# Touffes d'herbe rase dans la cour piétinée.
			_terrain[i] = T.GRASS
		elif camp[i] < 0.0 or camp[i] < 4.0 + n * 7.0 + n2 * 2.5:
			_terrain[i] = T.DIRT
		elif camp[i] < 12.0 + n * 4.0 and _terrain[i] != T.FOREST:
			_terrain[i] = T.GRASS


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	_harvest_farm()
	_fences()
	_abandoned_camp()
	_landing()
	_island()
	_wilds()
	_place_signs()
	_portal("E", R.FELLMERE_PORTAL_E, R.AGONY_ID, R.AGONY_PORTAL_W, R.AGONY)
	_checks["Rive ouest"] = Vector2(41.5, 126.5)
	_checks["Champs du nord"] = Vector2(196.5, 47.5)
	_checks["Bois sombres"] = Vector2(40.5, 46.5)
	_hunting_grounds()


## Monstres du lac de Fellmere de Lineage 2 (niveaux 14-25) : lézards Felim sur les rives,
## ours, loups-garous Gora et hommes-rats dans les champs, araignées dans les bois sombres,
## Ol Mahum et yeux flottants au camp abandonné et alentour ; boss de raid Greyclaw Kutus
## devant la tente du chef, Princess Molrang sur l'île.
func _hunting_grounds() -> void:
	_monster_zone("Fellmere_RiveEst", Vector2(184, 140), 18.0, M.mix([["Felim Lizardman", 3], ["Felim Lizardman Scout", 1]]), 9)
	_monster_zone("Fellmere_Lisiere", Vector2(232, 72), 22.0, M.mix([["Red Bear", 3], ["Grizzly Bear", 1]]), 9)
	_monster_zone("Fellmere_RiveNord", Vector2(108, 88), 22.0, M.mix([["Felim Lizardman", 2], ["Felim Lizardman Scout", 2],
			["Felim Lizardman Warrior", 1]]), 10)
	_monster_zone("Fellmere_Moissons", Vector2(168, 34), 30.0, M.mix([["Red Bear", 2], ["Grizzly Bear", 2], ["Gora Werewolf", 2]]), 13)
	_monster_zone("Fellmere_ChampsOuest", Vector2(100, 44), 24.0, M.mix([["Gora Werewolf", 2], ["Ratman Warrior", 3],
			["Grizzly Bear", 1]]), 10)
	_monster_zone("Fellmere_BoisSombres", Vector2(40, 52), 26.0, M.mix([["Arachnid Predator", 4], ["Ratman Warrior", 1]]), 10)
	_monster_zone("Fellmere_RiveOuest", Vector2(34, 150), 20.0, M.mix([["Felim Lizardman Scout", 1], ["Felim Lizardman Warrior", 2]]), 8)
	_monster_zone("Fellmere_AbordsCamp", Vector2(196, 206), 22.0, M.mix([["Ol Mahum Novice", 3], ["Ol Mahum Straggler", 2],
			["Wandering Eye", 1]]), 10)
	_monster_zone("Fellmere_Trainards", Vector2(80, 196), 22.0, M.mix([["Ol Mahum Straggler", 2], ["Hungry Eye", 2],
			["Wandering Eye", 1], ["Ol Mahum Patrol", 1]]), 10)
	_monster_zone("Fellmere_CampOlMahum", CAMP + Vector2(4, 0), 22.0, M.mix([["Ol Mahum Recruit", 2], ["Ol Mahum Patrol", 2],
			["Ol Mahum Guard", 2], ["Ol Mahum Supplier", 1], ["Ol Mahum Officer", 1], ["Ol Mahum Captain", 1]]), 16)
	_monster_zone("Fellmere_GreyclawKutus", Vector2(131.5, 197.5), 3.0, M.mix([["Greyclaw Kutus", 1]]), 1, 3600)
	_monster_zone("Fellmere_PrincessMolrang", ISLAND + Vector2(1.5, 2.5), 3.0, M.mix([["Princess Molrang", 1]]), 1, 3600)


## Ferme en ruine des champs de moisson.
func _harvest_farm() -> void:
	var group := _add(_props, _node("Ferme"))
	var house_pos := FARM + Vector2(0, -11.5)
	_building("HouseMedium", group, house_pos, Vector2(0, 1), "Ferme_Maison")
	_reserve_cells(_rect_cells(house_pos, Vector2(0, 1), BUILDING_SIZE["HouseMedium"], 1.0))
	_occupy(house_pos, 4.5)
	var shed_pos := FARM + Vector2(12.5, -1.0)
	_building("HouseSmall", group, shed_pos, Vector2(-1, 0), "Ferme_Remise")
	_occupy(shed_pos, 3.8)
	# Grange écroulée : pans de murets autour d'un tas de gravats.
	var barn := FARM + Vector2(-14.0, -7.0)
	var barn_group := _add(group, _node("Grange_ecroulee"))
	_wall_run(barn_group, "RuinWallLow", 4.0, barn + Vector2(-4.5, -3.5), barn + Vector2(4.5, -3.5))
	_wall_run(barn_group, "RuinWallLow", 4.0, barn + Vector2(-4.5, -3.5), barn + Vector2(-4.5, 1.0))
	_wall_run(barn_group, "RuinWallLow", 4.0, barn + Vector2(4.5, 0.0), barn + Vector2(4.5, 3.5))
	_instance("RuinRubble", barn_group, barn + Vector2(0.5, 0.5), 0.6)
	_instance("PlankPile", barn_group, barn + Vector2(-1.5, 4.5), 0.3)
	_occupy(barn, 6.0)
	_instance("Well", group, FARM + Vector2(-4.0, 3.5), 0.0)
	_occupy(FARM + Vector2(-4.0, 3.5), 1.6)
	for entry in [["CartBroken", FARM + Vector2(5.5, 5.0), 2.4], ["LogPile", FARM + Vector2(9.0, -8.5), 1.6],
			["Barrel", FARM + Vector2(6.0, -6.5), 0.6], ["Barrel", FARM + Vector2(6.9, -5.8), 0.6],
			["Crate", FARM + Vector2(-6.5, -5.5), 0.8], ["Stump", FARM + Vector2(-8.0, 6.0), 0.8],
			["Stump", FARM + Vector2(13.0, 7.0), 0.8], ["LogFallen", FARM + Vector2(-17.0, 6.5), 2.0]]:
		_instance(entry[0], group, entry[1], _rng.randf() * TAU)
		_occupy(entry[1], entry[2])
	_checks["Cour de la ferme"] = FARM + Vector2(0, 1.5)


## Clôtures effondrées autour des parcelles (tronçons manquants, piquets de travers).
func _fences() -> void:
	var group := _add(_props, _node("Clotures"))
	for f in FIELDS:
		var rect: Rect2 = (f[0] as Rect2).grow(1.0)
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			var length := a.distance_to(b)
			var count := roundi(length / 2.0)
			var dir := (b - a) / length
			for i in count:
				if i == count / 2 or _rng.randf() < 0.3 + float(f[1]) * 0.3:
					continue
				var p := a + dir * (length / count) * (i + 0.5)
				if _dist("road", p) < 1.0 or _t_at(p) == T.WATER:
					continue
				var node := _instance("Fence", group, p, atan2(-dir.y, dir.x) + _rng.randf_range(-0.12, 0.12))
				node.scale = Vector3(length / count / 2.0, 1.0, 1.0)
				if _rng.randf() < 0.2:
					node.rotation.z = _rng.randf_range(-0.35, 0.35)


## Camp abandonné des Ol Mahum : palissade, tours de guet, tentes, feux, râteliers, cages.
func _abandoned_camp() -> void:
	var camp := _add(_props, _node("Camp_Ol_Mahum"))
	var features := [[CAMP_GATE_E, 3.6, "PalisadeGate", "Porte_Est"], [CAMP_GATE_W, 3.6, "PalisadeGate", "Poterne_Ouest"]]
	var first := _terrain_under.size()
	_fortification(camp, CAMP_WALL, CAMP, features, "WatchTowerWood", 1.6, "Palisade", 4.0, 0.3)
	# Sous les pieux et les tours de bois : terrain bloquant rendu en terre battue (le
	# "rampart" de _fortification se dessine en pavés, comme une muraille de pierre).
	for k in range(first, _terrain_under.size()):
		_terrain_under[k][1] = T.FORGE
	for v in CAMP_WALL:
		_reserve_disc(v, 3.0)
	_reserve_disc(CAMP_GATE_E, 4.0)
	_reserve_disc(CAMP_GATE_W, 4.0)
	var inner := _add(camp, _node("Cour"))
	# Grande tente du chef, à l'ouest, ouverte vers la porte est.
	var chief := Vector2(122.5, 197.5)
	_instance("TentLarge", inner, chief, atan2(1.0, 0.0)).name = "Tente_du_Chef"
	_occupy(chief, 5.5)
	_checks["Devant la tente du chef"] = chief + Vector2(8.0, 0.0)
	for c in [Vector2(122.5, 187.0), Vector2(122.5, 208.5)]:
		_instance("Cage", inner, c, _rng.randf_range(-0.3, 0.3))
		_occupy(c, 1.8)
	_instance("WeaponRack", inner, chief + Vector2(6.0, -6.0), PI / 2.0)
	_occupy(chief + Vector2(6.0, -6.0), 1.2)
	# Tentes en deux rangs face à la cour.
	var k := 0
	for x in [136.0, 147.0, 158.0]:
		for row in [[184.5, 0.0], [211.5, PI]]:
			var p := Vector2(x + (1.5 if row[0] > 200 else 0.0), row[0])
			_instance("Tent", inner, p, row[1] + _rng.randf_range(-0.15, 0.15)).name = "Tente_%d" % k
			_occupy(p, 3.0)
			k += 1
	# Feux de camp, râteliers d'armes.
	for c in [Vector2(146.5, 198.0), Vector2(158.0, 205.0)]:
		_instance("Campfire", inner, c, _rng.randf() * TAU)
		_occupy(c, 1.4)
	for entry in [[Vector2(141.5, 191.0), 0.0], [Vector2(152.0, 191.0), 0.0], [Vector2(160.5, 192.0), -PI / 2.0]]:
		_instance("WeaponRack", inner, entry[0], entry[1])
		_occupy(entry[0], 1.2)
	# Réserves du ravitailleur (angle sud-est) et bois (angle sud-ouest).
	var supplies := _add(inner, _node("Reserves"))
	for entry in [["Crate", Vector2(163.0, 212.5)], ["Crate", Vector2(164.2, 212.2)], ["Crate", Vector2(163.5, 213.0)],
			["Barrel", Vector2(161.0, 213.5)], ["Barrel", Vector2(160.2, 212.8)], ["Barrel", Vector2(164.0, 210.6)],
			["Crate", Vector2(163.5, 183.0)], ["Barrel", Vector2(162.2, 182.6)], ["LogPile", Vector2(117.5, 214.0)],
			["PlankPile", Vector2(117.0, 181.5)]]:
		_instance(entry[0], supplies, entry[1], _rng.randf() * TAU)
		_occupy(entry[1], 0.8)
	_checks["Cour du camp"] = Vector2(150.5, 198.5)
	_checks["Porte est du camp (dehors)"] = CAMP_GATE_E + Vector2(6.0, 0.0)
	_checks["Poterne ouest du camp (dehors)"] = CAMP_GATE_W + Vector2(-6.0, 0.0)
	# Tour de guet avancée sur le chemin, et bivouac de traînards à l'ouest, hors les murs.
	var outpost := Vector2(190.0, 182.0)
	_instance("WatchTowerWood", camp, outpost, atan2(-1.0, 0.6)).name = "Tour_de_guet_avancee"
	_occupy(outpost, 2.8)
	var bivouac := _add(camp, _node("Bivouac_des_trainards"))
	var bc := Vector2(95.0, 213.0)
	_instance("Campfire", bivouac, bc, 0.0)
	_occupy(bc, 1.4)
	for entry in [["Tent", bc + Vector2(-5.5, -1.0), PI / 2.0, 3.0], ["Tent", bc + Vector2(2.0, 5.5), PI, 3.0],
			["Barrel", bc + Vector2(4.0, -3.0), 0.0, 0.6], ["LogFallen", bc + Vector2(0.0, -4.0), 0.1, 1.8]]:
		_instance(entry[0], bivouac, entry[1], entry[2])
		_occupy(entry[1], entry[3])


## Embarcadère de la rive est : ponton, planches, bois, tonneaux.
func _landing() -> void:
	var group := _add(_props, _node("Embarcadere"))
	var base := _pier + Vector2(8.0, 0.0)
	for entry in [["PlankPile", base + Vector2(1.5, -4.0), 1.6], ["LogPile", base + Vector2(4.5, 4.0), 1.6],
			["Barrel", base + Vector2(-0.5, 3.6), 0.6], ["Barrel", base + Vector2(0.4, 4.3), 0.6],
			["Crate", base + Vector2(5.0, -3.5), 0.8]]:
		_instance(entry[0], group, entry[1], _rng.randf() * TAU)
		_occupy(entry[1], entry[2])
	_checks["Bout du ponton"] = _pier + Vector2(-5.0, 0.0)


## Île du lac : vieil autel des hommes-lézards, colonnes brisées.
func _island() -> void:
	var group := _add(_props, _node("Ile"))
	var altar := ISLAND + Vector2(2.0, -2.5)
	_instance("RuinAltar", group, altar, PI / 2.0 + PI).name = "Autel_de_l_ile"
	_occupy(altar, 2.6)
	for c in [ISLAND + Vector2(-2.5, -5.0), ISLAND + Vector2(5.0, 4.0)]:
		_instance("RuinColumnBroken", group, c, _rng.randf() * TAU)
		_occupy(c, 1.0)
	_checks["Île du lac"] = ISLAND + Vector2(-3.0, 1.5)


## Rochers, troncs, souches et arbres morts.
func _wilds() -> void:
	var group := _add(_props, _node("Nature"))
	var area := Rect2(12, 12, W - 24, H - 24)
	var out_camp := func(p: Vector2) -> bool: return _dist("camp", p) > 8.0 and _dist("field", p) > 2.0 and _dist("yard", p) > 2.0
	_scatter_props(group, ["RockLarge", "RockMedium", "RockMedium"], 26, area, 1.3, out_camp)
	var in_wood := func(p: Vector2) -> bool: return _dist("wood", p) < 3.0 or _dist("darkwood", p) < 3.0
	_scatter_props(group, ["LogFallen", "Stump", "Stump"], 18, area, 1.6, in_wood)
	var in_dark := func(p: Vector2) -> bool: return _dist("darkwood", p) < 0.0
	_scatter_props(group, ["TreeDead"], 10, area, 1.4, in_dark)
	var on_shore := func(p: Vector2) -> bool: return _dist("river", p) > 3.0 and _dist("river", p) < 9.0
	_scatter_props(group, ["LogFallen", "RockMedium", "Stump"], 10, area, 1.6, on_shore)


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	_sign_at(signs, "Teleporteur", R.FELLMERE_PORTAL_E + Vector2(-6.0, -5.5), [[R.AGONY, 0.0], ["Lac de Fellmere", 180.0]])
	_sign_at(signs, "Fourche", FORK + Vector2(4.5, -5.0), [[R.AGONY, 0.0], ["Champs de moisson", _heading(FORK, Vector2(207, 84))],
			["Camp abandonné", _heading(FORK, Vector2(211, 152))], ["Embarcadère", 180.0]])
	_sign_at(signs, "Ferme", FARM + Vector2(-9.5, 6.0), [["Rive ouest, île du lac", 170.0], [R.AGONY, _heading(FARM, FORK)]])
	_sign_at(signs, "Rive_ouest", Vector2(37.0, 118.0), [["Île du lac", 0.0], ["Champs de moisson", -60.0], ["Camp abandonné", 80.0]])
	_sign_at(signs, "Camp", Vector2(180.0, 200.5), [["Camp abandonné", 180.0], [R.AGONY, -60.0]])


# ---------------------------------------------------------------------------
# Outils de pose (même jeu d'outils que generate_ruins_of_agony.gd)
# ---------------------------------------------------------------------------

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
	if [T.WATER, T.BRIDGE, T.THICKET, T.REEDS, T.CROP].has(_t_at(p)):
		return false
	if _dist("road", p) < radius + 1.5 or _dist("river", p) < radius + 1.0 or _near_check(p, radius + 2.5):
		return false
	if _reserved.has(cell):
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
	var tree_prob := func(x: int, z: int) -> float:
		var p := Vector2(x + 0.5, z + 0.5)
		if blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)):
			return 0.0
		if _dist("road", p) < 2.5 or _dist("river", p) < 1.5 or _dist("open", p) < 0.0:
			return 0.0
		if _dist("camp", p) < 7.0 or _dist("field", p) < 1.5 or _dist("yard", p) < 3.0 or _near_check(p, 3.0):
			return 0.0
		if _dist("island", p) < 0.0:
			return 0.07
		var dark := _dist("darkwood", p)
		if dark < 0.0:
			return lerpf(0.09, 0.19, clampf(-dark / 8.0, 0.0, 1.0))
		var wood := _dist("wood", p)
		if wood < 0.0:
			return lerpf(0.16, 0.42, clampf(-wood / 6.0, 0.0, 1.0))
		var edge := float(_edge(x, z))
		return lerpf(0.006, 0.32, clampf(1.0 - (edge - 7.0) / 16.0, 0.0, 1.0))
	# Bois sombres : quelques arbres morts d'abord.
	var dead := _scatter(T.DEAD_TREE, [T.FOREST, T.DARK_GRASS], func(x: int, z: int) -> float:
		if _dist("darkwood", Vector2(x + 0.5, z + 0.5)) > -2.0 or tree_prob.call(x, z) <= 0.0:
			return 0.0
		return 0.06
	, 1)
	var trees := _scatter(T.TREE, [T.GRASS, T.DARK_GRASS, T.FOREST], tree_prob)
	print("Arbres : %d (+ %d morts)" % [trees, dead])


func _configure_ground(ground: TerrainGround) -> void:
	ground.shader_overrides = {
		"grass_tint": Color(0.66, 0.70, 0.60),
		"dark_grass_tint": Color(0.50, 0.54, 0.47),
		"forest_tint": Color(0.68, 0.66, 0.58),
		"dirt_tint": Color(0.72, 0.64, 0.54),
	}
	ground.water_overrides = {
		"deep_color": Color(0.05, 0.13, 0.17),
		"shallow_color": Color(0.20, 0.32, 0.32),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.grass_density = 0.55
	vegetation.forest_grass_density = 0.2
	vegetation.dead_tree_ratio = 0.06
	vegetation.rock_density = 0.015
	vegetation.outer_dead_ratio = 0.06
