extends Node3D
## Outil de développement (hors jeu) : joue un effet de sort (voir scenes/game/vfx/SpellVfx.gd)
## entre deux mannequins, attend --time secondes, enregistre une capture PNG et quitte.
##
## Usage :
##   Godot_console.exe --path . res://tools/spell_preview/SpellPreview.tscn -- \
##       --fx=cast --element=fire --time=1.2 --out=C:/tmp/cast.png
## --fx : cast (cercle en cours, --duration = temps de cast), release (cast terminé, --time
##        compté après la fin), break (cast interrompu à mi-parcours, --time compté après),
##        projectile (--time compté depuis le lancer, --duration = durée du vol), target
##        (soin/buff/debuff/impact sur la cible selon l'élément), impact, escape (fin d'un Scroll
##        of Escape : cast blanc de --duration puis ascension, --time compté après la fin).
## --element : fire, water, wind, holy, dark, arcane, heal, buff, debuff, physical, escape.
## --charged=1 : cast chargé d'un spiritshot (couronnes flottantes, voir CastCircle).
## --skill=<nom> : compétence nommée (élément et projectile déduits du nom) — --fx=target joue
##        son effet propre (SpellVfx.play_skill_on_target), --fx=projectile son projectile
##        (Ice Bolt, Power Shot) ; --fx=charge (arme qui se charge, --duration), drain (Vampiric
##        Touch, cible -> lanceur), poison (période de Curse: Poison).
## Sans --out, la scène rejoue l'effet en boucle (pratique dans l'éditeur).

const CHARACTER_SCENE := preload("res://scenes/game/entities/Character.tscn")
const ELEMENTS := {
	"fire": SpellVfx.Element.FIRE, "water": SpellVfx.Element.WATER, "wind": SpellVfx.Element.WIND,
	"holy": SpellVfx.Element.HOLY, "dark": SpellVfx.Element.DARK, "arcane": SpellVfx.Element.ARCANE,
	"heal": SpellVfx.Element.HEAL, "buff": SpellVfx.Element.BUFF, "debuff": SpellVfx.Element.DEBUFF,
	"physical": SpellVfx.Element.PHYSICAL, "escape": SpellVfx.Element.ESCAPE,
}

var _fx := "cast"
var _element := SpellVfx.Element.FIRE
var _time := 1.0
var _duration := 2.0
var _charged := false
var _out := ""
var _skill := ""
var _vfx: SpellVfx
var _caster: Character
var _target: Character


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"fx":
				_fx = parts[1]
			"element":
				_element = ELEMENTS.get(parts[1], SpellVfx.Element.FIRE)
			"time":
				_time = float(parts[1])
			"duration":
				_duration = float(parts[1])
			"out":
				_out = parts[1]
			"charged":
				_charged = parts[1] in ["1", "true", "yes"]
			"skill":
				_skill = parts[1].replace("_", " ")
				_element = SpellVfx.element_for_skill(_skill)
	_build_stage()
	_vfx = SpellVfx.new()
	add_child(_vfx)
	_run.call_deferred()


func _build_stage() -> void:
	# Même ambiance que Game.tscn (fond, ambiance, tonemap filmique, pas de glow).
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.29, 0.33, 0.40)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 12)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.33, 0.4, 0.27)
	plane.material = ground_mat
	ground.mesh = plane
	add_child(ground)

	_caster = _make_character("woman", Vector3(-2.2, 0, 0), {"WEAPON": {"name": "Staff of Healing"}})
	_target = _make_character("man", Vector3(2.2, 0, 0), {"CHEST": {"name": "Leather Armor", "armorCategory": "LIGHT"}})
	_caster.look_at(_target.position, Vector3.UP)
	_target.look_at(_caster.position, Vector3.UP)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 5.5, 7.5)
	add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	camera.fov = 42


func _make_character(gender: String, pos: Vector3, equipment: Dictionary) -> Character:
	var character: Character = CHARACTER_SCENE.instantiate()
	add_child(character)
	character.position = pos
	character.set_gender(gender)
	character.set_equipment(equipment)
	return character


func _run() -> void:
	while true:
		await _play_once()
		if not _out.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_out)
			get_tree().quit()
			return
		await get_tree().create_timer(1.5).timeout


func _play_once() -> void:
	# Laisse quelques images au rendu pour compiler les pipelines avant de lancer le chrono.
	for i in 3:
		await get_tree().process_frame
	var wait := _time
	match _fx:
		"cast":
			_caster.play_cast(_duration)
			_vfx.start_cast(_caster, _element, _duration, _charged)
		"release":
			_caster.play_cast(_duration)
			var circle := _vfx.start_cast(_caster, _element, _duration, _charged)
			await get_tree().create_timer(_duration).timeout
			circle.finish(true)
			_caster.play_launch()
		"break":
			_caster.play_cast(_duration)
			var circle := _vfx.start_cast(_caster, _element, _duration, _charged)
			await get_tree().create_timer(_duration * 0.5).timeout
			circle.finish(false)
			_caster.play_state(Character.IDLE_ANIM)
		"projectile":
			_vfx.play_projectile(_caster, _target, _element, _duration, Callable(), SpellVfx.projectile_style_for_skill(_skill))
		"target":
			if _skill.is_empty():
				_vfx.play_on_target(_target, _element)
			else:
				_vfx.play_skill_on_target(_target, _skill, _element)
		"charge":
			_vfx.play_weapon_charge(_caster, _skill, _duration)
		"drain":
			_vfx.play_drain(_target, _caster)
		"poison":
			_vfx.play_poison_tick(_target)
		"escape":
			_caster.play_cast(_duration)
			var circle := _vfx.start_cast(_caster, SpellVfx.Element.ESCAPE, _duration)
			await get_tree().create_timer(_duration).timeout
			circle.finish(true)
			_caster.play_launch()
			_vfx.play_escape(_caster, 1.6)
		"impact":
			_vfx.play_impact(_target.global_position, _element)
	await get_tree().create_timer(wait).timeout
