extends Node3D
## Règles de respawn d'un groupe de points MonsterSpawnMarker3D (converti depuis l'objet
## Tiled type="monsterSpawnGroup") — sans position propre dans le .tmx source (toujours
## x=0, y=0), ce n'est pas un repère spatial mais un porteur de métadonnées de groupe.

@export var group_id: String = ""
@export var max_monsters: int = 0
@export var respawn_delay_seconds: int = 0
