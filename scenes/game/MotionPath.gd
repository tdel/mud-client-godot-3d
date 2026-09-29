class_name MotionPath
## Suivi côté client des chemins à waypoints envoyés par le serveur (MovementStarted/
## CharacterMovementStarted/EntityView.waypoints) : même trajectoire que MovementEngine/
## ContinuousStep côté serveur, pour ne plus diverger autour des obstacles (voir
## Game3D._step_movement). `path` est un Array de Vector3 (plan XZ = x/y serveur), consommé
## au fur et à mesure.


## Avance `from` de `distance` le long de `path` (waypoints atteints retirés) ; renvoie la
## nouvelle position.
static func advance(from: Vector3, path: Array, distance: float) -> Vector3:
	var pos := from
	var budget := distance
	while budget > 0.0 and not path.is_empty():
		var waypoint: Vector3 = path[0]
		var to_waypoint := pos.distance_to(waypoint)
		if to_waypoint <= budget:
			pos = waypoint
			budget -= to_waypoint
			path.pop_front()
		else:
			pos = pos.move_toward(waypoint, budget)
			budget = 0.0
	return pos


## Longueur restante de `from` jusqu'au bout de `path`.
static func remaining_length(from: Vector3, path: Array) -> float:
	var length := 0.0
	var segment_start := from
	for waypoint in path:
		length += segment_start.distance_to(waypoint)
		segment_start = waypoint
	return length


## Recalage de `from` vers `pos` (correction serveur) : retire les waypoints que `pos` a déjà
## dépassés — le segment de la polyligne (from, path...) le plus proche de `pos` devient le
## segment courant. Sans ça, une correction juste après un virage renverrait le personnage en
## arrière vers le waypoint du virage.
static func drop_passed_waypoints(path: Array, from: Vector3, pos: Vector3) -> void:
	var best_index := 0
	var best_distance := INF
	var segment_start := from
	for i in path.size():
		var closest := Geometry3D.get_closest_point_to_segment(pos, segment_start, path[i])
		var distance := closest.distance_squared_to(pos)
		if distance < best_distance:
			best_distance = distance
			best_index = i
		segment_start = path[i]
	for i in best_index:
		path.pop_front()


## rotation.y d'un nœud dont le -Z local doit regarder dans `direction` (même convention que
## Node3D.look_at, voir Game3D._face_direction).
static func yaw_toward(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
