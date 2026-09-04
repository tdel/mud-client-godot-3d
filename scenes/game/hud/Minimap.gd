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
@onready var _map_name_label: Label = %MapNameLabel
@onready var _coords_label: Label = %CoordsLabel


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
