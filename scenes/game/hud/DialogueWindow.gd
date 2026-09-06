extends WindowFrame
## Fenêtre de dialogue PNJ (voir Talk.java côté backend, commit "Simplifie le protocole
## réseau pour un client GUI (Godot)" du 2026-09-05) ouverte au clic droit → "Parler" sur un
## PNJ sélectionné (voir Game3D._open_npc_menu/_on_npc_menu_id_pressed). Même principe que
## %ShopWindow : elle ne s'ouvre jamais via une touche/un clic bas-droite, elle s'abonne
## directement à Net.message_received et s'ouvre elle-même dès qu'un "DialogueOptions"
## arrive — Game3D n'a donc besoin d'aucune référence vers cette fenêtre.
##
## Le serveur envoie tout l'arbre de dialogue en un seul message (greeting + options, texte
## de réponse de chaque option RESPONSE déjà inclus) : ce client n'a besoin d'aucun
## aller-retour supplémentaire par choix. Cliquer une option RESPONSE affiche simplement son
## texte à la place du greeting (la fenêtre reste ouverte, mêmes options) ; une option SHOP
## se résout localement via "shop <npcId>" (%ShopWindow s'ouvre elle-même sur ShopCatalog) ;
## une option LEAVE ferme simplement cette fenêtre.

@onready var _npc_name_label: Label = %NpcNameLabel
@onready var _text_label: Label = %TextLabel
@onready var _options_container: VBoxContainer = %OptionsContainer

var _npc_id := ""


func _ready() -> void:
	super._ready()
	set_window_title("Dialogue")
	Net.message_received.connect(_on_message_received)


func _on_message_received(type: String, payload: Dictionary) -> void:
	if type == "DialogueOptions":
		_open_with_dialogue(payload)


func _open_with_dialogue(payload: Dictionary) -> void:
	_npc_id = str(payload.get("npcId", ""))
	_npc_name_label.text = str(payload.get("npcName", "PNJ"))
	_text_label.text = str(payload.get("greeting", ""))
	_build_options(payload.get("options", []))
	show_window()


func _build_options(options: Array) -> void:
	for child in _options_container.get_children():
		child.queue_free()
	for option in options:
		var button := Button.new()
		button.text = str(option.get("label", "..."))
		button.pressed.connect(_on_option_pressed.bind(option))
		_options_container.add_child(button)


func _on_option_pressed(option: Dictionary) -> void:
	match str(option.get("type", "LEAVE")):
		"RESPONSE":
			_text_label.text = str(option.get("response", ""))
		"SHOP":
			Net.send_command("shop", _npc_id)
			close_window()
		_:
			close_window()
