extends Marker3D
## Point d'apparition d'un monstre (converti depuis l'objet Tiled type="monsterSpawn").
## `spawn_group` relie ce point à un MonsterSpawnGroupMarker3D de même id (voir
## groupId sur ce dernier) qui porte les règles de respawn du groupe.

@export var template_id: String = ""
@export var spawn_group: String = ""
