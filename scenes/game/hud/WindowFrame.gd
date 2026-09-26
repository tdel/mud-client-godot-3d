class_name WindowFrame
extends Control
## Base commune à toutes les fenêtres HUD déplaçables/fermables (SkillBook, InventoryWindow,
## EquipmentWindow, CharacterSheetWindow, OptionsWindow, ShopWindow, DialogueWindow) : glisser
## la barre de titre déplace la fenêtre, la croix la ferme, Échap ferme la plus récente.
##
## Chaque fenêtre concrète hérite de ce script (`extends WindowFrame`) et fournit sa propre
## scène avec la structure attendue par les @onready ci-dessous, façon fenêtre Lineage 2 :
##   Panel (PanelContainer, variation "WindowPanel")
##     VBox
##       TitleBar (PanelContainer, variation "TitleBar")   -> %TitleBar
##         TitleRow : TitleLabel (%TitleLabel) + CloseButton (%CloseButton, variation "CloseButton")
##       BodyMargin (MarginContainer)
##         Body (%Body) — contenu propre à la fenêtre
## La fenêtre s'ajuste automatiquement à la taille minimale de son contenu (voir
## _fit_to_content) : la taille posée dans le .tscn n'est qu'un point de départ.

## Pile des fenêtres ouvertes, dans l'ordre d'ouverture/mise au premier plan — Échap
## (Game3D._unhandled_input → close_topmost) ferme toujours la dernière.
static var _open_stack: Array[WindowFrame] = []

@onready var _panel: Control = $Panel
@onready var _title_bar: Control = %TitleBar
@onready var _title_label: Label = %TitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _body: Control = %Body

var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	visible = false
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.gui_input.connect(_on_title_bar_gui_input)
	_close_button.pressed.connect(close_window)
	_close_button.tooltip_text = "Fermer (Échap)"
	_close_button.focus_mode = Control.FOCUS_NONE
	_panel.minimum_size_changed.connect(_fit_to_content)
	# Un clic n'importe où dans la fenêtre la ramène au premier plan (comme dans L2), pas
	# seulement sur la barre de titre.
	_panel.gui_input.connect(_on_panel_gui_input)
	_fit_to_content()


func set_window_title(text: String) -> void:
	_title_label.text = text


## Conteneur où la fenêtre concrète ajoute son propre contenu (voir en-tête de fichier).
func get_body() -> Control:
	return _body


## À appeler en tête du `open()` propre à chaque fenêtre concrète.
func show_window() -> void:
	visible = true
	_bring_to_front()
	_fit_to_content.call_deferred()


func close_window() -> void:
	visible = false
	WindowFrame._open_stack.erase(self)


func _bring_to_front() -> void:
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	WindowFrame._open_stack.erase(self)
	WindowFrame._open_stack.append(self)


## Ferme la fenêtre au premier plan (voir _open_stack) ; renvoie false si aucune fenêtre
## n'était ouverte, pour que l'appelant retombe sur son propre traitement d'Échap.
static func close_topmost() -> bool:
	while not _open_stack.is_empty():
		var top: WindowFrame = _open_stack.back()
		if not is_instance_valid(top) or not top.visible:
			_open_stack.pop_back()
			continue
		top.close_window()
		return true
	return false


func _fit_to_content() -> void:
	var wanted := _panel.get_combined_minimum_size()
	size = Vector2(maxf(wanted.x, custom_minimum_size.x), maxf(wanted.y, custom_minimum_size.y))
	_clamp_to_viewport()


## Garde toujours la barre de titre à l'écran (sinon une fenêtre glissée trop loin devient
## impossible à rattraper).
func _clamp_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size == Vector2.ZERO:
		return
	global_position = Vector2(
		clampf(global_position.x, 40.0 - size.x, viewport_size.x - 40.0),
		clampf(global_position.y, 0.0, viewport_size.y - 24.0)
	)


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_bring_to_front()


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			_bring_to_front()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_viewport()
