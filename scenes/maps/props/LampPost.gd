@tool
class_name LampPost
extends EnvProp
## Lampadaire de chemin : lanterne allumée la nuit (OmniLight3D avec ombres + vitres
## émissives), éteinte le jour. Piloté par Game3D via le groupe NIGHT_GROUP
## (set_night_factor, 0.0 = plein jour, 1.0 = pleine nuit), au même rythme que le reste de
## l'ambiance jour/nuit. Léger vacillement de flamme quand elle est allumée.

const NIGHT_GROUP := "map_night_lights"
## Centre de la lanterne dans le repère du modèle (voir build_lamp_post, build_environment.py).
const LANTERN_OFFSET := Vector3(0.62, 2.52, 0.0)
const FLAME_COLOR := Color(1.0, 0.7, 0.38)

@export var light_energy := 2.4
@export var light_range := 10.0
@export var cast_shadows := true
## Allume la lanterne dans l'éditeur (aperçu de nuit).
@export var preview_lit := false:
	set(value):
		preview_lit = value
		if is_inside_tree():
			set_night_factor(1.0 if value else 0.0)

var _light: OmniLight3D
var _factor := 0.0
var _phase := 0.0


func _ready() -> void:
	super()
	add_to_group(NIGHT_GROUP)
	_phase = fmod(global_position.x * 1.7 + global_position.z * 0.9, TAU)
	_light = OmniLight3D.new()
	_light.position = LANTERN_OFFSET
	_light.light_color = FLAME_COLOR
	_light.omni_range = light_range
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = cast_shadows
	_light.shadow_bias = 0.08
	_light.distance_fade_enabled = true
	# Distances mesurées depuis la caméra, elle-même à 60 m du joueur (Game3D.CAMERA_DISTANCE).
	_light.distance_fade_begin = 95.0
	_light.distance_fade_length = 15.0
	_light.distance_fade_shadow = 85.0
	add_child(_light, false, Node.INTERNAL_MODE_BACK)
	# Vitres : matériau partagé lamp_glass (EnvMaterials, allumé par set_night_factor), qui
	# devient transparent en damier avec le reste du lampadaire quand il cache le joueur.
	var glass := find_child("lamp_glass", true, false) as MeshInstance3D
	if glass != null:
		glass.material_override = EnvMaterials.get_material("lamp_glass")
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_night_factor(1.0 if (Engine.is_editor_hint() and preview_lit) else 0.0)


func set_night_factor(factor: float) -> void:
	_factor = factor
	if _light == null:
		return
	_light.visible = factor > 0.01
	_light.light_energy = light_energy * factor
	EnvMaterials.set_night_factor(factor)
	set_process(factor > 0.01 and not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	var t := GameClock.now()
	var flicker := 1.0 + 0.05 * sin(t * 9.0 + _phase) + 0.03 * sin(t * 23.0 + _phase * 2.0)
	_light.light_energy = light_energy * _factor * flicker
