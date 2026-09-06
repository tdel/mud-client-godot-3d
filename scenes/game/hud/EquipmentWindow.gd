extends WindowFrame
## Emplacements d'équipement porté, arrangés en silhouette (tête en haut, arme/bouclier de
## part et d'autre du torse, bijoux autour, jambes/pieds en bas — voir EquipmentWindow.tscn)
## façon L2J : glisser un objet non équipé depuis InventoryWindow ici pour l'équiper, clic
## droit sur un slot rempli pour le retirer. Entièrement nouveau (2026-09-03, demandé
## explicitement) — le client 2D n'a qu'une liste texte en lecture seule dans CharacterSheet
## (mud-godot/scenes/game/hud/CharacterSheet.gd), jamais de slots interactifs.
##
## Le slot précis où un objet finit réellement équipé est décidé par le serveur (voir
## app.domain.item.ItemType.equipmentSlots côté backend, ex. un anneau peut aller à gauche
## OU à droite) : glisser sur N'IMPORTE LEQUEL des slots compatibles déclenche le même
## `equip <uuid>`, seul le retour serveur (message Inventory rejoué après ItemEquipped, voir
## _refresh) détermine quel(s) slot(s) s'allume(nt) réellement — même limitation assumée que
## le bouton "Équiper" du client 2D, qui ne choisit pas non plus de slot précis.

const SLOT_ORDER := [
	"WEAPON", "OFF_HAND", "HEAD", "CHEST", "HANDS", "LEGS", "FEET",
	"NECKLACE", "LEFT_EARRING", "RIGHT_EARRING", "LEFT_RING", "RIGHT_RING",
]

@onready var _message_label: Label = %MessageLabel
## Plus d'icône ni de raccourci clavier propres à cette fenêtre (demandé explicitement le
## 2026-09-06) : elle s'ouvre/se ferme toujours avec InventoryWindow, qui pilote normalement
## les deux (voir InventoryWindow.open()/close_window()) ; ce rappel symétrique ne sert que si
## cette fenêtre est fermée par sa propre croix ou par Échap alors qu'elle est au sommet de la
## pile (voir WindowFrame.close_topmost).
@onready var _inventory_window: WindowFrame = %InventoryWindow

var _slots_by_key: Dictionary = {}


func _ready() -> void:
	super._ready()
	set_window_title("Équipement")
	Net.message_received.connect(_on_message_received)
	for slot_key in SLOT_ORDER:
		var slot_node: Control = get_body().find_child(slot_key, true, false)
		slot_node.setup(slot_key)
		slot_node.item_dropped.connect(_on_item_dropped)
		slot_node.unequip_requested.connect(_on_unequip_requested)
		_slots_by_key[slot_key] = slot_node


func open() -> void:
	show_window()
	_clear_message()
	Net.send_command("inventory")
	_refresh()


func close_window() -> void:
	var was_visible := visible
	super.close_window()
	if was_visible and _inventory_window.visible:
		_inventory_window.close_window()


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
		"ItemNotEquippable":
			_show_message("« %s » ne peut pas être équipé." % str(payload.get("name", "?")))
		"ItemNotEquipped":
			_show_message("« %s » n'est pas équipé." % str(payload.get("name", "?")))
		"ItemNotCarried":
			_show_message("Cet objet n'est plus dans votre inventaire.")
		_:
			pass


func _refresh() -> void:
	for slot_key in SLOT_ORDER:
		_slots_by_key[slot_key].clear_item()
	for item in GameState.inventory.get("items", []):
		var slot = item.get("slot")
		if slot == null or str(slot).is_empty():
			continue
		var slot_key := str(slot)
		if _slots_by_key.has(slot_key):
			_slots_by_key[slot_key].set_item(item)


func _on_item_dropped(_slot_key: String, ref_id: String, _ref_name: String) -> void:
	if ref_id.is_empty():
		return
	Net.send_command("equip", ref_id)


func _on_unequip_requested(item_id: String) -> void:
	Net.send_command("unequip", item_id)


func _show_message(message: String) -> void:
	_message_label.text = message
	_message_label.visible = true


func _clear_message() -> void:
	_message_label.text = ""
	_message_label.visible = false
