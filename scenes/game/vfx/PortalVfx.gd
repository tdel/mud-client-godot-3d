class_name PortalVfx
extends Node3D
## Effet d'un portail de carte (téléporteur), posé par Game3D (_make_portal_node) à la
## position serveur du portail. Symétrique autour de Y : lisible sous tout angle de caméra,
## sans billboard à réorienter.
##   - cercle de runes au sol qui tourne, pentagramme en contre-rotation ;
##   - colonne d'énergie torsadée (deux cylindres, stries qui montent en sens opposés) ;
##   - cœur lumineux pulsant à mi-hauteur ;
##   - couronnes de runes qui s'élèvent en boucle du sol au sommet en s'effaçant ;
##   - étincelles qui montent en spirale, poussières aspirées du bord vers le centre ;
##   - lumière bleue pulsante.
## set_highlight(true) (portail sélectionné) avive le tout.

const COLOR := Color(0.25, 0.55, 0.95)
const CORE_COLOR := Color(0.78, 0.95, 1.0)
const CIRCLE_RADIUS := 1.7
const COLUMN_RADIUS := 0.85
const HEIGHT := 3.0
const CORE_HEIGHT := 1.3
const RISING_RINGS := 3
const RING_PERIOD := 4.2

var _circle_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _outer: MeshInstance3D
var _outer_mat: ShaderMaterial
var _inner: MeshInstance3D
var _inner_mat: ShaderMaterial
var _core: MeshInstance3D
var _core_mat: ShaderMaterial
var _rings: Array[MeshInstance3D] = []
var _sparks: GPUParticles3D
var _light: OmniLight3D
var _highlight := 0.0
var _highlight_target := 0.0
var _phase := 0.0


func _ready() -> void:
	_phase = fmod(global_position.x * 0.37 + global_position.z * 0.71, TAU)
	var circle := VfxLib.magic_circle(COLOR, CIRCLE_RADIUS * 2.0, {"energy": 1.5})
	_circle_mat = VfxLib.mat_of(circle)
	circle.position.y = 0.09
	add_child(circle)
	var halo := VfxLib.ring(COLOR, CIRCLE_RADIUS * 2.6, 0.0, 0.55, {"energy": 0.5, "fill": 1.0, "alpha": 0.45})
	_halo_mat = VfxLib.mat_of(halo)
	halo.position.y = 0.085
	add_child(halo)

	_outer = VfxLib.beam(COLOR, COLUMN_RADIUS, COLUMN_RADIUS * 0.8, HEIGHT, {
		"energy": 1.3, "twist": 0.55, "scroll": 0.7, "density": 9.0, "top_fade": 0.55, "alpha": 0.75,
	})
	_outer_mat = VfxLib.mat_of(_outer)
	add_child(_outer)
	_inner = VfxLib.beam(CORE_COLOR, 0.42, 0.16, HEIGHT + 0.5, {
		"energy": 0.8, "twist": -1.3, "scroll": 1.5, "density": 6.0, "top_fade": 0.65, "alpha": 0.55,
	})
	_inner_mat = VfxLib.mat_of(_inner)
	add_child(_inner)

	_core = VfxLib.glow_sprite(CORE_COLOR.lerp(COLOR, 0.35), 1.25, 0.8, 0.35)
	_core_mat = VfxLib.mat_of(_core)
	_core.position.y = CORE_HEIGHT
	add_child(_core)

	for i in RISING_RINGS:
		var ring := VfxLib.magic_circle(COLOR, 1.6, {"energy": 1.4, "show_star": 0.0, "alpha": 0.0})
		add_child(ring)
		_rings.append(ring)

	# Étincelles qui montent en spirale le long de la colonne.
	_sparks = VfxLib.particles(40, 2.6, 0.09, VfxLib.process({
		"emission": "ring", "radius": COLUMN_RADIUS, "inner": COLUMN_RADIUS * 0.5,
		"direction": Vector3.UP, "spread": 10.0, "velocity": Vector2(0.5, 1.1),
		"gravity": Vector3(0, 0.25, 0), "tangential_accel": Vector2(1.2, 2.2), "radial_accel": Vector2(-0.3, 0.0),
		"scale": Vector2(0.6, 1.4), "scale_curve": [Vector2(0, 0.2), Vector2(0.2, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, VfxLib.clear(COLOR)], [0.15, CORE_COLOR], [0.6, COLOR], [1.0, VfxLib.clear(COLOR)]],
	}), {"local": true, "shape": VfxLib.SHAPE_SPARK, "energy": 2.2})
	VfxLib.emit(self, _sparks, Vector3(0, 0.1, 0))
	# Poussières lumineuses aspirées depuis le bord du cercle.
	VfxLib.emit(self, VfxLib.particles(30, 1.6, 0.07, VfxLib.process({
		"emission": "ring", "radius": CIRCLE_RADIUS, "inner": CIRCLE_RADIUS * 0.8,
		"direction": Vector3.UP, "spread": 25.0, "velocity": Vector2(0.05, 0.25),
		"gravity": Vector3(0, 0.35, 0), "radial_accel": Vector2(-1.6, -1.0), "tangential_accel": Vector2(0.6, 1.2),
		"scale": Vector2(0.6, 1.2), "scale_curve": [Vector2(0, 0.0), Vector2(0.3, 1.0), Vector2(1, 0.2)],
		"colors": [[0.0, VfxLib.clear(COLOR)], [0.3, COLOR], [1.0, VfxLib.clear(CORE_COLOR)]],
	}), {"local": true, "energy": 1.8}), Vector3(0, 0.1, 0))

	_light = VfxLib.light(COLOR, 1.4, 6.5)
	_light.position.y = CORE_HEIGHT
	add_child(_light)


func set_highlight(on: bool) -> void:
	_highlight_target = 1.0 if on else 0.0


func _process(delta: float) -> void:
	_highlight = move_toward(_highlight, _highlight_target, delta * 4.0)
	var t := GameClock.now() + _phase
	var pulse := 0.5 + 0.5 * sin(t * 2.2)
	var boost := 1.0 + _highlight * 0.8
	_circle_mat.set_shader_parameter("spin", t * 0.35)
	_circle_mat.set_shader_parameter("star_spin", -t * 0.22)
	_circle_mat.set_shader_parameter("energy", (1.4 + 0.3 * pulse) * boost)
	_halo_mat.set_shader_parameter("energy", (0.4 + 0.2 * pulse) * boost)
	_outer.rotation.y = t * 0.45
	_inner.rotation.y = -t * 0.9
	_outer_mat.set_shader_parameter("energy", (1.15 + 0.25 * pulse) * boost)
	_inner_mat.set_shader_parameter("energy", (0.7 + 0.25 * pulse) * boost)
	_core_mat.set_shader_parameter("energy", (0.6 + 0.35 * pulse) * boost)
	_core.scale = Vector3.ONE * (0.85 + 0.2 * pulse + 0.15 * _highlight)
	_core.position.y = CORE_HEIGHT + 0.08 * sin(t * 1.3)
	for i in _rings.size():
		var phase := fmod(t / RING_PERIOD + float(i) / RISING_RINGS, 1.0)
		var ring := _rings[i]
		ring.position.y = 0.12 + phase * (HEIGHT - 0.4)
		ring.scale = Vector3.ONE * lerpf(1.15, 0.55, phase)
		var mat := VfxLib.mat_of(ring)
		mat.set_shader_parameter("alpha", sin(phase * PI) * (0.75 + 0.25 * _highlight))
		mat.set_shader_parameter("spin", -t * 0.9 + i * 2.0)
	_sparks.amount_ratio = 0.7 + 0.3 * _highlight
	_light.light_energy = (1.2 + 0.4 * pulse) * (1.0 + _highlight)
