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
const ATTRIBUTE_LABELS := {
	"strength": "Force", "dexterity": "Dextérité", "constitution": "Constitution",
	"intelligence": "Intelligence", "wit": "Sagesse (WIT)", "men": "Mental (MEN)",
}

## Colonnes de %CombatColumns (voir CharacterSheetWindow.tscn) : gauche physique, droite
## magique — même groupement que l'écran de statut Lineage 2 d'origine. "Vitesse" (mouvement,
## champ `speed` de GamePlayerStats.Payload, jusqu'ici jamais affiché dans aucune fenêtre du
## HUD) comble la 4e ligne de droite ; "Vit.Incant" (`castSpd`, ajouté côté backend le
## 2026-09-06 — voir CombatFormulas.castSpeed()/ModifiedStat.CASTSPD, dérivé de WIT comme
## m.crit, façon L2J : durée d'incantation réelle = durée d'auteur du sort *
## BASE_CAST_SPD/castSpd, voir SkillCastEngine.beginCast côté backend) comble la 5e.
const COMBAT_LEFT_KEYS := ["pAtk", "pDef", "accuracy", "criticalRate", "atkSpd"]
const COMBAT_RIGHT_KEYS := ["mAtk", "mDef", "evasion", "speed", "castSpd"]
const COMBAT_STAT_LABELS := {
	"pAtk": "P.Atk", "mAtk": "M.Atk", "pDef": "P.Def", "mDef": "M.Def",
	"accuracy": "Précision", "evasion": "Esquive", "criticalRate": "Critique", "atkSpd": "Vit.Atk",
	"speed": "Vitesse", "castSpd": "Vit.Incant",
}
## Suffixe "%" uniquement pour le taux critique — les autres stats de combat sont des scores
## bruts (voir CombatFormulas côté backend).
const COMBAT_STAT_SUFFIX := {"criticalRate": "%"}

## %SocialGrid : karma/PvP/PK (champs karma/pvpCount/pkCount de GamePlayerStats.Payload) — pas
## de "Clan"/"Eval Score"/"Rec Remaining" comme sur la capture Lineage 2, absents du backend.
const SOCIAL_KEYS := ["karma", "pvpCount", "pkCount"]
const SOCIAL_LABELS := {"karma": "Karma", "pvpCount": "PvP", "pkCount": "PK"}

@onready var _name_label: Label = %NameLabel
@onready var _player_title_label: Label = %PlayerTitleLabel
@onready var _class_level_label: Label = %ClassLevelLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_label: Label = %ManaLabel
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _exp_label: Label = %ExpLabel
@onready var _combat_left_column: VBoxContainer = %CombatLeftColumn
@onready var _combat_right_column: VBoxContainer = %CombatRightColumn
@onready var _attributes_grid: GridContainer = %AttributesGrid
@onready var _social_grid: GridContainer = %SocialGrid


func _ready() -> void:
	super._ready()
	set_window_title("Statut")
	Net.message_received.connect(_on_message_received)


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
			# XpGained (voir GameState.gd) ne renvoie pas lui-même un GamePlayerStats — sans
			# réagir aussi à ce message, %ExpBar resterait figée jusqu'à la prochaine
			# ouverture de cette fenêtre après un gain d'XP survenu pendant qu'elle est ouverte.
			_refresh()
		"ItemEquipped", "ItemUnequipped":
			# equip/unequip ne renvoient pas eux-mêmes de GamePlayerStats à jour (voir
			# app.network.command.ingame.Equip/Unequip côté backend) — sans ce redemande
			# explicite, p.atk/p.def/m.atk/m.def resteraient figés sur les valeurs d'avant
			# le changement d'arme/armure tant que cette fenêtre reste ouverte.
			Net.send_command("stats")


func _refresh() -> void:
	var stats: Dictionary = GameState.player_stats
	if stats.is_empty():
		return

	_name_label.text = str(stats.get("name", ""))
	var title := str(stats.get("title", ""))
	_player_title_label.text = title
	_player_title_label.visible = not title.is_empty()
	_class_level_label.text = "Niveau %s — %s (%s)" % [
		stats.get("level", "?"), stats.get("characterClass", "?"), stats.get("gender", "?"),
	]

	var current_health := int(stats.get("currentHealth", 0))
	var max_health := int(stats.get("maxHealth", 0))
	_health_bar.max_value = max(max_health, 1)
	_health_bar.value = current_health
	_health_label.text = "PV %s/%s" % [current_health, max_health]

	var current_mana := int(stats.get("currentMana", 0))
	var max_mana := int(stats.get("maxMana", 0))
	_mana_bar.max_value = max(max_mana, 1)
	_mana_bar.value = current_mana
	_mana_label.text = "Mana %s/%s" % [current_mana, max_mana]

	# xp/xpForCurrentLevel/xpForNextLevel vivent dans GameState (voir PlayerFrame.set_xp, même
	# calcul) plutôt que dans `stats` : GameState les tient à jour aussi bien depuis
	# GamePlayerStats que XpGained, `stats` (dernier GamePlayerStats brut) ne l'est que par le
	# premier.
	var xp_span := GameState.xp_for_next_level - GameState.xp_for_current_level
	if xp_span <= 0:
		_exp_bar.max_value = 1.0
		_exp_bar.value = 1.0
		_exp_label.text = "Exp 100%"
	else:
		_exp_bar.max_value = xp_span
		var xp_progress := clampf(GameState.xp - GameState.xp_for_current_level, 0.0, xp_span)
		_exp_bar.value = xp_progress
		_exp_label.text = "Exp %d%%" % roundi(xp_progress / xp_span * 100.0)

	for child in _combat_left_column.get_children():
		child.queue_free()
	for child in _combat_right_column.get_children():
		child.queue_free()
	_populate_stat_column(_combat_left_column, COMBAT_LEFT_KEYS, stats)
	_populate_stat_column(_combat_right_column, COMBAT_RIGHT_KEYS, stats)

	# Score brut uniquement : le modificateur DnD5e (score-10)/2 affiché ici jusqu'au
	# 2026-09-03 était un reliquat de l'ancien système de combat, sans rôle dans les
	# formules Lineage2 actuelles (voir CombatFormulas côté backend, qui consomme le score
	# directement via statBonus()) — retiré à la demande de l'utilisateur ("on n'a plus de
	# modifiers"), plutôt que de garder un nombre qui ne correspond plus à rien en jeu.
	for child in _attributes_grid.get_children():
		child.queue_free()
	for attr_key in ATTRIBUTE_KEYS:
		var attr = stats.get(attr_key, {})
		if typeof(attr) != TYPE_DICTIONARY:
			continue
		var score = attr.get("score", 0)
		var row := Label.new()
		row.text = "%s : %s" % [ATTRIBUTE_LABELS.get(attr_key, attr_key.capitalize()), score]
		_attributes_grid.add_child(row)

	for child in _social_grid.get_children():
		child.queue_free()
	_populate_stat_column(_social_grid, SOCIAL_KEYS, stats, SOCIAL_LABELS)


## Ajoute une Label "Label : valeur[suffixe]" par clé de `keys` dans `column` — factorisé
## entre %CombatLeftColumn/%CombatRightColumn (COMBAT_STAT_LABELS/COMBAT_STAT_SUFFIX) et
## %SocialGrid (SOCIAL_LABELS, pas de suffixe). `speed` (Vitesse) est un double côté backend
## (unités/seconde, voir MovementEngine.unitsPerSecond) arrondi ici comme les autres scores
## entiers plutôt que d'afficher des décimales qui n'apporteraient rien à la lecture.
func _populate_stat_column(
	column: Container, keys: Array, stats: Dictionary, labels: Dictionary = COMBAT_STAT_LABELS
) -> void:
	for stat_key in keys:
		var row := Label.new()
		var value = stats.get(stat_key, 0)
		if typeof(value) == TYPE_FLOAT:
			value = roundi(value)
		row.text = "%s : %s%s" % [labels.get(stat_key, stat_key), value, COMBAT_STAT_SUFFIX.get(stat_key, "")]
		column.add_child(row)
