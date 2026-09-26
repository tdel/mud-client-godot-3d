class_name MapBoundsVeil
extends MeshInstance3D
## Voile gris sur tout ce qui est hors des bornes de la carte (voir map_bounds_veil.gdshader) :
## le décor des cartes déborde de la grille praticable, la limite doit rester lisible. À poser
## en enfant de la caméra (Game3D._ready, MapPreview) : le vertex shader le place en plein
## écran, sa position locale le garde simplement dans le frustum.

const SHADER := preload("res://scenes/game/map_bounds_veil.gdshader")

var _mat: ShaderMaterial


func _init() -> void:
	name = "MapBoundsVeil"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	# Premier des objets transparents : la texture d'écran lue par le shader ne les contient
	# pas encore, le voile les effacerait sinon (nom, anneau de cible, colonne d'un portail
	# de lisière qui se projette au-dessus de l'extérieur de la carte).
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func _ready() -> void:
	var camera := get_parent() as Camera3D
	position = Vector3(0.0, 0.0, -(camera.near + 1.0) if camera != null else -1.0)


## Taille de la grille en tuiles (x, z monde) ; Vector2.ZERO coupe le voile.
func set_map_size(map_size: Vector2) -> void:
	_mat.set_shader_parameter("map_size", map_size)
