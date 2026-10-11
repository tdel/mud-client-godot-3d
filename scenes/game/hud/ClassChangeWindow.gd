extends WindowFrame
## Fenêtre "Changer de profession" du Grand Master (PNJ backend NpcType SKILL_LEARNER), façon
## changement de classe de Lineage 2 : parcours actuel (Human Mystic → Human Wizard →
## Sorcerer), puis une carte par profession proposée au palier suivant (niveau 20 puis 40)
## avec sa description et un bouton "Choisir" — à confirmer d'un second clic, le choix étant
## définitif.
##
## S'ouvre elle-même sur "ClassChangeOptions" (réponse à "class-list <npcId>", envoyé par
## Game3D depuis le menu du clic droit ou l'option CLASS_CHANGE du dialogue) ; après un
## SubclassChosen, redemande la liste pour afficher le palier suivant.

const ICON_SIZE := Vector2(40, 40)
const SlotPanel := preload("res://scenes/game/hud/SlotPanel.gd")

@onready var _npc_name_label: Label = %NpcNameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _path_label: Label = %PathLabel
@onready var _options_container: VBoxContainer = %OptionsContainer
@onready var _message_label: Label = %MessageLabel
@onready var _footer_label: Label = %FooterLabel

var _npc_id := ""
## Profession en attente de confirmation (second clic sur son bouton).
var _pending_choice := ""


func _ready() -> void:
	super._ready()
	set_window_title("Changer de profession")
	Net.message_received.connect(_on_message_received)


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"ClassChangeOptions":
			_open_with(payload)
		"SubclassChosen":
			if visible:
				_show_message("Vous devenez %s ! De nouvelles compétences vous attendent." % str(payload.get("label", "?")), UITheme.SUCCESS)
				Net.send_command("class-list", _npc_id)
		"InvalidSubclass":
			if visible:
				_show_message("Cette profession ne vous est pas accessible.", UITheme.DANGER)
		"NoPendingSubclassChoice":
			if visible:
				var required = payload.get("requiredLevel")
				_show_message("Niveau %d requis pour changer de profession." % int(required) if required != null else "Vous avez déjà choisi toutes vos professions.", UITheme.DANGER)
		"TargetNotFound":
			if visible and str(payload.get("targetId", "")) == _npc_id:
				close_window()


func _open_with(payload: Dictionary) -> void:
	var npc_id := str(payload.get("npcId", ""))
	if npc_id != _npc_id:
		_clear_message()
	_npc_id = npc_id
	_pending_choice = ""
	_npc_name_label.text = str(payload.get("npcName", "Grand Master"))
	var level := int(payload.get("characterLevel", 0))
	_level_label.text = "Votre niveau : %d" % level
	var path: Array = payload.get("classPath", [])
	_path_label.text = "Parcours : %s" % " → ".join(PackedStringArray(path.map(func(c): return str(c))))
	var required = payload.get("requiredLevel")
	var options: Array = payload.get("options", [])
	if required == null or options.is_empty():
		_footer_label.text = "Vous avez accompli tous les changements de profession."
	elif level < int(required):
		_footer_label.text = "Prochain changement de profession au niveau %d." % int(required)
	else:
		_footer_label.text = "Choisissez votre voie : ce choix est définitif."
	show_window()
	_refresh(options, required == null or level >= int(required))


func _refresh(options: Array, unlocked: bool) -> void:
	for child in _options_container.get_children():
		child.queue_free()
	if options.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Je n'ai plus rien à vous apprendre sur votre voie."
		empty_label.theme_type_variation = &"DimLabel"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.custom_minimum_size = Vector2(320, 0)
		_options_container.add_child(empty_label)
		return
	for option in options:
		_options_container.add_child(_build_card(option, unlocked))


func _build_card(option: Dictionary, unlocked: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"RowPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var slot: Panel = SlotPanel.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = ICON_SIZE + Vector2(4, 4)
	var icon := TextureRect.new()
	icon.position = Vector2(2, 2)
	icon.size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = IconFactory.slot_icon("skill", _emblem_skill(str(option.get("name", ""))))
	slot.add_child(icon)
	row.add_child(slot)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var name_label := Label.new()
	name_label.text = str(option.get("label", option.get("name", "?")))
	name_label.add_theme_color_override("font_color", UITheme.TEXT_VALUE)
	column.add_child(name_label)
	var description := Label.new()
	description.text = str(option.get("description", ""))
	description.theme_type_variation = &"StatLabel"
	description.add_theme_font_size_override("font_size", 11)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(250, 0)
	column.add_child(description)

	var choose := Button.new()
	choose.text = "Choisir"
	choose.custom_minimum_size = Vector2(86, 0)
	choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	choose.focus_mode = Control.FOCUS_NONE
	choose.disabled = not unlocked
	choose.pressed.connect(_on_choose_pressed.bind(str(option.get("name", "")), str(option.get("label", "")), choose))
	row.add_child(choose)
	return card


## Icône représentative de chaque profession : celle d'une compétence emblématique.
static func _emblem_skill(subclass: String) -> String:
	return {
		"WARRIOR": "Wild Sweep", "KNIGHT": "Shield Stun", "ROGUE": "Dash", "WIZARD": "Blaze", "CLERIC": "Resurrection",
		"GLADIATOR": "Triple Slash", "WARLORD": "Whirlwind", "PALADIN": "Divine Blessing",
		"DARK_AVENGER": "Summon Dark Panther", "TREASURE_HUNTER": "Backstab", "HAWKEYE": "Double Shot",
		"SORCERER": "Prominence", "NECROMANCER": "Vampiric Claw", "WARLOCK": "Summon Kat the Cat",
		"BISHOP": "Greater Heal", "PROPHET": "Death Whisper",
	}.get(subclass, "Expertise Grade")


func _on_choose_pressed(subclass: String, label: String, button: Button) -> void:
	if _npc_id.is_empty() or subclass.is_empty():
		return
	if _pending_choice != subclass:
		# Premier clic : demande de confirmation, le choix étant définitif.
		_pending_choice = subclass
		for card in _options_container.get_children():
			var other := card.get_child(0).get_child(2) as Button if card.get_child_count() > 0 else null
			if other != null and other != button:
				other.text = "Choisir"
		button.text = "Confirmer ?"
		_show_message("Devenir %s ? Cliquez de nouveau pour confirmer." % label, UITheme.TEXT_VALUE)
		return
	button.disabled = true
	Net.send_command("choose-subclass", subclass)


func _show_message(message: String, color: Color) -> void:
	_message_label.text = message
	_message_label.add_theme_color_override("font_color", color)
	_message_label.visible = true


func _clear_message() -> void:
	_message_label.text = ""
	_message_label.visible = false
