class_name MonsterCatalog
extends RefCounted
## Nom de monstre serveur (MonsterTemplate.name, voir data/monsters.xml côté backend) ->
## fiche visuelle MonsterModel. Le serveur n'envoie que le nom (EntityView.name) : clé en
## minuscules, comparée au nom normalisé. Un monstre absent d'ici reste une capsule rouge
## (voir Game3D._make_entity_node).
##
## Ajouter un monstre : déposer son .glb dans assets/monsters/<monstre>/, créer la .tres
## MonsterModel à côté (nom des clips, échelle), puis l'enregistrer ci-dessous — plusieurs
## noms peuvent partager une même fiche (variantes d'un même animal).

const MODELS := {
	"fox": preload("res://assets/monsters/fox/fox.tres"),
}


## Fiche du monstre `monster_name`, null si aucun modèle dédié.
static func model_for(monster_name: String) -> MonsterModel:
	return MODELS.get(monster_name.strip_edges().to_lower())
