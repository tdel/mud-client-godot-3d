extends SceneTree
## Outil hors-ligne : convertit un fichier .tmx existant (voir data/maps/) en scène Godot
## (un GridMap peint avec assets/terrain/terrain_library.res + des marqueurs pour les
## spawns/portails/zones de paix, voir map_objects/) — remplace l'édition dans Tiled par
## l'édition native Godot pour la carte convertie. Une fois la scène validée, elle est
## éditable au pinceau (GridMap) et à la main (ajout de n'importe quel nœud) directement
## dans l'éditeur Godot.
##
## Nécessite que res://assets/terrain/terrain_library.res existe déjà, voir
## tools/generate_terrain_library.gd.
##
## Lancer avec :
##   godot --headless --script res://tools/convert_tmx_to_scene.gd -- \
##     res://data/maps/Place_du_village.tmx res://scenes/maps/Place_du_village.tscn

const LIBRARY_PATH := "res://assets/terrain/terrain_library.res"
const TerrainNames = preload("res://tools/TerrainNames.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Usage: convert_tmx_to_scene.gd <fichier.tmx> <scene_sortie.tscn>")
		quit(1)
		return

	var tmx_path: String = args[0]
	var out_path: String = args[1]

	var parsed := _parse_tmx(tmx_path)
	if parsed.is_empty():
		quit(1)
		return

	var scene_root := _build_scene(parsed)
	var packed := PackedScene.new()
	packed.pack(scene_root)

	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := ResourceSaver.save(packed, out_path)
	if err != OK:
		printerr("Échec sauvegarde %s (code %d)" % [out_path, err])
		quit(1)
		return

	print("Scène écrite : %s (%s, %dx%d, %d objets)" % [
		out_path, parsed.map_name, parsed.width, parsed.height, parsed.objects.size()
	])
	quit()


# ---------------------------------------------------------------------------
# Parsing .tmx — inspiré de ZoneAssets3D._parse_map_file, étendu au layer d'objets
# (spawns/portails/zones de paix) que ce client 3D ne lisait pas jusqu'ici.
# ---------------------------------------------------------------------------

func _parse_tmx(path: String) -> Dictionary:
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		printerr("Lecture/XML invalide: %s" % path)
		return {}

	var tag_stack: Array = []
	var map_id := ""
	var map_name := ""
	var description := ""
	var is_starting_map := false
	var width := 0
	var height := 0
	var tile_w := 32
	var tile_h := 32

	var first_gid := 1
	var seen_tileset := false
	var current_tile_id := -1
	var terrain_by_local_id: Dictionary = {}

	var in_terrain_layer := false
	var terrain_csv := ""

	var current_object = null
	var objects: Array = []

	while xml.read() == OK:
		var node_type := xml.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var tag_name := xml.get_node_name()
			var parent: String = tag_stack.back() if not tag_stack.is_empty() else ""

			match tag_name:
				"map":
					width = int(xml.get_named_attribute_value_safe("width"))
					height = int(xml.get_named_attribute_value_safe("height"))
					tile_w = int(xml.get_named_attribute_value_safe("tilewidth"))
					tile_h = int(xml.get_named_attribute_value_safe("tileheight"))
				"tileset":
					if not seen_tileset and parent == "map":
						seen_tileset = true
						first_gid = int(xml.get_named_attribute_value_safe("firstgid"))
				"tile":
					if parent == "tileset":
						current_tile_id = int(xml.get_named_attribute_value_safe("id"))
				"layer":
					if parent == "map":
						in_terrain_layer = xml.get_named_attribute_value_safe("name") == "terrain"
						if in_terrain_layer:
							terrain_csv = ""
				"object":
					if parent == "objectgroup":
						current_object = {
							"type": xml.get_named_attribute_value_safe("type"),
							"name": xml.get_named_attribute_value_safe("name"),
							"x": float(xml.get_named_attribute_value_safe("x")),
							"y": float(xml.get_named_attribute_value_safe("y")),
							"props": {},
							"polygon": PackedVector2Array(),
						}
				"property":
					var prop_name := xml.get_named_attribute_value_safe("name")
					var prop_value := xml.get_named_attribute_value_safe("value")
					if current_object != null and parent == "properties":
						current_object.props[prop_name] = prop_value
					elif current_tile_id >= 0 and parent == "properties":
						if prop_name == "terrain":
							terrain_by_local_id[current_tile_id] = prop_value
					elif parent == "properties" and tag_stack.size() == 2 and tag_stack[0] == "map":
						match prop_name:
							"id":
								map_id = prop_value
							"name":
								map_name = prop_value
							"description":
								description = prop_value
							"isStartingMap":
								is_starting_map = prop_value == "true"
				"polygon":
					if current_object != null and parent == "object":
						var points := PackedVector2Array()
						for pair in xml.get_named_attribute_value_safe("points").split(" "):
							var coords := pair.split(",")
							if coords.size() == 2:
								points.append(Vector2(float(coords[0]), float(coords[1])))
						current_object.polygon = points

			if not xml.is_empty():
				tag_stack.append(tag_name)
		elif node_type == XMLParser.NODE_TEXT:
			if in_terrain_layer:
				terrain_csv += xml.get_node_data()
		elif node_type == XMLParser.NODE_ELEMENT_END:
			var closed_name := xml.get_node_name()
			if closed_name == "tile":
				current_tile_id = -1
			elif closed_name == "layer":
				in_terrain_layer = false
			elif closed_name == "object":
				if current_object != null:
					objects.append(current_object)
					current_object = null
			if not tag_stack.is_empty():
				tag_stack.pop_back()

	if map_name.is_empty():
		printerr("Pas de propriété 'name' dans %s" % path)
		return {}

	var terrain_grid: Array = []
	var gids := PackedInt64Array()
	for token in terrain_csv.split(","):
		var trimmed := token.strip_edges()
		if not trimmed.is_empty():
			gids.append(int(trimmed))
	for y in height:
		var row: Array = []
		for x in width:
			var index := y * width + x
			var gid: int = gids[index] if index < gids.size() else 0
			var terrain := ""
			if gid > 0:
				terrain = terrain_by_local_id.get(gid - first_gid, "")
			row.append(terrain)
		terrain_grid.append(row)

	return {
		"map_id": map_id, "map_name": map_name, "description": description,
		"is_starting_map": is_starting_map,
		"width": width, "height": height, "tile_w": tile_w, "tile_h": tile_h,
		"terrain_grid": terrain_grid, "objects": objects,
	}


# ---------------------------------------------------------------------------
# Construction de la scène Godot à partir des données parsées
# ---------------------------------------------------------------------------

func _build_scene(parsed: Dictionary) -> Node3D:
	var library: MeshLibrary = load(LIBRARY_PATH)
	var names := TerrainNames.ordered_list()
	var id_by_name := {}
	for i in names.size():
		id_by_name[names[i]] = i

	var root := Node3D.new()
	root.name = String(parsed.map_name).replace(" ", "_")
	root.set_script(preload("res://map_objects/MapData.gd"))
	root.map_id = parsed.map_id
	root.map_name = parsed.map_name
	root.description = parsed.description
	root.is_starting_map = parsed.is_starting_map

	var grid_map := GridMap.new()
	grid_map.name = "Terrain"
	grid_map.mesh_library = library
	grid_map.cell_size = Vector3(1, 1, 1)
	grid_map.cell_center_x = true
	grid_map.cell_center_y = false
	grid_map.cell_center_z = true
	root.add_child(grid_map)
	grid_map.owner = root

	var terrain_grid: Array = parsed.terrain_grid
	var unknown_terrains := {}
	for y in terrain_grid.size():
		var row: Array = terrain_grid[y]
		for x in row.size():
			var terrain_name: String = row[x]
			if terrain_name.is_empty():
				continue
			var item_id: int = id_by_name.get(terrain_name, -1)
			if item_id == -1:
				unknown_terrains[terrain_name] = true
				continue
			grid_map.set_cell_item(Vector3i(x, 0, y), item_id)
	for terrain_name in unknown_terrains:
		printerr("Terrain inconnu ignoré dans la MeshLibrary: %s" % terrain_name)

	var objects_root := Node3D.new()
	objects_root.name = "Objects"
	root.add_child(objects_root)
	objects_root.owner = root

	for obj in parsed.objects:
		var marker := _build_object_node(obj, parsed.tile_w, parsed.tile_h)
		if marker == null:
			continue
		objects_root.add_child(marker)
		marker.owner = root

	return root


func _build_object_node(obj: Dictionary, tile_w: int, tile_h: int) -> Node3D:
	var tile_x: float = obj.x / float(tile_w)
	var tile_z: float = obj.y / float(tile_h)

	match obj.type:
		"playerSpawn":
			var m := Marker3D.new()
			m.name = "PlayerSpawn"
			m.set_script(preload("res://map_objects/PlayerSpawnMarker3D.gd"))
			m.position = Vector3(tile_x, 0.0, tile_z)
			return m
		"npcSpawn":
			var npc_id: String = obj.props.get("npcId", "")
			var m := Marker3D.new()
			m.name = "NpcSpawn_%s" % npc_id.left(8)
			m.set_script(preload("res://map_objects/NpcSpawnMarker3D.gd"))
			m.npc_id = npc_id
			m.position = Vector3(tile_x, 0.0, tile_z)
			return m
		"portal":
			var m := Marker3D.new()
			m.name = "Portal_%s" % String(obj.props.get("direction", ""))
			m.set_script(preload("res://map_objects/PortalMarker3D.gd"))
			m.direction = obj.props.get("direction", "")
			m.target_map_id = obj.props.get("targetMapId", "")
			m.target_x = float(obj.props.get("targetX", "0"))
			m.target_y = float(obj.props.get("targetY", "0"))
			m.position = Vector3(tile_x, 0.0, tile_z)
			return m
		"monsterSpawn":
			var template_id: String = obj.props.get("templateId", "")
			var m := Marker3D.new()
			m.name = "MonsterSpawn_%s" % template_id.left(8)
			m.set_script(preload("res://map_objects/MonsterSpawnMarker3D.gd"))
			m.template_id = template_id
			m.spawn_group = obj.props.get("spawnGroup", "")
			m.position = Vector3(tile_x, 0.0, tile_z)
			return m
		"monsterSpawnGroup":
			var group_id: String = obj.props.get("groupId", "")
			var n2 := Node3D.new()
			n2.name = "MonsterSpawnGroup_%s" % group_id.replace(" ", "_")
			n2.set_script(preload("res://map_objects/MonsterSpawnGroupMarker3D.gd"))
			n2.group_id = group_id
			n2.max_monsters = int(obj.props.get("maxMonsters", "0"))
			n2.respawn_delay_seconds = int(obj.props.get("respawnDelaySeconds", "0"))
			n2.position = Vector3(tile_x, 0.0, tile_z)
			return n2
		"peaceZone":
			var n := Node3D.new()
			var obj_name: String = obj.name
			n.name = "PeaceZone" if obj_name.is_empty() else obj_name.replace(" ", "_")
			n.set_script(preload("res://map_objects/PeaceZoneMarker3D.gd"))
			n.zone_name = obj_name
			var points := PackedVector2Array()
			for p in obj.polygon:
				points.append(Vector2(p.x / float(tile_w), p.y / float(tile_h)))
			n.polygon_points = points
			n.position = Vector3(tile_x, 0.0, tile_z)
			return n
		_:
			printerr("Type d'objet Tiled inconnu ignoré: %s" % obj.type)
			return null
