@tool
class_name TerrainGround
extends Node3D
## Sol texturé d'une carte décorée : un seul plan à la taille de la carte, rendu par
## terrain_ground.gdshader à partir d'une splat map (une texel par case) déduite du GridMap
## "Terrain" frère — le GridMap reste la donnée éditable (pinceau de l'éditeur, export
## serveur, minimap) mais n'est plus affiché. Après avoir repeint le GridMap dans
## l'éditeur, cliquer "Rafraîchir le sol" (ou rouvrir la scène).

## Terrain (nom d'item de la MeshLibrary) -> canal de splat : 0 = R sol forestier,
## 1 = G terre, 2 = B pavés, 3 = A herbe sombre. Absent = herbe (poids restant).
const CHANNEL_BY_TERRAIN := {
	"forestFloor": 0, "tree": 0, "deadTree": 0, "bramble": 0, "caveFloor": 0,
	"dirtPath": 1, "fieldCrop": 1, "dangerGround": 1, "rubble": 1,
	"pavedStone": 2, "fountain": 2, "gate": 2, "rampart": 2, "ironGate": 2, "auberge": 2, "forge": 1,
	"darkGrass": 3, "tallGrass": 3, "denseTallGrass": 3, "hedge": 3,
}
const TEX := "res://assets/environment/textures/"
const SHADER := preload("res://scenes/maps/common/terrain_ground.gdshader")

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
@export_tool_button("Rafraîchir le sol", "Reload") var refresh_action := rebuild

## Plan réellement affiché : enfant interne jamais enregistré dans la scène (la splat map
## est recalculée à chaque chargement, elle ne doit pas finir en base64 dans le .tscn).
var _ground: MeshInstance3D


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
	for item in library.get_item_list():
		channel_by_item[item] = CHANNEL_BY_TERRAIN.get(library.get_item_name(item), -1)
	var data := PackedByteArray()
	data.resize(width * height * 4)
	for z in height:
		for x in width:
			var item := grid_map.get_cell_item(Vector3i(x, 0, z))
			var channel: int = channel_by_item.get(item, -1)
			if channel >= 0:
				data[(z * width + x) * 4 + channel] = 255
	var splat := ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data))

	if _ground == null:
		_ground = MeshInstance3D.new()
		_ground.name = "Ground"
		add_child(_ground, false, Node.INTERNAL_MODE_BACK)
	var plane := PlaneMesh.new()
	plane.size = Vector2(width + margin * 2.0, height + margin * 2.0)
	plane.center_offset = Vector3(width / 2.0, 0.0, height / 2.0)
	_ground.mesh = plane
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
