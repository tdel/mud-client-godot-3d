class_name Monster
extends Node3D
## Corps animé d'un monstre (voir MonsterModel/MonsterCatalog) : instancié par
## Game3D._make_entity_node comme "Body" d'un monstre qui a un modèle dédié, à la place de la
## capsule rouge.
##
## Même vocabulaire que Character.gd pour que Game3D pilote les deux de la même façon :
## play_state("idle"/"run") pour l'état tenu, play_attack() revient seul à cet état une fois
## le coup fini, play_death() reste figé sur la dernière image. Les noms logiques sont
## traduits en clips du .glb par la fiche MonsterModel.
##
## Case "Animations et skins (personnages et monstres)" décochée (Settings.character_models_enabled) :
## le modèle est remplacé par une craie (ChalkBody) haute comme le monstre (head_height), qui
## se couche à la mort ; bascule à chaud comme Character.

const IDLE_STATE := "idle"
const RUN_STATE := "run"
const BLEND_TIME := 0.15
const FLASH_MATERIAL_ALPHA := 0.55
## Proportions de la craie d'un monstre : celles de la craie d'un personnage (0.35 / 1.6).
const CHALK_RADIUS_RATIO := 0.22
const CHALK_DEFAULT_COLOR := Color(0.85, 0.30, 0.28)
const ChalkBody := preload("res://scenes/game/entities/ChalkBody.gd")

var model: MonsterModel

var _model: Node3D
var _animation_player: AnimationPlayer
var _base_state := IDLE_STATE
var _dead := false
var _flash_material: StandardMaterial3D
var _flash_tween: Tween
## Craie affichée à la place du modèle (null en mode modèle).
var _chalk: ChalkBody
var _chalk_color := CHALK_DEFAULT_COLOR


## Doit être appelé avant l'entrée dans l'arbre (voir Game3D._make_entity_node).
func setup(monster_model: MonsterModel) -> void:
	model = monster_model


## Teinte de la craie (MONSTER_COLOR de Game3D) ; sans effet visible en mode modèle.
func set_chalk_color(color: Color) -> void:
	_chalk_color = color
	if _chalk != null:
		_chalk.set_color(color)


func _ready() -> void:
	Settings.character_models_changed.connect(_on_character_models_changed)
	_refresh_body()


func _on_character_models_changed(_enabled: bool) -> void:
	_refresh_body()


## Modèle animé ou craie selon le réglage courant.
func _refresh_body() -> void:
	if Settings.character_models_enabled():
		if _chalk != null:
			_chalk.queue_free()
			_chalk = null
		if _model == null:
			_instance_model()
	else:
		_free_model()
		if _chalk == null:
			var height := model.head_height if model != null else 1.0
			_chalk = ChalkBody.new(height * CHALK_RADIUS_RATIO, height, _chalk_color)
			add_child(_chalk)
			_chalk.set_lying(_dead, false)


func _free_model() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_material = null
	if _model != null:
		_model.queue_free()
		_model = null
	_animation_player = null


func _instance_model() -> void:
	if model == null or model.scene == null:
		push_warning("Monster: pas de modèle")
		return
	_model = model.scene.instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * model.model_scale
	_model.rotation.y = deg_to_rad(model.yaw_degrees)
	_model.position.y = 0.0 if _dead else model.hover_height
	add_child(_model)
	_attach_accessories()
	if not model.material_colors.is_empty() or model.tint != Color.WHITE:
		_recolor()
	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("Monster: modèle sans AnimationPlayer (%s)" % model.scene.resource_path)
		return
	for anim_name in [model.idle_anim, model.run_anim]:
		if _animation_player.has_animation(anim_name):
			_animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_animation_player.animation_finished.connect(_on_animation_finished)
	if _dead:
		_freeze_on_death()
	else:
		_play_base()


## État tenu : "idle" ou "run" (Character.IDLE_ANIM/RUN_ANIM). Ignoré tant que le monstre est
## mort.
func play_state(state_name: String) -> void:
	if state_name != IDLE_STATE and state_name != RUN_STATE:
		return
	_base_state = state_name
	if not _dead:
		_play_base()


## Coup (AttackResult dont le monstre est l'attaquant), puis retour à l'état tenu.
func play_attack() -> void:
	if _dead or _animation_player == null or not _animation_player.has_animation(model.attack_anim):
		return
	# Deux attaques de suite : sans stop(), play() sur le clip en cours ne repart pas du début.
	if _animation_player.current_animation == model.attack_anim:
		_animation_player.stop()
	_animation_player.play(model.attack_anim, BLEND_TIME, model.attack_speed_scale)


func play_death() -> void:
	_dead = true
	if _chalk != null:
		_chalk.set_lying(true, true)
	if _animation_player != null and _animation_player.has_animation(model.death_anim):
		_animation_player.play(model.death_anim, BLEND_TIME)
	if _model != null and model.hover_height > 0.0:
		create_tween().tween_property(_model, "position:y", 0.0, maxf(0.3, death_duration() * 0.6)) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func revive() -> void:
	if not _dead:
		return
	_dead = false
	if _model != null:
		_model.position.y = model.hover_height
	if _chalk != null:
		_chalk.set_lying(false, true)
	_play_base()


func is_dead() -> bool:
	return _dead


## Durée du clip de mort (pour caler la disparition du corps, voir Game3D._despawn_monster).
func death_duration() -> float:
	if _chalk != null:
		return ChalkBody.FALL_TIME
	if _animation_player == null or not _animation_player.has_animation(model.death_anim):
		return 0.0
	return _animation_player.get_animation(model.death_anim).length


## Éclair de couleur au coup reçu (équivalent de Game3D._flash_entity pour la capsule) :
## overlay non éclairé posé sur tous les meshes du modèle, dont l'opacité monte puis retombe.
func flash(color: Color, up_duration: float, down_duration: float) -> void:
	if _chalk != null:
		_chalk.flash(color, up_duration, down_duration)
		return
	if _model == null:
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = _flash_material
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_material.albedo_color = Color(color, 0.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", FLASH_MATERIAL_ALPHA, up_duration)
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, down_duration)


func _play_base() -> void:
	if _animation_player == null:
		return
	var anim_name := model.run_anim if _base_state == RUN_STATE else model.idle_anim
	var speed := model.run_speed_scale if _base_state == RUN_STATE else 1.0
	if not _animation_player.has_animation(anim_name):
		return
	if _animation_player.current_animation == anim_name and _animation_player.is_playing():
		return
	_animation_player.play(anim_name, BLEND_TIME, speed)


## Applique MonsterModel.material_colors : les matériaux du .glb étant partagés par toutes les
## instances (et par d'autres fiches du même modèle), chacun est dupliqué avant d'être teint.
## La copie est rendue mate : le metallic hérité des packs (conversion FBX Phong) reflète le
## ciel bleuté et grise les teintes sombres.
func _recolor() -> void:
	var tinted := {}
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			var recolored := model.material_colors.has(material.resource_name)
			if not recolored and model.tint == Color.WHITE:
				continue
			if not tinted.has(material):
				var copy := material.duplicate() as BaseMaterial3D
				if recolored:
					copy.albedo_color = model.material_colors[material.resource_name]
				copy.albedo_color *= model.tint
				copy.metallic = 0.0
				tinted[material] = copy
			mesh_instance.set_surface_override_material(surface, tinted[material])


## MonsterModel.attachments : chaque scène sous un BoneAttachment3D de l'os nommé (absent du
## squelette : ignoré avec un avertissement).
func _attach_accessories() -> void:
	if model.attachments.is_empty():
		return
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	var skeleton: Skeleton3D = skeletons[0] if not skeletons.is_empty() else null
	if skeleton == null:
		push_warning("Monster: accessoires sans Skeleton3D (%s)" % model.scene.resource_path)
		return
	for bone in model.attachments:
		if skeleton.find_bone(bone) < 0:
			push_warning("Monster: os %s absent (%s)" % [bone, model.scene.resource_path])
			continue
		var holder := BoneAttachment3D.new()
		holder.bone_name = bone
		skeleton.add_child(holder)
		holder.add_child(model.attachments[bone].instantiate())


func _freeze_on_death() -> void:
	if not _animation_player.has_animation(model.death_anim):
		return
	_animation_player.play(model.death_anim)
	_animation_player.seek(_animation_player.current_animation_length, true)


func _on_animation_finished(anim_name: StringName) -> void:
	if _dead or anim_name == model.death_anim:
		return
	if anim_name != model.idle_anim and anim_name != model.run_anim:
		_play_base()
