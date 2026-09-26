@tool
class_name EnvMaterials
extends RefCounted
## Matériaux partagés de l'environnement (arbres, props de carte). Les .glb produits par
## tools/env_gen/build_environment.py n'embarquent aucune image : leurs matériaux ne portent
## qu'un nom stable (bark_oak, foliage_fir, planks_old, iron...), remplacé ici par un
## matériau construit une seule fois à partir des textures d'assets/environment/textures —
## une seule copie de chaque texture en mémoire, et un même shader (bark.gdshader) pour tout
## ce qui doit devenir transparent en damier quand il cache le joueur.

const TEX_DIR := "res://assets/environment/textures/"
const FOLIAGE_SHADER := preload("res://scenes/maps/common/foliage.gdshader")
const BARK_SHADER := preload("res://scenes/maps/common/bark.gdshader")

## nom de matériau glTF -> [asset ambientCG, répétition UV, teinte]
const PBR := {
	"bark_oak": ["Bark012", Vector2(1, 1), Color(0.85, 0.8, 0.75)],
	"bark_fir": ["Bark014", Vector2(1, 1), Color(0.8, 0.72, 0.66)],
	"bark_birch": ["Bark001", Vector2(1, 1), Color(1.05, 1.05, 1.05)],
	"rock": ["Rock020", Vector2(1, 1), Color(0.85, 0.85, 0.82)],
	"stone_bricks": ["Bricks089", Vector2(1, 2), Color(1, 1, 1)],
	"stone_smooth": ["Rock020", Vector2(1, 1), Color(0.95, 0.93, 0.9)],
	"iron": ["Metal021", Vector2(1, 1), Color(0.55, 0.52, 0.5)],
	"wood_dark": ["Wood051", Vector2(1, 1), Color(0.8, 0.75, 0.7)],
	"wood_sign": ["Wood049", Vector2(1, 1), Color(0.85, 0.75, 0.6)],
	"planks_old": ["Planks023A", Vector2(1, 1), Color(0.9, 0.88, 0.85)],
	"planks_fresh": ["Planks021", Vector2(1, 1), Color(0.85, 0.78, 0.68)],
	"roof_slate": ["RoofingTiles001", Vector2(1, 1), Color(0.6, 0.62, 0.6)],
	"castle_stone": ["Bricks076A", Vector2(1, 1), Color(0.95, 0.93, 0.9)],
	"rubble_stone": ["Bricks102", Vector2(1, 2), Color(0.9, 0.88, 0.85)],
	"plaster": ["Plaster003", Vector2(1, 1), Color(0.96, 0.92, 0.84)],
	"roof_tiles": ["RoofingTiles006", Vector2(1, 1), Color(0.85, 0.72, 0.66)],
}
## Matériaux unis (sans texture) : nom -> [teinte, couleur d'émission, énergie d'émission de
## jour, énergie de nuit]. Les vitres ne s'allument que la nuit ; runes et braises brillent
## en permanence (voir set_night_factor, appelé par les props du groupe LampPost.NIGHT_GROUP).
const FLAT := {
	"window_glass": [Color(0.07, 0.08, 0.11), Color(1.0, 0.7, 0.38), 0.0, 1.6],
	"lamp_glass": [Color(1.0, 0.85, 0.6), Color(1.0, 0.7, 0.38), 0.2, 3.7],
	"rune_glow": [Color(0.3, 0.6, 1.0), Color(0.35, 0.65, 1.0), 1.3, 2.8],
	"forge_fire": [Color(1.0, 0.45, 0.12), Color(1.0, 0.42, 0.1), 2.6, 3.6],
	"cloth_red": [Color(0.48, 0.07, 0.06), Color.BLACK, 0.0, 0.0],
	"cloth_blue": [Color(0.1, 0.17, 0.42), Color.BLACK, 0.0, 0.0],
	"cloth_cream": [Color(0.76, 0.7, 0.56), Color.BLACK, 0.0, 0.0],
	"shadow_dark": [Color(0.02, 0.02, 0.02), Color.BLACK, 0.0, 0.0],
}
## nom -> [texture, tint, vent (amplitude), hauteur de balancement (m), translucidité]
const FOLIAGE := {
	"foliage_oak": ["foliage_oak.png", Color(0.6, 0.7, 0.55), 0.10, 7.0, 0.35],
	"foliage_birch": ["foliage_birch.png", Color(0.68, 0.78, 0.56), 0.12, 7.0, 0.4],
	"foliage_fir": ["foliage_fir.png", Color(0.58, 0.68, 0.58), 0.06, 10.0, 0.25],
	"foliage_grass": ["foliage_grass.png", Color(0.62, 0.72, 0.5), 0.08, 0.6, 0.45],
	"foliage_grass_seed": ["foliage_grass_seed.png", Color(0.68, 0.72, 0.55), 0.1, 0.7, 0.45],
}

static var _cache: Dictionary = {}
static var _night_factor := 0.0


## Matériau partagé pour `material_name`, ou null si ce nom n'est pas géré ici (le matériau
## importé du .glb reste alors en place).
static func get_material(material_name: String) -> Material:
	if _cache.has(material_name):
		return _cache[material_name]
	var mat: Material = null
	if PBR.has(material_name):
		var def: Array = PBR[material_name]
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = BARK_SHADER
		shader_mat.set_shader_parameter("albedo_texture", load(TEX_DIR + def[0] + "_color.jpg"))
		shader_mat.set_shader_parameter("normal_texture", load(TEX_DIR + def[0] + "_normal.jpg"))
		shader_mat.set_shader_parameter("roughness_texture", load(TEX_DIR + def[0] + "_rough.jpg"))
		shader_mat.set_shader_parameter("uv_scale", def[1])
		shader_mat.set_shader_parameter("tint", def[2])
		# Seuls les arbres se balancent ; props (pierre, fer, planches) immobiles.
		shader_mat.set_shader_parameter("wind_strength", 0.1 if material_name.begins_with("bark_") else 0.0)
		# Rochers : trop bas pour cacher le joueur, pas de tramage.
		shader_mat.set_shader_parameter("occlusion_fade", material_name != "rock")
		mat = shader_mat
	elif FOLIAGE.has(material_name):
		var def: Array = FOLIAGE[material_name]
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = FOLIAGE_SHADER
		shader_mat.set_shader_parameter("albedo_texture", load(TEX_DIR + def[0]))
		shader_mat.set_shader_parameter("tint", def[1])
		shader_mat.set_shader_parameter("wind_strength", def[2])
		shader_mat.set_shader_parameter("sway_height", def[3])
		shader_mat.set_shader_parameter("translucency", def[4])
		# L'herbe ne cache jamais le joueur : pas de tramage (moins de calcul par pixel).
		shader_mat.set_shader_parameter("occlusion_fade", not material_name.begins_with("foliage_grass"))
		mat = shader_mat
	elif FLAT.has(material_name):
		var def: Array = FLAT[material_name]
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = BARK_SHADER
		shader_mat.set_shader_parameter("use_albedo_texture", false)
		shader_mat.set_shader_parameter("use_normal_map", false)
		shader_mat.set_shader_parameter("use_roughness_map", false)
		shader_mat.set_shader_parameter("tint", def[0])
		shader_mat.set_shader_parameter("wind_strength", 0.0)
		shader_mat.set_shader_parameter("emission_color", def[1])
		shader_mat.set_shader_parameter("emission_energy", lerpf(def[2], def[3], _night_factor))
		mat = shader_mat
	elif material_name == "wood_rings":
		var std := StandardMaterial3D.new()
		std.albedo_texture = load(TEX_DIR + "wood_rings.jpg")
		std.roughness = 0.85
		mat = std
	_cache[material_name] = mat
	return mat


## Énergie d'émission courante d'un matériau uni (FLAT) : celle de jour ou de nuit selon le
## dernier set_night_factor.
static func emission_energy(material_name: String) -> float:
	var def: Array = FLAT.get(material_name, [])
	return lerpf(def[2], def[3], _night_factor) if not def.is_empty() else 0.0


## Allume vitres/lanternes/runes selon l'heure (0.0 = plein jour, 1.0 = pleine nuit) : un
## seul matériau partagé par nom, tous les bâtiments suivent. Appelé par chaque prop du groupe
## LampPost.NIGHT_GROUP qui en porte (House, Teleporter) — idempotent.
static func set_night_factor(factor: float) -> void:
	_night_factor = factor
	for material_name in FLAT:
		var mat := _cache.get(material_name) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("emission_energy", emission_energy(material_name))


## Copie de `mesh` dont chaque surface reçoit son matériau partagé (pour les MultiMesh, qui
## n'ont pas de surcharge de matériau par surface).
static func remap_mesh(mesh: Mesh) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var current := copy.surface_get_material(i)
		if current == null:
			continue
		var shared := get_material(current.resource_name)
		if shared != null:
			copy.surface_set_material(i, shared)
	return copy


## Applique les matériaux partagés à tous les MeshInstance3D sous `root` (surcharges de
## surface : le .glb importé reste intact).
static func apply(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			var mi: MeshInstance3D = node
			for i in mi.mesh.get_surface_count():
				var current := mi.mesh.surface_get_material(i)
				if current == null:
					continue
				var shared := get_material(current.resource_name)
				if shared != null:
					mi.set_surface_override_material(i, shared)
