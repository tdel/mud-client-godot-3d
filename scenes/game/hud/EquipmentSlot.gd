extends Control
## Un emplacement d'équipement (voir EquipmentWindow), cible de glisser-déposer pour une
## icône d'InventoryWindow. Ce script ignore tout du protocole réseau : EquipmentWindow décide
## quoi envoyer sur item_dropped/unequip_requested. Retrait au clic droit.
##
## Vide, le slot affiche en filigrane le pictogramme du type d'objet attendu (casque, gants,
## anneau...), comme la silhouette d'équipement de Lineage 2.

signal item_dropped(slot_key: String, ref_id: String, ref_name: String)
signal unequip_requested(item_id: String)

const SLOT_LABELS := {
	"WEAPON": "Arme", "OFF_HAND": "Bouclier / main secondaire", "HEAD": "Tête",
	"CHEST": "Torse", "HANDS": "Mains", "LEGS": "Jambes", "FEET": "Pieds",
	"NECKLACE": "Collier", "LEFT_EARRING": "Boucle d'oreille (gauche)",
	"RIGHT_EARRING": "Boucle d'oreille (droite)", "LEFT_RING": "Anneau (gauche)",
	"RIGHT_RING": "Anneau (droite)",
}
## Type d'objet dont le pictogramme sert de filigrane au slot vide.
const SLOT_PLACEHOLDER_TYPES := {
	"WEAPON": "WEAPON", "OFF_HAND": "SHIELD", "HEAD": "HELMET", "CHEST": "ARMOR",
	"HANDS": "GLOVES", "LEGS": "PANTS", "FEET": "BOOTS", "NECKLACE": "NECKLACE",
	"LEFT_EARRING": "EARRING", "RIGHT_EARRING": "EARRING", "LEFT_RING": "RING", "RIGHT_RING": "RING",
}
const PLACEHOLDER_MODULATE := Color(0.55, 0.55, 0.55, 0.22)
## Slot condamné (voir set_blocked) : tout le slot, cadre compris, passe en grisé.
const BLOCKED_MODULATE := Color(0.4, 0.4, 0.4, 0.8)
const BLOCKED_ICON_MODULATE := Color(0.7, 0.7, 0.7, 0.5)

@onready var _background: Panel = $Background
@onready var _icon: TextureRect = %Icon
@onready var _grade_badge_holder: Control = %GradeBadgeHolder

var slot_key := ""
var _item_id := ""
var _blocked := false


func _ready() -> void:
	mouse_entered.connect(func():
		if not _blocked:
			_background.theme_type_variation = &"SlotPanelHover")
	mouse_exited.connect(func(): _background.theme_type_variation = &"SlotPanel")


func setup(key: String) -> void:
	slot_key = key
	clear_item()


## `item` : une entrée telle que reçue dans Inventory.payload.items (voir GameState.inventory).
func set_item(item: Dictionary) -> void:
	_item_id = str(item.get("id", ""))
	_icon.texture = IconFactory.item_icon(item)
	_icon.modulate = Color.WHITE
	_set_grade_badge(str(item.get("grade", "NOGRADE")))
	tooltip_text = "%s\n%s" % [
		"[color=#%s]%s[/color]" % [UITheme.TEXT_LABEL.to_html(false), SLOT_LABELS.get(slot_key, slot_key)],
		ItemTooltip.build(item, ["Clic droit : retirer"]),
	]


func clear_item() -> void:
	_item_id = ""
	_icon.texture = IconFactory.slot_icon("item", "", SLOT_PLACEHOLDER_TYPES.get(slot_key, "MISC"))
	_icon.modulate = PLACEHOLDER_MODULATE
	_set_grade_badge("NOGRADE")
	tooltip_text = "%s [color=#%s](vide)[/color]" % [SLOT_LABELS.get(slot_key, slot_key), UITheme.TEXT_DIM.to_html(false)]


## Main secondaire sous une arme à deux mains (champ `offHandBlocked` d'Inventory, décidé par
## le serveur) : grisé et refuse le dépôt ; comme dans L2, l'icône de l'arme (`blocking_item`)
## y apparaît en fantôme. À appeler après set_item/clear_item. Un objet encore présent
## (sauvegarde antérieure à la règle) reste affiché et retirable au clic droit.
func set_blocked(blocked: bool, blocking_item: Dictionary = {}) -> void:
	_blocked = blocked
	modulate = BLOCKED_MODULATE if blocked else Color.WHITE
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if blocked else Control.CURSOR_POINTING_HAND
	if blocked and _item_id.is_empty():
		if not blocking_item.is_empty():
			_icon.texture = IconFactory.item_icon(blocking_item)
			_icon.modulate = BLOCKED_ICON_MODULATE
		tooltip_text = "%s [color=#%s](indisponible : arme à deux mains)[/color]" % [
			SLOT_LABELS.get(slot_key, slot_key), UITheme.TEXT_DIM.to_html(false)]


func _set_grade_badge(grade: String) -> void:
	for child in _grade_badge_holder.get_children():
		child.queue_free()
	if grade != "NOGRADE":
		_grade_badge_holder.add_child(UITheme.make_grade_badge(grade))


func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_rich_tooltip(for_text)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not _item_id.is_empty():
			unequip_requested.emit(_item_id)


func _can_drop_data(_pos: Vector2, data) -> bool:
	return not _blocked and typeof(data) == TYPE_DICTIONARY and data.get("kind") == "item" \
		and not str(data.get("ref_id", "")).is_empty()


func _drop_data(_pos: Vector2, data) -> void:
	item_dropped.emit(slot_key, str(data.get("ref_id", "")), str(data.get("ref_name", "")))
