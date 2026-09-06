extends Node3D
## Prototype 3D isométrique du client mud-godot (protocole réseau documenté en commentaires
## dans autoload/Net.gd — voir son en-tête pour le format stateless actuel).
##
## Caméra isométrique fixe, sol/obstacles générés depuis les mêmes .tmx que le client 2D,
## déplacement au clic (un clic = une demande de déplacement), entités (joueurs/PNJ/monstres) visibles et
## animées en position/orientation, chat de zone, sélection de cible, attaque, sorts
## (incantation/projectile/impact), hotbar/inventaire/équipement/fiche de personnage (voir
## scenes/game/hud/), portails, dialogue PNJ (%DialogueWindow), cycle jour/nuit avec
## trajectoire soleil/lune est-ouest et lumières nocturnes procédurales
## (_apply_day_night_preset/_animate_day_night/_update_celestial_lights), mort/respawn
## (%DeathPopup).
##
## PAS dans ce prototype : groupe, sous-classe. Les entités restent de simples capsules
## colorées — pas de rig/squelette/attach points d'équipement.

const WORLD_UP := Vector3.UP
const DEFAULT_SPEED_TILES_PER_SEC := 2.4
const CAMERA_DISTANCE := 20.0
const CAMERA_SIZE_MIN := 6.0
const CAMERA_SIZE_MAX := 30.0
const CAMERA_ZOOM_STEP := 1.5
## Maintenir le clic droit (sans bouger la souris) au-delà de ce délai bascule en mode
## "rotation de caméra" (voir _start_right_click_hold/_process) plutôt que d'ouvrir le menu
## contextuel du portail sélectionné (_handle_right_click, toujours déclenché sur un clic
## droit BREF, comme avant cette fonctionnalité). Assez court pour ne pas sembler mou au
## clic, assez long pour ne jamais se déclencher sur un simple clic. Abaissé de 180 à 80 le
## 2026-09-03 (retour explicite : 180 semblait trop long avant de basculer en rotation).
const CAMERA_ROTATE_HOLD_THRESHOLD_MS := 80.0
## Radians de rotation caméra par pixel de déplacement souris pendant le mode rotation.
## Abaissé de 0.01 à 0.004 le 2026-09-03 (retour explicite : la rotation tournait trop vite).
const CAMERA_ROTATE_SENSITIVITY := 0.004
## Vitesse (par seconde) de rattrapage de l'angle affiché (_camera_yaw) vers l'angle brut
## accumulé depuis la souris (_camera_yaw_target, voir _process/_unhandled_input) — plus
## haut = rattrapage plus rapide/moins de latence perçue, plus bas = plus "smooth"/inertiel.
## Formule de lissage exponentiel indépendante du framerate (`1 - exp(-k*delta)`), pas un
## simple `delta * k` qui dépendrait de la fréquence d'images.
const CAMERA_ROTATE_SMOOTHING := 14.0
const POSITION_QUERY_INTERVAL_SEC := 1.0
const POSITION_CORRECTION_DEADZONE := 0.6

const PLAYER_COLOR := Color(0.35, 0.65, 0.95)
const OTHER_PLAYER_COLOR := Color(0.30, 0.80, 0.55)
const MONSTER_COLOR := Color(0.85, 0.30, 0.28)
const NPC_COLOR := Color(0.85, 0.75, 0.30)
## Bleu façon "portail d'énergie" (au lieu du violet précédent) — voir _make_portal_node,
## qui recouvre désormais l'ancien disque plat au sol d'un anneau vertical + tourbillon
## animé, demande explicite du 2026-09-06 pour se rapprocher d'un portail bleu tourbillonnant
## façon jeu vidéo plutôt qu'un simple disque plat coloré.
const PORTAL_COLOR := Color(0.25, 0.55, 0.95)
## Cœur clair et bord profond du tourbillon (voir PORTAL_VORTEX_SHADER_CODE) — dégradé
## indépendant de PORTAL_COLOR (qui reste la teinte de l'anneau/halo/étiquette) pour un effet
## plus riche qu'une simple couleur unie.
const PORTAL_CORE_COLOR := Color(0.78, 0.95, 1.0)
const PORTAL_EDGE_COLOR := Color(0.05, 0.18, 0.65)
## Hauteur du centre de l'anneau vertical au-dessus du sol.
const PORTAL_RING_HEIGHT_Y := 1.05
const PORTAL_RING_INNER_RADIUS := 0.68
const PORTAL_RING_OUTER_RADIUS := 0.88
## Titre optionnel (EntityView.title / GamePlayerStats.Payload.title côté backend, ex. fonction
## d'un PNJ comme "Blacksmith") affiché au-dessus du nom, voir TITLE_LABEL_OFFSET_Y. Vert saturé
## volontairement plus soutenu que OTHER_PLAYER_COLOR (0.30, 0.80, 0.55, très clair une fois
## éclairci par `lightened(0.5)` pour le nom des autres joueurs) pour rester lisible sans être
## fade — couleur "titre" classique de RPG (vert distinct du blanc du nom).
const TITLE_LABEL_COLOR := Color(0.15, 0.85, 0.25)
const SELECTION_COLOR := Color(0.92, 0.20, 0.16)

## Lueur d'arme sur la consommation d'un soulshot/spiritshot (voir _flash_entity, réutilisé
## avec une durée plus longue que le flash de dégâts pour rester bien visible) — orange pour
## le soulshot (physique), cyan pour le spiritshot (magique, cohérent avec CAST_BAR_COLOR déjà
## bleu). Déclenché par ShotUsed (nous-même) et SoulshotUsed/SpiritshotUsed (les autres,
## diffusés à toute la zone sauf à l'auteur — voir commit backend "Ajoute le système
## soulshot/spiritshot" du 2026-09-04).
const SOULSHOT_GLOW_COLOR := Color(1.0, 0.55, 0.15)
const SPIRITSHOT_GLOW_COLOR := Color(0.3, 0.85, 1.0)
const SHOT_GLOW_UP_DURATION := 0.1
const SHOT_GLOW_DOWN_DURATION := 0.35

## Cycle jour/nuit (voir TimeEngine côté backend, commit "Ajoute un cycle jour/nuit
## in-game" du 2026-09-05) : 24h in-game = 8h réelles, aube 7h-8h, crépuscule 21h-22h
## (GameClock). Le serveur ne pousse pas de tick régulier — seulement GameTimeSync au
## login (resynchronisation immédiate, voir _day_night_t_for_time) et Sunrise/Sunset aux
## deux transitions (animées sur transitionDurationMs, voir _animate_day_night). Les
## valeurs DAY_* reprennent telles quelles le sub_resource Environment/Sun par défaut de
## Game.tscn (c'était jusqu'ici la seule ambiance possible).
const DAWN_START_MIN := 7 * 60
const DAWN_END_MIN := 8 * 60
const DUSK_START_MIN := 21 * 60
const DUSK_END_MIN := 22 * 60
const NIGHT_BACKGROUND_COLOR := Color(0.04, 0.05, 0.11, 1.0)
const NIGHT_AMBIENT_COLOR := Color(0.16, 0.18, 0.30, 1.0)
const NIGHT_AMBIENT_ENERGY := 0.22
const NIGHT_SUN_ENERGY := 0.05
const NIGHT_SUN_COLOR := Color(0.55, 0.60, 0.85, 1.0)
const DAY_BACKGROUND_COLOR := Color(0.29, 0.33, 0.40, 1.0)
const DAY_AMBIENT_COLOR := Color(0.55, 0.58, 0.65, 1.0)
const DAY_AMBIENT_ENERGY := 0.7
const DAY_SUN_ENERGY := 1.15
const DAY_SUN_COLOR := Color(1.0, 0.96, 0.88, 1.0)

## En-dessous de cette énergie, une lumière directionnelle n'apporte plus rien de visible :
## on coupe alors son ombre (shadow_enabled) plutôt que de payer une passe d'ombre pour un
## astre quasi éteint (le Soleil la nuit, la Lune en plein jour, voir _apply_day_night_preset).
const MIN_SHADOW_LIGHT_ENERGY := 0.03

## Éclairage de la lune : blanc légèrement bleuté, nettement plus faible que le soleil (elle
## n'a pas d'équivalent DAY_*/NIGHT_* — elle est éteinte en plein jour et à pleine énergie en
## pleine nuit, voir _apply_day_night_preset). Sa couleur est fixée une fois pour toutes sur
## le node Moon (Game.tscn), seule son énergie varie ici.
const MOON_MAX_ENERGY := 0.35

## Simule côté client une horloge in-game continue (le serveur ne pousse qu'un GameTimeSync
## ponctuel au login, voir plus haut) pour faire avancer Soleil/Lune image par image plutôt
## que de les figer entre deux resynchronisations. 24h in-game = 8h réelles (voir plus haut).
const IN_GAME_MINUTES_PER_REAL_SECOND := 1440.0 / (8.0 * 3600.0)

## Élévation maximale (degrés) atteinte par le Soleil/la Lune à leur zénith de trajectoire —
## volontairement un peu sous 90° (plutôt que droit au-dessus) pour garder une direction
## d'ombre visible même en milieu de course, voir _celestial_direction.
const CELESTIAL_MAX_ELEVATION_DEG := 78.0

## Hauteur (mètres) des petites lumières de ville procédurales posées sur les cases de
## terrain remarquables ci-dessous — hauteur de lanterne/torchère, voir _rebuild_night_lights.
const NIGHT_LIGHT_HEIGHT := 1.6

## Terrain .tmx (voir ZoneAssets3D.TERRAIN_COLORS) -> lumière de ville posée la nuit sur
## chaque groupe de cases contigües de ce terrain (fontaine, auberge, forge : les points
## d'intérêt d'un village où l'on s'attend à voir une lanterne/un brasero). Purement cosmétique
## et indépendant du gameplay, au même titre que ZoneAssets3D.obstacle_height_for. Couleur
## reprise en plus chaud/saturé que TERRAIN_COLORS (pensée pour une texture de sol en plein
## jour, pas pour une source de lumière nocturne).
const LANDMARK_LIGHTS := {
	"fountain": {"color": Color(0.55, 0.85, 1.0), "energy": 1.4, "range": 6.0},
	"auberge": {"color": Color(1.0, 0.72, 0.35), "energy": 1.1, "range": 5.0},
	"forge": {"color": Color(1.0, 0.55, 0.25), "energy": 1.1, "range": 4.5},
}

## Couleurs des lignes de journal de combat/progression (voir les _log_* plus bas), reprises
## telles quelles de mud-godot/scenes/game/hud/ChatOverlay.gd pour un rendu identique — la
## zone de chat 3D n'affichait jusqu'ici (2026-09-03) qu'une poignée de messages (chat/erreur/
## zone paisible), très en retrait du 2D qui logue aussi combat/XP/loot/mort/groupe.
const LOG_COLOR_DAMAGE_OUT := "#e0a050"
const LOG_COLOR_DAMAGE_IN := "#e0705a"
const LOG_COLOR_HEAL := "#7fd18a"
const LOG_COLOR_XP := "#8fb8e0"
const LOG_COLOR_LOOT := "#d8c26a"
const LOG_COLOR_DEFEAT := "#9a9488"
const LOG_COLOR_PEACE := "#7fb0d1"

const PLAYER_KEY := "player"

## Rayon du halo au sol marquant la zone d'activation du portail (voir _make_portal_node) —
## sert uniquement de repère visuel désormais : la sélection au clic passe par un vrai rayon
## physique 3D sur tout l'objet (voir PORTAL_PICK_COLLISION_LAYER/_pick_portal_id_at_mouse),
## comme pour les entités, depuis la demande explicite du 2026-09-06 ("je veux que l'objet
## entier soit sélectionnable, pas juste la base").
const PORTAL_PICK_RADIUS := 0.7

## Nom/titre par défaut si le serveur ne les transmet pas encore (PortalView.name/title, voir
## _apply_appeared_portal) — même dégradation gracieuse que targetMapName ci-dessous.
const PORTAL_NAME_DEFAULT := "Clairière"
const PORTAL_TITLE_DEFAULT := "Téléporteur"
## Portée de téléportation si le serveur ne transmet pas triggerRadius — reprend PORTAL_PICK_RADIUS
## (même rayon que le halo au sol, cohérent avec l'ancienne zone d'activation).
const PORTAL_RANGE_DEFAULT := PORTAL_PICK_RADIUS

## Sélectionner une entité ou un portail se fait par un vrai rayon physique caméra→souris
## contre sa zone de collision (voir _pick_entity_id_at_mouse/_make_entity_node pour les
## entités, _pick_portal_id_at_mouse/_make_portal_node pour les portails), pas par une
## projection au sol : une capsule mesure 1.6 unité de haut et un portail se dresse jusqu'à
## ~2 unités, tous deux vus depuis un angle par la caméra isométrique — cliquer sur leur haut
## visible projetterait, sur le plan y=0, un point bien au-delà de leur base (bug signalé le
## 2026-09-02 pour les entités : le clic "passait à travers" le sprite). Deux couches
## physiques dédiées (aucune autre collision 3D dans ce prototype, voir CLAUDE.md : "pas de
## physique 3D" pour le déplacement) pour que chaque requête n'accroche jamais que le type de
## cible voulu.
const ENTITY_PICK_COLLISION_LAYER := 1 << 5
const PORTAL_PICK_COLLISION_LAYER := 1 << 6
const ENTITY_PICK_RAY_LENGTH := 1000.0

## Barres flottantes génériques (vie/incantation), voir _make_floating_bar. Toutes deux
## réagrandies le 2026-09-03 (encore signalées trop petites, vie y compris cette fois) en
## se calant sur la taille réelle du nom flottant : `Label3D.get_aabb()` mesuré en isolation
## dans ce projet donne une hauteur de 0.825 unité pour NameLabel.font_size=120 (voir
## NAME_LABEL_OFFSET_Y plus bas pour le calcul complet de l'empilement vertical).
const BAR_WIDTH := 1.1
const BAR_HEIGHT := 0.22
## Redimensionnée en petit format le 2026-09-03 (troisième passe) : la barre d'incantation
## agrandie deux fois de suite (2026-09-02 puis plus tôt le 2026-09-03) a fini par être jugée
## trop sombre plutôt que trop petite — voir CAST_BAR_COLOR/CAST_BAR_BG_COLOR juste en dessous
## et _make_rounded_progress_bar pour le rendu (pilule bleue pleine, sans transparence).
const CAST_BAR_WIDTH := 0.9
const CAST_BAR_HEIGHT := 0.2
const HP_BAR_OFFSET_Y := 1.85
const CAST_BAR_OFFSET_Y := 2.35
const HP_BAR_COLOR := Color(0.75, 0.15, 0.15)
const HP_BAR_BG_COLOR := Color(0.05, 0.05, 0.05, 0.85)
## Remplacée le 2026-09-03 (troisième passe) par une vraie pilule aux bords arrondis rendue
## via shader (_make_rounded_progress_bar) plutôt que les deux quads plats fond+remplissage
## de _make_floating_bar : fond bleu nuit OPAQUE (alpha=1, plus de flou de transparence qui
## la faisait paraître trop sombre sur le fond du monde) + remplissage bleu vif émissif.
const CAST_BAR_COLOR := Color(0.3, 0.6, 1.0)
const CAST_BAR_BG_COLOR := Color(0.08, 0.22, 0.5, 1.0)

const DAMAGE_NUMBER_RISE := 0.8
const DAMAGE_NUMBER_DURATION := 0.9
const DAMAGE_NUMBER_FADE_START := 0.45
const DAMAGE_NUMBER_COLOR_NORMAL := Color(1.0, 1.0, 1.0)
const DAMAGE_NUMBER_COLOR_CRITICAL := Color(1.0, 0.88, 0.15)

const MONSTER_DEATH_GREY_DELAY := 0.5
const MONSTER_DEATH_FADE_DURATION := 0.6
const MONSTER_DEATH_GREY_COLOR := Color(0.42, 0.42, 0.42)

## Catégorie visuelle par sort (voir _play_skill_animation/_play_skill_projectile). Le
## protocole ne transmet ni élément ni type de dégât en détail — voir le catalogue
## mud-server-java/src/main/resources/data/skills/skills.json ; un sort absent de cette
## table retombe sur un projectile arcane neutre. Couleurs unies plutôt que textures (pas
## d'art directionnel disponible dans ce prototype, voir _make_entity_node).
enum SkillVisualKind { FIRE, FROST, STORM, HOLY, DARK, ARCANE, HEAL, BUFF, DEBUFF }
const SKILL_VISUAL_KIND_DEFAULT := SkillVisualKind.ARCANE
const SKILL_VISUAL_KIND_BY_NAME := {
	"Flame Strike": SkillVisualKind.FIRE, "Prominence": SkillVisualKind.FIRE,
	"Aqua Strike": SkillVisualKind.FROST,
	"Wind Strike": SkillVisualKind.STORM, "Twister": SkillVisualKind.STORM,
	"Solar Strike": SkillVisualKind.HOLY,
	"Death Spike": SkillVisualKind.DARK,
	"Heal": SkillVisualKind.HEAL, "Mass Heal": SkillVisualKind.HEAL,
	"Might": SkillVisualKind.BUFF, "Focus": SkillVisualKind.BUFF, "Empower": SkillVisualKind.BUFF,
	"Rage": SkillVisualKind.BUFF, "Guidance": SkillVisualKind.BUFF, "Bulwark": SkillVisualKind.BUFF,
	"Curse: Doom": SkillVisualKind.DEBUFF, "Curse: Weakness": SkillVisualKind.DEBUFF,
}
const SKILL_VISUAL_COLOR_BY_KIND := {
	SkillVisualKind.FIRE: Color(1.0, 0.55, 0.25),
	SkillVisualKind.FROST: Color(0.55, 0.85, 1.0),
	SkillVisualKind.STORM: Color(1.0, 0.92, 0.35),
	SkillVisualKind.HOLY: Color(1.0, 0.97, 0.80),
	SkillVisualKind.DARK: Color(0.45, 0.15, 0.55),
	SkillVisualKind.ARCANE: Color(0.65, 0.55, 1.0),
	# Jaune chaud (demande explicite du 2026-09-03, confirmée le 2026-09-06 pour les nouveaux
	# effets dédiés — voir _play_heal_cast_effect/_play_heal_target_effect plus bas).
	SkillVisualKind.HEAL: Color(1.0, 0.92, 0.35),
	SkillVisualKind.BUFF: Color(1.0, 0.88, 0.45),
	SkillVisualKind.DEBUFF: Color(0.55, 0.25, 0.75),
}
## Sorts à dégâts sans projectile (portée "toucher" côté backend) : flash direct plutôt
## qu'un projectile lancé, voir _play_skill_animation.
const NON_PROJECTILE_DAMAGE_SKILLS := ["Twister", "Prominence"]

## Sorts affichant une petite animation pendant l'incantation elle-même (pas seulement à
## l'impact, voir _play_skill_animation/_play_skill_projectile) — voir _spawn_wind_wisp,
## déclenché depuis _advance_casting tant que le sort est dans _casting_by_key. Heal utilisait
## ce même souffle tourbillonnant (recoloré en jaune) jusqu'au 2026-09-06, remplacé depuis par
## un effet au sol dédié à l'entrée en incantation, voir _on_skill_cast_started/
## _play_heal_cast_effect — Wind Strike reste seul ici.
const WIND_CAST_ANIMATION_SKILLS := ["Wind Strike"]
const WIND_WISP_SPAWN_INTERVAL_MS := 110.0
const WIND_WISP_RISE_HEIGHT := 1.5
const WIND_WISP_DURATION := 0.55
const WIND_WISP_COLOR := Color(0.75, 0.95, 0.85, 0.65)
## Rayon d'apparition des souffles autour du lanceur : au-delà du rayon de la capsule
## (0.35, voir _make_entity_node) pour qu'ils l'entourent visiblement plutôt que de partir
## de son centre (donc de sembler "passer à travers" le corps).
const WIND_WISP_RADIUS_MIN := 0.45
const WIND_WISP_RADIUS_MAX := 0.75
const WIND_WISP_SIZE := Vector2(0.24, 0.5)

## Effet de soin dédié (demande du 2026-09-06) — voir _play_heal_cast_effect (au sol, au début
## de l'incantation) et _play_heal_target_effect (autour de la cible, à l'impact).
const HEAL_CAST_BURST_LIFETIME := 0.9
const HEAL_CAST_BURST_AMOUNT := 26
const HEAL_CAST_FLARE_HEIGHT := 1.6
const HEAL_CAST_FLARE_DURATION := 0.7
const HEAL_TARGET_EFFECT_DURATION := 2.6
const HEAL_TARGET_PARTICLE_AMOUNT := 30

@onready var _world: Node3D = $World
@onready var _ground: MeshInstance3D = $World/Ground
@onready var _obstacles: MultiMeshInstance3D = $World/Obstacles
@onready var _entities_root: Node3D = $World/Entities
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _minimap: Control = %Minimap
@onready var _player_frame: Control = %PlayerFrame
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _chat_input: LineEdit = %ChatInput
@onready var _target_status_bar: Control = %TargetStatusBar
@onready var _npc_menu: PopupMenu = %NpcMenu
@onready var _death_popup: Control = %DeathPopup
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _moon: DirectionalLight3D = $Moon
@onready var _night_lights: Node3D = $World/NightLights

var _player_node: Node3D
var _current_map_name := ""
var _map_width := 0
var _map_height := 0
var _walkable_rows: Array = []

## Toutes les entités (joueur compris, sous la clé PLAYER_KEY) sont traitées de façon
## générique par _step_movement : key -> Node3D / {"target": Vector3} / vitesse (tuiles/s).
var _entities_by_key: Dictionary = {}
var _key_by_entity_id: Dictionary = {}
var _entity_speed_by_key: Dictionary = {}
var _moving: Dictionary = {}
## Vie/niveau courants de chaque entité connue, indexés par la même clé que
## _entities_by_key : {current, max, level}. Alimenté par EntityAppeared (voir
## _apply_appeared_entity) quand ces champs sont présents, et par
## AttackResult/CastResult/SkillCastAnnounced ensuite.
var _entity_vitals_by_key: Dictionary = {}
## Barres flottantes (vie + incantation) par entité, voir _ensure_bars/_make_floating_bar.
var _entity_bars_by_key: Dictionary = {}
## Incantations en cours, indexées par la même clé que _entities_by_key :
## {elapsed_ms, total_ms}. Alimenté par SkillCastStarted, vidé par SkillCastCancelled/
## SkillFizzled ou par expiration locale du délai (voir _process).
var _casting_by_key: Dictionary = {}

## UUID de l'entité actuellement sélectionnée ("" si aucune) — seule source de vérité pour
## F1-F12 (Hotbar.gd envoie attack/cast sans UUID de cible, résolus côté serveur sur la
## cible de combat courante).
var _selected_target_id := ""
var _selection_ring: MeshInstance3D

## Portails actuellement à portée de perception (KnownList côté backend, voir CLAUDE.md),
## indexés par UUID de portail — poussés séparément de MapView par PortalAppeared/
## PortalDisappeared, exactement comme _entities_by_key l'est par EntityAppeared/
## EntityDisappeared (voir _apply_appeared_portal/_on_portal_disappeared). Contrairement aux
## autres entités, ils ne sont pas mélangés dans _entities_by_key : un portail se sélectionne
## au clic gauche mais ne se cible jamais côté serveur (pas d'UUID transmis, "portal" ne prend
## aucun argument — le serveur se base sur la position courante du joueur). Dictionnaire
## {id: {position: Vector2, target_map_name, portal_name, portal_title, range, node}}.
var _portals: Dictionary = {}
var _selected_portal_id := ""

## Cercle de portée affiché autour du joueur au survol d'un sort en hotbar (voir
## show_skill_range/hide_skill_range, appelés par Hotbar.gd).
var _range_indicator: MeshInstance3D

var _move_marker: MeshInstance3D
var _camera_size := 16.0
var _position_query_timer := 0.0

## Voir _start_right_click_hold/_end_right_click_hold/_apply_camera_orbit :
## _right_click_active suit le bouton droit de la souris pressé, _camera_orbiting ne
## devient vrai qu'après CAMERA_ROTATE_HOLD_THRESHOLD_MS de maintien (voir _process) —
## c'est cette transition qui distingue un clic droit bref (menu de téléportation) d'un
## maintien (rotation caméra). _camera_yaw_target est l'angle brut accumulé directement
## depuis les mouvements de souris (voir _unhandled_input) ; _camera_yaw est l'angle
## réellement affiché, qui rattrape _camera_yaw_target en douceur chaque frame (voir
## _process, CAMERA_ROTATE_SMOOTHING) plutôt que de le suivre au pixel près — c'est ce qui
## rend la rotation "smooth" plutôt que de coller instantanément à la souris. Les deux sont
## des angles autour de l'axe Y par rapport à la direction isométrique par défaut (1,1,1).
## _right_click_press_screen_pos permet de replacer le curseur là où le clic droit a
## commencé une fois la rotation finie (la souris est capturée/invisible pendant la
## rotation, voir Input.mouse_mode).
var _right_click_active := false
var _right_click_started_at_ms := 0.0
var _camera_orbiting := false
var _camera_yaw := 0.0
var _camera_yaw_target := 0.0
var _right_click_press_screen_pos := Vector2.ZERO

## 0.0 = nuit pleine, 1.0 = jour plein — voir _apply_day_night_preset/_animate_day_night.
## Initialisé au jour pour matcher le sub_resource Environment par défaut de Game.tscn tant
## qu'aucun GameTimeSync n'est encore arrivé (juste après la connexion).
var _day_night_t := 1.0
var _day_night_tween: Tween

## Horloge in-game continue simulée côté client (minutes depuis minuit, 0.0-1440.0), voir
## IN_GAME_MINUTES_PER_REAL_SECOND/_advance_day_night_clock — pilote la position Soleil/Lune
## indépendamment de _day_night_t (qui ne pilote que les couleurs/énergies, resynchronisé/
## animé par GameTimeSync/Sunrise/Sunset). Défaut à 13h, cohérent avec _day_night_t=1.0
## ci-dessus (13h est en plein jour, avant tout GameTimeSync).
var _game_minutes_of_day := 13.0 * 60.0



func _ready() -> void:
	# Permet à Hotbar.gd (autre branche de l'arbre, sous HUD) de retrouver cette scène
	# pour is_player_casting()/show_skill_range()/hide_skill_range().
	add_to_group("game_root")
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	_chat_input.text_submitted.connect(_on_chat_submitted)

	_npc_menu.add_item("Parler", 0)
	_npc_menu.add_item("Boutique", 1)
	_npc_menu.id_pressed.connect(_on_npc_menu_id_pressed)
	_player_frame.self_clicked.connect(_on_player_frame_self_clicked)
	_target_status_bar.teleport_requested.connect(_on_teleport_button_pressed)

	_camera.size = _camera_size
	_minimap.set_camera_zoom(_camera_size)
	_apply_camera_orbit()

	_make_move_marker()
	_make_selection_ring()
	_update_celestial_lights()
	_log("[color=#9a9488]Prototype 3D isométrique — connecté.[/color]")

	Net.send_command("stats")
	Net.send_command("skills")
	# MapView/MapEnter/EntityAppeared sont poussés automatiquement par le serveur au spawn
	# (character-select/create), mais peuvent être arrivés avant que cette scène n'existe
	# (GameState les met en cache dès l'autoload) : on les rejoue ici si besoin. EntityAppeared
	# (KnownList.populate() côté backend, appelé par MapInstance.join() avant l'envoi de
	# MapEnter — voir CLAUDE.md, commit acfb970) est ce qui peuple désormais les entités à
	# portée au chargement de carte : sans ce rejeu, un joueur/monstre/PNJ déjà présent au
	# moment du spawn n'apparaîtrait qu'à son prochain déplacement (refresh() suivant).
	if not GameState.map_view.is_empty():
		_rebuild_map(GameState.map_view)
	if not GameState.map_enter.is_empty():
		_refresh_entities(GameState.map_enter)
	for entry in GameState.appeared_entities.values():
		_apply_appeared_entity(entry)
	for entry in GameState.appeared_portals.values():
		_apply_appeared_portal(entry)
	# Cas de reconnexion pendant qu'on est déjà mort (GamePlayerDefeated manqué, voir
	# GameState.is_dead, alimenté aussi par GamePlayerStats) : rouvre la fenêtre de respawn
	# sans nom de tueur (perdu, ce message n'est jamais rejoué), même geste que
	# mud-godot/scenes/game/Game.gd.
	if GameState.is_dead:
		_death_popup.open("")


func _process(delta: float) -> void:
	_advance_day_night_clock(delta)
	_step_movement(delta)
	_advance_casting(delta)
	_update_bars()
	_update_selection_ring()
	if _right_click_active and not _camera_orbiting \
			and Time.get_ticks_msec() - _right_click_started_at_ms >= CAMERA_ROTATE_HOLD_THRESHOLD_MS:
		_camera_orbiting = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if absf(angle_difference(_camera_yaw, _camera_yaw_target)) > 0.0005:
		var weight := 1.0 - exp(-CAMERA_ROTATE_SMOOTHING * delta)
		_camera_yaw = fposmod(lerp_angle(_camera_yaw, _camera_yaw_target, weight), TAU)
		_apply_camera_orbit()
	if _player_node != null:
		_camera_rig.position = _player_node.position
		if _range_indicator != null and _range_indicator.visible:
			_range_indicator.position = Vector3(_player_node.position.x, 0.06, _player_node.position.z)
		if not _selected_portal_id.is_empty():
			_update_portal_teleport_range()
	if _moving.has(PLAYER_KEY):
		_position_query_timer += delta
		if _position_query_timer >= POSITION_QUERY_INTERVAL_SEC:
			_position_query_timer = 0.0
			Net.send_command("position")
	else:
		_position_query_timer = 0.0

	_update_minimap()
	_update_player_frame()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not _chat_input.has_focus():
			_chat_input.grab_focus()
			get_viewport().set_input_as_handled()
			return
		if _chat_input.has_focus():
			return
		if event.keycode == KEY_ESCAPE:
			# Ferme d'abord la fenêtre HUD au premier plan (inventaire/équipement/fiche de
			# personnage/sorts/options, voir WindowFrame.gd) si une seule est ouverte — la
			# désélection ci-dessous ne s'applique que si aucune ne l'était (voir CLAUDE.md,
			# session du 2026-09-03, "Échap ferme la fenêtre la plus proche de nous").
			if WindowFrame.close_topmost():
				get_viewport().set_input_as_handled()
				return
			if not _selected_target_id.is_empty() or not _selected_portal_id.is_empty():
				Net.send_command("select", "")
				_clear_selection()
				_clear_portal_selection()
				get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB:
			_select_next_nearest_monster()
			get_viewport().set_input_as_handled()
			return
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_start_right_click_hold()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(CAMERA_ZOOM_STEP)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_end_right_click_hold()
	elif event is InputEventMouseMotion and _camera_orbiting:
		# N'avance que la cible brute : l'angle réellement affiché (_camera_yaw) la rattrape
		# en douceur dans _process (voir CAMERA_ROTATE_SMOOTHING) plutôt que de sauter
		# directement à chaque évènement souris. Signe inversé par rapport à la sensation
		# initiale (2026-09-03) — retour explicite, le sens paraissait inversé à l'usage.
		_camera_yaw_target = fposmod(_camera_yaw_target + event.relative.x * CAMERA_ROTATE_SENSITIVITY, TAU)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Réseau
# ---------------------------------------------------------------------------

func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"MapView":
			_rebuild_map(payload)
		"MapEnter":
			_refresh_entities(payload)
		"GamePlayerStats":
			_ensure_player_node()
			_set_entity_label(_player_node, str(payload.get("name", "")))
			_set_entity_title(_player_node, _extract_title(payload))
			# Enregistre notre propre UUID sous PLAYER_KEY : sans ça, _apply_target_current_health
			# (AttackResult/CastResult/SkillCastAnnounced qui nous ciblent) ne nous reconnaît
			# jamais comme cible (elle indexe par _key_by_entity_id, pas par comparaison directe
			# à GameState.player_stats.id comme _key_for_entity_id) — bug corrigé le 2026-09-03,
			# voir CLAUDE.md : jusqu'ici les PV du joueur affichés en HUD ne bougeaient jamais
			# en combat, seule la barre flottante au-dessus de sa tête restait invisible.
			_register_entity_id(PLAYER_KEY, str(payload.get("id", "")))
			_entity_vitals_by_key[PLAYER_KEY] = {
				"current": int(payload.get("currentHealth", 0)), "max": int(payload.get("maxHealth", 0)),
				"level": int(payload.get("level", 1)),
			}
		"GamePlayerJoinedMap":
			var joined_name := str(payload.get("characterName", ""))
			if not joined_name.is_empty():
				var key := "character:%s" % joined_name
				var node := _ensure_entity_node(key, joined_name, OTHER_PLAYER_COLOR)
				node.position = Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
				_register_entity_id(key, str(payload.get("characterId", "")))
				_log("[color=#8fd1c9]%s rejoint la carte.[/color]" % _bbcode_escape(joined_name))
		"GamePlayerLeftMap", "GamePlayerDisconnected":
			var left_name := str(payload.get("characterName", ""))
			if not left_name.is_empty():
				_remove_entity("character:%s" % left_name)
				_log("[color=#9a9488]%s quitte la carte.[/color]" % _bbcode_escape(left_name))
		"MovementStarted":
			_ensure_player_node()
			var target := Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
			_moving[PLAYER_KEY] = {"target": target}
			_entity_speed_by_key[PLAYER_KEY] = _player_speed()
			_face_heading(_player_node, float(payload.get("heading", 0.0)))
			_show_move_marker(Vector2(target.x, target.z))
		"MovementFinished", "MovementStopped", "MovementBlockedByBounds":
			_moving.erase(PLAYER_KEY)
			_ensure_player_node()
			_player_node.position = Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
			_hide_move_marker()
		"NoPathToDestination":
			_hide_move_marker()
		"PositionUpdated":
			_ensure_player_node()
			var server_pos := Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
			if _player_node.position.distance_to(server_pos) > POSITION_CORRECTION_DEADZONE:
				_player_node.position = server_pos
			_face_heading(_player_node, float(payload.get("heading", 0.0)))
		"CharacterMovementStarted":
			var entity_name := str(payload.get("characterName", ""))
			var character_id := str(payload.get("characterId", ""))
			if not entity_name.is_empty():
				var key := _resolve_movement_key(character_id, entity_name)
				var color := MONSTER_COLOR if key.begins_with("monster:") else OTHER_PLAYER_COLOR
				var node := _ensure_entity_node(key, entity_name, color)
				_register_entity_id(key, character_id)
				_face_heading(node, float(payload.get("heading", 0.0)))
				_moving[key] = {"target": Vector3(payload.get("targetX", 0.0), 0.0, payload.get("targetY", 0.0))}
				if not _entity_speed_by_key.has(key):
					_entity_speed_by_key[key] = DEFAULT_SPEED_TILES_PER_SEC
		"CharacterMovementFinished", "CharacterMovementStopped", "CharacterMovementBlocked":
			var entity_name2 := str(payload.get("characterName", ""))
			var character_id2 := str(payload.get("characterId", ""))
			if not entity_name2.is_empty():
				var key2 := _resolve_movement_key(character_id2, entity_name2)
				_moving.erase(key2)
				var node2 := _ensure_entity_node(key2, entity_name2, OTHER_PLAYER_COLOR)
				node2.position = Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
		"EntityAppeared":
			for entry in payload.get("entities", []):
				_apply_appeared_entity(entry)
		"EntityDisappeared":
			for id in payload.get("entityIds", []):
				_on_entity_disappeared(str(id))
		"PortalAppeared":
			for entry in payload.get("portals", []):
				_apply_appeared_portal(entry)
		"PortalDisappeared":
			for id in payload.get("portalIds", []):
				_on_portal_disappeared(str(id))
		"MonsterDefeated":
			var defeated_name := str(payload.get("monsterName", ""))
			_despawn_monster(defeated_name)
			_log("[color=%s]%s est vaincu.[/color]" % [LOG_COLOR_DEFEAT, _bbcode_escape(defeated_name)])
		"TargetSelected":
			_apply_selection(str(payload.get("targetId", "")), str(payload.get("targetName", "")))
		"TargetDeselected":
			_clear_selection()
		"NoTargetSelected":
			_clear_selection()
			_log("[i][color=#999999]Aucune cible sélectionnée.[/color][/i]")
		"TargetNotFound":
			if str(payload.get("targetId", "")) == _selected_target_id:
				_clear_selection()
			_log("[i][color=#999999]Cible introuvable.[/color][/i]")
		"AttackResult":
			var attack_target_id := str(payload.get("targetId", ""))
			_flash_entity_by_id(attack_target_id)
			if bool(payload.get("hit", false)):
				var attack_damage := int(payload.get("damage", 0))
				if attack_damage > 0:
					_show_damage_number(
						_entity_node_by_id(attack_target_id), attack_damage, bool(payload.get("critical", false))
					)
			_apply_target_current_health(attack_target_id, int(payload.get("targetCurrentHealth", 0)))
			_log_attack_result(payload)
		"AttackOutOfRange":
			_log("[i][color=#999999]%s est hors de portée.[/color][/i]" % _bbcode_escape(
				str(payload.get("targetName", "?"))
			))
		"SkillOutOfRange":
			_log("[i][color=#999999]%s est hors de portée pour %s.[/color][/i]" % [
				_bbcode_escape(str(payload.get("targetName", "?"))),
				_bbcode_escape(str(payload.get("skillName", ""))),
			])
		"SkillCastStarted":
			_on_skill_cast_started(payload)
		"SkillCastCancelled":
			_clear_casting(_key_for_entity_id(str(payload.get("casterId", ""))))
		"SkillFizzled":
			_clear_casting(PLAYER_KEY)
			_log("[i][color=#999999]Incantation ratée : %s[/color][/i]" % _bbcode_escape(
				str(payload.get("reason", ""))
			))
		"AlreadyCasting":
			_log("[i][color=#999999]Vous êtes déjà en train d'incanter un sort.[/color][/i]")
		"SkillProjectileLaunched":
			_on_skill_projectile_launched(payload)
		"CastResult":
			_on_own_cast_result(payload)
			_log_cast_result(payload)
		"SkillCastAnnounced":
			_on_skill_cast_announced(payload)
			_log_skill_cast_announced(payload)
		"SkillModifierAnnounced":
			if bool(payload.get("hit", false)):
				_play_skill_animation(str(payload.get("targetId", "")), str(payload.get("skillName", "")))
		"ShotUsed":
			# Envoyé uniquement à nous-même (voir GameState.gd) : la lueur d'arme des AUTRES
			# personnages arrive séparément via SoulshotUsed/SpiritshotUsed ci-dessous.
			_ensure_player_node()
			var used_color := SOULSHOT_GLOW_COLOR if str(payload.get("shotType", "")) == "SOULSHOT" else SPIRITSHOT_GLOW_COLOR
			_flash_entity(_player_node, used_color, SHOT_GLOW_UP_DURATION, SHOT_GLOW_DOWN_DURATION)
		"SoulshotUsed":
			var soulshot_node := _entity_node_by_id(str(payload.get("characterId", "")))
			if soulshot_node != null:
				_flash_entity(soulshot_node, SOULSHOT_GLOW_COLOR, SHOT_GLOW_UP_DURATION, SHOT_GLOW_DOWN_DURATION)
		"SpiritshotUsed":
			var spiritshot_node := _entity_node_by_id(str(payload.get("characterId", "")))
			if spiritshot_node != null:
				_flash_entity(spiritshot_node, SPIRITSHOT_GLOW_COLOR, SHOT_GLOW_UP_DURATION, SHOT_GLOW_DOWN_DURATION)
		"ShotGradeChanged":
			var sg_label := "Soulshot" if str(payload.get("shotType", "")) == "SOULSHOT" else "Spiritshot"
			var sg_grade = payload.get("grade")
			if sg_grade == null:
				_log("[i][color=#999999]%s désactivé.[/color][/i]" % sg_label)
			else:
				_log("[i][color=#999999]%s activé (%s).[/color][/i]" % [sg_label, str(sg_grade)])
		"ShotOutOfStock":
			var out_label := "Soulshots" if str(payload.get("shotType", "")) == "SOULSHOT" else "Spiritshots"
			_log("[i][color=#999999]Plus de %s (%s) — auto-use désactivé.[/color][/i]" % [
				out_label, str(payload.get("grade", "?")),
			])
		"InvalidShotGrade":
			_log("[i][color=#999999]Grade de charge invalide : %s[/color][/i]" % _bbcode_escape(
				str(payload.get("argument", ""))
			))
		"RegenTick":
			# Message privé (jamais diffusé à la zone, voir CLAUDE.md du client 2D) : concerne
			# toujours notre propre personnage, contrairement à AttackResult/CastResult qui
			# portent un targetId à comparer.
			var regen_level := int(_entity_vitals_by_key.get(PLAYER_KEY, {}).get("level", 1))
			_entity_vitals_by_key[PLAYER_KEY] = {
				"current": int(payload.get("currentHealth", 0)), "max": int(payload.get("maxHealth", 0)),
				"level": regen_level,
			}
		"XpGained":
			_log("[color=%s]Vous gagnez %s points d'expérience.[/color]" % [
				LOG_COLOR_XP, str(payload.get("amount", 0)),
			])
		"PlayerLeveledUp":
			if str(payload.get("characterName", "")) == str(GameState.player_stats.get("name", "")):
				_log("[color=%s]Vous passez au niveau %s ![/color]" % [
					LOG_COLOR_XP, str(payload.get("newLevel", "?")),
				])
				# XpGained (déjà reçu juste avant ce message, voir CharacterInstance.gainXp côté
				# backend) reporte xpForCurrentLevel/xpForNextLevel du niveau D'AVANT cette montée
				# — la barre d'XP resterait donc bloquée à un seuil obsolète tant qu'un nouveau
				# GamePlayerStats n'est pas reçu. On le redemande explicitement plutôt que
				# d'attendre le prochain gain d'XP (même pattern que Net.send_command("stats") au
				# _ready de cette scène).
				Net.send_command("stats")
		"EquipmentLooted":
			_log("[color=%s]Vous trouvez : %s[/color]" % [
				LOG_COLOR_LOOT, _bbcode_escape(str(payload.get("itemName", "?"))),
			])
		"GoldLooted":
			_log("[color=%s]Vous trouvez %s pièces d'or.[/color]" % [
				LOG_COLOR_LOOT, str(payload.get("amount", 0)),
			])
		"ItemBought":
			# Réponse à "shop"/"buy" (voir %ShopWindow, qui réagit indépendamment au même
			# message pour son propre panneau de confirmation — même principe que GameState/
			# Game3D réagissant chacun à ShotGradeChanged sans se coordonner).
			_log("[color=%s]Vous achetez : %s (%s or).[/color]" % [
				LOG_COLOR_LOOT, _bbcode_escape(str(payload.get("itemName", "?"))), str(payload.get("price", 0)),
			])
		"NotEnoughGold":
			_log("[i][color=#999999]Pas assez d'or (%s requis).[/color][/i]" % str(payload.get("price", 0)))
		"ShopItemNotFound":
			_log("[i][color=#999999]Cet objet n'est plus disponible chez ce marchand.[/color][/i]")
		"GamePlayerDefeated":
			_log_player_defeated(payload)
			if str(payload.get("characterName", "")) == str(GameState.player_stats.get("name", "")):
				_death_popup.open(str(payload.get("killerName", "")))
		"PlayerRespawned":
			_log("[color=%s]Vous revenez à la vie.[/color]" % LOG_COLOR_HEAL)
			_death_popup.close()
			var respawn_level := int(_entity_vitals_by_key.get(PLAYER_KEY, {}).get("level", 1))
			_entity_vitals_by_key[PLAYER_KEY] = {
				"current": int(payload.get("currentHealth", 0)), "max": int(payload.get("maxHealth", 0)),
				"level": respawn_level,
			}
		"CharacterIsDead":
			_log("[i][color=#999999]Vous êtes mort — impossible tant que vous n'avez pas réapparu.[/color][/i]")
		"CharacterNotDead":
			_log("[i][color=#999999]Vous n'êtes pas mort.[/color][/i]")
		"NoPortalHere":
			_log("[i][color=#999999]Vous n'êtes pas assez proche d'un portail.[/color][/i]")
		"CombatForbiddenHere":
			_log("[i][color=#999999]Combat impossible ici (%s).[/color][/i]" % _bbcode_escape(
				str(payload.get("zoneName", "?"))
			))
		"Chat":
			# Diffusé à toute la zone SAUF au locuteur (voir "YouSaid" ci-dessous) — comme
			# SkillCastAnnounced/CastResult, le serveur sépare toujours l'écho à l'auteur du
			# message diffusé aux autres.
			_log("[b]%s[/b] : %s" % [
				_bbcode_escape(str(payload.get("speakerName", "?"))),
				_bbcode_escape(str(payload.get("text", ""))),
			])
		"YouSaid":
			# Écho envoyé uniquement à l'auteur d'un "say" (jamais inclus dans "Chat", voir
			# ci-dessus) — absent jusqu'ici, ce qui faisait qu'aucun message tapé par
			# soi-même n'apparaissait dans le chat (bug signalé le 2026-09-02, flagrant en
			# session solo puisque "Chat" n'a alors personne d'autre à qui être diffusé).
			_log("[b]Vous[/b] : %s" % _bbcode_escape(str(payload.get("text", ""))))
		"PeaceZoneEntered":
			_log("[color=%s]Zone paisible (%s) : %s[/color]" % [
				LOG_COLOR_PEACE,
				_bbcode_escape(str(payload.get("zoneName", "?"))),
				_bbcode_escape(str(payload.get("description", ""))),
			])
		"PeaceZoneExited":
			_log("[color=%s]Vous quittez la zone paisible : %s.[/color]" % [
				LOG_COLOR_PEACE, _bbcode_escape(str(payload.get("zoneName", "?"))),
			])
		"Error":
			_log("[color=#9a9488]%s[/color]" % _bbcode_escape(str(payload.get("message", "Erreur."))))
		"GameTimeSync":
			# Resynchronisation ponctuelle (au login) : bascule immédiate, pas d'animation —
			# voir _day_night_t_for_time/_apply_day_night_preset. Resynchronise aussi l'horloge
			# continue qui pilote la trajectoire Soleil/Lune (_advance_day_night_clock) : sans
			# ça, un client resterait sur son heure locale simulée dérivée de _game_minutes_of_day
			# (défaut 13h) au lieu de l'heure serveur reçue au login.
			var sync_hour := int(payload.get("hour", 12))
			var sync_minute := int(payload.get("minute", 0))
			_game_minutes_of_day = float(sync_hour * 60 + sync_minute)
			_apply_day_night_preset(_day_night_t_for_time(sync_hour, sync_minute))
		"Sunrise":
			_animate_day_night(1.0, int(payload.get("transitionDurationMs", 0)))
		"Sunset":
			_animate_day_night(0.0, int(payload.get("transitionDurationMs", 0)))
		_:
			pass


func _on_net_disconnected() -> void:
	var login_to_keep := GameState.current_login
	GameState.clear_session()
	GameState.current_login = login_to_keep
	GameState.pending_disconnect_message = "Connexion au serveur interrompue."
	get_tree().change_scene_to_file("res://scenes/login/Login.tscn")


func _on_chat_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	_chat_input.text = ""
	_chat_input.release_focus()
	if not trimmed.is_empty():
		Net.send_command("say", trimmed)


# ---------------------------------------------------------------------------
# Carte (sol + obstacles + portails), voir ZoneAssets3D
# ---------------------------------------------------------------------------

func _rebuild_map(payload: Dictionary) -> void:
	_current_map_name = str(payload.get("mapName", ""))
	var grid: Dictionary = payload.get("grid", {})
	_map_width = int(grid.get("width", 0))
	_map_height = int(grid.get("height", 0))
	_walkable_rows = grid.get("walkableRows", [])

	_clear_entities()
	_hide_move_marker()

	var texture := ZoneAssets3D.build_ground_texture(payload)
	var plane := PlaneMesh.new()
	plane.size = Vector2(maxf(_map_width, 1.0), maxf(_map_height, 1.0))
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_texture = texture
	ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground_mat.roughness = 0.95
	plane.material = ground_mat
	_ground.mesh = plane
	_ground.position = Vector3(_map_width / 2.0, 0.0, _map_height / 2.0)

	_rebuild_obstacles()
	_clear_portals()
	_rebuild_night_lights()
	_minimap.set_map(texture, _map_width, _map_height, _current_map_name)
	_log("[color=#9a9488]Carte : %s (%dx%d)[/color]" % [_current_map_name, _map_width, _map_height])


func _rebuild_obstacles() -> void:
	var transforms: Array[Transform3D] = []
	for y in _map_height:
		var row: String = _walkable_rows[y] if y < _walkable_rows.size() else ""
		for x in _map_width:
			var walkable: bool = x < row.length() and row[x] == "1"
			var height := ZoneAssets3D.obstacle_height_for(_current_map_name, x, y, walkable)
			if height <= 0.0:
				continue
			var obstacle_basis := Basis().scaled(Vector3(0.94, height, 0.94))
			var origin := Vector3(x + 0.5, height / 2.0, y + 0.5)
			transforms.append(Transform3D(obstacle_basis, origin))

	if transforms.is_empty():
		_obstacles.multimesh = null
		return

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var obstacle_mat := StandardMaterial3D.new()
	obstacle_mat.albedo_color = Color(0.30, 0.28, 0.26)
	obstacle_mat.roughness = 1.0
	box.material = obstacle_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	_obstacles.multimesh = mm


## Repose les lumières de ville (voir LANDMARK_LIGHTS) sur la carte courante : un
## OmniLight3D par groupe de cases contigües de chaque terrain remarquable (fontaine,
## auberge, forge), posé au centre du groupe plutôt qu'un par case (évite une nappe de
## lumières redondantes sur une place pavée large de plusieurs cases). Reconstruit à chaque
## _rebuild_map (changement de carte) comme _rebuild_obstacles/_clear_portals ci-dessus.
func _rebuild_night_lights() -> void:
	for child in _night_lights.get_children():
		child.queue_free()

	var terrain_grid: Array = ZoneAssets3D.get_terrain_grid(_current_map_name)
	for terrain_name in LANDMARK_LIGHTS:
		var props: Dictionary = LANDMARK_LIGHTS[terrain_name]
		for cluster_center in _terrain_clusters(terrain_grid, terrain_name):
			var light := OmniLight3D.new()
			light.light_color = props["color"]
			light.omni_range = props["range"]
			light.shadow_enabled = false
			light.set_meta("base_energy", props["energy"])
			light.position = Vector3(cluster_center.x, NIGHT_LIGHT_HEIGHT, cluster_center.y)
			_night_lights.add_child(light)

	_update_night_lights_energy(_day_night_t)


## Regroupe par connexité (4 voisins) les cases de terrain_grid valant terrain_name, et
## renvoie le centre (coordonnées tuile, +0.5 pour retomber au milieu de chaque case comme
## _rebuild_obstacles) de chaque groupe — voir _rebuild_night_lights.
func _terrain_clusters(terrain_grid: Array, terrain_name: String) -> Array[Vector2]:
	var visited: Dictionary = {}
	var clusters: Array[Vector2] = []
	for y in terrain_grid.size():
		var row: Array = terrain_grid[y]
		for x in row.size():
			var start := Vector2i(x, y)
			if visited.has(start) or row[x] != terrain_name:
				continue
			visited[start] = true
			var stack: Array[Vector2i] = [start]
			var sum := Vector2.ZERO
			var count := 0
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				sum += Vector2(cell.x + 0.5, cell.y + 0.5)
				count += 1
				var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
				for offset in offsets:
					var neighbor: Vector2i = cell + offset
					if visited.has(neighbor) or neighbor.y < 0 or neighbor.y >= terrain_grid.size():
						continue
					var neighbor_row: Array = terrain_grid[neighbor.y]
					if neighbor.x < 0 or neighbor.x >= neighbor_row.size() or neighbor_row[neighbor.x] != terrain_name:
						continue
					visited[neighbor] = true
					stack.append(neighbor)
			clusters.append(sum / count)
	return clusters


## Fait suivre le facteur jour/nuit t (0.0 nuit, 1.0 jour) aux lumières de ville : pleine
## intensité en pleine nuit, éteintes en plein jour, avec le même fondu que le reste de
## l'ambiance (voir _apply_day_night_preset, qui appelle cette fonction à chaque mise à
## jour). Nul besoin d'un Tween dédié : déjà appelée en continu par le tween/l'instantané de
## _day_night_t existant.
func _update_night_lights_energy(t: float) -> void:
	var factor := 1.0 - t
	for child in _night_lights.get_children():
		if child is OmniLight3D:
			child.light_energy = float(child.get_meta("base_energy", 1.0)) * factor


func _is_walkable(target: Vector2) -> bool:
	if _walkable_rows.is_empty():
		return true
	var cx := int(floor(target.x))
	var cy := int(floor(target.y))
	if cy < 0 or cy >= _walkable_rows.size():
		return true
	var row: String = _walkable_rows[cy]
	if cx < 0 or cx >= row.length():
		return true
	return row[cx] == "1"


## Vide tous les portails actuellement affichés (voir _portals) — appelé à chaque _rebuild_map
## (changement de carte, coordonnées de l'ancienne carte devenues obsolètes), comme
## _clear_entities ci-dessus : PortalDisappeared pour l'ancienne carte n'est pas garanti
## d'arriver avant que le nouveau MapView ne soit traité.
func _clear_portals() -> void:
	for entry in _portals.values():
		var node: Node3D = entry.get("node")
		if node != null:
			node.queue_free()
	_portals.clear()
	_clear_portal_selection()


## Portail entrant dans notre KnownList (portée de perception) — au spawn/changement de carte
## ou en cours de partie après un déplacement, voir CLAUDE.md : PortalAppeared, poussé par
## KnownList côté backend exactement comme EntityAppeared (voir _apply_appeared_entity), a
## remplacé l'ancien champ MapView.portals (retiré côté backend) où tous les portails de la
## carte arrivaient d'un bloc plutôt qu'un par un à portée.
func _apply_appeared_portal(entry: Dictionary) -> void:
	var portal_id := str(entry.get("id", ""))
	if portal_id.is_empty() or _portals.has(portal_id):
		return
	var target_map_name := str(entry.get("targetMapName", "Portail"))
	var portal_name := str(entry.get("name", PORTAL_NAME_DEFAULT))
	var portal_title := str(entry.get("title", PORTAL_TITLE_DEFAULT))
	var portal_range: float = entry.get("triggerRadius", PORTAL_RANGE_DEFAULT)
	var pos := Vector2(entry.get("x", 0.0), entry.get("y", 0.0))
	var portal_node := _make_portal_node(portal_name, portal_title)
	portal_node.position = Vector3(pos.x, 0.0, pos.y)
	_world.add_child(portal_node)
	portal_node.set_meta("portal_id", portal_id)
	_portals[portal_id] = {
		"position": pos, "target_map_name": target_map_name, "portal_name": portal_name,
		"portal_title": portal_title, "range": portal_range, "node": portal_node,
	}
	_orient_portal_to_camera(portal_node)


## Portail sortant de notre KnownList — hors de portée après un déplacement, ou retiré de la
## carte, voir CLAUDE.md/_on_entity_disappeared (même mécanisme, PortalDisappeared plutôt
## qu'EntityDisappeared). Désélectionne au passage si c'était le portail actuellement ciblé par
## %TargetStatusBar.
func _on_portal_disappeared(portal_id: String) -> void:
	if not _portals.has(portal_id):
		return
	if _selected_portal_id == portal_id:
		_clear_portal_selection()
	var node: Node3D = _portals[portal_id].node
	if node != null:
		node.queue_free()
	_portals.erase(portal_id)


## Shader du "voile" d'énergie tourbillonnant à l'intérieur de l'anneau (voir
## _make_portal_node) — motif spiralé + anneaux concentriques générés uniquement à partir de
## TIME et de la distance au centre (pas de texture externe : aucun asset image n'est
## disponible/généré pour ce projet, voir échange avec l'utilisateur du 2026-09-06).
## cull_disabled : le voile reste visible quel que soit le côté d'où on le regarde, ce qui
## dispense _orient_portal_to_camera d'un calcul d'orientation exact (voir cette fonction).
const PORTAL_VORTEX_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, shadows_disabled, specular_disabled;

uniform vec4 core_color : source_color = vec4(0.78, 0.95, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.05, 0.18, 0.65, 1.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float radius = length(centered);
	if (radius > 1.0) {
		discard;
	}
	float angle = atan(centered.y, centered.x);
	float swirl = angle * 3.0 + radius * 6.0 - TIME * 2.2;
	float bands = sin(swirl) * 0.5 + 0.5;
	float rings = sin(radius * 16.0 - TIME * 3.4) * 0.5 + 0.5;
	float pattern = mix(bands, rings, 0.35);
	vec4 base_color = mix(core_color, edge_color, smoothstep(0.0, 1.0, radius));
	vec3 glow = base_color.rgb * (0.55 + 0.45 * pattern) * (1.0 + highlight * 0.9);
	ALBEDO = glow;
	EMISSION = glow * (1.3 + highlight);
	ALPHA = smoothstep(1.0, 0.55, radius);
}
"""


## Anneau vertical + voile tourbillonnant (au lieu de l'ancien simple disque plat au sol) —
## un halo au sol subsiste pour repérer la zone d'activation (voir PORTAL_PICK_RADIUS), le
## reste ("Facing", voir _orient_portal_to_camera) se dresse verticalement façon "portail
## d'énergie".
func _make_portal_node(portal_name: String, portal_title: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Portal"

	var ground_glow := MeshInstance3D.new()
	var ground_disc := CylinderMesh.new()
	ground_disc.top_radius = PORTAL_PICK_RADIUS
	ground_disc.bottom_radius = PORTAL_PICK_RADIUS
	ground_disc.height = 0.02
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(PORTAL_COLOR.r, PORTAL_COLOR.g, PORTAL_COLOR.b, 0.35)
	ground_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_mat.emission_enabled = true
	ground_mat.emission = PORTAL_COLOR
	ground_mat.emission_energy_multiplier = 0.8
	ground_disc.material = ground_mat
	ground_glow.mesh = ground_disc
	ground_glow.position = Vector3(0.0, 0.02, 0.0)
	root.add_child(ground_glow)

	# Zone de collision englobant tout l'objet (halo au sol + anneau + voile), pas juste la
	# "base" — voir _pick_portal_id_at_mouse, même mécanisme que PickArea dans
	# _make_entity_node (couche physique dédiée PORTAL_PICK_COLLISION_LAYER). Un cylindre
	# suffit et reste correct quel que soit l'angle de caméra (contrairement à "Facing", il
	# n'a pas besoin d'être réorienté) : il est symétrique par rotation autour de Y, comme
	# l'ancien test au sol qu'il remplace.
	var pick_area := Area3D.new()
	pick_area.name = "PickArea"
	pick_area.collision_layer = PORTAL_PICK_COLLISION_LAYER
	pick_area.collision_mask = 0
	var pick_shape := CollisionShape3D.new()
	var pick_cylinder := CylinderShape3D.new()
	pick_cylinder.radius = PORTAL_RING_OUTER_RADIUS + 0.05
	pick_cylinder.height = PORTAL_RING_HEIGHT_Y + PORTAL_RING_OUTER_RADIUS + 0.1
	pick_shape.shape = pick_cylinder
	pick_area.position = Vector3(0.0, pick_cylinder.height / 2.0, 0.0)
	pick_area.add_child(pick_shape)
	root.add_child(pick_area)

	# "Facing" ne tourne qu'autour de Y (voir _orient_portal_to_camera) : contrairement au
	# halo au sol ci-dessus (un disque à plat, donc symétrique quel que soit l'angle de vue),
	# un anneau dressé verticalement présenterait sa tranche (quasi invisible) sous certains
	# angles de caméra s'il restait figé — d'où ce "billboard" limité à l'axe Y, qui garde le
	# portail toujours bien droit (jamais penché) tout en le gardant face à la caméra.
	var facing := Node3D.new()
	facing.name = "Facing"
	facing.position = Vector3(0.0, PORTAL_RING_HEIGHT_Y, 0.0)
	root.add_child(facing)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PORTAL_RING_INNER_RADIUS
	torus.outer_radius = PORTAL_RING_OUTER_RADIUS
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = PORTAL_COLOR
	ring_mat.emission_enabled = true
	ring_mat.emission = PORTAL_COLOR
	ring_mat.emission_energy_multiplier = 1.4
	torus.material = ring_mat
	ring.mesh = torus
	# TorusMesh est par défaut un anneau À PLAT (axe du trou = Y, comme l'ancien halo au sol) ;
	# cette rotation de 90° autour de X redresse son axe sur Z (celui vers lequel "Facing"
	# regarde), pour un anneau dressé façon "porte" plutôt que posé au sol.
	ring.rotation.x = PI / 2.0
	facing.add_child(ring)
	root.set_meta("ring_material", ring_mat)

	var vortex := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * PORTAL_RING_INNER_RADIUS * 2.0
	var vortex_shader := Shader.new()
	vortex_shader.code = PORTAL_VORTEX_SHADER_CODE
	var vortex_mat := ShaderMaterial.new()
	vortex_mat.shader = vortex_shader
	vortex_mat.set_shader_parameter("core_color", PORTAL_CORE_COLOR)
	vortex_mat.set_shader_parameter("edge_color", PORTAL_EDGE_COLOR)
	quad.material = vortex_mat
	vortex.mesh = quad
	facing.add_child(vortex)
	root.set_meta("vortex_material", vortex_mat)

	root.add_child(_make_portal_particles())
	root.set_meta("facing", facing)

	# Nom/titre façon personnage (voir _make_entity_node/TITLE_LABEL_COLOR) plutôt que l'ancien
	# libellé unique affichant la carte cible : "Clairière"/"Téléporteur" identifient l'objet
	# lui-même, la destination reste affichée dans %TargetStatusBar (voir _select_portal).
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = portal_name
	label.position = Vector3(0.0, PORTAL_RING_HEIGHT_Y + PORTAL_RING_OUTER_RADIUS + 0.35, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 6
	label.modulate = PORTAL_COLOR.lightened(0.4)
	root.add_child(label)

	var title_label := Label3D.new()
	title_label.name = "TitleLabel"
	title_label.text = portal_title
	title_label.position = Vector3(0.0, PORTAL_RING_HEIGHT_Y + PORTAL_RING_OUTER_RADIUS + 0.68, 0.0)
	title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title_label.no_depth_test = true
	title_label.font_size = 20
	title_label.outline_size = 5
	title_label.modulate = TITLE_LABEL_COLOR
	root.add_child(title_label)

	return root


## Petites étincelles d'énergie flottant près de l'anneau — rattachées à root (pas à
## "Facing") pour ne jamais suivre son "billboard" en Y : une sphère de particules est
## indifférente à l'angle de vue de toute façon, autant éviter le moindre à-coup au moment où
## la caméra s'oriente (voir _orient_portal_to_camera).
func _make_portal_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.position = Vector3(0.0, PORTAL_RING_HEIGHT_Y, 0.0)
	particles.amount = 20
	particles.lifetime = 2.2
	particles.local_coords = false

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.08
	var particle_mat := StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.emission_enabled = true
	particle_mat.emission = PORTAL_CORE_COLOR
	particle_mat.emission_energy_multiplier = 2.0
	particle_mat.albedo_color = Color(PORTAL_CORE_COLOR.r, PORTAL_CORE_COLOR.g, PORTAL_CORE_COLOR.b, 0.85)
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = particle_mat
	particles.draw_pass_1 = quad

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 180.0
	process_mat.initial_velocity_min = 0.05
	process_mat.initial_velocity_max = 0.18
	process_mat.gravity = Vector3(0.0, 0.05, 0.0)
	process_mat.damping_min = 0.05
	process_mat.damping_max = 0.15
	process_mat.angular_velocity_min = -90.0
	process_mat.angular_velocity_max = 90.0
	process_mat.scale_min = 0.6
	process_mat.scale_max = 1.4
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process_mat.emission_sphere_radius = PORTAL_RING_INNER_RADIUS
	process_mat.color = PORTAL_CORE_COLOR
	particles.process_material = process_mat

	return particles


## Rappelée par _apply_camera_orbit à chaque changement d'angle (et une fois à la création du
## portail, voir _apply_appeared_portal) : ne tourne "Facing" qu'autour de Y, à partir de la
## direction horizontale vers la caméra — jamais de tangage, pour que l'anneau reste toujours
## vertical peu importe l'angle de vue.
func _orient_portal_to_camera(root: Node3D) -> void:
	var facing = root.get_meta("facing", null)
	if facing == null:
		return
	var to_camera: Vector3 = _camera.global_position - facing.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return
	facing.look_at(facing.global_position + to_camera, WORLD_UP)


func _orient_all_portals() -> void:
	for entry in _portals.values():
		_orient_portal_to_camera(entry.node)


func _set_portal_highlight(portal_id: String, on: bool) -> void:
	if not _portals.has(portal_id):
		return
	var node: Node3D = _portals[portal_id].node
	var ring_mat: StandardMaterial3D = node.get_meta("ring_material")
	ring_mat.emission_energy_multiplier = 2.6 if on else 1.4
	var vortex_mat: ShaderMaterial = node.get_meta("vortex_material")
	vortex_mat.set_shader_parameter("highlight", 1.0 if on else 0.0)


# ---------------------------------------------------------------------------
# Sélection de cible, attaque, sorts, portails — clic/pick
# ---------------------------------------------------------------------------

## Même principe que _pick_entity_id_at_mouse ci-dessous, mais contre la zone de collision du
## portail (voir PickArea/PORTAL_PICK_COLLISION_LAYER dans _make_portal_node) — tout l'objet
## est désormais cliquable (anneau/voile compris), pas seulement le halo au sol comme avant
## le 2026-09-06 (l'ancien test comparait juste la distance au sol au centre du portail).
## Renvoie l'id (UUID) dans _portals, ou "" si aucun portail touché.
func _pick_portal_id_at_mouse() -> String:
	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var to := from + _camera.project_ray_normal(mouse_pos) * ENTITY_PICK_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PORTAL_PICK_COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return ""
	var collider = result.get("collider")
	if collider is Node:
		var portal_root := (collider as Node).get_parent()
		if portal_root != null:
			return str(portal_root.get_meta("portal_id", ""))
	return ""


## Rayon caméra→souris testé contre les capsules de collision des entités (voir
## _make_entity_node/ENTITY_PICK_COLLISION_LAYER), pas contre une projection au sol : une
## capsule fait 1.6 unité de haut, vue de biais par la caméra isométrique, donc cliquer sur
## son haut visible ne correspond à aucun point proche de sa base au sol (voir la note sur
## ENTITY_PICK_COLLISION_LAYER). Renvoie l'UUID réseau de l'entité touchée, ou "" si aucune
## (self exclu, voir `pickable` dans _make_entity_node).
func _pick_entity_id_at_mouse() -> String:
	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var to := from + _camera.project_ray_normal(mouse_pos) * ENTITY_PICK_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ENTITY_PICK_COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return ""
	var collider = result.get("collider")
	if collider is Node:
		var entity_root := (collider as Node).get_parent()
		if entity_root != null:
			return str(entity_root.get_meta("entity_id", ""))
	return ""


func _handle_left_click() -> void:
	var entity_id := _pick_entity_id_at_mouse()
	if not entity_id.is_empty():
		Net.send_command("select", entity_id)
		_clear_portal_selection()
		return

	var portal_id := _pick_portal_id_at_mouse()
	if not portal_id.is_empty():
		_select_portal(portal_id)
		return

	if not is_player_casting() and not GameState.is_dead:
		_try_send_goto_at_mouse()


## Le clic droit ne concerne plus que le PNJ déjà sélectionné (voir _apply_selection/
## EntityView.kind) — le portail se sélectionne et se déclenche désormais uniquement via
## %TargetStatusBar (bouton "Téléporter", voir _select_portal/_on_teleport_button_pressed),
## demande explicite du 2026-09-06 pour ne plus dépendre du clic droit sur le téléporteur.
func _handle_right_click() -> void:
	if not _selected_target_id.is_empty():
		var target_node := _entity_node_by_id(_selected_target_id)
		if target_node != null and str(target_node.get_meta("kind", "")) == "npc":
			_open_npc_menu(bool(target_node.get_meta("has_shop", false)))


## Début d'un appui du bouton droit : ne fait encore rien de visible, voir _process pour la
## bascule en rotation caméra après CAMERA_ROTATE_HOLD_THRESHOLD_MS, et _end_right_click_hold
## pour le clic bref (menu PNJ).
func _start_right_click_hold() -> void:
	_right_click_active = true
	_camera_orbiting = false
	_right_click_started_at_ms = Time.get_ticks_msec()
	_right_click_press_screen_pos = get_viewport().get_mouse_position()


## Relâchement du bouton droit : si le maintien n'a jamais atteint le seuil de rotation
## (_camera_orbiting toujours faux), c'est un clic bref classique — comportement inchangé
## (menu PNJ sur une cible déjà sélectionnée). Sinon, sort du mode rotation et replace le
## curseur là où le clic droit avait commencé (souris capturée/invisible pendant la rotation,
## voir Input.mouse_mode dans _process).
func _end_right_click_hold() -> void:
	var was_orbiting := _camera_orbiting
	_right_click_active = false
	if _camera_orbiting:
		_camera_orbiting = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.warp_mouse(_right_click_press_screen_pos)
	if not was_orbiting:
		_handle_right_click()


## Repositionne la caméra sur un cercle horizontal de rayon/hauteur fixes (dérivés de
## l'offset isométrique par défaut (1,1,1)) à l'angle _camera_yaw près, puis la réoriente
## vers le pivot CameraRig — nécessaire à chaque changement d'angle (contrairement à une
## simple translation du rig, qui préserve l'orientation locale existante sans recalcul,
## voir _process). Appelée une fois dans _ready() (angle par défaut, _camera_yaw=0) et à
## chaque frame où _camera_yaw se rapproche encore de _camera_yaw_target (voir _process) —
## PAS directement depuis le mouvement de souris (_unhandled_input), qui ne fait qu'avancer
## _camera_yaw_target ; c'est ce découplage qui rend la rotation progressive/"smooth".
func _apply_camera_orbit() -> void:
	var base := Vector3.ONE.normalized() * CAMERA_DISTANCE
	var horizontal_radius := Vector2(base.x, base.z).length()
	var angle := atan2(base.z, base.x) + _camera_yaw
	_camera.position = Vector3(horizontal_radius * cos(angle), base.y, horizontal_radius * sin(angle))
	_camera.look_at(_camera_rig.global_position, WORLD_UP)
	_orient_all_portals()


## has_shop : EntityView.hasShop côté backend — désactive "Boutique" pour un PNJ qui ne
## vend rien (voir _apply_appeared_entity), "Parler" reste toujours disponible.
func _open_npc_menu(has_shop: bool) -> void:
	_npc_menu.set_item_disabled(1, not has_shop)
	_npc_menu.popup(Rect2i(get_viewport().get_mouse_position(), Vector2i.ZERO))


## "Parler" envoie "talk <npcId>" — le serveur répond par DialogueOptions (arbre de dialogue
## complet en un seul message, voir Talk.java), que %DialogueWindow s'ouvre elle-même en
## réagissant à ce message (voir DialogueWindow.gd). "Boutique" envoie "shop <npcId>", le PNJ
## ciblé étant la sélection courante (voir _handle_right_click) — le serveur répond par
## ShopCatalog, que %ShopWindow s'ouvre elle-même en réagissant à ce message.
func _on_npc_menu_id_pressed(id: int) -> void:
	match id:
		0:
			Net.send_command("talk", _selected_target_id)
		1:
			Net.send_command("shop", _selected_target_id)


func _select_portal(portal_id: String) -> void:
	if portal_id == _selected_portal_id:
		return
	_clear_portal_selection()
	if not _selected_target_id.is_empty():
		Net.send_command("select", "")
		_clear_selection()
	_selected_portal_id = portal_id
	_set_portal_highlight(portal_id, true)
	var entry: Dictionary = _portals[portal_id]
	_target_status_bar.show_portal(str(entry.portal_name), str(entry.target_map_name))
	_update_portal_teleport_range()


func _clear_portal_selection() -> void:
	if _selected_portal_id.is_empty():
		return
	_set_portal_highlight(_selected_portal_id, false)
	_selected_portal_id = ""
	_target_status_bar.hide_target()


## Distance joueur -> portail sélectionné, dans le même plan XZ/units que la position serveur
## (voir _apply_appeared_portal, portal.position déjà en coordonnées monde comme
## _player_node.position).
func _selected_portal_distance() -> float:
	if _selected_portal_id.is_empty() or _player_node == null:
		return INF
	var entry: Dictionary = _portals[_selected_portal_id]
	var pos: Vector2 = entry.position
	return Vector2(_player_node.position.x, _player_node.position.z).distance_to(pos)


## Reflète côté client, à chaque frame où un portail est sélectionné (voir _process), la même
## règle de portée que le serveur (voir MapInstance.findPortalAt, triggerRadius) : le bouton
## "Téléporter" se grise tant que le joueur reste hors de portée, sans attendre un aller-retour
## réseau/le message d'erreur NoPortalHere.
func _update_portal_teleport_range() -> void:
	if _selected_portal_id.is_empty():
		return
	var entry: Dictionary = _portals[_selected_portal_id]
	var in_range := _selected_portal_distance() <= float(entry.range)
	_target_status_bar.set_teleport_enabled(in_range)


## Bouton "Téléporter" de %TargetStatusBar (voir _select_portal/TargetStatusBar.gd) — envoie
## "portal" tel quel, comme l'ancien menu contextuel du même nom : le serveur se base
## uniquement sur la position courante du joueur, pas sur un identifiant de portail transmis
## par le client.
func _on_teleport_button_pressed() -> void:
	Net.send_command("portal")


## Clic sur le cadre de vitaux (PlayerFrame, haut-gauche) — voir PlayerFrame.gd/self_clicked.
## Se sélectionner soi-même n'est pas possible en 3D (capsule non cliquable, `pickable=false`
## dans _make_entity_node) alors que c'est nécessaire pour cibler un sort de soin (Heal) sur
## soi ; le serveur accepte notre propre UUID dans `select` (Select.java résout n'importe quel
## occupant de la carte courante, nous y compris), donc aucun changement backend nécessaire.
func _on_player_frame_self_clicked() -> void:
	var my_id := str(GameState.player_stats.get("id", ""))
	if my_id.is_empty():
		return
	Net.send_command("select", my_id)
	_clear_portal_selection()


func _select_next_nearest_monster() -> void:
	var monster_keys: Array = []
	for key in _entities_by_key.keys():
		if key.begins_with("monster:"):
			monster_keys.append(key)
	if monster_keys.is_empty():
		return
	var player_pos := _player_node.position if _player_node != null else Vector3.ZERO
	monster_keys.sort_custom(func(a, b):
		var da: float = (_entities_by_key[a] as Node3D).position.distance_to(player_pos)
		var db: float = (_entities_by_key[b] as Node3D).position.distance_to(player_pos)
		return da < db
	)
	var current_key: String = _key_by_entity_id.get(_selected_target_id, "")
	var start_index := monster_keys.find(current_key)
	var next_index := (start_index + 1) % monster_keys.size() if start_index != -1 else 0
	var node: Node3D = _entities_by_key[monster_keys[next_index]]
	var id := str(node.get_meta("entity_id", ""))
	if not id.is_empty():
		Net.send_command("select", id)


func _apply_selection(target_id: String, target_name: String) -> void:
	if target_id == _selected_target_id:
		return
	_clear_selection()
	if target_id.is_empty():
		return
	_selected_target_id = target_id
	var key: String = _key_by_entity_id.get(target_id, "")
	var vitals: Dictionary = _entity_vitals_by_key.get(key, {"current": 0, "max": 0, "level": 1})
	_target_status_bar.show_target(
		target_name, int(vitals.get("level", 1)), int(vitals.get("current", 0)), int(vitals.get("max", 0))
	)


func _clear_selection() -> void:
	if _selected_target_id.is_empty():
		return
	_selected_target_id = ""
	_target_status_bar.hide_target()
	_npc_menu.hide()


func _update_selection_ring() -> void:
	if _selected_target_id.is_empty():
		_selection_ring.visible = false
		return
	var key: String = _key_by_entity_id.get(_selected_target_id, "")
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		_selection_ring.visible = false
		return
	_selection_ring.position = Vector3(node.position.x, 0.05, node.position.z)
	_selection_ring.visible = true


func is_player_casting() -> bool:
	return _casting_by_key.has(PLAYER_KEY)


## Affiche le cercle de portée autour du joueur (voir Hotbar._on_slot_mouse_entered) tant
## que la souris survole un slot "skill" — la portée n'est jamais vérifiée côté client,
## purement indicatif.
func show_skill_range(range_tiles: float) -> void:
	if _player_node == null or range_tiles <= 0.0:
		return
	if _range_indicator == null:
		_range_indicator = MeshInstance3D.new()
		var torus := TorusMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.8, 1.0, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.8, 1.0)
		mat.emission_energy_multiplier = 0.6
		torus.material = mat
		_range_indicator.mesh = torus
		_world.add_child(_range_indicator)
	var torus_mesh: TorusMesh = _range_indicator.mesh
	torus_mesh.outer_radius = maxf(range_tiles, 0.1)
	torus_mesh.inner_radius = maxf(range_tiles - 0.08, 0.02)
	_range_indicator.position = Vector3(_player_node.position.x, 0.06, _player_node.position.z)
	_range_indicator.visible = true


func hide_skill_range() -> void:
	if _range_indicator != null:
		_range_indicator.visible = false


# ---------------------------------------------------------------------------
# Entités
# ---------------------------------------------------------------------------

func _refresh_entities(view: Dictionary) -> void:
	var self_pos := Vector2(view.get("selfX", 0.0), view.get("selfY", 0.0))
	_ensure_player_node()
	_player_node.position = Vector3(self_pos.x, 0.0, self_pos.y)
	_face_heading(_player_node, float(view.get("selfHeading", 0.0)))
	# _rebuild_map (MapView, toujours reçu juste avant un MapEnter — portail/spawn) efface
	# _key_by_entity_id (_clear_entities) : notre propre UUID doit être ré-enregistré ici pour
	# que _apply_target_current_health nous reconnaisse à nouveau dès la première attaque
	# subie sur la nouvelle carte, sans attendre un éventuel GamePlayerStats. player_stats
	# (GameState) survit lui aux changements de carte, contrairement à ce cache local.
	var my_id := str(GameState.player_stats.get("id", ""))
	if not my_id.is_empty():
		_register_entity_id(PLAYER_KEY, my_id)
		if not _entity_vitals_by_key.has(PLAYER_KEY):
			_entity_vitals_by_key[PLAYER_KEY] = {
				"current": int(GameState.player_stats.get("currentHealth", 0)),
				"max": int(GameState.player_stats.get("maxHealth", 0)),
				"level": int(GameState.player_stats.get("level", 1)),
			}
	# Les occupants de la carte (joueurs/PNJ/monstres à portée) ne sont plus transmis par ce
	# message depuis le commit backend acfb970 (2026-09-03, "Fait de la KnownList l'unique
	# canal de présence des entités") : ils arrivent séparément via EntityAppeared, poussé par
	# KnownList.populate() côté backend au moment du join qui précède l'envoi de ce MapEnter
	# (voir _apply_appeared_entity/_on_message_received) — rien d'autre à faire ici.


## Entité entrant dans notre KnownList (portée de perception) — au spawn/changement de carte
## (juste avant/après le MapEnter correspondant) ou en cours de partie après un déplacement
## (nôtre ou celui de l'entité elle-même), voir CLAUDE.md (commit backend acfb970). Remplace
## à la fois l'ancien diffing par listes de MapEnter (characters/npcs/monsters, supprimées de
## ce message par ce même commit) et MonsterSpawned (supprimé, devenu redondant avec ce
## mécanisme générique).
func _apply_appeared_entity(entry: Dictionary) -> void:
	var entity_id := str(entry.get("id", ""))
	var entity_name := str(entry.get("name", ""))
	if entity_id.is_empty() or entity_name.is_empty():
		return
	if entity_id == str(GameState.player_stats.get("id", "")):
		# Ne devrait jamais arriver (nearbyOthers exclut déjà le personnage lui-même côté
		# backend) — gardé par prudence pour ne jamais dupliquer notre propre capsule.
		return
	# "character"/"npc"/"monster", voir EntityView.kind côté backend (ajouté pour ce commit,
	# calqué tel quel sur ces préfixes de clé déjà utilisés dans tout ce fichier) — repli sur
	# "character" si absent (backend pas encore redémarré avec ce champ).
	var kind := str(entry.get("kind", "character"))
	var color := OTHER_PLAYER_COLOR
	if kind == "monster":
		color = MONSTER_COLOR
	elif kind == "npc":
		color = NPC_COLOR
	# Préfère la clé déjà connue pour cet UUID si elle existe (ex. GamePlayerJoinedMap, diffusé
	# à toute la carte, peut avoir déjà enregistré ce même joueur sous "character:<nom>" juste
	# avant l'EntityAppeared scopé issu de KnownList.populate() pour le même join) : évite de
	# recréer un second nœud pour la même entité.
	var key: String = _key_by_entity_id.get(entity_id, "")
	if key.is_empty():
		# Un nom de personnage est unique (contrainte serveur à la création), mais pas un nom de
		# monstre/PNJ (ex. plusieurs "Fox" sur la même carte) — clé par nom pour "character",
		# par UUID pour "monster"/"npc" sous peine de fusionner plusieurs monstres homonymes sur
		# un seul et même nœud visuel (bug confirmé le 2026-09-03 : un deuxième Fox EntityAppeared
		# réutilisait le nœud du premier via _ensure_entity_node et le téléportait à sa propre
		# position, laissant le Fox proche du joueur invisible).
		if kind == "character":
			key = "%s:%s" % [kind, entity_name]
		else:
			key = "%s:%s" % [kind, entity_id]
	var node := _ensure_entity_node(key, entity_name, color)
	node.position = Vector3(entry.get("x", 0.0), 0.0, entry.get("y", 0.0))
	_set_entity_title(node, _extract_title(entry))
	_face_heading(node, float(entry.get("heading", 0.0)))
	_entity_speed_by_key[key] = float(entry.get("speed", DEFAULT_SPEED_TILES_PER_SEC))
	# EntityView.hasShop côté backend (2026-09-04, "Shop PNJ") : détermine si le clic droit sur
	# ce PNJ, une fois sélectionné, propose "Boutique" (voir _handle_right_click/_open_npc_menu).
	node.set_meta("has_shop", bool(entry.get("hasShop", false)))
	# Détermine si le clic droit propose le menu PNJ ("Parler"/"Boutique") du tout, voir
	# _handle_right_click.
	node.set_meta("kind", kind)
	_register_entity_id(key, entity_id)
	if entry.has("currentHealth") or entry.has("maxHealth"):
		_entity_vitals_by_key[key] = {
			"current": int(entry.get("currentHealth", 0)),
			"max": int(entry.get("maxHealth", 0)),
			"level": int(entry.get("level", 1)),
		}

	var target_x = entry.get("targetX")
	var target_y = entry.get("targetY")
	if target_x != null and target_y != null:
		_moving[key] = {"target": Vector3(float(target_x), 0.0, float(target_y))}
	else:
		_moving.erase(key)


## Entité sortant de notre KnownList — hors de portée après un déplacement, ou départ
## définitif de la carte (leave/disconnect/mort d'un monstre), voir CLAUDE.md. Simple retrait
## sans effet particulier : le grisement/fondu de la mort d'un monstre reste géré par
## MonsterDefeated (_despawn_monster, toujours diffusé séparément côté backend), qui a déjà
## retiré son nœud de _entities_by_key avant qu'EntityDisappeared n'arrive pour la même
## entité dans ce cas précis — _remove_entity no-op alors silencieusement (clé déjà absente).
func _on_entity_disappeared(entity_id: String) -> void:
	if entity_id.is_empty() or entity_id == str(GameState.player_stats.get("id", "")):
		return
	var key: String = _key_by_entity_id.get(entity_id, "")
	if not key.is_empty() and key != PLAYER_KEY:
		_remove_entity(key)


func _ensure_player_node() -> void:
	if _player_node != null:
		return
	var player_name := str(GameState.player_stats.get("name", "Vous"))
	# pickable = false : on ne se sélectionne pas soi-même (voir _make_entity_node/
	# _pick_entity_id_at_mouse — aucune PickArea créée pour cette capsule).
	_player_node = _make_entity_node(player_name, PLAYER_COLOR, false)
	_set_entity_title(_player_node, _extract_title(GameState.player_stats))
	_entities_root.add_child(_player_node)
	_entities_by_key[PLAYER_KEY] = _player_node
	_ensure_bars(PLAYER_KEY)


func _ensure_entity_node(key: String, entity_name: String, color: Color) -> Node3D:
	if _entities_by_key.has(key):
		return _entities_by_key[key]
	var node := _make_entity_node(entity_name, color, true)
	_entities_root.add_child(node)
	_entities_by_key[key] = node
	_ensure_bars(key)
	return node


## Capsule colorée + nom flottant (Label3D, toujours face caméra) — pas d'art directionnel
## disponible pour ce prototype, contrairement au client 2D qui a au moins des portraits ;
## ce sera le premier axe à enrichir (rig + squelette + attach points d'équipement) une
## fois la direction 3D validée.
func _make_entity_node(entity_name: String, color: Color, pickable: bool) -> Node3D:
	var root := Node3D.new()
	root.name = entity_name if not entity_name.is_empty() else "Entity"
	# Godot renomme silencieusement les nœuds enfants homonymes (ex. "Fox" -> "Fox2") pour
	# garder des noms de frères et sœurs uniques sous _entities_root : root.name n'est donc pas
	# fiable pour retrouver un monstre par son nom serveur (voir _despawn_monster) une fois
	# plusieurs monstres homonymes présents — meta séparée, jamais réécrite par le moteur.
	root.set_meta("entity_name", entity_name)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	capsule.material = mat
	body.mesh = capsule
	body.position = Vector3(0.0, 0.8, 0.0)
	root.add_child(body)

	if pickable:
		# Zone de collision calquée exactement sur la capsule visuelle (même rayon/hauteur,
		# même décalage vertical) : voir _pick_entity_id_at_mouse pour la requête qui la
		# vise. L'UUID réseau à sélectionner (voir _register_entity_id) est lu directement
		# sur `root` via sa meta "entity_id", pas sur cette zone elle-même.
		var pick_area := Area3D.new()
		pick_area.name = "PickArea"
		pick_area.collision_layer = ENTITY_PICK_COLLISION_LAYER
		pick_area.collision_mask = 0
		pick_area.position = body.position
		var pick_shape := CollisionShape3D.new()
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = capsule.radius
		capsule_shape.height = capsule.height
		pick_shape.shape = capsule_shape
		pick_area.add_child(pick_shape)
		root.add_child(pick_area)

	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = entity_name
	# Décalage recalculé le 2026-09-03 (le nom empiétait sur la barre de vie) : avec
	# font_size=120 et l'alignement vertical CENTER par défaut, le nom mesure 0.825 unité de
	# haut (Label3D.get_aabb() mesuré en isolation dans ce projet) et s'étend donc pour moitié
	# de chaque côté de sa position. CAST_BAR_OFFSET_Y + CAST_BAR_HEIGHT/2 = 2.55 est le sommet
	# de la barre la plus haute (l'incantation) : 3.15 - 0.825/2 = 2.7375 laisse une marge
	# d'environ 0.19 unité au-dessus, donc plus aucun chevauchement avec les deux barres.
	label.position = Vector3(0.0, 3.15, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# Encore signalé trop petit à 60 (2026-09-02, deuxième passe) : la caméra orthogonale ne
	# rapetisse pas le texte avec la distance (voir CLAUDE.md — pas de perspective), donc c'est
	# uniquement une question de taille de police absolue, pas de zoom/distance.
	label.font_size = 120
	label.outline_size = 18
	label.modulate = color.lightened(0.5)
	root.add_child(label)

	# Titre (fonction/rang, voir TITLE_LABEL_COLOR) : au-dessus du nom, pas trop haut. Même
	# hypothèse de mise à l'échelle linéaire avec font_size que le calcul de NameLabel ci-dessus
	# (0.825 unité de haut pour font_size=120) : à font_size=72, hauteur ≈ 0.825*72/120=0.495.
	# Nom : centre 3.15, sommet 3.15+0.825/2=3.5625. Titre centré à 3.5625+0.15 (marge)+0.495/2 ≈
	# 3.96. Texte vide par défaut (la plupart des entités n'ont pas de titre) : un Label3D sans
	# texte ne dessine rien, pas besoin de le cacher explicitement.
	var title_label := Label3D.new()
	title_label.name = "TitleLabel"
	title_label.text = ""
	title_label.position = Vector3(0.0, 3.96, 0.0)
	title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title_label.no_depth_test = true
	title_label.font_size = 72
	title_label.outline_size = 14
	title_label.modulate = TITLE_LABEL_COLOR
	root.add_child(title_label)

	return root


## AbstractObject.title côté backend vaut `null` (pas "") quand aucun titre n'est défini —
## `entry.get("title", "")` renverrait ce `null` tel quel (la clé EST présente), d'où ce garde-fou.
func _extract_title(entry: Dictionary) -> String:
	var raw = entry.get("title")
	return raw if raw is String else ""


func _set_entity_label(node: Node3D, text: String) -> void:
	if text.is_empty():
		return
	for child in node.get_children():
		if child is Label3D and child.name == "NameLabel":
			child.text = text
			return


## Contrairement à _set_entity_label (nom, jamais vide en pratique) : un titre vide est un cas
## normal (la plupart des entités n'en ont pas, voir AbstractObject.title côté backend, null par
## défaut) et doit bien effacer un ancien titre affiché plutôt que d'être ignoré.
func _set_entity_title(node: Node3D, text: String) -> void:
	for child in node.get_children():
		if child is Label3D and child.name == "TitleLabel":
			child.text = text
			return


func _remove_entity(key: String) -> void:
	var node: Node3D = _entities_by_key.get(key)
	if node != null:
		node.queue_free()
	_entities_by_key.erase(key)
	_moving.erase(key)
	_entity_speed_by_key.erase(key)
	_entity_vitals_by_key.erase(key)
	_casting_by_key.erase(key)
	_free_bars(key)
	for id in _key_by_entity_id.keys().duplicate():
		if _key_by_entity_id[id] == key:
			if id == _selected_target_id:
				_clear_selection()
			_key_by_entity_id.erase(id)


func _clear_entities() -> void:
	for child in _entities_root.get_children():
		child.queue_free()
	for key in _entity_bars_by_key.keys().duplicate():
		_free_bars(key)
	_entities_by_key.clear()
	_key_by_entity_id.clear()
	_entity_speed_by_key.clear()
	_entity_vitals_by_key.clear()
	_casting_by_key.clear()
	_moving.clear()
	_player_node = null
	_clear_selection()


func _register_entity_id(key: String, id: String) -> void:
	if id.is_empty():
		return
	_key_by_entity_id[id] = key
	var node: Node3D = _entities_by_key.get(key)
	if node != null:
		node.set_meta("entity_id", id)


## Comme côté client 2D (voir Game.gd::_resolve_movement_event_key) : un nom de monstre
## n'est pas unique, on résout d'abord par UUID (déjà connu via EntityAppeared) et
## on ne retombe sur "character:<nom>" que pour un joueur pas encore vu autrement.
func _resolve_movement_key(character_id: String, character_name: String) -> String:
	if not character_id.is_empty() and _key_by_entity_id.has(character_id):
		return _key_by_entity_id[character_id]
	return "character:%s" % character_name


## Retrouve le nœud d'affichage d'une entité (soi-même inclus) par son UUID — null si cet
## UUID n'a jamais été appris localement ou ne correspond à aucune entité visible.
func _entity_node_by_id(entity_id: String) -> Node3D:
	if entity_id.is_empty():
		return null
	if entity_id == str(GameState.player_stats.get("id", "")):
		return _player_node
	var key: String = _key_by_entity_id.get(entity_id, "")
	if key.is_empty():
		return null
	return _entities_by_key.get(key)


## Clé locale (voir _entities_by_key) pour un UUID donné, PLAYER_KEY pour nous-même.
func _key_for_entity_id(entity_id: String) -> String:
	if entity_id.is_empty():
		return ""
	if entity_id == str(GameState.player_stats.get("id", "")):
		return PLAYER_KEY
	return _key_by_entity_id.get(entity_id, "")


func _face_heading(node: Node3D, heading: float) -> void:
	var dir := Vector3(cos(heading), 0.0, sin(heading))
	if dir.length_squared() < 0.0001:
		return
	var target := node.position + dir
	if target.is_equal_approx(node.position):
		return
	node.look_at(target, WORLD_UP)


func _step_movement(delta: float) -> void:
	for key in _moving.keys().duplicate():
		var node: Node3D = _entities_by_key.get(key)
		if node == null:
			_moving.erase(key)
			continue
		var target: Vector3 = _moving[key].target
		var speed: float = _entity_speed_by_key.get(key, DEFAULT_SPEED_TILES_PER_SEC)
		node.position = node.position.move_toward(target, speed * delta)
		if node.position.distance_to(target) < 0.02:
			_moving.erase(key)


func _player_speed() -> float:
	return float(GameState.player_stats.get("speed", DEFAULT_SPEED_TILES_PER_SEC))


# ---------------------------------------------------------------------------
# Barres flottantes (vie/incantation)
# ---------------------------------------------------------------------------

func _ensure_bars(key: String) -> void:
	if _entity_bars_by_key.has(key):
		return
	var entry := {}
	if key != PLAYER_KEY:
		entry["hp"] = _make_floating_bar(HP_BAR_COLOR, HP_BAR_BG_COLOR, BAR_WIDTH, BAR_HEIGHT, false)
	# Pilule aux bords arrondis (voir _make_rounded_progress_bar), pas les quads plats de
	# _make_floating_bar utilisés par la barre de vie : demandé explicitement le 2026-09-03
	# (troisième passe) après que le rendu plat+sombre a de nouveau été jugé peu lisible/pas
	# assez joli.
	entry["cast"] = _make_rounded_progress_bar(CAST_BAR_BG_COLOR, CAST_BAR_COLOR, CAST_BAR_WIDTH, CAST_BAR_HEIGHT)
	_entity_bars_by_key[key] = entry


func _free_bars(key: String) -> void:
	if not _entity_bars_by_key.has(key):
		return
	var entry: Dictionary = _entity_bars_by_key[key]
	if entry.has("hp"):
		entry["hp"]["root"].queue_free()
	if entry.has("cast"):
		entry["cast"]["root"].queue_free()
	_entity_bars_by_key.erase(key)


## Barre billboard (fond + remplissage ancré à gauche) : root est manuellement orienté
## face caméra chaque frame (voir _billboard_node) plutôt que via BILLBOARD_ENABLED sur
## chaque quad, pour que fond/remplissage tournent comme un seul bloc rigide. `emissive_fill`
## fait rayonner uniquement le remplissage (jamais le fond, qui doit rester sombre) — voir
## _make_bar_quad.
func _make_floating_bar(
	fill_color: Color, bg_color: Color, width: float, height: float, emissive_fill: bool
) -> Dictionary:
	var root := Node3D.new()
	var bg := _make_bar_quad(bg_color, width, height, false)
	root.add_child(bg)

	var fill_pivot := Node3D.new()
	fill_pivot.position = Vector3(-width / 2.0, 0.0, 0.001)
	root.add_child(fill_pivot)
	var fill := _make_bar_quad(fill_color, width, height, emissive_fill)
	fill.position = Vector3(width / 2.0, 0.0, 0.0)
	fill_pivot.add_child(fill)

	root.visible = false
	_world.add_child(root)
	return {"root": root, "fill_pivot": fill_pivot}


func _make_bar_quad(color: Color, width: float, height: float, emissive: bool) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	# Le sens exact de _billboard_node (copie de la base caméra) n'est pas garanti face à la
	# normale par défaut du QuadMesh : on désactive le culling plutôt que de risquer une
	# barre invisible selon l'orientation.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	mesh_instance.mesh = quad
	return mesh_instance


## Shader de la barre d'incantation (2026-09-03, troisième passe) : un seul quad plutôt que
## les deux quads fond+remplissage de _make_bar_quad, pour dessiner fond ET remplissage comme
## une seule pilule aux bords arrondis (SDF de rectangle arrondi, `corner_radius` égal à la
## demi-hauteur ⇒ bouts parfaitement semi-circulaires). `ALPHA` vaut toujours 0 ou 1 (un
## `discard` en dehors de la pilule, pas de dégradé) : aucune transparence sur la barre
## elle-même, seul le contour est légèrement lissé via `fwidth` pour éviter l'aliasing en
## dents de scie d'un bord dur. Remplacer `fill_ratio` (uniform, mis à jour à chaque frame
## dans _update_bars) suffit à faire avancer le remplissage — pas de scale ni de fill_pivot
## comme pour les barres plates, donc aucune distorsion du bord arrondi quand le ratio change.
const ROUNDED_BAR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, specular_disabled;

uniform vec4 bg_color : source_color = vec4(0.08, 0.22, 0.5, 1.0);
uniform vec4 fill_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 4.0;

float rounded_box_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 d = abs(p) - half_size + radius;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float dist = rounded_box_sdf(p, half_size, half_size.y);
	float edge = max(fwidth(dist), 0.001);
	float shape_alpha = 1.0 - smoothstep(-edge, edge, dist);
	if (shape_alpha <= 0.001) {
		discard;
	}
	float is_fill = step(UV.x, fill_ratio);
	ALBEDO = mix(bg_color.rgb, fill_color.rgb, is_fill);
	EMISSION = fill_color.rgb * is_fill * 1.3;
	ALPHA = shape_alpha;
}
"""


## Pilule pleine (fond + remplissage dans un seul quad, voir ROUNDED_BAR_SHADER_CODE) utilisée
## par la barre d'incantation. `bar.material.set_shader_parameter("fill_ratio", ...)` fait
## avancer le remplissage — voir _update_bars, qui ne passe donc pas par _set_bar_ratio (pensé
## pour les barres plates fond+remplissage de _make_floating_bar/_make_bar_quad).
func _make_rounded_progress_bar(bg_color: Color, fill_color: Color, width: float, height: float) -> Dictionary:
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var shader := Shader.new()
	shader.code = ROUNDED_BAR_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("bg_color", bg_color)
	mat.set_shader_parameter("fill_color", fill_color)
	mat.set_shader_parameter("fill_ratio", 1.0)
	mat.set_shader_parameter("aspect", width / height)
	quad.material = mat
	mesh_instance.mesh = quad
	mesh_instance.visible = false
	_world.add_child(mesh_instance)
	return {"root": mesh_instance, "material": mat}


func _set_bar_ratio(bar: Dictionary, ratio: float) -> void:
	bar.fill_pivot.scale.x = clampf(ratio, 0.0, 1.0)


func _billboard_node(node: Node3D) -> void:
	node.global_transform.basis = _camera.global_transform.basis


func _update_bars() -> void:
	for key in _entity_bars_by_key.keys():
		var node: Node3D = _entities_by_key.get(key)
		if node == null:
			continue
		var bars: Dictionary = _entity_bars_by_key[key]
		if bars.has("hp"):
			var hp_bar: Dictionary = bars["hp"]
			var vitals: Dictionary = _entity_vitals_by_key.get(key, {})
			var max_hp := int(vitals.get("max", 0))
			if max_hp > 0:
				_set_bar_ratio(hp_bar, float(vitals.get("current", 0)) / float(max_hp))
				hp_bar.root.position = node.position + Vector3(0, HP_BAR_OFFSET_Y, 0)
				_billboard_node(hp_bar.root)
				hp_bar.root.visible = true
			else:
				hp_bar.root.visible = false
		if bars.has("cast"):
			var cast_bar: Dictionary = bars["cast"]
			if _casting_by_key.has(key):
				var cast_state: Dictionary = _casting_by_key[key]
				var total_ms: float = cast_state.get("total_ms", 0.0)
				var ratio := clampf(cast_state.get("elapsed_ms", 0.0) / total_ms, 0.0, 1.0) if total_ms > 0.0 else 0.0
				cast_bar.material.set_shader_parameter("fill_ratio", ratio)
				cast_bar.root.position = node.position + Vector3(0, CAST_BAR_OFFSET_Y, 0)
				_billboard_node(cast_bar.root)
				cast_bar.root.visible = true
			else:
				cast_bar.root.visible = false


func _advance_casting(delta: float) -> void:
	for key in _casting_by_key.keys().duplicate():
		var state: Dictionary = _casting_by_key[key]
		state.elapsed_ms += delta * 1000.0
		if state.has("wind_timer_ms"):
			state.wind_timer_ms += delta * 1000.0
			if state.wind_timer_ms >= WIND_WISP_SPAWN_INTERVAL_MS:
				state.wind_timer_ms = 0.0
				_spawn_wind_wisp(key)
		if state.elapsed_ms >= state.total_ms:
			_clear_casting(key)


# ---------------------------------------------------------------------------
# Attaque / sorts — feedback visuel
# ---------------------------------------------------------------------------

func _flash_entity_by_id(entity_id: String) -> void:
	var node := _entity_node_by_id(entity_id)
	if node != null:
		_flash_entity(node)


func _flash_entity(
	node: Node3D, color: Color = Color(1.0, 0.3, 0.3),
	up_duration: float = 0.05, down_duration: float = 0.15
) -> void:
	var body := node.get_node_or_null("Body") as MeshInstance3D
	if body == null or body.mesh == null or body.mesh.material == null:
		return
	var mat: StandardMaterial3D = body.mesh.material
	var original := mat.albedo_color
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color", color, up_duration)
	tween.tween_property(mat, "albedo_color", original, down_duration)


## Attaché comme enfant de l'entité visée (position locale) plutôt que placé une fois en
## coordonnées monde : sinon le nombre reste figé à l'endroit où était la cible au moment de
## l'impact et se détache visiblement d'elle si elle continue de se déplacer pendant
## l'animation (bug signalé le 2026-09-02 — "l'indicateur doit être au-dessus du personnage
## qui se fait attaquer"). En enfant, il suit sa position (et sa rotation Y, sans effet sur un
## décalage purement vertical) à chaque frame gratuitement, sans code de suivi dédié.
func _show_damage_number(node: Node3D, amount: int, critical: bool) -> void:
	if node == null:
		return
	var label := Label3D.new()
	label.text = str(amount)
	label.font_size = 46 if critical else 36
	label.outline_size = 8
	label.modulate = DAMAGE_NUMBER_COLOR_CRITICAL if critical else DAMAGE_NUMBER_COLOR_NORMAL
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(randf_range(-0.3, 0.3), 2.3, 0.0)
	node.add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + DAMAGE_NUMBER_RISE, DAMAGE_NUMBER_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, DAMAGE_NUMBER_DURATION - DAMAGE_NUMBER_FADE_START).set_delay(
		DAMAGE_NUMBER_FADE_START
	)
	tween.chain().tween_callback(label.queue_free)


## Met à jour la vie d'une entité déjà résolue par UUID. `max_health` absent (-1) pour
## AttackResult, qui ne porte que le HP courant de la cible : le maximum déjà connu
## (EntityAppeared/cast précédent) est conservé plutôt qu'écrasé à 0.
func _apply_target_current_health(target_id: String, current_health: int, max_health: int = -1) -> void:
	var key: String = _key_by_entity_id.get(target_id, "")
	if key.is_empty():
		return
	var existing: Dictionary = _entity_vitals_by_key.get(key, {"current": 0, "max": 0, "level": 1})
	var resolved_max := max_health if max_health >= 0 else int(existing.get("max", 0))
	_entity_vitals_by_key[key] = {
		"current": current_health, "max": resolved_max, "level": existing.get("level", 1),
	}
	if target_id == _selected_target_id:
		_target_status_bar.set_health(current_health, resolved_max)


func _on_skill_cast_started(payload: Dictionary) -> void:
	var caster_id := str(payload.get("casterId", ""))
	var total_ms := float(payload.get("castingTimeMs", 0))
	var key := _key_for_entity_id(caster_id)
	if key.is_empty() or total_ms <= 0.0:
		return
	var skill_name := str(payload.get("skillName", ""))
	var state := {"elapsed_ms": 0.0, "total_ms": total_ms}
	if skill_name in WIND_CAST_ANIMATION_SKILLS:
		state["wind_timer_ms"] = 0.0
		state["skill_name"] = skill_name
	_casting_by_key[key] = state
	if _skill_visual_kind(skill_name) == SkillVisualKind.HEAL:
		var caster_node: Node3D = _entities_by_key.get(key)
		if caster_node != null:
			_play_heal_cast_effect(caster_node)


func _clear_casting(key: String) -> void:
	if key.is_empty():
		return
	_casting_by_key.erase(key)


func _skill_visual_kind(skill_name: String) -> int:
	return SKILL_VISUAL_KIND_BY_NAME.get(skill_name, SKILL_VISUAL_KIND_DEFAULT)


func _skill_visual_color(skill_name: String) -> Color:
	return SKILL_VISUAL_COLOR_BY_KIND.get(_skill_visual_kind(skill_name), Color.WHITE)


## Anime l'impact d'un sort sur sa cible : une pulsation colorée pour un soin/buff/debuff
## (portée "toucher" côté backend, pas de trajectoire à montrer), un flash pour un sort à
## dégâts sans projectile (voir NON_PROJECTILE_DAMAGE_SKILLS). Un sort à dégâts AVEC
## projectile est animé séparément, dès son lancer, par _on_skill_projectile_launched.
func _play_skill_animation(target_id: String, skill_name: String) -> void:
	var target_node := _entity_node_by_id(target_id)
	if target_node == null:
		return
	var kind := _skill_visual_kind(skill_name)
	if kind == SkillVisualKind.HEAL:
		_play_heal_target_effect(target_node)
	elif kind == SkillVisualKind.BUFF or kind == SkillVisualKind.DEBUFF:
		_play_skill_pulse(target_node, kind)
	elif skill_name in NON_PROJECTILE_DAMAGE_SKILLS:
		_flash_entity(target_node)


func _on_skill_projectile_launched(payload: Dictionary) -> void:
	var caster_node := _entity_node_by_id(str(payload.get("casterId", "")))
	var target_node := _entity_node_by_id(str(payload.get("targetId", "")))
	if caster_node == null or target_node == null or caster_node == target_node:
		return
	var color := _skill_visual_color(str(payload.get("skillName", "")))
	var duration_sec := maxf(float(payload.get("travelDurationMs", 0)) / 1000.0, 0.05)
	_play_skill_projectile(caster_node, target_node, color, duration_sec)


func _play_skill_projectile(caster_node: Node3D, target_node: Node3D, color: Color, duration_sec: float) -> void:
	var projectile := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	sphere.material = mat
	projectile.mesh = sphere
	projectile.position = caster_node.position + Vector3(0, 1.0, 0)
	_world.add_child(projectile)

	var target_pos := target_node.position + Vector3(0, 1.0, 0)
	var tween := create_tween()
	tween.tween_property(projectile, "position", target_pos, duration_sec)
	tween.finished.connect(func() -> void:
		projectile.queue_free()
		_flash_entity(target_node)
	)


func _play_skill_pulse(target_node: Node3D, kind: int) -> void:
	var color: Color = SKILL_VISUAL_COLOR_BY_KIND.get(kind, Color.WHITE)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = mat
	ring.mesh = torus
	ring.position = target_node.position + Vector3(0, 0.1, 0)
	_world.add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 2.0, 0.45)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(ring.queue_free)


## Dégradé alpha 1 → 0 (avec un palier intermédiaire pour éviter une extinction trop linéaire)
## appliqué au color_ramp d'un ParticleProcessMaterial, pour que les particules d'un effet en
## one-shot s'estompent progressivement plutôt que de disparaître d'un coup en fin de vie —
## voir _play_heal_cast_effect/_play_heal_target_effect.
func _fade_out_color_ramp(color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 1.0))
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.65, Color(color.r, color.g, color.b, 0.7))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Effet de sol joué une seule fois au tout début de l'incantation d'un sort de soin (voir
## _on_skill_cast_started) : un burst sphérique de particules jaunes qui jaillissent du sol
## (le "pop" initial) accompagné d'une flare verticale lumineuse qui jaillit puis s'estompe —
## demande du 2026-09-06 ("animation sur le sol, jaune... burst de particules sphérique avec
## une flare verticale et des textures qui brillent doucement"). Remplace l'ancien souffle
## tourbillonnant partagé avec Wind Strike (voir WIND_CAST_ANIMATION_SKILLS ci-dessus).
func _play_heal_cast_effect(caster_node: Node3D) -> void:
	var color: Color = SKILL_VISUAL_COLOR_BY_KIND[SkillVisualKind.HEAL]
	var base_pos := caster_node.position + Vector3(0, 0.03, 0)

	var particles := GPUParticles3D.new()
	particles.position = base_pos
	particles.amount = HEAL_CAST_BURST_AMOUNT
	particles.lifetime = HEAL_CAST_BURST_LIFETIME
	particles.one_shot = true
	particles.local_coords = false

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	var particle_mat := StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.emission_enabled = true
	particle_mat.emission = color
	particle_mat.emission_energy_multiplier = 2.5
	particle_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = particle_mat
	particles.draw_pass_1 = quad

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 60.0
	process_mat.initial_velocity_min = 0.8
	process_mat.initial_velocity_max = 1.6
	process_mat.gravity = Vector3(0.0, -1.4, 0.0)
	process_mat.scale_min = 0.5
	process_mat.scale_max = 1.1
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process_mat.emission_sphere_radius = 0.25
	process_mat.color = color
	process_mat.color_ramp = _fade_out_color_ramp(color)
	particles.process_material = process_mat

	_world.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

	# Flare verticale : un cône fin qui jaillit du sol puis s'estompe, pour la "vertical flare"
	# demandée en plus du burst de particules.
	var flare := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.16
	cone.height = 1.0
	var flare_mat := StandardMaterial3D.new()
	flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_mat.emission_enabled = true
	flare_mat.emission = Color(1.0, 0.95, 0.6)
	flare_mat.emission_energy_multiplier = 3.0
	flare_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.75)
	cone.material = flare_mat
	flare.mesh = cone
	flare.position = base_pos
	flare.scale = Vector3(0.25, 0.01, 0.25)
	_world.add_child(flare)

	var flare_tween := create_tween()
	flare_tween.set_parallel(true)
	flare_tween.tween_property(
		flare, "scale", Vector3(1.0, HEAL_CAST_FLARE_HEIGHT, 1.0), HEAL_CAST_FLARE_DURATION * 0.4
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flare_tween.tween_property(
		flare_mat, "albedo_color:a", 0.0, HEAL_CAST_FLARE_DURATION
	).set_delay(HEAL_CAST_FLARE_DURATION * 0.3)
	flare_tween.chain().tween_callback(flare.queue_free)


## Effet joué à l'impact d'un soin sur sa cible (voir _play_skill_animation) : un anneau
## lumineux immédiat (même pulsation que _play_skill_pulse) puis une volée de particules
## jaunes qui montent en tourbillonnant autour du personnage pendant HEAL_TARGET_EFFECT_
## DURATION (2 à 3 secondes, demande du 2026-09-06) — bien plus long que l'ancienne pulsation
## de 0.45s, réservée depuis à BUFF/DEBUFF.
func _play_heal_target_effect(target_node: Node3D) -> void:
	var color: Color = SKILL_VISUAL_COLOR_BY_KIND[SkillVisualKind.HEAL]
	_play_skill_pulse(target_node, SkillVisualKind.HEAL)

	var particles := GPUParticles3D.new()
	particles.position = target_node.position + Vector3(0, 0.05, 0)
	particles.amount = HEAL_TARGET_PARTICLE_AMOUNT
	particles.lifetime = HEAL_TARGET_EFFECT_DURATION
	particles.one_shot = true
	particles.explosiveness = 0.15
	particles.local_coords = false

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.16
	var particle_mat := StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.emission_enabled = true
	particle_mat.emission = color
	particle_mat.emission_energy_multiplier = 2.0
	particle_mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = particle_mat
	particles.draw_pass_1 = quad

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 10.0
	process_mat.initial_velocity_min = 0.6
	process_mat.initial_velocity_max = 1.0
	process_mat.gravity = Vector3.ZERO
	process_mat.damping_min = 0.25
	process_mat.damping_max = 0.55
	process_mat.scale_min = 0.5
	process_mat.scale_max = 1.0
	process_mat.angular_velocity_min = -60.0
	process_mat.angular_velocity_max = 60.0
	process_mat.orbit_velocity_min = 0.15
	process_mat.orbit_velocity_max = 0.3
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process_mat.emission_ring_radius = 0.45
	process_mat.emission_ring_inner_radius = 0.35
	process_mat.emission_ring_height = 0.1
	process_mat.emission_ring_axis = Vector3(0, 1, 0)
	process_mat.color = color
	process_mat.color_ramp = _fade_out_color_ramp(color)
	particles.process_material = process_mat

	_world.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Un souffle léger qui part du bas du lanceur (au ras du sol) vers le haut, répété toutes
## les WIND_WISP_SPAWN_INTERVAL_MS pendant l'incantation d'un sort de WIND_CAST_ANIMATION_
## SKILLS (voir _advance_casting) — purement cosmétique, distinct de l'impact sur la cible
## (_play_skill_animation/_play_skill_projectile), qui reste inchangé.
func _spawn_wind_wisp(key: String) -> void:
	var caster_node: Node3D = _entities_by_key.get(key)
	if caster_node == null:
		return
	# Deux souffles de part et d'autre (angle et angle+PI) pour que l'effet encercle bien le
	# lanceur au lieu de n'apparaître que d'un seul côté.
	var angle := randf() * TAU
	_spawn_wind_wisp_at(caster_node, angle, WIND_WISP_COLOR)
	_spawn_wind_wisp_at(caster_node, angle + PI, WIND_WISP_COLOR)


func _spawn_wind_wisp_at(caster_node: Node3D, angle: float, color: Color) -> void:
	var radius := randf_range(WIND_WISP_RADIUS_MIN, WIND_WISP_RADIUS_MAX)
	var wisp := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = WIND_WISP_SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	wisp.mesh = quad
	wisp.position = caster_node.position + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
	_world.add_child(wisp)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wisp, "position:y", wisp.position.y + WIND_WISP_RISE_HEIGHT, WIND_WISP_DURATION)
	tween.tween_property(mat, "albedo_color:a", 0.0, WIND_WISP_DURATION)
	tween.chain().tween_callback(wisp.queue_free)


## Résultat de notre propre incantation (envoyé uniquement au lanceur). selfHeal :
## targetCurrentHealth/targetMaxHealth décrivent alors le lanceur lui-même (toujours nous).
func _on_own_cast_result(payload: Dictionary) -> void:
	var target_id := str(payload.get("targetId", ""))
	var skill_name := str(payload.get("skillName", ""))
	if bool(payload.get("selfHeal", false)):
		# Bug corrigé le 2026-09-03 (voir CLAUDE.md) : targetCurrentHealth/targetMaxHealth
		# décrivent bien le lanceur (toujours nous ici, voir doc de fonction ci-dessus) mais
		# n'étaient jusqu'ici jamais appliqués — se soigner soi-même ne mettait à jour ni la
		# barre flottante ni le HUD, malgré la donnée déjà présente dans le payload.
		_apply_target_current_health(
			target_id, int(payload.get("targetCurrentHealth", 0)), int(payload.get("targetMaxHealth", 0))
		)
		_play_skill_animation(target_id, skill_name)
		return
	_apply_target_current_health(
		target_id, int(payload.get("targetCurrentHealth", 0)), int(payload.get("targetMaxHealth", 0))
	)
	if bool(payload.get("hit", false)):
		var amount := int(payload.get("amount", 0))
		if amount > 0:
			_show_damage_number(_entity_node_by_id(target_id), amount, false)
	_play_skill_animation(target_id, skill_name)


## Sort d'un AUTRE lanceur observé ou subi (diffusé à toute la zone SAUF au lanceur, qui a
## déjà reçu CastResult). Porte le HP absolu de la cible (targetHealthAfter), contrairement
## à AttackResult qui n'a que le HP courant.
func _on_skill_cast_announced(payload: Dictionary) -> void:
	var target_id := str(payload.get("targetId", ""))
	var skill_name := str(payload.get("skillName", ""))
	if bool(payload.get("selfHeal", false)):
		# Même correctif que _on_own_cast_result ci-dessus : ce cas couvre un AUTRE lanceur qui
		# se soigne lui-même, sous nos yeux — sa barre flottante doit suivre, même si ce n'est
		# jamais nous la cible.
		_apply_target_current_health(
			target_id, int(payload.get("targetHealthAfter", 0)), int(payload.get("targetMaxHealth", 0))
		)
		_play_skill_animation(target_id, skill_name)
		return
	_apply_target_current_health(
		target_id, int(payload.get("targetHealthAfter", 0)), int(payload.get("targetMaxHealth", 0))
	)
	if bool(payload.get("hit", false)):
		var amount := int(payload.get("amount", 0))
		if amount > 0:
			_show_damage_number(_entity_node_by_id(target_id), amount, false)
	_play_skill_animation(target_id, skill_name)


# ---------------------------------------------------------------------------
# Spawn / mort des monstres
# ---------------------------------------------------------------------------

## Le monstre est déjà retiré côté serveur à ce stade, donc rien ne le fera réapparaître
## dans un futur MapEnter : on grise son corps immédiatement puis on le fait disparaître
## après un court délai, plutôt que de le retirer instantanément.
func _despawn_monster(monster_name: String) -> void:
	# MonsterDefeated ne porte que le nom (pas d'UUID, voir app.network.message.ingame.
	# MonsterDefeated côté backend) — ambigu s'il existe plusieurs monstres homonymes en vie
	# à la fois (rare en pratique, aucun meilleur moyen de résoudre sans changement backend) :
	# on prend le premier nœud "monster:<uuid>" (voir _apply_appeared_entity, clé désormais par
	# UUID) dont le nom affiché correspond.
	var key := ""
	for candidate_key in _entities_by_key.keys():
		var candidate_node: Node3D = _entities_by_key[candidate_key]
		if candidate_key.begins_with("monster:") and str(candidate_node.get_meta("entity_name", "")) == monster_name:
			key = candidate_key
			break
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		return

	var monster_id := ""
	for id in _key_by_entity_id.keys():
		if _key_by_entity_id[id] == key:
			monster_id = id
			break

	_entities_by_key.erase(key)
	_moving.erase(key)
	_entity_speed_by_key.erase(key)
	_entity_vitals_by_key.erase(key)
	_casting_by_key.erase(key)
	_free_bars(key)
	if not monster_id.is_empty():
		_key_by_entity_id.erase(monster_id)
		if monster_id == _selected_target_id:
			_clear_selection()

	var body := node.get_node_or_null("Body") as MeshInstance3D
	if body != null and body.mesh != null and body.mesh.material != null:
		(body.mesh.material as StandardMaterial3D).albedo_color = MONSTER_DEATH_GREY_COLOR

	var tween := create_tween()
	tween.tween_interval(MONSTER_DEATH_GREY_DELAY)
	tween.tween_method(func(t: float): _set_node_transparency(node, t), 0.0, 1.0, MONSTER_DEATH_FADE_DURATION)
	tween.tween_callback(node.queue_free)


func _set_node_transparency(node: Node3D, t: float) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.transparency = t


# ---------------------------------------------------------------------------
# Caméra isométrique fixe + déplacement au clic
# ---------------------------------------------------------------------------

func _zoom_camera(delta: float) -> void:
	_camera_size = clampf(_camera_size + delta, CAMERA_SIZE_MIN, CAMERA_SIZE_MAX)
	_camera.size = _camera_size
	_minimap.set_camera_zoom(_camera_size)


func _ground_point_at_mouse():
	var mouse_pos := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


func _try_send_goto_at_mouse() -> void:
	var point = _ground_point_at_mouse()
	if point == null:
		return
	var target := Vector2(point.x, point.z)
	if not _is_walkable(target):
		return
	Net.send_command("goto", "%.2f %.2f" % [target.x, target.y])
	_show_move_marker(target)


func _make_move_marker() -> void:
	_move_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.4
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.95, 0.85, 0.45)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(0.95, 0.85, 0.45)
	marker_mat.emission_energy_multiplier = 1.2
	torus.material = marker_mat
	_move_marker.mesh = torus
	_move_marker.visible = false
	_world.add_child(_move_marker)


func _show_move_marker(pos: Vector2) -> void:
	_move_marker.position = Vector3(pos.x, 0.05, pos.y)
	_move_marker.visible = true


func _hide_move_marker() -> void:
	_move_marker.visible = false


func _make_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.56
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SELECTION_COLOR
	mat.emission_enabled = true
	mat.emission = SELECTION_COLOR
	mat.emission_energy_multiplier = 1.4
	torus.material = mat
	_selection_ring.mesh = torus
	_selection_ring.visible = false
	_world.add_child(_selection_ring)


# ---------------------------------------------------------------------------
# HUD minimal
# ---------------------------------------------------------------------------

## Nom de carte + coordonnées : affichés sous la minimap ronde (%Minimap, voir
## scenes/game/hud/Minimap.gd) plutôt que dans un label brut à gauche — déménagé ici le
## 2026-09-03 à la demande explicite de l'utilisateur (minimap en haut à droite, nom de
## carte/coordonnées juste en dessous).
func _update_minimap() -> void:
	if _player_node != null:
		_minimap.set_player_tile_position(_player_node.position.x, _player_node.position.z)
	var selected_key: String = _key_by_entity_id.get(_selected_target_id, "")
	var party_member_ids: Dictionary = GameState.party.get("members", {})
	var monster_tile_positions: Array[Vector2] = []
	var npc_tile_positions: Array[Vector2] = []
	var other_player_tile_positions: Array[Vector2] = []
	var party_member_tile_positions: Array[Vector2] = []
	var portal_tile_positions: Array[Vector2] = []
	var selected_monster_tile_pos = null
	for entry in _portals.values():
		portal_tile_positions.append(entry.position)
	for key in _entities_by_key.keys():
		if key == PLAYER_KEY:
			continue
		var node: Node3D = _entities_by_key[key]
		var tile_pos := Vector2(node.position.x, node.position.z)
		match str(node.get_meta("kind", "")):
			"monster":
				monster_tile_positions.append(tile_pos)
				if key == selected_key:
					selected_monster_tile_pos = tile_pos
			"npc":
				npc_tile_positions.append(tile_pos)
			"character":
				if party_member_ids.has(str(node.get_meta("entity_id", ""))):
					party_member_tile_positions.append(tile_pos)
				else:
					other_player_tile_positions.append(tile_pos)
	_minimap.set_known_entities(
		monster_tile_positions, npc_tile_positions,
		other_player_tile_positions, party_member_tile_positions,
		portal_tile_positions, selected_monster_tile_pos
	)


## Nom/niveau/PV/mana/XP déménagés ici depuis l'ancien %InfoLabel le 2026-09-03 (demande
## explicite d'un vrai cadre "vitaux" façon MMO plutôt qu'une ligne de texte brute, voir
## CLAUDE.md). PV/niveau lus depuis
## _entity_vitals_by_key[PLAYER_KEY] (tenu à jour en temps réel par GamePlayerStats/
## RegenTick/AttackResult/CastResult/SkillCastAnnounced/PlayerRespawned, voir
## _on_message_received) plutôt que GameState.player_stats, qui ne se rafraîchit lui qu'au
## "stats" explicite — resterait sinon figé entre deux combats. Mana/XP en revanche viennent
## de GameState (current_mana/max_mana déjà tenus à jour là pour Hotbar.gd ; xp/
## xpForCurrentLevel/xpForNextLevel du même principe, voir GameState.gd).
func _update_player_frame() -> void:
	var vitals: Dictionary = _entity_vitals_by_key.get(PLAYER_KEY, {})
	_player_frame.set_identity(
		str(GameState.player_stats.get("name", "?")), int(vitals.get("level", 1))
	)
	_player_frame.set_health(int(vitals.get("current", 0)), int(vitals.get("max", 0)))
	_player_frame.set_mana(GameState.current_mana, GameState.max_mana)
	_player_frame.set_xp(GameState.xp, GameState.xp_for_current_level, GameState.xp_for_next_level)


## Ligne de journal pour un AttackResult (attaque de base), diffusé à toute la KnownList —
## une ligne différente si nous sommes l'attaquant ou la cible, aucune si simple témoin.
## Porté de ChatOverlay._on_attack_result (client 2D) : le retour visuel (flash/nombre de
## dégâts flottant) est déjà géré ailleurs (voir le "AttackResult" du match ci-dessus), ceci
## n'ajoute que la ligne de texte, absente jusqu'ici (2026-09-03).
func _log_attack_result(payload: Dictionary) -> void:
	var my_id := str(GameState.player_stats.get("id", ""))
	var attacker_id := str(payload.get("attackerId", ""))
	var target_id := str(payload.get("targetId", ""))
	var hit := bool(payload.get("hit", false))
	var critical_suffix := " (critique !)" if payload.get("critical", false) else ""

	if attacker_id == my_id:
		var target_name := _bbcode_escape(str(payload.get("targetName", "?")))
		if not hit:
			_log("[color=%s]Vous manquez %s.[/color]" % [LOG_COLOR_DAMAGE_OUT, target_name])
			return
		_log("[color=%s]Vous infligez %s dégâts à %s%s.[/color]" % [
			LOG_COLOR_DAMAGE_OUT, str(payload.get("damage", 0)), target_name, critical_suffix,
		])
	elif target_id == my_id:
		var attacker_name := _bbcode_escape(str(payload.get("attackerName", "?")))
		if not hit:
			_log("[color=%s]%s vous manque.[/color]" % [LOG_COLOR_DAMAGE_IN, attacker_name])
			return
		_log("[color=%s]%s vous inflige %s dégâts%s.[/color]" % [
			LOG_COLOR_DAMAGE_IN, attacker_name, str(payload.get("damage", 0)), critical_suffix,
		])


## Ligne de journal pour notre propre CastResult (envoyé uniquement au lanceur) — porté de
## ChatOverlay._on_cast_result. Un sort de soin (selfHeal) est toujours appliqué au lanceur
## côté serveur, donc jamais de targetName pertinent dans ce cas.
func _log_cast_result(payload: Dictionary) -> void:
	var skill_name := _bbcode_escape(str(payload.get("skillName", "?")))
	if bool(payload.get("selfHeal", false)):
		_log("[color=%s]Vous récupérez %s PV avec %s.[/color]" % [
			LOG_COLOR_HEAL, str(payload.get("amount", 0)), skill_name,
		])
		return
	var target_name := _bbcode_escape(str(payload.get("targetName", "?")))
	if not bool(payload.get("hit", false)):
		_log("[color=%s]Vous manquez %s avec %s.[/color]" % [LOG_COLOR_DAMAGE_OUT, target_name, skill_name])
		return
	_log("[color=%s]Vous infligez %s dégâts à %s avec %s.[/color]" % [
		LOG_COLOR_DAMAGE_OUT, str(payload.get("amount", 0)), target_name, skill_name,
	])


## Ligne de journal pour le sort d'un AUTRE lanceur (SkillCastAnnounced, diffusé à toute la
## zone SAUF au lanceur qui a déjà reçu CastResult) — porté de
## ChatOverlay._on_skill_cast_announced. Ne construit une ligne que si notre personnage est
## bien la cible ; les autres témoins n'ont rien à voir apparaître ici (l'animation, elle, se
## joue pour tout le monde, voir _on_skill_cast_announced ci-dessus).
func _log_skill_cast_announced(payload: Dictionary) -> void:
	if str(payload.get("targetId", "")) != str(GameState.player_stats.get("id", "")):
		return
	var caster_name := _bbcode_escape(str(payload.get("casterName", "?")))
	var skill_name := _bbcode_escape(str(payload.get("skillName", "?")))
	if not bool(payload.get("hit", false)):
		_log("[color=%s]%s vous manque avec %s.[/color]" % [LOG_COLOR_DAMAGE_IN, caster_name, skill_name])
		return
	_log("[color=%s]%s vous inflige %s dégâts avec %s.[/color]" % [
		LOG_COLOR_DAMAGE_IN, caster_name, str(payload.get("amount", 0)), skill_name,
	])


## Un personnage meurt (GamePlayerDefeated, diffusé à toute la zone, pas d'UUID donc
## comparaison par nom) — porté de ChatOverlay._on_player_defeated. Toujours purement
## informatif pour un autre personnage ; quand characterName est le nôtre, l'appelant
## (_on_message_received) ouvre en plus %DeathPopup (voir CLAUDE.md, fenêtre de respawn
## ajoutée le 2026-09-03).
func _log_player_defeated(payload: Dictionary) -> void:
	var killer_name := _bbcode_escape(str(payload.get("killerName", "?")))
	if str(payload.get("characterName", "")) == str(GameState.player_stats.get("name", "")):
		_log("[color=%s]Vous êtes mort, tué par %s.[/color]" % [LOG_COLOR_DEFEAT, killer_name])
	else:
		_log("[color=%s]%s est mort, tué par %s.[/color]" % [
			LOG_COLOR_DEFEAT, _bbcode_escape(str(payload.get("characterName", "?"))), killer_name,
		])


func _log(text: String) -> void:
	_log_label.append_text(text + "\n")


## Dérive un facteur jour/nuit (0.0 nuit, 1.0 jour) directement de l'heure in-game plutôt
## que du seul DayPhase transmis (NIGHT/DAWN/DAY/DUSK) : donne une resynchronisation exacte
## même si le client se connecte en plein milieu d'une transition d'aube/crépuscule, sans
## dépendre d'un champ de progression que le backend ne transmet pas. Fenêtres identiques à
## GameClock côté serveur (aube 7h-8h, crépuscule 21h-22h in-game).
func _day_night_t_for_time(hour: int, minute: int) -> float:
	var minutes := hour * 60 + minute
	if minutes >= DAWN_END_MIN and minutes < DUSK_START_MIN:
		return 1.0
	if minutes >= DAWN_START_MIN and minutes < DAWN_END_MIN:
		return float(minutes - DAWN_START_MIN) / float(DAWN_END_MIN - DAWN_START_MIN)
	if minutes >= DUSK_START_MIN and minutes < DUSK_END_MIN:
		return 1.0 - float(minutes - DUSK_START_MIN) / float(DUSK_END_MIN - DUSK_START_MIN)
	return 0.0


## Applique directement (sans transition) l'ambiance correspondant à t (0.0 nuit, 1.0 jour)
## sur le WorldEnvironment/Sun/Moon/lumières de ville de la scène — utilisé aussi bien pour
## une resynchronisation immédiate (GameTimeSync) que comme callback de tween à chaque pas
## d'une transition animée (voir _animate_day_night). Ne touche pas à la position de
## Soleil/Lune : c'est _update_celestial_lights (piloté par l'horloge continue, voir
## _advance_day_night_clock) qui s'en charge indépendamment, en continu.
func _apply_day_night_preset(t: float) -> void:
	_day_night_t = t
	var env := _world_environment.environment
	env.background_color = NIGHT_BACKGROUND_COLOR.lerp(DAY_BACKGROUND_COLOR, t)
	env.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(DAY_AMBIENT_COLOR, t)
	env.ambient_light_energy = lerp(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, t)
	_sun.light_energy = lerp(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, t)
	_sun.light_color = NIGHT_SUN_COLOR.lerp(DAY_SUN_COLOR, t)
	_sun.shadow_enabled = _sun.light_energy > MIN_SHADOW_LIGHT_ENERGY
	_moon.light_energy = (1.0 - t) * MOON_MAX_ENERGY
	_moon.shadow_enabled = _moon.light_energy > MIN_SHADOW_LIGHT_ENERGY
	_update_night_lights_energy(t)


## Anime une transition Sunrise (target_t=1.0)/Sunset (target_t=0.0) depuis l'ambiance
## courante sur duration_ms (voir Sunrise.java/Sunset.java, transitionDurationMs) — annule
## toute transition encore en cours (ex. reconnexion pendant un crépuscule déjà entamé).
func _animate_day_night(target_t: float, duration_ms: int) -> void:
	if _day_night_tween != null and _day_night_tween.is_valid():
		_day_night_tween.kill()
	var duration_sec: float = max(duration_ms / 1000.0, 0.01)
	_day_night_tween = create_tween()
	_day_night_tween.tween_method(_apply_day_night_preset, _day_night_t, target_t, duration_sec)


## Avance l'horloge in-game continue simulée côté client (voir _game_minutes_of_day) et
## replace Soleil/Lune en conséquence à chaque frame — indépendant de _day_night_t/du tween
## ci-dessus (qui ne pilotent que les couleurs/énergies) : sans cette horloge, le Soleil
## resterait figé à sa dernière orientation entre deux GameTimeSync/Sunrise/Sunset, ce que le
## serveur ne pousse que ponctuellement (voir en-tête du fichier).
func _advance_day_night_clock(delta: float) -> void:
	_game_minutes_of_day = fposmod(_game_minutes_of_day + delta * IN_GAME_MINUTES_PER_REAL_SECOND, 1440.0)
	_update_celestial_lights()


## Progression (0.0-1.0) du Soleil le long de son arc, de l'aube (DAWN_START_MIN, à l'horizon
## est) au crépuscule (DUSK_END_MIN, à l'horizon ouest) — voir _celestial_direction.
func _sun_arc_fraction(minutes: float) -> float:
	return clampf(float(minutes - DAWN_START_MIN) / float(DUSK_END_MIN - DAWN_START_MIN), 0.0, 1.0)


## Équivalent nocturne de _sun_arc_fraction : progression de la Lune du crépuscule
## (DUSK_END_MIN) à l'aube suivante (DAWN_START_MIN), en traversant minuit.
func _moon_arc_fraction(minutes: float) -> float:
	var night_span := 1440.0 - float(DUSK_END_MIN - DAWN_START_MIN)
	var since_dusk := fposmod(minutes - DUSK_END_MIN, 1440.0)
	return clampf(since_dusk / night_span, 0.0, 1.0)


## Direction de propagation (normalisée, de l'astre vers le sol) d'un astre à la progression
## d'arc frac (0.0 = levant à l'horizon est, 0.5 = zénith, 1.0 = couchant à l'horizon ouest) —
## azimut est-ouest linéaire (est = +X, ouest = -X, aucune composante nord-sud), élévation en
## cloche (sin) plafonnée à CELESTIAL_MAX_ELEVATION_DEG. Partagée par Soleil et Lune : seul
## frac (voir _sun_arc_fraction/_moon_arc_fraction) diffère entre les deux.
func _celestial_direction(frac: float) -> Vector3:
	var azimuth := deg_to_rad(lerpf(90.0, -90.0, frac))
	var elevation := deg_to_rad(sin(frac * PI) * CELESTIAL_MAX_ELEVATION_DEG)
	var sky_position := Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
	return -sky_position


## Repositionne Soleil et Lune sur leur trajectoire est-ouest respective d'après l'horloge
## continue _game_minutes_of_day — un DirectionalLight3D éclaire selon son axe -Z local, donc
## orienter la lumière revient à orienter cet axe vers _celestial_direction (Basis.looking_at,
## le vecteur "up" n'a ici aucune importance visuelle : une lumière directionnelle n'a pas de
## notion de haut/bas propre, seule sa direction compte). Les ombres suivent automatiquement,
## Godot les recalculant à partir de cette même transformation à chaque frame.
func _update_celestial_lights() -> void:
	_sun.transform.basis = Basis.looking_at(_celestial_direction(_sun_arc_fraction(_game_minutes_of_day)), Vector3.FORWARD)
	_moon.transform.basis = Basis.looking_at(_celestial_direction(_moon_arc_fraction(_game_minutes_of_day)), Vector3.FORWARD)


func _bbcode_escape(text: String) -> String:
	return text.replace("[", "[lb]")
