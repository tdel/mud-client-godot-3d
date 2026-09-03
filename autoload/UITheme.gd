extends Node
## Thème global "médiéval fantasy" (voir CLAUDE.md, section refonte visuelle) appliqué à
## tout l'arbre de scène : construit un Theme Godot entièrement en code, dans le même
## esprit que ZoneAssets (polices système en fallback et StyleBox générés) pour rester
## cohérent entre Login/CharSelect/CharacterCreate et le HUD en jeu sans avoir à toucher
## chaque scène. Fournit aussi le fond d'écran des écrans hors-jeu (voir
## get_hero_backdrop_texture, seule image téléchargée du projet — licence Pixabay
## Content License, voir res://Backgrounds/).

const BG_PANEL := Color(0.09, 0.07, 0.05, 0.94)
const BG_PANEL_LIGHT := Color(0.16, 0.12, 0.08, 0.96)
const BG_FIELD := Color(0.06, 0.05, 0.04, 0.9)
const BORDER_GOLD := Color(0.72, 0.58, 0.28)
const BORDER_GOLD_BRIGHT := Color(0.92, 0.80, 0.46)
const BORDER_DARK := Color(0.32, 0.25, 0.14)
const TEXT_IVORY := Color(0.92, 0.87, 0.76)
const TEXT_GOLD := Color(0.88, 0.74, 0.44)
const TEXT_DIM := Color(0.60, 0.55, 0.47)
const DANGER := Color(0.85, 0.32, 0.30)

## Fallback de polices système (aucune ne nécessite de téléchargement — voir CLAUDE.md) :
## Godot retient la première police effectivement installée sur la machine.
const FONT_FALLBACK := ["Cinzel", "Trajan Pro", "Constantia", "Cambria", "Palatino Linotype", "Georgia", "Times New Roman", "serif"]

var theme: Theme


func _ready() -> void:
	theme = _build_theme()
	get_tree().root.theme = theme


func _build_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_FALLBACK)

	t.default_font = font
	t.default_font_size = 15

	t.set_font("font", "Label", font)
	t.set_color("font_color", "Label", TEXT_IVORY)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	t.set_font("normal_font", "RichTextLabel", font)
	t.set_font("bold_font", "RichTextLabel", font)
	t.set_color("default_color", "RichTextLabel", TEXT_IVORY)

	var panel_style := _panel_style(BG_PANEL, BORDER_GOLD, 2, 10)
	t.set_stylebox("panel", "Panel", panel_style)
	t.set_stylebox("panel", "PanelContainer", panel_style)
	t.set_stylebox("panel", "AcceptDialog", panel_style)
	t.set_stylebox("embedded_border", "Window", _panel_style(BG_PANEL, BORDER_GOLD, 3, 10))

	t.set_font("font", "Button", font)
	t.set_stylebox("normal", "Button", _button_style(BG_PANEL_LIGHT, BORDER_GOLD))
	t.set_stylebox("hover", "Button", _button_style(BG_PANEL_LIGHT.lightened(0.10), BORDER_GOLD_BRIGHT))
	t.set_stylebox("pressed", "Button", _button_style(BG_PANEL.darkened(0.15), BORDER_GOLD_BRIGHT))
	t.set_stylebox("disabled", "Button", _button_style(BG_PANEL.darkened(0.25), BORDER_DARK))
	t.set_stylebox("focus", "Button", _button_style(BG_PANEL_LIGHT, BORDER_GOLD_BRIGHT))
	t.set_color("font_color", "Button", TEXT_IVORY)
	t.set_color("font_hover_color", "Button", TEXT_GOLD)
	t.set_color("font_pressed_color", "Button", TEXT_GOLD)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_focus_color", "Button", TEXT_GOLD)

	t.set_font("font", "OptionButton", font)
	t.set_stylebox("normal", "OptionButton", _button_style(BG_PANEL_LIGHT, BORDER_GOLD))
	t.set_stylebox("hover", "OptionButton", _button_style(BG_PANEL_LIGHT.lightened(0.10), BORDER_GOLD_BRIGHT))
	t.set_stylebox("pressed", "OptionButton", _button_style(BG_PANEL.darkened(0.15), BORDER_GOLD_BRIGHT))
	t.set_stylebox("disabled", "OptionButton", _button_style(BG_PANEL.darkened(0.25), BORDER_DARK))
	t.set_color("font_color", "OptionButton", TEXT_IVORY)
	t.set_color("font_hover_color", "OptionButton", TEXT_GOLD)

	t.set_font("font", "LineEdit", font)
	t.set_stylebox("normal", "LineEdit", _field_style(false))
	t.set_stylebox("focus", "LineEdit", _field_style(true))
	t.set_stylebox("read_only", "LineEdit", _field_style(false))
	t.set_color("font_color", "LineEdit", TEXT_IVORY)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", TEXT_GOLD)
	t.set_color("selection_color", "LineEdit", Color(BORDER_GOLD.r, BORDER_GOLD.g, BORDER_GOLD.b, 0.35))

	t.set_stylebox("slider", "HSlider", _panel_style(BG_FIELD, BORDER_DARK, 1, 5))
	t.set_stylebox("grabber_area", "HSlider", _panel_style(BORDER_GOLD.darkened(0.1), BORDER_GOLD_BRIGHT, 1, 5))
	t.set_stylebox("grabber_area_highlight", "HSlider", _panel_style(BORDER_GOLD_BRIGHT, BORDER_GOLD_BRIGHT, 1, 5))
	var knob := _knob_texture(BORDER_GOLD_BRIGHT, 14)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_icon("grabber_disabled", "HSlider", _knob_texture(TEXT_DIM, 14))

	for scrollbar_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", scrollbar_type, _panel_style(BG_FIELD, BORDER_DARK, 1, 6))
		t.set_stylebox("scroll_focus", scrollbar_type, _panel_style(BG_FIELD, BORDER_GOLD, 1, 6))
		t.set_stylebox("grabber", scrollbar_type, _panel_style(BORDER_GOLD.darkened(0.1), BORDER_GOLD, 1, 6))
		t.set_stylebox("grabber_highlight", scrollbar_type, _panel_style(BORDER_GOLD_BRIGHT, BORDER_GOLD_BRIGHT, 1, 6))
		t.set_stylebox("grabber_pressed", scrollbar_type, _panel_style(BORDER_GOLD_BRIGHT, BORDER_GOLD_BRIGHT, 1, 6))

	return t


func _panel_style(bg: Color, border: Color, border_width: int = 2, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 6
	s.anti_aliasing = true
	return s


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := _panel_style(bg, border, 2, 6)
	s.shadow_size = 0
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


func _field_style(focused: bool) -> StyleBoxFlat:
	var s := _panel_style(BG_FIELD, BORDER_GOLD_BRIGHT if focused else BORDER_DARK, 1 if not focused else 2, 5)
	s.shadow_size = 0
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## Petit galet doré procédural pour les poignées de curseur (HSlider), même esprit que
## ZoneAssets.make_entity_texture (aucune image externe disponible).
func _knob_texture(color: Color, diameter: int = 14) -> ImageTexture:
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(diameter / 2.0, diameter / 2.0)
	var radius := diameter / 2.0 - 1.0
	for y in diameter:
		for x in diameter:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if dist <= radius:
				var shade := 1.0 - (dist / radius) * 0.3
				image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 1.0))
			elif dist <= radius + 1.2:
				image.set_pixel(x, y, color.darkened(0.5))
	return ImageTexture.create_from_image(image)


## Château au clair de lune survolé par un dragon (voir CLAUDE.md, remplace l'ancien
## night_castle_moon.png le 2026-09-03 — retour explicite pour un wallpaper "façon
## Lineage/Lineage2"), utilisé comme fond des écrans hors-jeu (login/sélection/création de
## personnage — voir Backdrop dans leurs .tscn) ; res://scenes/common/HeroSilhouettes.gd
## ajoute par-dessus les silhouettes de personnages/l'effet de sort. Chargé une seule fois
## (le TextureRect ne bouge jamais).
const HERO_BACKDROP_PATH := "res://Backgrounds/castle_dragon_moon.jpg"
var _hero_backdrop_texture: Texture2D


func get_hero_backdrop_texture() -> Texture2D:
	if _hero_backdrop_texture == null:
		_hero_backdrop_texture = load(HERO_BACKDROP_PATH)
	return _hero_backdrop_texture


## Fond d'ambiance plein écran procédural (dégradé sombre + vignette + grain léger façon
## pierre), conservé en fallback/pour d'éventuels futurs écrans sans thème dédié — plus
## utilisé par défaut sur Login/CharSelect/CharacterCreate depuis l'ajout du fond
## ci-dessus. La carte de jeu elle-même sert de fond à Game.tscn, cette texture n'y est
## pas utilisée non plus.
func make_backdrop_texture(size: Vector2i = Vector2i(640, 360)) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var top_color := Color(0.07, 0.06, 0.05, 1.0)
	var bottom_color := Color(0.03, 0.025, 0.02, 1.0)
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	var max_dist := center.length()

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ui_backdrop")

	for y in size.y:
		var base := top_color.lerp(bottom_color, float(y) / float(size.y))
		for x in size.x:
			var dist := Vector2(x, y).distance_to(center)
			var vignette := clampf(dist / max_dist, 0.0, 1.0) * 0.35
			var col := base.darkened(vignette)
			if rng.randf() < 0.04:
				var grain := rng.randf_range(-0.02, 0.03)
				col = Color(
					clampf(col.r + grain, 0.0, 1.0),
					clampf(col.g + grain, 0.0, 1.0),
					clampf(col.b + grain, 0.0, 1.0),
				)
			image.set_pixel(x, y, col)

	return ImageTexture.create_from_image(image)
