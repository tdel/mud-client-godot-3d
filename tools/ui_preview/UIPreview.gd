extends Node
## Outil de développement (hors jeu) : charge un écran avec des données factices, sans
## serveur, puis enregistre une capture PNG et quitte. Sert à vérifier visuellement l'UI.
##
## Usage :
##   Godot_console.exe --path . res://tools/ui_preview/UIPreview.tscn -- --shot=game --out=C:/tmp/game.png
## Scénarios : login, charselect, create, game, game_select_self, game_select_party, game_party[_menu],
## game_party_invite, game_invite_button, game_windows, game_2h, game_shop, game_misc, game_death, game_options[_sound|_system], game_worldmap, loading.
## game_worldmap accepte --map=<nom de carte> (autre carte que la Place du village) et
## --map-size=LxH (taille du parchemin, pour vérifier le redimensionnement).
## Suffixe _menu sur login/charselect/create : ouvre le Menu système hors jeu (SystemMenu).
##
## user://hotbar.cfg est sauvegardé puis restauré tel quel : la hotbar écrit sa config pour le
## personnage factice au chargement, ce qui ne doit pas polluer la config réelle du joueur.
## Les positions de fenêtres sauvegardées (user://windows.cfg) sont ignorées et jamais écrites,
## pour des captures reproductibles.

const HOTBAR_CFG := "user://hotbar.cfg"
const MAP_NAME := "Place du village"

var _shot := "game"
var _out := "user://ui_preview.png"
var _map_override := ""
var _map_canvas_size := Vector2.ZERO
var _hotbar_backup: PackedByteArray
var _hotbar_existed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot = arg.substr(7)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--map="):
			_map_override = arg.substr(6)
		elif arg.begins_with("--map-size="):
			var dims := arg.substr(11).split("x")
			_map_canvas_size = Vector2(float(dims[0]), float(dims[1]))
	WindowFrame.persist_positions = false
	_hotbar_existed = FileAccess.file_exists(HOTBAR_CFG)
	if _hotbar_existed:
		_hotbar_backup = FileAccess.get_file_as_bytes(HOTBAR_CFG)
	_run.call_deferred()


func _run() -> void:
	match _shot.trim_suffix("_menu"):
		"login":
			_open_scene("res://scenes/login/Login.tscn")
		"charselect":
			GameState.character_list = [
				{"name": "Aelwyn", "race": "HUMAN", "characterClass": "FIGHTER", "level": 12, "gender": "MAN",
					"equipment": [
						{"slot": "WEAPON", "name": "Long Sword", "weaponType": "SWORD"},
						{"slot": "OFF_HAND", "name": "Wooden Shield", "type": "SHIELD"},
						{"slot": "CHEST", "name": "Chain Mail", "armorCategory": "HEAVY"},
						{"slot": "LEGS", "name": "Leather Pants", "armorCategory": "LIGHT"},
						{"slot": "FEET", "name": "Leather Boots", "armorCategory": "LIGHT"},
						{"slot": "HEAD", "name": "Iron Helmet", "armorCategory": "HEAVY"},
					]},
				{"name": "Morwen", "race": "HUMAN", "characterClass": "MYSTIC", "level": 27, "gender": "WOMAN",
					"equipment": [
						{"slot": "WEAPON", "name": "Staff of Healing", "weaponType": "STAFF"},
						{"slot": "CHEST", "name": "Major Arcana Robe", "armorCategory": "LIGHT"},
						{"slot": "HEAD", "name": "Major Arcana Circlet", "armorCategory": "LIGHT"},
					]},
				{"name": "Thorgal", "race": "HUMAN", "characterClass": "FIGHTER", "level": 3, "gender": "MAN",
					"equipment": []},
			]
			_open_scene("res://scenes/charselect/CharSelect.tscn")
		"create":
			_open_scene("res://scenes/charselect/CharacterCreate.tscn")
		"icons":
			_build_icon_sheet()
		"loading":
			LoadingScreen.begin(MAP_NAME)
			LoadingScreen.set_progress(0.42)
		_:
			_feed_game_state()
			_open_scene("res://scenes/game/Game.tscn")
	await _frames(8)
	if _shot.begins_with("game"):
		# La carte ne s'affiche qu'une fois l'écran de chargement refermé (voir LoadingScreen).
		while LoadingScreen.is_active():
			await get_tree().process_frame
		_setup_game_scene()
	elif _shot.ends_with("_menu"):
		get_tree().current_scene.get_node("SystemMenu/OptionsWindow").open()
	if _shot == "game_spells":
		await _play_spell_scenario()
	await _frames(20)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out)
	print("UIPreview: capture enregistrée dans ", _out)
	_restore_hotbar()
	get_tree().quit()


## Instancie la scène à côté de ce nœud plutôt que via change_scene_to_file, qui libérerait
## ce nœud (scène principale) avant la capture.
func _open_scene(path: String) -> void:
	var scene: Node = load(path).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _restore_hotbar() -> void:
	if _hotbar_existed:
		var f := FileAccess.open(HOTBAR_CFG, FileAccess.WRITE)
		f.store_buffer(_hotbar_backup)
		f.close()
	elif FileAccess.file_exists(HOTBAR_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HOTBAR_CFG))


## Planche de toutes les icônes procédurales + quelques widgets du thème.
func _build_icon_sheet() -> void:
	var root := PanelContainer.new()
	root.theme_type_variation = &"WindowPanel"
	root.position = Vector2(20, 20)
	get_tree().root.add_child.call_deferred(root)
	var col := VBoxContainer.new()
	root.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 13
	col.add_child(grid)
	var entries := [
		["attack", "Attaque", ""], ["skill", "Heal", "HEALING"], ["skill", "Wind Strike", "DAMAGE"],
		["skill", "Might", "BUFF"], ["skill", "Curse", "DEBUFF"], ["skill", "Fire Bolt", "DAMAGE"],
		["skill", "Ice Bolt", "DAMAGE"], ["skill", "Power Strike", "DAMAGE"],
		["item", "Short Sword", "SWORD"], ["item", "Tsurugi", "BIG_SWORD"], ["item", "Dagger", "DAGGER"],
		["item", "Wooden Club", "BLUNT"], ["item", "Hammer of Ruin", "BIG_BLUNT"], ["item", "Battle Axe", "AXE"],
		["item", "Spear", "POLE"], ["item", "Wooden Staff", "STAFF"], ["item", "Wand of Flames", "WAND"],
		["item", "Wooden Bow", "BOW"], ["item", "Bastard Sword", "WEAPON"], ["item", "Iron Helmet", "HELMET"], ["item", "Tunic", "ARMOR"],
		["item", "Pants", "PANTS"], ["item", "Boots", "BOOTS"], ["item", "Gloves", "GLOVES"],
		["item", "Shield", "SHIELD"], ["item", "Necklace", "NECKLACE"], ["item", "Earring", "EARRING"],
		["item", "Ring", "RING"], ["item", "Healing Potion", "POTION"], ["item", "Mana Potion", "POTION"],
		["item", "Elixir", "POTION"], ["item", "Scroll of Escape", "SCROLL"], ["item", "Soulshot", "SOULSHOT"], ["item", "Spiritshot", "SPIRITSHOT"],
		["item", "Old Key", "KEY"], ["item", "Hammer", "TOOL"], ["item", "Junk", "MISC"],
	]
	for e in entries:
		var slot := Panel.new()
		slot.theme_type_variation = &"SlotPanel"
		slot.custom_minimum_size = Vector2(118, 118)
		var tr := TextureRect.new()
		tr.texture = IconFactory.slot_icon(e[0], e[1], e[2])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(4, 4)
		tr.size = Vector2(110, 110)
		slot.add_child(tr)
		grid.add_child(slot)
	var row := HBoxContainer.new()
	col.add_child(row)
	for k in ["character", "inventory", "skills", "options", "coin"]:
		var b := Button.new()
		b.theme_type_variation = &"IconButton"
		b.icon = IconFactory.ui_icon(k, 32)
		b.custom_minimum_size = Vector2(42, 42)
		row.add_child(b)
	for t in ["Bouton", "Désactivé"]:
		var b := Button.new()
		b.text = t
		b.disabled = t == "Désactivé"
		row.add_child(b)
	var le := LineEdit.new()
	le.placeholder_text = "Champ de saisie"
	le.custom_minimum_size = Vector2(160, 0)
	row.add_child(le)
	for k in ["hp", "mp", "cp", "exp", "cast"]:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 14)
		bar.value = 65
		UITheme.style_progress_bar(bar, k)
		col.add_child(bar)


func _emit(type: String, payload: Dictionary) -> void:
	Net.message_received.emit(type, payload)


func _feed_game_state() -> void:
	_emit("GamePlayerStats", {
		"id": "p1", "name": "Aelwyn", "title": "Gardien", "level": 12,
		"characterClass": "FIGHTER", "gender": "man",
		"currentHealth": 342, "maxHealth": 480, "currentMana": 120, "maxMana": 210,
		"xp": 5400, "xpForCurrentLevel": 4000, "xpForNextLevel": 7000,
		"pAtk": 128, "mAtk": 64, "pDef": 97, "mDef": 71, "accuracy": 38, "evasion": 35,
		"criticalRate": 8, "atkSpd": 330, "speed": 2.4, "castSpd": 213,
		"strength": {"score": 40}, "dexterity": {"score": 30}, "constitution": {"score": 43},
		"intelligence": {"score": 21}, "wit": {"score": 11}, "men": {"score": 25},
		"karma": 0, "pvpCount": 3, "pkCount": 0,
		"activeSoulshotGrade": "NOGRADE",
	})
	_emit("Inventory", {
		"gold": 1254300,
		"items": [
			{"id": "i1", "name": "Healing Potion", "grade": "NOGRADE", "type": "POTION", "quantity": 100, "description": "Rend 50 PV."},
			{"id": "i2", "name": "Mana Potion", "grade": "NOGRADE", "type": "POTION", "quantity": 37},
			{"id": "i3", "name": "Soulshot", "grade": "NOGRADE", "type": "SOULSHOT", "quantity": 1520},
			{"id": "i4", "name": "Spiritshot", "grade": "D", "type": "SPIRITSHOT", "quantity": 340},
			{"id": "i5", "name": "Bastard Sword", "grade": "C", "type": "WEAPON", "pAtk": 107, "atkSpd": 379, "critBonus": 8, "enchant": 3},
			{"id": "i6", "name": "Mithril Tunic", "grade": "D", "type": "ARMOR", "armorCategory": "LIGHT", "pDef": 64},
			{"id": "i7", "name": "Old Key", "grade": "NOGRADE", "type": "KEY"},
			{"id": "i9", "name": "Scroll of Escape", "grade": "NOGRADE", "type": "SCROLL", "quantity": 12, "description": "Après 8 secondes d'incantation, ramène à un endroit au hasard de la ville la plus proche."},
			{"id": "i8", "name": "Ring of Wisdom", "grade": "B", "type": "RING", "mDef": 21},
			{"id": "e1", "name": "Iron Helmet", "grade": "D", "type": "HELMET", "slot": "HEAD", "pDef": 27},
			{"id": "e2", "name": "Saber", "grade": "NOGRADE", "type": "WEAPON", "slot": "WEAPON", "pAtk": 32},
			{"id": "e3", "name": "Leather Boots", "grade": "NOGRADE", "type": "BOOTS", "slot": "FEET", "pDef": 9},
			{"id": "e4", "name": "Necklace of Magic", "grade": "S", "type": "NECKLACE", "slot": "NECKLACE", "mDef": 40},
		],
	})
	_emit("KnownSkills", {"skills": [
		{"id": "s1", "name": "Heal", "level": 3, "skillType": "HEALING", "manaCost": 24, "cooldownSeconds": 4, "range": 6, "description": "Rend des PV à la cible."},
		{"id": "s2", "name": "Wind Strike", "level": 5, "skillType": "DAMAGE", "manaCost": 18, "cooldownSeconds": 2, "range": 8},
		{"id": "s3", "name": "Might", "level": 1, "skillType": "BUFF", "manaCost": 12, "cooldownSeconds": 10, "durationSeconds": 1200},
		{"id": "s4", "name": "Power Strike", "level": 2, "skillType": "DAMAGE", "manaCost": 10, "cooldownSeconds": 5, "granted": true},
	]})
	var size := _map_size(MAP_NAME)
	var width := size.x
	var height := size.y
	var rows := []
	for y in height:
		rows.append("1".repeat(width))
	_emit("MapView", {"mapName": MAP_NAME, "grid": {"width": width, "height": height, "walkableRows": rows}})
	# Au sud de la fontaine de la Place du village (72, 46, voir generate_place_du_village.gd).
	var cx := 72.5
	var cy := 53.0
	_emit("MapEnter", {"selfX": cx, "selfY": cy, "selfHeading": 0.0})
	_emit("EntityAppeared", {"entities": [
		{"id": "m1", "name": "Loup gris", "kind": "monster", "x": cx + 3, "y": cy + 1, "currentHealth": 64, "maxHealth": 120, "level": 14},
		{"id": "m2", "name": "Gobelin", "kind": "monster", "x": cx - 4, "y": cy + 3, "currentHealth": 80, "maxHealth": 80, "level": 9},
		{"id": "n1", "name": "Lector", "kind": "npc", "title": "Marchand", "x": cx - 2, "y": cy - 3, "hasShop": true},
		{"id": "n2", "name": "Village Guard", "kind": "npc", "title": "City Guard", "x": cx - 3.5, "y": cy - 0.5,
			"heading": 90.0, "npcType": "GUARD", "gender": "MAN"},
		{"id": "n3", "name": "Village Guard", "kind": "npc", "title": "City Guard", "x": cx - 3.5, "y": cy + 1.2,
			"heading": 90.0, "npcType": "GUARD", "gender": "WOMAN"},
		{"id": "c1", "name": "Kaelis", "kind": "character", "title": "Chevalier", "x": cx + 1, "y": cy - 4, "currentHealth": 300, "maxHealth": 300, "level": 20,
			"gender": "WOMAN", "equipment": [
				{"slot": "WEAPON", "name": "Tsurugi", "type": "WEAPON", "grade": "C", "weaponType": "BIG_SWORD"},
				{"slot": "CHEST", "name": "Plate Armor", "type": "ARMOR", "grade": "C", "armorCategory": "HEAVY"},
				{"slot": "HEAD", "name": "Helm of Terror", "type": "HELMET", "grade": "C"},
				{"slot": "FEET", "name": "Dark Crystal Boots", "type": "BOOTS", "grade": "B"},
			]},
	]})


func _setup_game_scene() -> void:
	var game := get_tree().current_scene
	var hud := game.get_node("HUD")
	var hotbar := hud.get_node("Hotbar")
	var slot_nodes: Array = hotbar._slot_nodes
	slot_nodes[1].set_content("skill", "Heal")
	slot_nodes[2].set_content("skill", "Wind Strike")
	slot_nodes[3].set_content("skill", "Might")
	slot_nodes[4].set_content("item", "Healing Potion")
	slot_nodes[4].set_quantity(237)
	slot_nodes[5].set_content("item", "Mana Potion")
	slot_nodes[5].set_quantity(37)
	slot_nodes[6].set_content("item", "Soulshot")
	slot_nodes[6].set_quantity(1520)
	slot_nodes[6].set_active(true)
	slot_nodes[7].set_content("item", "Greater Healing Potion")
	slot_nodes[7].set_quantity(0)
	slot_nodes[8].set_content("item", "Spiritshot")
	slot_nodes[8].set_quantity(340)
	slot_nodes[2].set_cooldown_overlay(6000.0)

	game._log("Vous infligez 42 dégâts à Loup gris.")
	game._log("[color=%s]Vous gagnez 120 points d'expérience.[/color]" % game.LOG_COLOR_GAIN)
	game._log("Loup gris vous inflige 12 dégâts.")
	game._log_chat("Kaelis : Quelqu'un pour la chasse aux loups ?")
	game._log_chat("[color=%s](Groupe) Morwen : j'arrive[/color]" % game.LOG_COLOR_PARTY, "party")
	game._log_chat("[color=%s]Thorgal chuchote : salut ![/color]" % game.LOG_COLOR_WHISPER, "whisper")

	match _shot:
		"game":
			game._apply_selection("m1", "Loup gris")
			hud.get_node("ChatBar/ChatInput").grab_focus()
		"game_select_self":
			game._apply_selection("p1", "Aelwyn")
		"game_select_party":
			_emit("PartyMemberJoined", {"memberId": "c1", "memberName": "Kaelis", "level": 20, "characterClass": "FIGHTER", "currentHealth": 300,
				"maxHealth": 300, "currentMana": 80, "maxMana": 95})
			game._apply_selection("c1", "Kaelis")
		"game_party", "game_party_menu":
			_feed_party()
			game._apply_selection("c1", "Kaelis")
			if _shot == "game_party_menu":
				# Nous devenons chef : le menu montre alors toutes ses entrées.
				_emit("NewPartyLeader", {"leaderId": "p1", "leaderName": "Aelwyn"})
				await _frames(4)
				var party_window: Control = hud.get_node("PartyWindow")
				var frame: Control = party_window.get_node("%Members").get_child(0)
				get_viewport().warp_mouse(frame.get_global_rect().get_center() + Vector2(60, 0))
				party_window._open_menu(frame.member_id)
		"game_party_invite":
			_emit("PartyInviteReceived", {"inviterId": "c1", "inviterName": "Kaelis"})
		"game_invite_button":
			game._apply_selection("c1", "Kaelis")
		"game_windows":
			hud.get_node("InventoryWindow").open()
			hud.get_node("CharacterSheetWindow").open()
		"game_2h":
			# Arme à deux mains équipée : la main secondaire doit apparaître grisée.
			var inventory_payload: Dictionary = GameState.inventory.duplicate(true)
			for item in inventory_payload["items"]:
				if item["id"] == "e2":
					item.merge({"name": "Tsurugi", "grade": "C", "weaponType": "BIG_SWORD", "pAtk": 140}, true)
			inventory_payload["offHandBlocked"] = true
			_emit("Inventory", inventory_payload)
			hud.get_node("InventoryWindow").open()
		"game_shop":
			_emit("ShopCatalog", {"npcId": "n1", "npcName": "Lector", "gold": 1254300, "entries": [
				{"itemTemplateId": "t1", "itemName": "Healing Potion", "grade": "NOGRADE", "price": 40},
				{"itemTemplateId": "t2", "itemName": "Mana Potion", "grade": "NOGRADE", "price": 60},
				{"itemTemplateId": "t3", "itemName": "Soulshot", "grade": "NOGRADE", "price": 7},
				{"itemTemplateId": "t4", "itemName": "Bastard Sword", "grade": "C", "price": 125000},
			]})
			_emit("DialogueOptions", {"npcId": "n1", "npcName": "Lector", "greeting": "Bienvenue, voyageur ! Les routes sont dangereuses ces temps-ci. Que puis-je faire pour vous ?", "options": [
				{"label": "Parler des loups", "type": "RESPONSE", "response": "..."},
				{"label": "Voir la boutique", "type": "SHOP"},
				{"label": "Au revoir", "type": "LEAVE"},
			]})
			var dialogue: Control = hud.get_node("DialogueWindow")
			dialogue.position = Vector2(60, 160)
		"game_options", "game_options_sound", "game_options_system":
			var options: Control = hud.get_node("OptionsWindow")
			options.open()
			var tab: int = {"game_options": 0, "game_options_sound": 1, "game_options_system": 2}[_shot]
			(options._tab_row.get_child(tab) as Button).button_pressed = true
			options._show_page(tab)
			options.position = Vector2(620, 240)
		"game_misc":
			hud.get_node("SkillBook").open()
			hud.get_node("OptionsWindow").open()
			game._apply_selection("n1", "Lector")
			game._open_npc_menu(true)
		"game_death":
			hud.get_node("DeathPopup").open("Loup gris")
		"game_tooltip":
			var inventory: Control = hud.get_node("InventoryWindow")
			inventory.open()
			await _frames(6)
			# Survole la 5e case (l'épée) pour faire apparaître son infobulle.
			var grid: GridContainer = inventory.get_node("%ItemsContainer")
			var cell: Control = grid.get_child(4)
			get_viewport().warp_mouse(cell.get_global_rect().get_center())
			# Le survol simulé ne déclenche pas l'infobulle native : on reproduit son rendu
			# (même StyleBox "TooltipPanel" + contenu de _make_custom_tooltip) à côté.
			for i in 2:
				var item: Dictionary = GameState.inventory["items"][4 if i == 0 else 3]
				var tip := PanelContainer.new()
				tip.add_theme_stylebox_override("panel", UITheme.theme.get_stylebox("panel", "TooltipPanel"))
				var action := "équiper" if str(item.get("type", "")) in inventory.EQUIPPABLE_TYPES else "utiliser"
				var footer := ["Clic droit : %s" % action, "Glisser hors de la fenêtre : jeter"]
				tip.add_child(UITheme.make_rich_tooltip(ItemTooltip.build(item, footer)))
				tip.position = cell.get_global_rect().end + Vector2(8 + 230 * i, 8)
				hud.add_child(tip)
		"game_worldmap":
			if not _map_override.is_empty():
				var map_size := _map_size(_map_override)
				var rows := []
				for y in map_size.y:
					rows.append("1".repeat(map_size.x))
				_emit("MapView", {"mapName": _map_override, "grid": {"width": map_size.x, "height": map_size.y, "walkableRows": rows}})
				_emit("MapEnter", {"selfX": map_size.x / 2.0, "selfY": map_size.y / 2.0, "selfHeading": 0.0})
				await _frames(4)
			var world_map: Control = hud.get_node("WorldMapWindow")
			world_map.open()
			if _map_canvas_size != Vector2.ZERO:
				world_map._set_canvas_size(_map_canvas_size)
			world_map.position = Vector2(40, 60)
		"game_dialog":
			var inventory: Control = hud.get_node("InventoryWindow")
			inventory.open()
			inventory._on_drop_pressed("i5", "Bastard Sword")


## Groupe factice (game_party*) : Kaelis (chef) puis Morwen et Thorgal (mort), buffs/debuffs
## variés — dont un qui expire (clignote) — passés par les vrais messages serveur, pour
## exercer aussi GameState et le journal.
func _feed_party() -> void:
	_emit("PartyJoined", {"leaderId": "c1", "leaderName": "Kaelis", "memberCount": 4, "members": [
		{"id": "c1", "name": "Kaelis", "level": 20, "characterClass": "FIGHTER", "subclass": "KNIGHT", "currentHealth": 214, "maxHealth": 300, "currentMana": 60, "maxMana": 95,
			"effects": [{"skillName": "Might", "beneficial": true, "secondsRemaining": 1100},
				{"skillName": "Bulwark", "beneficial": true, "secondsRemaining": 640}]},
		{"id": "c2", "name": "Morwen", "level": 17, "characterClass": "MYSTIC", "subclass": null, "currentHealth": 188, "maxHealth": 196, "currentMana": 305, "maxMana": 410,
			"effects": [{"skillName": "Empower", "beneficial": true, "secondsRemaining": 6},
				{"skillName": "Focus", "beneficial": true, "secondsRemaining": 900},
				{"skillName": "Curse: Weakness", "beneficial": false, "secondsRemaining": 25}]},
		{"id": "c3", "name": "Thorgal", "level": 9, "characterClass": "FIGHTER", "subclass": null, "currentHealth": 0, "maxHealth": 254, "currentMana": 12, "maxMana": 70,
			"effects": []},
	]})
	_emit("PartyMemberEffectApplied", {"characterId": "c1", "characterName": "Kaelis", "skillName": "Curse: Doom",
		"stat": "P. Def.", "amount": -12, "secondsRemaining": 30, "beneficial": false})
	_emit("PartyMemberVitalsUpdated", {"characterId": "c2", "characterName": "Morwen", "currentHealth": 150,
		"maxHealth": 196, "currentMana": 280, "maxMana": 410})
	_emit("PartyMemberJoined", {"memberId": "c4", "memberName": "Elenwë", "currentHealth": 120, "maxHealth": 160,
		"currentMana": 200, "maxMana": 240, "effects": [{"skillName": "Rage", "beneficial": true, "secondsRemaining": 300}]})
	_emit("PartyMemberLeft", {"memberName": "Elenwë"})
	# Morwen monte au niveau 18 en cours de groupe.
	_emit("PartyMemberProfileUpdated", {"characterId": "c2", "characterName": "Morwen", "level": 18,
		"characterClass": "MYSTIC", "subclass": null})


## Dimensions de la carte lues sur le GridMap "Terrain" de sa scène (voir
## ZoneAssets3D.get_map_scene_path), 40x40 par défaut si introuvable.
func _map_size(map_name: String) -> Vector2i:
	var path := ZoneAssets3D.get_map_scene_path(map_name)
	if path.is_empty():
		return Vector2i(40, 40)
	var map_instance: Node = load(path).instantiate()
	var grid_map := map_instance.get_node_or_null("Terrain") as GridMap
	var result := Vector2i(40, 40)
	if grid_map != null and not grid_map.get_used_cells().is_empty():
		result = Vector2i.ZERO
		for cell in grid_map.get_used_cells():
			result = Vector2i(maxi(result.x, cell.x + 1), maxi(result.y, cell.z + 1))
	map_instance.free()
	return result


## --shot=game_spells : incantations/projectile/soin simulés dans la vraie scène de jeu
## (flux Net -> Game3D -> SpellVfx), capturés en plein vol.
func _play_spell_scenario() -> void:
	_emit("SkillCastStarted", {"casterId": "p1", "casterName": "Aelwyn", "skillName": "Wind Strike",
		"targetId": "m1", "castingTimeMs": 4000, "casterHeading": 0.0})
	_emit("SkillCastStarted", {"casterId": "c1", "casterName": "Kaelis", "skillName": "Curse: Doom",
		"targetId": "m2", "castingTimeMs": 3000, "casterHeading": 0.0})
	await get_tree().create_timer(0.7).timeout
	_emit("SkillProjectileLaunched", {"casterId": "c1", "skillName": "Flame Strike", "targetId": "m1",
		"travelDurationMs": 1200})
	await get_tree().create_timer(0.3).timeout
	_emit("SkillCastAnnounced", {"casterId": "m2", "casterName": "Gobelin", "targetId": "m2",
		"skillName": "Heal", "selfHeal": true, "targetHealthAfter": 80, "targetMaxHealth": 80})
	await get_tree().create_timer(0.2).timeout
	_emit("SkillCastCancelled", {"casterId": "c1", "casterName": "Kaelis", "skillName": "Curse: Doom"})
	await get_tree().create_timer(0.15).timeout
