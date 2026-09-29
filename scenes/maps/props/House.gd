@tool
class_name House
extends EnvProp
## Bâtiment du village (maisons, auberge, forge) : la nuit, ses fenêtres (window_glass) et sa
## lanterne (lamp_glass) s'allument — matériaux partagés, voir EnvMaterials.set_night_factor —
## et une lumière chaude éclaire le seuil. Une forge garde en plus un foyer rougeoyant jour et
## nuit (`fire_offset`). Piloté par Game3D via le groupe LampPost.NIGHT_GROUP.

## Position locale de la lanterne de façade (ZERO : pas de lumière de seuil).
@export var lantern_offset := Vector3.ZERO
@export var lantern_energy := 1.4
@export var lantern_range := 7.0
## Position locale du foyer (ZERO : pas de feu).
@export var fire_offset := Vector3.ZERO
## Allume les lumières dans l'éditeur (aperçu de nuit).
@export var preview_lit := false:
	set(value):
		preview_lit = value
		if is_inside_tree():
			set_night_factor(1.0 if value else 0.0)

const LANTERN_COLOR := Color(1.0, 0.7, 0.38)
const FIRE_COLOR := Color(1.0, 0.5, 0.2)

var _lantern: OmniLight3D
var _fire: OmniLight3D
var _factor := 0.0
var _phase := 0.0


func _ready() -> void:
	super()
	add_to_group(LampPost.NIGHT_GROUP)
	_phase = fmod(global_position.x * 1.3 + global_position.z * 0.7, TAU)
	if lantern_offset != Vector3.ZERO:
		_lantern = _make_light(lantern_offset, LANTERN_COLOR, lantern_range)
	if fire_offset != Vector3.ZERO:
		_fire = _make_light(fire_offset, FIRE_COLOR, 6.0)
	set_night_factor(1.0 if (Engine.is_editor_hint() and preview_lit) else 0.0)


func _make_light(offset: Vector3, color: Color, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = offset
	light.light_color = color
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 95.0
	light.distance_fade_length = 15.0
	add_child(light, false, Node.INTERNAL_MODE_BACK)
	return light


func set_night_factor(factor: float) -> void:
	_factor = factor
	EnvMaterials.set_night_factor(factor)
	if _lantern != null:
		_lantern.visible = factor > 0.01
		_lantern.light_energy = lantern_energy * factor
	set_process((factor > 0.01 and _lantern != null) or _fire != null)
	_process(0.0)


func _process(_delta: float) -> void:
	var t := GameClock.now()
	var flicker := 1.0 + 0.05 * sin(t * 9.0 + _phase) + 0.03 * sin(t * 23.0 + _phase * 2.0)
	if _lantern != null and _factor > 0.01:
		_lantern.light_energy = lantern_energy * _factor * flicker
	if _fire != null:
		var ember := 1.0 + 0.12 * sin(t * 7.0 + _phase) + 0.08 * sin(t * 17.0)
		_fire.light_energy = (0.9 + 1.4 * _factor) * ember
