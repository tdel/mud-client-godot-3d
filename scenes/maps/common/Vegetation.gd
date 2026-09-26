@tool
class_name Vegetation
extends Node3D
## Végétation d'une carte décorée, entièrement déduite du GridMap "Terrain" frère (rien
## n'est enregistré dans la scène : tout est reconstruit au chargement, de façon
## déterministe via `seed`) :
##   - un arbre par case de terrain "tree" (case non praticable côté serveur) : essence
##     choisie par un bruit de "type de forêt" (chênaie / sapinière / mélange), bouleaux en
##     lisière, quelques arbres morts ; en cœur de massif dense, un arbre sur deux seulement
##     est dessiné (les couronnes se recouvrent de toute façon, la case reste bloquante) ;
##   - du décor non bloquant sur les cases praticables : touffes d'herbe, graminées,
##     buissons, cailloux, souches — jamais sous l'emprise d'un obstacle posé
##     (ObstacleFootprint3D), jamais sur les pavés, rarement sur la terre battue.
## Rendu en MultiMeshInstance3D par bloc de `chunk_size` cases et par modèle, pour que le
## moteur n'affiche (et n'ombre) que les blocs visibles. Après avoir repeint le GridMap
## dans l'éditeur, cliquer "Régénérer la végétation".

const NATURE_SCENE := "res://assets/environment/models/nature.glb"
const ZoneAssets := preload("res://autoload/ZoneAssets3D.gd")
const OAKS := ["tree_oak_0", "tree_oak_1", "tree_oak_2"]
const BIRCHES := ["tree_birch_0", "tree_birch_1"]
const FIRS := ["tree_fir_0", "tree_fir_1", "tree_fir_2"]
## Modèles de décor sans ombre portée (petits, nombreux) et masqués au-delà de
## GRASS_VISIBILITY_END mètres de la caméra (qui est à 60 m du joueur, voir
## Game3D.CAMERA_DISTANCE : ne coupe que ce qui sort de l'écran au zoom le plus large).
const SMALL_DECOR := {"grass_0": true, "grass_1": true, "rock_0": true}
const GRASS_VISIBILITY_END := 115.0

@export var grid_map_path: NodePath = ^"../Terrain"
@export var seed := 1
@export var chunk_size := 32
## Bande (cases) de forêt purement visuelle plantée autour de la carte (voir aussi
## TerrainGround.margin) ; interrompue face aux cases de bord pavées ou en terre (routes qui
## sortent de la carte).
@export var outer_margin := 24
## Densités (probabilité par case praticable) du décor.
@export_range(0.0, 1.0) var grass_density := 0.55
@export_range(0.0, 1.0) var forest_grass_density := 0.22
@export_range(0.0, 0.2) var bush_density := 0.035
@export_range(0.0, 0.2) var rock_density := 0.012
@export_tool_button("Régénérer la végétation", "Reload") var regenerate_action := rebuild

var _meshes: Dictionary = {}
var _container: Node3D


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var grid_map := get_node_or_null(grid_map_path) as GridMap
	if grid_map == null:
		push_warning("Vegetation: GridMap introuvable (%s)" % grid_map_path)
		return
	if _container != null:
		_container.queue_free()
	_container = Node3D.new()
	_container.name = "Instances"
	add_child(_container, false, Node.INTERNAL_MODE_BACK)
	_load_meshes()

	var library := grid_map.mesh_library
	var terrain_by_item := {}
	for item in library.get_item_list():
		terrain_by_item[item] = library.get_item_name(item)
	var width := 0
	var height := 0
	for cell in grid_map.get_used_cells():
		width = maxi(width, cell.x + 1)
		height = maxi(height, cell.z + 1)
	var terrain := PackedStringArray()
	terrain.resize(width * height)
	for cell in grid_map.get_used_cells():
		terrain[cell.z * width + cell.x] = terrain_by_item.get(grid_map.get_cell_item(cell), "")

	var blocked := _obstacle_cells()
	var forest_type := FastNoiseLite.new()
	forest_type.seed = seed
	forest_type.frequency = 0.014
	var clump := FastNoiseLite.new()
	clump.seed = seed + 7
	clump.frequency = 0.08

	var buckets := {}  # "cx,cz,mesh" -> Array de floats (12 / instance)
	var rng := RandomNumberGenerator.new()
	for z in height:
		for x in width:
			var t := terrain[z * width + x]
			if t.is_empty():
				continue
			rng.seed = _cell_hash(x, z)
			if t == "tree":
				_place_tree(buckets, rng, terrain, width, height, x, z, forest_type)
			elif not ZoneAssets.BLOCKING_TERRAINS.has(t) and not blocked.has(Vector2i(x, z)):
				_place_decor(buckets, rng, terrain, width, height, x, z, t, clump)

	_place_outer_forest(buckets, rng, terrain, width, height)

	for key in buckets:
		var parts: PackedStringArray = key.split(",")
		var mesh_name := parts[2]
		var data := PackedFloat32Array(buckets[key])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[mesh_name]
		mm.instance_count = data.size() / 12
		mm.buffer = data
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s_%s" % [mesh_name, parts[0], parts[1]]
		mmi.multimesh = mm
		if SMALL_DECOR.has(mesh_name):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = GRASS_VISIBILITY_END
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_container.add_child(mmi, false, Node.INTERNAL_MODE_BACK)


func _load_meshes() -> void:
	if not _meshes.is_empty():
		return
	var scene: Node = (load(NATURE_SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			_meshes[String(node.name)] = EnvMaterials.remap_mesh(node.mesh)
	scene.free()


func _obstacle_cells() -> Dictionary:
	var cells := {}
	var scene_root := owner if owner != null else get_parent()
	if not is_inside_tree():
		return cells
	for node in get_tree().get_nodes_in_group(ObstacleFootprint3D.GROUP):
		if scene_root != null and not scene_root.is_ancestor_of(node):
			continue
		for cell in (node as ObstacleFootprint3D).blocked_cells():
			cells[cell] = true
	return cells


func _place_tree(buckets: Dictionary, rng: RandomNumberGenerator, terrain: PackedStringArray,
		width: int, height: int, x: int, z: int, forest_type: FastNoiseLite) -> void:
	var tree_neighbours := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= width or nz >= height or terrain[nz * width + nx] == "tree":
				tree_neighbours += 1
	var interior := tree_neighbours == 8
	if interior and rng.randf() > 0.5:
		return
	var kind := forest_type.get_noise_2d(x, z)
	var mesh_name: String
	var roll := rng.randf()
	if roll < 0.02:
		mesh_name = "tree_dead_0"
	elif tree_neighbours <= 5 and roll < 0.3:
		mesh_name = BIRCHES[rng.randi() % BIRCHES.size()]
	elif kind > 0.12 or (kind > -0.2 and rng.randf() < 0.5):
		mesh_name = FIRS[rng.randi() % FIRS.size()]
	else:
		mesh_name = OAKS[rng.randi() % OAKS.size()]
	var scale := rng.randf_range(0.8, 1.2) * (1.12 if interior else 1.0)
	var pos := Vector3(x + 0.5 + rng.randf_range(-0.2, 0.2), 0.0, z + 0.5 + rng.randf_range(-0.2, 0.2))
	_add(buckets, mesh_name, x, z, pos, rng.randf() * TAU, scale)


func _place_decor(buckets: Dictionary, rng: RandomNumberGenerator, terrain: PackedStringArray,
		width: int, height: int, x: int, z: int, t: String, clump: FastNoiseLite) -> void:
	var grassy := t == "grass" or t == "clearingGrass" or t == "darkGrass" or t == "tallGrass"
	var forest := t == "forestFloor"
	var near_tree := false
	var edge := false
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + offset.x
		var nz: int = z + offset.y
		if nx < 0 or nz < 0 or nx >= width or nz >= height:
			continue
		var n := terrain[nz * width + nx]
		if n == "tree":
			near_tree = true
		if n != t:
			edge = true
	var clumping := clump.get_noise_2d(x, z) * 0.5 + 0.5
	var grass_p := 0.0
	if grassy:
		grass_p = grass_density * (0.5 + clumping)
	elif forest:
		grass_p = forest_grass_density * (0.4 + clumping)
	elif t == "dirtPath" and edge:
		grass_p = 0.3
	elif t == "pavedStone" and edge:
		grass_p = 0.06
	if t == "fieldCrop":
		# Cultures : deux rangs de graminées par case, alignés selon X.
		for row in [0.28, 0.72]:
			for k in 2:
				var pos := Vector3(x + 0.25 + k * 0.5 + rng.randf_range(-0.08, 0.08), 0.0, z + row)
				_add(buckets, "grass_1", x, z, pos, rng.randf() * TAU, rng.randf_range(0.85, 1.15))
		return
	var tufts := 2 if rng.randf() < grass_p * 0.5 else (1 if rng.randf() < grass_p else 0)
	for i in tufts:
		var mesh_name := "grass_1" if rng.randf() < 0.18 else "grass_0"
		var pos := Vector3(x + rng.randf_range(0.1, 0.9), 0.0, z + rng.randf_range(0.1, 0.9))
		_add(buckets, mesh_name, x, z, pos, rng.randf() * TAU, rng.randf_range(0.7, 1.25))
	if t == "pavedStone" or t == "dirtPath":
		return
	var bush_p := bush_density * (2.2 if near_tree else 1.0) * (1.3 if forest else 0.6)
	if rng.randf() < bush_p:
		var bush := "bush_0" if rng.randf() < 0.6 else "bush_1"
		_add(buckets, bush, x, z, Vector3(x + 0.5, 0.0, z + 0.5), rng.randf() * TAU, rng.randf_range(0.7, 1.2))
	elif rng.randf() < rock_density:
		_add(buckets, "rock_0", x, z, Vector3(x + rng.randf_range(0.2, 0.8), 0.0, z + rng.randf_range(0.2, 0.8)),
				rng.randf() * TAU, rng.randf_range(0.6, 1.4))
	elif forest and rng.randf() < 0.004:
		_add(buckets, "stump_1", x, z, Vector3(x + 0.5, 0.0, z + 0.5), rng.randf() * TAU, rng.randf_range(0.8, 1.2))


func _place_outer_forest(buckets: Dictionary, rng: RandomNumberGenerator, terrain: PackedStringArray,
		width: int, height: int) -> void:
	for z in range(-outer_margin, height + outer_margin):
		for x in range(-outer_margin, width + outer_margin):
			if x >= 0 and z >= 0 and x < width and z < height:
				continue
			if _near_edge_road(terrain, width, height, x, z):
				continue
			rng.seed = _cell_hash(x + 100000, z + 100000)
			if rng.randf() > 0.42:
				continue
			var roll := rng.randf()
			var mesh_name: String = FIRS[rng.randi() % FIRS.size()] if roll < 0.55 else OAKS[rng.randi() % OAKS.size()]
			var pos := Vector3(x + 0.5 + rng.randf_range(-0.3, 0.3), 0.0, z + 0.5 + rng.randf_range(-0.3, 0.3))
			_add(buckets, mesh_name, x, z, pos, rng.randf() * TAU, rng.randf_range(0.85, 1.25))


## Vrai si une case de bord de carte proche (à ±5 cases le long du bord) de la case hors
## carte (x, z) est pavée ou en terre : garde dégagé le prolongement visuel des routes, sans
## que les couronnes des arbres voisins ne referment le passage.
func _near_edge_road(terrain: PackedStringArray, width: int, height: int, x: int, z: int) -> bool:
	var cx := clampi(x, 0, width - 1)
	var cz := clampi(z, 0, height - 1)
	for offset in range(-5, 6):
		var ex := cx if (x < 0 or x >= width) else clampi(cx + offset, 0, width - 1)
		var ez := cz if (z < 0 or z >= height) else clampi(cz + offset, 0, height - 1)
		var t := terrain[ez * width + ex]
		if t == "pavedStone" or t == "dirtPath":
			return true
	return false


func _add(buckets: Dictionary, mesh_name: String, x: int, z: int, pos: Vector3, yaw: float, scale: float) -> void:
	var key := "%d,%d,%s" % [x / chunk_size, z / chunk_size, mesh_name]
	# Array (type référence) plutôt que PackedFloat32Array : ajouter à un tableau packé
	# rangé dans un Dictionary le recopie à chaque fois.
	var data: Array = buckets.get(key, [])
	if data.is_empty():
		buckets[key] = data
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	data.append_array([basis.x.x, basis.y.x, basis.z.x, pos.x,
			basis.x.y, basis.y.y, basis.z.y, pos.y,
			basis.x.z, basis.y.z, basis.z.z, pos.z])


func _cell_hash(x: int, z: int) -> int:
	return ((x * 73856093) ^ (z * 19349663) ^ (seed * 83492791)) & 0x7fffffff
