class_name CharacterStage
extends SubViewportContainer
## Aperçu 3D d'un personnage hors jeu (écran de sélection) : le même Character.tscn qu'en jeu
## (mannequin homme/femme + équipement porté, voir Character.set_equipment) rendu dans un
## SubViewport à fond transparent, par-dessus le décor 2D de l'écran. Animation idle en
## boucle ; glisser à la souris (clic gauche maintenu) fait pivoter le personnage.

const CHARACTER_SCENE := preload("res://scenes/game/entities/Character.tscn")

## Radians par pixel de glissé horizontal.
const DRAG_SENSITIVITY := 0.012
## Orientation de repos : face caméra (les personnages regardent -Z en jeu, la caméra est
## en +Z) avec un léger trois-quarts.
const REST_YAW := PI - 0.35

var _viewport: SubViewport
var _character: Character
var _dragging := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	_build_stage()
	_character = CHARACTER_SCENE.instantiate()
	_character.rotation.y = REST_YAW
	_character.visible = false
	_viewport.add_child(_character)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.48, 0.58)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_viewport.add_child(env)
	# Décor nocturne : lumière principale tamisée de face, contre-jour froid (lune) derrière.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_color = Color(0.95, 0.88, 0.78)
	key.light_energy = 0.75
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 1.0
	_viewport.add_child(rim)
	# Sol invisible qui ne garde que l'ombre portée : le personnage ne flotte pas sur le décor.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.shadow_to_opacity = true
	ground_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	ground.material_override = ground_material
	_viewport.add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.0, 3.4)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 38
	_viewport.add_child(camera)


## `gender` : "MAN"/"WOMAN" (CharacterList) ; `equipment` : liste d'EquipmentView. Remet le
## personnage dans son orientation de repos.
func show_character(gender: String, equipment) -> void:
	_character.set_gender(gender)
	_character.set_equipment(Character.equipped_from_items(equipment), false)
	_character.play_state(Character.IDLE_ANIM)
	_character.rotation.y = REST_YAW
	_character.visible = true


func clear() -> void:
	_character.visible = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _dragging else Control.CURSOR_ARROW
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_character.rotation.y += event.relative.x * DRAG_SENSITIVITY
		accept_event()
