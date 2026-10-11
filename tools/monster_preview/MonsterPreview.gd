extends Node3D
## Outil de développement (hors jeu) : un mannequin pour l'échelle, puis le monstre demandé
## dans chacun de ses états (idle, run, attack, death), enregistre une capture PNG et quitte.
## Sert à régler une fiche MonsterModel (échelle, orientation, noms des clips, gabarit).
##
## Usage :
##   Godot_console.exe --path . res://tools/monster_preview/MonsterPreview.tscn -- \
##       --monster=Fox --time=0.4 --view=iso --out=C:/tmp/fox.png
## --monster : nom serveur (voir MonsterCatalog) ; --time : secondes dans les clips ;
## --view : side (profil, défaut) ou iso (caméra du jeu, voir Game3D).
## --gallery=Nom1,Nom2,... : un exemplaire de chaque monstre listé, côte à côte, dans l'état
## --state (idle par défaut, ou run/attack/death) ; --gallery=all : tout MonsterCatalog.MODELS.
## Sans --out, la scène reste ouverte (animations en boucle, pratique dans l'éditeur).
## Le trait jaune au-dessus de chaque monstre marque head_height, le cylindre filaire la zone
## cliquable (pick_radius/pick_height).

const CHARACTER_SCENE := preload("res://scenes/game/entities/Character.tscn")
const STATES := ["idle", "run", "attack", "death"]
const SPACING := 1.6

var _monster_name := "Fox"
var _time := 0.4
var _view := "side"
var _out := ""
var _gallery: PackedStringArray = []
var _state := "idle"
var _monsters: Array[Monster] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--monster="):
			_monster_name = arg.substr(10)
		elif arg.begins_with("--time="):
			_time = float(arg.substr(7))
		elif arg.begins_with("--view="):
			_view = arg.substr(7)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--gallery="):
			var names := arg.substr(10)
			_gallery = PackedStringArray(MonsterCatalog.MODELS.keys()) if names == "all" else names.split(",")
		elif arg.begins_with("--state="):
			_state = arg.substr(8)
	if not _gallery.is_empty():
		_build_gallery()
		return
	var model := MonsterCatalog.model_for(_monster_name)
	if model == null:
		push_error("MonsterPreview: aucun modèle pour %s" % _monster_name)
		get_tree().quit(1)
		return
	_build_stage()
	var reference: Character = CHARACTER_SCENE.instantiate()
	add_child(reference)
	reference.position = Vector3(-SPACING * 2.5, 0, 0)
	reference.rotation.y = PI
	for i in STATES.size():
		var monster := Monster.new()
		monster.setup(model)
		add_child(monster)
		monster.position = Vector3((i - 1.5) * SPACING, 0, 0)
		# Profil : museau vers la gauche (-X), comme s'il courait vers le mannequin.
		monster.look_at(monster.position + Vector3.LEFT, Vector3.UP)
		_monsters.append(monster)
		_add_markers(monster.position, model)
	_start.call_deferred()


## Galerie : rangées de 6, mannequin de référence en tête de la première, nom au-dessus.
func _build_gallery() -> void:
	var columns := 6
	var rows := ceili(_gallery.size() / float(columns))
	_build_stage(Vector2(columns * 2.4, rows * 2.6))
	var reference: Character = CHARACTER_SCENE.instantiate()
	add_child(reference)
	reference.position = Vector3(-1.6, 0, 0)
	reference.rotation.y = PI
	for i in _gallery.size():
		var model := MonsterCatalog.model_for(_gallery[i])
		if model == null:
			push_warning("MonsterPreview: aucun modèle pour %s" % _gallery[i])
			continue
		var monster := Monster.new()
		monster.setup(model)
		add_child(monster)
		monster.position = Vector3((i % columns) * 2.4 + 0.8, 0, (i / columns) * 2.6)
		monster.look_at(monster.position + Vector3(-1, 0, 1), Vector3.UP)
		var label := Label3D.new()
		label.text = _gallery[i]
		label.font_size = 40
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = monster.position + Vector3(0, model.head_height + 0.35, 0)
		add_child(label)
		_monsters.append(monster)
	_start.call_deferred()


func _build_stage(gallery_size := Vector2.ZERO) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 6)
	ground.mesh = plane
	add_child(ground)
	var camera := Camera3D.new()
	if gallery_size != Vector2.ZERO:
		plane.size = gallery_size + Vector2(6, 6)
		ground.position = Vector3(gallery_size.x / 2.0 - 1.0, 0, gallery_size.y / 2.0 - 1.3)
		camera.position = ground.position + Vector3(0, gallery_size.y * 0.9 + 3.0, gallery_size.y * 0.8 + 6.0)
		camera.look_at_from_position(camera.position, ground.position + Vector3(0, 0.5, 0), Vector3.UP)
		camera.fov = 50
	elif _view == "iso":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 6.0
		camera.position = Vector3(-1.2, 8, 8)
		camera.look_at_from_position(camera.position, Vector3(-1.2, 0, 0), Vector3.UP)
	else:
		camera.position = Vector3(-1.2, 0.9, 7.5)
		camera.rotation_degrees = Vector3(-4, 0, 0)
		camera.fov = 40
	add_child(camera)


func _add_markers(at: Vector3, model: MonsterModel) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.85, 0.2)
	var head := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.5, 0.015, 0.015)
	bar.material = mat
	head.mesh = bar
	head.position = at + Vector3(0, model.head_height, 0)
	add_child(head)
	var pick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = model.pick_radius
	cyl.bottom_radius = model.pick_radius
	cyl.height = model.pick_height
	var wire := StandardMaterial3D.new()
	wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire.albedo_color = Color(0.3, 0.8, 1.0, 0.12)
	cyl.material = wire
	pick.mesh = cyl
	pick.position = at + Vector3(0, model.pick_height / 2.0, 0)
	add_child(pick)


func _start() -> void:
	for i in _monsters.size():
		match STATES[i] if _gallery.is_empty() else _state:
			"run":
				_monsters[i].play_state(Monster.RUN_STATE)
			"attack":
				_monsters[i].play_attack()
			"death":
				_monsters[i].play_death()
	if _out.is_empty():
		return
	await get_tree().create_timer(_time).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	get_tree().quit()
