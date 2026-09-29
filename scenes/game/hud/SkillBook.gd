extends WindowFrame
## Fenêtre "Compétences" (touche K) façon Lineage 2 : onglets de filtre (Toutes / Attaque /
## Soutien / Passives), puis une ligne par compétence connue — icône dans un slot, nom, et en dessous
## "Niv. X · effet · coût". Seule l'icône (DraggableIcon) est la poignée de glisser-déposer
## vers la barre de raccourcis (sauf pour une passive, toujours active, qui ne se lance
## pas) ; les caractéristiques complètes passent en infobulle (SkillTooltip).
## Backend : verbe "skills" / message "KnownSkills".

const DraggableIcon := preload("res://scenes/game/hud/DraggableIcon.gd")

## Onglets : [libellé, types de compétence affichés (vide = tous)].
const TABS := [
	["Toutes", []],
	["Attaque", ["DAMAGE", "DEBUFF"]],
	["Soutien", ["HEALING", "BUFF", "CURE"]],
	["Passives", ["PASSIVE"]],
]
const SlotPanel := preload("res://scenes/game/hud/SlotPanel.gd")
const ICON_SIZE := Vector2(36, 36)

@onready var _skills_container: VBoxContainer = %SkillsContainer
@onready var _tab_row: HBoxContainer = %TabRow

var _current_tab := 0


func _ready() -> void:
	super._ready()
	set_window_title("Compétences")
	Net.message_received.connect(_on_message_received)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tab := Button.new()
		tab.text = TABS[i][0]
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = i == 0
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_on_tab_pressed.bind(i))
		_tab_row.add_child(tab)


## Bascule (ouvre/ferme) la fenêtre, sauf si un champ de texte a le focus (ex. chat).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_K or get_viewport().gui_get_focus_owner() != null:
		return
	if visible:
		close_window()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	show_window()
	Net.send_command("skills")
	_refresh()


func _on_message_received(type: String, _payload: Dictionary) -> void:
	if visible and type == "KnownSkills":
		_refresh()


func _on_tab_pressed(index: int) -> void:
	_current_tab = index
	_refresh()


func _refresh() -> void:
	for child in _skills_container.get_children():
		child.queue_free()

	var filter: Array = TABS[_current_tab][1]
	var shown := 0
	for skill in GameState.known_skills.get("skills", []):
		if filter.is_empty() or str(skill.get("skillType", "")) in filter:
			_skills_container.add_child(_build_row(skill))
			shown += 1
	if shown == 0:
		var empty_label := Label.new()
		empty_label.text = "Aucune compétence."
		empty_label.theme_type_variation = &"DimLabel"
		_skills_container.add_child(empty_label)


func _build_row(skill: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"RowPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var skill_name := str(skill.get("name", ""))
	var effect := str(skill.get("skillType", ""))

	var passive := effect == "PASSIVE"
	var slot: Panel = SlotPanel.new() if passive else Panel.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = ICON_SIZE + Vector2(4, 4)
	var icon: TextureRect
	if passive:
		# Toujours active : rien à glisser sur la barre de raccourcis.
		icon = TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.tooltip_text = SkillTooltip.build(skill)
	else:
		var draggable := DraggableIcon.new()
		draggable.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		draggable.drag_kind = "skill"
		draggable.drag_ref_id = str(skill.get("id", ""))
		draggable.drag_ref_name = skill_name
		draggable.drag_preview_text = skill_name
		draggable.tooltip_text = SkillTooltip.build(skill, ["Glisser sur la barre de raccourcis pour l'utiliser."])
		icon = draggable
	icon.position = Vector2(2, 2)
	icon.size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture = IconFactory.slot_icon("skill", skill_name, effect)
	icon.custom_minimum_size = ICON_SIZE
	slot.add_child(icon)
	row.add_child(slot)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)

	var name_label := Label.new()
	name_label.text = skill_name
	name_label.add_theme_color_override("font_color", UITheme.TEXT_VALUE)
	column.add_child(name_label)

	var detail := Label.new()
	var parts := PackedStringArray(["Niv. %s" % skill.get("level", "?"), SkillTooltip.type_label(effect)])
	if int(skill.get("manaCost", 0)) > 0:
		parts.append("%s MP" % skill.get("manaCost", 0))
	if skill.get("granted", false):
		parts.append("octroyée")
	detail.text = " · ".join(parts)
	detail.theme_type_variation = &"StatLabel"
	detail.add_theme_font_size_override("font_size", 11)
	column.add_child(detail)

	return card
