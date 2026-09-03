extends Control
## Silhouettes de personnages + effet de sort dessinées en code, superposées au fond
## res://Backgrounds/night_castle_moon.png (voir CLAUDE.md, refonte visuelle) sur
## Login/CharSelect/CharacterCreate. Le pack Claw&Blade déjà importé (voir
## ZoneAssets.gd) ne fournit que des portraits bustes 128x128, pas de pose pleine
## longueur avec arme : plutôt que de chercher 4 illustrations séparées d'origines et
## de styles hétérogènes (et de devoir suivre 4 licences différentes), ces silhouettes
## d'ambiance sont générées ici, dans le même esprit procédural que ZoneAssets/UITheme.
## Jamais utilisées comme sprites de jeu (uniquement décor des écrans hors-jeu).

## Bleu-ardoise sombre plutôt que noir pur : sur le bandeau de sol (voir _draw), un
## remplissage quasi noir se fond dans le fond et ne laisse voir que le contour doré
## (silhouettes en "fil de fer" constatées à l'écran) — cette teinte reste sombre mais
## se détache nettement du ciel/de la colline.
const SILHOUETTE := Color(0.13, 0.17, 0.27, 1.0)
const RIM := Color(0.82, 0.72, 0.48, 0.6)
const WEAPON := Color(0.88, 0.80, 0.58, 0.9)
const ORB_CORE := Color(0.85, 0.62, 1.0, 1.0)
const ORB_GLOW := Color(0.55, 0.35, 0.95, 0.4)
const GROUND_TOP := Color(0.05, 0.04, 0.03, 0.0)
const GROUND_BOTTOM := Color(0.03, 0.025, 0.02, 0.68)

var _time := 0.0
var _particles: CPUParticles2D

var _mage_pos: Vector2
var _mage_h: float


## Désactivé (2026-08-27) : les 4 personnages sont désormais incrustés directement
## dans Backgrounds/night_castle_moon.png (voir CLAUDE.md) — dessiner ces silhouettes
## par-dessus ferait doublon (formes vectorielles + bandeau sombre superposés aux
## vrais personnages). Node laissé en place dans les scènes plutôt que retiré des
## .tscn, pour pouvoir réactiver facilement si le fond change à nouveau.
const _DISABLED := true


func _ready() -> void:
	if _DISABLED:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	resized.connect(func(): queue_redraw())

	# Étincelles montant de l'orbe du sort (voir _draw_mage) — seul élément non tracé en
	# _draw(), CPUParticles2D gère mieux le mouvement/la durée de vie qu'un dessin manuel.
	_particles = CPUParticles2D.new()
	_particles.emitting = true
	_particles.amount = 14
	_particles.lifetime = 2.4
	_particles.direction = Vector2.UP
	_particles.spread = 22.0
	_particles.gravity = Vector2(0, -12)
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 14.0
	_particles.scale_amount_min = 1.4
	_particles.scale_amount_max = 2.6
	_particles.color = Color(0.78, 0.58, 1.0, 0.85)
	add_child(_particles)


func _process(delta: float) -> void:
	if _DISABLED:
		return
	_time += delta
	_mage_pos = Vector2(size.x * 0.91, size.y * 0.95)
	_mage_h = size.y * 0.27
	_particles.position = _orb_point()
	queue_redraw()


func _orb_point() -> Vector2:
	return _mage_pos + Vector2(_mage_h * 0.34, -_mage_h * 1.02)


func _draw() -> void:
	if _DISABLED:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return

	# Bandeau sombre au raz du sol : garantit que les silhouettes restent lisibles quel
	# que soit le contenu exact de l'image à cet endroit (pas de recalage pixel-perfect
	# possible sans capture d'écran dans cet environnement, voir CLAUDE.md).
	var strip_top := size.y * 0.68
	draw_polygon(
		PackedVector2Array([
			Vector2(0, strip_top), Vector2(size.x, strip_top),
			Vector2(size.x, size.y), Vector2(0, size.y),
		]),
		PackedColorArray([GROUND_TOP, GROUND_TOP, GROUND_BOTTOM, GROUND_BOTTOM])
	)

	_draw_swordsman(Vector2(size.x * 0.07, size.y * 0.95), size.y * 0.26)
	_draw_archer(Vector2(size.x * 0.19, size.y * 0.95), size.y * 0.24)
	_draw_dwarf(Vector2(size.x * 0.81, size.y * 0.95), size.y * 0.19)
	_draw_mage(_mage_pos, _mage_h)


func _shape(points: PackedVector2Array) -> void:
	draw_colored_polygon(points, SILHOUETTE)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, RIM, 1.3, true)


func _circle_shape(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, SILHOUETTE)
	draw_arc(center, radius, 0, TAU, 20, RIM, 1.3, true)


## Jambes + torse + tête communs, `pos` = point au sol entre les pieds, `h` = hauteur
## totale du personnage. Retourne le y du sommet des épaules (repère local, négatif).
func _body(pos: Vector2, h: float, leg_w: float, hip_frac: float, shoulder_frac: float, shoulder_w: float) -> float:
	var hip_y := -h * hip_frac
	var shoulder_y := -h * shoulder_frac
	_shape(PackedVector2Array([
		pos + Vector2(-leg_w * 0.55, 0), pos + Vector2(-leg_w * 0.20, 0),
		pos + Vector2(-leg_w * 0.14, hip_y), pos + Vector2(-leg_w * 0.42, hip_y),
	]))
	_shape(PackedVector2Array([
		pos + Vector2(leg_w * 0.20, 0), pos + Vector2(leg_w * 0.55, 0),
		pos + Vector2(leg_w * 0.42, hip_y), pos + Vector2(leg_w * 0.14, hip_y),
	]))
	_shape(PackedVector2Array([
		pos + Vector2(-leg_w * 0.34, hip_y), pos + Vector2(leg_w * 0.34, hip_y),
		pos + Vector2(shoulder_w, shoulder_y), pos + Vector2(-shoulder_w, shoulder_y),
	]))
	_circle_shape(pos + Vector2(0, shoulder_y - h * 0.10), h * 0.095)
	return shoulder_y


## Humain, épée levée + petit bouclier rond dans le dos.
func _draw_swordsman(pos: Vector2, h: float) -> void:
	var w := h * 0.30
	var shoulder_y := _body(pos, h, w, 0.44, 0.80, w * 0.30)
	var shoulder_pt := pos + Vector2(w * 0.28, shoulder_y + h * 0.05)
	var hand_pt := pos + Vector2(w * 0.46, shoulder_y - h * 0.20)
	var blade_tip := hand_pt + Vector2(w * 0.06, -h * 0.42)
	draw_line(shoulder_pt, hand_pt, SILHOUETTE, w * 0.22)
	draw_line(hand_pt, blade_tip, WEAPON, 2.2)
	_circle_shape(pos + Vector2(-w * 0.32, shoulder_y + h * 0.12), w * 0.20)


## Elfe, arc bandé (pose de tir) et carquois dans le dos.
func _draw_archer(pos: Vector2, h: float) -> void:
	var w := h * 0.28
	var shoulder_y := _body(pos, h, w, 0.44, 0.80, w * 0.26)
	# Arc (silhouette en "D" : la courbure bombe vers l'extérieur, la corde reste droite)
	# + flèche encochée tirée vers l'arrière, plutôt qu'un point de tir confondu avec le
	# torse (essai précédent, illisible à l'échelle du bandeau — voir capture de test).
	var bow_center := pos + Vector2(w * 0.78, shoulder_y + h * 0.05)
	var bow_radius := h * 0.20
	var start_a := -PI * 0.42
	var end_a := PI * 0.42
	draw_arc(bow_center, bow_radius, start_a, end_a, 20, WEAPON, 2.0, true)
	var top := bow_center + Vector2(cos(start_a), sin(start_a)) * bow_radius
	var bottom := bow_center + Vector2(cos(end_a), sin(end_a)) * bow_radius
	draw_line(top, bottom, WEAPON, 1.3)
	var string_mid := (top + bottom) / 2.0
	var nock := string_mid + Vector2(-w * 0.16, 0)
	draw_line(nock, bow_center + Vector2(bow_radius * 0.85, 0), WEAPON, 1.6)
	_shape(PackedVector2Array([
		pos + Vector2(-w * 0.42, shoulder_y + h * 0.18), pos + Vector2(-w * 0.24, shoulder_y + h * 0.18),
		pos + Vector2(-w * 0.20, shoulder_y - h * 0.12), pos + Vector2(-w * 0.46, shoulder_y - h * 0.12),
	]))


## Nain, silhouette basse et large, hache portée sur l'épaule + barbe.
func _draw_dwarf(pos: Vector2, h: float) -> void:
	var w := h * 0.46
	var shoulder_y := _body(pos, h, w, 0.42, 0.78, w * 0.34)
	_shape(PackedVector2Array([
		pos + Vector2(-w * 0.16, shoulder_y - h * 0.06), pos + Vector2(w * 0.16, shoulder_y - h * 0.06),
		pos + Vector2(0, shoulder_y + h * 0.20),
	]))
	var hand_pt := pos + Vector2(w * 0.30, shoulder_y - h * 0.02)
	var head_pt := pos + Vector2(w * 0.50, shoulder_y - h * 0.36)
	draw_line(hand_pt, head_pt, SILHOUETTE, w * 0.11)
	var dir := (head_pt - hand_pt).normalized()
	var perp := Vector2(-dir.y, dir.x)
	_shape(PackedVector2Array([
		head_pt + perp * h * 0.16, head_pt + dir * h * 0.14 + perp * h * 0.05,
		head_pt + dir * h * 0.14 - perp * h * 0.22, head_pt - perp * h * 0.22,
	]))


## Elfe noire, robe évasée, bâton surmonté d'un orbe lumineux (le "sort" en train
## d'être lancé) et cercle runique flottant au sol (deuxième effet, plus discret).
func _draw_mage(pos: Vector2, h: float) -> void:
	var w := h * 0.26
	var shoulder_y := _body(pos, h, w, 0.46, 0.82, w * 0.22)
	_shape(PackedVector2Array([
		pos + Vector2(-w * 0.62, 0), pos + Vector2(w * 0.62, 0),
		pos + Vector2(w * 0.30, -h * 0.40), pos + Vector2(-w * 0.30, -h * 0.40),
	]))
	var hand_pt := pos + Vector2(w * 0.36, shoulder_y + h * 0.05)
	var orb_pt := _orb_point()
	draw_line(hand_pt, orb_pt, WEAPON, 1.8)

	var pulse := 0.75 + 0.25 * sin(_time * 2.4)
	draw_circle(orb_pt, h * 0.20 * pulse, ORB_GLOW)
	draw_circle(orb_pt, h * 0.11 * pulse, Color(ORB_GLOW.r, ORB_GLOW.g, ORB_GLOW.b, 0.6))
	draw_circle(orb_pt, h * 0.05, ORB_CORE)

	var ring_pulse := 0.85 + 0.15 * sin(_time * 1.6 + 1.0)
	draw_arc(
		pos + Vector2(0, -h * 0.02), w * 0.9 * ring_pulse, 0, TAU, 28,
		Color(ORB_GLOW.r, ORB_GLOW.g, ORB_GLOW.b, 0.4), 1.4, true
	)
