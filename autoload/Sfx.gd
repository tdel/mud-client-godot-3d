extends Node
## Effets sonores (réglables dans Menu système > Son) :
##   - play_ui : sons d'interface non spatialisés, bus "UI" (ouverture/fermeture de fenêtre,
##     fin de recharge d'un skill, équipement d'un objet via play_item...) ;
##   - play_spell : sons de sort spatialisés, attachés au nœud 3D qui les émet (ils suivent
##     le lanceur pendant son incantation et disparaissent avec lui), bus "SFX" ;
##   - play_at_point : son spatialisé posé en un point du monde, qui survit à l'entité
##     concernée (impact/raté sur une cible que le coup peut tuer et faire disparaître) ;
##   - play_sfx : son non spatialisé du bus "SFX" (cible abattue...) ;
##   - play_event : événement de progression non spatialisé du bus "SFX" (montée de niveau).
##
## Les fichiers sont générés par tools/sfx_gen/build_sfx.py dans assets/audio/sfx/ :
## spell_<famille>_<cast|launch|impact>.ogg, combat_<nom>.ogg, event_<nom>.ogg et ui_<nom>.ogg (sources et licences :
## assets/audio/sfx/CREDITS.md). Un son absent (ex. pas d'impact pour un soin) est ignoré.

const DIR := "res://assets/audio/sfx/"
const BUS := &"SFX"
const UI_BUS := &"UI"
const UI_VOICES := 6
## Un même son relancé dans cet intervalle est ignoré : évite l'effet "flam" quand deux
## déclencheurs tombent ensemble (inventaire + équipement qui s'ouvrent d'un bloc, même skill
## posé sur deux slots dont la recharge finit au même instant...).
const DEDUPE_MSEC := 60

## Spatialisation : l'écouteur est à ~20 m du joueur sur l'axe de la caméra isométrique (voir
## Game3D.AUDIO_LISTENER_DISTANCE), d'où unit_size = 20 pour qu'un sort lancé au centre de l'écran
## sonne à plein volume ; au-delà, décroissance douce jusqu'au silence à MAX_DISTANCE.
const UNIT_SIZE := 20.0
const MAX_DISTANCE := 75.0
const PANNING := 0.6

## Élément de sort (SpellVfx.Element) -> famille de sons.
const SPELL_FAMILY := {
	SpellVfx.Element.FIRE: "fire",
	SpellVfx.Element.WATER: "water",
	SpellVfx.Element.WIND: "wind",
	SpellVfx.Element.HOLY: "holy",
	SpellVfx.Element.DARK: "dark",
	SpellVfx.Element.DEBUFF: "dark",
	SpellVfx.Element.ARCANE: "arcane",
	SpellVfx.Element.HEAL: "heal",
	SpellVfx.Element.BUFF: "buff",
	SpellVfx.Element.PHYSICAL: "physical",
}

## Slot d'équipement (EquipmentWindow.SLOT_ORDER) -> famille de sons ui_item_* ; tout slot
## absent (tête, torse, gants, jambes, pieds...) sonne comme une armure.
const EQUIP_FAMILY := {
	"WEAPON": "weapon", "OFF_HAND": "weapon",
	"NECKLACE": "jewel", "LEFT_EARRING": "jewel", "RIGHT_EARRING": "jewel",
	"LEFT_RING": "jewel", "RIGHT_RING": "jewel",
}

var _streams := {}
var _ui_players: Array[AudioStreamPlayer] = []
var _next_ui_player := 0
var _last_played_msec := {}
## Voix réservée aux événements (play_event) : ils durent plusieurs secondes et ne doivent pas
## être coupés par le tourniquet des sons courts.
var _event_player := AudioStreamPlayer.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in UI_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_ui_players.append(player)
	_event_player.bus = BUS
	add_child(_event_player)


func play_ui(sound: String, volume_db: float = 0.0) -> void:
	_play_flat("ui_" + sound, UI_BUS, volume_db)


## Son non spatialisé sur le bus des effets (réglé par le slider "Effets", pas "Interface").
func play_sfx(sound: String, volume_db: float = 0.0) -> void:
	_play_flat(sound, BUS, volume_db)


## Événement de progression, non spatialisé, bus "SFX" : "level_up" -> event_level_up.ogg
## (~3,5 s, montée de niveau du joueur).
func play_event(sound: String, volume_db: float = 0.0) -> void:
	var stream := _stream("event_" + sound)
	if stream == null or _is_duplicate("event_" + sound):
		return
	_event_player.stream = stream
	_event_player.volume_db = volume_db
	_event_player.play()


## Objet équipé (`equipped`) ou retiré de `slot` ; slot inconnu ("") : son d'armure.
func play_item(slot: String, equipped: bool) -> void:
	play_ui("item_%s_%s" % ["equip" if equipped else "unequip", EQUIP_FAMILY.get(slot, "armor")])


## Échantillon joué au relâchement d'un slider de volume (OptionsWindow) : un son du bus
## réglé, pour entendre aussitôt le niveau choisi.
func play_preview(bus: StringName) -> void:
	if bus == BUS:
		_play_flat("spell_holy_impact", BUS, -4.0)
	else:
		play_ui("window_open")


## Son non spatialisé sur `bus`.
func _play_flat(sound: String, bus: StringName, volume_db: float) -> void:
	var stream := _stream(sound)
	if stream == null or _is_duplicate(sound):
		return
	# Tourniquet de voix : un nouveau son coupe le plus ancien plutôt que d'être perdu.
	var player := _ui_players[_next_ui_player]
	_next_ui_player = (_next_ui_player + 1) % _ui_players.size()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.play()


## `phase` : "cast" (début d'incantation), "launch" (libération du sort), "impact" (arrivée
## d'un projectile). Renvoie le lecteur (pour fade_out), ou null si rien n'est joué.
func play_spell(element: int, phase: String, emitter: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var family: String = SPELL_FAMILY.get(element, "arcane")
	return play_at("spell_%s_%s" % [family, phase], emitter, volume_db)


## Comme play_spell, mais posé en un point du monde (voir play_at_point).
func play_spell_at_point(element: int, phase: String, world: Node3D, point: Vector3, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var family: String = SPELL_FAMILY.get(element, "arcane")
	return play_at_point("spell_%s_%s" % [family, phase], world, point, volume_db)


func play_at(sound: String, emitter: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	if emitter == null or not emitter.is_inside_tree():
		return null
	var player := _make_player_3d(sound, volume_db)
	if player == null:
		return null
	player.position = Vector3.UP * 1.0
	emitter.add_child(player)
	player.play()
	return player


## Son posé en `point` (coordonnées monde, pieds de la cible), rattaché à `world` (un nœud 3D
## durable de la scène) plutôt qu'à l'entité : il va à son terme même si l'entité est libérée
## entre-temps (monstre tué par ce coup, EntityDisappeared...), là où un son enfant de la cible
## serait coupé net.
func play_at_point(sound: String, world: Node3D, point: Vector3, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	if world == null or not world.is_inside_tree():
		return null
	var player := _make_player_3d(sound, volume_db)
	if player == null:
		return null
	world.add_child(player)
	player.global_position = point + Vector3.UP * 1.0
	player.play()
	return player


func _make_player_3d(sound: String, volume_db: float) -> AudioStreamPlayer3D:
	var stream := _stream(sound)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = volume_db
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.panning_strength = PANNING
	# Pas d'étouffement avec la distance : à ~20 m de la caméra, le filtre par défaut rendrait
	# tous les sons sourds.
	player.attenuation_filter_db = 0.0
	player.finished.connect(player.queue_free)
	return player


## Éteint un son en cours (incantation interrompue ou terminée) puis libère son lecteur.
func fade_out(player: Variant, duration: float = 0.2) -> void:
	if not is_instance_valid(player) or not (player as Node).is_inside_tree():
		return
	var voice := player as AudioStreamPlayer3D
	var tween := voice.create_tween()
	tween.tween_property(voice, "volume_db", voice.volume_db - 40.0, duration)
	tween.tween_callback(voice.queue_free)


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := DIR + sound + ".ogg"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


func _is_duplicate(key: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played_msec.get(key, -100000)) < DEDUPE_MSEC:
		return true
	_last_played_msec[key] = now
	return false
