extends WindowFrame
## Inventaire (touche I) façon Lineage 2 : onglets de filtre (Tout / Équipement /
## Consommables / Divers), grille fixe de slots en creux (les emplacements vides restent
## visibles), adena et nombre d'objets en pied de fenêtre. Seuls les objets non équipés
## (slot vide, voir Inventory.Entry.slot) y figurent ; l'équipement porté est dans
## EquipmentWindow, qui s'ouvre/se ferme toujours avec cette fenêtre (voir open/close_window).
## Chaque objet garde sa case (GameState.inventory_cells) : un objet remplacé à l'équipement
## prend la case de celui qu'on vient d'équiper, un objet déséquipé se range après le dernier.
##
## Gestes sur une icône : glisser vers un slot d'équipement = équiper, vers la barre de
## raccourcis = raccourci, clic droit = équiper un objet équipable (l'objet déjà porté à cet
## emplacement revient dans l'inventaire — échange fait par InventorySystem.equipItem côté
## serveur), utiliser un consommable, ou activer/désactiver l'auto-use d'une charge
## soulshot/spiritshot ; glisser-déposer hors de cette fenêtre = jeter (avec
## confirmation locale, "drop" détruisant l'objet côté serveur sans confirmation).

const DraggableIcon := preload("res://scenes/game/hud/DraggableIcon.gd")

## Types d'objet qui ont un emplacement d'équipement (ItemType.equipmentSlots non vide côté
## backend) : clic droit = "equip" plutôt que "use".
const EQUIPPABLE_TYPES := ["WEAPON", "HELMET", "ARMOR", "PANTS", "BOOTS", "GLOVES", "SHIELD", "NECKLACE", "EARRING", "RING"]
## Onglets : [libellé, types d'objet affichés (vide = tous, null = "le reste")].
const TABS := [
	["Tout", []],
	["Équipement", EQUIPPABLE_TYPES],
	["Consommables", ["POTION", "SOULSHOT", "SPIRITSHOT"]],
	["Divers", null],
]
const COLUMNS := 8
## Nombre minimal de cases affichées (les vides restent visibles, comme dans L2).
const MIN_CELLS := 48
const CELL_SIZE := Vector2(38, 38)

@onready var _items_container: GridContainer = %ItemsContainer
@onready var _gold_label: Label = %GoldLabel
@onready var _count_label: Label = %CountLabel
@onready var _coin_icon: TextureRect = %CoinIcon
@onready var _tab_row: HBoxContainer = %TabRow
@onready var _drop_confirm_dialog: ConfirmationDialog = %DropConfirmDialog
@onready var _message_label: Label = %MessageLabel
@onready var _equipment_window: WindowFrame = %EquipmentWindow

var _pending_drop_id := ""
var _pending_drop_name := ""
var _current_tab := 0


func _ready() -> void:
	super._ready()
	set_window_title("Inventaire")
	attach_to(_equipment_window)
	Net.message_received.connect(_on_message_received)
	_drop_confirm_dialog.confirmed.connect(_on_drop_confirmed)
	_coin_icon.texture = IconFactory.ui_icon("coin", 16)
	_items_container.columns = COLUMNS
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
	if not _equipment_window.visible:
		_equipment_window.open()
	show_window()
	_clear_message()
	Net.send_command("inventory")
	_refresh()
	_dock_equipment_window.call_deferred()


## Comme dans L2 (où équipement et inventaire ne forment qu'une fenêtre), l'équipement se
## cale contre le bord gauche de l'inventaire à chaque ouverture — ou à droite s'il n'y a
## pas la place.
func _dock_equipment_window() -> void:
	await get_tree().process_frame
	var target := global_position - Vector2(_equipment_window.size.x + 2, 0)
	if target.x < 0:
		target = global_position + Vector2(size.x + 2, 0)
	_equipment_window.global_position = target


func close_window() -> void:
	var was_visible := visible
	super.close_window()
	if was_visible and _equipment_window.visible:
		_equipment_window.close_window()


func _on_tab_pressed(index: int) -> void:
	_current_tab = index
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
		"ShotGradeChanged", "ShotOutOfStock":
			# GameState.active_*shot_grade est déjà à jour : on ne fait que redessiner le
			# surlignage "actif" sans attendre un aller-retour "inventory".
			_refresh()
		"ItemUsed", "ManaPotionUsed", "ShotUsed":
			# GameState (autoload, abonné avant cette fenêtre) a déjà décrémenté la pile en
			# place : pas d'aller-retour "inventory" à chaque tir/potion.
			_refresh()
		_:
			pass


func _refresh() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	var inventory: Dictionary = GameState.inventory
	_gold_label.text = UITheme.format_number(int(inventory.get("gold", 0)))

	var carried: Array = []
	for item in inventory.get("items", []):
		var slot = item.get("slot")
		if slot == null or str(slot).is_empty():
			carried.append(item)
	_count_label.text = "%d objet%s" % [carried.size(), "s" if carried.size() > 1 else ""]

	var by_cell := _layout(carried.filter(_matches_tab))
	var last_cell := -1
	for cell in by_cell:
		last_cell = maxi(last_cell, cell)
	var total_cells := maxi(MIN_CELLS, ceili((last_cell + 1) / float(COLUMNS)) * COLUMNS)
	for i in total_cells:
		_items_container.add_child(_build_cell(by_cell[i]) if by_cell.has(i) else _build_empty_cell())


## Case -> objet. Onglet "Tout" : chaque objet à sa case GameState.inventory_cells (trous
## compris, un objet reste en place quand on équipe/déséquipe autour de lui). Onglets filtrés :
## même ordre, mais tassé. Un objet sans case connue (inventaire posé sans message Inventory,
## voir tools/ui_preview) comble le premier trou.
func _layout(items: Array) -> Dictionary:
	var positions: Dictionary = GameState.inventory_cells
	var by_cell := {}
	var unplaced: Array = []
	if _current_tab == 0:
		for item in items:
			var cell = positions.get(str(item.get("id", "")))
			if cell == null or by_cell.has(cell):
				unplaced.append(item)
			else:
				by_cell[cell] = item
	else:
		unplaced = items.duplicate()
		unplaced.sort_custom(func(a, b):
			return int(positions.get(str(a.get("id", "")), 1 << 30)) < int(positions.get(str(b.get("id", "")), 1 << 30)))
	var next := 0
	for item in unplaced:
		while by_cell.has(next):
			next += 1
		by_cell[next] = item
	return by_cell


func _matches_tab(item: Dictionary) -> bool:
	var filter = TABS[_current_tab][1]
	var type_key := str(item.get("type", ""))
	if filter == null:
		for i in range(1, TABS.size()):
			if TABS[i][1] != null and type_key in TABS[i][1]:
				return false
		return true
	return filter.is_empty() or type_key in filter


func _build_empty_cell() -> Control:
	var cell := Panel.new()
	cell.theme_type_variation = &"SlotPanel"
	cell.custom_minimum_size = CELL_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cell


## Une case façon slot L2 : icône, pastille de grade en haut à droite, quantité en bas à
## droite pour les charges empilées, liseré doré si la charge est armée en auto-use.
func _build_cell(item: Dictionary) -> Control:
	var item_id := str(item.get("id", ""))
	var item_name := str(item.get("name", ""))
	var grade := str(item.get("grade", "NOGRADE"))
	var type_key := str(item.get("type", ""))
	var is_shot := type_key == "SOULSHOT" or type_key == "SPIRITSHOT"
	var quantity := int(item.get("quantity", 1))
	var active := is_shot and _is_shot_active(type_key, grade)

	var cell := Panel.new()
	cell.theme_type_variation = &"SlotPanelHover" if active else &"SlotPanel"
	cell.custom_minimum_size = CELL_SIZE

	var icon := DraggableIcon.new()
	icon.position = Vector2(2, 2)
	icon.size = CELL_SIZE - Vector2(4, 4)
	icon.custom_minimum_size = CELL_SIZE - Vector2(4, 4)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon.texture = IconFactory.item_icon(item)
	# ref_id = UUID d'instance : EquipmentSlot envoie "equip <uuid>" directement.
	icon.drag_kind = "item"
	icon.drag_ref_id = item_id
	icon.drag_ref_name = item_name
	icon.drag_item_type = type_key
	icon.drag_item_grade = grade
	icon.drag_preview_text = item_name
	if not active:
		icon.mouse_entered.connect(func(): cell.theme_type_variation = &"SlotPanelHover")
		icon.mouse_exited.connect(func(): cell.theme_type_variation = &"SlotPanel")

	if is_shot:
		# Clic droit = bascule d'auto-use "soulshot <grade>"/"spiritshot <grade>" (le serveur
		# éteint la charge si la même grade est déjà active).
		icon.tooltip_text = ItemTooltip.build(item, [
			"Auto-use : %s" % ("actif" if active else "inactif"),
			"Clic droit : %s" % ("désactiver" if active else "activer"),
			"Glisser hors de la fenêtre : jeter",
		])
		icon.right_clicked.connect(func(): Net.send_command(type_key.to_lower(), grade.to_lower()))
	elif type_key in EQUIPPABLE_TYPES:
		icon.tooltip_text = ItemTooltip.build(item, ["Clic droit : équiper", "Glisser hors de la fenêtre : jeter"])
		icon.right_clicked.connect(func(): Net.send_command("equip", item_id))
	else:
		icon.tooltip_text = ItemTooltip.build(item, ["Clic droit : utiliser", "Glisser hors de la fenêtre : jeter"])
		icon.right_clicked.connect(func(): Net.send_command("use", item_id))
	icon.drag_finished.connect(_on_item_drag_finished.bind(item_id, item_name))
	cell.add_child(icon)

	if grade != "NOGRADE":
		var badge := UITheme.make_grade_badge(grade)
		badge.position = Vector2(CELL_SIZE.x - 11, 0)
		cell.add_child(badge)

	if quantity != 1:
		var qty_label := Label.new()
		qty_label.text = _short_quantity(quantity)
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty_label.add_theme_font_size_override("font_size", 10)
		qty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		qty_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		qty_label.add_theme_constant_override("outline_size", 3)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.position = Vector2(0, CELL_SIZE.y - 15)
		qty_label.size = Vector2(CELL_SIZE.x - 3, 14)
		cell.add_child(qty_label)

	return cell


## "1520" -> "1520", "15200" -> "15k" : tient dans le coin d'une case de 38 px.
func _short_quantity(quantity: int) -> String:
	if quantity >= 1000000:
		return "%dM" % (quantity / 1000000)
	if quantity >= 10000:
		return "%dk" % (quantity / 1000)
	return str(quantity)


func _is_shot_active(item_type: String, item_grade: String) -> bool:
	var active_grade := GameState.active_soulshot_grade if item_type == "SOULSHOT" else GameState.active_spiritshot_grade
	return not active_grade.is_empty() and active_grade == item_grade


## Un lâcher qui n'atterrit sur aucune cible valide ET hors de cette fenêtre = "jeter" ;
## un lâcher raté à l'intérieur de la fenêtre ne fait rien.
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
		"Détruire définitivement « %s » ?\nCette action est irréversible." % item_name
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
