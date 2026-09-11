class_name TerrainTextureGenerator
extends RefCounted
## Génère des textures de terrain procédurales (albedo + normal) à partir d'une seule
## couleur de base — remplace les blocs plats de ZoneAssets3D.build_ground_texture par un
## grain/relief simple, dans le même esprit "tout procédural, aucun art externe" que le
## reste de ZoneAssets3D.gd (icônes de hotbar, etc.). Utilisé uniquement par
## tools/generate_terrain_library.gd : le rendu en jeu ne recalcule jamais ces textures,
## elles sont cuites une fois dans assets/terrain/terrain_library.res.

const SIZE := 128


static func generate_albedo(base_color: Color, seed_value: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.06
	noise.fractal_octaves = 3

	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var n := noise.get_noise_2d(x, y)
			var shade := 1.0 + n * 0.18
			image.set_pixel(x, y, Color(
				clampf(base_color.r * shade, 0.0, 1.0),
				clampf(base_color.g * shade, 0.0, 1.0),
				clampf(base_color.b * shade, 0.0, 1.0),
			))
	return image


## Normal map dérivée d'une heightmap de bruit indépendante de l'albedo (graine +1) : la
## générer depuis la même graine que l'albedo donnait un relief qui "gaufre" exactement là
## où l'albedo fonce/éclaircit, un léger décalage de graine casse cette corrélation.
static func generate_normal(seed_value: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 1
	noise.frequency = 0.06
	noise.fractal_octaves = 3

	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_RF)
	for y in SIZE:
		for x in SIZE:
			height.set_pixel(x, y, Color(noise.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 0.0))

	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var inverse_strength := 0.4
	for y in SIZE:
		for x in SIZE:
			var hl := height.get_pixel(wrapi(x - 1, 0, SIZE), y).r
			var hr := height.get_pixel(wrapi(x + 1, 0, SIZE), y).r
			var hu := height.get_pixel(x, wrapi(y - 1, 0, SIZE)).r
			var hd := height.get_pixel(x, wrapi(y + 1, 0, SIZE)).r
			var n := Vector3(hl - hr, hu - hd, inverse_strength).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return normal
