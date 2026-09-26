extends WindowFrame
## Fiche de personnage façon fenêtre "Status" Lineage 2 — voir EquipmentWindow pour
## l'équipement porté à slots/drag-and-drop (retiré d'ici le 2026-09-03, jamais réintroduit).
## Réagencée le 2026-09-06 d'après une capture d'écran Lineage 2 fournie explicitement par
## l'utilisateur (cdn.mobygames.com/screenshots/10284168-..., fenêtre "Status" du client
## original) : nom, barres PV (rouge)/mana (bleue)/exp (dorée), puis 3 sections dans le même
## ordre que cette capture — "Combat" (stats physiques/magiques sur deux colonnes), "Basic"
## (STR/DEX/CON puis INT/WIT/MEN sur une grille à 3 colonnes, PAS 2 — la capture montre bien
## les 3 stats "physiques" sur une même ligne, pas appariées avec leur pendant mental comme
## le faisait la version précédente de ce fichier) et "Social" (karma/PvP/PK). N'affiche que
## des champs réellement présents dans GamePlayerStats.Payload côté backend (voir
## mud-server-java/.../GamePlayerStats.java) : pas de Clan/CP/SP/Eval Score/Rec Remaining
## comme sur la capture, ce système de jeu simplifié n'a pas ces concepts — mieux vaut omettre
## une ligne que d'afficher une valeur inventée. "Casting Spd." (castSpd), d'abord omis pour
## cette même raison, a été ajouté côté backend le 2026-09-06 sur demande explicite après
## vérification qu'il n'existait pas encore (voir CombatFormulas.castSpeed()).

const ATTRIBUTE_KEYS := ["strength", "dexterity", "constitution", "intelligence", "wit", "men"]
## Abréviations façon L2 (STR/DEX/CON/INT/WIT/MEN), nom complet en infobulle.
const ATTRIBUTE_SHORT := {
	"strength": "FOR", "dexterity": "DEX", "constitution": "CON",
	"intelligence": "INT", "wit": "SAG", "men": "MEN",
}
const ATTRIBUTE_LABELS := {
	"strength": "Force", "dexterity": "Dextérité", "constitution": "Constitution",
	"intelligence": "Intelligence", "wit": "Sagesse (WIT)", "men": "Mental (MEN)",
}

## Deux colonnes "physique | magique", même groupement que la fenêtre Status de L2 :
## chaque ligne de %CombatGrid = libellé, valeur, libellé, valeur.
const COMBAT_ROWS := [
	["pAtk", "mAtk"], ["pDef", "mDef"], ["accuracy", "evasion"],
	["criticalRate", "speed"], ["atkSpd", "castSpd"],
]
const COMBAT_STAT_LABELS := {
	"pAtk": "P. Atk.", "mAtk": "M. Atk.", "pDef": "P. Déf.", "mDef": "M. Déf.",
	"accuracy": "Précision", "evasion": "Esquive", "criticalRate": "Critique", "atkSpd": "Vit. Atk.",
	"speed": "Vitesse", "castSpd": "Vit. Incant.",
}
## Suffixe "%" uniquement pour le taux critique — les autres stats sont des scores bruts.
const COMBAT_STAT_SUFFIX := {"criticalRate": "%"}

## Karma/PvP/PK (champs karma/pvpCount/pkCount de GamePlayerStats.Payload).
const SOCIAL_KEYS := ["karma", "pvpCount", "pkCount"]
const SOCIAL_LABELS := {"karma": "Karma", "pvpCount": "PvP", "pkCount": "PK"}

const RACE_LABELS := {"HUMAN": "Humain"}
const CLASS_LABELS := {"FIGHTER": "Guerrier", "MYSTIC": "Mystique"}
const GENDER_LABELS := {"man": "Homme", "woman": "Femme", "MALE": "Homme", "FEMALE": "Femme"}

@onready var _level_label: Label = %LevelLabel
@onready var _name_label: Label = %NameLabel
@onready var _player_title_label: Label = %PlayerTitleLabel
@onready var _class_level_label: Label = %ClassLevelLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_label: Label = %ManaLabel
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _exp_label: Label = %ExpLabel
@onready var _combat_grid: GridContainer = %CombatGrid
@onready var _attributes_grid: GridContainer = %AttributesGrid
@onready var _social_grid: GridContainer = %SocialGrid


func _ready() -> void:
	super._ready()
	set_window_title("Statut")
	Net.message_received.connect(_on_message_received)
	UITheme.style_progress_bar(_health_bar, "hp")
	UITheme.style_progress_bar(_mana_bar, "mp")
	UITheme.style_progress_bar(_exp_bar, "exp")
	UITheme.style_bar_label(_health_label, 11)
	UITheme.style_bar_label(_mana_label, 11)
	UITheme.style_bar_label(_exp_label, 9)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_P or get_viewport().gui_get_focus_owner() != null:
		return
	if visible:
		close_window()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	show_window()
	Net.send_command("stats")
	_refresh()


func _on_message_received(type: String, _payload: Dictionary) -> void:
	if not visible:
		return
	match type:
		"GamePlayerStats", "XpGained":
			# XpGained ne renvoie pas de GamePlayerStats : sans ça la jauge d'EXP resterait
			# figée tant que la fenêtre reste ouverte.
			_refresh()
		"ItemEquipped", "ItemUnequipped":
			# equip/unequip ne renvoient pas de GamePlayerStats à jour : on le redemande pour
			# rafraîchir P./M. Atk. et Déf. après un changement d'arme/armure.
			Net.send_command("stats")


func _refresh() -> void:
	var stats: Dictionary = GameState.player_stats
	if stats.is_empty():
		return

	_level_label.text = str(stats.get("level", "?"))
	_name_label.text = str(stats.get("name", ""))
	var title := str(stats.get("title", ""))
	_player_title_label.text = title
	_player_title_label.visible = not title.is_empty()
	var char_class := str(stats.get("characterClass", ""))
	var gender := str(stats.get("gender", ""))
	var race := str(stats.get("race", "HUMAN"))
	_class_level_label.text = "%s · %s · %s" % [
		RACE_LABELS.get(race, race.capitalize()),
		CLASS_LABELS.get(char_class, char_class.capitalize()), GENDER_LABELS.get(gender, gender.capitalize()),
	]

	var current_health := int(stats.get("currentHealth", 0))
	var max_health := int(stats.get("maxHealth", 0))
	_health_bar.max_value = max(max_health, 1)
	_health_bar.value = current_health
	_health_label.text = "%s / %s" % [current_health, max_health]

	var current_mana := int(stats.get("currentMana", 0))
	var max_mana := int(stats.get("maxMana", 0))
	_mana_bar.max_value = max(max_mana, 1)
	_mana_bar.value = current_mana
	_mana_label.text = "%s / %s" % [current_mana, max_mana]

	# xp/xpForCurrentLevel/xpForNextLevel vivent dans GameState (tenus à jour par
	# GamePlayerStats ET XpGained), pas dans `stats`.
	var xp_span := GameState.xp_for_next_level - GameState.xp_for_current_level
	if xp_span <= 0:
		_exp_bar.max_value = 1.0
		_exp_bar.value = 1.0
		_exp_label.text = "100.00%"
	else:
		_exp_bar.max_value = xp_span
		var xp_progress := clampf(GameState.xp - GameState.xp_for_current_level, 0.0, xp_span)
		_exp_bar.value = xp_progress
		_exp_label.text = "%.2f%%" % (xp_progress / xp_span * 100.0)

	_clear(_combat_grid)
	for pair in COMBAT_ROWS:
		for stat_key in pair:
			_add_stat(_combat_grid, COMBAT_STAT_LABELS.get(stat_key, stat_key), _format_stat(stats, stat_key), "")

	# Score brut uniquement (pas de modificateur) : c'est lui qu'utilisent les formules de
	# combat côté backend.
	_clear(_attributes_grid)
	for attr_key in ATTRIBUTE_KEYS:
		var attr = stats.get(attr_key, {})
		var score = attr.get("score", 0) if typeof(attr) == TYPE_DICTIONARY else 0
		_add_stat(_attributes_grid, ATTRIBUTE_SHORT[attr_key], str(score), ATTRIBUTE_LABELS[attr_key])

	_clear(_social_grid)
	for stat_key in SOCIAL_KEYS:
		_add_stat(_social_grid, SOCIAL_LABELS[stat_key], _format_stat(stats, stat_key), "")


func _clear(grid: Container) -> void:
	for child in grid.get_children():
		child.queue_free()


## Ajoute la paire "libellé (tan) / valeur (blanche, alignée à droite)" dans `grid`.
func _add_stat(grid: GridContainer, label_text: String, value_text: String, tooltip: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"StatLabel"
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	grid.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.theme_type_variation = &"StatValue"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.custom_minimum_size = Vector2(34, 0)
	grid.add_child(value)


## `speed` est un double côté backend (unités/seconde) : arrondi comme les autres scores.
func _format_stat(stats: Dictionary, stat_key: String) -> String:
	var value = stats.get(stat_key, 0)
	if typeof(value) == TYPE_FLOAT:
		value = roundi(value)
	return "%s%s" % [value, COMBAT_STAT_SUFFIX.get(stat_key, "")]
