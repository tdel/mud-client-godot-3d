extends Control
## Création de personnage façon L2 : race, classe (avec description) et sexe choisis par
## boutons à bascule, puis nom. Depuis le commit
## backend "Refond le système race/classe : Human unique, Fighter/Mystic, sous-classes
## niveaux 20/40" (48049de, 2026-08-30), il n'y a plus qu'une seule race (Race.HUMAN,
## choisie en dur côté serveur dans CharacterCreate.java) : pas de champ Race ici.
##
## Protocole stateless depuis le commit backend "Simplifie le protocole réseau pour un
## client GUI (Godot)" (c884a48, 2026-09-05) : "character-create" porte nom + genre +
## classe en un seul envoi séparé par "|" ("<name>|<gender>|<classe>"), plus de
## choréographie ChooseGender/ChooseClass côté serveur.

@onready var _backdrop: TextureRect = %Backdrop
@onready var _name_field: LineEdit = %NameField
@onready var _class_row: HBoxContainer = %ClassRow
@onready var _class_description: Label = %ClassDescription
@onready var _gender_row: HBoxContainer = %GenderRow
@onready var _error_label: Label = %ErrorLabel
@onready var _create_button: Button = %CreateButton
@onready var _back_button: Button = %BackButton

# [valeur envoyée au serveur, libellé affiché]
const GENDERS := [["man", "Homme"], ["woman", "Femme"]]
const CLASSES := [
	["FIGHTER", "Guerrier"], ["MYSTIC", "Mystique"],
]
const CLASS_DESCRIPTIONS := {
	"FIGHTER": "Combattant au corps à corps : solide, il encaisse les coups et frappe fort avec les armes et armures lourdes.",
	"MYSTIC": "Adepte des arts magiques : fragile mais redoutable à distance, il soigne ses alliés et foudroie ses ennemis.",
}
## Icône de chaque classe (réutilise les pictogrammes de compétences/objets).
const CLASS_ICONS := {"FIGHTER": ["item", "Sword", "WEAPON"], "MYSTIC": ["skill", "Arcane", "DAMAGE"]}

var _busy := false
var _gender_index := 0
var _class_index := 0
var _toggle_buttons: Array[Button] = []


func _ready() -> void:
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	MenuMusic.play()
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	_create_button.pressed.connect(_on_create_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_name_field.text_submitted.connect(func(_t: String): _on_create_pressed())
	_build_toggles(_class_row, CLASSES, func(i: int): _set_class(i), true)
	_build_toggles(_gender_row, GENDERS, func(i: int): _gender_index = i, false)
	_set_class(0)
	_name_field.grab_focus()


## Rangée de boutons à bascule exclusifs (façon sélecteurs de L2) à la place de listes
## déroulantes.
func _build_toggles(row: HBoxContainer, values: Array, on_pick: Callable, with_icons: bool) -> void:
	var group := ButtonGroup.new()
	for i in values.size():
		var button := Button.new()
		button.text = values[i][1]
		button.theme_type_variation = &"TabButton"
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == 0
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 30)
		if with_icons:
			var icon_def: Array = CLASS_ICONS.get(values[i][0], [])
			if not icon_def.is_empty():
				button.icon = IconFactory.slot_icon(icon_def[0], icon_def[1], icon_def[2], 24)
		button.pressed.connect(on_pick.bind(i))
		row.add_child(button)
		_toggle_buttons.append(button)


func _set_class(index: int) -> void:
	_class_index = index
	_class_description.text = CLASS_DESCRIPTIONS.get(CLASSES[index][0], "")


func _on_create_pressed() -> void:
	if _busy:
		return
	var name_text := _name_field.text.strip_edges()
	if name_text.is_empty():
		_show_error("Nom requis.")
		return
	_busy = true
	_set_controls_enabled(false)
	_clear_error()
	var gender: String = GENDERS[_gender_index][0]
	var classe: String = CLASSES[_class_index][0]
	Net.send_command("character-create", "%s|%s|%s" % [name_text, gender, classe])


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"CharacterNameTaken":
			_fail("Ce nom est déjà utilisé.")
		"InvalidGender":
			_fail("Genre invalide : %s" % str(payload.get("input", "")))
		"InvalidClass":
			_fail("Classe invalide : %s" % str(payload.get("input", "")))
		"Usage":
			_fail(str(payload.get("usage", "Commande invalide.")))
		"NowPlaying":
			_busy = false
			LoadingScreen.change_scene_to_file("res://scenes/game/Game.tscn")
		"Error":
			_fail(str(payload.get("message", "Erreur inconnue.")))
		_:
			pass


func _fail(message: String) -> void:
	_busy = false
	_set_controls_enabled(true)
	_show_error(message)


func _set_controls_enabled(enabled: bool) -> void:
	_create_button.disabled = not enabled
	_name_field.editable = enabled
	for button in _toggle_buttons:
		button.disabled = not enabled


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/charselect/CharSelect.tscn")


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
