class_name ItemTooltip
extends RefCounted
## Texte d'infobulle (BBCode) d'un objet, façon Lineage 2 : nom coloré selon le grade suivi
## de son grade, type, puis caractéristiques "libellé tan / valeur blanche", bonus, niveau
## d'amélioration et description. Partagé par InventoryWindow, EquipmentSlot et ShopWindow ;
## affiché via UITheme.make_rich_tooltip (voir DraggableIcon/EquipmentSlot._make_custom_tooltip).
## Les caractéristiques valant 0 (objet non équipable : potion, clé...) sont omises.

const ITEM_TYPE_LABELS := {
	"WEAPON": "Arme", "HELMET": "Casque", "ARMOR": "Armure", "PANTS": "Jambières",
	"BOOTS": "Bottes", "GLOVES": "Gants", "SHIELD": "Bouclier", "NECKLACE": "Collier",
	"EARRING": "Boucle d'oreille", "RING": "Anneau", "POTION": "Potion", "SCROLL": "Parchemin", "KEY": "Clé",
	"TOOL": "Outil", "MISC": "Objet", "SOULSHOT": "Soulshot", "SPIRITSHOT": "Spiritshot",
}
## Types d'armure L2 (backend ArmorCategory).
const ARMOR_CATEGORY_LABELS := {"HEAVY": "armure lourde", "LIGHT": "armure légère", "ROBE": "robe"}

const STAT_LINES := [
	["pAtk", "P. Atk."], ["mAtk", "M. Atk."], ["pDef", "P. Déf."], ["mDef", "M. Déf."],
	["accuracyBonus", "Précision"], ["evasionBonus", "Esquive"], ["critBonus", "Critique"],
	["atkSpd", "Vit. Atk."],
]


static func build(item: Dictionary, footer_lines: Array = []) -> String:
	var lines: Array[String] = []
	var grade := str(item.get("grade", "NOGRADE"))
	var enchant := int(item.get("enchant", 0))
	var title := _escape(str(item.get("name", "?")))
	if enchant > 0:
		title = "+%d %s" % [enchant, title]
	var grade_suffix := "" if grade == "NOGRADE" else "  [color=#%s]%s[/color]" % [UITheme.grade_color(grade).to_html(false), grade]
	lines.append("[b][color=#%s]%s[/color][/b]%s" % [UITheme.grade_color(grade).to_html(false), title, grade_suffix])

	var type_key := str(item.get("type", ""))
	var type_line: String = ITEM_TYPE_LABELS.get(type_key, type_key)
	var armor_category = item.get("armorCategory")
	if armor_category != null and not str(armor_category).is_empty():
		var category_label: String = ARMOR_CATEGORY_LABELS.get(str(armor_category), str(armor_category))
		# Plastron : "Armure lourde" / "Armure légère" / "Robe" comme dans L2 ; autre pièce :
		# "Jambières (armure lourde)".
		if type_key == "ARMOR":
			type_line = category_label[0].to_upper() + category_label.substr(1)
		else:
			type_line += " (%s)" % category_label
	if not type_line.is_empty():
		lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), type_line])

	if type_key in ["SOULSHOT", "SPIRITSHOT", "POTION", "SCROLL"]:
		lines.append(UITheme.tooltip_stat("Quantité :", UITheme.format_number(int(item.get("quantity", 1)))))

	for entry in STAT_LINES:
		var value := int(item.get(entry[0], 0))
		if value != 0:
			var shown := str(value) if entry[0] in ["pAtk", "mAtk", "pDef", "mDef", "atkSpd"] else _signed(value)
			lines.append(UITheme.tooltip_stat("%s :" % entry[1], shown))

	var description := str(item.get("description", ""))
	if not description.is_empty():
		lines.append("")
		lines.append(_escape(description))

	if not footer_lines.is_empty():
		lines.append("")
		for footer in footer_lines:
			lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), footer])
	return "\n".join(lines)


static func _signed(value: int) -> String:
	return "+%s" % value if value >= 0 else str(value)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
