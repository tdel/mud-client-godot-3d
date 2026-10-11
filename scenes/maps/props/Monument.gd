@tool
class_name Monument
extends EnvProp
## Monument de la place (Gludio) : bassin dont la nappe (monument_water) et les quatre filets
## d'eau des gargouilles (monument_water_fall) sont animés par water.gdshader, clapotis
## spatialisé (bus SFX) et, la nuit, lueur bleutée dans le bassin (groupe LampPost.NIGHT_GROUP).

const WATER_SHADER := preload("res://scenes/maps/common/water.gdshader")
const WATER_SOUND := "res://assets/audio/sfx/env_fountain_loop.ogg"

var _water_materials: Array[ShaderMaterial] = []
var _glow: OmniLight3D


func _ready() -> void:
	super()
	add_to_group(LampPost.NIGHT_GROUP)
	for node_name in ["monument_water", "monument_water_fall"]:
		var mi := find_child(node_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		mat.set_shader_parameter("falling", node_name == "monument_water_fall")
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_materials.append(mat)

	_glow = OmniLight3D.new()
	_glow.position = Vector3(0.0, 1.2, 0.0)
	_glow.light_color = Color(0.45, 0.75, 1.0)
	_glow.omni_range = 7.5
	_glow.shadow_enabled = false
	add_child(_glow, false, Node.INTERNAL_MODE_BACK)

	if not Engine.is_editor_hint() and ResourceLoader.exists(WATER_SOUND):
		var audio := AudioStreamPlayer3D.new()
		var stream: AudioStream = load(WATER_SOUND)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		audio.stream = stream
		audio.bus = &"SFX"
		audio.position = Vector3(0.0, 1.0, 0.0)
		audio.volume_db = -6.0
		audio.unit_size = 12.0
		audio.max_distance = 42.0
		audio.panning_strength = 0.6
		audio.attenuation_filter_db = 0.0
		audio.autoplay = true
		add_child(audio, false, Node.INTERNAL_MODE_BACK)
	set_night_factor(0.0)


func set_night_factor(factor: float) -> void:
	for mat in _water_materials:
		mat.set_shader_parameter("night_glow", factor)
	if _glow != null:
		_glow.visible = factor > 0.01
		_glow.light_energy = 1.0 * factor
