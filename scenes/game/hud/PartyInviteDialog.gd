extends Control
## Invitation à rejoindre un groupe (PartyInviteReceived), façon boîte de dialogue L2 : nom de
## l'inviteur, jauge du temps restant, Accepter / Refuser ("party-accept"/"party-decline").
## Piloté par Game3D.gd comme DeathPopup : open() sur PartyInviteReceived, close() quand
## l'invitation se conclut (PartyJoined, PartyInviteDeclined — refus ou expiration côté
## serveur). Ne bloque pas le jeu : seul le cadre capte la souris.

## PartyEngine.INVITE_TIMEOUT_MS côté backend.
const TIMEOUT_SEC := 20.0

@onready var _message_label: Label = %MessageLabel
@onready var _time_bar: ProgressBar = %TimeBar
@onready var _accept_button: Button = %AcceptButton
@onready var _decline_button: Button = %DeclineButton

## Nom de l'inviteur de l'invitation affichée, "" si aucune.
var inviter_name := ""
## Vrai une fois "Refuser" cliqué : distingue notre refus de l'expiration dans le journal (le
## serveur envoie le même PartyInviteDeclined dans les deux cas).
var declined := false
var _opened_at := 0.0


func _ready() -> void:
	visible = false
	UITheme.style_progress_bar(_time_bar, "cast")
	_accept_button.pressed.connect(_answer.bind("party-accept"))
	_decline_button.pressed.connect(_answer.bind("party-decline"))


func open(from_name: String) -> void:
	inviter_name = from_name
	_message_label.text = "%s vous invite à rejoindre son groupe." % from_name
	_opened_at = GameClock.now()
	declined = false
	_time_bar.value = 1.0
	_accept_button.disabled = false
	_decline_button.disabled = false
	if not visible:
		Sfx.play_ui("window_open")
	visible = true


func close() -> void:
	visible = false
	inviter_name = ""


func _process(_delta: float) -> void:
	if not visible:
		return
	# La réponse du serveur (PartyInviteDeclined à l'expiration) referme la fenêtre ; la jauge
	# ne fait que montrer le temps qui reste.
	_time_bar.value = clampf(1.0 - (GameClock.now() - _opened_at) / TIMEOUT_SEC, 0.0, 1.0)


func _answer(command: String) -> void:
	declined = command == "party-decline"
	_accept_button.disabled = true
	_decline_button.disabled = true
	Net.send_command(command)
