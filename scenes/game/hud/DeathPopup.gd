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


func _ready() -> void:
	visible = false
	_respawn_button.pressed.connect(_on_respawn_pressed)


func open(killer_name: String) -> void:
	_killer_label.visible = not killer_name.is_empty()
	_killer_label.text = "Tué par %s." % killer_name
	_respawn_button.disabled = false
	_respawn_button.text = "Respawn"
	visible = true


func close() -> void:
	visible = false


func _on_respawn_pressed() -> void:
	# Respawn.java répond CharacterNotDead si on n'est déjà plus mort (ex. double-clic) —
	# rien de plus à faire côté client dans ce cas, le bouton reste juste désactivé jusqu'à
	# ce que PlayerRespawned (via Game3D.gd) ferme cette fenêtre.
	_respawn_button.disabled = true
	_respawn_button.text = "Réapparition..."
	Net.send_command("respawn")
