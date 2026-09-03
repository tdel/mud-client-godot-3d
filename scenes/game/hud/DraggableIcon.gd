extends TextureRect
## Icône "draggable" (glisser-déposer vers un slot de Hotbar.gd/EquipmentSlot.gd), avec un
## clic droit optionnel (ex. "Utiliser" un objet d'inventaire). Remplace DraggableRow.gd
## (toute une ligne était la source du glisser-déposer) : demandé explicitement le
## 2026-09-03 ("c'est cette icône qu'il faudra drag&drop"/"Utiliser, c'est un clic droit sur
## l'icône de l'objet") — seule l'icône, pas le nom à côté, est désormais la poignée.
## Utilisée par SkillBook (sorts) et InventoryWindow (objets), Control pur indépendant du
## rendu 2D/3D comme le reste des scripts *Slot.gd/*Row.gd de ce dossier.

## Émis quand un clic droit atterrit sur l'icône (InventoryWindow : "use" sur l'objet).
signal right_clicked

## Émis quand un glisser-déposer commencé depuis cette icône se termine, réussi ou non
## (voir Control.NOTIFICATION_DRAG_END) — InventoryWindow s'en sert pour distinguer un
## drop sur une cible valide (hotbar/équipement) d'un lâcher dans le vide, traité comme
## "jeter l'objet" s'il a lieu hors de la fenêtre (voir InventoryWindow._on_item_drag_finished).
signal drag_finished(successful: bool)

var drag_kind := ""
## UUID de référence réseau : objet (résolution immédiate) ou sort (catalogue, id stable).
var drag_ref_id := ""
var drag_ref_name := ""
var drag_preview_text := ""


func _get_drag_data(_pos: Vector2) -> Variant:
	if drag_kind.is_empty() or drag_ref_name.is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = texture
	preview.custom_minimum_size = custom_minimum_size
	preview.stretch_mode = stretch_mode
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	return {"kind": drag_kind, "ref_id": drag_ref_id, "ref_name": drag_ref_name}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drag_finished.emit(get_viewport().gui_is_drag_successful())
