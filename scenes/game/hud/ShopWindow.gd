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
## ... ou plusieurs quantités facilement dans le cas des shots"). "Confirmer l'achat" envoie
## un "buy <npcId>|<itemTemplateId>|<quantité>" par ligne à quantité > 0 (voir Buy.java côté
## backend, achat tout-ou-rien par ligne — cf. NpcSellerInstance.sell), remet tout le panier à
## 0, puis redemande "inventory" pour resynchroniser l'or affiché ici (ItemBought ne pousse
## pas d'Inventory complet de lui-même côté backend) et rafraîchir InventoryWindow au passage
## si elle est ouverte.

const GRADE_COLORS := {
	"NOGRADE": Color(0.75, 0.75, 0.75),
	"D": Color(0.90, 0.90, 0.90),
	"C": Color(0.30, 0.85, 0.35),
	"B": Color(0.30, 0.55, 0.95),
	"A": Color(0.95, 0.75, 0.15),
	"S": Color(0.90, 0.20, 0.20),
}
const MAX_QUANTITY := 999

@onready var _npc_name_label: Label = %NpcNameLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _items_container: VBoxContainer = %ItemsContainer
@onready var _total_label: Label = %TotalLabel
@onready var _confirm_button: Button = %ConfirmButton
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
				_show_message("Acheté : %s (%s or)." % [str(payload.get("itemName", "?")), str(payload.get("price", 0))])
		"NotEnoughGold":
			if visible:
				_show_message("Pas assez d'or (%s requis)." % str(payload.get("price", 0)))
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
		_items_container.add_child(empty_label)
	else:
		for entry in _entries:
			_items_container.add_child(_build_row(entry))

	_update_totals()


## Chaque ligne est enveloppée dans une petite carte (PanelContainer, thème par défaut —
## voir UITheme.gd) plutôt qu'un simple HBoxContainer nu, pour rappeler les rangées à cadre
## des fenêtres L2 (voir CLAUDE.md, session "refonte L2" du 2026-09-04) sans pour autant
## réécrire toute l'interaction en grille + glisser-déposer (le SpinBox par ligne, demandé
## explicitement pour choisir une quantité, ne se prête pas à une cellule d'icône seule).
## L'icône est elle-même encadrée par un petit Panel carré (même thème par défaut) pour
## évoquer un slot plutôt qu'une simple image flottante.
func _build_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var item_id := str(entry.get("itemTemplateId", ""))
	var item_name := str(entry.get("itemName", ""))
	var grade := str(entry.get("grade", "NOGRADE"))
	var price := int(entry.get("price", 0))

	var icon_slot := Panel.new()
	icon_slot.custom_minimum_size = Vector2(44, 44)
	var icon := TextureRect.new()
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = ZoneAssets3D.make_slot_icon_texture("item", item_name)
	icon_slot.add_child(icon)
	row.add_child(icon_slot)

	var name_label := Label.new()
	name_label.text = "%s (%s or / unité)" % [item_name, price]
	name_label.add_theme_color_override("font_color", GRADE_COLORS.get(grade, Color.WHITE))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.tooltip_text = "%s (%s)" % [item_name, grade]
	row.add_child(name_label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = MAX_QUANTITY
	spin.step = 1
	spin.value = _quantity_by_item_id.get(item_id, 0)
	spin.custom_minimum_size = Vector2(90, 0)
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
	_gold_label.text = "Or : %s" % _gold
	var total := _cart_total()
	_total_label.text = "Total : %s or" % total
	_confirm_button.disabled = total <= 0 or total > _gold


func _cart_total() -> int:
	var total := 0
	for entry in _entries:
		var item_id := str(entry.get("itemTemplateId", ""))
		if _quantity_by_item_id.has(item_id):
			total += int(entry.get("price", 0)) * int(_quantity_by_item_id[item_id])
	return total


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
