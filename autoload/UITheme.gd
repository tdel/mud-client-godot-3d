extends Node
## Thème global de l'interface, inspiré de la direction artistique de Lineage 2 (chronique
## High Five) sans en reprendre les assets : fenêtres noires translucides cerclées d'un filet
## de métal bronze/argent biseauté, barre de titre en dégradé sombre, boutons "pierre et
## bronze", slots d'objets en creux, barres CP/HP/MP à dégradé brillant, petite police
## sans-serif très lisible (Tahoma/Verdana) en crème sur noir.
##
## Tout est généré en code (textures 9-slices peintes pixel par pixel au démarrage, aucune
## image externe) et appliqué à tout l'arbre de scène (voir _on_node_added). Les scènes
## choisissent une variante via `theme_type_variation` (ex. "TitleBar", "SlotPanel",
## "HudPanel"...) — voir _build_theme pour la liste complète — plutôt que de dupliquer des
## StyleBoxFlat dans chaque .tscn.

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

## Fond de fenêtre : noir légèrement bleuté, translucide (on devine le monde derrière).
const WIN_BG_TOP := Color(0.085, 0.085, 0.095, 0.90)
const WIN_BG_BOTTOM := Color(0.030, 0.030, 0.036, 0.90)
## Filet de cadre : métal bronze/argent terne, avec une variante claire pour le biseau.
const METAL := Color(0.40, 0.37, 0.30)
const METAL_LIGHT := Color(0.70, 0.64, 0.49)
const METAL_DARK := Color(0.16, 0.15, 0.12)
const GOLD := Color(0.80, 0.68, 0.40)
const GOLD_BRIGHT := Color(1.00, 0.86, 0.52)

## Textes : crème pour les titres, blanc cassé pour le texte courant, "tan" pour les
## libellés de caractéristiques (la couleur des en-têtes des fenêtres L2), blanc pur pour
## les valeurs.
const TEXT_TITLE := Color(0.91, 0.86, 0.70)
const TEXT_NORMAL := Color(0.88, 0.87, 0.83)
const TEXT_LABEL := Color(0.70, 0.62, 0.47)
const TEXT_VALUE := Color(1.0, 1.0, 1.0)
const TEXT_DIM := Color(0.52, 0.50, 0.45)
const TEXT_LINK := Color(0.93, 0.82, 0.52)
const TEXT_SYSTEM := Color(0.80, 0.84, 0.90)
const DANGER := Color(0.95, 0.36, 0.30)
const SUCCESS := Color(0.45, 0.88, 0.45)

## Alias conservés pour les scripts qui les référencent encore.
const TEXT_IVORY := TEXT_NORMAL
const TEXT_GOLD := TEXT_TITLE

## Couleurs de chat façon L2 (canal général blanc, groupe vert, chuchotement magenta...).
const CHAT_SAY := "#ffffff"
const CHAT_PARTY := "#5ce65c"
const CHAT_WHISPER := "#ff77ff"
const CHAT_GAIN := "#f2df6a"
const CHAT_SYSTEM := "#c9d4e2"
const CHAT_DAMAGE_DEALT := "#ffffff"
const CHAT_DAMAGE_TAKEN := "#ff9a8a"

## Couleurs de grade des objets (NOGRADE/D/C/B/A/S).
const GRADE_COLORS := {
	"NOGRADE": Color(0.82, 0.82, 0.82),
	"D": Color(0.55, 0.78, 1.00),
	"C": Color(0.45, 0.90, 0.45),
	"B": Color(0.40, 0.58, 1.00),
	"A": Color(1.00, 0.80, 0.25),
	"S": Color(1.00, 0.38, 0.30),
}

## Barres de vitalité : [haut du dégradé, bas du dégradé, fond].
const BAR_COLORS := {
	"cp": [Color(0.98, 0.74, 0.22), Color(0.58, 0.34, 0.04), Color(0.14, 0.09, 0.02)],
	"hp": [Color(0.90, 0.22, 0.20), Color(0.46, 0.05, 0.05), Color(0.13, 0.03, 0.03)],
	"mp": [Color(0.30, 0.56, 1.00), Color(0.07, 0.19, 0.55), Color(0.03, 0.05, 0.13)],
	"exp": [Color(0.92, 0.86, 0.50), Color(0.50, 0.42, 0.10), Color(0.10, 0.09, 0.03)],
	"cast": [Color(0.55, 0.80, 1.00), Color(0.12, 0.36, 0.80), Color(0.03, 0.06, 0.14)],
}

## Police principale sans-serif (Godot retient la première installée) ; police d'apparat à
## empattements pour les grands titres des écrans hors-jeu uniquement.
const FONT_MAIN := ["Tahoma", "Verdana", "Segoe UI", "Arial", "Liberation Sans", "DejaVu Sans", "sans-serif"]
const FONT_DISPLAY := ["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua", "Georgia", "serif"]

var theme: Theme
var font_main: SystemFont
var font_bold: SystemFont
var font_display: SystemFont

var _bar_fill_cache: Dictionary = {}
var _bar_bg_style: StyleBox


func _ready() -> void:
	theme = _build_theme()
	get_tree().root.theme = theme
	# Un Control dont l'ascendance passe par un nœud non-Control (CanvasLayer du HUD, Node3D
	# de Game3D) ne remonte pas jusqu'au thème de la racine dans cette version de Godot :
	# on l'affecte donc directement à chaque Control "racine" qui entre dans l'arbre, il se
	# propage ensuite normalement à ses descendants.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if (node is Control or node is Window) and node.theme == null and not (node.get_parent() is Control):
		node.theme = theme


# ---------------------------------------------------------------------------
# API utilitaire pour les scènes
# ---------------------------------------------------------------------------

## Applique le style de barre de vitalité `kind` ("hp"/"mp"/"cp"/"exp"/"cast") à `bar`.
func style_progress_bar(bar: ProgressBar, kind: String) -> void:
	bar.add_theme_stylebox_override("background", _bar_bg_style)
	bar.add_theme_stylebox_override("fill", _bar_fill_style(kind))
	bar.show_percentage = false


## Label posé sur une barre (valeur "342/480") : petit, blanc, contour noir.
func style_bar_label(label: Label, font_size: int = 11) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func grade_color(grade: String) -> Color:
	return GRADE_COLORS.get(grade, TEXT_NORMAL)


## Couleur du nom d'une cible selon l'écart de niveau avec le joueur, façon L2 (gris =
## sans danger, vert/bleu = plus faible, blanc = équivalent, jaune/rouge/violet = dangereux).
func level_diff_color(target_level: int, player_level: int) -> Color:
	var diff := target_level - player_level
	if diff <= -9:
		return Color(0.60, 0.60, 0.60)
	if diff <= -6:
		return Color(0.45, 0.88, 0.45)
	if diff <= -3:
		return Color(0.52, 0.76, 1.00)
	if diff <= 2:
		return Color(1.0, 1.0, 1.0)
	if diff <= 5:
		return Color(1.00, 0.92, 0.42)
	if diff <= 8:
		return Color(1.00, 0.42, 0.38)
	return Color(0.85, 0.45, 1.00)


## "1254300" -> "1 254 300" (espaces insécables).
func format_number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## Infobulle riche (BBCode) façon L2 : à retourner depuis `_make_custom_tooltip`. Le texte de
## tooltip_text peut contenir des balises [color]/[b]... ; sans balise, s'affiche tel quel.
func make_rich_tooltip(bbcode: String) -> Control:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("normal_font_size", 12)
	label.add_theme_font_size_override("bold_font_size", 13)
	label.add_theme_color_override("default_color", TEXT_NORMAL)
	label.text = bbcode
	var width := 0.0
	for line in label.get_parsed_text().split("\n"):
		width = maxf(width, font_main.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	label.custom_minimum_size = Vector2(minf(width + 8.0, 360.0), 0)
	if width + 8.0 > 360.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Ligne "Libellé : valeur" pour les infobulles (libellé tan, valeur blanche).
func tooltip_stat(label_text: String, value_text: String) -> String:
	return "[color=#%s]%s[/color] [color=#ffffff]%s[/color]" % [TEXT_LABEL.to_html(false), label_text, value_text]


## Petite pastille carrée "D"/"C"/... aux couleurs du grade, pour les coins de slots.
func make_grade_badge(grade: String) -> Control:
	var label := Label.new()
	label.text = grade
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font_bold)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", grade_color(grade))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	return label


# ---------------------------------------------------------------------------
# Construction du thème
# ---------------------------------------------------------------------------

func _build_theme() -> Theme:
	var t := Theme.new()
	font_main = SystemFont.new()
	font_main.font_names = PackedStringArray(FONT_MAIN)
	font_main.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font_main.hinting = TextServer.HINTING_LIGHT
	font_bold = SystemFont.new()
	font_bold.font_names = PackedStringArray(FONT_MAIN)
	font_bold.font_weight = 700
	font_display = SystemFont.new()
	font_display.font_names = PackedStringArray(FONT_DISPLAY)

	t.default_font = font_main
	t.default_font_size = 13

	# --- Textes -------------------------------------------------------------
	t.set_color("font_color", "Label", TEXT_NORMAL)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 1))

	_label_variation(t, "WindowTitle", TEXT_TITLE, 13, font_bold)
	_label_variation(t, "HeaderLabel", TEXT_LABEL, 12, font_bold)
	_label_variation(t, "StatLabel", TEXT_LABEL, 12)
	_label_variation(t, "StatValue", TEXT_VALUE, 12)
	_label_variation(t, "DimLabel", TEXT_DIM, 12)
	_label_variation(t, "MessageLabel", TEXT_LINK, 12)
	_label_variation(t, "ErrorLabel", DANGER, 13)
	_label_variation(t, "DisplayTitle", TEXT_TITLE, 26, font_display)
	_label_variation(t, "NameLabel", TEXT_VALUE, 14, font_bold)

	t.set_font("normal_font", "RichTextLabel", font_main)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_color("default_color", "RichTextLabel", TEXT_NORMAL)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.9))
	t.set_constant("shadow_offset_x", "RichTextLabel", 1)
	t.set_constant("shadow_offset_y", "RichTextLabel", 1)
	t.set_font_size("normal_font_size", "RichTextLabel", 12)
	t.set_font_size("bold_font_size", "RichTextLabel", 12)

	# --- Panneaux -----------------------------------------------------------
	var window_style := _sbt(_window_image(WIN_BG_TOP, WIN_BG_BOTTOM), 8, 4, 4, 4, 4)
	t.set_stylebox("panel", "Panel", window_style)
	t.set_stylebox("panel", "PanelContainer", window_style)

	_panel_variation(t, "WindowPanel", window_style)
	var hud_style := _sbt(_window_image(Color(0.06, 0.06, 0.07, 0.80), Color(0.02, 0.02, 0.025, 0.80)), 8, 8, 6, 8, 6)
	_panel_variation(t, "HudPanel", hud_style)
	_panel_variation(t, "TitleBar", _sbt(_titlebar_image(), 3, 10, 3, 4, 3))
	_panel_variation(t, "InsetPanel", _sbt(_inset_image(Color(0.015, 0.015, 0.02, 0.75)), 3, 8, 6, 8, 6))
	_panel_variation(t, "SlotPanel", _sbt(_slot_image(false), 4, 0, 0, 0, 0))
	_panel_variation(t, "SlotPanelHover", _sbt(_slot_image(true), 4, 0, 0, 0, 0))
	_panel_variation(t, "RowPanel", _row_style(false))
	_panel_variation(t, "RowPanelSelected", _row_style(true))
	_panel_variation(t, "PlaquePanel", _sbt(_plaque_image(), 5, 10, 3, 10, 3))

	var chat_style := StyleBoxFlat.new()
	chat_style.bg_color = Color(0.0, 0.0, 0.0, 0.50)
	chat_style.border_color = Color(0.34, 0.32, 0.26, 0.55)
	chat_style.set_border_width_all(1)
	chat_style.set_content_margin_all(5)
	_panel_variation(t, "ChatPanel", chat_style)

	# Séparateurs : filet métal fin avec un reflet dessous (effet gravé).
	t.set_stylebox("separator", "HSeparator", _separator_style(false))
	t.set_stylebox("separator", "VSeparator", _separator_style(true))
	t.set_constant("separation", "HSeparator", 6)
	t.set_constant("separation", "VSeparator", 6)

	# --- Boutons ------------------------------------------------------------
	var btn_normal := _sbt(_button_image("normal"), 4, 12, 4, 12, 4)
	var btn_hover := _sbt(_button_image("hover"), 4, 12, 4, 12, 4)
	var btn_pressed := _sbt(_button_image("pressed"), 4, 12, 5, 12, 3)
	var btn_disabled := _sbt(_button_image("disabled"), 4, 12, 4, 12, 4)
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, btn_normal)
		t.set_stylebox("hover", type_name, btn_hover)
		t.set_stylebox("pressed", type_name, btn_pressed)
		t.set_stylebox("hover_pressed", type_name, btn_pressed)
		t.set_stylebox("disabled", type_name, btn_disabled)
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		t.set_font_size("font_size", type_name, 12)
		t.set_color("font_color", type_name, TEXT_NORMAL)
		t.set_color("font_hover_color", type_name, Color.WHITE)
		t.set_color("font_pressed_color", type_name, GOLD_BRIGHT)
		t.set_color("font_hover_pressed_color", type_name, GOLD_BRIGHT)
		t.set_color("font_focus_color", type_name, TEXT_NORMAL)
		t.set_color("font_disabled_color", type_name, TEXT_DIM)
		t.set_color("font_outline_color", type_name, Color(0, 0, 0, 1))
		t.set_constant("outline_size", type_name, 2)
		t.set_constant("h_separation", type_name, 6)
	t.set_icon("arrow", "OptionButton", _arrow_icon(9, false, TEXT_TITLE))
	t.set_constant("arrow_margin", "OptionButton", 6)

	# Gros bouton des écrans hors-jeu (connexion, sélection...).
	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 14)
	t.set_stylebox("normal", "BigButton", _sbt(_button_image("normal"), 4, 18, 7, 18, 7))
	t.set_stylebox("hover", "BigButton", _sbt(_button_image("hover"), 4, 18, 7, 18, 7))
	t.set_stylebox("pressed", "BigButton", _sbt(_button_image("pressed"), 4, 18, 8, 18, 6))
	t.set_stylebox("hover_pressed", "BigButton", _sbt(_button_image("pressed"), 4, 18, 8, 18, 6))
	t.set_stylebox("disabled", "BigButton", _sbt(_button_image("disabled"), 4, 18, 7, 18, 7))

	# Croix de fermeture des fenêtres : pas de fond, juste un pictogramme.
	t.set_type_variation("CloseButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(1)
		t.set_stylebox(state, "CloseButton", empty)
	t.set_icon("icon", "CloseButton", _close_icon(TEXT_LABEL))
	t.set_color("icon_normal_color", "CloseButton", Color(1, 1, 1, 0.85))
	t.set_color("icon_hover_color", "CloseButton", Color(1.5, 1.4, 1.2, 1))
	t.set_color("icon_pressed_color", "CloseButton", GOLD_BRIGHT)

	# Bouton-icône carré (barre de menu bas-droite).
	t.set_type_variation("IconButton", "Button")
	t.set_stylebox("normal", "IconButton", _sbt(_slot_image(false), 4, 3, 3, 3, 3))
	t.set_stylebox("hover", "IconButton", _sbt(_slot_image(true), 4, 3, 3, 3, 3))
	t.set_stylebox("pressed", "IconButton", _sbt(_slot_image(true), 4, 4, 4, 2, 2))
	t.set_stylebox("hover_pressed", "IconButton", _sbt(_slot_image(true), 4, 4, 4, 2, 2))
	t.set_stylebox("focus", "IconButton", StyleBoxEmpty.new())
	t.set_color("icon_normal_color", "IconButton", Color(0.92, 0.92, 0.92))
	t.set_color("icon_hover_color", "IconButton", Color(1.2, 1.15, 1.05))
	t.set_color("icon_pressed_color", "IconButton", Color(1.3, 1.2, 0.9))

	# Lien de dialogue PNJ (texte cliquable plutôt que gros bouton).
	t.set_type_variation("DialogLink", "Button")
	var link_normal := StyleBoxEmpty.new()
	link_normal.content_margin_left = 6
	link_normal.content_margin_top = 3
	link_normal.content_margin_bottom = 3
	var link_hover := StyleBoxFlat.new()
	link_hover.bg_color = Color(1.0, 0.85, 0.5, 0.08)
	link_hover.border_color = Color(1.0, 0.85, 0.5, 0.25)
	link_hover.border_width_left = 2
	link_hover.content_margin_left = 6
	link_hover.content_margin_top = 3
	link_hover.content_margin_bottom = 3
	for state in ["normal", "focus", "disabled"]:
		t.set_stylebox(state, "DialogLink", link_normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "DialogLink", link_hover)
	t.set_color("font_color", "DialogLink", TEXT_LINK)
	t.set_color("font_hover_color", "DialogLink", Color.WHITE)
	t.set_color("font_pressed_color", "DialogLink", GOLD_BRIGHT)
	t.set_constant("outline_size", "DialogLink", 0)

	# Onglet façon L2 : bouton plat à bascule (voir le chat, l'inventaire...).
	t.set_type_variation("TabButton", "Button")
	t.set_stylebox("normal", "TabButton", _sbt(_tab_image(false, false), 4, 10, 3, 10, 3))
	t.set_stylebox("hover", "TabButton", _sbt(_tab_image(false, true), 4, 10, 3, 10, 3))
	t.set_stylebox("pressed", "TabButton", _sbt(_tab_image(true, false), 4, 10, 3, 10, 3))
	t.set_stylebox("hover_pressed", "TabButton", _sbt(_tab_image(true, false), 4, 10, 3, 10, 3))
	t.set_stylebox("disabled", "TabButton", _sbt(_tab_image(false, false), 4, 10, 3, 10, 3))
	t.set_color("font_color", "TabButton", TEXT_DIM)
	t.set_color("font_hover_color", "TabButton", TEXT_NORMAL)
	t.set_color("font_pressed_color", "TabButton", TEXT_TITLE)
	t.set_color("font_hover_pressed_color", "TabButton", TEXT_TITLE)
	t.set_font_size("font_size", "TabButton", 12)

	# --- TabBar (chat) ------------------------------------------------------
	t.set_font_size("font_size", "TabBar", 12)
	t.set_stylebox("tab_selected", "TabBar", _sbt(_tab_image(true, false), 4, 10, 3, 10, 3))
	t.set_stylebox("tab_unselected", "TabBar", _sbt(_tab_image(false, false), 4, 10, 3, 10, 3))
	t.set_stylebox("tab_hovered", "TabBar", _sbt(_tab_image(false, true), 4, 10, 3, 10, 3))
	t.set_stylebox("tab_disabled", "TabBar", _sbt(_tab_image(false, false), 4, 10, 3, 10, 3))
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", TEXT_TITLE)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT_NORMAL)
	t.set_color("font_outline_color", "TabBar", Color(0, 0, 0, 1))
	t.set_constant("outline_size", "TabBar", 2)
	t.set_constant("h_separation", "TabBar", 2)
	t.set_color("drop_mark_color", "TabBar", GOLD_BRIGHT)

	# --- Champs de saisie ---------------------------------------------------
	var field := _sbt(_field_image(false), 3, 7, 4, 7, 4)
	var field_focus := _sbt(_field_image(true), 3, 7, 4, 7, 4)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_font_size("font_size", "LineEdit", 13)
	t.set_color("font_color", "LineEdit", TEXT_VALUE)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.85))
	t.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	t.set_constant("caret_width", "LineEdit", 1)

	t.set_icon("up", "SpinBox", _arrow_icon(8, true, TEXT_TITLE))
	t.set_icon("down", "SpinBox", _arrow_icon(8, false, TEXT_TITLE))
	for sb_name in ["up_background", "down_background"]:
		t.set_stylebox(sb_name, "SpinBox", _sbt(_button_image("normal"), 3, 3, 1, 3, 1))
		t.set_stylebox(sb_name + "_hovered", "SpinBox", _sbt(_button_image("hover"), 3, 3, 1, 3, 1))
		t.set_stylebox(sb_name + "_pressed", "SpinBox", _sbt(_button_image("pressed"), 3, 3, 1, 3, 1))
		t.set_stylebox(sb_name + "_disabled", "SpinBox", _sbt(_button_image("disabled"), 3, 3, 1, 3, 1))
	t.set_color("up_icon_modulate", "SpinBox", TEXT_TITLE)
	t.set_color("down_icon_modulate", "SpinBox", TEXT_TITLE)
	t.set_constant("buttons_width", "SpinBox", 14)

	# --- Barres de défilement : piste en creux, poignée bronze, petites flèches ------
	for sb_type in ["VScrollBar", "HScrollBar"]:
		var vertical: bool = sb_type == "VScrollBar"
		t.set_stylebox("scroll", sb_type, _sbt(_inset_image(Color(0.01, 0.01, 0.012, 0.8)), 2, 1, 1, 1, 1))
		t.set_stylebox("scroll_focus", sb_type, _sbt(_inset_image(Color(0.01, 0.01, 0.012, 0.8)), 2, 1, 1, 1, 1))
		t.set_stylebox("grabber", sb_type, _sbt(_button_image("normal"), 3, 3, 3, 3, 3))
		t.set_stylebox("grabber_highlight", sb_type, _sbt(_button_image("hover"), 3, 3, 3, 3, 3))
		t.set_stylebox("grabber_pressed", sb_type, _sbt(_button_image("hover"), 3, 3, 3, 3, 3))
		var dec := _arrow_icon(9, true, TEXT_LABEL) if vertical else _side_arrow_icon(9, true, TEXT_LABEL)
		var inc := _arrow_icon(9, false, TEXT_LABEL) if vertical else _side_arrow_icon(9, false, TEXT_LABEL)
		var dec_hl := _arrow_icon(9, true, GOLD_BRIGHT) if vertical else _side_arrow_icon(9, true, GOLD_BRIGHT)
		var inc_hl := _arrow_icon(9, false, GOLD_BRIGHT) if vertical else _side_arrow_icon(9, false, GOLD_BRIGHT)
		t.set_icon("decrement", sb_type, dec)
		t.set_icon("increment", sb_type, inc)
		t.set_icon("decrement_highlight", sb_type, dec_hl)
		t.set_icon("increment_highlight", sb_type, inc_hl)
		t.set_icon("decrement_pressed", sb_type, dec_hl)
		t.set_icon("increment_pressed", sb_type, inc_hl)

	# --- Barres de progression (défaut : HP) ---------------------------------
	_bar_bg_style = _sbt(_bar_bg_image(), 2, 0, 0, 0, 0)
	t.set_stylebox("background", "ProgressBar", _bar_bg_style)
	t.set_stylebox("fill", "ProgressBar", _bar_fill_style("hp"))
	t.set_color("font_color", "ProgressBar", Color.WHITE)
	t.set_font_size("font_size", "ProgressBar", 11)

	t.set_stylebox("slider", "HSlider", _sbt(_inset_image(Color(0.01, 0.01, 0.012, 0.8)), 2, 0, 2, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _bar_fill_style("exp"))
	t.set_stylebox("grabber_area_highlight", "HSlider", _bar_fill_style("exp"))

	# --- Infobulles -----------------------------------------------------------
	var tooltip := StyleBoxFlat.new()
	tooltip.bg_color = Color(0.02, 0.02, 0.025, 0.94)
	tooltip.border_color = Color(0.46, 0.43, 0.35, 0.95)
	tooltip.set_border_width_all(1)
	tooltip.content_margin_left = 8
	tooltip.content_margin_right = 8
	tooltip.content_margin_top = 5
	tooltip.content_margin_bottom = 5
	t.set_stylebox("panel", "TooltipPanel", tooltip)
	t.set_color("font_color", "TooltipLabel", TEXT_NORMAL)
	t.set_font_size("font_size", "TooltipLabel", 12)
	t.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0.9))

	# --- Menus contextuels (clic droit PNJ, listes déroulantes) ---------------
	t.set_stylebox("panel", "PopupMenu", _sbt(_window_image(Color(0.06, 0.06, 0.07, 0.96), Color(0.03, 0.03, 0.035, 0.96)), 8, 6, 6, 6, 6))
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color(0.85, 0.72, 0.42, 0.16)
	popup_hover.border_color = Color(0.85, 0.72, 0.42, 0.45)
	popup_hover.set_border_width_all(1)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_stylebox("separator", "PopupMenu", _separator_style(false))
	t.set_color("font_color", "PopupMenu", TEXT_NORMAL)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Color(TEXT_DIM, 0.7))
	t.set_font_size("font_size", "PopupMenu", 13)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 16)

	# --- Boîtes de dialogue (ConfirmationDialog) -----------------------------
	var dialog_border := _sbt(_window_image(Color(0.07, 0.07, 0.08, 0.97), Color(0.03, 0.03, 0.035, 0.97)), 8, 0, 0, 0, 0)
	dialog_border.expand_margin_left = 4
	dialog_border.expand_margin_right = 4
	dialog_border.expand_margin_bottom = 4
	dialog_border.expand_margin_top = 28
	t.set_stylebox("embedded_border", "Window", dialog_border)
	t.set_stylebox("embedded_unfocused_border", "Window", dialog_border)
	t.set_constant("title_height", "Window", 24)
	t.set_color("title_color", "Window", TEXT_TITLE)
	t.set_font("title_font", "Window", font_bold)
	t.set_font_size("title_font_size", "Window", 13)
	t.set_color("title_outline_modulate", "Window", Color(0, 0, 0, 1))
	t.set_constant("title_outline_size", "Window", 2)
	t.set_icon("close", "Window", _close_icon(TEXT_LABEL))
	t.set_icon("close_pressed", "Window", _close_icon(GOLD_BRIGHT))
	t.set_constant("close_h_offset", "Window", 20)
	t.set_constant("close_v_offset", "Window", 18)
	var dialog_panel := StyleBoxEmpty.new()
	dialog_panel.set_content_margin_all(10)
	t.set_stylebox("panel", "AcceptDialog", dialog_panel)
	t.set_constant("buttons_separation", "AcceptDialog", 12)

	return t


func _label_variation(t: Theme, name: String, color: Color, size: int, font: Font = null) -> void:
	t.set_type_variation(name, "Label")
	t.set_color("font_color", name, color)
	t.set_font_size("font_size", name, size)
	if font != null:
		t.set_font("font", name, font)


## Variation de panneau : utilisable aussi bien sur un PanelContainer que sur un Panel (la
## StyleBox "panel" de la variation est trouvée en premier quel que soit le type du nœud).
func _panel_variation(t: Theme, name: String, style: StyleBox) -> void:
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, style)


func _bar_fill_style(kind: String) -> StyleBox:
	if not _bar_fill_cache.has(kind):
		var colors: Array = BAR_COLORS.get(kind, BAR_COLORS["hp"])
		_bar_fill_cache[kind] = _sbt(_bar_fill_image(colors[0], colors[1]), 2, 0, 0, 0, 0)
	return _bar_fill_cache[kind]


func _row_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.85, 0.72, 0.42, 0.13) if selected else Color(1, 1, 1, 0.025)
	s.border_color = Color(0.85, 0.72, 0.42, 0.55) if selected else Color(0.40, 0.37, 0.30, 0.35)
	if selected:
		s.set_border_width_all(1)
	else:
		s.border_width_bottom = 1
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _separator_style(vertical: bool) -> StyleBoxTexture:
	var img := Image.create(3 if vertical else 8, 8 if vertical else 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 8:
		if vertical:
			img.set_pixel(0, i, Color(0, 0, 0, 0.7))
			img.set_pixel(1, i, Color(METAL, 0.9))
			img.set_pixel(2, i, Color(0, 0, 0, 0.5))
		else:
			img.set_pixel(i, 0, Color(0, 0, 0, 0.7))
			img.set_pixel(i, 1, Color(METAL, 0.9))
			img.set_pixel(i, 2, Color(METAL_LIGHT, 0.18))
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	if vertical:
		s.content_margin_left = 1
		s.content_margin_right = 1
	else:
		s.content_margin_top = 1
		s.content_margin_bottom = 1
	return s


## StyleBoxTexture 9-slices : `margin` = taille des coins/bords non étirés, puis marges de
## contenu gauche/haut/droite/bas.
func _sbt(img: Image, margin: int, cl: float, ct: float, cr: float, cb: float) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = margin
	s.texture_margin_top = margin
	s.texture_margin_right = margin
	s.texture_margin_bottom = margin
	s.content_margin_left = cl
	s.content_margin_top = ct
	s.content_margin_right = cr
	s.content_margin_bottom = cb
	return s


# ---------------------------------------------------------------------------
# Peinture procédurale des textures
# ---------------------------------------------------------------------------

## Distance au bord le plus proche (0 = pixel de bord).
func _edge(x: int, y: int, w: int, h: int) -> int:
	return mini(mini(x, y), mini(w - 1 - x, h - 1 - y))


## Vrai si le pixel de l'anneau `d` est sur le côté haut ou gauche (éclairé).
func _lit(x: int, y: int, w: int, h: int, d: int) -> bool:
	return (y == d and x < w - 1 - d) or (x == d and y < h - 1 - d)


## Cadre de fenêtre : filet noir, métal biseauté, ombre intérieure, fond en dégradé, et
## équerres de métal clair renforcées dans les 4 coins.
func _window_image(bg_top: Color, bg_bottom: Color) -> Image:
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var bg := bg_top.lerp(bg_bottom, float(y) / float(h - 1))
		for x in w:
			var d := _edge(x, y, w, h)
			var corner := (x < 7 or x > w - 8) and (y < 7 or y > h - 8)
			var c: Color
			match d:
				0:
					c = Color(0, 0, 0, 0.95)
				1:
					c = METAL_LIGHT if _lit(x, y, w, h, d) else METAL.darkened(0.25)
					if corner:
						c = METAL_LIGHT.lightened(0.15)
				2:
					c = METAL.darkened(0.45) if not corner else METAL
				3:
					c = Color(0, 0, 0, 0.9) if not corner else METAL.darkened(0.3)
				_:
					c = bg
					if d == 4:
						c = bg.lerp(Color(0, 0, 0, bg.a), 0.5)
			img.set_pixel(x, y, c)
	# Petits rivets clairs au coin intérieur de chaque équerre.
	for p in [Vector2i(3, 3), Vector2i(w - 4, 3), Vector2i(3, h - 4), Vector2i(w - 4, h - 4)]:
		img.set_pixel(p.x, p.y, GOLD_BRIGHT)
	return img


func _titlebar_image() -> Image:
	var w := 12
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color(0.22, 0.21, 0.18, 0.96)
	var bottom := Color(0.08, 0.075, 0.068, 0.96)
	for y in h:
		var c := top.lerp(bottom, float(y) / float(h - 1))
		for x in w:
			var px := c
			if y == 0:
				px = Color(0.36, 0.34, 0.28, 0.96)
			elif y == h - 2:
				px = Color(0, 0, 0, 0.9)
			elif y == h - 1:
				px = Color(METAL, 0.95)
			img.set_pixel(x, y, px)
	return img


## Plaque (petit cartouche) : utilisée pour le nom de zone sous la minimap et les en-têtes.
func _plaque_image() -> Image:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var bg := Color(0.14, 0.13, 0.11, 0.92).lerp(Color(0.05, 0.05, 0.045, 0.92), float(y) / float(h - 1))
		for x in w:
			var d := _edge(x, y, w, h)
			var c := bg
			if d == 0:
				c = Color(0, 0, 0, 0.9)
			elif d == 1:
				c = METAL_LIGHT if _lit(x, y, w, h, d) else METAL.darkened(0.3)
			img.set_pixel(x, y, c)
	return img


## Zone en creux (fond de liste, piste de défilement) : biseau inversé.
func _inset_image(bg: Color) -> Image:
	var w := 12
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := _edge(x, y, w, h)
			var c := bg
			if d == 0:
				c = Color(0, 0, 0, 0.85) if _lit(x, y, w, h, d) else Color(METAL, 0.55)
			elif d == 1:
				c = Color(0, 0, 0, 0.6) if _lit(x, y, w, h, d) else bg
			img.set_pixel(x, y, c)
	return img


func _field_image(focused: bool) -> Image:
	var w := 12
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := Color(0.02, 0.02, 0.024, 0.92)
	for y in h:
		for x in w:
			var d := _edge(x, y, w, h)
			var c := bg
			if d == 0:
				if focused:
					c = GOLD
				else:
					c = Color(0, 0, 0, 1) if _lit(x, y, w, h, d) else METAL.darkened(0.2)
			elif d == 1:
				c = Color(0.0, 0.0, 0.0, 0.8) if _lit(x, y, w, h, d) else bg
				if focused:
					c = Color(GOLD, 0.25)
			img.set_pixel(x, y, c)
	return img


## Slot d'objet/compétence : carré noir en creux cerclé d'un fin filet métal.
func _slot_image(highlight: bool) -> Image:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var bg := Color(0.075, 0.075, 0.08, 0.92).lerp(Color(0.02, 0.02, 0.022, 0.92), float(y) / float(h - 1))
		for x in w:
			var d := _edge(x, y, w, h)
			var c := bg
			match d:
				0:
					c = Color(0, 0, 0, 0.95)
				1:
					if highlight:
						c = GOLD_BRIGHT if _lit(x, y, w, h, d) else GOLD
					else:
						c = METAL.darkened(0.55) if _lit(x, y, w, h, d) else METAL_LIGHT.darkened(0.15)
				2:
					c = Color(0, 0, 0, 0.8)
			img.set_pixel(x, y, c)
	return img


## Bouton "pierre et bronze" : dégradé vertical avec reflet brillant sur la moitié haute,
## liseré sombre et biseau clair en haut à gauche, coins légèrement écornés.
func _button_image(state: String) -> Image:
	var w := 16
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top: Color
	var bottom: Color
	var border: Color
	var bevel_light: Color
	match state:
		"hover":
			top = Color(0.50, 0.45, 0.35)
			bottom = Color(0.22, 0.20, 0.16)
			border = GOLD
			bevel_light = Color(0.85, 0.76, 0.55)
		"pressed":
			top = Color(0.12, 0.11, 0.09)
			bottom = Color(0.27, 0.245, 0.20)
			border = Color(0.62, 0.52, 0.32)
			bevel_light = Color(0.10, 0.09, 0.08)
		"disabled":
			top = Color(0.20, 0.20, 0.19)
			bottom = Color(0.11, 0.11, 0.105)
			border = Color(0.05, 0.05, 0.05)
			bevel_light = Color(0.27, 0.27, 0.26)
		_:
			top = Color(0.38, 0.345, 0.28)
			bottom = Color(0.15, 0.135, 0.11)
			border = Color(0.04, 0.035, 0.03)
			bevel_light = Color(0.62, 0.56, 0.43)
	for y in h:
		var ty := float(y) / float(h - 1)
		var fill := top.lerp(bottom, ty)
		if state != "pressed" and ty < 0.45:
			fill = fill.lightened(0.10 * (1.0 - ty / 0.45))
		for x in w:
			var d := _edge(x, y, w, h)
			var c := fill
			if d == 0:
				c = border
				var is_corner := (x == 0 or x == w - 1) and (y == 0 or y == h - 1)
				if is_corner:
					c = Color(0, 0, 0, 0)
			elif d == 1:
				c = bevel_light if _lit(x, y, w, h, d) else fill.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


## Onglet : coins supérieurs écornés, bord inférieur ouvert s'il est sélectionné.
func _tab_image(selected: bool, hovered: bool) -> Image:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color(0.30, 0.28, 0.23, 0.95) if selected else (Color(0.16, 0.155, 0.14, 0.9) if hovered else Color(0.09, 0.09, 0.085, 0.88))
	var bottom := Color(0.12, 0.11, 0.095, 0.95) if selected else Color(0.04, 0.04, 0.04, 0.88)
	var border := METAL_LIGHT if selected else (METAL if hovered else METAL.darkened(0.35))
	for y in h:
		var fill := top.lerp(bottom, float(y) / float(h - 1))
		for x in w:
			var c := fill
			var on_side := x == 0 or x == w - 1
			if (x == 0 or x == w - 1) and y == 0:
				c = Color(0, 0, 0, 0)
			elif y == 0 or on_side:
				c = border
			elif y == h - 1 and not selected:
				c = METAL.darkened(0.2)
			elif y == 1 and selected:
				c = GOLD_BRIGHT.darkened(0.2)
			img.set_pixel(x, y, c)
	return img


func _bar_bg_image() -> Image:
	var w := 8
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := _edge(x, y, w, h)
			var c := Color(0.02, 0.02, 0.02, 0.85)
			if d == 0:
				c = Color(0, 0, 0, 1)
			elif d == 1 and _lit(x, y, w, h, d):
				c = Color(0, 0, 0, 0.9)
			img.set_pixel(x, y, c)
	return img


## Remplissage de barre : dégradé vertical, reflet clair sur la ligne du haut, ligne sombre
## en bas — l'effet "tube brillant" des jauges L2.
func _bar_fill_image(top: Color, bottom: Color) -> Image:
	var w := 6
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var ty := float(y) / float(h - 1)
		var c := top.lerp(bottom, ty)
		if ty < 0.35:
			c = c.lerp(Color.WHITE, 0.22 * (1.0 - ty / 0.35))
		for x in w:
			var px := c
			if y == 0:
				px = Color(0, 0, 0, 0)
			elif y == 1:
				px = top.lerp(Color.WHITE, 0.45)
			elif y == h - 1:
				px = Color(0, 0, 0, 0)
			elif y == h - 2:
				px = bottom.darkened(0.4)
			if x == 0 or x == w - 1:
				px = Color(0, 0, 0, 0) if (y == 0 or y == h - 1) else px.darkened(0.25)
			img.set_pixel(x, y, px)
	return img


## Croix de fermeture 12x12 anti-crénelée.
func _close_icon(color: Color) -> ImageTexture:
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var a := Vector2(2.5, 2.5)
	var b := Vector2(size - 2.5, size - 2.5)
	var c := Vector2(size - 2.5, 2.5)
	var d := Vector2(2.5, size - 2.5)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var dist := minf(_seg_dist(p, a, b), _seg_dist(p, c, d))
			var outline := clampf(2.4 - dist, 0.0, 1.0)
			var core := clampf(1.3 - dist, 0.0, 1.0)
			if outline > 0.0:
				var col := Color(0, 0, 0, outline).lerp(Color(color, 1.0), core)
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Petit triangle plein (haut/bas), pour les barres de défilement/SpinBox/listes.
func _arrow_icon(size: int, up: bool, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := size / 2.0
	for y in size:
		for x in size:
			var fy := (y + 0.5) / size
			var t := (1.0 - fy) if not up else fy
			var width := t * half * 0.95
			var dx: float = abs(x + 0.5 - half)
			if fy > 0.2 and fy < 0.8 and dx <= width * 1.25 - 0.5:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


func _side_arrow_icon(size: int, left: bool, color: Color) -> ImageTexture:
	var img := _arrow_icon(size, left, color).get_image()
	img.rotate_90(COUNTERCLOCKWISE)
	return ImageTexture.create_from_image(img)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var hh := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * hh).length()


# ---------------------------------------------------------------------------
# Fond des écrans hors-jeu
# ---------------------------------------------------------------------------

## Château au clair de lune survolé par un dragon (licence Pixabay Content License, voir
## res://Backgrounds/), fond des écrans connexion/sélection/création de personnage.
const HERO_BACKDROP_PATH := "res://Backgrounds/castle_dragon_moon.jpg"
var _hero_backdrop_texture: Texture2D


func get_hero_backdrop_texture() -> Texture2D:
	if _hero_backdrop_texture == null:
		_hero_backdrop_texture = load(HERO_BACKDROP_PATH)
	return _hero_backdrop_texture
