extends WindowFrame
## Fenêtre d'achat façon L2J (voir CLAUDE.md, session du 2026-09-04 "Shop PNJ") ouverte au
## clic droit → "Boutique" sur un PNJ vendeur déjà sélectionné (Game3D._open_npc_menu, meta
## "has_shop" posée depuis EntityView.hasShop côté backend). Contrairement aux autres
## fenêtres HUD, elle ne s'ouvre jamais via une touche/un clic bas-droite : elle s'abonne
## directement à Net.message_received et s'ouvre elle-même dès qu'un "ShopCatalog" arrive
## (réponse à "shop <npcId>", envoyé par Game3D) — Game3D n'a donc besoin d'aucune référence
## vers cette fenêtre, même principe que GameState qui réagit à un signal indépendamment de
## ce que fait Game3D avec le même signal.
##
## Chaque ligne porte son propre SpinBox de quantité (0 = pas dans le panier) plutôt qu'un
## bouton "Ajouter au panier" séparé — demandé explicitement ("sélectionner plusieurs items
## ... ou plusieurs quantités facilement dans le cas des shots"). "Acheter" envoie
## un "buy <npcId>|<itemTemplateId>|<quantité>" par ligne à quantité > 0 (voir Buy.java côté
## backend, achat tout-ou-rien par ligne — cf. NpcSellerInstance.sell), remet tout le panier à
## 0, puis redemande "inventory" pour resynchroniser l'or affiché ici (ItemBought ne pousse
## pas d'Inventory complet de lui-même côté backend) et rafraîchir InventoryWindow au passage
## si elle est ouverte.

const MAX_QUANTITY := 999
const ICON_SIZE := Vector2(34, 34)
const SlotPanel := preload("res://scenes/game/hud/SlotPanel.gd")

@onready var _npc_name_label: Label = %NpcNameLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _total_label: Label = %TotalLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _clear_button: Button = %ClearButton
@onready var _message_label: Label = %MessageLabel

var _npc_id := ""
var _entries: Array = []
## item_template_id -> quantité choisie (>0 seulement, voir _on_quantity_changed).
var _quantity_by_item_id: Dictionary = {}
var _gold := 0


func _ready() -> void:
	super._ready()
	set_window_title("Boutique")
	Net.message_received.connect(_on_message_received)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_clear_button.pressed.connect(_on_clear_pressed)
	%GoldCoin.texture = IconFactory.ui_icon("coin", 14)
	%TotalCoin.texture = IconFactory.ui_icon("coin", 14)


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"ShopCatalog":
			_open_with_catalog(payload)
		"Inventory":
			if visible:
				_gold = int(payload.get("gold", _gold))
				_update_totals()
		"ItemBought":
			if visible:
				_show_message("Acheté : %s (%s adena)." % [str(payload.get("itemName", "?")), UITheme.format_number(int(payload.get("price", 0)))])
		"NotEnoughGold":
			if visible:
				_show_message("Pas assez d'adena (%s requis)." % UITheme.format_number(int(payload.get("price", 0))))
		"ShopItemNotFound":
			if visible:
				_show_message("Cet objet n'est plus disponible chez ce marchand.")
		_:
			pass


func _open_with_catalog(payload: Dictionary) -> void:
	_npc_id = str(payload.get("npcId", ""))
	_npc_name_label.text = str(payload.get("npcName", "Marchand"))
	_entries = payload.get("entries", [])
	_gold = int(payload.get("gold", 0))
	_quantity_by_item_id.clear()
	_clear_message()
	show_window()
	_refresh()


func _refresh() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	if _entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Ce marchand ne vend rien pour l'instant."
		empty_label.theme_type_variation = &"DimLabel"
		_items_container.add_child(empty_label)
	else:
		for entry in _entries:
			_items_container.add_child(_build_row(entry))

	_update_totals()


## Une ligne de la liste d'achat façon L2 : icône dans un slot, nom coloré selon le grade et
## prix unitaire en dessous, puis la quantité voulue (0 = pas dans le panier).
func _build_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"RowPanel"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var item_id := str(entry.get("itemTemplateId", ""))
	var item_name := str(entry.get("itemName", ""))
	var grade := str(entry.get("grade", "NOGRADE"))
	var price := int(entry.get("price", 0))

	var slot: Panel = SlotPanel.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = ICON_SIZE + Vector2(4, 4)
	slot.tooltip_text = ItemTooltip.build({"name": item_name, "grade": grade, "type": IconFactory.guess_item_type(item_name)})
	var icon := TextureRect.new()
	icon.position = Vector2(2, 2)
	icon.size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = IconFactory.slot_icon("item", item_name)
	slot.add_child(icon)
	if grade != "NOGRADE":
		var badge := UITheme.make_grade_badge(grade)
		badge.position = Vector2(slot.custom_minimum_size.x - 11, 0)
		slot.add_child(badge)
	row.add_child(slot)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var name_label := Label.new()
	name_label.text = item_name
	name_label.add_theme_color_override("font_color", UITheme.grade_color(grade))
	column.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%s adena" % UITheme.format_number(price)
	price_label.theme_type_variation = &"StatLabel"
	price_label.add_theme_font_size_override("font_size", 11)
	column.add_child(price_label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = MAX_QUANTITY
	spin.step = 1
	spin.value = _quantity_by_item_id.get(item_id, 0)
	spin.custom_minimum_size = Vector2(76, 0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.value_changed.connect(_on_quantity_changed.bind(item_id))
	row.add_child(spin)

	return card


func _on_quantity_changed(value: float, item_id: String) -> void:
	var quantity := int(value)
	if quantity <= 0:
		_quantity_by_item_id.erase(item_id)
	else:
		_quantity_by_item_id[item_id] = quantity
	_update_totals()


func _update_totals() -> void:
	_gold_label.text = UITheme.format_number(_gold)
	var total := _cart_total()
	_total_label.text = UITheme.format_number(total)
	_total_label.add_theme_color_override("font_color", UITheme.DANGER if total > _gold else UITheme.TEXT_VALUE)
	_confirm_button.disabled = total <= 0 or total > _gold
	_clear_button.disabled = _quantity_by_item_id.is_empty()


func _cart_total() -> int:
	var total := 0
	for entry in _entries:
		var item_id := str(entry.get("itemTemplateId", ""))
		if _quantity_by_item_id.has(item_id):
			total += int(entry.get("price", 0)) * int(_quantity_by_item_id[item_id])
	return total


func _on_clear_pressed() -> void:
	_quantity_by_item_id.clear()
	_refresh()


func _on_confirm_pressed() -> void:
	if _npc_id.is_empty() or _quantity_by_item_id.is_empty():
		return
	for item_id in _quantity_by_item_id.keys():
		Net.send_command("buy", "%s|%s|%s" % [_npc_id, item_id, _quantity_by_item_id[item_id]])
	_quantity_by_item_id.clear()
	_refresh()
	Net.send_command("inventory")
	_show_message("Achat envoyé...")


func _show_message(message: String) -> void:
	_message_label.text = message
	_message_label.visible = true


func _clear_message() -> void:
	_message_label.text = ""
	_message_label.visible = false
