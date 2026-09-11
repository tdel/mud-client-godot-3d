extends SceneTree
## Outil hors-ligne : cuit une texture procédurale par terrain (voir
## TerrainTextureGenerator.gd) dans une MeshLibrary partagée par toutes les cartes
## converties depuis Tiled (voir convert_tmx_to_scene.gd). À relancer si on retouche la
## palette de terrains (TERRAIN_COLORS dans autoload/ZoneAssets3D.gd).
##
## Lancer avec :
##   godot --headless --script res://tools/generate_terrain_library.gd

const LIBRARY_PATH := "res://assets/terrain/terrain_library.res"

const TerrainTextureGenerator = preload("res://tools/TerrainTextureGenerator.gd")
const TerrainNames = preload("res://tools/TerrainNames.gd")


func _initialize() -> void:
	var za := preload("res://autoload/ZoneAssets3D.gd").new()
	var colors: Dictionary = za.TERRAIN_COLORS
	var fallback_colors := {
		TerrainNames.FALLBACK_WALKABLE: za.WALKABLE_FALLBACK_COLOR,
		TerrainNames.FALLBACK_BLOCKED: za.BLOCKED_FALLBACK_COLOR,
	}

	DirAccess.make_dir_recursive_absolute("res://assets/terrain")

	var library := MeshLibrary.new()
	var names := TerrainNames.ordered_list()
	for id in names.size():
		var terrain_name: String = names[id]
		var base_color: Color = fallback_colors.get(terrain_name, colors.get(terrain_name))
		_add_item(library, id, terrain_name, base_color)
		print("Terrain %d: %s" % [id, terrain_name])
	za.free()

	var err := ResourceSaver.save(library, LIBRARY_PATH)
	if err != OK:
		printerr("Échec sauvegarde %s (code %d)" % [LIBRARY_PATH, err])
		quit(1)
		return

	print("MeshLibrary écrite : %s (%d terrains)" % [LIBRARY_PATH, names.size()])
	quit()


func _add_item(library: MeshLibrary, id: int, terrain_name: String, base_color: Color) -> void:
	var seed_value: int = absi(hash(terrain_name)) % 100000
	var albedo_image := TerrainTextureGenerator.generate_albedo(base_color, seed_value)
	var normal_image := TerrainTextureGenerator.generate_normal(seed_value)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(albedo_image)
	mat.normal_enabled = true
	mat.normal_texture = ImageTexture.create_from_image(normal_image)
	mat.roughness = 0.95

	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = mat

	library.create_item(id)
	library.set_item_name(id, terrain_name)
	library.set_item_mesh(id, mesh)
