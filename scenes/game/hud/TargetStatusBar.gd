extends Control
## Fenêtre "cible sélectionnée" (monstre/PNJ/autre joueur), centrée en haut de l'écran.
## Entièrement piloté par Game3D.gd (pas d'abonnement direct à Net.message_received ici),
## seul à savoir quelle entité est actuellement sélectionnée et à retenir nom/niveau/HP de
## chaque entité connue. Port du client 2D (mud-godot/scenes/game/hud/TargetStatusBar.gd)
## sans le bouton "Inviter au groupe" — le groupe est hors scope de ce prototype.

@onready var _name_label: Label = %NameLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel

var _entity_name := ""
var _level := 1


func _ready() -> void:
	visible = false


func show_target(entity_name: String, level: int, current_health: int, max_health: int) -> void:
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


func hide_target() -> void:
	visible = false
