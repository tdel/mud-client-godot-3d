class_name EffectIcon
extends TextureRect
## Une icône de buff/debuff d'EffectBar : pictogramme propre au sort (IconFactory, le même
## que dans la barre de raccourcis et le livre de compétences), cerné d'un fin liseré vert
## (bonus) ou rouge (malus). Sous COUNTDOWN_UNDER_SEC secondes restantes, le décompte s'inscrit
## en gros chiffres dans l'icône ; sinon le temps restant est dans l'infobulle (nom, bonus/
## malus, modificateurs de stats, poison, temps restant).

const COUNTDOWN_UNDER_SEC := 10.0
const BUFF_EDGE := Color(0.45, 0.85, 0.40, 0.95)
const DEBUFF_EDGE := Color(0.95, 0.30, 0.25, 0.95)

## app.domain.actor.ModifiedStat côté backend, mêmes libellés que CharacterSheetWindow.
const STAT_LABELS := {
	"ACCURACY": "Précision", "EVASION": "Esquive", "PATK": "P. Atk.", "PDEF": "P. Déf.",
	"MATK": "M. Atk.", "MDEF": "M. Déf.", "PCRIT": "Critique", "MCRIT": "Critique magique",
	"ATKSPD": "Vit. Atk.", "CASTSPD": "Vit. Incant.", "SPEED": "Vitesse",
	"HP_REGEN": "Régén. PV", "MP_REGEN": "Régén. PM",
}

var skill_name := ""
var beneficial := true
var _countdown: Label
## Seconde affichée (décompte + infobulle), pour ne réécrire qu'à chaque changement.
var _shown_seconds := -1
## Entrée d'effet permanent affichée (pas de décompte qui déclenche la réécriture).
var _shown_effect: Dictionary = {}


func _init(p_skill_name: String = "", p_beneficial: bool = true, icon_size: int = 24) -> void:
	skill_name = p_skill_name
	beneficial = p_beneficial
	custom_minimum_size = Vector2(icon_size, icon_size)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Rendu au double de la taille affichée puis réduit : trait net même à 20 px.
	texture = IconFactory.slot_icon("skill", skill_name, "BUFF" if beneficial else "DEBUFF", icon_size * 2)
	_countdown = Label.new()
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_override("font", UITheme.font_bold)
	_countdown.add_theme_font_size_override("font_size", maxi(10, roundi(icon_size * 0.6)))
	_countdown.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_countdown.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_countdown.add_theme_constant_override("outline_size", maxi(3, roundi(icon_size * 0.2)))
	_countdown.visible = false
	add_child(_countdown)


## `effect` : entrée de GameState.entity_effects/party.members[...].effects (voir
## GameState._effect_entry), relue à chaque image — un sort renouvelé remplace l'entrée.
func refresh(effect: Dictionary, now: float) -> void:
	if bool(effect.get("permanent", false)):
		# Pénalité de grade : pas de décompte ; l'infobulle n'est réécrite que pour une nouvelle
		# entrée (GameState en crée une à chaque EffectApplied, ex. changement de niveau).
		if not is_same(effect, _shown_effect):
			_shown_effect = effect
			_shown_seconds = -1
			_countdown.visible = false
			tooltip_text = tooltip_bbcode(skill_name, effect, INF)
		return
	_shown_effect = {}
	var remaining := float(effect.get("expires_at", now)) - now
	var seconds := maxi(0, ceili(remaining))
	if seconds == _shown_seconds:
		return
	_shown_seconds = seconds
	if _countdown.visible != (remaining < COUNTDOWN_UNDER_SEC):
		_countdown.visible = remaining < COUNTDOWN_UNDER_SEC
		queue_redraw()
	_countdown.text = str(seconds)
	tooltip_text = tooltip_bbcode(skill_name, effect, remaining)


func _draw() -> void:
	# Sous le décompte, un voile sombre fait ressortir les chiffres (le liseré reste vif).
	if _countdown.visible:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(Vector2.ZERO, size), BUFF_EDGE if beneficial else DEBUFF_EDGE, false, 1.0)


func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_rich_tooltip(for_text)


static func tooltip_bbcode(effect_name: String, effect: Dictionary, remaining: float) -> String:
	var is_buff := bool(effect.get("beneficial", true))
	var lines: Array[String] = [
		"[b]%s[/b]" % effect_name,
		"[color=#%s]%s[/color]" % [
			(UITheme.SUCCESS if is_buff else UITheme.DANGER).to_html(false), "Bonus" if is_buff else "Malus",
		],
	]
	for modifier in effect.get("modifiers", []):
		lines.append(modifier_text(modifier))
	if int(effect.get("periodic_damage", 0)) > 0:
		lines.append("Perd %d PV toutes les %d s" % [
			int(effect.periodic_damage), maxi(1, int(effect.get("periodic_interval", 0))),
		])
	if bool(effect.get("breaks_on_action", false)):
		lines.append("[color=#%s]Cesse dès que l'on bouge, attaque ou incante[/color]" % UITheme.TEXT_DIM.to_html(false))
	if bool(effect.get("toggle", false)):
		lines.append("[color=#%s]Actif jusqu'à ce qu'on le désactive[/color]" % UITheme.TEXT_DIM.to_html(false))
	elif bool(effect.get("permanent", false)):
		# Seul autre effet sans échéance : la pénalité de grade (GradePenalty côté serveur).
		lines.append("[color=#%s]Équipement d'un grade supérieur à votre expertise : dure tant qu'il est porté[/color]" % UITheme.TEXT_DIM.to_html(false))
	else:
		lines.append(UITheme.tooltip_stat("Temps restant :", format_remaining(remaining)))
	return "\n".join(lines)


## {stat, value, operator} -> "P. Atk. +8 %" (MULTIPLICATIVE) ou "M. Atk. +3" (ADDITIVE).
static func modifier_text(modifier: Dictionary) -> String:
	var stat := str(modifier.get("stat", ""))
	var value := int(modifier.get("value", 0))
	var suffix := " %" if str(modifier.get("operator", "")) == "MULTIPLICATIVE" else ""
	var color := UITheme.SUCCESS if value >= 0 else UITheme.DANGER
	return "%s [color=#%s]%+d%s[/color]" % [STAT_LABELS.get(stat, stat.capitalize()), color.to_html(false), value, suffix]


static func format_remaining(remaining: float) -> String:
	var seconds := maxi(0, ceili(remaining))
	if seconds >= 3600:
		return "%d h %02d min" % [floori(seconds / 3600.0), floori((seconds % 3600) / 60.0)]
	if seconds >= 60:
		return "%d min %02d s" % [floori(seconds / 60.0), seconds % 60]
	return "%d s" % seconds
