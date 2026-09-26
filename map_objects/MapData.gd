class_name MapData
extends Node3D
## Métadonnées d'une carte convertie depuis Tiled (voir tools/convert_tmx_to_scene.gd).
## Purement informatif/édition : la marchabilité et les dimensions réellement jouées
## restent celles envoyées par le serveur (MapView), voir Game3D._rebuild_map.

## Type de lieu, purement client : pilote l'ambiance sonore (voir autoload/ZoneMusic.gd,
## qui associe une musique à chaque biome). NONE = pas de musique de zone.
enum Biome { NONE, FOREST }

@export var map_id: String = ""
@export var map_name: String = ""
@export_multiline var description: String = ""
@export var is_starting_map: bool = false
@export var biome: Biome = Biome.NONE
