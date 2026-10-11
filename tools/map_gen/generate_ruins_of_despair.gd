extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Ruins_of_Despair.tscn (240 x 220 cases), les
## ruines du Désespoir, au sud de Gludio, sur le modèle des Ruins of Despair de Lineage 2.
## Zone sauvage (ni ville ni zone de paix), sans PNJ ; monstres de Lineage 2 (voir _hunting_grounds). Relancer ce script ÉCRASE
## la scène ; ensuite l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Ruins_of_Despair.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - une lande désolée : terre nue, sol maudit, herbe flétrie, bois d'arbres morts,
##     arbres tordus des marais ; forêt et fourrés le long des bords ;
##   - la route du téléporteur du nord (Gludio) descend vers le sud, gardée par deux
##     statues, puis oblique vers l'est et franchit la rivière sur un pont de pierre
##     jusqu'au téléporteur de l'est (Dion) ;
##   - la rivière descend du nord-est et longe l'est de la carte, vers Dion ;
##   - à l'ouest, la forteresse en ruine : anneau de murailles éventrées flanqué de tours
##     effondrées, une arche pour porte à l'est ; dans la cour, sur le sol maudit, le crâne
##     géant domine l'autel aux runes rouges, entouré de statues et de colonnes ;
##   - des maisons éboulées le long de la route, un champ de gravats au sud, statues et
##     arches isolées dans la lande ;
##   - poteaux indicateurs près des téléporteurs, du pont et du chemin de la forteresse.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_ruins_of_despair.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")

const ROAD_HALF := 2.5
## Route de Gludio (nord) à Dion (est), prolongée au-delà des bords ; tronçon droit est-ouest
## au droit du pont.
const ROAD := [Vector2(120.5, -8), Vector2(120.5, 5.5), Vector2(120.5, 24), Vector2(117, 46), Vector2(111.5, 70),
		Vector2(112, 95), Vector2(121, 117), Vector2(137, 136), Vector2(158, 147), Vector2(178, 150.5), Vector2(190, 150.5),
		Vector2(203, 150.5), Vector2(216, 150.5), R.DESPAIR_PORTAL_E, Vector2(248, 150.5)]
## Rivière venue du nord-est, tronçon droit nord-sud au droit du pont.
const RIVER := [Vector2(232, -12), Vector2(220, 14), Vector2(205, 38), Vector2(197, 62), Vector2(198, 88),
		Vector2(201.5, 112), Vector2(203, 132), Vector2(203, 150.5), Vector2(203, 169), Vector2(207, 190), Vector2(216, 232)]
const BRIDGE := Vector2(203.0, 150.5)
## Forteresse en ruine (anneau de murailles) et sa cour.
const FORT := Vector2(68.5, 122.5)
const FORT_R := 30.0
const FORT_SIDES := 20
const COURT_R := 17.0
## Bois morts : [centre, rayon].
const DEADWOODS := [[Vector2(36, 40), 20.0], [Vector2(40, 194), 16.0], [Vector2(160, 200), 14.0], [Vector2(165, 45), 16.0],
		[Vector2(224, 96), 8.0], [Vector2(224, 196), 9.0], [Vector2(98, 204), 9.0], [Vector2(18, 106), 8.0],
		[Vector2(80, 30), 9.0]]
## Champ de gravats (sud).
const RUBBLE_FIELD := Vector2(112.0, 183.0)

## Bruit de "taches" (dallages troués, terre nue).
var _patch := FastNoiseLite.new()
## Props posés : [position, rayon] (évitement mutuel des props épars).
var _occupied: Array = []


func _setup() -> void:
	W = R.DESPAIR_SIZE.x
	H = R.DESPAIR_SIZE.y
	SEED = 20261012
	MAP_ID = R.DESPAIR_ID
	MAP_NAME = R.DESPAIR
	DESCRIPTION = "Une lande désolée au sud de Gludio : terre nue, arbres morts et les murailles éventrées d'une forteresse où un crâne géant veille sur un autel maudit. La route descend de Gludio, au nord, puis franchit la rivière sur un pont de pierre vers la ville de Dion, à l'est."
	OUT_PATH = "res://scenes/maps/Ruins_of_Despair.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = false
	BIOME = MapData.Biome.FOREST
	# Sur la route, une douzaine de cases après le téléporteur venu de Gludio.
	PLAYER_SPAWN = Vector2(120.5, 18.5)
	CARVE_TERRAIN = T.DIRT
	_patch.seed = SEED + 3
	_patch.frequency = 0.16


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Lande : herbe flétrie, grandes plaques de terre nue.
	var barren := FastNoiseLite.new()
	barren.seed = SEED + 11
	barren.frequency = 0.02
	for z in H:
		for x in W:
			var n := barren.get_noise_2d(x, z)
			if n > 0.08:
				_terrain[z * W + x] = T.DIRT
			elif n < -0.22:
				_terrain[z * W + x] = T.DARK_GRASS
	# Sol maudit autour de la forteresse et par taches dans la lande.
	_stamp_blob("cursed", FORT, FORT_R + 6.0)
	for c in [[Vector2(152, 170), 9.0], [Vector2(56, 178), 7.0], [Vector2(150, 92), 6.0], [Vector2(30, 76), 6.0]]:
		_stamp_blob("cursed", c[0], c[1])
	_paint_field("cursed", 0.0, T.DANGER, 2.0)

	# Bois morts (sol forestier ; arbres plantés après les props).
	for g in DEADWOODS:
		_stamp_blob("deadwood", g[0], g[1])
	_paint_field("deadwood", 0.0, T.FOREST, 1.5)

	# Rivière et pont de la route de Dion (pont déclaré d'abord : la rivière s'y resserre).
	_bridge(BRIDGE, "x", true, "Pont_de_Dion")
	_river(RIVER, 4.2)

	# Route, abords des téléporteurs, chemin de la forteresse.
	_road(ROAD, ROAD_HALF, T.PAVED, 4.0, 0.35)
	for portal in [R.DESPAIR_PORTAL_N, R.DESPAIR_PORTAL_E]:
		_paint_disc(portal, 4.2, T.PAVED, [T.WATER])
		_stamp("open", portal, 10.0, 20.0)
	_road([Vector2(121, 117), Vector2(108, 120), Vector2(FORT.x + FORT_R + 2.0, FORT.y), Vector2(FORT.x + COURT_R, FORT.y)],
			1.4, T.DIRT, 2.0, 0.4)
	# Sentier vers le champ de gravats.
	_road([Vector2(137, 136), Vector2(128, 152), Vector2(118, 168), RUBBLE_FIELD], 1.2, T.DIRT, 1.5, 0.45)

	_edge_band(7, T.THICKET, [T.GRASS, T.DARK_GRASS, T.DIRT, T.FOREST, T.DANGER])


# ---------------------------------------------------------------------------
# 2. Ruines, props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	var ruins := _add(_props, _node("Ruines"))
	_fortress(ruins)
	_roadside_ruins(ruins)
	_rubble_field(ruins)
	_wilds()
	_place_signs()
	_portal("N", R.DESPAIR_PORTAL_N, R.GLUDIO_ID, R.GLUDIO_PORTAL_S, R.GLUDIO)
	_portal("E", R.DESPAIR_PORTAL_E, R.DION_ID, R.DION_PORTAL_W, R.DION)
	_checks["Pont de Dion"] = BRIDGE
	_hunting_grounds()


## Monstres des Ruins of Despair de Lineage 2 (niveaux 15-25) : squelettes et zombies dans la
## forteresse et le champ de gravats, imps et chauves-souris dans les bois morts, bugbears
## Veelan au sud-ouest, le boss Zombie Lord Crowl dans la cour de la forteresse.
func _hunting_grounds() -> void:
	_monster_zone("Despair_Forteresse", FORT, FORT_R - 2.0, M.mix([["Shield Skeleton", 2], ["Skeleton Infantryman", 2],
			["Zombie Soldier", 2], ["Zombie Warrior", 1]]), 16)
	_monster_zone("Despair_Gravats", RUBBLE_FIELD, 22.0, M.mix([["Zombie Soldier", 2], ["Zombie Warrior", 1], ["Shield Skeleton", 1]]), 12)
	_monster_zone("Despair_BoisMorts", DEADWOODS[0][0], 22.0, M.mix([["Ruin Imp", 2], ["Scavenger Bat", 2], ["Ruin Bat", 1]]), 12)
	_monster_zone("Despair_LandeEst", DEADWOODS[3][0], 20.0, M.mix([["Scavenger Bat", 2], ["Ruin Imp", 1], ["Ruin Imp Elder", 1]]), 10)
	_monster_zone("Despair_LandeOuest", Vector2(40, 75), 18.0, M.mix([["Shield Skeleton", 2], ["Skeleton Infantryman", 1], ["Ruin Imp", 1]]), 8)
	_monster_zone("Despair_Bugbears", DEADWOODS[1][0], 20.0, M.mix([["Veelan Bugbear", 2], ["Veelan Bugbear Warrior", 1]]), 9)
	_monster_zone("Despair_BoisSud", DEADWOODS[2][0], 16.0, M.mix([["Ruin Bat", 2], ["Ruin Imp Elder", 1]]), 8)
	_monster_zone("Despair_ZombieLordCrowl", FORT, 6.0, M.mix([["Zombie Lord Crowl", 1]]), 1, 3600)


## Forteresse : anneau de murailles éventrées (tours = colonnes brisées massives), porte en
## arche à l'est ; cour au sol maudit, crâne géant au nord tourné vers l'autel, statues et
## couronne de colonnes.
func _fortress(parent: Node) -> void:
	var group := _add(parent, _node("Forteresse"))
	var walls := _add(group, _node("Murailles"))
	var step := TAU / FORT_SIDES
	var verts := []
	for k in FORT_SIDES:
		var a := step * k + step / 2.0
		verts.append(FORT + Vector2(cos(a), sin(a)) * FORT_R)
	for k in FORT_SIDES:
		var v: Vector2 = verts[k]
		if k % 2 == 0 or _rng.randf() < 0.5:
			_tower(walls, v)
		else:
			var col := _instance("RuinColumn", walls, v, _rng.randf() * TAU)
			col.scale = Vector3.ONE * 1.25
			_occupy(v, 1.2)
		var b: Vector2 = verts[(k + 1) % FORT_SIDES]
		var dir := (b - v).normalized()
		if k == FORT_SIDES - 1:
			# Porte de l'est : arche au milieu du pan, passage est-ouest.
			var mid := (v + b) / 2.0
			_arch(group, mid, Vector2(1, 0), "Porte_Forteresse")
			_wall_run(walls, "RuinWall", 4.0, v + dir * 1.4, mid - dir * 3.2)
			_wall_run(walls, "RuinWall", 4.0, mid + dir * 3.2, b - dir * 1.4)
			continue
		_broken_wall(walls, v + dir * 1.4, b - dir * 1.4, 0.32)
	_stamp("ruin", FORT, FORT_R + 1.0, FORT_R + 12.0)
	_stamp("open", FORT, FORT_R + 3.0, FORT_R + 12.0)
	_reserve_disc(FORT, FORT_R + 2.0)

	# Cour : dallage troué sur le sol maudit.
	_ruin_floor_blob(FORT, COURT_R, 0.4)
	var skull := FORT + Vector2(0, -15.0)
	_instance("RuinSkull", group, skull, 0.0).name = "Crane_Geant"
	_occupy(skull, 5.0)
	_checks["Devant le crâne géant"] = skull + Vector2(0, 7.0)
	var altar := FORT + Vector2(0, 3.5)
	_instance("RuinAltar", group, altar, PI).name = "Autel_Maudit"
	_occupy(altar, 3.6)
	_checks["Devant l'autel maudit"] = altar + Vector2(0, -5.5)
	_checks["Derrière l'autel"] = altar + Vector2(0, 6.0)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := FORT + Vector2(s.x * 12.5, 3.5 + s.y * 9.0)
		var face := (altar - p).normalized()
		_instance("RuinStatue", group, p, atan2(face.x, face.y))
		_occupy(p, 2.4)
	# Couronne de colonnes, ouverte vers le crâne (nord) et la porte (est).
	for k in 14:
		var a := TAU * k / 14.0
		var deg := rad_to_deg(a)
		if (deg > 235.0 and deg < 305.0) or deg < 20.0 or deg > 340.0:
			continue
		var p := FORT + Vector2(cos(a), sin(a)) * (COURT_R + 2.5)
		var r := _rng.randf()
		if r < 0.45:
			_column(group, p, "RuinColumn")
		elif r < 0.85:
			_column(group, p, "RuinColumnBroken")
	for p in [FORT + Vector2(-9, 15), FORT + Vector2(14, -10)]:
		_instance("RuinColumnFallen", group, p, _rng.randf() * PI)
		_occupy(p, 2.6)
	# Éboulis le long des murailles, dehors comme dedans.
	for k in 9:
		var a := TAU * (k + 0.5) / 9.0 + 0.3
		var rr := FORT_R + (4.0 if k % 2 == 0 else -4.5)
		_rubble_patch(FORT + Vector2(cos(a), sin(a)) * rr, _rng.randf_range(1.5, 2.5))
	_checks["Porte de la forteresse (dehors)"] = FORT + Vector2(FORT_R + 4.0, 0)


## Maisons éboulées, statues gardiennes et arches le long de la route ; une ruine sur la
## rive est.
func _roadside_ruins(parent: Node) -> void:
	var group := _add(parent, _node("Bord_de_route"))
	# Deux statues gardent l'entrée de la route, face à la chaussée.
	for s in [-1.0, 1.0]:
		var p := Vector2(119.3 + s * 6.8, 34.0)
		_instance("RuinStatue", group, p, atan2(-s, 0.0)).name = "Gardien_%s" % ("O" if s < 0 else "E")
		_occupy(p, 2.4)
	_ruin_building(group, Vector2(142.5, 72.5), Vector2(12, 9), Vector2(-1, 0), "Maison_1")
	_ruin_building(group, Vector2(161.5, 98.5), Vector2(14, 10), Vector2(0, 1), "Maison_2")
	_ruin_building(group, Vector2(146.5, 115.5), Vector2(10, 8), Vector2(-1, 0), "Maison_3")
	_ruin_building(group, Vector2(88.5, 62.5), Vector2(12, 10), Vector2(1, 0), "Maison_4", 0.4)
	_ruin_building(group, Vector2(223.5, 118.5), Vector2(10, 8), Vector2(-1, 0), "Maison_Rive")
	_arch(group, Vector2(46.5, 72.0), Vector2(0, 1), "Arche_Nord_Ouest")
	_arch(group, Vector2(176.0, 124.0), Vector2(1, 0.3), "Arche_Est")
	for c in [Vector2(135, 80), Vector2(155, 108), Vector2(97, 70), Vector2(170, 88)]:
		_rubble_patch(c, _rng.randf_range(1.5, 2.4))
	var st := Vector2(184.5, 168.5)
	_instance("RuinStatue", group, st, atan2(-0.5, -1.0)).name = "Statue_du_Pont"
	_occupy(st, 2.4)


## Champ de gravats au sud : maisons rasées, murets, fûts couchés, éboulis.
func _rubble_field(parent: Node) -> void:
	var group := _add(parent, _node("Champ_de_gravats"))
	_ruin_building(group, RUBBLE_FIELD + Vector2(-14, -2), Vector2(12, 10), Vector2(1, 0), "Maison_Rasee_1", 0.45)
	_ruin_building(group, RUBBLE_FIELD + Vector2(14, 8), Vector2(10, 8), Vector2(0, -1), "Maison_Rasee_2", 0.45)
	_ruin_floor_blob(RUBBLE_FIELD, 6.0, 0.2)
	_stamp_blob("ruin", RUBBLE_FIELD, 16.0)
	_column(group, RUBBLE_FIELD + Vector2(2, -3), "RuinColumnBroken")
	for k in 7:
		var a := TAU * k / 7.0 + 0.4
		_rubble_patch(RUBBLE_FIELD + Vector2(cos(a), sin(a)) * _rng.randf_range(10.0, 17.0), _rng.randf_range(1.4, 2.6))
	var area := Rect2(RUBBLE_FIELD - Vector2(22, 16), Vector2(44, 30))
	var near := func(p: Vector2) -> bool: return p.distance_to(RUBBLE_FIELD) < 22.0
	_scatter_props(group, ["RuinRubble"], 8, area, 1.7, near)
	_scatter_props(group, ["RuinColumnFallen"], 3, area, 2.7, near)
	_scatter_props(group, ["RuinWallLow"], 3, area, 2.4, near)
	_checks["Champ de gravats"] = RUBBLE_FIELD


## Lande : arbres morts et tordus, colonnes isolées, murets, éboulis, rochers.
func _wilds() -> void:
	var group := _add(_props, _node("Lande"))
	var area := Rect2(12, 12, W - 24, H - 24)
	var out_ruins := func(p: Vector2) -> bool: return _dist("ruin", p) > 5.0
	_scatter_props(group, ["TreeDead", "MarshTree", "MarshTreeSmall"], 55, area, 0.8, out_ruins)
	_scatter_props(group, ["RuinColumnBroken", "RuinColumnBroken", "RuinColumn"], 12, area, 1.0, out_ruins)
	_scatter_props(group, ["RuinWallLow"], 7, area, 2.4, out_ruins)
	_scatter_props(group, ["RuinRubble"], 16, area, 1.7, out_ruins)
	_scatter_props(group, ["RuinColumnFallen"], 5, area, 2.7, out_ruins)
	_scatter_props(group, ["RockLarge", "RockMedium", "RockMedium"], 24, area, 1.3, out_ruins)
	_scatter_props(group, ["LogFallen", "Stump"], 10, area, 1.6, func(p: Vector2) -> bool: return _dist("deadwood", p) < 3.0)
	_scatter_props(group, ["CartBroken"], 1, Rect2(150, 140, 30, 20), 2.5)


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	_sign_at(signs, "Teleporteur_N", R.DESPAIR_PORTAL_N + Vector2(6.0, 6.0), [[R.GLUDIO, 270.0], [R.DION, 80.0]])
	_sign_at(signs, "Forteresse", Vector2(125.5, 111.0), [["Forteresse en ruine", 175.0], [R.GLUDIO, 265.0], [R.DION, 45.0]])
	_sign_at(signs, "Pont", BRIDGE + Vector2(-13.0, -5.5), [[R.DION, 0.0], [R.GLUDIO, 190.0]])
	_sign_at(signs, "Teleporteur_E", R.DESPAIR_PORTAL_E + Vector2(-6.0, -5.5), [[R.DION, 0.0], [R.GLUDIO, 180.0]])
	_sign_at(signs, "Gravats", Vector2(142.5, 132.5), [["Champ de gravats", 120.0], [R.GLUDIO, 240.0], [R.DION, 20.0]])


# ---------------------------------------------------------------------------
# Kit de ruines (même jeu d'outils que generate_ruins_of_agony.gd)
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
	var skip := func(x: int, z: int) -> bool:
		var p := Vector2(x + 0.5, z + 0.5)
		return blocked.has(Vector2i(x, z)) or _reserved.has(Vector2i(x, z)) or _dist("road", p) < 2.5 \
				or _dist("river", p) < 1.5 or _dist("open", p) < 0.0 or _dist("ruin", p) < 4.0 or _near_check(p, 3.0)
	# Arbres morts : bois morts, lisières, quelques-uns épars dans la lande.
	var dead := _scatter(T.DEAD_TREE, [T.GRASS, T.DARK_GRASS, T.DIRT, T.FOREST, T.DANGER], func(x: int, z: int) -> float:
		if skip.call(x, z):
			return 0.0
		var wood := _dist("deadwood", Vector2(x + 0.5, z + 0.5))
		if wood < 0.0:
			return lerpf(0.08, 0.2, clampf(-wood / 6.0, 0.0, 1.0))
		return lerpf(0.008, 0.12, clampf(1.0 - (float(_edge(x, z)) - 7.0) / 14.0, 0.0, 1.0)), 1)
	# Arbres encore debout (une bonne part dessinée morte, voir dead_tree_ratio).
	var trees := _scatter(T.TREE, [T.GRASS, T.DARK_GRASS, T.FOREST], func(x: int, z: int) -> float:
		if skip.call(x, z):
			return 0.0
		if _dist("deadwood", Vector2(x + 0.5, z + 0.5)) < 0.0:
			return 0.06
		return lerpf(0.002, 0.22, clampf(1.0 - (float(_edge(x, z)) - 7.0) / 12.0, 0.0, 1.0)), 1)
	print("Arbres morts : %d, arbres : %d" % [dead, trees])


func _configure_ground(ground: TerrainGround) -> void:
	# Herbe flétrie, terre sèche, pavés gris éteints.
	ground.paved_tint = Color(0.56, 0.55, 0.54)
	ground.paved_desaturate = 0.7
	ground.shader_overrides = {
		"grass_tint": Color(0.56, 0.52, 0.60),
		"dark_grass_tint": Color(0.44, 0.41, 0.48),
		"forest_tint": Color(0.44, 0.43, 0.48),
		"dirt_tint": Color(0.52, 0.55, 0.62),
	}
	ground.water_overrides = {
		"deep_color": Color(0.05, 0.09, 0.08),
		"shallow_color": Color(0.21, 0.25, 0.19),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.foliage_tint = Color(0.8, 0.7, 0.48)
	vegetation.grass_density = 0.28
	vegetation.forest_grass_density = 0.12
	vegetation.bush_density = 0.015
	vegetation.rock_density = 0.03
	vegetation.dead_tree_ratio = 0.55
	vegetation.outer_density = 0.32
	vegetation.outer_dead_ratio = 0.5
