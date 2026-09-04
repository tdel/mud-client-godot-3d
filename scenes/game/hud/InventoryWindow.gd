extends WindowFrame
## Objets non équipés (slot vide, voir Inventory.Entry.slot) + or. Contrairement au client
## 2D (mud-godot/scenes/game/hud/InventoryPanel.gd), pas de bouton "Équiper" ici : équiper
## se fait en glissant l'icône vers un slot d'EquipmentWindow (voir DraggableIcon/
## EquipmentSlot) — demandé explicitement le 2026-09-03 ("faire du drag and drop des objets
## depuis l'inventaire", "quelque chose qui ressemble à du Lineage 2 / L2J"). "Jeter" détruit
## définitivement l'objet côté serveur (Drop → ItemDiscarded, aucune confirmation proposée
## par le backend) : une confirmation locale est donc demandée avant l'envoi, porté tel quel
## du client 2D.
##
## Boutons "Utiliser"/"Jeter" retirés (2026-09-03, demandé explicitement) au profit de deux
## gestes façon L2J sur l'icône elle-même : clic droit = utiliser (voir
## DraggableIcon.right_clicked), glisser-déposer hors de cette fenêtre = jeter (voir
## _on_item_drag_finished — un drop réussi sur la hotbar/l'équipement ne déclenche pas ce
## chemin, seul un lâcher qui n'atterrit sur aucune cible ET en dehors du rectangle de cette
## fenêtre est traité comme "jeter", pour ne rien faire si l'utilisateur relâche simplement
## ailleurs dans la liste).

const DraggableIcon := preload("res://scenes/game/hud/DraggableIcon.gd")

## Depuis le passage du backend à un système Lineage2, Inventory.Entry.grade est un
## ItemGrade (NOGRADE/D/C/B/A/S) — code couleur L2 classique, copié du client 2D.
const GRADE_COLORS := {
	"NOGRADE": Color(0.75, 0.75, 0.75),
	"D": Color(0.90, 0.90, 0.90),
	"C": Color(0.30, 0.85, 0.35),
	"B": Color(0.30, 0.55, 0.95),
	"A": Color(0.95, 0.75, 0.15),
	"S": Color(0.90, 0.20, 0.20),
}

## Traduction de app.domain.item.ItemType/ArmorCategory (backend) pour l'infobulle — voir
## _item_tooltip.
const ITEM_TYPE_LABELS := {
	"WEAPON": "Arme", "HELMET": "Casque", "ARMOR": "Armure", "PANTS": "Jambières",
	"BOOTS": "Bottes", "GLOVES": "Gants", "SHIELD": "Bouclier", "NECKLACE": "Collier",
	"EARRING": "Boucle d'oreille", "RING": "Anneau", "POTION": "Potion", "KEY": "Clé",
	"TOOL": "Outil", "MISC": "Objet", "SOULSHOT": "Soulshot", "SPIRITSHOT": "Spiritshot",
}
const ARMOR_CATEGORY_LABELS := {"LIGHT": "légère", "MEDIUM": "moyenne", "HEAVY": "lourde"}

## Taille d'une cellule de la grille (voir _build_cell) — refonte "façon L2" du 2026-09-04
## (voir CLAUDE.md) : la liste nom+icône d'origine (une HBoxContainer par ligne) devient une
## grille d'icônes façon Lineage 2, le nom ne s'affichant plus qu'en tooltip (comme un vrai
## slot L2). GridContainer.columns fixé dans InventoryWindow.tscn (6 colonnes).
const CELL_SIZE := Vector2(52, 52)

@onready var _items_container: GridContainer = %ItemsContainer
@onready var _gold_label: Label = %GoldLabel
@onready var _drop_confirm_dialog: ConfirmationDialog = %DropConfirmDialog
@onready var _message_label: Label = %MessageLabel

var _pending_drop_id := ""
var _pending_drop_name := ""


func _ready() -> void:
	super._ready()
	set_window_title("Inventaire")
	Net.message_received.connect(_on_message_received)
	_drop_confirm_dialog.confirmed.connect(_on_drop_confirmed)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_I or get_viewport().gui_get_focus_owner() != null:
		return
	if visible:
		close_window()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	show_window()
	_clear_message()
	Net.send_command("inventory")
	_refresh()


func _on_message_received(type: String, payload: Dictionary) -> void:
	if not visible:
		return
	match type:
		"Inventory":
			_clear_message()
			_refresh()
		"ItemEquipped":
			_show_message("%s équipé." % str(payload.get("name", "?")))
			Net.send_command("inventory")
		"ItemUnequipped":
			_show_message("%s retiré." % str(payload.get("name", "?")))
			Net.send_command("inventory")
		"ItemDiscarded":
			_show_message("%s détruit." % str(payload.get("name", "?")))
			Net.send_command("inventory")
		"ItemNotCarried":
			_show_message("Cet objet n'est plus dans votre inventaire.")
		"ItemNotUsable":
			_show_message("« %s » ne peut pas être utilisé." % str(payload.get("name", "?")))
		"ShotGradeChanged", "ShotOutOfStock":
			# Fait réagir le surlignage "actif" (voir _is_shot_active) sans attendre un aller-
			# retour "inventory" complet — GameState.active_soulshot_grade/
			# active_spiritshot_grade est déjà à jour à ce point (GameState.gd traite le même
			# signal indépendamment, voir Net.message_received, sans garantie d'ordre entre les
			# deux écouteurs mais peu importe : seule la valeur une fois les deux exécutés compte).
			_refresh()
		"ShotUsed":
			# Corrige juste la quantité affichée en place, sans redemander "inventory" à
			# chaque tir/coup consommé (un vrai combat en enverrait des dizaines par minute) —
			# voir _patch_shot_quantity.
			_patch_shot_quantity(str(payload.get("shotType", "")), int(payload.get("remainingQuantity", 0)))
		_:
			pass


func _refresh() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	var inventory: Dictionary = GameState.inventory
	_gold_label.text = "Or : %s" % inventory.get("gold", 0)

	var carried: Array = []
	for item in inventory.get("items", []):
		var slot = item.get("slot")
		if slot == null or str(slot).is_empty():
			carried.append(item)

	if carried.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Inventaire vide."
		_items_container.add_child(empty_label)
		return

	for item in carried:
		_items_container.add_child(_build_cell(item))


## Une cellule carrée façon slot L2 (fond de HotbarSlot.tscn répliqué en code faute de scène
## dédiée pour une grille dynamique) : icône seule, nom relégué au tooltip, fin bandeau de
## couleur de grade en bas (remplace le texte coloré par grade de l'ancienne ligne), badge de
## quantité en bas à droite pour les charges (soulshot/spiritshot) empilées, pastille dorée en
## haut à gauche si la charge est actuellement armée (voir _is_shot_active). Glisser-déposer/
## clic droit inchangés (DraggableIcon), voir CLAUDE.md session "refonte L2" du 2026-09-04.
func _build_cell(item: Dictionary) -> Control:
	var item_id := str(item.get("id", ""))
	var item_name := str(item.get("name", ""))
	var grade := str(item.get("grade", "NOGRADE"))
	var type_key := str(item.get("type", ""))
	var is_shot := type_key == "SOULSHOT" or type_key == "SPIRITSHOT"
	var quantity := int(item.get("quantity", 1))
	var active := is_shot and _is_shot_active(type_key, grade)

	var cell := Control.new()
	cell.custom_minimum_size = CELL_SIZE

	var background := Panel.new()
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(background)

	var icon := DraggableIcon.new()
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_default_cursor_shape = Control.CURSOR_MOVE
	icon.texture = ZoneAssets3D.make_slot_icon_texture("item", item_name)

	# ref_id (l'UUID d'instance, contrairement à SkillBook qui ne l'utilise que pour les
	# sorts) est indispensable ici : EquipmentSlot.gd envoie "equip <uuid>" directement sur
	# la donnée du drag, sans re-résolution par nom (voir EquipmentSlot._can_drop_data).
	icon.drag_kind = "item"
	icon.drag_ref_id = item_id
	icon.drag_ref_name = item_name
	icon.drag_item_type = type_key
	icon.drag_item_grade = grade
	icon.drag_preview_text = item_name
	icon.modulate = Color(1.25, 1.1, 0.55) if active else Color(1, 1, 1, 1)

	if is_shot:
		# Soulshot/spiritshot (voir CLAUDE.md, commit backend "Ajoute le système soulshot/
		# spiritshot" du 2026-09-04) : pas un "use" ponctuel comme une potion, mais un toggle
		# d'auto-use — clic droit renvoie "soulshot <grade>"/"spiritshot <grade>", le serveur
		# se charge lui-même du bascule actif/inactif (renvoyer la même grade l'éteint).
		icon.tooltip_text = "%s\n\n%s\nClic droit : %s\nGlisser hors de la fenêtre : jeter" % [
			_item_tooltip(item),
			"Auto-use : actif" if active else "Auto-use : inactif",
			"désactiver" if active else "activer",
		]
		icon.right_clicked.connect(func(): Net.send_command(type_key.to_lower(), grade.to_lower()))
	else:
		icon.tooltip_text = "%s\n\nClic droit : utiliser\nGlisser hors de la fenêtre : jeter" % _item_tooltip(item)
		icon.right_clicked.connect(func(): Net.send_command("use", item_id))
	icon.drag_finished.connect(_on_item_drag_finished.bind(item_id, item_name))
	cell.add_child(icon)

	var grade_bar := ColorRect.new()
	grade_bar.color = GRADE_COLORS.get(grade, Color.WHITE)
	grade_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_bar.anchor_left = 0.0
	grade_bar.anchor_right = 1.0
	grade_bar.anchor_top = 1.0
	grade_bar.anchor_bottom = 1.0
	grade_bar.offset_top = -3.0
	cell.add_child(grade_bar)

	if quantity != 1:
		var qty_label := Label.new()
		qty_label.text = str(quantity)
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		qty_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		qty_label.add_theme_constant_override("outline_size", 3)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.anchor_left = 0.0
		qty_label.anchor_right = 1.0
		qty_label.anchor_top = 1.0
		qty_label.anchor_bottom = 1.0
		qty_label.offset_top = -18.0
		qty_label.offset_right = -3.0
		cell.add_child(qty_label)

	if active:
		var active_marker := Label.new()
		active_marker.text = "●"
		active_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		active_marker.add_theme_font_size_override("font_size", 13)
		active_marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1))
		active_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		active_marker.add_theme_constant_override("outline_size", 3)
		active_marker.offset_left = 2.0
		active_marker.offset_top = -2.0
		cell.add_child(active_marker)

	return cell


## Dupliqué à l'identique dans Hotbar.gd (même convention que le reste du HUD, voir CLAUDE.md :
## chaque fenêtre reste un Control autonome sans dépendance croisée).
func _is_shot_active(item_type: String, item_grade: String) -> bool:
	var active_grade := GameState.active_soulshot_grade if item_type == "SOULSHOT" else GameState.active_spiritshot_grade
	return not active_grade.is_empty() and active_grade == item_grade


## Corrige juste la quantité affichée en place, sans redemander "inventory" à chaque tir/coup
## consommé (un vrai combat en enverrait des dizaines par minute) — voir ShotUsed ci-dessus.
## Ne retire jamais l'entrée à 0 (le serveur la supprime, voir Item.quantity côté backend) :
## une prochaine ouverture de fenêtre (Net.send_command("inventory") dans open()) la fera
## disparaître pour de bon, léger décalage cosmétique jugé préférable à re-fetch systématique.
func _patch_shot_quantity(shot_type: String, remaining: int) -> void:
	if shot_type.is_empty():
		return
	for item in GameState.inventory.get("items", []):
		if str(item.get("type", "")) == shot_type:
			item["quantity"] = remaining
			break
	_refresh()


## Un drop qui n'a atterri sur aucune cible valide (hotbar/équipement, seuls Control à
## implémenter _can_drop_data pour kind "item") ET qui a lieu hors du rectangle de cette
## fenêtre est traité comme "jeter" — un drop réussi ne déclenche rien ici, et un lâcher
## raté mais toujours à l'intérieur de la fenêtre (ex. sur une autre ligne) ne fait rien non
## plus, pour ne pas surprendre l'utilisateur qui relâche simplement par erreur dans la liste.
func _on_item_drag_finished(successful: bool, item_id: String, item_name: String) -> void:
	if successful:
		return
	if get_global_rect().has_point(get_global_mouse_position()):
		return
	_on_drop_pressed(item_id, item_name)


func _on_drop_pressed(item_id: String, item_name: String) -> void:
	_pending_drop_id = item_id
	_pending_drop_name = item_name
	_drop_confirm_dialog.dialog_text = (
		"Détruire définitivement « %s » ? Cette action est irréversible." % item_name
	)
	_drop_confirm_dialog.popup_centered()


func _on_drop_confirmed() -> void:
	if not _pending_drop_id.is_empty():
		Net.send_command("drop", _pending_drop_id)
		_pending_drop_id = ""
		_pending_drop_name = ""


func _show_message(message: String) -> void:
	_message_label.text = message
	_message_label.visible = true


func _clear_message() -> void:
	_message_label.text = ""
	_message_label.visible = false


## Construit le texte complet des caractéristiques d'un objet (nom/grade, type, stats de
## combat, éventuel bonus d'amélioration, description) — dupliqué à l'identique dans
## EquipmentSlot.gd (même convention que le reste du HUD, voir CLAUDE.md : chaque fenêtre
## reste un Control autonome sans dépendance croisée). Les stats de combat valent toutes 0
## côté backend pour un objet non équipable (potion, clé...), donc simplement omises ici.
static func _item_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("%s (%s)" % [item.get("name", "?"), item.get("grade", "NOGRADE")])

	var type_key := str(item.get("type", ""))
	var type_line: String = ITEM_TYPE_LABELS.get(type_key, type_key)
	var armor_category = item.get("armorCategory")
	if armor_category != null and not str(armor_category).is_empty():
		type_line += " (%s)" % ARMOR_CATEGORY_LABELS.get(str(armor_category), str(armor_category))
	lines.append(type_line)

	if type_key == "SOULSHOT" or type_key == "SPIRITSHOT":
		lines.append("Quantité : %d" % int(item.get("quantity", 1)))

	var atk_def_line := PackedStringArray()
	if int(item.get("pAtk", 0)) != 0:
		atk_def_line.append("P.Atk %s" % _signed(item.get("pAtk", 0)))
	if int(item.get("mAtk", 0)) != 0:
		atk_def_line.append("M.Atk %s" % _signed(item.get("mAtk", 0)))
	if int(item.get("pDef", 0)) != 0:
		atk_def_line.append("P.Def %s" % _signed(item.get("pDef", 0)))
	if int(item.get("mDef", 0)) != 0:
		atk_def_line.append("M.Def %s" % _signed(item.get("mDef", 0)))
	if not atk_def_line.is_empty():
		lines.append("   ".join(atk_def_line))

	var bonus_line := PackedStringArray()
	if int(item.get("accuracyBonus", 0)) != 0:
		bonus_line.append("Précision %s" % _signed(item.get("accuracyBonus", 0)))
	if int(item.get("evasionBonus", 0)) != 0:
		bonus_line.append("Esquive %s" % _signed(item.get("evasionBonus", 0)))
	if int(item.get("critBonus", 0)) != 0:
		bonus_line.append("Critique %s" % _signed(item.get("critBonus", 0)))
	if int(item.get("atkSpd", 0)) != 0:
		bonus_line.append("Vit.Atk %s" % _signed(item.get("atkSpd", 0)))
	if not bonus_line.is_empty():
		lines.append("   ".join(bonus_line))

	var enchant := int(item.get("enchant", 0))
	if enchant > 0:
		lines.append("Amélioration : +%s" % enchant)

	var description := str(item.get("description", ""))
	if not description.is_empty():
		lines.append(description)

	return "\n".join(lines)


## "+5"/"-2" plutôt que le "+%s" naïf qui produirait "+-2" sur un bonus négatif
## (evasionBonus notamment, souvent négatif pour une armure lourde).
static func _signed(value: int) -> String:
	return "+%s" % value if value >= 0 else str(value)
