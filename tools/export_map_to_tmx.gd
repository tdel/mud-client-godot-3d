extends SceneTree
## Outil hors-ligne : exporte une scène de carte (res://scenes/maps/*.tscn) au format .tmx
## lu par le serveur (TiledMapLoader côté backend) — le pendant inverse de
## convert_tmx_to_scene.gd, maintenant que les cartes s'éditent dans Godot.
##
## Ce que le serveur reçoit :
##   - calque "terrain" : une tuile par case, avec les propriétés "walkable" (seule lue par le
##     serveur : collisions, pathfinding, spawns) et "terrain" (nom du terrain, informatif).
##     Une case est non praticable si son terrain l'est (ZoneAssets3D.BLOCKING_TERRAINS) OU si
##     elle est couverte par l'emprise d'un obstacle (ObstacleFootprint3D : fontaine,
##     lampadaire, scierie, rocher...). Case vide du GridMap = non praticable (gid 0).
##   - calque "objects" : playerSpawn, portal, monsterSpawn, monsterSpawnGroup, npcSpawn,
##     peaceZone, lus sur les marqueurs de map_objects/ (positions en pixels : 32 px/case).
##
## Lancer avec (Godot en ligne de commande, depuis la racine du projet) :
##   godot --headless --script res://tools/export_map_to_tmx.gd -- \
##     res://scenes/maps/Orée_de_la_forêt.tscn \
##     //wsl.localhost/Debian/home/<user>/workspace/mud-server-java/src/main/resources/data/maps/
## Le second argument est un fichier .tmx ou un dossier (nom = celui de la scène + .tmx).
## Des vérifications équivalentes à celles du serveur au démarrage (spawn/portails sur case
## praticable, spawn à plus de 5 cases des portails, groupes de spawn déclarés) sont faites
## avant d'écrire : en cas d'erreur, rien n'est écrit.

const ZoneAssets := preload("res://autoload/ZoneAssets3D.gd")
const PIXELS_PER_TILE := 32.0
## Doit rester aligné sur TiledMapLoader.MIN_SPAWN_PORTAL_DISTANCE (backend).
const MIN_SPAWN_PORTAL_DISTANCE := 5.0

const SCRIPT_PLAYER_SPAWN := "res://map_objects/PlayerSpawnMarker3D.gd"
const SCRIPT_PORTAL := "res://map_objects/PortalMarker3D.gd"
const SCRIPT_MONSTER_SPAWN := "res://map_objects/MonsterSpawnMarker3D.gd"
const SCRIPT_MONSTER_GROUP := "res://map_objects/MonsterSpawnGroupMarker3D.gd"
const SCRIPT_NPC_SPAWN := "res://map_objects/NpcSpawnMarker3D.gd"
const SCRIPT_PEACE_ZONE := "res://map_objects/PeaceZoneMarker3D.gd"

var _scene_path := ""
var _out_path := ""
var _root: Node3D
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Usage: export_map_to_tmx.gd -- <scene.tscn> <sortie.tmx|dossier>")
		quit(1)
		return
	_scene_path = args[0]
	_out_path = args[1]
	if not _out_path.ends_with(".tmx"):
		_out_path = _out_path.path_join(_scene_path.get_file().get_basename() + ".tmx")


func _process(_delta: float) -> bool:
	# Scène ajoutée à la première frame (autoloads prêts), lue à la suivante (_ready des
	# nœuds @tool passés, transformations globales à jour).
	_frames += 1
	if _frames == 1:
		var packed: PackedScene = load(_scene_path)
		if packed == null:
			printerr("Scène illisible : %s" % _scene_path)
			quit(1)
			return true
		_root = packed.instantiate()
		root.add_child(_root)
		return false
	var ok := _export()
	quit(0 if ok else 1)
	return true


func _export() -> bool:
	if not (_root is MapData):
		printerr("La racine de %s n'est pas un MapData" % _scene_path)
		return false
	var map: MapData = _root
	var grid_map: GridMap = _root.get_node_or_null("Terrain")
	if grid_map == null:
		printerr("Pas de GridMap 'Terrain' dans %s" % _scene_path)
		return false

	# Dimensions : de (0, 0) à la case peinte la plus éloignée.
	var width := 0
	var height := 0
	for cell in grid_map.get_used_cells():
		width = maxi(width, cell.x + 1)
		height = maxi(height, cell.z + 1)

	var blocked_by_obstacle := {}
	for node in _root.get_tree().get_nodes_in_group(ObstacleFootprint3D.GROUP):
		if not _root.is_ancestor_of(node):
			continue
		for cell in (node as ObstacleFootprint3D).blocked_cells():
			blocked_by_obstacle[cell] = true

	var library := grid_map.mesh_library
	var tile_ids := {}  # "terrain|walkable" -> id local de tuile
	var tiles: Array = []  # [terrain, walkable]
	var gids := PackedInt32Array()
	gids.resize(width * height)
	var walkable_grid := PackedByteArray()
	walkable_grid.resize(width * height)
	var blocked_count := 0
	for z in height:
		for x in width:
			var item := grid_map.get_cell_item(Vector3i(x, 0, z))
			if item == GridMap.INVALID_CELL_ITEM:
				gids[z * width + x] = 0
				walkable_grid[z * width + x] = 0
				blocked_count += 1
				continue
			var terrain := library.get_item_name(item)
			var walkable: bool = not ZoneAssets.BLOCKING_TERRAINS.has(terrain) \
					and not blocked_by_obstacle.has(Vector2i(x, z))
			var key := "%s|%s" % [terrain, walkable]
			if not tile_ids.has(key):
				tile_ids[key] = tiles.size()
				tiles.append([terrain, walkable])
			gids[z * width + x] = tile_ids[key] + 1
			walkable_grid[z * width + x] = 1 if walkable else 0
			if not walkable:
				blocked_count += 1

	var objects := _collect_objects()
	var errors := _validate(objects, walkable_grid, width, height)
	if not errors.is_empty():
		for e in errors:
			printerr("ERREUR : " + e)
		printerr("Export annulé (%d erreur(s)), rien n'a été écrit." % errors.size())
		return false

	var xml := _build_xml(map, width, height, tiles, gids, objects)
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		printerr("Écriture impossible : %s (%s)" % [_out_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(xml)
	file.close()
	var counts := {}
	for o in objects:
		counts[o.type] = counts.get(o.type, 0) + 1
	print("Carte exportée : %s" % _out_path)
	print("  %s (%dx%d) — %d cases non praticables dont %d par des obstacles posés" % [
		map.map_name, width, height, blocked_count, blocked_by_obstacle.size()])
	print("  objets : %s" % str(counts))
	return true


# ---------------------------------------------------------------------------
# Objets (marqueurs map_objects/)
# ---------------------------------------------------------------------------

func _collect_objects() -> Array:
	var objects: Array = []
	var stack: Array[Node] = [_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for i in range(node.get_child_count() - 1, -1, -1):
			stack.append(node.get_child(i))
		var script: Script = node.get_script()
		if script == null or not (node is Node3D):
			continue
		var pos: Vector3 = (node as Node3D).global_position
		var obj := {"x": pos.x * PIXELS_PER_TILE, "y": pos.z * PIXELS_PER_TILE, "name": "", "props": [],
				"polygon": PackedVector2Array(), "world": Vector2(pos.x, pos.z)}
		match script.resource_path:
			SCRIPT_PLAYER_SPAWN:
				obj.type = "playerSpawn"
			SCRIPT_PORTAL:
				obj.type = "portal"
				obj.props = [["direction", "", node.direction], ["targetMapId", "", node.target_map_id],
						["targetX", "float", node.target_x], ["targetY", "float", node.target_y]]
			SCRIPT_MONSTER_SPAWN:
				obj.type = "monsterSpawn"
				obj.props = [["templateId", "", node.template_id], ["spawnGroup", "", node.spawn_group]]
			SCRIPT_MONSTER_GROUP:
				obj.type = "monsterSpawnGroup"
				obj.props = [["groupId", "", node.group_id], ["maxMonsters", "int", node.max_monsters],
						["respawnDelaySeconds", "int", node.respawn_delay_seconds]]
			SCRIPT_NPC_SPAWN:
				obj.type = "npcSpawn"
				obj.props = [["npcId", "", node.npc_id]]
			SCRIPT_PEACE_ZONE:
				obj.type = "peaceZone"
				obj.name = node.zone_name
				for p in node.polygon_points:
					obj.polygon.append(p * PIXELS_PER_TILE)
			_:
				continue
		objects.append(obj)
	return objects


func _validate(objects: Array, walkable: PackedByteArray, width: int, height: int) -> Array[String]:
	var errors: Array[String] = []
	var is_walkable := func(p: Vector2) -> bool:
		var x := floori(p.x)
		var z := floori(p.y)
		return x >= 0 and z >= 0 and x < width and z < height and walkable[z * width + x] == 1
	var spawns := objects.filter(func(o): return o.type == "playerSpawn")
	var portals := objects.filter(func(o): return o.type == "portal")
	var groups := {}
	for o in objects:
		if o.type == "monsterSpawnGroup":
			groups[o.props[0][2]] = true
	if spawns.size() != 1:
		errors.append("il faut exactement un PlayerSpawn (trouvé %d)" % spawns.size())
	for s in spawns:
		if not is_walkable.call(s.world):
			errors.append("PlayerSpawn %s sur une case non praticable" % s.world)
		for p in portals:
			if s.world.distance_to(p.world) < MIN_SPAWN_PORTAL_DISTANCE:
				errors.append("PlayerSpawn à moins de %.0f cases du portail %s" % [MIN_SPAWN_PORTAL_DISTANCE, p.props[0][2]])
	for p in portals:
		if not is_walkable.call(p.world):
			errors.append("portail %s en %s sur une case non praticable" % [p.props[0][2], p.world])
	var bad_spawns := 0
	for o in objects:
		if o.type != "monsterSpawn":
			continue
		if not groups.has(o.props[1][2]):
			errors.append("monsterSpawn en %s : groupe '%s' non déclaré" % [o.world, o.props[1][2]])
		if not is_walkable.call(o.world):
			bad_spawns += 1
	if bad_spawns > 0:
		errors.append("%d monsterSpawn sur des cases non praticables" % bad_spawns)
	return errors


# ---------------------------------------------------------------------------
# Écriture XML (même mise en forme que les .tmx historiques)
# ---------------------------------------------------------------------------

func _build_xml(map: MapData, width: int, height: int, tiles: Array, gids: PackedInt32Array, objects: Array) -> String:
	var lines := PackedStringArray()
	lines.append('<?xml version="1.0" encoding="UTF-8"?>')
	lines.append('<map version="1.10" tiledversion="1.11.0" orientation="orthogonal" renderorder="right-down" width="%d" height="%d" tilewidth="32" tileheight="32" infinite="0" nextlayerid="3" nextobjectid="%d">' % [width, height, objects.size() + 1])
	lines.append(' <properties>')
	lines.append('  <property name="id" value="%s"/>' % _esc(map.map_id))
	lines.append('  <property name="name" value="%s"/>' % _esc(map.map_name))
	lines.append('  <property name="description" value="%s"/>' % _esc(map.description))
	lines.append('  <property name="isStartingMap" type="bool" value="%s"/>' % str(map.is_starting_map).to_lower())
	lines.append(' </properties>')
	lines.append(' <tileset firstgid="1" name="%s" tilewidth="32" tileheight="32" tilecount="%d" columns="%d">' % [_esc(map.map_name), tiles.size(), tiles.size()])
	for i in tiles.size():
		var terrain: String = tiles[i][0]
		lines.append('  <tile id="%d">' % i)
		lines.append('   <properties>')
		lines.append('    <property name="walkable" type="bool" value="%s"/>' % str(tiles[i][1]).to_lower())
		if not terrain.begins_with("__"):
			lines.append('    <property name="terrain" value="%s"/>' % _esc(terrain))
		lines.append('   </properties>')
		lines.append('  </tile>')
	lines.append(' </tileset>')
	lines.append(' <layer id="1" name="terrain" width="%d" height="%d">' % [width, height])
	lines.append('  <data encoding="csv">')
	for z in height:
		var row := PackedStringArray()
		for x in width:
			row.append(str(gids[z * width + x]))
		lines.append(",".join(row) + ("," if z < height - 1 else ""))
	lines.append('  </data>')
	lines.append(' </layer>')
	lines.append(' <objectgroup id="2" name="objects">')
	for i in objects.size():
		var o: Dictionary = objects[i]
		lines.append('  <object id="%d" name="%s" type="%s" x="%s" y="%s">' % [i + 1, _esc(o.name), o.type, _num(o.x), _num(o.y)])
		if not o.props.is_empty():
			lines.append('   <properties>')
			for prop in o.props:
				var type_attr: String = (' type="%s"' % prop[1]) if prop[1] != "" else ""
				var value = prop[2]
				var text: String = _num(value) if prop[1] == "float" else str(value)
				lines.append('         <property name="%s"%s value="%s"/>' % [prop[0], type_attr, _esc(text)])
			lines.append('   </properties>')
		if not o.polygon.is_empty():
			var pts := PackedStringArray()
			for p in o.polygon:
				pts.append("%s,%s" % [_num(p.x).trim_suffix(".0"), _num(p.y).trim_suffix(".0")])
			lines.append('   <polygon points="%s"/>' % " ".join(pts))
		lines.append('  </object>')
	lines.append(' </objectgroup>')
	lines.append('</map>')
	return "\n".join(lines) + "\n"


func _num(v: float) -> String:
	var rounded := snappedf(v, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d.0" % int(roundf(rounded))
	return str(rounded)


func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
