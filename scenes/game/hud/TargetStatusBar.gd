extends Control
## Fenêtre "cible sélectionnée" (monstre/PNJ/autre joueur, ou désormais portail — voir
## show_portal), centrée en haut de l'écran. Entièrement piloté par Game3D.gd (pas
## d'abonnement direct à Net.message_received ici), seul à savoir quelle entité/quel portail
## est actuellement sélectionné et à retenir nom/niveau/HP de chaque entité connue. Port du
## client 2D (mud-godot/scenes/game/hud/TargetStatusBar.gd) sans le bouton "Inviter au
## groupe" — le groupe est hors scope de ce prototype.
##
## show_portal (2026-09-06, demande explicite : "j'aurais aimé que la fenêtre de sélection
## tout en haut fonctionne aussi pour le portail") remplace la barre de vie par un bouton
## "Téléporter" — un portail n'a ni vie ni niveau, mais réutilise cette même fenêtre plutôt
## qu'un second widget dédié, pour rester cohérent avec la sélection d'une entité (et parce
## que les deux sélections sont déjà mutuellement exclusives côté client, voir
## Game3D._select_portal/_handle_left_click).

signal teleport_requested

@onready var _name_label: Label = %NameLabel
@onready var _health_bar_box: Control = %HealthBarBox
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _destination_label: Label = %DestinationLabel
@onready var _teleport_button: Button = %TeleportButton

var _entity_name := ""
var _level := 1


func _ready() -> void:
	visible = false
	UITheme.decorate_corners(self)
	_teleport_button.pressed.connect(func(): teleport_requested.emit())


func show_target(entity_name: String, level: int, current_health: int, max_health: int) -> void:
	_health_bar_box.visible = true
	_destination_label.visible = false
	_teleport_button.visible = false
	_entity_name = entity_name
	set_level(level)
	set_health(current_health, max_health)
	visible = true


func set_level(level: int) -> void:
	_level = level
	_name_label.text = "%s (Niv. %d)" % [_entity_name, _level]


func set_health(current_health: int, max_health: int) -> void:
	_health_bar.max_value = max(max_health, 1)
	_health_bar.value = current_health
	_health_label.text = "%s/%s" % [current_health, max_health]


## Portail sélectionné (voir Game3D._select_portal) : ni niveau ni vie, un nom/titre façon
## personnage ("Clairière"/"Téléporteur", voir Game3D._make_portal_node), la carte de
## destination en rappel, et un bouton "Téléporter" à la place de la barre de vie (voir
## teleport_requested, connecté par Game3D._on_teleport_button_pressed, et set_teleport_enabled
## pour le griser hors de portée).
func show_portal(portal_name: String, target_map_name: String) -> void:
	_entity_name = portal_name
	_name_label.text = portal_name
	_health_bar_box.visible = false
	_destination_label.text = "Vers : %s" % target_map_name
	_destination_label.visible = true
	_teleport_button.visible = true
	visible = true


## Reflète la portée calculée côté client (voir Game3D._update_portal_teleport_range) — le
## serveur reste la seule vérité (message d'erreur NoPortalHere s'il refuse quand même), ceci
## n'évite qu'un aller-retour réseau inutile en désactivant le bouton par avance.
func set_teleport_enabled(enabled: bool) -> void:
	_teleport_button.disabled = not enabled


func hide_target() -> void:
	visible = false
