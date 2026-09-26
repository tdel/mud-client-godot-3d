@tool
class_name Fountain
extends EnvProp
## Fontaine en fonctionnement : nappes d'eau animées (water.gdshader) sur les trois maillages
## fountain_water_* du modèle, jet central qui retombe dans la vasque haute, gouttes qui
## débordent de la vasque, éclaboussures au pied du rideau d'eau, clapotis spatialisé
## (bus SFX) et, la nuit, une lueur bleutée dans le bassin (groupe LampPost.NIGHT_GROUP).

const WATER_SHADER := preload("res://scenes/maps/common/water.gdshader")
const WATER_SOUND := "res://assets/audio/sfx/env_fountain_loop.ogg"
const JET_ORIGIN := Vector3(0.0, 2.36, 0.0)
const UPPER_RIM := Vector3(0.0, 1.74, 0.0)
const LOW_WATER_Y := 0.5

var _water_materials: Array[ShaderMaterial] = []
var _glow: OmniLight3D


func _ready() -> void:
	super()
	add_to_group(LampPost.NIGHT_GROUP)
	for node_name in ["fountain_water_low", "fountain_water_high", "fountain_water_fall"]:
		var mi := find_child(node_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		mat.set_shader_parameter("falling", node_name == "fountain_water_fall")
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_materials.append(mat)

	_add_particles("Jet", JET_ORIGIN, 110, 0.7, _jet_material(), 0.055)
	_add_particles("Overflow", UPPER_RIM, 220, 0.55, _overflow_material(), 0.04)
	_add_particles("Splash", Vector3(0.0, LOW_WATER_Y, 0.0), 140, 0.38, _splash_material(), 0.07)

	_glow = OmniLight3D.new()
	_glow.position = Vector3(0.0, 0.9, 0.0)
	_glow.light_color = Color(0.45, 0.75, 1.0)
	_glow.omni_range = 6.5
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
		audio.volume_db = -5.0
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
		_glow.light_energy = 0.9 * factor


func _add_particles(node_name: String, origin: Vector3, amount: int, lifetime: float,
		process: ParticleProcessMaterial, size: float) -> void:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = origin
	particles.amount = amount
	particles.lifetime = lifetime
	particles.process_material = process
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-2.5, -2.5, -2.5), Vector3(5, 5, 5))
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 1.6)
	quad.material = _drop_material()
	particles.draw_pass_1 = quad
	add_child(particles, false, Node.INTERNAL_MODE_BACK)


func _drop_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.82, 0.92, 1.0, 0.75)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.1
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.35, 0.45)
	return mat


func _jet_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 16.0
	m.initial_velocity_min = 1.9
	m.initial_velocity_max = 2.4
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.7
	m.scale_max = 1.2
	return m


func _overflow_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 0.97
	m.emission_ring_inner_radius = 0.9
	m.emission_ring_height = 0.0
	m.direction = Vector3.DOWN
	m.spread = 5.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.3
	m.radial_velocity_min = 0.25
	m.radial_velocity_max = 0.45
	m.gravity = Vector3(0, -9.8, 0)
	return m


func _splash_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 1.22
	m.emission_ring_inner_radius = 1.1
	m.emission_ring_height = 0.0
	m.direction = Vector3.UP
	m.spread = 35.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.1
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.6
	m.scale_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0.3))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	m.scale_curve = fade_tex
	return m
