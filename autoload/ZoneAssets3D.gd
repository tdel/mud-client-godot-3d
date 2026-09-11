extends Node
## Terrain et cartes : depuis la migration vers l'éditeur Godot interne (les cartes sont
## désormais des scènes res://scenes/maps/*.tscn contenant un GridMap peint avec
## assets/terrain/terrain_library.res, voir tools/convert_tmx_to_scene.gd), ce fichier ne
## garde que : (1) l'annuaire nom de carte -> chemin de scène, construit une fois au
## démarrage en scannant scenes/maps/ (équivalent du _scan_map_files historique, qui
## scannait des .tmx) et (2) les données de terrain encore utiles à Game3D après coup —
## couleurs simplifiées pour la minimap (TERRAIN_COLORS) et hauteur d'obstacle
## (TALL_OBSTACLE_TERRAINS) — le nom de terrain par case étant désormais lu en direct sur
## le GridMap de la scène instanciée (voir Game3D._read_terrain_grid) plutôt que stocké ici.
## Comme avant la migration, le walkable/non-walkable envoyé par le serveur
## (MapView.grid.walkableRows) reste l'unique source de vérité pour les règles de jeu : les
## scènes de carte ne servent qu'au rendu (sol, hauteur d'obstacle, lumières de nuit).
##
## Prototype : ce fichier ne fait QUE le rendu du sol/des obstacles. Combat, sorts,
## équipement visuel, animations ne sont pas dans le scope de ce prototype (voir
## scenes/game/Game3D.gd).

const MAP_SCENES_DIR := "res://scenes/maps"
const PX_PER_TILE := 4

## Couleurs de terrain — copiées telles quelles depuis ZoneAssets.gd (2D) pour rester
## visuellement cohérentes entre les deux prototypes.
const TERRAIN_COLORS := {
	"rampart": Color(0.35, 0.35, 0.38), "gate": Color(0.55, 0.45, 0.30),
	"pavedStone": Color(0.62, 0.62, 0.65), "fountain": Color(0.25, 0.55, 0.78),
	"auberge": Color(0.72, 0.42, 0.22), "forge": Color(0.50, 0.22, 0.18),
	"dirtPath": Color(0.55, 0.42, 0.28), "grass": Color(0.32, 0.56, 0.26),
	"tree": Color(0.18, 0.40, 0.20), "forestFloor": Color(0.35, 0.38, 0.22),
	"fieldCrop": Color(0.72, 0.65, 0.28), "fence": Color(0.60, 0.50, 0.35),
	"hedge": Color(0.22, 0.42, 0.22), "bramble": Color(0.35, 0.32, 0.18),
	"darkGrass": Color(0.22, 0.38, 0.20), "clearingGrass": Color(0.40, 0.62, 0.30),
	"tallGrass": Color(0.30, 0.50, 0.24), "denseTallGrass": Color(0.24, 0.42, 0.20),
	"tallGrassPatch": Color(0.34, 0.52, 0.26), "ironGate": Color(0.30, 0.30, 0.32),
	"deadTree": Color(0.40, 0.35, 0.30), "dangerGround": Color(0.45, 0.40, 0.35),
	"grave": Color(0.45, 0.45, 0.50), "mausoleum": Color(0.55, 0.55, 0.58),
	"rockWall": Color(0.30, 0.28, 0.27), "caveFloor": Color(0.32, 0.28, 0.26),
	"rubble": Color(0.40, 0.38, 0.36),
}
const WALKABLE_FALLBACK_COLOR := Color(0.40, 0.60, 0.35)
const BLOCKED_FALLBACK_COLOR := Color(0.25, 0.25, 0.28)

## Terrains non franchissables qu'on affiche plus hauts (mur/rempart/tronc) qu'un simple
## obstacle bas (buisson/débris/tombe) — purement cosmétique, choisi à la main faute
## d'information de hauteur dans le protocole.
const TALL_OBSTACLE_TERRAINS := {
	"rampart": true, "tree": true, "ironGate": true, "rockWall": true,
	"mausoleum": true, "deadTree": true, "gate": true,
}

## map_name (propriété "name" exportée par MapData.gd sur la racine de la scène) -> chemin
## de la scène res://scenes/maps/*.tscn correspondante — voir _scan_map_scenes.
var _map_scene_path_by_name: Dictionary = {}


func _ready() -> void:
	_scan_map_scenes()


## Chemin de la scène convertie pour `map_name` (nom envoyé par le serveur dans
## MapView.mapName), ou "" si aucune carte n'a été convertie sous ce nom — voir
## Game3D._rebuild_map, qui instancie cette scène pour le rendu du sol.
func get_map_scene_path(map_name: String) -> String:
	return _map_scene_path_by_name.get(map_name, "")


## Construit une texture de sol simplifiée pour la minimap (une passe, un seul quad à
## l'usage — voir Game3D._minimap) : PX_PER_TILE x PX_PER_TILE pixels par case, coloré par
## terrain connu ou par un fallback marche/bloqué déterminé par le grid serveur.
## `terrain_grid` (Array[Array[String]]) est lu par l'appelant sur le GridMap de la carte
## tout juste instanciée, voir Game3D._read_terrain_grid.
func build_ground_texture(map_view_payload: Dictionary, terrain_grid: Array) -> ImageTexture:
	var grid: Dictionary = map_view_payload.get("grid", {})
	var width: int = grid.get("width", 0)
	var height: int = grid.get("height", 0)
	var walkable_rows: Array = grid.get("walkableRows", [])

	var image := Image.create(maxi(width * PX_PER_TILE, 1), maxi(height * PX_PER_TILE, 1), false, Image.FORMAT_RGBA8)

	var rng := RandomNumberGenerator.new()
	for y in height:
		var row: String = walkable_rows[y] if y < walkable_rows.size() else ""
		var terrain_row: Array = terrain_grid[y] if y < terrain_grid.size() else []
		for x in width:
			var walkable: bool = x < row.length() and row[x] == "1"
			var terrain_name: String = terrain_row[x] if x < terrain_row.size() else ""
			var base_color: Color = TERRAIN_COLORS.get(
				terrain_name,
				WALKABLE_FALLBACK_COLOR if walkable else BLOCKED_FALLBACK_COLOR
			)
			rng.seed = hash(Vector2i(x, y))
			var variance := rng.randf_range(-0.05, 0.05)
			var cell_color := Color(
				clampf(base_color.r + variance, 0.0, 1.0),
				clampf(base_color.g + variance, 0.0, 1.0),
				clampf(base_color.b + variance, 0.0, 1.0),
			)
			image.fill_rect(Rect2i(x * PX_PER_TILE, y * PX_PER_TILE, PX_PER_TILE, PX_PER_TILE), cell_color)
			# Liseré assombri sur les deux bords haut/gauche de la case : ancre visuellement
			# le sol vu de l'angle iso sans le bruit de moiré qu'un pixel isolé par coin
			# donnait sous filtrage "nearest" à cet angle (essayé, retiré).
			var edge_color := cell_color.darkened(0.18)
			image.fill_rect(Rect2i(x * PX_PER_TILE, y * PX_PER_TILE, PX_PER_TILE, 1), edge_color)
			image.fill_rect(Rect2i(x * PX_PER_TILE, y * PX_PER_TILE, 1, PX_PER_TILE), edge_color)

	var texture := ImageTexture.create_from_image(image)
	return texture


## Hauteur d'obstacle (mètres) pour une case non franchissable de terrain `terrain_name`,
## ou 0.0 si franchissable — Game3D construit un MultiMeshInstance3D de blocs à partir de
## cette info (voir Game3D._rebuild_obstacles). Purement cosmétique : la vraie règle de
## collision reste walkableRows côté serveur, jamais recalculée ici.
func obstacle_height_for(terrain_name: String, walkable: bool) -> float:
	if walkable:
		return 0.0
	return 2.4 if TALL_OBSTACLE_TERRAINS.get(terrain_name, false) else 0.7


## Couleur de base par catégorie de slot hotbar — copiée telle quelle depuis ZoneAssets.gd
## (2D) ; la variation par ref_name (voir make_slot_icon_texture) est ce qui différencie
## deux slots de la même catégorie.
const SLOT_KIND_COLORS := {
	"attack": Color(0.85, 0.25, 0.25),
	"skill": Color(0.30, 0.45, 0.90),
	"item": Color(0.30, 0.75, 0.35),
}


## Icône carrée procédurale pour un slot de hotbar : couleur de catégorie (kind), variée
## de façon déterministe selon ref_name pour distinguer deux slots de même catégorie, avec
## un léger dégradé et un liseré assombri. Copiée telle quelle depuis ZoneAssets.gd (2D) :
## pure génération de texture 2D, indépendante du rendu 3D du reste de ce fichier.
##
## Quelques objets/sorts emblématiques ont en plus une icône dessinée à la main (toujours
## procédurale, aucun art externe dans ce prototype — voir CLAUDE.md) plutôt que le carré
## générique ci-dessous, dans l'esprit des icônes Lineage 1/2 pour ces mêmes objets/sorts :
## fiole à bouchon pour les potions de soin/mana, croix dorée lumineuse pour "Heal",
## spirale verte pour "Wind Strike". `kind` distingue l'objet "Healing Potion" du sort
## "Heal" sans collision de nom. Noms matchés tels qu'envoyés par le serveur, voir
## data/items/consumables.xml et data/skills/skills.xml côté mud-server-java.
func make_slot_icon_texture(kind: String, ref_name: String, size: int = 40) -> ImageTexture:
	var lower_name := ref_name.to_lower()
	if kind == "item" and lower_name.ends_with("healing potion"):
		return _make_potion_icon_texture(Color(0.85, 0.12, 0.14), size)
	if kind == "item" and lower_name.ends_with("mana potion"):
		return _make_potion_icon_texture(Color(0.22, 0.42, 0.95), size)
	if kind == "skill" and lower_name == "heal":
		return _make_heal_icon_texture(size)
	if kind == "skill" and lower_name == "wind strike":
		return _make_wind_strike_icon_texture(size)

	var base_color: Color = SLOT_KIND_COLORS.get(kind, Color(0.5, 0.5, 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ref_name)
	var variance := rng.randf_range(-0.15, 0.15) if not ref_name.is_empty() else 0.0
	var varied_color := Color(
		clampf(base_color.r + variance, 0.0, 1.0),
		clampf(base_color.g + variance, 0.0, 1.0),
		clampf(base_color.b + variance, 0.0, 1.0),
	)

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(varied_color)

	var center := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var shade := 1.0 - clampf(dist / (size * 0.7), 0.0, 1.0) * 0.2
			image.set_pixel(x, y, Color(varied_color.r * shade, varied_color.g * shade, varied_color.b * shade, 1.0))

	var border_color := varied_color.darkened(0.4)
	for x in size:
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, size - 1, border_color)
	for y in size:
		image.set_pixel(0, y, border_color)
		image.set_pixel(size - 1, y, border_color)

	return ImageTexture.create_from_image(image)


## Fond commun aux icônes dédiées ci-dessous : vignette radiale (centre légèrement plus
## clair que les bords) sur `bg_color`, avec le même liseré assombri que le carré
## générique de make_slot_icon_texture, pour rester cohérent avec le reste de la hotbar.
func _fill_icon_background(image: Image, size: int, bg_color: Color) -> void:
	var center := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var shade := 1.0 - clampf(dist / (size * 0.75), 0.0, 1.0) * 0.35
			image.set_pixel(x, y, Color(bg_color.r * shade, bg_color.g * shade, bg_color.b * shade, 1.0))

	var border_color := bg_color.darkened(0.5)
	for x in size:
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, size - 1, border_color)
	for y in size:
		image.set_pixel(0, y, border_color)
		image.set_pixel(size - 1, y, border_color)


## Fiole de potion façon Lineage 1/2 : bouchon, col de verre, corps rond rempli de
## `liquid_color` avec un reflet clair en haut à gauche (verre) — sert aux potions de soin
## (rouge) et de mana (bleu), voir make_slot_icon_texture. Coordonnées normalisées [0,1]
## pour le col/bouchon (proportions stables quelle que soit `size`), distance en pixels
## pour le corps rond (plus simple pour un cercle).
func _make_potion_icon_texture(liquid_color: Color, size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	_fill_icon_background(image, size, Color(0.12, 0.11, 0.13))

	var glass_color := Color(0.78, 0.85, 0.90)
	var cork_color := Color(0.42, 0.28, 0.16)
	var body_center := Vector2(size * 0.5, size * 0.60)
	var body_radius := size * 0.29

	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var nx := p.x / size
			var ny := p.y / size

			if ny >= 0.08 and ny < 0.20 and abs(nx - 0.5) <= 0.10:
				image.set_pixel(x, y, cork_color)
				continue
			if ny >= 0.20 and ny < 0.34 and abs(nx - 0.5) <= 0.085:
				image.set_pixel(x, y, glass_color)
				continue

			var dist_body := p.distance_to(body_center)
			if dist_body <= body_radius:
				if dist_body >= body_radius - 1.4:
					image.set_pixel(x, y, glass_color.darkened(0.2))
					continue
				# Liquide un peu plus sombre vers le bas, reflet clair en haut à gauche
				# (façon verre) — donne du volume à un simple disque plat.
				var shade := 1.0 - (p.y - body_center.y + body_radius) / (body_radius * 2.0) * 0.35
				var highlight_dist := p.distance_to(body_center + Vector2(-body_radius * 0.35, -body_radius * 0.35))
				var highlight := clampf(1.0 - highlight_dist / (body_radius * 0.55), 0.0, 1.0) * 0.5
				image.set_pixel(x, y, Color(
					clampf(liquid_color.r * shade + highlight, 0.0, 1.0),
					clampf(liquid_color.g * shade + highlight, 0.0, 1.0),
					clampf(liquid_color.b * shade + highlight, 0.0, 1.0),
				))

	return ImageTexture.create_from_image(image)


## Croix lumineuse dorée façon icône "Heal" Lineage 1/2 : halo radial chaud vert-doré
## derrière une croix blanc-or à bords nets. Voir make_slot_icon_texture.
func _make_heal_icon_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	_fill_icon_background(image, size, Color(0.09, 0.24, 0.14))

	var center := Vector2(size * 0.5, size * 0.5)
	var glow_color := Color(0.70, 0.90, 0.40)
	var cross_color := Color(1.0, 0.95, 0.68)
	var half_thickness := size * 0.11
	var half_length := size * 0.30

	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p - center
			var dist := d.length()

			var in_cross: bool = (abs(d.x) <= half_thickness and abs(d.y) <= half_length) \
				or (abs(d.y) <= half_thickness and abs(d.x) <= half_length)
			if in_cross:
				image.set_pixel(x, y, cross_color)
				continue

			# Halo radial chaud autour de la croix, qui s'estompe vers le bord — donne
			# l'impression de lumière irradiant plutôt qu'une croix plate sur fond uni.
			var glow: float = clampf(1.0 - dist / (size * 0.5), 0.0, 1.0)
			glow = glow * glow * 0.55
			if glow > 0.02:
				image.set_pixel(x, y, image.get_pixel(x, y).lerp(glow_color, glow))

	return ImageTexture.create_from_image(image)


## Spirale de vent façon icône "Wind Strike" Lineage 1/2 : traînée verte qui s'enroule du
## centre vers l'extérieur, épaissie et éclaircie vers la pointe pour suggérer le
## mouvement/la vitesse. Voir make_slot_icon_texture.
func _make_wind_strike_icon_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	_fill_icon_background(image, size, Color(0.08, 0.14, 0.16))

	var center := Vector2(size * 0.5, size * 0.5)
	var max_radius := size * 0.36
	var turns := 1.35
	var steps := 160
	for i in steps:
		var t := float(i) / float(steps - 1)
		var angle := t * TAU * turns
		var radius := lerpf(size * 0.03, max_radius, t)
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		var brush_radius := lerpf(size * 0.05, size * 0.09, t)
		var brightness := lerpf(0.55, 1.0, t)
		var stroke_color := Color(0.75 * brightness, 1.0 * brightness, 0.78 * brightness)
		_stamp_soft_dot(image, size, point, brush_radius, stroke_color)

	return ImageTexture.create_from_image(image)


## Tamponne un disque plein à `center` — utilisé par _make_wind_strike_icon_texture pour
## composer une traînée continue à partir d'une suite de points discrets le long de la
## spirale, sans laisser de trous entre deux points consécutifs.
func _stamp_soft_dot(image: Image, size: int, center: Vector2, radius: float, color: Color) -> void:
	var min_x := maxi(0, int(center.x - radius - 1))
	var max_x := mini(size - 1, int(center.x + radius + 1))
	var min_y := maxi(0, int(center.y - radius - 1))
	var max_y := mini(size - 1, int(center.y + radius + 1))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


## Couleurs procédurales des icônes de fenêtre HUD ci-dessous (BottomRightIcons) —
## dupliquées depuis UITheme.gd (palette or/ivoire du thème global) plutôt qu'importées :
## UITheme est un autoload Node construit à _ready(), ZoneAssets3D doit pouvoir générer ces
## textures indépendamment de l'ordre d'initialisation des autoloads.
const UI_ICON_GOLD := Color(0.80, 0.64, 0.32)
const UI_ICON_GOLD_BRIGHT := Color(0.95, 0.85, 0.55)
const UI_ICON_IVORY := Color(0.90, 0.86, 0.76)


## Icône procédurale à fond transparent pour les boutons de BottomRightIcons.gd (rangée
## bas-droite façon L2J) : remplace le texte à 2 lettres ("So"/"Sa"/"Pe"/"Éq"/"Op") par un
## pictogramme, demandé explicitement le 2026-09-03 ("plus joli"). Fond transparent
## (contrairement à make_slot_icon_texture, qui peint son propre fond de slot) car ces
## icônes vivent à l'intérieur d'un Button déjà stylé (bordure/fond dorés par UITheme.gd).
## `kind` : "skills" (grimoire), "inventory" (sac), "character" (silhouette), "equipment"
## (bouclier), "options" (engrenage).
func make_ui_icon_texture(kind: String, size: int = 40) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	match kind:
		"skills":
			_draw_skills_icon(image, size)
		"inventory":
			_draw_inventory_icon(image, size)
		"character":
			_draw_character_icon(image, size)
		"equipment":
			_draw_equipment_icon(image, size)
		"options":
			_draw_options_icon(image, size)
	return ImageTexture.create_from_image(image)


## Distance signée à un rectangle centré à l'origine (négative à l'intérieur), coins
## arrondis de rayon `radius` — sert à peindre des rectangles arrondis avec un contour net
## sur 1-2px. Même principe que ROUNDED_BAR_SHADER (Game3D.gd) mais en GDScript CPU pur :
## ces icônes ne sont peintes qu'une fois à la construction, pas par image par frame, un
## shader serait inutile ici.
func _sdf_rounded_box(p: Vector2, half_size: Vector2, radius: float) -> float:
	var q := Vector2(abs(p.x) - half_size.x + radius, abs(p.y) - half_size.y + radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Tamponne une étincelle à 4 branches (deux losanges fins croisés, pointus aux extrémités)
## centrée sur `center` — utilisée par _draw_skills_icon pour évoquer un enchantement.
func _stamp_sparkle(image: Image, size: int, center: Vector2, arm_length: float, arm_half_width: float, color: Color) -> void:
	var min_x := maxi(0, int(center.x - arm_length))
	var max_x := mini(size - 1, int(center.x + arm_length))
	var min_y := maxi(0, int(center.y - arm_length))
	var max_y := mini(size - 1, int(center.y + arm_length))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(x + 0.5, y + 0.5) - center
			var horiz: bool = abs(d.x) <= arm_length and abs(d.y) <= arm_half_width * (1.0 - abs(d.x) / arm_length)
			var vert: bool = abs(d.y) <= arm_length and abs(d.x) <= arm_half_width * (1.0 - abs(d.y) / arm_length)
			if horiz or vert:
				image.set_pixel(x, y, color)


## Grimoire fermé (couverture arrondie couleur cuir, tranche dorée, étincelle sur la
## couverture) pour le bouton "Compétences".
func _draw_skills_icon(image: Image, size: int) -> void:
	var center := Vector2(size * 0.5, size * 0.5)
	var half_size := Vector2(size * 0.30, size * 0.34)
	var radius := size * 0.05
	var cover_color := Color(0.45, 0.16, 0.14)

	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var d := _sdf_rounded_box(p, half_size, radius)
			if d <= 0.0:
				var on_spine: bool = abs(p.x) <= size * 0.025
				image.set_pixel(x, y, UI_ICON_GOLD_BRIGHT if on_spine else cover_color)
			elif d <= 1.4:
				image.set_pixel(x, y, UI_ICON_GOLD)

	_stamp_sparkle(image, size, center + Vector2(0, -size * 0.02), size * 0.16, size * 0.045, UI_ICON_GOLD_BRIGHT)


## Besace (corps arrondi + col resserré fermé par un lien) pour le bouton "Inventaire".
func _draw_inventory_icon(image: Image, size: int) -> void:
	var bag_color := Color(0.52, 0.35, 0.19)
	var tie_color := Color(0.28, 0.18, 0.09)

	var body_center := Vector2(size * 0.5, size * 0.60)
	var body_half := Vector2(size * 0.28, size * 0.24)
	var body_radius := size * 0.16

	var neck_center := Vector2(size * 0.5, size * 0.32)
	var neck_half := Vector2(size * 0.12, size * 0.09)
	var neck_radius := size * 0.05

	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = minf(
				_sdf_rounded_box(p - body_center, body_half, body_radius),
				_sdf_rounded_box(p - neck_center, neck_half, neck_radius),
			)
			if d <= 0.0:
				image.set_pixel(x, y, bag_color)
			elif d <= 1.4:
				image.set_pixel(x, y, bag_color.darkened(0.45))

	# Lien noué à la jonction col/corps — ne peint que par-dessus le sac déjà peint (alpha
	# non nul) pour rester dans sa silhouette sans la recalculer.
	var tie_y := int(size * 0.40)
	var tie_half_height := maxi(1, int(size * 0.02))
	for y in range(maxi(0, tie_y - tie_half_height), mini(size, tie_y + tie_half_height + 1)):
		for x in size:
			if image.get_pixel(x, y).a > 0.0:
				image.set_pixel(x, y, tie_color)


## Silhouette tête + épaules pour le bouton "Fiche de personnage".
func _draw_character_icon(image: Image, size: int) -> void:
	var head_center := Vector2(size * 0.5, size * 0.36)
	var head_radius := size * 0.16
	var shoulders_center := Vector2(size * 0.5, size * 0.86)
	var shoulders_radius := size * 0.34
	var shoulders_cutoff_y := size * 0.72

	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var in_head := p.distance_to(head_center) <= head_radius
			var in_shoulders := p.y <= shoulders_cutoff_y and p.distance_to(shoulders_center) <= shoulders_radius
			if in_head or in_shoulders:
				image.set_pixel(x, y, UI_ICON_IVORY)


## Bouclier héraldique (sommet plat à coins arrondis, effilé jusqu'à une pointe basse) avec
## une ligne dorée centrale façon blason, pour le bouton "Équipement". Le sommet est un
## rectangle arrondi (_sdf_rounded_box) plutôt qu'un dégradé de largeur comme la pointe
## basse : une largeur qui croît de 0 en haut donnait un losange (pointu aux deux bouts,
## corrigé après une première capture d'écran qui le montrait clairement).
func _draw_equipment_icon(image: Image, size: int) -> void:
	var fill_color := Color(0.38, 0.41, 0.45)
	var center_x := size * 0.5
	var top_frac := 0.14
	var shoulder_frac := 0.52
	var tip_frac := 0.90
	var half_width_max := size * 0.30
	var corner_radius := half_width_max * 0.18

	var box_half_height := (shoulder_frac - top_frac) * size * 0.5
	var box_center_y := (top_frac + shoulder_frac) * 0.5 * size

	for y in size:
		var ny := (y + 0.5) / size
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var dx: float = abs(p.x - center_x)
			var d_box := _sdf_rounded_box(Vector2(p.x - center_x, p.y - box_center_y), Vector2(half_width_max, box_half_height), corner_radius)

			var inside: bool = d_box <= 0.0
			var near_edge: bool = d_box > 0.0 and d_box <= 1.4

			if ny > shoulder_frac and ny <= tip_frac:
				var t: float = clampf((ny - shoulder_frac) / (tip_frac - shoulder_frac), 0.0, 1.0)
				var taper_half_width: float = lerpf(half_width_max, 0.0, t)
				if dx <= taper_half_width:
					inside = true
					near_edge = dx >= taper_half_width - 1.6
				elif not inside:
					near_edge = false

			if inside:
				image.set_pixel(x, y, fill_color)
			elif near_edge:
				image.set_pixel(x, y, UI_ICON_GOLD)

	var emblem_top := int(size * top_frac)
	var emblem_bottom := int(size * tip_frac * 0.8)
	for y in range(emblem_top, emblem_bottom):
		for x in range(int(center_x - 1.2), int(center_x + 1.6)):
			if x >= 0 and x < size and image.get_pixel(x, y).a > 0.0:
				image.set_pixel(x, y, UI_ICON_GOLD_BRIGHT)


## Engrenage (disque central + dents radiales, trou au centre) pour le bouton "Options".
func _draw_options_icon(image: Image, size: int) -> void:
	var center := Vector2(size * 0.5, size * 0.5)
	var outer_radius := size * 0.38
	var inner_radius := size * 0.24
	var hole_radius := size * 0.11
	var tooth_count := 8
	var tooth_half_angle := (TAU / tooth_count) * 0.35

	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var dist := p.length()
			if dist > outer_radius or dist < hole_radius:
				continue
			var inside := dist <= inner_radius
			if not inside:
				var slice := TAU / tooth_count
				var local_angle := fposmod(p.angle(), slice) - slice * 0.5
				inside = abs(local_angle) <= tooth_half_angle
			if inside:
				image.set_pixel(x, y, UI_ICON_IVORY)


## Scanne res://scenes/maps/*.tscn une fois au démarrage pour indexer chaque scène par sa
## propriété `map_name` (exportée par MapData.gd sur la racine, voir
## tools/convert_tmx_to_scene.gd) — équivalent du _scan_map_files historique, qui indexait
## les .tmx par leur propriété Tiled "name". Instancie brièvement chaque scène pour lire
## cette propriété puis la libère aussitôt : Game3D ne garde en mémoire que la carte
## réellement affichée (voir Game3D._rebuild_map), pas les sept à la fois.
func _scan_map_scenes() -> void:
	var dir := DirAccess.open(MAP_SCENES_DIR)
	if dir == null:
		push_warning("ZoneAssets3D: dossier introuvable: %s" % MAP_SCENES_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tscn"):
			_index_map_scene(MAP_SCENES_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _index_map_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("ZoneAssets3D: scène illisible: %s" % path)
		return
	var root: Node3D = packed.instantiate()
	var map_name: String = root.map_name
	root.free()
	if map_name.is_empty():
		push_warning("ZoneAssets3D: pas de map_name dans %s" % path)
		return
	_map_scene_path_by_name[map_name] = path
