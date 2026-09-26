class_name MapData
extends Node3D
## Métadonnées d'une carte (racine de chaque scène res://scenes/maps/*.tscn). Exportées vers
## le serveur par tools/export_map_to_tmx.gd (propriétés id/name/description/isStartingMap
## du .tmx) ; en jeu, la marchabilité et les dimensions restent celles envoyées par le
## serveur (MapView), voir Game3D._rebuild_map.

## Type de lieu, purement client : pilote l'ambiance sonore (voir autoload/ZoneMusic.gd,
## qui associe une musique à chaque biome). NONE = pas de musique de zone.
enum Biome { NONE, FOREST }

@export var map_id: String = ""
@export var map_name: String = ""
@export_multiline var description: String = ""
@export var is_starting_map: bool = false
@export var biome: Biome = Biome.NONE
## true (cartes converties depuis Tiled) : Game3D dessine un bloc gris sur chaque case non
## praticable, faute d'autre représentation. false pour une carte décorée à la main (arbres,
## props avec ObstacleFootprint3D, sol TerrainGround) : ses obstacles sont déjà visibles.
@export var render_obstacle_blocks: bool = true
