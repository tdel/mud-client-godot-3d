@tool
class_name TerrainGround
extends Node3D
## Sol texturé d'une carte décorée : un seul plan à la taille de la carte, rendu par
## terrain_ground.gdshader à partir d'une splat map (une texel par case) déduite du GridMap
## "Terrain" frère — le GridMap reste la donnée éditable (pinceau de l'éditeur, export
## serveur, minimap) mais n'est plus affiché. Après avoir repeint le GridMap dans
## l'éditeur, cliquer "Rafraîchir le sol" (ou rouvrir la scène).
##
## Rivières : les cases "water" (non praticables) et "bridge" (praticables, sous le tablier
## d'un pont) sont creusées sous le niveau du sol — berges en pente puis lit à -river_depth,
## surface d'eau à water_level (river_water.gdshader). Le sol devient alors un maillage par
## blocs de CHUNK m : un simple quad loin de l'eau, une grille fine (FINE_STEP m) autour, dont
## la hauteur suit un champ de distance signé à la rivière (lissé, bords bruités). Les
## personnages restant à y = 0, les cases praticables ne sont jamais creusées (la berge
## commence au bord des cases d'eau) et les ponts ont leur tablier au ras du sol.

## Terrain (nom d'item de la MeshLibrary) -> canal de splat : 0 = R sol forestier,
## 1 = G terre, 2 = B pavés, 3 = A herbe sombre. Absent = herbe (poids restant).
const CHANNEL_BY_TERRAIN := {
	"forestFloor": 0, "tree": 0, "deadTree": 0, "bramble": 0, "caveFloor": 0, "thicket": 0,
	"dirtPath": 1, "fieldCrop": 1, "dangerGround": 1, "rubble": 1, "water": 1, "bridge": 1,
	"pavedStone": 2, "fountain": 2, "gate": 2, "rampart": 2, "ironGate": 2, "auberge": 2, "forge": 1,
	"darkGrass": 3, "tallGrass": 3, "denseTallGrass": 3, "hedge": 3,
}
const TEX := "res://assets/environment/textures/"
const SHADER := preload("res://scenes/maps/common/terrain_ground.gdshader")
const WATER_SHADER := preload("res://scenes/maps/common/river_water.gdshader")
const RIVER_TERRAINS := {"water": true, "bridge": true}
const CHUNK := 16.0
const FINE_STEP := 0.5
## Rayon (cases) de calcul du champ de distance autour de la rivière.
const SDF_REACH := 5

@export var grid_map_path: NodePath = ^"../Terrain"
## Débord (m) du sol au-delà des limites de la carte, purement visuel : la caméra ne montre
## jamais le vide près des bords. Les cases de bordure s'y prolongent (la splat map est
## lue en mode "clamp"), une route qui sort de la carte continue donc au-delà.
@export var margin := 30.0
## Pavés (canal B) : asset ambientCG d'assets/environment/textures, mètres couverts par une
## répétition, désaturation et teinte — vieille route moussue par défaut, pavés de ville
## pour le village.
@export var paved_asset := "PavingStones138"
@export var paved_tile := Vector2(1.6, 3.2)
@export_range(0.0, 1.0) var paved_desaturate := 0.55
@export var paved_tint := Color(0.66, 0.66, 0.68)
## Rivière : profondeur du lit, niveau de l'eau (m, sous le sol) et largeur (cases) de la
## berge en pente, prise sur le bord des cases d'eau.
@export var river_depth := 2.0
@export var water_level := -1.1
@export var bank_width := 1.7
@export_tool_button("Rafraîchir le sol", "Reload") var refresh_action := rebuild

## Plan réellement affiché : enfant interne jamais enregistré dans la scène (la splat map
## est recalculée à chaque chargement, elle ne doit pas finir en base64 dans le .tscn).
var _ground: MeshInstance3D
var _water: MeshInstance3D
## Champ de distance signé (cases, négatif dans la rivière) sur la carte étendue de la marge,
## voir _build_river_sdf ; vide sans rivière.
var _sdf := PackedFloat32Array()
var _sdf_size := Vector2i.ZERO
var _sdf_origin := 0
var _bank_noise := FastNoiseLite.new()


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var grid_map := get_node_or_null(grid_map_path) as GridMap
	if grid_map == null:
		push_warning("TerrainGround: GridMap introuvable (%s)" % grid_map_path)
		return
	var width := 0
	var height := 0
	for cell in grid_map.get_used_cells():
		width = maxi(width, cell.x + 1)
		height = maxi(height, cell.z + 1)
	if width == 0 or height == 0:
		return

	var library := grid_map.mesh_library
	var channel_by_item := {}
	var river_items := {}
	for item in library.get_item_list():
		channel_by_item[item] = CHANNEL_BY_TERRAIN.get(library.get_item_name(item), -1)
		if RIVER_TERRAINS.has(library.get_item_name(item)):
			river_items[item] = true
	var data := PackedByteArray()
	data.resize(width * height * 4)
	var river := PackedByteArray()
	river.resize(width * height)
	var has_river := false
	for z in height:
		for x in width:
			var item := grid_map.get_cell_item(Vector3i(x, 0, z))
			var channel: int = channel_by_item.get(item, -1)
			if channel >= 0:
				data[(z * width + x) * 4 + channel] = 255
			if river_items.has(item):
				river[z * width + x] = 1
				has_river = true
	var splat := ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data))

	if _ground == null:
		_ground = MeshInstance3D.new()
		_ground.name = "Ground"
		add_child(_ground, false, Node.INTERNAL_MODE_BACK)
	if has_river:
		_build_river_sdf(river, width, height)
		_ground.mesh = _build_channel_mesh(width, height)
	else:
		_sdf = PackedFloat32Array()
		var plane := PlaneMesh.new()
		plane.size = Vector2(width + margin * 2.0, height + margin * 2.0)
		plane.center_offset = Vector3(width / 2.0, 0.0, height / 2.0)
		_ground.mesh = plane
		if _water != null:
			_water.queue_free()
			_water = null
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("splat_map", splat)
	mat.set_shader_parameter("map_size", Vector2(width, height))
	mat.set_shader_parameter("paved_tile", paved_tile)
	mat.set_shader_parameter("paved_desaturate", paved_desaturate)
	mat.set_shader_parameter("paved_tint", paved_tint)
	for prefix_asset in [["grass", "Grass004"], ["forest", "Ground037"], ["dirt", "Ground067"], ["paved", paved_asset]]:
		var asset: String = prefix_asset[1]
		mat.set_shader_parameter(prefix_asset[0] + "_albedo", load(TEX + asset + "_color.jpg"))
		mat.set_shader_parameter(prefix_asset[0] + "_normal", load(TEX + asset + "_normal.jpg"))
		mat.set_shader_parameter(prefix_asset[0] + "_rough", load(TEX + asset + "_rough.jpg"))
	_ground.material_override = mat
	grid_map.visible = false


## Hauteur du sol (m) au point (x, z) du monde : 0 hors de la rivière, négative dans son lit.
func ground_height(x: float, z: float) -> float:
	if _sdf.is_empty():
		return 0.0
	var s := _sdf_at(x, z) + _bank_noise.get_noise_2d(x, z) * 0.35
	if s >= 0.0:
		return 0.0
	var t := smoothstep(0.0, bank_width, -s)
	return -river_depth * t + _bank_noise.get_noise_2d(x * 3.1 + 50.0, z * 3.1) * 0.18 * t


## Distance signée (cases) au bord des cases de rivière, négative dedans, calculée d'un centre
## de case à l'autre puis ramenée au bord (±0,5) ; plafonnée à ±SDF_REACH. La carte est
## étendue de la marge visuelle en prolongeant les cases de bord (comme la splat map) : une
## rivière qui sort de la carte continue jusqu'au bout du sol.
func _build_river_sdf(river: PackedByteArray, width: int, height: int) -> void:
	_bank_noise.seed = 4242
	_bank_noise.frequency = 0.18
	var m := ceili(margin)
	var ew := width + 2 * m
	var eh := height + 2 * m
	var ext := PackedByteArray()
	ext.resize(ew * eh)
	var river_cells := PackedInt32Array()
	for ez in eh:
		var row := clampi(ez - m, 0, height - 1) * width
		for ex in ew:
			if river[row + clampi(ex - m, 0, width - 1)] == 1:
				ext[ez * ew + ex] = 1
				river_cells.append(ez * ew + ex)
	_sdf = PackedFloat32Array()
	_sdf.resize(ew * eh)
	_sdf.fill(float(SDF_REACH))
	for i in river_cells:
		_sdf[i] = -float(SDF_REACH)
	for i in river_cells:
		var rx := i % ew
		var rz := i / ew
		var nearest_land := float(SDF_REACH) + 0.5
		for dz in range(-SDF_REACH, SDF_REACH + 1):
			var z := rz + dz
			if z < 0 or z >= eh:
				continue
			for dx in range(-SDF_REACH, SDF_REACH + 1):
				var x := rx + dx
				if x < 0 or x >= ew:
					continue
				var j := z * ew + x
				if ext[j] == 1:
					continue
				var d := sqrt(float(dx * dx + dz * dz))
				if d - 0.5 < _sdf[j]:
					_sdf[j] = d - 0.5
				nearest_land = minf(nearest_land, d)
		_sdf[i] = maxf(_sdf[i], 0.5 - nearest_land)
	_sdf_size = Vector2i(ew, eh)
	_sdf_origin = m


## Lecture bilinéaire du champ de distance (valeurs aux centres de cases).
func _sdf_at(x: float, z: float) -> float:
	var fx := clampf(x + _sdf_origin - 0.5, 0.0, _sdf_size.x - 1.001)
	var fz := clampf(z + _sdf_origin - 0.5, 0.0, _sdf_size.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * _sdf_size.x + ix
	var a := lerpf(_sdf[i], _sdf[i + 1], tx)
	var b := lerpf(_sdf[i + _sdf_size.x], _sdf[i + _sdf_size.x + 1], tx)
	return lerpf(a, b, tz)


## Sol en blocs de CHUNK m : grille fine là où la rivière (ou sa berge) passe, un quad
## ailleurs. Les arêtes entre bloc fin et bloc grossier sont toujours à hauteur 0 (un bloc est
## fin dès que la rivière approche à moins de 2 cases de lui) : pas de fente. Construit aussi
## la surface d'eau (un quad par bloc dont le lit descend sous water_level).
func _build_channel_mesh(width: int, height: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	var water_verts := PackedVector3Array()
	var water_indices := PackedInt32Array()
	var x_max := width + margin
	var z_max := height + margin
	var cz0 := -margin
	while cz0 < z_max - 0.001:
		var cz1 := minf(cz0 + CHUNK, z_max)
		var cx0 := -margin
		while cx0 < x_max - 0.001:
			var cx1 := minf(cx0 + CHUNK, x_max)
			if _chunk_near_river(cx0, cz0, cx1, cz1):
				if _add_fine_chunk(verts, normals, tangents, indices, cx0, cz0, cx1, cz1):
					var base := water_verts.size()
					water_verts.append_array([Vector3(cx0, water_level, cz0), Vector3(cx1, water_level, cz0),
							Vector3(cx1, water_level, cz1), Vector3(cx0, water_level, cz1)])
					water_indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			else:
				var base := verts.size()
				verts.append_array([Vector3(cx0, 0, cz0), Vector3(cx1, 0, cz0), Vector3(cx1, 0, cz1), Vector3(cx0, 0, cz1)])
				for k in 4:
					normals.append(Vector3.UP)
					tangents.append_array([1.0, 0.0, 0.0, 1.0])
				indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			cx0 = cx1
		cz0 = cz1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "Water"
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water, false, Node.INTERNAL_MODE_BACK)
	var water_mesh := ArrayMesh.new()
	if not water_verts.is_empty():
		var up := PackedVector3Array()
		up.resize(water_verts.size())
		up.fill(Vector3.UP)
		var water_arrays := []
		water_arrays.resize(Mesh.ARRAY_MAX)
		water_arrays[Mesh.ARRAY_VERTEX] = water_verts
		water_arrays[Mesh.ARRAY_NORMAL] = up
		water_arrays[Mesh.ARRAY_INDEX] = water_indices
		water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water_arrays)
	_water.mesh = water_mesh
	var water_mat := ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	_water.material_override = water_mat
	return mesh


func _chunk_near_river(x0: float, z0: float, x1: float, z1: float) -> bool:
	for z in range(floori(z0) - 2, ceili(z1) + 2):
		for x in range(floori(x0) - 2, ceili(x1) + 2):
			if _sdf_at(x + 0.5, z + 0.5) < 1.0:
				return true
	return false


## Grille fine d'un bloc ; renvoie vrai si le lit y descend sous le niveau de l'eau.
func _add_fine_chunk(verts: PackedVector3Array, normals: PackedVector3Array, tangents: PackedFloat32Array,
		indices: PackedInt32Array, x0: float, z0: float, x1: float, z1: float) -> bool:
	var nx := ceili((x1 - x0) / FINE_STEP)
	var nz := ceili((z1 - z0) / FINE_STEP)
	var sx := (x1 - x0) / nx
	var sz := (z1 - z0) / nz
	# Hauteurs avec une rangée de bord en plus, pour les normales par différences centrées.
	var gw := nx + 3
	var h := PackedFloat32Array()
	h.resize(gw * (nz + 3))
	var wet := false
	for j in nz + 3:
		for i in gw:
			var y := ground_height(x0 + (i - 1) * sx, z0 + (j - 1) * sz)
			h[j * gw + i] = y
			if y < water_level:
				wet = true
	var base := verts.size()
	for j in nz + 1:
		for i in nx + 1:
			var k := (j + 1) * gw + i + 1
			var dx := (h[k + 1] - h[k - 1]) / (2.0 * sx)
			var dz := (h[k + gw] - h[k - gw]) / (2.0 * sz)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			var t := (Vector3(1.0, dx, 0.0) - n * n.dot(Vector3(1.0, dx, 0.0))).normalized()
			verts.append(Vector3(x0 + i * sx, h[k], z0 + j * sz))
			normals.append(n)
			tangents.append_array([t.x, t.y, t.z, 1.0])
	for j in nz:
		for i in nx:
			var a := base + j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 2
			var d := a + nx + 1
			indices.append_array([a, b, c, a, c, d])
	return wet
