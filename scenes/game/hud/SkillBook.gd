extends WindowFrame
## Fenêtre "Compétences" (touche K) façon Lineage 2 : onglets de filtre (Toutes / Attaque /
## Soutien), puis une ligne par sort connu — icône dans un slot, nom, et en dessous
## "Niv. X · effet · coût". Seule l'icône (DraggableIcon) est la poignée de glisser-déposer
## vers la barre de raccourcis ; les caractéristiques complètes passent en infobulle.
## Backend : verbe "skills" / message "KnownSkills".

const DraggableIcon := preload("res://scenes/game/hud/DraggableIcon.gd")

const EFFECT_LABELS := {
	"DAMAGE": "Dégâts", "HEALING": "Soin", "BUFF": "Bonus", "DEBUFF": "Malus",
}
## Onglets : [libellé, types de sort affichés (vide = tous)].
const TABS := [
	["Toutes", []],
	["Attaque", ["DAMAGE", "DEBUFF"]],
	["Soutien", ["HEALING", "BUFF"]],
]
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

	var slot := Panel.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = ICON_SIZE + Vector2(4, 4)
	var icon := DraggableIcon.new()
	icon.position = Vector2(2, 2)
	icon.size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon.texture = IconFactory.slot_icon("skill", skill_name, effect)
	icon.drag_kind = "skill"
	icon.drag_ref_id = str(skill.get("id", ""))
	icon.drag_ref_name = skill_name
	icon.drag_preview_text = skill_name
	icon.custom_minimum_size = ICON_SIZE
	icon.tooltip_text = _skill_tooltip(skill)
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
	var parts := PackedStringArray(["Niv. %s" % skill.get("level", "?"), EFFECT_LABELS.get(effect, effect)])
	if int(skill.get("manaCost", 0)) > 0:
		parts.append("%s MP" % skill.get("manaCost", 0))
	if skill.get("granted", false):
		parts.append("octroyée")
	detail.text = " · ".join(parts)
	detail.theme_type_variation = &"StatLabel"
	detail.add_theme_font_size_override("font_size", 11)
	column.add_child(detail)

	return card


## Caractéristiques complètes du sort, en BBCode (voir UITheme.make_rich_tooltip).
func _skill_tooltip(skill: Dictionary) -> String:
	var effect := str(skill.get("skillType", ""))
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  [color=#%s]Niv. %s[/color]" % [skill.get("name", ""), UITheme.TEXT_LABEL.to_html(false), skill.get("level", "?")])
	lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), EFFECT_LABELS.get(effect, effect)])
	lines.append(UITheme.tooltip_stat("MP consommés :", str(skill.get("manaCost", 0))))
	lines.append(UITheme.tooltip_stat("Recharge :", "%s s" % skill.get("cooldownSeconds", 0)))
	if int(skill.get("range", 0)) > 0:
		lines.append(UITheme.tooltip_stat("Portée :", str(skill.get("range", 0))))
	if int(skill.get("durationSeconds", 0)) > 0:
		lines.append(UITheme.tooltip_stat("Durée :", "%s s" % skill.get("durationSeconds", 0)))
	var description := str(skill.get("description", ""))
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	if skill.get("granted", false):
		lines.append("")
		lines.append("[color=#%s]Octroyée par un objet équipé.[/color]" % UITheme.TEXT_DIM.to_html(false))
	return "\n".join(lines)
