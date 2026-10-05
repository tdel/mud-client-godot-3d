extends WindowFrame
## Menu système (icône bas-droite, voir BottomRightIcons), en trois onglets façon L2 :
##   - Graphisme : affichage (résolution, plein écran, V-Sync, limite et compteur d'images/s)
##     et qualité (anticrénelage, échelle de rendu, ombres, SSAO, lueur, animations et skins
##     des personnages — décochée : "craies", voir Character), voir Settings.GRAPHICS_DEFAULTS ;
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

## Listes déroulantes de l'onglet Graphisme : [section ("display"/"quality"), clé
## Settings.GRAPHICS_DEFAULTS, libellé, [[valeur, texte], ...]].
const GRAPHICS_CHOICES := [
	["display", "max_fps", "Images/s max", [
		[0, "Illimité"], [30, "30"], [60, "60"], [120, "120"], [144, "144"], [240, "240"],
	]],
	["quality", "antialiasing", "Anticrénelage", [
		["off", "Désactivé"], ["fxaa", "FXAA (rapide)"], ["smaa", "SMAA"], ["msaa_2x", "MSAA 2x"],
		["msaa_4x", "MSAA 4x"], ["msaa_8x", "MSAA 8x"], ["taa", "TAA (temporel)"],
	]],
	["quality", "render_scale", "Échelle de rendu", [
		[0.5, "50 % (FSR)"], [0.67, "67 % (FSR)"], [0.75, "75 % (FSR)"], [0.85, "85 % (FSR)"],
		[1.0, "100 %"], [1.5, "150 %"], [2.0, "200 %"],
	]],
	["quality", "shadow_quality", "Ombres", [
		# Settings.SHADOWS_OFF/LOW/MEDIUM/HIGH (constantes d'autoload, hors expression constante).
		[0, "Désactivées"], [1, "Basses"], [2, "Moyennes"], [3, "Hautes"],
	]],
]
## Cases à cocher de l'onglet Graphisme : [section, clé Settings.GRAPHICS_DEFAULTS, libellé].
const GRAPHICS_TOGGLES := [
	["display", "fullscreen", "Plein écran"],
	["display", "vsync", "Synchronisation verticale (V-Sync)"],
	["display", "show_fps", "Afficher les images par seconde"],
	["quality", "ssao", "Occlusion ambiante (SSAO)"],
	["quality", "glow", "Lueur des effets (bloom)"],
]

@onready var _tab_row: HBoxContainer = %TabRow
@onready var _pages: Array[Control] = [%GraphicsPage, %SoundPage, %SystemPage]
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _character_models_check: CheckBox = %CharacterModelsCheck
@onready var _graphics_grids := {"display": %DisplayGrid, "quality": %QualityGrid}
@onready var _graphics_checks := {"display": %DisplayChecks, "quality": %QualityChecks}
@onready var _volume_grid: GridContainer = %VolumeGrid
@onready var _logout_button: Button = %LogoutButton
@onready var _quit_button: Button = %QuitButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmDialog

var _pending_action := ""
var _resolutions: Array[Vector2i] = []
var _pre_game := false
## Clé Settings.GRAPHICS_DEFAULTS -> CheckBox (voir _build_graphics_controls).
var _graphics_toggle_by_key := {}


func _ready() -> void:
	super._ready()
	set_window_title("Menu système")
	_build_tabs()
	_build_graphics_controls()
	_build_volume_rows()
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_character_models_check.set_pressed_no_signal(Settings.character_models_enabled())
	_character_models_check.toggled.connect(Settings.set_character_models_enabled)
	Settings.graphics_changed.connect(_on_graphics_changed)
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
	# En plein écran, la taille est celle de l'écran : choisir une résolution n'a de sens
	# qu'en fenêtré (Settings.set_resolution y repasse d'ailleurs).
	_resolution_option.disabled = bool(Settings.get_graphics("fullscreen"))


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < _resolutions.size():
		Settings.set_resolution(_resolutions[index])


## Une ligne libellé + liste déroulante par GRAPHICS_CHOICES, une case par GRAPHICS_TOGGLES,
## rangées dans la section Affichage ou Qualité. La case "Animations et skins" (scène) reste
## la dernière de la section Qualité.
func _build_graphics_controls() -> void:
	for choice in GRAPHICS_CHOICES:
		var key: String = choice[1]
		var label := Label.new()
		label.text = choice[2]
		label.theme_type_variation = &"StatLabel"
		label.custom_minimum_size.x = 110
		_graphics_grids[choice[0]].add_child(label)

		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.focus_mode = Control.FOCUS_NONE
		var values: Array = []
		var current = Settings.get_graphics(key)
		for entry in choice[3]:
			option.add_item(entry[1], values.size())
			values.append(entry[0])
			if _same_graphics_value(entry[0], current):
				option.select(values.size() - 1)
		option.item_selected.connect(func(index: int) -> void: Settings.set_graphics(key, values[index]))
		_graphics_grids[choice[0]].add_child(option)

	for toggle in GRAPHICS_TOGGLES:
		var key: String = toggle[1]
		var check := CheckBox.new()
		check.text = toggle[2]
		check.focus_mode = Control.FOCUS_NONE
		check.button_pressed = bool(Settings.get_graphics(key))
		check.toggled.connect(func(pressed: bool) -> void: Settings.set_graphics(key, pressed))
		_graphics_checks[toggle[0]].add_child(check)
		_graphics_toggle_by_key[key] = check
	_graphics_checks["quality"].move_child(_character_models_check, -1)


static func _same_graphics_value(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b


## Un réglage peut changer sans passer par sa case (choisir une résolution quitte le plein
## écran) : la case suit, et la liste des résolutions est rafraîchie une fois la fenêtre
## redimensionnée.
func _on_graphics_changed(key: String) -> void:
	if _graphics_toggle_by_key.has(key):
		(_graphics_toggle_by_key[key] as CheckBox).set_pressed_no_signal(bool(Settings.get_graphics(key)))
	if key == "fullscreen":
		await get_tree().process_frame
		if is_inside_tree():
			_refresh_resolutions()


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
