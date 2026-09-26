# Effets sonores

Tous les fichiers de ce dossier sont générés par `tools/sfx_gen/build_sfx.py` (voir son en-tête
pour la commande). Chaque son mixe des enregistrements libres de droits avec des couches
synthétisées par le script (tourbillons de vent à filtres résonants, chœur, cloches, grondements, nappes), puis passe
par une réverbération et une normalisation.

## Sources

Toutes les sources sont sous licence **CC0** (domaine public) : aucune attribution n'est
obligatoire, on les crédite quand même ici.

| Pack | Auteur | Utilisé pour | Source |
|---|---|---|---|
| 80 CC0 RPG SFX | rubberduck | feu, arcane, frappe physique, éclat de gemme (sorts, bijoux) | https://opengameart.org/content/80-cc0-rpg-sfx |
| 40 CC0 water / splash / slime SFX | rubberduck | eau (bulles, éclaboussures) | https://opengameart.org/content/40-cc0-water-splash-slime-sfx |
| 3 dark magic spells | qubodup | ténèbres / malédictions | https://opengameart.org/content/3-dark-magic-spells |
| Swish - bamboo stick weapon swooshes | qubodup | vent, élans d'arme | https://opengameart.org/content/swish-bamboo-stick-weapon-swhoshes |
| Magic Spell SFX | JaggedStone | motifs magiques (arcane, eau, vent, sacré, renforcement, soin) | https://opengameart.org/content/magic-spell-sfx |
| Interface Sounds | Kenney | tic de fin de recharge | https://kenney.nl/assets/interface-sounds |
| RPG Audio | Kenney | page tournée / livre refermé (fenêtres), dégainer, tissu, cuir, boucle, loquet (équipement) | https://kenney.nl/assets/rpg-audio |

## Fichiers

- `spell_<famille>_cast.ogg` : début d'incantation.
- `spell_<famille>_launch.ogg` : libération du sort.
- `spell_<famille>_impact.ogg` : arrivée d'un projectile sur sa cible (seulement pour les
  familles qui peuvent lancer un projectile).
- Familles : fire, water, wind, holy, dark (ténèbres et malédictions), arcane (sort non
  classé), heal, buff, physical. La correspondance élément → famille est dans
  `autoload/Sfx.gd`.
- `ui_*.ogg` : sons d'interface, joués sur le bus audio « UI » (slider « Interface »).
- `ui_window_open.ogg`, `ui_window_close.ogg` : ouverture (page qu'on tourne) et fermeture
  (livre qu'on referme) d'une fenêtre.
- `ui_item_<equip|unequip>_<weapon|armor|jewel>.ogg` : objet équipé / retiré, par famille
  (arme et bouclier, pièce d'armure, bijou — voir `Sfx.EQUIP_FAMILY`).
- `ui_cooldown_ready.ogg` : un skill sort de sa recharge.
- `event_level_up.ogg` : montée de niveau du joueur (bus « SFX », ~3,5 s) — entièrement
  synthétisé (tourbillon, harpe, cloches, chœur) plus un éclat de gemme de rubberduck.
