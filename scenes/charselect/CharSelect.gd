extends Control
## Liste des personnages du compte : sélection, suppression (avec confirmation locale,
## le backend n'en demande aucune), création d'un nouveau personnage.

@onready var _backdrop: TextureRect = %Backdrop
@onready var _list_container: VBoxContainer = %ListContainer
@onready var _scroll_container: ScrollContainer = %ScrollContainer
@onready var _error_label: Label = %ErrorLabel
@onready var _delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog
@onready var _logout_button: Button = %LogoutButton

const CREATE_ROW_TOP_MARGIN := 20
## Hauteur maximale de la liste avant qu'elle ne défile en interne (voir _update_scroll_height).
const MAX_LIST_HEIGHT := 480.0

var _pending_delete_name := ""


func _ready() -> void:
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	_delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	_logout_button.pressed.connect(_on_logout_pressed)

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
	_list_container.add_child(_build_create_row())
	_update_scroll_height()


## `ScrollContainer` ne calcule jamais sa taille minimale sur son contenu — par conception
## (voir la doc Godot, il est fait pour recevoir une taille fixe de son parent et défiler en
## interne). Sans ce calcul manuel, il s'effondre à hauteur nulle une fois son
## `size_flags_vertical` retiré (nécessaire pour que la liste se cale en bas de l'écran via
## TopSpacer plutôt que de remplir tout l'espace vertical disponible sous le titre, voir
## CharSelect.tscn) et plus aucun personnage ne serait visible. Hauteur naturelle du contenu,
## plafonnée à MAX_LIST_HEIGHT (au-delà, le défilement interne reprend la main comme avant).
func _update_scroll_height() -> void:
	var content_height := _list_container.get_combined_minimum_size().y
	_scroll_container.custom_minimum_size.y = min(content_height, MAX_LIST_HEIGHT)


func _build_row(entry: Dictionary) -> Control:
	var wrapper := PanelContainer.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	_wire_row_hover(wrapper)

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


## Même direction artistique que les lignes de personnage (voir _build_row/_row_style) pour
## que "Créer un nouveau personnage" s'intègre visuellement à la liste plutôt que d'être un
## bouton isolé sous celle-ci. Enveloppée dans une marge (au lieu d'être ajoutée nue à
## `_list_container`) pour garder un écart visible avec le dernier personnage malgré la
## séparation à 0 entre les lignes de personnage (voir _populate_list/ListContainer, lignes
## volontairement collées les unes aux autres) — seule cette ligne a besoin de cet écart.
func _build_create_row() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", CREATE_ROW_TOP_MARGIN)

	var wrapper := PanelContainer.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	_wire_row_hover(wrapper)
	margin.add_child(wrapper)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	wrapper.add_child(row)

	var create_button := Button.new()
	create_button.text = "Créer un nouveau personnage"
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(_on_create_pressed)
	row.add_child(create_button)

	return margin


## Fond visible en permanence pour chaque ligne (personnage ou "créer"), plus clair au survol
## plutôt que le fond sombre par défaut (retours explicites : le fond doit rester affiché en
## toutes circonstances, y compris au survol des boutons de la ligne, et s'éclaircir plutôt
## que s'assombrir au survol). `mouse_exited` ignore le cas où un bouton enfant (filtre STOP)
## devient le contrôle "survolé" au sens de Godot alors que la souris reste géométriquement
## dans la ligne — sans quoi le fond disparaissait dès qu'on passait sur "Sélectionner"/
## "Supprimer".
func _wire_row_hover(wrapper: PanelContainer) -> void:
	wrapper.add_theme_stylebox_override("panel", _row_style(false))
	wrapper.mouse_entered.connect(func():
		wrapper.add_theme_stylebox_override("panel", _row_style(true))
	)
	wrapper.mouse_exited.connect(func():
		if not wrapper.get_global_rect().has_point(wrapper.get_global_mouse_position()):
			wrapper.add_theme_stylebox_override("panel", _row_style(false))
	)


func _row_style(hovered: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if hovered:
		s.bg_color = UITheme.BG_PANEL_LIGHT.lightened(0.16)
		s.border_color = UITheme.BORDER_GOLD_BRIGHT
		s.set_border_width_all(2)
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = 4
	else:
		s.bg_color = UITheme.BG_PANEL_LIGHT
		s.border_color = Color(UITheme.BORDER_GOLD.r, UITheme.BORDER_GOLD.g, UITheme.BORDER_GOLD.b, 0.5)
		s.set_border_width_all(1)
	s.set_corner_radius_all(0)
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


## Même geste que OptionsWindow._on_confirm_confirmed (cas "logout", client 3D en jeu) :
## prévient le serveur puis revient à l'écran de connexion, sans attendre sa réponse.
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
