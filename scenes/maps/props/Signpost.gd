@tool
class_name Signpost
extends EnvProp
## Panneau indicateur : un poteau et une planche fléchée par destination. `destinations`
## liste des entrées "Texte|angle" où angle (degrés) est la direction pointée SUR LA CARTE,
## indépendamment de la rotation du nœud : 0 = est (+X, vers la droite de la carte),
## 90 = sud (+Z), 180 = ouest, 270 = nord. Exemple : "Place du village|0".
## Le texte est peint des deux côtés de la planche et réduit s'il est trop long.

const BOARD_SCENE := preload("res://assets/environment/models/signpost.glb")
const BOARD_TOP := 2.12
const BOARD_STEP := 0.3
## Zone utile de la planche (m, repère de la planche : de x=0.08 au poteau à x=1.15 à la
## pointe), pointe exclue.
const TEXT_CENTER_X := 0.52
const TEXT_MAX_WIDTH := 0.78
const TEXT_FONT_SIZE := 64
const TEXT_MAX_PIXEL_SIZE := 0.0036
const TEXT_COLOR := Color(0.96, 0.9, 0.74)
const TEXT_OUTLINE := Color(0.16, 0.1, 0.05)

@export var destinations: PackedStringArray = PackedStringArray(["Destination|0"]):
	set(value):
		destinations = value
		if is_inside_tree():
			_build_boards()

var _boards: Node3D
var _board_mesh: Mesh


func _ready() -> void:
	super()
	_build_boards()


func _build_boards() -> void:
	if _boards != null:
		_boards.queue_free()
	_boards = Node3D.new()
	add_child(_boards, false, Node.INTERNAL_MODE_BACK)
	if _board_mesh == null:
		var model := BOARD_SCENE.instantiate()
		var board_node := model.find_child("sign_board", true, false) as MeshInstance3D
		_board_mesh = EnvMaterials.remap_mesh(board_node.mesh)
		model.free()
		# Le modèle instancié par la scène contient aussi une planche : on la cache, les
		# planches sont reconstruites ici selon `destinations`.
		var own_board := find_child("sign_board", true, false)
		if own_board != null:
			own_board.visible = false
	var font: Font = ThemeDB.fallback_font
	for i in destinations.size():
		var parts := destinations[i].split("|")
		var text := parts[0]
		var angle := float(parts[1]) if parts.size() > 1 else 0.0
		var board := MeshInstance3D.new()
		board.mesh = _board_mesh
		_boards.add_child(board)
		# Rotation monde voulue : +X local vers (cos a, sin a) sur le plan (x, z) — soit
		# -a autour de Y — compensée de la rotation propre du panneau.
		board.global_rotation = Vector3(0.0, -deg_to_rad(angle), 0.0)
		board.position.y = BOARD_TOP - i * BOARD_STEP
		var width_px := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_FONT_SIZE).x
		var pixel_size := minf(TEXT_MAX_PIXEL_SIZE, TEXT_MAX_WIDTH / maxf(width_px, 1.0))
		for side in [1.0, -1.0]:
			var label := Label3D.new()
			label.text = text
			label.font_size = TEXT_FONT_SIZE
			label.pixel_size = pixel_size
			label.modulate = TEXT_COLOR
			label.outline_modulate = TEXT_OUTLINE
			label.outline_size = 10
			label.shaded = true
			label.double_sided = false
			label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
			label.position = Vector3(TEXT_CENTER_X, 0.0, 0.026 * side)
			if side < 0.0:
				label.rotation.y = PI
			board.add_child(label)
