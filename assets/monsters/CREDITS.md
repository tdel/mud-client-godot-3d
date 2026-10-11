# Modèles de monstres — provenance

Tous les modèles sont sous licence CC0 (domaine public). Fiches (échelle, clips, teintes,
armes) : une `.tres` MonsterModel par monstre, écrites par
`tools/monster_gen/build_monster_models.py` (sauf `fox.tres` et `brown_keltir.tres`).

| Dossier | Modèle | Auteur | Source | Monstres |
|---|---|---|---|---|
| `fox/fox.glb` | Fox (Animated Animal Pack) | Quaternius | https://poly.pizza/m/Bc97C66HKi | Fox |
| `keltir/keltir.glb` | Wolf (Animated Animal Pack) | Quaternius | https://poly.pizza/m/P1gU3Qkr9r | Keltirs, Wolf, Elder Wolf, Shadow Beast |
| `zombie/zombie.glb` | Zombie (Zombie Apocalypse Kit) | Quaternius | https://poly.pizza/m/VlXjG0N8Eg | Zombies, Zombie Lord Crowl |
| `orc/orc.glb` | Orc (Ultimate Monsters) | Quaternius | https://poly.pizza/m/5vO2YJsPEf | Orcs, Goblins, Vuku Orcs |
| `bugbear/yeti.glb` | Yeti (Ultimate Monsters) | Quaternius | https://poly.pizza/m/ceRHrn8HHE | Bugbears, Werewolves |
| `ratman/monkroose.glb` | Monkroose (Ultimate Monsters) | Quaternius | https://poly.pizza/m/j4rVPvxyLg | Ratmen, Sukar Wererat Chief |
| `lizardman/dino.glb` | Dino (Ultimate Monsters) | Quaternius | https://poly.pizza/m/wuerCFCWNR | Maille Lizardmen |
| `imp/demon_flying.glb` | Demon, volant (Ultimate Monsters) | Quaternius | https://poly.pizza/m/Mo2ky6vkf8 | Ruin Imps |
| `wraith/ghost.glb` | Ghost (Ultimate Monsters) | Quaternius | https://poly.pizza/m/Iip30bDHmu | Horror Mist Ripper |
| `gremlin/hywirl.glb` | Hywirl (Ultimate Monsters) | Quaternius | https://poly.pizza/m/zjr7CmWGER | Gremlin |
| `elpy/bunny.glb` | Bunny (Ultimate Monsters) | Quaternius | https://poly.pizza/m/irZjWFARyl | Elpy |
| `stakato/armabee.glb`, `armabee_evolved.glb` | Armabee / Armabee Evolved (Ultimate Monsters) | Quaternius | https://poly.pizza/m/42djT5zJnx, https://poly.pizza/m/GcttdvsqsQ | Stakatos, Stakato Queen Zyrnna |
| `bat/bat.glb` | Bat (Animated Monster Pack) | Quaternius | https://poly.pizza/m/hNO9XvjlKa | Scavenger Bat, Ruin Bat |
| `leech/snake.glb` | Snake (Animated Enemies) | Quaternius | https://poly.pizza/m/x9x0viZs8V | Giant Mist Leech |
| `wasp/wasp.glb` | Wasp (Animated Enemies) | Quaternius | https://poly.pizza/m/3aQgc75sUR | Stinger Wasp |
| `toad/frog.glb` | Frog (Animated Enemies) | Quaternius | https://poly.pizza/m/9Z2V8fpazF | Giant Toad, Toad Lord |
| `spider/spider.glb` | Spider (Animated Enemies) | Quaternius | https://poly.pizza/m/yRYJiAJyiM | Araignées, fourmis, Pinrul |
| `skeleton/*.glb`, `skeleton/weapons/*` | KayKit Character Pack: Skeletons 1.0 (Warrior, Rogue, Minion, Mage + armes) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 (voir `skeleton/LICENSE.txt`) | Squelettes, Spartoi, Soul Scavenger |

Clips du renard / loup : Idle, Idle_2, Idle_2_HeadLow, Walk, Gallop, Gallop_Jump, Jump_ToIdle,
Attack, Death, Eating, Idle_HitReact_Left/Right. Les modèles Ultimate Monsters préfixent leurs
clips (`CharacterArmature|Idle`...) ; le serpent n'a pas de clip de mort (son saut en tient
lieu). Armes KayKit accrochées aux os `handslot.r` / `handslot.l` (MonsterModel.attachments).

Réglage d'une fiche : `tools/monster_preview/MonsterPreview.tscn` (`--monster=Nom` pour les
quatre états, `--gallery=all` pour tous les monstres côte à côte).
