extends "res://tools/map_gen/MapGenBase.gd"
## Outil hors-ligne : génère res://scenes/maps/Execution_Grounds.tscn (280 x 240 cases), le
## lieu d'exécution de Dion, à l'est de la ville, sur le modèle des Execution Grounds de
## Lineage 2 (niveaux 26-35). Zone sauvage (ni ville ni zone de paix), cul-de-sac : un seul
## téléporteur, à l'ouest, vers Dion ; monstres de Lineage 2 (voir _hunting_grounds).
## Relancer ce script ÉCRASE la scène ; ensuite l'exporter vers le serveur :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##       res://scenes/maps/Execution_Grounds.tscn <backend>/src/main/resources/data/maps/
##
## Disposition (voir tools/map_gen/GludioRegion.gd pour la région) :
##   - une terre maudite où Dion a exécuté ses criminels pendant un siècle : herbe flétrie
##     gris-brun, terre nue, plaques d'éboulis, sol maudit aux endroits les plus funestes,
##     bois d'arbres morts tordus ; fourrés et bois morts le long des bords ;
##   - la vieille route pavée, usée, part du téléporteur de l'ouest (Dion) et file vers
##     l'est jusqu'à la place d'exécution, au milieu de la carte ; des gibets la bordent ;
##   - près de l'entrée, au nord de la route, le poste des gardiens : enclos palissadé
##     (porte au sud), maison de garde, tour de guet, feu de camp, râtelier d'armes ;
##     les gardiens Roderik et Endrigo s'y tiennent ;
##   - la place d'exécution : esplanade dallée et trouée, l'échafaud au nord, des gibets,
##     des cages et des charrettes brisées, ceinte d'un muret en ruine ; le boss Guillotine
##     y veille ;
##   - au nord-ouest de la place, la prison en ruine (cages au fond) ; au sud-ouest, le
##     tribunal effondré et sa statue ;
##   - au sud-est, le champ des sépultures des suppliciés : rangées irrégulières de tombes
##     dans un enclos de murets, la chapelle funéraire en ruine au fond (boss Revenant of
##     Sir Calibus) ;
##   - au nord-est, la carrière : sol de terre, éboulis, gros rochers (golems de granit) ;
##   - à l'est, au fond, le bois des Pendus (Hangman Trees), sur le sol maudit ;
##   - poteaux indicateurs près du téléporteur et aux embranchements.
##
## Lancer avec :
##   godot --headless --path . --script res://tools/map_gen/generate_execution_grounds.gd

const R := preload("res://tools/map_gen/GludioRegion.gd")
const M := preload("res://tools/map_gen/L2Monsters.gd")

## Gardiens du lieu d'exécution (backend data/npc).
const RODERIK_ID := "e72933b2-d487-42e7-ba42-49773a84ca95"
const ENDRIGO_ID := "dab6ea7f-a69f-4da6-bd9b-71bcb980088f"

const ROAD_HALF := 2.5
const PATH_HALF := 1.5
## Vieille route, du téléporteur de l'ouest (Dion) à la place d'exécution, prolongée
## au-delà du bord ouest.
const ROAD := [Vector2(-8, 120.5), R.EXECUTION_PORTAL_W, Vector2(22, 120.5), Vector2(42, 121), Vector2(62, 118.5),
		Vector2(84, 120), Vector2(104, 118.5), Vector2(122, 118), Vector2(134, 118)]
## Poste des gardiens : enclos palissadé (porte au milieu du côté sud).
const POST := Rect2(33, 89, 26, 21)
const POST_GATE := Vector2(46.0, 110.0)
## Place d'exécution et échafaud.
const SQUARE := Vector2(150.5, 118.5)
const SQUARE_R := 16.0
const SCAFFOLD := Vector2(150.5, 108.5)
## Prison (nord-ouest de la place) et tribunal (sud-ouest), en ruine.
const PRISON := Vector2(122.5, 76.5)
const PRISON_SIZE := Vector2(26, 16)
const COURT := Vector2(112.5, 166.5)
const COURT_SIZE := Vector2(22, 14)
## Croisée des chemins de la prison et du tribunal, sur la route.
const CROSS := Vector2(104.0, 118.5)
## Champ des sépultures (enclos) et chapelle funéraire au fond.
const BURIAL := Rect2(174, 160, 52, 36)
const BURIAL_GATE := Vector2(200.0, 160.0)
const CHAPEL := Vector2(200.5, 206.5)
const CHAPEL_SIZE := Vector2(18, 12)
## Carrière (nord-est).
const QUARRY := Vector2(226.0, 54.0)
const QUARRY_R := 20.0
## Bois des Pendus (est, au fond).
const HANGMAN := Vector2(248.0, 130.0)
const HANGMAN_R := 21.0
## Bois morts clairsemés : [centre, rayon].
const DEADWOODS := [[Vector2(165, 40), 17.0], [Vector2(62, 192), 14.0], [Vector2(40, 48), 14.0],
		[Vector2(86, 70), 11.0], [Vector2(150, 205), 12.0], [Vector2(262, 205), 10.0]]

## Bruit de "taches" (dallages troués, usure de la route).
var _patch := FastNoiseLite.new()
## Props posés : [position, rayon] (évitement mutuel des props épars).
var _occupied: Array = []


func _setup() -> void:
	W = R.EXECUTION_SIZE.x
	H = R.EXECUTION_SIZE.y
	SEED = 20261022
	MAP_ID = R.EXECUTION_ID
	MAP_NAME = R.EXECUTION
	DESCRIPTION = "Le lieu d'exécution de Dion, à l'est de la ville : une terre maudite et flétrie où l'échafaud et les gibets se dressent encore au milieu des ruines de la prison et du tribunal. Au-delà s'étendent le champ des sépultures des suppliciés, la carrière des golems et le bois des Pendus ; seule la vieille route ramène vers Dion, à l'ouest."
	OUT_PATH = "res://scenes/maps/Execution_Grounds.tscn" if OS.get_environment("MAPGEN_OUT").is_empty() else OS.get_environment("MAPGEN_OUT")
	IS_TOWN = false
	BIOME = MapData.Biome.FOREST
	# Sur la route, une douzaine de cases après le téléporteur venu de Dion.
	PLAYER_SPAWN = R.EXECUTION_PORTAL_W + Vector2(12.0, 0.0)
	CARVE_TERRAIN = T.DIRT
	_patch.seed = SEED + 3
	_patch.frequency = 0.16


# ---------------------------------------------------------------------------
# 1. Plan au sol
# ---------------------------------------------------------------------------

func _layout() -> void:
	# Terre flétrie : herbe sombre, grandes plaques de terre nue, un peu d'herbe sèche.
	var barren := FastNoiseLite.new()
	barren.seed = SEED + 11
	barren.frequency = 0.021
	for z in H:
		for x in W:
			var n := barren.get_noise_2d(x, z)
			if n > 0.2:
				_terrain[z * W + x] = T.DIRT
			elif n > -0.3:
				_terrain[z * W + x] = T.DARK_GRASS

	# Bois morts et bois des Pendus (sol forestier ; arbres plantés après les props).
	for g in DEADWOODS:
		_stamp_blob("deadwood", g[0], g[1])
	_stamp_blob("deadwood", HANGMAN, HANGMAN_R)
	_paint_field("deadwood", 0.0, T.FOREST, 1.5)

	# Carrière : sol de terre nue.
	_stamp_blob("quarry", QUARRY, QUARRY_R)
	_paint_field("quarry", 2.0, T.DIRT, 2.0)

	# Sol maudit : sous l'échafaud, au cœur des sépultures, dans le bois des Pendus.
	_stamp_blob("cursed", SCAFFOLD + Vector2(0, 2.0), 8.0)
	_stamp_blob("cursed", BURIAL.get_center() + Vector2(0, 4.0), 9.0)
	_stamp_blob("cursed", HANGMAN, 8.0)
	_stamp_blob("cursed", Vector2(76, 156), 4.5)
	_paint_field("cursed", 0.0, T.DANGER, 1.5)

	# Vieille route pavée, usée (pavés arrachés par endroits), abords du téléporteur.
	_road(ROAD, ROAD_HALF, T.PAVED, 4.0, 0.35)
	for i in W * H:
		if _terrain[i] == T.PAVED and _patch.get_noise_2d((i % W) * 1.2, (i / W) * 1.2) < -0.38:
			_terrain[i] = T.DIRT
	_paint_disc(R.EXECUTION_PORTAL_W, 4.2, T.PAVED)
	_stamp("open", R.EXECUTION_PORTAL_W, 10.0, 20.0)

	# Chemins de terre : poste des gardiens, prison, tribunal, carrière, sépultures.
	_road([Vector2(46, 121), Vector2(46, 112)], PATH_HALF, T.DIRT, 2.0, 0.3)
	_road([CROSS, Vector2(108, 108), Vector2(116, 96), Vector2(PRISON.x, PRISON.y + PRISON_SIZE.y / 2.0 + 3.0)],
			PATH_HALF, T.DIRT, 2.0, 0.4)
	_road([CROSS, Vector2(105, 132), Vector2(109, 146), Vector2(COURT.x, COURT.y - COURT_SIZE.y / 2.0 - 3.0)],
			PATH_HALF, T.DIRT, 2.0, 0.4)
	_road([SQUARE + Vector2(12, -11), Vector2(176, 92), Vector2(194, 76), Vector2(206, 64)], PATH_HALF, T.DIRT, 2.0, 0.4)
	_road([SQUARE + Vector2(12, 11), Vector2(174, 142), Vector2(190, 151), BURIAL_GATE + Vector2(0, -4.0)],
			PATH_HALF, T.DIRT, 2.0, 0.4)

	# Place d'exécution : terre battue, dallage troué.
	_paint_disc(SQUARE, SQUARE_R + 2.0, T.DIRT)
	_ruin_floor_blob(SQUARE, SQUARE_R, 0.4)
	_paint_field("cursed", -2.0, T.DANGER, 1.0)
	_stamp("open", SQUARE, SQUARE_R + 4.0, SQUARE_R + 12.0)
	_stamp("ruin", SQUARE, SQUARE_R + 5.0, SQUARE_R + 14.0)

	# Poste des gardiens : cour en terre battue.
	_paint_rect(POST.grow(-1.0), T.DIRT)
	_stamp_rect("open", POST, 6.0)

	# Champ des sépultures : herbe sombre (sol maudit au cœur), allée de terre vers la chapelle.
	_paint_rect(BURIAL, T.DARK_GRASS, [T.DANGER])
	_paint_rect(Rect2(BURIAL_GATE.x - 2.0, BURIAL.position.y, 4.0, CHAPEL.y - CHAPEL_SIZE.y / 2.0 - BURIAL.position.y), T.DIRT)

	_edge_band(6, T.THICKET, [T.GRASS, T.DARK_GRASS, T.DIRT, T.FOREST, T.DANGER])


# ---------------------------------------------------------------------------
# 2. Props et marqueurs
# ---------------------------------------------------------------------------

func _decorate() -> void:
	_wardens_post()
	var ruins := _add(_props, _node("Ruines"))
	_execution_square(ruins)
	_prison(ruins)
	_court(ruins)
	_burial_field(ruins)
	_quarry()
	_road_gibbets()
	_wilds()
	_place_signs()
	_portal("O", R.EXECUTION_PORTAL_W, R.DION_ID, R.DION_PORTAL_E, R.DION)
	_checks["Bois des Pendus"] = HANGMAN + Vector2(-HANGMAN_R + 4.0, 0)
	_hunting_grounds()


## Monstres des Execution Grounds de Lineage 2 (niveaux 26-35), plus forts vers l'est :
## spectres et pleureuses à l'ouest, goules de Neer dans la prison et sur la place,
## basilics au tribunal, golems de granit à la carrière, goules et chercheurs morts dans le
## champ des sépultures, arbres pendus au fond ; boss Guillotine sur la place d'exécution,
## Revenant of Sir Calibus dans la chapelle funéraire.
func _hunting_grounds() -> void:
	_monster_zone("Exec_Lande", Vector2(78, 160), 22.0, M.mix([["Specter", 3], ["Sorrow Maiden", 2]]), 10)
	_monster_zone("Exec_BoisOuest", Vector2(84, 70), 20.0, M.mix([["Specter", 2], ["Sorrow Maiden", 2], ["Neer Crawler", 1]]), 9)
	_monster_zone("Exec_Prison", PRISON, 20.0, M.mix([["Neer Crawler", 2], ["Neer Ghoul Berserker", 2], ["Strain", 1]]), 12)
	_monster_zone("Exec_BoisNord", DEADWOODS[0][0], 20.0, M.mix([["Neer Ghoul Berserker", 2], ["Specter", 1], ["Ghoul", 1]]), 10)
	_monster_zone("Exec_Place", SQUARE, 22.0, M.mix([["Neer Ghoul Berserker", 2], ["Strain", 2], ["Ghoul", 1],
			["Sorrow Maiden", 1]]), 14)
	_monster_zone("Exec_Tribunal", COURT, 20.0, M.mix([["Amber Basilisk", 2], ["Strain", 2], ["Neer Crawler", 1]]), 10)
	_monster_zone("Exec_Carriere", QUARRY, 22.0, M.mix([["Granite Golem", 3], ["Amber Basilisk", 1]]), 12)
	_monster_zone("Exec_Sepultures", BURIAL.get_center(), 24.0, M.mix([["Ghoul", 2], ["Dead Seeker", 2], ["Strain", 1],
			["Sorrow Maiden", 1]]), 16)
	_monster_zone("Exec_Pendus", HANGMAN, 20.0, M.mix([["Hangman Tree", 3], ["Dead Seeker", 2]]), 12)
	_monster_zone("Exec_Guillotine", SCAFFOLD + Vector2(0, 8.0), 5.0,
			M.mix([["Guillotine, Warden of the Execution Grounds", 1]]), 1, 3600)
	_monster_zone("Exec_Calibus", CHAPEL + Vector2(0, -1.0), 4.0, M.mix([["Revenant of Sir Calibus", 1]]), 1, 3600)


## Poste des gardiens : enclos palissadé (porte au sud, sur le chemin de la route), maison
## de garde, tour de guet, feu de camp, râtelier, tente ; Roderik et Endrigo près de la
## porte, deux lampadaires dehors.
func _wardens_post() -> void:
	var group := _add(_props, _node("Poste_des_gardiens"))
	var walls := _add(group, _node("Palissade"))
	var a := POST.position
	var b := Vector2(POST.end.x, POST.position.y)
	var c := POST.end
	var d := Vector2(POST.position.x, POST.end.y)
	_wall_run(walls, "Palisade", 4.0, a, b)
	_wall_run(walls, "Palisade", 4.0, b, c)
	_wall_run(walls, "Palisade", 4.0, a, d)
	_wall_run(walls, "Palisade", 4.0, d, Vector2(POST_GATE.x - 3.6, POST.end.y))
	_wall_run(walls, "Palisade", 4.0, Vector2(POST_GATE.x + 3.6, POST.end.y), c)
	_instance("PalisadeGate", walls, POST_GATE, 0.0).name = "Porte_Poste"
	_reserve_disc(POST.get_center(), 16.0)
	_checks["Porte du poste (dehors)"] = POST_GATE + Vector2(0, 3.5)
	_checks["Cour du poste"] = POST_GATE + Vector2(0, -5.0)

	_building("HouseSmall", group, Vector2(39.5, 95.0), Vector2(0, 1), "Maison_de_garde")
	_occupy(Vector2(39.5, 95.0), 4.0)
	_prop("WatchTowerWood", group, Vector2(54.5, 93.5), PI * 0.75, 2.6, "Tour_de_guet")
	_prop("Campfire", group, Vector2(48.0, 99.5), 0.0, 1.2, "Feu_de_camp")
	_prop("WeaponRack", group, Vector2(56.6, 101.5), -PI / 2.0, 1.0, "Ratelier")
	_prop("Tent", group, Vector2(53.0, 105.5), PI, 2.0, "Tente")
	for p in [Vector2(35.8, 101.8), Vector2(36.6, 103.0)]:
		_prop("Barrel", group, p, _rng.randf() * TAU, 0.6)
	_prop("Crate", group, Vector2(36.0, 107.2), 0.3, 0.7)
	_prop("LogPile", group, Vector2(44.5, 91.5), 0.0, 1.2)
	_npc("Roderik", RODERIK_ID, POST_GATE + Vector2(-3.2, -3.0))
	_npc("Endrigo", ENDRIGO_ID, POST_GATE + Vector2(3.2, -3.0))
	var lamps := _add(group, _node("Lampadaires"))
	for s in [-1.0, 1.0]:
		_lamp(lamps, POST_GATE + Vector2(s * 4.6, 2.6), Vector2(-s, 0))


## Place d'exécution : échafaud au nord, gibets, cages, charrettes brisées, muret en ruine
## tout autour (ouvert vers la route et les chemins).
func _execution_square(parent: Node) -> void:
	var group := _add(parent, _node("Place_d_execution"))
	_prop("Scaffold", group, SCAFFOLD, 0.0, 4.6, "Echafaud")
	_checks["Devant l'échafaud"] = SCAFFOLD + Vector2(0, 7.0)
	_checks["Place d'exécution"] = SQUARE + Vector2(0, 6.0)
	for p in [SQUARE + Vector2(-12.5, -6.5), SQUARE + Vector2(12.5, -6.5), SQUARE + Vector2(-9.5, 9.5), SQUARE + Vector2(10.0, 9.0)]:
		var face: Vector2 = (SQUARE - p).normalized()
		_prop("Gallows", group, p, atan2(face.x, face.y), 2.4, "Gibet")
	for p in [SQUARE + Vector2(-14.0, 4.0), SQUARE + Vector2(-3.0, 13.5), SQUARE + Vector2(14.5, 1.0), SQUARE + Vector2(4.0, 14.0)]:
		_prop("Cage", group, p, _rng.randf() * TAU, 1.2, "Cage")
	_prop("CartBroken", group, SQUARE + Vector2(-11.0, -12.5), 0.8, 2.0)
	_prop("CartBroken", group, SQUARE + Vector2(15.0, 12.5), 2.3, 2.0)
	_prop("Crate", group, SQUARE + Vector2(6.0, -9.0), 0.4, 0.7)
	_prop("Barrel", group, SQUARE + Vector2(-6.0, -9.5), 0.0, 0.6)
	# Muret en ruine autour de la place, ouvert vers la route (ouest) et les chemins (NE, SE).
	var walls := _add(group, _node("Muret"))
	var sides := 18
	var ring := SQUARE_R + 5.0
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var mid := rad_to_deg((a0 + a1) / 2.0)
		if absf(mid - 180.0) < 22.0 or absf(mid - 317.0) < 20.0 or absf(mid - 43.0) < 20.0 or _rng.randf() < 0.3:
			continue
		var pa := SQUARE + Vector2(cos(a0), sin(a0)) * ring
		var pb := SQUARE + Vector2(cos(a1), sin(a1)) * ring
		_wall_run(walls, "RuinWallLow" if _rng.randf() < 0.75 else "RuinWall", 4.0, pa, pb)
		_occupy((pa + pb) / 2.0, 2.0)
	for k in 5:
		var a := TAU * (k + 0.3) / 5.0
		_rubble_patch(SQUARE + Vector2(cos(a), sin(a)) * (ring + 3.5), _rng.randf_range(1.3, 2.0))


## Prison en ruine au nord-ouest de la place : murs éventrés, cages au fond.
func _prison(parent: Node) -> void:
	var group := _add(parent, _node("Prison"))
	_ruin_building(group, PRISON, PRISON_SIZE, Vector2(0, 1), "Prison_en_ruine", 0.25)
	for dx in [-8.5, 0.0, 8.5]:
		_prop("Cage", group, PRISON + Vector2(dx, -4.5), _rng.randf_range(-0.2, 0.2), 1.2, "Cage_Prison")
	_column(group, PRISON + Vector2(-7.0, 2.5), "RuinColumnBroken")
	_column(group, PRISON + Vector2(7.0, 2.5), "RuinColumnBroken")
	for c in [PRISON + Vector2(-17, -4), PRISON + Vector2(17, 6), PRISON + Vector2(4, -13)]:
		_rubble_patch(c, _rng.randf_range(1.5, 2.3))


## Tribunal effondré au sud-ouest de la place : salle à colonnes, statue de la justice au
## fond, fût tombé devant l'entrée.
func _court(parent: Node) -> void:
	var group := _add(parent, _node("Tribunal"))
	_ruin_building(group, COURT, COURT_SIZE, Vector2(0, -1), "Tribunal_en_ruine", 0.35)
	_prop("RuinStatue", group, COURT + Vector2(0, 3.5), PI, 2.2, "Statue_Justice")
	for s in [-1.0, 1.0]:
		_column(group, COURT + Vector2(s * 6.5, -2.0), "RuinColumn" if s < 0 else "RuinColumnBroken")
		_column(group, COURT + Vector2(s * 6.0, -COURT_SIZE.y / 2.0 - 3.5), "RuinColumnBroken")
	_prop("RuinColumnFallen", group, COURT + Vector2(11.5, -COURT_SIZE.y / 2.0 - 4.5), 0.4, 2.6)
	for c in [COURT + Vector2(-15, 4), COURT + Vector2(14, 6)]:
		_rubble_patch(c, _rng.randf_range(1.5, 2.2))


## Champ des sépultures : enclos de murets, arche d'entrée au nord, rangées irrégulières de
## tombes de part et d'autre de l'allée, arbres morts, chapelle funéraire en ruine au fond.
func _burial_field(parent: Node) -> void:
	var group := _add(parent, _node("Champ_des_sepultures"))
	var walls := _add(group, _node("Enclos"))
	var r := BURIAL
	var nw := r.position
	var ne := Vector2(r.end.x, r.position.y)
	var se := r.end
	var sw := Vector2(r.position.x, r.end.y)
	_broken_wall(walls, nw, Vector2(BURIAL_GATE.x - 3.0, nw.y), 0.35, "RuinWallLow")
	_broken_wall(walls, Vector2(BURIAL_GATE.x + 3.0, ne.y), ne, 0.35, "RuinWallLow")
	_broken_wall(walls, ne, se, 0.4, "RuinWallLow")
	_broken_wall(walls, nw, sw, 0.4, "RuinWallLow")
	_broken_wall(walls, sw, Vector2(CHAPEL.x - CHAPEL_SIZE.x / 2.0 - 2.0, sw.y), 0.4, "RuinWallLow")
	_broken_wall(walls, Vector2(CHAPEL.x + CHAPEL_SIZE.x / 2.0 + 2.0, se.y), se, 0.4, "RuinWallLow")
	_arch(group, BURIAL_GATE, Vector2(0, 1), "Arche_Sepultures")
	_stamp_rect("ruin", r, 3.0)
	_reserve_cells(_rect_cells(r.get_center(), Vector2(0, 1), r.size, 1.0))

	# Statue de pleureuse au bord de l'allée, tournée vers elle.
	var statue := Vector2(BURIAL_GATE.x - 5.5, r.get_center().y + 2.0)
	_prop("RuinStatue", group, statue, PI * 0.5, 1.6, "Statue_Pleureuse")
	# Tombes : stèles et croix, de travers, face au nord (vers l'arche).
	var graves := _add(group, _node("Tombes"))
	var n := 0
	var z := r.position.y + 4.0
	while z < r.end.y - 2.5:
		for side in [-1.0, 1.0]:
			var x: float = BURIAL_GATE.x + side * 4.5
			while absf(x - BURIAL_GATE.x) < r.size.x / 2.0 - 2.5:
				if _rng.randf() > 0.18 and Vector2(x, z).distance_to(statue) > 3.6:
					var p := Vector2(x + _rng.randf_range(-0.4, 0.4), z + _rng.randf_range(-0.35, 0.35))
					var g := _instance("GravestoneCross" if _rng.randf() < 0.4 else "Gravestone", graves, p,
							PI + _rng.randf_range(-0.22, 0.22))
					g.rotation.z = _rng.randf_range(-0.12, 0.12)
					g.rotation.x = _rng.randf_range(-0.1, 0.06)
					g.name = "Tombe_%d" % n
					n += 1
				x += side * _rng.randf_range(2.8, 3.6)
		z += _rng.randf_range(3.2, 3.8)
	# Arbres morts et ruines dans le champ.
	for p in [r.position + Vector2(3.5, 4.0), Vector2(r.end.x - 3.5, r.position.y + 13.0), Vector2(r.position.x + 3.0, r.end.y - 5.0),
			Vector2(r.end.x - 3.0, r.end.y - 3.0)]:
		_instance("TreeDead", group, p, _rng.randf() * TAU)
	_checks["Allée des sépultures"] = Vector2(BURIAL_GATE.x, r.get_center().y)

	# Chapelle funéraire au fond, ouverte vers le champ.
	_ruin_building(group, CHAPEL, CHAPEL_SIZE, Vector2(0, -1), "Chapelle_funeraire", 0.3)
	_prop("RuinAltar", group, CHAPEL + Vector2(0, 3.0), PI, 3.0, "Autel_Funeraire")
	_column(group, CHAPEL + Vector2(-6.0, -1.0), "RuinColumn")
	_column(group, CHAPEL + Vector2(6.0, -1.0), "RuinColumnBroken")


## Carrière : rochers en arc de cercle sur les bords nord et est, éboulis, blocs épars,
## outils abandonnés à l'entrée (sud-ouest).
func _quarry() -> void:
	var group := _add(_props, _node("Carriere"))
	for k in 13:
		var a := deg_to_rad(lerpf(170.0, 420.0, k / 12.0))
		var p := QUARRY + Vector2(cos(a), sin(a)) * (QUARRY_R + _rng.randf_range(-1.0, 2.5))
		if _spot_free(p, 2.0):
			var rock := _instance("RockLarge", group, p, _rng.randf() * TAU)
			rock.scale = Vector3.ONE * _rng.randf_range(1.1, 1.6)
			_occupy(p, 2.6)
	for k in 7:
		var a := TAU * k / 7.0 + 0.5
		_rubble_patch(QUARRY + Vector2(cos(a), sin(a)) * _rng.randf_range(8.0, 15.0), _rng.randf_range(1.3, 2.3))
	var area := Rect2(QUARRY - Vector2(QUARRY_R, QUARRY_R), Vector2(QUARRY_R, QUARRY_R) * 2.0)
	var inside := func(p: Vector2) -> bool: return p.distance_to(QUARRY) < QUARRY_R - 3.0
	_scatter_props(group, ["RockMedium", "RockMedium", "RockLarge"], 12, area, 1.3, inside)
	_scatter_props(group, ["RuinRubble"], 4, area, 1.6, inside)
	var gate := QUARRY + Vector2(-QUARRY_R + 6.0, QUARRY_R - 6.0)
	_prop("CartBroken", group, gate + Vector2(-3.0, -4.0), 2.0, 2.0)
	_prop("PlankPile", group, gate + Vector2(4.5, 1.5), 0.3, 1.5)
	_prop("Crate", group, gate + Vector2(-5.5, 1.0), 0.1, 0.7)
	_checks["Carrière"] = QUARRY


## Gibets plantés le long de la vieille route (les pendus d'autrefois), une cage.
func _road_gibbets() -> void:
	var group := _add(_props, _node("Gibets_de_la_route"))
	for e in [[Vector2(70, 112.5), 0.0], [Vector2(92, 126.5), PI], [Vector2(118, 111.5), 0.0]]:
		_prop("Gallows", group, e[0], e[1], 2.4, "Gibet_Route")
	_prop("Cage", group, Vector2(80.5, 112.8), 0.3, 1.2, "Cage_Route")


## Lande : arbres morts, murets, éboulis, rochers, souches et troncs, os du passé.
func _wilds() -> void:
	var group := _add(_props, _node("Lande"))
	var area := Rect2(12, 12, W - 24, H - 24)
	var out_ruins := func(p: Vector2) -> bool: return _dist("ruin", p) > 5.0 and _dist("quarry", p) > 3.0 \
			and not POST.grow(6.0).has_point(p)
	_scatter_props(group, ["TreeDead"], 60, area, 0.8, out_ruins)
	_scatter_props(group, ["TreeDead"], 22, Rect2(HANGMAN - Vector2(HANGMAN_R, HANGMAN_R), Vector2(HANGMAN_R, HANGMAN_R) * 2.0),
			0.8, func(p: Vector2) -> bool: return _dist("deadwood", p) < 0.0)
	_scatter_props(group, ["RuinWallLow"], 9, area, 2.4, out_ruins)
	_scatter_props(group, ["RuinRubble"], 14, area, 1.7, out_ruins)
	_scatter_props(group, ["RuinColumnBroken"], 6, area, 1.0, out_ruins)
	_scatter_props(group, ["RockLarge", "RockMedium", "RockMedium"], 20, area, 1.3, out_ruins)
	_scatter_props(group, ["LogFallen", "Stump", "Stump"], 16, area, 1.6, func(p: Vector2) -> bool: return _dist("deadwood", p) < 3.0)
	_scatter_props(group, ["CartBroken"], 2, Rect2(60, 128, 60, 20), 2.5, out_ruins)


func _place_signs() -> void:
	var signs := _add(_props, _node("Panneaux"))
	_sign_at(signs, "Teleporteur", R.EXECUTION_PORTAL_W + Vector2(6.0, -5.5), [[R.DION, 180.0], [R.EXECUTION, 0.0]])
	_sign_at(signs, "Poste", Vector2(40.5, 115.5), [["Wardens' Post", 270.0], [R.DION, 180.0], ["Execution Square", 0.0]])
	_sign_at(signs, "Croisee", CROSS + Vector2(-5.5, -5.0), [["Execution Square", 0.0], [R.DION, 180.0],
			["Prison", _heading(CROSS, PRISON)], ["Court", _heading(CROSS, COURT)]])
	_sign_at(signs, "Place", Vector2(130.5, 112.5), [["Execution Square", 0.0], [R.DION, 180.0],
			["Quarry", _heading(SQUARE, QUARRY)], ["Burial Field", _heading(SQUARE, BURIAL.get_center())]])
	_sign_at(signs, "Sepultures", BURIAL_GATE + Vector2(6.5, -6.0), [["Burial Field", 90.0], ["Execution Square", 220.0]])
	_sign_at(signs, "Carriere", Vector2(201.5, 74.0), [["Quarry", -40.0], ["Execution Square", 140.0]])


# ---------------------------------------------------------------------------
# Kit de ruines (même jeu d'outils que generate_ruins_of_despair.gd)
# ---------------------------------------------------------------------------

## Prop isolé (nom de nœud facultatif), abords réservés sur `radius` m.
func _prop(scene: String, parent: Node, pos: Vector2, yaw: float, radius: float, node_name := "") -> Node3D:
	var node := _instance(scene, parent, pos, yaw)
	if not node_name.is_empty():
		node.name = node_name
	_occupy(pos, radius)
	return node


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


## Plaque d'éboulis infranchissable (terrain "rubble"), jamais sur une route ni un dallage.
func _rubble_patch(c: Vector2, radius: float) -> void:
	var tmp := "_tmp_rubble"
	_fields.erase(tmp)
	_stamp_blob(tmp, c, radius)
	var arr: PackedFloat32Array = _fields[tmp]
	for i in W * H:
		if arr[i] > 0.0 or [T.WATER, T.PAVED, T.BRIDGE].has(_terrain[i]):
			continue
		var p := Vector2(i % W + 0.5, i / W + 0.5)
		if _dist("road", p) < 2.0 or _near_check(p, 2.5) or _reserved.has(Vector2i(i % W, i / W)):
			continue
		_terrain[i] = T.RUBBLE
	_fields.erase(tmp)


## Dallage ancien, troué, dans un rectangle orienté.
func _ruin_floor_rect(center: Vector2, facing: Vector2, size: Vector2, holes: float) -> void:
	for c in _rect_cells(center, facing, size, 0.0):
		if _in_map(c) and _terrain[c.y * W + c.x] != T.WATER and _patch.get_noise_2d(c.x, c.y) > holes - 0.6:
			_terrain[c.y * W + c.x] = T.PAVED


## Dallage ancien, troué, sur un disque au bord irrégulier.
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
## sec, loin des routes, des points vérifiés, des ouvrages réservés et des autres props.
func _spot_free(p: Vector2, radius: float) -> bool:
	var cell := Vector2i(int(p.x), int(p.y))
	if not _in_map(cell) or _edge(cell.x, cell.y) < 9 or _reserved.has(cell):
		return false
	if [T.WATER, T.BRIDGE, T.THICKET, T.REEDS, T.RUBBLE].has(_t_at(p)):
		return false
	if _dist("road", p) < radius + 1.5 or _near_check(p, radius + 2.5):
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
				or _dist("open", p) < 0.0 or _dist("ruin", p) < 3.0 or _dist("quarry", p) < 2.0 or _near_check(p, 3.0)
	# Arbres morts : bois des Pendus (dense), bois morts, lisières, quelques-uns dans la lande.
	var dead := _scatter(T.DEAD_TREE, [T.GRASS, T.DARK_GRASS, T.DIRT, T.FOREST, T.DANGER], func(x: int, z: int) -> float:
		if skip.call(x, z):
			return 0.0
		var p := Vector2(x + 0.5, z + 0.5)
		var wood := _dist("deadwood", p)
		if p.distance_to(HANGMAN) < HANGMAN_R and wood < 0.0:
			return lerpf(0.12, 0.26, clampf(-wood / 6.0, 0.0, 1.0))
		if wood < 0.0:
			return lerpf(0.08, 0.2, clampf(-wood / 6.0, 0.0, 1.0))
		return lerpf(0.006, 0.2, clampf(1.0 - (float(_edge(x, z)) - 6.0) / 14.0, 0.0, 1.0)), 1)
	# Quelques arbres encore debout (la plupart dessinés morts, voir dead_tree_ratio), surtout
	# en lisière.
	var trees := _scatter(T.TREE, [T.GRASS, T.DARK_GRASS, T.FOREST], func(x: int, z: int) -> float:
		if skip.call(x, z):
			return 0.0
		if _dist("deadwood", Vector2(x + 0.5, z + 0.5)) < 0.0:
			return 0.03
		return lerpf(0.0, 0.07, clampf(1.0 - (float(_edge(x, z)) - 7.0) / 12.0, 0.0, 1.0)), 1)
	print("Arbres morts : %d, arbres : %d" % [dead, trees])


func _configure_ground(ground: TerrainGround) -> void:
	# Herbe flétrie gris-brun, terre sèche, pavés gris éteints.
	ground.paved_tint = Color(0.58, 0.56, 0.53)
	ground.paved_desaturate = 0.7
	ground.shader_overrides = {
		"grass_tint": Color(0.62, 0.52, 0.40),
		"dark_grass_tint": Color(0.50, 0.42, 0.33),
		"forest_tint": Color(0.48, 0.44, 0.40),
		"dirt_tint": Color(0.54, 0.50, 0.48),
	}


func _configure_vegetation(vegetation: Vegetation) -> void:
	vegetation.foliage_tint = Color(0.78, 0.66, 0.46)
	vegetation.grass_density = 0.26
	vegetation.forest_grass_density = 0.1
	vegetation.bush_density = 0.012
	vegetation.rock_density = 0.03
	vegetation.dead_tree_ratio = 0.7
	vegetation.outer_density = 0.32
	vegetation.outer_dead_ratio = 0.65
