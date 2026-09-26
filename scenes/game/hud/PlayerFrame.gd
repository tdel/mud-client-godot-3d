extends Control
## Fenêtre de statut en haut à gauche du HUD, façon Lineage 2 : niveau dans un petit
## cartouche + nom, puis jauges HP (rouge) / MP (bleue) / EXP (dorée, pourcentage à deux
## décimales) étiquetées à gauche. Entièrement piloté par Game3D.gd (pas
## d'abonnement Net propre), même principe que TargetStatusBar.gd — Game3D.gd est seul à
## savoir agréger nos PV courants (_entity_vitals_by_key[PLAYER_KEY], alimenté par
## GamePlayerStats/RegenTick/AttackResult/CastResult/SkillCastAnnounced/PlayerRespawned) et
## notre mana/XP (GameState).
##
## Cliquer sur ce cadre nous sélectionne nous-même (`self_clicked`, écouté par Game3D.gd) —
## demandé explicitement pour pouvoir cibler un sort de soin (Heal) sur soi, la capsule du
## joueur n'étant pas cliquable en 3D (`pickable=false`, voir _make_entity_node). Le `Panel`
## (voir .tscn) passe en `mouse_filter=STOP` pour capter le clic ; les autres nœuds du cadre
## restent en `IGNORE` pour le laisser remonter jusqu'au Panel.

signal self_clicked

@onready var _panel: Control = $Panel
@onready var _level_label: Label = %LevelLabel
@onready var _name_label: Label = %NameLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _mana_label: Label = %ManaLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _xp_label: Label = %XpLabel


func _ready() -> void:
	_panel.gui_input.connect(_on_panel_gui_input)
	_panel.tooltip_text = "Cliquer pour se cibler soi-même"
	UITheme.style_progress_bar(_health_bar, "hp")
	UITheme.style_progress_bar(_mana_bar, "mp")
	UITheme.style_progress_bar(_xp_bar, "exp")
	for label in [_health_label, _mana_label]:
		UITheme.style_bar_label(label, 11)
	UITheme.style_bar_label(_xp_label, 9)


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		self_clicked.emit()
		accept_event()


func set_identity(character_name: String, level: int) -> void:
	_name_label.text = character_name
	_level_label.text = str(level)


func set_health(current: int, max_value: int) -> void:
	_health_bar.max_value = max(max_value, 1)
	_health_bar.value = current
	_health_label.text = "%s / %s" % [current, max_value]


func set_mana(current: int, max_value: int) -> void:
	_mana_bar.max_value = max(max_value, 1)
	_mana_bar.value = current
	_mana_label.text = "%s / %s" % [current, max_value]


## `xp_for_next_level <= xp_for_current_level` : niveau maximum atteint — barre pleine
## plutôt qu'une division par zéro. Pourcentage à deux décimales, comme dans L2.
func set_xp(xp: int, xp_for_current_level: int, xp_for_next_level: int) -> void:
	var span := xp_for_next_level - xp_for_current_level
	if span <= 0:
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_label.text = "100.00%"
		return
	_xp_bar.max_value = span
	var progress := clampf(xp - xp_for_current_level, 0.0, span)
	_xp_bar.value = progress
	_xp_label.text = "%.2f%%" % (progress / span * 100.0)
