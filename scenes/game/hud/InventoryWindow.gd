extends WindowFrame
## Objets non équipés (slot vide, voir Inventory.Entry.slot) + or. Contrairement au client
## 2D (mud-godot/scenes/game/hud/InventoryPanel.gd), pas de bouton "Équiper" ici : équiper
## se fait en glissant l'icône vers un slot d'EquipmentWindow (voir DraggableIcon/
## EquipmentSlot) — demandé explicitement le 2026-09-03 ("faire du drag and drop des objets
## depuis l'inventaire", "quelque chose qui ressemble à du Lineage 2 / L2J"). "Jeter" détruit
## définitivement l'objet côté serveur (Drop → ItemDiscarded, aucune confirmation proposée
## par le backend) : une confirmation locale est donc demandée avant l'envoi, porté tel quel
## du client 2D.
##
## Boutons "Utiliser"/"Jeter" retirés (2026-09-03, demandé explicitement) au profit de deux
## gestes façon L2J sur l'icône elle-même : clic droit = utiliser (voir
## DraggableIcon.right_clicked), glisser-déposer hors de cette fenêtre = jeter (voir
## _on_item_drag_finished — un drop réussi sur la hotbar/l'équipement ne déclenche pas ce
## chemin, seul un lâcher qui n'atterrit sur aucune cible ET en dehors du rectangle de cette
## fenêtre est traité comme "jeter", pour ne rien faire si l'utilisateur relâche simplement
## ailleurs dans la liste).

const DraggableIcon := preload("res://scenes/game/hud/DraggableIcon.gd")

## Depuis le passage du backend à un système Lineage2, Inventory.Entry.grade est un
## ItemGrade (NOGRADE/D/C/B/A/S) — code couleur L2 classique, copié du client 2D.
const GRADE_COLORS := {
	"NOGRADE": Color(0.75, 0.75, 0.75),
	"D": Color(0.90, 0.90, 0.90),
	"C": Color(0.30, 0.85, 0.35),
	"B": Color(0.30, 0.55, 0.95),
	"A": Color(0.95, 0.75, 0.15),
	"S": Color(0.90, 0.20, 0.20),
}

## Traduction de app.domain.item.ItemType/ArmorCategory (backend) pour l'infobulle — voir
## _item_tooltip.
const ITEM_TYPE_LABELS := {
	"WEAPON": "Arme", "HELMET": "Casque", "ARMOR": "Armure", "PANTS": "Jambières",
	"BOOTS": "Bottes", "GLOVES": "Gants", "SHIELD": "Bouclier", "NECKLACE": "Collier",
	"EARRING": "Boucle d'oreille", "RING": "Anneau", "POTION": "Potion", "KEY": "Clé",
	"TOOL": "Outil", "MISC": "Objet",
}
const ARMOR_CATEGORY_LABELS := {"LIGHT": "légère", "MEDIUM": "moyenne", "HEAVY": "lourde"}

@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _gold_label: Label = %GoldLabel
@onready var _drop_confirm_dialog: ConfirmationDialog = %DropConfirmDialog
@onready var _message_label: Label = %MessageLabel

var _pending_drop_id := ""
var _pending_drop_name := ""


func _ready() -> void:
	super._ready()
	set_window_title("Inventaire")
	Net.message_received.connect(_on_message_received)
	_drop_confirm_dialog.confirmed.connect(_on_drop_confirmed)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_I or get_viewport().gui_get_focus_owner() != null:
		return
	if visible:
		close_window()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	show_window()
	_clear_message()
	Net.send_command("inventory")
	_refresh()


func _on_message_received(type: String, payload: Dictionary) -> void:
	if not visible:
		return
	match type:
		"Inventory":
			_clear_message()
			_refresh()
		"ItemEquipped":
			_show_message("%s équipé." % str(payload.get("name", "?")))
			Net.send_command("inventory")
		"ItemUnequipped":
			_show_message("%s retiré." % str(payload.get("name", "?")))
			Net.send_command("inventory")
		"ItemDiscarded":
			_show_message("%s détruit." % str(payload.get("name", "?")))
			Net.send_command("inventory")
		"ItemNotCarried":
			_show_message("Cet objet n'est plus dans votre inventaire.")
		"ItemNotUsable":
			_show_message("« %s » ne peut pas être utilisé." % str(payload.get("name", "?")))
		_:
			pass


func _refresh() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	var inventory: Dictionary = GameState.inventory
	_gold_label.text = "Or : %s" % inventory.get("gold", 0)

	var carried: Array = []
	for item in inventory.get("items", []):
		var slot = item.get("slot")
		if slot == null or str(slot).is_empty():
			carried.append(item)

	if carried.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Inventaire vide."
		_items_container.add_child(empty_label)
		return

	for item in carried:
		_items_container.add_child(_build_row(item))


func _build_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var item_id := str(item.get("id", ""))
	var item_name := str(item.get("name", ""))
	var grade := str(item.get("grade", "NOGRADE"))

	var icon := DraggableIcon.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_default_cursor_shape = Control.CURSOR_MOVE
	icon.texture = ZoneAssets3D.make_slot_icon_texture("item", item_name)
	icon.tooltip_text = "%s\n\nClic droit : utiliser\nGlisser hors de la fenêtre : jeter" % _item_tooltip(item)

	# ref_id (l'UUID d'instance, contrairement à SkillBook qui ne l'utilise que pour les
	# sorts) est indispensable ici : EquipmentSlot.gd envoie "equip <uuid>" directement sur
	# la donnée du drag, sans re-résolution par nom (voir EquipmentSlot._can_drop_data).
	icon.drag_kind = "item"
	icon.drag_ref_id = item_id
	icon.drag_ref_name = item_name
	icon.drag_preview_text = item_name
	icon.right_clicked.connect(func(): Net.send_command("use", item_id))
	icon.drag_finished.connect(_on_item_drag_finished.bind(item_id, item_name))
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = item_name
	name_label.add_theme_color_override("font_color", GRADE_COLORS.get(grade, Color.WHITE))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	return row


## Un drop qui n'a atterri sur aucune cible valide (hotbar/équipement, seuls Control à
## implémenter _can_drop_data pour kind "item") ET qui a lieu hors du rectangle de cette
## fenêtre est traité comme "jeter" — un drop réussi ne déclenche rien ici, et un lâcher
## raté mais toujours à l'intérieur de la fenêtre (ex. sur une autre ligne) ne fait rien non
## plus, pour ne pas surprendre l'utilisateur qui relâche simplement par erreur dans la liste.
func _on_item_drag_finished(successful: bool, item_id: String, item_name: String) -> void:
	if successful:
		return
	if get_global_rect().has_point(get_global_mouse_position()):
		return
	_on_drop_pressed(item_id, item_name)


func _on_drop_pressed(item_id: String, item_name: String) -> void:
	_pending_drop_id = item_id
	_pending_drop_name = item_name
	_drop_confirm_dialog.dialog_text = (
		"Détruire définitivement « %s » ? Cette action est irréversible." % item_name
	)
	_drop_confirm_dialog.popup_centered()


func _on_drop_confirmed() -> void:
	if not _pending_drop_id.is_empty():
		Net.send_command("drop", _pending_drop_id)
		_pending_drop_id = ""
		_pending_drop_name = ""


func _show_message(message: String) -> void:
	_message_label.text = message
	_message_label.visible = true


func _clear_message() -> void:
	_message_label.text = ""
	_message_label.visible = false


## Construit le texte complet des caractéristiques d'un objet (nom/grade, type, stats de
## combat, éventuel bonus d'amélioration, description) — dupliqué à l'identique dans
## EquipmentSlot.gd (même convention que le reste du HUD, voir CLAUDE.md : chaque fenêtre
## reste un Control autonome sans dépendance croisée). Les stats de combat valent toutes 0
## côté backend pour un objet non équipable (potion, clé...), donc simplement omises ici.
static func _item_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("%s (%s)" % [item.get("name", "?"), item.get("grade", "NOGRADE")])

	var type_key := str(item.get("type", ""))
	var type_line: String = ITEM_TYPE_LABELS.get(type_key, type_key)
	var armor_category = item.get("armorCategory")
	if armor_category != null and not str(armor_category).is_empty():
		type_line += " (%s)" % ARMOR_CATEGORY_LABELS.get(str(armor_category), str(armor_category))
	lines.append(type_line)

	var atk_def_line := PackedStringArray()
	if int(item.get("pAtk", 0)) != 0:
		atk_def_line.append("P.Atk %s" % _signed(item.get("pAtk", 0)))
	if int(item.get("mAtk", 0)) != 0:
		atk_def_line.append("M.Atk %s" % _signed(item.get("mAtk", 0)))
	if int(item.get("pDef", 0)) != 0:
		atk_def_line.append("P.Def %s" % _signed(item.get("pDef", 0)))
	if int(item.get("mDef", 0)) != 0:
		atk_def_line.append("M.Def %s" % _signed(item.get("mDef", 0)))
	if not atk_def_line.is_empty():
		lines.append("   ".join(atk_def_line))

	var bonus_line := PackedStringArray()
	if int(item.get("accuracyBonus", 0)) != 0:
		bonus_line.append("Précision %s" % _signed(item.get("accuracyBonus", 0)))
	if int(item.get("evasionBonus", 0)) != 0:
		bonus_line.append("Esquive %s" % _signed(item.get("evasionBonus", 0)))
	if int(item.get("critBonus", 0)) != 0:
		bonus_line.append("Critique %s" % _signed(item.get("critBonus", 0)))
	if int(item.get("atkSpd", 0)) != 0:
		bonus_line.append("Vit.Atk %s" % _signed(item.get("atkSpd", 0)))
	if not bonus_line.is_empty():
		lines.append("   ".join(bonus_line))

	var enchant := int(item.get("enchant", 0))
	if enchant > 0:
		lines.append("Amélioration : +%s" % enchant)

	var description := str(item.get("description", ""))
	if not description.is_empty():
		lines.append(description)

	return "\n".join(lines)


## "+5"/"-2" plutôt que le "+%s" naïf qui produirait "+-2" sur un bonus négatif
## (evasionBonus notamment, souvent négatif pour une armure lourde).
static func _signed(value: int) -> String:
	return "+%s" % value if value >= 0 else str(value)
