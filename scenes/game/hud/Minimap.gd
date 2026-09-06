extends Control
## Minimap ronde en haut à droite du HUD (voir Game3D._rebuild_map/_process) — le
## personnage reste FIXE au centre du disque, c'est la carte qui défile sous lui à mesure
## qu'il se déplace (retour explicite du 2026-09-03 : la toute première version affichait
## la carte entière avec un simple point mobile, sans "zoom" sur le personnage) — même
## principe que la minimap de la plupart des MMO (L2 compris).
##
## Réutilise directement la texture de sol déjà construite par
## ZoneAssets3D.build_ground_texture (voir Game3D._rebuild_map) plutôt que d'en régénérer
## une dédiée — mêmes couleurs de terrain, un seul point de génération — %MapLayer se
## contente de l'étirer à l'échelle de zoom voulue (voir PIXELS_PER_TILE) et de la faire
## glisser sous un disque fixe.
##
## Le disque (fond + carte qui défile + point du joueur) est rendu dans un SubViewport de
## taille FIXE (168x168, voir %CircleViewport dans Minimap.tscn) plutôt que composé
## directement dans le Control parent : un SubViewport agit comme une vraie "caméra" sur
## cette zone — tout ce qui dépasse ses bornes est simplement non rendu, quelle que soit la
## taille réelle de %MapLayer (qui, lui, peut largement dépasser 168x168 une fois mis à
## l'échelle de zoom, voir PIXELS_PER_TILE). Un CanvasGroup a été essayé en premier
## (fusionner les enfants dans un tampon post-traité par un shader canvas_item) mais s'est
## révélé inutilisable ici : sa taille de tampon suit les bornes RÉELLES (non écrêtées) de
## ses enfants, donc grandissait avec le défilement de %MapLayer — la minimap gonflait alors
## en un énorme disque blanc au lieu de rester un petit cercle fixe (constaté visuellement
## via une capture d'écran de test, corrigé en passant à ce SubViewport). Le
## SubViewportContainer (%CircleViewportContainer) affiche ensuite ce rendu à travers le
## même shader de découpe circulaire + bandeau doré.

## Diamètre à l'écran du disque de minimap, en pixels.
const CIRCLE_SIZE := 168.0

## Nombre de tuiles visibles sur le diamètre du disque — choisi égal à la portée de
## perception serveur (AWARENESS_RANGE, voir CLAUDE.md, session EntityAppeared/
## EntityDisappeared du 2026-09-03) : la minimap montre ainsi exactement la zone dans
## laquelle une entité peut nous être signalée, plutôt qu'un rayon de zoom arbitraire.
const VISIBLE_TILES_DIAMETER := 40.0
const PIXELS_PER_TILE := CIRCLE_SIZE / VISIBLE_TILES_DIAMETER

const RING_COLOR := Color(0.72, 0.58, 0.28, 1.0)

## Points de connaissance (%EntityDots, voir set_known_entities) — monstres/PNJ/autres
## joueurs de la KnownList affichés sur le disque, le joueur restant lui le point bleu
## central fixe (%PlayerDot, voir PlayerDot dans Minimap.tscn).
const MONSTER_DOT_RADIUS := 2.5
const NPC_DOT_RADIUS := 2.5
const PLAYER_DOT_RADIUS := 2.5
const MONSTER_DOT_COLOR := Color(0.9, 0.15, 0.1, 1.0)
const NPC_DOT_COLOR := Color(0.05, 0.05, 0.05, 1.0)
## Joueur hors groupe : blanc. Membre du groupe (party) : jaune, pour le repérer d'un
## coup d'œil pendant un combat de groupe.
const OTHER_PLAYER_DOT_COLOR := Color(0.95, 0.95, 0.95, 1.0)
const PARTY_MEMBER_DOT_COLOR := Color(0.95, 0.85, 0.25, 1.0)
const SELECTION_RING_RADIUS := 5.0
const SELECTION_RING_WIDTH := 1.2
const SELECTION_RING_COLOR := Color(1.0, 1.0, 1.0, 1.0)

const CIRCLE_MASK_SHADER_CODE := """
shader_type canvas_item;

uniform vec4 ring_color : source_color = vec4(0.72, 0.58, 0.28, 1.0);

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(centered);
	if (dist > 1.0) {
		discard;
	}
	vec4 tex_color = texture(TEXTURE, UV);
	float ring_mix = smoothstep(0.90, 1.0, dist);
	COLOR = mix(tex_color, ring_color, ring_mix);
}
"""

@onready var _circle_container: SubViewportContainer = %CircleViewportContainer
@onready var _map_layer: TextureRect = %MapLayer
@onready var _entity_dots: Control = %EntityDots
@onready var _map_name_label: Label = %MapNameLabel
@onready var _coords_label: Label = %CoordsLabel

var _player_tile_pos := Vector2.ZERO
var _monster_tile_positions: Array[Vector2] = []
var _npc_tile_positions: Array[Vector2] = []
var _other_player_tile_positions: Array[Vector2] = []
var _party_member_tile_positions: Array[Vector2] = []
## Position tuile du monstre sélectionné, null si aucun monstre n'est sélectionné (voir
## set_known_entities, appelé depuis Game3D._update_minimap).
var _selected_monster_tile_pos = null


func _ready() -> void:
	var shader := Shader.new()
	shader.code = CIRCLE_MASK_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ring_color", RING_COLOR)
	_circle_container.material = mat

	# expand_mode=IGNORE_SIZE : autorise à donner à %MapLayer une taille arbitraire (le
	# zoom voulu) indépendante de la résolution native de la texture de sol assignée par
	# set_map (PX_PER_TILE=4, voir ZoneAssets3D) ; stretch_mode=SCALE l'étire pour
	# remplir exactement cette taille.
	_map_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_layer.stretch_mode = TextureRect.STRETCH_SCALE
	_map_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_entity_dots.draw.connect(_on_entity_dots_draw)


## Appelé par Game3D._rebuild_map à chaque nouvelle carte/changement de carte.
func set_map(ground_texture: Texture2D, map_width: int, map_height: int, map_name: String) -> void:
	_map_name_label.text = map_name
	_map_layer.texture = ground_texture
	_map_layer.size = Vector2(maxi(map_width, 1), maxi(map_height, 1)) * PIXELS_PER_TILE


## Appelé par Game3D._process à chaque frame avec la position tuile courante du joueur —
## recentre la carte sous le disque fixe plutôt que de déplacer un point sur une carte fixe
## (voir en-tête de fichier : le joueur reste toujours au centre du disque).
func set_player_tile_position(x: float, z: float) -> void:
	_map_layer.position = Vector2(CIRCLE_SIZE, CIRCLE_SIZE) / 2.0 - Vector2(x, z) * PIXELS_PER_TILE
	_coords_label.text = "%.1f, %.1f" % [x, z]
	_player_tile_pos = Vector2(x, z)
	_entity_dots.queue_redraw()


## Appelé par Game3D._update_minimap à chaque frame avec les monstres/PNJ/autres joueurs
## actuellement dans la KnownList (voir Game3D._entities_by_key/EntityAppeared) — monstre en
## point rouge, PNJ en point noir, autre joueur en point blanc (jaune s'il est dans notre
## groupe, voir GameState.party), selected_monster_tile_pos (null si aucun monstre sélectionné)
## entoure le point rouge correspondant d'un petit trait.
func set_known_entities(
	monster_tile_positions: Array[Vector2],
	npc_tile_positions: Array[Vector2],
	other_player_tile_positions: Array[Vector2],
	party_member_tile_positions: Array[Vector2],
	selected_monster_tile_pos
) -> void:
	_monster_tile_positions = monster_tile_positions
	_npc_tile_positions = npc_tile_positions
	_other_player_tile_positions = other_player_tile_positions
	_party_member_tile_positions = party_member_tile_positions
	_selected_monster_tile_pos = selected_monster_tile_pos
	_entity_dots.queue_redraw()


func _on_entity_dots_draw() -> void:
	var center := Vector2(CIRCLE_SIZE, CIRCLE_SIZE) / 2.0
	for tile_pos in _npc_tile_positions:
		var screen_pos := center + (tile_pos - _player_tile_pos) * PIXELS_PER_TILE
		_entity_dots.draw_circle(screen_pos, NPC_DOT_RADIUS, NPC_DOT_COLOR)
	for tile_pos in _other_player_tile_positions:
		var screen_pos := center + (tile_pos - _player_tile_pos) * PIXELS_PER_TILE
		_entity_dots.draw_circle(screen_pos, PLAYER_DOT_RADIUS, OTHER_PLAYER_DOT_COLOR)
	for tile_pos in _party_member_tile_positions:
		var screen_pos := center + (tile_pos - _player_tile_pos) * PIXELS_PER_TILE
		_entity_dots.draw_circle(screen_pos, PLAYER_DOT_RADIUS, PARTY_MEMBER_DOT_COLOR)
	for tile_pos in _monster_tile_positions:
		var screen_pos := center + (tile_pos - _player_tile_pos) * PIXELS_PER_TILE
		_entity_dots.draw_circle(screen_pos, MONSTER_DOT_RADIUS, MONSTER_DOT_COLOR)
	if _selected_monster_tile_pos != null:
		var selected_screen_pos: Vector2 = center \
				+ (_selected_monster_tile_pos - _player_tile_pos) * PIXELS_PER_TILE
		_entity_dots.draw_arc(
			selected_screen_pos, SELECTION_RING_RADIUS, 0.0, TAU, 24,
			SELECTION_RING_COLOR, SELECTION_RING_WIDTH, true
		)
