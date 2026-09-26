# Environnement (cartes décorées) — provenance

## Textures (`textures/`)

Toutes issues d'[ambientCG](https://ambientcg.com) (Lennart Demes), licence **CC0 1.0**
(domaine public). Téléchargées et redimensionnées par `tools/env_gen/fetch_textures.py`
(seules les cartes couleur / normale OpenGL / rugosité sont gardées).

| Fichiers | Asset ambientCG | Usage |
|---|---|---|
| `Grass004_*` | [Grass004](https://ambientcg.com/view?id=Grass004) | herbe (sol) |
| `Ground037_*` | [Ground037](https://ambientcg.com/view?id=Ground037) | sol forestier moussu |
| `Ground067_*` | [Ground067](https://ambientcg.com/view?id=Ground067) | chemins de terre |
| `PavingStones138_*` | [PavingStones138](https://ambientcg.com/view?id=PavingStones138) | route et place pavées |
| `Bark012_*`, `Bark014_*`, `Bark001_*` | [Bark012](https://ambientcg.com/view?id=Bark012), [Bark014](https://ambientcg.com/view?id=Bark014), [Bark001](https://ambientcg.com/view?id=Bark001) | écorces (chêne, sapin, bouleau) |
| `Planks023A_*`, `Planks021_*` | [Planks023A](https://ambientcg.com/view?id=Planks023A), [Planks021](https://ambientcg.com/view?id=Planks021) | scierie, piles de planches, caisses |
| `RoofingTiles001_*` | [RoofingTiles001](https://ambientcg.com/view?id=RoofingTiles001) | toit d'ardoise de la scierie |
| `Wood051_*`, `Wood049_*` | [Wood051](https://ambientcg.com/view?id=Wood051), [Wood049](https://ambientcg.com/view?id=Wood049) | poutres, poteaux et planches des panneaux |
| `Bricks089_*`, `Rock020_*` | [Bricks089](https://ambientcg.com/view?id=Bricks089), [Rock020](https://ambientcg.com/view?id=Rock020) | fontaine, socles, rochers |
| `Metal021_*` | [Metal021](https://ambientcg.com/view?id=Metal021) | fer des lampadaires, lame de scie |
| `PavingStones151_*` | [PavingStones151](https://ambientcg.com/view?id=PavingStones151) | pavés en éventail des rues du village |
| `Bricks076A_*` | [Bricks076A](https://ambientcg.com/view?id=Bricks076A) | remparts, tours et porte fortifiée |
| `Bricks102_*` | [Bricks102](https://ambientcg.com/view?id=Bricks102) | soubassements des maisons, puits |
| `Plaster003_*` | [Plaster003](https://ambientcg.com/view?id=Plaster003) | enduit des murs à colombages |
| `RoofingTiles006_*` | [RoofingTiles006](https://ambientcg.com/view?id=RoofingTiles006) | tuiles de terre cuite des maisons |
| `LeafSet024_*`, `LeafSet023_*`, `LeafSet019_*` | [LeafSet024](https://ambientcg.com/view?id=LeafSet024), [LeafSet023](https://ambientcg.com/view?id=LeafSet023), [LeafSet019](https://ambientcg.com/view?id=LeafSet019) | atlas de feuilles / rameaux de sapin |
| `Foliage001_*`, `Foliage002_*`, `Foliage006_*` | [Foliage001](https://ambientcg.com/view?id=Foliage001), [Foliage002](https://ambientcg.com/view?id=Foliage002), [Foliage006](https://ambientcg.com/view?id=Foliage006) | brins d'herbe, graminées |

Dérivées (même licence, produites par `tools/env_gen/build_foliage.py` à partir des atlas) :
`foliage_oak.png`, `foliage_birch.png`, `foliage_fir.png`, `foliage_grass.png`,
`foliage_grass_seed.png` ; `wood_rings.jpg` (cernes) est entièrement procédurale.

## Modèles (`models/`)

Tous générés par `tools/env_gen/build_environment.py` (Blender, sans ressource externe
autre que les textures ci-dessus) : arbres, buissons, rochers, fontaine, lampadaire, panneau,
scierie et ses abords. `models/village/` (remparts, tours, porte fortifiée, maisons, auberge,
forge, téléporteur, étals, puits, clôture) : générés par `tools/env_gen/build_village.py`.

## Son

`assets/audio/sfx/env_fountain_loop.ogg` : entièrement synthétisé par
`tools/env_gen/build_fountain_sound.py`.
