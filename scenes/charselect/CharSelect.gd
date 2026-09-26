extends Control
## Sélection du personnage façon Lineage 2 : liste des personnages du compte à gauche (clic =
## sélection, double-clic = jouer), le personnage sélectionné en 3D au centre (mannequin +
## équipement porté, comme en jeu — voir CharacterStage), sa fiche à droite, et en bas les
## actions Créer / Jouer / Supprimer (suppression avec confirmation locale, le backend n'en
## demande aucune) plus Déconnexion.

@onready var _backdrop: TextureRect = %Backdrop
@onready var _character_stage: CharacterStage = %CharacterStage
@onready var _list_container: VBoxContainer = %ListContainer
@onready var _error_label: Label = %ErrorLabel
@onready var _slots_label: Label = %SlotsLabel
@onready var _info_panel: Control = %InfoPanel
@onready var _info_name: Label = %InfoName
@onready var _info_grid: GridContainer = %InfoGrid
@onready var _play_button: Button = %PlayButton
@onready var _create_button: Button = %CreateButton
@onready var _delete_button: Button = %DeleteButton
@onready var _delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog
@onready var _logout_button: Button = %LogoutButton

const GENDER_LABELS := {"MAN": "Homme", "WOMAN": "Femme"}
const RACE_LABELS := {"HUMAN": "Humain"}
const CLASS_LABELS := {"FIGHTER": "Guerrier", "MYSTIC": "Mystique"}

var _selected_name := ""
var _pending_delete_name := ""


func _ready() -> void:
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	MenuMusic.play()
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	_delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	_logout_button.pressed.connect(_on_logout_pressed)
	_create_button.pressed.connect(_on_create_pressed)
	_play_button.pressed.connect(func(): _on_select_pressed(_selected_name))
	_delete_button.pressed.connect(func(): _on_delete_pressed(_selected_name))

	_populate_list()
	Net.send_command("character-list")


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"CharacterList", "NoCharacters":
			_clear_error()
			_populate_list()
		"NoCharacterNamed":
			_show_error("Aucun personnage nommé « %s »." % str(payload.get("name", "")))
		"CharacterCurrentlyInGame":
			_show_error("Ce personnage est déjà en jeu ailleurs.")
		"NowPlaying":
			_go_to_game()
		"Error":
			_show_error(str(payload.get("message", "Erreur inconnue.")))
		_:
			pass


func _populate_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()
	var names: Array = []
	for entry in GameState.character_list:
		names.append(str(entry.get("name", "")))
		_list_container.add_child(_build_row(entry))
	if GameState.character_list.is_empty():
		var empty := Label.new()
		empty.text = "Aucun personnage.\nCréez-en un pour commencer."
		empty.theme_type_variation = &"DimLabel"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_list_container.add_child(empty)
	_slots_label.text = "%d personnage%s" % [names.size(), "s" if names.size() > 1 else ""]
	# Conserve la sélection si le personnage existe toujours, sinon sélectionne le premier.
	if not names.has(_selected_name):
		_selected_name = names[0] if not names.is_empty() else ""
	_refresh_selection()


func _build_row(entry: Dictionary) -> Control:
	var char_name := str(entry.get("name", ""))
	var card := PanelContainer.new()
	card.theme_type_variation = &"RowPanel"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("char_name", char_name)
	card.gui_input.connect(_on_row_gui_input.bind(char_name))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var slot := Panel.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = Vector2(36, 36)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = IconFactory.ui_icon("character", 28)
	icon.position = Vector2(4, 4)
	icon.size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	row.add_child(slot)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var name_label := Label.new()
	name_label.text = char_name
	name_label.theme_type_variation = &"NameLabel"
	column.add_child(name_label)

	var detail := Label.new()
	detail.text = "Niv. %s · %s" % [entry.get("level", "?"), _class_text(entry)]
	detail.theme_type_variation = &"StatLabel"
	detail.add_theme_font_size_override("font_size", 11)
	column.add_child(detail)

	return card


func _on_row_gui_input(event: InputEvent, char_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_selected_name = char_name
		_refresh_selection()
		if event.double_click:
			_on_select_pressed(char_name)


func _refresh_selection() -> void:
	for card in _list_container.get_children():
		if card.has_meta("char_name"):
			var selected: bool = card.get_meta("char_name") == _selected_name
			card.theme_type_variation = &"RowPanelSelected" if selected else &"RowPanel"
	var has_selection := not _selected_name.is_empty()
	_play_button.disabled = not has_selection
	_delete_button.disabled = not has_selection
	_info_panel.visible = has_selection
	for child in _info_grid.get_children():
		child.queue_free()
	if not has_selection:
		_character_stage.clear()
		return
	var entry := _entry_for(_selected_name)
	# gender/equipment : ajoutés à CharacterList (backend, 2026-09-26) ; absents d'un backend
	# plus ancien -> mannequin masculin sans équipement.
	_character_stage.show_character(str(entry.get("gender", "")), entry.get("equipment", []))
	_info_name.text = _selected_name
	_add_info("Niveau", str(entry.get("level", "?")))
	var gender := str(entry.get("gender", ""))
	if not gender.is_empty():
		_add_info("Sexe", GENDER_LABELS.get(gender, _prettify(gender)))
	_add_info("Race", RACE_LABELS.get(str(entry.get("race", "")), _prettify(str(entry.get("race", "")))))
	_add_info("Classe", CLASS_LABELS.get(str(entry.get("characterClass", "")), _prettify(str(entry.get("characterClass", "")))))


func _add_info(label_text: String, value_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"StatLabel"
	_info_grid.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.theme_type_variation = &"StatValue"
	_info_grid.add_child(value)


func _entry_for(char_name: String) -> Dictionary:
	for entry in GameState.character_list:
		if str(entry.get("name", "")) == char_name:
			return entry
	return {}


func _class_text(entry: Dictionary) -> String:
	var race := str(entry.get("race", ""))
	var char_class := str(entry.get("characterClass", ""))
	return "%s %s" % [
		RACE_LABELS.get(race, _prettify(race)), CLASS_LABELS.get(char_class, _prettify(char_class)).to_lower(),
	]


func _prettify(enum_name: String) -> String:
	if enum_name.is_empty():
		return ""
	var out: Array[String] = []
	for w in enum_name.split("_"):
		if not w.is_empty():
			out.append(w.substr(0, 1).to_upper() + w.substr(1).to_lower())
	return " ".join(PackedStringArray(out))


func _on_select_pressed(char_name: String) -> void:
	if char_name.is_empty():
		return
	_clear_error()
	Net.send_command("character-select", char_name)


func _on_delete_pressed(char_name: String) -> void:
	if char_name.is_empty():
		return
	_pending_delete_name = char_name
	_delete_confirm_dialog.dialog_text = (
		"Supprimer définitivement « %s » ?\nCette action est irréversible." % char_name
	)
	_delete_confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if not _pending_delete_name.is_empty():
		Net.send_command("character-delete", _pending_delete_name)
		_pending_delete_name = ""


func _on_create_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/charselect/CharacterCreate.tscn")


func _go_to_game() -> void:
	LoadingScreen.change_scene_to_file("res://scenes/game/Game.tscn")


## Même geste que OptionsWindow._on_confirm_confirmed (cas "logout", en jeu) : prévient le
## serveur puis revient à l'écran de connexion, sans attendre sa réponse.
func _on_logout_pressed() -> void:
	Net.send_command("logout")
	GameState.clear_session()
	get_tree().change_scene_to_file("res://scenes/login/Login.tscn")


func _on_net_disconnected() -> void:
	var login_to_keep := GameState.current_login
	GameState.clear_session()
	GameState.current_login = login_to_keep
	GameState.pending_disconnect_message = "Connexion au serveur interrompue."
	get_tree().change_scene_to_file("res://scenes/login/Login.tscn")


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true


func _clear_error() -> void:
	_error_label.text = ""
	_error_label.visible = false
