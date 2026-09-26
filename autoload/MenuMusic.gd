extends Node
## Musique d'ambiance des écrans hors-jeu (connexion, sélection et création de personnage).
##
## Autoload plutôt que nœud de scène : la musique doit survivre aux change_scene_to_file
## entre Login -> CharSelect -> CharacterCreate sans redémarrer. Chaque écran de menu appelle
## play() dans son _ready (sans effet si elle joue déjà), Game3D appelle stop() en entrant
## dans le monde.
##
## Piste : "Forest of Abandoned Souls" d'Alexandr Zhelanov, CC-BY 4.0 (attribution
## obligatoire) — voir assets/audio/music/CREDITS.md.

const TRACK_PATH := "res://assets/audio/music/forest_of_abandoned_souls.ogg"
## La piste s'ouvre sur une montée depuis le silence et se termine par un fondu : on boucle
## depuis le tout début, la respiration entre deux passages fait partie du morceau.
const LOOP_OFFSET := 0.0
## Volume de croisière : musique de fond, elle ne doit pas couvrir les sons d'interface.
## Le mixage est dense (~-14 dBFS RMS), d'où une atténuation plus forte que d'ordinaire.
const VOLUME_DB := -17.0
const FADE_IN_DEFAULT := 0.4
const FADE_OUT_DEFAULT := 3.0

var _player: AudioStreamPlayer
var _tween: Tween
## Amplitude linéaire 0..1 appliquée par-dessus VOLUME_DB : on anime ça plutôt que les dB
## directement, sinon le fondu s'entend comme une chute brutale en fin de course.
var _amplitude := 0.0
var _stopping := false


func _ready() -> void:
	# La musique continue même si un menu met l'arbre en pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stream := load(TRACK_PATH) as AudioStreamOggVorbis
	stream.loop = true
	stream.loop_offset = LOOP_OFFSET
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.stream = stream
	_player.bus = &"Music"
	add_child(_player)
	_apply_amplitude(0.0)


## Lance (ou maintient) la musique de menu. Si elle joue déjà — passage d'un écran de menu
## à l'autre — elle continue sans coupure ; si elle était en train de s'éteindre, elle
## remonte depuis son volume courant.
func play(fade_in := FADE_IN_DEFAULT) -> void:
	if not _player.playing:
		_apply_amplitude(0.0)
		_player.play()
	elif not _stopping and _amplitude >= 1.0:
		return
	_stopping = false
	_fade_to(1.0, fade_in)


## Éteint la musique en fondu puis arrête le lecteur : le prochain play() repartira du début.
func stop(fade_out := FADE_OUT_DEFAULT) -> void:
	if not _player.playing or _stopping:
		return
	_stopping = true
	_fade_to(0.0, fade_out).finished.connect(func():
		if _stopping:
			_player.stop()
			_stopping = false
	)


func _fade_to(target: float, duration: float) -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply_amplitude, _amplitude, target, maxf(duration, 0.01))
	return _tween


func _apply_amplitude(value: float) -> void:
	_amplitude = value
	_player.volume_db = VOLUME_DB + linear_to_db(maxf(value, 0.0001))
