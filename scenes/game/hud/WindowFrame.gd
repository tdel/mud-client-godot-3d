class_name WindowFrame
extends Control
## Base commune à toutes les fenêtres HUD déplaçables/fermables (SkillBook, InventoryWindow,
## EquipmentWindow, CharacterSheetWindow, OptionsWindow — voir CLAUDE.md, session du
## 2026-09-03 "icônes bas-droite façon L2J") : demandé explicitement ("les fenêtres doivent
## pouvoir s'ouvrir et être déplaçables, avec une croix pour les fermer, ou Échap ferme la
## fenêtre la plus proche de nous"), alors qu'aucune fenêtre du client 2D
## (mud-godot/scenes/game/hud/*.gd) n'est déplaçable ni ne porte de croix — rien à porter
## ici, entièrement nouveau.
##
## Chaque fenêtre concrète hérite de ce script (`extends WindowFrame`) et fournit sa propre
## scène avec la structure minimale attendue par les @onready ci-dessous — %TitleBar (la
## rangée de titre, glissée pour déplacer la fenêtre), %TitleLabel, %CloseButton, %Body (où
## la fenêtre concrète ajoute son propre contenu) — voir SkillBook.tscn pour un exemple.
## Ainsi la mise en page reste dupliquée par fichier .tscn (même convention que le reste du
## projet) mais la logique de déplacement/fermeture/pile-Échap n'existe qu'une fois.

## Pile des fenêtres actuellement ouvertes, dans l'ordre d'ouverture/mise au premier plan —
## `close_topmost` (voir Game3D._unhandled_input, touche Échap) ferme toujours la dernière,
## donc soit la plus récemment ouverte, soit la dernière dont la barre de titre a été
## cliquée (voir _bring_to_front) : c'est ce que l'utilisateur appelle "la fenêtre la plus
## proche de nous".
static var _open_stack: Array[WindowFrame] = []

@onready var _title_bar: Control = %TitleBar
@onready var _title_label: Label = %TitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _body: Control = %Body

var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	visible = false
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.gui_input.connect(_on_title_bar_gui_input)
	_close_button.pressed.connect(close_window)


func set_window_title(text: String) -> void:
	_title_label.text = text


## Conteneur où la fenêtre concrète ajoute son propre contenu (voir en-tête de fichier).
func get_body() -> Control:
	return _body


## À appeler en tête du `open()` propre à chaque fenêtre concrète, qui y ajoute ensuite son
## rafraîchissement réseau (voir InventoryWindow.open() par exemple) — ce script ignore
## tout du protocole réseau, comme HotbarSlot/DraggableIcon.
func show_window() -> void:
	visible = true
	_bring_to_front()


func close_window() -> void:
	visible = false
	WindowFrame._open_stack.erase(self)


func _bring_to_front() -> void:
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	WindowFrame._open_stack.erase(self)
	WindowFrame._open_stack.append(self)


## Ferme la fenêtre au premier plan (voir _open_stack) ; renvoie false si aucune fenêtre
## n'était ouverte, pour que l'appelant (Game3D, touche Échap) retombe alors sur son propre
## traitement (désélection de cible/portail).
static func close_topmost() -> bool:
	while not _open_stack.is_empty():
		var top: WindowFrame = _open_stack.back()
		if not is_instance_valid(top) or not top.visible:
			_open_stack.pop_back()
			continue
		top.close_window()
		return true
	return false


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
