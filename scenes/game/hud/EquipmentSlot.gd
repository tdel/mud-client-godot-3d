extends Control
## Un emplacement d'équipement (voir EquipmentWindow), cible de glisser-déposer pour une
## ligne d'InventoryWindow. Cousin de HotbarSlot.gd (même principe : ce script ignore tout
## du protocole réseau, EquipmentWindow décide quoi envoyer sur item_dropped/
## unequip_requested) mais sans cooldown/mana, avec en plus le retrait au clic droit.

signal item_dropped(slot_key: String, ref_id: String, ref_name: String)
signal unequip_requested(item_id: String)

## Glyphe (2 lettres, affiché en attente d'un objet) et libellé complet (tooltip) par slot —
## voir app.domain.item.EquipmentSlot côté backend pour la liste faisant foi.
const SLOT_ABBREVIATIONS := {
	"WEAPON": "Ar", "OFF_HAND": "Bo", "HEAD": "Tê", "CHEST": "To", "HANDS": "Ma",
	"LEGS": "Ja", "FEET": "Pi", "NECKLACE": "Co", "LEFT_EARRING": "BG",
	"RIGHT_EARRING": "BD", "LEFT_RING": "AG", "RIGHT_RING": "AD",
}
const SLOT_LABELS := {
	"WEAPON": "Arme", "OFF_HAND": "Bouclier / main secondaire", "HEAD": "Tête",
	"CHEST": "Torse", "HANDS": "Mains", "LEGS": "Jambes", "FEET": "Pieds",
	"NECKLACE": "Collier", "LEFT_EARRING": "Boucle d'oreille (gauche)",
	"RIGHT_EARRING": "Boucle d'oreille (droite)", "LEFT_RING": "Anneau (gauche)",
	"RIGHT_RING": "Anneau (droite)",
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

@onready var _icon: TextureRect = %Icon
@onready var _glyph_label: Label = %GlyphLabel

var slot_key := ""
var _item_id := ""


func setup(key: String) -> void:
	slot_key = key
	clear_item()


## `item` : une entrée telle que reçue dans Inventory.payload.items (voir GameState.inventory)
## — id/name/grade/slot/type/description/weight/armorCategory/pAtk/mAtk/pDef/mDef/
## accuracyBonus/evasionBonus/critBonus/atkSpd/enchant, tous ajoutés côté backend le
## 2026-09-03 pour cette infobulle (voir _item_tooltip).
func set_item(item: Dictionary) -> void:
	_item_id = str(item.get("id", ""))
	var item_name := str(item.get("name", ""))
	_icon.texture = ZoneAssets3D.make_slot_icon_texture("item", item_name)
	_glyph_label.text = ""
	tooltip_text = "%s\n%s\n\nClic droit : retirer" % [
		SLOT_LABELS.get(slot_key, slot_key), _item_tooltip(item),
	]


func clear_item() -> void:
	_item_id = ""
	_icon.texture = null
	_glyph_label.text = SLOT_ABBREVIATIONS.get(slot_key, "")
	tooltip_text = "%s (vide)" % SLOT_LABELS.get(slot_key, slot_key)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not _item_id.is_empty():
			unequip_requested.emit(_item_id)


func _can_drop_data(_pos: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind") == "item" \
		and not str(data.get("ref_id", "")).is_empty()


func _drop_data(_pos: Vector2, data) -> void:
	item_dropped.emit(slot_key, str(data.get("ref_id", "")), str(data.get("ref_name", "")))


## Construit le texte complet des caractéristiques d'un objet (nom/grade, type, stats de
## combat, éventuel bonus d'amélioration, description) — dupliqué à l'identique dans
## InventoryWindow.gd (même convention que le reste du HUD, voir CLAUDE.md : chaque fenêtre
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
