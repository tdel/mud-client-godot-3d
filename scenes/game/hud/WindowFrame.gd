class_name WindowFrame
extends Control
## Base commune à toutes les fenêtres HUD déplaçables/fermables (SkillBook, InventoryWindow,
## EquipmentWindow, CharacterSheetWindow, OptionsWindow, ShopWindow, DialogueWindow) : glisser
## la barre de titre déplace la fenêtre, la croix la ferme, Échap ferme celle qui a le focus
## (voir _focused).
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
##
## La position de chaque fenêtre est mémorisée côté client dans user://windows.cfg (clé : nom
## du nœud) à la fin d'un glisser et à la fermeture, puis restaurée à la première ouverture —
## y compris après un redémarrage du jeu. La position du .tscn ne sert que tant qu'aucune
## position n'a été sauvegardée.

const POSITIONS_PATH := "user://windows.cfg"
const POSITIONS_SECTION := "positions"

## Pile des fenêtres ouvertes, dans l'ordre d'ouverture/mise au premier plan — Échap
## (Game3D._unhandled_input → close_topmost) ferme toujours la dernière.
static var _open_stack: Array[WindowFrame] = []
## Fenêtre qui a le focus : prise à l'ouverture et à tout clic dans la fenêtre (voir
## _bring_to_front), perdue dès qu'on clique ailleurs (monde, hotbar, chat… voir _input).
## Échap ferme la fenêtre qui a le focus ; sans focus, il désélectionne d'abord la cible
## (Game3D._unhandled_input → close_focused).
static var _focused: WindowFrame = null
## Désactivé par l'outil tools/ui_preview, dont les captures doivent utiliser les positions
## par défaut sans écraser celles du joueur.
static var persist_positions := true
## Cache de user://windows.cfg, chargé au premier accès (voir _positions_config).
static var _positions: ConfigFile = null

@onready var _panel: Control = $Panel
@onready var _title_bar: Control = %TitleBar
@onready var _title_label: Label = %TitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _body: Control = %Body

var _dragging := false
var _drag_offset := Vector2.ZERO
## Fenêtre solidaire de celle-ci (voir attach_to) : glisser l'une déplace l'autre du même
## écart, et les deux passent ensemble au premier plan — ex. InventoryWindow/EquipmentWindow,
## qui ne forment qu'une seule fenêtre dans L2.
var _attached: WindowFrame = null
var _position_restored := false


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
	if not _position_restored:
		_position_restored = true
		_restore_position()
	if not visible:
		Sfx.play_ui("window_open")
	visible = true
	_bring_to_front()
	_fit_to_content.call_deferred()


func close_window() -> void:
	if visible:
		_save_position()
		Sfx.play_ui("window_close")
	visible = false
	WindowFrame._open_stack.erase(self)
	# Le focus passe à la fenêtre suivante, pour que des Échap successifs referment les
	# fenêtres une à une ; une fenêtre fermée sans avoir le focus ne le donne à personne.
	if WindowFrame._focused == self:
		WindowFrame._focused = WindowFrame._topmost_visible()


## Lie deux fenêtres dans les deux sens (déplacement et premier plan communs).
func attach_to(other: WindowFrame) -> void:
	_attached = other
	other._attached = self


func _bring_to_front() -> void:
	# La fenêtre solidaire passe devant d'abord, pour que celle cliquée reste au sommet.
	if _attached != null and _attached.visible:
		_attached._raise()
	_raise()
	WindowFrame._focused = self


func _raise() -> void:
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	WindowFrame._open_stack.erase(self)
	WindowFrame._open_stack.append(self)


## Ferme la fenêtre au premier plan (voir _open_stack), qu'elle ait le focus ou non ;
## renvoie false si aucune fenêtre n'était ouverte, pour que l'appelant retombe sur son
## propre traitement d'Échap.
static func close_topmost() -> bool:
	var top := _topmost_visible()
	if top == null:
		return false
	top.close_window()
	return true


## Ferme la fenêtre qui a le focus (voir _focused) ; renvoie false si aucune ne l'a.
static func close_focused() -> bool:
	if _focused == null or not is_instance_valid(_focused) or not _focused.visible:
		_focused = null
		return false
	_focused.close_window()
	return true


## Dernière fenêtre ouverte encore visible de _open_stack (purgée au passage), ou null.
static func _topmost_visible() -> WindowFrame:
	while not _open_stack.is_empty():
		var top: WindowFrame = _open_stack.back()
		if is_instance_valid(top) and top.visible:
			return top
		_open_stack.pop_back()
	return null


## Clic (gauche/droit/milieu, pas la molette) : donne le focus à la fenêtre la plus haute
## sous la souris — et la ramène au premier plan, même si le clic tombe sur un bouton ou un
## slot qui l'absorbe avant _on_panel_gui_input — ou le retire si le clic est hors de toute
## fenêtre. _input passe avant la GUI : une fenêtre ouverte par ce clic même (bouton du HUD,
## PNJ cliqué) prend le focus ensuite via show_window. Chaque fenêtre visible reçoit
## l'évènement ; le calcul est idempotent, seul le premier appel change quelque chose.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton and event.pressed):
		return
	if not event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		return
	for i in range(WindowFrame._open_stack.size() - 1, -1, -1):
		var window: WindowFrame = WindowFrame._open_stack[i]
		if is_instance_valid(window) and window.visible \
				and window.get_global_rect().has_point(window.get_global_mouse_position()):
			if WindowFrame._focused != window:
				window._bring_to_front()
			return
	WindowFrame._focused = null


func _fit_to_content() -> void:
	var wanted := _panel.get_combined_minimum_size()
	size = Vector2(maxf(wanted.x, custom_minimum_size.x), maxf(wanted.y, custom_minimum_size.y))
	_clamp_to_viewport()


## Garde toujours la barre de titre à l'écran (sinon une fenêtre glissée trop loin devient
## impossible à rattraper). Une fenêtre solidaire visible est bornée avec elle comme un seul
## bloc, pour que le recadrage ne les décale jamais l'une par rapport à l'autre.
func _clamp_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size == Vector2.ZERO:
		return
	var with_attached := _attached != null and _attached.visible
	var rect := get_global_rect()
	if with_attached:
		rect = rect.merge(_attached.get_global_rect())
	var clamped := Vector2(
		clampf(rect.position.x, 40.0 - rect.size.x, viewport_size.x - 40.0),
		clampf(rect.position.y, 0.0, viewport_size.y - 24.0)
	)
	_move_by(clamped - rect.position)


func _move_by(delta: Vector2) -> void:
	global_position += delta
	if _attached != null and _attached.visible:
		_attached.global_position += delta


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_bring_to_front()


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			_bring_to_front()
		elif _dragging:
			_dragging = false
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		_move_by(get_global_mouse_position() - _drag_offset - global_position)
		_clamp_to_viewport()


static func _positions_config() -> ConfigFile:
	if _positions == null:
		_positions = ConfigFile.new()
		_positions.load(POSITIONS_PATH)
	return _positions


## Une position sauvegardée avec une fenêtre de jeu plus grande est ramenée à l'écran par le
## _fit_to_content différé de show_window (voir _clamp_to_viewport).
func _restore_position() -> void:
	var config := _positions_config()
	if not persist_positions or not config.has_section_key(POSITIONS_SECTION, name):
		return
	var saved = config.get_value(POSITIONS_SECTION, name)
	if saved is Vector2:
		global_position = saved


## Sauvegarde aussi la fenêtre solidaire, que le glisser a déplacée du même écart.
func _save_position() -> void:
	if not persist_positions:
		return
	var config := _positions_config()
	config.set_value(POSITIONS_SECTION, name, global_position)
	if _attached != null and _attached.visible:
		config.set_value(POSITIONS_SECTION, _attached.name, _attached.global_position)
	config.save(POSITIONS_PATH)
