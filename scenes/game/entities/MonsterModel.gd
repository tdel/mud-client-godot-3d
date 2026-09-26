class_name MonsterModel
extends Resource
## Fiche visuelle d'un monstre (une .tres par modèle, voir assets/monsters/<monstre>/) :
## quel .glb afficher, à quelle échelle, et quels clips de son AnimationPlayer jouer pour
## chacun des états logiques de Monster.gd (idle/run/attack/death). Reliée aux noms serveur
## par MonsterCatalog.
##
## Les clips sont désignés par leur nom dans le .glb, tel qu'importé par Godot (ex. "Gallop"
## pour la course du renard Quaternius) : chaque pack nomme ses animations à sa façon, cette
## fiche fait la traduction.

## Modèle importé (.glb) contenant un AnimationPlayer.
@export var scene: PackedScene
## Échelle uniforme appliquée au modèle (les packs sont rarement à l'échelle du jeu, où un
## personnage mesure ~1.75).
@export var model_scale := 1.0
## Rotation Y (degrés) pour que le museau pointe vers -Z comme les entités du jeu (voir
## Game3D._face_heading, qui oriente via look_at). 180 pour un glTF qui regarde +Z.
@export var yaw_degrees := 180.0

@export_group("Animations")
@export var idle_anim: StringName = &"Idle"
@export var run_anim: StringName = &"Run"
@export var attack_anim: StringName = &"Attack"
@export var death_anim: StringName = &"Death"
## Vitesse de lecture de la course (à caler sur la vitesse de déplacement pour éviter que les
## pattes glissent).
@export var run_speed_scale := 1.0
## Vitesse de lecture de l'attaque.
@export var attack_speed_scale := 1.0

@export_group("Gabarit")
## Sommet de la silhouette : base du nom et des barres flottantes (voir
## Game3D._layout_overhead).
@export var head_height := 1.0
## Zone cliquable (capsule verticale, voir Game3D._make_entity_node).
@export var pick_radius := 0.35
@export var pick_height := 1.0
