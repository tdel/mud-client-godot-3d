class_name Character
extends Node3D
## Mannequin low-poly joueur (homme/femme) — voir tools/character_gen/build_characters.py
## (générateur Blender) pour le squelette, les animations et la garde-robe. Instancié par
## Game3D._make_entity_node comme "Body" de tout personnage (kind="character", joueur compris).
##
## Chaque .glb contient le corps en sous-vêtements ("Body" + "Hair") ET toutes les pièces
## d'équipement ("torso_plate", "weapon_sword", ...) déjà skinnées sur le même Skeleton3D et
## ajustées au gabarit : équiper un objet revient à rendre visible la pièce correspondante
## (voir set_equipment/visual_for_item). Aucune pièce n'est visible par défaut.
##
## Animations (clips du .glb, noms conservés) : idle/run/cast bouclent ; attack_1h/attack_2h/
## launch reviennent à l'état de base (idle ou run) une fois finies ; death reste figée sur
## sa dernière image jusqu'à revive(). Pilotage direct de l'AnimationPlayer (fondu enchaîné
## via BLEND_TIME) : plus besoin d'AnimationTree, et la vitesse du cast se règle par clip.
##
## Case "Animations et skins (personnages et monstres)" décochée (Settings.character_models_enabled,
## menu système > Graphisme) : le mannequin est remplacé par une "craie" (ChalkBody), simple
## bâton coloré sans squelette ni animation (comme les PNJ sans modèle), qui se couche à la
## mort. Bascule à chaud : équipement, gabarit et état (mort comprise) sont conservés pour le
## retour au mannequin.

const IDLE_ANIM := "idle"
const RUN_ANIM := "run"
const CAST_ANIM := "cast"
const LAUNCH_ANIM := "launch"
const DEATH_ANIM := "death"
const ATTACK_1H_ANIM := "attack_1h"
const ATTACK_2H_ANIM := "attack_2h"

const LOOPED_ANIMS := [IDLE_ANIM, RUN_ANIM, CAST_ANIM]
const BLEND_TIME := 0.15

## Préfixes des meshes d'équipement du .glb (cachés à l'instanciation).
const EQUIPMENT_PREFIXES := ["torso_", "legs_", "helmet_", "gloves_", "boots_", "weapon_", "shield_"]
## Armes tenues à deux mains : attaque attack_2h (le générateur place la main gauche sur la
## poignée) et bouclier masqué.
const TWO_HANDED_WEAPONS := ["weapon_greatsword", "weapon_hammer", "weapon_staff", "weapon_spear"]
## L'arc occupe la main gauche : pas de bouclier non plus.
const OFF_HAND_BLOCKING_WEAPONS := ["weapon_greatsword", "weapon_hammer", "weapon_staff", "weapon_spear", "weapon_bow"]
## Couvre-chefs qui laissent voir les cheveux.
const HAIR_VISIBLE_HELMETS := ["helmet_circlet", "helmet_guard"]

## Tenue d'un PNJ par EntityView.npcType (backend NpcType) : slot -> mesh, posée telle quelle
## par set_outfit. Le sexe (EntityView.gender) choisit le gabarit ; le chapel de fer laisse
## voir visage et cheveux (queue de cheval des gardes femmes).
const NPC_OUTFITS := {
	"GUARD": {
		"CHEST": "torso_guard", "LEGS": "legs_plate", "HEAD": "helmet_guard", "HANDS": "gloves_plate",
		"FEET": "boots_plate", "WEAPON": "weapon_shortsword", "OFF_HAND": "shield_guard",
	},
	# Maître des compétences (Grand Master) : robe de mage, diadème et bâton.
	"SKILL_LEARNER": {
		"CHEST": "torso_robe", "LEGS": "legs_cloth", "HEAD": "helmet_circlet", "HANDS": "gloves_leather",
		"FEET": "boots_leather", "WEAPON": "weapon_staff",
	},
}

## WeaponType serveur (champ `weaponType` d'Inventory/EquipmentView, voir
## app.domain.item.WeaponType côté backend) -> mesh d'arme.
const WEAPON_VISUALS := {
	"SWORD": "weapon_sword", "BIG_SWORD": "weapon_greatsword", "DAGGER": "weapon_dagger",
	"BLUNT": "weapon_mace", "BIG_BLUNT": "weapon_hammer", "AXE": "weapon_axe", "POLE": "weapon_spear",
	"STAFF": "weapon_staff", "WAND": "weapon_wand", "BOW": "weapon_bow",
}

## Effet d'équipement (voir _play_mesh_effect) : la pièce qui apparaît se matérialise (fondu
## + halo doré qui s'éteint + étincelles montantes), celle qui disparaît s'illumine puis se
## dissout (poussière bleutée qui retombe).
const EQUIP_GLOW_SHADER := preload("res://scenes/game/entities/equip_glow.gdshader")
const EQUIP_COLOR := Color(1.0, 0.8, 0.35)
const UNEQUIP_COLOR := Color(0.55, 0.75, 1.0)
const EQUIP_FADE_TIME := 0.35
const EQUIP_GLOW_TIME := 0.9
const UNEQUIP_FLASH_TIME := 0.12
const UNEQUIP_FADE_TIME := 0.5
## Préfixe de mesh -> [bones où émettre les étincelles, rayon d'émission].
const EFFECT_BONES := {
	"weapon_bow": [["LeftHand"], 0.2],
	"weapon_": [["RightHand"], 0.2],
	"shield_": [["LeftHand"], 0.18],
	"helmet_": [["Head"], 0.14],
	"torso_": [["Chest"], 0.24],
	"legs_": [["LeftLowerLeg", "RightLowerLeg"], 0.16],
	"gloves_": [["LeftHand", "RightHand"], 0.1],
	"boots_": [["LeftFoot", "RightFoot"], 0.1],
}

## Gabarit de la craie : celui des capsules de PNJ/monstres sans modèle (voir
## Game3D._make_entity_node).
const CHALK_RADIUS := 0.35
const CHALK_HEIGHT := 1.6
const CHALK_DEFAULT_COLOR := Color(0.35, 0.65, 0.95)
const ChalkBody := preload("res://scenes/game/entities/ChalkBody.gd")

static var _sparkle_mesh: QuadMesh

@export var male_scene: PackedScene
@export var female_scene: PackedScene

@onready var _model_holder: Node3D = $Model

var _gender := "male"
var _model: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
## slot EquipmentSlot -> nom du mesh visible (voir set_equipment).
var _visuals: Dictionary = {}
## Faux jusqu'au premier set_equipment : la tenue initiale (arrivée en jeu, entité qui
## apparaît) s'affiche sans effet, seuls les changements ultérieurs sont animés.
var _equipment_initialized := false
## Nom de mesh -> Tween de l'effet en cours (voir _play_mesh_effect).
var _effect_tweens: Dictionary = {}
## Meshes retirés mais encore visibles le temps de leur disparition.
var _vanishing: Dictionary = {}
var _base_state := IDLE_ANIM
var _dead := false
## Craie affichée à la place du mannequin (null en mode mannequin), voir _show_chalk.
var _chalk: ChalkBody
var _chalk_color := CHALK_DEFAULT_COLOR


func _ready() -> void:
	Settings.character_models_changed.connect(_on_character_models_changed)
	_refresh_body()


## Teinte de la craie (couleur d'entité de Game3D : nous, autres joueurs, PNJ) ; sans effet
## visible en mode mannequin.
func set_chalk_color(color: Color) -> void:
	_chalk_color = color
	if _chalk != null:
		_chalk.set_color(color)


## "man"/"woman" (GamePlayerStats.gender) ou "male"/"female" ; ré-instancie le modèle si le
## gabarit change, en conservant équipement et état (mort comprise).
func set_gender(gender: String) -> void:
	var normalized := "female" if gender.to_lower() in ["woman", "female", "f"] else "male"
	if normalized == _gender and (_model != null or _chalk != null):
		return
	_gender = normalized
	if is_inside_tree():
		_refresh_body()


func _on_character_models_changed(_enabled: bool) -> void:
	_refresh_body()


## Mannequin ou craie selon le réglage courant.
func _refresh_body() -> void:
	if Settings.character_models_enabled():
		_hide_chalk()
		_instance_model()
	else:
		_free_model()
		_show_chalk()


func _free_model() -> void:
	_clear_mesh_effects()
	if _model != null:
		_model.queue_free()
		_model = null
	_skeleton = null
	_animation_player = null


func _instance_model() -> void:
	_free_model()
	var scene := female_scene if _gender == "female" else male_scene
	if scene == null:
		return
	_model = scene.instantiate()
	_model_holder.add_child(_model)
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null or _animation_player == null:
		push_warning("Character: modèle sans Skeleton3D/AnimationPlayer (%s)" % scene.resource_path)
		return
	for anim_name in LOOPED_ANIMS:
		if _animation_player.has_animation(anim_name):
			_animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_animation_player.animation_finished.connect(_on_animation_finished)
	_apply_visuals()
	if _dead:
		_animation_player.play(DEATH_ANIM)
		_animation_player.seek(_animation_player.current_animation_length, true)
	else:
		_play(_base_state)


# ---------------------------------------------------------------------------
# Craie (animations et skins désactivés)
# ---------------------------------------------------------------------------

## Craie (voir ChalkBody) couchée d'emblée si le personnage est déjà mort.
func _show_chalk() -> void:
	if _chalk != null:
		return
	_chalk = ChalkBody.new(CHALK_RADIUS, CHALK_HEIGHT, _chalk_color)
	add_child(_chalk)
	_chalk.set_lying(_dead, false)


func _hide_chalk() -> void:
	if _chalk != null:
		_chalk.queue_free()
	_chalk = null


## Éclair de couleur sur la craie (coup reçu, voir Game3D._flash_entity) ; rien sur le
## mannequin, dont les matériaux importés sont partagés entre instances.
func flash(color: Color, up_duration: float, down_duration: float) -> void:
	if _chalk != null:
		_chalk.flash(color, up_duration, down_duration)


# ---------------------------------------------------------------------------
# Équipement
# ---------------------------------------------------------------------------

## `equipped` : slot EquipmentSlot ("WEAPON", "OFF_HAND", "HEAD", "CHEST", "HANDS", "LEGS",
## "FEET"...) -> item de l'Inventory ({name, type, armorCategory, ...}). Les slots absents
## sont vidés ; les bijoux n'ont pas de rendu. Les pièces qui apparaissent/disparaissent
## par rapport à l'appel précédent sont animées, sauf au tout premier appel ou si `animate`
## est faux (aperçu de l'écran de sélection, qui change de personnage et non de tenue).
func set_equipment(equipped: Dictionary, animate := true) -> void:
	animate = animate and _equipment_initialized
	_equipment_initialized = true
	var before := _shown_meshes()
	_visuals.clear()
	for slot in equipped.keys():
		var visual := visual_for_item(str(slot), equipped[slot])
		if not visual.is_empty():
			_visuals[str(slot)] = visual
	var after := _shown_meshes()
	_apply_visuals()
	if not animate or _skeleton == null:
		return
	for mesh_name in after:
		if not before.has(mesh_name):
			_play_mesh_effect(mesh_name, true)
	for mesh_name in before:
		if not after.has(mesh_name):
			_play_mesh_effect(mesh_name, false)


## Tenue fixe d'un PNJ (voir NPC_OUTFITS), sans effet d'apparition. Faux si `npc_type` n'a
## pas de tenue connue (le PNJ garde alors une capsule, voir Game3D._ensure_entity_node).
func set_outfit(npc_type: String) -> bool:
	if not NPC_OUTFITS.has(npc_type):
		return false
	_equipment_initialized = true
	_visuals = NPC_OUTFITS[npc_type].duplicate()
	_apply_visuals()
	return true


static func has_outfit(npc_type: String) -> bool:
	return NPC_OUTFITS.has(npc_type)


## `items` : entrées Inventory ou EquipmentView ({slot, name, type, armorCategory, weaponType,
## ...}) -> dictionnaire slot -> item attendu par set_equipment ; seules les entrées dont
## `slot` est renseigné sont portées.
static func equipped_from_items(items) -> Dictionary:
	var equipped := {}
	if not items is Array:
		return equipped
	for item in items:
		if not item is Dictionary:
			continue
		var slot = item.get("slot")
		if slot != null and not str(slot).is_empty():
			equipped[str(slot)] = item
	return equipped


## Mesh du .glb à montrer pour `item` porté dans `slot` ("" : rien à afficher).
static func visual_for_item(slot: String, item: Dictionary) -> String:
	var item_name := str(item.get("name", "")).to_lower()
	var category := str(item.get("armorCategory", "")).to_upper()
	match slot:
		"WEAPON":
			# Sans `weaponType` (backend antérieur à ce champ) : même devinette que les icônes.
			if item_name.contains("short sword"):
				return "weapon_shortsword"
			var weapon_type := str(item.get("weaponType", "")).to_upper()
			if not WEAPON_VISUALS.has(weapon_type):
				weapon_type = IconFactory.guess_weapon_type(item_name)
			return WEAPON_VISUALS.get(weapon_type, "weapon_sword")
		"OFF_HAND":
			return "shield_round"
		"HEAD":
			if _has_any(item_name, ["circlet", "crown", "tiara", "diadem"]):
				return "helmet_circlet"
			if _has_any(item_name, ["hood", "cowl"]):
				return "helmet_hood"
			if _has_any(item_name, ["leather", "padded", "cap"]) or category == "LIGHT":
				return "helmet_leather"
			return "helmet_plate"
		"CHEST":
			# Type d'armure L2 (backend ArmorCategory HEAVY/LIGHT/ROBE) : une robe est une robe,
			# quel que soit son nom (Tallum Tunic, Apprentice's Robe...).
			if category == "ROBE":
				return "torso_robe"
			if item_name.contains("leather"):
				return "torso_leather"
			if _has_any(item_name, ["robe", "tunic", "arcana"]):
				return "torso_robe"
			if _has_any(item_name, ["plate", "mail", "breastplate", "cuirass"]):
				return "torso_plate"
			if item_name.contains("padded"):
				return "torso_cloth"
			return _by_category(category, "torso_", "cloth")
		"LEGS":
			if category == "ROBE" or _has_any(item_name, ["stockings", "hose"]):
				return "legs_cloth"
			if _has_any(item_name, ["leather", "pants"]):
				return "legs_leather"
			if _has_any(item_name, ["leggings", "greaves", "plate"]):
				return "legs_plate"
			return _by_category(category, "legs_", "cloth")
		"HANDS":
			if item_name.contains("leather"):
				return "gloves_leather"
			if item_name.contains("gauntlet"):
				return "gloves_plate"
			return "gloves_plate" if category == "HEAVY" else "gloves_leather"
		"FEET":
			if item_name.contains("leather"):
				return "boots_leather"
			return "boots_plate" if category == "HEAVY" else "boots_leather"
	return ""


static func _has_any(text: String, words: Array) -> bool:
	for word in words:
		if text.contains(word):
			return true
	return false


## HEAVY/LIGHT (ArmorCategory backend, types d'armure L2) -> variante de mesh, `fallback`
## sinon ; les robes (ROBE) sont traitées avant, dans visual_for_item.
static func _by_category(category: String, prefix: String, fallback: String) -> String:
	match category:
		"HEAVY":
			return prefix + "plate"
		"LIGHT":
			return prefix + "leather"
	return prefix + fallback


## Meshes d'équipement à rendre visibles d'après _visuals (nom -> true).
func _shown_meshes() -> Dictionary:
	var shown := {}
	for visual in _visuals.values():
		shown[visual] = true
	if _visuals.get("WEAPON", "") in OFF_HAND_BLOCKING_WEAPONS:
		shown.erase(_visuals.get("OFF_HAND", ""))
	return shown


func _apply_visuals() -> void:
	if _skeleton == null:
		return
	var shown := _shown_meshes()
	var helmet: String = _visuals.get("HEAD", "")
	for child in _skeleton.get_children():
		if not child is MeshInstance3D:
			continue
		var child_name := str(child.name)
		if child_name == "Hair":
			child.visible = helmet.is_empty() or helmet in HAIR_VISIBLE_HELMETS
		elif _is_equipment_mesh(child_name):
			child.visible = shown.has(child_name) or _vanishing.has(child_name)


## Apparition (`appearing`) ou disparition animée d'une pièce : fondu via
## GeometryInstance3D.transparency (compatible avec les matériaux opaques du .glb), halo
## equip_glow.gdshader en overlay, puis étincelles aux bones concernés. Une pièce qui
## disparaît reste visible (_vanishing) jusqu'à la fin de l'effet ; un nouvel effet sur la
## même pièce (ré-équipement rapide) interrompt le précédent.
func _play_mesh_effect(mesh_name: String, appearing: bool) -> void:
	var mesh := _skeleton.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
	if mesh == null:
		return
	_stop_mesh_effect(mesh_name)
	var glow := ShaderMaterial.new()
	glow.shader = EQUIP_GLOW_SHADER
	glow.set_shader_parameter("glow_color", EQUIP_COLOR if appearing else UNEQUIP_COLOR)
	mesh.material_overlay = glow
	mesh.visible = true
	var tween := create_tween()
	_effect_tweens[mesh_name] = tween
	if appearing:
		mesh.transparency = 1.0
		glow.set_shader_parameter("intensity", 2.2)
		tween.tween_property(mesh, "transparency", 0.0, EQUIP_FADE_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(glow, "shader_parameter/intensity", 0.0, EQUIP_GLOW_TIME) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_vanishing[mesh_name] = true
		glow.set_shader_parameter("intensity", 0.0)
		tween.tween_property(glow, "shader_parameter/intensity", 2.5, UNEQUIP_FLASH_TIME)
		tween.tween_property(mesh, "transparency", 1.0, UNEQUIP_FADE_TIME) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(glow, "shader_parameter/intensity", 0.0, UNEQUIP_FADE_TIME)
	tween.finished.connect(_stop_mesh_effect.bind(mesh_name))
	_spawn_sparkles(mesh_name, appearing)


## Termine l'effet de `mesh_name` (interrompu ou fini) : rendu normal, visibilité selon
## l'équipement courant.
func _stop_mesh_effect(mesh_name: String) -> void:
	var tween: Tween = _effect_tweens.get(mesh_name)
	if tween != null and tween.is_valid():
		tween.kill()
	_effect_tweens.erase(mesh_name)
	_vanishing.erase(mesh_name)
	var mesh: MeshInstance3D = null
	if _skeleton != null:
		mesh = _skeleton.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
	if mesh != null:
		mesh.transparency = 0.0
		mesh.material_overlay = null
	_apply_visuals()


## Avant de jeter le modèle (changement de gabarit) : les Tweens visent ses meshes.
func _clear_mesh_effects() -> void:
	for tween in _effect_tweens.values():
		if tween != null and tween.is_valid():
			tween.kill()
	_effect_tweens.clear()
	_vanishing.clear()


func _spawn_sparkles(mesh_name: String, appearing: bool) -> void:
	var spec: Array = []
	for prefix in EFFECT_BONES:
		if mesh_name.begins_with(prefix):
			spec = EFFECT_BONES[prefix]
			break
	if spec.is_empty():
		return
	for bone_name in spec[0]:
		if _skeleton.find_bone(bone_name) < 0:
			continue
		# Accrochée au bone (et non placée une fois pour toutes) : la rafale part de la pose
		# animée, pas de la pose de repos, et suit la main en pleine course.
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone_name
		_skeleton.add_child(attachment)
		var particles := _make_sparkles(appearing, spec[1])
		attachment.add_child(particles)
		particles.finished.connect(attachment.queue_free)
		_emit_next_frame.call_deferred(particles)


## Deux frames plus tard (process_frame part avant l'AnimationPlayer de la frame) : le
## BoneAttachment3D a alors suivi la pose animée — un équipement appliqué avant la toute
## première frame d'animation partirait sinon de la pose de repos.
func _emit_next_frame(particles: CPUParticles3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(particles):
		particles.emitting = true


## Rafale unique de points lumineux additifs : dorés et montants à l'équipement, bleutés et
## retombants au retrait. Coordonnées monde (local_coords faux) : la rafale ne suit pas le
## personnage une fois émise.
func _make_sparkles(appearing: bool, radius: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 28 if appearing else 22
	particles.lifetime = 0.8 if appearing else 0.7
	particles.explosiveness = 0.8
	particles.mesh = _get_sparkle_mesh()
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius
	particles.direction = Vector3.UP if appearing else Vector3.DOWN
	particles.spread = 70.0
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.8 if appearing else 0.5
	particles.gravity = Vector3(0, 0.8, 0) if appearing else Vector3(0, -1.6, 0)
	particles.damping_min = 0.5
	particles.damping_max = 1.5
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3
	var base_color := EQUIP_COLOR if appearing else UNEQUIP_COLOR
	var ramp := Gradient.new()
	ramp.set_color(0, Color(base_color.lightened(0.5), 1.0))
	ramp.set_color(1, Color(base_color, 0.0))
	particles.color_ramp = ramp
	return particles


static func _get_sparkle_mesh() -> QuadMesh:
	if _sparkle_mesh != null:
		return _sparkle_mesh
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 1))
	falloff.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = falloff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = dot
	material.disable_receive_shadows = true
	_sparkle_mesh = QuadMesh.new()
	_sparkle_mesh.size = Vector2(0.05, 0.05)
	_sparkle_mesh.material = material
	return _sparkle_mesh


func _is_equipment_mesh(mesh_name: String) -> bool:
	for prefix in EQUIPMENT_PREFIXES:
		if mesh_name.begins_with(prefix):
			return true
	return false


func is_two_handed() -> bool:
	return _visuals.get("WEAPON", "") in TWO_HANDED_WEAPONS


# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

## État tenu : idle ou run (et cast, voir play_cast). Ignoré tant que le personnage est mort.
func play_state(state_name: String) -> void:
	if state_name == IDLE_ANIM or state_name == RUN_ANIM:
		_base_state = state_name
	if _dead:
		return
	_play(state_name)


## Coup d'arme (auto-attaque) : attack_2h avec une arme à deux mains, attack_1h sinon (mains
## nues comprises), puis retour à l'état de base.
func play_attack() -> void:
	if not _dead:
		_play(ATTACK_2H_ANIM if is_two_handed() else ATTACK_1H_ANIM)


## Libération d'un sort (fin d'incantation), puis retour à l'état de base.
func play_launch() -> void:
	if not _dead:
		_play(LAUNCH_ANIM)


## Incantation calée sur duration_sec (castingTimeMs serveur, voir
## Game3D._on_skill_cast_started) : le clip bouclé est accéléré/ralenti pour qu'un cycle dure
## au moins autant que le cast (jamais plus d'un cycle et demi accéléré).
func play_cast(duration_sec: float) -> void:
	if _dead or _animation_player == null or not _animation_player.has_animation(CAST_ANIM):
		return
	var natural_length := _animation_player.get_animation(CAST_ANIM).length
	var speed := 1.0
	if duration_sec > 0.0 and natural_length > 0.0:
		speed = clampf(natural_length / duration_sec, 0.5, 1.5)
	_animation_player.play(CAST_ANIM, BLEND_TIME, speed)


func play_death() -> void:
	_dead = true
	_play(DEATH_ANIM)
	if _chalk != null:
		_chalk.set_lying(true, true)


func revive() -> void:
	if not _dead:
		return
	_dead = false
	_play(_base_state)
	if _chalk != null:
		_chalk.set_lying(false, true)


func is_dead() -> bool:
	return _dead


func _play(anim_name: String) -> void:
	if _animation_player == null or not _animation_player.has_animation(anim_name):
		return
	if _animation_player.current_animation == anim_name and anim_name in LOOPED_ANIMS \
			and _animation_player.get_playing_speed() == 1.0:
		return
	# Relance explicite d'un clip ponctuel (deux attaques de suite) : sans stop(), play() sur
	# le clip déjà en cours ne repart pas du début.
	if _animation_player.current_animation == anim_name:
		_animation_player.stop()
	_animation_player.play(anim_name, BLEND_TIME)


func _on_animation_finished(anim_name: StringName) -> void:
	if _dead or anim_name == DEATH_ANIM:
		return
	if not str(anim_name) in LOOPED_ANIMS:
		_play(_base_state)
