class_name SkillTooltip
extends RefCounted
## Texte d'infobulle (BBCode, voir UITheme.make_rich_tooltip) d'une compétence, façon
## Lineage 2 : nom + niveau, type, caractéristiques "libellé tan / valeur blanche", arme
## exigée, puis description. Partagé par SkillBook, Hotbar et SkillLearnWindow ; lit une
## entrée KnownSkills ou LearnableSkills (backend) — les champs absents sont omis.

const TYPE_LABELS := {
	"DAMAGE": "Attaque", "HEALING": "Soin", "BUFF": "Bonus", "DEBUFF": "Malus",
	"CURE": "Purification", "PASSIVE": "Passive",
}
const TARGET_LABELS := {"SELF": "Soi-même", "PARTY": "Groupe", "AOE": "Zone"}
const WEAPON_LABELS := {
	"SWORD": "épée", "BIG_SWORD": "épée à deux mains", "DAGGER": "dague", "BLUNT": "masse",
	"BIG_BLUNT": "masse à deux mains", "AXE": "hache", "POLE": "arme d'hast", "STAFF": "bâton",
	"WAND": "baguette", "BOW": "arc",
}
const ELEMENT_LABELS := {"FIRE": "Feu", "WATER": "Eau", "WIND": "Vent", "EARTH": "Terre", "HOLY": "Sacré", "DARK": "Ténèbres"}


static func type_label(skill_type: String) -> String:
	return TYPE_LABELS.get(skill_type, skill_type)


## Familles d'arme exigées, en toutes lettres ("épée, masse ou hache"), "" si aucune.
static func weapons_label(weapon_types: Array) -> String:
	var names := PackedStringArray()
	for weapon_type in weapon_types:
		names.append(WEAPON_LABELS.get(str(weapon_type), str(weapon_type).to_lower()))
	if names.size() <= 1:
		return "".join(names)
	return "%s ou %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]


static func build(skill: Dictionary, footer_lines: Array = []) -> String:
	var skill_type := str(skill.get("skillType", ""))
	var lines := PackedStringArray()
	var level_text := "Niv. %s" % skill.get("level", "?")
	if int(skill.get("maxLevel", 0)) > 1:
		level_text += " / %s" % skill.get("maxLevel", 0)
	lines.append("[b]%s[/b]  [color=#%s]%s[/color]" % [_escape(str(skill.get("name", ""))), UITheme.TEXT_LABEL.to_html(false), level_text])
	var kind := type_label(skill_type)
	var element := str(skill.get("element", "NONE"))
	if ELEMENT_LABELS.has(element):
		kind += " · %s" % ELEMENT_LABELS[element]
	lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), kind])
	if skill_type != "PASSIVE":
		if int(skill.get("manaCost", 0)) > 0:
			lines.append(UITheme.tooltip_stat("MP consommés :", str(skill.get("manaCost", 0))))
		if int(skill.get("castTimeMs", 0)) > 0:
			lines.append(UITheme.tooltip_stat("Incantation :", "%.1f s" % (float(skill.get("castTimeMs", 0)) / 1000.0)))
		lines.append(UITheme.tooltip_stat("Recharge :", "%s s" % skill.get("cooldownSeconds", 0)))
		if int(skill.get("range", 0)) > 0:
			lines.append(UITheme.tooltip_stat("Portée :", str(skill.get("range", 0))))
		var target := str(skill.get("target", ""))
		if TARGET_LABELS.has(target):
			lines.append(UITheme.tooltip_stat("Cible :", TARGET_LABELS[target]))
		if int(skill.get("durationSeconds", 0)) > 0:
			lines.append(UITheme.tooltip_stat("Durée :", _duration(int(skill.get("durationSeconds", 0)))))
	var weapons := weapons_label(skill.get("weaponTypes", []))
	if not weapons.is_empty():
		lines.append(UITheme.tooltip_stat("Arme :", weapons))
	var description := str(skill.get("description", ""))
	if not description.is_empty():
		lines.append("")
		lines.append(_escape(description))
	if skill.get("granted", false):
		lines.append("")
		lines.append("[color=#%s]Octroyée par un objet équipé.[/color]" % UITheme.TEXT_DIM.to_html(false))
	if not footer_lines.is_empty():
		lines.append("")
		for line in footer_lines:
			lines.append("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), str(line)])
	return "\n".join(lines)


static func _duration(seconds: int) -> String:
	if seconds >= 60 and seconds % 60 == 0:
		return "%d min" % int(seconds / 60.0)
	return "%d s" % seconds


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
