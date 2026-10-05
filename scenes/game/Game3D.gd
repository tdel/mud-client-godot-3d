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
## Les personnages (joueur + autres joueurs, kind="character") utilisent le mannequin low-poly
## homme/femme (scenes/game/entities/Character.gd, voir _make_entity_node/CHARACTER_SCENE) :
## animations idle/course/attaque 1 ou 2 mains/incantation/lancer/mort, équipement porté
## visible (voir _apply_player_equipment). Les monstres qui ont un modèle (MonsterCatalog)
## sont animés par scenes/game/entities/Monster.gd (idle/course/attaque/mort) ; PNJ et autres
## monstres restent de simples capsules colorées, faute de modèle dédié.

const WORLD_UP := Vector3.UP
const DEFAULT_SPEED_TILES_PER_SEC := 2.4
## Recul de la caméra orthographique (sans effet sur la taille apparente, fixée par `size`) :
## à 20 u, au dézoom maximal (size 30, demi-hauteur 15) le bas du cadre partait sous le sol —
## le plan near coupait les blocs du premier plan et laissait voir le fond bleu de
## l'Environment en bas de l'écran. À 60 u, même au dézoom maximal, l'origine des rayons du bas
## du cadre reste ~22 u au-dessus du sol.
const CAMERA_DISTANCE := 60.0
## Plan near repoussé d'autant : le plus proche élément visible (sommet d'un bloc en bas du
## cadre au dézoom maximal) reste à ~30 u de la caméra ; ne pas démarrer à 0.1 garde la
## précision de profondeur et les cascades d'ombre du soleil sur la partie utile.
const CAMERA_NEAR := 20.0
## L'écouteur audio reste à l'ancienne distance du pivot (voir Sfx.UNIT_SIZE, calé dessus) :
## reculer la caméra ne change pas le volume des sons spatialisés.
const AUDIO_LISTENER_DISTANCE := 20.0
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
## Écart (cases) sous lequel une PositionUpdated est ignorée : bruit de latence, pas une dérive.
## Le chemin étant désormais le même que celui du serveur, l'écart attendu est quasi nul.
const POSITION_CORRECTION_DEADZONE := 0.12
## Au-delà de cet écart (cases), une correction serveur téléporte au lieu de lisser : vraie
## désynchronisation (entité réapparue loin, respawn...), un glissement serait pire.
const POSITION_SNAP_DISTANCE := 3.0
## Vitesse (1/s) de résorption de l'écart visuel laissé par une correction serveur (voir
## _correct_position/_step_movement) : la position logique saute, l'affichage la rattrape en
## lissage exponentiel (~200 ms) au lieu de sauter avec elle — plus de saccade, caméra comprise.
const POSITION_SMOOTHING_RATE := 5.0
const POSITION_SMOOTHING_EPSILON := 0.003
## MovementFinished alors que l'affichage n'a pas fini son chemin : sous cette longueur
## restante (cases), le personnage finit de courir jusqu'au point final au lieu d'y glisser.
const ARRIVAL_WALK_MAX_DISTANCE := 1.5
## Vitesse (1/s) de rotation vers le cap visé (voir _face_direction/_update_facing) : les
## changements de direction tournent en ~60 ms au lieu de claquer instantanément.
const FACING_SMOOTHING := 18.0

const PLAYER_COLOR := Color(0.35, 0.65, 0.95)
const OTHER_PLAYER_COLOR := Color(0.30, 0.80, 0.55)
const MONSTER_COLOR := Color(0.85, 0.30, 0.28)
const NPC_COLOR := Color(0.85, 0.75, 0.30)
## Mannequin partagé par tous les personnages (voir _make_entity_node, modèles générés par
## tools/character_gen/build_characters.py), donc PLAYER_COLOR/OTHER_PLAYER_COLOR ne teintent
## ces entités qu'en mode "craie" (animations et skins désactivés dans le menu système, voir
## ChalkBody — monstres animés compris, en MONSTER_COLOR) ; les monstres/PNJ sans modèle
## (capsules) restent colorés.
const CHARACTER_SCENE := preload("res://scenes/game/entities/Character.tscn")
## Périmètre runique du cercle de portée des skills (voir show_skill_range).
const RANGE_RING_SHADER := preload("res://scenes/game/vfx/range_ring.gdshader")
## Plaques de nom flottantes façon Lineage 2 : nom des joueurs en blanc, des PNJ en bleu
## clair, des monstres en blanc rosé ; titre (EntityView.title / GamePlayerStats.Payload.title,
## ex. fonction d'un PNJ comme "Blacksmith") en jaune pâle au-dessus du nom.
const TITLE_LABEL_COLOR := Color(1.0, 1.0, 0.47)
const PLAYER_NAME_COLOR := Color(1.0, 1.0, 1.0)
const NPC_NAME_COLOR := Color(0.62, 0.82, 1.0)
const MONSTER_NAME_COLOR := Color(1.0, 0.80, 0.76)
const SELECTION_COLOR := Color(0.95, 0.22, 0.18)
const SELECTION_SELF_COLOR := Color(0.96, 0.96, 0.92)
const SELECTION_PARTY_COLOR := Color(0.36, 0.92, 0.36)
const SELECTION_NPC_COLOR := Color(0.55, 0.78, 1.0)

## Lueur d'arme sur la consommation d'un soulshot/spiritshot (voir _flash_entity, réutilisé
## avec une durée plus longue que le flash de dégâts pour rester bien visible) — orange pour
## le soulshot (physique), cyan pour le spiritshot (magique, cohérent avec la barre
## d'incantation déjà bleue). Déclenché par ShotUsed (nous-même) et SoulshotUsed/SpiritshotUsed (les autres,
## diffusés à toute la zone sauf à l'auteur — voir commit backend "Ajoute le système
## soulshot/spiritshot" du 2026-09-04).
const SOULSHOT_GLOW_COLOR := Color(1.0, 0.55, 0.15)
const SPIRITSHOT_GLOW_COLOR := Color(0.3, 0.85, 1.0)
const SHOT_GLOW_UP_DURATION := 0.1
const SHOT_GLOW_DOWN_DURATION := 0.35
## Le serveur consomme le spiritshot au début du cast et envoie ShotUsed/SpiritshotUsed juste
## avant SkillCastStarted (voir SkillCastEngine.beginCast) : un SkillCastStarted reçu dans ce
## délai après la consommation est un cast chargé (couronnes flottantes, voir CastCircle).
const SPIRITSHOT_CAST_WINDOW_MS := 1000

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

## Couleur des gains (or/XP/loot) dans la fenêtre de journal système (voir _log/_log_chat et
## la fenêtre %SystemLogPanel de Game.tscn, qui sépare désormais ces messages système du chat
## entre joueurs affiché dans %ChatLogPanel) — tout le reste du journal système reste dans la
## couleur par défaut (blanc/ivoire, voir UITheme.TEXT_IVORY), demande explicite du
## 2026-09-06 pour ne garder qu'une seule couleur d'accent plutôt que la palette par catégorie
## (dégâts/soin/mort/zone paisible) utilisée jusqu'ici.
const LOG_COLOR_GAIN := "#f2e35a"

## Couleurs du chat entre joueurs (%ChatLogLabel/%ChatPartyLogLabel) — demande explicite du
## 2026-09-06 ("système d'onglet... all, tous les messages en blanc + party en vert + whisper
## en violet") : un "say" normal (Chat/YouSaid) reste en blanc pur plutôt que l'ivoire par
## défaut du thème (UITheme.TEXT_IVORY, trop proche du gris pour bien se distinguer des deux
## autres canaux), un message de groupe (PartyChat) en vert, un chuchotement (Whisper) en
## violet — ces deux derniers apparaissent aussi bien dans l'onglet "Tous" que dans l'onglet
## "#Groupe" (voir _log_chat/_on_chat_tab_changed), contrairement au "say" qui ne va que dans
## "Tous".
const LOG_COLOR_SAY := "#ffffff"
const LOG_COLOR_PARTY := "#5ce65c"
const LOG_COLOR_WHISPER := "#ff77ff"

## Party.MAX_SIZE côté backend (nous compris).
const PARTY_MAX_SIZE := 8

## Transparence des fenêtres de discussion (%ChatLogPanel/%SystemLogPanel) — demande explicite
## du 2026-09-06 : quasi invisibles tant que %ChatInput n'a pas le focus (pour ne pas gêner la
## vue 3D et laisser le clic passer à travers, voir _set_chat_windows_interactive), légèrement
## opaques quelques secondes à chaque nouveau message (_flash_chat_window), pleinement opaques
## dès que l'on tape (focus gagné).
const CHAT_WINDOW_IDLE_ALPHA := 0.0
const CHAT_WINDOW_MESSAGE_ALPHA := 0.85
const CHAT_WINDOW_FOCUSED_ALPHA := 1.0
## Durée pendant laquelle la fenêtre de chat reste opaque après un nouveau message avant de
## commencer son fondu — portée de 4 s à 10 s (demande explicite du 2026-09-27 : trop rapide).
const CHAT_WINDOW_MESSAGE_HOLD_SEC := 10.0
## Fenêtre de statut (%SystemLogPanel) : maintenue visible 10 s à chaque nouveau message, pour
## laisser le temps de lire — demande explicite du 2026-09-26.
const SYSTEM_WINDOW_MESSAGE_HOLD_SEC := 10.0
## Perte du focus de %ChatInput : les fenêtres (et %ChatInput) restent opaques ce délai avant
## leur fondu, au lieu de disparaître d'un coup — demande explicite du 2026-09-27.
const CHAT_WINDOW_UNFOCUS_HOLD_SEC := 10.0
const CHAT_WINDOW_FADE_SEC := 1.5

const PLAYER_KEY := "player"

## Nom/titre par défaut si le serveur ne les transmet pas encore (PortalView.name/title, voir
## _apply_appeared_portal) — même dégradation gracieuse que targetMapName ci-dessous.
const PORTAL_NAME_DEFAULT := "Clairière"
const PORTAL_TITLE_DEFAULT := "Téléporteur"
## Portée de téléportation si le serveur ne transmet pas triggerRadius (ancienne zone
## d'activation). La sélection au clic passe par un vrai rayon physique 3D sur tout l'objet
## (voir PORTAL_PICK_COLLISION_LAYER/_pick_portal_id_at_mouse), comme pour les entités.
const PORTAL_RANGE_DEFAULT := 0.7

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

## Barre de vie flottante (voir _make_gauge_bar) : même rendu que la jauge HP du cadre
## joueur (UITheme.BAR_COLORS["hp"], dégradé "tube" + liseré), demandé le 2026-09-26.
## Celle de la cible sélectionnée est "en gras" (2026-09-26, on la voyait mal sur un sol
## clair) : plus grande (TARGET_BAR_*), opaque et entourée d'un contour noir extérieur en plus
## du liseré (voir GAUGE_BAR_SHADER_CODE/_layout_overhead).
const BAR_WIDTH := 1.15
const BAR_HEIGHT := 0.22
const TARGET_BAR_WIDTH := 1.25
const TARGET_BAR_HEIGHT := 0.3
const TARGET_BAR_OUTLINE_PX := 2.0
## La barre d'incantation (2026-09-26 : l'ancienne pilule bleue détonnait à côté des jauges)
## reprend exactement ce rendu et ce gabarit, aux couleurs UITheme.BAR_COLORS["cast"] (celles
## de la jauge d'incantation du HUD), et se range avec la barre de vie sous le nom.

## Empilement au-dessus de la tête (recalculé chaque frame dans _layout_overhead, 2026-09-26 :
## le nom flottait bien trop haut) : sommet de la silhouette (mannequin, capsule 1.6),
## puis un petit espace, la barre de vie si elle est affichée, le nom, le titre, et enfin la
## barre d'incantation pendant un sort. Les Label3D sont alignés par le bas, leur hauteur
## vient de la police elle-même (voir _world_label_height).
const HEAD_HEIGHT_HUMANOID := 1.72
const HEAD_HEIGHT_CAPSULE := 1.6
const OVERHEAD_GAP := 0.2
const OVERHEAD_SPACING := 0.05
## Noms/titres flottants : police de l'UI (UITheme.font_world, graisse normale) rendue à une
## taille de police plus grande que sa taille à l'écran puis réduite via `pixel_size` — le
## suréchantillonnage + mipmaps (voir _style_world_label) lisse nettement les contours.
const NAME_FONT_SIZE := 64
const NAME_PIXEL_SIZE := 0.0062
const NAME_OUTLINE_SIZE := 9
const NAME_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.85)
## Nom de la cible sélectionnée (2026-09-26 : illisible sur un sol clair) : en gras
## (UITheme.font_world_bold) avec un contour noir opaque deux fois plus épais.
const TARGET_NAME_OUTLINE_SIZE := 18
const TARGET_NAME_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const TITLE_FONT_SIZE := 52
const TITLE_OUTLINE_SIZE := 8

const DAMAGE_NUMBER_RISE := 0.8
const DAMAGE_NUMBER_DURATION := 0.9
const DAMAGE_NUMBER_FADE_START := 0.45
const DAMAGE_NUMBER_COLOR_NORMAL := Color(1.0, 1.0, 1.0)
const DAMAGE_NUMBER_COLOR_CRITICAL := Color(1.0, 0.88, 0.15)

const MONSTER_DEATH_GREY_DELAY := 0.5
const MONSTER_DEATH_FADE_DURATION := 0.6
const MONSTER_DEATH_GREY_COLOR := Color(0.42, 0.42, 0.42)
## Monstre animé (voir Monster.gd) : temps passé au sol une fois le clip de mort fini, avant le
## fondu.
const MONSTER_CORPSE_LINGER := 0.8

## Sorts à dégâts sans projectile (portée "toucher" côté backend) : impact direct de leur
## élément sur la cible plutôt qu'un projectile lancé, voir _play_skill_animation. L'élément
## (et donc la couleur/forme des effets) de chaque sort est défini dans SpellVfx.
const NON_PROJECTILE_DAMAGE_SKILLS := ["Twister", "Prominence", "Vampiric Touch"]
## EntityView.npcType du maître des compétences (backend NpcType.SKILL_LEARNER).
const SKILL_LEARNER_NPC_TYPE := "SKILL_LEARNER"

## Son de cible abattue (voir _play_kill_sound) : léger retard pour qu'il se détache du son
## d'impact du coup fatal plutôt que de s'y fondre ; une même cible ne le rejoue pas dans
## KILL_SOUND_MEMO_MSEC (sa mort est annoncée par plusieurs messages).
const KILL_SOUND_DELAY := 0.15
const KILL_SOUND_MEMO_MSEC := 3000

@onready var _world: Node3D = $World
@onready var _map_scene_root: Node3D = $World/MapScene
@onready var _obstacles: MultiMeshInstance3D = $World/Obstacles
@onready var _entities_root: Node3D = $World/Entities
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _minimap: Control = %Minimap
## Carte entière de la zone (touche M), voir WorldMapWindow.gd.
@onready var _world_map: Control = %WorldMapWindow
@onready var _player_frame: Control = %PlayerFrame
## Fenêtre de groupe sous %PlayerFrame (voir PartyWindow.gd) et invitation reçue (voir
## PartyInviteDialog.gd, pilotée par _on_party_message).
@onready var _party_window: Control = %PartyWindow
@onready var _party_invite_dialog: Control = %PartyInviteDialog
## Journal système (arrivée/départ de carte, dégâts, XP, loot, incantations, erreurs...) —
## voir _log — distinct du chat entre joueurs (_chat_log_label/_log_chat), demande explicite
## du 2026-09-06 pour ne plus mélanger les deux dans une seule fenêtre.
@onready var _system_log_label: RichTextLabel = %SystemLogLabel
@onready var _system_log_background: PanelContainer = %SystemLogBackground
@onready var _system_log_resize_handle: Control = %SystemLogResizeHandle
@onready var _chat_log_label: RichTextLabel = %ChatLogLabel
@onready var _chat_log_background: PanelContainer = %ChatLogBackground
@onready var _chat_log_resize_handle: Control = %ChatLogResizeHandle
## Onglets "Tous"/"#Groupe" du chat entre joueurs (voir Game.tscn/%ChatLogContent) — %ChatLogLabel
## (onglet "Tous") reçoit tout le chat, %ChatPartyLogLabel (onglet "#Groupe") seulement le
## groupe/chuchotement (voir _log_chat) ; %ChatScrollBar/%ChatPartyScrollBar sont des
## VScrollBar posées à GAUCHE de chaque RichTextLabel (demande explicite du 2026-09-06) qui
## pilotent la scrollbar interne du RichTextLabel (masquée, voir _wire_left_scrollbar) plutôt
## que d'en réafficher une deuxième à droite.
@onready var _chat_tab_bar: TabBar = %ChatTabBar
@onready var _chat_all_row: Control = %AllRow
@onready var _chat_party_row: Control = %PartyRow
@onready var _chat_scroll_bar: VScrollBar = %ChatScrollBar
@onready var _chat_party_log_label: RichTextLabel = %ChatPartyLogLabel
@onready var _chat_party_scroll_bar: VScrollBar = %ChatPartyScrollBar
@onready var _chat_input: LineEdit = %ChatInput
@onready var _chat_bar: Control = %ChatBar
@onready var _target_status_bar: Control = %TargetStatusBar
@onready var _npc_menu: PopupMenu = %NpcMenu
@onready var _death_popup: Control = %DeathPopup
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _moon: DirectionalLight3D = $Moon
@onready var _night_lights: Node3D = $World/NightLights

## Tween de fondu en cours par fenêtre de discussion (PanelContainer, ou %ChatInput -> Tween),
## voir _fade_chat_window_later — permet d'annuler un fondu déjà lancé quand un nouvel évènement
## (message ou focus) en redemande un autre avant la fin du précédent.
var _chat_window_fade_tweens: Dictionary = {}

## Poignée de redimensionnement associée à chaque fond de fenêtre de discussion
## (PanelContainer -> Control), peuplé dans _ready — la poignée n'est pas un enfant du fond
## (voir Game.tscn) donc son alpha ne suit pas automatiquement celui du fond via `modulate`
## et doit être piloté explicitement à côté (_flash_chat_window/_set_chat_windows_interactive),
## demande explicite du 2026-09-06 pour qu'elle se fonde comme le reste de la fenêtre.
var _chat_window_handles: Dictionary = {}

var _player_node: Node3D
var _current_map_name := ""
var _map_width := 0
var _map_height := 0
var _walkable_rows: Array = []
## false pour une carte décorée (MapData.render_obstacle_blocks) : ses obstacles (arbres,
## props) sont déjà dessinés, pas de bloc gris par case non praticable.
var _render_obstacle_blocks := true
## Nom de terrain par case de la carte courante (Array[Array[String]]), lu sur le GridMap
## "Terrain" de la scène instanciée dans _map_scene_root — voir _read_terrain_grid.
## Alimente le rendu de la minimap et le choix de hauteur des obstacles/lumières de nuit ;
## la marchabilité réelle reste dans _walkable_rows (source de vérité : le serveur).
var _terrain_grid: Array = []
## Voile gris sur le décor hors de la grille, enfant de la caméra (voir MapBoundsVeil).
var _map_bounds_veil: MapBoundsVeil
## Chargement de la scène de carte en cours, derrière LoadingScreen (voir _rebuild_map, qui
## le lance, et _advance_map_load, qui le fait avancer d'une étape par image depuis
## _process pour que la barre de progression reste animée).
enum MapLoadStep { NONE, LOADING, INSTANTIATE, BUILD, WARMUP }
## Images rendues avec la nouvelle carte (toujours masquée) avant d'atteindre 100 % :
## compilation des shaders/pipelines de ses matériaux hors de la vue du joueur.
const MAP_LOAD_WARMUP_FRAMES := 4
var _map_load_step := MapLoadStep.NONE
var _map_load_payload: Dictionary = {}
var _map_load_scene_path := ""
var _map_load_packed: PackedScene
var _map_load_instance: Node3D
## Progression déjà acquise quand le chargement de carte a démarré (chargement de Game.tscn
## lui-même à l'entrée en jeu, voir LoadingScreen.change_scene_to_file).
var _map_load_base := 0.0
var _map_load_frames := 0

## Toutes les entités (joueur compris, sous la clé PLAYER_KEY) sont traitées de façon
## générique par _step_movement : key -> Node3D / vitesse (tuiles/s) /
## {"path": Array[Vector3] (waypoints serveur restants, voir MotionPath),
##  "idle_on_arrival": bool (repasse en idle au bout du chemin sans attendre le serveur)}.
var _entities_by_key: Dictionary = {}
var _key_by_entity_id: Dictionary = {}
var _entity_speed_by_key: Dictionary = {}
var _moving: Dictionary = {}
## Écart visuel restant (Vector3) par entité après une correction serveur : node.position =
## position logique + cet écart, qui décroît vers zéro (voir _correct_position/_step_movement).
## Compensation de latence : le client démarre chaque déplacement à la réception de l'ordre,
## une demi-latence après le serveur, et toute position serveur reçue date elle aussi d'une
## demi-latence — les deux retards se compensent, donc une position serveur se compare
## directement à la position logique actuelle, sans extrapolation ni mesure du ping.
var _smooth_offset_by_key: Dictionary = {}
## Vie/niveau courants de chaque entité connue, indexés par la même clé que
## _entities_by_key : {current, max, level}. Alimenté par EntityAppeared (voir
## _apply_appeared_entity) quand ces champs sont présents, et par
## AttackResult/CastResult/SkillCastAnnounced ensuite.
var _entity_vitals_by_key: Dictionary = {}
## Barres flottantes (vie + incantation) par entité, voir _ensure_bars/_make_gauge_bar.
var _entity_bars_by_key: Dictionary = {}
## Incantations en cours, indexées par la même clé que _entities_by_key :
## {elapsed_ms, total_ms}. Alimenté par SkillCastStarted, vidé par SkillCastCancelled/
## SkillFizzled ou par expiration locale du délai (voir _process).
var _casting_by_key: Dictionary = {}
## Clé d'entité -> Time.get_ticks_msec() du dernier spiritshot consommé, en attente du
## SkillCastStarted qui suit (voir SPIRITSHOT_CAST_WINDOW_MS).
var _spiritshot_at_by_key: Dictionary = {}
## Fin d'un Scroll of Escape (CharacterTeleporting nous concernant) : jusqu'à ce
## Time.get_ticks_msec(), aucune action (voir is_player_casting) — le serveur refuse tout
## (TeleportInProgress) jusqu'au MapView de la ville, qui lève ce verrou.
var _teleport_lock_until_msec := 0
## Effets visuels des sorts (cercles d'incantation, projectiles, soins...), voir SpellVfx.
var _spell_vfx: SpellVfx

## UUID de l'entité actuellement sélectionnée ("" si aucune) — seule source de vérité pour
## F1-F12 (Hotbar.gd envoie attack/cast sans UUID de cible, résolus côté serveur sur la
## cible de combat courante).
var _selected_target_id := ""
var _selection_ring: MeshInstance3D
## Dernière cible dont la mort a été sonnée (voir _play_kill_sound).
var _kill_sound_target_id := ""
var _kill_sound_msec := 0

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
var _move_marker_tween: Tween
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
	# Entrée dans le monde : la musique des menus s'éteint doucement (celle de la carte
	# prend le relais au premier MapView, voir _rebuild_map).
	MenuMusic.stop()
	_spell_vfx = SpellVfx.new()
	_spell_vfx.name = "SpellVfx"
	_world.add_child(_spell_vfx)
	Net.message_received.connect(_on_message_received)
	Net.disconnected.connect(_on_net_disconnected)
	Settings.graphics_changed.connect(_on_graphics_changed)
	_apply_environment_settings()
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.focus_entered.connect(_on_chat_input_focus_entered)
	_chat_input.focus_exited.connect(_on_chat_input_focus_exited)
	_chat_window_handles[_chat_log_background] = _chat_log_resize_handle
	_chat_window_handles[_system_log_background] = _system_log_resize_handle
	_chat_log_resize_handle.panel_resized.connect(_on_chat_log_panel_resized)
	_on_chat_log_panel_resized()
	_set_chat_windows_interactive(false)
	# Messages système en gris-bleu clair, distincts du chat entre joueurs (comme dans L2).
	_system_log_label.add_theme_color_override("default_color", UITheme.TEXT_SYSTEM)

	_chat_tab_bar.add_tab("Tous")
	_chat_tab_bar.add_tab("#Groupe")
	_chat_tab_bar.tab_changed.connect(_on_chat_tab_changed)
	_wire_left_scrollbar(_chat_scroll_bar, _chat_log_label)
	_wire_left_scrollbar(_chat_party_scroll_bar, _chat_party_log_label)

	_npc_menu.add_item("Parler", 0)
	_npc_menu.add_item("Boutique", 1)
	_npc_menu.add_item("Apprendre des compétences", 2)
	_npc_menu.id_pressed.connect(_on_npc_menu_id_pressed)
	_player_frame.self_clicked.connect(_on_player_frame_self_clicked)
	_target_status_bar.teleport_requested.connect(_on_teleport_button_pressed)
	_target_status_bar.close_requested.connect(_deselect_all)
	_target_status_bar.invite_requested.connect(func(): Net.send_command("party-invite"))
	_party_window.member_selected.connect(_on_party_member_selected)

	_camera.size = _camera_size
	_camera.near = CAMERA_NEAR
	_minimap.set_camera_zoom(_camera_size)
	_apply_camera_orbit()
	var listener := AudioListener3D.new()
	# La caméra regarde vers -Z local : l'écouteur avance vers le pivot.
	listener.position = Vector3(0.0, 0.0, -(CAMERA_DISTANCE - AUDIO_LISTENER_DISTANCE))
	_camera.add_child(listener)
	listener.make_current()

	_make_move_marker()
	_make_selection_ring()
	_map_bounds_veil = MapBoundsVeil.new()
	_camera.add_child(_map_bounds_veil)
	_update_celestial_lights()
	_log("Prototype 3D isométrique — connecté.")

	Net.send_command("stats")
	Net.send_command("skills")
	# Équipement porté, pour l'habiller dès l'arrivée (voir _apply_player_equipment) — sinon
	# il ne serait demandé qu'à l'ouverture de l'inventaire/de la fenêtre d'équipement.
	Net.send_command("inventory")
	# MapView/MapEnter/EntityAppeared sont poussés automatiquement par le serveur au spawn
	# (character-select/create), mais peuvent être arrivés avant que cette scène n'existe
	# (GameState les met en cache dès l'autoload) : on les rejoue ici si besoin. EntityAppeared
	# (KnownList.populate() côté backend, appelé par MapInstance.join() avant l'envoi de
	# MapEnter — voir CLAUDE.md, commit acfb970) est ce qui peuple désormais les entités à
	# portée au chargement de carte : sans ce rejeu, un joueur/monstre/PNJ déjà présent au
	# moment du spawn n'apparaîtrait qu'à son prochain déplacement (refresh() suivant).
	# L'écran de chargement (déjà affiché par LoadingScreen.change_scene_to_file depuis
	# CharSelect/CharacterCreate) reste en place jusqu'à la fin du chargement de la première
	# carte (voir _advance_map_load), même si son MapView n'est pas encore arrivé.
	LoadingScreen.begin()
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
		_ensure_player_node()
		_play_body_death(_player_node)


func _exit_tree() -> void:
	# Retour à l'écran de connexion (déconnexion, Menu système) : la musique de zone
	# s'efface pendant que MenuMusic repart.
	ZoneMusic.stop()
	LoadingScreen.cancel()


func _process(delta: float) -> void:
	_advance_map_load()
	_advance_day_night_clock(delta)
	_step_movement(delta)
	_update_facing(delta)
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
	_update_occlusion_globals()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not _chat_input.has_focus():
			_chat_input.grab_focus()
			get_viewport().set_input_as_handled()
			return
		if _chat_input.has_focus():
			return
		if event.keycode == KEY_ESCAPE:
			# Une incantation en cours passe avant tout : Échap l'abandonne via la commande
			# "stop" (SkillCastEngine.cancelCast côté serveur), le SkillCastCancelled renvoyé
			# brise le cercle et remet le personnage au repos (_clear_casting). La cible reste
			# sélectionnée ; un second Échap la désélectionne. Pas pendant l'ascension d'un
			# Scroll of Escape (_teleport_lock_until_msec) : le cast y est déjà résolu.
			if _casting_by_key.has(PLAYER_KEY):
				Net.send_command("stop")
				get_viewport().set_input_as_handled()
				return
			# Ferme ensuite la fenêtre HUD qui a le focus (inventaire/équipement/fiche de
			# personnage/sorts/options, voir WindowFrame._focused) — "Échap ferme la fenêtre la
			# plus proche de nous", CLAUDE.md, session du 2026-09-03. Des fenêtres restées
			# ouvertes mais qui ont perdu le focus (clic dans le monde, sur la hotbar…) ne
			# bloquent pas la désélection de la cible ; elles ne se ferment à Échap qu'une fois
			# plus rien de sélectionné.
			if WindowFrame.close_focused():
				get_viewport().set_input_as_handled()
				return
			if not _selected_target_id.is_empty() or not _selected_portal_id.is_empty():
				_deselect_all()
				get_viewport().set_input_as_handled()
				return
			if WindowFrame.close_topmost():
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
			_teleport_lock_until_msec = 0
			_rebuild_map(payload)
		"MapEnter":
			_refresh_entities(payload)
		"GamePlayerStats":
			_ensure_player_node()
			_set_body_gender(_player_node, str(payload.get("gender", "")))
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
				_place_entity(key, Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0)))
				_register_entity_id(key, str(payload.get("characterId", "")))
				# Retour d'un joueur mort (respawn = nouvelle entrée sur une carte) : on le relève.
				_play_body_revive(node)
				_log("%s rejoint la carte." % _bbcode_escape(joined_name))
		"GamePlayerLeftMap", "GamePlayerDisconnected":
			var left_name := str(payload.get("characterName", ""))
			if not left_name.is_empty():
				_remove_entity("character:%s" % left_name)
				_log("%s quitte la carte." % _bbcode_escape(left_name))
		"MovementStarted":
			_ensure_player_node()
			var target := Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
			# Position serveur au départ (rattrapée à l'instant du clic côté serveur) : recalage
			# doux avant de suivre le même chemin que lui, virages compris.
			if payload.has("startX"):
				_correct_position(PLAYER_KEY, Vector3(payload.get("startX", 0.0), 0.0, payload.get("startY", 0.0)))
			_start_path(PLAYER_KEY, _payload_path(payload, target), true)
			_entity_speed_by_key[PLAYER_KEY] = _player_speed()
			_play_body_state(_player_node, Character.RUN_ANIM)
			_show_move_marker(Vector2(target.x, target.z))
		"MovementFinished":
			_ensure_player_node()
			_finish_path(PLAYER_KEY, Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0)))
			_hide_move_marker()
		"MovementStopped", "MovementBlockedByBounds":
			_ensure_player_node()
			_stop_at(PLAYER_KEY, Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0)))
			_hide_move_marker()
		"NoPathToDestination":
			_hide_move_marker()
		"PositionUpdated":
			_ensure_player_node()
			var server_pos := Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
			if _logical_position(PLAYER_KEY).distance_to(server_pos) > POSITION_CORRECTION_DEADZONE:
				_correct_position(PLAYER_KEY, server_pos)
			# En course, le cap suit le chemin (voir _step_movement).
			if not _moving.has(PLAYER_KEY):
				_face_heading(_player_node, float(payload.get("heading", 0.0)))
		"CharacterMovementStarted":
			var entity_name := str(payload.get("characterName", ""))
			var character_id := str(payload.get("characterId", ""))
			if not entity_name.is_empty():
				var key := _resolve_movement_key(character_id, entity_name)
				var color := MONSTER_COLOR if key.begins_with("monster:") else OTHER_PLAYER_COLOR
				var node := _ensure_entity_node(key, entity_name, color)
				_register_entity_id(key, character_id)
				if payload.has("x"):
					_correct_position(key, Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0)))
				var target2 := Vector3(payload.get("targetX", 0.0), 0.0, payload.get("targetY", 0.0))
				# Un monstre en poursuite reçoit une cible fraîche à chaque pas serveur : il
				# continue de courir en attendant la suivante plutôt que de repasser en idle.
				_start_path(key, _payload_path(payload, target2), not key.begins_with("monster:"))
				if not payload.has("waypoints"):
					_face_heading(node, float(payload.get("heading", 0.0)))
				_play_body_state(node, Character.RUN_ANIM)
				if not _entity_speed_by_key.has(key):
					_entity_speed_by_key[key] = DEFAULT_SPEED_TILES_PER_SEC
		"CharacterMovementFinished", "CharacterMovementStopped", "CharacterMovementBlocked":
			var entity_name2 := str(payload.get("characterName", ""))
			var character_id2 := str(payload.get("characterId", ""))
			if not entity_name2.is_empty():
				var key2 := _resolve_movement_key(character_id2, entity_name2)
				_ensure_entity_node(key2, entity_name2, OTHER_PLAYER_COLOR)
				var end_pos := Vector3(payload.get("x", 0.0), 0.0, payload.get("y", 0.0))
				if type == "CharacterMovementFinished":
					_finish_path(key2, end_pos)
				else:
					_stop_at(key2, end_pos)
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
			_despawn_monster(str(payload.get("monsterId", "")), defeated_name)
			_log("%s est vaincu." % _bbcode_escape(defeated_name))
		"TargetSelected":
			_apply_selection(str(payload.get("targetId", "")), str(payload.get("targetName", "")))
		"TargetDeselected":
			_clear_selection()
		"NoTargetSelected":
			_clear_selection()
			_log("[i]Aucune cible sélectionnée.[/i]")
		"TargetNotFound":
			if str(payload.get("targetId", "")) == _selected_target_id:
				_clear_selection()
			_log("[i]Cible introuvable.[/i]")
		"AttackResult":
			var attacker_node := _entity_node_by_id(str(payload.get("attackerId", "")))
			# L'attaquant fait face à sa cible : heading calculé par le serveur (source de vérité,
			# même valeur qu'EntityView pour les nouveaux arrivants).
			if attacker_node != null and payload.has("attackerHeading"):
				_face_heading(attacker_node, float(payload.get("attackerHeading", 0.0)))
			_play_body_attack(attacker_node)
			var attack_target_id := str(payload.get("targetId", ""))
			_flash_entity_by_id(attack_target_id)
			if bool(payload.get("hit", false)):
				var attack_damage := int(payload.get("damage", 0))
				if attack_damage > 0:
					_show_damage_number(
						_entity_node_by_id(attack_target_id), attack_damage, bool(payload.get("critical", false))
					)
			_apply_target_current_health(attack_target_id, int(payload.get("targetCurrentHealth", 0)))
			if bool(payload.get("hit", false)) and int(payload.get("targetCurrentHealth", 0)) <= 0 \
					and str(payload.get("attackerId", "")) == str(GameState.player_stats.get("id", "")):
				_play_kill_sound(attack_target_id)
			_log_attack_result(payload)
		"AttackOutOfRange":
			_log("[i]%s est hors de portée.[/i]" % _bbcode_escape(
				str(payload.get("targetName", "?"))
			))
		"SkillOutOfRange":
			_log("[i]%s est hors de portée pour %s.[/i]" % [
				_bbcode_escape(str(payload.get("targetName", "?"))),
				_bbcode_escape(str(payload.get("skillName", ""))),
			])
		"SkillCastStarted":
			_on_skill_cast_started(payload)
		"SkillCastCancelled":
			var cancelled_key := _key_for_entity_id(str(payload.get("casterId", "")))
			if cancelled_key == PLAYER_KEY and _casting_by_key.has(PLAYER_KEY):
				_log("[i]Vous abandonnez %s.[/i]" % _bbcode_escape(str(payload.get("skillName", "l'incantation"))))
			_clear_casting(cancelled_key)
		"CharacterTeleporting":
			_on_character_teleporting(payload)
		"ScrollUsed":
			_log("[i]Vous lisez %s.[/i]" % _bbcode_escape(str(payload.get("name", "le parchemin"))))
		"ItemOnCooldown":
			# rejected : réutilisation refusée (le slot de la hotbar clignote de son côté).
			if bool(payload.get("rejected", false)):
				Sfx.play_ui("action_denied")
				_log("[i]%s n'est pas encore prêt (%.1f s).[/i]" % [
					_bbcode_escape(str(payload.get("name", ""))),
					float(payload.get("remainingMillis", 0)) / 1000.0,
				])
		"TeleportInProgress":
			Sfx.play_ui("action_denied")
			_log("[i]Téléportation en cours…[/i]")
		"SkillFizzled":
			_clear_casting(PLAYER_KEY)
			_log("[i]Incantation ratée : %s[/i]" % _bbcode_escape(
				str(payload.get("reason", ""))
			))
		"AlreadyCasting":
			Sfx.play_ui("action_denied")
			_log("[i]Vous êtes déjà en train d'incanter un sort.[/i]")
		"HealthAlreadyFull", "ManaAlreadyFull":
			# Potion refusée par le serveur, non consommée (voir ConsumableItem côté backend).
			Sfx.play_ui("action_denied")
			_log("[i]%s est inutile : vos %s sont déjà au maximum.[/i]" % [
				_bbcode_escape(str(payload.get("name", "La potion"))),
				"PV" if type == "HealthAlreadyFull" else "PM",
			])
		"SkillOnCooldown":
			# rejected : relance refusée (sinon simple annonce de la recharge qui démarre) — le
			# slot de la hotbar clignote et sonne de son côté (Hotbar.gd).
			if bool(payload.get("rejected", false)):
				_log("[i]%s n'est pas encore prêt (%.1f s).[/i]" % [
					_bbcode_escape(str(payload.get("skillName", ""))),
					float(payload.get("remainingMillis", 0)) / 1000.0,
				])
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
			if str(payload.get("shotType", "")) == "SPIRITSHOT":
				_spiritshot_at_by_key[PLAYER_KEY] = Time.get_ticks_msec()
		"SoulshotUsed":
			var soulshot_node := _entity_node_by_id(str(payload.get("characterId", "")))
			if soulshot_node != null:
				_flash_entity(soulshot_node, SOULSHOT_GLOW_COLOR, SHOT_GLOW_UP_DURATION, SHOT_GLOW_DOWN_DURATION)
		"SpiritshotUsed":
			var spiritshot_node := _entity_node_by_id(str(payload.get("characterId", "")))
			if spiritshot_node != null:
				_flash_entity(spiritshot_node, SPIRITSHOT_GLOW_COLOR, SHOT_GLOW_UP_DURATION, SHOT_GLOW_DOWN_DURATION)
			var spiritshot_key := _key_for_entity_id(str(payload.get("characterId", "")))
			if not spiritshot_key.is_empty():
				_spiritshot_at_by_key[spiritshot_key] = Time.get_ticks_msec()
		"ShotGradeChanged":
			var sg_label := "Soulshot" if str(payload.get("shotType", "")) == "SOULSHOT" else "Spiritshot"
			var sg_grade = payload.get("grade")
			if sg_grade == null:
				_log("[i]%s désactivé.[/i]" % sg_label)
			else:
				_log("[i]%s activé (%s).[/i]" % [sg_label, str(sg_grade)])
		"ShotOutOfStock":
			var out_label := "Soulshots" if str(payload.get("shotType", "")) == "SOULSHOT" else "Spiritshots"
			_log("[i]Plus de %s (%s) — auto-use désactivé.[/i]" % [
				out_label, str(payload.get("grade", "?")),
			])
		"InvalidShotGrade":
			_log("[i]Grade de charge invalide : %s[/i]" % _bbcode_escape(
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
				LOG_COLOR_GAIN, str(payload.get("amount", 0)),
			])
		"PlayerLeveledUp":
			if str(payload.get("characterName", "")) == str(GameState.player_stats.get("name", "")):
				_log("[color=%s]Vous passez au niveau %s ![/color]" % [
					LOG_COLOR_GAIN, str(payload.get("newLevel", "?")),
				])
				Sfx.play_event("level_up")
				# XpGained (déjà reçu juste avant ce message, voir CharacterInstance.gainXp côté
				# backend) reporte xpForCurrentLevel/xpForNextLevel du niveau D'AVANT cette montée
				# — la barre d'XP resterait donc bloquée à un seuil obsolète tant qu'un nouveau
				# GamePlayerStats n'est pas reçu. On le redemande explicitement plutôt que
				# d'attendre le prochain gain d'XP (même pattern que Net.send_command("stats") au
				# _ready de cette scène).
				Net.send_command("stats")
		"EquipmentLooted":
			_log("[color=%s]Vous trouvez : %s[/color]" % [
				LOG_COLOR_GAIN, _bbcode_escape(str(payload.get("itemName", "?"))),
			])
		"GoldLooted":
			_log("[color=%s]Vous trouvez %s pièces d'or.[/color]" % [
				LOG_COLOR_GAIN, str(payload.get("amount", 0)),
			])
		"ItemBought":
			# Réponse à "shop"/"buy" (voir %ShopWindow, qui réagit indépendamment au même
			# message pour son propre panneau de confirmation — même principe que GameState/
			# Game3D réagissant chacun à ShotGradeChanged sans se coordonner).
			# Un achat stackable arrive en un message par pile touchée (quantity = exemplaires
			# versés dans cette pile, voir InventorySystem.store côté backend).
			var bought_quantity := int(payload.get("quantity", 1))
			var bought_name := _bbcode_escape(str(payload.get("itemName", "?")))
			if bought_quantity > 1:
				bought_name = "%s x%d" % [bought_name, bought_quantity]
			_log("[color=%s]Vous achetez : %s (%s or).[/color]" % [
				LOG_COLOR_GAIN, bought_name, str(payload.get("price", 0)),
			])
		"NotEnoughGold":
			_log("[i]Pas assez d'or (%s requis).[/i]" % str(payload.get("price", 0)))
		"ShopItemNotFound":
			_log("[i]Cet objet n'est plus disponible chez ce marchand.[/i]")
		"GamePlayerDefeated":
			_log_player_defeated(payload)
			var defeated_node := _character_node_by_name(str(payload.get("characterName", "")))
			if defeated_node != null and defeated_node != _player_node \
					and defeated_node == _entity_node_by_id(_selected_target_id):
				_play_kill_sound(_selected_target_id)
			_play_body_death(defeated_node)
			if str(payload.get("characterName", "")) == str(GameState.player_stats.get("name", "")):
				_death_popup.open(str(payload.get("killerName", "")))
		"PlayerRespawned":
			_log("Vous revenez à la vie.")
			_death_popup.close()
			_play_body_revive(_player_node)
			var respawn_level := int(_entity_vitals_by_key.get(PLAYER_KEY, {}).get("level", 1))
			_entity_vitals_by_key[PLAYER_KEY] = {
				"current": int(payload.get("currentHealth", 0)), "max": int(payload.get("maxHealth", 0)),
				"level": respawn_level,
			}
		"Inventory":
			_apply_player_equipment(payload)
		"CharacterAppearanceChanged":
			# Un joueur à portée a équipé/retiré un objet (jamais nous : le serveur nous exclut,
			# notre propre tenue suit l'Inventory).
			_set_body_equipment(_entity_node_by_id(str(payload.get("characterId", ""))), payload.get("equipment", []))
		"ItemEquipped", "ItemUnequipped":
			Sfx.play_item(_equipment_sound_slot(payload), type == "ItemEquipped")
			# Ces deux messages ne portent pas l'inventaire complet (slot par objet) : on le
			# redemande pour rhabiller le personnage — même geste qu'EquipmentWindow.
			Net.send_command("inventory")
		"CharacterIsDead":
			_log("[i]Vous êtes mort — impossible tant que vous n'avez pas réapparu.[/i]")
		"CharacterNotDead":
			_log("[i]Vous n'êtes pas mort.[/i]")
		"NoPortalHere":
			_log("[i]Vous n'êtes pas assez proche d'un portail.[/i]")
		"CombatForbiddenHere":
			_log("[i]Combat impossible ici (%s).[/i]" % _bbcode_escape(
				str(payload.get("zoneName", "?"))
			))
		"Chat":
			# Diffusé à toute la zone SAUF au locuteur (voir "YouSaid" ci-dessous) — comme
			# SkillCastAnnounced/CastResult, le serveur sépare toujours l'écho à l'auteur du
			# message diffusé aux autres.
			_log_chat("[color=%s][b]%s[/b] : %s[/color]" % [
				LOG_COLOR_SAY,
				_bbcode_escape(str(payload.get("speakerName", "?"))),
				_bbcode_escape(str(payload.get("text", ""))),
			])
		"YouSaid":
			# Écho envoyé uniquement à l'auteur d'un "say" (jamais inclus dans "Chat", voir
			# ci-dessus) — absent jusqu'ici, ce qui faisait qu'aucun message tapé par
			# soi-même n'apparaissait dans le chat (bug signalé le 2026-09-02, flagrant en
			# session solo puisque "Chat" n'a alors personne d'autre à qui être diffusé).
			_log_chat("[color=%s][b]Vous[/b] : %s[/color]" % [
				LOG_COLOR_SAY, _bbcode_escape(str(payload.get("text", ""))),
			])
		"Whisper":
			# "say #nom message" (voir Say.java, 2026-09-06) : le serveur renvoie le même
			# message aux deux participants, donc c'est au client de distinguer émetteur et
			# destinataire par leur nom pour choisir le bon libellé.
			var whisper_from := str(payload.get("fromName", "?"))
			var whisper_to := str(payload.get("toName", "?"))
			var whisper_text := _bbcode_escape(str(payload.get("text", "")))
			if whisper_from == str(GameState.player_stats.get("name", "")):
				_log_chat("[color=%s][i]Vous chuchotez à %s[/i] : %s[/color]" % [
					LOG_COLOR_WHISPER, _bbcode_escape(whisper_to), whisper_text,
				], "whisper")
			else:
				_log_chat("[color=%s][i]%s vous chuchote[/i] : %s[/color]" % [
					LOG_COLOR_WHISPER, _bbcode_escape(whisper_from), whisper_text,
				], "whisper")
		"PartyChat":
			# "say %message" (voir Say.java, 2026-09-06) : diffusé à tout le groupe, l'auteur
			# compris (contrairement à Chat/YouSaid, pas d'écho séparé à distinguer ici).
			_log_chat("[color=%s][i][Groupe][/i] [b]%s[/b] : %s[/color]" % [
				LOG_COLOR_PARTY,
				_bbcode_escape(str(payload.get("speakerName", "?"))),
				_bbcode_escape(str(payload.get("text", ""))),
			], "party")
		"CannotWhisperSelf":
			_log("[i]Vous ne pouvez pas vous chuchoter à vous-même.[/i]")
		"WhisperTargetNotFound":
			_log("[i]%s n'est pas connecté.[/i]" % _bbcode_escape(str(payload.get("name", "?"))))
		"NotInParty", "PartyInviteSent", "PartyInviteReceived", "PartyInviteDeclined", "PartyJoined", \
				"PartyMemberJoined", "PartyMemberLeft", "PartyMemberKicked", "KickedFromParty", "PartyLeft", \
				"PartyDisbanded", "NewPartyLeader", "PartyLootModeChanged", "AlreadyInParty", "PartyFull", \
				"NotPartyLeader", "NoPendingInvite", "CannotInviteSelf", "CannotKickSelf", "NoSuchPartyMember":
			_on_party_message(type, payload)
		"PeaceZoneEntered":
			_log("Zone paisible (%s) : %s" % [
				_bbcode_escape(str(payload.get("zoneName", "?"))),
				_bbcode_escape(str(payload.get("description", ""))),
			])
		"PeaceZoneExited":
			_log("Vous quittez la zone paisible : %s." % _bbcode_escape(str(payload.get("zoneName", "?"))))
		"SkillLearned":
			# Maître des compétences (learn-skill) ou compétence acquise d'office en montant de
			# niveau : on redemande la liste (livre, barre) et les stats (passifs).
			Sfx.play_ui("skill_learn")
			_log("[color=%s]Vous apprenez %s (niv. %s).[/color]" % [
				LOG_COLOR_GAIN, _bbcode_escape(str(payload.get("skillName", "?"))), str(payload.get("level", "?")),
			])
			Net.send_command("skills")
			Net.send_command("stats")
		"NewSkillsAvailable":
			_log("[color=%s]De nouvelles compétences vous attendent auprès du Maître des compétences de la Place du village.[/color]" % LOG_COLOR_GAIN)
		"SkillNotLearnable":
			Sfx.play_ui("action_denied")
		"SkillWeaponRequired":
			Sfx.play_ui("action_denied")
			_log("[i]%s nécessite une arme adaptée : %s.[/i]" % [
				_bbcode_escape(str(payload.get("skillName", "?"))),
				SkillTooltip.weapons_label(payload.get("weaponTypes", [])),
			])
		"EffectDamage":
			_on_effect_damage(payload)
		"SkillDrained":
			_on_skill_drained(payload)
		"Error":
			_log(_bbcode_escape(str(payload.get("message", "Erreur."))))
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
	_clear_portals()
	_release_input_for_loading()
	# Au changement de carte (portail, Scroll of Escape, respawn), le backend fait
	# leave()-puis-join() avant d'envoyer MapView : les EntityAppeared/PortalAppeared de la
	# nouvelle carte sont donc déjà arrivés (et effacés ci-dessus). GameState les a gardés en
	# cache (l'ancienne carte en a été retirée par les EntityDisappeared/PortalDisappeared de
	# KnownList.clear()) : on les rejoue, sinon PNJ et téléporteurs immobiles n'apparaîtraient
	# qu'en sortant puis en revenant dans leur portée.
	for entry in GameState.appeared_entities.values():
		_apply_appeared_entity(entry)
	for entry in GameState.appeared_portals.values():
		_apply_appeared_portal(entry)

	for child in _map_scene_root.get_children():
		child.queue_free()

	# La scène de carte (sol, décor, props) est chargée en tâche de fond derrière l'écran de
	# chargement puis construite étape par étape (_advance_map_load) : la carte n'apparaît
	# qu'une fois entièrement prête. Tout ce qui précède reste immédiat pour que les messages
	# qui suivent MapView (MapEnter, EntityAppeared, PortalAppeared) s'appliquent pendant le
	# chargement sur un état déjà remis à zéro.
	_map_load_base = LoadingScreen.begin(_current_map_name)
	_map_load_payload = payload
	_map_load_packed = null
	_map_load_instance = null
	_map_load_scene_path = ZoneAssets3D.get_map_scene_path(_current_map_name)
	_map_load_step = MapLoadStep.BUILD
	if _map_load_scene_path.is_empty():
		push_warning("Game3D: aucune scène convertie pour la carte '%s'" % _current_map_name)
	else:
		var err := ResourceLoader.load_threaded_request(_map_load_scene_path, "", true)
		if err == OK:
			_map_load_step = MapLoadStep.LOADING
		else:
			push_warning("Game3D: chargement impossible de %s (%s)" % [_map_load_scene_path, error_string(err)])


## Fait avancer le chargement lancé par _rebuild_map d'une étape par image (appelé en tête
## de _process) : chargement de la scène en tâche de fond (0 → 70 % de la part de barre du
## chargement de carte), instanciation (80 %), construction minimap/obstacles/lumières
## (90 %), puis quelques images de rendu masqué (100 %) avant de rendre la main au joueur.
func _advance_map_load() -> void:
	match _map_load_step:
		MapLoadStep.LOADING:
			var progress := []
			var status := ResourceLoader.load_threaded_get_status(_map_load_scene_path, progress)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_set_map_load_progress(0.7 * (float(progress[0]) if not progress.is_empty() else 0.0))
				return
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_map_load_packed = ResourceLoader.load_threaded_get(_map_load_scene_path)
			else:
				push_warning("Game3D: échec du chargement de %s" % _map_load_scene_path)
			_set_map_load_progress(0.7)
			_map_load_step = MapLoadStep.INSTANTIATE
		MapLoadStep.INSTANTIATE:
			if _map_load_packed != null:
				_map_load_instance = _map_load_packed.instantiate()
				_map_scene_root.add_child(_map_load_instance)
			_map_load_packed = null
			_set_map_load_progress(0.8)
			_map_load_step = MapLoadStep.BUILD
		MapLoadStep.BUILD:
			_build_loaded_map(_map_load_payload, _map_load_instance)
			_map_load_payload = {}
			_map_load_instance = null
			_set_map_load_progress(0.9)
			_map_load_frames = 0
			_map_load_step = MapLoadStep.WARMUP
		MapLoadStep.WARMUP:
			_map_load_frames += 1
			_set_map_load_progress(0.9 + 0.1 * float(_map_load_frames) / MAP_LOAD_WARMUP_FRAMES)
			if _map_load_frames >= MAP_LOAD_WARMUP_FRAMES:
				_map_load_step = MapLoadStep.NONE
				LoadingScreen.finish()


func _set_map_load_progress(ratio: float) -> void:
	LoadingScreen.set_progress(lerpf(_map_load_base, 1.0, ratio))


## Début d'un chargement de carte : lâche tout ce qui pourrait rester « tenu » pendant que
## LoadingScreen avale les entrées (relâchement du clic droit jamais reçu -> souris restée
## capturée en rotation caméra, champ de chat encore focalisé, menu PNJ ouvert).
func _release_input_for_loading() -> void:
	_right_click_active = false
	if _camera_orbiting:
		_camera_orbiting = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chat_input.release_focus()
	_npc_menu.hide()


## Fin de _rebuild_map, une fois la scène de carte instanciée (`map_instance` null si aucune
## scène n'existe pour cette carte ou si son chargement a échoué).
func _build_loaded_map(payload: Dictionary, map_instance: Node3D) -> void:
	var grid_map: GridMap = null
	var map_portals: Array = []
	var biome := MapData.Biome.NONE
	_render_obstacle_blocks = true
	if map_instance != null:
		grid_map = map_instance.get_node("Terrain")
		map_portals = _read_map_portals(map_instance)
		if map_instance is MapData:
			biome = map_instance.biome
			_render_obstacle_blocks = map_instance.render_obstacle_blocks
	_terrain_grid = _read_terrain_grid(grid_map)
	# Même biome que la carte précédente : la musique continue sans coupure.
	ZoneMusic.play_for_biome(biome)

	var texture := ZoneAssets3D.build_ground_texture(payload, _terrain_grid)

	_rebuild_obstacles()
	_rebuild_night_lights()
	_minimap.set_map(texture, _map_width, _map_height, _current_map_name)
	_map_bounds_veil.set_map_size(Vector2(_map_width, _map_height))
	_world_map.set_map(_current_map_name, _map_width, _map_height, _terrain_grid, _walkable_rows, map_portals)
	_log("Carte :%s (%dx%d)" % [_current_map_name, _map_width, _map_height])


## Nom de terrain par case (voir _terrain_grid) lu directement sur le GridMap de la scène
## de carte tout juste instanciée — remplace l'ancien ZoneAssets3D.get_terrain_grid, qui
## lisait un dictionnaire construit une fois au démarrage depuis les .tmx. `grid_map` est
## null quand aucune scène n'a été trouvée pour la carte (voir _rebuild_map) : renvoie
## alors une grille de "" (fallback marche/bloqué déjà géré par build_ground_texture et
## obstacle_height_for dans ce cas).
func _read_terrain_grid(grid_map: GridMap) -> Array:
	var terrain_grid: Array = []
	var mesh_library: MeshLibrary = grid_map.mesh_library if grid_map != null else null
	for y in _map_height:
		var row: Array = []
		for x in _map_width:
			var terrain_name := ""
			if grid_map != null:
				var item_id := grid_map.get_cell_item(Vector3i(x, 0, y))
				if item_id != GridMap.INVALID_CELL_ITEM and mesh_library != null:
					terrain_name = mesh_library.get_item_name(item_id)
			row.append(terrain_name)
		terrain_grid.append(row)
	return terrain_grid


## Téléporteurs de la carte entière pour la carte (voir WorldMapWindow), lus sur les
## PortalMarker3D de la scène plutôt que sur _portals : le serveur ne pousse que ceux à portée
## de perception. [{position: Vector2 (cases), target_map_name}].
func _read_map_portals(map_instance: Node) -> Array:
	var portals: Array = []
	var objects := map_instance.get_node_or_null("Objects")
	if objects == null:
		return portals
	for child in objects.get_children():
		if child is Node3D and "target_map_id" in child:
			portals.append({
				"position": Vector2(child.position.x, child.position.z),
				"target_map_name": ZoneAssets3D.get_map_name_by_id(str(child.target_map_id)),
			})
	return portals


func _rebuild_obstacles() -> void:
	var transforms: Array[Transform3D] = []
	if not _render_obstacle_blocks:
		_obstacles.multimesh = null
		return
	for y in _map_height:
		var row: String = _walkable_rows[y] if y < _walkable_rows.size() else ""
		var terrain_row: Array = _terrain_grid[y] if y < _terrain_grid.size() else []
		for x in _map_width:
			var walkable: bool = x < row.length() and row[x] == "1"
			var terrain_name: String = terrain_row[x] if x < terrain_row.size() else ""
			var height := ZoneAssets3D.obstacle_height_for(terrain_name, walkable)
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

	# Carte décorée : ses bâtiments (auberge, forge...) portent leurs propres lumières (voir
	# scenes/maps/props/House.gd), pas de lueur procédurale par-dessus.
	for terrain_name in (LANDMARK_LIGHTS if _render_obstacle_blocks else {}):
		var props: Dictionary = LANDMARK_LIGHTS[terrain_name]
		for cluster_center in _terrain_clusters(_terrain_grid, terrain_name):
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
	# Lampadaires, fontaine... posés dans la scène de carte (voir LampPost.NIGHT_GROUP).
	get_tree().call_group(LampPost.NIGHT_GROUP, "set_night_factor", factor)


## Position du joueur et direction de la caméra pour le tramage des arbres/props qui le
## cachent (voir scenes/maps/common/occlusion_fade.gdshaderinc).
func _update_occlusion_globals() -> void:
	var player_pos := Vector3(0.0, -1000.0, 0.0)
	if _player_node != null:
		player_pos = _player_node.global_position
	RenderingServer.global_shader_parameter_set(&"player_world_position", player_pos)
	RenderingServer.global_shader_parameter_set(&"main_camera_direction", -_camera.global_basis.z)


## Hors de la grille (décor de lisière sous le voile, voir MapBoundsVeil) : jamais
## praticable, le serveur n'y trouverait aucun chemin.
func _is_walkable(target: Vector2) -> bool:
	if _walkable_rows.is_empty():
		return true
	var cx := int(floor(target.x))
	var cy := int(floor(target.y))
	if cx < 0 or cy < 0 or cx >= _map_width or cy >= _map_height:
		return false
	if cy >= _walkable_rows.size():
		return true
	var row: String = _walkable_rows[cy]
	if cx >= row.length():
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


## Portail : effet PortalVfx (cercle de runes, colonne d'énergie torsadée, couronnes qui
## s'élèvent, étincelles — symétrique autour de Y, donc juste sous tout angle de caméra) +
## zone de clic englobant toute la colonne + nom/titre au-dessus.
func _make_portal_node(portal_name: String, portal_title: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Portal"
	var vfx := PortalVfx.new()
	root.add_child(vfx)
	root.set_meta("vfx", vfx)

	# Zone de collision englobant tout l'objet, pas juste la base — voir
	# _pick_portal_id_at_mouse, même mécanisme que PickArea dans _make_entity_node (couche
	# physique dédiée PORTAL_PICK_COLLISION_LAYER).
	var pick_area := Area3D.new()
	pick_area.name = "PickArea"
	pick_area.collision_layer = PORTAL_PICK_COLLISION_LAYER
	pick_area.collision_mask = 0
	var pick_shape := CollisionShape3D.new()
	var pick_cylinder := CylinderShape3D.new()
	pick_cylinder.radius = PortalVfx.COLUMN_RADIUS + 0.15
	pick_cylinder.height = PortalVfx.HEIGHT
	pick_shape.shape = pick_cylinder
	pick_area.position = Vector3(0.0, pick_cylinder.height / 2.0, 0.0)
	pick_area.add_child(pick_shape)
	root.add_child(pick_area)

	# Nom/titre façon personnage (voir _make_entity_node/TITLE_LABEL_COLOR) plutôt que l'ancien
	# libellé unique affichant la carte cible : "Clairière"/"Téléporteur" identifient l'objet
	# lui-même, la destination reste affichée dans %TargetStatusBar (voir _select_portal).
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = portal_name
	label.position = Vector3(0.0, PortalVfx.HEIGHT + 0.3, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 6
	label.modulate = PortalVfx.COLOR.lightened(0.4)
	label.font = UITheme.font_bold
	root.add_child(label)

	var title_label := Label3D.new()
	title_label.name = "TitleLabel"
	title_label.text = portal_title
	title_label.position = Vector3(0.0, PortalVfx.HEIGHT + 0.63, 0.0)
	title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title_label.no_depth_test = true
	title_label.font_size = 20
	title_label.outline_size = 5
	title_label.modulate = TITLE_LABEL_COLOR
	title_label.font = UITheme.font_bold
	root.add_child(title_label)

	return root


func _set_portal_highlight(portal_id: String, on: bool) -> void:
	if not _portals.has(portal_id):
		return
	var node: Node3D = _portals[portal_id].node
	(node.get_meta("vfx") as PortalVfx).set_highlight(on)


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
			_open_npc_menu(bool(target_node.get_meta("has_shop", false)),
				str(target_node.get_meta("npc_type", "")) == SKILL_LEARNER_NPC_TYPE)


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
	_minimap.set_camera_forward(Vector2(-cos(angle), -sin(angle)))


## has_shop : EntityView.hasShop côté backend — désactive "Boutique" pour un PNJ qui ne
## vend rien (voir _apply_appeared_entity), "Parler" reste toujours disponible.
## teaches_skills : PNJ SKILL_LEARNER — seul à activer "Apprendre des compétences".
func _open_npc_menu(has_shop: bool, teaches_skills := false) -> void:
	_npc_menu.set_item_disabled(1, not has_shop)
	_npc_menu.set_item_disabled(2, not teaches_skills)
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
		2:
			Net.send_command("skill-list", _selected_target_id)


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


## Clic sur un membre de %PartyWindow : le cible comme un clic dans le monde (utile pour le
## soigner/buffer). Hors de notre carte, le serveur répond TargetNotFound.
func _on_party_member_selected(member_id: String) -> void:
	Net.send_command("select", member_id)
	_clear_portal_selection()


## Vrai si la cible est un autre joueur qu'on peut inviter : on n'a pas de groupe, ou on en
## est le chef et il n'y est pas encore (8 membres au plus, voir Party.MAX_SIZE côté backend).
func _can_invite_selected() -> bool:
	var my_id := str(GameState.player_stats.get("id", ""))
	if _selected_target_id.is_empty() or _selected_target_id == my_id:
		return false
	var node := _entity_node_by_id(_selected_target_id)
	if node == null or str(node.get_meta("kind", "")) != "character":
		return false
	if GameState.party.is_empty():
		return true
	var members: Dictionary = GameState.party.get("members", {})
	return str(GameState.party.get("leader_id", "")) == my_id and not members.has(_selected_target_id) \
			and members.size() < PARTY_MAX_SIZE - 1


## Messages du groupe (voir le match de _on_message_received) : GameState a déjà mis
## GameState.party à jour (voir GameState.party_changed) ; ici, seulement le journal, les sons
## (arrivée d'un membre / départ, exclusion ou dissolution) et la fenêtre d'invitation.
func _on_party_message(type: String, payload: Dictionary) -> void:
	var my_id := str(GameState.player_stats.get("id", ""))
	match type:
		"PartyInviteSent":
			_log_party("Vous invitez %s à rejoindre votre groupe." % _bbcode_escape(str(payload.get("targetName", "?"))))
		"PartyInviteReceived":
			var inviter := str(payload.get("inviterName", "?"))
			_log_party("%s vous invite à rejoindre son groupe." % _bbcode_escape(inviter))
			_party_invite_dialog.open(inviter)
		"PartyInviteDeclined":
			# Même message pour un refus et une expiration, envoyé aux deux joueurs avec le nom
			# de l'autre : si notre fenêtre d'invitation vient de cet inviteur, c'est nous
			# l'invité.
			var other := str(payload.get("otherName", "?"))
			if _party_invite_dialog.visible and _party_invite_dialog.inviter_name == other:
				var line := "Vous déclinez l'invitation de %s." if _party_invite_dialog.declined \
						else "L'invitation de %s a expiré."
				_log("[i]%s[/i]" % (line % _bbcode_escape(other)))
				_party_invite_dialog.close()
			else:
				_log("[i]%s a décliné votre invitation.[/i]" % _bbcode_escape(other))
		"PartyJoined":
			_party_invite_dialog.close()
			_log_party("Vous rejoignez le groupe de %s." % _bbcode_escape(str(payload.get("leaderName", "?"))))
			Sfx.play_ui("party_join")
		"PartyMemberJoined":
			_log_party("%s rejoint le groupe." % _bbcode_escape(str(payload.get("memberName", "?"))))
			Sfx.play_ui("party_join")
		"PartyMemberLeft":
			_log_party("%s a quitté le groupe." % _bbcode_escape(str(payload.get("memberName", "?"))))
			Sfx.play_ui("party_leave")
		"PartyMemberKicked":
			var kicked := _bbcode_escape(str(payload.get("targetName", "?")))
			if str(GameState.party.get("leader_id", "")) == my_id or GameState.party.is_empty():
				_log_party("Vous excluez %s du groupe." % kicked)
			else:
				_log_party("%s a été exclu du groupe." % kicked)
			Sfx.play_ui("party_leave")
		"KickedFromParty":
			_log_party("Vous avez été exclu du groupe.")
			Sfx.play_ui("party_leave")
		"PartyLeft":
			_log_party("Vous quittez le groupe.")
			Sfx.play_ui("party_leave")
		"PartyDisbanded":
			_log_party("Le groupe est dissous.")
			Sfx.play_ui("party_leave")
		"NewPartyLeader":
			if str(payload.get("leaderId", "")) == my_id:
				_log_party("Vous êtes désormais le chef du groupe.")
			else:
				_log_party("%s est désormais le chef du groupe." % _bbcode_escape(str(payload.get("leaderName", "?"))))
		"PartyLootModeChanged":
			var loot_label := "Aléatoire" if str(payload.get("lootMode", "")) == "RANDOM" else "Tour par tour"
			_log_party("Mode de butin du groupe : %s." % loot_label)
		"NotInParty":
			_log("[i]Vous n'êtes dans aucun groupe.[/i]")
		"AlreadyInParty":
			_log("[i]%s fait déjà partie d'un groupe.[/i]" % _bbcode_escape(str(payload.get("targetName", "?"))))
		"PartyFull":
			_party_invite_dialog.close()
			_log("[i]Le groupe est complet.[/i]")
		"NotPartyLeader":
			_log("[i]Seul le chef du groupe peut faire cela.[/i]")
		"NoPendingInvite":
			_party_invite_dialog.close()
			_log("[i]Aucune invitation en attente.[/i]")
		"CannotInviteSelf":
			_log("[i]Vous ne pouvez pas vous inviter vous-même.[/i]")
		"CannotKickSelf":
			_log("[i]Vous ne pouvez pas vous exclure vous-même.[/i]")
		"NoSuchPartyMember":
			_log("[i]Ce joueur ne fait pas partie de votre groupe.[/i]")


## Ligne de journal système aux couleurs du groupe (même vert que le canal #Groupe).
func _log_party(text: String) -> void:
	_log("[color=%s]%s[/color]" % [LOG_COLOR_PARTY, text])


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


## Échap ou croix de %TargetStatusBar : désélectionne l'entité (côté serveur aussi) et le portail.
func _deselect_all() -> void:
	if not _selected_target_id.is_empty():
		Net.send_command("select", "")
		_clear_selection()
	_clear_portal_selection()


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
	_selection_ring.position = Vector3(node.position.x, 0.04, node.position.z)
	# Réévalué chaque frame : l'entrée/sortie du groupe change la couleur sans resélection.
	var mat: ShaderMaterial = _selection_ring.get_meta("material")
	mat.set_shader_parameter("ring_color", _selection_color_for(_selected_target_id, key))
	_selection_ring.visible = true


func is_player_casting() -> bool:
	return _casting_by_key.has(PLAYER_KEY) or Time.get_ticks_msec() < _teleport_lock_until_msec


## Affiche le cercle de portée autour du joueur (voir Hotbar._on_slot_mouse_entered) tant
## que la souris survole un slot "skill" — la portée n'est jamais vérifiée côté client,
## purement indicatif.
func show_skill_range(range_tiles: float) -> void:
	if _player_node == null or range_tiles <= 0.0:
		return
	if _range_indicator == null:
		_range_indicator = VfxLib.ground_quad(1.0, VfxLib.shader_material(RANGE_RING_SHADER))
		_range_indicator.visible = false
		_world.add_child(_range_indicator)
	# Le plan porteur déborde un peu du cercle pour laisser la place au halo du filet extérieur.
	var radius := maxf(range_tiles, 0.1)
	var half_size := radius + 0.3
	(_range_indicator.mesh as PlaneMesh).size = Vector2.ONE * half_size * 2.0
	var mat := VfxLib.mat_of(_range_indicator)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("half_size", half_size)
	_range_indicator.position = Vector3(_player_node.position.x, 0.06, _player_node.position.z)
	if not _range_indicator.visible:
		_range_indicator.visible = true
		VfxLib.tween_param(_range_indicator.create_tween(), mat, "alpha", 0.0, 1.0, 0.18).set_ease(Tween.EASE_OUT)


func hide_skill_range() -> void:
	if _range_indicator != null:
		_range_indicator.visible = false


# ---------------------------------------------------------------------------
# Entités
# ---------------------------------------------------------------------------

func _refresh_entities(view: Dictionary) -> void:
	var self_pos := Vector2(view.get("selfX", 0.0), view.get("selfY", 0.0))
	_ensure_player_node()
	_moving.erase(PLAYER_KEY)
	_place_entity(PLAYER_KEY, Vector3(self_pos.x, 0.0, self_pos.y))
	_face_heading(_player_node, float(view.get("selfHeading", 0.0)), true)
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
	# EntityView.npcType/gender (backend, 2026-09-27) : un garde est un mannequin homme ou
	# femme en armure lourde, écu et épée courte (voir Character.NPC_OUTFITS).
	var npc_type := str(entry.get("npcType", "")) if entry.get("npcType") != null else ""
	var node := _ensure_entity_node(key, entity_name, color)
	if kind == "npc":
		var npc_body := _character_body(node)
		if npc_body != null:
			_set_body_gender(node, str(entry.get("gender", "")) if entry.get("gender") != null else "")
			npc_body.set_outfit(npc_type)
	_place_entity(key, Vector3(entry.get("x", 0.0), 0.0, entry.get("y", 0.0)))
	_set_entity_title(node, _extract_title(entry))
	_face_heading(node, float(entry.get("heading", 0.0)), true)
	_entity_speed_by_key[key] = float(entry.get("speed", DEFAULT_SPEED_TILES_PER_SEC))
	# EntityView.hasShop côté backend (2026-09-04, "Shop PNJ") : détermine si le clic droit sur
	# ce PNJ, une fois sélectionné, propose "Boutique" (voir _handle_right_click/_open_npc_menu).
	node.set_meta("has_shop", bool(entry.get("hasShop", false)))
	# Maître des compétences (NpcType SKILL_LEARNER) : le menu propose "Apprendre des
	# compétences" (commande skill-list, voir %SkillLearnWindow).
	node.set_meta("npc_type", npc_type)
	# Détermine si le clic droit propose le menu PNJ ("Parler"/"Boutique") du tout, voir
	# _handle_right_click.
	node.set_meta("kind", kind)
	if kind == "character":
		# EntityView.gender/equipment (backend, 2026-09-26) : bon mannequin, habillé. Mis à
		# jour ensuite par CharacterAppearanceChanged.
		_set_body_gender(node, str(entry.get("gender", "")))
		_set_body_equipment(node, entry.get("equipment", []))
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
		var target := Vector3(float(target_x), 0.0, float(target_y))
		_start_path(key, _payload_path(entry, target), kind != "monster")
		_play_body_state(node, Character.RUN_ANIM)
	else:
		_moving.erase(key)
		_play_body_state(node, Character.IDLE_ANIM)


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
	# _pick_entity_id_at_mouse — aucune PickArea créée pour ce nœud). humanoid = true : le
	# joueur est toujours un personnage (mannequin), jamais un monstre/PNJ.
	_player_node = _make_entity_node(player_name, PLAYER_COLOR, false, true)
	_set_entity_title(_player_node, _extract_title(GameState.player_stats))
	_set_body_gender(_player_node, str(GameState.player_stats.get("gender", "")))
	if not GameState.inventory.is_empty():
		_apply_player_equipment(GameState.inventory)
	_entities_root.add_child(_player_node)
	_entities_by_key[PLAYER_KEY] = _player_node
	_ensure_bars(PLAYER_KEY)


## `key` porte déjà le "kind" serveur en préfixe ("character:"/"monster:"/"npc:", voir
## _apply_appeared_entity et les gestionnaires Character/MovementStarted) : un personnage a
## toujours le mannequin (voir Character.gd), un monstre son modèle animé s'il en a un (voir
## MonsterCatalog/Monster.gd) ; un PNJ a lui aussi le mannequin, habillé par
## _apply_appeared_entity selon son rôle (EntityView.npcType, voir Character.NPC_OUTFITS —
## tenue de villageois par défaut) ; les monstres sans modèle restent des capsules.
func _ensure_entity_node(key: String, entity_name: String, color: Color) -> Node3D:
	if _entities_by_key.has(key):
		return _entities_by_key[key]
	var monster_model: MonsterModel = null
	if key.begins_with("monster:"):
		monster_model = MonsterCatalog.model_for(entity_name)
	var humanoid := key.begins_with("character:") or key.begins_with("npc:")
	var node := _make_entity_node(entity_name, color, true, humanoid, monster_model)
	_entities_root.add_child(node)
	_entities_by_key[key] = node
	_ensure_bars(key)
	return node


## `humanoid` : mannequin (voir CHARACTER_SCENE/Character.gd — squelette, animations,
## équipement visible) pour les personnages joueurs ; `monster_model` : modèle animé d'un
## monstre (voir Monster.gd), gabarit (hauteur, zone cliquable) compris ; sinon capsule
## colorée (PNJ, monstres sans modèle). `color` est ignoré pour les modèles importés (ils
## portent leurs propres matériaux) — seul le nom flottant/l'anneau de sélection les distingue.
func _make_entity_node(
	entity_name: String, color: Color, pickable: bool, humanoid: bool = false,
	monster_model: MonsterModel = null
) -> Node3D:
	var root := Node3D.new()
	root.name = entity_name if not entity_name.is_empty() else "Entity"
	# Godot renomme silencieusement les nœuds enfants homonymes (ex. "Fox" -> "Fox2") pour
	# garder des noms de frères et sœurs uniques sous _entities_root : root.name n'est donc pas
	# fiable pour retrouver un monstre par son nom serveur (voir _despawn_monster) une fois
	# plusieurs monstres homonymes présents — meta séparée, jamais réécrite par le moteur.
	root.set_meta("entity_name", entity_name)
	# Sommet de la silhouette, base de l'empilement nom/barres (voir _layout_overhead).
	var head_height := HEAD_HEIGHT_HUMANOID if humanoid else HEAD_HEIGHT_CAPSULE
	if monster_model != null:
		head_height = monster_model.head_height
	root.set_meta("head_height", head_height)

	# Gabarit de la zone cliquable (voir plus bas) — repris de l'ancienne capsule visuelle même
	# pour le mannequin (1.78 unité de haut pour l'homme, 1.68 pour la femme, voir
	# tools/character_gen/build_characters.py) :
	# juste une approximation de silhouette humaine, pas besoin de coller au mesh réel. Un
	# monstre animé fournit le sien (voir MonsterModel.pick_radius/pick_height).
	var pick_radius := 0.35
	var pick_height := 1.6
	if monster_model != null:
		pick_radius = monster_model.pick_radius
		pick_height = monster_model.pick_height
	var pick_offset := Vector3(0.0, pick_height / 2.0, 0.0)

	var body: Node3D
	if humanoid:
		var character: Character = CHARACTER_SCENE.instantiate()
		character.set_chalk_color(color)
		body = character
	elif monster_model != null:
		var monster := Monster.new()
		monster.setup(monster_model)
		monster.set_chalk_color(color)
		body = monster
	else:
		var mesh_instance := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = pick_radius
		capsule.height = pick_height
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		capsule.material = mat
		mesh_instance.mesh = capsule
		mesh_instance.position = pick_offset
		body = mesh_instance
	body.name = "Body"
	root.add_child(body)

	if pickable:
		# Zone de collision calquée sur le gabarit ci-dessus (voir pick_radius/pick_height/
		# pick_offset) : voir _pick_entity_id_at_mouse pour la requête qui la vise. L'UUID
		# réseau à sélectionner (voir _register_entity_id) est lu directement sur `root` via sa
		# meta "entity_id", pas sur cette zone elle-même.
		var pick_area := Area3D.new()
		pick_area.name = "PickArea"
		pick_area.collision_layer = ENTITY_PICK_COLLISION_LAYER
		pick_area.collision_mask = 0
		pick_area.position = pick_offset
		var pick_shape := CollisionShape3D.new()
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = pick_radius
		capsule_shape.height = pick_height
		pick_shape.shape = capsule_shape
		pick_area.add_child(pick_shape)
		root.add_child(pick_area)

	# Hauteurs (position.y) posées chaque frame par _layout_overhead.
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = entity_name
	_style_world_label(label, NAME_FONT_SIZE, NAME_OUTLINE_SIZE)
	label.modulate = _name_color_for(color)
	root.add_child(label)

	# Titre (fonction/rang, voir TITLE_LABEL_COLOR) : juste au-dessus du nom. Texte vide par
	# défaut (la plupart des entités n'ont pas de titre) : un Label3D sans texte ne dessine
	# rien, et _layout_overhead ne lui réserve alors aucune place.
	var title_label := Label3D.new()
	title_label.name = "TitleLabel"
	title_label.text = ""
	_style_world_label(title_label, TITLE_FONT_SIZE, TITLE_OUTLINE_SIZE)
	title_label.modulate = TITLE_LABEL_COLOR
	root.add_child(title_label)

	return root


## Texte flottant façon UI : police UITheme.font_world, aligné par le bas (voir
## _layout_overhead), toujours face caméra et par-dessus le décor. Rendu à `font_size` puis
## réduit par NAME_PIXEL_SIZE, filtré avec mipmaps pour un contour lisse à tous les zooms.
func _style_world_label(label: Label3D, font_size: int, outline_size: int) -> void:
	label.font = UITheme.font_world
	label.font_size = font_size
	label.outline_size = outline_size
	label.outline_modulate = NAME_OUTLINE_COLOR
	label.pixel_size = NAME_PIXEL_SIZE
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## Hauteur en unités monde d'une ligne de texte d'un Label3D stylé par _style_world_label.
func _world_label_height(font_size: int) -> float:
	return UITheme.font_world.get_height(font_size) * NAME_PIXEL_SIZE


## Couleur du nom flottant selon le type d'entité (voir PLAYER_NAME_COLOR/NPC_NAME_COLOR/
## MONSTER_NAME_COLOR) — `color` est la couleur de capsule passée à _make_entity_node.
func _name_color_for(color: Color) -> Color:
	if color == MONSTER_COLOR:
		return MONSTER_NAME_COLOR
	if color == NPC_COLOR:
		return NPC_NAME_COLOR
	return PLAYER_NAME_COLOR


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
	_smooth_offset_by_key.erase(key)
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
	_spiritshot_at_by_key.clear()
	_moving.clear()
	_smooth_offset_by_key.clear()
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


## Cap serveur (radians, plan x/y serveur). `instant` : apparition, sans rotation animée.
func _face_heading(node: Node3D, heading: float, instant: bool = false) -> void:
	_face_direction(node, Vector3(cos(heading), 0.0, sin(heading)))
	if instant and node.has_meta("yaw_target"):
		node.rotation.y = node.get_meta("yaw_target")
		node.remove_meta("yaw_target")


## Oriente le -Z local de `node` vers `direction` (comme look_at), en douceur via
## _update_facing.
func _face_direction(node: Node3D, direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		return
	node.set_meta("yaw_target", MotionPath.yaw_toward(direction))


func _update_facing(delta: float) -> void:
	var weight := 1.0 - exp(-FACING_SMOOTHING * delta)
	for node in _entities_by_key.values():
		if not node.has_meta("yaw_target"):
			continue
		var target_yaw: float = node.get_meta("yaw_target")
		if absf(angle_difference(node.rotation.y, target_yaw)) < 0.001:
			node.rotation.y = target_yaw
			node.remove_meta("yaw_target")
		else:
			node.rotation.y = lerp_angle(node.rotation.y, target_yaw, weight)


## Idle/course (Character.IDLE_ANIM/RUN_ANIM, même vocabulaire pour Monster.play_state).
## No-op pour une capsule (pas de rig) : évite un `if` dupliqué à chaque appelant.
func _play_body_state(node: Node3D, state_name: String) -> void:
	var body := _animated_body(node)
	if body != null:
		body.play_state(state_name)


## Corps animé de `node`, personnage (Character) ou monstre (Monster), qui partagent
## play_state/play_attack/play_death/revive ; null pour une capsule.
func _animated_body(node: Node3D) -> Node3D:
	if node == null:
		return null
	var body := node.get_node_or_null("Body")
	if body is Character or body is Monster:
		return body
	return null


## Rig du nœud d'entité `node` (null pour un monstre/PNJ, simple capsule) — évite un `if`
## dupliqué dans chaque helper _play_body_* ci-dessous.
func _character_body(node: Node3D) -> Character:
	if node == null:
		return null
	return node.get_node_or_null("Body") as Character


## Coup d'arme (AttackResult) : attack_1h ou attack_2h selon l'arme portée pour un
## personnage, clip d'attaque de sa fiche pour un monstre, puis retour seul à l'état tenu
## (idle/course).
func _play_body_attack(node: Node3D) -> void:
	var body := _animated_body(node)
	if body != null:
		body.play_attack()


## Geste de libération à la fin d'une incantation (voir _clear_casting).
func _play_body_launch(node: Node3D) -> void:
	var body := _character_body(node)
	if body != null:
		body.play_launch()


## Chute au sol, figée jusqu'à _play_body_revive (PlayerRespawned pour nous, retour sur la
## carte pour les autres — voir GamePlayerJoinedMap).
func _play_body_death(node: Node3D) -> void:
	var body := _animated_body(node)
	if body != null:
		body.play_death()


func _play_body_revive(node: Node3D) -> void:
	var body := _animated_body(node)
	if body != null:
		body.revive()


## "man"/"woman" (GamePlayerStats.gender) ou "MAN"/"WOMAN" (EntityView.gender, autres joueurs).
func _set_body_gender(node: Node3D, gender: String) -> void:
	var body := _character_body(node)
	if body != null and not gender.is_empty():
		body.set_gender(gender)


## Nœud d'un personnage par son nom (GamePlayerDefeated ne porte pas d'UUID) — nous-même
## compris.
func _character_node_by_name(character_name: String) -> Node3D:
	if character_name.is_empty():
		return null
	if character_name == str(GameState.player_stats.get("name", "")):
		return _player_node
	return _entities_by_key.get("character:%s" % character_name)


## Habille notre personnage d'après l'Inventory (objets dont `slot` est renseigné = portés,
## voir EquipmentWindow._refresh).
func _apply_player_equipment(inventory_payload: Dictionary) -> void:
	_ensure_player_node()
	_set_body_equipment(_player_node, inventory_payload.get("items", []))


## Slot concerné par ItemEquipped (qui le porte) ou ItemUnequipped (qui ne le porte pas : on
## le lit dans l'Inventory encore non rafraîchi, où l'objet est toujours porté), pour choisir
## le son (voir Sfx.play_item) ; "" si introuvable.
func _equipment_sound_slot(payload: Dictionary) -> String:
	var slot = payload.get("slot")
	if slot != null and not str(slot).is_empty():
		return str(slot)
	var item_id := str(payload.get("itemId", ""))
	var item_name := str(payload.get("name", ""))
	for item in GameState.inventory.get("items", []):
		var item_slot = item.get("slot")
		if item_slot == null or str(item_slot).is_empty():
			continue
		if str(item.get("id", "")) == item_id or str(item.get("name", "")) == item_name:
			return str(item_slot)
	return ""


## `items` : entrées Inventory ou EquipmentView (voir Character.equipped_from_items).
func _set_body_equipment(node: Node3D, items) -> void:
	var body := _character_body(node)
	if body == null or not items is Array:
		return
	body.set_equipment(Character.equipped_from_items(items))


## Comme _play_body_state, mais spécifiquement pour l'incantation (voir Character.play_cast) :
## cale la vitesse du clip CAST_ANIM sur duration_sec (castingTimeMs serveur) plutôt que sa
## vitesse native — no-op silencieux pour une entité sans rig (capsule).
func _play_body_cast(node: Node3D, duration_sec: float) -> void:
	if node == null:
		return
	var body := node.get_node_or_null("Body")
	if body is Character:
		body.play_cast(duration_sec)


## Avance chaque entité en mouvement le long de son chemin (position logique), puis résorbe
## l'écart visuel laissé par les corrections serveur : node.position = logique + écart.
func _step_movement(delta: float) -> void:
	var decay := exp(-POSITION_SMOOTHING_RATE * delta)
	var keys := _moving.keys()
	for key in _smooth_offset_by_key.keys():
		if not _moving.has(key):
			keys.append(key)
	for key in keys:
		var node: Node3D = _entities_by_key.get(key)
		if node == null:
			_moving.erase(key)
			_smooth_offset_by_key.erase(key)
			continue
		var offset: Vector3 = _smooth_offset_by_key.get(key, Vector3.ZERO)
		var logical := node.position - offset
		var move: Dictionary = _moving.get(key, {})
		if not move.is_empty():
			var path: Array = move.path
			var speed: float = _entity_speed_by_key.get(key, DEFAULT_SPEED_TILES_PER_SEC)
			logical = MotionPath.advance(logical, path, speed * delta)
			if path.is_empty():
				_moving.erase(key)
				if move.idle_on_arrival and not _casting_by_key.has(key):
					_play_body_state(node, Character.IDLE_ANIM)
			else:
				_face_direction(node, path[0] - logical)
		offset *= decay
		if offset.length() < POSITION_SMOOTHING_EPSILON:
			offset = Vector3.ZERO
			_smooth_offset_by_key.erase(key)
		else:
			_smooth_offset_by_key[key] = offset
		node.position = logical + offset


## Position logique (sans l'écart visuel en cours de résorption) : celle qui suit le serveur.
func _logical_position(key: String) -> Vector3:
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		return Vector3.ZERO
	return node.position - (_smooth_offset_by_key.get(key, Vector3.ZERO) as Vector3)


## Placement direct (apparition, changement de carte) : pas de lissage.
func _place_entity(key: String, pos: Vector3) -> void:
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		return
	node.position = pos
	_smooth_offset_by_key.erase(key)


## Recale la position logique de `key` sur `server_pos` sans bouger l'affichage : l'écart
## devient un décalage visuel que _step_movement résorbe en douceur (le personnage accélère,
## ralentit ou dérive légèrement au lieu de se téléporter). Le chemin en cours est raccourci
## des waypoints que le serveur a déjà dépassés.
func _correct_position(key: String, server_pos: Vector3) -> void:
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		return
	var logical := _logical_position(key)
	if logical.distance_to(server_pos) > POSITION_SNAP_DISTANCE:
		_place_entity(key, server_pos)
	else:
		_smooth_offset_by_key[key] = node.position - server_pos
	var move: Dictionary = _moving.get(key, {})
	if not move.is_empty():
		MotionPath.drop_passed_waypoints(move.path, logical, server_pos)


func _start_path(key: String, path: Array, idle_on_arrival: bool) -> void:
	_moving[key] = {"path": path, "idle_on_arrival": idle_on_arrival}


## Chemin `waypoints` ([{x, y}...]) d'un message de déplacement, ou ligne droite vers
## `fallback_target` si absent (backend antérieur).
func _payload_path(payload: Dictionary, fallback_target: Vector3) -> Array:
	var path: Array = []
	var waypoints = payload.get("waypoints")
	if waypoints is Array:
		for waypoint in waypoints:
			if waypoint is Dictionary:
				path.append(Vector3(float(waypoint.get("x", 0.0)), 0.0, float(waypoint.get("y", 0.0))))
	if path.is_empty():
		path.append(fallback_target)
	return path


## Fin normale annoncée par le serveur : si l'affichage est encore en chemin tout près du
## point final, il finit d'y courir (repasse en idle à l'arrivée) ; sinon, arrêt recalé.
func _finish_path(key: String, end_pos: Vector3) -> void:
	var move: Dictionary = _moving.get(key, {})
	if not move.is_empty() and not move.path.is_empty() \
			and MotionPath.remaining_length(_logical_position(key), move.path) <= ARRIVAL_WALK_MAX_DISTANCE:
		move.path[move.path.size() - 1] = end_pos
		move.idle_on_arrival = true
		return
	_stop_at(key, end_pos)


## Arrêt en `pos` (stop, attaque, incantation, blocage) : recalage doux et idle.
func _stop_at(key: String, pos: Vector3) -> void:
	_moving.erase(key)
	_correct_position(key, pos)
	_play_body_state(_entities_by_key.get(key), Character.IDLE_ANIM)


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
		entry["hp"] = _make_gauge_bar("hp", BAR_WIDTH, BAR_HEIGHT)
	entry["cast"] = _make_gauge_bar("cast", BAR_WIDTH, BAR_HEIGHT)
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


## Jauge flottante façon HUD (voir UITheme._bar_bg_image/_bar_fill_image, reproduites ici en
## shader pour un seul quad billboard) : contour noir extérieur de `outline_px` px (cible
## sélectionnée seulement, voir TARGET_BAR_OUTLINE_PX), liseré bronze + trait noir d'1 px, fond sombre teinté,
## remplissage en dégradé vertical avec reflet clair en haut et ligne sombre en bas — l'effet
## "tube brillant" des jauges du cadre joueur. Les bordures sont calculées en pixels écran via
## fwidth(UV), donc restent fines et nettes quel que soit le zoom.
const GAUGE_BAR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, specular_disabled, shadows_disabled;

uniform vec4 fill_top : source_color = vec4(0.9, 0.22, 0.2, 1.0);
uniform vec4 fill_bottom : source_color = vec4(0.46, 0.05, 0.05, 1.0);
uniform vec4 back_color : source_color = vec4(0.13, 0.03, 0.03, 1.0);
uniform vec4 frame_color : source_color = vec4(0.4, 0.37, 0.3, 1.0);
uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float outline_px = 0.0;
uniform float opacity = 0.96;

void fragment() {
	vec2 px = max(fwidth(UV), vec2(1e-5));
	vec2 size_px = 1.0 / px;
	vec2 pos_px = UV * size_px;
	float edge = min(min(pos_px.x, size_px.x - pos_px.x), min(pos_px.y, size_px.y - pos_px.y));
	float OUTLINE = outline_px;
	float FRAME = outline_px + 1.0;
	float BORDER = outline_px + 2.0;

	vec3 col;
	if (edge < OUTLINE) {
		col = vec3(0.0);
	} else if (edge < FRAME) {
		col = frame_color.rgb;
	} else if (edge < BORDER) {
		col = vec3(0.0);
	} else {
		float inner_h = max(size_px.y - 2.0 * BORDER, 1.0);
		float y_px = pos_px.y - BORDER;
		float ty = clamp(y_px / inner_h, 0.0, 1.0);
		float inner_w = max(size_px.x - 2.0 * BORDER, 1.0);
		float tx = (pos_px.x - BORDER) / inner_w;
		if (tx <= fill_ratio) {
			col = mix(fill_top.rgb, fill_bottom.rgb, ty);
			col = mix(col, vec3(1.0), 0.22 * (1.0 - clamp(ty / 0.35, 0.0, 1.0)));
			if (y_px < 1.0) {
				col = mix(fill_top.rgb, vec3(1.0), 0.45);
			} else if (y_px > inner_h - 1.0) {
				col = fill_bottom.rgb * 0.6;
			}
			// Bout du remplissage légèrement assombri, comme les bords de la texture HUD.
			if ((fill_ratio - tx) * inner_w < 1.0 && fill_ratio < 1.0) {
				col *= 0.75;
			}
		} else {
			col = mix(back_color.rgb, vec3(0.0), ty * 0.5);
		}
	}
	ALBEDO = col;
	ALPHA = opacity;
}
"""


## Quad billboard dessiné par GAUGE_BAR_SHADER_CODE aux couleurs UITheme.BAR_COLORS[`kind`].
## `bar.material.set_shader_parameter("fill_ratio", ...)` fait avancer le remplissage.
func _make_gauge_bar(kind: String, width: float, height: float) -> Dictionary:
	var colors: Array = UITheme.BAR_COLORS[kind]
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var shader := Shader.new()
	shader.code = GAUGE_BAR_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fill_top", colors[0])
	mat.set_shader_parameter("fill_bottom", colors[1])
	mat.set_shader_parameter("back_color", colors[2])
	mat.set_shader_parameter("frame_color", UITheme.METAL)
	mat.set_shader_parameter("fill_ratio", 1.0)
	quad.material = mat
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false
	_world.add_child(mesh_instance)
	return {"root": mesh_instance, "material": mat, "quad": quad}


func _billboard_node(node: Node3D) -> void:
	node.global_transform.basis = _camera.global_transform.basis


func _update_bars() -> void:
	var selected_key: String = _key_by_entity_id.get(_selected_target_id, "")
	for key in _entity_bars_by_key.keys():
		var node: Node3D = _entities_by_key.get(key)
		if node == null:
			continue
		var bars: Dictionary = _entity_bars_by_key[key]
		var show_hp := false
		if bars.has("hp"):
			var vitals: Dictionary = _entity_vitals_by_key.get(key, {})
			var max_hp := int(vitals.get("max", 0))
			show_hp = max_hp > 0
			if show_hp:
				var ratio := clampf(float(vitals.get("current", 0)) / float(max_hp), 0.0, 1.0)
				bars["hp"].material.set_shader_parameter("fill_ratio", ratio)
		var cast_ratio := -1.0
		if _casting_by_key.has(key):
			var cast_state: Dictionary = _casting_by_key[key]
			var total_ms: float = cast_state.get("total_ms", 0.0)
			cast_ratio = clampf(cast_state.get("elapsed_ms", 0.0) / total_ms, 0.0, 1.0) if total_ms > 0.0 else 0.0
		_layout_overhead(node, bars, show_hp, cast_ratio, key == selected_key)


## Empile barre de vie / barre d'incantation / nom / titre au-dessus de la tête de `node`
## (voir HEAD_HEIGHT_*/OVERHEAD_*) : chaque élément absent (pas de PV connus, pas de titre,
## pas d'incantation — `cast_ratio` < 0) ne réserve aucune place. Les deux jauges restent
## groupées sous le nom, à la même largeur : sur le joueur (sans barre de vie flottante), la
## barre d'incantation prend la place qu'occupe la barre de vie des autres entités.
func _layout_overhead(
	node: Node3D, bars: Dictionary, show_hp: bool, cast_ratio: float, is_target: bool
) -> void:
	var y: float = float(node.get_meta("head_height", HEAD_HEIGHT_CAPSULE)) + OVERHEAD_GAP
	# Jauges "en gras" pour la cible sélectionnée seulement (voir TARGET_BAR_*).
	var bar_width := TARGET_BAR_WIDTH if is_target else BAR_WIDTH
	if bars.has("hp"):
		var hp_bar: Dictionary = bars["hp"]
		var hp_root: Node3D = hp_bar.root
		hp_root.visible = show_hp
		if show_hp:
			var bar_size := Vector2(bar_width, TARGET_BAR_HEIGHT if is_target else BAR_HEIGHT)
			_style_gauge_bar(hp_bar, bar_size, is_target)
			hp_root.position = node.position + Vector3(0, y + bar_size.y / 2.0, 0)
			_billboard_node(hp_root)
			y += bar_size.y + OVERHEAD_SPACING
	if bars.has("cast"):
		var cast_bar: Dictionary = bars["cast"]
		cast_bar.root.visible = cast_ratio >= 0.0
		if cast_ratio >= 0.0:
			var cast_size := Vector2(bar_width, BAR_HEIGHT)
			_style_gauge_bar(cast_bar, cast_size, is_target)
			cast_bar.material.set_shader_parameter("fill_ratio", cast_ratio)
			cast_bar.root.position = node.position + Vector3(0, y + cast_size.y / 2.0, 0)
			_billboard_node(cast_bar.root)
			y += cast_size.y + OVERHEAD_SPACING
	var name_label := node.get_node_or_null("NameLabel") as Label3D
	if name_label != null:
		# Nom en gras + contour épais pour la cible sélectionnée seulement (voir TARGET_NAME_*).
		name_label.font = UITheme.font_world_bold if is_target else UITheme.font_world
		name_label.outline_size = TARGET_NAME_OUTLINE_SIZE if is_target else NAME_OUTLINE_SIZE
		name_label.outline_modulate = TARGET_NAME_OUTLINE_COLOR if is_target else NAME_OUTLINE_COLOR
		name_label.position = Vector3(0.0, y, 0.0)
		y += _world_label_height(NAME_FONT_SIZE)
	var title_label := node.get_node_or_null("TitleLabel") as Label3D
	if title_label != null and not title_label.text.is_empty():
		title_label.position = Vector3(0.0, y, 0.0)


## Taille + contour de la jauge `bar` (voir _make_gauge_bar), mis à jour seulement quand la
## taille change (sélection/désélection).
func _style_gauge_bar(bar: Dictionary, bar_size: Vector2, is_target: bool) -> void:
	var quad: QuadMesh = bar.quad
	if quad.size == bar_size:
		return
	quad.size = bar_size
	bar.material.set_shader_parameter("outline_px", TARGET_BAR_OUTLINE_PX if is_target else 0.0)
	bar.material.set_shader_parameter("opacity", 1.0 if is_target else 0.96)


func _advance_casting(delta: float) -> void:
	for key in _casting_by_key.keys().duplicate():
		var state: Dictionary = _casting_by_key[key]
		state.elapsed_ms += delta * 1000.0
		if state.elapsed_ms >= state.total_ms:
			_clear_casting(key, true)


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
	var animated := _animated_body(node)
	if animated != null:
		animated.flash(color, up_duration, down_duration)
		return
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
	label.font = UITheme.font_bold
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
	# Un nouveau cast remplace le précédent (jamais deux cercles sous le même lanceur).
	_finish_cast_vfx(key, false)
	var skill_name := str(payload.get("skillName", ""))
	var state := {"elapsed_ms": 0.0, "total_ms": total_ms}
	_casting_by_key[key] = state
	var caster_node: Node3D = _entities_by_key.get(key)
	# Le lanceur fait face à sa cible (inchangé côté serveur pour un sort sur soi-même).
	if caster_node != null and payload.has("casterHeading"):
		_face_heading(caster_node, float(payload.get("casterHeading", 0.0)))
	# Cercle d'incantation calé sur castingTimeMs (voir CastCircle), couleur selon l'élément,
	# avec couronnes flottantes seulement si le cast est chargé d'un spiritshot.
	var element := SpellVfx.element_for_skill(skill_name)
	state["element"] = element
	if element == SpellVfx.Element.PHYSICAL:
		# Compétence martiale (Power Strike, Mortal Blow, Power Shot) : pas de pose
		# d'incantation — le combattant reste en garde pendant que son arme se charge
		# d'énergie, puis frappe (voir _clear_casting).
		state["physical"] = true
		if caster_node != null:
			_spell_vfx.play_weapon_charge(caster_node, skill_name, total_ms / 1000.0)
	else:
		_play_body_cast(caster_node, total_ms / 1000.0)
	var shot_at: int = _spiritshot_at_by_key.get(key, -SPIRITSHOT_CAST_WINDOW_MS - 1)
	_spiritshot_at_by_key.erase(key)
	var charged := Time.get_ticks_msec() - shot_at <= SPIRITSHOT_CAST_WINDOW_MS
	if caster_node != null and SpellVfx.has_cast_circle(element):
		state["vfx"] = _spell_vfx.start_cast(caster_node, element, total_ms / 1000.0, charged)
	# Son d'incantation propre à l'élément, éteint par _clear_casting (voir Sfx).
	state["sfx"] = Sfx.play_spell(element, "cast", caster_node)


## `completed` : fin normale du temps d'incantation (voir _advance_casting) -> geste de
## libération du sort (Character.play_launch, qui revient ensuite seul à idle/course) et
## libération du cercle ; une annulation (SkillCastCancelled/SkillFizzled) revient directement
## à idle/course et brise le cercle.
func _clear_casting(key: String, completed: bool = false) -> void:
	if key.is_empty():
		return
	_finish_cast_vfx(key, completed)
	var state: Dictionary = _casting_by_key.get(key, {})
	# Le son d'incantation s'efface pour laisser la place au son de libération.
	Sfx.fade_out(state.get("sfx"), 0.25 if completed else 0.15)
	_casting_by_key.erase(key)
	var node: Node3D = _entities_by_key.get(key)
	_play_body_state(node, Character.RUN_ANIM if _moving.has(key) else Character.IDLE_ANIM)
	if completed:
		if state.get("physical", false):
			_play_body_attack(node)
		else:
			_play_body_launch(node)
		if state.has("element"):
			Sfx.play_spell(int(state["element"]), "launch", node)


## Fin d'un Scroll of Escape (nous ou un autre joueur) : le pentagramme blanc se libère (s'il
## ne l'a pas déjà fait à l'expiration locale du cast) et la lumière emporte le personnage vers
## le ciel pendant delayMs ; le serveur le téléporte ensuite (MapView pour nous,
## GamePlayerLeftMap pour les autres).
func _on_character_teleporting(payload: Dictionary) -> void:
	var key := _key_for_entity_id(str(payload.get("characterId", "")))
	var delay_ms := float(payload.get("delayMs", 0))
	if key == PLAYER_KEY:
		_teleport_lock_until_msec = Time.get_ticks_msec() + int(delay_ms) + 3000
		_log("[i]Une lumière vous emporte vers %s…[/i]" % _bbcode_escape(
			str(payload.get("destinationMapName", "la ville"))
		))
	if _casting_by_key.has(key):
		_clear_casting(key, true)
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		return
	_spell_vfx.play_escape(node, delay_ms / 1000.0)
	Sfx.play_spell_at_point(SpellVfx.Element.ESCAPE, "impact", _spell_vfx, node.global_position)


## Termine le cercle d'incantation en cours de `key` s'il y en a un (voir CastCircle.finish).
func _finish_cast_vfx(key: String, completed: bool) -> void:
	var state: Dictionary = _casting_by_key.get(key, {})
	# Variant d'abord : assigner une instance déjà libérée à une variable typée lèverait une erreur.
	var circle: Variant = state.get("vfx")
	if is_instance_valid(circle):
		(circle as CastCircle).finish(completed)


## Anime l'effet d'un sort sur sa cible : soin (colonne de lumière qui monte du sol), buff
## (anneaux qui s'élèvent), debuff (sceau qui descend de la tête aux pieds), impact direct pour
## un sort à dégâts sans projectile (voir NON_PROJECTILE_DAMAGE_SKILLS) ou une compétence
## physique. Un sort à dégâts AVEC projectile est animé séparément, dès son lancer, par
## _on_skill_projectile_launched (impact compris).
func _play_skill_animation(target_id: String, skill_name: String) -> void:
	var target_node := _entity_node_by_id(target_id)
	if target_node == null:
		return
	var element := SpellVfx.element_for_skill(skill_name)
	match element:
		SpellVfx.Element.HEAL, SpellVfx.Element.BUFF, SpellVfx.Element.DEBUFF:
			_spell_vfx.play_skill_on_target(target_node, skill_name, element)
		SpellVfx.Element.PHYSICAL:
			# Power Shot : l'impact de la flèche est joué à l'arrivée du projectile.
			if not SpellVfx.is_projectile_skill(skill_name):
				_spell_vfx.play_skill_on_target(target_node, skill_name, element)
		_:
			if skill_name in NON_PROJECTILE_DAMAGE_SKILLS:
				_spell_vfx.play_skill_on_target(target_node, skill_name, element)
				_flash_entity(target_node)
				Sfx.play_spell_at_point(element, "impact", _spell_vfx, target_node.global_position)


## Sort raté (CastResult/SkillCastAnnounced hit = false) : son de raté sur la cible, sans
## l'effet visuel du sort. Un sort à projectile a déjà joué son raté à l'arrivée du projectile
## (voir _on_skill_projectile_launched), il n'y a rien à rejouer ici.
func _play_skill_miss(target_id: String, skill_name: String) -> void:
	var element := SpellVfx.element_for_skill(skill_name)
	var projectile := SpellVfx.is_projectile_skill(skill_name) or skill_name not in NON_PROJECTILE_DAMAGE_SKILLS and element not in [
		SpellVfx.Element.HEAL, SpellVfx.Element.BUFF, SpellVfx.Element.DEBUFF, SpellVfx.Element.PHYSICAL,
	]
	var target_node := _entity_node_by_id(target_id)
	if projectile or target_node == null:
		return
	Sfx.play_at_point("combat_miss", _spell_vfx, target_node.global_position)


## Petit son distinctif quand la cible meurt (notre coup fatal : CastResult.targetDefeated,
## AttackResult à 0 PV ; ou mort de la cible sélectionnée : MonsterDefeated, GamePlayerDefeated).
## Plusieurs de ces messages annoncent la même mort : une seule fois par cible.
func _play_kill_sound(target_id: String) -> void:
	var now := Time.get_ticks_msec()
	if target_id.is_empty() or (target_id == _kill_sound_target_id and now - _kill_sound_msec < KILL_SOUND_MEMO_MSEC):
		return
	_kill_sound_target_id = target_id
	_kill_sound_msec = now
	get_tree().create_timer(KILL_SOUND_DELAY).timeout.connect(func() -> void: Sfx.play_sfx("combat_kill"))


func _on_skill_projectile_launched(payload: Dictionary) -> void:
	var caster_node := _entity_node_by_id(str(payload.get("casterId", "")))
	var target_node := _entity_node_by_id(str(payload.get("targetId", "")))
	if caster_node == null or target_node == null or caster_node == target_node:
		return
	var element := SpellVfx.element_for_skill(str(payload.get("skillName", "")))
	var duration_sec := maxf(float(payload.get("travelDurationMs", 0)) / 1000.0, 0.05)
	# Issue du jet déjà tirée par le serveur au lancer : raté = son dédié à l'arrivée.
	var hit := bool(payload.get("hit", true))
	# Sons posés au point d'impact plutôt qu'attachés à la cible : un coup fatal la fait
	# disparaître (MonsterDefeated/EntityDisappeared) et couperait net un son enfant de son nœud.
	var projectile_style := SpellVfx.projectile_style_for_skill(str(payload.get("skillName", "")))
	_spell_vfx.play_projectile(caster_node, target_node, element, duration_sec, func(point: Vector3) -> void:
		if not hit:
			Sfx.play_at_point("combat_miss", _spell_vfx, point)
			return
		if is_instance_valid(target_node):
			_flash_entity(target_node)
		Sfx.play_spell_at_point(element, "impact", _spell_vfx, point)
	, projectile_style)


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
	if not bool(payload.get("hit", false)):
		_play_skill_miss(target_id, skill_name)
		return
	var amount := int(payload.get("amount", 0))
	# Soin (Heal sur un allié) ou purification : pas de chiffre de dégâts.
	if amount > 0 and SpellVfx.element_for_skill(skill_name) not in [SpellVfx.Element.HEAL, SpellVfx.Element.BUFF]:
		_show_damage_number(_entity_node_by_id(target_id), amount, false)
	_play_skill_animation(target_id, skill_name)
	if bool(payload.get("targetDefeated", false)):
		_play_kill_sound(target_id)


## Période d'un poison (EffectDamage, Curse: Poison) sur une entité à portée : PV à jour,
## chiffre de dégâts et bulles de poison ; si c'est notre poison qui achève la cible, son de
## coup fatal comme pour un coup direct.
func _on_effect_damage(payload: Dictionary) -> void:
	var target_id := str(payload.get("targetId", ""))
	var amount := int(payload.get("amount", 0))
	_apply_target_current_health(target_id, int(payload.get("targetHealthAfter", 0)), int(payload.get("targetMaxHealth", 0)))
	var node := _entity_node_by_id(target_id)
	if node != null:
		if amount > 0:
			_show_damage_number(node, amount, false)
		_spell_vfx.play_poison_tick(node)
	var my_id := str(GameState.player_stats.get("id", ""))
	if bool(payload.get("targetDefeated", false)) and str(payload.get("sourceId", "")) == my_id:
		_play_kill_sound(target_id)
	if target_id == my_id:
		_log("[i]%s vous fait perdre %d PV.[/i]" % [_bbcode_escape(str(payload.get("skillName", "Le poison"))), amount])


## Vampiric Touch (SkillDrained) : filets de vie de la cible vers le lanceur, dont les PV
## remontent d'autant.
func _on_skill_drained(payload: Dictionary) -> void:
	var caster_id := str(payload.get("casterId", ""))
	_apply_target_current_health(caster_id, int(payload.get("casterHealth", 0)), int(payload.get("casterMaxHealth", 0)))
	var caster_node := _entity_node_by_id(caster_id)
	if caster_node != null:
		_spell_vfx.play_drain(_entity_node_by_id(str(payload.get("targetId", ""))), caster_node)
	if caster_id == str(GameState.player_stats.get("id", "")):
		_log("[color=%s]Vous absorbez %s PV avec %s.[/color]" % [
			LOG_COLOR_GAIN, str(payload.get("amount", 0)), _bbcode_escape(str(payload.get("skillName", "?"))),
		])


## Type backend (KnownSkills.skillType) d'une de nos compétences, "" si inconnue.
func _known_skill_type(skill_name: String) -> String:
	for skill in GameState.known_skills.get("skills", []):
		if str(skill.get("name", "")) == skill_name:
			return str(skill.get("skillType", ""))
	return ""


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
	if not bool(payload.get("hit", false)):
		_play_skill_miss(target_id, skill_name)
		return
	var amount := int(payload.get("amount", 0))
	# Soin (Heal sur un allié) ou purification : pas de chiffre de dégâts.
	if amount > 0 and SpellVfx.element_for_skill(skill_name) not in [SpellVfx.Element.HEAL, SpellVfx.Element.BUFF]:
		_show_damage_number(_entity_node_by_id(target_id), amount, false)
	_play_skill_animation(target_id, skill_name)


# ---------------------------------------------------------------------------
# Spawn / mort des monstres
# ---------------------------------------------------------------------------

## Le monstre est déjà retiré côté serveur à ce stade, donc rien ne le fera réapparaître
## dans un futur MapEnter : on grise son corps immédiatement puis on le fait disparaître
## après un court délai, plutôt que de le retirer instantanément.
func _despawn_monster(monster_id: String, monster_name: String) -> void:
	# Résolution par UUID (MonsterDefeated.monsterId, backend 2026-09-26) : par nom, tuer un
	# Fox faisait mourir un autre Fox homonyme (le premier trouvé), tandis que le vrai disparaissait
	# sans animation à l'EntityDisappeared qui suit. Repli par nom si le backend n'envoie pas
	# encore l'UUID.
	var key: String = _key_by_entity_id.get(monster_id, "")
	if key.is_empty():
		for candidate_key in _entities_by_key.keys():
			var candidate_node: Node3D = _entities_by_key[candidate_key]
			if candidate_key.begins_with("monster:") and str(candidate_node.get_meta("entity_name", "")) == monster_name:
				key = candidate_key
				break
	var node: Node3D = _entities_by_key.get(key)
	if node == null:
		return

	if monster_id.is_empty():
		for id in _key_by_entity_id.keys():
			if _key_by_entity_id[id] == key:
				monster_id = id
				break

	_entities_by_key.erase(key)
	_moving.erase(key)
	_smooth_offset_by_key.erase(key)
	_entity_speed_by_key.erase(key)
	_entity_vitals_by_key.erase(key)
	_finish_cast_vfx(key, false)
	_casting_by_key.erase(key)
	_free_bars(key)
	if not monster_id.is_empty():
		_key_by_entity_id.erase(monster_id)
		if monster_id == _selected_target_id:
			_play_kill_sound(monster_id)
			_clear_selection()

	# Modèle animé : il s'effondre (clip de mort, figé sur sa dernière image) et reste au sol
	# un instant avant de s'effacer ; capsule : grisée aussitôt.
	var fade_delay := MONSTER_DEATH_GREY_DELAY
	var monster := node.get_node_or_null("Body") as Monster
	var body := node.get_node_or_null("Body") as MeshInstance3D
	if monster != null:
		monster.play_death()
		fade_delay = monster.death_duration() + MONSTER_CORPSE_LINGER
	elif body != null and body.mesh != null and body.mesh.material != null:
		(body.mesh.material as StandardMaterial3D).albedo_color = MONSTER_DEATH_GREY_COLOR

	var tween := create_tween()
	tween.tween_interval(fade_delay)
	tween.tween_method(func(t: float): _set_node_transparency(node, t), 0.0, 1.0, MONSTER_DEATH_FADE_DURATION)
	tween.tween_callback(node.queue_free)


## Récursif : les meshes d'un modèle importé (Monster) sont enfouis sous son squelette.
func _set_node_transparency(node: Node3D, t: float) -> void:
	for child in node.find_children("*", "GeometryInstance3D", true, false):
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


## Destination d'un clic au sol : même anneau que le cercle de cible (voir
## SELECTION_RING_SHADER_CODE/_make_ground_ring), plus petit et doré, qui se resserre en
## apparaissant à chaque clic (voir _show_move_marker) au lieu du simple tore jaune.
const MOVE_MARKER_SIZE := 1.25
const MOVE_MARKER_COLOR := Color(1.0, 0.82, 0.36)
const MOVE_MARKER_POP_SCALE := 1.7
const MOVE_MARKER_POP_TIME := 0.22


func _make_move_marker() -> void:
	_move_marker = _make_ground_ring(MOVE_MARKER_SIZE, MOVE_MARKER_COLOR)
	_world.add_child(_move_marker)


## Appelée au clic puis à l'écho MovementStarted du serveur : l'animation d'apparition ne
## rejoue que pour une nouvelle destination.
func _show_move_marker(pos: Vector2) -> void:
	var marker_pos := Vector3(pos.x, 0.05, pos.y)
	var fresh := not _move_marker.visible or _move_marker.position.distance_to(marker_pos) > 0.3
	_move_marker.position = marker_pos
	_move_marker.visible = true
	if not fresh:
		return
	if _move_marker_tween != null and _move_marker_tween.is_valid():
		_move_marker_tween.kill()
	var mat: ShaderMaterial = _move_marker.get_meta("material")
	_move_marker.scale = Vector3.ONE * MOVE_MARKER_POP_SCALE
	mat.set_shader_parameter("intensity", 0.0)
	_move_marker_tween = _move_marker.create_tween().set_parallel(true) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_marker_tween.tween_property(_move_marker, "scale", Vector3.ONE, MOVE_MARKER_POP_TIME)
	_move_marker_tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.0, 1.0, MOVE_MARKER_POP_TIME
	)


func _hide_move_marker() -> void:
	if _move_marker_tween != null and _move_marker_tween.is_valid():
		_move_marker_tween.kill()
	_move_marker.visible = false


## Cercle de cible au sol (remplace le gros tore rouge, 2026-09-26) : un seul plan plaqué au
## sol dessiné par shader — fin anneau net + halo doux, léger voile intérieur, quatre arcs
## qui tournent lentement autour et une ombre sombre sous l'anneau pour rester lisible même
## en blanc sur un sol clair. Tout est en distances normalisées (0 = centre, 1 = bord du plan)
## et lissé via fwidth, donc net à tous les niveaux de zoom. Couleur par type de cible, voir
## _selection_color_for.
const SELECTION_RING_SIZE := 1.8
const SELECTION_RING_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, specular_disabled, shadows_disabled;

uniform vec4 ring_color : source_color = vec4(0.92, 0.2, 0.16, 1.0);
uniform float intensity = 1.0;

float band(float d, float center, float half_width) {
	float aa = max(fwidth(d), 0.0005);
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d - center));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float pulse = 0.82 + 0.18 * sin(TIME * 3.2);

	float ring = band(r, 0.66, 0.026);
	float glow = exp(-pow((r - 0.66) / 0.07, 2.0)) * 0.5 * pulse;
	float veil = smoothstep(0.15, 0.64, r) * (1.0 - smoothstep(0.64, 0.68, r)) * 0.16;

	// Quatre arcs extérieurs (~55° chacun) tournant lentement, bouts arrondis par le lissage.
	float seg = fract((angle + TIME * 0.7) / (PI * 0.5));
	float arc_mask = smoothstep(0.0, 0.04, seg) * (1.0 - smoothstep(0.26, 0.30, seg));
	float arcs = band(r, 0.82, 0.03) * arc_mask;

	float light = clamp(ring + arcs * 0.9 + glow + veil, 0.0, 1.0);
	float shadow = (band(r, 0.66, 0.05) + band(r, 0.82, 0.055) * arc_mask) * 0.35;
	float alpha = clamp(max(light, shadow), 0.0, 1.0);
	if (alpha < 0.003) {
		discard;
	}
	vec3 lit = mix(ring_color.rgb, vec3(1.0), ring * 0.15);
	ALBEDO = lit * (light / alpha);
	ALPHA = alpha * ring_color.a * intensity;
}
"""


func _make_selection_ring() -> void:
	_selection_ring = _make_ground_ring(SELECTION_RING_SIZE, SELECTION_COLOR)
	_world.add_child(_selection_ring)


## Plan plaqué au sol dessiné par SELECTION_RING_SHADER_CODE (matériau en meta "material",
## caché à la création).
func _make_ground_ring(size: float, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * size
	var shader := Shader.new()
	shader.code = SELECTION_RING_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ring_color", color)
	plane.material = mat
	ring.mesh = plane
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	ring.set_meta("material", mat)
	return ring


## Blanc sur soi-même, vert sur un membre du groupe (voir GameState.party), bleu clair sur un
## PNJ (même teinte que son nom dans %TargetStatusBar), rouge sinon (monstre, autre joueur).
func _selection_color_for(target_id: String, key: String) -> Color:
	if key == PLAYER_KEY or target_id == str(GameState.player_stats.get("id", "")):
		return SELECTION_SELF_COLOR
	if (GameState.party.get("members", {}) as Dictionary).has(target_id):
		return SELECTION_PARTY_COLOR
	if key.begins_with("npc:"):
		return SELECTION_NPC_COLOR
	return SELECTION_COLOR


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
		if _world_map.visible:
			# Le corps regarde vers son -Z local (voir _face_heading, look_at).
			var forward := -_player_node.global_transform.basis.z
			_world_map.set_player(Vector2(_player_node.position.x, _player_node.position.z),
					Vector2(forward.x, forward.z))
	_minimap.set_game_time(_game_minutes_of_day)
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
	_party_window.set_selected(_selected_target_id)
	_target_status_bar.set_invite_visible(_can_invite_selected())


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
			_log("Vous manquez %s." % target_name)
			return
		_log("Vous infligez %s dégâts à %s%s." % [str(payload.get("damage", 0)), target_name, critical_suffix])
	elif target_id == my_id:
		var attacker_name := _bbcode_escape(str(payload.get("attackerName", "?")))
		if not hit:
			_log("%s vous manque." % attacker_name)
			return
		_log("%s vous inflige %s dégâts%s." % [attacker_name, str(payload.get("damage", 0)), critical_suffix])


## Ligne de journal pour notre propre CastResult (envoyé uniquement au lanceur) — porté de
## ChatOverlay._on_cast_result. Un sort de soin (selfHeal) est toujours appliqué au lanceur
## côté serveur, donc jamais de targetName pertinent dans ce cas.
func _log_cast_result(payload: Dictionary) -> void:
	var skill_name := _bbcode_escape(str(payload.get("skillName", "?")))
	if bool(payload.get("selfHeal", false)):
		_log("Vous récupérez %s PV avec %s." % [str(payload.get("amount", 0)), skill_name])
		return
	var target_name := _bbcode_escape(str(payload.get("targetName", "?")))
	match _known_skill_type(str(payload.get("skillName", ""))):
		"HEALING":
			_log("Vous rendez %s PV à %s avec %s." % [str(payload.get("amount", 0)), target_name, skill_name])
			return
		"CURE":
			if bool(payload.get("hit", false)):
				_log("Vous purifiez %s avec %s." % [target_name, skill_name])
			else:
				_log("[i]%s n'est affligé d'aucun poison.[/i]" % target_name)
			return
	if not bool(payload.get("hit", false)):
		_log("Vous manquez %s avec %s." % [target_name, skill_name])
		return
	_log("Vous infligez %s dégâts à %s avec %s." % [str(payload.get("amount", 0)), target_name, skill_name])


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
		_log("%s vous manque avec %s." % [caster_name, skill_name])
		return
	_log("%s vous inflige %s dégâts avec %s." % [caster_name, str(payload.get("amount", 0)), skill_name])


## Un personnage meurt (GamePlayerDefeated, diffusé à toute la zone, pas d'UUID donc
## comparaison par nom) — porté de ChatOverlay._on_player_defeated. Toujours purement
## informatif pour un autre personnage ; quand characterName est le nôtre, l'appelant
## (_on_message_received) ouvre en plus %DeathPopup (voir CLAUDE.md, fenêtre de respawn
## ajoutée le 2026-09-03).
func _log_player_defeated(payload: Dictionary) -> void:
	var killer_name := _bbcode_escape(str(payload.get("killerName", "?")))
	if str(payload.get("characterName", "")) == str(GameState.player_stats.get("name", "")):
		_log("Vous êtes mort, tué par %s." % killer_name)
	else:
		_log("%s est mort, tué par %s." % [_bbcode_escape(str(payload.get("characterName", "?"))), killer_name])


## Journal système (voir _system_log_label) : tout sauf le chat entre joueurs (_log_chat).
func _log(text: String) -> void:
	_system_log_label.append_text(text + "\n")
	_flash_chat_window(_system_log_background, SYSTEM_WINDOW_MESSAGE_HOLD_SEC)


## Journal du chat entre joueurs (voir _chat_log_label), distinct du journal système ci-dessus
## depuis la demande explicite du 2026-09-06 de séparer les deux flux en deux fenêtres.
## `channel` ("say"/"party"/"whisper") détermine si `text` va aussi dans %ChatPartyLogLabel
## (onglet "#Groupe", voir Game.tscn) — seuls "party"/"whisper" y apparaissent, un "say" normal
## reste réservé à l'onglet "Tous" (%ChatLogLabel, qui reçoit lui TOUJOURS tous les canaux).
func _log_chat(text: String, channel: String = "say") -> void:
	_chat_log_label.append_text(text + "\n")
	if channel != "say":
		_chat_party_log_label.append_text(text + "\n")
	_flash_chat_window(_chat_log_background)


## Fait clignoter légèrement une fenêtre de discussion à l'arrivée d'un nouveau message (voir
## _log/_log_chat) : passe à CHAT_WINDOW_MESSAGE_ALPHA (sans redescendre si elle est encore plus
## opaque, ex. pendant CHAT_WINDOW_UNFOCUS_HOLD_SEC) puis retombe en fondu vers
## CHAT_WINDOW_IDLE_ALPHA après `hold_sec` — sans effet tant que %ChatInput a
## le focus (la fenêtre reste alors pleinement opaque, voir _set_chat_windows_interactive).
func _flash_chat_window(background: PanelContainer, hold_sec: float = CHAT_WINDOW_MESSAGE_HOLD_SEC) -> void:
	if _chat_input.has_focus():
		return
	var alpha := maxf(background.modulate.a, CHAT_WINDOW_MESSAGE_ALPHA)
	background.modulate.a = alpha
	var handle := _chat_window_handles.get(background) as Control
	if handle != null:
		handle.modulate.a = alpha
	_fade_chat_window_later(background, hold_sec)


## Lance (en remplaçant celui en cours) le fondu de `control` — une fenêtre de discussion et sa
## poignée (_chat_window_handles), ou %ChatInput seul — vers CHAT_WINDOW_IDLE_ALPHA après
## `hold_sec`, depuis son alpha actuel.
func _fade_chat_window_later(control: Control, hold_sec: float) -> void:
	_kill_chat_window_fade(control)
	var handle := _chat_window_handles.get(control) as Control
	var tween := create_tween()
	tween.tween_interval(hold_sec)
	tween.set_parallel(true)
	tween.tween_property(control, "modulate:a", CHAT_WINDOW_IDLE_ALPHA, CHAT_WINDOW_FADE_SEC)
	if handle != null:
		tween.tween_property(handle, "modulate:a", CHAT_WINDOW_IDLE_ALPHA, CHAT_WINDOW_FADE_SEC)
	_chat_window_fade_tweens[control] = tween


func _kill_chat_window_fade(control: Control) -> void:
	var tween := _chat_window_fade_tweens.get(control) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	_chat_window_fade_tweens.erase(control)


## Bascule les 2 fenêtres de discussion (+ %ChatInput) entre interactives/opaques (focus sur
## %ChatInput) et transparentes/traversables au clic (focus perdu) — demande explicite du
## 2026-09-06 pour ne pas gêner le clic sur la scène 3D tant qu'on ne discute pas, étendue le
## même jour aux poignées de redimensionnement (leur alpha ne suit pas celui du fond puisqu'elles
## ne sont pas ses enfants, voir _chat_window_handles) et à %ChatInput lui-même. Le clic continue
## de fonctionner sur les poignées dans les deux cas : un enfant garde son propre mouse_filter
## quel que soit celui de son parent (voir ChatWindowResizeHandle.gd) — seul leur alpha change ici.
## `fade_hold_sec` > 0 (perte du focus, voir _on_chat_input_focus_exited) : le clic traverse
## aussitôt, mais l'alpha ne retombe qu'en fondu après ce délai au lieu de disparaître d'un coup.
func _set_chat_windows_interactive(focused: bool, fade_hold_sec: float = 0.0) -> void:
	var filter := Control.MOUSE_FILTER_STOP if focused else Control.MOUSE_FILTER_IGNORE
	for control in [
		_chat_log_background, _chat_log_label, _chat_party_log_label,
		_system_log_background, _system_log_label,
	]:
		control.mouse_filter = filter
	if not focused and fade_hold_sec > 0.0:
		for control in [_chat_log_background, _system_log_background, _chat_input]:
			_fade_chat_window_later(control, fade_hold_sec)
		return
	var target_alpha := CHAT_WINDOW_FOCUSED_ALPHA if focused else CHAT_WINDOW_IDLE_ALPHA
	for control in [_chat_log_background, _system_log_background, _chat_input]:
		_kill_chat_window_fade(control)
		control.modulate.a = target_alpha
		var handle := _chat_window_handles.get(control) as Control
		if handle != null:
			handle.modulate.a = target_alpha


func _on_chat_input_focus_entered() -> void:
	_set_chat_windows_interactive(true)


func _on_chat_input_focus_exited() -> void:
	_set_chat_windows_interactive(false, CHAT_WINDOW_UNFOCUS_HOLD_SEC)


## Fait suivre la largeur de %ChatBar à celle de %ChatLogPanel (redimensionnée via
## %ChatLogResizeHandle, voir son signal "panel_resized") — les deux commencent alignées dans
## Game.tscn mais %ChatLogPanel peut être élargie/rétrécie indépendamment, demande explicite
## du 2026-09-06 pour que la barre de saisie ne se retrouve pas plus étroite/large que la
## fenêtre de chat juste au-dessus d'elle. Ne touche jamais %SystemLogPanel (pas de barre en
## dessous d'elle à faire suivre).
func _on_chat_log_panel_resized() -> void:
	var chat_log_panel := _chat_log_resize_handle.get_parent() as Control
	_chat_bar.offset_right = chat_log_panel.offset_right


## Bascule l'onglet "Tous"/"#Groupe" du chat (voir %ChatTabBar, Game.tscn) : les deux onglets
## sont peuplés en continu par _log_chat (jamais reconstruits à la volée) — changer d'onglet ne
## fait donc que montrer la rangée (RichTextLabel + scrollbar gauche) correspondante.
func _on_chat_tab_changed(tab: int) -> void:
	_chat_all_row.visible = tab == 0
	_chat_party_row.visible = tab == 1


## Pose une VScrollBar à gauche d'un RichTextLabel (voir %ChatScrollBar/%ChatPartyScrollBar,
## Game.tscn) — demande explicite du 2026-09-06 ("une scrollbar sur la gauche"). RichTextLabel
## ne permet pas nativement de déplacer sa propre scrollbar interne (get_v_scroll_bar(), à
## droite, repositionnée par le moteur lui-même à chaque reflow) : on la masque plutôt que
## d'essayer de la déplacer, et on pilote son `value` depuis cette scrollbar de gauche — qui
## elle-même se resynchronise (min/max/page/value) sur l'interne à chaque changement de
## contenu (Range.changed/value_changed), donc reflète toujours le vrai scroll du texte,
## molette comprise (gérée par le RichTextLabel lui-même, indépendamment de sa scrollbar).
func _wire_left_scrollbar(bar: VScrollBar, label: RichTextLabel) -> void:
	var internal := label.get_v_scroll_bar()
	internal.modulate.a = 0.0
	internal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sync := func() -> void:
		bar.min_value = internal.min_value
		bar.max_value = internal.max_value
		bar.page = internal.page
		bar.value = internal.value
	internal.changed.connect(func() -> void: sync.call())
	internal.value_changed.connect(func(_v: float) -> void: sync.call())
	bar.value_changed.connect(func(v: float) -> void: internal.value = v)
	sync.call()


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
	_moon.light_energy = (1.0 - t) * MOON_MAX_ENERGY
	_update_celestial_shadows()
	_update_night_lights_energy(t)


## Ombres du soleil et de la lune : coupées quand l'astre est trop faible (voir
## MIN_SHADOW_LIGHT_ENERGY) ou quand le joueur a désactivé les ombres (menu système).
func _update_celestial_shadows() -> void:
	var shadows := Settings.shadows_enabled()
	_sun.shadow_enabled = shadows and _sun.light_energy > MIN_SHADOW_LIGHT_ENERGY
	_moon.shadow_enabled = shadows and _moon.light_energy > MIN_SHADOW_LIGHT_ENERGY


## Effets de l'environnement réglables dans le menu système (Settings.GRAPHICS_DEFAULTS) :
## occlusion ambiante (SSAO) et lueur (glow) des sources très lumineuses (sorts, portails).
func _apply_environment_settings() -> void:
	var env := _world_environment.environment
	env.ssao_enabled = bool(Settings.get_graphics("ssao"))
	env.glow_enabled = bool(Settings.get_graphics("glow"))


func _on_graphics_changed(key: String) -> void:
	match key:
		"shadow_quality":
			_update_celestial_shadows()
		"ssao", "glow":
			_apply_environment_settings()


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
