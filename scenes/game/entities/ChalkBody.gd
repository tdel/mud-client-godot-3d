extends Node3D
## (Préchargé sous le nom ChalkBody par Character.gd et Monster.gd.)
## "Craie" : simple bâton coloré sans squelette ni animation, affiché à la place du modèle
## d'un personnage (Character) ou d'un monstre (Monster) quand la case "Animations et skins
## (personnages et monstres)" est décochée (Settings.character_models_enabled, menu système >
## Graphisme).
##
## Le nœud lui-même est le pivot, posé au sol : la capsule se couche sur le dos autour de sa
## base à la mort (set_lying) et se relève à la résurrection.

## Bascule couchée/debout.
const FALL_TIME := 0.35

var _material: StandardMaterial3D
var _color: Color
var _radius: float
var _tween: Tween
var _flash_tween: Tween


func _init(radius: float, height: float, color: Color) -> void:
	name = "Chalk"
	_radius = radius
	_color = color
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	capsule.material = _material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = capsule
	mesh_instance.position.y = capsule.height / 2.0
	add_child(mesh_instance)


func set_color(color: Color) -> void:
	_color = color
	_material.albedo_color = color


## Couchée sur le dos (mort) ou debout ; relevée d'un rayon une fois couchée pour ne pas
## s'enfoncer à moitié dans le sol.
func set_lying(lying: bool, animate: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var angle := PI / 2.0 if lying else 0.0
	var lift := _radius if lying else 0.0
	if not animate or not is_inside_tree():
		rotation.x = angle
		position.y = lift
		return
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "rotation:x", angle, FALL_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if lying else Tween.EASE_OUT)
	_tween.tween_property(self, "position:y", lift, FALL_TIME)


## Éclair de couleur au coup reçu (voir Game3D._flash_entity).
func flash(color: Color, up_duration: float, down_duration: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "albedo_color", color, up_duration)
	_flash_tween.tween_property(_material, "albedo_color", _color, down_duration)
