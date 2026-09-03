extends WindowFrame
## Menu Options minimal (2026-09-03, demandé explicitement) : seulement déconnexion/quitter,
## contrairement à celui du client 2D (mud-godot/scenes/game/hud/OptionsMenu.gd) qui gère
## aussi graphismes/son — aucun autoload Settings.gd dans ce prototype (jamais porté, hors
## scope), et l'utilisateur n'a demandé que ces deux actions ici. Pas de raccourci clavier
## dédié (non demandé) : uniquement accessible depuis l'icône bas-droite (BottomRightIcons).

@onready var _logout_button: Button = %LogoutButton
@onready var _quit_button: Button = %QuitButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmDialog

var _pending_action := ""


func _ready() -> void:
	super._ready()
	set_window_title("Options")
	_logout_button.pressed.connect(_on_logout_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_confirm_dialog.confirmed.connect(_on_confirm_confirmed)


func open() -> void:
	show_window()


func _on_logout_pressed() -> void:
	_pending_action = "logout"
	_confirm_dialog.dialog_text = "Se déconnecter et revenir à l'écran de connexion ?"
	_confirm_dialog.popup_centered()


func _on_quit_pressed() -> void:
	_pending_action = "quit"
	_confirm_dialog.dialog_text = "Quitter le jeu ? Vous serez déconnecté et la fenêtre se fermera."
	_confirm_dialog.popup_centered()


func _on_confirm_confirmed() -> void:
	match _pending_action:
		"logout":
			Net.send_command("logout")
			GameState.clear_session()
			get_tree().change_scene_to_file("res://scenes/login/Login.tscn")
		"quit":
			# "Quitter" implique la déconnexion (voir en-tête de fichier) : pas besoin
			# d'attendre de réponse serveur, la fermeture du process coupe la connexion TCP
			# de toute façon — même geste que Login.gd._on_quit_pressed.
			Net.send_command("logout")
			get_tree().quit()
	_pending_action = ""
