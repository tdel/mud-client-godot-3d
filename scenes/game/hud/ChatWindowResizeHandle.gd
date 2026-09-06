extends Control
## Poignée de redimensionnement au coin haut-droit d'une fenêtre de discussion (voir
## Game.tscn, %ChatLogPanel/%SystemLogPanel) — ces fenêtres restent ancrées par leur coin
## bas-gauche (offset_left/offset_bottom fixes, voir Game3D.gd) : glisser cette poignée ne
## fait bouger que offset_top (hauteur) et offset_right (largeur) du panneau parent, jamais
## son coin bas-gauche. Toujours cliquable (mouse_filter=STOP) même quand le panneau parent
## passe en MOUSE_FILTER_IGNORE (fenêtre non focalisée) — un enfant garde son propre filtre
## quel que soit celui de son parent.

const MIN_WIDTH := 180.0
const MAX_WIDTH := 900.0
const MIN_HEIGHT := 90.0
const MAX_HEIGHT := 640.0

var _resizing := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var col := Color(0.86, 0.72, 0.40, 0.85)
	for i in range(3):
		var off := 3.0 + i * 4.0
		draw_line(Vector2(off, size.y), Vector2(size.x, off), col, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _resizing:
		var panel := get_parent() as Control
		var min_top := panel.offset_bottom - MAX_HEIGHT
		var max_top := panel.offset_bottom - MIN_HEIGHT
		panel.offset_top = clampf(panel.offset_top + event.relative.y, min_top, max_top)
		var min_right := panel.offset_left + MIN_WIDTH
		var max_right := panel.offset_left + MAX_WIDTH
		panel.offset_right = clampf(panel.offset_right + event.relative.x, min_right, max_right)
		get_viewport().set_input_as_handled()
