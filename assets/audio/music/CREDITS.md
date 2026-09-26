# Musiques

| Fichier | Titre | Auteur | Licence | Source |
|---|---|---|---|---|
| `forest_of_abandoned_souls.ogg` | Forest of Abandoned Souls | Alexandr Zhelanov | CC-BY 4.0 | https://opengameart.org/content/forest-of-abandoned-souls |

`forest_of_abandoned_souls.ogg` est le fichier d'origine, non modifié (2 min 58). La piste finit
par un fondu jusqu'au silence : elle boucle telle quelle depuis le début (voir autoload/MenuMusic.gd).

**Attribution obligatoire (CC-BY 4.0)** — à reprendre dans les crédits du jeu :

> "Forest of Abandoned Souls" by Alexandr Zhelanov (https://soundcloud.com/alexandr-zhelanov),
> licensed under CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/)

## Musiques de zone (générées)

| Fichier | Carte(s) | Origine |
|---|---|---|
| `forest_ambience.ogg` | biome Forêt (`MapData.biome`, ex. Orée de la forêt) | Synthèse maison, `tools/music_gen/build_forest_music.py` — aucun crédit requis |

2 min 30, bouclage sans couture depuis 0 (voir autoload/ZoneMusic.gd). Ne pas retoucher l'ogg :
modifier le script (SEED, STEM_DB…) et le relancer.
