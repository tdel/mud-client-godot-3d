"""Outil hors-ligne : fiches visuelles MonsterModel (.tres) des monstres L2 de
tools/monster_gen/build_monsters.py, et table MonsterCatalog.MODELS (nom serveur -> fiche).

Chaque monstre a sa fiche, même quand plusieurs partagent un modèle : échelle, teinte
(material_colors sur les matériaux unis des packs Quaternius, `tint` multiplicatif sur les
modèles texturés) et armes (squelettes KayKit) les distinguent. Modèles et provenance :
assets/monsters/CREDITS.md. Réglage visuel : tools/monster_preview (--gallery=all).

Usage : python -I tools/monster_gen/build_monster_models.py   (depuis la racine du projet)
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "scenes/game/entities/MonsterCatalog.gd"

# Modèles : chemin, clips (idle, run, attack, death), vitesse de lecture de la course,
# hauteur du sommet du modèle à l'échelle 1 (gabarit : nom flottant, zone cliquable).
CA = "CharacterArmature|"
BASES = {
    "zombie": ("zombie/zombie.glb", ("Idle", "Walk", "Punch", "Death"), 1.0, 1.36),
    "orc": ("orc/orc.glb", (CA + "Idle", CA + "Run", CA + "Weapon", CA + "Death"), 1.0, 3.2),
    "yeti": ("bugbear/yeti.glb", (CA + "Idle", CA + "Run", CA + "Punch", CA + "Death"), 1.0, 2.8),
    "monkroose": ("ratman/monkroose.glb", (CA + "Idle", CA + "Run", CA + "Punch", CA + "Death"), 1.0, 2.9),
    "dino": ("lizardman/dino.glb", (CA + "Idle", CA + "Run", CA + "Weapon", CA + "Death"), 1.0, 3.1),
    "bunny": ("elpy/bunny.glb", (CA + "Idle", CA + "Run", CA + "Punch", CA + "Death"), 1.0, 3.3),
    "imp": ("imp/demon_flying.glb", (CA + "Flying_Idle", CA + "Fast_Flying", CA + "Punch", CA + "Death"), 1.0, 2.8),
    "ghost": ("wraith/ghost.glb", (CA + "Flying_Idle", CA + "Fast_Flying", CA + "Punch", CA + "Death"), 1.0, 3.4),
    "hywirl": ("gremlin/hywirl.glb", (CA + "Flying_Idle", CA + "Fast_Flying", CA + "Headbutt", CA + "Death"), 1.0, 2.8),
    "armabee": ("stakato/armabee.glb", (CA + "Flying_Idle", CA + "Fast_Flying", CA + "Punch", CA + "Death"), 1.0, 3.1),
    "armabee_evolved": ("stakato/armabee_evolved.glb", (CA + "Flying_Idle", CA + "Fast_Flying", CA + "Punch", CA + "Death"), 1.0, 3.0),
    "bat": ("bat/bat.glb", ("BatArmature|Bat_Flying", "BatArmature|Bat_Flying", "BatArmature|Bat_Attack", "BatArmature|Bat_Death"), 1.4, 3.4),
    "wasp": ("wasp/wasp.glb", ("WaspArmature|Wasp_Flying", "WaspArmature|Wasp_Flying", "WaspArmature|Wasp_Attack", "WaspArmature|Wasp_Death"), 1.5, 4.0),
    "snake": ("leech/snake.glb", ("SnakeArmature|Snake_Idle", "SnakeArmature|Snake_Walk", "SnakeArmature|Snake_Attack", "SnakeArmature|Snake_Jump"), 1.0, 2.4),
    "frog": ("toad/frog.glb", ("FrogArmature|Frog_Idle", "FrogArmature|Frog_Jump", "FrogArmature|Frog_Attack", "FrogArmature|Frog_Death"), 1.0, 1.45),
    "spider": ("spider/spider.glb", ("SpiderArmature|Spider_Idle", "SpiderArmature|Spider_Walk", "SpiderArmature|Spider_Attack", "SpiderArmature|Spider_Death"), 1.3, 1.9),
    "wolf": ("keltir/keltir.glb", ("Idle", "Gallop", "Attack", "Death"), 1.0, 2.7),
    "sk_warrior": ("skeleton/Skeleton_Warrior.glb", ("Idle", "Running_A", "1H_Melee_Attack_Chop", "Death_A"), 1.0, 2.55),
    "sk_rogue": ("skeleton/Skeleton_Rogue.glb", ("Idle", "Running_A", "1H_Melee_Attack_Stab", "Death_A"), 1.0, 2.3),
    "sk_minion": ("skeleton/Skeleton_Minion.glb", ("Idle", "Running_A", "1H_Melee_Attack_Chop", "Death_A"), 1.0, 2.3),
    "sk_mage": ("skeleton/Skeleton_Mage.glb", ("Idle", "Running_A", "1H_Melee_Attack_Slice_Diagonal", "Death_B"), 1.0, 2.6),
}
SHOOT = "1H_Ranged_Shoot"
# Hauteur de vol (m) des modèles dont le clip de vol reste au niveau du sol.
HOVER = {"bat": 0.9}
WEAPONS = "skeleton/weapons/Skeleton_%s.gltf"


def c(r, g, b):
    return (r, g, b)


# nom serveur -> (dossier, base, échelle, {matériau: couleur}, teinte, {os: arme}, clip d'attaque remplacé)
MODELS = {}


def add(name, base, scale, colors=None, tint=None, weapons=None, attack=None, folder=None):
    MODELS[name] = dict(base=base, scale=scale, colors=colors or {}, tint=tint, weapons=weapons or {}, attack=attack,
                        folder=folder or BASES[base][0].split("/")[0])


# --- Bêtes des bois (loup Quaternius recoloré, comme le Brown Keltir) -------------------------
add("Young Keltir", "wolf", 0.17, {"Main": c(0.62, 0.42, 0.24), "Main_Light": c(0.86, 0.72, 0.52)})
add("Elder Keltir", "wolf", 0.26, {"Main": c(0.33, 0.21, 0.12), "Main_Light": c(0.62, 0.48, 0.32)})
add("Wolf", "wolf", 0.25)
add("Elder Wolf", "wolf", 0.29, {"Main": c(0.30, 0.30, 0.32), "Main_Light": c(0.58, 0.58, 0.60)})
add("Shadow Beast", "wolf", 0.33, {"Main": c(0.12, 0.09, 0.16), "Main_Light": c(0.30, 0.22, 0.38)})
add("Elpy", "bunny", 0.2, {"Bunny_Main": c(0.93, 0.90, 0.84), "Bunny_Secondary": c(0.95, 0.72, 0.74)})
add("Gremlin", "hywirl", 0.2, {"Hywirl_Main": c(0.42, 0.62, 0.30)})
add("Giant Toad", "frog", 0.4, {"Green": c(0.38, 0.48, 0.22), "Yellow": c(0.74, 0.70, 0.42)})
add("Toad Lord", "frog", 0.6, {"Green": c(0.34, 0.30, 0.16), "Yellow": c(0.62, 0.52, 0.30), "Red": c(0.55, 0.12, 0.10)})
# --- Orques, gobelins, bugbears, loups-garous, hommes-rats, lézards -----------------------------
add("Orc", "orc", 0.52)
add("Orc Grunt", "orc", 0.54, {"Orc_Main": c(0.40, 0.50, 0.28)})
add("Orc Archer", "orc", 0.5, {"Orc_Main": c(0.48, 0.52, 0.30), "Belt": c(0.30, 0.22, 0.14)})
add("Orc Fighter", "orc", 0.58, {"Orc_Main": c(0.36, 0.42, 0.24), "Orc_Hair": c(0.12, 0.08, 0.06)})
add("Goblin", "orc", 0.36, {"Orc_Main": c(0.55, 0.60, 0.25), "Orc_Secondary": c(0.42, 0.34, 0.22)})
add("Goblin Scout", "orc", 0.38, {"Orc_Main": c(0.50, 0.56, 0.22), "Orc_Secondary": c(0.30, 0.38, 0.22)})
add("Vuku Orc", "orc", 0.56, {"Orc_Main": c(0.46, 0.36, 0.26), "Orc_Hair": c(0.55, 0.15, 0.10)})
add("Vuku Orc Archer", "orc", 0.54, {"Orc_Main": c(0.50, 0.40, 0.28), "Orc_Hair": c(0.55, 0.15, 0.10)})
add("Werewolf", "yeti", 0.62, {"Yeti_Main": c(0.36, 0.34, 0.34), "Yeti_Secondary": c(0.20, 0.18, 0.18)}, folder="werewolf")
add("Werewolf Hunter", "yeti", 0.66, {"Yeti_Main": c(0.24, 0.22, 0.22), "Yeti_Secondary": c(0.48, 0.20, 0.14)}, folder="werewolf")
add("Tumran Bugbear Warrior", "yeti", 0.8, {"Yeti_Main": c(0.46, 0.32, 0.20), "Yeti_Secondary": c(0.30, 0.20, 0.12)})
add("Veelan Bugbear", "yeti", 0.76, {"Yeti_Main": c(0.52, 0.40, 0.24), "Yeti_Secondary": c(0.36, 0.26, 0.15)})
add("Veelan Bugbear Warrior", "yeti", 0.82, {"Yeti_Main": c(0.40, 0.30, 0.20), "Yeti_Secondary": c(0.55, 0.22, 0.14)})
add("Bugbear Raider", "yeti", 0.74, {"Yeti_Main": c(0.50, 0.36, 0.22), "Yeti_Secondary": c(0.26, 0.18, 0.10)})
add("Ratman Spy", "monkroose", 0.48, {"Monkroose_Main": c(0.48, 0.44, 0.40), "Monkroose_Secondary": c(0.70, 0.62, 0.56)})
add("Ratman Hunter", "monkroose", 0.5, {"Monkroose_Main": c(0.40, 0.34, 0.28), "Monkroose_Secondary": c(0.64, 0.56, 0.48)})
add("Ratman Sub Chieftain", "monkroose", 0.54, {"Monkroose_Main": c(0.30, 0.28, 0.26), "Monkroose_Secondary": c(0.55, 0.20, 0.16)})
add("Ratman Chieftain", "monkroose", 0.58, {"Monkroose_Main": c(0.24, 0.22, 0.22), "Monkroose_Secondary": c(0.75, 0.60, 0.25)})
add("Sukar Wererat Chief", "monkroose", 0.85, {"Monkroose_Main": c(0.16, 0.14, 0.16), "Monkroose_Secondary": c(0.70, 0.12, 0.10)})
add("Maille Lizardman", "dino", 0.56, {"Dino_Main": c(0.30, 0.46, 0.26), "Dino_Secondary": c(0.70, 0.66, 0.44)})
add("Maille Lizardman Scout", "dino", 0.54, {"Dino_Main": c(0.38, 0.48, 0.24), "Dino_Secondary": c(0.62, 0.58, 0.38)})
add("Maille Lizardman Guard", "dino", 0.6, {"Dino_Main": c(0.22, 0.38, 0.30), "Dino_Secondary": c(0.60, 0.62, 0.50)})
add("Maille Lizardman Warrior", "dino", 0.62, {"Dino_Main": c(0.26, 0.34, 0.20), "Dino_Secondary": c(0.55, 0.30, 0.20)})
add("Maille Lizardman Shaman", "dino", 0.56, {"Dino_Main": c(0.22, 0.36, 0.44), "Dino_Secondary": c(0.70, 0.70, 0.56)})
add("Maille Lizardman Matriarch", "dino", 0.68, {"Dino_Main": c(0.36, 0.24, 0.40), "Dino_Secondary": c(0.78, 0.66, 0.36)})
# --- Morts-vivants -----------------------------------------------------------------------------
add("Ruin Zombie", "zombie", 1.25)
add("Ruin Zombie Leader", "zombie", 1.32, tint=c(0.78, 0.84, 0.72))
add("Zombie Soldier", "zombie", 1.3, tint=c(0.80, 0.76, 0.70))
add("Zombie Warrior", "zombie", 1.38, tint=c(0.86, 0.68, 0.64))
add("Zombie Lord Crowl", "zombie", 2.1, tint=c(0.62, 0.52, 0.72))
add("Skeleton Tracker", "sk_rogue", 0.72, weapons={"handslot.r": "Blade", "handslot.l": "Shield_Small_A"})
add("Skeleton Tracker Leader", "sk_rogue", 0.76, tint=c(0.78, 0.74, 0.70), weapons={"handslot.r": "Blade", "handslot.l": "Shield_Small_A"})
add("Skeleton Scout", "sk_rogue", 0.72, tint=c(0.92, 0.88, 0.80), weapons={"handslot.r": "Crossbow"}, attack=SHOOT)
add("Skeleton Bowman", "sk_minion", 0.74, weapons={"handslot.r": "Crossbow"}, attack=SHOOT)
add("Ruin Spartoi", "sk_warrior", 0.72, weapons={"handslot.r": "Blade", "handslot.l": "Shield_Large_A"})
add("Raging Spartoi", "sk_warrior", 0.76, tint=c(0.90, 0.66, 0.60), weapons={"handslot.r": "Blade", "handslot.l": "Shield_Small_A"})
add("Shield Skeleton", "sk_minion", 0.72, weapons={"handslot.r": "Axe", "handslot.l": "Shield_Large_A"})
add("Skeleton Infantryman", "sk_warrior", 0.7, tint=c(0.86, 0.84, 0.78), weapons={"handslot.r": "Axe", "handslot.l": "Shield_Small_A"})
add("Soul Scavenger", "sk_mage", 1.0, tint=c(0.72, 0.70, 0.90), weapons={"handslot.r": "Blade"})
add("Horror Mist Ripper", "ghost", 0.5, {"Ghost_Main": c(0.62, 0.70, 0.74)})
# --- Imps, chauves-souris ----------------------------------------------------------------------
add("Ruin Imp", "imp", 0.42, {"Demon_Main": c(0.62, 0.26, 0.20)})
add("Ruin Imp Elder", "imp", 0.48, {"Demon_Main": c(0.40, 0.18, 0.36)})
add("Scavenger Bat", "bat", 0.3, {"Main": c(0.34, 0.28, 0.26), "Belly": c(0.52, 0.44, 0.38)})
add("Ruin Bat", "bat", 0.34, {"Main": c(0.22, 0.18, 0.22), "Belly": c(0.46, 0.30, 0.30)})
# --- Insectes et bêtes du marais ---------------------------------------------------------------
add("Giant Mist Leech", "snake", 0.5, {"DarkGreen": c(0.24, 0.18, 0.20), "LightGreen": c(0.44, 0.32, 0.30), "Purple": c(0.36, 0.20, 0.24)})
add("Gray Ant", "spider", 0.34, {"Material": c(0.40, 0.40, 0.42), "Material.001": c(0.22, 0.22, 0.24)})
add("Giant Crimson Ant", "spider", 0.38, {"Material": c(0.55, 0.14, 0.10), "Material.001": c(0.30, 0.08, 0.06)})
add("Pinrul", "spider", 0.3, {"Material": c(0.62, 0.50, 0.30), "Material.001": c(0.36, 0.28, 0.16)})
add("Marsh Spider", "spider", 0.42, {"Material": c(0.26, 0.30, 0.20), "Material.001": c(0.48, 0.52, 0.26)})
add("Giant Araneid", "spider", 0.46, {"Material": c(0.36, 0.26, 0.18), "Material.001": c(0.58, 0.44, 0.28)})
add("Poison Araneid", "spider", 0.46, {"Material": c(0.26, 0.40, 0.16), "Material.001": c(0.62, 0.26, 0.56)})
add("King of the Araneid", "spider", 0.62, {"Material": c(0.18, 0.10, 0.12), "Material.001": c(0.70, 0.14, 0.10)})
add("Stinger Wasp", "wasp", 0.4)
add("Marsh Stakato", "armabee", 0.46, {"Armabee_Main": c(0.42, 0.46, 0.22), "Armabee_Secondary": c(0.26, 0.22, 0.14)}, folder="stakato")
add("Marsh Stakato Worker", "armabee", 0.44, {"Armabee_Main": c(0.52, 0.42, 0.22), "Armabee_Secondary": c(0.30, 0.24, 0.14)}, folder="stakato")
add("Marsh Stakato Soldier", "armabee", 0.5, {"Armabee_Main": c(0.34, 0.40, 0.26), "Armabee_Secondary": c(0.55, 0.20, 0.12)}, folder="stakato")
add("Marsh Stakato Drone", "armabee_evolved", 0.5, {"Armabee_Main": c(0.30, 0.36, 0.20), "Armabee_Secondary": c(0.16, 0.14, 0.10)}, folder="stakato")
add("Stakato Queen Zyrnna", "armabee_evolved", 0.95, {"Armabee_Main": c(0.40, 0.22, 0.46), "Armabee_Secondary": c(0.82, 0.66, 0.26)}, folder="stakato")
# --- Neutral Zone -----------------------------------------------------------------------------
add("Scavenger Spider", "spider", 0.36, {"Material": c(0.30, 0.26, 0.22), "Material.001": c(0.52, 0.46, 0.36)})
add("Moonstone Beast", "wolf", 0.34, {"Main": c(0.62, 0.66, 0.74), "Main_Light": c(0.86, 0.90, 0.96)})
add("Scavenger Wererat", "monkroose", 0.5, {"Monkroose_Main": c(0.44, 0.38, 0.34), "Monkroose_Secondary": c(0.30, 0.26, 0.24)})
add("Arachnid Tracker", "spider", 0.42, {"Material": c(0.20, 0.20, 0.24), "Material.001": c(0.66, 0.58, 0.30)})
add("Lycanthrope", "yeti", 0.68, {"Yeti_Main": c(0.30, 0.26, 0.24), "Yeti_Secondary": c(0.62, 0.56, 0.50)}, folder="werewolf")
# --- Fellmere Lake : lézards Felim, ours, loups-garous Gora, camp des Ol Mahum -----------------
add("Felim Lizardman", "dino", 0.54, {"Dino_Main": c(0.42, 0.52, 0.34), "Dino_Secondary": c(0.76, 0.70, 0.50)})
add("Felim Lizardman Scout", "dino", 0.52, {"Dino_Main": c(0.48, 0.50, 0.30), "Dino_Secondary": c(0.66, 0.58, 0.40)})
add("Felim Lizardman Warrior", "dino", 0.6, {"Dino_Main": c(0.34, 0.44, 0.30), "Dino_Secondary": c(0.60, 0.36, 0.24)})
add("Red Bear", "yeti", 0.7, {"Yeti_Main": c(0.52, 0.24, 0.16), "Yeti_Secondary": c(0.34, 0.16, 0.10)}, folder="bear")
add("Grizzly Bear", "yeti", 0.76, {"Yeti_Main": c(0.40, 0.30, 0.22), "Yeti_Secondary": c(0.26, 0.20, 0.14)}, folder="bear")
add("Gora Werewolf", "yeti", 0.64, {"Yeti_Main": c(0.42, 0.36, 0.28), "Yeti_Secondary": c(0.22, 0.18, 0.14)}, folder="werewolf")
add("Arachnid Predator", "spider", 0.48, {"Material": c(0.16, 0.14, 0.16), "Material.001": c(0.60, 0.20, 0.12)})
add("Ratman Warrior", "monkroose", 0.54, {"Monkroose_Main": c(0.36, 0.30, 0.26), "Monkroose_Secondary": c(0.50, 0.42, 0.20)})
add("Ol Mahum Novice", "orc", 0.56, {"Orc_Main": c(0.56, 0.46, 0.36), "Orc_Hair": c(0.20, 0.16, 0.12)}, folder="olmahum")
add("Ol Mahum Recruit", "orc", 0.6, {"Orc_Main": c(0.52, 0.42, 0.32), "Orc_Hair": c(0.24, 0.18, 0.12)}, folder="olmahum")
add("Ol Mahum Patrol", "orc", 0.62, {"Orc_Main": c(0.48, 0.40, 0.34), "Belt": c(0.40, 0.18, 0.12)}, folder="olmahum")
add("Ol Mahum Guard", "orc", 0.64, {"Orc_Main": c(0.46, 0.38, 0.30), "Belt": c(0.30, 0.30, 0.34)}, folder="olmahum")
add("Ol Mahum Supplier", "orc", 0.6, {"Orc_Main": c(0.58, 0.48, 0.36), "Belt": c(0.46, 0.34, 0.18)}, folder="olmahum")
add("Ol Mahum Straggler", "orc", 0.6, {"Orc_Main": c(0.44, 0.40, 0.36), "Orc_Hair": c(0.40, 0.36, 0.32)}, folder="olmahum")
add("Ol Mahum Officer", "orc", 0.68, {"Orc_Main": c(0.42, 0.34, 0.28), "Belt": c(0.62, 0.48, 0.18)}, folder="olmahum")
add("Ol Mahum Captain", "orc", 0.72, {"Orc_Main": c(0.38, 0.30, 0.24), "Orc_Hair": c(0.62, 0.14, 0.10), "Belt": c(0.70, 0.56, 0.20)}, folder="olmahum")
add("Hungry Eye", "hywirl", 0.32, {"Hywirl_Main": c(0.60, 0.30, 0.34)}, folder="eye")
add("Wandering Eye", "hywirl", 0.3, {"Hywirl_Main": c(0.46, 0.40, 0.58)}, folder="eye")
add("Greyclaw Kutus", "yeti", 1.05, {"Yeti_Main": c(0.46, 0.46, 0.48), "Yeti_Secondary": c(0.20, 0.20, 0.22)}, folder="werewolf")
add("Princess Molrang", "dino", 0.95, {"Dino_Main": c(0.50, 0.30, 0.52), "Dino_Secondary": c(0.86, 0.72, 0.36)})
# --- Execution Grounds : esprits des suppliciés, goules, golems, arbres aux pendus --------------
add("Specter", "ghost", 0.46, {"Ghost_Main": c(0.70, 0.76, 0.82)})
add("Sorrow Maiden", "ghost", 0.48, {"Ghost_Main": c(0.62, 0.66, 0.86)})
add("Neer Crawler", "zombie", 1.2, tint=c(0.70, 0.74, 0.62))
add("Neer Ghoul Berserker", "zombie", 1.34, tint=c(0.84, 0.62, 0.56))
add("Strain", "zombie", 1.28, tint=c(0.66, 0.70, 0.76))
add("Ghoul", "zombie", 1.36, tint=c(0.60, 0.66, 0.54))
add("Amber Basilisk", "dino", 0.66, {"Dino_Main": c(0.66, 0.46, 0.18), "Dino_Secondary": c(0.86, 0.70, 0.36)}, folder="basilisk")
add("Granite Golem", "yeti", 0.9, {"Yeti_Main": c(0.46, 0.46, 0.46), "Yeti_Secondary": c(0.30, 0.30, 0.32)}, folder="golem")
add("Dead Seeker", "wolf", 0.36, {"Main": c(0.28, 0.24, 0.20), "Main_Light": c(0.52, 0.46, 0.38)})
add("Hangman Tree", "yeti", 0.92, {"Yeti_Main": c(0.30, 0.24, 0.16), "Yeti_Secondary": c(0.24, 0.32, 0.18)}, folder="tree")
add("Revenant of Sir Calibus", "sk_warrior", 1.15, tint=c(0.74, 0.80, 0.92), weapons={"handslot.r": "Blade", "handslot.l": "Shield_Large_A"})
add("Guillotine, Warden of the Execution Grounds", "sk_warrior", 1.25, tint=c(0.80, 0.56, 0.52), weapons={"handslot.r": "Axe"})
# --- Dion Castle : plaines de Dion, lézards Delu, yeux et golems des plaines --------------------
add("Tumran Bugbear", "yeti", 0.76, {"Yeti_Main": c(0.50, 0.36, 0.22), "Yeti_Secondary": c(0.34, 0.24, 0.14)})
add("Dire Wolf", "wolf", 0.34, {"Main": c(0.22, 0.20, 0.20), "Main_Light": c(0.46, 0.40, 0.36)})
add("Monster Eye Gazer", "hywirl", 0.34, {"Hywirl_Main": c(0.36, 0.52, 0.46)}, folder="eye")
add("Watchman of the Plains", "hywirl", 0.4, {"Hywirl_Main": c(0.64, 0.56, 0.28)}, folder="eye")
add("Cursed Seer", "hywirl", 0.42, {"Hywirl_Main": c(0.40, 0.20, 0.44)}, folder="eye")
add("Roughly Hewn Rock Golem", "yeti", 0.95, {"Yeti_Main": c(0.52, 0.48, 0.42), "Yeti_Secondary": c(0.36, 0.33, 0.30)}, folder="golem")
add("Delu Lizardman Supplier", "dino", 0.58, {"Dino_Main": c(0.30, 0.40, 0.46), "Dino_Secondary": c(0.70, 0.64, 0.48)})
add("Delu Lizardman Special Agent", "dino", 0.58, {"Dino_Main": c(0.24, 0.34, 0.40), "Dino_Secondary": c(0.50, 0.56, 0.40)})
add("Delu Lizardman Shaman", "dino", 0.6, {"Dino_Main": c(0.28, 0.30, 0.52), "Dino_Secondary": c(0.78, 0.74, 0.58)})
add("Delu Lizardman Commander", "dino", 0.7, {"Dino_Main": c(0.20, 0.30, 0.36), "Dino_Secondary": c(0.80, 0.62, 0.22)})


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def color(rgb):
    return "Color(%.2f, %.2f, %.2f, 1)" % rgb


def tres(name, m):
    path, clips, run_speed, top = BASES[m["base"]]
    scale = m["scale"]
    ext = [("Script", "res://scenes/game/entities/MonsterModel.gd"), ("PackedScene", "res://assets/monsters/" + path)]
    weapon_ids = {}
    for bone, weapon in m["weapons"].items():
        ext.append(("PackedScene", "res://assets/monsters/" + WEAPONS % weapon))
        weapon_ids[bone] = len(ext)
    lines = [f'[gd_resource type="Resource" script_class="MonsterModel" load_steps={len(ext) + 1} format=3]', ""]
    for i, (kind, res) in enumerate(ext, 1):
        lines.append(f'[ext_resource type="{kind}" path="{res}" id="{i}"]')
    hover = HOVER.get(m["base"], 0.0)
    head = top * scale + hover
    pick_r = max(0.3, min(0.9, head * 0.35))
    lines += ["", "[resource]", 'script = ExtResource("1")', 'scene = ExtResource("2")', f"model_scale = {scale:g}",
              "yaw_degrees = 180.0"]
    if m["colors"]:
        entries = ",\n".join(f'"{k}": {color(v)}' for k, v in m["colors"].items())
        lines.append("material_colors = Dictionary[String, Color]({\n" + entries + "\n})")
    if m["weapons"]:
        entries = ",\n".join(f'"{bone}": ExtResource("{i}")' for bone, i in weapon_ids.items())
        lines.append("attachments = Dictionary[String, PackedScene]({\n" + entries + "\n})")
    if m["tint"]:
        lines.append(f"tint = {color(m['tint'])}")
    if hover:
        lines.append(f"hover_height = {hover:g}")
    idle, run, attack, death = clips
    lines += [f'idle_anim = &"{idle}"', f'run_anim = &"{run}"', f'attack_anim = &"{m["attack"] or attack}"',
              f'death_anim = &"{death}"', f"run_speed_scale = {run_speed:g}", "attack_speed_scale = 1.0",
              f"head_height = {head:.2f}", f"pick_radius = {pick_r:.2f}", f"pick_height = {max(0.8, head):.2f}", ""]
    return "\n".join(lines)


def main():
    entries = []
    for name, m in MODELS.items():
        rel = f'{m["folder"]}/{slug(name)}.tres'
        out = ROOT / "assets/monsters" / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(tres(name, m), encoding="utf-8", newline="\n")
        entries.append(f'\t"{name.lower()}": preload("res://assets/monsters/{rel}"),')
    text = CATALOG.read_text(encoding="utf-8")
    begin = "\t# --- Fiches générées par tools/monster_gen/build_monster_models.py ---"
    end = "\t# --- Fin des fiches générées ---"
    block = "\n".join([begin] + entries + [end])
    if begin in text:
        text = re.sub(re.escape(begin) + r".*?" + re.escape(end), lambda _: block, text, flags=re.S)
    else:
        text = text.replace('\t"brown keltir": preload("res://assets/monsters/keltir/brown_keltir.tres"),\n',
                            '\t"brown keltir": preload("res://assets/monsters/keltir/brown_keltir.tres"),\n' + block + "\n")
    CATALOG.write_text(text, encoding="utf-8", newline="\n")
    print(f"{len(MODELS)} fiches écrites, MonsterCatalog.MODELS mis à jour")


if __name__ == "__main__":
    main()
