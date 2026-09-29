extends HBoxContainer
## Un membre du groupe dans PartyWindow, façon fenêtre de groupe de Lineage 2 : cadre HUD
## (couronne du chef, cartouche de niveau, nom, classe à droite — sous-classe si choisie —,
## jauges PV/PM chiffrées), et à sa droite ses buffs (1re rangée) et
## debuffs (2e rangée) en petites icônes. Un effet qui s'achève clignote pendant ses
## EXPIRING_SEC dernières secondes, comme dans L2 ; son infobulle donne le temps restant.
##
## Aucune logique réseau ici : PartyWindow appelle refresh() à chaque image avec l'entrée de
## GameState.party.members, et relaie `panel_input` (clic = cibler, glisser = déplacer la
## fenêtre, clic droit = menu).

signal panel_input(member_id: String, event: InputEvent)

const ICON_SIZE := 20
const EXPIRING_SEC := 10.0
## Un effet dont PartyMemberEffectExpired n'est jamais arrivé est masqué passé ce délai.
const EXPIRY_GRACE_SEC := 3.0

## Classes de base (app.domain.actor.CharacterClass, mêmes libellés que CharSelect/
## CharacterSheetWindow) et sous-classes (app.domain.actor.Subclass), noms français de L2.
const CLASS_LABELS := {
	"FIGHTER": "Guerrier", "MYSTIC": "Mystique",
	"WARRIOR": "Combattant", "KNIGHT": "Chevalier", "ROGUE": "Voleur", "WIZARD": "Magicien", "CLERIC": "Clerc",
}

@onready var _panel: PanelContainer = %Panel
@onready var _leader_icon: TextureRect = %LeaderIcon
@onready var _level_badge: Control = %LevelBadge
@onready var _level_label: Label = %LevelLabel
@onready var _name_label: Label = %NameLabel
@onready var _class_label: Label = %ClassLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_label: Label = %ManaLabel
@onready var _buff_row: HBoxContainer = %BuffRow
@onready var _debuff_row: HBoxContainer = %DebuffRow

var member_id := ""
## Liste d'effets affichée (noms + nature), pour ne reconstruire les icônes qu'à un
## changement réel.
var _effects_signature := ""
## {skill_name: TextureRect}
var _icons := {}


func _ready() -> void:
	UITheme.style_progress_bar(_health_bar, "hp")
	UITheme.style_progress_bar(_mana_bar, "mp")
	for label in [_health_label, _mana_label]:
		UITheme.style_bar_label(label, 9)
	_leader_icon.texture = IconFactory.ui_icon("crown", 26)
	_leader_icon.tooltip_text = "Chef du groupe"
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("outline_size", 3)
	_panel.gui_input.connect(_on_panel_gui_input)


## `member` : entrée de GameState.party.members ({name, level, character_class, subclass,
## current_health, max_health, current_mana, max_mana, effects}).
func refresh(member: Dictionary, is_leader: bool, selected: bool) -> void:
	var member_name := str(member.get("name", "?"))
	var level := int(member.get("level", 0))
	var class_name_text := class_label(str(member.get("character_class", "")), str(member.get("subclass", "")))
	var current_health := int(member.get("current_health", 0))
	var max_health := int(member.get("max_health", 0))
	var current_mana := int(member.get("current_mana", 0))
	var max_mana := int(member.get("max_mana", 0))
	_name_label.text = member_name
	_leader_icon.visible = is_leader
	# Niveau inconnu (0) : pas de cartouche vide.
	_level_badge.visible = level > 0
	_level_label.text = str(level)
	_class_label.text = class_name_text
	# Membre mort : nom grisé, comme la fenêtre de groupe de L2.
	var dead := max_health > 0 and current_health <= 0
	_name_label.add_theme_color_override("font_color", UITheme.TEXT_DIM if dead else UITheme.TEXT_VALUE)
	_panel.theme_type_variation = &"HudPanelSelected" if selected else &"HudPanel"
	var identity := member_name
	if level > 0:
		identity += " — Niv. %d" % level
	if not class_name_text.is_empty():
		identity += " %s" % class_name_text
	_panel.tooltip_text = "%s\nPV %d / %d — PM %d / %d\nClic : cibler — clic droit : options" % [
		identity, current_health, max_health, current_mana, max_mana,
	]
	_health_bar.max_value = max(max_health, 1)
	_health_bar.value = current_health
	_health_label.text = "%d / %d" % [current_health, max_health]
	_mana_bar.max_value = max(max_mana, 1)
	_mana_bar.value = current_mana
	_mana_label.text = "%d / %d" % [current_mana, max_mana]
	_update_effects(member.get("effects", {}))


## Sous-classe si elle est choisie (c'est la classe courante, comme dans L2), sinon classe de
## base ; "" si inconnue.
static func class_label(character_class: String, subclass: String) -> String:
	var key := subclass if not subclass.is_empty() else character_class
	return CLASS_LABELS.get(key, key.capitalize())


func _update_effects(effects: Dictionary) -> void:
	var now := GameClock.now()
	var shown: Array = []
	for skill_name in effects:
		if float(effects[skill_name].expires_at) + EXPIRY_GRACE_SEC > now:
			shown.append(skill_name)
	var signature := ""
	for skill_name in shown:
		signature += "%s:%s|" % [skill_name, effects[skill_name].beneficial]
	if signature != _effects_signature:
		_effects_signature = signature
		_rebuild_icons(shown, effects)
	for skill_name in _icons:
		var icon: TextureRect = _icons[skill_name]
		var remaining := float(effects[skill_name].expires_at) - now
		icon.modulate.a = _blink_alpha(remaining, now)
		icon.tooltip_text = "%s\n%s — %s" % [
			skill_name, "Bonus" if effects[skill_name].beneficial else "Malus", _format_remaining(remaining),
		]


func _rebuild_icons(shown: Array, effects: Dictionary) -> void:
	for row in [_buff_row, _debuff_row]:
		for child in row.get_children():
			child.queue_free()
	_icons.clear()
	for skill_name in shown:
		var beneficial: bool = effects[skill_name].beneficial
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		icon.texture = IconFactory.slot_icon("skill", skill_name, "BUFF" if beneficial else "DEBUFF", 36)
		(_buff_row if beneficial else _debuff_row).add_child(icon)
		_icons[skill_name] = icon
	_debuff_row.visible = _debuff_row.get_child_count() > 0


## Clignote (≈ 1,5 Hz) pendant les EXPIRING_SEC dernières secondes.
func _blink_alpha(remaining: float, now: float) -> float:
	if remaining > EXPIRING_SEC:
		return 1.0
	return 0.35 + 0.65 * (0.5 + 0.5 * cos(now * TAU * 1.5))


func _format_remaining(remaining: float) -> String:
	var seconds := maxi(0, ceili(remaining))
	if seconds >= 60:
		return "%d min %02d s" % [floori(seconds / 60.0), seconds % 60]
	return "%d s" % seconds


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		panel_input.emit(member_id, event)
		if event is InputEventMouseButton:
			_panel.accept_event()
