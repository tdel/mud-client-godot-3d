extends CanvasLayer
## Écran de chargement plein écran : même illustration que Login/CharSelect
## (UITheme.get_hero_backdrop_texture) + nom de la carte + barre de progression 0 → 100 %.
##
## Affiché à l'entrée en jeu (CharSelect/CharacterCreate -> change_scene_to_file ci-dessous,
## qui charge Game.tscn en tâche de fond) et à chaque changement de carte (MapView :
## téléporteur, respawn — voir Game3D._rebuild_map/_advance_map_load, qui pilote la suite de
## la barre et appelle finish() une fois la carte instanciée ET rendue quelques images).
## Tant qu'il est actif, toute entrée clavier/souris est avalée dans _input (avant la GUI et
## avant tous les _unhandled_input du jeu : Game3D, Hotbar, fenêtres HUD, SystemMenu) — aucune
## action de jeu possible pendant le chargement.
##
## Autoload placé après UITheme : le Control racine reçoit le thème via
## UITheme._on_node_added (parent CanvasLayer, non-Control).

signal finished

## Au-dessus du HUD (CanvasLayer par défaut, layer 1) et de toute fenêtre de jeu.
const LAYER := 100
## Durée minimale d'un remplissage complet de la barre : la barre affichée rattrape la
## progression réelle à cette vitesse au plus, pour qu'une carte déjà en cache ne donne pas
## un simple flash de quelques images.
const MIN_FILL_SEC := 0.9
## Temps d'arrêt à 100 % avant le fondu, puis durée du fondu vers la carte.
const FULL_HOLD_SEC := 0.15
const FADE_OUT_SEC := 0.35
const BAR_MAX_WIDTH := 720.0
const BAR_HEIGHT := 14.0

var _root: Control
var _backdrop: TextureRect
var _title_label: Label
var _status_label: Label
var _bar: ProgressBar
var _percent_label: Label

var _active := false
var _finishing := false
var _fading := false
var _hold_elapsed := 0.0
## Progression demandée (0..1, jamais en recul) et progression affichée qui la rattrape.
var _target := 0.0
var _shown := 0.0
var _fade_tween: Tween

## Scène en cours de chargement par change_scene_to_file (vide sinon), et part de la barre
## qui lui est allouée — le reste revient au chargement de carte piloté par Game3D.
var _scene_path := ""
var _scene_share := 0.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false
	set_process(false)
	# Perte du serveur en plein chargement : la scène active renvoie à l'écran de connexion
	# (Game3D/CharSelect._on_net_disconnected), l'écran de chargement ne doit ni la masquer
	# ni basculer ensuite sur Game.tscn.
	Net.disconnected.connect(cancel)


## Affiche l'écran (instantanément, sans fondu d'entrée : il doit masquer la carte dès cette
## image). Sans effet s'il est déjà affiché — renvoie alors la progression déjà acquise, pour
## que l'appelant répartisse la suite de la barre entre cette valeur et 1.0 (voir
## Game3D._rebuild_map après change_scene_to_file).
func begin(title: String = "") -> float:
	if not title.is_empty():
		set_title(title)
	if _active and not _fading:
		_finishing = false
		return _target
	if _fade_tween != null:
		_fade_tween.kill()
	_active = true
	_finishing = false
	_fading = false
	_target = 0.0
	_shown = 0.0
	if title.is_empty():
		set_title("")
	_root.modulate.a = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = true
	_refresh_bar()
	set_process(true)
	return 0.0


func set_title(title: String) -> void:
	_title_label.text = title
	_title_label.visible = not title.is_empty()


## Progression réelle (0..1). Jamais en recul : une étape plus lente qu'une autre ne fait pas
## repartir la barre en arrière.
func set_progress(ratio: float) -> void:
	if not _active:
		return
	_target = maxf(_target, clampf(ratio, 0.0, 1.0))


## Chargement terminé : la barre file jusqu'à 100 %, marque un court arrêt puis l'écran se
## fond vers la carte (signal `finished` une fois complètement masqué).
func finish() -> void:
	if not _active:
		return
	_target = 1.0
	_finishing = true


## Masque immédiatement (déconnexion en plein chargement, retour à l'écran de connexion).
func cancel() -> void:
	_scene_path = ""
	if not _active:
		return
	if _fade_tween != null:
		_fade_tween.kill()
	_hide()


func is_active() -> bool:
	return _active


## Remplace get_tree().change_scene_to_file pour l'entrée en jeu : affiche l'écran tout de
## suite, charge `path` en tâche de fond (0 → `share` de la barre) puis bascule dessus. La
## scène d'arrivée poursuit la barre (voir begin) et appelle finish() quand elle est prête.
func change_scene_to_file(path: String, share: float = 0.12) -> void:
	begin()
	var err := ResourceLoader.load_threaded_request(path, "", true)
	if err != OK:
		push_warning("LoadingScreen: chargement impossible de %s (%s)" % [path, error_string(err)])
		get_tree().change_scene_to_file(path)
		return
	_scene_path = path
	_scene_share = share


func _process(delta: float) -> void:
	_poll_scene_load()
	_shown = move_toward(_shown, _target, delta / MIN_FILL_SEC)
	_refresh_bar()
	if _finishing and not _fading and _shown >= 1.0:
		_hold_elapsed += delta
		if _hold_elapsed >= FULL_HOLD_SEC:
			_start_fade_out()
	else:
		_hold_elapsed = 0.0


func _poll_scene_load() -> void:
	if _scene_path.is_empty():
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_scene_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			set_progress(_scene_share * float(progress[0]) if not progress.is_empty() else 0.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed: PackedScene = ResourceLoader.load_threaded_get(_scene_path)
			_scene_path = ""
			set_progress(_scene_share)
			get_tree().change_scene_to_packed(packed)
		_:
			push_warning("LoadingScreen: échec du chargement de %s" % _scene_path)
			var path := _scene_path
			_scene_path = ""
			get_tree().change_scene_to_file(path)


## Aucune entrée ne passe tant que l'écran est affiché (fondu de sortie compris : la carte
## est prête mais pas encore visible).
func _input(event: InputEvent) -> void:
	if _active:
		get_viewport().set_input_as_handled()


func _start_fade_out() -> void:
	_fading = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT_SEC)
	_fade_tween.tween_callback(_hide)


func _hide() -> void:
	_active = false
	_finishing = false
	_fading = false
	_root.visible = false
	set_process(false)
	finished.emit()


func _refresh_bar() -> void:
	_bar.value = _shown * 100.0
	_percent_label.text = "%d %%" % int(floor(_shown * 100.0))
	_status_label.text = "Chargement terminé" if _shown >= 1.0 else "Chargement en cours…"


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "LoadingRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Fond opaque sous l'illustration : aucune image de la carte ne transparaît pendant
	# que la texture se charge ou si l'illustration ne couvre pas tout l'écran.
	var base := ColorRect.new()
	base.color = Color.BLACK
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(base)

	_backdrop = TextureRect.new()
	_backdrop.texture = UITheme.get_hero_backdrop_texture()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	# Même vignettage que Login.tscn, un peu plus appuyé en bas pour détacher la barre.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.88)])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	var vignette := TextureRect.new()
	vignette.texture = gradient_texture
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vignette)

	# Bandeau bas : nom de la carte, barre, état — centré, largeur bornée.
	var anchor := Control.new()
	anchor.anchor_left = 0.5
	anchor.anchor_right = 0.5
	anchor.anchor_top = 1.0
	anchor.anchor_bottom = 1.0
	anchor.offset_left = -BAR_MAX_WIDTH * 0.5
	anchor.offset_right = BAR_MAX_WIDTH * 0.5
	anchor.offset_top = -150.0
	anchor.offset_bottom = -48.0
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(anchor)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(column)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"DisplayTitle"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title_label.add_theme_constant_override("outline_size", 6)
	column.add_child(_title_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.style_progress_bar(_bar, "exp")
	column.add_child(_bar)

	_percent_label = Label.new()
	_percent_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.style_bar_label(_percent_label, 11)
	_bar.add_child(_percent_label)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"DimLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)
