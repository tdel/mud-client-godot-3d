class_name VfxLib
extends RefCounted
## Briques des effets de sorts (voir SpellVfx/CastCircle) : matériaux des shaders dédiés du
## dossier, sprites lumineux, anneaux au sol, colonnes, orbes, systèmes de particules, lumières.
## Tout est procédural (aucune texture), rendu additif sauf la fumée.

const MAGIC_CIRCLE_SHADER := preload("res://scenes/game/vfx/magic_circle.gdshader")
const BEAM_SHADER := preload("res://scenes/game/vfx/vfx_beam.gdshader")
const RING_SHADER := preload("res://scenes/game/vfx/vfx_ring.gdshader")
const ORB_SHADER := preload("res://scenes/game/vfx/vfx_orb.gdshader")
const SPRITE_SHADER := preload("res://scenes/game/vfx/vfx_sprite.gdshader")
const SMOKE_SHADER := preload("res://scenes/game/vfx/vfx_smoke.gdshader")
const CRESCENT_SHADER := preload("res://scenes/game/vfx/vfx_crescent.gdshader")

const SHAPE_GLOW := 0
const SHAPE_SPARK := 1

## Matériaux de draw pass partagés entre systèmes de particules (la couleur vient du
## color_ramp de chaque ParticleProcessMaterial) : clé "forme/énergie" ou "smoke".
static var _particle_materials: Dictionary = {}


static func shader_material(shader: Shader, params: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for key in params:
		mat.set_shader_parameter(key, params[key])
	return mat


static func _no_shadow(inst: GeometryInstance3D) -> void:
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Plan horizontal (normale +Y) de `size` mètres de côté, UV 0..1.
static func ground_quad(size: float, mat: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	_no_shadow(inst)
	return inst


static func magic_circle(color: Color, size: float, params: Dictionary = {}) -> MeshInstance3D:
	var all := {"tint": color}
	all.merge(params, true)
	return ground_quad(size, shader_material(MAGIC_CIRCLE_SHADER, all))


## Anneau au sol : `radius`/`width` en fraction du demi-côté du plan (voir vfx_ring).
static func ring(color: Color, size: float, radius: float, width: float, params: Dictionary = {}) -> MeshInstance3D:
	var all := {"tint": color, "radius": radius, "width": width}
	all.merge(params, true)
	return ground_quad(size, shader_material(RING_SHADER, all))


## Sprite face caméra (lueur ronde ou étincelle), taille en mètres.
static func glow_sprite(color: Color, size: float, energy: float = 1.5, core_white: float = 0.5, shape: int = SHAPE_GLOW) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = shader_material(SPRITE_SHADER, {
		"tint": color, "energy": energy, "core_white": core_white, "shape": shape,
	})
	_no_shadow(inst)
	return inst


## Colonne verticale (ou entonnoir si les rayons diffèrent) de `height` mètres posée sur y = 0
## du parent (voir vfx_beam : head/tail/downward/twist...).
static func beam(color: Color, bottom_radius: float, top_radius: float, height: float, params: Dictionary = {}) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = 1.0
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 32
	mesh.rings = 6
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var all := {"tint": color}
	all.merge(params, true)
	inst.material_override = shader_material(BEAM_SHADER, all)
	inst.scale = Vector3(1.0, height, 1.0)
	inst.position.y = height * 0.5
	_no_shadow(inst)
	return inst


static func orb(color: Color, core_color: Color, radius: float, params: Dictionary = {}) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var all := {"tint": color, "core_tint": core_color}
	all.merge(params, true)
	inst.material_override = shader_material(ORB_SHADER, all)
	_no_shadow(inst)
	return inst


static func crescent(color: Color, size: float, params: Dictionary = {}) -> MeshInstance3D:
	var all := {"tint": color}
	all.merge(params, true)
	return ground_quad(size, shader_material(CRESCENT_SHADER, all))


static func light(color: Color, energy: float, light_range: float) -> OmniLight3D:
	var omni := OmniLight3D.new()
	omni.light_color = color
	omni.light_energy = energy
	omni.omni_range = light_range
	omni.omni_attenuation = 1.4
	omni.shadow_enabled = false
	return omni


## Dégradé de couleur (color_ramp) : `stops` = [[offset, Color], ...].
static func ramp(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(stop[0])
		colors.append(stop[1])
	gradient.offsets = offsets
	gradient.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


## Courbe 0..1 (scale_curve) : `points` = [Vector2(t, valeur), ...].
static func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


## Couleur -> même couleur transparente (fin de color_ramp).
static func clear(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


## ParticleProcessMaterial depuis un dictionnaire d'options (valeurs par défaut raisonnables) :
## direction, spread, velocity (Vector2 min/max), gravity, damping (Vector2), scale (Vector2),
## scale_curve (points), colors (stops de ramp), radial_accel/tangential_accel (Vector2),
## angle (bool, rotation aléatoire), emission : "sphere" (radius) / "ring" (radius, inner, height)
## / "point".
static func process(opts: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = opts.get("direction", Vector3.UP)
	m.spread = opts.get("spread", 180.0)
	var velocity: Vector2 = opts.get("velocity", Vector2(0.5, 1.0))
	m.initial_velocity_min = velocity.x
	m.initial_velocity_max = velocity.y
	m.gravity = opts.get("gravity", Vector3.ZERO)
	var damping: Vector2 = opts.get("damping", Vector2.ZERO)
	m.damping_min = damping.x
	m.damping_max = damping.y
	var scale_range: Vector2 = opts.get("scale", Vector2(0.7, 1.2))
	m.scale_min = scale_range.x
	m.scale_max = scale_range.y
	if opts.has("scale_curve"):
		m.scale_curve = curve(opts["scale_curve"])
	if opts.has("colors"):
		m.color_ramp = ramp(opts["colors"])
	if opts.has("radial_accel"):
		var radial: Vector2 = opts["radial_accel"]
		m.radial_accel_min = radial.x
		m.radial_accel_max = radial.y
	if opts.has("tangential_accel"):
		var tangential: Vector2 = opts["tangential_accel"]
		m.tangential_accel_min = tangential.x
		m.tangential_accel_max = tangential.y
	if opts.get("angle", true):
		m.angle_min = -180.0
		m.angle_max = 180.0
	match str(opts.get("emission", "sphere")):
		"ring":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			m.emission_ring_axis = Vector3.UP
			m.emission_ring_radius = opts.get("radius", 0.5)
			m.emission_ring_inner_radius = opts.get("inner", 0.0)
			m.emission_ring_height = opts.get("height", 0.02)
		"point":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		_:
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = opts.get("radius", 0.1)
	return m


## Système de particules prêt à ajouter (émission lancée par `emit`). opts : one_shot,
## explosiveness, local (coordonnées locales), shape (SHAPE_*), energy, smoke (fumée en mélange
## alpha au lieu d'additif).
static func particles(amount: int, lifetime: float, size: float, process_mat: ParticleProcessMaterial, opts: Dictionary = {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = opts.get("one_shot", false)
	p.explosiveness = opts.get("explosiveness", 0.0)
	p.randomness = opts.get("randomness", 0.3)
	p.local_coords = opts.get("local", false)
	p.process_material = process_mat
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	_no_shadow(p)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _particle_material(
		bool(opts.get("smoke", false)), int(opts.get("shape", SHAPE_GLOW)), float(opts.get("energy", 1.6))
	)
	p.draw_pass_1 = quad
	return p


static func _particle_material(smoke: bool, shape: int, energy: float) -> ShaderMaterial:
	var key := "smoke" if smoke else "%d/%.2f" % [shape, energy]
	if _particle_materials.has(key):
		return _particle_materials[key]
	var mat: ShaderMaterial
	if smoke:
		mat = shader_material(SMOKE_SHADER)
	else:
		mat = shader_material(SPRITE_SHADER, {
			"particles": true, "shape": shape, "energy": energy, "core_white": 0.35,
		})
	_particle_materials[key] = mat
	return mat


## Ajoute `p` sous `parent` à `local_pos` et démarre l'émission.
static func emit(parent: Node, p: GPUParticles3D, local_pos: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	p.position = local_pos
	parent.add_child(p)
	p.emitting = true
	return p


## Libère `node` après `seconds` (tween lié au nœud : rien ne reste si le parent part avant).
static func free_after(node: Node, seconds: float) -> void:
	var tween := node.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(node.queue_free)


## Anime un paramètre de shader de `from` à `to`.
static func tween_param(tween: Tween, mat: ShaderMaterial, param: StringName, from: Variant, to: Variant, duration: float) -> MethodTweener:
	return tween.tween_method(func(value: Variant) -> void: mat.set_shader_parameter(param, value), from, to, duration)


static func mat_of(inst: GeometryInstance3D) -> ShaderMaterial:
	return inst.material_override as ShaderMaterial
