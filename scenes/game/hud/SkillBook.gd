extends WindowFrame
## Sorts connus par le personnage (appris ou octroyés par un objet équipé), à glisser
## vers un slot de la hotbar. Backend : verbe "skills" / message "KnownSkills". Port
## verbatim du client 2D (mud-godot/scenes/game/hud/SkillBook.gd) — Control pur, aucune
## dépendance au rendu 2D/3D. Rendue déplaçable/fermable via WindowFrame le 2026-09-03 (voir
## ce script pour le pourquoi), seul changement de comportement par rapport au 2D.
##
## Chaque ligne affiche désormais icône + nom (au lieu d'une seule ligne de texte
## "Nom (Niv. X, Dégâts, Y mana, Zs cd)") : demandé explicitement ("pour chaque skill,
## avoir son icone et son nom"), les caractéristiques passent en tooltip sur l'icône
## plutôt qu'affichées en permanence. Seule l'icône (DraggableIcon, pas toute la ligne)
## est la poignée de glisser-déposer vers la hotbar.

const DraggableIcon := preload("res://scenes/game/hud/DraggableIcon.gd")

const EFFECT_LABELS := {
	"DAMAGE": "Dégâts", "HEALING": "Soin", "BUFF": "Bonus", "DEBUFF": "Malus",
}

@onready var _skills_container: VBoxContainer = %SkillsContainer


func _ready() -> void:
	super._ready()
	set_window_title("Sorts connus")
	Net.message_received.connect(_on_message_received)


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


func _refresh() -> void:
	for child in _skills_container.get_children():
		child.queue_free()

	var skills: Array = GameState.known_skills.get("skills", [])
	if skills.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Aucun sort connu."
		_skills_container.add_child(empty_label)
		return

	for skill in skills:
		_skills_container.add_child(_build_row(skill))


func _build_row(skill: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var skill_name := str(skill.get("name", ""))

	var icon := DraggableIcon.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_default_cursor_shape = Control.CURSOR_MOVE
	icon.texture = ZoneAssets3D.make_slot_icon_texture("skill", skill_name)
	icon.drag_kind = "skill"
	icon.drag_ref_id = str(skill.get("id", ""))
	icon.drag_ref_name = skill_name
	icon.drag_preview_text = skill_name
	icon.tooltip_text = _skill_tooltip(skill)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = skill_name
	if skill.get("granted", false):
		name_label.text += " (octroyé)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	return row


## Caractéristiques complètes du sort pour le tooltip de son icône — même contenu que
## Hotbar._skill_tooltip (dupliqué plutôt que partagé, comme EFFECT_LABELS ci-dessus :
## chaque fenêtre HUD reste un Control autonome sans dépendance croisée, voir en-tête).
func _skill_tooltip(skill: Dictionary) -> String:
	var effect := str(skill.get("skillType", ""))
	var lines := PackedStringArray()
	lines.append(str(skill.get("name", "")))
	lines.append("Niveau %s — %s" % [skill.get("level", "?"), EFFECT_LABELS.get(effect, effect)])
	lines.append("Coût : %s mana — Recharge : %ss" % [skill.get("manaCost", 0), skill.get("cooldownSeconds", 0)])
	if int(skill.get("range", 0)) > 0:
		lines.append("Portée : %s" % skill.get("range", 0))
	if int(skill.get("durationSeconds", 0)) > 0:
		lines.append("Durée : %ss" % skill.get("durationSeconds", 0))
	if skill.get("granted", false):
		lines.append("(octroyé par un objet équipé)")
	var description := str(skill.get("description", ""))
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	return "\n".join(lines)
