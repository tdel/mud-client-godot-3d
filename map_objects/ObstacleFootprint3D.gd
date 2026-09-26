@tool
class_name ObstacleFootprint3D
extends Node3D
## Emprise au sol d'un obstacle posé sur une carte (fontaine, lampadaire, scierie, rocher...) :
## les cases dont le centre tombe dans cette forme deviennent non praticables à l'export
## serveur (voir tools/export_map_to_tmx.gd), en plus des terrains bloquants du GridMap
## (voir ZoneAssets3D.BLOCKING_TERRAINS). La case sous l'origine du nœud est toujours
## bloquée, même pour une emprise plus petite qu'une case (poteau, lampadaire).
##
## À placer comme enfant de la scène du prop (position/rotation/échelle suivent le prop). Le
## contour est dessiné en rouge dans l'éditeur uniquement ; en jeu le nœud n'affiche rien.
## Vegetation.gd s'en sert aussi pour ne pas faire pousser d'herbe à travers les props.

enum Shape { BOX, CIRCLE }

const GROUP := "map_obstacle"
const OUTLINE_COLOR := Color(1.0, 0.2, 0.15)

@export var shape: Shape = Shape.BOX:
	set(value):
		shape = value
		_update_outline()
## Dimensions X x Z (mètres, repère local) pour BOX.
@export var size := Vector2(1.0, 1.0):
	set(value):
		size = value
		_update_outline()
## Rayon (mètres) pour CIRCLE.
@export var radius := 0.5:
	set(value):
		radius = value
		_update_outline()

var _outline: MeshInstance3D


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_update_outline()


## Cases (x, z) de la grille de carte couvertes par cette emprise, d'après la transformation
## globale courante (le nœud doit être dans l'arbre).
func blocked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var xform := global_transform
	var outline := _world_outline(xform)
	var min_c := Vector2(INF, INF)
	var max_c := Vector2(-INF, -INF)
	for p in outline:
		min_c = min_c.min(p)
		max_c = max_c.max(p)
	var inverse := xform.affine_inverse()
	for z in range(floori(min_c.y), ceili(max_c.y) + 1):
		for x in range(floori(min_c.x), ceili(max_c.x) + 1):
			var local := inverse * Vector3(x + 0.5, xform.origin.y, z + 0.5)
			if _contains_local(Vector2(local.x, local.z)):
				cells.append(Vector2i(x, z))
	var origin_cell := Vector2i(floori(xform.origin.x), floori(xform.origin.z))
	if not cells.has(origin_cell):
		cells.append(origin_cell)
	return cells


func _contains_local(p: Vector2) -> bool:
	if shape == Shape.CIRCLE:
		return p.length() <= radius
	return absf(p.x) <= size.x / 2.0 and absf(p.y) <= size.y / 2.0


func _local_outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape == Shape.CIRCLE:
		for i in 24:
			var a := TAU * i / 24.0
			points.append(Vector2(cos(a), sin(a)) * radius)
	else:
		var h := size / 2.0
		points.append_array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	return points


func _world_outline(xform: Transform3D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in _local_outline():
		var w := xform * Vector3(p.x, 0.0, p.y)
		result.append(Vector2(w.x, w.z))
	return result


func _update_outline() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	if _outline == null:
		_outline = MeshInstance3D.new()
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = OUTLINE_COLOR
		mat.no_depth_test = true
		_outline.material_override = mat
		add_child(_outline, false, Node.INTERNAL_MODE_BACK)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var points := _local_outline()
	for i in points.size() + 1:
		var p := points[i % points.size()]
		mesh.surface_add_vertex(Vector3(p.x, 0.05, p.y))
	mesh.surface_end()
	_outline.mesh = mesh
