extends HBoxContainer
## Rangée d'icônes bas-droite façon L2J : accès direct à chaque fenêtre HUD, contrairement
## au menu bas-droite du client 2D (mud-godot/scenes/game/hud/BottomRightMenu.gd) qui cache
## tout derrière un unique bouton "☰" — demandé explicitement en icônes visibles directement
## le 2026-09-03. Chaque bouton n'est qu'un déclencheur : chaque fenêtre gère sa propre
## ouverture/fermeture (open()/close_window(), voir WindowFrame) et son propre raccourci
## clavier (K/I/P, voir leurs _unhandled_input respectifs) — les deux chemins convergent
## donc naturellement sans code dupliqué.
##
## Boutons à abréviation texte ("So"/"Sa"/"Pe"/"Op") remplacés le 2026-09-03 par des
## pictogrammes procéduraux (ZoneAssets3D.make_ui_icon_texture, toujours aucun art externe —
## voir CLAUDE.md) — jugés "plus jolis" par l'utilisateur. _style_icon_button resserre au
## passage le remplissage du bouton (hérité d'UITheme.gd, pensé pour du texte court) pour
## laisser la place à une icône carrée.
##
## Pas de bouton "Équipement" (retiré le 2026-09-06, demandé explicitement) : cette fenêtre
## s'ouvre/se ferme désormais toujours avec InventoryWindow, qui s'en charge seule (voir
## InventoryWindow.gd).

@onready var _skills_button: Button = %SkillsButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _character_button: Button = %CharacterButton
@onready var _options_button: Button = %OptionsButton

@onready var _skill_book: Control = %SkillBook
@onready var _inventory_window: Control = %InventoryWindow
@onready var _character_sheet: Control = %CharacterSheetWindow
@onready var _options_window: Control = %OptionsWindow


func _ready() -> void:
	_skills_button.tooltip_text = "Compétences (K)"
	_inventory_button.tooltip_text = "Inventaire (I)"
	_character_button.tooltip_text = "Fiche de personnage (P)"
	_options_button.tooltip_text = "Options"

	_style_icon_button(_skills_button, "skills")
	_style_icon_button(_inventory_button, "inventory")
	_style_icon_button(_character_button, "character")
	_style_icon_button(_options_button, "options")

	_skills_button.pressed.connect(_toggle.bind(_skill_book))
	_inventory_button.pressed.connect(_toggle.bind(_inventory_window))
	_character_button.pressed.connect(_toggle.bind(_character_sheet))
	_options_button.pressed.connect(func(): _options_window.open())


## Pictogramme procédural + remplissage resserré (voir en-tête de fichier) — dupliquant
## chaque stylebox du thème global (StyleBoxFlat.duplicate()) pour ne toucher que ces 5
## boutons, pas UITheme.gd (partagé par tout le HUD).
func _style_icon_button(button: Button, kind: String) -> void:
	button.text = ""
	button.icon = ZoneAssets3D.make_ui_icon_texture(kind, 40)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBox = button.get_theme_stylebox(style_name, "Button")
		if style is StyleBoxFlat:
			var shrunk: StyleBoxFlat = style.duplicate()
			shrunk.content_margin_left = 6
			shrunk.content_margin_right = 6
			shrunk.content_margin_top = 6
			shrunk.content_margin_bottom = 6
			button.add_theme_stylebox_override(style_name, shrunk)


func _toggle(window: Control) -> void:
	if window.visible:
		window.close_window()
	else:
		window.open()
