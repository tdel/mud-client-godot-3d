extends Control
## Fenêtre de groupe, façon Lineage 2 : à gauche de l'écran, juste sous notre propre cadre
## (PlayerFrame), un cadre par AUTRE membre du groupe (nous restons dans PlayerFrame, comme
## dans L2) — chef en tête puis ordre d'arrivée — avec nom, PV/PM et buffs/debuffs (voir
## PartyMemberFrame). Visible seulement quand on est en groupe.
##
## État lu dans GameState.party (voir sa doc), jamais suivi ici : la liste des cadres est
## reconstruite sur GameState.party_changed quand les membres changent, les valeurs sont
## rafraîchies à chaque image (barres, clignotement des effets qui expirent).
##
## Souris : clic sur un membre = le cibler (`member_selected`, Game3D envoie "select") ;
## glisser = déplacer toute la fenêtre (position mémorisée dans user://windows.cfg, comme les
## fenêtres WindowFrame) ; clic droit = menu Cibler / Exclure (chef) / Quitter / Dissoudre
## (chef) / mode de butin (chef). "party-kick <uuid>" vise le membre directement, même
## hors de notre carte (voir PartyKick.java).

signal member_selected(member_id: String)

const MEMBER_FRAME_SCENE := preload("res://scenes/game/hud/PartyMemberFrame.tscn")
## Distance (px) au-delà de laquelle un appui devient un glisser plutôt qu'un clic.
const DRAG_THRESHOLD := 5.0

enum MenuId { TARGET, KICK, LEAVE, DISBAND, LOOT_RANDOM, LOOT_ROUND_ROBIN }

@onready var _members: VBoxContainer = %Members
@onready var _menu: PopupMenu = %MemberMenu

## {member_id: PartyMemberFrame}, dans l'ordre d'affichage.
var _frames := {}
var _selected_id := ""
var _menu_member_id := ""
var _press_member_id := ""
var _press_position := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	GameState.party_changed.connect(_on_party_changed)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	_members.minimum_size_changed.connect(_fit_to_content)
	_restore_position()
	_rebuild()


## Cible courante (Game3D._selected_target_id) : son cadre est surligné s'il est du groupe.
func set_selected(target_id: String) -> void:
	_selected_id = target_id


func _process(_delta: float) -> void:
	# Filet de sécurité pour un GameState.party affecté directement sans message serveur (outils
	# tools/demo_video, tools/ui_preview) : sans changement de composition, _rebuild ne fait rien.
	_rebuild()
	if not visible:
		return
	_refresh_frames()


func _refresh_frames() -> void:
	var members: Dictionary = GameState.party.get("members", {})
	var leader_id := str(GameState.party.get("leader_id", ""))
	for member_id in _frames:
		if members.has(member_id):
			_frames[member_id].refresh(members[member_id], member_id == leader_id, member_id == _selected_id)


func _on_party_changed(_event: String, _payload: Dictionary) -> void:
	_rebuild()


## Reconstruit les cadres seulement si la liste ordonnée des membres a changé (arrivée,
## départ, nouveau chef).
func _rebuild() -> void:
	var order := _member_order()
	visible = not order.is_empty()
	if order == _frames.keys():
		return
	var kept := {}
	for member_id in _frames:
		if member_id in order:
			kept[member_id] = _frames[member_id]
		else:
			_frames[member_id].queue_free()
	_frames = {}
	for i in order.size():
		var member_id: String = order[i]
		var frame: Node = kept.get(member_id)
		if frame == null:
			frame = MEMBER_FRAME_SCENE.instantiate()
			frame.member_id = member_id
			frame.panel_input.connect(_on_member_panel_input)
			_members.add_child(frame)
		_members.move_child(frame, i)
		_frames[member_id] = frame
	_refresh_frames()


## Chef en tête (s'il n'est pas nous), puis ordre d'arrivée dans le groupe.
func _member_order() -> Array:
	var members: Dictionary = GameState.party.get("members", {})
	var leader_id := str(GameState.party.get("leader_id", ""))
	var order: Array = []
	if members.has(leader_id):
		order.append(leader_id)
	for member_id in members:
		if member_id != leader_id:
			order.append(member_id)
	return order


func _fit_to_content() -> void:
	size = _members.get_combined_minimum_size()


# ---------------------------------------------------------------------------
# Souris : cibler, déplacer, menu
# ---------------------------------------------------------------------------

func _on_member_panel_input(member_id: String, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_member_id = member_id
				_press_position = get_global_mouse_position()
				_drag_offset = _press_position - global_position
				_dragging = false
			elif _press_member_id == member_id:
				if _dragging:
					_save_position()
				else:
					member_selected.emit(member_id)
				_press_member_id = ""
				_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open_menu(member_id)
	elif event is InputEventMouseMotion and not _press_member_id.is_empty():
		if not _dragging and get_global_mouse_position().distance_to(_press_position) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			global_position = _clamped(get_global_mouse_position() - _drag_offset)


func _open_menu(member_id: String) -> void:
	_menu_member_id = member_id
	var is_leader := str(GameState.party.get("leader_id", "")) == str(GameState.player_stats.get("id", ""))
	var member_name := str(GameState.party.get("members", {}).get(member_id, {}).get("name", "?"))
	_menu.clear()
	_menu.add_separator(member_name)
	_menu.add_item("Cibler", MenuId.TARGET)
	if is_leader:
		_menu.add_item("Exclure du groupe", MenuId.KICK)
	_menu.add_separator()
	_menu.add_item("Quitter le groupe", MenuId.LEAVE)
	if is_leader:
		_menu.add_item("Dissoudre le groupe", MenuId.DISBAND)
	_menu.add_separator("Butin")
	var loot_mode := str(GameState.party.get("loot_mode", ""))
	for entry in [[MenuId.LOOT_RANDOM, "Aléatoire", "RANDOM"], [MenuId.LOOT_ROUND_ROBIN, "Tour par tour", "ROUND_ROBIN"]]:
		_menu.add_radio_check_item(entry[1], entry[0])
		var index := _menu.get_item_index(entry[0])
		_menu.set_item_checked(index, loot_mode == entry[2])
		# Seul le chef choisit le mode de butin : les autres le voient sans pouvoir le changer.
		_menu.set_item_disabled(index, not is_leader)
	_menu.reset_size()
	_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.TARGET:
			member_selected.emit(_menu_member_id)
		MenuId.KICK:
			Net.send_command("party-kick", _menu_member_id)
		MenuId.LEAVE:
			Net.send_command("party-leave")
		MenuId.DISBAND:
			Net.send_command("party-disband")
		MenuId.LOOT_RANDOM:
			Net.send_command("party-loot", "random")
		MenuId.LOOT_ROUND_ROBIN:
			Net.send_command("party-loot", "byturn")


# ---------------------------------------------------------------------------
# Position mémorisée (même fichier que les fenêtres WindowFrame)
# ---------------------------------------------------------------------------

## Garde au moins un bout de cadre à l'écran pour pouvoir le rattraper.
func _clamped(pos: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(
		clampf(pos.x, 40.0 - maxf(size.x, 40.0), viewport_size.x - 40.0),
		clampf(pos.y, 0.0, viewport_size.y - 24.0)
	)


func _restore_position() -> void:
	var config := WindowFrame._positions_config()
	if not WindowFrame.persist_positions or not config.has_section_key(WindowFrame.POSITIONS_SECTION, name):
		return
	var saved = config.get_value(WindowFrame.POSITIONS_SECTION, name)
	if saved is Vector2:
		global_position = _clamped(saved)


func _save_position() -> void:
	if not WindowFrame.persist_positions:
		return
	var config := WindowFrame._positions_config()
	config.set_value(WindowFrame.POSITIONS_SECTION, name, global_position)
	config.save(WindowFrame.POSITIONS_PATH)
