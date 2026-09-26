extends PanelContainer
## Barre de menu bas-droite façon Lineage 2 : une rangée de boutons-icônes encadrée donnant
## accès direct à chaque fenêtre (Statut, Inventaire, Compétences, Carte, Menu système). Chaque
## bouton n'est qu'un déclencheur : chaque fenêtre gère sa propre ouverture/fermeture
## (open()/close_window(), voir WindowFrame) et son propre raccourci clavier (P/I/K/M).
## Pas de bouton "Équipement" : cette fenêtre suit toujours l'inventaire (voir InventoryWindow).

@onready var _character_button: Button = %CharacterButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _skills_button: Button = %SkillsButton
@onready var _map_button: Button = %MapButton
@onready var _options_button: Button = %OptionsButton

@onready var _skill_book: Control = %SkillBook
@onready var _inventory_window: Control = %InventoryWindow
@onready var _character_sheet: Control = %CharacterSheetWindow
@onready var _world_map: Control = %WorldMapWindow
@onready var _options_window: Control = %OptionsWindow


func _ready() -> void:
	_setup_button(_character_button, "character", "Statut (P)", _character_sheet)
	_setup_button(_inventory_button, "inventory", "Inventaire (I)", _inventory_window)
	_setup_button(_skills_button, "skills", "Compétences (K)", _skill_book)
	_setup_button(_map_button, "map", "Carte (M)", _world_map)
	_setup_button(_options_button, "options", "Menu système", _options_window)


func _setup_button(button: Button, icon_kind: String, tooltip: String, window: Control) -> void:
	button.text = ""
	button.icon = IconFactory.ui_icon(icon_kind, 28)
	button.tooltip_text = tooltip
	button.pressed.connect(_toggle.bind(window))


func _toggle(window: Control) -> void:
	if window.visible:
		window.close_window()
	else:
		window.open()
