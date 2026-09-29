extends Node
## Réglages client persistants (user://settings.cfg) : résolution de la fenêtre et niveaux
## sonores par bus (Master = global, SFX = effets de jeu, UI = sons d'interface, Music =
## musique de fond — voir
## res://default_bus_layout.tres). Édités depuis l'onglet Graphisme/Son du Menu système
## (OptionsWindow), appliqués au démarrage.

const PATH := "user://settings.cfg"
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const BUSES: Array[StringName] = [BUS_MASTER, BUS_SFX, BUS_UI, BUS_MUSIC]
## Résolutions fenêtrées proposées (filtrées selon l'écran, voir available_resolutions).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]

var _config := ConfigFile.new()
## Niveau 0..1 par bus, tel qu'affiché par les sliders (0-100 %).
var _volumes := {BUS_MASTER: 1.0, BUS_SFX: 1.0, BUS_UI: 1.0, BUS_MUSIC: 1.0}


func _ready() -> void:
	_config.load(PATH)
	for bus in BUSES:
		_volumes[bus] = clampf(float(_config.get_value("audio", String(bus), 1.0)), 0.0, 1.0)
		_apply_volume(bus)
	# La résolution n'est imposée que si le joueur en a choisi une : sinon on garde la taille
	# de project.godot (et celle de l'éditeur quand le jeu y est intégré). Un --resolution en
	# ligne de commande (enregistrement Movie Maker, voir tools/demo_video) garde la priorité.
	if _config.has_section_key("display", "resolution") and not "--resolution" in OS.get_cmdline_args():
		var saved = _config.get_value("display", "resolution")
		if saved is Vector2i:
			_apply_resolution.call_deferred(saved)


func get_volume(bus: StringName) -> float:
	return _volumes.get(bus, 1.0)


func set_volume(bus: StringName, value: float) -> void:
	_volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	_config.set_value("audio", String(bus), _volumes[bus])
	_config.save(PATH)


## Courbe quadratique : un réglage linéaire en amplitude paraît "tout ou rien" à l'oreille
## (50 % ne s'entendrait qu'à peine moins fort) ; au carré, 50 % ≈ -12 dB, plus naturel.
func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Bus audio introuvable : %s (voir default_bus_layout.tres)" % bus)
		return
	var value: float = _volumes[bus]
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value * value, 0.0001)))


func get_resolution() -> Vector2i:
	return DisplayServer.window_get_size()


## Résolutions qui tiennent sur l'écran courant (au moins la plus petite, pour ne jamais
## renvoyer une liste vide sur un petit écran), plus la taille actuelle si elle n'y est pas.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i] = []
	for res in RESOLUTIONS:
		if res.x <= screen.x and res.y <= screen.y:
			result.append(res)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	var current := get_resolution()
	if current.x > 0 and current.y > 0 and not current in result:
		result.append(current)
		result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return result


func set_resolution(res: Vector2i) -> void:
	_apply_resolution(res)
	_config.set_value("display", "resolution", res)
	_config.save(PATH)


## Passe en fenêtré à la taille demandée, centré sur l'écran courant.
func _apply_resolution(res: Vector2i) -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_position(area.position + ((area.size - res) / 2).max(Vector2i.ZERO))
