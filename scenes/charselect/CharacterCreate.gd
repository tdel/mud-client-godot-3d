extends Control
## Création de personnage : un seul formulaire (nom + genre/classe), la choréographie
## serveur (ChooseGender/ChooseClass) est enchaînée en interne. Depuis le commit backend
## "Refond le système race/classe : Human unique, Fighter/Mystic, sous-classes niveaux
## 20/40" (48049de, 2026-08-30), il n'y a plus qu'une seule race (Race.HUMAN, choisie en
## dur côté serveur dans CharacterCreate.java) : plus de prompt ChooseRace, donc plus de
## champ Race dans ce formulaire.

@onready var _backdrop: TextureRect = %Backdrop
@onready var _name_field: LineEdit = %NameField
@onready var _gender_option: OptionButton = %GenderOption
@onready var _class_option: OptionButton = %ClassOption
@onready var _error_label: Label = %ErrorLabel
@onready var _create_button: Button = %CreateButton
@onready var _back_button: Button = %BackButton

# [valeur envoyée au serveur, libellé affiché]
const GENDERS := [["man", "Homme"], ["woman", "Femme"]]
const CLASSES := [
	["FIGHTER", "Guerrier"], ["MYSTIC", "Mystique"],
]

var _busy := false


func _ready() -> void:
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	_create_button.pressed.connect(_on_create_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_populate_options(_gender_option, GENDERS)
	_populate_options(_class_option, CLASSES)


func _populate_options(option_button: OptionButton, values: Array) -> void:
	option_button.clear()
	for pair in values:
		option_button.add_item(pair[1])
	option_button.select(0)


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
	Net.send_command("character-create", name_text)


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"CharacterNameTaken":
			_fail("Ce nom est déjà utilisé.")
		"ChooseGender", "InvalidGender":
			Net.send_reply(GENDERS[_gender_option.selected][0])
		"ChooseClass", "InvalidClass":
			Net.send_reply(CLASSES[_class_option.selected][0])
		"NowPlaying":
			_busy = false
			get_tree().change_scene_to_file("res://scenes/game/Game.tscn")
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
	_gender_option.disabled = not enabled
	_class_option.disabled = not enabled


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
