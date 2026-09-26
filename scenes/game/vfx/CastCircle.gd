class_name CastCircle
extends Node3D
## Cercle d'incantation posé aux pieds du lanceur (enfant de son nœud, le suit donc s'il bouge),
## calé sur le temps de cast serveur (castingTimeMs, voir Game3D._on_skill_cast_started) :
##   - intro : le cercle se trace (anneaux, runes, pentagramme) en jaillissant avec un éclat
##     d'étincelles, une onde au sol et un bref trait de lumière vertical ;
##   - pendant le cast : l'anneau extérieur se remplit exactement en `duration` (tête de comète),
##     une couronne de runes flottante monte du sol vers la poitrine, des particules sont aspirées
##     vers le haut, la lumière et la rotation s'intensifient, pulsation sur les derniers 20 % ;
##   - finish(true) : libération (flash, colonne de lumière, gerbe d'étincelles, onde de choc) ;
##   - finish(false) : brisure (le cercle grisonne, vacille, se fragmente, éclats qui tombent,
##     fumée).
## La couleur dépend de l'élément du sort (voir SpellVfx.COLORS).

const RADIUS := 1.1
const FLOAT_RING_RADIUS := 0.6
const FLOAT_RING_TOP := 1.25
const INTRO_MAX := 0.5
const BROKEN_GREY := Color(0.45, 0.45, 0.5)
## Filet de sécurité : si personne n'appelle finish (message serveur perdu), le cercle se brise
## seul ce délai après la fin théorique du cast.
const ORPHAN_TIMEOUT := 3.0

var _color: Color
var _duration := 1.0
var _elapsed := 0.0
var _finished := false
var _spin := 0.0
var _star_spin := 0.0
## Surcroît de lumière animé par les tweens (intro), ajouté à la lumière de charge dans _process.
var _light_boost := 0.0

var _circle: MeshInstance3D
var _circle_mat: ShaderMaterial
var _float_ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _motes: GPUParticles3D
var _light: OmniLight3D
var _intro_tween: Tween


func _init(color: Color, duration_sec: float) -> void:
	_color = color
	_duration = maxf(duration_sec, 0.15)
	name = "CastCircle"


func _ready() -> void:
	_build()
	_play_intro()


func _build() -> void:
	_circle = VfxLib.magic_circle(_color, RADIUS * 2.0, {"energy": 1.6, "reveal": 0.0})
	_circle_mat = VfxLib.mat_of(_circle)
	_circle.position.y = 0.04
	add_child(_circle)

	_float_ring = VfxLib.magic_circle(_color, FLOAT_RING_RADIUS * 2.0, {
		"energy": 1.3, "reveal": 0.0, "show_star": 0.0, "alpha": 0.0,
	})
	_ring_mat = VfxLib.mat_of(_float_ring)
	_float_ring.position.y = 0.1
	add_child(_float_ring)

	# Particules aspirées depuis le bord du cercle vers le haut et le centre, en coordonnées
	# locales pour suivre le lanceur.
	_motes = VfxLib.particles(40, 1.2, 0.1, VfxLib.process({
		"emission": "ring", "radius": RADIUS * 0.9, "inner": RADIUS * 0.75,
		"direction": Vector3.UP, "spread": 12.0, "velocity": Vector2(0.4, 0.9),
		"gravity": Vector3(0, 0.8, 0), "radial_accel": Vector2(-1.2, -0.6),
		"tangential_accel": Vector2(0.8, 1.6), "scale": Vector2(0.6, 1.3),
		"scale_curve": [Vector2(0, 0.2), Vector2(0.25, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, VfxLib.clear(_color)], [0.2, _color], [0.7, _color.lightened(0.4)], [1.0, VfxLib.clear(_color)]],
	}), {"local": true, "shape": VfxLib.SHAPE_SPARK, "energy": 2.0})
	VfxLib.emit(self, _motes)
	_motes.amount_ratio = 0.3

	_light = VfxLib.light(_color, 0.0, 3.2)
	_light.position.y = 0.6
	add_child(_light)


func _play_intro() -> void:
	var intro := minf(INTRO_MAX, _duration * 0.35)
	_circle.scale = Vector3.ONE * 0.3
	_float_ring.scale = Vector3.ONE * 0.3
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.tween_property(_circle, "scale", Vector3.ONE, intro).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(_float_ring, "scale", Vector3.ONE, intro * 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(_intro_tween, _circle_mat, "reveal", 0.0, 1.0, intro * 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(_intro_tween, _circle_mat, "flash", 2.5, 0.0, 0.6).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(_intro_tween, _ring_mat, "reveal", 0.0, 1.0, intro * 1.8)
	VfxLib.tween_param(_intro_tween, _ring_mat, "alpha", 0.0, 0.85, intro * 1.5)
	_intro_tween.tween_property(self, "_light_boost", 0.0, 0.5).from(3.5)

	# Éclat d'étincelles au sol.
	var sparks := VfxLib.particles(28, 0.6, 0.12, VfxLib.process({
		"radius": 0.15, "direction": Vector3.UP, "spread": 85.0, "velocity": Vector2(2.0, 3.5),
		"damping": Vector2(3.0, 5.0), "gravity": Vector3(0, -2.0, 0),
		"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, Color.WHITE], [0.3, _color], [1.0, VfxLib.clear(_color)]],
	}), {"one_shot": true, "explosiveness": 1.0, "shape": VfxLib.SHAPE_SPARK, "energy": 2.2})
	VfxLib.emit(self, sparks, Vector3(0, 0.1, 0))
	VfxLib.free_after(sparks, 1.0)

	_spawn_shockwave(0.15, 0.95, 0.45, 0.06)

	# Bref trait de lumière vertical.
	var flare := VfxLib.beam(_color, 0.3, 0.12, 2.2, {"energy": 2.0, "head": 0.0, "scroll": 3.0, "density": 6.0})
	add_child(flare)
	var flare_mat := VfxLib.mat_of(flare)
	var flare_tween := flare.create_tween()
	VfxLib.tween_param(flare_tween, flare_mat, "head", 0.0, 1.2, 0.18).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(flare_tween, flare_mat, "tail", 0.0, 1.2, 0.35).set_ease(Tween.EASE_IN)
	flare_tween.tween_callback(flare.queue_free)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	_spin += delta * (0.4 + 1.6 * t)
	_star_spin -= delta * (0.2 + 0.7 * t)
	# Pulsation d'imminence sur la fin du cast.
	var pulse := maxf(0.0, (t - 0.8) / 0.2) * (0.5 + 0.5 * sin(_elapsed * 20.0)) * 0.7
	_circle_mat.set_shader_parameter("charge", t)
	_circle_mat.set_shader_parameter("spin", _spin)
	_circle_mat.set_shader_parameter("star_spin", _star_spin)
	_circle_mat.set_shader_parameter("energy", 1.5 + 1.1 * t + pulse)
	_ring_mat.set_shader_parameter("spin", -_spin * 1.7)
	_ring_mat.set_shader_parameter("energy", 1.2 + 1.2 * t + pulse)
	_float_ring.position.y = lerpf(0.1, FLOAT_RING_TOP, eased)
	_motes.amount_ratio = 0.3 + 0.7 * t
	_light.light_energy = 0.3 + 1.4 * t + pulse + _light_boost
	if _elapsed > _duration + ORPHAN_TIMEOUT:
		finish(false)


## Fin de l'incantation : `completed` = sort libéré (fin normale), sinon interrompu/raté.
func finish(completed: bool) -> void:
	if _finished:
		return
	_finished = true
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_motes.emitting = false
	if completed:
		_play_release()
	else:
		_play_break()
	VfxLib.free_after(self, 1.6)


func _play_release() -> void:
	_circle_mat.set_shader_parameter("charge", 1.0)
	_circle_mat.set_shader_parameter("reveal", 1.0)
	_ring_mat.set_shader_parameter("reveal", 1.0)
	var tw := create_tween().set_parallel(true)
	VfxLib.tween_param(tw, _circle_mat, "flash", 3.0, 0.0, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(_circle, "scale", Vector3.ONE * 1.35, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(tw, _circle_mat, "alpha", 1.0, 0.0, 0.5).set_delay(0.08)
	tw.tween_property(_float_ring, "position:y", _float_ring.position.y + 1.6, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_float_ring, "scale", Vector3.ONE * 1.8, 0.4)
	VfxLib.tween_param(tw, _ring_mat, "flash", 2.0, 0.0, 0.4)
	VfxLib.tween_param(tw, _ring_mat, "alpha", 0.85, 0.0, 0.4)
	tw.tween_property(_light, "light_energy", 0.0, 0.5).from(5.0)

	var sparks := VfxLib.particles(40, 0.8, 0.12, VfxLib.process({
		"emission": "ring", "radius": RADIUS * 0.8, "inner": 0.1,
		"direction": Vector3.UP, "spread": 18.0, "velocity": Vector2(3.0, 6.0),
		"damping": Vector2(1.0, 2.5), "gravity": Vector3(0, -3.0, 0),
		"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, Color.WHITE], [0.35, _color], [1.0, VfxLib.clear(_color)]],
	}), {"one_shot": true, "explosiveness": 0.9, "shape": VfxLib.SHAPE_SPARK, "energy": 2.4})
	VfxLib.emit(self, sparks, Vector3(0, 0.1, 0))

	_spawn_shockwave(0.3, 0.98, 0.5, 0.05)

	var pillar := VfxLib.beam(_color, RADIUS * 0.5, RADIUS * 0.38, 3.6, {
		"energy": 1.3, "head": 0.0, "scroll": 3.5, "density": 7.0, "top_fade": 0.5,
	})
	add_child(pillar)
	var pillar_mat := VfxLib.mat_of(pillar)
	var ptw := pillar.create_tween()
	VfxLib.tween_param(ptw, pillar_mat, "head", 0.0, 1.2, 0.2).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(ptw, pillar_mat, "tail", 0.0, 1.2, 0.45).set_ease(Tween.EASE_IN)


func _play_break() -> void:
	var tw := create_tween().set_parallel(true)
	VfxLib.tween_param(tw, _circle_mat, "tint", _color, BROKEN_GREY, 0.2)
	VfxLib.tween_param(tw, _ring_mat, "tint", _color, BROKEN_GREY, 0.2)
	VfxLib.tween_param(tw, _circle_mat, "crack", 0.0, 1.0, 0.55).set_delay(0.15)
	VfxLib.tween_param(tw, _circle_mat, "alpha", 1.0, 0.0, 0.6).set_delay(0.12)
	tw.tween_property(_circle, "scale", Vector3.ONE * 0.85, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# L'anneau flottant retombe au sol puis se brise.
	tw.tween_property(_float_ring, "position:y", 0.06, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	VfxLib.tween_param(tw, _ring_mat, "crack", 0.0, 1.0, 0.4).set_delay(0.28)
	VfxLib.tween_param(tw, _ring_mat, "alpha", 0.85, 0.0, 0.45).set_delay(0.25)
	tw.tween_property(_light, "light_energy", 0.0, 0.3).from(2.2)

	# Vacillement.
	var flicker := create_tween()
	var previous := 0.0
	for level in [1.4, 0.0, 0.9, -0.4, 0.6, -0.6, 0.0]:
		VfxLib.tween_param(flicker, _circle_mat, "flash", previous, level, 0.045)
		previous = level

	var shards := VfxLib.particles(34, 0.85, 0.09, VfxLib.process({
		"emission": "ring", "radius": RADIUS * 0.95, "inner": RADIUS * 0.5,
		"direction": Vector3.UP, "spread": 35.0, "velocity": Vector2(1.0, 2.6),
		"gravity": Vector3(0, -7.0, 0), "scale": Vector2(0.6, 1.2),
		"colors": [[0.0, _color.lightened(0.3)], [0.3, BROKEN_GREY], [1.0, VfxLib.clear(BROKEN_GREY)]],
	}), {"one_shot": true, "explosiveness": 0.85, "shape": VfxLib.SHAPE_SPARK, "energy": 1.6})
	VfxLib.emit(self, shards, Vector3(0, 0.08, 0))

	var smoke := VfxLib.particles(12, 1.3, 0.7, VfxLib.process({
		"emission": "ring", "radius": RADIUS * 0.8, "inner": 0.2,
		"direction": Vector3.UP, "spread": 25.0, "velocity": Vector2(0.25, 0.6),
		"damping": Vector2(0.2, 0.5), "scale": Vector2(0.6, 1.2),
		"scale_curve": [Vector2(0, 0.4), Vector2(1, 1.0)],
		"colors": [[0.0, Color(0.35, 0.35, 0.38, 0.0)], [0.15, Color(0.35, 0.35, 0.38, 0.4)], [1.0, Color(0.3, 0.3, 0.32, 0.0)]],
	}), {"one_shot": true, "explosiveness": 0.7, "smoke": true})
	VfxLib.emit(self, smoke, Vector3(0, 0.15, 0))


## Onde de choc au sol : anneau qui s'élargit de `from_radius` à `to_radius` (fraction du rayon
## du cercle x1.5) en s'estompant.
func _spawn_shockwave(from_radius: float, to_radius: float, duration: float, width: float) -> void:
	var wave := VfxLib.ring(_color, RADIUS * 3.0, from_radius, width, {"energy": 2.2})
	wave.position.y = 0.05
	add_child(wave)
	var wave_mat := VfxLib.mat_of(wave)
	var tw := wave.create_tween().set_parallel(true)
	VfxLib.tween_param(tw, wave_mat, "radius", from_radius, to_radius, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(tw, wave_mat, "alpha", 1.0, 0.0, duration).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(wave.queue_free)
