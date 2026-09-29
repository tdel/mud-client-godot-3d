extends Control
## Un slot de la barre de raccourcis (F1-F12), cible de glisser-déposer. Hotbar.gd pilote
## entièrement son contenu et ses états (recharge, erreur, mana insuffisante, charge armée) —
## ce script ne connaît rien du protocole réseau.
##
## Rendu façon Lineage 2 : slot en creux, touche en petit en haut à gauche, recharge affichée
## comme un voile sombre qui se retire dans le sens horaire (plus le temps restant au centre),
## charge soulshot/spiritshot armée signalée par une icône brillante animée.

signal slot_drop_requested(
	slot_index: int, kind: String, ref_id: String, ref_name: String, item_type: String, item_grade: String
)
## Clic gauche : Hotbar.gd le traite comme un appui sur la touche F1-F12 correspondante.
signal slot_clicked(slot_index: int)
## Clic droit : bascule d'un objet "toggle" (soulshot/spiritshot), voir Hotbar.gd.
signal slot_right_clicked(slot_index: int)

const KEY_LABELS := ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
const ERROR_FLASH_DURATION := 0.4
const INSUFFICIENT_MANA_MODULATE := Color(0.40, 0.42, 0.55, 1.0)
const COOLDOWN_SHADE := Color(0.0, 0.0, 0.0, 0.62)
const COOLDOWN_EDGE := Color(1.0, 0.92, 0.65, 0.85)

@onready var _background: Panel = $Background
@onready var _icon: TextureRect = %Icon
@onready var _overlay: Control = %Overlay
@onready var _key_label: Label = %KeyLabel
@onready var _quantity_label: Label = %QuantityLabel
@onready var _cooldown_label: Label = %CooldownLabel
@onready var _error_overlay: ColorRect = %ErrorOverlay

var slot_index: int = 0
var _kind: String = ""
var _ref_name: String = ""
var _cooldown_end_msec: float = 0.0
var _cooldown_total_msec: float = 0.0
## Une recharge est en cours et n'a pas encore été signalée comme terminée (voir _process).
var _cooldown_pending := false


func _ready() -> void:
	_cooldown_label.visible = false
	_error_overlay.visible = false
	_overlay.draw.connect(_on_overlay_draw)
	mouse_entered.connect(func(): _background.theme_type_variation = &"SlotPanelHover")
	mouse_exited.connect(func(): _background.theme_type_variation = &"SlotPanel")
	set_process(false)


## Doit être appelé une fois par Hotbar.gd juste après l'instanciation.
func setup(index: int) -> void:
	slot_index = index
	_key_label.text = KEY_LABELS[index] if index < KEY_LABELS.size() else ""


## `tooltip` : texte détaillé optionnel (BBCode accepté, voir Hotbar._build_tooltip).
func set_content(kind: String, ref_name: String, tooltip: String = "") -> void:
	_kind = kind
	_ref_name = ref_name
	set_insufficient_mana(false)
	set_quantity(-1)
	# Réappliqué par Hotbar._refresh_shot_active_states si le nouveau contenu est une charge armée.
	_icon.material = null
	if kind.is_empty():
		_icon.texture = null
		tooltip_text = ""
		return
	_icon.texture = IconFactory.slot_icon(kind, ref_name)
	if not tooltip.is_empty():
		tooltip_text = tooltip
	else:
		tooltip_text = "Attaque de base" if kind == "attack" else ref_name


func clear_content() -> void:
	set_content("", "")
	set_active(false)


## Icône brillante (voir IconFactory.active_shot_material) d'un slot "item" de charge
## (soulshot/spiritshot) armée en auto-use, icône normale sinon — voir
## Hotbar._refresh_shot_active_states. Le shader s'anime seul, sans _process.
func set_active(active: bool, item_type: String = "SOULSHOT") -> void:
	_icon.material = IconFactory.active_shot_material(item_type) if active else null


## Démarre la recharge, ou la recale si elle est déjà en cours : seule l'heure de fin est
## alors corrigée, la durée totale est conservée pour que l'aiguille reprenne là où elle en
## est au lieu de repartir de midi (SkillOnCooldown arrive dès la fin de l'incantation,
## CastResult seulement à l'impact du projectile, et un refus serveur renvoie le temps restant).
func set_cooldown_overlay(remaining_ms: float) -> void:
	if remaining_ms <= 0.0:
		return
	if not is_cooling_down():
		_cooldown_total_msec = remaining_ms
	else:
		_cooldown_total_msec = maxf(_cooldown_total_msec, remaining_ms)
	_cooldown_end_msec = GameClock.now_msec() + remaining_ms
	_cooldown_pending = true
	_cooldown_label.visible = true
	_update_processing()


func is_cooling_down() -> bool:
	return _cooldown_remaining() > 0.0


func _update_processing() -> void:
	set_process(_cooldown_remaining() > 0.0)


func _cooldown_remaining() -> float:
	return maxf(_cooldown_end_msec - GameClock.now_msec(), 0.0)


func _process(_delta: float) -> void:
	var remaining := _cooldown_remaining()
	if remaining <= 0.0:
		_cooldown_label.visible = false
		if _cooldown_pending:
			_cooldown_pending = false
			# Petit "tic" quand un skill redevient disponible (pas pour l'attaque de base,
			# dont la recharge de quelques dixièmes de seconde en ferait un crépitement).
			if _kind == "skill":
				Sfx.play_ui("cooldown_ready")
	else:
		_cooldown_label.text = ("%.1f" % (remaining / 1000.0)) if remaining < 10000.0 else str(ceili(remaining / 1000.0))
	_overlay.queue_redraw()
	_update_processing()


func _on_overlay_draw() -> void:
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var remaining := _cooldown_remaining()
	if remaining > 0.0 and _cooldown_total_msec > 0.0:
		# Voile sombre couvrant la fraction restante, qui se retire dans le sens horaire à
		# partir de midi (secteur de disque découpé au carré du slot).
		var fraction := clampf(remaining / _cooldown_total_msec, 0.0, 1.0)
		var center := rect.get_center()
		var radius := rect.size.length()
		var start := -PI / 2.0 + (1.0 - fraction) * TAU
		var points := PackedVector2Array([center])
		var steps := maxi(3, int(fraction * 48.0))
		for i in steps + 1:
			var a := start + fraction * TAU * float(i) / float(steps)
			points.append(_clip_to_rect(center, Vector2(cos(a), sin(a)) * radius, rect))
		if points.size() >= 3:
			_overlay.draw_colored_polygon(points, COOLDOWN_SHADE)
			_overlay.draw_line(center, points[1], COOLDOWN_EDGE, 1.0, true)


## Projette le rayon partant de `center` sur le bord du rectangle `rect`.
func _clip_to_rect(center: Vector2, ray: Vector2, rect: Rect2) -> Vector2:
	var t := INF
	if ray.x != 0.0:
		t = minf(t, ((rect.end.x if ray.x > 0.0 else rect.position.x) - center.x) / ray.x)
	if ray.y != 0.0:
		t = minf(t, ((rect.end.y if ray.y > 0.0 else rect.position.y) - center.y) / ray.y)
	return center + ray * t


## Nombre d'exemplaires en inventaire d'un slot "item" (toutes piles confondues, voir
## Hotbar._refresh_item_quantities) : -1 = pas de compteur ; 0 = épuisé, compteur masqué et
## icône grisée (le slot reste en place pour le prochain achat, comme dans L2).
func set_quantity(quantity: int) -> void:
	_quantity_label.visible = quantity > 0
	if quantity > 0:
		_quantity_label.text = _short_quantity(quantity)
	_icon.modulate = INSUFFICIENT_MANA_MODULATE if quantity == 0 else Color(1, 1, 1, 1)


## Même format que InventoryWindow._short_quantity ("15200" -> "15k").
static func _short_quantity(quantity: int) -> String:
	if quantity >= 1000000:
		return "%dM" % (quantity / 1000000)
	if quantity >= 10000:
		return "%dk" % (quantity / 1000)
	return str(quantity)


## Grise l'icône (mais pas le voile de recharge) quand la mana manque pour ce sort.
func set_insufficient_mana(insufficient: bool) -> void:
	_icon.modulate = INSUFFICIENT_MANA_MODULATE if insufficient else Color(1, 1, 1, 1)


## Retour bref sur une action refusée (erreur serveur ou verrou local) — voile rouge et
## "bang" sourd ; le slot n'est jamais vidé.
func flash_error() -> void:
	Sfx.play_ui("action_denied")
	_error_overlay.visible = true
	var tween := create_tween()
	tween.tween_interval(ERROR_FLASH_DURATION)
	tween.tween_callback(func(): _error_overlay.visible = false)


func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_rich_tooltip(for_text)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(slot_index)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		slot_right_clicked.emit(slot_index)


func _can_drop_data(_pos: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind") in ["skill", "item"] \
		and not str(data.get("ref_name", "")).is_empty()


func _drop_data(_pos: Vector2, data) -> void:
	slot_drop_requested.emit(
		slot_index, data["kind"], str(data.get("ref_id", "")), data["ref_name"],
		str(data.get("item_type", "")), str(data.get("item_grade", ""))
	)
