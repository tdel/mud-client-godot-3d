@tool
class_name Teleporter
extends EnvProp
## Socle de téléporteur, posé sous un portail de carte (PortalMarker3D, même position) — au
## bord de la carte, là où la route en sort. Le portail lui-même (colonne d'énergie, cercle de
## runes animé) est dessiné par Game3D (PortalVfx) à partir du PortalAppeared serveur ; le socle
## ajoute la couronne de runes gravées qui pulse (matériau partagé rune_glow), quatre cristaux
## qui flottent au sommet des obélisques et des rayons d'énergie qui les relient à la colonne,
## plus un halo bleuté plus fort la nuit (groupe LampPost.NIGHT_GROUP).

const GLOW_COLOR := Color(0.35, 0.62, 1.0)
const BEAM_SHADER := preload("res://scenes/maps/props/teleporter_beam.gdshader")
## Cristaux (repère du modèle, voir build_teleporter dans tools/env_gen/build_village.py) et
## point de la colonne où convergent les rayons.
const CRYSTAL_OFFSET := 2.404
const CRYSTAL_HEIGHT := 2.95
const BEAM_TARGET := Vector3(0.0, 2.1, 0.0)

var _light: OmniLight3D
var _crystals: Node3D
var _beams: Array[MeshInstance3D] = []
var _factor := 0.0
var _phase := 0.0


func _ready() -> void:
	super()
	add_to_group(LampPost.NIGHT_GROUP)
	_phase = fmod(global_position.x * 0.9 + global_position.z * 1.7, TAU)
	_crystals = find_child("teleporter_crystals", true, false) as Node3D
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 1.4, 0.0)
	_light.light_color = GLOW_COLOR
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 95.0
	_light.distance_fade_length = 15.0
	add_child(_light, false, Node.INTERNAL_MODE_BACK)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.035
	beam_mesh.bottom_radius = 0.035
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 6
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = BEAM_SHADER
	for i in 4:
		var beam := MeshInstance3D.new()
		beam.mesh = beam_mesh
		beam.material_override = beam_mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam, false, Node.INTERNAL_MODE_BACK)
		_beams.append(beam)
	set_night_factor(0.0)


func set_night_factor(factor: float) -> void:
	_factor = factor
	EnvMaterials.set_night_factor(factor)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Matériau partagé : même pulsation pour tous les téléporteurs (horloge commune).
	var pulse := 1.0 + 0.3 * sin(now * 2.1)
	var bob := 0.1 * sin(now * 1.4 + _phase)
	if _crystals != null:
		_crystals.position.y = bob
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in _beams.size():
		var c: Vector2 = corners[i] * CRYSTAL_OFFSET
		_place_beam(_beams[i], Vector3(c.x, CRYSTAL_HEIGHT + bob, c.y), BEAM_TARGET)
	_light.light_energy = (0.35 + 1.6 * _factor) * pulse
	var rune := EnvMaterials.get_material("rune_glow") as ShaderMaterial
	if rune != null:
		rune.set_shader_parameter("emission_energy", EnvMaterials.emission_energy("rune_glow") * pulse)


## Cylindre de hauteur 1 étiré de `from` à `to` (repère local).
func _place_beam(beam: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var axis := to - from
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	var z := x.cross(y)
	beam.transform = Transform3D(Basis(x, y * axis.length(), z), (from + to) * 0.5)
