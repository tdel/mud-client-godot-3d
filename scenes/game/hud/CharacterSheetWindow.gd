extends WindowFrame
## Fiche de personnage : caractéristiques + stats de combat (voir EquipmentWindow pour
## l'équipement porté à slots/drag-and-drop — retiré d'ici le 2026-09-03, demandé
## explicitement pour ne plus dupliquer cette information entre les deux fenêtres). Port
## ~verbatim du client 2D (mud-godot/scenes/game/hud/CharacterSheet.gd), rendue
## déplaçable/fermable via WindowFrame le 2026-09-03 (voir ce script pour le pourquoi).

## Depuis le commit backend "Renomme wisdom/charisma en wit/men", les deux dernières
## caractéristiques DnD5e sont devenues WIT (crit magique) et MEN (mana/résistance mentale).
const ATTRIBUTE_KEYS := ["strength", "dexterity", "constitution", "intelligence", "wit", "men"]
const ATTRIBUTE_LABELS := {
	"strength": "Force", "dexterity": "Dextérité", "constitution": "Constitution",
	"intelligence": "Intelligence", "wit": "Sagesse (WIT)", "men": "Mental (MEN)",
}

@onready var _name_label: Label = %NameLabel
@onready var _class_level_label: Label = %ClassLevelLabel
@onready var _hp_mana_label: Label = %HpManaLabel
@onready var _combat_stats_label: Label = %CombatStatsLabel
@onready var _attributes_container: VBoxContainer = %AttributesContainer


func _ready() -> void:
	super._ready()
	set_window_title("Fiche de personnage")
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
		"GamePlayerStats":
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
	_class_level_label.text = "Niveau %s — %s (%s)" % [
		stats.get("level", "?"), stats.get("characterClass", "?"), stats.get("gender", "?"),
	]
	_hp_mana_label.text = "PV %s/%s    Mana %s/%s" % [
		stats.get("currentHealth", 0), stats.get("maxHealth", 0),
		stats.get("currentMana", 0), stats.get("maxMana", 0),
	]
	# Stats de combat Lineage2 (p.atk/p.def/m.atk/m.def/accuracy/evasion/critique/atk.spd).
	_combat_stats_label.text = (
		"P.Atk %s   P.Def %s   M.Atk %s   M.Def %s\nPrécision %s   Esquive %s   Critique %s%%   Vit.Atk %s"
	) % [
		stats.get("pAtk", 0), stats.get("pDef", 0), stats.get("mAtk", 0), stats.get("mDef", 0),
		stats.get("accuracy", 0), stats.get("evasion", 0), stats.get("criticalRate", 0), stats.get("atkSpd", 0),
	]

	# Score brut uniquement : le modificateur DnD5e (score-10)/2 affiché ici jusqu'au
	# 2026-09-03 était un reliquat de l'ancien système de combat, sans rôle dans les
	# formules Lineage2 actuelles (voir CombatFormulas côté backend, qui consomme le score
	# directement via statBonus()) — retiré à la demande de l'utilisateur ("on n'a plus de
	# modifiers"), plutôt que de garder un nombre qui ne correspond plus à rien en jeu.
	for child in _attributes_container.get_children():
		child.queue_free()
	for attr_key in ATTRIBUTE_KEYS:
		var attr = stats.get(attr_key, {})
		if typeof(attr) != TYPE_DICTIONARY:
			continue
		var score = attr.get("score", 0)
		var row := Label.new()
		row.text = "%s : %s" % [ATTRIBUTE_LABELS.get(attr_key, attr_key.capitalize()), score]
		_attributes_container.add_child(row)
