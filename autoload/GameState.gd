extends Node
## État de session, gardé uniquement en mémoire (jamais persisté sur disque).
## Vidé à chaque déconnexion (voir clear_session()).

## Login du compte courant, utilisé pour préremplir l'écran de login lors de
## "changer de personnage".
var current_login := ""

## Dernière CharacterList reçue: Array[Dictionary] {name, race, characterClass, level}.
var character_list: Array = []

## Dernier GamePlayerStats.payload reçu (fiche de personnage complète).
var player_stats: Dictionary = {}

## Dernier MapView.payload reçu (carte statique de la carte courante — message renommé
## depuis ZoneMap par le commit backend "Renomme le concept Zone en Map dans tout le
## projet", 2026-08-30, voir CLAUDE.md).
var map_view: Dictionary = {}

## Dernier MapEnter.payload reçu (photo des entités connues à l'entrée en carte — renommé
## depuis ViewAround puis ZoneEnter par les commits backend "Diffuse les actions selon une
## portée de perception (KnownList)" (2026-08-29) puis "Renomme le concept Zone en Map dans
## tout le projet" (2026-08-30), voir CLAUDE.md — liste désormais TOUS les occupants de la
## carte depuis le correctif "sélection non restreinte par la portée" du 2026-08-30). Les
## arrivées/départs ultérieurs en cours de partie (sans changement de carte réel)
## arrivent par GamePlayerJoinedMap/GamePlayerLeftMap/MonsterSpawned/MonsterDefeated, pas
## par un MapEnter répété — ce cache n'est donc rafraîchi qu'au chargement de carte
## (portail/connexion/respawn), pas en continu.
##
## Depuis le commit backend acfb970 (2026-09-03, "Fait de la KnownList l'unique canal de
## présence des entités") : ce payload ne liste plus lui-même les occupants de la carte
## (champs characters/npcs/monsters retirés) — ils arrivent séparément via EntityAppeared,
## voir appeared_entities ci-dessous. Ajout propre à ce client 3D, jamais porté côté 2D (qui
## n'a pas encore adopté ce commit backend, voir CLAUDE.md) : ce fichier n'est donc plus une
## copie strictement identique à celui du 2D depuis les champs xp_*/current_mana ci-dessus.
var map_enter: Dictionary = {}

## Dernières entités connues (à portée de KnownList), indexées par UUID — même raison de
## cache que map_view/map_enter ci-dessus : KnownList.populate() côté backend, appelé au
## join qui précède l'envoi de MapEnter (voir CharacterSelect/CharacterCreate/Portal/
## Respawn), peut pousser EntityAppeared avant que la scène de jeu n'existe pour s'y
## abonner directement (Game3D._ready). PAS vidé sur un nouveau MapView (contrairement à ce
## qu'on pourrait attendre) : un changement de carte fait passer par
## MapInstance.leave()-puis-join() côté backend, donc par EntityDisappeared (toutes les
## entités de l'ancienne carte, traité ci-dessous) PUIS EntityAppeared (celles de la
## nouvelle) AVANT MapView/MapEnter — vider ici sur MapView effacerait justement les
## entités de la nouvelle carte qu'on vient de recevoir. Dictionnaire {id: payload
## EntityView} plutôt qu'un array pour dédupliquer une même entité annoncée deux fois.
var appeared_entities: Dictionary = {}

## Groupe (party) courant, {} si on n'est dans aucun groupe. Sinon :
## {leader_id: String, members: {id: {name, current_health, max_health, current_mana,
## max_mana}}, loot_mode: String ("RANDOM"/"ROUND_ROBIN")}. `members` exclut volontairement
## notre propre personnage : nos propres PV/mana sont déjà tenus à jour ailleurs
## (player_stats/current_mana/max_mana) et dupliquer cette source ici la ferait diverger
## dès la prochaine regen/dégât — PartyPanel.gd affiche sa propre ligne à partir de ces
## champs plutôt que de members. Alimenté par PartyJoined/PartyMemberJoined (voir
## CLAUDE.md, correctif backend "PartyJoined.members"/"PartyMemberJoined vitaux" — sans lui
## un joueur qui rejoint un groupe de 3+ n'apprendrait que le leader).
var party: Dictionary = {}

## Dernier Inventory.payload reçu: {items: Array[{name, grade, slot, type, quantity, ...}],
## gold: int} — grade (ex-rarity, voir CLAUDE.md) : enum ItemGrade NOGRADE/D/C/B/A/S.
## `quantity` (2026-09-04, commit backend "Ajoute le système soulshot/spiritshot") vaut 1
## pour tout objet normal, la taille du stack pour un ItemType stackable (SOULSHOT/
## SPIRITSHOT pour l'instant, voir ItemType.stackable() côté backend).
var inventory: Dictionary = {}

## Dernier KnownSkills.payload reçu (ex-KnownSpells, renommé par le commit backend "Unifie
## sorts/passifs sous SkillSystem", voir CLAUDE.md) : {skills: Array[{name, level, description,
## manaCost, cooldownSeconds, range, skillType, durationSeconds, granted}]} — `level`/
## `skillType` étaient encore `tier`/`effect` jusqu'à un commit backend ultérieur (2026-09-02),
## qui avait été jugé hors de portée du prototype 3D à tort : Hotbar.gd/SkillBook.gd lisaient
## bel et bien ces deux champs pour l'infobulle/la liste de sorts (retombaient silencieusement
## sur "?"/vide, jamais d'erreur) — corrigé à cette date, voir CLAUDE.md.
var known_skills: Dictionary = {}

## Mana courante/max du joueur, tenue à jour ici plutôt que dans chaque écran qui en a
## besoin (PlayerStatusBars pour l'affichage, Hotbar pour griser les sorts trop coûteux).
## Alimentée directement par les champs casterCurrentMana/casterMaxMana ajoutés côté
## backend à CastResult/SkillModifierAnnounced (2026-08-27) : plus de prédiction locale à
## partir du manaCost du sort, la valeur vient désormais du serveur au moment même du cast.
var current_mana := 0
var max_mana := 0

## XP cumulée du personnage + seuils du niveau courant/suivant (voir GamePlayerStats.Payload/
## XpGained côté backend, champs ajoutés le 2026-09-03 pour la barre d'XP du HUD — absents du
## protocole jusque-là, ni l'un ni l'autre client n'en avait besoin auparavant).
## `xp_for_next_level <= xp_for_current_level` au niveau maximum (voir LevelCatalog côté
## backend) : PlayerFrame.set_xp affiche alors une barre pleine plutôt que de diviser par
## zéro. Même principe que current_mana/max_mana ci-dessus : tenu à jour ici plutôt que dans
## chaque écran (Game3D.gd pour le HUD), alimenté par GamePlayerStats (fiche complète) et
## XpGained (mise à jour en direct sans attendre un "stats").
var xp := 0
var xp_for_current_level := 0
var xp_for_next_level := 0

## Grade actuellement armé (auto-use) pour chaque type de charge — "" si désactivé, sinon
## "NOGRADE"/"D"/"C"/"B"/"A"/"S" (voir app.domain.item.ItemGrade côté backend, commit "Ajoute
## le système soulshot/spiritshot" du 2026-09-04). Alimenté par GamePlayerStats (état persisté,
## utile à la reconnexion — voir CLAUDE.md, champs activeSoulshotGrade/activeSpiritshotGrade
## ajoutés côté backend pour ce client), ShotGradeChanged (toggle confirmé) et ShotOutOfStock
## (le serveur désactive lui-même la charge épuisée). Lu par Hotbar.gd/InventoryWindow.gd pour
## savoir quelle ligne/quel slot surligner comme "actif".
var active_soulshot_grade := ""
var active_spiritshot_grade := ""

## Vrai si notre personnage est mort (PV à 0, voir CharacterInstance.takeDamage/
## GamePlayerDied côté backend). Alimenté par GamePlayerStats (reconnexion pendant qu'on
## est déjà mort), GamePlayerDefeated (mort en direct, diffusé à toute la zone — ne
## concerne notre état que si characterName est le nôtre, ce message ne porte pas d'UUID)
## et remis à faux par PlayerRespawned. Lu par Game.gd (bloque le déplacement au clic) et
## Hotbar.gd (bloque F1-F12) pour anticiper le rejet CharacterIsDead que le serveur
## renverrait de toute façon (voir CommandDispatcher côté backend) plutôt que d'attendre
## l'aller-retour réseau.
var is_dead := false

## Message à afficher une seule fois sur l'écran de login (ex. déconnexion serveur
## survenue en cours de jeu) — posé par l'écran qui détecte la coupure, consommé et vidé
## par Login.gd à l'affichage.
var pending_disconnect_message := ""


func _ready() -> void:
	# GameState est un autoload toujours vivant : il met en cache les messages serveur
	# indépendamment de la scène active, pour éviter de perdre un MapView/GamePlayerStats
	# poussé par le serveur pile pendant une transition de scène (ex. character-select).
	Net.message_received.connect(_on_message_received)


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"CharacterList":
			character_list = payload.get("characters", [])
		"NoCharacters":
			character_list = []
		"GamePlayerStats":
			player_stats = payload
			current_mana = int(payload.get("currentMana", current_mana))
			max_mana = int(payload.get("maxMana", max_mana))
			xp = int(payload.get("xp", xp))
			xp_for_current_level = int(payload.get("xpForCurrentLevel", xp_for_current_level))
			xp_for_next_level = int(payload.get("xpForNextLevel", xp_for_next_level))
			is_dead = int(payload.get("currentHealth", 0)) <= 0
			var soulshot_grade = payload.get("activeSoulshotGrade")
			active_soulshot_grade = str(soulshot_grade) if soulshot_grade != null else ""
			var spiritshot_grade = payload.get("activeSpiritshotGrade")
			active_spiritshot_grade = str(spiritshot_grade) if spiritshot_grade != null else ""
		"GamePlayerDefeated":
			if str(payload.get("characterName", "")) == str(player_stats.get("name", "")):
				is_dead = true
		"PlayerRespawned":
			is_dead = false
			current_mana = int(payload.get("currentMana", current_mana))
			max_mana = int(payload.get("maxMana", max_mana))
		"MapView":
			map_view = payload
		"MapEnter":
			map_enter = payload
		"EntityAppeared":
			for entry in payload.get("entities", []):
				var entity_id := str(entry.get("id", ""))
				if not entity_id.is_empty():
					appeared_entities[entity_id] = entry
		"EntityDisappeared":
			for entity_id in payload.get("entityIds", []):
				appeared_entities.erase(str(entity_id))
		"Inventory":
			inventory = payload
		"KnownSkills":
			known_skills = payload
		"ShotGradeChanged":
			# grade == null : l'auto-use vient d'être désactivé pour cette catégorie (voir
			# Soulshot.java/Spiritshot.java côté backend, "off" ou re-toggle de la même
			# grade déjà active).
			var changed_grade = payload.get("grade")
			var changed_grade_str := str(changed_grade) if changed_grade != null else ""
			if str(payload.get("shotType", "")) == "SOULSHOT":
				active_soulshot_grade = changed_grade_str
			elif str(payload.get("shotType", "")) == "SPIRITSHOT":
				active_spiritshot_grade = changed_grade_str
		"ShotOutOfStock":
			# Le serveur désactive lui-même la charge côté personnage (voir
			# CharacterPersistenceListener.onShotGradeDepleted) : reflété ici plutôt que
			# d'attendre un GamePlayerStats/ShotGradeChanged qui ne viendra pas spontanément.
			if str(payload.get("shotType", "")) == "SOULSHOT":
				active_soulshot_grade = ""
			elif str(payload.get("shotType", "")) == "SPIRITSHOT":
				active_spiritshot_grade = ""
		"RegenTick", "ManaPotionUsed":
			current_mana = int(payload.get("currentMana", current_mana))
			max_mana = int(payload.get("maxMana", max_mana))
		"XpGained":
			xp = int(payload.get("xp", xp))
			xp_for_current_level = int(payload.get("xpForCurrentLevel", xp_for_current_level))
			xp_for_next_level = int(payload.get("xpForNextLevel", xp_for_next_level))
		"CastResult":
			# Envoyé uniquement au lanceur : casterCurrentMana/casterMaxMana décrivent donc
			# toujours notre propre mana après déduction côté serveur.
			current_mana = int(payload.get("casterCurrentMana", current_mana))
			max_mana = int(payload.get("casterMaxMana", max_mana))
		"SkillModifierAnnounced":
			# BUFF/DEBUFF n'ont pas de CastResult dédié au lanceur : uniquement ce broadcast
			# de zone, reçu par tout le monde — on ne s'applique la mana que si c'est notre
			# sort. Ciblé par UUID (casterId, voir CLAUDE.md/commit backend "Cible les
			# commandes réseau par UUID au lieu du nom") plutôt que par nom, fragile en cas
			# d'homonymie.
			if str(payload.get("casterId", "")) == str(player_stats.get("id", "")):
				current_mana = int(payload.get("casterCurrentMana", current_mana))
				max_mana = int(payload.get("casterMaxMana", max_mana))
		"PartyJoined":
			# Réponse à "party-accept" : `members` liste les membres déjà présents (leader
			# compris, nous exclus, voir CLAUDE.md/correctif backend "PartyJoined.members")
			# avec leurs vitaux — sans ça on n'apprendrait que le leader (leaderId/leaderName)
			# et ignorerait l'identité des autres membres d'un groupe de 3+.
			var joined_members := {}
			for member in payload.get("members", []):
				var member_id := str(member.get("id", ""))
				if member_id.is_empty():
					continue
				joined_members[member_id] = _member_vitals(member)
			party = {
				"leader_id": str(payload.get("leaderId", "")), "members": joined_members,
				"loot_mode": "ROUND_ROBIN",
			}
		"PartyMemberJoined":
			# Diffusé aux membres déjà présents quand quelqu'un rejoint le groupe. Peut être
			# le tout premier signal qu'un groupe existe de notre point de vue : le leader qui
			# vient d'inviter (PartyInvite.java attache déjà son personnage à une Party dès
			# l'envoi de l'invitation, avant toute acceptation) ne reçoit aucune confirmation
			# explicite avant ce message.
			if party.is_empty():
				party = {"leader_id": str(player_stats.get("id", "")), "members": {}, "loot_mode": "ROUND_ROBIN"}
			var joined_id := str(payload.get("memberId", ""))
			if not joined_id.is_empty():
				party.members[joined_id] = _member_vitals({
					"name": payload.get("memberName", ""), "currentHealth": payload.get("currentHealth", 0),
					"maxHealth": payload.get("maxHealth", 0), "currentMana": payload.get("currentMana", 0),
					"maxMana": payload.get("maxMana", 0),
				})
		"PartyMemberVitalsUpdated":
			# Ne concerne jamais notre propre personnage (broadcastVitalsToParty côté backend
			# nous exclut nous-même, voir CLAUDE.md) : members ne contient de toute façon pas
			# notre propre entrée (voir la doc de `party` plus haut).
			if not party.is_empty():
				var vitals_id := str(payload.get("characterId", ""))
				if party.members.has(vitals_id):
					party.members[vitals_id] = _member_vitals({
						"name": party.members[vitals_id].name, "currentHealth": payload.get("currentHealth", 0),
						"maxHealth": payload.get("maxHealth", 0), "currentMana": payload.get("currentMana", 0),
						"maxMana": payload.get("maxMana", 0),
					})
		"PartyMemberLeft":
			# Pas d'UUID sur ce message (voir CLAUDE.md) : recherche par nom, seule clé
			# disponible. Un groupe réduit à nous seul n'a plus rien à gérer (pas de
			# différence visible avec "pas de groupe" côté protocole, voir la doc de `party`
			# plus haut) : on l'efface plutôt que de garder un groupe fantôme d'un membre.
			if not party.is_empty():
				var left_name := str(payload.get("memberName", ""))
				for member_id in party.members.keys():
					if str(party.members[member_id].name) == left_name:
						party.members.erase(member_id)
						break
				if party.members.is_empty():
					party = {}
		"PartyMemberKicked":
			if not party.is_empty():
				party.members.erase(str(payload.get("targetId", "")))
				if party.members.is_empty():
					party = {}
		"KickedFromParty", "PartyDisbanded", "PartyLeft":
			party = {}
		"NewPartyLeader":
			if not party.is_empty():
				party.leader_id = str(payload.get("leaderId", ""))
		"PartyLootModeChanged":
			if not party.is_empty():
				party.loot_mode = str(payload.get("lootMode", party.loot_mode))
		_:
			pass


func _member_vitals(member: Dictionary) -> Dictionary:
	return {
		"name": str(member.get("name", "")), "current_health": int(member.get("currentHealth", 0)),
		"max_health": int(member.get("maxHealth", 0)), "current_mana": int(member.get("currentMana", 0)),
		"max_mana": int(member.get("maxMana", 0)),
	}


func clear_session() -> void:
	current_login = ""
	character_list = []
	player_stats = {}
	map_view = {}
	map_enter = {}
	appeared_entities = {}
	inventory = {}
	known_skills = {}
	current_mana = 0
	max_mana = 0
	xp = 0
	xp_for_current_level = 0
	xp_for_next_level = 0
	is_dead = false
	party = {}
	active_soulshot_grade = ""
	active_spiritshot_grade = ""
