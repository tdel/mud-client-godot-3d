extends Node
## Outil de développement (hors jeu) : vidéo de démo scriptée, sans serveur. Rejoue de faux
## messages serveur (Net.message_received) dans la vraie scène de jeu (Game.tscn : HUD, VFX,
## sons, musique) : Aelwyn (guerrier, le joueur) et Morwen (mystique, son groupe) quittent la
## Place du village par le portail ouest, arrivent à l'Orée de la forêt et y affrontent un
## Brown Keltir et deux Fox, avec soulshots, spiritshots et compétences.
##
## Enregistrement via Movie Maker (pas fixe, sortie PNG + WAV), puis montage ffmpeg :
##   powershell -File tools/demo_video/record_demo.ps1
## Les trajets suivent un A* sur la praticabilité réelle des cartes (terrain + obstacles, même
## règle que tools/export_map_to_tmx.gd). Imprime DEMO_START_SEC / DEMO_END_SEC (temps de jeu
## depuis le lancement) pour couper le chargement initial au montage.
##
## user://hotbar.cfg est sauvegardé puis restauré tel quel, les positions de fenêtres ne sont
## ni lues ni écrites (comme tools/ui_preview).

const HOTBAR_CFG := "user://hotbar.cfg"
const VILLAGE := "Place du village"
const OREE := "Orée de la forêt"
const OREE_SCENE := "res://scenes/maps/Orée_de_la_forêt.tscn"

const PLAYER_ID := "demo-aelwyn"
const PLAYER_NAME := "Aelwyn"
const MATE_ID := "demo-morwen"
const MATE_NAME := "Morwen"
const KELTIR_ID := "demo-keltir"
const FOX_A_ID := "demo-fox-a"
const FOX_B_ID := "demo-fox-b"

## Tuiles par seconde (joueurs) et des monstres en chasse.
const RUN_SPEED := 4.0
const MONSTER_SPEED := 4.6

## Place du village : départ sur l'avenue, juste avant la porte ouest ; portail ouest (5, 46)
## qui mène au portail est de l'Orée (442, 135) — voir Portal_O dans Place_du_village.tscn.
const VILLAGE_START := Vector2(34.5, 45.4)
const VILLAGE_MATE_START := Vector2(35.4, 46.9)
const VILLAGE_PORTAL := Vector2(5.0, 46.0)
const OREE_ARRIVAL := Vector2(442.0, 135.0)

var _game: Node
## Incrémenté à chaque changement de carte : les fins de déplacement encore en attente sur la
## carte précédente (voir _later) ne doivent pas replacer une entité de la nouvelle carte.
var _map_epoch := 0
var _astar: AStarGrid2D
var _map_size := Vector2i.ZERO
var _hp := {}
var _max_hp := {}
var _names := {}
var _soulshots := 250
var _mana := 62
var _hotbar_backup: PackedByteArray
var _hotbar_existed := false
## Gardée en mémoire pour que le chargement de l'Orée (threaded, voir Game3D._advance_map_load)
## sorte du cache : sous Movie Maker, chaque image d'attente du disque serait filmée.
var _oree_packed: PackedScene


func _ready() -> void:
	WindowFrame.persist_positions = false
	# Volumes par défaut (non sauvegardés) : le mixage de la vidéo ne dépend pas des réglages
	# du joueur.
	for bus in Settings.BUSES:
		Settings._volumes[bus] = 1.0
		Settings._apply_volume(bus)
	_hotbar_existed = FileAccess.file_exists(HOTBAR_CFG)
	if _hotbar_existed:
		_hotbar_backup = FileAccess.get_file_as_bytes(HOTBAR_CFG)
	_run.call_deferred()


func _run() -> void:
	_oree_packed = load(OREE_SCENE)
	_feed_initial_state()
	var scene: Node = load("res://scenes/game/Game.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	_game = scene
	_enter_map(VILLAGE, VILLAGE_START, PI)
	await _wait_map_loaded()
	# Musique de la forêt dès le village (même piste à l'Orée, donc sans coupure).
	ZoneMusic.play_for_biome(MapData.Biome.FOREST)
	_setup_hotbar()
	_game._zoom_camera(14.0 - float(_game._camera_size))
	_spawn_village()
	await _frames(20)
	print("DEMO_START_SEC=%.4f" % GameClock.now())
	await _play_village()
	await _play_oree()
	print("DEMO_END_SEC=%.4f" % GameClock.now())
	_restore_hotbar()
	get_tree().quit()


# ---------------------------------------------------------------------------
# Scénario
# ---------------------------------------------------------------------------

func _play_village() -> void:
	_party_chat(MATE_NAME, "Prêt ? Direction l'Orée de la forêt !")
	await _wait(0.5)
	_emit("ShotGradeChanged", {"shotType": "SOULSHOT", "grade": "NOGRADE"})
	GameState.player_stats["activeSoulshotGrade"] = "NOGRADE"
	await _wait(0.3)
	_cast_other(MATE_ID, "Empower", MATE_ID, 900, true)
	await _wait(0.9)
	_emit("SkillModifierAnnounced", {"casterId": MATE_ID, "casterName": MATE_NAME, "skillName": "Empower",
		"targetId": MATE_ID, "hit": true})
	# Le buff apparaît dans la fenêtre de groupe, comme le diffuse PartyEngine au groupe.
	_emit("PartyMemberEffectApplied", {"characterId": MATE_ID, "characterName": MATE_NAME, "skillName": "Empower",
		"stat": "M. Atk.", "amount": 1, "secondsRemaining": 60, "beneficial": true})
	await _wait(0.35)
	_say("En route !")
	var run := _move_player(VILLAGE_PORTAL + Vector2(0.4, 0.0))
	await _wait(0.35)
	_move_entity(MATE_ID, MATE_NAME, VILLAGE_PORTAL + Vector2(1.2, 1.1), RUN_SPEED)
	# Porte ouest (remparts x 23..28) : sortie de la zone paisible du village.
	await _wait(maxf((VILLAGE_START.x - 25.5) / RUN_SPEED - 0.35, 0.0))
	_emit("PeaceZoneExited", {"zoneName": VILLAGE})
	await _wait(maxf(run - (VILLAGE_START.x - 25.5) / RUN_SPEED, 0.0) + 0.05)


func _play_oree() -> void:
	# Passage du portail : MapView/MapEnter comme le serveur, Morwen arrive avec nous.
	_enter_map(OREE, OREE_ARRIVAL, PI)
	_emit("PortalAppeared", {"portals": [{"id": "demo-portal-oree-e", "name": VILLAGE, "title": "Téléporteur",
		"targetMapName": VILLAGE, "x": 442.0, "y": 135.0, "triggerRadius": 0.7}]})
	_emit("EntityAppeared", {"entities": [
		_mate_entry(OREE_ARRIVAL + Vector2(0.6, 1.3)),
		_monster_entry(KELTIR_ID, "Brown Keltir", Vector2(416.5, 134.5), 55, 2, 0.2),
		_monster_entry(FOX_A_ID, "Fox", Vector2(415.0, 139.0), 44, 2, -0.4),
		_monster_entry(FOX_B_ID, "Fox", Vector2(411.5, 137.5), 44, 2, 0.1),
	]})
	_emit("PartyMemberVitalsUpdated", {"characterId": MATE_ID, "characterName": MATE_NAME,
		"currentHealth": _hp[MATE_ID], "maxHealth": _max_hp[MATE_ID], "currentMana": 90, "maxMana": 90})
	await _wait_map_loaded()
	await _wait(0.25)

	var fight_spot := Vector2(427.5, 137.2)
	var mate_spot := Vector2(431.0, 136.0)
	_move_player(fight_spot)
	_zoom_to(12.5, 2.0)
	await _wait(0.2)
	_move_entity(MATE_ID, MATE_NAME, mate_spot, RUN_SPEED)
	await _wait(0.9)
	_select(KELTIR_ID)
	await _wait(0.2)
	# Les monstres nous repèrent et chargent.
	var keltir_run := _move_entity(KELTIR_ID, "Brown Keltir", fight_spot + Vector2(-1.25, -0.15), MONSTER_SPEED)
	await _wait(0.25)
	_move_entity(FOX_A_ID, "Fox", mate_spot + Vector2(-1.2, 0.5), MONSTER_SPEED * 0.8)
	await _wait(0.35)
	# Morwen, arrivée, lance un Wind Strike chargé (spiritshot) sur le Fox qui approche.
	_cast_other(MATE_ID, "Wind Strike", FOX_A_ID, 1000, true)
	await _wait(1.0)
	_projectile_other(MATE_ID, "Wind Strike", FOX_A_ID, 0.35, 27)
	await _wait(maxf(keltir_run - 2.05, 0.1))

	# Mêlée : Aelwyn contre le Keltir, un soulshot par coup ; le second Fox accourt en renfort.
	var melee_start := GameClock.now()
	var fox_b_run := _move_entity(FOX_B_ID, "Fox", fight_spot + Vector2(-1.1, 0.9), MONSTER_SPEED)
	_player_attack(KELTIR_ID, 14)
	await _wait(0.3)
	_monster_attack(KELTIR_ID, PLAYER_ID, 6)
	await _wait(0.5)
	_player_attack(KELTIR_ID, 15)
	await _wait(0.25)
	_monster_attack(FOX_A_ID, MATE_ID, 7)
	await _wait(0.25)
	_monster_attack(KELTIR_ID, PLAYER_ID, 5)
	await _wait(0.25)
	# Power Strike pour achever le Keltir, pendant que Morwen enchaîne un second Wind Strike.
	_player_skill("Power Strike", KELTIR_ID, 600, 26)
	await _wait(0.1)
	_cast_other(MATE_ID, "Wind Strike", FOX_A_ID, 900, true)
	await _wait(0.9)
	_projectile_other(MATE_ID, "Wind Strike", FOX_A_ID, 0.2, 21)
	await _wait(0.45)
	_select(FOX_B_ID)
	_cast_other(MATE_ID, "Heal", MATE_ID, 900, true)
	await _wait(maxf(fox_b_run - (GameClock.now() - melee_start), 0.1))
	_player_attack(FOX_B_ID, 23, true)
	await _wait(0.35)
	_mate_self_heal(15)
	_monster_attack(FOX_B_ID, PLAYER_ID, 6)
	await _wait(0.5)
	_player_attack(FOX_B_ID, 13)
	await _wait(0.8)
	_player_attack(FOX_B_ID, 12)
	await _wait(0.45)
	_emit("PlayerLeveledUp", {"characterName": PLAYER_NAME, "newLevel": 6})
	var stats: Dictionary = GameState.player_stats.duplicate()
	stats.merge({"level": 6, "currentHealth": _hp[PLAYER_ID], "maxHealth": 188, "currentMana": _mana,
		"maxMana": 70, "xp": GameState.xp, "xpForCurrentLevel": 1520, "xpForNextLevel": 2400,
		"activeSoulshotGrade": "NOGRADE"}, true)
	_max_hp[PLAYER_ID] = 188
	_emit("GamePlayerStats", stats)
	_emit("GoldLooted", {"amount": 37})
	await _wait(0.6)
	_party_chat(MATE_NAME, "Bien joué ! On pousse plus loin dans la forêt ?")
	await _wait(1.4)


# ---------------------------------------------------------------------------
# État initial
# ---------------------------------------------------------------------------

func _feed_initial_state() -> void:
	_hp = {PLAYER_ID: 131, MATE_ID: 96}
	_max_hp = {PLAYER_ID: 162, MATE_ID: 104}
	_names = {PLAYER_ID: PLAYER_NAME, MATE_ID: MATE_NAME}
	_emit("GamePlayerStats", {
		"id": PLAYER_ID, "name": PLAYER_NAME, "level": 5, "characterClass": "FIGHTER", "gender": "MAN",
		"currentHealth": _hp[PLAYER_ID], "maxHealth": _max_hp[PLAYER_ID], "currentMana": _mana, "maxMana": 62,
		"xp": 1360, "xpForCurrentLevel": 900, "xpForNextLevel": 1520,
		"pAtk": 38, "mAtk": 16, "pDef": 64, "mDef": 41, "accuracy": 33, "evasion": 32,
		"criticalRate": 8, "atkSpd": 300, "speed": RUN_SPEED, "castSpd": 213,
		"strength": {"score": 40}, "dexterity": {"score": 30}, "constitution": {"score": 43},
		"intelligence": {"score": 21}, "wit": {"score": 11}, "men": {"score": 25},
		"karma": 0, "pvpCount": 0, "pkCount": 0,
	})
	# Équipement de base (noms du catalogue backend) + charges et consommables.
	_emit("Inventory", {"gold": 2150, "items": [
		{"id": "demo-e1", "name": "Short Sword", "grade": "NOGRADE", "type": "WEAPON", "slot": "WEAPON",
			"weaponType": "SWORD", "pAtk": 9, "atkSpd": 300},
		{"id": "demo-e2", "name": "Wooden Shield", "grade": "NOGRADE", "type": "SHIELD", "slot": "OFF_HAND", "pDef": 12},
		{"id": "demo-e3", "name": "Leather Tunic", "grade": "NOGRADE", "type": "ARMOR", "slot": "CHEST",
			"armorCategory": "LIGHT", "pDef": 18},
		{"id": "demo-e4", "name": "Leather Pants", "grade": "NOGRADE", "type": "PANTS", "slot": "LEGS",
			"armorCategory": "LIGHT", "pDef": 11},
		{"id": "demo-e5", "name": "Leather Gloves", "grade": "NOGRADE", "type": "GLOVES", "slot": "HANDS",
			"armorCategory": "LIGHT", "pDef": 4},
		{"id": "demo-e6", "name": "Leather Boots", "grade": "NOGRADE", "type": "BOOTS", "slot": "FEET",
			"armorCategory": "LIGHT", "pDef": 5},
		{"id": "demo-i1", "name": "Soulshot : Aucun grade", "grade": "NOGRADE", "type": "SOULSHOT", "quantity": _soulshots},
		{"id": "demo-i2", "name": "Healing Potion", "grade": "NOGRADE", "type": "POTION", "quantity": 15},
		{"id": "demo-i3", "name": "Scroll of Escape", "grade": "NOGRADE", "type": "SCROLL", "quantity": 2},
	]})
	_emit("KnownSkills", {"skills": [
		{"id": "demo-s1", "name": "Power Strike", "level": 1, "skillType": "DAMAGE", "manaCost": 9,
			"cooldownSeconds": 4, "range": 2},
	]})
	GameState.party = {"leader_id": PLAYER_ID, "loot_mode": "ROUND_ROBIN", "members": {
		MATE_ID: GameState._member_vitals({"name": MATE_NAME, "level": 5, "characterClass": "MYSTIC",
			"currentHealth": _hp[MATE_ID],
			"maxHealth": _max_hp[MATE_ID], "currentMana": 90, "maxMana": 90}),
	}}


func _spawn_village() -> void:
	_emit("EntityAppeared", {"entities": [
		_mate_entry(VILLAGE_MATE_START),
		{"id": "demo-guard-o1", "name": "Gate Guard", "kind": "npc", "title": "City Guard", "x": 30.5, "y": 43.8,
			"heading": PI / 2.0, "npcType": "GUARD", "gender": "MAN"},
		{"id": "demo-guard-o2", "name": "Gate Guard", "kind": "npc", "title": "City Guard", "x": 30.5, "y": 48.2,
			"heading": -PI / 2.0, "npcType": "GUARD", "gender": "WOMAN"},
	]})
	_emit("PortalAppeared", {"portals": [{"id": "demo-portal-village-o", "name": OREE, "title": "Téléporteur",
		"targetMapName": OREE, "x": VILLAGE_PORTAL.x, "y": VILLAGE_PORTAL.y, "triggerRadius": 0.7}]})


func _mate_entry(pos: Vector2) -> Dictionary:
	return {"id": MATE_ID, "name": MATE_NAME, "kind": "character", "x": pos.x, "y": pos.y, "heading": PI,
		"currentHealth": _hp[MATE_ID], "maxHealth": _max_hp[MATE_ID], "level": 5, "speed": RUN_SPEED,
		"gender": "WOMAN", "equipment": [
			{"slot": "WEAPON", "name": "Basic Wizard Staff", "type": "WEAPON", "grade": "NOGRADE", "weaponType": "STAFF"},
			{"slot": "CHEST", "name": "Apprentice's Robe", "type": "ARMOR", "grade": "NOGRADE", "armorCategory": "LIGHT"},
			{"slot": "FEET", "name": "Leather Boots", "type": "BOOTS", "grade": "NOGRADE", "armorCategory": "LIGHT"},
		]}


func _monster_entry(id: String, monster_name: String, pos: Vector2, max_health: int, level: int, heading: float) -> Dictionary:
	_hp[id] = max_health
	_max_hp[id] = max_health
	_names[id] = monster_name
	return {"id": id, "name": monster_name, "kind": "monster", "x": pos.x, "y": pos.y, "heading": heading,
		"currentHealth": max_health, "maxHealth": max_health, "level": level, "speed": MONSTER_SPEED}


func _setup_hotbar() -> void:
	var hotbar: Node = _game.get_node("HUD/Hotbar")
	for i in hotbar.SLOT_COUNT:
		hotbar.clear_slot(i)
	hotbar.set_slot(0, "attack", "", "Attaque")
	hotbar.set_slot(1, "skill", "demo-s1", "Power Strike")
	hotbar.set_slot(2, "item", "demo-i1", "Soulshot : Aucun grade", "SOULSHOT", "NOGRADE")
	hotbar.set_slot(3, "item", "demo-i2", "Healing Potion", "POTION", "NOGRADE")
	hotbar.set_slot(4, "item", "demo-i3", "Scroll of Escape", "SCROLL", "NOGRADE")


func _enter_map(map_name: String, pos: Vector2, heading: float) -> void:
	_map_epoch += 1
	var size := _scene_size(map_name)
	var rows := []
	for y in size.y:
		rows.append("1".repeat(size.x))
	_emit("MapView", {"mapName": map_name, "grid": {"width": size.x, "height": size.y, "walkableRows": rows}})
	_emit("MapEnter", {"selfX": pos.x, "selfY": pos.y, "selfHeading": heading})


func _wait_map_loaded() -> void:
	await _frames(2)
	while LoadingScreen.is_active():
		await get_tree().process_frame
	_build_astar()


# ---------------------------------------------------------------------------
# Actions (messages serveur simulés)
# ---------------------------------------------------------------------------

func _emit(type: String, payload: Dictionary) -> void:
	Net.message_received.emit(type, payload)


func _say(text: String) -> void:
	_emit("PartyChat", {"speakerName": PLAYER_NAME, "text": text})


func _party_chat(speaker: String, text: String) -> void:
	_emit("PartyChat", {"speakerName": speaker, "text": text})


func _select(target_id: String) -> void:
	_emit("TargetSelected", {"targetId": target_id, "targetName": _names[target_id]})


## Déplacement du joueur le long d'un chemin A* ; renvoie sa durée (s). MovementFinished part
## tout seul à l'arrivée.
func _move_player(to: Vector2) -> float:
	var from := _pos_of(PLAYER_ID)
	var path := _find_path(from, to)
	_emit("MovementStarted", {"x": to.x, "y": to.y, "startX": from.x, "startY": from.y,
		"waypoints": _waypoints(path)})
	var duration := _path_length(from, path) / RUN_SPEED
	_later(duration, func() -> void: _emit("MovementFinished", {"x": to.x, "y": to.y}))
	return duration


func _move_entity(id: String, entity_name: String, to: Vector2, speed: float) -> float:
	var from := _pos_of(id)
	var path := _find_path(from, to)
	_game._entity_speed_by_key[_game._key_for_entity_id(id)] = speed
	_emit("CharacterMovementStarted", {"characterId": id, "characterName": entity_name, "x": from.x, "y": from.y,
		"targetX": to.x, "targetY": to.y, "waypoints": _waypoints(path)})
	var duration := _path_length(from, path) / speed
	_later(duration, func() -> void:
		_emit("CharacterMovementFinished", {"characterId": id, "characterName": entity_name, "x": to.x, "y": to.y}))
	return duration


func _player_attack(target_id: String, damage: int, critical := false) -> void:
	_soulshots -= 1
	_emit("ShotUsed", {"shotType": "SOULSHOT", "grade": "NOGRADE", "remainingQuantity": _soulshots})
	_attack(PLAYER_ID, target_id, damage, critical)


func _monster_attack(attacker_id: String, target_id: String, damage: int) -> void:
	_attack(attacker_id, target_id, damage, false)
	if target_id == MATE_ID:
		_update_mate_vitals()


func _attack(attacker_id: String, target_id: String, damage: int, critical: bool) -> void:
	var hp := maxi(int(_hp[target_id]) - damage, 0)
	_hp[target_id] = hp
	_emit("AttackResult", {"attackerId": attacker_id, "attackerName": _names[attacker_id],
		"targetId": target_id, "targetName": _names[target_id], "hit": true, "damage": damage,
		"critical": critical, "targetCurrentHealth": hp, "attackerHeading": _heading(attacker_id, target_id)})
	if hp <= 0:
		_defeat(target_id)


func _player_skill(skill_name: String, target_id: String, cast_ms: int, damage: int) -> void:
	_emit("SkillCastStarted", {"casterId": PLAYER_ID, "casterName": PLAYER_NAME, "skillName": skill_name,
		"targetId": target_id, "castingTimeMs": cast_ms, "casterHeading": _heading(PLAYER_ID, target_id)})
	_later(cast_ms / 1000.0, func() -> void:
		_mana -= 9
		var hp := maxi(int(_hp[target_id]) - damage, 0)
		_hp[target_id] = hp
		_emit("CastResult", {"skillId": "demo-s1", "skillName": skill_name, "targetId": target_id,
			"targetName": _names[target_id], "hit": true, "amount": damage, "targetCurrentHealth": hp,
			"targetMaxHealth": _max_hp[target_id], "targetDefeated": hp <= 0,
			"casterCurrentMana": _mana, "casterMaxMana": 62})
		if hp <= 0:
			_defeat(target_id))


## Incantation d'un autre personnage (Morwen), chargée d'un spiritshot si `charged` (couronnes
## de runes du cercle, voir CastCircle).
func _cast_other(caster_id: String, skill_name: String, target_id: String, cast_ms: int, charged: bool) -> void:
	if charged:
		_emit("SpiritshotUsed", {"characterId": caster_id})
	_emit("SkillCastStarted", {"casterId": caster_id, "casterName": _names[caster_id], "skillName": skill_name,
		"targetId": target_id, "castingTimeMs": cast_ms, "casterHeading": _heading(caster_id, target_id)})


func _projectile_other(caster_id: String, skill_name: String, target_id: String, travel_sec: float, damage: int) -> void:
	_emit("SkillProjectileLaunched", {"casterId": caster_id, "skillName": skill_name, "targetId": target_id,
		"travelDurationMs": int(travel_sec * 1000.0), "hit": true})
	_later(travel_sec, func() -> void:
		var hp := maxi(int(_hp[target_id]) - damage, 0)
		_hp[target_id] = hp
		_emit("SkillCastAnnounced", {"casterId": caster_id, "casterName": _names[caster_id], "targetId": target_id,
			"skillName": skill_name, "hit": true, "amount": damage, "targetHealthAfter": hp,
			"targetMaxHealth": _max_hp[target_id]})
		if hp <= 0:
			_defeat(target_id))


func _mate_self_heal(amount: int) -> void:
	_hp[MATE_ID] = mini(int(_hp[MATE_ID]) + amount, int(_max_hp[MATE_ID]))
	_emit("SkillCastAnnounced", {"casterId": MATE_ID, "casterName": MATE_NAME, "targetId": MATE_ID,
		"skillName": "Heal", "selfHeal": true, "hit": true, "amount": amount,
		"targetHealthAfter": _hp[MATE_ID], "targetMaxHealth": _max_hp[MATE_ID]})
	_update_mate_vitals()


func _update_mate_vitals() -> void:
	_emit("PartyMemberVitalsUpdated", {"characterId": MATE_ID, "currentHealth": _hp[MATE_ID],
		"maxHealth": _max_hp[MATE_ID], "currentMana": 90, "maxMana": 90})


func _defeat(monster_id: String) -> void:
	_later(0.12, func() -> void:
		_emit("MonsterDefeated", {"monsterId": monster_id, "monsterName": _names[monster_id]})
		_emit("XpGained", {"amount": 64, "xp": GameState.xp + 64,
			"xpForCurrentLevel": GameState.xp_for_current_level, "xpForNextLevel": GameState.xp_for_next_level}))


# ---------------------------------------------------------------------------
# Chemins (A* sur la praticabilité réelle de la carte chargée)
# ---------------------------------------------------------------------------

func _build_astar() -> void:
	var map_root: Node = _game.get_node("World/MapScene")
	var map_instance: Node = null
	for child in map_root.get_children():
		if not child.is_queued_for_deletion():
			map_instance = child
	var grid_map: GridMap = map_instance.get_node("Terrain")
	_map_size = Vector2i.ZERO
	for cell in grid_map.get_used_cells():
		_map_size = Vector2i(maxi(_map_size.x, cell.x + 1), maxi(_map_size.y, cell.z + 1))
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(Vector2i.ZERO, _map_size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	var library := grid_map.mesh_library
	for z in _map_size.y:
		for x in _map_size.x:
			var item := grid_map.get_cell_item(Vector3i(x, 0, z))
			if item == GridMap.INVALID_CELL_ITEM or ZoneAssets3D.BLOCKING_TERRAINS.has(library.get_item_name(item)):
				_astar.set_point_solid(Vector2i(x, z))
	for node in get_tree().get_nodes_in_group(ObstacleFootprint3D.GROUP):
		var footprint := node as ObstacleFootprint3D
		if footprint.blocks_movement and map_instance.is_ancestor_of(footprint):
			for cell in footprint.blocked_cells():
				if _astar.is_in_boundsv(cell):
					_astar.set_point_solid(cell)


## Chemin A* de `from` à `to` (hors point de départ), lissé en lignes droites dès que la ligne
## de vue le permet.
func _find_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var cells := _astar.get_id_path(Vector2i(from.floor()), Vector2i(to.floor()), true)
	var points: Array[Vector2] = [from]
	for i in range(1, cells.size() - 1):
		points.append(Vector2(cells[i]) + Vector2(0.5, 0.5))
	points.append(to)
	var smoothed: Array[Vector2] = []
	var i := 0
	while i < points.size() - 1:
		var j := points.size() - 1
		while j > i + 1 and not _clear_line(points[i], points[j]):
			j -= 1
		smoothed.append(points[j])
		i = j
	return smoothed


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / 0.2)
	for s in steps + 1:
		var p := a.lerp(b, float(s) / maxf(steps, 1))
		# Marge latérale : un personnage n'effleure pas les murs.
		for offset: Vector2 in [Vector2.ZERO, Vector2(0.3, 0.3), Vector2(-0.3, 0.3), Vector2(0.3, -0.3), Vector2(-0.3, -0.3)]:
			var cell := Vector2i((p + offset).floor())
			if not _astar.is_in_boundsv(cell) or _astar.is_point_solid(cell):
				return false
	return true


func _waypoints(path: Array[Vector2]) -> Array:
	var result := []
	for p in path:
		result.append({"x": p.x, "y": p.y})
	return result


func _path_length(from: Vector2, path: Array[Vector2]) -> float:
	var length := 0.0
	var prev := from
	for p in path:
		length += prev.distance_to(p)
		prev = p
	return length


func _pos_of(id: String) -> Vector2:
	var key: String = _game._key_for_entity_id(id)
	var pos: Vector3 = _game._logical_position(key)
	return Vector2(pos.x, pos.z)


## Cap serveur (radians, plan x/y) de `from_id` vers `to_id`.
func _heading(from_id: String, to_id: String) -> float:
	var d := _pos_of(to_id) - _pos_of(from_id)
	return atan2(d.y, d.x)


# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _later(sec: float, callback: Callable) -> void:
	var epoch := _map_epoch
	get_tree().create_timer(sec).timeout.connect(func() -> void:
		if epoch == _map_epoch:
			callback.call())


## Zoom caméra (taille orthographique, voir Game3D._zoom_camera), en douceur.
func _zoom_to(size: float, duration: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(v: float) -> void: _game._zoom_camera(v - float(_game._camera_size)),
		float(_game._camera_size), size, duration)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Dimensions de la carte lues sur le GridMap "Terrain" de sa scène (comme UIPreview._map_size).
func _scene_size(map_name: String) -> Vector2i:
	var packed: PackedScene = _oree_packed if map_name == OREE else load(ZoneAssets3D.get_map_scene_path(map_name))
	# Hors de l'arbre : pas de _ready, donc pas de végétation construite pour rien.
	var instance: Node = packed.instantiate()
	var grid_map := instance.get_node_or_null("Terrain") as GridMap
	var result := Vector2i(40, 40)
	if grid_map != null and not grid_map.get_used_cells().is_empty():
		result = Vector2i.ZERO
		for cell in grid_map.get_used_cells():
			result = Vector2i(maxi(result.x, cell.x + 1), maxi(result.y, cell.z + 1))
	instance.free()
	return result


func _restore_hotbar() -> void:
	if _hotbar_existed:
		var f := FileAccess.open(HOTBAR_CFG, FileAccess.WRITE)
		f.store_buffer(_hotbar_backup)
		f.close()
	elif FileAccess.file_exists(HOTBAR_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HOTBAR_CFG))
