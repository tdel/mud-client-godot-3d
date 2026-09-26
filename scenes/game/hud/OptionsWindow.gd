extends WindowFrame
## Menu système (icône bas-droite, voir BottomRightIcons), en trois onglets façon L2 :
##   - Graphisme : résolution de la fenêtre ;
##   - Son : niveaux global / effets / interface / musique, sliders 0-100 % (bus audio, voir
##     Settings) ;
##   - Système : se déconnecter (retour à l'écran de connexion) / quitter le jeu.
## Les réglages sont appliqués immédiatement et sauvegardés par l'autoload Settings.
## Pas de raccourci clavier dédié (non demandé).

const TABS := ["Graphisme", "Son", "Système"]
## [bus (voir Settings.BUSES), libellé] des sliders de l'onglet Son, dans l'ordre d'affichage.
const VOLUME_ROWS := [
	[&"Master", "Son global"],
	[&"SFX", "Effets"],
	[&"UI", "Interface"],
	[&"Music", "Musique"],
]

@onready var _tab_row: HBoxContainer = %TabRow
@onready var _pages: Array[Control] = [%GraphicsPage, %SoundPage, %SystemPage]
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _volume_grid: GridContainer = %VolumeGrid
@onready var _logout_button: Button = %LogoutButton
@onready var _quit_button: Button = %QuitButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmDialog

var _pending_action := ""
var _resolutions: Array[Vector2i] = []
var _pre_game := false


func _ready() -> void:
	super._ready()
	set_window_title("Menu système")
	_build_tabs()
	_build_volume_rows()
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_logout_button.pressed.connect(_on_logout_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_confirm_dialog.confirmed.connect(_on_confirm_confirmed)
	_logout_button.visible = not _pre_game


func open() -> void:
	# La taille de fenêtre a pu changer depuis la dernière ouverture (redimensionnement à la
	# souris, autre écran) : la liste est reconstruite à chaque fois.
	_refresh_resolutions()
	show_window()


## Hors jeu (écrans de connexion/sélection, voir scenes/common/SystemMenu), "Se déconnecter"
## n'a pas de sens. Appelable avant comme après _ready.
func set_pre_game(pre_game: bool) -> void:
	_pre_game = pre_game
	if is_node_ready():
		_logout_button.visible = not pre_game


func _build_tabs() -> void:
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tab := Button.new()
		tab.text = TABS[i]
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = i == 0
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_show_page.bind(i))
		_tab_row.add_child(tab)
	_show_page(0)


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index


# ---------------------------------------------------------------------------
# Graphisme
# ---------------------------------------------------------------------------

func _refresh_resolutions() -> void:
	_resolutions = Settings.available_resolutions()
	var current := Settings.get_resolution()
	_resolution_option.clear()
	for i in _resolutions.size():
		var res := _resolutions[i]
		_resolution_option.add_item("%d x %d" % [res.x, res.y], i)
		if res == current:
			_resolution_option.select(i)


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < _resolutions.size():
		Settings.set_resolution(_resolutions[index])


# ---------------------------------------------------------------------------
# Son
# ---------------------------------------------------------------------------

## Une ligne par bus : libellé, slider 0-100 (pas de 1 %), valeur en pourcentage.
func _build_volume_rows() -> void:
	for row in VOLUME_ROWS:
		var bus: StringName = row[0]
		var label := Label.new()
		label.text = row[1]
		label.theme_type_variation = &"StatLabel"
		label.custom_minimum_size.x = 110
		_volume_grid.add_child(label)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size = Vector2(140, 16)
		slider.focus_mode = Control.FOCUS_NONE
		slider.value = roundf(Settings.get_volume(bus) * 100.0)
		_volume_grid.add_child(slider)

		var value_label := Label.new()
		value_label.theme_type_variation = &"StatValue"
		value_label.custom_minimum_size.x = 38
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.text = "%d %%" % int(slider.value)
		_volume_grid.add_child(value_label)

		slider.value_changed.connect(func(value: float) -> void:
			value_label.text = "%d %%" % int(value)
			Settings.set_volume(bus, value / 100.0)
		)
		# Retour sonore au relâchement des sliders (sauf musique, déjà audible) : on entend tout
		# de suite le niveau choisi (même geste que les options de son de la plupart des MMO).
		if bus != Settings.BUS_MUSIC:
			slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.play_preview(bus))


# ---------------------------------------------------------------------------
# Système
# ---------------------------------------------------------------------------

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
			# "Quitter" implique la déconnexion : pas besoin d'attendre de réponse serveur, la
			# fermeture du process coupe la connexion TCP de toute façon — même geste que
			# Login.gd._on_quit_pressed. Sur l'écran de connexion, on n'est souvent pas connecté.
			if Net.is_connected_to_host:
				Net.send_command("logout")
			get_tree().quit()
	_pending_action = ""
