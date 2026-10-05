extends Node3D
## Outil de développement (hors jeu) : aligne des mannequins homme/femme avec différents
## équipements (voir LINEUP), leur fait jouer une animation, puis enregistre une capture PNG
## et quitte. Sert à vérifier visuellement Character.gd et les .glb générés par
## tools/character_gen/build_characters.py.
##
## Usage :
##   Godot_console.exe --path . res://tools/character_preview/CharacterPreview.tscn -- \
##       --anim=attack --time=0.45 --out=C:/tmp/attack.png
## --anim : idle, run, cast, launch, attack, death, equip, unequip (effet d'apparition/de
## disparition de l'équipement, voir Character._play_mesh_effect) ; --time : secondes dans le
## clip/l'effet.
## Sans --out, la scène reste ouverte (animations en boucle, pratique dans l'éditeur).
## --lineup=guards : PNJ (gardes homme/femme, maître, marchande, forgeron, villageois sans
## type) en tenue Character.NPC_OUTFITS, vus de plus près.

const CHARACTER_SCENE := preload("res://scenes/game/entities/Character.tscn")

## [sexe, {slot: item factice}] — noms tirés du catalogue réel pour passer par la même
## devinette nom -> mesh que le jeu (Character.visual_for_item).
const LINEUP := [
	["man", {}],
	["woman", {}],
	["man", {
		"WEAPON": {"name": "Long Sword"}, "OFF_HAND": {"name": "Wooden Shield", "type": "SHIELD"},
		"CHEST": {"name": "Leather Armor", "armorCategory": "LIGHT"}, "LEGS": {"name": "Leather Pants"},
		"FEET": {"name": "Leather Boots"}, "HANDS": {"name": "Leather Gloves"}, "HEAD": {"name": "Leather Cap"},
	}],
	["woman", {
		"WEAPON": {"name": "Bastard Sword"}, "CHEST": {"name": "Plate Armor", "armorCategory": "HEAVY"},
		"LEGS": {"name": "Dark Crystal Leggings", "armorCategory": "HEAVY"}, "HEAD": {"name": "Iron Helmet", "armorCategory": "HEAVY"},
		"HANDS": {"name": "Draconic Gauntlets", "armorCategory": "HEAVY"}, "FEET": {"name": "Draconic Boots", "armorCategory": "HEAVY"},
	}],
	["man", {
		"WEAPON": {"name": "Hammer of Ruin"}, "CHEST": {"name": "Chain Mail", "armorCategory": "HEAVY"},
		"FEET": {"name": "Dark Crystal Boots", "armorCategory": "HEAVY"}, "HEAD": {"name": "Helm of Terror", "armorCategory": "HEAVY"},
	}],
	["woman", {
		"WEAPON": {"name": "Staff of Healing"}, "CHEST": {"name": "Major Arcana Robe", "armorCategory": "ROBE"},
		"HEAD": {"name": "Major Arcana Circlet", "armorCategory": "LIGHT"},
	}],
	["man", {
		"WEAPON": {"name": "Wand of Flames"}, "CHEST": {"name": "Tallum Tunic", "armorCategory": "ROBE"},
		"HEAD": {"name": "Tallum Hood", "armorCategory": "LIGHT"}, "FEET": {"name": "Leather Boots"},
	}],
	["woman", {
		"WEAPON": {"name": "Wooden Bow"}, "CHEST": {"name": "Leather Tunic", "armorCategory": "LIGHT"},
		"LEGS": {"name": "Leather Pants"}, "FEET": {"name": "Leather Boots"},
	}],
	["man", {"WEAPON": {"name": "Dagger"}, "CHEST": {"name": "Padded Armor", "armorCategory": "LIGHT"}}],
	["woman", {"WEAPON": {"name": "Battle Axe"}, "OFF_HAND": {"name": "Draconic Shield", "type": "SHIELD"},
		"CHEST": {"name": "Zealot's Armor", "armorCategory": "LIGHT"}}],
]
## PNJ : [sexe, npcType] — tenue fixe (Character.set_outfit).
const GUARD_LINEUP := [
	["man", "GUARD"], ["woman", "GUARD"], ["man", "SKILL_LEARNER"], ["woman", "MERCHANT"],
	["man", "BLACKSMITH"], ["man", ""],
]
const SPACING := 1.1

var _anim := "idle"
var _time := 0.6
var _out := ""
var _lineup: Array = LINEUP
var _characters: Array[Character] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim="):
			_anim = arg.substr(7)
		elif arg.begins_with("--time="):
			_time = float(arg.substr(7))
		elif arg == "--lineup=guards":
			_lineup = GUARD_LINEUP
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
	_build_stage()
	for i in _lineup.size():
		var character: Character = CHARACTER_SCENE.instantiate()
		add_child(character)
		character.position = Vector3((i - (_lineup.size() - 1) / 2.0) * SPACING, 0, 0)
		# Les personnages regardent -Z dans le jeu (look_at) : on les tourne vers la caméra.
		character.rotation.y = PI
		character.set_gender(_lineup[i][0])
		# equip : on part en sous-vêtements (la tenue initiale n'est jamais animée), l'équipement
		# arrive dans _start.
		if _lineup[i][1] is String:
			character.set_outfit(_lineup[i][1])
		else:
			character.set_equipment({} if _anim == "equip" else _lineup[i][1])
		_characters.append(character)
	_start.call_deferred()


func _build_stage() -> void:
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
	plane.size = Vector2(14, 4)
	ground.mesh = plane
	add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.1, 6.2) if _lineup.size() > 2 else Vector3(0, 1.0, 3.0)
	camera.rotation_degrees = Vector3(-4, 0, 0)
	camera.fov = 40
	add_child(camera)


func _start() -> void:
	for i in _characters.size():
		var character := _characters[i]
		match _anim:
			"equip":
				if _lineup[i][1] is Dictionary:
					character.set_equipment(_lineup[i][1])
			"unequip":
				character.set_equipment({})
			"run":
				character.play_state(Character.RUN_ANIM)
			"cast":
				character.play_cast(0.0)
			"launch":
				character.play_launch()
			"attack":
				character.play_attack()
			"death":
				character.play_death()
			_:
				character.play_state(Character.IDLE_ANIM)
	if _out.is_empty():
		return
	await get_tree().create_timer(_time).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	get_tree().quit()
