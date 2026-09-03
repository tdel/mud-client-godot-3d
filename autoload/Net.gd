extends Node
## Couche réseau : une ligne = un message JSON sur socket TCP brute (port 4002).
## Protocole complet documenté dans /CLAUDE.md.

signal connected_to_server
signal connection_failed
signal disconnected
## Émis pour chaque message serveur : type ("Chat", "MapEnter", ...) + payload.
signal message_received(type: String, payload: Dictionary)

const HOST := "::1"
const PORT := 4002

## Types de message qui attendent une réponse `{"reply": "..."}` sur la ligne suivante
## plutôt qu'une commande `{"verb": ...}` normale (voir Connection.requestBlocking côté
## serveur : login/register (mot de passe), création de perso (genre/classe — plus de
## race depuis le commit backend "Refond le système race/classe..." 48049de,
## 2026-08-30, une seule race Human choisie en dur côté serveur), dialogue et boutique
## PNJ).
const PROMPT_TYPES := [
	"RequestPassword", "ConfirmPassword",
	"ChooseGender", "ChooseClass",
	"DialogueOptions", "ShopCatalog",
]

var awaiting_reply := false
var is_connected_to_host := false

var _peer: StreamPeerTCP
var _buffer := PackedByteArray()


func connect_to_server() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = StreamPeerTCP.new()
	_buffer = PackedByteArray()
	awaiting_reply = false
	is_connected_to_host = false
	var err := _peer.connect_to_host(HOST, PORT)
	if err != OK:
		push_warning("Net: connect_to_host a échoué (%s)" % error_string(err))
		connection_failed.emit()
		_peer = null
		return
	set_process(true)


func close() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_buffer = PackedByteArray()
	awaiting_reply = false
	if is_connected_to_host:
		is_connected_to_host = false
		disconnected.emit()
	set_process(false)


func send_command(verb: String, argument: String = "") -> void:
	_send_line({"verb": verb, "argument": argument})


func send_reply(value: String) -> void:
	_send_line({"reply": value})


func _send_line(obj: Dictionary) -> void:
	if _peer == null or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		push_warning("Net: pas connecté, message perdu: %s" % JSON.stringify(obj))
		return
	var line := JSON.stringify(obj) + "\n"
	_peer.put_data(line.to_utf8_buffer())


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not is_connected_to_host:
				is_connected_to_host = true
				connected_to_server.emit()
			var available := _peer.get_available_bytes()
			if available > 0:
				var result: Array = _peer.get_data(available)
				if result[0] == OK:
					_buffer.append_array(result[1])
					_drain_buffer()
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			if is_connected_to_host:
				is_connected_to_host = false
				disconnected.emit()
			else:
				connection_failed.emit()
			_peer = null
			set_process(false)
		StreamPeerTCP.STATUS_CONNECTING:
			pass


func _drain_buffer() -> void:
	while true:
		var newline_index := _buffer.find(10) # '\n'
		if newline_index == -1:
			break
		var line_bytes := _buffer.slice(0, newline_index)
		_buffer = _buffer.slice(newline_index + 1)
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if not line.is_empty():
			_handle_line(line)


func _handle_line(line: String) -> void:
	var json := JSON.new()
	if json.parse(line) != OK:
		push_warning("Net: ligne JSON invalide ignorée: %s" % line)
		return
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var type: String = data.get("type", "")
	var payload = data.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		payload = {}
	awaiting_reply = PROMPT_TYPES.has(type)
	message_received.emit(type, payload)
