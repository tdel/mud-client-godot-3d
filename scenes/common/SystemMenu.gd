extends Control
## Accès au Menu système (OptionsWindow, la même fenêtre qu'en jeu) depuis les écrans hors jeu
## (Login, CharSelect) : un bouton-icône encadré en haut à droite, façon barre bas-droite du
## HUD (BottomRightIcons), pour régler graphismes/son avant d'entrer en jeu.
##
## Calque plein écran transparent aux clics (mouse_filter IGNORE) : WindowFrame suppose un
## parent plein écran (premier plan via move_child, bornage à l'écran). À placer en dernier
## enfant de la scène pour passer devant ses panneaux.
##
## La fenêtre y est en mode hors jeu (set_pre_game) : pas de "Se déconnecter", chaque écran
## garde son propre bouton (Quitter sur Login, Déconnexion sur CharSelect). Échap ferme la
## fenêtre au premier plan, comme en jeu (Game3D._unhandled_input).

@onready var _button: Button = %SystemMenuButton
@onready var _options_window: WindowFrame = %OptionsWindow


func _ready() -> void:
	_button.text = ""
	_button.icon = IconFactory.ui_icon("options", 28)
	_button.tooltip_text = "Menu système"
	_button.pressed.connect(_toggle)
	_options_window.set_pre_game(true)


func _toggle() -> void:
	if _options_window.visible:
		_options_window.close_window()
	else:
		_options_window.open()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if WindowFrame.close_topmost():
			get_viewport().set_input_as_handled()
