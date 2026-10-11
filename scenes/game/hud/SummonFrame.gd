extends WindowFrame
## Fenêtre du serviteur invoqué (Summon Kat the Cat, Corrupted Man, Dark Panther...), façon
## fenêtre de familier de Lineage 2 : nom et niveau, jauge de PV chiffrée, temps restant
## avant son départ, et bouton "Renvoyer" (commande unsummon). Le serviteur suit son maître
## et attaque ce qu'il attaque, sans ordre à donner.
##
## S'abonne elle-même à Net.message_received : s'ouvre sur SummonStatus (apparition, dégâts
## reçus), se ferme sur SummonDismissed. Cliquer le nom cible le serviteur (soins, buffs).

signal summon_clicked(summon_id: String)

@onready var _name_label: Label = %SummonNameLabel
@onready var _level_label: Label = %SummonLevelLabel
@onready var _health_bar: ProgressBar = %SummonHealthBar
@onready var _health_label: Label = %SummonHealthLabel
@onready var _time_label: Label = %SummonTimeLabel
@onready var _dismiss_button: Button = %DismissButton

var _summon_id := ""
## Instant (GameClock) du départ du serviteur, pour le décompte.
var _expires_at := 0.0


func _ready() -> void:
	super._ready()
	set_window_title("Serviteur")
	UITheme.style_progress_bar(_health_bar, "hp")
	UITheme.style_bar_label(_health_label, 10)
	_dismiss_button.pressed.connect(func(): Net.send_command("unsummon"))
	_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_label.tooltip_text = "Cliquer pour cibler votre serviteur"
	_name_label.gui_input.connect(_on_name_input)
	Net.message_received.connect(_on_message_received)
	visible = false


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"SummonStatus":
			var first := _summon_id != str(payload.get("summonId", ""))
			_summon_id = str(payload.get("summonId", ""))
			_name_label.text = str(payload.get("name", "?"))
			_level_label.text = "Niv. %s" % payload.get("level", "?")
			_set_health(int(payload.get("currentHealth", 0)), int(payload.get("maxHealth", 1)))
			_expires_at = GameClock.now() + float(payload.get("secondsRemaining", 0))
			if first or not visible:
				show_window()
		"SummonDismissed":
			_summon_id = ""
			close_window()
		"AttackResult", "SkillCastAnnounced":
			if not _summon_id.is_empty() and str(payload.get("targetId", "")) == _summon_id:
				_set_health(int(payload.get("targetCurrentHealth", payload.get("targetHealthAfter", 0))),
						int(_health_bar.max_value))


func _process(_delta: float) -> void:
	if not visible or _summon_id.is_empty():
		return
	var remaining := maxi(0, int(_expires_at - GameClock.now()))
	_time_label.text = "Reste %d:%02d" % [remaining / 60, remaining % 60]


func _set_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maxi(maximum, 1)
	_health_bar.value = current
	_health_label.text = "%d / %d" % [current, maximum]


func _on_name_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _summon_id.is_empty():
			summon_clicked.emit(_summon_id)
