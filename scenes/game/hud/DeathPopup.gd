extends Control
## Popup de mort : affichée par Game3D.gd quand GamePlayerDefeated nous concerne (voir
## CharacterInstance.takeDamage/GamePlayerDied côté backend), fermée sur PlayerRespawned.
## Porté quasi verbatim de mud-godot/scenes/game/hud/DeathPopup.gd (client 2D) : ce widget
## ne s'abonne pas lui-même à Net.message_received, c'est Game3D.gd qui le pilote
## directement (il connaît déjà notre nom pour filtrer GamePlayerDefeated). Couvre tout
## l'écran (voir DeathPopup.tscn) : ses clics consommés bloquent déjà le déplacement au clic
## pendant qu'elle est visible, en plus du verrou explicite déjà posé côté Game3D.gd/
## Hotbar.gd (voir GameState.is_dead).

@onready var _killer_label: Label = %KillerLabel
@onready var _respawn_button: Button = %RespawnButton

## Proposition de résurrection d'un prêtre (ResurrectionOffered, voir offer_resurrection) :
## ligne ajoutée sous le bouton de réapparition, cachée sans proposition.
var _resurrect_label := Label.new()
var _resurrect_button := Button.new()


func _ready() -> void:
	visible = false
	_respawn_button.pressed.connect(_on_respawn_pressed)
	_resurrect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resurrect_label.custom_minimum_size = Vector2(260, 0)
	_resurrect_label.add_theme_color_override("font_color", UITheme.SUCCESS)
	_resurrect_button.text = "Accepter la résurrection"
	_resurrect_button.focus_mode = Control.FOCUS_NONE
	_resurrect_button.pressed.connect(_on_resurrect_pressed)
	_respawn_button.get_parent().add_child(_resurrect_label)
	_respawn_button.get_parent().add_child(_resurrect_button)
	_hide_resurrection()


func open(killer_name: String) -> void:
	_killer_label.visible = not killer_name.is_empty()
	_killer_label.text = "Vous avez été tué par %s." % killer_name
	_respawn_button.disabled = false
	_respawn_button.text = "Réapparaître"
	visible = true


func close() -> void:
	visible = false
	_hide_resurrection()


## `caster_name` propose de nous ramener à la vie sur place (Resurrection) : accepter envoie
## resurrect-accept ; la popup se ferme sur PlayerResurrected (voir Game3D).
func offer_resurrection(caster_name: String, skill_name: String) -> void:
	_resurrect_label.text = "%s vous propose %s." % [caster_name, skill_name]
	_resurrect_label.visible = true
	_resurrect_button.visible = true
	_resurrect_button.disabled = false


func _hide_resurrection() -> void:
	_resurrect_label.visible = false
	_resurrect_button.visible = false


func _on_resurrect_pressed() -> void:
	_resurrect_button.disabled = true
	Net.send_command("resurrect-accept")


func _on_respawn_pressed() -> void:
	# Respawn.java répond CharacterNotDead si on n'est déjà plus mort (ex. double-clic) —
	# rien de plus à faire côté client dans ce cas, le bouton reste juste désactivé jusqu'à
	# ce que PlayerRespawned (via Game3D.gd) ferme cette fenêtre.
	_respawn_button.disabled = true
	_respawn_button.text = "Réapparition..."
	Net.send_command("respawn")
