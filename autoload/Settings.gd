extends Node
## Réglages client persistants (user://settings.cfg) : résolution de la fenêtre, rendu des
## personnages (mannequins animés ou "craies", voir character_models_enabled), réglages
## graphiques (plein écran, anticrénelage, échelle de rendu, ombres, effets, V-Sync, limite
## d'images/s, compteur d'images/s — voir GRAPHICS_DEFAULTS) et niveaux sonores par bus
## (Master = global, SFX = effets de jeu, UI = sons d'interface, Music = musique de fond —
## voir res://default_bus_layout.tres). Édités depuis l'onglet Graphisme/Son du Menu système
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

const SHADOWS_OFF := 0
const SHADOWS_LOW := 1
const SHADOWS_MEDIUM := 2
const SHADOWS_HIGH := 3
## Qualité d'ombres -> [atlas directionnel (soleil/lune), atlas positionnel (lanternes),
## filtre d'ombre douce]. Moyennes = valeurs par défaut de Godot.
const SHADOW_PRESETS := {
	SHADOWS_LOW: [2048, 1024, RenderingServer.SHADOW_QUALITY_HARD],
	SHADOWS_MEDIUM: [4096, 4096, RenderingServer.SHADOW_QUALITY_SOFT_LOW],
	SHADOWS_HIGH: [8192, 4096, RenderingServer.SHADOW_QUALITY_SOFT_HIGH],
}
## Réglages graphiques (section [graphics] de settings.cfg) et leur valeur par défaut, lus et
## écrits par get_graphics/set_graphics. `antialiasing` : off, fxaa, smaa, msaa_2x, msaa_4x,
## msaa_8x, taa ; `render_scale` : rendu 3D à cette fraction de la fenêtre (< 1 : upscaling
## FSR, > 1 : suréchantillonnage) ; `max_fps` : 0 = illimité ; `ssao`/`glow` : effets de
## l'environnement de jeu, appliqués par Game3D (voir graphics_changed).
const GRAPHICS_DEFAULTS := {
	"fullscreen": false,
	"vsync": true,
	"max_fps": 0,
	"show_fps": false,
	"antialiasing": "msaa_4x",
	"render_scale": 1.0,
	"shadow_quality": SHADOWS_MEDIUM,
	"ssao": false,
	"glow": false,
}
const MSAA_MODES := {
	"msaa_2x": Viewport.MSAA_2X, "msaa_4x": Viewport.MSAA_4X, "msaa_8x": Viewport.MSAA_8X,
}
const SCREEN_SPACE_AA_MODES := {
	"fxaa": Viewport.SCREEN_SPACE_AA_FXAA, "smaa": Viewport.SCREEN_SPACE_AA_SMAA,
}

## Émis quand la case "Animations et skins (personnages et monstres)" change (voir
## set_character_models_enabled) : chaque Character bascule aussitôt de rendu.
signal character_models_changed(enabled: bool)
## Émis après chaque set_graphics : ce qui ne relève pas de la fenêtre/du viewport racine
## (ombres du soleil et de la lune, SSAO, lueur) est réappliqué par la scène de jeu.
signal graphics_changed(key: String)

var _config := ConfigFile.new()
## Niveau 0..1 par bus, tel qu'affiché par les sliders (0-100 %).
var _volumes := {BUS_MASTER: 1.0, BUS_SFX: 1.0, BUS_UI: 1.0, BUS_MUSIC: 1.0}
var _character_models := true
var _graphics := GRAPHICS_DEFAULTS.duplicate()
var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_refresh := 0.0


func _ready() -> void:
	_config.load(PATH)
	for bus in BUSES:
		_volumes[bus] = clampf(float(_config.get_value("audio", String(bus), 1.0)), 0.0, 1.0)
		_apply_volume(bus)
	_character_models = bool(_config.get_value("display", "character_models", true))
	for key in GRAPHICS_DEFAULTS:
		var value = _config.get_value("graphics", key, GRAPHICS_DEFAULTS[key])
		if typeof(value) == typeof(GRAPHICS_DEFAULTS[key]) \
				or (GRAPHICS_DEFAULTS[key] is float and value is int):
			_graphics[key] = type_convert(value, typeof(GRAPHICS_DEFAULTS[key]))
	_build_fps_counter()
	# Un --resolution en ligne de commande (enregistrement Movie Maker, voir tools/demo_video)
	# garde la priorité sur la taille et le mode de fenêtre enregistrés.
	var forced_resolution := "--resolution" in OS.get_cmdline_args()
	for key in GRAPHICS_DEFAULTS:
		if key != "fullscreen" or not forced_resolution:
			_apply_graphics.call_deferred(key)
	# La résolution n'est imposée que si le joueur en a choisi une : sinon on garde la taille
	# de project.godot (et celle de l'éditeur quand le jeu y est intégré).
	if _config.has_section_key("display", "resolution") and not forced_resolution \
			and not _graphics.fullscreen:
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


## Vrai (défaut) : personnages en mannequins animés et habillés ; faux : simples bâtons
## colorés sans animation ("craies", voir Character._show_chalk).
func character_models_enabled() -> bool:
	return _character_models


func set_character_models_enabled(enabled: bool) -> void:
	if enabled == _character_models:
		return
	_character_models = enabled
	_config.set_value("display", "character_models", enabled)
	_config.save(PATH)
	character_models_changed.emit(enabled)


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


## Repasse aussi en fenêtré (voir _apply_resolution) : le plein écran est décoché.
func set_resolution(res: Vector2i) -> void:
	_apply_resolution(res)
	_config.set_value("display", "resolution", res)
	if _graphics.fullscreen:
		_graphics.fullscreen = false
		_config.set_value("graphics", "fullscreen", false)
		graphics_changed.emit("fullscreen")
	_config.save(PATH)


## Passe en fenêtré à la taille demandée, centré sur l'écran courant.
func _apply_resolution(res: Vector2i) -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_position(area.position + ((area.size - res) / 2).max(Vector2i.ZERO))


# ---------------------------------------------------------------------------
# Graphisme
# ---------------------------------------------------------------------------

func get_graphics(key: String) -> Variant:
	return _graphics.get(key, GRAPHICS_DEFAULTS.get(key))


func set_graphics(key: String, value: Variant) -> void:
	if not GRAPHICS_DEFAULTS.has(key) or _graphics[key] == value:
		return
	_graphics[key] = value
	_config.set_value("graphics", key, value)
	_config.save(PATH)
	_apply_graphics(key)
	graphics_changed.emit(key)


## Faux si les ombres sont désactivées (qualité SHADOWS_OFF) : Game3D coupe alors celles du
## soleil et de la lune, les lanternes perdent les leurs via l'atlas positionnel vide.
func shadows_enabled() -> bool:
	return int(_graphics.shadow_quality) != SHADOWS_OFF


func _apply_graphics(key: String) -> void:
	var viewport := get_tree().root
	match key:
		"fullscreen":
			if _graphics.fullscreen:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			elif DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var saved = _config.get_value("display", "resolution", null)
				if saved is Vector2i:
					_apply_resolution(saved)
		"vsync":
			DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if _graphics.vsync else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = maxi(int(_graphics.max_fps), 0)
		"show_fps":
			_fps_layer.visible = bool(_graphics.show_fps)
			_fps_refresh = 0.0
		"antialiasing":
			var mode := str(_graphics.antialiasing)
			viewport.msaa_3d = MSAA_MODES.get(mode, Viewport.MSAA_DISABLED)
			viewport.screen_space_aa = SCREEN_SPACE_AA_MODES.get(mode, Viewport.SCREEN_SPACE_AA_DISABLED)
			viewport.use_taa = mode == "taa"
		"render_scale":
			var render_scale := clampf(float(_graphics.render_scale), 0.25, 2.0)
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 1.0 \
					else Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = render_scale
		"shadow_quality":
			var preset: Array = SHADOW_PRESETS.get(int(_graphics.shadow_quality), SHADOW_PRESETS[SHADOWS_MEDIUM])
			RenderingServer.directional_shadow_atlas_set_size(preset[0], true)
			viewport.positional_shadow_atlas_size = preset[1] if shadows_enabled() else 0
			RenderingServer.directional_soft_shadow_filter_set_quality(preset[2])
			RenderingServer.positional_soft_shadow_filter_set_quality(preset[2])


## Compteur d'images/s (case "Afficher les images par seconde") : petit libellé en haut à
## droite, juste à gauche de la minimap, au-dessus de toutes les scènes.
func _build_fps_counter() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 100
	_fps_layer.visible = false
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -290.0
	_fps_label.offset_right = -204.0
	_fps_label.offset_top = 8.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.add_theme_font_size_override("font_size", 13)
	_fps_label.add_theme_color_override("font_color", Color(0.93, 0.86, 0.62))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_layer.add_child(_fps_label)


func _process(delta: float) -> void:
	if not _fps_layer.visible:
		return
	_fps_refresh -= delta
	if _fps_refresh <= 0.0:
		_fps_refresh = 0.25
		_fps_label.text = "%d img/s" % Engine.get_frames_per_second()
