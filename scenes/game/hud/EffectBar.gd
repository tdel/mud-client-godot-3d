class_name EffectBar
extends VBoxContainer
## Buffs et debuffs d'un personnage, façon Lineage 2 : une rangée de bonus, un trait, une
## rangée de malus, chaque effet en petite icône (EffectIcon : décompte dans l'icône sous
## 10 s, infobulle détaillée). Le trait n'apparaît que si les deux rangées sont occupées ;
## sans aucun effet la barre se masque. Utilisée sous PlayerFrame (nous), dans
## TargetStatusBar (cible : monstre, PNJ ou joueur) et PartyMemberFrame (membres du groupe).
##
## Aucune logique réseau : l'appelant passe à chaque image le dictionnaire d'effets du
## personnage ({skill_name: effet}, voir GameState._effect_entry) à set_effects().

## Un effet dont l'expiration serveur n'est jamais arrivée (porteur sorti de portée,
## message perdu) est masqué passé ce délai.
const EXPIRY_GRACE_SEC := 3.0

var icon_size := 24
var _buff_row: HBoxContainer
var _separator: HSeparator
var _debuff_row: HBoxContainer
## Effets affichés (noms par rangée), pour ne reconstruire les icônes qu'à un changement réel.
var _signature := ""
## {skill_name: EffectIcon}
var _icons := {}


## `centered` : rangées centrées (fenêtre de cible) plutôt qu'alignées à gauche.
func _init(p_icon_size: int = 24, centered: bool = false) -> void:
	icon_size = p_icon_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	_buff_row = _make_row(centered)
	_separator = HSeparator.new()
	_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_separator.add_theme_constant_override("separation", 3)
	_debuff_row = _make_row(centered)
	for child in [_buff_row, _separator, _debuff_row]:
		add_child(child)
	visible = false


func _make_row(centered: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_BEGIN
	return row


func set_effects(effects: Dictionary) -> void:
	var now := GameClock.now()
	var buffs: Array[String] = []
	var debuffs: Array[String] = []
	for skill_name in effects:
		var effect: Dictionary = effects[skill_name]
		if float(effect.get("expires_at", 0.0)) + EXPIRY_GRACE_SEC <= now:
			continue
		if bool(effect.get("beneficial", true)):
			buffs.append(str(skill_name))
		else:
			debuffs.append(str(skill_name))
	var signature := "%s|%s" % [",".join(buffs), ",".join(debuffs)]
	if signature != _signature:
		_signature = signature
		_rebuild(buffs, debuffs)
	for skill_name in _icons:
		_icons[skill_name].refresh(effects[skill_name], now)


func _rebuild(buffs: Array[String], debuffs: Array[String]) -> void:
	for row in [_buff_row, _debuff_row]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	_icons.clear()
	for skill_name in buffs:
		_add_icon(_buff_row, skill_name, true)
	for skill_name in debuffs:
		_add_icon(_debuff_row, skill_name, false)
	_buff_row.visible = not buffs.is_empty()
	_debuff_row.visible = not debuffs.is_empty()
	_separator.visible = _buff_row.visible and _debuff_row.visible
	visible = _buff_row.visible or _debuff_row.visible


func _add_icon(row: HBoxContainer, skill_name: String, beneficial: bool) -> void:
	var icon := EffectIcon.new(skill_name, beneficial, icon_size)
	row.add_child(icon)
	_icons[skill_name] = icon
