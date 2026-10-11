class_name StatusVfx
extends Node3D
## Signes visibles des altérations d'état et des cubiques d'une entité (enfant de son nœud
## racine, voir Game3D._refresh_status_vfx) : étoiles qui tournent au-dessus de la tête
## (étourdi), « Z » qui s'envolent (endormi), anneau de racines aux pieds (enraciné, Ultimate
## Defense : dôme doré), spirale violette (peur), sceau barré (silence), points
## d'interrogation (confusion), voile gris (paralysé), halo blanc apaisé (Requiem), orbes des
## cubiques en orbite autour du torse.
##
## refresh(effects) reçoit l'entrée GameState.entity_effects de l'entité (nom de sort ->
## {status, cubic, ...}) et ne reconstruit que ce qui a changé.

## Hauteur du sommet de la silhouette (méta "head_height" du nœud entité, voir Game3D).
var head_height := 1.8

var _parts: Dictionary = {}  # clé (statut ou "cubic:<type>") -> Node3D
var _time := 0.0


func refresh(effects: Dictionary) -> void:
	var wanted := {}
	for entry in effects.values():
		var status := str(entry.get("status", ""))
		if not status.is_empty():
			wanted[status] = true
		var cubic := str(entry.get("cubic", ""))
		if not cubic.is_empty():
			wanted["cubic:" + cubic] = true
	for key in _parts.keys():
		if not wanted.has(key):
			_parts[key].queue_free()
			_parts.erase(key)
	for key in wanted.keys():
		if not _parts.has(key):
			var part := _build(str(key))
			if part != null:
				add_child(part)
				_parts[key] = part


func is_empty() -> bool:
	return _parts.is_empty()


func _process(delta: float) -> void:
	_time += delta
	for key in _parts.keys():
		var part: Node3D = _parts[key]
		match str(key):
			"STUN", "CONFUSION":
				part.rotation.y = _time * 3.2
			"FEAR":
				part.rotation.y = -_time * 4.0
				part.position.y = head_height + 0.25 + sin(_time * 6.0) * 0.05
			"SLEEP":
				for i in part.get_child_count():
					var z: Label3D = part.get_child(i)
					var t := fmod(_time * 0.6 + i / 3.0, 1.0)
					z.position = Vector3(0.15 + t * 0.35, t * 0.7, 0.0)
					z.modulate.a = sin(t * PI)
					z.pixel_size = 0.004 + t * 0.004
			"ROOT", "IMMOBILE", "PASSIVE":
				part.rotation.y = _time * 0.6
			_:
				if str(key).begins_with("cubic:"):
					var offset := 0.0 if key == "cubic:STORM" else PI
					part.position = Vector3(cos(_time * 1.6 + offset) * 0.7, 1.35 + sin(_time * 2.3) * 0.08,
							sin(_time * 1.6 + offset) * 0.7)


func _build(key: String) -> Node3D:
	match key:
		"STUN":
			return _orbit_of(_star_label("★", Color(1.0, 0.86, 0.25)), 3, 0.32, head_height + 0.18)
		"CONFUSION":
			return _orbit_of(_star_label("?", Color(0.95, 0.75, 1.0)), 3, 0.3, head_height + 0.2)
		"SLEEP":
			var sleep := Node3D.new()
			sleep.position = Vector3(0.0, head_height + 0.05, 0.0)
			for i in 3:
				var z := _star_label("Z", Color(0.75, 0.85, 1.0))
				sleep.add_child(z)
			return sleep
		"FEAR":
			var fear := Node3D.new()
			fear.position.y = head_height + 0.25
			fear.add_child(VfxLib.ring(Color(0.55, 0.15, 0.75), 0.9, 0.6, 0.08))
			fear.add_child(VfxLib.glow_sprite(Color(0.45, 0.1, 0.6), 0.45, 1.2))
			return fear
		"SILENCE":
			var silence := Node3D.new()
			silence.position.y = head_height + 0.3
			silence.add_child(_star_label("⊘", Color(0.8, 0.45, 1.0)))
			return silence
		"ROOT":
			var root := Node3D.new()
			root.position.y = 0.05
			root.add_child(VfxLib.ring(Color(0.35, 0.8, 0.25), 1.6, 0.55, 0.07, {"wobble": 0.3}))
			root.add_child(VfxLib.ring(Color(0.55, 0.35, 0.12), 1.2, 0.7, 0.06, {"wobble": 0.5}))
			return root
		"IMMOBILE":
			var dome := Node3D.new()
			dome.add_child(VfxLib.orb(Color(1.0, 0.85, 0.35), Color(1.0, 0.95, 0.7), 1.05, {"alpha": 0.22, "core_amount": 0.0}))
			dome.get_child(0).position.y = 0.9
			dome.add_child(VfxLib.ring(Color(1.0, 0.8, 0.3), 2.2, 0.95, 0.04))
			return dome
		"PARALYZE":
			var stone := Node3D.new()
			stone.add_child(VfxLib.orb(Color(0.55, 0.6, 0.7), Color(0.8, 0.85, 0.9), 0.95, {"alpha": 0.3, "core_amount": 0.0}))
			stone.get_child(0).position.y = 0.85
			return stone
		"PASSIVE":
			var calm := Node3D.new()
			calm.add_child(VfxLib.ring(Color(0.95, 0.95, 1.0), 1.4, 0.8, 0.05))
			calm.position.y = 0.06
			return calm
		"cubic:STORM":
			return _cubic(Color(0.35, 0.9, 1.0))
		"cubic:BINDING":
			return _cubic(Color(0.75, 0.35, 1.0))
	return null


func _cubic(color: Color) -> Node3D:
	var cubic := Node3D.new()
	cubic.add_child(VfxLib.orb(color, Color(1, 1, 1), 0.12))
	cubic.add_child(VfxLib.glow_sprite(color, 0.5, 1.4))
	return cubic


func _orbit_of(template: Label3D, count: int, radius: float, height: float) -> Node3D:
	var orbit := Node3D.new()
	orbit.position.y = height
	for i in count:
		var item: Label3D = template.duplicate() if i > 0 else template
		var angle := TAU * i / count
		item.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		orbit.add_child(item)
	return orbit


func _star_label(text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	return label
