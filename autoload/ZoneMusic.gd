extends Node
## Musique d'ambiance en jeu, choisie selon le biome de la carte courante (MapData.biome).
##
## Game3D appelle play_for_biome() à chaque MapView (_rebuild_map) et stop() en quittant le
## monde. Changer de carte sans changer de biome ne relance pas la piste ; passer à une carte
## sans musique (biome NONE) l'éteint en fondu, et le prochain retour repartira du début.
## Joue sur le bus Music : le slider "Musique" du Menu système (Settings) règle son volume.
##
## Pistes générées par tools/music_gen/ (synthèse, aucun crédit requis) — ne pas retoucher
## les .ogg à la main, modifier le script puis le relancer.

## Biome -> piste et volume de croisière (dB). Les pistes bouclent depuis 0 : elles sont
## construites sans couture (voir tools/music_gen/build_forest_music.py).
const TRACKS := {
	MapData.Biome.FOREST: {"path": "res://assets/audio/music/forest_ambience.ogg", "volume_db": -9.0},
}
const FADE_IN := 4.0
const FADE_OUT := 3.0

## Un lecteur par piste déjà jouée : deux biomes différents se croisent en fondu au lieu de
## se couper.
var _players := {}
var _tweens := {}
var _current_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func play_for_biome(biome: int) -> void:
	var track: Dictionary = TRACKS.get(biome, {})
	var path: String = track.get("path", "")
	if path == _current_path:
		return
	if not _current_path.is_empty():
		_fade_out(_current_path, FADE_OUT)
	_current_path = path
	if path.is_empty():
		return
	var player := _player_for(path)
	if not player.playing:
		player.volume_db = -80.0
		player.play()
	_fade(path, track["volume_db"], FADE_IN)


func stop(fade_out := FADE_OUT) -> void:
	if not _current_path.is_empty():
		_fade_out(_current_path, fade_out)
	_current_path = ""


func _player_for(path: String) -> AudioStreamPlayer:
	if _players.has(path):
		return _players[path]
	var stream := load(path) as AudioStreamOggVorbis
	stream.loop = true
	stream.loop_offset = 0.0
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Music"
	add_child(player)
	_players[path] = player
	return player


func _fade_out(path: String, duration: float) -> void:
	_fade(path, -80.0, duration).finished.connect(func():
		# Un retour sur ce biome pendant le fondu relance _fade, qui tue ce tween (finished
		# n'est alors jamais émis) ; le test couvre un retour pile à la fin du fondu.
		if path != _current_path:
			_players[path].stop()
	)


## Fondu en amplitude linéaire (et non en dB) : sinon la fin d'un fondu de sortie s'entend
## comme une chute brutale, voir MenuMusic._apply_amplitude.
func _fade(path: String, target_db: float, duration: float) -> Tween:
	var player: AudioStreamPlayer = _players[path]
	if _tweens.has(path):
		_tweens[path].kill()
	var tween := create_tween()
	var from := db_to_linear(player.volume_db)
	var to := db_to_linear(target_db)
	tween.tween_method(func(a: float): player.volume_db = linear_to_db(maxf(a, 0.00001)),
		from, to, maxf(duration, 0.01))
	_tweens[path] = tween
	return tween
