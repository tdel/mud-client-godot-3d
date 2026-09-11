extends Node3D
## Zone de paix (combat désactivé), convertie depuis l'objet Tiled type="peaceZone".
## `polygon_points` est en coordonnées cases (x, z), relatives à la position de ce nœud —
## purement informatif pour l'instant, aucune règle de jeu client ne s'appuie encore
## dessus (le layer d'objets Tiled n'était pas lu par ce client avant cette conversion).

@export var zone_name: String = ""
@export var polygon_points: PackedVector2Array = PackedVector2Array()
