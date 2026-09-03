extends Control
## Écran d'authentification : connexion et création de compte, dans un même formulaire
## à deux modes. La choréographie de mot de passe (RequestPassword/ConfirmPassword) est
## gérée en interne, l'utilisateur ne voit qu'un seul formulaire à remplir.

@onready var _backdrop: TextureRect = %Backdrop
@onready var _title_label: Label = %TitleLabel
@onready var _login_field: LineEdit = %LoginField
@onready var _password_field: LineEdit = %PasswordField
@onready var _confirm_password_field: LineEdit = %ConfirmPasswordField
@onready var _error_label: Label = %ErrorLabel
@onready var _submit_button: Button = %SubmitButton
@onready var _login_tab_button: Button = %LoginTabButton
@onready var _register_tab_button: Button = %RegisterTabButton
@onready var _quit_button: Button = %QuitButton

var _mode := "login"
var _busy := false
## true dès qu'on a appelé Net.connect_to_server() et qu'on attend encore l'issue
## (connected_to_server/connection_failed) — évite de relancer une connexion par-dessus
## une déjà en cours si l'utilisateur reclique entre-temps (voir _ensure_connected).
var _connect_in_progress := false
## Identifiant à envoyer avec le verbe _mode une fois la connexion établie, quand le
## clic sur "Se connecter"/"Créer le compte" a dû déclencher lui-même la connexion (voir
## _on_submit_pressed/_on_connected_to_server). Vide = rien en attente.
var _pending_login_argument := ""


func _ready() -> void:
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	Net.message_received.connect(_on_message_received)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.connected_to_server.connect(_on_connected_to_server)

	_login_tab_button.pressed.connect(_set_mode.bind("login"))
	_register_tab_button.pressed.connect(_on_register_tab_pressed)
	_submit_button.pressed.connect(_on_submit_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_login_field.text_submitted.connect(func(_text: String): _on_submit_pressed())
	_password_field.text_submitted.connect(func(_text: String): _on_submit_pressed())
	_confirm_password_field.text_submitted.connect(func(_text: String): _on_submit_pressed())

	_set_mode("login")
	if not GameState.current_login.is_empty():
		_login_field.text = GameState.current_login
	if not GameState.pending_disconnect_message.is_empty():
		_show_error(GameState.pending_disconnect_message)
		GameState.pending_disconnect_message = ""

	# Pas de connexion automatique ici : elle n'a lieu qu'au clic sur "Créer un compte"
	# (_on_register_tab_pressed) ou à la validation du formulaire de connexion
	# (_on_submit_pressed) — pour ne pas ouvrir de socket tant que l'utilisateur n'a rien
	# demandé.


func _on_register_tab_pressed() -> void:
	_set_mode("register")
	_ensure_connected()


func _ensure_connected() -> void:
	if Net.is_connected_to_host or _connect_in_progress:
		return
	_connect_in_progress = true
	Net.connect_to_server()


func _set_mode(mode: String) -> void:
	_mode = mode
	var is_register := mode == "register"
	_confirm_password_field.visible = is_register
	_submit_button.text = "Créer le compte" if is_register else "Se connecter"
	_title_label.text = "Créer un compte" if is_register else "Connexion"
	_login_tab_button.button_pressed = not is_register
	_register_tab_button.button_pressed = is_register
	_clear_error()


func _on_submit_pressed() -> void:
	if _busy:
		return
	var login_text := _login_field.text.strip_edges()
	var password_text := _password_field.text
	if login_text.is_empty():
		_show_error("Identifiant requis.")
		return
	if password_text.is_empty():
		_show_error("Mot de passe requis.")
		return
	if _mode == "register" and password_text != _confirm_password_field.text:
		_show_error("Les mots de passe ne correspondent pas.")
		return

	_busy = true
	_set_controls_enabled(false)
	_clear_error()
	if Net.is_connected_to_host:
		Net.send_command(_mode, login_text)
	else:
		# En mode connexion (le mode inscription se connecte déjà au clic sur l'onglet,
		# voir _on_register_tab_pressed), c'est ce clic qui déclenche la connexion — le
		# verbe login/register n'est envoyé qu'une fois connected_to_server reçu, voir
		# _on_connected_to_server.
		_pending_login_argument = login_text
		_ensure_connected()


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"RequestPassword":
			if _busy:
				Net.send_reply(_password_field.text)
		"ConfirmPassword":
			if _busy:
				Net.send_reply(_confirm_password_field.text)
		"AccountNotFound":
			_fail("Aucun compte avec cet identifiant.")
		"IncorrectPassword":
			_fail("Mot de passe incorrect.")
		"AccountAlreadyConnected":
			_fail("Ce compte est déjà connecté ailleurs.")
		"LoginAlreadyTaken":
			_fail("Cet identifiant est déjà utilisé.")
		"InvalidPassword":
			var reasons: Array = payload.get("reasons", [])
			_fail("\n".join(PackedStringArray(reasons)) if not reasons.is_empty() else "Mot de passe invalide.")
		"PasswordMismatch":
			_fail("Les mots de passe ne correspondent pas.")
		"WelcomeBack":
			GameState.current_login = str(payload.get("login", _login_field.text.strip_edges()))
		"NoCharacters", "CharacterList":
			_busy = false
			_go_to_char_select()
		"Error":
			_fail(str(payload.get("message", "Erreur inconnue.")))
		"ActionNotFound":
			_fail("Commande refusée par le serveur.")
		_:
			pass


func _fail(message: String) -> void:
	_busy = false
	_connect_in_progress = false
	_pending_login_argument = ""
	_set_controls_enabled(true)
	_show_error(message)


func _go_to_char_select() -> void:
	_set_controls_enabled(true)
	get_tree().change_scene_to_file("res://scenes/charselect/CharSelect.tscn")


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true


func _clear_error() -> void:
	_error_label.text = ""
	_error_label.visible = false


func _set_controls_enabled(enabled: bool) -> void:
	_submit_button.disabled = not enabled
	_login_tab_button.disabled = not enabled
	_register_tab_button.disabled = not enabled


func _on_connected_to_server() -> void:
	_connect_in_progress = false
	if _busy and not _pending_login_argument.is_empty():
		var argument := _pending_login_argument
		_pending_login_argument = ""
		Net.send_command(_mode, argument)


func _on_connection_failed() -> void:
	_fail("Connexion au serveur impossible.")


func _on_disconnected() -> void:
	_fail("Connexion au serveur perdue.")


func _on_quit_pressed() -> void:
	get_tree().quit()
