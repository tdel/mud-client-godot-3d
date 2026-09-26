@tool
class_name EnvProp
extends Node3D
## Racine des scènes de props d'environnement simples (rochers, bûches, souches, abords de la
## scierie...) : applique les matériaux partagés (EnvMaterials) au modèle .glb instancié
## dessous. L'obstacle serveur éventuel est porté par un enfant ObstacleFootprint3D.


func _ready() -> void:
	EnvMaterials.apply(self)
