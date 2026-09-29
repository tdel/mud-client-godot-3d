class_name TerrainNames
extends RefCounted
## Liste ordonnée des terrains connus (l'index = id d'item dans terrain_library.res) —
## partagée par generate_terrain_library.gd (qui construit la MeshLibrary dans cet ordre)
## et convert_tmx_to_scene.gd (qui doit retrouver le même id pour peindre les cases du
## GridMap), pour ne jamais faire diverger les deux tant qu'on repasse par ce point commun
## plutôt que de dupliquer la liste.

const FALLBACK_WALKABLE := "__walkable_fallback__"
const FALLBACK_BLOCKED := "__blocked_fallback__"
## Terrains ajoutés après coup à TERRAIN_COLORS : placés APRÈS les deux fallbacks pour ne pas
## décaler les ids d'items déjà peints dans les scènes existantes.
const APPENDED := ["water", "thicket", "bridge"]


static func ordered_list() -> Array:
	var za := preload("res://autoload/ZoneAssets3D.gd").new()
	var names: Array = za.TERRAIN_COLORS.keys().filter(func(n): return not APPENDED.has(n))
	names.append(FALLBACK_WALKABLE)
	names.append(FALLBACK_BLOCKED)
	names.append_array(APPENDED)
	za.free()
	return names
