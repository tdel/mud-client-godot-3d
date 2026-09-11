class_name Character
extends Node3D
## Rig Mixamo (squelette + animations) — voir pipeline Mixamo -> Godot. Instancié par
## Game3D._make_entity_node comme "Body" de tout personnage (kind="character", joueur compris) ;
## Game3D pilote les transitions via play_state()/play_transient_state() (MovementStarted,
## SkillCastStarted, ShotUsed, etc. — voir _play_body_state/_play_body_action côté Game3D.gd).
##
## Chaque export Mixamo (FBX "With Skin", un clip par fichier — voir assets/characters/human/)
## contient exactement UN clip, toujours nommé "mixamo_com" par l'import Godot (assaini depuis
## "mixamo.com") : inutile de renommer quoi que ce soit à l'import, on le renomme ici à la
## volée dans l'AnimationLibrary de body_scene sous IDLE_ANIM/RUN_ANIM/ATTACK_ANIM/CAST_ANIM
## (vérifié par inspection : voir get_animation_list() sur chaque .fbx importé). Les bones
## utilisent déjà l'underscore ("mixamorig_RightHand", pas "mixamorig:RightHand" — Godot
## assainit aussi les deux-points des noms de bones à l'import).
##
## Caveat connu (personnage Mixamo "Maria" utilisé pour les tests) : le mesh de base embarque
## déjà une épée skinnée ("Maria_sword"), visible même sans rien équiper via equip_weapon —
## à cacher/retirer le jour où un vrai set d'armes swappables remplace ce mesh de test.

const IDLE_ANIM := "idle"
const RUN_ANIM := "run"
const ATTACK_ANIM := "attack"
const CAST_ANIM := "cast"

## Nom de bone Mixamo standard pour la main droite — sert d'ancrage à l'arme équipée.
const RIGHT_HAND_BONE := "mixamorig_RightHand"

## Corps de base : mesh + Skeleton3D + AnimationPlayer (le clip embarqué devient IDLE_ANIM).
@export var body_scene: PackedScene
## Animations additionnelles : un FBX par état, chacun avec un seul clip (voir commentaire
## d'en-tête) fusionné dans l'AnimationPlayer de body_scene sous le nom canonique.
@export var run_scene: PackedScene
@export var attack_scene: PackedScene
@export var cast_scene: PackedScene

@onready var _model_holder: Node3D = $Model
@onready var _animation_tree: AnimationTree = $AnimationTree

var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _weapon_attachment: BoneAttachment3D
var _weapon_node: Node3D


func _ready() -> void:
	if body_scene != null:
		_instance_model()


func _instance_model() -> void:
	var model := body_scene.instantiate()
	_model_holder.add_child(model)
	_skeleton = _find_of_type(model, "Skeleton3D") as Skeleton3D
	_animation_player = _find_of_type(model, "AnimationPlayer") as AnimationPlayer
	if _skeleton == null or _animation_player == null:
		push_warning("Character: body_scene sans Skeleton3D/AnimationPlayer (%s)" % body_scene.resource_path)
		return
	# idle/course/incantation bouclent (états tenus tant qu'aucune transition n'arrive) ;
	# l'attaque ne boucle pas (un seul coup, voir play_transient_state qui revient à idle après).
	_rename_only_clip(_animation_player, IDLE_ANIM, true)
	_import_animation(RUN_ANIM, run_scene, true)
	_import_animation(ATTACK_ANIM, attack_scene, false)
	_import_animation(CAST_ANIM, cast_scene, true)
	_setup_animation_tree()
	_setup_root_motion()
	_setup_weapon_attachment()


## Renomme l'unique clip de `player` (voir commentaire d'en-tête — toujours "mixamo_com" pour
## ces exports) en `target_name`, quel que soit son nom d'origine.
func _rename_only_clip(player: AnimationPlayer, target_name: String, loop: bool) -> void:
	var names := player.get_animation_list()
	if names.is_empty():
		return
	var lib := player.get_animation_library("")
	lib.rename_animation(names[0], target_name)
	if loop:
		lib.get_animation(target_name).loop_mode = Animation.LOOP_LINEAR


## Instancie temporairement `source_scene` (un FBX Mixamo, un seul clip dedans) pour copier ce
## clip dans l'AnimationLibrary de _animation_player sous `target_name` — évite d'avoir à
## configurer le renommage côté import (voir commentaire d'en-tête).
func _import_animation(target_name: String, source_scene: PackedScene, loop: bool) -> void:
	if source_scene == null or _animation_player == null:
		return
	var source := source_scene.instantiate()
	var source_player := _find_of_type(source, "AnimationPlayer") as AnimationPlayer
	if source_player != null:
		var names := source_player.get_animation_list()
		if not names.is_empty():
			var anim := source_player.get_animation(names[0]).duplicate()
			if loop:
				anim.loop_mode = Animation.LOOP_LINEAR
			_animation_player.get_animation_library("").add_animation(target_name, anim)
	source.free()


func _find_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find_of_type(child, type_name)
		if found != null:
			return found
	return null


## Construit l'état-machine à partir des clips réellement présents dans model_scene plutôt que
## de supposer IDLE/RUN/ATTACK/CAST déjà tous exportés — permet de brancher un modèle partiel
## (idle+run seuls, par exemple) sans faire planter l'AnimationTree.
func _setup_animation_tree() -> void:
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)
	var state_machine := AnimationNodeStateMachine.new()
	var available := _animation_player.get_animation_list()
	for anim_name in [IDLE_ANIM, RUN_ANIM, ATTACK_ANIM, CAST_ANIM]:
		if anim_name in available:
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = anim_name
			state_machine.add_node(anim_name, anim_node)
	_animation_tree.tree_root = state_machine
	_animation_tree.active = true
	# Pas de "start node" sur AnimationNodeStateMachine (Godot 4) : on démarre directement sur
	# idle via la playback plutôt que de câbler une transition depuis le pseudo-état "Start".
	if state_machine.has_node(IDLE_ANIM):
		var playback: AnimationNodeStateMachinePlayback = _animation_tree.get("parameters/playback")
		playback.start(IDLE_ANIM)


## Les clips Mixamo "run"/"walk" embarquent le déplacement dans la piste de position du bone
## Hips (le personnage avance déjà "tout seul" dans l'animation) — or c'est déjà le script
## (Game3D._advance_positions, move_toward sur le speed serveur) qui déplace le node racine :
## sans ceci les deux se cumulent et le perso semble avancer bien plus vite que speed. En
## déclarant cette piste comme root_motion_track, l'AnimationMixer la retire de la pose jouée
## (le clip tourne "sur place") au lieu de l'appliquer au bone — on n'a pas besoin de récupérer
## le delta puisque c'est déjà le script qui pilote la translation.
func _setup_root_motion() -> void:
	if _animation_player == null or _animation_tree == null:
		return
	for anim_name in [RUN_ANIM, IDLE_ANIM]:
		if not _animation_player.has_animation(anim_name):
			continue
		var anim := _animation_player.get_animation(anim_name)
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
				continue
			var path := anim.track_get_path(i)
			if str(path).findn("Hips") != -1:
				_animation_tree.root_motion_track = path
				return


## Joue la transition idle/course/attaque/incantation — nom d'état = nom de clip (voir
## _setup_animation_tree) ; no-op silencieux si le clip n'a pas été importé (modèle partiel).
func play_state(state_name: String) -> void:
	if _animation_tree == null or _animation_tree.tree_root == null:
		return
	var state_machine := _animation_tree.tree_root as AnimationNodeStateMachine
	if not state_machine.has_node(state_name):
		return
	if not _animation_tree.active:
		# Sortie de play_cast (voir plus bas) : l'AnimationPlayer a été piloté directement le
		# temps du cast, en dehors de l'AnimationTree — on rend la main à la state machine.
		_animation_player.speed_scale = 1.0
		_animation_tree.active = true
	var playback: AnimationNodeStateMachinePlayback = _animation_tree.get("parameters/playback")
	playback.travel(state_name)


## Comme play_state(CAST_ANIM), mais avec la vitesse de lecture ajustée pour que la durée du
## clip corresponde exactement à duration_sec (temps de cast serveur, voir
## Game3D._on_skill_cast_started) plutôt que sa durée native — avant ce changement le clip
## rejouait en boucle à vitesse native, désynchronisé du temps de cast réel. La state machine
## (AnimationNodeStateMachinePlayback) n'expose pas de contrôle de vitesse par état : on sort
## temporairement l'AnimationTree du jeu (active=false) pour piloter _animation_player en
## direct, seul moyen simple d'accélérer/ralentir CE clip sans toucher idle/run/attack. play_state
## (appelé par Game3D._clear_casting à la fin du cast) réactive l'AnimationTree ensuite.
func play_cast(duration_sec: float) -> void:
	if _animation_player == null or not _animation_player.has_animation(CAST_ANIM):
		return
	if duration_sec <= 0.0:
		play_state(CAST_ANIM)
		return
	var natural_length := _animation_player.get_animation(CAST_ANIM).length
	_animation_tree.active = false
	_animation_player.speed_scale = natural_length / duration_sec if natural_length > 0.0 else 1.0
	_animation_player.play(CAST_ANIM)


## Comme play_state, mais pour un clip non bouclé (attaque) : revient automatiquement à
## `fallback_state` une fois sa durée écoulée — sinon l'AnimationPlayer resterait figé sur la
## dernière frame. Le minutage est approximatif (Timer du SceneTree, pas calé sur la playback
## elle-même) : suffisant pour ne pas rester figé, pas garanti à l'image près.
func play_transient_state(state_name: String, fallback_state: String) -> void:
	if _animation_player == null or not _animation_player.has_animation(state_name):
		return
	play_state(state_name)
	var duration := _animation_player.get_animation(state_name).length
	get_tree().create_timer(duration).timeout.connect(play_state.bind(fallback_state))


func _setup_weapon_attachment() -> void:
	_weapon_attachment = BoneAttachment3D.new()
	_weapon_attachment.name = "WeaponAttachment"
	_weapon_attachment.bone_name = RIGHT_HAND_BONE
	_skeleton.add_child(_weapon_attachment)


## Remplace l'arme en main : détruit l'ancienne, instancie weapon_scene sous WeaponAttachment
## (donc elle suit la main dans toutes les animations sans code par animation). weapon_scene
## à null pour désarmer.
func equip_weapon(weapon_scene: PackedScene) -> void:
	if _weapon_attachment == null:
		return
	if _weapon_node != null:
		_weapon_node.queue_free()
		_weapon_node = null
	if weapon_scene != null:
		_weapon_node = weapon_scene.instantiate()
		_weapon_attachment.add_child(_weapon_node)


## Armure par slot : remplace le nœud nommé exactement `slot` sous le modèle (convention à
## tenir côté export Blender/Mixamo, ex. "Head"/"Torso"/"Legs") par mesh_scene, reskinné sur
## le même Skeleton3D. mesh_scene à null pour retirer la pièce.
func equip_armor(slot: String, mesh_scene: PackedScene) -> void:
	if _model_holder == null:
		return
	var old := _model_holder.find_child(slot, true, false)
	if old != null:
		old.queue_free()
	if mesh_scene == null:
		return
	var new_part := mesh_scene.instantiate()
	new_part.name = slot
	_model_holder.add_child(new_part)
	if new_part is MeshInstance3D and _skeleton != null:
		(new_part as MeshInstance3D).skeleton = new_part.get_path_to(_skeleton)
