extends Control
## Liste des personnages du compte : sélection, suppression (avec confirmation locale,
## le backend n'en demande aucune), création d'un nouveau personnage.

@onready var _backdrop: TextureRect = %Backdrop
@onready var _list_container: VBoxContainer = %ListContainer
@onready var _create_button: Button = %CreateButton
@onready var _error_label: Label = %ErrorLabel
@onready var _delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog

var _pending_delete_name := ""


func _ready() -> void:
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	_create_button.pressed.connect(_on_create_pressed)
	_delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)

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
	for entry in GameState.character_list:
		_list_container.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var wrapper := PanelContainer.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	wrapper.add_theme_stylebox_override("panel", _row_style(false))
	wrapper.mouse_entered.connect(func(): wrapper.add_theme_stylebox_override("panel", _row_style(true)))
	wrapper.mouse_exited.connect(func(): wrapper.add_theme_stylebox_override("panel", _row_style(false)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	wrapper.add_child(row)

	var char_name := str(entry.get("name", ""))
	var race := _prettify(str(entry.get("race", "")))
	var char_class := _prettify(str(entry.get("characterClass", "")))

	var label := Label.new()
	label.text = "%s — %s %s (niveau %s)" % [char_name, race, char_class, entry.get("level", "?")]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var select_button := Button.new()
	select_button.text = "Sélectionner"
	select_button.pressed.connect(_on_select_pressed.bind(char_name))
	row.add_child(select_button)

	var delete_button := Button.new()
	delete_button.text = "Supprimer"
	delete_button.pressed.connect(_on_delete_pressed.bind(char_name))
	row.add_child(delete_button)

	return wrapper


## Contour doré + fond éclairci au survol, pour repérer facilement la ligne visée dans la
## liste (retour explicite : la ligne survolée n'était visuellement pas distinguable des
## autres). Transparent/sans bordure au repos pour ne pas alourdir la liste.
func _row_style(hovered: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if hovered:
		s.bg_color = UITheme.BG_PANEL_LIGHT.lightened(0.12)
		s.border_color = UITheme.BORDER_GOLD_BRIGHT
		s.set_border_width_all(2)
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = 4
	else:
		s.bg_color = Color(UITheme.BG_PANEL_LIGHT.r, UITheme.BG_PANEL_LIGHT.g, UITheme.BG_PANEL_LIGHT.b, 0.0)
		s.border_color = Color(0, 0, 0, 0)
		s.set_border_width_all(0)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	return s


func _prettify(enum_name: String) -> String:
	if enum_name.is_empty():
		return ""
	var words := enum_name.split("_")
	var out: Array[String] = []
	for w in words:
		if w.is_empty():
			continue
		out.append(w.substr(0, 1).to_upper() + w.substr(1).to_lower())
	return " ".join(PackedStringArray(out))


func _on_select_pressed(char_name: String) -> void:
	_clear_error()
	Net.send_command("character-select", char_name)


func _on_delete_pressed(char_name: String) -> void:
	_pending_delete_name = char_name
	_delete_confirm_dialog.dialog_text = (
		"Supprimer définitivement « %s » ? Cette action est irréversible." % char_name
	)
	_delete_confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if not _pending_delete_name.is_empty():
		Net.send_command("character-delete", _pending_delete_name)
		_pending_delete_name = ""


func _on_create_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/charselect/CharacterCreate.tscn")


func _go_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


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
