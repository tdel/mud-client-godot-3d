extends Node
## Terrain et cartes : depuis la migration vers l'éditeur Godot interne (les cartes sont
## désormais des scènes res://scenes/maps/*.tscn contenant un GridMap peint avec
## assets/terrain/terrain_library.res, voir tools/convert_tmx_to_scene.gd), ce fichier ne
## garde que : (1) l'annuaire nom de carte -> chemin de scène, construit une fois au
## démarrage en scannant scenes/maps/ (équivalent du _scan_map_files historique, qui
## scannait des .tmx) et (2) les données de terrain encore utiles à Game3D après coup —
## couleurs simplifiées pour la minimap (TERRAIN_COLORS) et hauteur d'obstacle
## (TALL_OBSTACLE_TERRAINS) — le nom de terrain par case étant désormais lu en direct sur
## le GridMap de la scène instanciée (voir Game3D._read_terrain_grid) plutôt que stocké ici.
## Comme avant la migration, le walkable/non-walkable envoyé par le serveur
## (MapView.grid.walkableRows) reste l'unique source de vérité pour les règles de jeu : les
## scènes de carte ne servent qu'au rendu (sol, hauteur d'obstacle, lumières de nuit).
##
## Prototype : ce fichier ne fait QUE le rendu du sol/des obstacles. Combat, sorts,
## équipement visuel, animations ne sont pas dans le scope de ce prototype (voir
## scenes/game/Game3D.gd).

const MAP_SCENES_DIR := "res://scenes/maps"
const PX_PER_TILE := 4

## Couleurs de terrain — copiées telles quelles depuis ZoneAssets.gd (2D) pour rester
## visuellement cohérentes entre les deux prototypes.
const TERRAIN_COLORS := {
	"rampart": Color(0.35, 0.35, 0.38), "gate": Color(0.55, 0.45, 0.30),
	"pavedStone": Color(0.62, 0.62, 0.65), "fountain": Color(0.25, 0.55, 0.78),
	"auberge": Color(0.72, 0.42, 0.22), "forge": Color(0.50, 0.22, 0.18),
	"dirtPath": Color(0.55, 0.42, 0.28), "grass": Color(0.32, 0.56, 0.26),
	"tree": Color(0.18, 0.40, 0.20), "forestFloor": Color(0.35, 0.38, 0.22),
	"fieldCrop": Color(0.72, 0.65, 0.28), "fence": Color(0.60, 0.50, 0.35),
	"hedge": Color(0.22, 0.42, 0.22), "bramble": Color(0.35, 0.32, 0.18),
	"darkGrass": Color(0.22, 0.38, 0.20), "clearingGrass": Color(0.40, 0.62, 0.30),
	"tallGrass": Color(0.30, 0.50, 0.24), "denseTallGrass": Color(0.24, 0.42, 0.20),
	"tallGrassPatch": Color(0.34, 0.52, 0.26), "ironGate": Color(0.30, 0.30, 0.32),
	"deadTree": Color(0.40, 0.35, 0.30), "dangerGround": Color(0.45, 0.40, 0.35),
	"grave": Color(0.45, 0.45, 0.50), "mausoleum": Color(0.55, 0.55, 0.58),
	"rockWall": Color(0.30, 0.28, 0.27), "caveFloor": Color(0.32, 0.28, 0.26),
	"rubble": Color(0.40, 0.38, 0.36),
}
const WALKABLE_FALLBACK_COLOR := Color(0.40, 0.60, 0.35)
const BLOCKED_FALLBACK_COLOR := Color(0.25, 0.25, 0.28)

## Terrains non franchissables qu'on affiche plus hauts (mur/rempart/tronc) qu'un simple
## obstacle bas (buisson/débris/tombe) — purement cosmétique, choisi à la main faute
## d'information de hauteur dans le protocole.
const TALL_OBSTACLE_TERRAINS := {
	"rampart": true, "tree": true, "ironGate": true, "rockWall": true,
	"mausoleum": true, "deadTree": true, "gate": true,
}

## map_name (propriété "name" exportée par MapData.gd sur la racine de la scène) -> chemin
## de la scène res://scenes/maps/*.tscn correspondante — voir _scan_map_scenes.
var _map_scene_path_by_name: Dictionary = {}


func _ready() -> void:
	_scan_map_scenes()


## Chemin de la scène convertie pour `map_name` (nom envoyé par le serveur dans
## MapView.mapName), ou "" si aucune carte n'a été convertie sous ce nom — voir
## Game3D._rebuild_map, qui instancie cette scène pour le rendu du sol.
func get_map_scene_path(map_name: String) -> String:
	return _map_scene_path_by_name.get(map_name, "")


## Construit une texture de sol simplifiée pour la minimap (une passe, un seul quad à
## l'usage — voir Game3D._minimap) : PX_PER_TILE x PX_PER_TILE pixels par case, coloré par
## terrain connu ou par un fallback marche/bloqué déterminé par le grid serveur.
## `terrain_grid` (Array[Array[String]]) est lu par l'appelant sur le GridMap de la carte
## tout juste instanciée, voir Game3D._read_terrain_grid.
func build_ground_texture(map_view_payload: Dictionary, terrain_grid: Array) -> ImageTexture:
	var grid: Dictionary = map_view_payload.get("grid", {})
	var width: int = grid.get("width", 0)
	var height: int = grid.get("height", 0)
	var walkable_rows: Array = grid.get("walkableRows", [])

	var image := Image.create(maxi(width * PX_PER_TILE, 1), maxi(height * PX_PER_TILE, 1), false, Image.FORMAT_RGBA8)

	var rng := RandomNumberGenerator.new()
	for y in height:
		var row: String = walkable_rows[y] if y < walkable_rows.size() else ""
		var terrain_row: Array = terrain_grid[y] if y < terrain_grid.size() else []
		for x in width:
			var walkable: bool = x < row.length() and row[x] == "1"
			var terrain_name: String = terrain_row[x] if x < terrain_row.size() else ""
			var base_color: Color = TERRAIN_COLORS.get(
				terrain_name,
				WALKABLE_FALLBACK_COLOR if walkable else BLOCKED_FALLBACK_COLOR
			)
			rng.seed = hash(Vector2i(x, y))
			var variance := rng.randf_range(-0.05, 0.05)
			var cell_color := Color(
				clampf(base_color.r + variance, 0.0, 1.0),
				clampf(base_color.g + variance, 0.0, 1.0),
				clampf(base_color.b + variance, 0.0, 1.0),
			)
			image.fill_rect(Rect2i(x * PX_PER_TILE, y * PX_PER_TILE, PX_PER_TILE, PX_PER_TILE), cell_color)
			# Liseré assombri sur les deux bords haut/gauche de la case : ancre visuellement
			# le sol vu de l'angle iso sans le bruit de moiré qu'un pixel isolé par coin
			# donnait sous filtrage "nearest" à cet angle (essayé, retiré).
			var edge_color := cell_color.darkened(0.18)
			image.fill_rect(Rect2i(x * PX_PER_TILE, y * PX_PER_TILE, PX_PER_TILE, 1), edge_color)
			image.fill_rect(Rect2i(x * PX_PER_TILE, y * PX_PER_TILE, 1, PX_PER_TILE), edge_color)

	var texture := ImageTexture.create_from_image(image)
	return texture


## Hauteur d'obstacle (mètres) pour une case non franchissable de terrain `terrain_name`,
## ou 0.0 si franchissable — Game3D construit un MultiMeshInstance3D de blocs à partir de
## cette info (voir Game3D._rebuild_obstacles). Purement cosmétique : la vraie règle de
## collision reste walkableRows côté serveur, jamais recalculée ici.
func obstacle_height_for(terrain_name: String, walkable: bool) -> float:
	if walkable:
		return 0.0
	return 2.4 if TALL_OBSTACLE_TERRAINS.get(terrain_name, false) else 0.7


## Scanne res://scenes/maps/*.tscn une fois au démarrage pour indexer chaque scène par sa
## propriété `map_name` (exportée par MapData.gd sur la racine, voir
## tools/convert_tmx_to_scene.gd) — équivalent du _scan_map_files historique, qui indexait
## les .tmx par leur propriété Tiled "name". Instancie brièvement chaque scène pour lire
## cette propriété puis la libère aussitôt : Game3D ne garde en mémoire que la carte
## réellement affichée (voir Game3D._rebuild_map), pas les sept à la fois.
func _scan_map_scenes() -> void:
	var dir := DirAccess.open(MAP_SCENES_DIR)
	if dir == null:
		push_warning("ZoneAssets3D: dossier introuvable: %s" % MAP_SCENES_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tscn"):
			_index_map_scene(MAP_SCENES_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _index_map_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("ZoneAssets3D: scène illisible: %s" % path)
		return
	var root: Node3D = packed.instantiate()
	var map_name: String = root.map_name
	root.free()
	if map_name.is_empty():
		push_warning("ZoneAssets3D: pas de map_name dans %s" % path)
		return
	_map_scene_path_by_name[map_name] = path
