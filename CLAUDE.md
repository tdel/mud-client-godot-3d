# CLAUDE.md

Prototype **isométrique 3D** du client mud-godot (voir [`../mud-godot`](../mud-godot)
pour le client 2D "vue du ciel" existant et son CLAUDE.md, qui documente le protocole
réseau complet — inchangé ici). Créé le 2026-09-02 pour évaluer la direction 3D avant d'y
investir davantage : caméra isométrique fixe, sol/obstacles générés depuis les mêmes
`.tmx` que le client 2D, déplacement au clic, entités (joueurs/PNJ/monstres) visibles et
animées en position/orientation, chat de zone.

## Ce qui N'EST PAS dans ce prototype

Groupe, sous-classe — pas demandés pour l'instant. Sélection de cible, combat (attaque +
cooldown), sorts (incantation/projectile/impact/buff-debuff), hotbar, portails (portés du
client 2D le 2026-09-02), inventaire/équipement visuel avec fenêtres déplaçables façon L2J
(depuis le 2026-09-03) et mort/respawn (fenêtre de respawn, également depuis le
2026-09-03 — voir "Ce qui est nouveau" ci-dessous), en revanche, sont bien présents : ce
n'est donc plus la liste de tout ce que le client 2D a et que ce prototype n'a pas,
seulement ce qui reste hors scope. Les entités
sont toujours de simples capsules colorées (bleu = soi, vert = autres joueurs, rouge =
monstres, or = PNJ) avec un nom flottant, pas de rig/squelette/attach points d'équipement
— ce sera la prochaine étape une fois la direction artistique validée (voir la
conversation qui a mené à ce projet : la 3D a été choisie plutôt que la 2D isométrique
précisément parce qu'elle rend l'équipement visible/les animations/les effets de sorts
réalistes à tenir seul, via des rigs + attach points plutôt qu'une combinatoire de
sprites).

## Ce qui est réutilisé tel quel du client 2D

`autoload/Net.gd`, `autoload/GameState.gd`, `autoload/UITheme.gd`,
`scenes/login/Login.tscn`/`.gd`, `scenes/charselect/CharSelect.tscn`/`.gd`,
`scenes/charselect/CharacterCreate.tscn`/`.gd`, `scenes/common/HeroSilhouettes.gd`,
`Backgrounds/night_castle_moon.png` : copiés sans modification (pure UI Control, aucune
dépendance à la vue 2D). Toute la choréographie login/register/création de personnage
fonctionne donc à l'identique du client 2D. `data/maps/*.tmx` copiés aussi (mêmes
fichiers, voir "Resynchroniser les fichiers de carte" dans le CLAUDE.md du client 2D pour
la procédure si le backend change une carte).

## Ce qui est nouveau

- **`autoload/ZoneAssets3D.gd`** — équivalent 3D de `ZoneAssets.gd` (2D) : parse les mêmes
  `.tmx` pour connaître le terrain par case, mais produit une texture de sol (peinte,
  un seul quad) + une hauteur d'obstacle par case plutôt qu'une `TileMapLayer`. Comme côté
  2D, le `walkable`/non-walkable envoyé par le serveur (`MapView.grid.walkableRows`) reste
  l'unique source de vérité pour les règles de jeu — les `.tmx` locaux ne choisissent que
  la couleur/hauteur affichée.
- **`scenes/game/Game.tscn` + `Game3D.gd`** (même chemin de scène que le client 2D, pour
  que `CharSelect.gd`/`CharacterCreate.gd` copiés tels quels y naviguent sans
  modification) : caméra isométrique fixe (`Camera3D` orthogonale, offset `(1,1,1)`
  normalisé depuis le pivot `CameraRig` qui suit le joueur), sol + obstacles reconstruits
  à chaque `MapView`, entités (capsule + `Label3D`) reconstruites/mises à jour à chaque
  `MapEnter`/`GamePlayerJoinedMap`/`EntityAppeared`/`EntityDisappeared`/mouvement (voir
  session du 2026-09-03 sur le spawn/respawn temps réel des monstres, plus bas, pour
  `EntityAppeared`/`EntityDisappeared` qui remplacent l'ancien `MonsterSpawned`),
  interpolation de mouvement
  générique (joueur compris, sous la clé `"player"`) à vitesse serveur (`speed`,
  tuiles/s), orientation via `look_at` sur la direction de la cible plutôt qu'un calcul de
  signe d'angle à la main (plus robuste). Déplacement au clic gauche (maintenu = renvoi
  d'un nouveau `goto` au plus 4x/s tant que la position visée change, même ergonomie que
  le client 2D) via une intersection analytique rayon-caméra/plan `y=0`, pas de physique
  3D. Chat minimal (`%ChatInput`/`%LogLabel`) et étiquette d'info joueur (`%InfoLabel`) en
  HUD — pas de reprise des scènes HUD du client 2D (`ChatOverlay.gd`, etc.), qui sont
  câblées sur l'API 2D de `Game.gd` (1934 lignes, hors de portée d'un prototype).
- **Sélection de cible, attaque, sorts, hotbar** (2026-09-02, portés du client 2D à la
  demande de l'utilisateur) : clic gauche sur une entité → `select` réseau (même protocole
  que le 2D, UUID par entité) ; Échap déselectionne, Tab cible le monstre non sélectionné
  le plus proche. Anneau émissif partagé (`_selection_ring`) qui suit la cible + fenêtre
  `scenes/game/hud/TargetStatusBar.tscn`/`.gd` (nom/niveau/vie, sans le bouton "Inviter au
  groupe" du 2D — le groupe reste hors scope). Hotbar 12 slots F1-F12
  (`scenes/game/hud/Hotbar.tscn`/`.gd` + `HotbarSlot.tscn`/`.gd`) et carnet de sorts
  (`SkillBook.tscn`/`.gd`, touche `K`, glisser-déposer via `DraggableRow.gd`) : ces 4
  scripts sont des `Control` purs pilotés par `Net`/`GameState`, portés ~verbatim du
  client 2D (seule différence : icônes via `ZoneAssets3D.make_slot_icon_texture`, ajoutée
  à cette même occasion). F1 est préremplie avec l'attaque de base tant qu'aucune config
  `user://hotbar.cfg` n'existe pour le personnage — le 2D a retiré ce défaut au profit
  d'une autre affordance non documentée/hors scope ici (voir `Hotbar.gd`). Feedback combat
  en 3D : flash rouge (`_flash_entity`) + nombre de dégâts flottant (`Label3D`) sur la
  cible, barres de vie/incantation génériques flottant au-dessus de chaque entité
  (`_make_floating_bar` : deux quads billboard orientés manuellement vers la caméra via
  `_billboard_node`, pas de `BILLBOARD_ENABLED` par quad, pour que fond et remplissage
  tournent comme un seul bloc rigide), projectile de sort (petite sphère colorée selon la
  catégorie du sort, `_play_skill_projectile`) et pulsation colorée pour soin/buff/debuff
  (`_play_skill_pulse`) — couleurs unies plutôt que les textures du 2D, aucun art
  directionnel disponible dans ce prototype (voir plus haut). La portée n'est jamais
  vérifiée côté client (uniquement indicatif via `show_skill_range`/`hide_skill_range`,
  survol d'un slot de sort), comme côté 2D.
- **Portails** : lus depuis `MapView.portals` (`{x, y, targetMapName}`, déjà envoyé par le
  serveur — juste jamais exploité jusqu'ici, aucun parsing `.tmx` nécessaire). Marqueur 3D
  (disque émissif violet + nom de la carte cible en `Label3D`) reconstruit à chaque
  `_rebuild_map`. Sélection au clic gauche (mutuellement exclusive avec la sélection
  d'entité), "Se téléporter" via clic droit sur le portail déjà sélectionné → `PopupMenu`
  (`%PortalMenu` dans `Game.tscn`) → `Net.send_command("portal")` sans argument, le
  serveur se basant uniquement sur la position courante du joueur.
- **Mort des monstres peaufinée** : `_despawn_monster` grise le corps puis le fait fondre
  (`GeometryInstance3D.transparency`, tweené) avant de le retirer, au lieu d'une
  suppression instantanée — même ressenti que `_despawn_monster` côté client 2D.

## Vitesse du joueur

Vitesse de déplacement doublée côté backend à la demande de l'utilisateur (jugée trop
lente) : `mud-server-java/src/main/java/app/domain/actor/Race.java`, `Race.HUMAN.speed()`
110 → 220 (2026-09-02). C'est l'unique constante de vitesse joueur (figée une fois dans
`ModifiedStat.SPEED` par `CharacterInstance`, aucune classe/niveau/objet n'y touche
ensuite) ; `MovementEngine.SPEED_DIVISOR` (conversion en tuiles/s, partagée avec les
monstres) n'a pas été touché. Les monstres ont leur propre vitesse par
`data/monsters.xml`/`MonsterTemplate`, non affectée par ce changement.

## Vérifié dans cet environnement

`mud-server-java` a eu quelques commits depuis la dernière session sur le client 2D
(renommage `tier`→`level`/`effect`→`skillType` sur `KnownSkills`, `ModifiedStat`→
`List<StatModifier>` sur `SkillModifierAnnounced`, attributs `STRENGTH`→`STR` etc.) : tous
concernent le détail des sorts/attributs, hors du scope de ce prototype (aucun champ lu
par `Game3D.gd` n'est touché) — vérifié par `git diff` sur `mud-server-java` entre le
dernier commit documenté côté client 2D et `HEAD`.

Projet chargé et testé dans l'éditeur Godot en headless (import des assets, scan des
scripts) puis en debug (`mcp__godot__run_project`) : aucune erreur sur `Login.tscn` (donc
`CharSelect`/`CharacterCreate`, pure UI identique) ; `Game.tscn` chargé seul (sans réseau)
ne produit que l'avertissement attendu "pas connecté". La logique de `_rebuild_map`/
`_rebuild_obstacles`/`_refresh_entities` a été exercée avec un `MapView`/`MapEnter`
synthétique (carte "Place du village" 105×75, vrai fichier `.tmx`, joueur + un
personnage + un PNJ + un monstre) : aucune erreur, capture d'écran réelle de la fenêtre de
jeu confirmant caméra isométrique correcte, sol coloré par terrain, obstacles avec
ombres portées, capsules + noms flottants bien positionnés, HUD lisible par-dessus (thème
`UITheme.gd` appliqué). **Aucun test de bout en bout contre le vrai backend** (login,
déplacement au clic, voir un autre joueur/monstre bouger en direct) n'a été fait ici — le
protocole réseau (`Net.gd`/`GameState.gd`, champs lus par `Game3D.gd`) est copié à
l'identique d'un client 2D déjà validé en conditions réelles à de nombreuses reprises
(voir l'historique du CLAUDE.md du client 2D), donc à faible risque, mais reste à
confirmer par un humain : lancer le backend (`mvn spring-boot:run`), ouvrir ce projet dans
Godot, se connecter, créer/sélectionner un personnage, et vérifier le déplacement au clic
+ la visibilité d'un second personnage/monstre en mouvement.

**Session du 2026-09-02 (sélection/attaque/sorts/hotbar/portails + vitesse x2)** : aucun
exécutable `godot` en CLI ni outil MCP Godot n'était disponible dans cet environnement
(contrairement à la session précédente citée ci-dessus) — vérification faite par relecture
statique soignée de chaque script ajouté/modifié (cohérence des noms de nœuds/signaux,
`%Unique` correctement déclarés dans les `.tscn`, indentation par tabulations uniforme)
plutôt que par un lancement réel. Le changement backend (`Race.java`) n'a pas non plus été
testé en conditions réelles (serveur non relancé ici). **Reste entièrement à confirmer par
un humain** : lancer le backend, ouvrir le projet dans Godot, et vérifier au minimum —
vitesse de déplacement visiblement doublée ; clic sur un monstre = sélection (anneau +
`TargetStatusBar`) ; l'attaque (F1 par défaut) inflige des dégâts visibles ; `K` ouvre le
carnet de sorts, glisser un sort sur un slot puis l'utiliser lance un cast complet (barre
d'incantation, projectile/pulsation, dégâts ou soin) ; un portail est visible et
téléporte bien via clic + clic droit + "Se téléporter".

Idem pour la sélection au clic sur une capsule (2026-09-02, demandé explicitement — "je
clique à travers le sprite", sans modification backend). `_pick_at_point` testait jusqu'ici
une entité en projetant le clic sur le plan `y=0` (`_ground_point_at_mouse`, rayon caméra→
souris ∩ sol) puis en comparant ce point du sol à `node.position.x/z` avec un rayon fixe
(`ENTITY_PICK_RADIUS`, 0.6) — correct pour un portail (disque plat au ras du sol), mais pas
pour une capsule de 1.6 unité de haut vue par une caméra isométrique : cliquer sur le haut
visible d'un personnage projette, sur le plan `y=0`, un point loin de sa base (l'angle de
la caméra "regarde par-dessus"), donc hors du rayon de 0.6 centré sur sa position au sol —
le clic "passait à travers" vers le sol derrière le personnage, confirmé par une capture
d'écran de l'utilisateur montrant le curseur sur le haut de la capsule sans effet.

Corrigé en remplaçant ce test pour les entités par un vrai rayon physique 3D
(`_pick_entity_id_at_mouse`) contre une capsule de collision (`Area3D` + `CollisionShape3D`
sur `CapsuleShape3D`, couche dédiée `ENTITY_PICK_COLLISION_LAYER` — aucune autre collision
3D dans ce prototype, voir plus haut "pas de physique 3D" pour le déplacement, donc aucun
risque de faux positif) calquée exactement sur la capsule visuelle (même rayon 0.35/hauteur
1.6/décalage vertical 0.8, voir `_make_entity_node`), ajoutée à chaque entité sauf soi-même
(`pickable=false` pour le joueur — on ne se sélectionne pas, même règle que l'ancien
`if key == PLAYER_KEY: continue`). `_handle_left_click` tente désormais ce rayon physique
en premier ; à défaut, retombe sur l'ancienne logique plan y=0 pour les portails et le
déplacement (`_pick_at_point`, désormais recentrée sur les seuls portails). Aucun réseau
touché : l'UUID envoyé à `select` est lu tel quel sur la meta `entity_id` déjà posée par
`_register_entity_id`. `Game.tscn` rechargé en headless
(`Godot_v4.7.2-stable_win64.exe --headless --path . res://scenes/game/Game.tscn
--quit-after 30`), aucune nouvelle erreur (mêmes avertissements "pas connecté" habituels).
**Aucun outil MCP Godot ni exécutable interactif n'était disponible pour un test visuel
dans cet environnement** (contrairement à la session de création du prototype) : reste
entièrement à confirmer par un humain une fois un backend démarré — cliquer n'importe où
sur la hauteur visible d'une capsule (bas, milieu, haut) doit la sélectionner (anneau +
`TargetStatusBar`), cliquer à côté sur le sol doit toujours simplement déplacer le
personnage, et Échap/Tab doivent continuer de fonctionner comme avant.

## Session du 2026-09-03 : nom flottant/barres agrandies, parité du journal de chat

Deux retours indépendants de l'utilisateur, tous deux dans `scenes/game/Game3D.gd`.

**Nom flottant qui empiétait sur la barre de vie, barres trop petites.** Mesuré (voir
ci-dessous) via `Label3D.get_aabb()` dans ce projet : à `font_size=120` (alignement
vertical par défaut, CENTER), le nom flottant mesure 0.825 unité de haut, centré sur sa
position — largement plus que l'écart de 0.3 unité qui séparait jusqu'ici
`HP_BAR_OFFSET_Y` (1.85) de la position du nom (2.15), d'où le chevauchement signalé (et,
dans une moindre mesure, avec la barre d'incantation à 2.45, seulement visible pendant un
cast). Corrigé en : (1) remontant le nom à `y=3.15`, calculé pour dégager le sommet de la
barre d'incantation (la plus haute des deux, `CAST_BAR_OFFSET_Y=2.35` + moitié de sa
hauteur) avec une marge d'environ 0.19 unité ; (2) agrandissant les deux barres, vie
`BAR_WIDTH/HEIGHT` 0.9x0.12 → 1.1x0.22 et incantation `CAST_BAR_WIDTH/HEIGHT` 1.2x0.24 →
1.6x0.4 (la vie était elle aussi jugée trop petite cette fois, pas seulement
l'incantation/"cooldown" comme le 2026-09-02). Voir le commentaire au-dessus de
`BAR_WIDTH`/`NameLabel.position` dans `Game3D.gd` pour le calcul complet.

**Journal de chat très en retrait du client 2D.** `_on_message_received` ne traitait
jusqu'ici qu'une poignée de types de message pour le journal (`Chat`/`YouSaid`/
`AttackOutOfRange`/`PeaceZoneEntered`/`PeaceZoneExited`/`Error`) — en solo, sans autre
joueur pour déclencher `Chat`, le journal restait quasiment vide, très en retrait de
`mud-godot/scenes/game/hud/ChatOverlay.gd` (client 2D) qui logue aussi tout le combat/la
progression. Porté depuis ce fichier (texte français identique, nouvelles constantes
`LOG_COLOR_*` et fonctions `_log_attack_result`/`_log_cast_result`/
`_log_skill_cast_announced`/`_log_player_defeated`) : résultats d'attaque/de sort (dégâts,
échecs, critiques), XP gagnée, montée de niveau, butin (objet/or), mort/résurrection
(purement informatif — mort/respawn reste hors mécanique de ce prototype, voir plus haut),
zone de combat interdit, portée insuffisante (attaque et sort), incantation ratée (avec la
raison), déjà en train d'incanter, cible introuvable/aucune cible, mort/pas mort, pas de
portail à proximité. `PeaceZoneEntered`/`PeaceZoneExited` reformulés pour inclure le nom de
la zone comme côté 2D (le payload le porte déjà, juste jamais lu ici). Volontairement
laissés de côté : tous les messages de groupe (`Party*`) et de sous-classe
(`Subclass*`/`InvalidSubclass`/`NoPendingSubclassChoice`) — groupe explicitly hors scope de
ce prototype (voir plus haut), et aucune UI de choix de sous-classe n'existe ici
(`SubclassChoicePopup.gd` n'a pas été porté), donc ces messages ne seraient de toute façon
jamais déclenchés par ce client.

Les deux correctifs ont été vérifiés dans l'éditeur (`mcp__godot__run_project`, disponible
dans cet environnement contrairement à la session du 2026-09-02) plutôt que par simple
relecture statique : une scène de test jetable a mesuré `Label3D.get_aabb()` en isolation
pour dériver les constantes ci-dessus, puis une deuxième a instancié `Game.tscn` en entier
et appelé `_on_message_received` avec des payloads synthétiques pour chacun des nouveaux
types de message (`AttackResult` dans les deux sens, `CastResult`, `SkillCastAnnounced`,
`MonsterDefeated`, `XpGained`, `PlayerLeveledUp`, `EquipmentLooted`, `GoldLooted`,
`GamePlayerDefeated`, `PlayerRespawned`, `PeaceZoneEntered/Exited`, `AttackOutOfRange`,
`SkillFizzled`, `TargetNotFound`, `NoTargetSelected`) : le texte produit dans
`%LogLabel` a été relu et correspond mot pour mot à ce que produirait `ChatOverlay.gd`
pour les mêmes payloads, aucune erreur dans la sortie debug (mêmes avertissements "pas
connecté" habituels). Les deux scènes de test ont été supprimées après coup, aucun
fichier de test ne subsiste dans le projet. **Reste à confirmer par un humain** : l'aspect
visuel réel une fois un backend démarré (aucune capture d'écran prise ici, l'outil MCP
Godot disponible dans cet environnement n'expose pas de capture d'écran) — en particulier
que le nom ne semble pas anormalement haut au-dessus du personnage à l'œil, et que le
volume de messages dans le journal en jeu réel correspond bien aux attentes.

## Session du 2026-09-03 (suite) : cadre "vitaux du joueur" en haut à gauche, bleu de cooldown

Demande explicite : en haut à gauche, une icône ronde du niveau, le nom à sa droite, une
barre de vie rouge (PV courants/max, régénération comprise) puis une barre de mana bleue
sous le nom, une barre d'XP sous l'ensemble — plus une meilleure visibilité de l'overlay de
cooldown des slots de hotbar (jugé peu visible).

**Nouveau `scenes/game/hud/PlayerFrame.tscn`/`.gd`** : `Control` piloté entièrement par
`Game3D.gd` (pas d'abonnement `Net` propre, même principe que `TargetStatusBar.gd`) —
badge rond doré (niveau) + nom, barre de vie (rouge sur fond bordeaux sombre) et de mana
(bleu franc `Color(0.16,0.5,0.98)` sur fond bleu nuit) empilées sous le nom, barre d'XP fine
sur toute la largeur du cadre en dessous. Instancié dans `Game.tscn` (`HUD/PlayerFrame`),
`%InfoLabel` (`InfoPanel`, repoussé sous le nouveau cadre) ne garde plus que
carte/position — nom/niveau/PV/mana disparaissent de ce texte brut, remplacés par le
nouveau cadre visuel. Alimenté à chaque frame par `Game3D._update_player_frame()` : PV/
niveau depuis `_entity_vitals_by_key[PLAYER_KEY]`, mana depuis `GameState.current_mana`/
`max_mana` (déjà tenus à jour pour `Hotbar.gd`), XP depuis trois nouveaux champs
`GameState.xp`/`xp_for_current_level`/`xp_for_next_level`.

**Bug préexistant corrigé en cours de route** : `_apply_target_current_health`
(`AttackResult`/`CastResult`/`SkillCastAnnounced` qui nous ciblent) résout sa cible via
`_key_by_entity_id`, mais rien n'y enregistrait jamais notre propre UUID sous `PLAYER_KEY`
— nos PV ne bougeaient donc JAMAIS en combat, ni sur la barre flottante au-dessus de notre
tête (déjà présente mais invisible faute de PV non nuls) ni désormais sur ce nouveau cadre.
Corrigé par `_register_entity_id(PLAYER_KEY, id)` dans le handler `GamePlayerStats` et,
pour survivre à un changement de carte (`_rebuild_map`/`_clear_entities` vide ce cache), à
nouveau dans `_refresh_entities` (`MapEnter`) à partir de `GameState.player_stats.id`
(persistant lui). Deux bugs additionnels apparentés corrigés au passage : `_on_own_cast_result`
et `_on_skill_cast_announced` avaient chacun un `return` prématuré sur `selfHeal=true` qui
sautait l'appel à `_apply_target_current_health` — se soigner soi-même (ou voir un autre
lanceur se soigner) ne mettait donc jamais à jour la barre de vie malgré
`targetCurrentHealth`/`targetHealthAfter` déjà présents dans le payload.

**Regen temps réel** : nouveau cas `"RegenTick"` dans `Game3D._on_message_received` (absent
jusqu'ici de ce client, contrairement au 2D) — met à jour `_entity_vitals_by_key[PLAYER_KEY]`
et le taux affiché en "(+X/s)" sur la barre de vie (`_health_regen_rate`/`_mana_regen_rate`,
mêmes noms/principe que `PlayerStatusBars.gd` côté 2D : un montant à 0 signifie juste que ce
tick ne concernait pas cette barre, PV et mana régénérant indépendamment, pas que la regen
s'est arrêtée). `PlayerRespawned` met aussi à jour les PV (quart des PV max, comme documenté
plus haut pour le respawn) plutôt que de laisser le cadre figé sur les PV d'avant la mort.

**Backend touché (`mud-server-java`, WSL `/home/tdelemis/workspace/mud-server-java`,
accessible depuis Windows via `\\wsl.localhost\Debian\...`)** : aucun champ XP cumulée/seuil
de niveau n'existait dans le protocole (`GamePlayerStats.Payload` n'avait que `level` ;
`XpGained` que `amount` ; vérifié par lecture directe des sources Java, aucun des deux
clients n'en avait jamais eu besoin jusqu'ici) — impossible de remplir une barre d'XP
proportionnelle sans ça. Ajout additif (aucun champ retiré/renommé, donc sans impact sur le
client 2D qui ignore simplement les champs qu'il ne lit pas) :
- `GamePlayerStats.Payload` gagne `xp`/`xpForCurrentLevel`/`xpForNextLevel`
  (`CharacterInstance.getXp()` + `LevelCatalogHolder.xpRequiredForLevel(level[/+1])` ;
  niveau max : `xpForNextLevel = xpForCurrentLevel`, barre pleine plutôt que division par
  zéro côté client).
- `XpGained` gagne les trois mêmes champs, calculés dans `CharacterInstance.gainXp()`
  juste après l'incrément et AVANT la boucle de montée de niveau (le `send()` d'origine
  n'a pas été déplacé, pour ne pas changer l'ordre `XpGained`/`PlayerLeveledUp` déjà validé
  côté client 2D) : si ce gain déclenche une montée de niveau, ce message précis peut
  reporter un ratio dépassant 1 (seuils de l'ancien niveau) — sans conséquence, corrigé dès
  le message suivant. `Game3D.gd` redemande d'ailleurs explicitement `Net.send_command
  ("stats")` sur notre propre `PlayerLeveledUp` pour rafraîchir les seuils au plus vite
  plutôt que d'attendre un futur gain d'XP.
Compilé avec succès (`mvn -o -q compile`, sdkman via `bash -lic`, aucune erreur) mais **le
serveur `mvn spring-boot:run` déjà lancé doit être redémarré pour prendre en compte ce
changement** — non fait ici (pas de serveur tournant dans cet environnement).

**Cooldown de hotbar peu visible** : `HotbarSlot.tscn`, `CooldownOverlay.color` passait de
`Color(0,0,0,0.6)` (noir, se distinguait mal du thème déjà sombre) à
`Color(0.10,0.40,1.0,0.6)` — même bleu franc que `CAST_BAR_COLOR` dans `Game3D.gd` (déjà
choisi et validé le 2026-09-02 pour la même raison, "pas assez visible"/"pas assez bleu"),
repris ici pour cohérence visuelle entre les deux indicateurs de temporisation du jeu.
L'aiguille blanche existante reste lisible par-dessus.

Vérifié dans cet éditeur (exécutable trouvé sous
`C:\Users\thoma\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
— ce chemin est en réalité un DOSSIER contenant l'exécutable du même nom, pas l'exécutable
lui-même ; la doc plus bas dans ce fichier est donc légèrement fausse, à corriger si
reconstatée) : `Game.tscn`/`Login.tscn` rechargés en headless sans nouvelle erreur, puis une
scène de test jetable (même principe que les sessions précédentes, supprimée après usage)
a émis de vrais signaux `Net.message_received` (pas un appel direct à `_on_message_received`,
qui aurait contourné l'abonnement séparé de `GameState.gd` au même signal — piège rencontré
une fois puis corrigé pendant cette vérification) simulant `GamePlayerStats`/`AttackResult`
(subi)/`RegenTick`/`CastResult` (selfHeal)/`XpGained` : chaque valeur affichée sur le nouveau
cadre (PV, mana, XP, taux de regen) correspond exactement à la valeur attendue calculée à la
main, y compris le cas limite niveau max (barre pleine, pas de division par zéro). Confirmé
aussi via `mcp__godot__run_project` (rendu réel, pas seulement headless) : aucune erreur au
démarrage ni pendant l'exécution. **Aucune capture d'écran prise** (MCP Godot disponible ici
n'en expose pas, comme noté dans les sessions précédentes) : l'apparat visuel réel (tailles
relatives icône/nom/barres, lisibilité, position par rapport au reste du HUD) reste à
confirmer par un humain, de même que le test de bout en bout avec un vrai backend (une fois
celui-ci redémarré pour le nouveau champ XP) — en particulier qu'encaisser des dégâts, se
soigner et regénérer PV/mana en solo font bien bouger les nouvelles barres, et qu'une
montée de niveau réelle rafraîchit correctement le seuil de la barre d'XP.

## Session du 2026-09-03 (suite) : barre de cast en pilule bleue arrondie, opaque

Retour visuel sur la barre d'incantation flottante (capture d'écran utilisateur à l'appui,
un personnage "Tata" en train d'incanter) : jugée trop sombre, demande explicite d'une
petite barre bleue aux bords arrondis, sans transparence, "quelque chose de joli".

`_make_floating_bar`/`_make_bar_quad` (toujours utilisés par la barre de vie, inchangée)
dessinaient fond + remplissage comme deux `QuadMesh` rectangulaires plats empilés, le fond
`CAST_BAR_BG_COLOR` étant un bleu quasi noir à alpha 0.85 (`TRANSPARENCY_ALPHA`) — le
mélange avec ce qu'il y a derrière (sol, ombre d'obstacle, capsule) l'assombrissait encore
plus que sa couleur de base ne le suggère, d'où le rendu perçu comme "trop sombre".

Remplacé pour la seule barre de cast par `_make_rounded_progress_bar` (nouveau,
`Game3D.gd`) : un unique `QuadMesh` avec un `ShaderMaterial` (code source dans
`ROUNDED_BAR_SHADER_CODE`) qui dessine fond ET remplissage comme une seule pilule via une
SDF de rectangle arrondi (`corner_radius` = demi-hauteur ⇒ bouts parfaitement
semi-circulaires) plutôt que deux quads séparés — évite aussi la distorsion du bord arrondi
qu'aurait causée le `fill_pivot.scale.x` de l'ancien système sur un bord non rectangulaire.
`ALPHA` du shader vaut toujours 0 (`discard`, hors pilule) ou 1 (dans la pilule) : plus
aucune transparence sur la barre elle-même, seul le contour est légèrement lissé
(`fwidth`) pour l'anti-aliasing. `fill_ratio` (uniform) est mis à jour chaque frame dans
`_update_bars` via `set_shader_parameter`, à la place de l'ancien `_set_bar_ratio`
(toujours utilisé tel quel par la barre de vie). Taille réduite (`CAST_BAR_WIDTH/HEIGHT`
1.6x0.4 → 0.9x0.2, "une petite barre" demandée explicitement après l'avoir agrandie deux
fois lors des sessions précédentes) et couleurs revues : fond `CAST_BAR_BG_COLOR` bleu nuit
désormais opaque (alpha=1, plus de flou de transparence), remplissage `CAST_BAR_COLOR` bleu
vif émissif inchangé dans l'esprit du 2026-09-02 (juste légèrement éclairci). Barre de vie
non touchée (le retour ne portait que sur celle de cast).

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) via une scène de
test jetable instanciant `Game.tscn`, forçant une entité factice en incantation
(`_casting_by_key`) et appelant `_ensure_bars`/`_update_bars` directement : aucune erreur de
compilation shader dans la sortie debug, `cast_bar.material` bien un `ShaderMaterial`,
`fill_ratio` réagit à l'avancement du cast. **Capture d'écran réelle obtenue cette fois**
(correctif à une affirmation des sessions précédentes comme quoi le MCP Godot disponible ici
n'expose pas de capture : il n'y a pas d'action dédiée dans l'outil MCP, mais la scène de
test elle-même peut sauvegarder une image via `get_viewport().get_texture().get_image().
save_png("res://...")`, relue ensuite depuis le disque) : confirme visuellement une petite
pilule bleue aux bouts arrondis, remplissage bleu vif net sur fond bleu nuit opaque, sans
aspect sombre/délavé. Scène de test et capture supprimées après usage, comme les sessions
précédentes. **Reste à confirmer par un humain** : le ressenti en jeu réel contre un vrai
backend (taille/lisibilité de la pilule à l'échelle d'un vrai cast, pas seulement en gros
plan de test).

## Session du 2026-09-03 (suite) : fenêtres HUD façon L2J — inventaire, équipement à slots,
## fiche de personnage, options, icônes bas-droite

Demande explicite : une rangée d'icônes en bas à droite (compétences/K, inventaire/I, fiche
de personnage/P, équipement/O, options — sans raccourci pour ce dernier), des fenêtres
toutes déplaçables avec une croix de fermeture, Échap fermant "la fenêtre la plus proche de
nous", et un équipement à emplacements (arme/casque/armure/bottes/bijoux/etc.) avec glisser-
déposer depuis l'inventaire — "quelque chose qui ressemble à du Lineage 2 / L2J".

**Aucune de ces fenêtres n'existait dans ce prototype 3D avant cette session** (voir
CLAUDE.md, section "Ce qui N'EST PAS dans ce prototype", mise à jour en conséquence) ;
`mud-godot` (client 2D) a bien un `InventoryPanel.gd`/`CharacterSheet.gd`/`OptionsMenu.gd`/
`BottomRightMenu.gd`, mais **aucune fenêtre du 2D n'est déplaçable ni ne porte de croix**
(popups fixes centrées, fermées par un bouton "Fermer" texte) et **aucune n'a de slots
d'équipement interactifs** (`CharacterSheet.gd` du 2D n'affiche l'équipement que comme une
liste de texte en lecture seule, "Arme : Épée longue") — le comportement déplaçable/
fermable façon L2J et les slots à glisser-déposer sont donc entièrement nouveaux, écrits
pour ce prototype plutôt que portés.

**`scenes/game/hud/WindowFrame.gd`** (nouveau, `class_name WindowFrame`) : classe de base
dont héritent (`extends WindowFrame`) toutes les fenêtres concrètes ci-dessous, portant la
logique commune — glisser par la barre de titre (`%TitleBar`, curseur "move"), bouton de
fermeture (`%CloseButton`, "×"), et une pile statique (`_open_stack`) de toutes les fenêtres
ouvertes, dans l'ordre d'ouverture/mise au premier plan (cliquer la barre de titre d'une
fenêtre la fait remonter en tête de pile ET au premier plan visuel via
`move_child`). `WindowFrame.close_topmost()` (statique) ferme la dernière de la pile — c'est
la fenêtre que l'utilisateur appelle "la plus proche de nous" — et renvoie `false` si aucune
n'était ouverte ; `Game3D._unhandled_input` l'appelle en tête de son traitement d'Échap,
avant la désélection de cible/portail déjà existante, pour que fermer une fenêtre soit
toujours prioritaire. Chaque fenêtre concrète fournit sa propre scène avec la structure
minimale attendue (`%TitleBar`/`%TitleLabel`/`%CloseButton`/`%Body`) — mise en page dupliquée
par fichier .tscn (même convention que le reste du projet), logique centralisée une seule
fois dans ce script.

**`SkillBook.gd`/`.tscn` retouchés** pour hériter de `WindowFrame` (seule fenêtre déjà
existante concernée) : bascule K désormais `close_window()`/`open()` au lieu d'un
`visible = false/true` brut, la fenêtre est donc devenue déplaçable/dans la pile Échap
comme les nouvelles, sans changement de comportement réseau.

**`scenes/game/hud/InventoryWindow.gd`/`.tscn`** (nouveau, touche I) : objets non équipés
(`Inventory.Entry.slot == null`) + or, port du contenu de `InventoryPanel.gd` (2D) minus le
bouton "Équiper" — équiper se fait désormais en glissant une ligne vers un slot
d'EquipmentWindow, demandé explicitement. Icônes générées par
`ZoneAssets3D.make_slot_icon_texture("item", nom)` (pas de `ITEM_ICON_BY_NAME`/pack
Claw&Blade ici, voir CLAUDE.md — aucun art externe dans ce prototype). Chaque ligne
(`DraggableRow`) porte désormais `drag_ref_id` (l'UUID de l'objet), pas seulement
`drag_ref_name` comme le fait la hotbar pour les objets consommables : contrairement à un
slot de hotbar (persisté par nom, résolu à l'UUID courant au moment de l'usage — un objet
consommé change d'UUID à chaque fois, voir `Hotbar._resolve_item_id`), équiper est une
action immédiate qui a besoin de l'UUID exact vu au moment du glisser, capturé directement
à la construction de la ligne. "Jeter" (confirmation locale avant `drop`, le backend n'en
propose aucune) inchangé du 2D.

**`scenes/game/hud/EquipmentSlot.gd`/`.tscn`** (nouveau) : un emplacement, cousin de
`HotbarSlot.gd` (même principe d'ignorance totale du protocole réseau — `EquipmentWindow`
décide quoi envoyer) mais sans cooldown/mana, avec en plus le retrait au clic droit
(`unequip_requested`). Vide, affiche une abréviation à 2 lettres discrète (ex. "Ar" pour
Arme, "BG"/"BD" pour les boucles d'oreille gauche/droite, "AG"/"AD" pour les anneaux — le
nom complet reste en tooltip) plutôt qu'une icône dédiée par catégorie (aucune iconographie
d'arme/casque/etc. disponible, voir plus haut) ; rempli, montre l'icône procédurale de
l'objet (même fonction que l'inventaire) avec tooltip nom+grade.

**`scenes/game/hud/EquipmentWindow.gd`/`.tscn`** (nouveau, touche O) : 12 `EquipmentSlot`
arrangés en silhouette façon paperdoll L2 via un `GridContainer` 3 colonnes (tête en haut-
centre ; arme à gauche/bouclier-main secondaire à droite au niveau du collier ; boucles
d'oreille de part et d'autre du torse ; anneaux de part et d'autre des mains ; jambes puis
pieds en bas-centre — cases vides comblées par des `Control` espaceurs invisibles de même
taille). Glisser une ligne d'InventoryWindow sur N'IMPORTE LEQUEL des 12 slots envoie le
même `equip <uuid>` : le slot où l'objet finit réellement équipé est décidé par le serveur
(`app.domain.item.ItemType.equipmentSlots`, ex. un anneau va à `LEFT_RING` OU `RIGHT_RING`
selon disponibilité) — seul le retour serveur (`Inventory` rejoué après `ItemEquipped`)
détermine quel(s) slot(s) s'allume(nt) réellement, même limitation assumée que le bouton
"Équiper" du 2D qui ne choisit pas non plus de slot précis. Backend vérifié pour cette
session (`app.network.command.ingame.Equip`/`Unequip`, `app.network.message.ingame.
Inventory`/`EquipmentSlot`/`ItemType` dans `mud-server-java`, accessible via
`\\wsl.localhost\Debian\home\tdelemis\workspace\mud-server-java`) : `equip`/`unequip`
prennent tous deux l'UUID de l'objet (celui déjà porté par `unequip`, pas un nom de slot) —
aucun champ "type" n'est exposé côté `Inventory.Entry` (seulement `id`/`name`/`grade`/
`slot`), donc impossible de prévisualiser côté client quel slot précis une arme/un bijou non
équipé occuperait avant de le glisser — c'est cette limitation qui a dicté "glisser sur
n'importe quel slot" plutôt qu'une validation de correspondance objet/slot avant envoi.

**`scenes/game/hud/CharacterSheetWindow.gd`/`.tscn`** (nouveau, touche P) : port quasi
verbatim de `CharacterSheet.gd` (2D) — attributs (Force/Dextérité/Constitution/
Intelligence/Sagesse WIT/Mental MEN, `GameState.player_stats`), stats de combat Lineage2
(P.Atk/P.Def/M.Atk/M.Def/Précision/Esquive/Critique/Vit.Atk), PV/Mana, et la même liste
texte d'équipement porté que le 2D (redondante avec EquipmentWindow mais volontairement
conservée : une fiche de personnage complète "attributs, etc." a été demandée séparément de
l'équipement à slots). Champs `GamePlayerStats.Payload` revérifiés à la source
(`mud-server-java`) pour cette session : toujours `strength`/`dexterity`/`constitution`/
`intelligence`/`wit`/`men` côté JSON malgré le renommage interne de l'enum Java
`Attribute` (STRENGTH→STR etc., mentionné dans une session précédente comme non vérifié
faute d'écran alors concerné) — aucun changement nécessaire par rapport au 2D sur ce point.

**`scenes/game/hud/OptionsWindow.gd`/`.tscn`** (nouveau, pas de raccourci clavier — non
demandé, uniquement accessible par icône) : menu volontairement minimal par rapport à
`OptionsMenu.gd` (2D, qui gère aussi graphismes/son via un autoload `Settings.gd` jamais
porté ici, hors scope) — seulement "Se déconnecter" (retour à `Login.tscn`) et "Quitter"
(déconnexion puis `get_tree().quit()`, même geste que le bouton "Quitter" de `Login.gd`),
chacun avec une confirmation (`ConfirmationDialog`) avant d'agir, absente du 2D.

**`scenes/game/hud/BottomRightIcons.gd`/`.tscn`** (nouveau) : 5 boutons 48×48 (texte à 2
lettres — "So"/"Sa"/"Pe"/"Éq"/"Op" — stylés par le thème global doré existant plutôt qu'une
icône image dédiée, aucun art externe disponible) ouvrant/fermant chaque fenêtre ; ne fait
que basculer `visible`/appeler `open()`/`close_window()`, aucune logique dupliquée avec les
raccourcis clavier de chaque fenêtre (les deux chemins convergent). Remplace l'équivalent
2D `BottomRightMenu.gd`, qui cache tout derrière un unique bouton "☰" — demandé explicitement
en icônes visibles directement plutôt qu'un menu à déplier.

**`Game3D._unhandled_input`** : la branche Échap tente d'abord `WindowFrame.close_topmost()`
avant la désélection de cible/portail déjà existante (voir plus haut). `Game.tscn` instancie
les 5 nouvelles scènes sous `HUD` et le `HintLabel` mentionne désormais I/P/O en plus de K.

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) : `Game.tscn`
rechargé en headless sans nouvelle erreur (juste après un `--headless --editor --quit` pour
forcer Godot à enregistrer `WindowFrame` comme classe globale dans son cache — sans ce passage
`class_name WindowFrame` n'est pas résolu par un lancement direct de scène, piège rencontré
puis corrigé pendant cette vérification). Une scène de test jetable (même principe que les
sessions précédentes, supprimée après usage) a ensuite, contre `Game.tscn` instancié avec de
vraies données `GameState` synthétiques (stats, inventaire avec objets équipés et non
équipés, sorts connus) :
- ouvert les 4 fenêtres (`open()`) et vérifié le texte réellement affiché (tooltips des
  slots d'équipement remplis/vides, attributs/stats de la fiche) — correspond exactement
  aux valeurs synthétiques ;
- simulé un vrai glisser-déposer (`EquipmentSlot._can_drop_data`/`_drop_data` appelés comme
  le ferait Godot) d'un objet non équipé vers un slot d'anneau : `equip <uuid>` bien envoyé
  (visible dans la sortie debug, "pas connecté" faute de serveur ici, comme attendu) ;
- simulé un clic sur la barre de titre d'une fenêtre pas au premier plan : `_dragging` passe
  à `true`, la fenêtre remonte bien en tête de `WindowFrame._open_stack` (bring-to-front) ;
- avec 4 fenêtres ouvertes, appelé `WindowFrame.close_topmost()` en boucle : les 4 se
  ferment une par une (la plus récemment au premier plan en premier), puis la pile vide
  renvoie bien `false` ;
- capturé une image réelle du viewport (`get_viewport().get_texture().get_image().
  save_png`, même technique que la session précédente sur la barre de cast) confirmant
  visuellement le thème doré/sombre cohérent avec le reste du HUD, les croix de fermeture,
  et la disposition en paperdoll de l'équipement (tête en haut, arme/bouclier de part et
  d'autre, bijoux en périphérie, jambes/pieds en bas). Scène de test et capture supprimées
  après usage.

**Reste à confirmer par un humain, une fois un backend démarré** : le rendu exact du drag
visuel PENDANT le déplacement d'une ligne d'inventaire (la préversion de `DraggableRow`
n'a été vue qu'au travers de son résultat, `_drop_data`, jamais pendant le survol réel) ;
qu'un `equip`/`unequip` réel change bien visuellement le bon slot une fois la réponse
serveur reçue ; le confort du positionnement par défaut des fenêtres en cascade légèrement
superposée à 1600×900 (délibéré, façon L2 — l'utilisateur peut les faire glisser) ; et que
d'autres raccourcis clavier du jeu (F1-F12, Tab, Entrée) ne sont pas capturés par erreur
par une fenêtre ouverte au premier plan (chaque fenêtre ne consomme que sa propre touche de
bascule et ignore tout le reste, en principe sans conflit, mais jamais testé en conditions
réelles avec le focus clavier d'une vraie fenêtre visible).

## Session du 2026-09-03 (suite) : icônes dédiées potion de soin/mana, Heal, Wind Strike

Demande explicite : une "belle" icône pour les potions de soin, en s'inspirant de Lineage 1/
2, ainsi que pour les sorts "Heal" et "Wind Strike" — jusqu'ici, `ZoneAssets3D.
make_slot_icon_texture` (voir plus haut, "Ce qui est nouveau") ne produisait qu'un carré
générique teinté par catégorie (rouge=attaque, bleu=sort, vert=objet) avec une légère
variation de teinte par nom : rien ne distinguait visuellement une potion de soin d'un
autre objet, ni "Heal" de "Wind Strike".

`make_slot_icon_texture` reste inchangé pour tout le reste ; il dispatch désormais en tête
vers 3 nouvelles fonctions dédiées sur un match exact du nom serveur (voir
`data/items/consumables.xml`/`data/skills/skills.xml` côté `mud-server-java`), toujours
100% procédural (`Image`/`set_pixel`, aucun art externe dans ce prototype, voir plus haut) :
- `_make_potion_icon_texture(liquid_color, size)` : fiole à bouchon/col de verre + corps
  rond avec reflet, réutilisée pour rouge (`*Healing Potion`, tous paliers confondus —
  Greater/Major/Supreme partagent la même icône, seul le nom en tooltip les distingue) et
  bleu (`*Mana Potion`, ajouté par cohérence même si non demandé explicitement — même
  fonction, juste une autre `liquid_color`, coût nul).
- `_make_heal_icon_texture(size)` : croix blanc-or à bords nets sur halo radial vert-doré.
- `_make_wind_strike_icon_texture(size)` : spirale verte tracée par tamponnage de disques
  le long d'une trajectoire polaire (`_stamp_soft_dot`), épaissie/éclaircie vers la pointe
  pour suggérer le mouvement.

`kind` (déjà transmis par tous les appelants, voir plus haut) évite toute collision entre
l'objet "Healing Potion" et le sort "Heal" homonyme en partie.

Vérifié avec l'exécutable console Godot en headless (`--check-only`, aucune erreur — une
première tentative a révélé une erreur d'inférence de type GDScript sur un `bool` calculé
sur deux lignes avec un retour à la ligne avant `or`, corrigée en annotant explicitement
`var in_cross: bool`) puis par un rendu réel : scène de test jetable (même principe que les
sessions précédentes, supprimée après usage) appelant `make_slot_icon_texture` pour les 5
noms concernés à 128px et sauvegardant chaque résultat en PNG (`Image.save_png`), relu
depuis le disque — confirme visuellement une fiole rouge/bleue convaincante (bouchon,
reflet de verre, volume du liquide) et une croix/spirale lisibles et distinctes l'une de
l'autre, cohérentes avec le thème doré/sombre du reste du HUD. **Reste à confirmer par un
humain** : le rendu à la taille réelle d'un slot de hotbar/inventaire (40px, plus petit que
les 128px de la vérification) et l'aspect en jeu réel une fois un backend démarré.

## Session du 2026-09-03 (suite) : icône = poignée de glisser-déposer dans le carnet de
## sorts, clic droit/glisser-hors-fenêtre dans l'inventaire, icônes bas-droite procédurales

Trois retours explicites sur les fenêtres HUD ajoutées plus tôt cette même session :
chaque sort du carnet doit afficher icône + nom (caractéristiques en tooltip sur l'icône,
qui doit être la poignée de glisser-déposer vers la hotbar) ; les boutons "Utiliser"/
"Jeter" de l'inventaire doivent disparaître au profit d'un clic droit sur l'icône (utiliser)
et d'un glisser-déposer hors de la fenêtre (jeter) ; les icônes bas-droite (jusqu'ici du
texte à 2 lettres, voir plus haut) doivent devenir de "petites icônes procédurales", jugées
"plus jolies".

**`scenes/game/hud/DraggableIcon.gd`** (nouveau, remplace entièrement `DraggableRow.gd`,
supprimé — plus aucune référence après ce refactor) : même rôle (source de glisser-déposer
vers Hotbar.gd/EquipmentSlot.gd, mêmes champs `drag_kind`/`drag_ref_id`/`drag_ref_name`,
même dictionnaire `{kind, ref_id, ref_name}` renvoyé par `_get_drag_data` — donc aucun
changement côté `HotbarSlot._can_drop_data`/`EquipmentSlot._can_drop_data`, qui ignorent
tout de la provenance du drag) mais porté par un `TextureRect` (l'icône elle-même) plutôt
que par toute une `HBoxContainer` (la ligne nom compris) — demandé explicitement ("c'est
cette icône qu'il faudra drag&drop"). Ajoute aussi `right_clicked` (`_gui_input` sur
`MOUSE_BUTTON_RIGHT`, même principe qu'`EquipmentSlot.gd`) et `drag_finished(successful)`
(`_notification(NOTIFICATION_DRAG_END)` + `get_viewport().gui_is_drag_successful()`), tous
deux utilisés par `InventoryWindow.gd` ci-dessous.

**`SkillBook._build_row`** : ligne simplifiée en icône (`DraggableIcon`, sort ⇒
`ZoneAssets3D.make_slot_icon_texture("skill", nom)`, donc les icônes dédiées Heal/Wind
Strike de la session précédente s'affichent aussi ici) + nom (au lieu de la précédente
ligne de texte unique "Nom (Niv. X, Dégâts, Y mana, Zs cd)") ; les caractéristiques
complètes (niveau, type d'effet, coût, recharge, portée, durée, octroyé, description)
passent en tooltip sur l'icône via une nouvelle `_skill_tooltip`, portée telle quelle
depuis `Hotbar._skill_tooltip` (dupliquée plutôt que partagée, comme `EFFECT_LABELS` déjà
dupliqué entre ces deux fichiers — chaque fenêtre HUD reste un `Control` autonome sans
dépendance croisée, convention déjà en place, voir `WindowFrame.gd`).

**`InventoryWindow._build_row`** : boutons "Utiliser"/"Jeter" retirés. L'icône (désormais
`DraggableIcon`) répond à `right_clicked` par `Net.send_command("use", item_id)` (identique
à l'ancien bouton "Utiliser", juste un geste différent) et à `drag_finished` par
`_on_item_drag_finished`, nouveau : un drop réussi (accepté par la hotbar ou un slot
d'équipement — les deux seuls `Control` de ce prototype à implémenter `_can_drop_data` pour
`kind == "item"`) ne fait rien de plus ; un drop raté (relâché n'importe où ailleurs) est
comparé au rectangle global de la fenêtre (`get_global_rect().has_point(get_global_mouse_
position())`) : à l'intérieur (ex. relâché par erreur sur une autre ligne), ignoré ; en
dehors, réutilise l'ancienne confirmation locale (`_on_drop_pressed`/`ConfirmationDialog`,
toujours nécessaire : `Drop` détruit l'objet côté serveur sans confirmation proposée par le
backend) puis `Net.send_command("drop", ...)` sur confirmation, inchangé.

**`ZoneAssets3D.make_ui_icon_texture(kind, size)`** (nouveau) : pictogrammes procéduraux à
fond transparent (contrairement à `make_slot_icon_texture`, qui peint son propre fond de
slot — ceux-ci vivent à l'intérieur d'un `Button` déjà stylé par `UITheme.gd`) pour les 5
boutons de `BottomRightIcons.gd` : grimoire fermé (couverture cuir, tranche dorée,
étincelle — "skills"), besace nouée (corps + col + lien — "inventory"), silhouette tête +
épaules ("character"), bouclier héraldique (sommet arrondi, ligne dorée centrale —
"equipment"), engrenage (disque + dents + trou central — "options"). Couleurs dupliquées
depuis `UITheme.gd` (`UI_ICON_GOLD`/`UI_ICON_GOLD_BRIGHT`/`UI_ICON_IVORY`) plutôt
qu'importées : `UITheme` est un autoload `Node` construit à `_ready()`, `ZoneAssets3D` doit
pouvoir générer ces textures sans dépendre de l'ordre d'initialisation des autoloads.
`BottomRightIcons._style_icon_button` vide le texte des boutons, assigne l'icône
(`expand_icon = true`, alignements centrés) et resserre leurs marges de contenu (dupliquant
chaque `StyleBoxFlat` du thème global — `normal`/`hover`/`pressed`/`disabled`/`focus` — avec
des marges de 6px au lieu des 16/7px pensées pour du texte court, sans toucher `UITheme.gd`
qui reste partagé par tout le HUD) pour qu'un pictogramme de 40px ne soit pas rogné dans un
bouton de 48×48.

**Piège rencontré en vérifiant** : le bouclier "Équipement" dessiné par une largeur qui
croît en `sqrt` depuis 0 en haut jusqu'à la largeur max à l'épaule, puis redescend
linéairement jusqu'à une pointe basse, donnait en réalité un losange (pointu en haut ET en
bas, confirmé par une première capture d'écran) plutôt qu'un bouclier (plat/arrondi en
haut). Corrigé en remplaçant le haut par un rectangle à coins arrondis
(`_sdf_rounded_box`, même helper que le grimoire/la besace) de largeur constante, épaulé en
dessous par le dégradé de largeur original pour la pointe basse — revérifié par une
deuxième capture, bouclier correctement reconnaissable.

Vérifié avec `mcp__godot__run_project` (nécessaire cette fois, pas seulement
`--headless --check-only` en CLI : une première tentative de capture d'écran via
`--headless res://... --quit-after` a échoué, `get_viewport().get_texture()` renvoyant une
texture nulle avec le driver de rendu "dummy" utilisé par ce mode — noter pour de futures
sessions que `mcp__godot__run_project`, qui utilise un vrai contexte OpenGL, reste
nécessaire pour toute capture d'écran, `--headless` en CLI ne suffit pas même pour un
rendu hors-écran) : scène de test jetable (même principe que les sessions précédentes,
supprimée après usage) instanciant `Game.tscn` avec `GameState.known_skills`/`inventory`
synthétiques (Heal, Wind Strike octroyé, Healing Potion, Greater Mana Potion, Short Sword
en repli sans icône dédiée), ouvrant `SkillBook`/`InventoryWindow` et sauvegardant une vraie
capture du viewport. Confirme visuellement : icône + nom pour chaque sort (croix dorée
Heal, spirale verte Wind Strike) ; icône + nom coloré par grade pour chaque objet (fiole
rouge/bleue, carré générique pour l'épée) sans bouton "Utiliser"/"Jeter" ; les 5 icônes
bas-droite lisibles et distinctes (grimoire/sac/personnage/bouclier/engrenage) dans le
thème doré/sombre existant. Un appel direct à `_on_item_drag_finished(false, ...)` (glisser-
déposer réel non simulable en headless) confirme que la branche "en dehors de la fenêtre"
ouvre bien la confirmation de destruction sans erreur. **Reste à confirmer par un humain,
une fois un backend démarré** : le ressenti d'un vrai glisser-déposer (aperçu pendant le
survol, comportement si relâché exactement sur la bordure de la fenêtre) et qu'utiliser un
objet via clic droit fonctionne de bout en bout comme l'ancien bouton "Utiliser".

## Session du 2026-09-03 (suite) : infobulles d'objets complètes, p.atk/p.def rafraîchis à
## l'équipement, refonte des caractéristiques, retrait de l'équipement porté de la fiche

Quatre retours explicites : (1) survoler l'icône d'un objet (inventaire ou équipement)
doit montrer toutes ses caractéristiques (grade, p.atk/m.atk pour une arme, etc.) ; (2) les
p.atk/p.def/m.atk/m.def de la fiche de personnage doivent refléter l'arme équipée ; (3) la
section "Caractéristiques" semblait fausse à l'utilisateur et devait être revue, "on n'a
plus de modifiers" ; (4) retirer la liste d'équipement porté de la fiche de personnage
(déjà dans `EquipmentWindow`, doublon).

**Backend touché (`mud-server-java`, WSL, voir plus haut pour le chemin)** : `Inventory.
Entry` (`app.network.message.ingame.Inventory`) n'exposait que `id`/`name`/`grade`/`slot` —
aucune caractéristique de combat, vérifié par lecture directe des sources Java. Étendu avec
`type`/`description`/`weight`/`armorCategory`/`pAtk`/`mAtk`/`pDef`/`mDef`/`accuracyBonus`/
`evasionBonus`/`critBonus`/`atkSpd`/`enchant`, peuplés dans `app.network.command.ingame.
Inventory.toEntry(Item)` (nouveau, remplace le lambda inline) à partir des getters déjà
existants sur `Item`/`EquipmentItem` — aucune formule ajoutée, ces valeurs existaient déjà
côté serveur (`Item.getPAtk()` etc., utilisées pour `recomputeStats()`), simplement jamais
renvoyées au client jusqu'ici. `Item.getPAtk()`/`getArmorCategory()`/etc. castent
inconditionnellement leur template en `EquipmentItem` (`Item.equipment()`) : un objet non
équipable (potion, clé) lèverait une `ClassCastException` si on les appelait telles
quelles — `toEntry` vérifie donc `item.getTemplate() instanceof EquipmentItem` avant de les
lire, sinon renvoie 0/null pour ces champs (`enchant` reste lisible pour tout objet, porté
directement par `Item`, pas par le template). Compilé avec succès (`mvn -o -q compile`,
aucune erreur) ; **serveur `mvn spring-boot:run` à redémarrer pour prendre en compte ce
changement**, non fait ici (pas de serveur tournant dans cet environnement).

**p.atk/p.def figés après un equip/unequip (bug confirmé, pas juste une impression)** :
`app.network.command.ingame.Equip`/`Unequip` appellent bien `character.recomputeStats()`
côté serveur (via `InventorySystem.equipItem`/`unequipItem`, vérifié) — les stats
effectives (`StatSystem.getEffective`) sont donc réellement à jour côté serveur dès
l'équipement. Mais ni `Equip` ni `Unequip` ne renvoient de `GamePlayerStats` frais (juste
`ItemEquipped`/`ItemUnequipped`, qui ne portent pas p.atk/p.def), et
`CharacterSheetWindow._on_message_received` ne redemandait "stats" qu'à l'ouverture de la
fenêtre (`open()`) — un equip pendant que la fiche reste ouverte ne la rafraîchissait donc
jamais, contrairement à l'impression du client 2D dont le comportement est identique (même
bug, jamais remarqué faute d'avoir gardé la fiche ouverte en changeant d'arme). Corrigé
côté ce client 3D uniquement (hors scope de retoucher le 2D ici) : `CharacterSheetWindow.
gd` redemande désormais "stats" sur `ItemEquipped`/`ItemUnequipped` reçus pendant qu'elle
est visible ; l'appel `Net.send_command("inventory")` de `open()` a aussi été retiré,
devenu inutile une fois la liste d'équipement retirée (voir point 4 ci-dessous).

**Caractéristiques (Force/Dextérité/etc.) : le "modifier" D&D5e retiré, pas les scores**
— revérifié côté backend (`AbstractCharacter.getAttribute`/`getModifier`,
`GamePlayerStats.Payload`) : les scores renvoyés sont corrects et déjà calculés sans lien
avec l'équipement (aucun objet ne modifie STR/DEX/etc. dans ce système, seulement p.atk/
p.def/etc. via `EquipmentItem`, vérifié) — rien à corriger côté valeurs. Le "(+X)"
affiché à côté de chaque score était le modificateur D&D5e `floor((score-10)/2)`, un
reliquat de l'ancien système de combat sans aucun rôle dans les formules Lineage2 actuelles
(`CombatFormulas` consomme le score brut directement via `statBonus()`, jamais ce
modificateur) — recalculé côté serveur mais sémantiquement mort. Retiré de l'affichage
(`CharacterSheetWindow._refresh`, `AttributeScore.modifier` toujours présent dans le
payload mais simplement plus lu côté client) suite au retour explicite "on n'a plus de
modifiers" : chaque ligne affiche désormais juste "Force : 16", etc.

**Équipement porté retiré de la fiche de personnage** : bloc `EquipmentTitle`/
`EquipmentContainer` (label + liste texte en lecture seule) supprimé de
`CharacterSheetWindow.tscn`/`.gd` — cette information vit maintenant uniquement dans
`EquipmentWindow` (slots interactifs, ajoutée dans une session précédente), la fiche de
personnage ne montre plus que nom/niveau/PV/mana/stats de combat/caractéristiques.

**Infobulles d'objets complètes** : `EquipmentSlot.set_item` prend désormais l'`Entry`
Inventory complet (`Dictionary`) plutôt que 3 chaînes extraites, et `InventoryWindow.
_build_row` construit la même infobulle enrichie sur l'icône (`DraggableIcon.tooltip_text`)
— nom (grade), type traduit (+ catégorie d'armure légère/moyenne/lourde entre parenthèses
pour une armure), ligne p.atk/m.atk/p.def/m.def (uniquement les valeurs non nulles), ligne
précision/esquive/critique/vit.atk (idem), niveau d'amélioration si > 0, description ;
zéro ligne de stats affichée pour un objet non équipable (potion, etc.), toutes valant 0
côté backend. `_item_tooltip`/`_signed` (formatage "+5"/"-2" — un "+%s" naïf produirait
"+-2" sur un bonus négatif, typiquement `evasionBonus` d'une armure lourde) dupliqués à
l'identique dans les deux fichiers (`EquipmentSlot.gd`/`InventoryWindow.gd`), même
convention que le reste du HUD (voir plus haut, "chaque fenêtre HUD reste un Control
autonome sans dépendance croisée").

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) : `mvn -o -q
compile` sur le backend (WSL) sans erreur ; côté client, une scène de test jetable (même
principe que les sessions précédentes, supprimée après usage) a injecté un `GameState.
player_stats`/`inventory` synthétiques (arme enchantée +5 avec bonus précision/critique/
vit.atk, armure avec `evasionBonus` négatif, potion sans stats), ouvert `CharacterSheet
Window`/`InventoryWindow`/`EquipmentWindow`, et affiché en sortie debug le texte exact de
chaque ligne (`AttributesContainer`, `CombatStatsLabel`) et de chaque tooltip construit —
confirmé caractère pour caractère (aucun "modifier", aucun bloc équipement, p.atk 285/
p.def 140 affichés correctement depuis les stats synthétiques, tooltip d'arme avec
"P.Atk +85" + bonus + "Amélioration : +5", tooltip d'armure avec "Armure (moyenne)" et
"Esquive -2" correctement signé, tooltip de potion sans ligne de stats). Une première
passe avait révélé "Armure (armure moyenne)" (redondant) et "Esquive +-2" (signe mal
formaté), corrigés puis revérifiés par une deuxième exécution. Capture d'écran réelle du
viewport également prise (même technique que les sessions précédentes,
`get_viewport().get_texture().get_image().save_png`) confirmant visuellement la mise en
page (fiche de personnage sans section équipement, fenêtre Équipement avec ses slots).
Scène de test et capture supprimées après usage. **Reste à confirmer par un humain, une
fois le backend redémarré avec ce changement et un vrai backend en conditions réelles** :
le contenu réel d'une infobulle au survol effectif de la souris (jamais simulé, seul le
texte `tooltip_text` a été vérifié) et qu'équiper une arme différente met bien à jour
p.atk/p.def en direct sous les yeux de l'utilisateur, fiche ouverte.

## Session du 2026-09-03 (suite) : sélection de soi-même via le cadre de vitaux, cast de
## Heal en jaune (animation de Wind Strike réutilisée)

Deux retours explicites : pouvoir se sélectionner soi-même en cliquant sur le cadre de
vitaux (`PlayerFrame`, haut-gauche) pour pouvoir lancer un sort comme Heal sur soi ; et,
pour l'animation d'incantation de Heal, réutiliser celle de Wind Strike mais en jaune (Heal
devient jaune, projectile/pulsation d'impact compris).

**Sélection de soi-même.** La capsule du joueur n'est pas cliquable en 3D
(`pickable=false` dans `_make_entity_node`, voir plus haut "Idem pour la sélection au clic
sur une capsule" — règle volontaire, on ne se sélectionne pas en cliquant sur son propre
personnage) : aucun moyen jusqu'ici de se cibler soi-même pour un sort de soin. Backend
revérifié (`app.network.command.ingame.Select`, WSL) : `select` résout n'importe quel
occupant de la carte courante par UUID (`findOccupantById`), nous y compris — aucun
changement serveur nécessaire, seulement envoyer notre propre UUID.

Nouveau signal `PlayerFrame.self_clicked` (`scenes/game/hud/PlayerFrame.gd`), émis par
`_on_panel_gui_input` sur clic gauche du sous-nœud `Panel`. Ce dernier passait jusqu'ici en
`mouse_filter=IGNORE` comme tout le reste du cadre (les clics traversaient donc entièrement
le panneau vers le monde 3D derrière, déclenchant un déplacement) : repassé en `STOP`
(`PlayerFrame.tscn`) pour intercepter le clic, plus un curseur "main" au survol
(`mouse_default_cursor_shape`). `Game3D._ready` connecte ce signal à
`_on_player_frame_self_clicked` (nouveau), qui envoie `select <notre UUID>`
(`GameState.player_stats.id`, même source que `_refresh_entities` pour notre propre
enregistrement) — le reste du flux de sélection (`TargetSelected` → `_apply_selection` →
`TargetStatusBar`/anneau de sélection) est entièrement générique et n'a nécessité aucune
autre modification.

**Cast de Heal en jaune, animation de Wind Strike réutilisée.**
`SKILL_VISUAL_COLOR_BY_KIND[SkillVisualKind.HEAL]` (couleur du projectile/de la pulsation
d'impact d'un sort de soin, voir `_play_skill_pulse`) passe de vert (0.55, 1.0, 0.6) à
jaune (1.0, 0.92, 0.35) — la même teinte que `SkillVisualKind.STORM` (Wind Strike).
`WIND_CAST_ANIMATION_SKILLS` (souffles tournoyants pendant l'incantation elle-même, voir
`_spawn_wind_wisp`/`_advance_casting`, jusqu'ici réservé à `"Wind Strike"`) gagne `"Heal"`.
Le souffle lui-même était jusqu'ici toujours coloré par la constante unique
`WIND_WISP_COLOR` (blanc-vert) : nouvelle table `WIND_WISP_COLOR_BY_SKILL` (`{"Heal":
Color(1.0, 0.92, 0.35, 0.65)}`, en override) + nom du sort désormais mémorisé dans l'état
d'incantation (`_casting_by_key[key]["skill_name"]`, ajouté dans `_on_skill_cast_started`)
pour que `_spawn_wind_wisp` sache quelle couleur choisir — Wind Strike garde sa couleur
d'origine (non demandé), seul Heal est recoloré.

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) via une scène de
test jetable (même principe que les sessions précédentes, supprimée après usage) instanciant
`Game.tscn` avec un UUID de joueur synthétique : (1) un événement de clic gauche synthétique
envoyé directement à `PlayerFrame._on_panel_gui_input` a bien fait remonter la chaîne
signal → `Game3D._on_player_frame_self_clicked` → `Net.send_command("select", ...)`, confirmé
par l'avertissement "pas connecté" de `Net.gd` qui reproduit l'argument exact envoyé
(`{"argument":"test-player-uuid-1234","verb":"select"}`, notre UUID synthétique) ; (2) un
`_on_skill_cast_started` synthétique avec `skillName="Heal"` suivi de plusieurs
`_advance_casting` a bien fait apparaître des souffles (`QuadMesh` sous `World`) à la couleur
`(1.0, 0.92, 0.35, ~0.63-0.65)` (alpha en cours de fondu via le tween existant, cohérent).
Aucune erreur dans la sortie debug (mêmes avertissements "pas connecté" habituels). **Reste
à confirmer par un humain, une fois un backend démarré** : le ressenti visuel réel (curseur
main au survol du cadre, clic qui sélectionne bien visuellement soi-même avec l'anneau de
sélection sous ses propres pieds et `TargetStatusBar` affichant son propre nom/PV) et le
rendu réel du sort Heal jaune (souffle + pulsation/projectile) en jeu.

## Session du 2026-09-03 (suite) : resynchronisation des .tmx depuis le backend

Demande explicite : les cartes ont changé côté backend, mettre à jour `data/maps/*.tmx`
(voir plus haut, "Ce qui est réutilisé tel quel du client 2D" — même procédure que
"Resynchroniser les fichiers de carte" documentée dans le CLAUDE.md du client 2D, appliquée
ici à ce projet). Comparaison fichier par fichier (`cmp`) entre `data/maps/` et
`mud-server-java/src/main/resources/data/maps/` (WSL) : 5 des 7 cartes différaient
(`Chemin_du_cimetière`, `Cimetière_abandonné`, `Clairière`, `Orée_de_la_forêt`,
`Repaire_sauvage`), `Place_du_village` et `Sentier_broussailleux` étaient déjà à jour.
Recopié tel quel (`cp .../data/maps/*.tmx data/maps/`), revérifié identique par un second
passage `cmp`. Changement notable : `Orée_de_la_forêt` est passée à 450×270 cases (bien
plus grande qu'avant, taille exacte antérieure non conservée puisque écrasée par la copie).

Aucun code n'a été touché — `ZoneAssets3D.gd`/`Game3D.gd` dérivent entièrement
largeur/hauteur/`walkableRows` du payload `MapView` envoyé par le serveur à chaque carte
(jamais des dimensions du `.tmx` local, voir `_rebuild_map`/`_rebuild_obstacles`) et
`obstacle_height_for` vérifie ses bornes avant de lire `terrain_grid[y][x]` : aucun risque
de plantage même si un `.tmx` local et le `MapView` serveur désaccordaient sur la taille.
Tous les noms de terrain (`<property name="terrain">`) des 5 fichiers mis à jour ont été
revérifiés présents dans `ZoneAssets3D.TERRAIN_COLORS` (aucun nouveau terrain introduit par
ce changement de cartes) — pas de case qui retomberait sur la couleur de repli
`WALKABLE_FALLBACK_COLOR`/`BLOCKED_FALLBACK_COLOR` faute de couleur dédiée.

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) :
`Login.tscn` (scène principale, charge les autoloads dont `ZoneAssets3D`, dont le `_ready()`
parse tous les `.tmx` de `data/maps/` sans condition) rechargé sans nouvelle erreur — preuve
que le XML des 5 fichiers resynchronisés est bien parsé sans exception par
`ZoneAssets3D._scan_map_files`. **Aucun test de rendu réel des cartes modifiées** (aucun
backend démarré ici pour pousser un vrai `MapView` sur l'une d'elles) : reste à confirmer
par un humain, une fois un backend démarré avec ces mêmes cartes, que le sol/les obstacles
s'affichent correctement sur les 5 cartes changées (en particulier `Orée_de_la_forêt`,
désormais nettement plus grande).

## Session du 2026-09-03 (suite) : gros bloc de mur sur Orée_de_la_forêt (artefact du
## redimensionnement Tiled), corrigé à la source

Retour explicite après la resynchronisation ci-dessus : un "gros bloc de mur" visible sur
`Orée_de_la_forêt` suite à son agrandissement. Analyse du calque `terrain` (CSV, 450×270) :
un cadre PARFAITEMENT uniforme de 4 cases d'épaisseur, tuile GID 1 (`tree`,
`walkable=false`, catégorie `TALL_OBSTACLE_TERRAINS` → 2.4 unité de haut côté rendu 3D) sur
tout le pourtour — les 4 premières/dernières lignes ET les 4 premières/dernières colonnes de
CHAQUE ligne, sans une seule exception sur les 270 lignes. Comparé à `Chemin_du_cimetière`,
`Cimetière_abandonné`, `Clairière`, `Repaire_sauvage`, `Place_du_village` et
`Sentier_broussailleux` (même analyse) : aucune de ces cartes n'a de ligne/colonne
entièrement solide en bordure — leurs contours sont irréguliers (forme organique). Un cadre
mathématiquement parfait sur toute une carte agrandie 3× est la signature typique d'un
redimensionnement de canvas dans Tiled Map Editor, qui remplit par défaut la zone ajoutée
avec la première tuile du tileset (ici GID 1 = `tree`, premier `<tile>` défini) — un
artefact de l'agrandissement, pas une intention de design.

**Vérifié que ce fichier est bien la seule source de vérité, y compris pour la règle de
jeu (pas seulement l'affichage)** : `TiledMapLoader.java` (`mud-server-java`, WSL) —
`parseTerrain` lit le même calque `terrain` du même `.tmx` pour construire le
`CollisionGrid` serveur (`walkable` par tuile, propriété custom du tileset), sans export
JSON intermédiaire ("c'est à la fois le fichier ouvert par Tiled Map Editor et la seule
source lue par le serveur", commentaire du fichier). Contrairement au reste du contenu de
`data/maps/*.tmx` dans CE projet (purement cosmétique, voir plus haut,
`MapView.grid.walkableRows` fait autorité) : ici, corriger uniquement la copie locale
aurait laissé un mur invisible mais toujours bloquant en jeu (le serveur aurait continué à
utiliser son propre exemplaire du fichier, inchangé). Un correctif à la source
(`mud-server-java/src/main/resources/data/maps/Orée_de_la_forêt.tmx`) était donc
nécessaire, en plus de la copie locale — confirmé explicitement par l'utilisateur avant
d'écrire hors de ce projet (écriture bloquée une première fois par le classifieur de
permissions du bac à sable, qui traite toute modification hors du répertoire de ce projet
comme une action à confirmer).

Correctif (script `awk`, vérifié avant application — voir ci-dessous) : le cadre de 4
cases est remplacé par la tuile GID 2 (`forestFloor`, `walkable=true`), qui domine déjà le
reste de la carte, en préservant strictement tout le reste (largeur de ligne inchangée,
450×270 fixes, arbres décoratifs de l'intérieur intacts — seules les 4 lignes/colonnes
strictement en bordure sont touchées, `ZoneAssets3D`/`TiledMapLoader` n'imposant aucune
bordure obligatoire par ailleurs). Réappliqué identique aux deux exemplaires du fichier
(`data/maps/` de ce projet ET `mud-server-java/src/main/resources/data/maps/`, `cmp`
confirmant les deux copies strictement identiques après coup) — même règle que la
resynchronisation habituelle, dans le sens inverse (source du changement ici, pas le
backend).

Vérifié avant toute écriture (analyse `awk` sur les 270 lignes du calque `terrain`) :
aucune ligne/colonne en dehors du cadre de 4 cases n'a été touchée (recherche de tout run
horizontal de tuiles `tree` > 15 cases en dehors des lignes de bordure : aucun résultat),
longueur de chaque ligne CSV inchangée (900 caractères avant/après, cadre y compris) ; puis
après écriture, plus aucune ligne/colonne entièrement solide. Revérifié avec
`mcp__godot__run_project` (disponible dans cet environnement) : `Login.tscn` (autoloads,
dont `ZoneAssets3D._scan_map_files` qui reparse tous les `.tmx`) rechargé sans nouvelle
erreur. **Build backend non revérifié par `mvn compile`** (un simple changement de fichier
de données, sans code Java touché, ce qui ne justifiait pas la vérification habituelle) —
`mvn spring-boot:run` doit être redémarré pour que le serveur recharge ce `.tmx` (comme
pour tout changement de carte, voir la resynchronisation ci-dessus). **Reste à confirmer
par un humain, une fois le backend redémarré** : que la bordure de trees remplacée par de
l'herbe rend bien la carte franchissable jusqu'au bord et visuellement propre (pas de reste
du bloc), sans effet de bord inattendu près des portails/spawns de cette carte (non
retouchés, calque `objects` inchangé).

## Session du 2026-09-03 (suite) : rotation de caméra au clic droit maintenu

Demande explicite : maintenir le clic droit pendant quelques millisecondes doit faire
basculer en mode "déplacement de caméra" permettant une rotation à 360° — jusqu'ici la
caméra isométrique était entièrement fixe (offset `(1,1,1)` normalisé, voir plus haut),
seul le zoom (molette) la faisait varier, en taille uniquement.

Le clic droit servait déjà à ouvrir le menu "Se téléporter" sur un portail déjà sélectionné
(`_handle_right_click`) : il fallait distinguer un clic bref (comportement inchangé) d'un
maintien (nouveau mode rotation) sans ambiguïté. `Game3D.gd` — `_start_right_click_hold`
(sur l'appui) arme juste un chronomètre (`_right_click_started_at_ms`) sans rien déclencher
tout de suite ; `_process` bascule `_camera_orbiting` à vrai dès que ce chronomètre dépasse
`CAMERA_ROTATE_HOLD_THRESHOLD_MS` (180 ms) tant que le bouton reste actif, et capture la
souris (`Input.mouse_mode = MOUSE_MODE_CAPTURED`, la cache et la recentre à chaque frame —
nécessaire pour un glisser de rotation illimité, sans buter sur les bords de l'écran) ;
`_end_right_click_hold` (sur le relâchement) n'appelle l'ancien `_handle_right_click`
(menu de téléportation) QUE si ce chronomètre n'a jamais atteint le seuil — sinon sort
juste du mode rotation et replace le curseur exactement là où le clic droit avait commencé
(`Input.warp_mouse`, mémorisé à l'appui) pour que la souris ne semble pas sauter à un
endroit arbitraire de l'écran une fois relâchée.

Pendant le mode rotation, chaque `InputEventMouseMotion` (interceptée dans
`_unhandled_input`, uniquement quand `_camera_orbiting`) avance `_camera_yaw` (angle cumulé
autour de l'axe Y, non borné — `fposmod(..., TAU)` le garde dans `[0, TAU)`, une rotation
à 360° et au-delà est donc bien possible en continuant de glisser) proportionnellement au
déplacement horizontal de la souris (`CAMERA_ROTATE_SENSITIVITY`, 0.01 rad/px — un tour
complet en ~628px de glisser), puis appelle `_apply_camera_orbit` (nouveau) : replace la
caméra sur le cercle horizontal dérivé de l'offset isométrique par défaut (rayon/hauteur
fixes, calculés depuis `Vector3.ONE.normalized() * CAMERA_DISTANCE`, seul l'angle autour de
l'axe Y varie) puis la réoriente vers `_camera_rig.global_position` (le pivot qui suit le
joueur). Cette réorientation explicite est nécessaire ici (contrairement à la simple
translation du rig à chaque frame côté `_process`, qui ne casse jamais l'orientation locale
existante de la caméra tant que l'offset ne change pas — argument déjà implicite dans le
code d'origine, qui ne rappelait `look_at` qu'une fois dans `_ready`) : tourner CHANGE
l'offset, donc la direction de visée doit être recalculée à chaque pas. `_apply_camera_orbit`
remplace aussi les deux lignes de positionnement d'origine dans `_ready` (angle par défaut,
`_camera_yaw=0` à l'initialisation) — aucun changement de comportement au repos, seule la
factorisation change. Le zoom (`_zoom_camera`, taille de la caméra orthogonale) reste
indépendant et continue de fonctionner pendant/après une rotation. Les barres de vie/
incantation flottantes (`_billboard_node`, alignées sur `_camera.global_transform.basis` à
chaque frame dans `_update_bars`) et tout le reste du rendu s'adaptent automatiquement à la
nouvelle orientation de caméra sans modification, n'ayant aucune dépendance à un angle de
caméra figé.

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) : `Game.tscn`
rechargé seul (sans réseau) sans nouvelle erreur (mêmes avertissements "pas connecté"
habituels), puis une scène de test jetable (même principe que les sessions précédentes,
supprimée après usage) instanciant `Game.tscn` et appelant directement
`_start_right_click_hold`/`_end_right_click_hold`/`_process`/`_unhandled_input` avec des
`InputEventMouseMotion` synthétiques a confirmé : un clic bref (appui puis relâchement
immédat, sans avancer le chronomètre) ne déclenche jamais le mode rotation
(`_camera_orbiting` reste faux, `Input.mouse_mode` reste `MOUSE_MODE_VISIBLE`) ; un maintien
au-delà du seuil bascule bien `_camera_orbiting` à vrai et `Input.mouse_mode` à
`MOUSE_MODE_CAPTURED` ; un mouvement de souris simulé pendant ce mode déplace la caméra sur
un cercle de rayon/hauteur strictement inchangés (mesuré : ~16.33/~11.55 avant et après) en
faisant varier l'angle ; faire avancer ce mouvement d'un tour complet (`TAU /
CAMERA_ROTATE_SENSITIVITY` pixels, lu dynamiquement depuis la constante du script pour éviter
toute valeur codée en dur dans le test) ramène la caméra quasiment exactement à sa position
précédente (rotation à 360° confirmée) ; relâcher le clic droit sort bien du mode rotation
(`_camera_orbiting` de nouveau faux) et restaure `MOUSE_MODE_VISIBLE`. Aucune régression sur
le clic droit bref (menu de téléportation), non testé explicitement ici mais dont le chemin
de code (`_handle_right_click`, appelé tel quel depuis `_end_right_click_hold` quand le
seuil n'a pas été atteint) est resté totalement inchangé. `HintLabel` (`Game.tscn`) mis à
jour pour mentionner le nouveau geste. **Reste à confirmer par un humain, une fois un
backend démarré** : le ressenti réel du glisser (vitesse de rotation, fluidité), que la
souris masquée/capturée pendant la rotation ne pose pas de souci particulier sous Windows
(comportement du curseur au retour), et qu'un clic droit bref sur un portail sélectionné
ouvre toujours bien le menu "Se téléporter" comme avant.

## Session du 2026-09-03 (suite) : retrait du glisser-déplacer, un clic = une demande de
## déplacement

Demande explicite : ne plus renvoyer de demande de déplacement en continu tant que le clic
gauche reste maintenu ("il faut refaire un clic pour renvoyer une demande de déplacement").
Depuis la création de ce prototype (voir plus haut, "Ce qui est nouveau"), maintenir le
clic gauche renvoyait un nouveau `goto` au plus 4x/s tant que la position visée changeait
(`_dragging_to_move`/`_try_send_goto_at_mouse(force)`/`DRAG_GOTO_RESEND_INTERVAL_MS`, même
ergonomie que le client 2D) — ce mécanisme est entièrement retiré ici, uniquement pour ce
client 3D (le 2D n'a pas été touché).

`_handle_left_click` envoie désormais un seul `goto` par clic (`_try_send_goto_at_mouse`,
simplifiée : plus de paramètre `force`/limite de fréquence/mémorisation de la dernière
cible envoyée) sans jamais armer de nouvel envoi tant que le bouton reste enfoncé.
Supprimés en conséquence : l'état `_dragging_to_move`/`_drag_last_sent_at_ms`/
`_drag_last_sent_target`, la constante `DRAG_GOTO_RESEND_INTERVAL_MS`, le bloc de
`_process` qui renvoyait `_try_send_goto_at_mouse(false)` tant que le bouton gauche restait
pressé, et les quelques `_dragging_to_move = false` disséminés (relâchement du clic,
sélection d'une entité/d'un portail, changement de carte) devenus sans objet. Aucun autre
comportement touché : la sélection au clic gauche (entité/portail) et le clic droit
(menu de téléportation/rotation de caméra, voir session précédente) sont restés inchangés.

Vérifié avec `mcp__godot__run_project` (disponible dans cet environnement) : `Game.tscn`
rechargé seul (sans réseau) sans nouvelle erreur (mêmes avertissements "pas connecté"
habituels), et une recherche projet entière confirmant qu'aucune référence aux identifiants
supprimés ne subsiste. `HintLabel` (`Game.tscn`) et le commentaire d'en-tête de
`Game3D.gd` mis à jour en conséquence. **Reste à confirmer par un humain, une fois un
backend démarré** : que maintenir le clic gauche enfoncé sans relâcher n'envoie plus qu'un
seul `goto` (le personnage s'arrête à la première destination même si le bouton reste
pressé), et qu'un nouveau clic pendant un déplacement en cours envoie bien un nouveau
`goto` vers la nouvelle destination (chemin de code inchangé, `_handle_left_click` reste
appelé à chaque clic).

## Session du 2026-09-03 (suite) : rotation de caméra inversée et lissée

Deux retours explicites sur la rotation de caméra ajoutée plus tôt cette session (clic
droit maintenu) : le sens paraissait inversé à l'usage, et le rendu jugé pas assez "smooth"
— jusqu'ici `_camera_yaw` sautait directement à la valeur calculée à chaque évènement
`InputEventMouseMotion` reçu (voir `_unhandled_input`), donc pixel pour pixel avec la
souris, sans aucune inertie.

**Inversion** : le signe appliqué au déplacement horizontal de la souris dans
`_unhandled_input` passe de `-` à `+` (`_camera_yaw_target = fposmod(_camera_yaw_target +
event.relative.x * CAMERA_ROTATE_SENSITIVITY, TAU)`).

**Lissage** : `_camera_yaw` (l'angle réellement utilisé par `_apply_camera_orbit`) et
`_camera_yaw_target` (l'angle brut, juste accumulé depuis la souris) sont désormais deux
variables séparées — la souris n'avance plus que la cible, sans plus jamais appeler
`_apply_camera_orbit` directement. Un nouveau bloc dans `_process` fait rattraper
`_camera_yaw` vers `_camera_yaw_target` chaque frame via `lerp_angle` (gère nativement le
passage 0/2π, indispensable puisque les deux angles sont contenus dans `[0, TAU)` via
`fposmod`) avec un poids `1 - exp(-CAMERA_ROTATE_SMOOTHING * delta)` — lissage exponentiel
indépendant du framerate (contrairement à un simple `delta * k`), nouvelle constante
`CAMERA_ROTATE_SMOOTHING := 14.0`. Ce rattrapage continue de tourner même après avoir
relâché le clic droit (le bloc n'est pas conditionné à `_camera_orbiting`) : un mouvement
rapide juste avant de relâcher se termine donc en douceur plutôt que de s'arrêter net,
sensation d'inertie légère non demandée explicitement mais cohérente avec "smooth" et sans
coût perceptible (le bloc ne fait rien dès que l'écart entre les deux angles devient
négligeable, `angle_difference(...) > 0.0005`).

Vérifié en CLI headless avec l'exécutable console (le MCP `mcp__godot__run_project`
utilisé pour toutes les vérifications précédentes de cette session s'est mis à retourner
"No active Godot process" immédiatement après lancement de la scène de test — cause non
investiguée, contournée en revenant à l'exécutable console documenté plus bas dans ce
fichier, `--headless res://scenes/_test_camera_orbit2.tscn --quit-after 5`, qui a fonctionné
sans accroc) : une scène de test jetable (même principe que les précédentes, supprimée après
usage) a placé `Game3D` en mode rotation, envoyé un `InputEventMouseMotion` synthétique
(`relative.x = 100`, positif) et confirmé (1) `_camera_yaw_target` devient positif (sens
inversé par rapport à avant ce correctif, où le même mouvement aurait produit une valeur
négative), (2) `_camera_yaw` (donc la caméra affichée) ne bouge PAS instantanément à ce même
appel — reste à 0.0 juste après l'évènement souris, (3) un seul pas de `_process(0.016)`
ne fait avancer `_camera_yaw` qu'à ~0.20 sur une cible de 1.0 (progression partielle, pas un
saut direct), (4) après 200 pas supplémentaires `_camera_yaw` converge bien à ~0.9995 (≈
cible). Aucune erreur dans la sortie debug (mêmes avertissements "pas connecté" habituels).
**Reste à confirmer par un humain** : le ressenti réel de la vitesse de lissage
(`CAMERA_ROTATE_SMOOTHING=14.0`, jamais éprouvé en conditions de jeu réelles) — à ajuster
si jugé trop mou ou pas assez.

**Réglage fin (même session, deux retours explicites après un essai réel)** : le délai de
maintien jugé trop long avant de basculer en rotation (`CAMERA_ROTATE_HOLD_THRESHOLD_MS`,
180 → 80 ms) et la rotation elle-même jugée trop rapide (`CAMERA_ROTATE_SENSITIVITY`, 0.01 →
0.004 rad/px, soit environ 2.5x plus lente pour un même glisser de souris) — simples
changements de constantes, aucune logique retouchée. Revérifié avec `mcp__godot__run_project`
(`Game.tscn` rechargé sans nouvelle erreur, mêmes avertissements "pas connecté" habituels) ;
pas de nouvelle scène de test jetable cette fois (changement de valeurs pures, déjà couvert
par les tests de comportement des sessions précédentes). **Reste à confirmer par un humain**
: ces deux nouvelles valeurs en conditions de jeu réelles — à raffiner encore si besoin.

## Session du 2026-09-03 (suite) : nouveau wallpaper "façon Lineage/Lineage2", survol de la
## liste de personnages mis en valeur

Deux retours explicites, tous deux sur les écrans hors-jeu (login/sélection) : une plus
belle image de fond ("typé Lineage/Lineage2") pour remplacer l'existante ; et, sur l'écran
de sélection de personnage, rendre visible la ligne survolée (contour + fond plus
prononcé), jusqu'ici un simple `HBoxContainer` sans aucun retour visuel au survol.

**Fond d'écran.** `UITheme.HERO_BACKDROP_PATH` (voir plus haut, "seule image téléchargée du
projet") pointait vers `Backgrounds/night_castle_moon.png` (975×1280, portrait) : remplacée
par `Backgrounds/castle_dragon_moon.jpg` (1280×633, paysage — château au clair de lune façon
Mont-Saint-Michel, dragon en vol au premier plan), 3 candidats parcourus sur Pixabay
(recherche "epic fantasy landscape castle") avant de choisir celui-ci pour son ambiance très
proche d'un écran de connexion Lineage 2 (château isolé, lune, silhouette de dragon).
Téléchargée avec l'accord explicite de l'utilisateur (source/nom de fichier/résolution/
licence présentés avant téléchargement, voir historique de conversation) :
`cdn.pixabay.com/photo/2018/03/02/20/38/fantasy-3194227_1280.jpg` — licence Pixabay Content
License (gratuite, aucune attribution requise, même régime que l'image qu'elle remplace),
auteur `jw432` sur Pixabay. Ancien fichier (`night_castle_moon.png` + son `.import`)
supprimé, aucune autre référence à son chemin dans le projet (uniquement lu via cette seule
constante). Aucun changement dans `Login.tscn`/`CharSelect.tscn`/`CharacterCreate.tscn` :
tous consomment `UITheme.get_hero_backdrop_texture()` (chargement paresseux, mis en cache),
donc un seul point de changement suffit.

**Survol de la liste de personnages.** `CharSelect._build_row` (seul générateur de lignes,
`CharSelect.tscn` ne contient que le `ScrollContainer`/`ListContainer` vide) enveloppe
désormais chaque ligne dans un `PanelContainer` (`mouse_filter = MOUSE_FILTER_PASS`, pour
laisser les boutons "Sélectionner"/"Supprimer" recevoir leurs clics normalement tout en
gardant le suivi de survol sur tout le rectangle de la ligne) dont le style
(`_row_style(hovered)`, nouveau) bascule sur `mouse_entered`/`mouse_exited` : transparent/
sans bordure au repos (pour ne pas alourdir visuellement la liste), fond éclairci
(`UITheme.BG_PANEL_LIGHT.lightened(0.12)`) + contour doré (`UITheme.BORDER_GOLD_BRIGHT`,
même couleur que les bordures de survol des boutons du thème global) + ombre légère au
survol. Aucun changement de mise en page/de logique de sélection/suppression, uniquement
l'ajout de ce conteneur autour du contenu déjà existant.

Vérifié avec l'exécutable console Godot en `--headless --editor --quit` (pour forcer la
réimportation du nouveau `.jpg`, sans quoi un chargement direct de scène échoue avec "No
loader found for resource", l'asset n'ayant pas encore de `.import` — piège déjà rencontré
pour `class_name` dans une session précédente, même cause : un lancement direct de scène ne
scanne pas les nouveaux fichiers) puis un lancement direct de `CharSelect.tscn`, sans
nouvelle erreur. `mcp__godot__run_project` s'est de nouveau mis à retourner "No active Godot
process" immédiatement après lancement (même symptôme que la session précédente sur la
rotation de caméra, cause toujours non investiguée) : contourné en revenant à l'exécutable
console documenté plus bas dans ce fichier. Une scène de test jetable (même principe que les
sessions précédentes, supprimée après usage) a instancié `CharSelect.tscn` avec une liste de
3 personnages synthétiques, capturé une image du viewport, simulé un survol de la 2e ligne
via un `InputEventMouseMotion` synthétique poussé par `get_viewport().push_input` (après
`Input.warp_mouse` sur le centre de la ligne, calculé via `get_global_rect()`), puis capturé
une seconde image : confirme visuellement (1) le nouveau fond (château/lune/dragon,
esthétique conforme à la demande) sur tout l'écran ; (2) la ligne "Lyra" seule surlignée
(fond éclairci + contour doré net) après le survol simulé, les deux autres lignes restant
inchangées. Scène de test et captures supprimées après usage. **Reste à confirmer par un
humain** : le ressenti réel du survol à la souris (jamais simulé autrement que par
l'événement synthétique ci-dessus) et l'aspect du nouveau fond sur les trois écrans
(login/sélection/création) en résolution d'écran réelle, plus large que celle capturée ici.

## Session du 2026-09-03 (suite) : spawn/respawn des monstres en temps réel (EntityAppeared/
## EntityDisappeared), suite au commit backend acfb970

Demande explicite : le spawn/respawn des monstres avait changé côté backend, il fallait une
notification en temps réel plutôt qu'au chargement de la carte ou du spawn du joueur.
Analyse du dernier commit backend (`mud-server-java`, WSL, HEAD = `acfb970`, "Fait de la
KnownList l'unique canal de présence des entités...") : `MonsterSpawned` (diffusé par
`MonsterRespawnEngine` à la KnownList d'un monstre qui réapparaît — déjà "temps réel" en un
sens, mais un canal DÉDIÉ au seul cas du respawn) est supprimé, tout comme les listes
`characters`/`monsters`/`npcs` de `MapEnter` (photo figée envoyée une fois au chargement) :
`KnownList.populate()` (spawn : création, sélection de personnage, portail, réapparition,
respawn de monstre) et `KnownList.refresh()` (après tout déplacement, joueur ou monstre)
poussent désormais uniformément `EntityAppeared`/`EntityDisappeared` (portée relevée de 25 à
40) à quiconque entre/sort de la portée de perception d'une entité — c'est désormais LE seul
canal par lequel ce client apprend qu'une entité existe sur la carte, respawn de monstre y
compris, en remplacement de `MonsterSpawned` ET des anciennes listes de `MapEnter`.

**Lacune de protocole trouvée et corrigée côté backend** (`EntityView.java`, WSL) : l'ancien
`MapEnter` distinguait joueur/PNJ/monstre par la liste d'origine (`characters`/`npcs`/
`monsters`), information perdue avec la liste unique `EntityAppeared.entities` — `EntityView`
(record partagé par `EntityAppeared`) ne portait qu'`id`/`name`/position/vitaux, sans aucun
discriminant de type, vérifié par lecture directe de la classe et de son unique site de
construction (`KnownList.java`). Sans ce champ, ce client n'aurait eu aucun moyen de choisir
la bonne couleur (bleu/vert/rouge/or, voir plus haut) pour une entité qu'il découvre pour la
première fois via ce message. Ajouté `EntityView.kind` (`"character"`/`"npc"`/`"monster"`,
calculé par `instanceof MonsterInstance`/`instanceof AbstractNpc` dans `EntityView.of()`) —
valeurs choisies pour correspondre telles quelles aux préfixes de clé déjà utilisés dans tout
`Game3D.gd` (`"character:<nom>"`/`"npc:<nom>"`/`"monster:<nom>"`, hérités de l'ancien système
à 3 listes), aucune table de traduction nécessaire côté client. Compilé avec succès (`mvn -o
-q compile`, aucune erreur, aucun autre site de construction d'`EntityView` à mettre à jour) ;
**serveur `mvn spring-boot:run` à redémarrer pour prendre en compte ce changement**, non fait
ici (pas de serveur tournant dans cet environnement) — un ancien backend non redémarré
enverrait un `EntityAppeared` sans `kind`, géré côté client par un repli sur `"character"`
(couleur joueur par défaut, dégradation gracieuse plutôt qu'un crash).

**`Game3D.gd`** : nouveaux cas `"EntityAppeared"`/`"EntityDisappeared"` dans
`_on_message_received`, remplaçant le cas `"MonsterSpawned"` retiré. `_apply_appeared_entity`
(nouveau) remplace à la fois l'ancienne `_apply_entity_entry` (bouclée sur les 3 listes de
`MapEnter`, ces listes n'existant plus) et `_on_monster_spawned` (supprimée, entièrement
redondante avec ce mécanisme générique) : résout la couleur depuis `kind`, préfère la clé déjà
connue pour cet UUID si elle existe (cas où `GamePlayerJoinedMap`, diffusion non scopée déjà
existante pour un vrai joueur qui rejoint, et l'`EntityAppeared` scopé issu de
`KnownList.populate()` pour ce même join arrivent tous deux pour la même entité — l'ordre côté
backend place `EntityAppeared` avant `GamePlayerJoinedMap`, mais peu importe lequel arrive en
premier, `_ensure_entity_node` est idempotent) sinon retombe sur `"<kind>:<nom>"`, même
convention de clé qu'avant. `_on_entity_disappeared` (nouveau) fait un simple
`_remove_entity` : le grisement/fondu de la mort d'un monstre reste porté par `MonsterDefeated`
(inchangé côté backend, toujours diffusé en plus de la `KnownList.clear()` qui déclenche
`EntityDisappeared` pour la même entité) — `_despawn_monster` a déjà retiré le nœud de
`_entities_by_key` au moment où `EntityDisappeared` arrive pour ce cas précis, donc
`_remove_entity` n'y fait jamais rien (idempotent, vérifié). `_refresh_entities` (MapEnter) ne
boucle plus sur des listes désormais absentes du payload ; ne gère plus que le repositionnement/
la ré-identification de notre propre personnage.

**`GameState.gd`** (autoload, jusqu'ici copié à l'identique du client 2D pour sa partie non
liée à l'XP — voir plus haut, correctif du 2026-09-03 sur les champs `xp_*` qui avait déjà
introduit une première divergence) : nouveau champ `appeared_entities` (`{id: payload
EntityView}`), même raison que `map_view`/`map_enter` déjà en cache — `KnownList.populate()`
côté backend, appelée par le `join()` qui précède l'envoi de `MapEnter`, peut pousser
`EntityAppeared` avant que `Game3D._ready()` n'existe pour s'y abonner directement (spawn/
sélection de personnage). Alimenté/nettoyé par les nouveaux cas `"EntityAppeared"`/
`"EntityDisappeared"` de `_on_message_received`. **Piège rencontré puis corrigé pendant la
vérification** : vider ce cache sur chaque nouveau `"MapView"` semblait naturel (nouvelle
carte ⇒ anciennes entités périmées) mais aurait en réalité effacé les entités de la carte de
DESTINATION qu'on vient tout juste de recevoir — vérifié dans le backend (`CharacterInstance.
moveToMap`/`MapInstance.join`/`Portal.java`/`CharacterSelect.java`) que l'ordre d'envoi est
toujours `EntityDisappeared` (ancienne carte, via `leave()`/`KnownList.clear()`) PUIS
`EntityAppeared` (nouvelle carte, via `join()`/`KnownList.populate()`) PUIS `MapView`/
`MapEnter` — donc vider explicitement sur `MapView` était non seulement inutile (les entités de
l'ancienne carte sont déjà proprement retirées via leurs propres `EntityDisappeared`) mais
activement néfaste. Retiré, `appeared_entities` ne se nettoie donc que par
`EntityDisappeared`, jamais par `MapView`. `Game3D._ready()` rejoue ce cache (après avoir
rejoué `map_view`/`map_enter` comme avant) via une boucle sur `appeared_entities.values()`.

Vérifié avec l'exécutable console Godot en `--headless` (`Game.tscn` rechargé seul, sans
réseau, sans nouvelle erreur — mêmes avertissements "pas connecté" habituels) puis par deux
scènes de test jetables (même principe que les sessions précédentes, supprimées après usage) :
la première a instancié `Game.tscn` avec un `GameState.player_stats`/`appeared_entities`
synthétiques (un monstre, un PNJ, un autre joueur, chacun avec un `kind` différent) et rejoué
le cache manuellement (pour simuler l'ordre réel où `EntityAppeared` précède l'existence de la
scène) — confirmé les 3 nœuds créés avec la bonne clé/couleur/vitaux, puis émis un
`EntityAppeared` EN COURS DE PARTIE (simulant un respawn réel) et vérifié que le monstre
apparaît immédiatement (`_entities_by_key.has(...)` vrai dès la frame suivante, sans attendre
un changement de carte), puis un `EntityDisappeared` et vérifié le retrait complet (nœud ET
`_key_by_entity_id`). La seconde scène a vérifié isolément la logique d'accumulation/nettoyage
de `GameState.appeared_entities` (deux `EntityAppeared` successifs s'accumulent, un
`EntityDisappeared` retire la bonne entrée, un `MapView` ne touche pas au cache). Aucune
erreur dans la sortie debug des deux scènes. **Reste à confirmer par un humain, une fois le
backend redémarré avec ce changement** : qu'un monstre qui réapparaît sur son point de spawn
devient bien visible en jeu sans attendre un changement de carte ou une reconnexion (le
scénario exact demandé), et que la portée de perception relevée à 40 (contre 25 avant ce
commit, valeur backend inchangée par cette session) ne semble pas trop courte ni trop longue à
l'usage réel.

## Session du 2026-09-03 (suite) : investigation "le Fox à (22,10) n'apparaît pas" — le
## serveur backend était simplement arrêté

Signalement explicite : un monstre "Fox" censé se trouver en (22.0, 10.0) restait invisible
en jeu. Vérifié qu'il s'agit du spawn `object id="4"` sur `Orée_de_la_forêt.tmx`
(`type="monsterSpawn"`, `x="704.0" y="320.0"` en pixels ÷ `tilewidth=32` = tuile (22,10)),
seul spawn de Fox à ces coordonnées exactes sur les 7 cartes (`Clairière.tmx` a bien un Fox
mais à la tuile (50,14)).

**Cause réelle : le process `mvn spring-boot:run` (WSL) ne tournait plus du tout** au moment
de l'investigation — confirmé par `ps aux`/`ss -ltnp` (aucun process Java, port 4002 fermé) et
par `logs/mud-server.log`, dont la dernière entrée était un "Graceful shutdown complete" à
13:22:15, juste après la déconnexion du personnage "Tata" (compte "tdel") à 13:22:12 — le
serveur s'est arrêté peu après que le joueur a quitté, sans aucun redémarrage depuis.

**Vérifications faites AVANT de conclure que c'était la seule cause** (le rapport
utilisateur laissait entendre qu'il jouait activement au moment du constat, donc le serveur
tournait peut-être encore à cet instant-là) :
- Relecture de `KnownList.occupantsWithin`/`populate`/`refresh` (voir session précédente sur
  `EntityAppeared`/`EntityDisappeared`) : la découverte d'une entité par un joueur ne dépend
  jamais d'un appel `populate()`/`refresh()` propre à CETTE entité — seulement de la position
  courante de tous les occupants de la carte au moment où LE JOUEUR appelle son propre
  `populate()`/`refresh()`. Un monstre placé au démarrage du serveur (`MonsterCatalog.
  placeMonsters`, jamais de `populate()` propre, contrairement à `MonsterRespawnEngine`) est
  donc bien découvert normalement dès qu'un joueur passe à moins de 40 tuiles (`AWARENESS_
  RANGE`), aucune régression trouvée à ce niveau.
- Rejeu de `logs/mud-server.log` pour la dernière session de "Tata" sur `Orée de la forêt`
  (13:21:07-13:22:12, avant l'arrêt) : `map.joined ... position=Position[x=20.55, y=21.54]`
  suivi immédiatement de `message.sent type=EntityAppeared` — le personnage a donc bien reçu
  un `EntityAppeared` dès son arrivée sur la carte, à une distance du Fox
  (√((22-20.55)²+(10-21.54)²) ≈ 11.6 tuiles) largement dans les 40 tuiles de portée. Impossible
  de confirmer le contenu exact de ce message précis (le log n'enregistre que le type, pas le
  payload), d'où le point suivant.
- Ajout d'un log permanent `monster.spawned name=... map=... position=... id=...` dans
  `MonsterCatalog.spawnMonster` (WSL, `mvn -o -q compile` sans erreur) — absent jusqu'ici,
  seul `monster.instances_placed count=N` (agrégé) existait pour le placement initial,
  contrairement à `MonsterRespawnEngine` qui logue déjà chaque respawn individuellement
  (`monster.respawned ...`) ; gardé en permanence (pas un log de debug jetable) pour la
  parité avec ce dernier et parce que ce type d'investigation ("tel monstre precise
  spawne-t-il vraiment ?") est visiblement amené à revenir.

**Serveur redémarré** (`mvn spring-boot:run`, WSL, arrière-plan) : le nouveau log confirme
sans ambiguïté `monster.spawned name=Fox map=Orée de la forêt position=Position[x=22.0,
y=10.0] id=86112fde-6ac2-3058-8320-dc817505d68f` parmi les 36 placements au démarrage — le
Fox est donc bien placé exactement là où l'utilisateur l'attendait. Combiné aux deux points
ci-dessus (mécanisme de découverte non régressé, `EntityAppeared` bien envoyé au bon moment
lors de la session précédente), la cause la plus probable du signalement reste l'arrêt du
serveur — **non re-testé en conditions réelles après ce redémarrage** (aucune tentative de
connexion via un vrai client dans cet environnement pour cette session précise, faute
d'identifiants du compte "tdel" ; une simulation par un compte de test via le protocole TCP
brut aurait nécessité de traverser plusieurs cartes/portails pour rejoindre `Orée de la
forêt` depuis la carte de départ `Place_du_village`, jugé disproportionné vu la force des
indices déjà réunis). **Reste à confirmer par l'utilisateur** : se reconnecter maintenant
(serveur tout juste redémarré) et vérifier que le Fox en (22,10) est bien visible en
approchant de cette zone sur `Orée de la forêt`.

**Suite (même session) : le redémarrage du serveur ne suffisait pas — capture d'écran
utilisateur montrant "Position : 21.3, 15.7" (à 5,7 tuiles du Fox, largement dans les 40 de
portée) sans AUCUN monstre visible sur `Orée de la forêt`, alors que le personnage venait de
se reconnecter.** Investigation poussée jusqu'à la preuve directe, cette fois avec identifiants
en main (compte de test `probe<timestamp>`/personnage `Probe36224` créés lors de la vérification
précédente, déjà positionnés sur `Orée de la forêt` près du Fox après un `portal` réel) :

- Ajout d'un log temporaire (`TcpJsonConnection.write`, retiré après usage) dumpant le JSON
  brut de chaque `EntityAppeared`/`EntityDisappeared` envoyé — confirmé : le Fox est bien
  présent tel quel dans le payload réel (`{"id":"8611...","name":"Fox","kind":"monster",
  "x":22.0,"y":10.0,...}`), `kind` bien sérialisé, aucun souci protocole/backend.
- Script Python jetable (`socket`, protocole JSON-lines brut, WSL — `register`/
  `character-create` MAN/FIGHTER/`Probe36224`/`goto`/`portal`) confirmant la même chose côté
  câble, depuis un client tiers indépendant de Godot.
- **Scène de test Godot jetée ensuite CETTE FOIS avec une vraie connexion réseau** (pas des
  évènements synthétiques comme les vérifications précédentes de cette session, jugées
  insuffisantes après ce nouveau signalement) : `Net.connect_to_server()` réel vers le
  backend tournant, `login`/`character-select "Probe36224"` réels, puis instanciation de
  `Game.tscn` exactement comme le ferait `CharSelect.gd` — `_entities_by_key` contient bien
  `"monster:Fox"` après réception du vrai `EntityAppeared` par le vrai `Net.gd`/`Game3D.gd`
  actuels. **Piège rencontré en écrivant ce test** : `--quit-after N` compte des ITÉRATIONS de
  boucle principale, pas des secondes — `--quit-after 25` tuait le process avant la fin des
  aller-retours réseau réels (contrairement aux tests synthétiques précédents, sans I/O
  réseau, qui terminaient en quelques frames) ; corrigé en passant `--quit-after 100000`.

**Conclusion : le code actuel (serveur ET client, fichiers sur disque à l'instant de cette
vérification) fonctionne bout-en-bout, prouvé par un test qui emprunte exactement le même
chemin qu'un vrai client (vraie socket, vrai `Net.gd`, vrai `Game3D.gd`, aucune simulation).**
La capture d'écran de l'utilisateur montrant néanmoins un plateau vide reste donc probablement
due à une instance Godot restée ouverte depuis AVANT les correctifs `EntityAppeared`/
`EntityDisappeared` de la session précédente (un script GDScript modifié sur disque n'est
repris que par un nouveau lancement — `F5`/Play — pas par une partie déjà en cours) : aucune
autre explication plausible n'a résisté à cette vérification. Log de debug JSON retiré après
usage (`TcpJsonConnection.java` revenu à son état d'avant cette investigation), serveur
recompilé et redémarré une dernière fois proprement. Compte/personnage de test
(`probe<timestamp>`/`Probe36224`) laissés tels quels dans `mud-server.db` (base de dev, déjà
d'autres comptes de test y trainent, voir `logs/mud-server.log` — `clitest000041`). **À
confirmer par l'utilisateur** : fermer complètement puis relancer une toute nouvelle partie
(pas juste se reconnecter dans une fenêtre Godot déjà ouverte) et vérifier à nouveau.

## Session du 2026-09-03 (suite) : fenêtre de respawn à la mort

Demande explicite : à la mort, une fenêtre doit proposer un bouton "Respawn" ; au clic,
envoyer `respawn` au serveur, puis se retrouver là où le serveur nous replace — jusqu'ici
la mort n'était que journalisée (`_log_player_defeated`, voir CLAUDE.md,
"Ce qui N'EST PAS dans ce prototype" avant cette session), sans aucun écran dédié,
contrairement au client 2D qui a déjà ce mécanisme (`DeathPopup.gd`/`.tscn`).

Backend revérifié (`app.network.command.ingame.Respawn`, WSL) : `respawn` ne prend aucun
argument, rejette avec `CharacterNotDead` si on n'est pas mort, sinon remet les PV à
maxHealth/4 (minimum 1)/la mana à 0 et téléporte vers le point d'apparition de la carte de
départ du monde (`WorldInstance.startingMapInstance()`, pas la carte où on est mort) —
`PlayerRespawned` (mapName/x/y/PV/mana) est envoyé, puis `MapView`/`MapEnter` (comme un
portail, la carte de départ pouvant différer de la carte de la mort) reconstruisent
entièrement la scène 3D : aucun code de repositionnement dédié n'était donc nécessaire ici,
le chemin générique `_rebuild_map`/`_refresh_entities` déjà utilisé par les portails s'en
charge automatiquement dès réception de ces deux messages, déjà envoyés par le serveur sans
changement de ce côté.

**`scenes/game/hud/DeathPopup.gd`/`.tscn`** (nouveau) : porté quasi verbatim de
`mud-godot/scenes/game/hud/DeathPopup.gd` (client 2D, seul écran de mort déjà existant dans
ce projet, voir plus haut) — `Control` plein écran (`ColorRect` d'assombrissement +
panneau centré, ce dernier laissé sans `StyleBoxFlat` dédié pour hériter du thème global
`UITheme.gd`, contrairement au 2D qui en avait un ; consistant avec le reste des fenêtres de
ce client 3D, voir `OptionsWindow.tscn`) avec titre "Vous êtes mort", nom du tueur (masqué
si vide) et bouton "Respawn" → `Net.send_command("respawn")` (bouton désactivé + texte
"Réapparition..." pendant l'attente, comme le 2D). N'hérite PAS de `WindowFrame` (pas de
croix de fermeture, pas dans la pile Échap, voir CLAUDE.md session précédente sur les
fenêtres HUD) : contrairement à l'inventaire/l'équipement/etc., cette fenêtre est modale et
ne doit pouvoir se fermer que via `PlayerRespawned`, jamais manuellement — même choix que le
2D. Elle-même ne s'abonne pas à `Net.message_received` (comme `TargetStatusBar.gd`),
entièrement pilotée par `Game3D.gd`.

**`Game3D.gd`** : `%DeathPopup` instancié dans `Game.tscn` sous `HUD` (après `PortalMenu`).
`"GamePlayerDefeated"` ouvre la popup (`_death_popup.open(killerName)`) en plus du log déjà
existant, uniquement quand `characterName` est le nôtre (même comparaison par nom que
`_log_player_defeated`, ce message ne porte pas d'UUID) ; `"PlayerRespawned"` la ferme en
plus de la mise à jour des PV déjà existante. Cas de reconnexion pendant qu'on est déjà mort
(`GamePlayerDefeated` manqué avant que la scène n'existe, `GameState.is_dead` alimenté aussi
par `GamePlayerStats` sur `currentHealth <= 0`) : `_ready()` rouvre la popup sans nom de
tueur si `GameState.is_dead` est vrai au chargement — même geste que `Game.gd` (2D). Aucun
changement à `GameState.gd` (le champ `is_dead` et son alimentation par
`GamePlayerStats`/`GamePlayerDefeated`/`PlayerRespawned` existaient déjà côté 3D, déjà
utilisés pour bloquer le déplacement au clic — voir `_unhandled_input`, inchangé).

Vérifié avec l'exécutable console Godot en `--headless` : `Game.tscn` rechargé sans nouvelle
erreur (mêmes avertissements "pas connecté" habituels). Une scène de test jetable (même
principe que les sessions précédentes, supprimée après usage) a instancié `Game.tscn` avec
un `GameState.player_stats` synthétique et émis de vrais signaux `Net.message_received`
(pas un appel direct à `_on_message_received`, même piège que documenté dans une session
précédente sur `GameState.gd`) : confirmé qu'un `GamePlayerDefeated` nous concernant ouvre
la popup avec le bon nom de tueur et passe `GameState.is_dead` à vrai ; qu'un
`GamePlayerDefeated` concernant un autre personnage ne l'ouvre pas ; qu'un clic sur
"Respawn" désactive le bouton, affiche "Réapparition...", et envoie bien `respawn` au
serveur (confirmé via l'avertissement "pas connecté" de `Net.gd`, qui reproduit l'argument
exact envoyé) ; qu'un `PlayerRespawned` ferme la popup et remet `GameState.is_dead` à faux ;
et que le cas de reconnexion (`GameState.is_dead = true` avant même l'instanciation de
`Game.tscn`) rouvre bien la popup sans nom de tueur dès `_ready()`. Scène de test supprimée
après usage. **Reste à confirmer par un humain, une fois un backend démarré** : le rendu
visuel réel de la popup (aucune capture d'écran prise cette fois) et que le personnage
apparaît effectivement au bon endroit (carte de départ du monde) après un clic sur
"Respawn" en conditions réelles — le mécanisme de reconstruction de carte
(`_rebuild_map`/`_refresh_entities` sur `MapView`/`MapEnter`) est le même que celui déjà
validé pour les portails, mais jamais exercé spécifiquement pour ce cas précis contre un
vrai backend.

## Session du 2026-09-03 (suite) : monstres invisibles — collision de clé entre monstres
## homonymes (deux Fox = un seul nœud visuel)

Signalement explicite : "les monstres ne s'affichent pas à l'écran". Reproduit par un test
de bout en bout avec une vraie connexion réseau (voir méthode ci-dessous) plutôt qu'une
simple relecture statique — la piste "serveur arrêté" (cause de l'investigation précédente
sur le Fox de `Orée_de_la_forêt`) a été écartée en premier : `mvn spring-boot:run` (WSL)
n'était en fait PAS lancé au moment du signalement non plus (dernier arrêt : 21:04:43, log
`mud-server.log`), redémarré avant tout test — mais un second test après redémarrage a
montré un vrai bug indépendant, documenté ici.

**Cause réelle : collision de clé dans `_entities_by_key`.** `_apply_appeared_entity`
(voir plus haut, session `EntityAppeared`/`EntityDisappeared` du même jour) dérivait la clé
d'un monstre/PNJ nouvellement vu comme `"<kind>:<nom>"` (ex. `"monster:Fox"`) dès que son
UUID n'était pas encore connu. Or contrairement à un nom de personnage (unique, contrainte
serveur à la création), un nom de monstre ne l'est PAS — plusieurs "Fox"/"Brown Keltir"/etc.
sont placés sur la même carte par `MonsterCatalog` (confirmé : `Orée de la forêt` a à elle
seule plusieurs Fox distincts). Deux monstres homonymes (UUID différents) retombaient donc
sur la MÊME clé `"monster:Fox"` : `_ensure_entity_node` voyait la clé déjà prise et
réutilisait le nœud du PREMIER Fox pour le second, dont la position écrasait celle du
premier — le nœud visuel se retrouvait téléporté à la position du second Fox (souvent loin
du joueur, hors champ de la caméra isométrique fixe), et le premier Fox restait sans aucun
nœud. Sur une carte avec plusieurs Fox, au mieux UN SEUL restait visible, et généralement
pas celui attendu près du joueur — d'où l'impression que "les monstres ne s'affichent pas".
Le commentaire déjà présent sur `_resolve_movement_key` (session précédente : "un nom de
monstre n'est pas unique, on résout d'abord par UUID") documentait déjà ce risque sans que
`_apply_appeared_entity`, le point d'entrée réel de tout nouveau monstre, ne le respecte.

**Corrigé** (`Game3D.gd`) : la clé n'est dérivée du nom que pour `kind == "character"`
(personnages, noms garantis uniques) ; pour `"monster"`/`"npc"`, elle est désormais
`"<kind>:<uuid>"`, garantissant un nœud distinct par instance quel que soit le nombre
d'homonymes. Effet de bord : `_despawn_monster` (appelé sur `MonsterDefeated`, qui ne porte
que le NOM du monstre côté backend — `app.network.message.ingame.MonsterDefeated`, aucun
UUID, vérifié à la source) cherchait jusqu'ici son nœud via `"monster:%s" % monster_name` —
recherche désormais par balayage de `_entities_by_key` (clés `"monster:*"`) comparé au nom
d'origine de l'entité. Ce nom ne peut plus être lu sur `node.name` (Godot renomme
silencieusement en `"Fox2"` un second enfant homonyme sous le même parent, confirmé en test)
— nouvelle meta `entity_name` posée sur chaque nœud dans `_make_entity_node`, jamais réécrite
par le moteur, utilisée à la place. Reste une ambiguïté résiduelle assumée (pas mieux
possible sans changement backend) : si DEUX Fox vivants meurent au même instant, ce balayage
prend le premier trouvé — cas limite jugé rare, `MonsterDefeated` ne portant de toute façon
aucun identifiant permettant de lever l'ambiguïté même côté backend actuel.

**Méthode de vérification — bout en bout avec une vraie connexion, pas une simulation**
(essentiel ici : le bug ne se manifeste qu'avec de VRAIS UUID serveur pour deux monstres
homonymes, impossible à faire apparaître avec des payloads synthétiques inventés à la
main comme les sessions précédentes) : scène de test jetable
(`scenes/_test_monster_visibility.tscn`/`.gd`, supprimée après usage) pilotant `Net.gd`
exactement comme le ferait un vrai client — connexion TCP réelle, `register`/
`character-create` (compte/personnage jetables), traversée du portail réel
`Place_du_village` → `Orée de la forêt` (`goto` vers la tuile du portail à (22.5, 67.5)
puis `portal`), puis `goto` vers les abords d'un spawn de Fox connu (56.5, 98.5,
`monster.spawned` en log serveur). Avant le correctif : capture d'écran réelle
(`get_viewport().get_texture().get_image().save_png`) montrant le joueur seul, aucun Fox
visible, malgré deux `EntityAppeared` de type `monster`/`Fox` bien reçus (confirmé par
inspection directe de `Game3D._entities_by_key` depuis le test : une seule clé
`"monster:Fox"`, positionnée à (14.5, 98.5) — la position du SECOND Fox alors que le
joueur se trouvait à (50, 92), donc hors caméra). Après correctif : même scénario,
`_entities_by_key` contient bien deux clés distinctes par UUID à leurs positions
respectives (56.5,98.5) et (14.5,98.5), capture d'écran confirmant la capsule rouge "Fox"
visible à côté du joueur avec sa barre de vie. Serveur `mvn spring-boot:run` (WSL) laissé
tournant après cette session (redémarré en début d'investigation) ; compte/personnage de
test (`monstertest<timestamp>`/`Zog<suffixe>`) laissés dans `mud-server.db`, même
convention que les comptes `probe*`/`clitest*` déjà présents (base de dev).

## Lancer le projet

Même backend que le client 2D (`mud-server-java`, `mvn spring-boot:run`, port 4002 — voir
son propre CLAUDE.md). Ouvrir `mud-godot-3d/` dans Godot 4.7 (scène principale
`res://scenes/login/Login.tscn`, identique au client 2D) et lancer le projet.

## Exécutable Godot disponible dans cet environnement

**Correctif de cette section (2026-09-03, reconstaté puis corrigé — voir la note laissée
plus haut dans une session précédente)** :
`C:\Users\thoma\Downloads\Godot_v4.7.2-stable_win64.exe` n'est PAS l'exécutable — c'est un
DOSSIER (confirmé via `ls`) contenant le vrai éditeur GUI
(`Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`) et sa variante console
(`Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` — même build, mais
avec une fenêtre console attachée, stdout/stderr visibles directement, utile en
`--headless`/`--check-only`/tests CLI plutôt que de devoir lire les logs après coup). Un
second exécutable console existe aussi directement sous `Downloads\` (hors de ce dossier,
`Downloads\Godot_v4.7.2-stable_win64_console.exe`) mais échoue immédiatement ("Main
executable ... not found") car il cherche son GUI compagnon au même niveau, absent à cet
endroit — utiliser systématiquement celui à l'intérieur du dossier
`Godot_v4.7.2-stable_win64.exe\`. Ex. `&
"C:\Users\thoma\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
--path C:\Users\thoma\Documents\workspace\mud-godot-3d --headless --quit` pour un simple
import/check de scripts (PowerShell — le tool Bash de cet environnement, git-bash, échoue
aussi sur ce chemin avec le même message "Main executable ... not found", cause non
creusée). Préférer l'outil MCP Godot (`mcp__godot__*`) quand il est connecté (voir
"Vérifié dans cet environnement" ci-dessus, qui documente son usage lors d'une session
précédente) ; ces exécutables sont le repli quand le MCP n'est pas disponible ou pour des
vérifications ponctuelles en CLI.

## Session du 2026-09-03 (suite) : passage au moteur de rendu Forward+

Demande explicite : passer ce prototype sous Forward+ "pour bénéficier d'un moteur plus
récent" — le projet avait été créé le 2026-09-02 en `gl_compatibility` (`config/features`
portait le tag `"GL Compatibility"`, `renderer/rendering_method`/`.mobile` valaient tous
deux `"gl_compatibility"` dans `project.godot`), sans qu'aucune session précédente
n'explique ce choix initial ni n'utilise de fonctionnalité spécifique à ce mode de rendu
(aucun `render_mode`/`shader_type` propre à la compatibilité trouvé dans le projet, voir
ci-dessous).

**`project.godot`** : les deux clés `renderer/rendering_method`/`renderer/rendering_method.
mobile` (valant `"gl_compatibility"`) ont été retirées entièrement plutôt que remplacées
par `"forward_plus"` explicite — `forward_plus` est la valeur par défaut du moteur en leur
absence (aussi bien pour la base que pour l'override mobile, qui retombe par défaut sur
`"mobile"`, non pertinent ici, ce prototype ne visant que le bureau), donc équivalent mais
plus proche de ce qu'un nouveau projet Godot 4 généré directement en Forward+ contient
réellement (aucune de ces deux clés n'y figure). `config/features` perd le tag `"GL
Compatibility"` (ne garde que `"4.7"`) pour la même raison — Forward+, étant la valeur par
défaut, n'ajoute lui-même aucun tag de renderer dans un projet neuf. `rendering_device/
driver.windows="d3d12"` (choix du driver RenderingDevice, Vulkan/D3D12/Metal) laissé
inchangé : ignoré par le mode `gl_compatibility` (qui n'utilise pas RenderingDevice) mais
redevient effectivement utilisé maintenant que le projet tourne en Forward+, sans qu'aucun
changement n'ait été nécessaire de ce côté.

**Recherche de code dépendant du mode de rendu** : seul point trouvé dans tout le projet,
le shader `ROUNDED_BAR_SHADER_CODE` de la barre de cast en pilule (voir session précédente
sur cette barre, plus haut) — `shader_type spatial; render_mode unshaded, cull_disabled,
depth_test_disabled, blend_mix, specular_disabled;`, un shader spatial non éclairé
utilisant une SDF, sans construction propre à un backend de rendu particulier. Fonctionne à
l'identique sous Forward+ (revérifié ci-dessous). Aucune autre occurrence de `shader_type`/
`render_mode`/référence explicite à "GLES"/"Compatibility" dans le projet.

Vérifié avec l'exécutable console Godot (voir correctif de chemin ci-dessus) en
`--headless res://scenes/game/Game.tscn --quit-after 30` : aucune nouvelle erreur (mêmes
avertissements "pas connecté" habituels, `Net.gd`/`Game3D._ready` qui tentent `stats`/
`skills` sans serveur). Puis avec `mcp__godot__run_project` (rendu réel, contexte GPU
complet plutôt que headless) : sortie de démarrage confirmant explicitement `D3D12 12_0 -
Forward+ - Using Device #0: AMD - AMD Radeon RX 6800 XT` sans aucune erreur avant l'arrêt du
projet. **Aucune capture d'écran comparative avant/après prise** (le changement ne touche
qu'un paramètre moteur, pas de régression visuelle attendue vu l'absence de code spécifique
à `gl_compatibility` trouvé ci-dessus) — reste à confirmer par un humain : le rendu réel en
jeu (ombres/éclairage/matériaux, notamment la barre de cast en pilule et les capsules
d'entités) une fois un backend démarré, Forward+ pouvant légèrement différer visuellement
de la compatibilité (éclairage indirect/nombre de lumières simultanées notamment, sans
impact connu ici vu le rendu volontairement simple de ce prototype — capsules colorées,
sol peint, pas de lumières dynamiques multiples).
