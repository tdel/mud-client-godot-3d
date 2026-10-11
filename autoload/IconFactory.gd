class_name IconFactory
extends RefCounted
## Icônes procédurales d'objets, de compétences et de l'interface, dans l'esprit des icônes
## Lineage 2 (objet peint, éclairé en haut à gauche, sur fond sombre vignetté teinté par
## catégorie, cerclé d'un biseau) — entièrement dessinées en code par champs de distance
## signée (SDF), sans aucune image externe. Rendu en 64 px puis réduit à l'affichage pour un
## anticrénelage propre ; chaque icône est mise en cache (clé = type + nom + taille).
##
## Le type d'objet (WEAPON/ARMOR/...) ou de compétence (DAMAGE/HEALING/...) détermine le
## pictogramme ; quand l'appelant ne le connaît pas (hotbar, boutique), il est retrouvé par
## nom dans GameState.inventory / GameState.known_skills, sinon deviné d'après le nom.
## Les armes ont un pictogramme par WeaponType serveur (épée, dague, bâton, arc...).

const BASE_SIZE := 64

## app.domain.item.WeaponType côté backend.
const WEAPON_TYPES := ["SWORD", "BIG_SWORD", "DAGGER", "BLUNT", "BIG_BLUNT", "AXE", "POLE", "STAFF", "WAND", "BOW"]
## Repli par mots-clés (nom d'objet en minuscules, testés dans l'ordre) pour une arme dont
## le `weaponType` est inconnu (boutique, hotbar, backend antérieur à ce champ).
const WEAPON_KEYWORDS := [
	["bow", "BOW"], ["dagger", "DAGGER"], ["knife", "DAGGER"],
	["staff", "STAFF"], ["wand", "WAND"], ["rod", "WAND"], ["scepter", "WAND"],
	["spear", "POLE"], ["lance", "POLE"], ["halberd", "POLE"], ["glaive", "POLE"],
	["hammer", "BIG_BLUNT"], ["club", "BLUNT"], ["mace", "BLUNT"],
	["axe", "AXE"],
	["bastard", "BIG_SWORD"], ["great", "BIG_SWORD"], ["claymore", "BIG_SWORD"],
	["two-hand", "BIG_SWORD"], ["tsurugi", "BIG_SWORD"],
]

static var _cache: Dictionary = {}


## `kind` : "attack", "skill" ou "item". `hint` : ItemType ou skillType backend (facultatif) ;
## pour une arme, un WeaponType est plus précis que "WEAPON" (sinon il est déduit du nom).
static func slot_icon(kind: String, ref_name: String, hint: String = "", size: int = BASE_SIZE) -> Texture2D:
	if hint.is_empty():
		hint = _resolve_hint(kind, ref_name)
	if kind == "item" and hint == "WEAPON":
		hint = _weapon_type_of(ref_name)
	var key := "%s|%s|%s|%d" % [kind, ref_name, hint, size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(BASE_SIZE, BASE_SIZE, false, Image.FORMAT_RGBA8)
	_paint_slot(img, kind, ref_name, hint)
	if size != BASE_SIZE:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Pictogrammes des boutons de menu (fond transparent) : "character", "inventory",
## "skills", "options", "coin", "map", "crown".
static func ui_icon(kind: String, size: int = 32) -> Texture2D:
	var key := "ui|%s|%d" % [kind, size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(BASE_SIZE, BASE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"character":
			_ui_character(img)
		"inventory":
			_ui_bag(img)
		"skills":
			_ui_book(img)
		"options":
			_ui_gear(img)
		"coin":
			_ui_coin(img)
		"map":
			_ui_map(img)
		"crown":
			_ui_crown(img)
	if size != BASE_SIZE:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Icône d'une entrée Inventory/EquipmentView ({name, type, weaponType, ...}).
static func item_icon(item: Dictionary, size: int = BASE_SIZE) -> Texture2D:
	return slot_icon("item", str(item.get("name", "")), _item_hint(item), size)


## Matériau posé sur l'icône d'un soulshot/spiritshot armé en auto-use (hotbar et
## inventaire) : icône brillante animée, doré pour le soulshot, cyan pour le spiritshot
## (mêmes teintes que la lueur d'arme de Game3D). Partagé entre toutes les icônes.
static func active_shot_material(item_type: String) -> ShaderMaterial:
	var key := "shot_material|%s" % item_type
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = preload("res://scenes/game/hud/shot_active.gdshader")
	var color := Color(0.45, 0.85, 1.0) if item_type == "SPIRITSHOT" else Color(1.0, 0.72, 0.28)
	material.set_shader_parameter("glow_color", color)
	_cache[key] = material
	return material


static func _item_hint(item: Dictionary) -> String:
	var type_key := str(item.get("type", ""))
	var weapon_type := str(item.get("weaponType", "")).to_upper()
	if weapon_type in WEAPON_TYPES and type_key in ["WEAPON", ""]:
		return weapon_type
	return type_key


static func _resolve_hint(kind: String, ref_name: String) -> String:
	if kind == "item":
		for item in GameState.inventory.get("items", []):
			if str(item.get("name", "")) == ref_name:
				return _item_hint(item)
		return guess_item_type(ref_name)
	if kind == "skill":
		for skill in GameState.known_skills.get("skills", []):
			if str(skill.get("name", "")) == ref_name:
				return str(skill.get("skillType", ""))
	return ""


## Repli quand l'objet n'est pas (ou plus) dans l'inventaire : quelques mots-clés courants.
static func guess_item_type(ref_name: String) -> String:
	var n := ref_name.to_lower()
	var table := {
		"potion": "POTION", "elixir": "POTION", "soulshot": "SOULSHOT", "spiritshot": "SPIRITSHOT",
		"scroll": "SCROLL", "parchemin": "SCROLL",
		"sword": "WEAPON", "blade": "WEAPON", "saber": "WEAPON", "épée": "WEAPON",
		"helmet": "HELMET", "helm": "HELMET", "cap": "HELMET", "casque": "HELMET",
		"boots": "BOOTS", "shoes": "BOOTS", "bottes": "BOOTS", "gloves": "GLOVES", "gauntlets": "GLOVES",
		"shield": "SHIELD", "bouclier": "SHIELD", "ring": "RING", "anneau": "RING",
		"necklace": "NECKLACE", "collier": "NECKLACE", "earring": "EARRING",
		"pants": "PANTS", "stockings": "PANTS", "gaiters": "PANTS", "tunic": "ARMOR", "armor": "ARMOR",
		"mail": "ARMOR", "robe": "ARMOR", "shirt": "ARMOR", "key": "KEY", "clé": "KEY",
	}
	for word in table.keys():
		if n.contains(word):
			return table[word]
	for entry in WEAPON_KEYWORDS:
		if n.contains(entry[0]):
			return "WEAPON"
	return "MISC"


## WeaponType deviné d'après le nom ("SWORD" par défaut).
static func guess_weapon_type(ref_name: String) -> String:
	var n := ref_name.to_lower()
	for entry in WEAPON_KEYWORDS:
		if n.contains(entry[0]):
			return entry[1]
	return "SWORD"


## WeaponType de l'objet `ref_name` s'il est dans l'inventaire, sinon deviné.
static func _weapon_type_of(ref_name: String) -> String:
	for item in GameState.inventory.get("items", []):
		if str(item.get("name", "")) == ref_name:
			var weapon_type := str(item.get("weaponType", "")).to_upper()
			if weapon_type in WEAPON_TYPES:
				return weapon_type
	return guess_weapon_type(ref_name)


# ---------------------------------------------------------------------------
# Composition des icônes de slot
# ---------------------------------------------------------------------------

static func _paint_slot(img: Image, kind: String, ref_name: String, hint: String) -> void:
	var lower := ref_name.to_lower()
	if kind == "attack":
		_background(img, Color(0.30, 0.08, 0.06))
		_crossed_swords(img)
	elif kind == "skill":
		_paint_skill(img, lower, hint, ref_name)
	else:
		_paint_item(img, lower, hint, ref_name)
	_bevel(img)


static func _paint_skill(img: Image, lower: String, hint: String, ref_name: String) -> void:
	# Compétences L2 des classes de base (Human Fighter / Human Mystic, skills.xml backend) :
	# un pictogramme dédié par nom ; les autres retombent sur celui de leur type.
	match lower:
		"wind strike":
			_background(img, Color(0.06, 0.20, 0.18))
			_wind_spiral(img)
			return
		"power strike":
			_skill_power_strike(img)
			return
		"mortal blow":
			_skill_mortal_blow(img)
			return
		"power shot":
			_background(img, Color(0.10, 0.17, 0.07))
			_glow(img, Vector2(0.78, 0.22), 0.30, Color(1.0, 0.85, 0.4), 0.9)
			_bow(img)
			return
		"relax":
			_skill_relax(img)
			return
		"weapon mastery":
			_background(img, Color(0.14, 0.15, 0.22))
			_glow(img, Vector2(0.5, 0.45), 0.55, Color(1.0, 0.80, 0.35), 0.55)
			_crossed_swords(img)
			return
		"armor mastery":
			_background(img, Color(0.22, 0.14, 0.07))
			_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.75, 0.35), 0.45)
			_armor(img)
			return
		"anti magic":
			_skill_anti_magic(img)
			return
		"expertise grade":
			_background(img, Color(0.26, 0.20, 0.04))
			_laurel(img)
			_gem(img, Vector2(0.5, 0.48), 0.19, Color(1.0, 0.78, 0.22))
			return
		"ice bolt":
			_skill_ice_bolt(img)
			return
		"vampiric touch":
			_skill_vampiric_touch(img)
			return
		"self heal":
			_background(img, Color(0.08, 0.24, 0.12))
			_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.55, 0.55), 0.7)
			_heart(img, Vector2(0.5, 0.52), 1.0)
			return
		"battle heal":
			_skill_battle_heal(img)
			return
		"group heal":
			_background(img, Color(0.08, 0.24, 0.12))
			_glow(img, Vector2(0.5, 0.52), 0.6, Color(0.70, 0.95, 0.45), 0.8)
			for c in [Vector2(0.5, 0.30), Vector2(0.28, 0.66), Vector2(0.72, 0.66)]:
				var cross_c: Vector2 = c
				_small_cross(img, cross_c, 0.62)
			return
		"might":
			_skill_might(img)
			return
		"shield":
			_background(img, Color(0.06, 0.12, 0.30))
			_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.45, 0.70, 1.0), 0.8)
			_shield(img)
			return
		"curse: weakness":
			_skill_curse_weakness(img)
			return
		"curse: poison":
			_skill_curse_poison(img)
			return
		"cure poison":
			_skill_cure_poison(img)
			return
		"weapon grade penalty":
			_skill_grade_penalty(img, true)
			return
		"armor grade penalty":
			_skill_grade_penalty(img, false)
			return
		# Maîtrises partagées par plusieurs professions (une icône par nom).
		"light armor mastery":
			_skill_light_armor_mastery(img)
			return
		"heavy armor mastery":
			_skill_heavy_armor_mastery(img)
			return
		"robe mastery":
			_skill_robe_mastery(img)
			return
		"sword/blunt weapon mastery":
			_skill_sword_blunt_mastery(img)
			return
		# Warrior / Gladiator / Warlord.
		"detect insect weakness":
			_skill_detect_weakness(img, false)
			return
		"detect animal weakness":
			_skill_detect_weakness(img, true)
			return
		"war cry":
			_skill_war_cry(img)
			return
		"stun attack":
			_skill_stun_attack(img)
			return
		"battle roar":
			_skill_battle_roar(img)
			return
		"vital force":
			_skill_vital_force(img)
			return
		"boost hp":
			_skill_boost_hp(img)
			return
		"fast hp recovery":
			_skill_fast_hp_recovery(img)
			return
		"polearm mastery":
			_skill_polearm_mastery(img)
			return
		"wild sweep":
			_skill_wild_sweep(img)
			return
		"power smash":
			_skill_power_smash(img)
			return
		"accuracy":
			_skill_accuracy(img)
			return
		"lionheart":
			_skill_lionheart(img)
			return
		"vicious stance":
			_skill_vicious_stance(img)
			return
		"triple slash":
			_skill_triple_slash(img)
			return
		"dual weapon mastery":
			_skill_dual_weapon_mastery(img)
			return
		"fatal strike":
			_skill_fatal_strike(img)
			return
		"hammer crush":
			_skill_hammer_crush(img)
			return
		"whirlwind":
			_skill_whirlwind(img)
			return
		"thunder storm":
			_skill_thunder_storm(img)
			return
		"focus attack":
			_skill_focus_attack(img)
			return
		"power crush":
			_skill_power_crush(img)
			return
		# Human Knight / Paladin / Dark Avenger.
		"aggression":
			_skill_aggression(img)
			return
		"aura of hate":
			_skill_aura_of_hate(img)
			return
		"divine heal":
			_skill_divine_heal(img)
			return
		"drain health":
			_skill_drain_health(img)
			return
		"majesty":
			_skill_majesty(img)
			return
		"shield stun":
			_skill_shield_stun(img)
			return
		"ultimate defense":
			_skill_ultimate_defense(img)
			return
		"deflect arrow":
			_skill_deflect_arrow(img)
			return
		"magic resistance":
			_skill_magic_resistance(img)
			return
		"shield mastery":
			_skill_shield_mastery(img)
			return
		"focus mind":
			_skill_focus_mind(img)
			return
		"remedy":
			_skill_remedy(img)
			return
		"holy armor":
			_skill_holy_armor(img)
			return
		"holy blessing":
			_skill_holy_blessing(img)
			return
		"life scavenge":
			_skill_corpse_drain(img, false)
			return
		"reflect damage":
			_skill_reflect_damage(img)
			return
		"summon dark panther":
			_skill_summon_dark_panther(img)
			return
		# Rogue / Treasure Hunter / Hawkeye.
		"dash":
			_skill_dash(img)
			return
		"bleed":
			_skill_bleed(img)
			return
		"rapid shot":
			_skill_rapid_shot(img)
			return
		"stun shot":
			_skill_stun_shot(img)
			return
		"ultimate evasion":
			_skill_ultimate_evasion(img)
			return
		"long shot":
			_skill_long_shot(img)
			return
		"critical chance":
			_skill_critical_chance(img)
			return
		"critical power":
			_skill_critical_power(img)
			return
		"boost attack speed":
			_skill_boost_attack_speed(img)
			return
		"quick step":
			_skill_quick_step(img)
			return
		"esprit":
			_skill_esprit(img)
			return
		"boost evasion":
			_skill_boost_evasion(img)
			return
		"bow mastery":
			_skill_bow_mastery(img)
			return
		"dagger mastery":
			_skill_dagger_mastery(img)
			return
		"acrobatic move":
			_skill_acrobatic_move(img)
			return
		"backstab":
			_skill_backstab(img)
			return
		"fake death":
			_skill_fake_death(img)
			return
		"silent move":
			_skill_silent_move(img)
			return
		"deadly blow":
			_skill_deadly_blow(img)
			return
		"shadow step":
			_skill_shadow_step(img)
			return
		"double shot":
			_skill_double_shot(img)
			return
		"hawk eye":
			_skill_hawk_eye(img)
			return
		"soul of sagittarius":
			_skill_soul_of_sagittarius(img)
			return
		# Human Wizard / Sorcerer / Necromancer / Warlock.
		"quick recycle":
			_skill_quick_recycle(img)
			return
		"boost mana":
			_skill_boost_mana(img)
			return
		"fast spell casting":
			_skill_fast_spell_casting(img)
			return
		"fast mana recovery":
			_skill_fast_mana_recovery(img)
			return
		"higher mana gain":
			_skill_higher_mana_gain(img)
			return
		"sleep":
			_skill_sleep(img)
			return
		"concentration":
			_skill_concentration(img)
			return
		"surrender to fire":
			_skill_surrender(img, true)
			return
		"surrender to wind":
			_skill_surrender(img, false)
			return
		"summon kat the cat":
			_skill_summon_kat(img)
			return
		"summon mew the cat":
			_skill_summon_mew(img)
			return
		"summon kai the cat":
			_skill_summon_kai(img)
			return
		"servitor recharge":
			_skill_servitor_recharge(img)
			return
		"servitor heal":
			_skill_servitor_heal(img)
			return
		"servitor wind walk":
			_skill_servitor_wind_walk(img)
			return
		"servitor physical shield":
			_skill_servitor_physical_shield(img)
			return
		"servitor cure":
			_skill_servitor_cure(img)
			return
		"corpse life drain":
			_skill_corpse_drain(img, true)
			return
		"body to mind":
			_skill_body_to_mind(img)
			return
		"slow":
			_skill_slow(img)
			return
		"poisonous cloud":
			_skill_poisonous_cloud(img)
			return
		"aura burn":
			_skill_aura_burn(img)
			return
		"flame strike":
			_skill_flame_strike(img)
			return
		"blaze":
			_skill_blaze(img)
			return
		"curse chaos":
			_skill_curse_chaos(img)
			return
		"energy bolt":
			_skill_energy_bolt(img)
			return
		"curse fear":
			_skill_curse_fear(img)
			return
		"blazing circle":
			_skill_blazing_circle(img)
			return
		"prominence":
			_skill_prominence(img)
			return
		"aura flare":
			_skill_aura_flare(img)
			return
		"blazing skin":
			_skill_blazing_skin(img)
			return
		"aura bolt":
			_skill_aura_bolt(img)
			return
		"clear mind":
			_skill_clear_mind(img)
			return
		"silence":
			_skill_silence(img)
			return
		"summon corrupted man":
			_skill_summon_corrupted_man(img)
			return
		"curse discord":
			_skill_curse_discord(img)
			return
		"anchor":
			_skill_anchor(img)
			return
		"vampiric claw":
			_skill_vampiric_claw(img)
			return
		"transfer pain":
			_skill_transfer_pain(img)
			return
		"summon storm cubic":
			_skill_summon_cubic(img, true)
			return
		"mass summon storm cubic":
			_skill_summon_cubic(img, true, true)
			return
		"summon binding cubic":
			_skill_summon_cubic(img, false)
			return
		# Cleric / Bishop / Prophet.
		"resurrection":
			_skill_resurrection(img)
			return
		"mass resurrection":
			_skill_mass_resurrection(img)
			return
		"disrupt undead":
			_skill_disrupt_undead(img)
			return
		"might of heaven":
			_skill_might_of_heaven(img)
			return
		"mental shield":
			_skill_mental_shield(img)
			return
		"holy weapon":
			_skill_holy_weapon(img)
			return
		"regeneration":
			_skill_regeneration(img)
			return
		"berserker spirit":
			_skill_berserker_spirit(img)
			return
		"peace":
			_skill_peace(img)
			return
		"focus":
			_skill_focus(img)
			return
		"acumen":
			_skill_acumen(img)
			return
		"resist fire":
			_skill_resist_fire(img)
			return
		"dryad root":
			_skill_dryad_root(img)
			return
		"wind walk":
			_skill_wind_walk(img)
			return
		"requiem":
			_skill_requiem(img)
			return
		"greater heal":
			_skill_greater_heal(img)
			return
		"greater battle heal":
			_skill_greater_battle_heal(img)
			return
		"greater group heal":
			_skill_greater_group_heal(img)
			return
		"invigor":
			_skill_invigor(img)
			return
		"return":
			_skill_return(img)
			return
		"guidance":
			_skill_guidance(img)
			return
		"death whisper":
			_skill_death_whisper(img)
			return
		"bless shield":
			_skill_bless_shield(img)
			return
		# Effets serveur affichés dans la barre d'effets (cubiques, attaques des chats).
		"storm cubic":
			_skill_storm_cubic(img)
			return
		"binding cubic":
			_skill_binding_cubic(img)
			return
		"master recharge":
			_skill_master_recharge(img)
			return
		"mega storm strike":
			_skill_mega_storm_strike(img)
			return
	match hint:
		"PASSIVE":
			_background(img, Color(0.22, 0.18, 0.06))
			_laurel(img)
			_gem(img, Vector2(0.5, 0.48), 0.17, _gem_color(ref_name))
			return
		"HEALING":
			_background(img, Color(0.08, 0.24, 0.12))
			_holy_cross(img)
		"BUFF":
			_background(img, Color(0.08, 0.14, 0.32))
			_buff_arrow(img)
		"DEBUFF":
			_background(img, Color(0.20, 0.06, 0.24))
			_debuff_arrow(img)
		_:
			var palette := [
				[Color(0.34, 0.10, 0.03), Color(1.0, 0.55, 0.15), Color(1.0, 0.92, 0.55)],
				[Color(0.06, 0.12, 0.30), Color(0.45, 0.70, 1.0), Color(0.90, 0.97, 1.0)],
				[Color(0.20, 0.07, 0.30), Color(0.78, 0.45, 1.0), Color(0.98, 0.88, 1.0)],
				[Color(0.25, 0.20, 0.03), Color(1.0, 0.85, 0.25), Color(1.0, 1.0, 0.80)],
			]
			var colors: Array = palette[absi(hash(ref_name)) % palette.size()]
			_background(img, colors[0])
			_burst(img, colors[1], colors[2], absi(hash(ref_name + "#")) % 3 + 7)


static func _paint_item(img: Image, lower: String, hint: String, ref_name: String) -> void:
	if hint in WEAPON_TYPES or hint == "WEAPON":
		_paint_weapon(img, hint)
		return
	match hint:
		"HELMET":
			_background(img, Color(0.17, 0.13, 0.10))
			_helmet(img)
		"ARMOR":
			_background(img, Color(0.17, 0.13, 0.10))
			_armor(img)
		"PANTS":
			_background(img, Color(0.15, 0.13, 0.11))
			_pants(img)
		"BOOTS":
			_background(img, Color(0.16, 0.12, 0.09))
			_boots(img)
		"GLOVES":
			_background(img, Color(0.16, 0.12, 0.09))
			_gloves(img)
		"SHIELD":
			_background(img, Color(0.12, 0.13, 0.17))
			_shield(img)
		"NECKLACE":
			_background(img, Color(0.16, 0.08, 0.20))
			_necklace(img, _gem_color(ref_name))
		"EARRING":
			_background(img, Color(0.16, 0.08, 0.20))
			_earring(img, _gem_color(ref_name))
		"RING":
			_background(img, Color(0.16, 0.08, 0.20))
			_ring(img, _gem_color(ref_name))
		"POTION":
			var liquid := Color(0.30, 0.80, 0.35)
			if lower.contains("heal") or lower.contains("soin") or lower.contains("vie"):
				liquid = Color(0.88, 0.12, 0.14)
			elif lower.contains("mana"):
				liquid = Color(0.22, 0.45, 1.0)
			_background(img, liquid.darkened(0.78))
			_potion(img, liquid)
		"SOULSHOT":
			_background(img, Color(0.22, 0.10, 0.03))
			_shots(img, Color(1.0, 0.60, 0.15), Color(1.0, 0.95, 0.65))
		"SPIRITSHOT":
			_background(img, Color(0.04, 0.12, 0.25))
			_shots(img, Color(0.30, 0.75, 1.0), Color(0.88, 1.0, 1.0))
		"SCROLL":
			_background(img, Color(0.10, 0.12, 0.18))
			_scroll(img)
		"KEY":
			_background(img, Color(0.15, 0.13, 0.08))
			_key(img)
		"TOOL":
			_background(img, Color(0.13, 0.13, 0.13))
			_hammer(img)
		_:
			_background(img, Color(0.14, 0.12, 0.10))
			_pouch(img)


## Fond teinté par famille : acier bleuté (mêlée), vert (arc), violet (armes de mage).
static func _paint_weapon(img: Image, weapon_type: String) -> void:
	match weapon_type:
		"STAFF", "WAND":
			_background(img, Color(0.15, 0.09, 0.22))
		"BOW":
			_background(img, Color(0.10, 0.15, 0.09))
		_:
			_background(img, Color(0.12, 0.14, 0.19))
	match weapon_type:
		"BIG_SWORD":
			_greatsword(img)
		"DAGGER":
			_dagger(img)
		"BLUNT":
			_mace(img)
		"BIG_BLUNT":
			_warhammer(img)
		"AXE":
			_axe(img)
		"POLE":
			_spear(img)
		"STAFF":
			_staff(img)
		"WAND":
			_wand(img)
		"BOW":
			_bow(img)
		_:
			_sword(img, Vector2(0.37, 0.63), -PI / 4.0, 1.0)


static func _gem_color(ref_name: String) -> Color:
	var gems := [Color(0.95, 0.15, 0.20), Color(0.20, 0.50, 1.0), Color(0.20, 0.85, 0.40), Color(0.75, 0.30, 1.0), Color(1.0, 0.80, 0.20)]
	return gems[absi(hash(ref_name)) % gems.size()]


# ---------------------------------------------------------------------------
# Moteur de peinture : SDF + ombrage + contour, composés "par-dessus" l'image
# ---------------------------------------------------------------------------

## Peint la forme `sdf` (distance signée en pixels, <0 à l'intérieur) ombrée par `shade`
## (Callable(p: Vector2 normalisé 0..1, d: float) -> Color), avec un contour sombre de
## `outline` px et un reflet clair le long du bord intérieur éclairé.
static func _draw(img: Image, sdf: Callable, shade: Callable, outline: float = 1.6) -> void:
	var s := float(BASE_SIZE)
	for y in BASE_SIZE:
		for x in BASE_SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = sdf.call(p)
			if d > outline + 1.0:
				continue
			var col: Color
			if d > 0.0:
				var a := clampf(outline + 0.5 - d, 0.0, 1.0) * 0.85
				col = Color(0, 0, 0, a)
			else:
				col = shade.call(p / s, d)
				var edge := clampf(0.5 - d, 0.0, 1.0)
				col.a *= edge
			_blend(img, x, y, col)


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if c.a <= 0.0:
		return
	var dst := img.get_pixel(x, y)
	var a := c.a + dst.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var r := (c.r * c.a + dst.r * dst.a * (1.0 - c.a)) / a
	var g := (c.g * c.a + dst.g * dst.a * (1.0 - c.a)) / a
	var b := (c.b * c.a + dst.b * dst.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(r, g, b, a))


## Halo lumineux additif (reflet magique, lueur de gemme).
static func _glow(img: Image, center: Vector2, radius: float, color: Color, intensity: float) -> void:
	var c := center * BASE_SIZE
	var r := radius * BASE_SIZE
	for y in BASE_SIZE:
		for x in BASE_SIZE:
			var t := 1.0 - Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if t <= 0.0:
				continue
			var k := t * t * intensity
			var dst := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				minf(dst.r + color.r * k, 1.0), minf(dst.g + color.g * k, 1.0),
				minf(dst.b + color.b * k, 1.0), maxf(dst.a, minf(k, 1.0))
			))


## Ombrage "métal/cuir" : dégradé selon la direction de la lumière (haut-gauche) entre
## `dark` et `light`, avec un reflet spéculaire en bande.
static func _lit_shade(light: Color, dark: Color, spec: float = 0.35) -> Callable:
	return func(p: Vector2, _d: float) -> Color:
		var t := clampf((p.x + p.y) * 0.75 - 0.25, 0.0, 1.0)
		var c := light.lerp(dark, t)
		var band := exp(-pow((p.x + p.y - 0.78) * 7.0, 2.0)) * spec
		return c.lerp(Color.WHITE, band)


static func _flat(color: Color) -> Callable:
	return func(_p: Vector2, _d: float) -> Color:
		return color


## Fond de slot : dégradé radial teinté, plus sombre sur les bords.
static func _background(img: Image, tint: Color) -> void:
	var c := Vector2(0.42, 0.38) * BASE_SIZE
	for y in BASE_SIZE:
		for x in BASE_SIZE:
			var t := clampf(Vector2(x + 0.5, y + 0.5).distance_to(c) / (BASE_SIZE * 0.78), 0.0, 1.0)
			var col := tint.lightened(0.10).lerp(Color(0.01, 0.01, 0.015), t * t * 0.9 + t * 0.1)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))


## Biseau : filet noir extérieur, lumière en haut à gauche, ombre en bas à droite.
static func _bevel(img: Image) -> void:
	var n := BASE_SIZE
	for i in n:
		for edge in [Vector2i(i, 0), Vector2i(0, i), Vector2i(i, n - 1), Vector2i(n - 1, i)]:
			img.set_pixel(edge.x, edge.y, Color(0, 0, 0, 1))
	for i in range(1, n - 1):
		_blend(img, i, 1, Color(1, 1, 1, 0.28))
		_blend(img, 1, i, Color(1, 1, 1, 0.20))
		_blend(img, i, n - 2, Color(0, 0, 0, 0.55))
		_blend(img, n - 2, i, Color(0, 0, 0, 0.55))


# --- Primitives SDF (coordonnées en pixels) ----------------------------------

static func _px(v: Vector2) -> Vector2:
	return v * BASE_SIZE


static func _sd_circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(_px(c)) - r * BASE_SIZE


static func _sd_capsule(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := p - _px(a)
	var ba := _px(b) - _px(a)
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - r * BASE_SIZE


static func _sd_box(p: Vector2, c: Vector2, half: Vector2, angle: float = 0.0, radius: float = 0.0) -> float:
	var q := (p - _px(c)).rotated(-angle)
	var hs := half * BASE_SIZE
	var rr := radius * BASE_SIZE
	var d := Vector2(absf(q.x), absf(q.y)) - hs + Vector2(rr, rr)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - rr


## SDF d'un polygone (points normalisés), d'après I. Quilez.
static func _sd_poly(p: Vector2, pts: Array) -> float:
	var n := pts.size()
	var v0: Vector2 = _px(pts[0])
	var d := (p - v0).dot(p - v0)
	var s := 1.0
	var j := n - 1
	for i in n:
		var vi: Vector2 = _px(pts[i])
		var vj: Vector2 = _px(pts[j])
		var e := vj - vi
		var w := p - vi
		var b := w - e * clampf(w.dot(e) / e.dot(e), 0.0, 1.0)
		d = minf(d, b.dot(b))
		var c1 := p.y >= vi.y
		var c2 := p.y < vj.y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
		j = i
	return s * sqrt(d)


## Transforme des points exprimés dans un repère local (origine, angle, échelle).
static func _xf(pts: Array, origin: Vector2, angle: float, scale: float) -> Array:
	var out := []
	for pt in pts:
		out.append(origin + (pt as Vector2).rotated(angle) * scale)
	return out


# --- Objets --------------------------------------------------------------------

const STEEL_LIGHT := Color(0.92, 0.94, 0.97)
const STEEL_DARK := Color(0.36, 0.40, 0.48)
const GOLD_LIGHT := Color(1.0, 0.88, 0.50)
const GOLD_DARK := Color(0.45, 0.28, 0.06)
const LEATHER_LIGHT := Color(0.62, 0.42, 0.24)
const LEATHER_DARK := Color(0.22, 0.12, 0.05)
const WOOD_LIGHT := Color(0.72, 0.52, 0.30)
const WOOD_DARK := Color(0.24, 0.13, 0.05)

## Axe des armes : du bas-gauche (poignée) vers le haut-droit (pointe), et sa perpendiculaire
## (vers le bas-droit ; son opposé pointe vers la lumière).
const AXIS := Vector2(0.7071, -0.7071)
const ACROSS := Vector2(0.7071, 0.7071)


## Lame droite à arête centrale, garde, poignée cuir et pommeau ; `blade_len` (partie
## parallèle), `half_w`, `tip` (longueur de la pointe), `grip_len` et `guard_half` en
## unités locales, multipliées par `scale`. Les défauts donnent l'épée à une main.
static func _sword(img: Image, origin: Vector2, angle: float, scale: float, blade_len: float = 0.46,
		half_w: float = 0.05, tip: float = 0.10, grip_len: float = 0.15, guard_half: float = 0.17) -> void:
	var blade := _xf([Vector2(0.0, -half_w), Vector2(blade_len, -half_w), Vector2(blade_len + tip, 0.0), Vector2(blade_len, half_w), Vector2(0.0, half_w)], origin, angle, scale)
	var axis_dir := Vector2.RIGHT.rotated(angle)
	var perp := Vector2.DOWN.rotated(angle)
	# Lame : deux pans (arête centrale), le pan éclairé plus clair.
	_draw(img, func(p): return _sd_poly(p, blade), func(q: Vector2, _d: float) -> Color:
		var side := (q - origin).dot(perp)
		var along := clampf((q - origin).dot(axis_dir) / ((blade_len + tip) * scale), 0.0, 1.0)
		var c := STEEL_LIGHT if side < 0.0 else STEEL_DARK.lerp(STEEL_LIGHT, 0.35)
		return c.lerp(Color(0.75, 0.80, 0.90), along * 0.3))
	var guard_c := origin + axis_dir * -0.01 * scale
	_draw(img, func(p): return _sd_box(p, guard_c, Vector2(0.035, guard_half) * scale, angle, 0.015), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	_grip(img, origin + axis_dir * -0.05 * scale, origin + axis_dir * -(0.05 + grip_len) * scale, 0.032 * scale)
	var pommel := origin + axis_dir * -(0.09 + grip_len) * scale
	_draw(img, func(p): return _sd_circle(p, pommel, 0.05 * scale), _lit_shade(GOLD_LIGHT, GOLD_DARK))


static func _crossed_swords(img: Image) -> void:
	_sword(img, Vector2(0.34, 0.66), -PI / 4.0, 0.85)
	_sword(img, Vector2(0.66, 0.66), -3.0 * PI / 4.0, 0.85)


## Ombrage cylindrique d'une hampe a -> b de rayon `r` (normalisés) : clair du côté haut-gauche,
## reflet en bande le long de l'axe.
static func _cyl_shade(a: Vector2, b: Vector2, r: float, light: Color, dark: Color, spec: float = 0.3) -> Callable:
	return func(q: Vector2, _d: float) -> Color:
		var ba := b - a
		var h := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		var lit := clampf((q - (a + ba * h)).dot(-ACROSS) / r, -1.0, 1.0)
		var c := dark.lerp(light, lit * 0.5 + 0.5)
		return c.lerp(Color.WHITE, exp(-pow((lit - 0.5) * 3.0, 2.0)) * spec)


## Ombrage sphérique : point chaud en haut à gauche.
static func _sphere_shade(c: Vector2, r: float, light: Color, dark: Color) -> Callable:
	return func(q: Vector2, _d: float) -> Color:
		var t := clampf(q.distance_to(c + Vector2(-0.38, -0.42) * r) / (r * 1.5), 0.0, 1.0)
		return light.lerp(dark, t)


## Hampe en bois a -> b.
static func _shaft(img: Image, a: Vector2, b: Vector2, r: float) -> void:
	_draw(img, func(p): return _sd_capsule(p, a, b, r), _cyl_shade(a, b, r, WOOD_LIGHT, WOOD_DARK, 0.2))


## Poignée tressée de cuir a -> b.
static func _grip(img: Image, a: Vector2, b: Vector2, r: float) -> void:
	var dir := (b - a).normalized()
	_draw(img, func(p): return _sd_capsule(p, a, b, r), func(q: Vector2, _d: float) -> Color:
		var k := sin((q - a).dot(dir) * 140.0)
		return LEATHER_LIGHT.lerp(LEATHER_DARK, 0.5 + k * 0.3))


## Bague dorée perpendiculaire à l'axe, centrée en `c`.
static func _collar(img: Image, c: Vector2, half_len: float, half_w: float) -> void:
	_draw(img, func(p): return _sd_box(p, c, Vector2(half_len, half_w), -PI / 4.0, 0.008), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


## Espadon : lame plus large et plus longue, longue fusée, large garde, gorge centrale.
static func _greatsword(img: Image) -> void:
	var origin := Vector2(0.33, 0.67)
	var scale := 1.0
	_sword(img, origin, -PI / 4.0, scale, 0.53, 0.085, 0.10, 0.20, 0.25)
	_draw(img, func(p): return _sd_capsule(p, origin + AXIS * 0.07 * scale, origin + AXIS * 0.48 * scale, 0.014 * scale),
		_flat(Color(0.20, 0.23, 0.31, 0.95)), 0.0)


## Dague : lame courte et large à longue pointe effilée, petite garde.
static func _dagger(img: Image) -> void:
	_sword(img, Vector2(0.42, 0.58), -PI / 4.0, 1.15, 0.13, 0.058, 0.21, 0.12, 0.13)


## Masse d'armes : manche de bois, tête sphérique à ailettes.
static func _mace(img: Image) -> void:
	var a := Vector2(0.24, 0.80)
	var head := Vector2(0.65, 0.39)
	_shaft(img, a, head, 0.032)
	_grip(img, a.lerp(head, 0.06), a.lerp(head, 0.42), 0.038)
	_draw(img, func(p): return _sd_circle(p, a, 0.045), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	_collar(img, head - AXIS * 0.15, 0.028, 0.055)
	var flanges := []
	for i in 16:
		var ang := TAU * i / 16.0 - PI / 4.0
		flanges.append(head + Vector2(cos(ang), sin(ang)) * (0.19 if i % 2 == 0 else 0.125))
	_draw(img, func(p): return _sd_poly(p, flanges) - 0.8, _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.45))
	_draw(img, func(p): return _sd_circle(p, head, 0.10), _sphere_shade(head, 0.10, STEEL_LIGHT, STEEL_DARK), 1.0)


## Marteau de guerre : long manche, tête massive à deux faces, pointe sommitale.
static func _warhammer(img: Image) -> void:
	var a := Vector2(0.18, 0.84)
	var head := Vector2(0.64, 0.38)
	_shaft(img, a, head, 0.032)
	_grip(img, a.lerp(head, 0.05), a.lerp(head, 0.36), 0.038)
	_draw(img, func(p): return _sd_circle(p, a, 0.045), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	var spike := _xf([Vector2(0.06, -0.045), Vector2(0.20, 0.0), Vector2(0.06, 0.045)], head, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, spike), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4))
	_draw(img, func(p): return _sd_box(p, head, Vector2(0.085, 0.19), -PI / 4.0, 0.02), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.45))
	for side in [-1.0, 1.0]:
		var face: Vector2 = head + ACROSS * 0.19 * side
		_draw(img, func(p): return _sd_box(p, face, Vector2(0.105, 0.035), -PI / 4.0, 0.01), _lit_shade(STEEL_LIGHT.darkened(0.1), STEEL_DARK.darkened(0.2), 0.3), 1.2)
	_collar(img, head, 0.09, 0.035)


## Hache de bataille : manche de bois, fer en croissant côté lumière, ergot au dos.
static func _axe(img: Image) -> void:
	var a := Vector2(0.24, 0.80)
	var top := Vector2(0.67, 0.37)
	var o := Vector2(0.60, 0.44)
	_shaft(img, a, top, 0.032)
	_grip(img, a.lerp(top, 0.05), a.lerp(top, 0.38), 0.038)
	var blade := _xf([Vector2(0.06, -0.02), Vector2(0.12, -0.11), Vector2(0.19, -0.21), Vector2(0.10, -0.265),
		Vector2(0.0, -0.28), Vector2(-0.10, -0.265), Vector2(-0.19, -0.21), Vector2(-0.12, -0.11), Vector2(-0.06, -0.02)], o, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, blade), func(q: Vector2, d: float) -> Color:
		var e := clampf((q - o).dot(-ACROSS) / 0.28, 0.0, 1.0)
		if e > 0.72 and d > -2.2:
			return STEEL_LIGHT.lerp(Color.WHITE, 0.5)
		return STEEL_DARK.lerp(STEEL_LIGHT, 0.25 + e * 0.6))
	var spur := _xf([Vector2(0.05, 0.02), Vector2(0.0, 0.14), Vector2(-0.05, 0.02)], o, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, spur), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.3))
	_collar(img, o, 0.075, 0.045)


## Lance : longue hampe, fer en feuille à nervure, douille dorée et houppe rouge.
static func _spear(img: Image) -> void:
	var a := Vector2(0.12, 0.88)
	var o := Vector2(0.66, 0.34)
	_shaft(img, a, o, 0.026)
	_draw(img, func(p): return _sd_circle(p, a, 0.032), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	var knot := o - AXIS * 0.06
	for dx in [-0.03, 0.0, 0.03]:
		var end: Vector2 = knot + Vector2(dx, 0.15)
		_draw(img, func(p): return _sd_capsule(p, knot, end, 0.016), _lit_shade(Color(0.95, 0.28, 0.20), Color(0.42, 0.04, 0.04), 0.2), 1.0)
	var head := _xf([Vector2(0.0, -0.03), Vector2(0.07, -0.07), Vector2(0.25, 0.0), Vector2(0.07, 0.07), Vector2(0.0, 0.03)], o, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, head), func(q: Vector2, _d: float) -> Color:
		return STEEL_LIGHT if (q - o).dot(ACROSS) < 0.0 else STEEL_DARK.lerp(STEEL_LIGHT, 0.35))
	_draw(img, func(p): return _sd_capsule(p, o - AXIS * 0.08, o + AXIS * 0.01, 0.034), _cyl_shade(o - AXIS * 0.08, o + AXIS * 0.01, 0.034, GOLD_LIGHT, GOLD_DARK, 0.4), 1.2)


## Bâton de mage : long bois noueux, orbe lumineux tenu par une griffe dorée.
static func _staff(img: Image) -> void:
	var a := Vector2(0.16, 0.86)
	var b := Vector2(0.60, 0.42)
	var orb := Vector2(0.69, 0.33)
	_glow(img, orb, 0.34, Color(0.35, 0.60, 1.0), 0.75)
	var ba_px := _px(b) - _px(a)
	_draw(img, func(p):
		var h := clampf((p - _px(a)).dot(ba_px) / ba_px.dot(ba_px), 0.0, 1.0)
		var r := (0.030 + 0.007 * sin(h * 19.0)) * BASE_SIZE
		return (p - _px(a) - ba_px * h).length() - r, _cyl_shade(a, b, 0.036, WOOD_LIGHT, WOOD_DARK, 0.2))
	_collar(img, b, 0.03, 0.05)
	_draw(img, func(p): return _sd_circle(p, orb, 0.105), _sphere_shade(orb, 0.105, Color(0.88, 0.98, 1.0), Color(0.10, 0.22, 0.72)), 1.2)
	_draw(img, func(p): return maxf(absf(_sd_circle(p, orb, 0.135)) - 0.022 * BASE_SIZE, (p - _px(orb)).dot(AXIS) - 0.03 * BASE_SIZE),
		_lit_shade(GOLD_LIGHT, GOLD_DARK), 1.2)
	for side in [-1.0, 1.0]:
		var root: Vector2 = orb + ACROSS * 0.135 * side + AXIS * 0.02
		var tip: Vector2 = orb + ACROSS * 0.095 * side + AXIS * 0.10
		_draw(img, func(p): return _sd_capsule(p, root, tip, 0.018), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_draw(img, func(p): return _sd_circle(p, orb + Vector2(-0.035, -0.04), 0.022), _flat(Color(1, 1, 1, 0.85)), 0.0)


## Baguette : court manche d'ébène cerclé d'or, gemme dans une coupelle, éclat magique.
static func _wand(img: Image) -> void:
	var a := Vector2(0.30, 0.74)
	var b := Vector2(0.56, 0.48)
	var gem_c := b + AXIS * 0.12
	_glow(img, gem_c, 0.30, Color(1.0, 0.45, 0.20), 0.6)
	_draw(img, func(p): return _sd_capsule(p, a, b, 0.024), _cyl_shade(a, b, 0.024, Color(0.48, 0.32, 0.26), Color(0.10, 0.05, 0.04), 0.3))
	for t in [0.30, 0.65]:
		_collar(img, a.lerp(b, t), 0.012, 0.032)
	_draw(img, func(p): return _sd_circle(p, a, 0.035), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	var cup := _xf([Vector2(-0.02, -0.03), Vector2(0.07, -0.085), Vector2(0.04, 0.0), Vector2(0.07, 0.085), Vector2(-0.02, 0.03)], b, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, cup), _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.4))
	_gem(img, gem_c, 0.12, Color(1.0, 0.35, 0.18))
	var star := []
	for i in 8:
		var ang := TAU * i / 8.0
		star.append(gem_c + Vector2(0.075, -0.085) + Vector2(cos(ang), sin(ang)) * (0.075 if i % 2 == 0 else 0.016))
	_draw(img, func(p): return _sd_poly(p, star), _flat(Color(1.0, 0.97, 0.85)), 0.0)


## Arc bandé : branches en arc de cercle, poignée cuir, corde tirée et flèche encochée.
static func _bow(img: Image) -> void:
	var m := Vector2(0.46, 0.54)
	var half := 0.40
	var sag := 0.20
	var radius := (half * half + sag * sag) / (2.0 * sag)
	var center := m + AXIS * (sag - radius)
	var p1 := m - ACROSS * half
	var p2 := m + ACROSS * half
	var apex := m + AXIS * sag
	_draw(img, func(p):
		var rel: Vector2 = p - _px(m)
		var k := clampf(rel.dot(AXIS) / (sag * BASE_SIZE), 0.0, 1.0)
		var ring := absf(p.distance_to(_px(center)) - radius * BASE_SIZE) - lerpf(0.022, 0.036, k) * BASE_SIZE
		return maxf(ring, -rel.dot(AXIS) - 0.5), _lit_shade(WOOD_LIGHT, WOOD_DARK, 0.3))
	_draw(img, func(p): return _sd_box(p, apex, Vector2(0.075, 0.044), PI / 4.0, 0.012), func(q: Vector2, _d: float) -> Color:
		var k := sin((q - apex).dot(ACROSS) * 140.0)
		return LEATHER_LIGHT.lerp(LEATHER_DARK, 0.5 + k * 0.3), 1.2)
	for tip_pt in [p1, p2]:
		var nock: Vector2 = tip_pt
		_draw(img, func(p): return _sd_circle(p, nock, 0.03), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.2)
	var drawn := m - AXIS * 0.10
	var string_col := _flat(Color(0.93, 0.91, 0.82))
	_draw(img, func(p): return minf(_sd_capsule(p, p1, drawn, 0.007), _sd_capsule(p, drawn, p2, 0.007)), string_col, 0.8)
	var tail := m - AXIS * 0.12
	var base := m + AXIS * 0.36
	_draw(img, func(p): return _sd_capsule(p, tail, base, 0.012), _lit_shade(Color(0.90, 0.78, 0.55), Color(0.45, 0.30, 0.14)), 1.0)
	for side in [-1.0, 1.0]:
		var s: float = side
		var feather := [tail + AXIS * 0.01, tail + AXIS * 0.11, tail + AXIS * 0.08 + ACROSS * 0.05 * s, tail - AXIS * 0.02 + ACROSS * 0.05 * s]
		_draw(img, func(p): return _sd_poly(p, feather), _lit_shade(Color(0.95, 0.35, 0.25), Color(0.45, 0.06, 0.05), 0.2), 1.0)
	var head := [base - ACROSS * 0.048, m + AXIS * 0.48, base + ACROSS * 0.048, base + AXIS * 0.02]
	_draw(img, func(p): return _sd_poly(p, head), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.2)


static func _helmet(img: Image) -> void:
	var dome := func(p): return maxf(_sd_circle(p, Vector2(0.5, 0.52), 0.30), p.y - 0.64 * BASE_SIZE)
	var cheeks := [Vector2(0.20, 0.50), Vector2(0.80, 0.50), Vector2(0.76, 0.80), Vector2(0.60, 0.82), Vector2(0.57, 0.62), Vector2(0.43, 0.62), Vector2(0.40, 0.82), Vector2(0.24, 0.80)]
	_draw(img, func(p): return minf(dome.call(p), _sd_poly(p, cheeks)), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.5))
	# Fente de visière et crête.
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.52), Vector2(0.20, 0.028), 0.0, 0.01), _flat(Color(0.03, 0.03, 0.04)), 0.8)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.33), Vector2(0.025, 0.12), 0.0, 0.02), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _armor(img: Image) -> void:
	var body := [Vector2(0.30, 0.20), Vector2(0.42, 0.17), Vector2(0.50, 0.28), Vector2(0.58, 0.17), Vector2(0.70, 0.20), Vector2(0.84, 0.40), Vector2(0.73, 0.47), Vector2(0.71, 0.84), Vector2(0.29, 0.84), Vector2(0.27, 0.47), Vector2(0.16, 0.40)]
	_draw(img, func(p): return _sd_poly(p, body), _lit_shade(Color(0.70, 0.55, 0.36), Color(0.26, 0.16, 0.08), 0.25))
	# Plastron central et ceinture dorés.
	_draw(img, func(p): return _sd_poly(p, [Vector2(0.40, 0.30), Vector2(0.50, 0.40), Vector2(0.60, 0.30), Vector2(0.62, 0.62), Vector2(0.38, 0.62)]), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.68), Vector2(0.21, 0.035)), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _pants(img: Image) -> void:
	var legs := [Vector2(0.30, 0.22), Vector2(0.70, 0.22), Vector2(0.75, 0.85), Vector2(0.56, 0.85), Vector2(0.50, 0.44), Vector2(0.44, 0.85), Vector2(0.25, 0.85)]
	_draw(img, func(p): return _sd_poly(p, legs), _lit_shade(Color(0.60, 0.50, 0.40), Color(0.20, 0.15, 0.10), 0.2))
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.25), Vector2(0.21, 0.04)), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _boots(img: Image) -> void:
	var boot := [Vector2(0.32, 0.18), Vector2(0.58, 0.18), Vector2(0.60, 0.60), Vector2(0.80, 0.68), Vector2(0.84, 0.84), Vector2(0.28, 0.84), Vector2(0.30, 0.60)]
	_draw(img, func(p): return _sd_poly(p, boot), _lit_shade(LEATHER_LIGHT, LEATHER_DARK, 0.25))
	_draw(img, func(p): return _sd_box(p, Vector2(0.45, 0.22), Vector2(0.15, 0.05), 0.0, 0.01), _lit_shade(Color(0.75, 0.60, 0.40), Color(0.35, 0.22, 0.10)), 1.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.56, 0.82), Vector2(0.28, 0.025)), _flat(Color(0.12, 0.08, 0.05)), 0.8)


static func _gloves(img: Image) -> void:
	var sdf := func(p):
		var d := _sd_box(p, Vector2(0.50, 0.58), Vector2(0.16, 0.15), 0.0, 0.06)
		for fx in [0.38, 0.46, 0.54, 0.62]:
			d = minf(d, _sd_capsule(p, Vector2(fx, 0.46), Vector2(fx, 0.22 + absf(fx - 0.5) * 0.3), 0.042))
		d = minf(d, _sd_capsule(p, Vector2(0.36, 0.62), Vector2(0.24, 0.45), 0.045))
		return d
	_draw(img, sdf, _lit_shade(LEATHER_LIGHT, LEATHER_DARK, 0.25))
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.80), Vector2(0.19, 0.07), 0.0, 0.02), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.0)


static func _shield(img: Image) -> void:
	var kite := [Vector2(0.24, 0.20), Vector2(0.76, 0.20), Vector2(0.77, 0.50), Vector2(0.50, 0.87), Vector2(0.23, 0.50)]
	_draw(img, func(p): return _sd_poly(p, kite) - 1.0, _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.3))
	_draw(img, func(p): return _sd_poly(p, kite) + 4.0, _lit_shade(Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28), 0.25), 0.5)
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.5, 0.46), Vector2(0.035, 0.22)), _sd_box(p, Vector2(0.5, 0.40), Vector2(0.17, 0.035))), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _necklace(img: Image, gem: Color) -> void:
	for i in 13:
		var a := lerpf(PI * 1.08, -PI * 0.08, i / 12.0)
		var c := Vector2(0.5, 0.40) + Vector2(cos(a), -sin(a)) * Vector2(0.26, 0.22)
		_draw(img, func(p): return _sd_circle(p, c, 0.028), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_gem(img, Vector2(0.5, 0.68), 0.13, gem)


static func _earring(img: Image, gem: Color) -> void:
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.26), 0.09)) - 0.022 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.5, 0.35), Vector2(0.5, 0.46), 0.02), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_gem(img, Vector2(0.5, 0.63), 0.15, gem)


static func _ring(img: Image, gem: Color) -> void:
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.60), 0.21)) - 0.05 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.5))
	_gem(img, Vector2(0.5, 0.35), 0.11, gem)


## Gemme taillée : losange à facettes + reflet + halo.
static func _gem(img: Image, c: Vector2, r: float, color: Color) -> void:
	_glow(img, c, r * 2.2, color, 0.45)
	var pts := [c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.85, -r * 0.2)]
	_draw(img, func(p): return _sd_poly(p, pts), func(q: Vector2, _d: float) -> Color:
		var rel := q - c
		var facet := 0.35 if rel.x < 0.0 else -0.15
		if rel.y < -r * 0.2:
			facet += 0.25
		return color.lerp(Color.WHITE, clampf(facet, 0.0, 1.0)) if facet > 0.0 else color.darkened(-facet), 1.2)
	_draw(img, func(p): return _sd_circle(p, c + Vector2(-r * 0.3, -r * 0.35), r * 0.16), _flat(Color(1, 1, 1, 0.9)), 0.0)


static func _potion(img: Image, liquid: Color) -> void:
	var glass := Color(0.80, 0.88, 0.95, 0.55)
	var flask := func(p): return minf(_sd_circle(p, Vector2(0.5, 0.63), 0.24), _sd_box(p, Vector2(0.5, 0.35), Vector2(0.075, 0.11), 0.0, 0.02))
	_draw(img, flask, func(q: Vector2, _d: float) -> Color:
		if q.y > 0.50:
			var shade := 1.0 - (q.y - 0.5) * 1.2
			return Color(liquid.r * shade, liquid.g * shade, liquid.b * shade, 1.0).lerp(Color.WHITE, clampf(0.25 - q.distance_to(Vector2(0.40, 0.58)) * 2.0, 0.0, 0.5))
		return glass)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.21), Vector2(0.095, 0.055), 0.0, 0.015), _lit_shade(Color(0.66, 0.46, 0.28), Color(0.30, 0.18, 0.08)), 1.0)
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.37, 0.56), Vector2(0.36, 0.70), 0.025), _flat(Color(1, 1, 1, 0.55)), 0.0)


static func _shots(img: Image, color: Color, core: Color) -> void:
	for c in [Vector2(0.38, 0.62), Vector2(0.62, 0.64), Vector2(0.50, 0.42)]:
		_glow(img, c, 0.30, color, 0.35)
	for c in [Vector2(0.38, 0.62), Vector2(0.62, 0.64), Vector2(0.50, 0.42)]:
		var center: Vector2 = c
		_draw(img, func(p): return _sd_circle(p, center, 0.13), func(q: Vector2, _d: float) -> Color:
			var t := clampf(q.distance_to(center + Vector2(-0.04, -0.04)) / 0.16, 0.0, 1.0)
			return core.lerp(color, t).lerp(color.darkened(0.5), maxf(t - 0.7, 0.0) * 2.0), 1.2)


## Parchemin roulé aux deux bouts, lignes d'écriture et sceau de cire, dans une lueur blanche
## (Scroll of Escape).
static func _scroll(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.48), 0.55, Color(0.85, 0.92, 1.0), 0.55)
	var paper_l := Color(0.97, 0.91, 0.72)
	var paper_d := Color(0.66, 0.52, 0.30)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.5), Vector2(0.20, 0.23), 0.0, 0.01), _lit_shade(paper_l, paper_d, 0.15))
	for y in [0.27, 0.73]:
		var roll_y: float = y
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.26, roll_y), Vector2(0.74, roll_y), 0.055), _lit_shade(paper_l.lightened(0.1), paper_d.darkened(0.2), 0.35), 1.2)
	for i in 4:
		var line_y := 0.38 + 0.065 * i
		var line_end := 0.64 if i % 2 == 0 else 0.58
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.37, line_y), Vector2(line_end, line_y), 0.012), _flat(Color(0.35, 0.24, 0.12, 0.8)), 0.0)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.63, 0.63), 0.075), _lit_shade(Color(0.95, 0.25, 0.20), Color(0.45, 0.04, 0.04), 0.3), 1.0)


static func _key(img: Image) -> void:
	var brass_l := Color(0.95, 0.80, 0.45)
	var brass_d := Color(0.40, 0.28, 0.08)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.32, 0.34), 0.13)) - 0.04 * BASE_SIZE, _lit_shade(brass_l, brass_d, 0.4))
	_draw(img, func(p): return minf(minf(_sd_capsule(p, Vector2(0.42, 0.44), Vector2(0.78, 0.80), 0.04), _sd_box(p, Vector2(0.72, 0.62), Vector2(0.05, 0.025), PI / 4.0)), _sd_box(p, Vector2(0.62, 0.70), Vector2(0.04, 0.022), PI / 4.0)), _lit_shade(brass_l, brass_d, 0.4))


static func _hammer(img: Image) -> void:
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.30, 0.78), Vector2(0.62, 0.38), 0.035), _lit_shade(LEATHER_LIGHT, LEATHER_DARK))
	_draw(img, func(p): return _sd_box(p, Vector2(0.63, 0.34), Vector2(0.20, 0.08), -PI / 4.0 + PI / 2.0 - 0.2, 0.02), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4))


static func _pouch(img: Image) -> void:
	_draw(img, func(p): return minf(_sd_circle(p, Vector2(0.5, 0.62), 0.24), _sd_poly(p, [Vector2(0.38, 0.40), Vector2(0.62, 0.40), Vector2(0.68, 0.24), Vector2(0.32, 0.24)])), _lit_shade(Color(0.72, 0.58, 0.40), Color(0.28, 0.18, 0.08), 0.2))
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.40), Vector2(0.14, 0.03), 0.0, 0.01), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


# --- Compétences -----------------------------------------------------------------

static func _holy_cross(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.70, 0.95, 0.45), 0.8)
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.5, 0.5), Vector2(0.09, 0.30), 0.0, 0.02), _sd_box(p, Vector2(0.5, 0.5), Vector2(0.30, 0.09), 0.0, 0.02)), _lit_shade(Color(1.0, 1.0, 0.88), Color(0.95, 0.80, 0.40), 0.3), 1.2)


static func _buff_arrow(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.5, 0.7, 1.0), 0.6)
	for i in 2:
		var oy := 0.16 * i
		_draw(img, func(p): return _sd_poly(p, [Vector2(0.5, 0.20 + oy), Vector2(0.78, 0.46 + oy), Vector2(0.66, 0.52 + oy), Vector2(0.5, 0.37 + oy), Vector2(0.34, 0.52 + oy), Vector2(0.22, 0.46 + oy)]), _lit_shade(Color(1.0, 0.96, 0.70), Color(0.95, 0.70, 0.20), 0.3), 1.2)


static func _debuff_arrow(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.3, 0.9), 0.6)
	for i in 2:
		var oy := 0.16 * i
		_draw(img, func(p): return _sd_poly(p, [Vector2(0.5, 0.64 + oy), Vector2(0.22, 0.38 + oy), Vector2(0.34, 0.32 + oy), Vector2(0.5, 0.47 + oy), Vector2(0.66, 0.32 + oy), Vector2(0.78, 0.38 + oy)]), _lit_shade(Color(0.95, 0.75, 1.0), Color(0.45, 0.10, 0.60), 0.3), 1.2)


static func _burst(img: Image, color: Color, core: Color, spikes: int) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.6, color, 0.9)
	var pts := []
	for i in spikes * 2:
		var a := TAU * i / (spikes * 2) - PI / 2.0
		var r := 0.36 if i % 2 == 0 else 0.15
		pts.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * r)
	_draw(img, func(p): return _sd_poly(p, pts), func(q: Vector2, _d: float) -> Color:
		return core.lerp(color, clampf(q.distance_to(Vector2(0.5, 0.5)) / 0.36, 0.0, 1.0)), 1.0)


static func _wind_spiral(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(0.4, 0.9, 0.7), 0.5)
	var steps := 90
	for i in steps:
		var t := float(i) / float(steps - 1)
		var a := t * TAU * 1.4
		var c := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * lerpf(0.03, 0.36, t)
		var r := lerpf(0.03, 0.075, t)
		var col := Color(0.70, 1.0, 0.80).lerp(Color(1, 1, 1), t * 0.5)
		_draw(img, func(p): return _sd_circle(p, c, r), _flat(col), 0.0)


# --- Compétences L2 (Human Fighter / Human Mystic) -----------------------------

## Étoile à `spikes` branches centrée en `c` (rayons normalisés), dégradé cœur -> bord.
static func _star(img: Image, c: Vector2, r_out: float, r_in: float, spikes: int, color: Color, core: Color, turn := 0.0) -> void:
	var pts := []
	for i in spikes * 2:
		var a := TAU * i / (spikes * 2) - PI / 2.0 + turn
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	_draw(img, func(p): return _sd_poly(p, pts), func(q: Vector2, _d: float) -> Color:
		return core.lerp(color, clampf(q.distance_to(c) / r_out, 0.0, 1.0)), 0.8)


## Arc de croissant (entaille d'une lame) : anneau de rayon `r` autour de `c`, épaisseur
## maximale `w` au milieu de l'arc [a0, a1] (radians), effilé aux extrémités.
static func _slash_arc(img: Image, c: Vector2, r: float, w: float, a0: float, a1: float, light: Color, dark: Color) -> void:
	var sdf := func(p: Vector2) -> float:
		var rel: Vector2 = p - _px(c)
		var ang := atan2(rel.y, rel.x)
		var t := clampf((ang - a0) / (a1 - a0), 0.0, 1.0)
		var thickness := sin(t * PI) * w * BASE_SIZE
		var d := absf(rel.length() - r * BASE_SIZE) - thickness
		return d if ang >= a0 and ang <= a1 else maxf(d, 4.0)
	var shade := func(q: Vector2, _d: float) -> Color:
		return light.lerp(dark, clampf(q.distance_to(c) / (r * 1.4), 0.0, 1.0))
	_draw(img, sdf, shade, 1.0)


static func _drop_sdf(p: Vector2, c: Vector2, scale: float) -> float:
	var body := _sd_circle(p, c + Vector2(0, 0.10) * scale, 0.20 * scale)
	var tip := _sd_poly(p, [c + Vector2(0, -0.26) * scale, c + Vector2(0.175, 0.02) * scale, c + Vector2(-0.175, 0.02) * scale])
	return minf(body, tip)


static func _heart(img: Image, c: Vector2, scale: float) -> void:
	var sdf := func(p: Vector2) -> float:
		var lobes := minf(_sd_circle(p, c + Vector2(-0.12, -0.08) * scale, 0.15 * scale), _sd_circle(p, c + Vector2(0.12, -0.08) * scale, 0.15 * scale))
		return minf(lobes, _sd_poly(p, [c + Vector2(-0.262, -0.02) * scale, c + Vector2(0.262, -0.02) * scale, c + Vector2(0, 0.30) * scale]))
	_draw(img, sdf, _lit_shade(Color(1.0, 0.62, 0.66), Color(0.62, 0.05, 0.12), 0.4))


static func _small_cross(img: Image, c: Vector2, scale: float) -> void:
	_draw(img, func(p): return minf(_sd_box(p, c, Vector2(0.07, 0.22) * scale, 0.0, 0.015), _sd_box(p, c, Vector2(0.22, 0.07) * scale, 0.0, 0.015)),
		_lit_shade(Color(1.0, 1.0, 0.88), Color(0.95, 0.80, 0.40), 0.3), 1.1)


## Couronne de laurier dorée (passifs) : deux branches de feuilles en arc.
static func _laurel(img: Image) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		for i in 6:
			var a := lerpf(PI * 0.62, PI * 1.12, i / 5.0)
			var leaf_c := Vector2(0.5, 0.50) + Vector2(cos(a) * s, sin(a)) * 0.31
			var leaf_angle := a + PI / 2.0
			if s > 0.0:
				leaf_angle = PI - leaf_angle
			_draw(img, func(p): return _sd_box(p, leaf_c, Vector2(0.075, 0.03), leaf_angle, 0.028), _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.3), 1.0)


static func _skill_power_strike(img: Image) -> void:
	_background(img, Color(0.34, 0.10, 0.03))
	_glow(img, Vector2(0.74, 0.26), 0.42, Color(1.0, 0.55, 0.15), 1.0)
	# Traînées du coup, derrière la lame.
	for k in 3:
		var off := Vector2(0.06, 0.06) * (k + 1)
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.20, 0.52) + off, Vector2(0.48, 0.24) + off, 0.012), _flat(Color(1.0, 0.75, 0.35, 0.55 - k * 0.15)), 0.0)
	_sword(img, Vector2(0.30, 0.70), -PI / 4.0, 0.92)
	_star(img, Vector2(0.76, 0.24), 0.17, 0.06, 6, Color(1.0, 0.55, 0.12), Color(1.0, 0.97, 0.75), 0.2)


static func _skill_mortal_blow(img: Image) -> void:
	_background(img, Color(0.22, 0.03, 0.05))
	_glow(img, Vector2(0.55, 0.45), 0.5, Color(0.9, 0.1, 0.1), 0.7)
	_dagger(img)
	_slash_arc(img, Vector2(0.30, 0.72), 0.52, 0.045, -PI * 0.52, -PI * 0.02, Color(1.0, 0.85, 0.85), Color(0.85, 0.05, 0.08))
	for c in [Vector2(0.78, 0.72), Vector2(0.70, 0.84)]:
		var drop_c: Vector2 = c
		_draw(img, func(p): return _drop_sdf(p, drop_c, 0.28), _lit_shade(Color(1.0, 0.35, 0.35), Color(0.45, 0.0, 0.02), 0.4), 1.0)


static func _skill_relax(img: Image) -> void:
	_background(img, Color(0.05, 0.12, 0.22))
	_glow(img, Vector2(0.42, 0.42), 0.45, Color(0.55, 0.75, 1.0), 0.55)
	_draw(img, func(p): return maxf(_sd_circle(p, Vector2(0.44, 0.46), 0.26), -_sd_circle(p, Vector2(0.56, 0.38), 0.22)),
		_lit_shade(Color(1.0, 0.98, 0.85), Color(0.85, 0.72, 0.35), 0.3))
	for entry in [[Vector2(0.72, 0.26), 0.07], [Vector2(0.80, 0.52), 0.05], [Vector2(0.62, 0.74), 0.045]]:
		var c: Vector2 = entry[0]
		var r: float = entry[1]
		_star(img, c, r, r * 0.35, 4, Color(0.85, 0.92, 1.0), Color.WHITE)


static func _skill_anti_magic(img: Image) -> void:
	_background(img, Color(0.11, 0.07, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.65, 0.45, 1.0), 0.8)
	var ring_shade := _lit_shade(Color(0.92, 0.85, 1.0), Color(0.45, 0.25, 0.85), 0.35)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.5), 0.32)) - 0.025 * BASE_SIZE, ring_shade, 1.0)
	var tri_a := []
	var tri_b := []
	for i in 3:
		tri_a.append(Vector2(0.5, 0.5) + Vector2.from_angle(-PI / 2.0 + TAU * i / 3.0) * 0.30)
		tri_b.append(Vector2(0.5, 0.5) + Vector2.from_angle(PI / 2.0 + TAU * i / 3.0) * 0.30)
	for tri in [tri_a, tri_b]:
		var pts: Array = tri
		_draw(img, func(p): return absf(_sd_poly(p, pts)) - 0.012 * BASE_SIZE, ring_shade, 0.6)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.5), 0.07), _sphere_shade(Vector2(0.5, 0.5), 0.07, Color(1, 1, 1), Color(0.55, 0.35, 1.0)), 1.0)


static func _skill_ice_bolt(img: Image) -> void:
	_background(img, Color(0.04, 0.10, 0.26))
	_glow(img, Vector2(0.62, 0.38), 0.5, Color(0.45, 0.80, 1.0), 0.9)
	var shard := [Vector2(0.84, 0.16), Vector2(0.60, 0.50), Vector2(0.52, 0.46), Vector2(0.20, 0.82), Vector2(0.46, 0.40), Vector2(0.42, 0.34)]
	_draw(img, func(p): return _sd_poly(p, shard), func(q: Vector2, _d: float) -> Color:
		var t := clampf((q.x - q.y + 0.6) * 0.8, 0.0, 1.0)
		return Color(0.55, 0.80, 1.0).lerp(Color(0.95, 1.0, 1.0), t), 1.2)
	for entry in [[Vector2(0.28, 0.30), 0.07], [Vector2(0.76, 0.66), 0.06], [Vector2(0.18, 0.56), 0.04]]:
		var c: Vector2 = entry[0]
		var r: float = entry[1]
		_star(img, c, r, r * 0.3, 6, Color(0.7, 0.9, 1.0), Color.WHITE)


static func _skill_vampiric_touch(img: Image) -> void:
	_background(img, Color(0.14, 0.02, 0.07))
	_glow(img, Vector2(0.5, 0.52), 0.55, Color(0.55, 0.05, 0.35), 0.9)
	# Filets de vie aspirés vers la goutte.
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var from := Vector2(0.5, 0.52) + Vector2.from_angle(a) * 0.42
		var to := Vector2(0.5, 0.52) + Vector2.from_angle(a) * 0.26
		_draw(img, func(p): return _sd_capsule(p, from, to, 0.018), _flat(Color(1.0, 0.45, 0.55, 0.8)), 0.6)
	_draw(img, func(p): return _drop_sdf(p, Vector2(0.5, 0.50), 1.0), _lit_shade(Color(1.0, 0.30, 0.35), Color(0.35, 0.0, 0.05), 0.5))


static func _skill_battle_heal(img: Image) -> void:
	_background(img, Color(0.18, 0.22, 0.05))
	_glow(img, Vector2(0.56, 0.5), 0.55, Color(0.9, 1.0, 0.45), 0.8)
	for k in 3:
		var y := 0.36 + k * 0.14
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.12, y), Vector2(0.34 - k * 0.03, y), 0.016), _flat(Color(1.0, 1.0, 0.75, 0.75)), 0.0)
	_small_cross(img, Vector2(0.60, 0.50), 1.2)


static func _skill_might(img: Image) -> void:
	_background(img, Color(0.32, 0.12, 0.03))
	_glow(img, Vector2(0.5, 0.45), 0.55, Color(1.0, 0.6, 0.2), 0.9)
	_sword(img, Vector2(0.5, 0.80), -PI / 2.0, 0.78)
	for i in 2:
		var oy := 0.13 * i
		_draw(img, func(p): return _sd_poly(p, [Vector2(0.80, 0.30 + oy), Vector2(0.92, 0.42 + oy), Vector2(0.87, 0.45 + oy), Vector2(0.80, 0.38 + oy), Vector2(0.73, 0.45 + oy), Vector2(0.68, 0.42 + oy)]),
			_lit_shade(Color(1.0, 0.96, 0.70), Color(0.95, 0.60, 0.15), 0.3), 1.0)


static func _skill_curse_weakness(img: Image) -> void:
	_background(img, Color(0.20, 0.06, 0.24))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.3, 0.9), 0.7)
	# Épée brisée : deux tronçons décalés de part et d'autre de la cassure.
	_sword(img, Vector2(0.30, 0.72), -PI / 4.0, 0.9, 0.18, 0.05, 0.0)
	var blade_top := [Vector2(0.52, 0.42), Vector2(0.60, 0.36), Vector2(0.80, 0.16), Vector2(0.80, 0.26), Vector2(0.62, 0.44), Vector2(0.55, 0.47)]
	_draw(img, func(p): return _sd_poly(p, blade_top), _lit_shade(STEEL_LIGHT.darkened(0.2), STEEL_DARK, 0.3), 1.2)
	_star(img, Vector2(0.50, 0.47), 0.09, 0.03, 5, Color(0.8, 0.4, 1.0), Color.WHITE)


static func _skill_curse_poison(img: Image) -> void:
	_background(img, Color(0.12, 0.05, 0.16))
	_glow(img, Vector2(0.5, 0.55), 0.55, Color(0.45, 0.95, 0.25), 0.8)
	_draw(img, func(p): return _drop_sdf(p, Vector2(0.46, 0.48), 1.0), _lit_shade(Color(0.75, 1.0, 0.45), Color(0.12, 0.40, 0.05), 0.45))
	for entry in [[Vector2(0.76, 0.30), 0.06], [Vector2(0.72, 0.16), 0.04], [Vector2(0.84, 0.44), 0.035]]:
		var c: Vector2 = entry[0]
		var r: float = entry[1]
		_draw(img, func(p): return _sd_circle(p, c, r), _sphere_shade(c, r, Color(0.85, 1.0, 0.6), Color(0.25, 0.6, 0.1)), 1.0)


## Pénalités de grade (Weapon/Armor Grade Penalty) : l'arme ou l'armure trop haut gradée,
## sous un sceau d'interdiction rouge (anneau barré).
static func _skill_grade_penalty(img: Image, weapon: bool) -> void:
	_background(img, Color(0.24, 0.05, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.30, 0.18), 0.6)
	if weapon:
		_sword(img, Vector2(0.30, 0.70), -PI / 4.0, 0.85)
	else:
		_armor(img)
	var c := Vector2(0.5, 0.5)
	var r := 0.34
	var w := 0.045
	_draw(img, func(p):
		var ring := absf(_sd_circle(p, c, r)) - w * BASE_SIZE
		var bar := maxf(_sd_box(p, c, Vector2(r, w), PI / 4.0), _sd_circle(p, c, r))
		return minf(ring, bar), _lit_shade(Color(1.0, 0.45, 0.35), Color(0.55, 0.06, 0.04), 0.3), 1.2)


static func _skill_cure_poison(img: Image) -> void:
	_background(img, Color(0.05, 0.22, 0.20))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.55, 1.0, 0.85), 0.8)
	_draw(img, func(p): return _drop_sdf(p, Vector2(0.46, 0.50), 0.95), _lit_shade(Color(0.75, 1.0, 0.95), Color(0.10, 0.45, 0.40), 0.45))
	_star(img, Vector2(0.72, 0.28), 0.15, 0.04, 4, Color(0.85, 1.0, 0.95), Color.WHITE, PI / 4.0)


# --- Compétences L2 des 1re/2e professions humaines : motifs partagés ----------

const FIRE_TIP := Color(0.85, 0.12, 0.04)
const FIRE_BASE := Color(1.0, 0.70, 0.18)
const FIRE_CORE := Color(1.0, 0.98, 0.80)
const MANA_LIGHT := Color(0.72, 0.90, 1.0)
const MANA_DARK := Color(0.06, 0.22, 0.70)
const BLOOD_LIGHT := Color(1.0, 0.38, 0.38)
const BLOOD_DARK := Color(0.42, 0.0, 0.03)
const DARK_LIGHT := Color(0.85, 0.60, 1.0)
const DARK_DARK := Color(0.24, 0.04, 0.40)
const BONE_LIGHT := Color(0.98, 0.95, 0.85)
const BONE_DARK := Color(0.50, 0.44, 0.32)
const LEAF_LIGHT := Color(0.70, 1.0, 0.45)
const LEAF_DARK := Color(0.08, 0.36, 0.05)
const WHITE_LIGHT := Color(1.0, 1.0, 1.0)
const WHITE_DARK := Color(0.55, 0.62, 0.75)
## Flamme (repère local : base en bas, trois langues vers le haut).
const FLAME_PTS := [Vector2(-0.17, 0.07), Vector2(-0.21, -0.12), Vector2(-0.09, -0.04), Vector2(-0.04, -0.32),
	Vector2(0.05, -0.12), Vector2(0.12, -0.24), Vector2(0.13, -0.04), Vector2(0.21, -0.15), Vector2(0.17, 0.07)]
## Écu en amande centré sur l'origine (mêmes proportions que _shield).
const KITE_PTS := [Vector2(-0.26, -0.30), Vector2(0.26, -0.30), Vector2(0.27, 0.0), Vector2(0.0, 0.37), Vector2(-0.27, 0.0)]
## Éclair en zigzag (⚡) centré sur l'origine.
const BOLT_PTS := [Vector2(-0.02, -0.34), Vector2(0.14, -0.34), Vector2(0.03, -0.08), Vector2(0.15, -0.08),
	Vector2(-0.10, 0.36), Vector2(-0.01, 0.04), Vector2(-0.14, 0.04)]


## Distance à une ligne brisée de rayon `r` (points normalisés).
static func _sd_polyline(p: Vector2, pts: Array, r: float) -> float:
	var d := INF
	for i in pts.size() - 1:
		d = minf(d, _sd_capsule(p, pts[i], pts[i + 1], r))
	return d


## Arc d'épaisseur constante `w` à bouts arrondis : rayon `r` autour de `c`, centré sur
## l'angle `mid` (radians, sens horaire à l'écran) et couvrant ±`half`.
static func _ring_arc(img: Image, c: Vector2, r: float, w: float, mid: float, half: float, shade: Callable, outline := 1.0) -> void:
	var e0 := c + Vector2.from_angle(mid - half) * r
	var e1 := c + Vector2.from_angle(mid + half) * r
	_draw(img, func(p: Vector2) -> float:
		var rel: Vector2 = p - _px(c)
		var ang := wrapf(atan2(rel.y, rel.x) - mid, -PI, PI)
		if absf(ang) <= half:
			return absf(rel.length() - r * BASE_SIZE) - w * BASE_SIZE
		return minf(p.distance_to(_px(e0)), p.distance_to(_px(e1))) - w * BASE_SIZE, shade, outline)


## Anneau elliptique fin (halo au sol, orbite d'étoiles).
static func _ellipse_ring(img: Image, c: Vector2, rx: float, ry: float, w: float, color: Color) -> void:
	_draw(img, func(p: Vector2) -> float:
		var q: Vector2 = (p - _px(c)) / (Vector2(rx, ry) * BASE_SIZE)
		return absf(q.length() - 1.0) * ry * BASE_SIZE - w * BASE_SIZE, _flat(color), 0.0)


## Flèche circulaire (régénération, recharge) : arc puis pointe, dans le sens horaire.
static func _circ_arrow(img: Image, c: Vector2, r: float, w: float, mid: float, half: float, light: Color, dark: Color) -> void:
	var shade := _lit_shade(light, dark, 0.3)
	_ring_arc(img, c, r, w, mid - 0.12, half - 0.12, shade)
	var end_a := mid + half - 0.22
	var radial := Vector2.from_angle(end_a)
	var tangent := Vector2.from_angle(end_a + PI / 2.0)
	var base := c + radial * r
	var head := [base + radial * w * 2.6, base + tangent * w * 3.6, base - radial * w * 2.6]
	_draw(img, func(p): return _sd_poly(p, head), shade, 1.0)


static func _circ_arrows(img: Image, c: Vector2, r: float, w: float, light: Color, dark: Color) -> void:
	_circ_arrow(img, c, r, w, -PI / 2.0 + 0.15, 1.30, light, dark)
	_circ_arrow(img, c, r, w, PI / 2.0 + 0.15, 1.30, light, dark)


## Flamme peinte : langues orange -> rouge, cœur jaune pâle.
static func _flame(img: Image, c: Vector2, s: float, tip: Color = FIRE_TIP, base: Color = FIRE_BASE, core: Color = FIRE_CORE) -> void:
	var outer := _xf(FLAME_PTS, c, 0.0, s)
	var inner := _xf(FLAME_PTS, c + Vector2(0, 0.07) * s, 0.0, s * 0.55)
	var bc := c + Vector2(0, 0.08) * s
	var bc2 := c + Vector2(0, 0.11) * s
	_draw(img, func(p): return minf(_sd_circle(p, bc, 0.17 * s), _sd_poly(p, outer)), func(q: Vector2, _d: float) -> Color:
		return base.lerp(tip, clampf((bc.y - q.y) / (0.38 * s) + 0.2, 0.0, 1.0)), 1.0)
	_draw(img, func(p): return minf(_sd_circle(p, bc2, 0.095 * s), _sd_poly(p, inner)), func(q: Vector2, _d: float) -> Color:
		return core.lerp(base, clampf((bc2.y - q.y) / (0.22 * s), 0.0, 1.0)), 0.0)


## Crâne : boîte crânienne, mâchoire, orbites (`socket`, lumineuses si claires), nez, dents.
static func _skull(img: Image, c: Vector2, s: float, socket := Color(0.06, 0.02, 0.04), light := BONE_LIGHT, dark := BONE_DARK) -> void:
	var cran := c + Vector2(0, -0.05) * s
	var jaw := c + Vector2(0, 0.15) * s
	_draw(img, func(p): return minf(_sd_circle(p, cran, 0.22 * s), _sd_box(p, jaw, Vector2(0.12, 0.09) * s, 0.0, 0.04 * s)), _lit_shade(light, dark, 0.25))
	for sx in [-1.0, 1.0]:
		var ec: Vector2 = c + Vector2(0.085 * sx, 0.0) * s
		_draw(img, func(p): return _sd_circle(p, ec, 0.064 * s), _sphere_shade(ec, 0.064 * s, socket.lightened(0.4), socket), 0.0)
	var nose := [c + Vector2(0.0, 0.07) * s, c + Vector2(0.035, 0.125) * s, c + Vector2(-0.035, 0.125) * s]
	_draw(img, func(p): return _sd_poly(p, nose), _flat(Color(0.10, 0.05, 0.05)), 0.0)
	for tx in [-0.055, 0.0, 0.055]:
		var t0: Vector2 = c + Vector2(tx, 0.18) * s
		var t1: Vector2 = c + Vector2(tx, 0.235) * s
		_draw(img, func(p): return _sd_capsule(p, t0, t1, 0.009 * s), _flat(Color(0.22, 0.15, 0.10, 0.9)), 0.0)


## Œil en amande : blanc, iris ombré, pupille ronde (ou fendue), reflet.
static func _eye(img: Image, c: Vector2, s: float, iris: Color, slit := false, white := Color(0.98, 0.96, 0.90)) -> void:
	var up := c - Vector2(0, 0.16) * s
	var dn := c + Vector2(0, 0.16) * s
	var almond := func(p: Vector2) -> float: return maxf(_sd_circle(p, up, 0.26 * s), _sd_circle(p, dn, 0.26 * s))
	_draw(img, almond, _lit_shade(white, white.darkened(0.45), 0.15), 1.4)
	_draw(img, func(p): return maxf(_sd_circle(p, c, 0.095 * s), almond.call(p)), _sphere_shade(c, 0.095 * s, iris.lightened(0.45), iris.darkened(0.5)), 0.0)
	if slit:
		_draw(img, func(p): return maxf(_sd_box(p, c, Vector2(0.02, 0.09) * s, 0.0, 0.018 * s), almond.call(p)), _flat(Color(0.02, 0.01, 0.02)), 0.0)
	else:
		_draw(img, func(p): return _sd_circle(p, c, 0.042 * s), _flat(Color(0.02, 0.01, 0.02)), 0.0)
	_draw(img, func(p): return _sd_circle(p, c + Vector2(-0.032, -0.032) * s, 0.022 * s), _flat(Color(1, 1, 1, 0.9)), 0.0)


## Tête de chat (invocations) : oreilles, bajoues, yeux fendus `eye`, truffe rose, moustaches.
static func _cat_head(img: Image, c: Vector2, s: float, fur_l: Color, fur_d: Color, eye: Color, stripes := false) -> void:
	var ears := []
	var inner_ears := []
	for sx in [-1.0, 1.0]:
		ears.append([c + Vector2(0.28 * sx, 0.0) * s, c + Vector2(0.23 * sx, -0.37) * s, c + Vector2(0.02 * sx, -0.18) * s])
		inner_ears.append([c + Vector2(0.22 * sx, -0.07) * s, c + Vector2(0.215 * sx, -0.29) * s, c + Vector2(0.09 * sx, -0.17) * s])
	var head := func(p: Vector2) -> float:
		var d := minf(_sd_circle(p, c + Vector2(0, -0.02) * s, 0.24 * s), _sd_box(p, c + Vector2(0, 0.08) * s, Vector2(0.28, 0.13) * s, 0.0, 0.12 * s))
		return minf(d, minf(_sd_poly(p, ears[0]), _sd_poly(p, ears[1])))
	_draw(img, head, _sphere_shade(c + Vector2(0, -0.04) * s, 0.30 * s, fur_l, fur_d), 1.4)
	for ear in inner_ears:
		var pts: Array = ear
		_draw(img, func(p): return _sd_poly(p, pts), _lit_shade(Color(1.0, 0.68, 0.72), Color(0.55, 0.22, 0.28), 0.1), 0.0)
	if stripes:
		for st in [[Vector2(0, -0.23), Vector2(0, -0.13)], [Vector2(-0.07, -0.21), Vector2(-0.05, -0.13)], [Vector2(0.07, -0.21), Vector2(0.05, -0.13)]]:
			var a: Vector2 = c + (st[0] as Vector2) * s
			var b: Vector2 = c + (st[1] as Vector2) * s
			_draw(img, func(p): return _sd_capsule(p, a, b, 0.017 * s), _flat(Color(fur_d.r, fur_d.g, fur_d.b, 0.85)), 0.0)
	for sx in [-1.0, 1.0]:
		var ec: Vector2 = c + Vector2(0.11 * sx, 0.0) * s
		var eye_sdf := func(p: Vector2) -> float: return maxf(_sd_circle(p, ec - Vector2(0, 0.06) * s, 0.10 * s), _sd_circle(p, ec + Vector2(0, 0.06) * s, 0.10 * s))
		_draw(img, eye_sdf, _sphere_shade(ec, 0.07 * s, eye.lightened(0.5), eye.darkened(0.35)), 1.0)
		_draw(img, func(p): return maxf(_sd_box(p, ec, Vector2(0.013, 0.05) * s, 0.0, 0.012 * s), eye_sdf.call(p)), _flat(Color(0.02, 0.01, 0.02)), 0.0)
		for wy in [[0.12, 0.07], [0.15, 0.17]]:
			var w0: Vector2 = c + Vector2(0.14 * sx, wy[0]) * s
			var w1: Vector2 = c + Vector2(0.40 * sx, wy[1]) * s
			_draw(img, func(p): return _sd_capsule(p, w0, w1, 0.007 * s), _flat(Color(0.95, 0.95, 0.90, 0.8)), 0.0)
	var nose := [c + Vector2(-0.045, 0.085) * s, c + Vector2(0.045, 0.085) * s, c + Vector2(0.0, 0.13) * s]
	_draw(img, func(p): return _sd_poly(p, nose), _lit_shade(Color(1.0, 0.65, 0.70), Color(0.55, 0.20, 0.25), 0.2), 0.8)
	var mouth := [c + Vector2(-0.06, 0.18) * s, c + Vector2(-0.025, 0.185) * s, c + Vector2(0.0, 0.14) * s, c + Vector2(0.025, 0.185) * s, c + Vector2(0.06, 0.18) * s]
	_draw(img, func(p): return _sd_polyline(p, mouth, 0.008 * s), _flat(Color(0.10, 0.05, 0.05, 0.85)), 0.0)


## Cubique du Warlock : cube isométrique de cristal, faces ombrées et arêtes lumineuses.
static func _cube(img: Image, c: Vector2, s: float, color: Color) -> void:
	_glow(img, c, 0.45 * s, color, 0.75)
	var t := c + Vector2(0, -0.22) * s
	var l := c + Vector2(-0.19, -0.11) * s
	var r := c + Vector2(0.19, -0.11) * s
	var bl := c + Vector2(-0.19, 0.11) * s
	var br := c + Vector2(0.19, 0.11) * s
	var b := c + Vector2(0, 0.22) * s
	var faces := [[[t, r, c, l], color.lightened(0.6), color.lightened(0.2)],
		[[l, c, b, bl], color.lightened(0.1), color.darkened(0.3)],
		[[c, r, br, b], color.darkened(0.3), color.darkened(0.65)]]
	for f in faces:
		var pts: Array = f[0]
		var fl: Color = f[1]
		var fd: Color = f[2]
		_draw(img, func(p): return _sd_poly(p, pts), _lit_shade(fl, fd, 0.15), 1.0)
	# Rune lumineuse au centre de chaque face.
	for fc in [c.lerp(t, 0.5), c.lerp(bl, 0.5), c.lerp(br, 0.5)]:
		var rc: Vector2 = fc
		_draw(img, func(p): return _sd_box(p, rc, Vector2(0.035, 0.035) * s, PI / 4.0, 0.0), _flat(color.lightened(0.85)), 0.0)
	for e in [l, r, b]:
		var end: Vector2 = e
		_draw(img, func(p): return _sd_capsule(p, c, end, 0.009 * s), _flat(color.lightened(0.75)), 0.0)


## Éclair en zigzag (⚡) peint.
static func _lightning(img: Image, c: Vector2, s: float, light := Color(1.0, 1.0, 0.85), dark := Color(0.95, 0.70, 0.15), angle := 0.0) -> void:
	var pts := _xf(BOLT_PTS, c, angle, s)
	_draw(img, func(p): return _sd_poly(p, pts), _lit_shade(light, dark, 0.3), 1.2)


## Chaîne de `n` maillons de a à b (alternativement de face et de profil).
static func _chain(img: Image, a: Vector2, b: Vector2, n: int, light: Color, dark: Color) -> void:
	var step := (b - a) / float(n)
	var ang := step.angle()
	var half_len := step.length() * 0.68
	var shade := _lit_shade(light, dark, 0.4)
	for i in n:
		var lc: Vector2 = a + step * (i + 0.5)
		if i % 2 == 0:
			_draw(img, func(p): return absf(_sd_box(p, lc, Vector2(half_len, 0.05), ang, 0.045)) - 0.014 * BASE_SIZE, shade, 1.0)
		else:
			_draw(img, func(p): return _sd_box(p, lc, Vector2(half_len, 0.017), ang, 0.017), shade, 1.0)


## Aile déployée : bras recourbé et rémiges pointues en éventail, des plus longues (vers
## l'extérieur et le haut, au bout de l'aile) aux plus courtes (pendantes, à l'épaule) ;
## `dir` = 1 vers la droite, -1 vers la gauche.
static func _wing(img: Image, c: Vector2, s: float, dir: float, light := WHITE_LIGHT, dark := WHITE_DARK) -> void:
	var elbow := c + Vector2(0.12 * dir, -0.17) * s
	var tip := c + Vector2(0.30 * dir, -0.21) * s
	var shade := _lit_shade(light, dark, 0.2)
	var n := 6
	for i in range(n - 1, -1, -1):
		var t := float(i) / float(n - 1)
		var root := c.lerp(elbow, t * 2.0) if t < 0.5 else elbow.lerp(tip, t * 2.0 - 1.0)
		var ang := lerpf(PI / 2.0 - 0.15, -0.25, t)
		var fdir := Vector2(cos(ang) * dir, sin(ang))
		var perp := Vector2(-fdir.y, fdir.x)
		var flen := lerpf(0.20, 0.36, t) * s
		var w := 0.05 * s
		var feather := [root + perp * w, root + fdir * flen * 0.55 + perp * w * 0.95, root + fdir * flen,
			root + fdir * flen * 0.55 - perp * w * 0.95, root - perp * w]
		_draw(img, func(p): return _sd_poly(p, feather), shade, 1.0)
	_draw(img, func(p): return minf(_sd_capsule(p, c, elbow, 0.05 * s), _sd_capsule(p, elbow, tip, 0.04 * s)), _lit_shade(light, dark.lerp(light, 0.4), 0.3), 1.0)


## « Zzz » du sommeil : trois Z croissants qui montent en diagonale.
static func _zzz(img: Image, c: Vector2, s: float, color: Color) -> void:
	for k in 3:
		var h := (0.05 + 0.025 * k) * s
		var zc := c + Vector2(-0.16 + 0.15 * k, 0.16 - 0.16 * k) * s
		var zpts := [zc + Vector2(-h, -h), zc + Vector2(h, -h), zc + Vector2(-h, h), zc + Vector2(h, h)]
		var w := 0.018 * s * (1.0 + 0.3 * k)
		_draw(img, func(p): return _sd_polyline(p, zpts, w), _lit_shade(color.lightened(0.4), color.darkened(0.3), 0.2), 1.0)


## Étoiles d'étourdissement tournant en ellipse autour de `c`.
static func _dizzy(img: Image, c: Vector2, rx: float, ry: float, color := Color(1.0, 0.85, 0.25)) -> void:
	_ellipse_ring(img, c, rx, ry, 0.010, Color(1.0, 0.95, 0.70, 0.55))
	for k in 4:
		var a := TAU * k / 4.0 + 0.5
		var sc := c + Vector2(cos(a) * rx, sin(a) * ry)
		var r := 0.085 if sin(a) > 0.0 else 0.06
		_star(img, sc, r, r * 0.42, 5, color, Color(1.0, 1.0, 0.9))


## Flèche tirée de `tail` à `tip` (empennage `fletch`).
static func _arrow(img: Image, tail: Vector2, tip: Vector2, s: float, fletch := Color(0.95, 0.35, 0.25)) -> void:
	var dir := (tip - tail).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var neck := tip - dir * 0.09 * s
	_draw(img, func(p): return _sd_capsule(p, tail, neck, 0.013 * s), _lit_shade(Color(0.90, 0.78, 0.55), Color(0.45, 0.30, 0.14)), 1.0)
	for side in [-1.0, 1.0]:
		var sd: float = side
		var feather := [tail + dir * 0.01 * s, tail + dir * 0.12 * s, tail + (dir * 0.09 + perp * 0.05 * sd) * s, tail + (dir * -0.02 + perp * 0.05 * sd) * s]
		_draw(img, func(p): return _sd_poly(p, feather), _lit_shade(fletch.lightened(0.2), fletch.darkened(0.6), 0.2), 1.0)
	var head := [neck - dir * 0.02 * s + perp * 0.05 * s, tip, neck - dir * 0.02 * s - perp * 0.05 * s, neck + dir * 0.015 * s]
	_draw(img, func(p): return _sd_poly(p, head), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.2)


## Écu en amande à bordure dorée et champ `field_l`/`field_d` (sans emblème).
static func _kite(img: Image, c: Vector2, s: float, field_l: Color, field_d: Color) -> void:
	var pts := _xf(KITE_PTS, c, 0.0, s)
	_draw(img, func(p): return _sd_poly(p, pts) - 1.0, _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.3))
	_draw(img, func(p): return _sd_poly(p, pts) + 4.0 * s, _lit_shade(field_l, field_d, 0.25), 0.5)


## Viseur : anneau, quatre graduations et point central.
static func _crosshair(img: Image, c: Vector2, r: float, color: Color) -> void:
	var shade := _lit_shade(color.lightened(0.4), color.darkened(0.4), 0.3)
	_draw(img, func(p: Vector2) -> float:
		var d := absf(_sd_circle(p, c, r)) - 0.022 * BASE_SIZE
		for k in 4:
			var dir := Vector2.from_angle(k * PI / 2.0)
			d = minf(d, _sd_capsule(p, c + dir * r * 0.55, c + dir * r * 1.3, 0.02))
		return d, shade, 1.0)
	_draw(img, func(p): return _sd_circle(p, c, 0.028), shade, 1.0)


## Empreinte de patte : coussinet et quatre doigts.
static func _paw(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	_draw(img, func(p: Vector2) -> float:
		var d := _sd_box(p, c + Vector2(0, 0.10) * s, Vector2(0.12, 0.09) * s, 0.0, 0.085 * s)
		for toe in [Vector2(-0.18, -0.07), Vector2(-0.065, -0.15), Vector2(0.065, -0.15), Vector2(0.18, -0.07)]:
			d = minf(d, _sd_circle(p, c + (toe as Vector2) * s, 0.055 * s))
		return d, _lit_shade(light, dark, 0.2), 1.0)


## Médaillon « serviteur » (patte) en bas à droite des compétences ciblant l'invocation.
static func _servitor_badge(img: Image) -> void:
	var c := Vector2(0.77, 0.77)
	_draw(img, func(p): return _sd_circle(p, c, 0.175), _sphere_shade(c, 0.175, Color(0.55, 0.42, 0.28), Color(0.12, 0.07, 0.03)), 1.2)
	_draw(img, func(p): return absf(_sd_circle(p, c, 0.165)) - 0.012 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK), 0.0)
	_paw(img, c + Vector2(0, 0.01), 0.55, Color(1.0, 0.95, 0.80), Color(0.70, 0.55, 0.35))


## Ânkh doré (résurrection).
static func _ankh(img: Image, c: Vector2, s: float) -> void:
	var loop_c := c + Vector2(0, -0.19) * s
	var bar_c := c + Vector2(0, -0.03) * s
	var stem := [c + Vector2(-0.035, -0.06) * s, c + Vector2(0.035, -0.06) * s, c + Vector2(0.075, 0.34) * s, c + Vector2(-0.075, 0.34) * s]
	_draw(img, func(p: Vector2) -> float:
		var ring := absf(_sd_box(p, loop_c, Vector2(0.09, 0.125) * s, 0.0, 0.085 * s)) - 0.036 * s * BASE_SIZE
		var bar := _sd_box(p, bar_c, Vector2(0.21, 0.042) * s, 0.0, 0.015 * s)
		return minf(minf(ring, bar), _sd_poly(p, stem)), _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.4), 1.2)


## Cercle magique : double anneau, hexagramme et runes.
static func _magic_circle(img: Image, c: Vector2, r: float, light: Color, dark: Color) -> void:
	var shade := _lit_shade(light, dark, 0.3)
	_draw(img, func(p): return minf(absf(_sd_circle(p, c, r)) - 0.018 * BASE_SIZE, absf(_sd_circle(p, c, r * 0.80)) - 0.010 * BASE_SIZE), shade, 0.8)
	var tri_a := []
	var tri_b := []
	for i in 3:
		tri_a.append(c + Vector2.from_angle(-PI / 2.0 + TAU * i / 3.0) * r * 0.78)
		tri_b.append(c + Vector2.from_angle(PI / 2.0 + TAU * i / 3.0) * r * 0.78)
	_draw(img, func(p): return minf(absf(_sd_poly(p, tri_a)), absf(_sd_poly(p, tri_b))) - 0.009 * BASE_SIZE, shade, 0.6)
	for i in 6:
		var dc := c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r * 0.90
		_draw(img, func(p): return _sd_circle(p, dc, 0.017), _flat(light), 0.0)


## Croche (musique du Requiem).
static func _note(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	var stem_top := c + Vector2(0.075, -0.34) * s
	_draw(img, func(p: Vector2) -> float:
		var head := _sd_box(p, c, Vector2(0.095, 0.062) * s, -0.4, 0.058 * s)
		var stem := _sd_capsule(p, c + Vector2(0.075, -0.02) * s, stem_top, 0.02 * s)
		var flag := _sd_capsule(p, stem_top, c + Vector2(0.20, -0.13) * s, 0.026 * s)
		return minf(head, minf(stem, flag)), _lit_shade(light, dark, 0.3), 1.0)


## Nuage bombé.
static func _cloud(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	_draw(img, func(p: Vector2) -> float:
		var d := minf(_sd_circle(p, c + Vector2(-0.16, 0.03) * s, 0.12 * s), _sd_circle(p, c + Vector2(0.0, -0.06) * s, 0.16 * s))
		d = minf(d, _sd_circle(p, c + Vector2(0.17, 0.02) * s, 0.12 * s))
		return minf(d, _sd_box(p, c + Vector2(0.0, 0.08) * s, Vector2(0.27, 0.07) * s, 0.0, 0.07 * s)), _lit_shade(light, dark, 0.2), 1.2)


## Silhouette en buste (tête + épaules).
static func _silhouette(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	var cut := (c.y + 0.32 * s) * BASE_SIZE
	_draw(img, func(p: Vector2) -> float:
		var body := maxf(_sd_box(p, c + Vector2(0, 0.20) * s, Vector2(0.25, 0.18) * s, 0.0, 0.14 * s), p.y - cut)
		return minf(_sd_circle(p, c + Vector2(0, -0.17) * s, 0.12 * s), body), _lit_shade(light, dark, 0.15), 1.2)


## Petite flèche pleine (vers le haut ; `angle` la fait tourner).
static func _up_arrow(img: Image, c: Vector2, s: float, light: Color, dark: Color, angle := 0.0) -> void:
	var pts := _xf([Vector2(0, -0.15), Vector2(0.13, 0.0), Vector2(0.05, 0.0), Vector2(0.05, 0.14), Vector2(-0.05, 0.14), Vector2(-0.05, 0.0), Vector2(-0.13, 0.0)], c, angle, s)
	_draw(img, func(p): return _sd_poly(p, pts), _lit_shade(light, dark, 0.3), 1.0)


## Goutte teintée (sang, mana, poison...).
static func _tinted_drop(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	_draw(img, func(p): return _drop_sdf(p, c, s), _lit_shade(light, dark, 0.45))


## Croix pleine teintée (variante colorée de _small_cross).
static func _plus(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	_draw(img, func(p): return minf(_sd_box(p, c, Vector2(0.07, 0.22) * s, 0.0, 0.015), _sd_box(p, c, Vector2(0.22, 0.07) * s, 0.0, 0.015)),
		_lit_shade(light, dark, 0.3), 1.1)


## Entaille effilée de a à b (épaisseur maximale `w` au milieu).
static func _cut(img: Image, a: Vector2, b: Vector2, w: float, light: Color, dark: Color) -> void:
	_draw(img, func(p: Vector2) -> float:
		var pa: Vector2 = p - _px(a)
		var ba: Vector2 = _px(b) - _px(a)
		var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
		return (pa - ba * h).length() - sin(h * PI) * w * BASE_SIZE, _lit_shade(light, dark, 0.3), 1.0)


## Trois griffures parallèles.
static func _claw_marks(img: Image, light: Color, dark: Color) -> void:
	for k in 3:
		_cut(img, Vector2(0.44 + 0.15 * k, 0.14), Vector2(0.16 + 0.15 * k, 0.80), 0.05, light, dark)


## Traits de vitesse partant de `c` dans la direction `dir`.
static func _speed_lines(img: Image, c: Vector2, s: float, color: Color, dir := Vector2.LEFT) -> void:
	var perp := Vector2(-dir.y, dir.x)
	for k in 3:
		var a := c + perp * (k - 1) * 0.12 * s
		var b := a + dir * (0.26 - 0.07 * absi(k - 1)) * s
		_draw(img, func(p): return _sd_capsule(p, a, b, 0.017 * s), _flat(color), 0.0)


## Spirale de petits disques du centre vers l'extérieur (`dir` = -1 : sens inverse).
static func _spiral(img: Image, c: Vector2, r_out: float, turns: float, w: float, inner: Color, outer: Color, dir := 1.0) -> void:
	var steps := 70
	for i in steps:
		var t := float(i) / float(steps - 1)
		var a := t * TAU * turns * dir
		var pc := c + Vector2(cos(a), sin(a)) * lerpf(0.03, r_out, t)
		var r := lerpf(w * 0.4, w, t)
		_draw(img, func(p): return _sd_circle(p, pc, r), _flat(inner.lerp(outer, t)), 0.0)


## Croissant de lune.
static func _crescent(img: Image, c: Vector2, r: float, light: Color, dark: Color) -> void:
	_draw(img, func(p): return maxf(_sd_circle(p, c, r), -_sd_circle(p, c + Vector2(0.45, -0.30) * r, r * 0.85)), _lit_shade(light, dark, 0.3))


## Cuirasse (variantes des maîtrises d'armure) : corps, plastron et ceinture.
static func _cuirass(img: Image, body_l: Color, body_d: Color, plate_l: Color, plate_d: Color, belt_l: Color, belt_d: Color) -> void:
	var body := [Vector2(0.30, 0.20), Vector2(0.42, 0.17), Vector2(0.50, 0.28), Vector2(0.58, 0.17), Vector2(0.70, 0.20), Vector2(0.84, 0.40), Vector2(0.73, 0.47), Vector2(0.71, 0.84), Vector2(0.29, 0.84), Vector2(0.27, 0.47), Vector2(0.16, 0.40)]
	_draw(img, func(p): return _sd_poly(p, body), _lit_shade(body_l, body_d, 0.25))
	_draw(img, func(p): return _sd_poly(p, [Vector2(0.40, 0.30), Vector2(0.50, 0.40), Vector2(0.60, 0.30), Vector2(0.62, 0.62), Vector2(0.38, 0.62)]), _lit_shade(plate_l, plate_d, 0.4), 1.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.68), Vector2(0.21, 0.035)), _lit_shade(belt_l, belt_d), 1.0)


## Robe de mage : capuche, manches larges, liseré et ceinture dorés.
static func _robe(img: Image, cloth_l: Color, cloth_d: Color) -> void:
	var robe := [Vector2(0.38, 0.15), Vector2(0.62, 0.15), Vector2(0.70, 0.26), Vector2(0.88, 0.52), Vector2(0.76, 0.58), Vector2(0.69, 0.46),
		Vector2(0.77, 0.88), Vector2(0.23, 0.88), Vector2(0.31, 0.46), Vector2(0.24, 0.58), Vector2(0.12, 0.52), Vector2(0.30, 0.26)]
	_draw(img, func(p): return _sd_poly(p, robe), _lit_shade(cloth_l, cloth_d, 0.25))
	var gold := _lit_shade(GOLD_LIGHT, GOLD_DARK)
	_draw(img, func(p): return minf(_sd_polyline(p, [Vector2(0.40, 0.17), Vector2(0.5, 0.33), Vector2(0.60, 0.17)], 0.022), _sd_capsule(p, Vector2(0.5, 0.33), Vector2(0.5, 0.86), 0.018)), gold, 1.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.50), Vector2(0.17, 0.03)), gold, 1.0)


## Grimoire ouvert : pages crème, couverture rouge, lignes d'écriture.
static func _book(img: Image, c: Vector2, s: float) -> void:
	var cover := _xf([Vector2(-0.38, -0.14), Vector2(0, -0.08), Vector2(0.38, -0.14), Vector2(0.38, 0.25), Vector2(0, 0.31), Vector2(-0.38, 0.25)], c, 0.0, s)
	_draw(img, func(p): return _sd_poly(p, cover), _lit_shade(Color(0.75, 0.20, 0.15), Color(0.25, 0.03, 0.03), 0.2))
	var paper := _lit_shade(Color(1.0, 0.97, 0.85), Color(0.75, 0.62, 0.40), 0.15)
	for sx in [-1.0, 1.0]:
		var page := _xf([Vector2(-0.34 * sx, -0.18), Vector2(-0.01 * sx, -0.12), Vector2(-0.01 * sx, 0.25), Vector2(-0.34 * sx, 0.19)], c, 0.0, s)
		_draw(img, func(p): return _sd_poly(p, page), paper, 1.0)
		for k in 4:
			var y := -0.08 + 0.075 * k
			var a: Vector2 = c + Vector2(-0.29 * sx, y - 0.006) * s
			var b: Vector2 = c + Vector2(-0.06 * sx, y + 0.032) * s
			_draw(img, func(p): return _sd_capsule(p, a, b, 0.008 * s), _flat(Color(0.35, 0.24, 0.12, 0.75)), 0.0)


## Sablier : montants de bois, verre, sable `sand` qui s'écoule.
static func _hourglass(img: Image, c: Vector2, s: float, sand: Color) -> void:
	var glass := _xf([Vector2(-0.18, -0.26), Vector2(0.18, -0.26), Vector2(0.03, 0.0), Vector2(0.18, 0.26), Vector2(-0.18, 0.26), Vector2(-0.03, 0.0)], c, 0.0, s)
	_draw(img, func(p): return _sd_poly(p, glass), _flat(Color(0.80, 0.90, 1.0, 0.35)), 1.0)
	var top := _xf([Vector2(-0.12, -0.12), Vector2(0.12, -0.12), Vector2(0.02, -0.015), Vector2(-0.02, -0.015)], c, 0.0, s)
	var pile := _xf([Vector2(-0.16, 0.245), Vector2(0.16, 0.245), Vector2(0.0, 0.10)], c, 0.0, s)
	var sand_shade := _lit_shade(sand.lightened(0.3), sand.darkened(0.4), 0.2)
	_draw(img, func(p): return minf(minf(_sd_poly(p, top), _sd_poly(p, pile)), _sd_capsule(p, c, c + Vector2(0, 0.2) * s, 0.01 * s)), sand_shade, 0.0)
	var wood := _lit_shade(WOOD_LIGHT, WOOD_DARK, 0.3)
	for sx in [-1.0, 1.0]:
		var a: Vector2 = c + Vector2(0.21 * sx, -0.28) * s
		var b: Vector2 = c + Vector2(0.21 * sx, 0.28) * s
		_draw(img, func(p): return _sd_capsule(p, a, b, 0.018 * s), wood, 1.0)
	for sy in [-1.0, 1.0]:
		var cc: Vector2 = c + Vector2(0, 0.30 * sy) * s
		_draw(img, func(p): return _sd_box(p, cc, Vector2(0.26, 0.04) * s, 0.0, 0.015 * s), wood, 1.0)


## Marque de colère (💢) : quatre arcs rouges bombés vers le centre.
static func _anger_mark(img: Image, c: Vector2, s: float, light: Color, dark: Color) -> void:
	var shade := _lit_shade(light, dark, 0.3)
	for k in 4:
		var diag := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
		_ring_arc(img, c + diag * 0.20 * s, 0.10 * s, 0.028 * s, diag.angle() + PI, 0.62, shade)


## Botte ailée (vitesse de déplacement).
static func _winged_boot(img: Image) -> void:
	_boots(img)
	_wing(img, Vector2(0.36, 0.32), 0.50, -1.0)


# --- Compétences L2 : Warrior / Gladiator / Warlord ------------------------------

## Detect Insect/Animal Weakness : scarabée ou empreinte sous un viseur rouge.
static func _skill_detect_weakness(img: Image, animal: bool) -> void:
	if animal:
		_background(img, Color(0.22, 0.13, 0.05))
		_glow(img, Vector2(0.5, 0.52), 0.5, Color(1.0, 0.70, 0.35), 0.6)
		_paw(img, Vector2(0.5, 0.54), 1.15, Color(0.85, 0.62, 0.38), Color(0.30, 0.16, 0.06))
	else:
		_background(img, Color(0.10, 0.18, 0.06))
		_glow(img, Vector2(0.5, 0.52), 0.5, Color(0.75, 1.0, 0.35), 0.6)
		var leg := _flat(Color(0.14, 0.10, 0.04))
		for sx in [-1.0, 1.0]:
			for k in 3:
				var a := Vector2(0.5 + 0.08 * sx, 0.46 + 0.09 * k)
				var b := Vector2(0.5 + 0.25 * sx, 0.38 + 0.15 * k)
				_draw(img, func(p): return _sd_capsule(p, a, b, 0.016), leg, 0.6)
			var ant := [Vector2(0.5 + 0.03 * sx, 0.30), Vector2(0.5 + 0.10 * sx, 0.20), Vector2(0.5 + 0.17 * sx, 0.18)]
			_draw(img, func(p): return _sd_polyline(p, ant, 0.011), leg, 0.5)
		_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.33), 0.075), _lit_shade(Color(0.45, 0.40, 0.20), Color(0.08, 0.06, 0.02)), 1.0)
		_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.55), Vector2(0.15, 0.19), 0.0, 0.14), _lit_shade(Color(0.60, 0.80, 0.30), Color(0.08, 0.22, 0.04), 0.4))
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.5, 0.40), Vector2(0.5, 0.73), 0.008), _flat(Color(0.05, 0.08, 0.02)), 0.0)
	_crosshair(img, Vector2(0.5, 0.52), 0.32, Color(1.0, 0.25, 0.18))


## War Cry : cor de guerre d'ivoire cerclé d'or et ondes sonores.
static func _skill_war_cry(img: Image) -> void:
	_background(img, Color(0.30, 0.08, 0.04))
	_glow(img, Vector2(0.62, 0.40), 0.5, Color(1.0, 0.5, 0.15), 0.8)
	var p0 := Vector2(0.16, 0.80)
	var p1 := Vector2(0.24, 0.40)
	var p2 := Vector2(0.56, 0.36)
	var centers := []
	var radii := []
	for i in 24:
		var t := float(i) / 23.0
		centers.append(p0 * (1.0 - t) * (1.0 - t) + p1 * 2.0 * (1.0 - t) * t + p2 * t * t)
		radii.append(lerpf(0.025, 0.115, t * t))
	_draw(img, func(p: Vector2) -> float:
		var d := INF
		for i in centers.size():
			d = minf(d, _sd_circle(p, centers[i], radii[i]))
		return d, _lit_shade(Color(1.0, 0.95, 0.80), Color(0.55, 0.40, 0.22), 0.3))
	for i in [9, 16]:
		var bc: Vector2 = centers[i]
		var br: float = radii[i]
		var tangent: Vector2 = (centers[i + 1] as Vector2) - (centers[i - 1] as Vector2)
		_draw(img, func(p): return _sd_box(p, bc, Vector2(0.018, br + 0.01), tangent.angle(), 0.008), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	var mouth_dir := (p2 - p1).angle()
	_draw(img, func(p): return _sd_box(p, p2, Vector2(0.026, 0.13), mouth_dir, 0.02), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.2)
	_draw(img, func(p): return _sd_box(p, p2 + Vector2(0.01, 0.0), Vector2(0.012, 0.095), mouth_dir, 0.01), _flat(Color(0.18, 0.08, 0.03)), 0.0)
	var wave := _flat(Color(1.0, 0.85, 0.55, 0.9))
	for k in 2:
		_ring_arc(img, p2, 0.19 + 0.09 * k, 0.018, mouth_dir, 0.55, wave, 0.0)


static func _skill_stun_attack(img: Image) -> void:
	_background(img, Color(0.26, 0.16, 0.05))
	_glow(img, Vector2(0.62, 0.38), 0.45, Color(1.0, 0.85, 0.4), 0.8)
	_mace(img)
	_dizzy(img, Vector2(0.50, 0.17), 0.30, 0.08)


## Battle Roar : cœur (PV max) entouré d'ondes de rugissement.
static func _skill_battle_roar(img: Image) -> void:
	_background(img, Color(0.30, 0.06, 0.05))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.35, 0.25), 0.8)
	var wave := _flat(Color(1.0, 0.78, 0.50, 0.85))
	for side in [0.0, PI]:
		for k in 2:
			_ring_arc(img, Vector2(0.5, 0.52), 0.32 + 0.09 * k, 0.018, side, 0.45, wave, 0.0)
	_heart(img, Vector2(0.5, 0.50), 0.92)
	_small_cross(img, Vector2(0.5, 0.47), 0.5)


## Vital Force : lune du repos, cœur et goutte de mana.
static func _skill_vital_force(img: Image) -> void:
	_background(img, Color(0.08, 0.20, 0.10))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.55, 1.0, 0.5), 0.6)
	_crescent(img, Vector2(0.34, 0.34), 0.20, Color(1.0, 0.98, 0.80), Color(0.85, 0.70, 0.30))
	_heart(img, Vector2(0.60, 0.62), 0.72)
	_tinted_drop(img, Vector2(0.78, 0.26), 0.40, MANA_LIGHT, MANA_DARK)


static func _skill_boost_hp(img: Image) -> void:
	_background(img, Color(0.26, 0.05, 0.07))
	_glow(img, Vector2(0.45, 0.55), 0.55, Color(1.0, 0.40, 0.40), 0.7)
	_heart(img, Vector2(0.44, 0.56), 1.0)
	_up_arrow(img, Vector2(0.77, 0.30), 1.0, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


static func _skill_fast_hp_recovery(img: Image) -> void:
	_background(img, Color(0.10, 0.22, 0.08))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.70, 1.0, 0.50), 0.6)
	_circ_arrows(img, Vector2(0.5, 0.5), 0.34, 0.032, Color(0.85, 1.0, 0.60), Color(0.20, 0.55, 0.10))
	_heart(img, Vector2(0.5, 0.50), 0.66)


static func _skill_polearm_mastery(img: Image) -> void:
	_background(img, Color(0.12, 0.16, 0.18))
	_glow(img, Vector2(0.55, 0.45), 0.55, Color(1.0, 0.80, 0.35), 0.55)
	_spear(img)


static func _skill_light_armor_mastery(img: Image) -> void:
	_background(img, Color(0.10, 0.18, 0.08))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.80, 1.0, 0.45), 0.45)
	_cuirass(img, LEATHER_LIGHT, LEATHER_DARK, Color(0.85, 0.66, 0.44), Color(0.36, 0.22, 0.10), Color(0.85, 0.60, 0.30), Color(0.35, 0.20, 0.06))


static func _skill_heavy_armor_mastery(img: Image) -> void:
	_background(img, Color(0.12, 0.14, 0.22))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.70, 0.80, 1.0), 0.45)
	_cuirass(img, Color(0.78, 0.82, 0.90), Color(0.22, 0.26, 0.34), STEEL_LIGHT, STEEL_DARK, GOLD_LIGHT, GOLD_DARK)
	for c in [Vector2(0.34, 0.26), Vector2(0.66, 0.26), Vector2(0.25, 0.41), Vector2(0.75, 0.41)]:
		var rc: Vector2 = c
		_draw(img, func(p): return _sd_circle(p, rc, 0.02), _lit_shade(GOLD_LIGHT, GOLD_DARK), 0.8)


static func _skill_robe_mastery(img: Image) -> void:
	_background(img, Color(0.14, 0.08, 0.24))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.70, 0.55, 1.0), 0.45)
	_robe(img, Color(0.45, 0.55, 0.95), Color(0.08, 0.10, 0.35))


static func _skill_wild_sweep(img: Image) -> void:
	_background(img, Color(0.08, 0.16, 0.20))
	_glow(img, Vector2(0.5, 0.32), 0.5, Color(0.6, 0.9, 1.0), 0.7)
	_slash_arc(img, Vector2(0.5, 0.88), 0.62, 0.065, -PI * 0.80, -PI * 0.20, Color(1, 1, 1), Color(0.30, 0.65, 1.0))
	_spear(img)


## Power Smash : épée abattue pointe en bas sur un éclat d'impact.
static func _skill_power_smash(img: Image) -> void:
	_background(img, Color(0.30, 0.12, 0.04))
	_glow(img, Vector2(0.5, 0.78), 0.45, Color(1.0, 0.6, 0.2), 0.9)
	_star(img, Vector2(0.5, 0.80), 0.32, 0.09, 7, Color(1.0, 0.50, 0.10), Color(1.0, 0.97, 0.75))
	_sword(img, Vector2(0.5, 0.26), PI / 2.0, 0.80)


## Accuracy : cible et flèche plantée au centre.
static func _skill_accuracy(img: Image) -> void:
	_background(img, Color(0.08, 0.12, 0.26))
	_glow(img, Vector2(0.48, 0.54), 0.5, Color(0.6, 0.8, 1.0), 0.5)
	var c := Vector2(0.46, 0.56)
	var rings := [[0.30, Color(0.95, 0.25, 0.20), Color(0.45, 0.04, 0.04)], [0.22, Color(1.0, 0.97, 0.90), Color(0.70, 0.65, 0.55)],
		[0.14, Color(0.95, 0.25, 0.20), Color(0.45, 0.04, 0.04)], [0.06, GOLD_LIGHT, GOLD_DARK]]
	for ring in rings:
		var r: float = ring[0]
		var light: Color = ring[1]
		var dark: Color = ring[2]
		_draw(img, func(p): return _sd_circle(p, c, r), _lit_shade(light, dark, 0.2), 1.0)
	_arrow(img, Vector2(0.88, 0.14), Vector2(0.49, 0.53), 1.0)


static func _skill_sword_blunt_mastery(img: Image) -> void:
	_background(img, Color(0.18, 0.13, 0.20))
	_glow(img, Vector2(0.5, 0.45), 0.55, Color(1.0, 0.80, 0.35), 0.55)
	_mace(img)
	_sword(img, Vector2(0.68, 0.68), -3.0 * PI / 4.0, 0.82)


## Lionheart : cœur dans une crinière de lion dorée.
static func _skill_lionheart(img: Image) -> void:
	_background(img, Color(0.30, 0.18, 0.03))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.70, 0.20), 0.9)
	_star(img, Vector2(0.5, 0.5), 0.42, 0.27, 14, Color(0.80, 0.40, 0.06), Color(1.0, 0.86, 0.38))
	_heart(img, Vector2(0.5, 0.50), 0.82)


## Vicious Stance : épée dans une aura cramoisie hérissée.
static func _skill_vicious_stance(img: Image) -> void:
	_background(img, Color(0.20, 0.02, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(1.0, 0.10, 0.10), 1.0)
	_star(img, Vector2(0.5, 0.5), 0.44, 0.15, 9, Color(0.55, 0.0, 0.05), Color(1.0, 0.35, 0.25))
	_sword(img, Vector2(0.30, 0.70), -PI / 4.0, 0.92)


static func _skill_triple_slash(img: Image) -> void:
	_background(img, Color(0.26, 0.05, 0.05))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.40, 0.30), 0.7)
	for k in 3:
		_slash_arc(img, Vector2(0.06, 0.94), 0.44 + 0.17 * k, 0.045, -PI * 0.47, -PI * 0.03, Color(1, 1, 1), Color(0.95, 0.20, 0.15))


## Dual Weapon Mastery : deux épées dressées en V.
static func _skill_dual_weapon_mastery(img: Image) -> void:
	_background(img, Color(0.16, 0.10, 0.24))
	_glow(img, Vector2(0.5, 0.42), 0.55, Color(1.0, 0.80, 0.35), 0.55)
	_sword(img, Vector2(0.38, 0.72), -PI / 2.0 - 0.24, 0.80)
	_sword(img, Vector2(0.62, 0.72), -PI / 2.0 + 0.24, 0.80)


## Fatal Strike : épée qui fend un écu (garde brisée).
static func _skill_fatal_strike(img: Image) -> void:
	_background(img, Color(0.22, 0.06, 0.03))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.45, 0.15), 0.7)
	_kite(img, Vector2(0.5, 0.50), 0.95, Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28))
	var crack := [Vector2(0.40, 0.23), Vector2(0.50, 0.37), Vector2(0.42, 0.50), Vector2(0.55, 0.63), Vector2(0.49, 0.82)]
	_draw(img, func(p): return _sd_polyline(p, crack, 0.014), _flat(Color(0.04, 0.02, 0.02)), 0.6)
	_sword(img, Vector2(0.22, 0.78), -PI / 4.0, 0.95)
	_star(img, Vector2(0.50, 0.50), 0.13, 0.04, 6, Color(1.0, 0.75, 0.3), Color(1, 1, 0.9))


static func _skill_hammer_crush(img: Image) -> void:
	_background(img, Color(0.20, 0.12, 0.08))
	_glow(img, Vector2(0.66, 0.36), 0.5, Color(1.0, 0.6, 0.25), 0.9)
	_star(img, Vector2(0.70, 0.32), 0.30, 0.10, 8, Color(1.0, 0.50, 0.10), Color(1.0, 0.95, 0.70))
	_warhammer(img)


## Whirlwind : lance au centre d'un cercle de taillades.
static func _skill_whirlwind(img: Image) -> void:
	_background(img, Color(0.06, 0.18, 0.18))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.5, 1.0, 0.9), 0.6)
	for k in 3:
		var a0 := -PI + 0.15 + k * TAU / 3.0
		_slash_arc(img, Vector2(0.5, 0.5), 0.36, 0.05, a0, a0 + TAU / 3.0 - 0.3, Color(1, 1, 1), Color(0.2, 0.75, 0.70))
	_spear(img)


static func _skill_thunder_storm(img: Image) -> void:
	_background(img, Color(0.10, 0.08, 0.24))
	_glow(img, Vector2(0.5, 0.4), 0.55, Color(0.6, 0.6, 1.0), 0.8)
	_spear(img)
	_lightning(img, Vector2(0.28, 0.34), 0.72)
	_lightning(img, Vector2(0.78, 0.68), 0.50)


static func _skill_focus_attack(img: Image) -> void:
	_background(img, Color(0.08, 0.14, 0.20))
	_glow(img, Vector2(0.74, 0.26), 0.45, Color(1.0, 0.85, 0.4), 0.8)
	_spear(img)
	_crosshair(img, Vector2(0.74, 0.26), 0.17, Color(1.0, 0.30, 0.20))


static func _skill_power_crush(img: Image) -> void:
	_background(img, Color(0.30, 0.10, 0.04))
	_glow(img, Vector2(0.80, 0.20), 0.45, Color(1.0, 0.55, 0.15), 1.0)
	for k in [-1.0, 1.0]:
		var off: Vector2 = ACROSS * 0.10 * k
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.12, 0.70) + off, Vector2(0.46, 0.36) + off, 0.012), _flat(Color(1.0, 0.75, 0.35, 0.6)), 0.0)
	_spear(img)
	_star(img, Vector2(0.84, 0.16), 0.16, 0.05, 8, Color(1.0, 0.55, 0.12), Color(1.0, 0.97, 0.75))


# --- Compétences L2 : Human Knight / Paladin / Dark Avenger -----------------------

## Aggression : heaume du chevalier et marque de colère.
static func _skill_aggression(img: Image) -> void:
	_background(img, Color(0.28, 0.04, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.25, 0.15), 0.8)
	_helmet(img)
	_anger_mark(img, Vector2(0.76, 0.24), 0.85, Color(1.0, 0.50, 0.40), Color(0.70, 0.02, 0.02))


## Aura of Hate : marque de colère au centre d'ondes rouges concentriques.
static func _skill_aura_of_hate(img: Image) -> void:
	_background(img, Color(0.22, 0.03, 0.06))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.9, 0.1, 0.15), 1.0)
	for k in 3:
		var r := 0.30 + 0.07 * k
		_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.5), r)) - 0.014 * BASE_SIZE, _flat(Color(1.0, 0.35, 0.28, 0.85 - 0.25 * k)), 0.0)
	_anger_mark(img, Vector2(0.5, 0.5), 1.15, Color(1.0, 0.55, 0.45), Color(0.70, 0.02, 0.02))


static func _skill_divine_heal(img: Image) -> void:
	_background(img, Color(0.20, 0.17, 0.05))
	_glow(img, Vector2(0.5, 0.45), 0.6, Color(1.0, 0.9, 0.5), 1.0)
	for k in 8:
		var dir := Vector2.from_angle(TAU * k / 8.0 + PI / 8.0)
		var a := Vector2(0.5, 0.46) + dir * 0.20
		var b := Vector2(0.5, 0.46) + dir * 0.40
		_draw(img, func(p): return _sd_capsule(p, a, b, 0.012), _flat(Color(1.0, 0.95, 0.65, 0.6)), 0.0)
	_small_cross(img, Vector2(0.5, 0.46), 1.2)
	_heart(img, Vector2(0.75, 0.75), 0.40)


## Drain Health : tourbillon des ténèbres aspirant un cœur.
static func _skill_drain_health(img: Image) -> void:
	_background(img, Color(0.12, 0.03, 0.18))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.55, 0.15, 0.75), 0.9)
	_spiral(img, Vector2(0.5, 0.5), 0.40, 1.4, 0.05, Color(0.95, 0.40, 0.50), Color(0.45, 0.15, 0.75), -1.0)
	_heart(img, Vector2(0.5, 0.52), 0.60)


static func _skill_majesty(img: Image) -> void:
	_background(img, Color(0.10, 0.08, 0.30))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(1.0, 0.85, 0.40), 0.8)
	_ui_crown(img)


static func _skill_shield_stun(img: Image) -> void:
	_background(img, Color(0.08, 0.12, 0.26))
	_glow(img, Vector2(0.5, 0.58), 0.5, Color(0.5, 0.7, 1.0), 0.6)
	_kite(img, Vector2(0.5, 0.60), 0.82, Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28))
	_star(img, Vector2(0.5, 0.56), 0.13, 0.055, 5, Color(0.95, 0.70, 0.20), Color(1.0, 0.97, 0.75))
	_dizzy(img, Vector2(0.5, 0.17), 0.30, 0.08)


## Ultimate Defense : écu dans une bulle de protection.
static func _skill_ultimate_defense(img: Image) -> void:
	_background(img, Color(0.06, 0.10, 0.26))
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.52), 0.42), _flat(Color(0.45, 0.70, 1.0, 0.22)), 0.0)
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(0.5, 0.8, 1.0), 0.6)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.52), 0.42)) - 0.018 * BASE_SIZE, _lit_shade(Color(0.9, 0.97, 1.0), Color(0.35, 0.60, 0.95), 0.4), 0.8)
	_kite(img, Vector2(0.5, 0.52), 0.82, Color(0.85, 0.92, 1.0), Color(0.22, 0.38, 0.70))
	_small_cross(img, Vector2(0.5, 0.47), 0.6)


## Deflect Arrow : flèche qui ricoche sur l'écu.
static func _skill_deflect_arrow(img: Image) -> void:
	_background(img, Color(0.08, 0.16, 0.14))
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(0.6, 1.0, 0.8), 0.5)
	_kite(img, Vector2(0.40, 0.54), 0.82, Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28))
	_arrow(img, Vector2(0.98, 0.94), Vector2(0.64, 0.62), 0.8)
	_arrow(img, Vector2(0.68, 0.48), Vector2(0.94, 0.12), 0.8)
	_star(img, Vector2(0.62, 0.57), 0.10, 0.03, 6, Color(1.0, 0.85, 0.4), Color.WHITE)


static func _skill_magic_resistance(img: Image) -> void:
	_background(img, Color(0.14, 0.07, 0.28))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.5, 1.0), 0.8)
	_kite(img, Vector2(0.5, 0.52), 0.92, Color(0.62, 0.42, 0.95), Color(0.16, 0.05, 0.36))
	_magic_circle(img, Vector2(0.5, 0.46), 0.15, Color(1.0, 0.95, 1.0), Color(0.75, 0.60, 1.0))


static func _skill_shield_mastery(img: Image) -> void:
	_background(img, Color(0.22, 0.18, 0.06))
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(1.0, 0.80, 0.35), 0.45)
	_laurel(img)
	_kite(img, Vector2(0.5, 0.49), 0.62, Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28))


## Focus Mind : œil clos de méditation au-dessus d'une goutte de mana.
static func _skill_focus_mind(img: Image) -> void:
	_background(img, Color(0.05, 0.12, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, MANA_LIGHT, 0.6)
	var lid := _lit_shade(Color(1.0, 1.0, 1.0), Color(0.55, 0.75, 1.0), 0.2)
	var eye_c := Vector2(0.5, 0.02)
	_ring_arc(img, eye_c, 0.32, 0.03, PI / 2.0, 0.72, lid)
	for k in 5:
		var a := PI / 2.0 + (k - 2) * 0.30
		var root := eye_c + Vector2.from_angle(a) * 0.33
		var tip := eye_c + Vector2.from_angle(a) * 0.42
		_draw(img, func(p): return _sd_capsule(p, root, tip, 0.016), lid, 0.8)
	_tinted_drop(img, Vector2(0.5, 0.68), 0.52, MANA_LIGHT, MANA_DARK)


## Remedy : goutte de sang pansée et croix verte.
static func _skill_remedy(img: Image) -> void:
	_background(img, Color(0.06, 0.20, 0.12))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 1.0, 0.6), 0.6)
	_tinted_drop(img, Vector2(0.44, 0.48), 0.85, BLOOD_LIGHT, BLOOD_DARK)
	_draw(img, func(p): return _sd_box(p, Vector2(0.46, 0.58), Vector2(0.28, 0.065), -0.45, 0.02), _lit_shade(Color(1.0, 0.97, 0.88), Color(0.70, 0.62, 0.48), 0.2), 1.0)
	_plus(img, Vector2(0.76, 0.26), 0.55, LEAF_LIGHT, LEAF_DARK)


static func _skill_holy_armor(img: Image) -> void:
	_background(img, Color(0.24, 0.20, 0.06))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(1.0, 0.92, 0.55), 0.9)
	_cuirass(img, Color(0.95, 0.95, 0.98), Color(0.40, 0.42, 0.50), STEEL_LIGHT, STEEL_DARK, GOLD_LIGHT, GOLD_DARK)
	_small_cross(img, Vector2(0.5, 0.47), 0.48)


## Holy Blessing : rayons tombant du ciel sur un cœur.
static func _skill_holy_blessing(img: Image) -> void:
	_background(img, Color(0.22, 0.18, 0.05))
	for k in [-1.0, 0.0, 1.0]:
		var beam := [Vector2(0.5 + 0.06 * k - 0.03, 0.0), Vector2(0.5 + 0.06 * k + 0.03, 0.0), Vector2(0.5 + 0.30 * k + 0.08, 0.95), Vector2(0.5 + 0.30 * k - 0.08, 0.95)]
		_draw(img, func(p): return _sd_poly(p, beam), _flat(Color(1.0, 0.95, 0.70, 0.30)), 0.0)
	_glow(img, Vector2(0.5, 0.28), 0.45, Color(1.0, 0.9, 0.5), 0.9)
	_heart(img, Vector2(0.5, 0.62), 0.8)
	_star(img, Vector2(0.5, 0.22), 0.13, 0.035, 4, GOLD_LIGHT, Color.WHITE)


## Life Scavenge / Corpse Life Drain : la vie d'un cadavre (crâne) aspirée vers un cœur ;
## version nécromancien en vert sur violet.
static func _skill_corpse_drain(img: Image, necro: bool) -> void:
	var wisp_col := Color(0.55, 1.0, 0.45, 0.85) if necro else Color(1.0, 0.55, 0.45, 0.85)
	_background(img, Color(0.10, 0.05, 0.16) if necro else Color(0.20, 0.10, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.40, 0.90, 0.30) if necro else Color(1.0, 0.55, 0.25), 0.6)
	_skull(img, Vector2(0.34, 0.64), 0.78, Color(0.25, 0.9, 0.2) if necro else Color(0.06, 0.02, 0.04))
	for k in 2:
		var o := Vector2(0.03, -0.03) * (k * 2 - 1)
		var wisp := [Vector2(0.40, 0.42) + o, Vector2(0.46, 0.30) + o, Vector2(0.56, 0.34) + o, Vector2(0.62, 0.26) + o]
		_draw(img, func(p): return _sd_polyline(p, wisp, 0.016), _flat(wisp_col), 0.0)
	_heart(img, Vector2(0.72, 0.28), 0.48)


## Reflect Damage : écu miroir et flèche de renvoi.
static func _skill_reflect_damage(img: Image) -> void:
	_background(img, Color(0.20, 0.08, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.5, 0.2), 0.6)
	_kite(img, Vector2(0.38, 0.54), 0.82, Color(0.92, 0.94, 1.0), Color(0.32, 0.36, 0.48))
	_circ_arrow(img, Vector2(0.70, 0.46), 0.17, 0.03, 0.0, 1.55, Color(1.0, 0.55, 0.40), Color(0.65, 0.05, 0.02))
	_star(img, Vector2(0.62, 0.30), 0.09, 0.03, 6, Color(1.0, 0.6, 0.3), Color.WHITE)


static func _skill_summon_dark_panther(img: Image) -> void:
	_background(img, Color(0.12, 0.04, 0.20))
	_glow(img, Vector2(0.5, 0.52), 0.6, Color(0.6, 0.2, 0.9), 0.9)
	_cat_head(img, Vector2(0.5, 0.56), 1.0, Color(0.36, 0.30, 0.44), Color(0.03, 0.02, 0.06), Color(0.75, 1.0, 0.25))


# --- Compétences L2 : Rogue / Treasure Hunter / Hawkeye ----------------------------

static func _skill_dash(img: Image) -> void:
	_background(img, Color(0.28, 0.14, 0.04))
	_glow(img, Vector2(0.6, 0.55), 0.5, Color(1.0, 0.7, 0.3), 0.7)
	_speed_lines(img, Vector2(0.30, 0.52), 1.1, Color(1.0, 0.88, 0.55, 0.8))
	_boots(img)


static func _skill_bleed(img: Image) -> void:
	_background(img, Color(0.20, 0.03, 0.04))
	_glow(img, Vector2(0.5, 0.45), 0.55, Color(0.9, 0.1, 0.1), 0.7)
	_claw_marks(img, Color(1.0, 0.55, 0.50), Color(0.55, 0.0, 0.04))
	for c in [Vector2(0.20, 0.89), Vector2(0.36, 0.91), Vector2(0.51, 0.88)]:
		var dc: Vector2 = c
		_tinted_drop(img, dc, 0.22, BLOOD_LIGHT, BLOOD_DARK)


## Rapid Shot : volée de flèches parallèles.
static func _skill_rapid_shot(img: Image) -> void:
	_background(img, Color(0.10, 0.18, 0.07))
	_glow(img, Vector2(0.66, 0.34), 0.45, Color(0.8, 1.0, 0.5), 0.7)
	for k in 3:
		var tail: Vector2 = Vector2(0.24, 0.76) + ACROSS * (k - 1) * 0.17
		_draw(img, func(p): return _sd_capsule(p, tail - AXIS * 0.16, tail - AXIS * 0.02, 0.010), _flat(Color(0.9, 1.0, 0.7, 0.6)), 0.0)
		_arrow(img, tail, tail + AXIS * 0.58, 0.85)


static func _skill_stun_shot(img: Image) -> void:
	_background(img, Color(0.22, 0.16, 0.04))
	_glow(img, Vector2(0.70, 0.32), 0.45, Color(1.0, 0.85, 0.4), 0.8)
	_arrow(img, Vector2(0.16, 0.84), Vector2(0.70, 0.30), 1.0)
	_dizzy(img, Vector2(0.68, 0.24), 0.22, 0.065)


## Ultimate Evasion : paire d'ailes déployées.
static func _skill_ultimate_evasion(img: Image) -> void:
	_background(img, Color(0.06, 0.18, 0.22))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.6, 1.0, 1.0), 0.8)
	_wing(img, Vector2(0.47, 0.60), 0.70, -1.0)
	_wing(img, Vector2(0.53, 0.60), 0.70, 1.0)
	_star(img, Vector2(0.5, 0.56), 0.11, 0.03, 4, Color(0.8, 1.0, 1.0), Color.WHITE)


## Long Shot : flèche au long sillage vers une cible lointaine.
static func _skill_long_shot(img: Image) -> void:
	_background(img, Color(0.14, 0.14, 0.06))
	_glow(img, Vector2(0.82, 0.18), 0.35, Color(1.0, 0.9, 0.5), 0.8)
	for e in [[0.17, Color(0.95, 0.25, 0.20)], [0.11, Color(1.0, 0.97, 0.90)], [0.05, Color(0.95, 0.25, 0.20)]]:
		var r: float = e[0]
		var col: Color = e[1]
		_draw(img, func(p): return _sd_circle(p, Vector2(0.80, 0.20), r * 0.6), _lit_shade(col, col.darkened(0.4), 0.2), 0.8)
	for i in 5:
		var dc := Vector2(0.08, 0.92).lerp(Vector2(0.36, 0.64), i / 4.0)
		_draw(img, func(p): return _sd_circle(p, dc, 0.016), _flat(Color(1.0, 0.95, 0.7, 0.3 + 0.12 * i)), 0.0)
	_arrow(img, Vector2(0.40, 0.60), Vector2(0.78, 0.22), 0.9)


## Critical Chance : trèfle à quatre feuilles et étincelle rouge.
static func _skill_critical_chance(img: Image) -> void:
	_background(img, Color(0.06, 0.20, 0.08))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 1.0, 0.4), 0.6)
	var c := Vector2(0.46, 0.50)
	_draw(img, func(p): return _sd_capsule(p, c, Vector2(0.60, 0.88), 0.022), _lit_shade(LEAF_LIGHT, LEAF_DARK), 1.0)
	_draw(img, func(p: Vector2) -> float:
		var d := INF
		for k in 4:
			var dir := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
			var perp := Vector2(-dir.y, dir.x)
			d = minf(d, minf(_sd_circle(p, c + dir * 0.15 + perp * 0.065, 0.105), _sd_circle(p, c + dir * 0.15 - perp * 0.065, 0.105)))
		return d, _lit_shade(LEAF_LIGHT, LEAF_DARK, 0.3), 1.2)
	for k in 4:
		var vein := c + Vector2.from_angle(k * PI / 2.0) * 0.26
		_draw(img, func(p): return _sd_capsule(p, c, vein, 0.012), _flat(Color(0.04, 0.18, 0.03)), 0.0)
	_star(img, Vector2(0.78, 0.22), 0.14, 0.04, 4, Color(1.0, 0.35, 0.20), Color(1.0, 1.0, 0.85))


static func _skill_critical_power(img: Image) -> void:
	_background(img, Color(0.28, 0.04, 0.03))
	_glow(img, Vector2(0.46, 0.54), 0.55, Color(1.0, 0.3, 0.15), 0.9)
	_star(img, Vector2(0.44, 0.56), 0.34, 0.12, 6, Color(0.9, 0.12, 0.05), Color(1.0, 0.92, 0.6))
	_up_arrow(img, Vector2(0.78, 0.26), 0.85, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


## Boost Attack Speed : épée et traînées de mouvement.
static func _skill_boost_attack_speed(img: Image) -> void:
	_background(img, Color(0.26, 0.12, 0.04))
	_glow(img, Vector2(0.55, 0.45), 0.55, Color(1.0, 0.65, 0.25), 0.7)
	for k in 3:
		_ring_arc(img, Vector2(0.30, 0.70), 0.30 + 0.12 * k, 0.014, -PI / 4.0 - 0.55, 0.35, _flat(Color(1.0, 0.85, 0.55, 0.75 - 0.15 * k)), 0.0)
	_sword(img, Vector2(0.30, 0.70), -PI / 4.0, 0.92)
	_up_arrow(img, Vector2(0.80, 0.76), 0.7, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


static func _skill_quick_step(img: Image) -> void:
	_background(img, Color(0.22, 0.16, 0.06))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.85, 0.45), 0.55)
	_winged_boot(img)


## Esprit : cœur et goutte de mana emportés par la course.
static func _skill_esprit(img: Image) -> void:
	_background(img, Color(0.06, 0.18, 0.16))
	_glow(img, Vector2(0.55, 0.5), 0.55, Color(0.5, 1.0, 0.85), 0.6)
	_speed_lines(img, Vector2(0.30, 0.52), 1.0, Color(0.75, 1.0, 0.9, 0.75))
	_heart(img, Vector2(0.46, 0.54), 0.58)
	_tinted_drop(img, Vector2(0.75, 0.50), 0.50, MANA_LIGHT, MANA_DARK)


static func _skill_boost_evasion(img: Image) -> void:
	_background(img, Color(0.06, 0.14, 0.22))
	_glow(img, Vector2(0.45, 0.5), 0.55, Color(0.6, 0.9, 1.0), 0.6)
	_wing(img, Vector2(0.20, 0.56), 0.95, 1.0)
	_up_arrow(img, Vector2(0.80, 0.74), 0.75, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


static func _skill_bow_mastery(img: Image) -> void:
	_background(img, Color(0.10, 0.16, 0.20))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.80, 0.35), 0.55)
	_bow(img)


static func _skill_dagger_mastery(img: Image) -> void:
	_background(img, Color(0.20, 0.08, 0.10))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.80, 0.35), 0.55)
	_dagger(img)


## Acrobatic Move : aile prise dans une flèche de pirouette.
static func _skill_acrobatic_move(img: Image) -> void:
	_background(img, Color(0.10, 0.16, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 0.85, 1.0), 0.55)
	_circ_arrow(img, Vector2(0.5, 0.5), 0.37, 0.03, -PI / 2.0, 2.4, Color(0.95, 1.0, 1.0), Color(0.3, 0.6, 0.9))
	_wing(img, Vector2(0.26, 0.60), 0.85, 1.0)


## Backstab : dague plantée dans le dos d'une silhouette.
static func _skill_backstab(img: Image) -> void:
	_background(img, Color(0.12, 0.04, 0.12))
	_glow(img, Vector2(0.6, 0.5), 0.5, Color(0.85, 0.1, 0.2), 0.6)
	_silhouette(img, Vector2(0.60, 0.58), 1.0, Color(0.32, 0.22, 0.40), Color(0.05, 0.02, 0.08))
	_sword(img, Vector2(0.30, 0.30), PI / 4.0, 1.0, 0.13, 0.058, 0.21, 0.12, 0.13)
	_star(img, Vector2(0.56, 0.56), 0.10, 0.03, 6, Color(1.0, 0.2, 0.15), Color(1.0, 0.9, 0.8))


## Fake Death : pierre tombale sous la lune.
static func _skill_fake_death(img: Image) -> void:
	_background(img, Color(0.10, 0.12, 0.14))
	_glow(img, Vector2(0.5, 0.42), 0.5, Color(0.7, 0.8, 0.9), 0.4)
	_crescent(img, Vector2(0.80, 0.20), 0.11, Color(1.0, 0.98, 0.85), Color(0.80, 0.75, 0.50))
	_draw(img, func(p): return maxf(minf(_sd_box(p, Vector2(0.5, 0.62), Vector2(0.20, 0.22)), _sd_circle(p, Vector2(0.5, 0.40), 0.20)), p.y - 0.84 * BASE_SIZE), _lit_shade(Color(0.80, 0.82, 0.85), Color(0.25, 0.27, 0.32), 0.2))
	var engrave := _flat(Color(0.12, 0.13, 0.16, 0.9))
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.5, 0.53), Vector2(0.025, 0.13)), _sd_box(p, Vector2(0.5, 0.47), Vector2(0.09, 0.025))), engrave, 0.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.87), Vector2(0.40, 0.05), 0.0, 0.03), _lit_shade(Color(0.45, 0.70, 0.30), Color(0.10, 0.25, 0.06), 0.2), 1.0)


## Silent Move : empreintes de pas qui s'estompent, sous la lune.
static func _skill_silent_move(img: Image) -> void:
	_background(img, Color(0.08, 0.06, 0.16))
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(0.5, 0.4, 0.9), 0.4)
	_crescent(img, Vector2(0.24, 0.22), 0.11, Color(0.95, 0.92, 1.0), Color(0.55, 0.50, 0.80))
	var steps := [[Vector2(0.34, 0.82), 0.25], [Vector2(0.52, 0.66), 0.45], [Vector2(0.50, 0.40), 0.65], [Vector2(0.70, 0.24), 0.9]]
	for st in steps:
		var c: Vector2 = st[0]
		var alpha: float = st[1]
		var ang := 0.45
		var heel := c + Vector2(0.0, 0.11).rotated(ang)
		_draw(img, func(p): return minf(_sd_box(p, c, Vector2(0.05, 0.075), ang, 0.045), _sd_circle(p, heel, 0.042)), _flat(Color(0.80, 0.72, 1.0, alpha)), 0.0)


static func _skill_deadly_blow(img: Image) -> void:
	_background(img, Color(0.16, 0.02, 0.06))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.85, 0.05, 0.2), 0.8)
	_dagger(img)
	_skull(img, Vector2(0.74, 0.72), 0.46, Color(0.75, 0.0, 0.05))


## Shadow Step : silhouette qui réapparaît plus loin dans une traînée d'ombre.
static func _skill_shadow_step(img: Image) -> void:
	_background(img, Color(0.08, 0.04, 0.14))
	_glow(img, Vector2(0.64, 0.5), 0.5, Color(0.6, 0.3, 1.0), 0.8)
	_silhouette(img, Vector2(0.30, 0.58), 0.78, Color(0.55, 0.45, 0.75, 0.35), Color(0.20, 0.10, 0.35, 0.35))
	for k in 3:
		var y := 0.44 + 0.12 * k
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.28, y), Vector2(0.52, y - 0.04), 0.014), _flat(Color(0.75, 0.55, 1.0, 0.55)), 0.0)
	_silhouette(img, Vector2(0.66, 0.58), 0.95, Color(0.42, 0.28, 0.58), Color(0.04, 0.02, 0.08))


static func _skill_double_shot(img: Image) -> void:
	_background(img, Color(0.06, 0.14, 0.24))
	_glow(img, Vector2(0.70, 0.30), 0.45, Color(0.6, 0.85, 1.0), 0.7)
	for k in [-1.0, 1.0]:
		var tail: Vector2 = Vector2(0.18, 0.76) + ACROSS * 0.09 * k
		_arrow(img, tail, tail + AXIS * 0.72, 0.95)


## Hawk Eye : œil de rapace ambré sous un sourcil sévère.
static func _skill_hawk_eye(img: Image) -> void:
	_background(img, Color(0.20, 0.14, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.8, 0.3), 0.7)
	_eye(img, Vector2(0.5, 0.56), 1.25, Color(1.0, 0.70, 0.10))
	var brow := [Vector2(0.14, 0.38), Vector2(0.50, 0.30), Vector2(0.88, 0.42), Vector2(0.86, 0.48), Vector2(0.50, 0.40), Vector2(0.16, 0.44)]
	_draw(img, func(p): return _sd_poly(p, brow), _lit_shade(Color(0.55, 0.38, 0.20), Color(0.18, 0.10, 0.04), 0.2), 1.0)


## Soul of Sagittarius : symbole ♐ doré dans un ciel étoilé.
static func _skill_soul_of_sagittarius(img: Image) -> void:
	_background(img, Color(0.08, 0.08, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.6, 0.6, 1.0), 0.8)
	for e in [[Vector2(0.22, 0.24), 0.05], [Vector2(0.80, 0.72), 0.045], [Vector2(0.30, 0.84), 0.035], [Vector2(0.86, 0.40), 0.03]]:
		var sc: Vector2 = e[0]
		var sr: float = e[1]
		_star(img, sc, sr, sr * 0.35, 4, Color(0.85, 0.9, 1.0), Color.WHITE)
	_draw(img, func(p: Vector2) -> float:
		var d := minf(_sd_capsule(p, Vector2(0.24, 0.76), Vector2(0.74, 0.26), 0.035), _sd_polyline(p, [Vector2(0.46, 0.24), Vector2(0.76, 0.24), Vector2(0.76, 0.54)], 0.035))
		return minf(d, _sd_capsule(p, Vector2(0.30, 0.46), Vector2(0.54, 0.70), 0.035)), _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.4), 1.2)


# --- Compétences L2 : Human Wizard / Sorcerer / Necromancer / Warlock -------------

## Quick Recycle : sablier dans des flèches de recyclage.
static func _skill_quick_recycle(img: Image) -> void:
	_background(img, Color(0.12, 0.08, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.75, 0.6, 1.0), 0.6)
	_circ_arrows(img, Vector2(0.5, 0.5), 0.36, 0.032, GOLD_LIGHT, GOLD_DARK)
	_hourglass(img, Vector2(0.5, 0.5), 0.62, Color(0.55, 0.80, 1.0))


static func _skill_boost_mana(img: Image) -> void:
	_background(img, Color(0.05, 0.10, 0.28))
	_glow(img, Vector2(0.45, 0.55), 0.55, MANA_LIGHT, 0.7)
	_tinted_drop(img, Vector2(0.42, 0.54), 1.0, MANA_LIGHT, MANA_DARK)
	_up_arrow(img, Vector2(0.77, 0.30), 1.0, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


static func _skill_fast_spell_casting(img: Image) -> void:
	_background(img, Color(0.10, 0.08, 0.26))
	_glow(img, Vector2(0.48, 0.52), 0.55, Color(0.6, 0.5, 1.0), 0.7)
	_magic_circle(img, Vector2(0.46, 0.56), 0.32, Color(0.92, 0.88, 1.0), Color(0.45, 0.30, 0.90))
	_up_arrow(img, Vector2(0.80, 0.22), 0.7, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


static func _skill_fast_mana_recovery(img: Image) -> void:
	_background(img, Color(0.05, 0.14, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, MANA_LIGHT, 0.6)
	_circ_arrows(img, Vector2(0.5, 0.5), 0.35, 0.032, Color(0.85, 0.95, 1.0), Color(0.15, 0.35, 0.80))
	_tinted_drop(img, Vector2(0.5, 0.48), 0.62, MANA_LIGHT, MANA_DARK)


static func _skill_higher_mana_gain(img: Image) -> void:
	_background(img, Color(0.06, 0.10, 0.24))
	_glow(img, Vector2(0.5, 0.6), 0.5, MANA_LIGHT, 0.6)
	_potion(img, Color(0.25, 0.50, 1.0))
	_plus(img, Vector2(0.78, 0.26), 0.55, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


## Sleep : lune et « Zzz ».
static func _skill_sleep(img: Image) -> void:
	_background(img, Color(0.08, 0.06, 0.22))
	_glow(img, Vector2(0.40, 0.50), 0.5, Color(0.6, 0.5, 1.0), 0.6)
	_crescent(img, Vector2(0.36, 0.58), 0.26, Color(0.95, 0.92, 1.0), Color(0.55, 0.45, 0.85))
	_zzz(img, Vector2(0.68, 0.40), 1.0, Color(0.80, 0.75, 1.0))


static func _skill_concentration(img: Image) -> void:
	_background(img, Color(0.08, 0.10, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 0.7, 1.0), 0.7)
	_magic_circle(img, Vector2(0.5, 0.5), 0.38, Color(0.90, 0.95, 1.0), Color(0.35, 0.50, 0.95))
	_eye(img, Vector2(0.5, 0.5), 0.80, Color(0.30, 0.60, 1.0))


## Surrender To Fire/Wind : l'élément visé et une flèche violette de vulnérabilité.
static func _skill_surrender(img: Image, fire: bool) -> void:
	if fire:
		_background(img, Color(0.22, 0.05, 0.08))
		_glow(img, Vector2(0.44, 0.50), 0.5, Color(1.0, 0.45, 0.15), 0.8)
		_flame(img, Vector2(0.42, 0.50), 0.95)
	else:
		_background(img, Color(0.06, 0.16, 0.14))
		_glow(img, Vector2(0.44, 0.50), 0.5, Color(0.4, 0.9, 0.7), 0.6)
		_spiral(img, Vector2(0.42, 0.48), 0.30, 1.4, 0.06, Color(0.70, 1.0, 0.80), Color(1, 1, 1))
	_up_arrow(img, Vector2(0.78, 0.74), 0.8, DARK_LIGHT, DARK_DARK, PI)


static func _skill_summon_kat(img: Image) -> void:
	_background(img, Color(0.24, 0.12, 0.04))
	_glow(img, Vector2(0.5, 0.52), 0.6, Color(1.0, 0.65, 0.25), 0.8)
	_cat_head(img, Vector2(0.48, 0.56), 0.95, Color(1.0, 0.72, 0.36), Color(0.50, 0.22, 0.05), Color(0.45, 0.95, 0.30), true)
	_tinted_drop(img, Vector2(0.84, 0.80), 0.30, MANA_LIGHT, MANA_DARK)


static func _skill_summon_mew(img: Image) -> void:
	_background(img, Color(0.06, 0.12, 0.30))
	_glow(img, Vector2(0.5, 0.52), 0.6, Color(0.5, 0.75, 1.0), 0.8)
	_cat_head(img, Vector2(0.48, 0.56), 0.95, Color(1.0, 1.0, 1.0), Color(0.55, 0.60, 0.72), Color(0.30, 0.65, 1.0))
	_lightning(img, Vector2(0.84, 0.24), 0.42)


static func _skill_summon_kai(img: Image) -> void:
	_background(img, Color(0.22, 0.06, 0.06))
	_glow(img, Vector2(0.5, 0.52), 0.6, Color(1.0, 0.30, 0.20), 0.8)
	_cat_head(img, Vector2(0.46, 0.58), 0.95, Color(0.80, 0.80, 0.86), Color(0.22, 0.22, 0.30), Color(1.0, 0.25, 0.15), true)
	for k in 3:
		_cut(img, Vector2(0.80 + 0.06 * k, 0.07), Vector2(0.70 + 0.06 * k, 0.30), 0.02, Color(1.0, 0.9, 0.9), Color(0.8, 0.1, 0.1))


static func _skill_servitor_recharge(img: Image) -> void:
	_background(img, Color(0.05, 0.12, 0.28))
	_glow(img, Vector2(0.40, 0.40), 0.5, MANA_LIGHT, 0.7)
	_tinted_drop(img, Vector2(0.36, 0.40), 0.78, MANA_LIGHT, MANA_DARK)
	_up_arrow(img, Vector2(0.60, 0.60), 0.45, Color(1.0, 0.98, 0.85), Color(0.40, 0.65, 1.0), 3.0 * PI / 4.0)
	_servitor_badge(img)


static func _skill_servitor_heal(img: Image) -> void:
	_background(img, Color(0.08, 0.24, 0.12))
	_glow(img, Vector2(0.42, 0.42), 0.5, Color(0.70, 0.95, 0.45), 0.8)
	_small_cross(img, Vector2(0.40, 0.40), 1.0)
	_servitor_badge(img)


static func _skill_servitor_wind_walk(img: Image) -> void:
	_background(img, Color(0.05, 0.20, 0.16))
	_glow(img, Vector2(0.42, 0.42), 0.5, Color(0.45, 1.0, 0.75), 0.7)
	_speed_lines(img, Vector2(0.22, 0.56), 0.8, Color(0.70, 1.0, 0.85, 0.7))
	_wing(img, Vector2(0.18, 0.46), 0.85, 1.0)
	_servitor_badge(img)


static func _skill_servitor_physical_shield(img: Image) -> void:
	_background(img, Color(0.08, 0.12, 0.26))
	_glow(img, Vector2(0.42, 0.42), 0.5, Color(0.5, 0.7, 1.0), 0.6)
	_kite(img, Vector2(0.40, 0.44), 0.78, Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28))
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.40, 0.42), Vector2(0.026, 0.17)), _sd_box(p, Vector2(0.40, 0.37), Vector2(0.13, 0.026))), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_servitor_badge(img)


static func _skill_servitor_cure(img: Image) -> void:
	_background(img, Color(0.05, 0.22, 0.20))
	_glow(img, Vector2(0.42, 0.42), 0.5, Color(0.55, 1.0, 0.85), 0.8)
	_tinted_drop(img, Vector2(0.38, 0.42), 0.78, Color(0.75, 1.0, 0.95), Color(0.10, 0.45, 0.40))
	_star(img, Vector2(0.60, 0.20), 0.13, 0.035, 4, Color(0.85, 1.0, 0.95), Color.WHITE, PI / 4.0)
	_servitor_badge(img)


## Body To Mind : cœur -> flèche -> goutte de mana.
static func _skill_body_to_mind(img: Image) -> void:
	_background(img, Color(0.12, 0.08, 0.22))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.5, 1.0), 0.6)
	_heart(img, Vector2(0.30, 0.32), 0.58)
	_up_arrow(img, Vector2(0.52, 0.52), 0.75, Color(1.0, 0.98, 0.85), Color(0.75, 0.65, 0.95), 3.0 * PI / 4.0)
	_tinted_drop(img, Vector2(0.72, 0.68), 0.55, MANA_LIGHT, MANA_DARK)


static func _skill_slow(img: Image) -> void:
	_background(img, Color(0.14, 0.06, 0.22))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.4, 1.0), 0.6)
	_hourglass(img, Vector2(0.5, 0.50), 1.15, Color(0.85, 0.60, 1.0))


static func _skill_poisonous_cloud(img: Image) -> void:
	_background(img, Color(0.08, 0.14, 0.06))
	_glow(img, Vector2(0.5, 0.42), 0.55, Color(0.5, 1.0, 0.3), 0.7)
	_cloud(img, Vector2(0.5, 0.40), 1.15, Color(0.75, 1.0, 0.45), Color(0.15, 0.40, 0.08))
	for c in [Vector2(0.32, 0.76), Vector2(0.52, 0.82), Vector2(0.70, 0.74)]:
		var dc: Vector2 = c
		_tinted_drop(img, dc, 0.24, Color(0.75, 1.0, 0.45), Color(0.12, 0.40, 0.05))


static func _skill_aura_burn(img: Image) -> void:
	_background(img, Color(0.14, 0.04, 0.22))
	_glow(img, Vector2(0.5, 0.55), 0.55, Color(0.75, 0.35, 1.0), 0.9)
	_flame(img, Vector2(0.5, 0.54), 1.05, Color(0.40, 0.08, 0.70), Color(0.85, 0.50, 1.0), Color(1.0, 0.95, 1.0))


## Flame Strike : flammes jaillissant du sol.
static func _skill_flame_strike(img: Image) -> void:
	_background(img, Color(0.26, 0.06, 0.03))
	_glow(img, Vector2(0.5, 0.70), 0.55, Color(1.0, 0.45, 0.10), 0.9)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.89), Vector2(0.46, 0.07), 0.0, 0.03), _lit_shade(Color(0.50, 0.30, 0.18), Color(0.12, 0.06, 0.03), 0.1), 1.0)
	_flame(img, Vector2(0.24, 0.68), 0.58)
	_flame(img, Vector2(0.76, 0.68), 0.58)
	_flame(img, Vector2(0.5, 0.58), 1.0)


## Blaze : boule de feu enveloppée de flammes.
static func _skill_blaze(img: Image) -> void:
	_background(img, Color(0.30, 0.08, 0.02))
	_glow(img, Vector2(0.5, 0.52), 0.55, Color(1.0, 0.5, 0.1), 1.0)
	_flame(img, Vector2(0.5, 0.52), 1.25)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.64), 0.11), _sphere_shade(Vector2(0.5, 0.64), 0.11, Color(1.0, 1.0, 0.9), Color(1.0, 0.6, 0.1)), 0.0)


static func _skill_curse_chaos(img: Image) -> void:
	_background(img, Color(0.16, 0.04, 0.22))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.3, 0.9), 0.7)
	_spiral(img, Vector2(0.5, 0.5), 0.38, 2.0, 0.055, Color(1.0, 0.85, 1.0), Color(0.55, 0.15, 0.80))


## Projectile : orbe lumineux et traînée effilée vers le bas-gauche.
static func _comet(img: Image, c: Vector2, r: float, light: Color, dark: Color) -> void:
	var dir := Vector2(-0.7071, 0.7071)
	var perp := Vector2(0.7071, 0.7071)
	var tail := [c + perp * r * 0.95, c + dir * 0.58, c - perp * r * 0.95]
	_draw(img, func(p): return _sd_poly(p, tail), func(q: Vector2, _d: float) -> Color:
		var t := clampf(q.distance_to(c) / 0.58, 0.0, 1.0)
		var col := light.lerp(dark, t)
		col.a = 1.0 - t * 0.9
		return col, 0.0)
	_glow(img, c, r * 2.6, light, 0.8)
	_draw(img, func(p): return _sd_circle(p, c, r), _sphere_shade(c, r, Color.WHITE, light), 1.0)


static func _skill_energy_bolt(img: Image) -> void:
	_background(img, Color(0.06, 0.12, 0.24))
	_comet(img, Vector2(0.62, 0.38), 0.12, Color(0.75, 0.95, 1.0), Color(0.20, 0.40, 1.0))
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.62, 0.38), 0.19)) - 0.01 * BASE_SIZE, _flat(Color(0.9, 1.0, 1.0, 0.7)), 0.0)


## Curse Fear : fantôme hurlant.
static func _skill_curse_fear(img: Image) -> void:
	_background(img, Color(0.10, 0.04, 0.16))
	_glow(img, Vector2(0.5, 0.45), 0.55, Color(0.6, 0.4, 0.9), 0.7)
	_draw(img, func(p: Vector2) -> float:
		var body := minf(_sd_circle(p, Vector2(0.5, 0.40), 0.24), _sd_box(p, Vector2(0.5, 0.58), Vector2(0.24, 0.18)))
		var notches := minf(_sd_circle(p, Vector2(0.38, 0.79), 0.065), _sd_circle(p, Vector2(0.62, 0.79), 0.065))
		return maxf(body, -notches), _lit_shade(Color(0.97, 0.95, 1.0), Color(0.50, 0.42, 0.72), 0.2), 1.2)
	var hole := _flat(Color(0.12, 0.04, 0.18))
	for x in [0.42, 0.58]:
		var ec := Vector2(x, 0.40)
		_draw(img, func(p): return _sd_box(p, ec, Vector2(0.04, 0.06), 0.0, 0.04), hole, 0.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.57), Vector2(0.05, 0.075), 0.0, 0.05), hole, 0.0)


## Blazing Circle : couronne de flammes.
static func _skill_blazing_circle(img: Image) -> void:
	_background(img, Color(0.24, 0.06, 0.02))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(1.0, 0.45, 0.1), 0.8)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.52), 0.27)) - 0.02 * BASE_SIZE, _flat(Color(1.0, 0.85, 0.4, 0.9)), 0.0)
	for k in 7:
		var a := -PI / 2.0 + TAU * k / 7.0
		_flame(img, Vector2(0.5, 0.52) + Vector2(cos(a), sin(a)) * 0.29, 0.34)


## Prominence : soleil à couronne de flammes d'où jaillit une boucle de feu.
static func _skill_prominence(img: Image) -> void:
	_background(img, Color(0.30, 0.10, 0.02))
	_glow(img, Vector2(0.46, 0.56), 0.6, Color(1.0, 0.6, 0.1), 1.0)
	var sun := Vector2(0.44, 0.58)
	_star(img, sun, 0.36, 0.22, 12, FIRE_TIP, FIRE_BASE, 0.13)
	var loop_c := Vector2(0.64, 0.34)
	_ring_arc(img, loop_c, 0.17, 0.05, -PI / 4.0, 1.6, func(q: Vector2, _d: float) -> Color:
		return FIRE_CORE.lerp(FIRE_TIP, clampf(absf(q.distance_to(loop_c) - 0.17) / 0.05, 0.0, 1.0)), 1.0)
	_draw(img, func(p): return _sd_circle(p, sun, 0.21), _sphere_shade(sun, 0.21, Color(1.0, 1.0, 0.85), Color(1.0, 0.45, 0.05)), 1.0)


static func _skill_aura_flare(img: Image) -> void:
	_background(img, Color(0.16, 0.05, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.8, 0.5, 1.0), 1.0)
	_star(img, Vector2(0.5, 0.5), 0.44, 0.12, 12, Color(0.55, 0.25, 0.95), Color(1.0, 0.95, 1.0))
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.5), 0.30)) - 0.012 * BASE_SIZE, _flat(Color(1.0, 0.9, 1.0, 0.7)), 0.0)
	_star(img, Vector2(0.5, 0.5), 0.20, 0.06, 4, Color(1.0, 0.95, 1.0), Color.WHITE)


## Blazing Skin : silhouette drapée de flammes.
static func _skill_blazing_skin(img: Image) -> void:
	_background(img, Color(0.26, 0.07, 0.03))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(1.0, 0.5, 0.1), 0.9)
	_flame(img, Vector2(0.5, 0.56), 1.45)
	_silhouette(img, Vector2(0.5, 0.60), 0.80, Color(0.45, 0.18, 0.08), Color(0.10, 0.03, 0.02))


static func _skill_aura_bolt(img: Image) -> void:
	_background(img, Color(0.12, 0.05, 0.24))
	_glow(img, Vector2(0.62, 0.38), 0.5, Color(0.7, 0.4, 1.0), 0.9)
	var shard := [Vector2(0.84, 0.16), Vector2(0.60, 0.50), Vector2(0.52, 0.46), Vector2(0.20, 0.82), Vector2(0.46, 0.40), Vector2(0.42, 0.34)]
	_draw(img, func(p): return _sd_poly(p, shard), func(q: Vector2, _d: float) -> Color:
		return Color(0.62, 0.32, 1.0).lerp(Color(1.0, 0.92, 1.0), clampf((q.x - q.y + 0.6) * 0.8, 0.0, 1.0)), 1.2)
	for e in [[Vector2(0.28, 0.30), 0.07], [Vector2(0.76, 0.66), 0.06]]:
		var sc: Vector2 = e[0]
		var sr: float = e[1]
		_star(img, sc, sr, sr * 0.3, 4, Color(0.85, 0.6, 1.0), Color.WHITE)


## Clear Mind : cristal de mana limpide et scintillant.
static func _skill_clear_mind(img: Image) -> void:
	_background(img, Color(0.05, 0.14, 0.28))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 0.9, 1.0), 0.7)
	_gem(img, Vector2(0.5, 0.52), 0.30, Color(0.35, 0.75, 1.0))
	for e in [[Vector2(0.24, 0.26), 0.07], [Vector2(0.78, 0.30), 0.05], [Vector2(0.76, 0.80), 0.06]]:
		var sc: Vector2 = e[0]
		var sr: float = e[1]
		_star(img, sc, sr, sr * 0.3, 4, Color(0.85, 0.95, 1.0), Color.WHITE)


## Silence : bulle de parole barrée.
static func _skill_silence(img: Image) -> void:
	_background(img, Color(0.14, 0.05, 0.20))
	_glow(img, Vector2(0.5, 0.45), 0.55, Color(0.7, 0.4, 0.9), 0.6)
	var tail := [Vector2(0.30, 0.56), Vector2(0.20, 0.82), Vector2(0.46, 0.60)]
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.5, 0.42), Vector2(0.32, 0.21), 0.0, 0.15), _sd_poly(p, tail)), _lit_shade(Color(1.0, 0.98, 0.92), Color(0.62, 0.56, 0.70), 0.2), 1.2)
	for x in [0.37, 0.5, 0.63]:
		var dc := Vector2(x, 0.42)
		_draw(img, func(p): return _sd_circle(p, dc, 0.035), _flat(Color(0.20, 0.12, 0.28)), 0.0)
	_draw(img, func(p): return minf(_sd_capsule(p, Vector2(0.20, 0.16), Vector2(0.80, 0.74), 0.042), _sd_capsule(p, Vector2(0.80, 0.16), Vector2(0.20, 0.74), 0.042)),
		_lit_shade(Color(1.0, 0.45, 0.60), Color(0.50, 0.0, 0.20), 0.3), 1.2)


static func _skill_summon_corrupted_man(img: Image) -> void:
	_background(img, Color(0.08, 0.14, 0.08))
	_glow(img, Vector2(0.5, 0.48), 0.6, Color(0.35, 0.9, 0.25), 0.8)
	_skull(img, Vector2(0.5, 0.50), 1.2, Color(0.35, 1.0, 0.25), Color(0.80, 0.85, 0.65), Color(0.30, 0.38, 0.20))
	for x in [0.398, 0.602]:
		_glow(img, Vector2(x, 0.50), 0.10, Color(0.5, 1.0, 0.3), 0.8)


## Curse Discord : épées croisées dans un éclat violet.
static func _skill_curse_discord(img: Image) -> void:
	_background(img, Color(0.16, 0.04, 0.20))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.75, 0.30, 0.95), 0.8)
	_crossed_swords(img)
	_star(img, Vector2(0.5, 0.50), 0.17, 0.05, 7, Color(0.75, 0.30, 1.0), Color(1.0, 0.9, 1.0))


static func _skill_anchor(img: Image) -> void:
	_background(img, Color(0.12, 0.06, 0.22))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 0.4, 0.9), 0.6)
	var iron := _lit_shade(Color(0.82, 0.86, 0.92), Color(0.22, 0.25, 0.32), 0.35)
	var c := Vector2(0.5, 0.50)
	_draw(img, func(p: Vector2) -> float:
		var d := absf(_sd_circle(p, Vector2(0.5, 0.17), 0.065)) - 0.022 * BASE_SIZE
		d = minf(d, _sd_capsule(p, Vector2(0.5, 0.24), Vector2(0.5, 0.80), 0.035))
		return minf(d, _sd_box(p, Vector2(0.5, 0.32), Vector2(0.17, 0.03), 0.0, 0.015)), iron, 1.2)
	_ring_arc(img, c, 0.30, 0.035, PI / 2.0, 1.05, iron, 1.2)
	for side in [-1.0, 1.0]:
		var sd: float = side
		var a := PI / 2.0 - 1.05 * sd
		var radial := Vector2.from_angle(a)
		var end := c + radial * 0.30
		var tangent := Vector2.from_angle(a - PI / 2.0 * sd)
		var fluke := [end + radial * 0.06, end + tangent * 0.11, end - radial * 0.06]
		_draw(img, func(p): return _sd_poly(p, fluke), iron, 1.2)


static func _skill_vampiric_claw(img: Image) -> void:
	_background(img, Color(0.16, 0.02, 0.12))
	_glow(img, Vector2(0.5, 0.48), 0.55, Color(0.70, 0.10, 0.50), 0.9)
	_claw_marks(img, Color(1.0, 0.55, 0.75), Color(0.45, 0.0, 0.25))
	_tinted_drop(img, Vector2(0.80, 0.74), 0.32, BLOOD_LIGHT, BLOOD_DARK)


## Transfer Pain : cœur fêlé dont la douleur passe au serviteur.
static func _skill_transfer_pain(img: Image) -> void:
	_background(img, Color(0.18, 0.06, 0.10))
	_glow(img, Vector2(0.4, 0.4), 0.5, Color(1.0, 0.35, 0.35), 0.6)
	_heart(img, Vector2(0.32, 0.36), 0.70)
	var crack := [Vector2(0.32, 0.22), Vector2(0.36, 0.32), Vector2(0.29, 0.40), Vector2(0.33, 0.52)]
	_draw(img, func(p): return _sd_polyline(p, crack, 0.012), _flat(Color(0.15, 0.0, 0.02)), 0.0)
	_up_arrow(img, Vector2(0.58, 0.58), 0.55, Color(1.0, 0.95, 0.90), Color(0.85, 0.40, 0.45), 3.0 * PI / 4.0)
	_servitor_badge(img)


## Summon Storm/Binding Cubic et Mass Summon Storm Cubic : cube(s) au-dessus d'un cercle
## d'invocation ; foudre bleue pour la tempête, chaîne pour l'entrave.
static func _skill_summon_cubic(img: Image, storm: bool, mass := false) -> void:
	var color := Color(0.35, 0.60, 1.0) if storm else Color(0.95, 0.60, 0.20)
	_background(img, Color(0.05, 0.08, 0.24) if storm else Color(0.20, 0.10, 0.04))
	_ellipse_ring(img, Vector2(0.5, 0.82), 0.38, 0.10, 0.016, color.lightened(0.5))
	_ellipse_ring(img, Vector2(0.5, 0.82), 0.28, 0.07, 0.010, color.lightened(0.3))
	if mass:
		for c in [Vector2(0.27, 0.60), Vector2(0.73, 0.60), Vector2(0.5, 0.32)]:
			_cube(img, c, 0.55, color)
		return
	_cube(img, Vector2(0.5, 0.46), 0.95, color)
	if storm:
		_lightning(img, Vector2(0.84, 0.22), 0.40, Color(0.95, 1.0, 1.0), Color(0.35, 0.65, 1.0))
	else:
		_chain(img, Vector2(0.08, 0.40), Vector2(0.28, 0.10), 4, STEEL_LIGHT, STEEL_DARK)


## Storm Cubic (effet) : cube qui foudroie la cible.
static func _skill_storm_cubic(img: Image) -> void:
	var color := Color(0.35, 0.60, 1.0)
	_background(img, Color(0.04, 0.08, 0.22))
	_cube(img, Vector2(0.36, 0.34), 0.72, color)
	var bolt := [Vector2(0.40, 0.50), Vector2(0.52, 0.62), Vector2(0.46, 0.67), Vector2(0.62, 0.80), Vector2(0.80, 0.86)]
	_glow(img, Vector2(0.62, 0.74), 0.30, color, 0.8)
	_draw(img, func(p): return _sd_polyline(p, bolt, 0.03), _flat(Color(0.55, 0.80, 1.0)), 1.0)
	_draw(img, func(p): return _sd_polyline(p, bolt, 0.012), _flat(Color(1, 1, 1)), 0.0)
	_star(img, Vector2(0.80, 0.86), 0.12, 0.035, 6, Color(0.55, 0.80, 1.0), Color.WHITE)


## Binding Cubic (effet) : cube d'où pendent des chaînes d'entrave.
static func _skill_binding_cubic(img: Image) -> void:
	_background(img, Color(0.20, 0.10, 0.04))
	_chain(img, Vector2(0.40, 0.46), Vector2(0.16, 0.92), 5, STEEL_LIGHT, STEEL_DARK)
	_chain(img, Vector2(0.60, 0.46), Vector2(0.84, 0.92), 5, STEEL_LIGHT, STEEL_DARK)
	_cube(img, Vector2(0.5, 0.32), 0.78, Color(0.95, 0.60, 0.20))


## Master Recharge (effet de Kat the Cat) : goutte de mana offerte par le chat.
static func _skill_master_recharge(img: Image) -> void:
	_background(img, Color(0.05, 0.12, 0.28))
	_glow(img, Vector2(0.58, 0.46), 0.5, MANA_LIGHT, 0.8)
	_tinted_drop(img, Vector2(0.60, 0.42), 0.85, MANA_LIGHT, MANA_DARK)
	_cat_head(img, Vector2(0.26, 0.76), 0.45, Color(1.0, 0.72, 0.36), Color(0.50, 0.22, 0.05), Color(0.45, 0.95, 0.30), true)


## Mega Storm Strike (attaque de Mew the Cat) : nuage d'orage et éclairs.
static func _skill_mega_storm_strike(img: Image) -> void:
	_background(img, Color(0.04, 0.08, 0.22))
	_glow(img, Vector2(0.5, 0.55), 0.6, Color(0.45, 0.75, 1.0), 1.0)
	_cloud(img, Vector2(0.5, 0.28), 1.1, Color(0.70, 0.75, 0.90), Color(0.18, 0.20, 0.35))
	_lightning(img, Vector2(0.42, 0.66), 0.75, Color(0.95, 1.0, 1.0), Color(0.35, 0.65, 1.0))
	_lightning(img, Vector2(0.72, 0.70), 0.50, Color(0.95, 1.0, 1.0), Color(0.35, 0.65, 1.0))


# --- Compétences L2 : Cleric / Bishop / Prophet ------------------------------------

static func _skill_resurrection(img: Image) -> void:
	_background(img, Color(0.24, 0.20, 0.06))
	_glow(img, Vector2(0.5, 0.45), 0.6, Color(1.0, 0.92, 0.55), 1.0)
	for k in 12:
		var dir := Vector2.from_angle(TAU * k / 12.0)
		var a := Vector2(0.5, 0.44) + dir * 0.24
		var b := Vector2(0.5, 0.44) + dir * 0.44
		_draw(img, func(p): return _sd_capsule(p, a, b, 0.010), _flat(Color(1.0, 0.95, 0.70, 0.5)), 0.0)
	_ankh(img, Vector2(0.5, 0.50), 1.0)


static func _skill_mass_resurrection(img: Image) -> void:
	_background(img, Color(0.26, 0.16, 0.04))
	_glow(img, Vector2(0.5, 0.45), 0.6, Color(1.0, 0.85, 0.45), 0.9)
	_ellipse_ring(img, Vector2(0.5, 0.16), 0.20, 0.05, 0.016, Color(1.0, 0.95, 0.70, 0.95))
	for c in [Vector2(0.24, 0.62), Vector2(0.76, 0.62), Vector2(0.5, 0.54)]:
		_ankh(img, c, 0.62)


## Disrupt Undead : rayon sacré qui fend un crâne.
static func _skill_disrupt_undead(img: Image) -> void:
	_background(img, Color(0.20, 0.17, 0.06))
	_glow(img, Vector2(0.5, 0.30), 0.55, Color(1.0, 0.92, 0.55), 1.0)
	_draw(img, func(p): return _sd_poly(p, [Vector2(0.42, 0.0), Vector2(0.58, 0.0), Vector2(0.72, 0.70), Vector2(0.28, 0.70)]), _flat(Color(1.0, 0.97, 0.75, 0.30)), 0.0)
	_skull(img, Vector2(0.5, 0.62), 0.85)
	_draw(img, func(p): return _sd_polyline(p, [Vector2(0.47, 0.42), Vector2(0.53, 0.48), Vector2(0.48, 0.53)], 0.01), _flat(Color(0.15, 0.08, 0.04)), 0.0)
	_star(img, Vector2(0.5, 0.40), 0.17, 0.04, 4, GOLD_LIGHT, Color.WHITE)


## Might of Heaven : foudre dorée tombant d'un nuage céleste.
static func _skill_might_of_heaven(img: Image) -> void:
	_background(img, Color(0.16, 0.14, 0.30))
	_glow(img, Vector2(0.5, 0.40), 0.6, Color(1.0, 0.92, 0.55), 0.9)
	_cloud(img, Vector2(0.5, 0.26), 0.95, Color(1.0, 1.0, 0.95), Color(0.75, 0.68, 0.50))
	_lightning(img, Vector2(0.50, 0.64), 0.80, Color(1.0, 1.0, 0.85), Color(0.95, 0.70, 0.15))


static func _skill_mental_shield(img: Image) -> void:
	_background(img, Color(0.06, 0.14, 0.26))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.5, 0.8, 1.0), 0.7)
	_kite(img, Vector2(0.5, 0.52), 0.92, Color(0.45, 0.78, 0.95), Color(0.05, 0.22, 0.42))
	_eye(img, Vector2(0.5, 0.46), 0.62, Color(0.55, 0.30, 0.95))


static func _skill_holy_weapon(img: Image) -> void:
	_background(img, Color(0.22, 0.19, 0.06))
	_glow(img, Vector2(0.58, 0.40), 0.6, Color(1.0, 0.95, 0.65), 1.0)
	_sword(img, Vector2(0.30, 0.70), -PI / 4.0, 0.95)
	_small_cross(img, Vector2(0.78, 0.22), 0.5)
	_star(img, Vector2(0.24, 0.30), 0.07, 0.02, 4, GOLD_LIGHT, Color.WHITE)


## Regeneration : cœur et croix vertes qui montent.
static func _skill_regeneration(img: Image) -> void:
	_background(img, Color(0.06, 0.22, 0.12))
	_glow(img, Vector2(0.45, 0.55), 0.55, Color(0.6, 1.0, 0.55), 0.7)
	_heart(img, Vector2(0.40, 0.58), 0.85)
	for e in [[Vector2(0.80, 0.64), 0.32], [Vector2(0.74, 0.38), 0.42], [Vector2(0.84, 0.16), 0.30]]:
		var pc: Vector2 = e[0]
		var ps: float = e[1]
		_plus(img, pc, ps, LEAF_LIGHT, LEAF_DARK)


## Berserker Spirit : hache dans un brasier rouge.
static func _skill_berserker_spirit(img: Image) -> void:
	_background(img, Color(0.28, 0.04, 0.02))
	_glow(img, Vector2(0.55, 0.45), 0.6, Color(1.0, 0.25, 0.05), 1.0)
	_flame(img, Vector2(0.56, 0.50), 1.3, Color(0.70, 0.02, 0.02), Color(1.0, 0.45, 0.10), Color(1.0, 0.85, 0.5))
	_axe(img)


## Peace : colombe blanche portant un rameau d'olivier.
static func _skill_peace(img: Image) -> void:
	_background(img, Color(0.08, 0.16, 0.26))
	_glow(img, Vector2(0.5, 0.45), 0.6, Color(0.85, 0.95, 1.0), 0.8)
	var white := _lit_shade(WHITE_LIGHT, WHITE_DARK, 0.2)
	var tail := [Vector2(0.40, 0.58), Vector2(0.14, 0.60), Vector2(0.18, 0.74), Vector2(0.42, 0.68)]
	_draw(img, func(p): return minf(minf(_sd_poly(p, tail), _sd_capsule(p, Vector2(0.38, 0.63), Vector2(0.64, 0.55), 0.10)), _sd_circle(p, Vector2(0.70, 0.46), 0.075)), white, 1.2)
	_draw(img, func(p): return _sd_poly(p, [Vector2(0.76, 0.43), Vector2(0.86, 0.47), Vector2(0.76, 0.50)]), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.84, 0.48), Vector2(0.92, 0.62), 0.01), _flat(Color(0.30, 0.45, 0.15)), 0.5)
	for e in [[Vector2(0.86, 0.58), 0.9], [Vector2(0.93, 0.54), -0.5]]:
		var lc: Vector2 = e[0]
		var la: float = e[1]
		_draw(img, func(p): return _sd_box(p, lc, Vector2(0.045, 0.02), la, 0.02), _lit_shade(LEAF_LIGHT, LEAF_DARK), 0.8)
	var wing := [Vector2(0.40, 0.56), Vector2(0.26, 0.16), Vector2(0.40, 0.24), Vector2(0.52, 0.14), Vector2(0.58, 0.30), Vector2(0.62, 0.52)]
	_draw(img, func(p): return _sd_poly(p, wing), white, 1.2)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.72, 0.445), 0.014), _flat(Color(0.05, 0.05, 0.08)), 0.0)


## Focus : viseur doré et étoile critique rouge.
static func _skill_focus(img: Image) -> void:
	_background(img, Color(0.22, 0.08, 0.04))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(1.0, 0.6, 0.3), 0.7)
	_crosshair(img, Vector2(0.5, 0.5), 0.33, Color(1.0, 0.80, 0.30))
	_star(img, Vector2(0.5, 0.5), 0.17, 0.06, 6, Color(1.0, 0.20, 0.10), Color(1.0, 0.95, 0.8))


## Acumen : grimoire ouvert et étincelles.
static func _skill_acumen(img: Image) -> void:
	_background(img, Color(0.12, 0.08, 0.26))
	_glow(img, Vector2(0.5, 0.40), 0.55, Color(0.75, 0.6, 1.0), 0.8)
	_book(img, Vector2(0.5, 0.62), 1.0)
	for e in [[Vector2(0.50, 0.24), 0.12], [Vector2(0.28, 0.30), 0.06], [Vector2(0.72, 0.28), 0.07]]:
		var sc: Vector2 = e[0]
		var sr: float = e[1]
		_star(img, sc, sr, sr * 0.3, 4, GOLD_LIGHT, Color.WHITE)


## Resist Fire : flamme enfermée dans une bulle protectrice bleue.
static func _skill_resist_fire(img: Image) -> void:
	_background(img, Color(0.08, 0.12, 0.24))
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(1.0, 0.5, 0.2), 0.5)
	_flame(img, Vector2(0.5, 0.52), 0.85)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.52), 0.36), _flat(Color(0.45, 0.70, 1.0, 0.28)), 0.0)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.52), 0.36)) - 0.028 * BASE_SIZE, _lit_shade(Color(0.85, 0.95, 1.0), Color(0.20, 0.45, 0.95), 0.4), 1.0)


## Dryad Root : racines qui sortent du sol et enserrent.
static func _skill_dryad_root(img: Image) -> void:
	_background(img, Color(0.10, 0.14, 0.05))
	_glow(img, Vector2(0.5, 0.55), 0.55, Color(0.6, 0.9, 0.3), 0.6)
	var roots := [[Vector2(0.18, 0.98), Vector2(0.26, 0.72), Vector2(0.18, 0.50), Vector2(0.30, 0.26)],
		[Vector2(0.82, 0.98), Vector2(0.74, 0.72), Vector2(0.84, 0.48), Vector2(0.68, 0.24)],
		[Vector2(0.42, 0.98), Vector2(0.36, 0.72), Vector2(0.48, 0.54), Vector2(0.40, 0.34)],
		[Vector2(0.60, 0.98), Vector2(0.66, 0.74), Vector2(0.54, 0.58), Vector2(0.62, 0.40)]]
	for root in roots:
		var pts: Array = root
		_draw(img, func(p): return _sd_polyline(p, pts, 0.032), _lit_shade(WOOD_LIGHT, WOOD_DARK, 0.2), 1.0)
	for e in [[Vector2(0.33, 0.22), 0.6], [Vector2(0.65, 0.20), -0.6], [Vector2(0.42, 0.29), 1.0], [Vector2(0.62, 0.35), -0.9], [Vector2(0.14, 0.48), 0.4]]:
		var lc: Vector2 = e[0]
		var la: float = e[1]
		_draw(img, func(p): return _sd_box(p, lc, Vector2(0.06, 0.026), la, 0.025), _lit_shade(LEAF_LIGHT, LEAF_DARK), 0.8)


static func _skill_wind_walk(img: Image) -> void:
	_background(img, Color(0.05, 0.20, 0.16))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.45, 1.0, 0.75), 0.7)
	_speed_lines(img, Vector2(0.28, 0.66), 1.0, Color(0.70, 1.0, 0.85, 0.75))
	_winged_boot(img)


## Requiem : crâne apaisé et notes du chant funèbre.
static func _skill_requiem(img: Image) -> void:
	_background(img, Color(0.10, 0.06, 0.18))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.65, 0.5, 0.9), 0.6)
	_skull(img, Vector2(0.36, 0.60), 0.80)
	_note(img, Vector2(0.70, 0.42), 0.70, GOLD_LIGHT, GOLD_DARK)
	_note(img, Vector2(0.84, 0.74), 0.45, GOLD_LIGHT, GOLD_DARK)


static func _skill_greater_heal(img: Image) -> void:
	_background(img, Color(0.08, 0.26, 0.12))
	_glow(img, Vector2(0.5, 0.5), 0.6, Color(0.8, 1.0, 0.5), 0.6)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.5), 0.40)) - 0.016 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK), 0.8)
	_holy_cross(img)
	for e in [[Vector2(0.22, 0.22), 0.07], [Vector2(0.80, 0.78), 0.06]]:
		var sc: Vector2 = e[0]
		var sr: float = e[1]
		_star(img, sc, sr, sr * 0.3, 4, Color(1.0, 1.0, 0.8), Color.WHITE)


static func _skill_greater_battle_heal(img: Image) -> void:
	_background(img, Color(0.24, 0.22, 0.04))
	_glow(img, Vector2(0.58, 0.5), 0.6, Color(1.0, 0.95, 0.45), 0.9)
	for k in 3:
		var y := 0.34 + k * 0.16
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.08, y), Vector2(0.30 - k * 0.03, y), 0.018), _flat(Color(1.0, 1.0, 0.75, 0.8)), 0.0)
	_small_cross(img, Vector2(0.60, 0.50), 1.45)
	_star(img, Vector2(0.84, 0.18), 0.10, 0.03, 4, Color(1.0, 1.0, 0.8), Color.WHITE)


static func _skill_greater_group_heal(img: Image) -> void:
	_background(img, Color(0.06, 0.24, 0.18))
	_glow(img, Vector2(0.5, 0.52), 0.6, Color(0.70, 1.0, 0.70), 0.9)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.53), 0.25)) - 0.016 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK), 0.8)
	for c in [Vector2(0.5, 0.28), Vector2(0.28, 0.66), Vector2(0.72, 0.66)]:
		var cross_c: Vector2 = c
		_small_cross(img, cross_c, 0.66)


## Invigor : goutte de sang protégée par un anneau vert.
static func _skill_invigor(img: Image) -> void:
	_background(img, Color(0.10, 0.20, 0.08))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.6, 1.0, 0.5), 0.6)
	_tinted_drop(img, Vector2(0.48, 0.48), 0.75, BLOOD_LIGHT, BLOOD_DARK)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.48, 0.52), 0.34)) - 0.03 * BASE_SIZE, _lit_shade(LEAF_LIGHT, LEAF_DARK, 0.3), 1.0)
	_up_arrow(img, Vector2(0.82, 0.20), 0.6, Color(1.0, 0.98, 0.75), Color(0.90, 0.60, 0.15))


## Return : tour de la ville dans une flèche de retour.
static func _skill_return(img: Image) -> void:
	_background(img, Color(0.06, 0.14, 0.24))
	_glow(img, Vector2(0.46, 0.52), 0.55, Color(0.80, 0.92, 1.0), 0.7)
	_circ_arrow(img, Vector2(0.48, 0.52), 0.38, 0.03, 0.2, 2.2, Color(0.95, 1.0, 1.0), Color(0.35, 0.65, 0.95))
	_draw(img, func(p: Vector2) -> float:
		var d := _sd_box(p, Vector2(0.46, 0.58), Vector2(0.13, 0.24))
		for x in [0.36, 0.46, 0.56]:
			d = minf(d, _sd_box(p, Vector2(x, 0.32), Vector2(0.032, 0.045)))
		return d, _lit_shade(Color(0.92, 0.88, 0.80), Color(0.40, 0.36, 0.30), 0.2), 1.2)
	var hole := _flat(Color(0.10, 0.08, 0.06))
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.46, 0.76), Vector2(0.05, 0.06)), _sd_circle(p, Vector2(0.46, 0.70), 0.05)), hole, 0.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.46, 0.48), Vector2(0.02, 0.045), 0.0, 0.015), hole, 0.0)


## Guidance : étoile guide dorée.
static func _skill_guidance(img: Image) -> void:
	_background(img, Color(0.08, 0.10, 0.28))
	_glow(img, Vector2(0.5, 0.48), 0.6, Color(1.0, 0.90, 0.55), 0.9)
	_star(img, Vector2(0.5, 0.48), 0.40, 0.08, 4, Color(1.0, 0.78, 0.25), Color(1.0, 1.0, 0.9))
	_star(img, Vector2(0.5, 0.48), 0.22, 0.05, 4, Color(1.0, 0.9, 0.5), Color.WHITE, PI / 4.0)
	for e in [[Vector2(0.20, 0.80), 0.05], [Vector2(0.82, 0.78), 0.04], [Vector2(0.80, 0.20), 0.035]]:
		var sc: Vector2 = e[0]
		var sr: float = e[1]
		_star(img, sc, sr, sr * 0.35, 4, Color(0.85, 0.9, 1.0), Color.WHITE)


## Death Whisper : crâne aux yeux rouges et murmures sombres.
static func _skill_death_whisper(img: Image) -> void:
	_background(img, Color(0.16, 0.02, 0.08))
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.75, 0.05, 0.25), 0.8)
	for k in 3:
		_ring_arc(img, Vector2(0.40, 0.52), 0.30 + 0.08 * k, 0.014, 0.0, 0.5, _flat(Color(1.0, 0.40, 0.55, 0.8 - 0.2 * k)), 0.0)
	_skull(img, Vector2(0.40, 0.52), 0.95, Color(1.0, 0.10, 0.10))


## Bless Shield : écu ailé.
static func _skill_bless_shield(img: Image) -> void:
	_background(img, Color(0.10, 0.14, 0.30))
	_glow(img, Vector2(0.5, 0.48), 0.6, Color(1.0, 0.92, 0.6), 0.9)
	_wing(img, Vector2(0.42, 0.48), 0.62, -1.0)
	_wing(img, Vector2(0.58, 0.48), 0.62, 1.0)
	_kite(img, Vector2(0.5, 0.56), 0.72, Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28))
	_small_cross(img, Vector2(0.5, 0.52), 0.45)


# --- Pictogrammes d'interface (fond transparent, métal argent/or) ---------------

const UI_LIGHT := Color(0.98, 0.94, 0.82)
const UI_DARK := Color(0.55, 0.47, 0.32)


static func _ui_character(img: Image) -> void:
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.33), 0.15), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return maxf(_sd_box(p, Vector2(0.5, 0.80), Vector2(0.30, 0.26), 0.0, 0.20), p.y - 0.86 * BASE_SIZE), _lit_shade(UI_LIGHT, UI_DARK), 2.0)


static func _ui_bag(img: Image) -> void:
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.62), Vector2(0.28, 0.24), 0.0, 0.10), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.36), 0.13)) - 0.035 * BASE_SIZE + maxf(0.0, p.y - 0.38 * BASE_SIZE), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.55), Vector2(0.28, 0.035)), _flat(Color(0.35, 0.28, 0.16)), 0.0)


static func _ui_book(img: Image) -> void:
	_draw(img, func(p): return _sd_box(p, Vector2(0.52, 0.50), Vector2(0.27, 0.34), 0.0, 0.03), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.29, 0.50), Vector2(0.04, 0.34)), _flat(Color(0.40, 0.32, 0.18)), 0.0)
	var star := []
	for i in 10:
		var a := TAU * i / 10.0 - PI / 2.0
		star.append(Vector2(0.55, 0.48) + Vector2(cos(a), sin(a)) * (0.14 if i % 2 == 0 else 0.06))
	_draw(img, func(p): return _sd_poly(p, star), _flat(Color(0.40, 0.30, 0.14)), 0.0)


static func _ui_gear(img: Image) -> void:
	var sdf := func(p):
		var rel: Vector2 = p - _px(Vector2(0.5, 0.5))
		var a := atan2(rel.y, rel.x)
		var teeth := clampf(cos(a * 8.0) * 3.0, -1.0, 1.0) * 0.5 + 0.5
		var r := (0.27 + 0.08 * teeth) * BASE_SIZE
		return maxf(rel.length() - r, -(rel.length() - 0.12 * BASE_SIZE))
	_draw(img, sdf, _lit_shade(UI_LIGHT, UI_DARK), 2.0)


## Carte pliée en trois volets, route pointillée rouge jusqu'à une croix.
static func _ui_map(img: Image) -> void:
	var folds := [Vector2(0.16, 0.25), Vector2(0.38, 0.18), Vector2(0.62, 0.25), Vector2(0.84, 0.18),
		Vector2(0.84, 0.76), Vector2(0.62, 0.83), Vector2(0.38, 0.76), Vector2(0.16, 0.83)]
	_draw(img, func(p): return _sd_poly(p, folds), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	for fold in [[Vector2(0.38, 0.19), Vector2(0.38, 0.75)], [Vector2(0.62, 0.26), Vector2(0.62, 0.82)]]:
		_draw(img, func(p): return _sd_capsule(p, fold[0], fold[1], 0.012), _flat(Color(0.45, 0.37, 0.24, 0.8)), 0.0)
	var route := [Vector2(0.24, 0.68), Vector2(0.33, 0.58), Vector2(0.45, 0.60), Vector2(0.53, 0.48), Vector2(0.64, 0.42)]
	for i in route.size() - 1:
		var a: Vector2 = route[i].lerp(route[i + 1], 0.2)
		var b: Vector2 = route[i].lerp(route[i + 1], 0.75)
		_draw(img, func(p): return _sd_capsule(p, a, b, 0.022), _flat(Color(0.62, 0.14, 0.08)), 0.0)
	for cross in [[Vector2(0.66, 0.30), Vector2(0.78, 0.42)], [Vector2(0.78, 0.30), Vector2(0.66, 0.42)]]:
		_draw(img, func(p): return _sd_capsule(p, cross[0], cross[1], 0.028), _flat(Color(0.62, 0.14, 0.08)), 0.0)


static func _ui_coin(img: Image) -> void:
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.5), 0.40), _lit_shade(Color(1.0, 0.92, 0.55), Color(0.62, 0.40, 0.08), 0.5), 2.5)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.5), 0.28)) - 0.03 * BASE_SIZE, _flat(Color(0.60, 0.40, 0.08, 0.9)), 0.0)


## Couronne dorée à trois pointes (chef du groupe, voir PartyWindow), gemme rouge au centre.
static func _ui_crown(img: Image) -> void:
	var outline := [Vector2(0.12, 0.30), Vector2(0.32, 0.52), Vector2(0.50, 0.20), Vector2(0.68, 0.52),
		Vector2(0.88, 0.30), Vector2(0.80, 0.78), Vector2(0.20, 0.78)]
	_draw(img, func(p): return _sd_poly(p, outline), _lit_shade(Color(1.0, 0.92, 0.55), Color(0.62, 0.40, 0.08), 0.5), 2.5)
	for tip in [Vector2(0.12, 0.28), Vector2(0.50, 0.18), Vector2(0.88, 0.28)]:
		_draw(img, func(p): return _sd_circle(p, tip, 0.065), _lit_shade(Color(1.0, 0.95, 0.70), Color(0.70, 0.48, 0.12)), 1.5)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.72), Vector2(0.30, 0.035)), _flat(Color(0.55, 0.36, 0.07, 0.9)), 0.0)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.58), 0.07), _lit_shade(Color(1.0, 0.55, 0.50), Color(0.55, 0.05, 0.08)), 1.2)
