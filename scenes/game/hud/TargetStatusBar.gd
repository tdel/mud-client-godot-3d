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

@onready var _panel: Control = %Panel
@onready var _name_label: Label = %NameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _health_bar_box: Control = %HealthBarBox
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _destination_label: Label = %DestinationLabel
@onready var _teleport_button: Button = %TeleportButton

var _entity_name := ""
var _level := 1


func _ready() -> void:
	visible = false
	UITheme.style_progress_bar(_health_bar, "hp")
	UITheme.style_bar_label(_health_label, 10)
	_panel.minimum_size_changed.connect(_fit_to_content)
	_teleport_button.pressed.connect(func(): teleport_requested.emit())


## La fenêtre garde son centre horizontal et s'ajuste en hauteur au contenu (barre de vie
## pour une entité, destination + bouton pour un portail).
func _fit_to_content() -> void:
	offset_bottom = offset_top + _panel.get_combined_minimum_size().y


func show_target(entity_name: String, level: int, current_health: int, max_health: int) -> void:
	_health_bar_box.visible = true
	_destination_label.visible = false
	_teleport_button.visible = false
	_entity_name = entity_name
	_name_label.text = entity_name
	set_level(level)
	set_health(current_health, max_health)
	if max_health <= 0:
		# PNJ : ni vie ni niveau transmis — juste le nom, en bleu clair comme dans L2.
		_health_bar_box.visible = false
		_level_label.visible = false
		_name_label.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0))
	visible = true
	_fit_to_content()


## Niveau affiché devant le nom, nom teinté selon l'écart de niveau avec le joueur (gris =
## sans danger ... violet = très dangereux), comme les cibles de Lineage 2.
func set_level(level: int) -> void:
	_level = level
	_level_label.visible = true
	_level_label.text = "Niv. %d" % _level
	var player_level := int(GameState.player_stats.get("level", level))
	_name_label.add_theme_color_override("font_color", UITheme.level_diff_color(level, player_level))


func set_health(current_health: int, max_health: int) -> void:
	if max_health > 0 and not _health_bar_box.visible and not _destination_label.visible:
		_health_bar_box.visible = true
	_health_bar.max_value = max(max_health, 1)
	_health_bar.value = current_health
	_health_label.text = "%s / %s" % [current_health, max_health]


## Portail sélectionné (voir Game3D._select_portal) : ni niveau ni vie — nom, destination et
## bouton "Téléporter" (grisé hors de portée, voir set_teleport_enabled).
func show_portal(portal_name: String, target_map_name: String) -> void:
	_entity_name = portal_name
	_name_label.text = portal_name
	_name_label.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0))
	_level_label.visible = false
	_health_bar_box.visible = false
	_destination_label.text = "Vers : %s" % target_map_name
	_destination_label.visible = true
	_teleport_button.visible = true
	visible = true
	_fit_to_content()


## Reflète la portée calculée côté client (voir Game3D._update_portal_teleport_range) — le
## serveur reste la seule vérité.
func set_teleport_enabled(enabled: bool) -> void:
	_teleport_button.disabled = not enabled


func hide_target() -> void:
	visible = false
