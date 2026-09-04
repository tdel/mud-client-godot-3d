extends Control
## Un slot de la hotbar (F1-F12), cible de glisser-déposer. Hotbar.gd pilote entièrement
## son contenu et ses overlays de cooldown/erreur/mana insuffisante — ce script ne connaît
## rien du protocole réseau. Port ~verbatim du client 2D
## (mud-godot/scenes/game/hud/HotbarSlot.gd), Control pur indépendant du rendu 2D/3D ;
## seule différence : icône générée par ZoneAssets3D plutôt que ZoneAssets.

signal slot_drop_requested(
	slot_index: int, kind: String, ref_id: String, ref_name: String, item_type: String, item_grade: String
)
## Clic gauche sur le slot : Hotbar.gd le traite exactement comme un appui sur la touche
## F1-F12 correspondante (voir Hotbar._trigger_slot).
signal slot_clicked(slot_index: int)

const KEY_LABELS := ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
const ATTACK_GLYPH := "⚔"
const ERROR_FLASH_COLOR := Color(0.9, 0.15, 0.15, 0.55)
const ERROR_FLASH_DURATION := 0.4
const INSUFFICIENT_MANA_MODULATE := Color(0.35, 0.35, 0.4, 1.0)
const NEEDLE_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const NEEDLE_WIDTH := 2.0
const NEEDLE_MARGIN := 3.0

@onready var _icon: TextureRect = %Icon
@onready var _glyph_label: Label = %GlyphLabel
@onready var _key_label: Label = %KeyLabel
@onready var _active_overlay: ColorRect = %ActiveOverlay
@onready var _cooldown_overlay: ColorRect = %CooldownOverlay
@onready var _cooldown_label: Label = %CooldownLabel
@onready var _error_overlay: ColorRect = %ErrorOverlay

var slot_index: int = 0
var _kind: String = ""
var _ref_name: String = ""
var _cooldown_end_msec: float = 0.0
var _cooldown_total_msec: float = 0.0


func _ready() -> void:
	_active_overlay.visible = false
	_cooldown_overlay.visible = false
	_cooldown_label.visible = false
	_error_overlay.visible = false
	set_process(false)


## Doit être appelé une fois par Hotbar.gd juste après l'instanciation.
func setup(index: int) -> void:
	slot_index = index
	_key_label.text = KEY_LABELS[index] if index < KEY_LABELS.size() else ""


## `tooltip` : texte détaillé optionnel (voir Hotbar._build_tooltip, qui va chercher les
## infos du sort dans GameState.known_skills — ce script reste volontairement ignorant du
## protocole réseau, voir en-tête de fichier). Vide = tooltip par défaut (nom brut).
func set_content(kind: String, ref_name: String, tooltip: String = "") -> void:
	_kind = kind
	_ref_name = ref_name
	set_insufficient_mana(false)
	if kind.is_empty():
		_icon.texture = null
		_glyph_label.text = ""
		tooltip_text = ""
		return
	_icon.texture = ZoneAssets3D.make_slot_icon_texture(kind, ref_name)
	_glyph_label.text = ATTACK_GLYPH if kind == "attack" else ""
	if not tooltip.is_empty():
		tooltip_text = tooltip
	else:
		tooltip_text = "Attaque de base" if kind == "attack" else ref_name


func clear_content() -> void:
	set_content("", "")
	set_active(false)


## Surlignage persistant (contrairement à flash_error, temporaire) pour un slot "item" de
## charge (soulshot/spiritshot) actuellement armée en auto-use — voir Hotbar._refresh_shot_
## active_states, seule appelante. Sans rapport avec le cooldown/l'erreur, qui restent
## indépendants et continuent de s'afficher par-dessus (voir l'ordre des nœuds dans
## HotbarSlot.tscn).
func set_active(active: bool) -> void:
	_active_overlay.visible = active


func set_cooldown_overlay(remaining_ms: float) -> void:
	if remaining_ms <= 0.0:
		return
	_cooldown_end_msec = Time.get_ticks_msec() + remaining_ms
	_cooldown_total_msec = remaining_ms
	_cooldown_overlay.visible = true
	_cooldown_label.visible = true
	set_process(true)


func _process(_delta: float) -> void:
	var remaining := _cooldown_end_msec - Time.get_ticks_msec()
	if remaining <= 0.0:
		_cooldown_overlay.visible = false
		_cooldown_label.visible = false
		set_process(false)
		queue_redraw()
		return
	_cooldown_label.text = "%.1f" % (remaining / 1000.0)
	queue_redraw()


## Aiguille façon horloge : part de midi au début du cooldown, fait un tour complet dans
## le sens horaire et revient pile à midi quand le cooldown atteint 0.
func _draw() -> void:
	if not _cooldown_overlay.visible or _cooldown_total_msec <= 0.0:
		return
	var remaining := _cooldown_end_msec - Time.get_ticks_msec()
	var progress := 1.0 - clampf(remaining / _cooldown_total_msec, 0.0, 1.0)
	var angle := -PI / 2.0 + progress * TAU
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - NEEDLE_MARGIN
	var tip := center + Vector2(cos(angle), sin(angle)) * radius
	draw_line(center, tip, NEEDLE_COLOR, NEEDLE_WIDTH)


## Grise l'icône (mais pas l'overlay/aiguille de cooldown, indépendant) quand le joueur
## n'a pas assez de mana pour ce sort — voir Hotbar._refresh_mana_affordability.
func set_insufficient_mana(insufficient: bool) -> void:
	_icon.modulate = INSUFFICIENT_MANA_MODULATE if insufficient else Color(1, 1, 1, 1)


## Feedback bref sur une erreur serveur liée à ce slot (objet/sort qui n'existe plus,
## etc.) — le slot n'est jamais vidé automatiquement.
func flash_error() -> void:
	_error_overlay.color = ERROR_FLASH_COLOR
	_error_overlay.visible = true
	var tween := create_tween()
	tween.tween_interval(ERROR_FLASH_DURATION)
	tween.tween_callback(func(): _error_overlay.visible = false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(slot_index)


func _can_drop_data(_pos: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind") in ["skill", "item"] \
		and not str(data.get("ref_name", "")).is_empty()


func _drop_data(_pos: Vector2, data) -> void:
	slot_drop_requested.emit(
		slot_index, data["kind"], str(data.get("ref_id", "")), data["ref_name"],
		str(data.get("item_type", "")), str(data.get("item_grade", ""))
	)
