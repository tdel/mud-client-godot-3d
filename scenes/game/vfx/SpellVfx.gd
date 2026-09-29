class_name SpellVfx
extends Node3D
## Effets visuels des sorts (instancié sous World par Game3D, transform identité) :
##   - start_cast : cercle d'incantation au sol, couleur selon l'élément, calé sur le temps de
##     cast (voir CastCircle) ;
##   - play_projectile : projectile propre à chaque élément (boule de feu, orbe d'eau, lames de
##     vent, orbe générique) qui suit sa cible, puis impact dédié (explosion, éclaboussure,
##     tornade...) ;
##   - play_on_target : soin (colonne de lumière qui part du sol et monte vers le ciel), buff
##     (anneaux qui s'élèvent), debuff (sceau qui descend du dessus de la tête jusqu'aux pieds),
##     sinon impact de l'élément.
## Le protocole ne transmet que le nom du sort : l'élément est déduit par ELEMENT_BY_SKILL
## (catalogue mud-server-java src/main/resources/data/skills/skills.xml).

## ESCAPE : Teleport du Scroll of Escape (pentagramme blanc, puis ascension, voir play_escape).
enum Element { FIRE, WATER, WIND, HOLY, DARK, ARCANE, HEAL, BUFF, DEBUFF, PHYSICAL, ESCAPE }

const DEFAULT_ELEMENT := Element.ARCANE
const ELEMENT_BY_SKILL := {
	# Compétences L2 des classes de base Human Fighter / Human Mystic.
	"Power Strike": Element.PHYSICAL, "Mortal Blow": Element.PHYSICAL, "Power Shot": Element.PHYSICAL,
	"Relax": Element.BUFF, "Ice Bolt": Element.WATER, "Vampiric Touch": Element.DARK,
	"Self Heal": Element.HEAL, "Battle Heal": Element.HEAL, "Group Heal": Element.HEAL, "Cure Poison": Element.HEAL,
	"Shield": Element.BUFF, "Curse: Poison": Element.DEBUFF,
	"Flame Strike": Element.FIRE, "Prominence": Element.FIRE,
	"Aqua Strike": Element.WATER,
	"Wind Strike": Element.WIND, "Twister": Element.WIND,
	"Solar Strike": Element.HOLY,
	"Death Spike": Element.DARK,
	"Heal": Element.HEAL, "Mass Heal": Element.HEAL,
	"Might": Element.BUFF, "Focus": Element.BUFF, "Empower": Element.BUFF,
	"Rage": Element.BUFF, "Guidance": Element.BUFF, "Bulwark": Element.BUFF,
	"Curse: Doom": Element.DEBUFF, "Curse: Weakness": Element.DEBUFF,
	"Teleport": Element.ESCAPE,
}
## Jaune = soin/buff, bleu = eau, blanc = vent et téléportation, rouge = feu, violet = debuff.
const COLORS := {
	Element.FIRE: Color(1.0, 0.16, 0.04),
	Element.WATER: Color(0.15, 0.5, 1.0),
	Element.WIND: Color(0.9, 0.95, 1.0),
	Element.HOLY: Color(1.0, 0.93, 0.65),
	Element.DARK: Color(0.4, 0.12, 0.55),
	Element.ARCANE: Color(0.55, 0.45, 1.0),
	Element.HEAL: Color(1.0, 0.8, 0.2),
	Element.BUFF: Color(1.0, 0.8, 0.2),
	Element.DEBUFF: Color(0.65, 0.2, 1.0),
	Element.PHYSICAL: Color(1.0, 0.85, 0.6),
	Element.ESCAPE: Color(0.96, 0.97, 1.0),
}

const CHEST_HEIGHT := 1.0
const HAND_HEIGHT := 1.25
## Au-dessus de la tête (mannequin : 1.78 m au plus) pour le sceau de debuff.
const ABOVE_HEAD_HEIGHT := 2.45

const FIRE_RAMP := [
	[0.0, Color(1.0, 0.95, 0.6, 1.0)], [0.25, Color(1.0, 0.5, 0.1, 0.95)],
	[0.65, Color(0.75, 0.1, 0.02, 0.6)], [1.0, Color(0.2, 0.02, 0.0, 0.0)],
]
const SMOKE_RAMP := [
	[0.0, Color(0.12, 0.1, 0.1, 0.0)], [0.2, Color(0.14, 0.11, 0.1, 0.45)], [1.0, Color(0.1, 0.1, 0.1, 0.0)],
]


## Projectile propre à une compétence plutôt qu'à son élément : éclat de glace (Ice Bolt),
## flèche (Power Shot, physique).
const PROJECTILE_STYLE_BY_SKILL := {"Ice Bolt": "ice", "Power Shot": "arrow"}
## Couleur de l'énergie qui charge l'arme pendant une compétence martiale.
const WEAPON_CHARGE_COLORS := {
	"Power Strike": Color(1.0, 0.62, 0.2), "Mortal Blow": Color(1.0, 0.15, 0.12), "Power Shot": Color(1.0, 0.88, 0.45),
}
const POISON_COLOR := Color(0.45, 0.95, 0.2)
const POISON_DARK := Color(0.32, 0.06, 0.42)
const DRAIN_COLOR := Color(1.0, 0.12, 0.2)


static func projectile_style_for_skill(skill_name: String) -> String:
	return PROJECTILE_STYLE_BY_SKILL.get(skill_name, "")


## Compétence (non magique) animée par un projectile : son impact et son raté se jouent à
## l'arrivée (voir Game3D._on_skill_projectile_launched).
static func is_projectile_skill(skill_name: String) -> bool:
	return PROJECTILE_STYLE_BY_SKILL.get(skill_name, "") == "arrow"


static func element_for_skill(skill_name: String) -> int:
	return ELEMENT_BY_SKILL.get(skill_name, DEFAULT_ELEMENT)


static func color_of(element: int) -> Color:
	return COLORS.get(element, Color.WHITE)


## Les compétences physiques (Power Strike...) n'ont pas de cercle magique.
static func has_cast_circle(element: int) -> bool:
	return element != Element.PHYSICAL


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Cercle d'incantation sous `caster`, à terminer par CastCircle.finish(completed).
## `charged` : cast chargé d'un spiritshot (couronnes flottantes, voir CastCircle).
func start_cast(caster: Node3D, element: int, duration_sec: float, charged: bool = false) -> CastCircle:
	var circle := CastCircle.new(color_of(element), duration_sec, charged)
	caster.add_child(circle)
	return circle


func play_on_target(target: Node3D, element: int) -> void:
	if target == null or not target.is_inside_tree():
		return
	match element:
		Element.HEAL:
			_play_heal(target)
		Element.BUFF:
			_play_buff(target)
		Element.DEBUFF:
			_play_debuff(target)
		_:
			play_impact(target.global_position, element)


## Fin d'un Scroll of Escape (CharacterTeleporting) : éclat blanc au sol, colonne de lumière
## jusqu'au ciel dont la base se détache et monte, halo qui enveloppe le corps puis s'élève en
## s'estompant, étincelles aspirées vers le haut. Posé dans le monde (pas sous `target`) : le
## personnage disparaît de la carte avant la fin de l'effet. `duration_sec` = délai serveur
## avant la téléportation (delayMs).
func play_escape(target: Node3D, duration_sec: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var color := color_of(Element.ESCAPE)
	var d := maxf(duration_sec, 0.6)
	var root := _spawn_root(target.global_position, d + 2.0)

	_ground_wave(root, color, 3.6, 0.1, 0.95, 0.7, 0.06, 0.0, {"energy": 2.4})
	_ground_wave(root, color, 3.6, 0.05, 0.7, 0.9, 0.04, 0.18)

	# Colonne qui jaillit jusqu'au ciel, puis dont la base monte à son tour : la lumière
	# "part vers le ciel".
	var pillar := VfxLib.beam(color, 0.62, 0.9, 24.0, {
		"energy": 1.2, "scroll": 2.4, "density": 6.0, "top_fade": 0.65, "soft": 0.3,
	})
	root.add_child(pillar)
	_animate_beam(pillar, 0.0, 0.35, d * 0.55, d * 0.75)
	var core := VfxLib.beam(Color.WHITE, 0.22, 0.3, 26.0, {
		"energy": 2.4, "scroll": 4.0, "density": 4.0, "top_fade": 0.6, "soft": 0.2,
	})
	root.add_child(core)
	_animate_beam(core, 0.05, 0.25, d * 0.5, d * 0.7)

	# Halo qui enveloppe le personnage, puis s'élève en s'estompant.
	var halo := VfxLib.glow_sprite(color, 2.6, 0.0, 0.8)
	halo.position.y = 1.0
	root.add_child(halo)
	var halo_mat := VfxLib.mat_of(halo)
	var ht := halo.create_tween()
	VfxLib.tween_param(ht, halo_mat, "energy", 0.0, 3.2, d * 0.35).set_ease(Tween.EASE_OUT)
	ht.tween_property(halo, "position:y", 16.0, d * 0.75 + 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ht.parallel().tween_property(halo, "scale", Vector3.ONE * 0.35, d * 0.75 + 0.6)
	VfxLib.tween_param(ht.parallel(), halo_mat, "energy", 3.2, 0.0, d * 0.75 + 0.6).set_ease(Tween.EASE_IN)

	var sparkles := VfxLib.particles(70, 1.8, 0.12, VfxLib.process({
		"emission": "ring", "radius": 0.75, "inner": 0.15, "direction": Vector3.UP, "spread": 6.0,
		"velocity": Vector2(2.5, 5.5), "gravity": Vector3(0, 3.0, 0), "radial_accel": Vector2(-0.8, -0.3),
		"tangential_accel": Vector2(0.6, 1.4), "scale": Vector2(0.5, 1.2),
		"scale_curve": [Vector2(0, 0.3), Vector2(0.2, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, Color.WHITE], [0.4, color], [1.0, VfxLib.clear(color)]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 2.3})
	VfxLib.emit(root, sparkles, Vector3(0, 0.05, 0))
	root.get_tree().create_timer(d * 0.8).timeout.connect(func() -> void:
		if is_instance_valid(sparkles):
			sparkles.emitting = false
	)

	var omni := VfxLib.light(color, 0.0, 6.0)
	omni.position.y = 1.2
	root.add_child(omni)
	var lt := omni.create_tween()
	lt.tween_property(omni, "light_energy", 4.0, d * 0.3)
	lt.tween_property(omni, "position:y", 9.0, d * 0.7 + 0.6).set_ease(Tween.EASE_IN)
	lt.parallel().tween_property(omni, "light_energy", 0.0, d * 0.7 + 0.6).set_ease(Tween.EASE_IN)


## Impact de l'élément au point `feet` (pieds de la cible).
func play_impact(feet: Vector3, element: int) -> void:
	match element:
		Element.FIRE:
			_impact_fire(feet)
		Element.WATER:
			_impact_water(feet)
		Element.WIND:
			_impact_wind(feet)
		Element.PHYSICAL:
			_impact_physical(feet)
		_:
			_impact_generic(feet, color_of(element))


## Projectile de `caster` vers `target` en `duration_sec` (travelDurationMs serveur) : suit la
## cible si elle bouge, joue l'impact de l'élément à l'arrivée puis appelle
## `on_impact(point: Vector3)` — pieds de la cible à l'arrivée (dernière position connue si
## elle a disparu en route).
func play_projectile(caster: Node3D, target: Node3D, element: int, duration_sec: float, on_impact: Callable = Callable(), style := "") -> void:
	var start := caster.global_position + Vector3.UP * HAND_HEIGHT
	var flat := (target.global_position - caster.global_position) * Vector3(1, 0, 1)
	if flat.length() > 0.01:
		start += flat.normalized() * 0.45
	var root := Node3D.new()
	root.name = "Projectile"
	add_child(root)
	root.global_position = start
	var parts := _build_projectile(root, element, style)
	var arc: float = parts.get("arc", 0.0)
	var orient: bool = parts.get("orient", false)
	var target_ref: WeakRef = weakref(target)
	# Dictionnaire (référence) plutôt qu'une variable capturée : les lambdas GDScript capturent
	# par valeur, une réaffectation ne survivrait pas d'un appel à l'autre.
	var state := {"feet": target.global_position}

	var tween := root.create_tween()
	tween.tween_method(func(t: float) -> void:
		var live := target_ref.get_ref() as Node3D
		if live != null and live.is_inside_tree():
			state["feet"] = live.global_position
		var end: Vector3 = state["feet"] + Vector3.UP * CHEST_HEIGHT
		var pos := start.lerp(end, t) + Vector3.UP * sin(t * PI) * arc
		var step := pos - root.global_position
		root.global_position = pos
		if orient and step.length_squared() > 0.000001 and absf(step.normalized().dot(Vector3.UP)) < 0.98:
			root.look_at(pos + step, Vector3.UP)
	, 0.0, 1.0, maxf(duration_sec, 0.05))
	tween.tween_callback(func() -> void:
		for node: Node3D in parts.get("hide", []):
			node.visible = false
		for trail: GPUParticles3D in parts.get("trails", []):
			trail.emitting = false
		var projectile_light: OmniLight3D = parts.get("light")
		if projectile_light != null:
			projectile_light.visible = false
		play_impact(state["feet"], element)
		if on_impact.is_valid():
			on_impact.call(state["feet"])
		VfxLib.free_after(root, 1.2)
	)


# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

## Racine d'effet en coordonnées monde (ne suit personne), libérée après `lifetime`.
func _spawn_root(feet: Vector3, lifetime: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = feet
	VfxLib.free_after(root, lifetime)
	return root


## Racine d'effet attachée à `target` (suit ses déplacements), libérée après `lifetime`.
func _attach_root(target: Node3D, lifetime: float) -> Node3D:
	var root := Node3D.new()
	target.add_child(root)
	VfxLib.free_after(root, lifetime)
	return root


## Onde au sol : anneau qui s'élargit de `from_r` à `to_r` en s'estompant (après `delay`).
func _ground_wave(parent: Node3D, color: Color, size: float, from_r: float, to_r: float, duration: float, width: float, delay: float = 0.0, params: Dictionary = {}) -> void:
	var all := {"energy": 2.0, "alpha": 0.0}
	all.merge(params, true)
	var wave := VfxLib.ring(color, size, from_r, width, all)
	wave.position.y = 0.05
	parent.add_child(wave)
	var mat := VfxLib.mat_of(wave)
	var tw := wave.create_tween().set_parallel(true)
	VfxLib.tween_param(tw, mat, "radius", from_r, to_r, duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(tw, mat, "alpha", 1.0, 0.0, duration).set_delay(delay).set_ease(Tween.EASE_IN)


## Flash de lumière ponctuelle : `peak` puis extinction en `duration`.
func _light_flash(parent: Node3D, color: Color, local_pos: Vector3, peak: float, duration: float, light_range: float, rise: float = 0.0) -> void:
	var omni := VfxLib.light(color, 0.0, light_range)
	omni.position = local_pos
	parent.add_child(omni)
	var tw := omni.create_tween()
	if rise > 0.0:
		tw.tween_property(omni, "light_energy", peak, rise)
	else:
		omni.light_energy = peak
	tw.tween_property(omni, "light_energy", 0.0, duration).set_ease(Tween.EASE_IN)


## Colonne qui jaillit (head 0 -> 1.3) puis s'envole/disparaît (tail 0 -> 1.3).
func _animate_beam(beam: MeshInstance3D, head_delay: float, head_time: float, tail_delay: float, tail_time: float) -> void:
	var mat := VfxLib.mat_of(beam)
	mat.set_shader_parameter("head", 0.0)
	var tw := beam.create_tween().set_parallel(true)
	VfxLib.tween_param(tw, mat, "head", 0.0, 1.3, head_time).set_delay(head_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(tw, mat, "tail", 0.0, 1.3, tail_time).set_delay(tail_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Entaille en croissant qui s'ouvre et s'efface (vent, physique).
func _slash(parent: Node3D, color: Color, local_pos: Vector3, size: float, delay: float) -> void:
	var cut := VfxLib.crescent(color, size, {"energy": 2.2, "alpha": 0.0, "thickness": 0.1, "span": 1.6})
	cut.position = local_pos
	cut.rotation = Vector3(randf_range(-1.3, 1.3), randf() * TAU, randf_range(-0.7, 0.7))
	cut.scale = Vector3.ONE * 0.3
	parent.add_child(cut)
	var mat := VfxLib.mat_of(cut)
	var tw := cut.create_tween().set_parallel(true)
	tw.tween_property(cut, "scale", Vector3.ONE * 1.2, 0.16).set_delay(delay).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(tw, mat, "alpha", 1.0, 0.0, 0.28).set_delay(delay).set_ease(Tween.EASE_IN)


# ---------------------------------------------------------------------------
# Soin / buff / debuff
# ---------------------------------------------------------------------------

## Soin : lueur au sol puis colonne de lumière qui part des pieds et monte vers le ciel,
## étincelles ascendantes, et la colonne finit par "s'envoler" (sa base se détache du sol).
func _play_heal(target: Node3D) -> void:
	var color := color_of(Element.HEAL)
	var root := _attach_root(target, 2.8)

	var glow := VfxLib.ring(color, 2.4, 0.2, 0.06, {"energy": 2.0, "fill": 0.55, "alpha": 0.0})
	glow.position.y = 0.03
	root.add_child(glow)
	var glow_mat := VfxLib.mat_of(glow)
	var gt := glow.create_tween().set_parallel(true)
	VfxLib.tween_param(gt, glow_mat, "alpha", 0.0, 1.0, 0.15)
	VfxLib.tween_param(gt, glow_mat, "radius", 0.2, 0.42, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(gt, glow_mat, "alpha", 1.0, 0.0, 0.9).set_delay(1.1)

	var column := VfxLib.beam(color, 0.48, 0.38, 5.5, {
		"energy": 1.1, "scroll": 1.6, "density": 7.0, "top_fade": 0.55, "soft": 0.25,
	})
	root.add_child(column)
	_animate_beam(column, 0.05, 0.5, 0.85, 1.0)
	var core := VfxLib.beam(Color(1.0, 0.97, 0.82), 0.17, 0.1, 6.5, {
		"energy": 2.2, "scroll": 3.0, "density": 5.0, "top_fade": 0.5, "soft": 0.2,
	})
	root.add_child(core)
	_animate_beam(core, 0.0, 0.35, 0.65, 0.85)

	var sparkles := VfxLib.particles(50, 1.4, 0.13, VfxLib.process({
		"emission": "ring", "radius": 0.55, "inner": 0.1, "direction": Vector3.UP, "spread": 5.0,
		"velocity": Vector2(1.6, 3.4), "gravity": Vector3(0, 1.2, 0), "scale": Vector2(0.5, 1.2),
		"scale_curve": [Vector2(0, 0.3), Vector2(0.2, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, Color(1.0, 1.0, 0.9)], [0.35, color], [1.0, VfxLib.clear(color)]],
	}), {"one_shot": true, "explosiveness": 0.4, "shape": VfxLib.SHAPE_SPARK, "energy": 2.2})
	VfxLib.emit(root, sparkles, Vector3(0, 0.05, 0))
	var motes := VfxLib.particles(18, 1.8, 0.28, VfxLib.process({
		"emission": "ring", "radius": 0.5, "inner": 0.3, "direction": Vector3.UP, "spread": 10.0,
		"velocity": Vector2(0.5, 1.1), "gravity": Vector3(0, 0.3, 0), "tangential_accel": Vector2(1.0, 2.0),
		"colors": [[0.0, VfxLib.clear(color)], [0.2, Color(color.r, color.g, color.b, 0.6)], [1.0, VfxLib.clear(color)]],
	}), {"one_shot": true, "explosiveness": 0.2, "energy": 1.4})
	VfxLib.emit(root, motes, Vector3(0, 0.1, 0))

	_light_flash(root, color, Vector3(0, 1.0, 0), 3.0, 1.3, 4.0, 0.2)


## Buff : onde au sol, trois anneaux dorés qui s'élèvent autour du corps, étincelles en
## spirale ascendante et fine colonne.
func _play_buff(target: Node3D) -> void:
	var color := color_of(Element.BUFF)
	var root := _attach_root(target, 2.2)
	_ground_wave(root, color, 2.4, 0.15, 0.7, 0.5, 0.05)

	for i in 3:
		var halo := VfxLib.ring(color, 1.5, 0.72, 0.05, {"energy": 2.3, "alpha": 0.0})
		halo.position.y = 0.05
		root.add_child(halo)
		var mat := VfxLib.mat_of(halo)
		var delay := i * 0.14
		var tw := halo.create_tween().set_parallel(true)
		tw.tween_property(halo, "position:y", 2.0 - i * 0.25, 0.85).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(halo, "scale", Vector3.ONE * 0.7, 0.85).set_delay(delay)
		VfxLib.tween_param(tw, mat, "alpha", 0.0, 1.0, 0.12).set_delay(delay)
		VfxLib.tween_param(tw, mat, "alpha", 1.0, 0.0, 0.4).set_delay(delay + 0.5)

	var sparkles := VfxLib.particles(34, 1.2, 0.11, VfxLib.process({
		"emission": "ring", "radius": 0.55, "inner": 0.45, "direction": Vector3.UP, "spread": 8.0,
		"velocity": Vector2(1.0, 2.0), "gravity": Vector3(0, 0.6, 0), "tangential_accel": Vector2(3.0, 5.0),
		"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, Color(1.0, 1.0, 0.85)], [0.4, color], [1.0, VfxLib.clear(color)]],
	}), {"one_shot": true, "explosiveness": 0.25, "shape": VfxLib.SHAPE_SPARK, "energy": 2.0})
	VfxLib.emit(root, sparkles, Vector3(0, 0.1, 0))

	var column := VfxLib.beam(color, 0.5, 0.42, 2.6, {"energy": 0.9, "scroll": 2.0, "density": 6.0, "soft": 0.25})
	root.add_child(column)
	_animate_beam(column, 0.0, 0.35, 0.5, 0.6)

	_light_flash(root, color, Vector3(0, 1.0, 0), 2.2, 1.0, 3.5, 0.15)


## Debuff : un sceau (pentagramme inversé) se trace au-dessus de la tête puis descend jusqu'aux
## pieds, précédé d'une colonne qui s'écoule du haut vers le bas et d'une pluie de particules ;
## à l'arrivée au sol, onde violette et fumée sombre.
func _play_debuff(target: Node3D) -> void:
	var color := color_of(Element.DEBUFF)
	var root := _attach_root(target, 2.8)

	var sigil := VfxLib.magic_circle(color, 1.3, {"energy": 2.0, "reveal": 0.0, "star_spin": PI})
	sigil.position.y = ABOVE_HEAD_HEIGHT
	root.add_child(sigil)
	var sm := VfxLib.mat_of(sigil)
	var st := sigil.create_tween().set_parallel(true)
	VfxLib.tween_param(st, sm, "reveal", 0.0, 1.0, 0.35).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(st, sm, "flash", 2.0, 0.0, 0.4)
	VfxLib.tween_param(st, sm, "charge", 0.0, 1.0, 1.15)
	VfxLib.tween_param(st, sm, "star_spin", PI, PI + 2.5, 1.7)
	VfxLib.tween_param(st, sm, "spin", 0.0, -4.0, 1.7)
	st.tween_property(sigil, "position:y", 0.05, 0.75).set_delay(0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.tween_callback(_debuff_land.bind(root, sigil, color)).set_delay(1.15)

	var column := VfxLib.beam(color, 0.55, 0.5, 2.8, {
		"downward": 1.0, "energy": 1.4, "scroll": 1.8, "density": 7.0, "top_fade": 0.15, "soft": 0.25,
	})
	root.add_child(column)
	_animate_beam(column, 0.3, 0.8, 1.0, 0.6)

	var rain := VfxLib.particles(44, 1.0, 0.12, VfxLib.process({
		"emission": "ring", "radius": 0.5, "inner": 0.0, "direction": Vector3.DOWN, "spread": 10.0,
		"velocity": Vector2(0.8, 1.8), "gravity": Vector3(0, -2.5, 0),
		"scale_curve": [Vector2(0, 0.4), Vector2(0.3, 1.0), Vector2(1, 0.2)],
		"colors": [[0.0, Color(0.9, 0.75, 1.0)], [0.3, color], [1.0, VfxLib.clear(Color(0.25, 0.05, 0.4))]],
	}), {"one_shot": true, "explosiveness": 0.1, "shape": VfxLib.SHAPE_SPARK, "energy": 2.0})
	rain.position.y = ABOVE_HEAD_HEIGHT - 0.05
	root.add_child(rain)
	var rt := rain.create_tween()
	rt.tween_interval(0.3)
	rt.tween_callback(func() -> void: rain.emitting = true)

	_light_flash(root, color, Vector3(0, 1.6, 0), 1.8, 1.4, 3.5, 0.3)


func _debuff_land(root: Node3D, sigil: MeshInstance3D, color: Color) -> void:
	var sm := VfxLib.mat_of(sigil)
	var tw := sigil.create_tween().set_parallel(true)
	VfxLib.tween_param(tw, sm, "flash", 2.5, 0.0, 0.5)
	tw.tween_property(sigil, "scale", Vector3.ONE * 1.7, 0.5).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(tw, sm, "alpha", 1.0, 0.0, 0.5)
	_ground_wave(root, color, 3.0, 0.15, 0.95, 0.55, 0.06)

	var smoke := VfxLib.particles(14, 1.2, 0.8, VfxLib.process({
		"emission": "ring", "radius": 0.45, "inner": 0.1, "direction": Vector3.UP, "spread": 80.0,
		"velocity": Vector2(0.4, 0.9), "damping": Vector2(0.8, 1.2), "scale": Vector2(0.6, 1.1),
		"scale_curve": [Vector2(0, 0.4), Vector2(1, 1.0)],
		"colors": [[0.0, Color(0.2, 0.04, 0.28, 0.0)], [0.15, Color(0.2, 0.05, 0.28, 0.55)], [1.0, Color(0.1, 0.02, 0.15, 0.0)]],
	}), {"one_shot": true, "explosiveness": 0.85, "smoke": true})
	VfxLib.emit(root, smoke, Vector3(0, 0.15, 0))


# ---------------------------------------------------------------------------
# Projectiles
# ---------------------------------------------------------------------------

## Retourne {hide: nœuds à masquer à l'impact, trails: particules à arrêter, light, arc (m),
## orient (le projectile s'aligne sur sa trajectoire, -Z vers l'avant)}.
func _build_projectile(root: Node3D, element: int, style := "") -> Dictionary:
	match style:
		"ice":
			return _projectile_ice(root)
		"arrow":
			return _projectile_arrow(root)
	match element:
		Element.FIRE:
			return _projectile_fire(root)
		Element.WATER:
			return _projectile_water(root)
		Element.WIND:
			return _projectile_wind(root)
		_:
			return _projectile_generic(root, color_of(element))


## Boule de feu : cœur blanc-jaune, halo rouge qui vacille, traînée de flammes, braises et fumée.
func _projectile_fire(root: Node3D) -> Dictionary:
	var halo := VfxLib.glow_sprite(Color(1.0, 0.28, 0.05), 1.1, 1.3, 0.0)
	var core := VfxLib.glow_sprite(Color(1.0, 0.6, 0.25), 0.4, 1.8, 0.7)
	root.add_child(halo)
	root.add_child(core)
	var flicker := halo.create_tween().set_loops()
	flicker.tween_property(halo, "scale", Vector3.ONE * 1.15, 0.07)
	flicker.tween_property(halo, "scale", Vector3.ONE * 0.9, 0.08)

	var flames := VfxLib.emit(root, VfxLib.particles(70, 0.45, 0.5, VfxLib.process({
		"radius": 0.12, "velocity": Vector2(0.1, 0.4), "gravity": Vector3(0, 1.5, 0),
		"scale": Vector2(0.6, 1.1), "scale_curve": [Vector2(0, 1.0), Vector2(1, 0.1)], "colors": FIRE_RAMP,
	}), {"energy": 1.0}))
	var embers := VfxLib.emit(root, VfxLib.particles(18, 0.7, 0.07, VfxLib.process({
		"radius": 0.15, "velocity": Vector2(0.4, 1.2), "gravity": Vector3(0, -1.5, 0),
		"colors": [[0.0, Color(1.0, 0.85, 0.4)], [1.0, VfxLib.clear(Color(1.0, 0.3, 0.0))]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 2.4}))
	var smoke := VfxLib.emit(root, VfxLib.particles(10, 0.8, 0.45, VfxLib.process({
		"radius": 0.1, "velocity": Vector2(0.1, 0.3), "gravity": Vector3(0, 0.8, 0),
		"scale_curve": [Vector2(0, 0.5), Vector2(1, 1.0)], "colors": SMOKE_RAMP,
	}), {"smoke": true}))
	var omni := VfxLib.light(Color(1.0, 0.5, 0.2), 2.5, 3.5)
	root.add_child(omni)
	return {"hide": [halo, core], "trails": [flames, embers, smoke], "light": omni, "arc": 0.25}


## Orbe d'eau : sphère ondulante bleue, trois gouttelettes en spirale autour de l'axe de vol,
## traînée de gouttes qui retombent et de bruine.
func _projectile_water(root: Node3D) -> Dictionary:
	var orb := VfxLib.orb(Color(0.1, 0.45, 1.0), Color(0.8, 0.95, 1.0), 0.2, {
		"energy": 1.6, "noise_scale": 5.0, "noise_speed": 2.5, "core_amount": 0.45, "rim_power": 1.2,
	})
	var halo := VfxLib.glow_sprite(Color(0.15, 0.45, 1.0), 0.8, 0.9, 0.0)
	root.add_child(orb)
	root.add_child(halo)
	var wobble := orb.create_tween().set_loops()
	wobble.tween_property(orb, "scale", Vector3(1.12, 0.9, 1.05), 0.12)
	wobble.tween_property(orb, "scale", Vector3(0.92, 1.1, 0.95), 0.12)

	var spinner := Node3D.new()
	root.add_child(spinner)
	for i in 3:
		var drop := VfxLib.glow_sprite(Color(0.55, 0.85, 1.0), 0.13, 2.0, 0.8)
		var angle := TAU * i / 3.0
		drop.position = Vector3(cos(angle), sin(angle), 0.0) * 0.32
		spinner.add_child(drop)
	var spin := spinner.create_tween().set_loops()
	spin.tween_property(spinner, "rotation:z", TAU, 0.35).from(0.0)

	var drops := VfxLib.emit(root, VfxLib.particles(36, 0.5, 0.08, VfxLib.process({
		"radius": 0.15, "velocity": Vector2(0.2, 0.6), "gravity": Vector3(0, -6.0, 0),
		"colors": [[0.0, Color(0.7, 0.9, 1.0)], [1.0, VfxLib.clear(Color(0.2, 0.5, 1.0))]],
	}), {"energy": 1.8}))
	var mist := VfxLib.emit(root, VfxLib.particles(20, 0.35, 0.32, VfxLib.process({
		"radius": 0.1, "velocity": Vector2(0.05, 0.2),
		"scale_curve": [Vector2(0, 0.5), Vector2(1, 1.0)],
		"colors": [[0.0, Color(0.3, 0.6, 1.0, 0.35)], [1.0, VfxLib.clear(Color(0.3, 0.6, 1.0))]],
	}), {"energy": 0.9}))
	var omni := VfxLib.light(Color(0.3, 0.6, 1.0), 1.8, 3.0)
	root.add_child(omni)
	return {"hide": [orb, halo, spinner], "trails": [drops, mist], "light": omni, "arc": 0.35, "orient": true}


## Lames de vent : deux croissants blancs croisés qui tournoient, traînée de souffle.
func _projectile_wind(root: Node3D) -> Dictionary:
	var color := color_of(Element.WIND)
	var halo := VfxLib.glow_sprite(Color(0.75, 0.9, 1.0), 0.7, 0.6, 0.2)
	root.add_child(halo)
	var hide: Array = [halo]
	for i in 2:
		var holder := Node3D.new()
		holder.rotation.z = i * PI * 0.5
		root.add_child(holder)
		var blade := VfxLib.crescent(color, 0.95, {"energy": 1.8})
		holder.add_child(blade)
		var spin := blade.create_tween().set_loops()
		spin.tween_property(blade, "rotation:y", -TAU if i == 0 else TAU, 0.22).from(0.0)
		hide.append(holder)

	var streaks := VfxLib.emit(root, VfxLib.particles(50, 0.3, 0.18, VfxLib.process({
		"radius": 0.25, "velocity": Vector2(0.0, 0.1),
		"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.2)],
		"colors": [[0.0, Color(0.85, 0.95, 1.0, 0.6)], [1.0, VfxLib.clear(Color(0.85, 0.95, 1.0))]],
	}), {"energy": 1.0}))
	var specks := VfxLib.emit(root, VfxLib.particles(24, 0.5, 0.06, VfxLib.process({
		"radius": 0.3, "velocity": Vector2(0.3, 0.8),
		"colors": [[0.0, Color.WHITE], [1.0, VfxLib.clear(Color.WHITE)]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 1.8}))
	var omni := VfxLib.light(Color(0.8, 0.9, 1.0), 1.0, 2.5)
	root.add_child(omni)
	return {"hide": hide, "trails": [streaks, specks], "light": omni, "arc": 0.0, "orient": true}


func _projectile_generic(root: Node3D, color: Color) -> Dictionary:
	var halo := VfxLib.glow_sprite(color, 0.9, 1.2, 0.0)
	var core := VfxLib.glow_sprite(color.lightened(0.5), 0.35, 2.4, 1.0)
	root.add_child(halo)
	root.add_child(core)
	var trail := VfxLib.emit(root, VfxLib.particles(50, 0.4, 0.28, VfxLib.process({
		"radius": 0.08, "velocity": Vector2(0.05, 0.25),
		"scale_curve": [Vector2(0, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, color.lightened(0.3)], [1.0, VfxLib.clear(color)]],
	}), {"energy": 1.6}))
	var sparks := VfxLib.emit(root, VfxLib.particles(16, 0.5, 0.07, VfxLib.process({
		"radius": 0.15, "velocity": Vector2(0.3, 0.9),
		"colors": [[0.0, Color.WHITE], [1.0, VfxLib.clear(color)]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 2.0}))
	var omni := VfxLib.light(color, 1.8, 3.0)
	root.add_child(omni)
	return {"hide": [halo, core], "trails": [trail, sparks], "light": omni, "arc": 0.15}


# ---------------------------------------------------------------------------
# Impacts
# ---------------------------------------------------------------------------

## Explosion : boule de feu qui gonfle et se dissout, gerbe de flammes, étincelles, fumée,
## onde brûlante au sol, flash orangé.
func _impact_fire(feet: Vector3) -> void:
	var root := _spawn_root(feet, 2.0)
	var center := Vector3.UP * CHEST_HEIGHT
	var ball := VfxLib.orb(Color(1.0, 0.18, 0.02), Color(1.0, 0.6, 0.2), 0.5, {
		"energy": 1.4, "noise_scale": 2.5, "noise_speed": 1.5,
	})
	ball.position = center
	ball.scale = Vector3.ONE * 0.3
	root.add_child(ball)
	var bt := ball.create_tween().set_parallel(true)
	bt.tween_property(ball, "scale", Vector3.ONE * 1.5, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(bt, VfxLib.mat_of(ball), "dissolve", 0.0, 1.2, 0.5).set_delay(0.08)

	VfxLib.emit(root, VfxLib.particles(36, 0.75, 0.6, VfxLib.process({
		"radius": 0.2, "velocity": Vector2(1.5, 3.5), "damping": Vector2(3.0, 5.0),
		"gravity": Vector3(0, 1.5, 0), "scale_curve": [Vector2(0, 1.0), Vector2(1, 0.15)], "colors": FIRE_RAMP,
	}), {"one_shot": true, "explosiveness": 0.95, "energy": 1.0}), center)
	VfxLib.emit(root, VfxLib.particles(30, 0.9, 0.08, VfxLib.process({
		"radius": 0.15, "velocity": Vector2(3.0, 6.5), "gravity": Vector3(0, -7.0, 0),
		"colors": [[0.0, Color(1.0, 0.9, 0.5)], [0.5, Color(1.0, 0.45, 0.1)], [1.0, VfxLib.clear(Color(1.0, 0.2, 0.0))]],
	}), {"one_shot": true, "explosiveness": 1.0, "shape": VfxLib.SHAPE_SPARK, "energy": 2.4}), center)
	VfxLib.emit(root, VfxLib.particles(12, 1.6, 0.8, VfxLib.process({
		"radius": 0.3, "direction": Vector3.UP, "spread": 70.0, "velocity": Vector2(0.4, 1.0),
		"damping": Vector2(0.5, 1.0), "gravity": Vector3(0, 0.5, 0),
		"scale_curve": [Vector2(0, 0.4), Vector2(1, 1.0)], "colors": SMOKE_RAMP,
	}), {"one_shot": true, "explosiveness": 0.8, "smoke": true}), center)
	_ground_wave(root, Color(1.0, 0.4, 0.1), 3.0, 0.1, 0.95, 0.5, 0.07, 0.0, {"wobble": 0.04})
	_light_flash(root, Color(1.0, 0.5, 0.2), center, 6.0, 0.5, 5.0)


## Éclaboussure : dôme d'eau qui éclate, gerbe de gouttes qui retombent, bruine, deux
## ondulations au sol.
func _impact_water(feet: Vector3) -> void:
	var root := _spawn_root(feet, 1.8)
	var center := Vector3.UP * CHEST_HEIGHT
	var splash := VfxLib.orb(Color(0.1, 0.45, 1.0), Color(0.85, 0.95, 1.0), 0.45, {
		"energy": 1.6, "noise_scale": 4.0, "noise_speed": 3.0, "core_amount": 0.4,
	})
	splash.position = center
	splash.scale = Vector3.ONE * 0.3
	root.add_child(splash)
	var st := splash.create_tween().set_parallel(true)
	st.tween_property(splash, "scale", Vector3.ONE * 1.2, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(st, VfxLib.mat_of(splash), "dissolve", 0.0, 1.2, 0.4).set_delay(0.05)

	VfxLib.emit(root, VfxLib.particles(50, 1.0, 0.09, VfxLib.process({
		"radius": 0.2, "direction": Vector3.UP, "spread": 70.0, "velocity": Vector2(2.5, 5.0),
		"gravity": Vector3(0, -10.0, 0),
		"colors": [[0.0, Color(0.8, 0.95, 1.0)], [0.6, Color(0.3, 0.6, 1.0)], [1.0, VfxLib.clear(Color(0.2, 0.5, 1.0))]],
	}), {"one_shot": true, "explosiveness": 0.95, "energy": 2.0}), center)
	VfxLib.emit(root, VfxLib.particles(14, 0.9, 0.6, VfxLib.process({
		"radius": 0.25, "velocity": Vector2(0.6, 1.4), "damping": Vector2(2.0, 3.0),
		"scale_curve": [Vector2(0, 0.5), Vector2(1, 1.0)],
		"colors": [[0.0, Color(0.4, 0.7, 1.0, 0.4)], [1.0, VfxLib.clear(Color(0.4, 0.7, 1.0))]],
	}), {"one_shot": true, "explosiveness": 0.9, "energy": 0.8}), center)
	var ripple_color := Color(0.25, 0.6, 1.0)
	_ground_wave(root, ripple_color, 3.0, 0.1, 0.95, 0.7, 0.03)
	_ground_wave(root, ripple_color, 3.0, 0.1, 0.8, 0.7, 0.025, 0.18)
	_light_flash(root, Color(0.3, 0.6, 1.0), center, 4.0, 0.4, 4.0)


## Tornade : deux entonnoirs de vent torsadés qui tournoient, poussière en spirale, entailles.
func _impact_wind(feet: Vector3) -> void:
	var root := _spawn_root(feet, 1.8)
	var funnels := [
		VfxLib.beam(Color(0.9, 0.96, 1.0), 0.22, 0.85, 2.3, {
			"energy": 0.55, "twist": 1.6, "scroll": 2.8, "density": 6.0, "top_fade": 0.35,
		}),
		VfxLib.beam(Color(0.75, 0.9, 1.0), 0.3, 1.0, 2.0, {
			"energy": 0.35, "twist": -1.2, "scroll": 2.2, "density": 5.0,
		}),
	]
	for funnel: MeshInstance3D in funnels:
		root.add_child(funnel)
		_animate_beam(funnel, 0.0, 0.25, 0.65, 0.45)
		var spin := funnel.create_tween()
		spin.tween_property(funnel, "rotation:y", -3.0 * PI, 1.1)

	VfxLib.emit(root, VfxLib.particles(32, 0.9, 0.08, VfxLib.process({
		"emission": "ring", "radius": 0.35, "inner": 0.2, "direction": Vector3.UP, "spread": 20.0,
		"velocity": Vector2(1.2, 2.4), "gravity": Vector3(0, 1.0, 0), "tangential_accel": Vector2(5.0, 8.0),
		"colors": [[0.0, Color.WHITE], [1.0, VfxLib.clear(Color(0.8, 0.9, 1.0))]],
	}), {"one_shot": true, "explosiveness": 0.4, "energy": 1.6}), Vector3(0, 0.1, 0))
	_ground_wave(root, Color(0.85, 0.9, 0.95), 2.6, 0.15, 0.9, 0.5, 0.07, 0.0, {"wobble": 0.05, "energy": 1.2})
	for i in 3:
		_slash(root, color_of(Element.WIND), Vector3(0, CHEST_HEIGHT + randf_range(-0.2, 0.3), 0), 1.1, i * 0.07)


func _impact_physical(feet: Vector3) -> void:
	var root := _spawn_root(feet, 1.2)
	var color := color_of(Element.PHYSICAL)
	var center := Vector3.UP * CHEST_HEIGHT
	_slash(root, color, center, 1.2, 0.0)
	VfxLib.emit(root, VfxLib.particles(20, 0.5, 0.08, VfxLib.process({
		"radius": 0.1, "velocity": Vector2(2.0, 4.0), "gravity": Vector3(0, -6.0, 0),
		"colors": [[0.0, Color.WHITE], [0.4, color], [1.0, VfxLib.clear(Color(1.0, 0.5, 0.2))]],
	}), {"one_shot": true, "explosiveness": 1.0, "shape": VfxLib.SHAPE_SPARK, "energy": 2.2}), center)


func _impact_generic(feet: Vector3, color: Color) -> void:
	var root := _spawn_root(feet, 1.6)
	var center := Vector3.UP * CHEST_HEIGHT
	var burst := VfxLib.orb(color, color.lightened(0.6), 0.4, {"energy": 2.0, "noise_scale": 3.0})
	burst.position = center
	burst.scale = Vector3.ONE * 0.3
	root.add_child(burst)
	var bt := burst.create_tween().set_parallel(true)
	bt.tween_property(burst, "scale", Vector3.ONE * 1.3, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(bt, VfxLib.mat_of(burst), "dissolve", 0.0, 1.2, 0.45).set_delay(0.05)
	VfxLib.emit(root, VfxLib.particles(28, 0.8, 0.09, VfxLib.process({
		"radius": 0.15, "velocity": Vector2(2.0, 4.5), "damping": Vector2(1.0, 2.0), "gravity": Vector3(0, -3.0, 0),
		"colors": [[0.0, Color.WHITE], [0.4, color], [1.0, VfxLib.clear(color)]],
	}), {"one_shot": true, "explosiveness": 1.0, "shape": VfxLib.SHAPE_SPARK, "energy": 2.2}), center)
	_ground_wave(root, color, 2.6, 0.1, 0.9, 0.5, 0.06)
	_light_flash(root, color, center, 4.0, 0.45, 4.0)


# ---------------------------------------------------------------------------
# Compétences L2 des classes de base (Human Fighter / Human Mystic)
# ---------------------------------------------------------------------------

## Effet sur la cible d'une compétence nommée (CastResult/SkillCastAnnounced/
## SkillModifierAnnounced) : variante propre à la compétence quand elle en a une, sinon
## l'effet générique de son élément (voir play_on_target).
func play_skill_on_target(target: Node3D, skill_name: String, element: int) -> void:
	if target == null or not target.is_inside_tree():
		return
	match skill_name:
		"Relax":
			_play_rest(target)
		"Shield":
			_play_buff(target)
			_shield_dome(target)
		"Might":
			_play_buff(target)
			_power_flare(target)
		"Curse: Poison":
			_play_debuff(target)
			_poison_cloud(target)
		"Cure Poison":
			_play_heal(target)
			_purge(target)
		"Power Strike":
			_impact_power_strike(target.global_position)
		"Mortal Blow":
			_impact_blow(target.global_position)
		_:
			play_on_target(target, element)


## Compétence martiale en préparation (castingTimeMs) : l'énergie converge vers la main de
## l'arme et y grossit, couleur propre à la compétence ; s'éteint d'elle-même à la frappe.
func play_weapon_charge(caster: Node3D, skill_name: String, duration_sec: float) -> void:
	var color: Color = WEAPON_CHARGE_COLORS.get(skill_name, color_of(Element.PHYSICAL))
	var d := maxf(duration_sec, 0.2)
	var root := _attach_root(caster, d + 0.4)
	var hand := Vector3(0.3, HAND_HEIGHT - 0.1, -0.25)
	var glow := VfxLib.glow_sprite(color, 0.7, 0.0, 0.6)
	glow.position = hand
	glow.scale = Vector3.ONE * 0.3
	root.add_child(glow)
	var gm := VfxLib.mat_of(glow)
	var gt := glow.create_tween().set_parallel(true)
	gt.tween_property(glow, "scale", Vector3.ONE * 1.2, d).set_ease(Tween.EASE_IN)
	VfxLib.tween_param(gt, gm, "energy", 0.4, 2.6, d).set_ease(Tween.EASE_IN)
	gt.chain().tween_property(glow, "scale", Vector3.ONE * 0.01, 0.15)

	var gather := VfxLib.particles(40, 0.45, 0.07, VfxLib.process({
		"radius": 0.9, "velocity": Vector2(0.0, 0.1), "radial_accel": Vector2(-9.0, -6.0),
		"scale_curve": [Vector2(0, 0.3), Vector2(1, 1.0)],
		"colors": [[0.0, VfxLib.clear(color)], [0.4, color], [1.0, Color.WHITE]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 2.0, "local": true})
	VfxLib.emit(root, gather, hand)
	var stop := gather.create_tween()
	stop.tween_interval(maxf(d - 0.2, 0.05))
	stop.tween_callback(func() -> void: gather.emitting = false)

	var aura := VfxLib.ring(color, 1.8, 0.6, 0.04, {"energy": 1.6, "alpha": 0.0})
	aura.position.y = 0.05
	root.add_child(aura)
	var am := VfxLib.mat_of(aura)
	var at := aura.create_tween().set_parallel(true)
	VfxLib.tween_param(at, am, "alpha", 0.0, 0.8, d * 0.5)
	VfxLib.tween_param(at, am, "radius", 0.85, 0.45, d)
	VfxLib.tween_param(at.chain(), am, "alpha", 0.8, 0.0, 0.2)
	_light_flash(root, color, hand, 1.6, 0.3, 2.5, d)


## Poison qui ronge sa cible (EffectDamage) : quelques bulles vertes qui montent du corps et
## une bouffée violacée.
func play_poison_tick(target: Node3D) -> void:
	if target == null or not target.is_inside_tree():
		return
	var root := _attach_root(target, 1.6)
	VfxLib.emit(root, VfxLib.particles(14, 1.0, 0.12, VfxLib.process({
		"radius": 0.35, "direction": Vector3.UP, "spread": 25.0, "velocity": Vector2(0.4, 0.9),
		"scale_curve": [Vector2(0, 0.4), Vector2(0.7, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, Color(0.8, 1.0, 0.5)], [0.5, POISON_COLOR], [1.0, VfxLib.clear(POISON_COLOR)]],
	}), {"one_shot": true, "explosiveness": 0.6, "energy": 1.6}), Vector3(0, CHEST_HEIGHT, 0))
	VfxLib.emit(root, VfxLib.particles(6, 1.1, 0.7, VfxLib.process({
		"radius": 0.25, "direction": Vector3.UP, "spread": 60.0, "velocity": Vector2(0.2, 0.5),
		"scale_curve": [Vector2(0, 0.4), Vector2(1, 1.0)],
		"colors": [[0.0, VfxLib.clear(POISON_DARK)], [0.2, Color(POISON_DARK, 0.45)], [1.0, VfxLib.clear(POISON_DARK)]],
	}), {"one_shot": true, "explosiveness": 0.8, "smoke": true}), Vector3(0, CHEST_HEIGHT, 0))


## Vampiric Touch : des filets de vie rouges quittent la cible et viennent se fondre dans le
## lanceur, qui s'illumine brièvement. Sans cible connue, seule la lueur du lanceur se joue.
func play_drain(from_target: Node3D, to_caster: Node3D) -> void:
	if to_caster == null or not to_caster.is_inside_tree():
		return
	var end := to_caster.global_position + Vector3.UP * CHEST_HEIGHT
	var travel := 0.0
	if from_target != null and from_target.is_inside_tree():
		var start := from_target.global_position + Vector3.UP * CHEST_HEIGHT
		travel = 0.55
		var world_root := _spawn_root(Vector3.ZERO, 2.2)
		for i in 6:
			var orb := VfxLib.glow_sprite(DRAIN_COLOR, 0.55, 2.4, 0.5)
			world_root.add_child(orb)
			orb.global_position = start
			var side := Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 1.0), randf_range(-0.8, 0.8))
			var tw := orb.create_tween()
			tw.tween_interval(i * 0.07)
			tw.tween_method(func(t: float) -> void:
				if is_instance_valid(orb):
					orb.global_position = start.lerp(end, t) + side * sin(t * PI) * 0.6
			, 0.0, 1.0, travel)
			tw.tween_callback(orb.queue_free)
	var root := _attach_root(to_caster, travel + 1.6)
	var halo := VfxLib.glow_sprite(DRAIN_COLOR, 1.8, 0.0, 0.4)
	halo.position.y = CHEST_HEIGHT
	root.add_child(halo)
	var hm := VfxLib.mat_of(halo)
	var ht := halo.create_tween()
	ht.tween_interval(travel)
	VfxLib.tween_param(ht, hm, "energy", 0.0, 2.2, 0.15)
	VfxLib.tween_param(ht, hm, "energy", 2.2, 0.0, 0.7).set_ease(Tween.EASE_IN)
	var sparks := VfxLib.particles(24, 1.0, 0.09, VfxLib.process({
		"emission": "ring", "radius": 0.5, "inner": 0.3, "direction": Vector3.UP, "spread": 10.0,
		"velocity": Vector2(0.6, 1.4), "tangential_accel": Vector2(2.0, 4.0),
		"colors": [[0.0, Color(1.0, 0.8, 0.8)], [0.4, DRAIN_COLOR], [1.0, VfxLib.clear(DRAIN_COLOR)]],
	}), {"one_shot": true, "explosiveness": 0.4, "shape": VfxLib.SHAPE_SPARK, "energy": 2.0})
	sparks.position.y = 0.2
	root.add_child(sparks)
	var st := sparks.create_tween()
	st.tween_interval(travel)
	st.tween_callback(func() -> void: sparks.emitting = true)


## Relax : le personnage se pose ; un cercle doré apaisé s'étend au sol et des lueurs douces
## montent lentement autour de lui.
func _play_rest(target: Node3D) -> void:
	var color := color_of(Element.BUFF)
	var root := _attach_root(target, 3.6)
	var circle := VfxLib.magic_circle(color, 2.0, {"energy": 0.9, "reveal": 0.0, "alpha": 0.8})
	circle.position.y = 0.04
	root.add_child(circle)
	var cm := VfxLib.mat_of(circle)
	var ct := circle.create_tween().set_parallel(true)
	VfxLib.tween_param(ct, cm, "reveal", 0.0, 1.0, 0.8).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(ct, cm, "spin", 0.0, 1.2, 3.4)
	VfxLib.tween_param(ct, cm, "alpha", 0.8, 0.0, 0.8).set_delay(2.6)
	VfxLib.emit(root, VfxLib.particles(24, 2.4, 0.14, VfxLib.process({
		"emission": "ring", "radius": 0.8, "inner": 0.2, "direction": Vector3.UP, "spread": 12.0,
		"velocity": Vector2(0.3, 0.6), "scale_curve": [Vector2(0, 0.3), Vector2(0.5, 1.0), Vector2(1, 0.0)],
		"colors": [[0.0, VfxLib.clear(color)], [0.3, Color(1.0, 0.95, 0.75)], [1.0, VfxLib.clear(color)]],
	}), {"one_shot": true, "explosiveness": 0.1, "energy": 1.4}), Vector3(0, 0.1, 0))
	_light_flash(root, color, Vector3(0, 0.6, 0), 1.2, 2.2, 3.0, 0.4)


## Shield : un dôme doré translucide enveloppe la cible puis se dissout.
func _shield_dome(target: Node3D) -> void:
	var color := color_of(Element.BUFF)
	var root := _attach_root(target, 2.0)
	var dome := VfxLib.orb(color, Color(1.0, 1.0, 0.9), 1.05, {
		"energy": 1.1, "noise_scale": 2.0, "core_amount": 0.0, "rim_power": 3.5,
	})
	dome.position.y = CHEST_HEIGHT
	dome.scale = Vector3.ONE * 0.6
	root.add_child(dome)
	var dt := dome.create_tween().set_parallel(true)
	dt.tween_property(dome, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	VfxLib.tween_param(dt, VfxLib.mat_of(dome), "dissolve", 0.0, 1.2, 1.0).set_delay(0.6)


## Might : gerbe d'étincelles orangées qui jaillit des mains vers le ciel.
func _power_flare(target: Node3D) -> void:
	var color := Color(1.0, 0.55, 0.15)
	var root := _attach_root(target, 1.8)
	VfxLib.emit(root, VfxLib.particles(30, 0.9, 0.1, VfxLib.process({
		"radius": 0.25, "direction": Vector3.UP, "spread": 20.0, "velocity": Vector2(2.5, 4.5),
		"gravity": Vector3(0, -3.0, 0),
		"colors": [[0.0, Color.WHITE], [0.35, color], [1.0, VfxLib.clear(color)]],
	}), {"one_shot": true, "explosiveness": 0.8, "shape": VfxLib.SHAPE_SPARK, "energy": 2.2}), Vector3(0, HAND_HEIGHT, 0))


## Curse: Poison : un nuage verdâtre et violacé s'accroche quelques secondes à la cible.
func _poison_cloud(target: Node3D) -> void:
	var root := _attach_root(target, 3.2)
	var cloud := VfxLib.particles(16, 1.6, 0.9, VfxLib.process({
		"emission": "ring", "radius": 0.45, "inner": 0.1, "height": 1.2, "direction": Vector3.UP, "spread": 70.0,
		"velocity": Vector2(0.1, 0.35), "scale_curve": [Vector2(0, 0.4), Vector2(1, 1.0)],
		"colors": [[0.0, VfxLib.clear(POISON_DARK)], [0.25, Color(0.25, 0.45, 0.1, 0.5)], [1.0, VfxLib.clear(POISON_DARK)]],
	}), {"smoke": true})
	VfxLib.emit(root, cloud, Vector3(0, 0.6, 0))
	var bubbles := VfxLib.particles(22, 1.2, 0.1, VfxLib.process({
		"radius": 0.4, "direction": Vector3.UP, "spread": 30.0, "velocity": Vector2(0.4, 1.0),
		"colors": [[0.0, Color(0.8, 1.0, 0.5)], [0.5, POISON_COLOR], [1.0, VfxLib.clear(POISON_COLOR)]],
	}), {"energy": 1.5})
	VfxLib.emit(root, bubbles, Vector3(0, CHEST_HEIGHT, 0))
	var stop := root.create_tween()
	stop.tween_interval(1.4)
	stop.tween_callback(func() -> void:
		cloud.emitting = false
		bubbles.emitting = false
	)


## Cure Poison : le poison est expulsé du corps (éclats vert sombre projetés au loin, qui
## blanchissent en s'éloignant).
func _purge(target: Node3D) -> void:
	var root := _attach_root(target, 1.8)
	VfxLib.emit(root, VfxLib.particles(28, 0.8, 0.1, VfxLib.process({
		"radius": 0.3, "velocity": Vector2(2.0, 3.5), "damping": Vector2(2.0, 3.0),
		"colors": [[0.0, Color(0.2, 0.55, 0.1)], [0.5, POISON_COLOR], [1.0, VfxLib.clear(Color.WHITE)]],
	}), {"one_shot": true, "explosiveness": 0.9, "shape": VfxLib.SHAPE_SPARK, "energy": 2.0}), Vector3(0, CHEST_HEIGHT, 0))


## Power Strike : grande entaille dorée doublée d'une onde de choc et d'une gerbe d'étincelles.
func _impact_power_strike(feet: Vector3) -> void:
	var root := _spawn_root(feet, 1.4)
	var color := Color(1.0, 0.7, 0.3)
	var center := Vector3.UP * CHEST_HEIGHT
	_slash(root, color, center, 1.7, 0.0)
	_slash(root, Color(1.0, 0.9, 0.6), center, 1.2, 0.05)
	_ground_wave(root, color, 2.8, 0.1, 0.9, 0.4, 0.05)
	VfxLib.emit(root, VfxLib.particles(34, 0.6, 0.09, VfxLib.process({
		"radius": 0.15, "velocity": Vector2(2.5, 5.0), "gravity": Vector3(0, -7.0, 0),
		"colors": [[0.0, Color.WHITE], [0.35, color], [1.0, VfxLib.clear(Color(1.0, 0.4, 0.1))]],
	}), {"one_shot": true, "explosiveness": 1.0, "shape": VfxLib.SHAPE_SPARK, "energy": 2.4}), center)
	_light_flash(root, color, center, 4.0, 0.35, 4.0)


## Mortal Blow : deux entailles cramoisies croisées et une giclée d'étincelles rouges.
func _impact_blow(feet: Vector3) -> void:
	var root := _spawn_root(feet, 1.3)
	var color := Color(1.0, 0.15, 0.12)
	var center := Vector3.UP * CHEST_HEIGHT
	_slash(root, color, center, 1.3, 0.0)
	_slash(root, Color(1.0, 0.55, 0.5), center, 1.3, 0.09)
	VfxLib.emit(root, VfxLib.particles(26, 0.55, 0.08, VfxLib.process({
		"radius": 0.1, "velocity": Vector2(2.0, 4.0), "gravity": Vector3(0, -8.0, 0),
		"colors": [[0.0, Color(1.0, 0.8, 0.8)], [0.3, color], [1.0, VfxLib.clear(Color(0.4, 0.0, 0.0))]],
	}), {"one_shot": true, "explosiveness": 1.0, "shape": VfxLib.SHAPE_SPARK, "energy": 2.0}), center)
	_light_flash(root, color, center, 3.0, 0.3, 3.0)


## Maillage émissif sans ombrage (projectiles façonnés : flèche, éclat de glace).
static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Cône (ou cylindre si top_radius > 0) couché le long de -Z (avant du projectile orienté).
static func _forward_mesh(bottom_radius: float, top_radius: float, height: float, mat: Material, z: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.rotation.x = -PI / 2.0
	inst.position.z = z
	return inst


## Power Shot : flèche dorée (hampe, pointe, lueur) et sa traînée d'étincelles.
func _projectile_arrow(root: Node3D) -> Dictionary:
	var gold := Color(1.0, 0.85, 0.45)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(_forward_mesh(0.04, 0.04, 1.1, _emissive(Color(0.95, 0.8, 0.5), 1.6), 0.0))
	holder.add_child(_forward_mesh(0.1, 0.0, 0.28, _emissive(Color(1.0, 0.95, 0.8), 2.5), -0.68))
	var glow := VfxLib.glow_sprite(gold, 0.45, 1.4, 0.6)
	glow.position.z = -0.7
	root.add_child(glow)
	var trail := VfxLib.emit(root, VfxLib.particles(40, 0.35, 0.07, VfxLib.process({
		"radius": 0.05, "velocity": Vector2(0.05, 0.2),
		"colors": [[0.0, Color.WHITE], [0.4, gold], [1.0, VfxLib.clear(gold)]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 2.0}))
	var omni := VfxLib.light(gold, 1.2, 2.5)
	root.add_child(omni)
	return {"hide": [holder, glow], "trails": [trail], "light": omni, "arc": 0.3, "orient": true}


## Ice Bolt : éclat de glace effilé, halo glacé, traînée de givre scintillant.
func _projectile_ice(root: Node3D) -> Dictionary:
	var ice := Color(0.6, 0.88, 1.0)
	var shard := _forward_mesh(0.13, 0.0, 0.75, _emissive(Color(0.75, 0.93, 1.0), 1.8), -0.05)
	root.add_child(shard)
	var tail := _forward_mesh(0.02, 0.13, 0.25, _emissive(Color(0.45, 0.75, 1.0), 1.2), 0.45)
	root.add_child(tail)
	var halo := VfxLib.glow_sprite(Color(0.3, 0.65, 1.0), 0.9, 1.0, 0.1)
	root.add_child(halo)
	var frost := VfxLib.emit(root, VfxLib.particles(40, 0.6, 0.07, VfxLib.process({
		"radius": 0.18, "velocity": Vector2(0.1, 0.4), "gravity": Vector3(0, -1.5, 0),
		"colors": [[0.0, Color.WHITE], [0.4, ice], [1.0, VfxLib.clear(ice)]],
	}), {"shape": VfxLib.SHAPE_SPARK, "energy": 2.0}))
	var mist := VfxLib.emit(root, VfxLib.particles(18, 0.4, 0.3, VfxLib.process({
		"radius": 0.1, "velocity": Vector2(0.05, 0.2), "scale_curve": [Vector2(0, 0.5), Vector2(1, 1.0)],
		"colors": [[0.0, Color(0.6, 0.85, 1.0, 0.35)], [1.0, VfxLib.clear(ice)]],
	}), {"energy": 0.9}))
	var omni := VfxLib.light(ice, 1.8, 3.0)
	root.add_child(omni)
	return {"hide": [shard, tail, halo], "trails": [frost, mist], "light": omni, "arc": 0.12, "orient": true}
