class_name IconFactory
extends RefCounted
## Icônes procédurales d'objets, de compétences et de l'interface, dans l'esprit des icônes
## Lineage 2 (objet peint, éclairé en haut à gauche, sur fond sombre vignetté teinté par
## catégorie, cerclé d'un biseau) — entièrement dessinées en code par champs de distance
## signée (SDF), sans aucune image externe. Rendu en 64 px puis réduit à l'affichage pour un
## anticrénelage propre ; chaque icône est mise en cache (clé = type + nom + taille).
##
## Le type d'objet (WEAPON/ARMOR/...) ou de compétence (DAMAGE/HEALING/...) détermine le
## pictogramme ; quand l'appelant ne le connaît pas (hotbar, boutique), il est retrouvé par
## nom dans GameState.inventory / GameState.known_skills, sinon deviné d'après le nom.
## Les armes ont un pictogramme par WeaponType serveur (épée, dague, bâton, arc...).

const BASE_SIZE := 64

## app.domain.item.WeaponType côté backend.
const WEAPON_TYPES := ["SWORD", "BIG_SWORD", "DAGGER", "BLUNT", "BIG_BLUNT", "AXE", "POLE", "STAFF", "WAND", "BOW"]
## Repli par mots-clés (nom d'objet en minuscules, testés dans l'ordre) pour une arme dont
## le `weaponType` est inconnu (boutique, hotbar, backend antérieur à ce champ).
const WEAPON_KEYWORDS := [
	["bow", "BOW"], ["dagger", "DAGGER"], ["knife", "DAGGER"],
	["staff", "STAFF"], ["wand", "WAND"], ["rod", "WAND"], ["scepter", "WAND"],
	["spear", "POLE"], ["lance", "POLE"], ["halberd", "POLE"], ["glaive", "POLE"],
	["hammer", "BIG_BLUNT"], ["club", "BLUNT"], ["mace", "BLUNT"],
	["axe", "AXE"],
	["bastard", "BIG_SWORD"], ["great", "BIG_SWORD"], ["claymore", "BIG_SWORD"],
	["two-hand", "BIG_SWORD"], ["tsurugi", "BIG_SWORD"],
]

static var _cache: Dictionary = {}


## `kind` : "attack", "skill" ou "item". `hint` : ItemType ou skillType backend (facultatif) ;
## pour une arme, un WeaponType est plus précis que "WEAPON" (sinon il est déduit du nom).
static func slot_icon(kind: String, ref_name: String, hint: String = "", size: int = BASE_SIZE) -> Texture2D:
	if hint.is_empty():
		hint = _resolve_hint(kind, ref_name)
	if kind == "item" and hint == "WEAPON":
		hint = _weapon_type_of(ref_name)
	var key := "%s|%s|%s|%d" % [kind, ref_name, hint, size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(BASE_SIZE, BASE_SIZE, false, Image.FORMAT_RGBA8)
	_paint_slot(img, kind, ref_name, hint)
	if size != BASE_SIZE:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Pictogrammes des boutons de menu (fond transparent) : "character", "inventory",
## "skills", "options", "coin", "map", "crown".
static func ui_icon(kind: String, size: int = 32) -> Texture2D:
	var key := "ui|%s|%d" % [kind, size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(BASE_SIZE, BASE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"character":
			_ui_character(img)
		"inventory":
			_ui_bag(img)
		"skills":
			_ui_book(img)
		"options":
			_ui_gear(img)
		"coin":
			_ui_coin(img)
		"map":
			_ui_map(img)
		"crown":
			_ui_crown(img)
	if size != BASE_SIZE:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Icône d'une entrée Inventory/EquipmentView ({name, type, weaponType, ...}).
static func item_icon(item: Dictionary, size: int = BASE_SIZE) -> Texture2D:
	return slot_icon("item", str(item.get("name", "")), _item_hint(item), size)


## Matériau posé sur l'icône d'un soulshot/spiritshot armé en auto-use (hotbar et
## inventaire) : icône brillante animée, doré pour le soulshot, cyan pour le spiritshot
## (mêmes teintes que la lueur d'arme de Game3D). Partagé entre toutes les icônes.
static func active_shot_material(item_type: String) -> ShaderMaterial:
	var key := "shot_material|%s" % item_type
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = preload("res://scenes/game/hud/shot_active.gdshader")
	var color := Color(0.45, 0.85, 1.0) if item_type == "SPIRITSHOT" else Color(1.0, 0.72, 0.28)
	material.set_shader_parameter("glow_color", color)
	_cache[key] = material
	return material


static func _item_hint(item: Dictionary) -> String:
	var type_key := str(item.get("type", ""))
	var weapon_type := str(item.get("weaponType", "")).to_upper()
	if weapon_type in WEAPON_TYPES and type_key in ["WEAPON", ""]:
		return weapon_type
	return type_key


static func _resolve_hint(kind: String, ref_name: String) -> String:
	if kind == "item":
		for item in GameState.inventory.get("items", []):
			if str(item.get("name", "")) == ref_name:
				return _item_hint(item)
		return guess_item_type(ref_name)
	if kind == "skill":
		for skill in GameState.known_skills.get("skills", []):
			if str(skill.get("name", "")) == ref_name:
				return str(skill.get("skillType", ""))
	return ""


## Repli quand l'objet n'est pas (ou plus) dans l'inventaire : quelques mots-clés courants.
static func guess_item_type(ref_name: String) -> String:
	var n := ref_name.to_lower()
	var table := {
		"potion": "POTION", "elixir": "POTION", "soulshot": "SOULSHOT", "spiritshot": "SPIRITSHOT",
		"scroll": "SCROLL", "parchemin": "SCROLL",
		"sword": "WEAPON", "blade": "WEAPON", "saber": "WEAPON", "épée": "WEAPON",
		"helmet": "HELMET", "helm": "HELMET", "cap": "HELMET", "casque": "HELMET",
		"boots": "BOOTS", "shoes": "BOOTS", "bottes": "BOOTS", "gloves": "GLOVES", "gauntlets": "GLOVES",
		"shield": "SHIELD", "bouclier": "SHIELD", "ring": "RING", "anneau": "RING",
		"necklace": "NECKLACE", "collier": "NECKLACE", "earring": "EARRING",
		"pants": "PANTS", "stockings": "PANTS", "gaiters": "PANTS", "tunic": "ARMOR", "armor": "ARMOR",
		"mail": "ARMOR", "robe": "ARMOR", "shirt": "ARMOR", "key": "KEY", "clé": "KEY",
	}
	for word in table.keys():
		if n.contains(word):
			return table[word]
	for entry in WEAPON_KEYWORDS:
		if n.contains(entry[0]):
			return "WEAPON"
	return "MISC"


## WeaponType deviné d'après le nom ("SWORD" par défaut).
static func guess_weapon_type(ref_name: String) -> String:
	var n := ref_name.to_lower()
	for entry in WEAPON_KEYWORDS:
		if n.contains(entry[0]):
			return entry[1]
	return "SWORD"


## WeaponType de l'objet `ref_name` s'il est dans l'inventaire, sinon deviné.
static func _weapon_type_of(ref_name: String) -> String:
	for item in GameState.inventory.get("items", []):
		if str(item.get("name", "")) == ref_name:
			var weapon_type := str(item.get("weaponType", "")).to_upper()
			if weapon_type in WEAPON_TYPES:
				return weapon_type
	return guess_weapon_type(ref_name)


# ---------------------------------------------------------------------------
# Composition des icônes de slot
# ---------------------------------------------------------------------------

static func _paint_slot(img: Image, kind: String, ref_name: String, hint: String) -> void:
	var lower := ref_name.to_lower()
	if kind == "attack":
		_background(img, Color(0.30, 0.08, 0.06))
		_crossed_swords(img)
	elif kind == "skill":
		_paint_skill(img, lower, hint, ref_name)
	else:
		_paint_item(img, lower, hint, ref_name)
	_bevel(img)


static func _paint_skill(img: Image, lower: String, hint: String, ref_name: String) -> void:
	if lower == "wind strike":
		_background(img, Color(0.06, 0.20, 0.18))
		_wind_spiral(img)
		return
	match hint:
		"HEALING":
			_background(img, Color(0.08, 0.24, 0.12))
			_holy_cross(img)
		"BUFF":
			_background(img, Color(0.08, 0.14, 0.32))
			_buff_arrow(img)
		"DEBUFF":
			_background(img, Color(0.20, 0.06, 0.24))
			_debuff_arrow(img)
		_:
			var palette := [
				[Color(0.34, 0.10, 0.03), Color(1.0, 0.55, 0.15), Color(1.0, 0.92, 0.55)],
				[Color(0.06, 0.12, 0.30), Color(0.45, 0.70, 1.0), Color(0.90, 0.97, 1.0)],
				[Color(0.20, 0.07, 0.30), Color(0.78, 0.45, 1.0), Color(0.98, 0.88, 1.0)],
				[Color(0.25, 0.20, 0.03), Color(1.0, 0.85, 0.25), Color(1.0, 1.0, 0.80)],
			]
			var colors: Array = palette[absi(hash(ref_name)) % palette.size()]
			_background(img, colors[0])
			_burst(img, colors[1], colors[2], absi(hash(ref_name + "#")) % 3 + 7)


static func _paint_item(img: Image, lower: String, hint: String, ref_name: String) -> void:
	if hint in WEAPON_TYPES or hint == "WEAPON":
		_paint_weapon(img, hint)
		return
	match hint:
		"HELMET":
			_background(img, Color(0.17, 0.13, 0.10))
			_helmet(img)
		"ARMOR":
			_background(img, Color(0.17, 0.13, 0.10))
			_armor(img)
		"PANTS":
			_background(img, Color(0.15, 0.13, 0.11))
			_pants(img)
		"BOOTS":
			_background(img, Color(0.16, 0.12, 0.09))
			_boots(img)
		"GLOVES":
			_background(img, Color(0.16, 0.12, 0.09))
			_gloves(img)
		"SHIELD":
			_background(img, Color(0.12, 0.13, 0.17))
			_shield(img)
		"NECKLACE":
			_background(img, Color(0.16, 0.08, 0.20))
			_necklace(img, _gem_color(ref_name))
		"EARRING":
			_background(img, Color(0.16, 0.08, 0.20))
			_earring(img, _gem_color(ref_name))
		"RING":
			_background(img, Color(0.16, 0.08, 0.20))
			_ring(img, _gem_color(ref_name))
		"POTION":
			var liquid := Color(0.30, 0.80, 0.35)
			if lower.contains("heal") or lower.contains("soin") or lower.contains("vie"):
				liquid = Color(0.88, 0.12, 0.14)
			elif lower.contains("mana"):
				liquid = Color(0.22, 0.45, 1.0)
			_background(img, liquid.darkened(0.78))
			_potion(img, liquid)
		"SOULSHOT":
			_background(img, Color(0.22, 0.10, 0.03))
			_shots(img, Color(1.0, 0.60, 0.15), Color(1.0, 0.95, 0.65))
		"SPIRITSHOT":
			_background(img, Color(0.04, 0.12, 0.25))
			_shots(img, Color(0.30, 0.75, 1.0), Color(0.88, 1.0, 1.0))
		"SCROLL":
			_background(img, Color(0.10, 0.12, 0.18))
			_scroll(img)
		"KEY":
			_background(img, Color(0.15, 0.13, 0.08))
			_key(img)
		"TOOL":
			_background(img, Color(0.13, 0.13, 0.13))
			_hammer(img)
		_:
			_background(img, Color(0.14, 0.12, 0.10))
			_pouch(img)


## Fond teinté par famille : acier bleuté (mêlée), vert (arc), violet (armes de mage).
static func _paint_weapon(img: Image, weapon_type: String) -> void:
	match weapon_type:
		"STAFF", "WAND":
			_background(img, Color(0.15, 0.09, 0.22))
		"BOW":
			_background(img, Color(0.10, 0.15, 0.09))
		_:
			_background(img, Color(0.12, 0.14, 0.19))
	match weapon_type:
		"BIG_SWORD":
			_greatsword(img)
		"DAGGER":
			_dagger(img)
		"BLUNT":
			_mace(img)
		"BIG_BLUNT":
			_warhammer(img)
		"AXE":
			_axe(img)
		"POLE":
			_spear(img)
		"STAFF":
			_staff(img)
		"WAND":
			_wand(img)
		"BOW":
			_bow(img)
		_:
			_sword(img, Vector2(0.37, 0.63), -PI / 4.0, 1.0)


static func _gem_color(ref_name: String) -> Color:
	var gems := [Color(0.95, 0.15, 0.20), Color(0.20, 0.50, 1.0), Color(0.20, 0.85, 0.40), Color(0.75, 0.30, 1.0), Color(1.0, 0.80, 0.20)]
	return gems[absi(hash(ref_name)) % gems.size()]


# ---------------------------------------------------------------------------
# Moteur de peinture : SDF + ombrage + contour, composés "par-dessus" l'image
# ---------------------------------------------------------------------------

## Peint la forme `sdf` (distance signée en pixels, <0 à l'intérieur) ombrée par `shade`
## (Callable(p: Vector2 normalisé 0..1, d: float) -> Color), avec un contour sombre de
## `outline` px et un reflet clair le long du bord intérieur éclairé.
static func _draw(img: Image, sdf: Callable, shade: Callable, outline: float = 1.6) -> void:
	var s := float(BASE_SIZE)
	for y in BASE_SIZE:
		for x in BASE_SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = sdf.call(p)
			if d > outline + 1.0:
				continue
			var col: Color
			if d > 0.0:
				var a := clampf(outline + 0.5 - d, 0.0, 1.0) * 0.85
				col = Color(0, 0, 0, a)
			else:
				col = shade.call(p / s, d)
				var edge := clampf(0.5 - d, 0.0, 1.0)
				col.a *= edge
			_blend(img, x, y, col)


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if c.a <= 0.0:
		return
	var dst := img.get_pixel(x, y)
	var a := c.a + dst.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var r := (c.r * c.a + dst.r * dst.a * (1.0 - c.a)) / a
	var g := (c.g * c.a + dst.g * dst.a * (1.0 - c.a)) / a
	var b := (c.b * c.a + dst.b * dst.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(r, g, b, a))


## Halo lumineux additif (reflet magique, lueur de gemme).
static func _glow(img: Image, center: Vector2, radius: float, color: Color, intensity: float) -> void:
	var c := center * BASE_SIZE
	var r := radius * BASE_SIZE
	for y in BASE_SIZE:
		for x in BASE_SIZE:
			var t := 1.0 - Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if t <= 0.0:
				continue
			var k := t * t * intensity
			var dst := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				minf(dst.r + color.r * k, 1.0), minf(dst.g + color.g * k, 1.0),
				minf(dst.b + color.b * k, 1.0), maxf(dst.a, minf(k, 1.0))
			))


## Ombrage "métal/cuir" : dégradé selon la direction de la lumière (haut-gauche) entre
## `dark` et `light`, avec un reflet spéculaire en bande.
static func _lit_shade(light: Color, dark: Color, spec: float = 0.35) -> Callable:
	return func(p: Vector2, _d: float) -> Color:
		var t := clampf((p.x + p.y) * 0.75 - 0.25, 0.0, 1.0)
		var c := light.lerp(dark, t)
		var band := exp(-pow((p.x + p.y - 0.78) * 7.0, 2.0)) * spec
		return c.lerp(Color.WHITE, band)


static func _flat(color: Color) -> Callable:
	return func(_p: Vector2, _d: float) -> Color:
		return color


## Fond de slot : dégradé radial teinté, plus sombre sur les bords.
static func _background(img: Image, tint: Color) -> void:
	var c := Vector2(0.42, 0.38) * BASE_SIZE
	for y in BASE_SIZE:
		for x in BASE_SIZE:
			var t := clampf(Vector2(x + 0.5, y + 0.5).distance_to(c) / (BASE_SIZE * 0.78), 0.0, 1.0)
			var col := tint.lightened(0.10).lerp(Color(0.01, 0.01, 0.015), t * t * 0.9 + t * 0.1)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))


## Biseau : filet noir extérieur, lumière en haut à gauche, ombre en bas à droite.
static func _bevel(img: Image) -> void:
	var n := BASE_SIZE
	for i in n:
		for edge in [Vector2i(i, 0), Vector2i(0, i), Vector2i(i, n - 1), Vector2i(n - 1, i)]:
			img.set_pixel(edge.x, edge.y, Color(0, 0, 0, 1))
	for i in range(1, n - 1):
		_blend(img, i, 1, Color(1, 1, 1, 0.28))
		_blend(img, 1, i, Color(1, 1, 1, 0.20))
		_blend(img, i, n - 2, Color(0, 0, 0, 0.55))
		_blend(img, n - 2, i, Color(0, 0, 0, 0.55))


# --- Primitives SDF (coordonnées en pixels) ----------------------------------

static func _px(v: Vector2) -> Vector2:
	return v * BASE_SIZE


static func _sd_circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(_px(c)) - r * BASE_SIZE


static func _sd_capsule(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := p - _px(a)
	var ba := _px(b) - _px(a)
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - r * BASE_SIZE


static func _sd_box(p: Vector2, c: Vector2, half: Vector2, angle: float = 0.0, radius: float = 0.0) -> float:
	var q := (p - _px(c)).rotated(-angle)
	var hs := half * BASE_SIZE
	var rr := radius * BASE_SIZE
	var d := Vector2(absf(q.x), absf(q.y)) - hs + Vector2(rr, rr)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - rr


## SDF d'un polygone (points normalisés), d'après I. Quilez.
static func _sd_poly(p: Vector2, pts: Array) -> float:
	var n := pts.size()
	var v0: Vector2 = _px(pts[0])
	var d := (p - v0).dot(p - v0)
	var s := 1.0
	var j := n - 1
	for i in n:
		var vi: Vector2 = _px(pts[i])
		var vj: Vector2 = _px(pts[j])
		var e := vj - vi
		var w := p - vi
		var b := w - e * clampf(w.dot(e) / e.dot(e), 0.0, 1.0)
		d = minf(d, b.dot(b))
		var c1 := p.y >= vi.y
		var c2 := p.y < vj.y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
		j = i
	return s * sqrt(d)


## Transforme des points exprimés dans un repère local (origine, angle, échelle).
static func _xf(pts: Array, origin: Vector2, angle: float, scale: float) -> Array:
	var out := []
	for pt in pts:
		out.append(origin + (pt as Vector2).rotated(angle) * scale)
	return out


# --- Objets --------------------------------------------------------------------

const STEEL_LIGHT := Color(0.92, 0.94, 0.97)
const STEEL_DARK := Color(0.36, 0.40, 0.48)
const GOLD_LIGHT := Color(1.0, 0.88, 0.50)
const GOLD_DARK := Color(0.45, 0.28, 0.06)
const LEATHER_LIGHT := Color(0.62, 0.42, 0.24)
const LEATHER_DARK := Color(0.22, 0.12, 0.05)
const WOOD_LIGHT := Color(0.72, 0.52, 0.30)
const WOOD_DARK := Color(0.24, 0.13, 0.05)

## Axe des armes : du bas-gauche (poignée) vers le haut-droit (pointe), et sa perpendiculaire
## (vers le bas-droit ; son opposé pointe vers la lumière).
const AXIS := Vector2(0.7071, -0.7071)
const ACROSS := Vector2(0.7071, 0.7071)


## Lame droite à arête centrale, garde, poignée cuir et pommeau ; `blade_len` (partie
## parallèle), `half_w`, `tip` (longueur de la pointe), `grip_len` et `guard_half` en
## unités locales, multipliées par `scale`. Les défauts donnent l'épée à une main.
static func _sword(img: Image, origin: Vector2, angle: float, scale: float, blade_len: float = 0.46,
		half_w: float = 0.05, tip: float = 0.10, grip_len: float = 0.15, guard_half: float = 0.17) -> void:
	var blade := _xf([Vector2(0.0, -half_w), Vector2(blade_len, -half_w), Vector2(blade_len + tip, 0.0), Vector2(blade_len, half_w), Vector2(0.0, half_w)], origin, angle, scale)
	var axis_dir := Vector2.RIGHT.rotated(angle)
	var perp := Vector2.DOWN.rotated(angle)
	# Lame : deux pans (arête centrale), le pan éclairé plus clair.
	_draw(img, func(p): return _sd_poly(p, blade), func(q: Vector2, _d: float) -> Color:
		var side := (q - origin).dot(perp)
		var along := clampf((q - origin).dot(axis_dir) / ((blade_len + tip) * scale), 0.0, 1.0)
		var c := STEEL_LIGHT if side < 0.0 else STEEL_DARK.lerp(STEEL_LIGHT, 0.35)
		return c.lerp(Color(0.75, 0.80, 0.90), along * 0.3))
	var guard_c := origin + axis_dir * -0.01 * scale
	_draw(img, func(p): return _sd_box(p, guard_c, Vector2(0.035, guard_half) * scale, angle, 0.015), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	_grip(img, origin + axis_dir * -0.05 * scale, origin + axis_dir * -(0.05 + grip_len) * scale, 0.032 * scale)
	var pommel := origin + axis_dir * -(0.09 + grip_len) * scale
	_draw(img, func(p): return _sd_circle(p, pommel, 0.05 * scale), _lit_shade(GOLD_LIGHT, GOLD_DARK))


static func _crossed_swords(img: Image) -> void:
	_sword(img, Vector2(0.34, 0.66), -PI / 4.0, 0.85)
	_sword(img, Vector2(0.66, 0.66), -3.0 * PI / 4.0, 0.85)


## Ombrage cylindrique d'une hampe a -> b de rayon `r` (normalisés) : clair du côté haut-gauche,
## reflet en bande le long de l'axe.
static func _cyl_shade(a: Vector2, b: Vector2, r: float, light: Color, dark: Color, spec: float = 0.3) -> Callable:
	return func(q: Vector2, _d: float) -> Color:
		var ba := b - a
		var h := clampf((q - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
		var lit := clampf((q - (a + ba * h)).dot(-ACROSS) / r, -1.0, 1.0)
		var c := dark.lerp(light, lit * 0.5 + 0.5)
		return c.lerp(Color.WHITE, exp(-pow((lit - 0.5) * 3.0, 2.0)) * spec)


## Ombrage sphérique : point chaud en haut à gauche.
static func _sphere_shade(c: Vector2, r: float, light: Color, dark: Color) -> Callable:
	return func(q: Vector2, _d: float) -> Color:
		var t := clampf(q.distance_to(c + Vector2(-0.38, -0.42) * r) / (r * 1.5), 0.0, 1.0)
		return light.lerp(dark, t)


## Hampe en bois a -> b.
static func _shaft(img: Image, a: Vector2, b: Vector2, r: float) -> void:
	_draw(img, func(p): return _sd_capsule(p, a, b, r), _cyl_shade(a, b, r, WOOD_LIGHT, WOOD_DARK, 0.2))


## Poignée tressée de cuir a -> b.
static func _grip(img: Image, a: Vector2, b: Vector2, r: float) -> void:
	var dir := (b - a).normalized()
	_draw(img, func(p): return _sd_capsule(p, a, b, r), func(q: Vector2, _d: float) -> Color:
		var k := sin((q - a).dot(dir) * 140.0)
		return LEATHER_LIGHT.lerp(LEATHER_DARK, 0.5 + k * 0.3))


## Bague dorée perpendiculaire à l'axe, centrée en `c`.
static func _collar(img: Image, c: Vector2, half_len: float, half_w: float) -> void:
	_draw(img, func(p): return _sd_box(p, c, Vector2(half_len, half_w), -PI / 4.0, 0.008), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


## Espadon : lame plus large et plus longue, longue fusée, large garde, gorge centrale.
static func _greatsword(img: Image) -> void:
	var origin := Vector2(0.33, 0.67)
	var scale := 1.0
	_sword(img, origin, -PI / 4.0, scale, 0.53, 0.085, 0.10, 0.20, 0.25)
	_draw(img, func(p): return _sd_capsule(p, origin + AXIS * 0.07 * scale, origin + AXIS * 0.48 * scale, 0.014 * scale),
		_flat(Color(0.20, 0.23, 0.31, 0.95)), 0.0)


## Dague : lame courte et large à longue pointe effilée, petite garde.
static func _dagger(img: Image) -> void:
	_sword(img, Vector2(0.42, 0.58), -PI / 4.0, 1.15, 0.13, 0.058, 0.21, 0.12, 0.13)


## Masse d'armes : manche de bois, tête sphérique à ailettes.
static func _mace(img: Image) -> void:
	var a := Vector2(0.24, 0.80)
	var head := Vector2(0.65, 0.39)
	_shaft(img, a, head, 0.032)
	_grip(img, a.lerp(head, 0.06), a.lerp(head, 0.42), 0.038)
	_draw(img, func(p): return _sd_circle(p, a, 0.045), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	_collar(img, head - AXIS * 0.15, 0.028, 0.055)
	var flanges := []
	for i in 16:
		var ang := TAU * i / 16.0 - PI / 4.0
		flanges.append(head + Vector2(cos(ang), sin(ang)) * (0.19 if i % 2 == 0 else 0.125))
	_draw(img, func(p): return _sd_poly(p, flanges) - 0.8, _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.45))
	_draw(img, func(p): return _sd_circle(p, head, 0.10), _sphere_shade(head, 0.10, STEEL_LIGHT, STEEL_DARK), 1.0)


## Marteau de guerre : long manche, tête massive à deux faces, pointe sommitale.
static func _warhammer(img: Image) -> void:
	var a := Vector2(0.18, 0.84)
	var head := Vector2(0.64, 0.38)
	_shaft(img, a, head, 0.032)
	_grip(img, a.lerp(head, 0.05), a.lerp(head, 0.36), 0.038)
	_draw(img, func(p): return _sd_circle(p, a, 0.045), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	var spike := _xf([Vector2(0.06, -0.045), Vector2(0.20, 0.0), Vector2(0.06, 0.045)], head, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, spike), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4))
	_draw(img, func(p): return _sd_box(p, head, Vector2(0.085, 0.19), -PI / 4.0, 0.02), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.45))
	for side in [-1.0, 1.0]:
		var face: Vector2 = head + ACROSS * 0.19 * side
		_draw(img, func(p): return _sd_box(p, face, Vector2(0.105, 0.035), -PI / 4.0, 0.01), _lit_shade(STEEL_LIGHT.darkened(0.1), STEEL_DARK.darkened(0.2), 0.3), 1.2)
	_collar(img, head, 0.09, 0.035)


## Hache de bataille : manche de bois, fer en croissant côté lumière, ergot au dos.
static func _axe(img: Image) -> void:
	var a := Vector2(0.24, 0.80)
	var top := Vector2(0.67, 0.37)
	var o := Vector2(0.60, 0.44)
	_shaft(img, a, top, 0.032)
	_grip(img, a.lerp(top, 0.05), a.lerp(top, 0.38), 0.038)
	var blade := _xf([Vector2(0.06, -0.02), Vector2(0.12, -0.11), Vector2(0.19, -0.21), Vector2(0.10, -0.265),
		Vector2(0.0, -0.28), Vector2(-0.10, -0.265), Vector2(-0.19, -0.21), Vector2(-0.12, -0.11), Vector2(-0.06, -0.02)], o, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, blade), func(q: Vector2, d: float) -> Color:
		var e := clampf((q - o).dot(-ACROSS) / 0.28, 0.0, 1.0)
		if e > 0.72 and d > -2.2:
			return STEEL_LIGHT.lerp(Color.WHITE, 0.5)
		return STEEL_DARK.lerp(STEEL_LIGHT, 0.25 + e * 0.6))
	var spur := _xf([Vector2(0.05, 0.02), Vector2(0.0, 0.14), Vector2(-0.05, 0.02)], o, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, spur), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.3))
	_collar(img, o, 0.075, 0.045)


## Lance : longue hampe, fer en feuille à nervure, douille dorée et houppe rouge.
static func _spear(img: Image) -> void:
	var a := Vector2(0.12, 0.88)
	var o := Vector2(0.66, 0.34)
	_shaft(img, a, o, 0.026)
	_draw(img, func(p): return _sd_circle(p, a, 0.032), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	var knot := o - AXIS * 0.06
	for dx in [-0.03, 0.0, 0.03]:
		var end: Vector2 = knot + Vector2(dx, 0.15)
		_draw(img, func(p): return _sd_capsule(p, knot, end, 0.016), _lit_shade(Color(0.95, 0.28, 0.20), Color(0.42, 0.04, 0.04), 0.2), 1.0)
	var head := _xf([Vector2(0.0, -0.03), Vector2(0.07, -0.07), Vector2(0.25, 0.0), Vector2(0.07, 0.07), Vector2(0.0, 0.03)], o, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, head), func(q: Vector2, _d: float) -> Color:
		return STEEL_LIGHT if (q - o).dot(ACROSS) < 0.0 else STEEL_DARK.lerp(STEEL_LIGHT, 0.35))
	_draw(img, func(p): return _sd_capsule(p, o - AXIS * 0.08, o + AXIS * 0.01, 0.034), _cyl_shade(o - AXIS * 0.08, o + AXIS * 0.01, 0.034, GOLD_LIGHT, GOLD_DARK, 0.4), 1.2)


## Bâton de mage : long bois noueux, orbe lumineux tenu par une griffe dorée.
static func _staff(img: Image) -> void:
	var a := Vector2(0.16, 0.86)
	var b := Vector2(0.60, 0.42)
	var orb := Vector2(0.69, 0.33)
	_glow(img, orb, 0.34, Color(0.35, 0.60, 1.0), 0.75)
	var ba_px := _px(b) - _px(a)
	_draw(img, func(p):
		var h := clampf((p - _px(a)).dot(ba_px) / ba_px.dot(ba_px), 0.0, 1.0)
		var r := (0.030 + 0.007 * sin(h * 19.0)) * BASE_SIZE
		return (p - _px(a) - ba_px * h).length() - r, _cyl_shade(a, b, 0.036, WOOD_LIGHT, WOOD_DARK, 0.2))
	_collar(img, b, 0.03, 0.05)
	_draw(img, func(p): return _sd_circle(p, orb, 0.105), _sphere_shade(orb, 0.105, Color(0.88, 0.98, 1.0), Color(0.10, 0.22, 0.72)), 1.2)
	_draw(img, func(p): return maxf(absf(_sd_circle(p, orb, 0.135)) - 0.022 * BASE_SIZE, (p - _px(orb)).dot(AXIS) - 0.03 * BASE_SIZE),
		_lit_shade(GOLD_LIGHT, GOLD_DARK), 1.2)
	for side in [-1.0, 1.0]:
		var root: Vector2 = orb + ACROSS * 0.135 * side + AXIS * 0.02
		var tip: Vector2 = orb + ACROSS * 0.095 * side + AXIS * 0.10
		_draw(img, func(p): return _sd_capsule(p, root, tip, 0.018), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_draw(img, func(p): return _sd_circle(p, orb + Vector2(-0.035, -0.04), 0.022), _flat(Color(1, 1, 1, 0.85)), 0.0)


## Baguette : court manche d'ébène cerclé d'or, gemme dans une coupelle, éclat magique.
static func _wand(img: Image) -> void:
	var a := Vector2(0.30, 0.74)
	var b := Vector2(0.56, 0.48)
	var gem_c := b + AXIS * 0.12
	_glow(img, gem_c, 0.30, Color(1.0, 0.45, 0.20), 0.6)
	_draw(img, func(p): return _sd_capsule(p, a, b, 0.024), _cyl_shade(a, b, 0.024, Color(0.48, 0.32, 0.26), Color(0.10, 0.05, 0.04), 0.3))
	for t in [0.30, 0.65]:
		_collar(img, a.lerp(b, t), 0.012, 0.032)
	_draw(img, func(p): return _sd_circle(p, a, 0.035), _lit_shade(GOLD_LIGHT, GOLD_DARK))
	var cup := _xf([Vector2(-0.02, -0.03), Vector2(0.07, -0.085), Vector2(0.04, 0.0), Vector2(0.07, 0.085), Vector2(-0.02, 0.03)], b, -PI / 4.0, 1.0)
	_draw(img, func(p): return _sd_poly(p, cup), _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.4))
	_gem(img, gem_c, 0.12, Color(1.0, 0.35, 0.18))
	var star := []
	for i in 8:
		var ang := TAU * i / 8.0
		star.append(gem_c + Vector2(0.075, -0.085) + Vector2(cos(ang), sin(ang)) * (0.075 if i % 2 == 0 else 0.016))
	_draw(img, func(p): return _sd_poly(p, star), _flat(Color(1.0, 0.97, 0.85)), 0.0)


## Arc bandé : branches en arc de cercle, poignée cuir, corde tirée et flèche encochée.
static func _bow(img: Image) -> void:
	var m := Vector2(0.46, 0.54)
	var half := 0.40
	var sag := 0.20
	var radius := (half * half + sag * sag) / (2.0 * sag)
	var center := m + AXIS * (sag - radius)
	var p1 := m - ACROSS * half
	var p2 := m + ACROSS * half
	var apex := m + AXIS * sag
	_draw(img, func(p):
		var rel: Vector2 = p - _px(m)
		var k := clampf(rel.dot(AXIS) / (sag * BASE_SIZE), 0.0, 1.0)
		var ring := absf(p.distance_to(_px(center)) - radius * BASE_SIZE) - lerpf(0.022, 0.036, k) * BASE_SIZE
		return maxf(ring, -rel.dot(AXIS) - 0.5), _lit_shade(WOOD_LIGHT, WOOD_DARK, 0.3))
	_draw(img, func(p): return _sd_box(p, apex, Vector2(0.075, 0.044), PI / 4.0, 0.012), func(q: Vector2, _d: float) -> Color:
		var k := sin((q - apex).dot(ACROSS) * 140.0)
		return LEATHER_LIGHT.lerp(LEATHER_DARK, 0.5 + k * 0.3), 1.2)
	for tip_pt in [p1, p2]:
		var nock: Vector2 = tip_pt
		_draw(img, func(p): return _sd_circle(p, nock, 0.03), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.2)
	var drawn := m - AXIS * 0.10
	var string_col := _flat(Color(0.93, 0.91, 0.82))
	_draw(img, func(p): return minf(_sd_capsule(p, p1, drawn, 0.007), _sd_capsule(p, drawn, p2, 0.007)), string_col, 0.8)
	var tail := m - AXIS * 0.12
	var base := m + AXIS * 0.36
	_draw(img, func(p): return _sd_capsule(p, tail, base, 0.012), _lit_shade(Color(0.90, 0.78, 0.55), Color(0.45, 0.30, 0.14)), 1.0)
	for side in [-1.0, 1.0]:
		var s: float = side
		var feather := [tail + AXIS * 0.01, tail + AXIS * 0.11, tail + AXIS * 0.08 + ACROSS * 0.05 * s, tail - AXIS * 0.02 + ACROSS * 0.05 * s]
		_draw(img, func(p): return _sd_poly(p, feather), _lit_shade(Color(0.95, 0.35, 0.25), Color(0.45, 0.06, 0.05), 0.2), 1.0)
	var head := [base - ACROSS * 0.048, m + AXIS * 0.48, base + ACROSS * 0.048, base + AXIS * 0.02]
	_draw(img, func(p): return _sd_poly(p, head), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.2)


static func _helmet(img: Image) -> void:
	var dome := func(p): return maxf(_sd_circle(p, Vector2(0.5, 0.52), 0.30), p.y - 0.64 * BASE_SIZE)
	var cheeks := [Vector2(0.20, 0.50), Vector2(0.80, 0.50), Vector2(0.76, 0.80), Vector2(0.60, 0.82), Vector2(0.57, 0.62), Vector2(0.43, 0.62), Vector2(0.40, 0.82), Vector2(0.24, 0.80)]
	_draw(img, func(p): return minf(dome.call(p), _sd_poly(p, cheeks)), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.5))
	# Fente de visière et crête.
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.52), Vector2(0.20, 0.028), 0.0, 0.01), _flat(Color(0.03, 0.03, 0.04)), 0.8)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.33), Vector2(0.025, 0.12), 0.0, 0.02), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _armor(img: Image) -> void:
	var body := [Vector2(0.30, 0.20), Vector2(0.42, 0.17), Vector2(0.50, 0.28), Vector2(0.58, 0.17), Vector2(0.70, 0.20), Vector2(0.84, 0.40), Vector2(0.73, 0.47), Vector2(0.71, 0.84), Vector2(0.29, 0.84), Vector2(0.27, 0.47), Vector2(0.16, 0.40)]
	_draw(img, func(p): return _sd_poly(p, body), _lit_shade(Color(0.70, 0.55, 0.36), Color(0.26, 0.16, 0.08), 0.25))
	# Plastron central et ceinture dorés.
	_draw(img, func(p): return _sd_poly(p, [Vector2(0.40, 0.30), Vector2(0.50, 0.40), Vector2(0.60, 0.30), Vector2(0.62, 0.62), Vector2(0.38, 0.62)]), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.68), Vector2(0.21, 0.035)), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _pants(img: Image) -> void:
	var legs := [Vector2(0.30, 0.22), Vector2(0.70, 0.22), Vector2(0.75, 0.85), Vector2(0.56, 0.85), Vector2(0.50, 0.44), Vector2(0.44, 0.85), Vector2(0.25, 0.85)]
	_draw(img, func(p): return _sd_poly(p, legs), _lit_shade(Color(0.60, 0.50, 0.40), Color(0.20, 0.15, 0.10), 0.2))
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.25), Vector2(0.21, 0.04)), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _boots(img: Image) -> void:
	var boot := [Vector2(0.32, 0.18), Vector2(0.58, 0.18), Vector2(0.60, 0.60), Vector2(0.80, 0.68), Vector2(0.84, 0.84), Vector2(0.28, 0.84), Vector2(0.30, 0.60)]
	_draw(img, func(p): return _sd_poly(p, boot), _lit_shade(LEATHER_LIGHT, LEATHER_DARK, 0.25))
	_draw(img, func(p): return _sd_box(p, Vector2(0.45, 0.22), Vector2(0.15, 0.05), 0.0, 0.01), _lit_shade(Color(0.75, 0.60, 0.40), Color(0.35, 0.22, 0.10)), 1.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.56, 0.82), Vector2(0.28, 0.025)), _flat(Color(0.12, 0.08, 0.05)), 0.8)


static func _gloves(img: Image) -> void:
	var sdf := func(p):
		var d := _sd_box(p, Vector2(0.50, 0.58), Vector2(0.16, 0.15), 0.0, 0.06)
		for fx in [0.38, 0.46, 0.54, 0.62]:
			d = minf(d, _sd_capsule(p, Vector2(fx, 0.46), Vector2(fx, 0.22 + absf(fx - 0.5) * 0.3), 0.042))
		d = minf(d, _sd_capsule(p, Vector2(0.36, 0.62), Vector2(0.24, 0.45), 0.045))
		return d
	_draw(img, sdf, _lit_shade(LEATHER_LIGHT, LEATHER_DARK, 0.25))
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.80), Vector2(0.19, 0.07), 0.0, 0.02), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4), 1.0)


static func _shield(img: Image) -> void:
	var kite := [Vector2(0.24, 0.20), Vector2(0.76, 0.20), Vector2(0.77, 0.50), Vector2(0.50, 0.87), Vector2(0.23, 0.50)]
	_draw(img, func(p): return _sd_poly(p, kite) - 1.0, _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.3))
	_draw(img, func(p): return _sd_poly(p, kite) + 4.0, _lit_shade(Color(0.30, 0.42, 0.75), Color(0.06, 0.10, 0.28), 0.25), 0.5)
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.5, 0.46), Vector2(0.035, 0.22)), _sd_box(p, Vector2(0.5, 0.40), Vector2(0.17, 0.035))), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


static func _necklace(img: Image, gem: Color) -> void:
	for i in 13:
		var a := lerpf(PI * 1.08, -PI * 0.08, i / 12.0)
		var c := Vector2(0.5, 0.40) + Vector2(cos(a), -sin(a)) * Vector2(0.26, 0.22)
		_draw(img, func(p): return _sd_circle(p, c, 0.028), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_gem(img, Vector2(0.5, 0.68), 0.13, gem)


static func _earring(img: Image, gem: Color) -> void:
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.26), 0.09)) - 0.022 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.5, 0.35), Vector2(0.5, 0.46), 0.02), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)
	_gem(img, Vector2(0.5, 0.63), 0.15, gem)


static func _ring(img: Image, gem: Color) -> void:
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.60), 0.21)) - 0.05 * BASE_SIZE, _lit_shade(GOLD_LIGHT, GOLD_DARK, 0.5))
	_gem(img, Vector2(0.5, 0.35), 0.11, gem)


## Gemme taillée : losange à facettes + reflet + halo.
static func _gem(img: Image, c: Vector2, r: float, color: Color) -> void:
	_glow(img, c, r * 2.2, color, 0.45)
	var pts := [c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.85, -r * 0.2)]
	_draw(img, func(p): return _sd_poly(p, pts), func(q: Vector2, _d: float) -> Color:
		var rel := q - c
		var facet := 0.35 if rel.x < 0.0 else -0.15
		if rel.y < -r * 0.2:
			facet += 0.25
		return color.lerp(Color.WHITE, clampf(facet, 0.0, 1.0)) if facet > 0.0 else color.darkened(-facet), 1.2)
	_draw(img, func(p): return _sd_circle(p, c + Vector2(-r * 0.3, -r * 0.35), r * 0.16), _flat(Color(1, 1, 1, 0.9)), 0.0)


static func _potion(img: Image, liquid: Color) -> void:
	var glass := Color(0.80, 0.88, 0.95, 0.55)
	var flask := func(p): return minf(_sd_circle(p, Vector2(0.5, 0.63), 0.24), _sd_box(p, Vector2(0.5, 0.35), Vector2(0.075, 0.11), 0.0, 0.02))
	_draw(img, flask, func(q: Vector2, _d: float) -> Color:
		if q.y > 0.50:
			var shade := 1.0 - (q.y - 0.5) * 1.2
			return Color(liquid.r * shade, liquid.g * shade, liquid.b * shade, 1.0).lerp(Color.WHITE, clampf(0.25 - q.distance_to(Vector2(0.40, 0.58)) * 2.0, 0.0, 0.5))
		return glass)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.21), Vector2(0.095, 0.055), 0.0, 0.015), _lit_shade(Color(0.66, 0.46, 0.28), Color(0.30, 0.18, 0.08)), 1.0)
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.37, 0.56), Vector2(0.36, 0.70), 0.025), _flat(Color(1, 1, 1, 0.55)), 0.0)


static func _shots(img: Image, color: Color, core: Color) -> void:
	for c in [Vector2(0.38, 0.62), Vector2(0.62, 0.64), Vector2(0.50, 0.42)]:
		_glow(img, c, 0.30, color, 0.35)
	for c in [Vector2(0.38, 0.62), Vector2(0.62, 0.64), Vector2(0.50, 0.42)]:
		var center: Vector2 = c
		_draw(img, func(p): return _sd_circle(p, center, 0.13), func(q: Vector2, _d: float) -> Color:
			var t := clampf(q.distance_to(center + Vector2(-0.04, -0.04)) / 0.16, 0.0, 1.0)
			return core.lerp(color, t).lerp(color.darkened(0.5), maxf(t - 0.7, 0.0) * 2.0), 1.2)


## Parchemin roulé aux deux bouts, lignes d'écriture et sceau de cire, dans une lueur blanche
## (Scroll of Escape).
static func _scroll(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.48), 0.55, Color(0.85, 0.92, 1.0), 0.55)
	var paper_l := Color(0.97, 0.91, 0.72)
	var paper_d := Color(0.66, 0.52, 0.30)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.5), Vector2(0.20, 0.23), 0.0, 0.01), _lit_shade(paper_l, paper_d, 0.15))
	for y in [0.27, 0.73]:
		var roll_y: float = y
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.26, roll_y), Vector2(0.74, roll_y), 0.055), _lit_shade(paper_l.lightened(0.1), paper_d.darkened(0.2), 0.35), 1.2)
	for i in 4:
		var line_y := 0.38 + 0.065 * i
		var line_end := 0.64 if i % 2 == 0 else 0.58
		_draw(img, func(p): return _sd_capsule(p, Vector2(0.37, line_y), Vector2(line_end, line_y), 0.012), _flat(Color(0.35, 0.24, 0.12, 0.8)), 0.0)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.63, 0.63), 0.075), _lit_shade(Color(0.95, 0.25, 0.20), Color(0.45, 0.04, 0.04), 0.3), 1.0)


static func _key(img: Image) -> void:
	var brass_l := Color(0.95, 0.80, 0.45)
	var brass_d := Color(0.40, 0.28, 0.08)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.32, 0.34), 0.13)) - 0.04 * BASE_SIZE, _lit_shade(brass_l, brass_d, 0.4))
	_draw(img, func(p): return minf(minf(_sd_capsule(p, Vector2(0.42, 0.44), Vector2(0.78, 0.80), 0.04), _sd_box(p, Vector2(0.72, 0.62), Vector2(0.05, 0.025), PI / 4.0)), _sd_box(p, Vector2(0.62, 0.70), Vector2(0.04, 0.022), PI / 4.0)), _lit_shade(brass_l, brass_d, 0.4))


static func _hammer(img: Image) -> void:
	_draw(img, func(p): return _sd_capsule(p, Vector2(0.30, 0.78), Vector2(0.62, 0.38), 0.035), _lit_shade(LEATHER_LIGHT, LEATHER_DARK))
	_draw(img, func(p): return _sd_box(p, Vector2(0.63, 0.34), Vector2(0.20, 0.08), -PI / 4.0 + PI / 2.0 - 0.2, 0.02), _lit_shade(STEEL_LIGHT, STEEL_DARK, 0.4))


static func _pouch(img: Image) -> void:
	_draw(img, func(p): return minf(_sd_circle(p, Vector2(0.5, 0.62), 0.24), _sd_poly(p, [Vector2(0.38, 0.40), Vector2(0.62, 0.40), Vector2(0.68, 0.24), Vector2(0.32, 0.24)])), _lit_shade(Color(0.72, 0.58, 0.40), Color(0.28, 0.18, 0.08), 0.2))
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.40), Vector2(0.14, 0.03), 0.0, 0.01), _lit_shade(GOLD_LIGHT, GOLD_DARK), 1.0)


# --- Compétences -----------------------------------------------------------------

static func _holy_cross(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.70, 0.95, 0.45), 0.8)
	_draw(img, func(p): return minf(_sd_box(p, Vector2(0.5, 0.5), Vector2(0.09, 0.30), 0.0, 0.02), _sd_box(p, Vector2(0.5, 0.5), Vector2(0.30, 0.09), 0.0, 0.02)), _lit_shade(Color(1.0, 1.0, 0.88), Color(0.95, 0.80, 0.40), 0.3), 1.2)


static func _buff_arrow(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.5, 0.7, 1.0), 0.6)
	for i in 2:
		var oy := 0.16 * i
		_draw(img, func(p): return _sd_poly(p, [Vector2(0.5, 0.20 + oy), Vector2(0.78, 0.46 + oy), Vector2(0.66, 0.52 + oy), Vector2(0.5, 0.37 + oy), Vector2(0.34, 0.52 + oy), Vector2(0.22, 0.46 + oy)]), _lit_shade(Color(1.0, 0.96, 0.70), Color(0.95, 0.70, 0.20), 0.3), 1.2)


static func _debuff_arrow(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.55, Color(0.7, 0.3, 0.9), 0.6)
	for i in 2:
		var oy := 0.16 * i
		_draw(img, func(p): return _sd_poly(p, [Vector2(0.5, 0.64 + oy), Vector2(0.22, 0.38 + oy), Vector2(0.34, 0.32 + oy), Vector2(0.5, 0.47 + oy), Vector2(0.66, 0.32 + oy), Vector2(0.78, 0.38 + oy)]), _lit_shade(Color(0.95, 0.75, 1.0), Color(0.45, 0.10, 0.60), 0.3), 1.2)


static func _burst(img: Image, color: Color, core: Color, spikes: int) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.6, color, 0.9)
	var pts := []
	for i in spikes * 2:
		var a := TAU * i / (spikes * 2) - PI / 2.0
		var r := 0.36 if i % 2 == 0 else 0.15
		pts.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * r)
	_draw(img, func(p): return _sd_poly(p, pts), func(q: Vector2, _d: float) -> Color:
		return core.lerp(color, clampf(q.distance_to(Vector2(0.5, 0.5)) / 0.36, 0.0, 1.0)), 1.0)


static func _wind_spiral(img: Image) -> void:
	_glow(img, Vector2(0.5, 0.5), 0.5, Color(0.4, 0.9, 0.7), 0.5)
	var steps := 90
	for i in steps:
		var t := float(i) / float(steps - 1)
		var a := t * TAU * 1.4
		var c := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * lerpf(0.03, 0.36, t)
		var r := lerpf(0.03, 0.075, t)
		var col := Color(0.70, 1.0, 0.80).lerp(Color(1, 1, 1), t * 0.5)
		_draw(img, func(p): return _sd_circle(p, c, r), _flat(col), 0.0)


# --- Pictogrammes d'interface (fond transparent, métal argent/or) ---------------

const UI_LIGHT := Color(0.98, 0.94, 0.82)
const UI_DARK := Color(0.55, 0.47, 0.32)


static func _ui_character(img: Image) -> void:
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.33), 0.15), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return maxf(_sd_box(p, Vector2(0.5, 0.80), Vector2(0.30, 0.26), 0.0, 0.20), p.y - 0.86 * BASE_SIZE), _lit_shade(UI_LIGHT, UI_DARK), 2.0)


static func _ui_bag(img: Image) -> void:
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.62), Vector2(0.28, 0.24), 0.0, 0.10), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.36), 0.13)) - 0.035 * BASE_SIZE + maxf(0.0, p.y - 0.38 * BASE_SIZE), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.55), Vector2(0.28, 0.035)), _flat(Color(0.35, 0.28, 0.16)), 0.0)


static func _ui_book(img: Image) -> void:
	_draw(img, func(p): return _sd_box(p, Vector2(0.52, 0.50), Vector2(0.27, 0.34), 0.0, 0.03), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	_draw(img, func(p): return _sd_box(p, Vector2(0.29, 0.50), Vector2(0.04, 0.34)), _flat(Color(0.40, 0.32, 0.18)), 0.0)
	var star := []
	for i in 10:
		var a := TAU * i / 10.0 - PI / 2.0
		star.append(Vector2(0.55, 0.48) + Vector2(cos(a), sin(a)) * (0.14 if i % 2 == 0 else 0.06))
	_draw(img, func(p): return _sd_poly(p, star), _flat(Color(0.40, 0.30, 0.14)), 0.0)


static func _ui_gear(img: Image) -> void:
	var sdf := func(p):
		var rel: Vector2 = p - _px(Vector2(0.5, 0.5))
		var a := atan2(rel.y, rel.x)
		var teeth := clampf(cos(a * 8.0) * 3.0, -1.0, 1.0) * 0.5 + 0.5
		var r := (0.27 + 0.08 * teeth) * BASE_SIZE
		return maxf(rel.length() - r, -(rel.length() - 0.12 * BASE_SIZE))
	_draw(img, sdf, _lit_shade(UI_LIGHT, UI_DARK), 2.0)


## Carte pliée en trois volets, route pointillée rouge jusqu'à une croix.
static func _ui_map(img: Image) -> void:
	var folds := [Vector2(0.16, 0.25), Vector2(0.38, 0.18), Vector2(0.62, 0.25), Vector2(0.84, 0.18),
		Vector2(0.84, 0.76), Vector2(0.62, 0.83), Vector2(0.38, 0.76), Vector2(0.16, 0.83)]
	_draw(img, func(p): return _sd_poly(p, folds), _lit_shade(UI_LIGHT, UI_DARK), 2.0)
	for fold in [[Vector2(0.38, 0.19), Vector2(0.38, 0.75)], [Vector2(0.62, 0.26), Vector2(0.62, 0.82)]]:
		_draw(img, func(p): return _sd_capsule(p, fold[0], fold[1], 0.012), _flat(Color(0.45, 0.37, 0.24, 0.8)), 0.0)
	var route := [Vector2(0.24, 0.68), Vector2(0.33, 0.58), Vector2(0.45, 0.60), Vector2(0.53, 0.48), Vector2(0.64, 0.42)]
	for i in route.size() - 1:
		var a: Vector2 = route[i].lerp(route[i + 1], 0.2)
		var b: Vector2 = route[i].lerp(route[i + 1], 0.75)
		_draw(img, func(p): return _sd_capsule(p, a, b, 0.022), _flat(Color(0.62, 0.14, 0.08)), 0.0)
	for cross in [[Vector2(0.66, 0.30), Vector2(0.78, 0.42)], [Vector2(0.78, 0.30), Vector2(0.66, 0.42)]]:
		_draw(img, func(p): return _sd_capsule(p, cross[0], cross[1], 0.028), _flat(Color(0.62, 0.14, 0.08)), 0.0)


static func _ui_coin(img: Image) -> void:
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.5), 0.40), _lit_shade(Color(1.0, 0.92, 0.55), Color(0.62, 0.40, 0.08), 0.5), 2.5)
	_draw(img, func(p): return absf(_sd_circle(p, Vector2(0.5, 0.5), 0.28)) - 0.03 * BASE_SIZE, _flat(Color(0.60, 0.40, 0.08, 0.9)), 0.0)


## Couronne dorée à trois pointes (chef du groupe, voir PartyWindow), gemme rouge au centre.
static func _ui_crown(img: Image) -> void:
	var outline := [Vector2(0.12, 0.30), Vector2(0.32, 0.52), Vector2(0.50, 0.20), Vector2(0.68, 0.52),
		Vector2(0.88, 0.30), Vector2(0.80, 0.78), Vector2(0.20, 0.78)]
	_draw(img, func(p): return _sd_poly(p, outline), _lit_shade(Color(1.0, 0.92, 0.55), Color(0.62, 0.40, 0.08), 0.5), 2.5)
	for tip in [Vector2(0.12, 0.28), Vector2(0.50, 0.18), Vector2(0.88, 0.28)]:
		_draw(img, func(p): return _sd_circle(p, tip, 0.065), _lit_shade(Color(1.0, 0.95, 0.70), Color(0.70, 0.48, 0.12)), 1.5)
	_draw(img, func(p): return _sd_box(p, Vector2(0.5, 0.72), Vector2(0.30, 0.035)), _flat(Color(0.55, 0.36, 0.07, 0.9)), 0.0)
	_draw(img, func(p): return _sd_circle(p, Vector2(0.5, 0.58), 0.07), _lit_shade(Color(1.0, 0.55, 0.50), Color(0.55, 0.05, 0.08)), 1.2)
