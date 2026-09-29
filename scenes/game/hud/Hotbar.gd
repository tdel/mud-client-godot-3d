extends Control
## Barre de compétences (hotbar), toujours visible en jeu. 12 slots (F1-F12) recevant un
## sort ou un objet consommable par glisser-déposer depuis SkillBook. Configuration
## persistée par personnage dans user://hotbar.cfg. Port ~verbatim du client 2D
## (mud-godot/scenes/game/hud/Hotbar.gd), Control pur indépendant du rendu 2D/3D : les deux
## seuls points d'intégration avec la scène de jeu (`game_root.is_player_casting()` et
## `game_root.show_skill_range()/hide_skill_range()`) sont implémentés par Game3D.gd.
##
## Différence assumée avec le 2D : celui-ci n'a plus de case "attaque" par défaut (retirée
## au profit d'une autre affordance, non reprise ici — hors scope de ce prototype) ; pour
## que l'attaque reste utilisable sans étape cachée, ce script préremplit F1 avec
## {kind:"attack"} tant qu'aucune config n'existe encore pour le personnage (voir
## _try_load_config).

const SLOT_COUNT := 12
const SLOT_KEYS := [
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6,
	KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
]
const CONFIG_PATH := "user://hotbar.cfg"

## Types empilés côté backend (ItemType.maxStack() > 1) : compteur affiché même à 1.
const STACKABLE_TYPES := ["SOULSHOT", "SPIRITSHOT", "POTION", "SCROLL"]

@onready var _slots_container: HBoxContainer = %SlotsContainer

## Array[Dictionary], indices 0-11 = F1-F12. {} = vide, sinon {kind, ref_id, ref_name}.
var _slots: Array[Dictionary] = []
var _slot_nodes: Array = []
## Nom du personnage pour lequel la config a déjà été chargée (vide = pas encore chargée).
var _config_loaded_for := ""
## UUID d'objet effectivement envoyé au dernier "use" déclenché par chaque slot "item".
var _last_used_item_id_by_slot: Dictionary = {}


func _ready() -> void:
	Net.message_received.connect(_on_message_received)

	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		_slots[i] = {}
		var slot_node: Control = _slots_container.get_child(i)
		slot_node.setup(i)
		slot_node.slot_drop_requested.connect(_on_slot_drop_requested)
		slot_node.slot_clicked.connect(_on_slot_left_clicked)
		slot_node.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_node.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		slot_node.mouse_exited.connect(_on_slot_mouse_exited.bind(i))
		_slot_nodes.append(slot_node)

	_try_load_config()


func _process(_delta: float) -> void:
	# GamePlayerStats arrive de façon asynchrone après le premier "stats" envoyé par
	# Game3D.gd ; on retente tant qu'on n'a pas encore de nom de personnage pour charger
	# la config qui lui est propre.
	_try_load_config()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var index := SLOT_KEYS.find(event.keycode)
	if index != -1:
		_trigger_slot(index)
		get_viewport().set_input_as_handled()


func get_slot(index: int) -> Dictionary:
	return _slots[index]


## `item_type`/`item_grade` : ItemType/ItemGrade backend ("SOULSHOT"/"NOGRADE", etc.), vides
## pour tout ce qui n'est pas une charge — voir DraggableIcon.drag_item_type/drag_item_grade,
## posés uniquement par InventoryWindow._build_row et propagés ici via
## _on_slot_drop_requested. Persistés dans user://hotbar.cfg comme le reste du dict (voir
## _save_config), donc récupérés tels quels au chargement même après un redémarrage.
func set_slot(index: int, kind: String, ref_id: String, ref_name: String, item_type: String = "", item_grade: String = "") -> void:
	_slots[index] = {
		"kind": kind, "ref_id": ref_id, "ref_name": ref_name,
		"item_type": item_type, "item_grade": item_grade,
	}
	_slot_nodes[index].set_content(kind, ref_name, _build_tooltip(kind, ref_name))
	_save_config()
	_refresh_mana_affordability()
	_refresh_shot_active_states()
	_refresh_item_quantities()


func clear_slot(index: int) -> void:
	_slots[index] = {}
	_slot_nodes[index].clear_content()
	_save_config()


func _trigger_slot(index: int) -> void:
	var slot: Dictionary = _slots[index]
	if slot.is_empty():
		return
	# Attack.java/Cast.java/Use.java rejettent (AlreadyCasting) toute action pendant une
	# incantation en cours : anticipé côté client plutôt que d'attendre l'aller-retour
	# réseau — Game3D.gd (groupe "game_root") est la seule source de vérité pour ce verrou.
	var game_root := get_tree().get_first_node_in_group("game_root")
	if game_root != null and game_root.is_player_casting():
		_slot_nodes[index].flash_error()
		return
	if GameState.is_dead:
		_slot_nodes[index].flash_error()
		return
	match slot.get("kind", ""):
		"attack":
			# Envoyé sans UUID de cible explicite : le serveur résout sur la cible de
			# combat courante (sélectionnée par clic dans Game3D.gd).
			Net.send_command("attack", "")
		"skill":
			# Le cooldown local ne démarre que sur CastResult : un cast peut échouer
			# (NotEnoughMana, NoTargetSelected, ...) et ne doit pas griser le slot.
			var skill_id := _resolve_skill_id(slot)
			if skill_id.is_empty():
				_slot_nodes[index].flash_error()
				return
			Net.send_command("cast", skill_id)
		"item":
			var item_type := str(slot.get("item_type", ""))
			if item_type == "SOULSHOT" or item_type == "SPIRITSHOT":
				# Toggle d'auto-use, pas "use <uuid>" : le serveur bascule lui-même la charge
				# active (renvoyer la même grade l'éteint, voir Soulshot.java/Spiritshot.java
				# côté backend) — aucune résolution d'UUID d'instance nécessaire ici,
				# contrairement à un objet consommable classique juste en dessous.
				Net.send_command(item_type.to_lower(), str(slot.get("item_grade", "NOGRADE")).to_lower())
				return
			var item_id := _resolve_item_id(str(slot.get("ref_name", "")))
			if item_id.is_empty():
				_slot_nodes[index].flash_error()
				return
			_last_used_item_id_by_slot[index] = item_id
			Net.send_command("use", item_id)


## Soulshot/spiritshot = objet "toggle" façon L2 : il ne s'active qu'au clic droit (voir
## _on_slot_right_clicked), le clic gauche ne fait rien. La touche F1-F12 le bascule toujours.
func _on_slot_left_clicked(index: int) -> void:
	if _is_shot_slot(_slots[index]):
		return
	_trigger_slot(index)


## Clic droit = utiliser, comme dans l'inventaire : bascule d'une charge, ou consommation d'un
## objet (potion, Scroll of Escape...). Sans effet sur un sort ou l'attaque.
func _on_slot_right_clicked(index: int) -> void:
	if str(_slots[index].get("kind", "")) == "item":
		_trigger_slot(index)


func _is_shot_slot(slot: Dictionary) -> bool:
	return str(slot.get("item_type", "")) in ["SOULSHOT", "SPIRITSHOT"]


## UUID du sort à envoyer à "cast" : celui déjà connu du slot (cas normal, voir set_slot),
## sinon résolu par nom dans les sorts actuellement connus.
func _resolve_skill_id(slot: Dictionary) -> String:
	var ref_id := str(slot.get("ref_id", ""))
	if not ref_id.is_empty():
		return ref_id
	var ref_name := str(slot.get("ref_name", ""))
	for entry in GameState.known_skills.get("skills", []):
		if str(entry.get("name", "")) == ref_name:
			return str(entry.get("id", ""))
	return ""


## UUID de l'objet à envoyer à "use", résolu dynamiquement par nom dans l'inventaire
## courant : contrairement à un sort, l'UUID d'un objet est celui d'une instance précise —
## il change à chaque potion consommée, donc jamais persisté dans le slot.
func _resolve_item_id(item_name: String) -> String:
	for entry in GameState.inventory.get("items", []):
		if str(entry.get("name", "")) == item_name:
			return str(entry.get("id", ""))
	return ""


func _on_slot_drop_requested(
	index: int, kind: String, ref_id: String, ref_name: String, item_type: String, item_grade: String
) -> void:
	set_slot(index, kind, ref_id, ref_name, item_type, item_grade)


## Estimation immédiate sur CastResult/SkillModifierAnnounced (voir _on_message_received),
## sans attendre SkillOnCooldown — cooldownSeconds vient du catalogue KnownSkills, pas d'un
## calcul serveur en direct, donc peut légèrement dévier d'un effet qui modifie la recharge ;
## corrigée par SkillOnCooldown s'il arrive.
func _start_skill_cooldown(index: int, skill_name: String) -> void:
	# Recharge déjà lancée (SkillOnCooldown reçu dès la fin de l'incantation, avant ce
	# CastResult qui n'arrive qu'à l'impact du projectile) : l'estimation la décalerait.
	if _slot_nodes[index].is_cooling_down():
		return
	for entry in GameState.known_skills.get("skills", []):
		if str(entry.get("name", "")) == skill_name:
			var cooldown_seconds := int(entry.get("cooldownSeconds", 0))
			_slot_nodes[index].set_cooldown_overlay(cooldown_seconds * 1000.0)
			return


## Estimation immédiate sur AttackResult (voir _on_message_received), sans attendre
## AttackOnCooldown — calculée depuis `atkSpd` (GamePlayerStats) avec la même formule que le
## serveur (500000/atkSpd ms, voir mud-godot/CLAUDE.md — commit backend "atk.spd Lineage2 +
## recalibrage des vitesses") ; corrigée par AttackOnCooldown s'il arrive.
func _start_attack_cooldown(index: int) -> void:
	if _slot_nodes[index].is_cooling_down():
		return
	var atk_spd := float(GameState.player_stats.get("atkSpd", 0))
	if atk_spd <= 0.0:
		return
	_slot_nodes[index].set_cooldown_overlay(500000.0 / atk_spd)


## Infobulle BBCode (voir UITheme.make_rich_tooltip) : caractéristiques du sort, ou de
## l'objet s'il est encore dans l'inventaire.
func _build_tooltip(kind: String, ref_name: String) -> String:
	if kind == "item":
		for item in GameState.inventory.get("items", []):
			if str(item.get("name", "")) == ref_name:
				if str(item.get("type", "")) in ["SOULSHOT", "SPIRITSHOT"]:
					return ItemTooltip.build(item, ["Clic droit : activer / désactiver l'auto-use"])
				return ItemTooltip.build(item)
		return ""
	if kind != "skill":
		return ""
	for entry in GameState.known_skills.get("skills", []):
		if str(entry.get("name", "")) == ref_name:
			return _skill_tooltip(entry)
	return ""


func _skill_tooltip(skill: Dictionary) -> String:
	return SkillTooltip.build(skill)


## KnownSkills peut arriver après que des slots aient déjà été chargés depuis
## user://hotbar.cfg : leur infobulle serait alors restée vide faute de données.
func _refresh_skill_tooltips() -> void:
	for i in SLOT_COUNT:
		var slot: Dictionary = _slots[i]
		var ref_name: String = slot.get("ref_name", "")
		if slot.get("kind", "") == "skill":
			_slot_nodes[i].set_content("skill", ref_name, _build_tooltip("skill", ref_name))


## Grise l'icône de chaque slot "skill" dont le coût en mana dépasse la mana courante.
func _refresh_mana_affordability() -> void:
	for i in SLOT_COUNT:
		var slot: Dictionary = _slots[i]
		if slot.get("kind", "") != "skill":
			continue
		var cost := _skill_mana_cost(str(slot.get("ref_name", "")))
		_slot_nodes[i].set_insufficient_mana(cost > GameState.current_mana)


## Surligne (voir HotbarSlot.set_active) chaque slot "item" de soulshot/spiritshot dont la
## grade correspond à celle actuellement armée en auto-use (GameState.active_soulshot_grade/
## active_spiritshot_grade) — appelé après tout changement de contenu de slot et sur les
## messages réseau qui font varier ces deux champs (voir _on_message_received).
func _refresh_shot_active_states() -> void:
	for i in SLOT_COUNT:
		var slot: Dictionary = _slots[i]
		var item_type := str(slot.get("item_type", ""))
		if item_type == "SOULSHOT" or item_type == "SPIRITSHOT":
			_slot_nodes[i].set_active(_is_shot_active(item_type, str(slot.get("item_grade", ""))), item_type)


## Compteur de chaque slot "item" : somme des quantités de toutes les entrées d'inventaire du
## même nom (les potions se répartissent en piles de 100, voir GameState.inventory). Affiché
## pour un objet stackable ou possédé en plusieurs exemplaires ; un objet unique non stackable
## (clé...) n'en a pas. Tant qu'aucun Inventory n'est arrivé, rien n'est grisé.
func _refresh_item_quantities() -> void:
	var inventory_known := GameState.inventory.has("items")
	for i in SLOT_COUNT:
		var slot: Dictionary = _slots[i]
		if slot.get("kind", "") != "item":
			continue
		var ref_name := str(slot.get("ref_name", ""))
		var total := 0
		var stackable := str(slot.get("item_type", "")) in STACKABLE_TYPES
		for entry in GameState.inventory.get("items", []):
			if str(entry.get("name", "")) != ref_name:
				continue
			var entry_slot = entry.get("slot")
			if entry_slot != null and not str(entry_slot).is_empty():
				continue
			total += int(entry.get("quantity", 1))
			stackable = stackable or str(entry.get("type", "")) in STACKABLE_TYPES
		if not inventory_known:
			_slot_nodes[i].set_quantity(-1)
		elif total == 0:
			_slot_nodes[i].set_quantity(0)
		else:
			_slot_nodes[i].set_quantity(total if stackable or total > 1 else -1)


## Dupliqué à l'identique dans InventoryWindow.gd (même convention que le reste du HUD, voir
## CLAUDE.md : chaque fenêtre reste un Control autonome sans dépendance croisée).
func _is_shot_active(item_type: String, item_grade: String) -> bool:
	var active_grade := GameState.active_soulshot_grade if item_type == "SOULSHOT" else GameState.active_spiritshot_grade
	return not active_grade.is_empty() and active_grade == item_grade


func _skill_mana_cost(skill_name: String) -> int:
	for entry in GameState.known_skills.get("skills", []):
		if str(entry.get("name", "")) == skill_name:
			return int(entry.get("manaCost", 0))
	return 0


func _skill_range(skill_name: String) -> float:
	for entry in GameState.known_skills.get("skills", []):
		if str(entry.get("name", "")) == skill_name:
			return float(entry.get("range", 0))
	return 0.0


## Affiche le cercle de portée autour du joueur (voir Game3D.show_skill_range) tant que la
## souris survole un slot "skill" — pas de portée connue côté client pour "attack"/"item".
func _on_slot_mouse_entered(index: int) -> void:
	var slot: Dictionary = _slots[index]
	if slot.get("kind", "") != "skill":
		return
	var range_tiles := _skill_range(str(slot.get("ref_name", "")))
	if range_tiles <= 0.0:
		return
	var game_root := get_tree().get_first_node_in_group("game_root")
	if game_root != null:
		game_root.show_skill_range(range_tiles)


func _on_slot_mouse_exited(index: int) -> void:
	var slot: Dictionary = _slots[index]
	if slot.get("kind", "") != "skill":
		return
	var game_root := get_tree().get_first_node_in_group("game_root")
	if game_root != null:
		game_root.hide_skill_range()


func _find_slot_index(kind: String, ref_name: String) -> int:
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		if slot.get("kind", "") == kind and slot.get("ref_name", "") == ref_name:
			return i
	return -1


## Retrouve un slot "skill" par UUID (quand disponible) ou par nom en repli (seul moyen
## pour SkillOnCooldown, qui ne porte que le nom).
func _find_skill_slot_index(skill_id: String, skill_name: String) -> int:
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		if slot.get("kind", "") != "skill":
			continue
		var ref_id: String = slot.get("ref_id", "")
		if not skill_id.is_empty() and not ref_id.is_empty() and ref_id == skill_id:
			return i
		if not skill_name.is_empty() and slot.get("ref_name", "") == skill_name:
			return i
	return -1


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"KnownSkills":
			_refresh_skill_tooltips()
			_refresh_mana_affordability()
		"GamePlayerStats", "RegenTick", "ManaPotionUsed":
			_refresh_mana_affordability()
			if type == "GamePlayerStats":
				_refresh_shot_active_states()
			elif type == "ManaPotionUsed":
				_refresh_item_quantities()
		"ShotGradeChanged", "ShotOutOfStock":
			_refresh_shot_active_states()
		"Inventory", "ItemUsed", "ShotUsed", "ScrollUsed":
			# GameState (autoload, abonné avant ce script) a déjà appliqué le message.
			_refresh_item_quantities()
		"ItemOnCooldown":
			# Délai de réutilisation d'un objet (Scroll of Escape) : même voile que la recharge
			# d'un sort, sur chaque slot portant cet objet.
			var item_name := str(payload.get("name", ""))
			for i in SLOT_COUNT:
				if _slots[i].get("kind", "") == "item" and str(_slots[i].get("ref_name", "")) == item_name:
					_slot_nodes[i].set_cooldown_overlay(float(payload.get("remainingMillis", 0)))
					if bool(payload.get("rejected", false)):
						_slot_nodes[i].flash_error()
		"CastResult":
			# Démarre une estimation immédiate (cooldownSeconds du catalogue) sans attendre
			# SkillOnCooldown : malgré l'évolution backend du 2026-09-02 (documentée plus bas)
			# qui était censée le rendre systématique, l'aiguille ne s'affichait toujours pas
			# en pratique en jeu (signalé le 2026-09-02, deuxième passe) — gardée comme filet de
			# sécurité, SkillOnCooldown corrige avec la vraie valeur serveur s'il arrive bien.
			var index := _find_skill_slot_index(
				str(payload.get("skillId", "")), str(payload.get("skillName", ""))
			)
			if index != -1:
				_start_skill_cooldown(index, str(payload.get("skillName", "")))
			_refresh_mana_affordability()
		"SkillModifierAnnounced":
			if str(payload.get("casterId", "")) == str(GameState.player_stats.get("id", "")):
				var buff_index := _find_skill_slot_index(
					str(payload.get("skillId", "")), str(payload.get("skillName", ""))
				)
				if buff_index != -1:
					_start_skill_cooldown(buff_index, str(payload.get("skillName", "")))
				_refresh_mana_affordability()
		"AttackResult":
			# Même filet de sécurité que CastResult ci-dessus, côté attaque de base : estimation
			# immédiate depuis atkSpd (GamePlayerStats), corrigée par AttackOnCooldown s'il
			# arrive avec la vraie valeur serveur.
			if str(payload.get("attackerId", "")) == str(GameState.player_stats.get("id", "")):
				var attack_index := _find_slot_index("attack", "")
				if attack_index != -1:
					_start_attack_cooldown(attack_index)
		# Le serveur est censé, depuis une évolution backend du 2026-09-02, renvoyer
		# systématiquement AttackOnCooldown/SkillOnCooldown (remainingMillis) en réponse à une
		# attaque/un cast qui vient d'être accepté, pas seulement en cas de refus (retentative
		# trop précoce) comme avant — en pratique pas observé en jeu (aiguille toujours absente,
		# signalé le 2026-09-02), donc traité comme une correction d'appoint plutôt que l'unique
		# source de vérité : voir _start_skill_cooldown/_start_attack_cooldown ci-dessus.
		"AttackOnCooldown":
			var index := _find_slot_index("attack", "")
			if index != -1:
				_slot_nodes[index].set_cooldown_overlay(float(payload.get("remainingMillis", 0)))
				if bool(payload.get("rejected", false)):
					_slot_nodes[index].flash_error()
		"SkillOnCooldown":
			var index := _find_skill_slot_index("", str(payload.get("skillName", "")))
			if index != -1:
				_slot_nodes[index].set_cooldown_overlay(float(payload.get("remainingMillis", 0)))
				# rejected : relance refusée car encore en recharge (sinon : recharge qui démarre).
				if bool(payload.get("rejected", false)):
					_slot_nodes[index].flash_error()
		"ItemNotCarried":
			var item_id := str(payload.get("itemId", ""))
			for i in SLOT_COUNT:
				if _slots[i].get("kind", "") == "item" and _last_used_item_id_by_slot.get(i, "") == item_id:
					_slot_nodes[i].flash_error()
					break
		"ItemNotUsable", "HealthAlreadyFull", "ManaAlreadyFull":
			var index := _find_slot_index("item", str(payload.get("name", "")))
			if index != -1:
				_slot_nodes[index].flash_error()
		"SkillNotKnown":
			var index := _find_skill_slot_index(str(payload.get("skillId", "")), "")
			if index != -1:
				_slot_nodes[index].flash_error()


func _try_load_config() -> void:
	var character_name := str(GameState.player_stats.get("name", ""))
	if character_name.is_empty() or character_name == _config_loaded_for:
		return
	_config_loaded_for = character_name
	set_process(false)

	var config := ConfigFile.new()
	var loaded_ok := config.load(CONFIG_PATH) == OK
	if not loaded_ok or not config.has_section(character_name):
		# Premier lancement pour ce personnage (pas de config sauvegardée) : préremplit F1
		# avec l'attaque de base pour qu'elle soit utilisable sans étape cachée (voir
		# en-tête de fichier).
		set_slot(0, "attack", "", "Attaque")
		return
	for i in SLOT_COUNT:
		var saved = config.get_value(character_name, "slot_%d" % i, {})
		if typeof(saved) == TYPE_DICTIONARY and saved.has("kind") and saved.has("ref_name"):
			set_slot(
				i, saved["kind"], str(saved.get("ref_id", "")), saved["ref_name"],
				str(saved.get("item_type", "")), str(saved.get("item_grade", "")),
			)


func _save_config() -> void:
	if _config_loaded_for.is_empty():
		return
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	for i in SLOT_COUNT:
		config.set_value(_config_loaded_for, "slot_%d" % i, _slots[i])
	config.save(CONFIG_PATH)
