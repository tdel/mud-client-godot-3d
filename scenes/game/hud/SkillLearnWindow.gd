extends WindowFrame
## Fenêtre "Apprendre des compétences" du maître des compétences (PNJ backend NpcType
## SKILL_LEARNER), façon fenêtre d'apprentissage de Lineage 2 : une ligne par compétence
## apprenable maintenant (icône, nom, niveau connu -> niveau proposé, type), avec son bouton
## "Apprendre", et en pied le niveau du prochain palier.
##
## Comme %ShopWindow, elle s'ouvre elle-même dès qu'un "LearnableSkills" arrive (réponse à
## "skill-list <npcId>", envoyé par Game3D depuis le menu du clic droit ou l'option
## SKILL_LEARN du dialogue) et se met à jour sur chaque nouvelle liste (renvoyée par le
## serveur après chaque "learn-skill"). Un seul niveau à la fois par compétence : le serveur
## propose le suivant dès que le précédent est appris.

const ICON_SIZE := Vector2(34, 34)
const SlotPanel := preload("res://scenes/game/hud/SlotPanel.gd")
const REFUSAL_MESSAGES := {
	"LEVEL_TOO_LOW": "Niveau %d requis.",
	"MAX_LEVEL": "Vous maîtrisez déjà cette compétence.",
	"AUTO_LEARNED": "Cette compétence s'acquiert d'elle-même au niveau %d.",
	"NOT_IN_TREE": "Je ne peux pas vous enseigner cela.",
}

@onready var _npc_name_label: Label = %NpcNameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _skills_container: VBoxContainer = %SkillsContainer
@onready var _message_label: Label = %MessageLabel
@onready var _next_level_label: Label = %NextLevelLabel

var _npc_id := ""


func _ready() -> void:
	super._ready()
	set_window_title("Apprendre des compétences")
	Net.message_received.connect(_on_message_received)


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"LearnableSkills":
			_open_with_list(payload)
		"SkillLearned":
			if visible:
				_show_message("Vous apprenez %s (niv. %s)." % [str(payload.get("skillName", "?")), str(payload.get("level", "?"))], UITheme.SUCCESS)
		"SkillNotLearnable":
			if visible:
				var template: String = REFUSAL_MESSAGES.get(str(payload.get("reason", "")), "Impossible d'apprendre cette compétence.")
				_show_message(template % int(payload.get("requiredLevel", 0)) if template.contains("%d") else template, UITheme.DANGER)
		"TargetNotFound":
			if visible and str(payload.get("targetId", "")) == _npc_id:
				close_window()


func _open_with_list(payload: Dictionary) -> void:
	var npc_id := str(payload.get("npcId", ""))
	if npc_id != _npc_id:
		_clear_message()
	_npc_id = npc_id
	_npc_name_label.text = str(payload.get("npcName", "Maître des compétences"))
	_level_label.text = "Votre niveau : %s" % payload.get("characterLevel", "?")
	var next_level = payload.get("nextLevel")
	var skills: Array = payload.get("skills", [])
	if next_level != null:
		_next_level_label.text = "Prochaines compétences au niveau %d." % int(next_level)
	elif skills.is_empty():
		_next_level_label.text = "Vous avez appris tout ce que je peux vous enseigner pour l'instant."
	else:
		_next_level_label.text = "Aucune autre compétence à venir avant votre changement de classe."
	show_window()
	_refresh(skills)


func _refresh(skills: Array) -> void:
	for child in _skills_container.get_children():
		child.queue_free()
	if skills.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Aucune compétence à apprendre pour le moment."
		empty_label.theme_type_variation = &"DimLabel"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.custom_minimum_size = Vector2(300, 0)
		_skills_container.add_child(empty_label)
		return
	for skill in skills:
		_skills_container.add_child(_build_row(skill))


func _build_row(skill: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"RowPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var skill_name := str(skill.get("name", ""))
	var skill_type := str(skill.get("skillType", ""))
	var current := int(skill.get("currentLevel", 0))
	var level := int(skill.get("level", 1))
	var tooltip := SkillTooltip.build(skill, ["Niveau de personnage requis : %s" % skill.get("requiredLevel", "?")])

	var slot: Panel = SlotPanel.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = ICON_SIZE + Vector2(4, 4)
	slot.tooltip_text = tooltip
	var icon := TextureRect.new()
	icon.position = Vector2(2, 2)
	icon.size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = IconFactory.slot_icon("skill", skill_name, skill_type)
	slot.add_child(icon)
	row.add_child(slot)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var name_label := Label.new()
	name_label.text = skill_name
	name_label.add_theme_color_override("font_color", UITheme.TEXT_VALUE)
	column.add_child(name_label)

	var detail := Label.new()
	var level_text := "Niv. %d" % level if current == 0 else "Niv. %d → %d" % [current, level]
	var parts := PackedStringArray([level_text, SkillTooltip.type_label(skill_type)])
	if int(skill.get("manaCost", 0)) > 0:
		parts.append("%s MP" % skill.get("manaCost", 0))
	detail.text = " · ".join(parts)
	detail.theme_type_variation = &"StatLabel"
	detail.add_theme_font_size_override("font_size", 11)
	column.add_child(detail)

	var learn := Button.new()
	learn.text = "Apprendre" if current == 0 else "Améliorer"
	learn.custom_minimum_size = Vector2(86, 0)
	learn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	learn.focus_mode = Control.FOCUS_NONE
	learn.pressed.connect(_on_learn_pressed.bind(str(skill.get("id", "")), learn))
	row.add_child(learn)
	return card


func _on_learn_pressed(skill_id: String, button: Button) -> void:
	if _npc_id.is_empty() or skill_id.is_empty():
		return
	# Évite un double envoi le temps que la liste à jour revienne du serveur.
	button.disabled = true
	Net.send_command("learn-skill", "%s %s" % [_npc_id, skill_id])


func _show_message(message: String, color: Color) -> void:
	_message_label.text = message
	_message_label.add_theme_color_override("font_color", color)
	_message_label.visible = true


func _clear_message() -> void:
	_message_label.text = ""
	_message_label.visible = false
