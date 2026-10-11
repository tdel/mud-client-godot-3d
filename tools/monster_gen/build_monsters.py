"""Outil hors-ligne : fiches monstres du serveur (backend data/monsters.xml) tirées des PNJ de
Lineage 2 High Five (datapack L2JMobius H5, stats/npcs/*.xml) pour les zones de la région de
Gludio et les anciennes petites zones de départ, plus la table nom -> templateId utilisée par
les générateurs de cartes (tools/map_gen/L2Monsters.gd).

Repris tels quels de L2 : nom, niveau, race, agressivité, PV, XP, éléments faibles/forts,
attributs (40/30/43/21/20/20, ceux des boss de raid 60/73/57/76/70/80). P.Atk/P.Def/M.Def sont
recalibrés : les armes et armures du jeu (data/items) sont environ dix fois plus faibles que
celles de L2 au-delà des premiers niveaux, recopier les défenses L2 rendrait les monstres de
niveau 20 intuables. On vise donc, contre un personnage du même niveau équipé comme le permet
la boutique (voir WEAPON / ARMOR ci-dessous) :
  - environ 4 coups (niveau 1) à 7 coups (niveau 35) pour tuer le monstre, sans soulshot ;
  - environ 12 coups du monstre pour tuer un Human Fighter ;
ce qui retombe sur les monstres de départ existants (Brown Keltir...). Les écarts propres à un
monstre (chef plus coriace, archer fragile, zombie lent) passent par les modificateurs ROLE.
Vitesse de course L2 x 1.3 (un humain court à 126 dans L2, 220 ici, soit x 1.75 : les monstres
restent un peu plus lents que le joueur, qui peut fuir). Rayon d'aggro : 6 cases pour un
monstre agressif, 0 sinon (MonsterAiEngine.scanAggro).

Les identifiants sont des UUID v5 dérivés du nom : relancer le script redonne les mêmes.

Usage : python -I tools/monster_gen/build_monsters.py <backend>/src/main/resources/data/monsters.xml
(réécrit les fiches générées en fin de fichier, conserve les fiches historiques, régénère
tools/map_gen/L2Monsters.gd).
"""
import math
import re
import sys
import uuid
from pathlib import Path

NAMESPACE = uuid.UUID("6f1e3c52-2b8a-4c7e-9d41-0a5b7e3f9c18")
BEGIN = "    <!-- ===== Fiches générées par tools/monster_gen/build_monsters.py : ne pas éditer à la main ===== -->"
END = "    <!-- ===== Fin des fiches générées ===== -->"

# Stats L2 H5 d'un monstre "standard" par niveau (identiques pour tous les monstres ordinaires
# d'un même niveau dans le datapack) : PV, P.Atk, M.Atk, P.Def, M.Def.
L2_STANDARD = {
    1: (39.7, 8.5, 5.8, 44.4, 29.6), 3: (57.5, 10.2, 7.0, 47.9, 31.9), 4: (68.2, 11.2, 7.7, 49.7, 33.1),
    5: (80.2, 12.3, 8.4, 51.6, 34.4), 6: (93.5, 13.5, 9.2, 53.5, 35.6), 7: (108.4, 14.8, 10.1, 55.5, 37.0),
    8: (124.9, 16.2, 11.1, 57.6, 38.3), 9: (143.2, 17.7, 12.1, 59.7, 39.7), 10: (163.3, 19.3, 13.2, 61.8, 41.2),
    15: (247, 29.6, 20.2, 73.6, 49.0), 16: (264, 32.2, 22.0, 76.1, 50.7), 17: (283, 34.9, 23.8, 78.7, 52.4),
    18: (302, 37.8, 25.8, 81.3, 54.2), 19: (322, 41.0, 28.0, 84.1, 56.0), 20: (343, 44.3, 30.3, 86.9, 57.8),
    21: (364, 47.9, 32.7, 89.7, 59.7), 22: (387, 51.8, 35.3, 92.7, 61.7), 23: (411, 55.8, 38.1, 95.6, 63.7),
    24: (435, 60.2, 41.1, 98.7, 65.7), 25: (461, 64.8, 44.3, 101.8, 67.8), 26: (488, 69.8, 47.6, 105.0, 69.9),
    27: (515, 75.0, 51.2, 108.3, 72.1), 28: (544, 80.5, 55.0, 111.6, 74.3), 29: (573, 86.4, 59.0, 115.0, 76.6),
    30: (604, 92.6, 63.3, 118.5, 78.9), 31: (636, 99.2, 67.8, 122.0, 81.2), 32: (668, 106.2, 72.5, 125.6, 83.6),
    33: (702, 113.5, 77.5, 129.2, 86.0), 34: (737, 121.2, 82.8, 132.9, 88.5), 35: (773, 129.3, 88.3, 136.7, 91.0),
}
# Niveaux 11-14 absents des zones relevées : interpolation géométrique entre 10 et 15.
for _lv in range(11, 15):
    _t = (_lv - 10) / 5
    L2_STANDARD[_lv] = tuple(a * (b / a) ** _t for a, b in zip(L2_STANDARD[10], L2_STANDARD[15]))
L2_STANDARD[2] = tuple((a * b) ** 0.5 for a, b in zip(L2_STANDARD[1], L2_STANDARD[3]))

MONSTER_ATTRS = {"STR": 40, "DEX": 30, "CON": 43, "INT": 21, "WIT": 20, "MEN": 20}
RAID_ATTRS = {"STR": 60, "DEX": 73, "CON": 57, "INT": 76, "WIT": 70, "MEN": 80}


def bonus(attr, score):
    """Attribute.bonus côté serveur (statBonus.xml L2J H5)."""
    base = {"STR": (1.036, 34.845), "INT": (1.020, 31.375), "CON": (1.030, 27.632), "MEN": (1.010, -0.060),
            "DEX": (1.009, 19.360), "WIT": (1.050, 20.000)}[attr]
    return round(base[0] ** (score - base[1]), 2)


def level_factor(level):
    return 1.0 + (level - 1) * 0.02


# Équipement attendu d'un personnage du niveau (boutiques de Gludio / Dion) : p.atk d'arme, p.def
# d'armure cumulée.
def weapon(level):
    for top, patk in ((3, 9), (8, 11), (14, 14), (22, 17), (30, 19)):
        if level <= top:
            return patk
    return 22


def armor(level):
    for top, pdef in ((5, 2), (10, 8), (15, 12), (22, 17), (30, 24)):
        if level <= top:
            return pdef
    return 30


def fighter_hp(level):
    return (68.3 + 11.635 * level + 0.065 * level * level) * bonus("CON", 43)


def player_patk(level):
    return weapon(level) * bonus("STR", 40) * level_factor(level)


def player_pdef(level):
    return armor(level) + bonus("CON", 43) * 6.0


# Rôles : multiplicateurs (p.atk, p.def/m.def) et bonus (précision, esquive, critique), vitesse
# d'attaque de "l'arme" (attackSpeed côté serveur).
ROLE = {
    "melee": (1.00, 1.00, 0, 0, 0, 270),
    "blunt": (1.05, 1.00, 2, -1, 0, 250),
    "dagger": (0.95, 0.95, 0, 2, 4, 300),
    "bow": (1.00, 0.85, 1, 0, 4, 230),
    "claw": (1.00, 1.00, 0, 1, 1, 280),
    "zombie": (1.10, 1.15, -2, -4, 0, 210),
    "flyer": (0.95, 0.90, 1, 4, 2, 290),
    "caster": (0.90, 0.90, 0, 0, 0, 240),
    "beast": (1.05, 1.05, 0, 0, 1, 260),
    "insect": (1.00, 1.05, 0, 1, 1, 280),
    "brute": (1.15, 1.10, 0, -2, 2, 240),
}
# Leaders / gardes : un peu plus forts que la piétaille du même niveau.
ELITE = (1.12, 1.12)

UNDEAD_RES = {"HOLY": -50, "DARK": 30}
BUG_RES = {"FIRE": -25}
BAT_RES = {"WIND": -25}
FAIRY_RES = {"WIND": 15}

# Objets du catalogue (data/items).
HEALING = "019fa0a5-80bf-7e84-87bf-5cf699c00315"
GREATER_HEALING = "6aeb7483-2694-4388-8c6b-f841fd5e48b4"
MAJOR_HEALING = "f9083584-d5af-458c-bb9b-3ee7714452e3"
MANA = "3a4a5836-051e-4641-aef8-7b6e6792322e"
GREATER_MANA = "7c1e9a4b-2d6f-4e8a-9c3b-5f1a7d9b0c2e"
ESCAPE = "5d6ae0ed-efda-412b-94b4-98677e2c8946"
ITEMS = {
    "Leather Cap": "d410f08b-8872-4ad1-984a-665dab47fd75", "Leather Tunic": "aa24f9ec-0608-4b46-819d-4c6087df1320",
    "Leather Pants": "83b1c12e-c594-4a7b-b0d0-cdd7dc2fca8f", "Leather Gloves": "4200e028-982b-4267-8c69-e62e305a5080",
    "Leather Boots": "8e96906e-1f06-40aa-b986-7946c1acd72d", "Wooden Shield": "8a692c7f-8461-4994-ab61-69d0079ed3fc",
    "Wooden Bow": "3c966b19-8f40-4791-9dd7-3a489f090f7b", "Wooden Club": "f3c8a065-ac0d-4913-9774-41098a6e088d",
    "Dagger": "ca8be0a4-9f92-4630-a918-2c7b3cf7c3cd", "Short Sword": "019fa0a5-80c0-7035-9c2d-113b09a275df",
    "Saber": "45785ec3-8118-4938-b614-3e3a03dabc5e", "Battle Axe": "21a73422-e8ee-49ba-8137-05b49a5dbea5",
    "Spear": "5b1f2d3e-6a7c-4e8f-9a01-2b3c4d5e6f70", "Tsurugi": "7ad6443f-65cf-4761-b894-5fa8dc859e2e",
    "Sword of Valhalla": "84349095-9c39-49e4-9f0a-1819dc7d1748", "Hammer of Ruin": "2f7c7759-45c8-4652-aea5-f244e1b11fc5",
    "Sword of Miracle": "7b732096-7d14-434b-b7d6-1569dd6ee37b", "Bow of Peril": "9f5b6c7d-aeb0-4c23-de45-6f708192a3b4",
    "Pike": "6c2e3f4a-7b8d-4f90-ab12-3c4d5e6f7081", "Wand of Flames": "6f1c2a3e-8b4d-4e7a-9c2f-1a3d5e7b9c1f",
    "Padded Armor": "153c7ce9-f976-45c5-ab58-5b5f42665e68", "Padded Helmet": "4ecc0ffd-3a7c-49ea-8af6-d0e76b0bb9dd",
    "Leather Armor": "019fcf0d-1f8b-7bc4-b7d8-eddd6c83c518", "Iron Helmet": "019faec6-116d-723d-b04c-76d51a2a2cb7",
    "Shield": "019fcf0d-1f8f-7d01-8e4f-fd592812a1a7", "Chain Mail": "019fcf0d-1f8c-7d43-9e98-a9944b4ccefe",
    "Plate Armor": "019fcf0d-1f8d-7c4c-9275-33c4af4410a8", "Zealot's Armor": "8b3e4c5a-0d6f-4a9c-9e4b-3c5f7a9b1d3e",
    "Helm of Terror": "9c4f5d6b-1e7a-4b0d-8f5c-4d6a8b0c2e4f", "Doom Breastplate": "044f02d7-ebcf-4275-8be2-c41a93695f96",
    "Doom Helmet": "3ca4de84-6813-4846-9fe7-9dfb3c245aa9", "Doom Gloves": "3b1d09c8-a3ec-4159-9f7d-403754c5ef39",
    "Garnet Ring": "0f50e068-ab87-41aa-9169-5eaa17a3c7ce", "Garnet Earring": "b0bc4f00-8f9f-44a4-9b7f-0095ab837218",
    "Amber Ring": "001d1121-6760-4831-83a3-a72b126f79f3", "Amber Earring": "bedb6df2-7bab-443c-8a3c-e97b9150d977",
    "Amber Necklace": "57201423-ae58-4cb7-a6c4-9bf856a76d4a", "Amethyst Ring": "40c0606e-29cc-448e-8906-8e229f0d5079",
    "Amethyst Necklace": "5da404a5-8f6e-4b67-9d06-556efdbddbd3", "Shield +1": "019fe3f6-b1ef-786d-bc17-46dd46660eb0",
}


def tier_loot(level):
    """Consommables communs selon la tranche de niveau."""
    if level <= 10:
        return [(HEALING, 0.10)]
    if level <= 24:
        return [(HEALING, 0.12), (GREATER_HEALING, 0.03), (MANA, 0.05), (ESCAPE, 0.01)]
    return [(GREATER_HEALING, 0.10), (GREATER_MANA, 0.05), (ESCAPE, 0.02)]


# (nom L2, id L2, niveau, race, agressif, PV L2, XP L2, rôle, élite, vitesse de course L2,
#  résistances, butin propre [(objet, chance)])
M = []


def mob(name, l2id, level, race, aggro, hp, xp, role, run, res=None, loot=(), elite=False):
    M.append(dict(name=name, l2id=l2id, level=level, race=race, aggro=aggro, hp=hp, xp=xp, role=role, run=run,
                  res=res or {}, loot=list(loot), elite=elite, raid=False))


def raid(name, l2id, level, race, hp, pa, pd, md, xp, run, res=None, loot=()):
    M.append(dict(name=name, l2id=l2id, level=level, race=race, aggro=False, hp=hp, xp=xp, role="melee", run=run,
                  res=res or {}, loot=list(loot), elite=False, raid=True, pa=pa, pd=pd, md=md))


I = ITEMS
# --- Sentier broussailleux (niveaux 3-5) : keltirs, loups et crapauds des bois ---------------
mob("Elder Keltir", 20544, 3, "ANIMAL", False, 57.5, 105, "beast", 110, loot=[(I["Leather Pants"], 0.03), (I["Leather Tunic"], 0.03)])
mob("Wolf", 20120, 4, "ANIMAL", False, 68.2, 141, "beast", 110, loot=[(I["Wooden Bow"], 0.02)])
mob("Elder Wolf", 20442, 5, "ANIMAL", False, 80.2, 176, "beast", 110, loot=[(I["Leather Gloves"], 0.03)], elite=True)
mob("Giant Toad", 20121, 5, "ANIMAL", False, 80.2, 178, "claw", 100, loot=[(I["Leather Boots"], 0.03)])
# --- Repaire sauvage (niveaux 5-10) : camp d'orques, gobelins et loups-garous -----------------
mob("Goblin", 20003, 5, "HUMANOID", False, 80.2, 176, "blunt", 110, loot=[(I["Garnet Ring"], 0.03), (I["Garnet Earring"], 0.02)])
mob("Orc", 20130, 6, "HUMANOID", False, 93.5, 213, "melee", 110, loot=[(I["Wooden Club"], 0.03)])
mob("Orc Grunt", 20131, 7, "HUMANOID", False, 108.4, 249, "blunt", 110, loot=[(I["Wooden Shield"], 0.04)])
mob("Orc Archer", 20006, 8, "HUMANOID", False, 124.9, 293, "bow", 110, loot=[(I["Wooden Bow"], 0.05)])
mob("Goblin Scout", 20326, 8, "HUMANOID", False, 124.9, 284, "blunt", 110, loot=[(I["Leather Cap"], 0.04), (I["Leather Armor"], 0.01)])
mob("Werewolf", 20132, 9, "HUMANOID", False, 143.2, 321, "claw", 120, loot=[(I["Padded Helmet"], 0.03)])
mob("Orc Fighter", 20093, 10, "HUMANOID", True, 163.3, 363, "melee", 110, loot=[(I["Short Sword"], 0.04), (I["Saber"], 0.01)], elite=True)
# --- Chemin du cimetière (niveaux 10-15) : loups-garous chasseurs, orques Vuku, bêtes d'ombre --
mob("Werewolf Hunter", 20343, 10, "HUMANOID", True, 163.3, 363, "blunt", 120, loot=[(I["Amber Ring"], 0.02)], elite=True)
mob("Vuku Orc", 20009, 14, "HUMANOID", False, 230, 650, "melee", 110, loot=[(I["Battle Axe"], 0.02)])
mob("Vuku Orc Archer", 20011, 15, "HUMANOID", False, 247, 700, "bow", 110, loot=[(I["Wooden Bow"], 0.04)])
mob("Shadow Beast", 20023, 15, "BEAST", False, 247, 720, "beast", 130, res={"DARK": 20, "HOLY": -20}, loot=[(I["Leather Armor"], 0.02)])
# --- Ruins of Agony (niveaux 15-25) -----------------------------------------------------------
mob("Ruin Zombie", 20026, 15, "UNDEAD", False, 247, 755, "zombie", 15, UNDEAD_RES, [(I["Padded Armor"], 0.03)])
mob("Ruin Zombie Leader", 20029, 16, "UNDEAD", False, 264, 807, "zombie", 15, UNDEAD_RES, [(I["Leather Armor"], 0.03)], elite=True)
mob("Skeleton Tracker", 20035, 17, "UNDEAD", False, 283, 605, "dagger", 140, UNDEAD_RES, [(I["Dagger"], 0.04), (I["Wooden Shield"], 0.03)])
mob("Skeleton Tracker Leader", 20042, 18, "UNDEAD", True, 302, 652, "dagger", 140, UNDEAD_RES, [(I["Dagger"], 0.05), (I["Shield"], 0.02)], elite=True)
mob("Skeleton Scout", 20045, 19, "UNDEAD", False, 322, 698, "bow", 140, UNDEAD_RES, [(I["Wooden Bow"], 0.05)])
mob("Skeleton Bowman", 20051, 20, "UNDEAD", False, 343, 734, "bow", 140, UNDEAD_RES, [(I["Bow of Peril"], 0.004)])
mob("Ruin Spartoi", 20054, 21, "UNDEAD", False, 364, 917, "melee", 140, UNDEAD_RES, [(I["Saber"], 0.04), (I["Tsurugi"], 0.004)])
mob("Raging Spartoi", 20060, 22, "UNDEAD", True, 387, 1005, "dagger", 140, UNDEAD_RES, [(I["Iron Helmet"], 0.03), (I["Tsurugi"], 0.005)], elite=True)
mob("Tumran Bugbear Warrior", 20064, 24, "GIANT", True, 435, 1145, "brute", 130, loot=[(I["Battle Axe"], 0.04), (I["Chain Mail"], 0.01)])
raid("Soul Scavenger", 25369, 25, "UNDEAD", 43316, 74.2, 305.5, 149.0, 2541012, 190, UNDEAD_RES,
     [(I["Tsurugi"], 0.35), (I["Sword of Valhalla"], 0.2), (I["Doom Gloves"], 0.3), (I["Amethyst Ring"], 0.25), (MAJOR_HEALING, 0.5)])
# --- Ruins of Despair (niveaux 15-25) ---------------------------------------------------------
mob("Shield Skeleton", 20514, 15, "UNDEAD", False, 247, 534, "blunt", 140, UNDEAD_RES, [(I["Shield"], 0.04), (I["Wooden Club"], 0.04)])
mob("Skeleton Infantryman", 20515, 16, "UNDEAD", False, 264, 570, "blunt", 140, UNDEAD_RES, [(I["Wooden Shield"], 0.05)])
mob("Ruin Imp", 20506, 17, "FAIRY", False, 283, 605, "flyer", 80, FAIRY_RES, [(I["Amber Earring"], 0.02)])
mob("Scavenger Bat", 20411, 18, "ANIMAL", False, 302, 640, "flyer", 80, BAT_RES, [(I["Garnet Earring"], 0.03)])
mob("Zombie Soldier", 20457, 19, "UNDEAD", False, 322, 958, "zombie", 15, UNDEAD_RES, [(I["Iron Helmet"], 0.03), (I["Chain Mail"], 0.008)])
mob("Ruin Bat", 20505, 20, "ANIMAL", False, 343, 712, "flyer", 80, BAT_RES, [(I["Amber Ring"], 0.02)])
mob("Ruin Imp Elder", 20507, 21, "FAIRY", True, 364, 935, "caster", 80, FAIRY_RES, [(I["Wand of Flames"], 0.02), (I["Amber Necklace"], 0.02)], elite=True)
mob("Zombie Warrior", 20458, 22, "UNDEAD", True, 387, 1421, "zombie", 15, UNDEAD_RES, [(I["Chain Mail"], 0.01), (I["Helm of Terror"], 0.004)], elite=True)
mob("Veelan Bugbear", 20401, 23, "GIANT", False, 411, 1054, "brute", 130, loot=[(I["Battle Axe"], 0.04)])
mob("Veelan Bugbear Warrior", 20402, 24, "GIANT", True, 435, 1145, "brute", 130, loot=[(I["Spear"], 0.04), (I["Chain Mail"], 0.01)], elite=True)
raid("Zombie Lord Crowl", 25149, 25, "UNDEAD", 43316, 74.2, 305.5, 149.0, 2541012, 190, UNDEAD_RES,
     [(I["Sword of Valhalla"], 0.25), (I["Plate Armor"], 0.15), (I["Doom Helmet"], 0.3), (I["Amethyst Necklace"], 0.2), (MAJOR_HEALING, 0.5)])
# --- Cruma Marshlands (niveaux 25-35) ---------------------------------------------------------
mob("Giant Mist Leech", 20225, 25, "BUG", False, 461, 1190, "insect", 110, BUG_RES, [(I["Leather Armor"], 0.02)])
mob("Gray Ant", 20226, 26, "BUG", False, 488, 1268, "insect", 130, BUG_RES, [(I["Iron Helmet"], 0.02)])
mob("Horror Mist Ripper", 20227, 27, "UNDEAD", True, 515, 1349, "claw", 100, UNDEAD_RES, [(I["Amber Necklace"], 0.02)])
mob("Giant Crimson Ant", 20228, 28, "BUG", False, 544, 1555, "insect", 130, BUG_RES, [(I["Zealot's Armor"], 0.01)])
mob("Marsh Stakato", 20157, 29, "HUMANOID", True, 573, 1811, "dagger", 120, BUG_RES, [(I["Doom Gloves"], 0.008), (I["Dagger"], 0.03)])
mob("Stinger Wasp", 20229, 30, "BUG", True, 604, 1744, "flyer", 90, BUG_RES, [(I["Amethyst Ring"], 0.004)])
mob("Marsh Stakato Worker", 20230, 31, "HUMANOID", False, 636, 1995, "blunt", 140, BUG_RES, [(I["Doom Helmet"], 0.008), (I["Chain Mail"], 0.015)])
mob("Toad Lord", 20231, 32, "ANIMAL", False, 668, 1946, "claw", 100, loot=[(I["Helm of Terror"], 0.01)])
mob("Marsh Stakato Soldier", 20232, 33, "HUMANOID", False, 702, 1900, "dagger", 155, BUG_RES, [(I["Sword of Valhalla"], 0.004), (I["Shield +1"], 0.004)])
mob("Marsh Spider", 20233, 34, "BUG", True, 737, 2241, "insect", 140, BUG_RES, [(I["Doom Breastplate"], 0.004)])
mob("Marsh Stakato Drone", 20234, 35, "HUMANOID", True, 773, 2267, "dagger", 174, BUG_RES, [(I["Hammer of Ruin"], 0.003), (I["Amethyst Necklace"], 0.004)], elite=True)
raid("Stakato Queen Zyrnna", 25023, 34, "HUMANOID", 87403, 284.0, 398.8, 194.6, 2316589, 170, BUG_RES,
     [(I["Sword of Miracle"], 0.15), (I["Hammer of Ruin"], 0.2), (I["Plate Armor"], 0.3), (I["Doom Breastplate"], 0.35), (MAJOR_HEALING, 0.6)])
# --- Gludio Castle : bois de l'ouest (lézards Maille, araignées) et de l'est (hommes-rats) ---
mob("Maille Lizardman", 20919, 20, "HUMANOID", False, 343, 320, "melee", 130, loot=[(I["Spear"], 0.03)])
mob("Maille Lizardman Scout", 20920, 22, "HUMANOID", False, 387, 712, "bow", 130, loot=[(I["Wooden Bow"], 0.04)])
mob("Maille Lizardman Guard", 20921, 24, "HUMANOID", True, 435, 515, "melee", 130, loot=[(I["Spear"], 0.04), (I["Pike"], 0.003)], elite=True)
mob("Giant Araneid", 20925, 24, "BUG", False, 435, 525, "insect", 140, BUG_RES, [(I["Leather Armor"], 0.03)])
mob("Poison Araneid", 20926, 25, "BUG", False, 461, 607, "insect", 140, BUG_RES, [(I["Zealot's Armor"], 0.01)])
mob("Maille Lizardman Warrior", 20922, 26, "HUMANOID", False, 488, 570, "brute", 130, loot=[(I["Pike"], 0.004)])
mob("King of the Araneid", 20927, 27, "BUG", True, 515, 872, "insect", 140, BUG_RES, [(I["Doom Gloves"], 0.01)], elite=True)
mob("Maille Lizardman Shaman", 20923, 28, "HUMANOID", False, 544, 835, "caster", 130, loot=[(I["Wand of Flames"], 0.03)])
mob("Maille Lizardman Matriarch", 20924, 30, "HUMANOID", True, 604, 1025, "melee", 130, loot=[(I["Shield +1"], 0.006), (I["Helm of Terror"], 0.01)], elite=True)
mob("Ratman Spy", 20360, 16, "HUMANOID", False, 264, 570, "dagger", 120, loot=[(I["Dagger"], 0.04)])
mob("Pinrul", 20032, 17, "BUG", False, 283, 605, "insect", 130, BUG_RES, [(I["Padded Armor"], 0.03)])
mob("Bugbear Raider", 20775, 17, "GIANT", True, 283, 599, "brute", 130, loot=[(I["Battle Axe"], 0.03)])
mob("Ratman Hunter", 20358, 18, "HUMANOID", False, 302, 640, "dagger", 120, loot=[(I["Leather Armor"], 0.02)])
mob("Ratman Sub Chieftain", 21093, 19, "HUMANOID", True, 322, 691, "dagger", 150, loot=[(I["Saber"], 0.03)], elite=True)
mob("Ratman Chieftain", 21094, 20, "HUMANOID", False, 343, 712, "melee", 155, loot=[(I["Sword of Valhalla"], 0.003), (I["Iron Helmet"], 0.03)], elite=True)
raid("Sukar Wererat Chief", 25357, 21, "HUMANOID", 37886, 53.1, 269.2, 131.3, 2646357, 190, None,
     [(I["Tsurugi"], 0.3), (I["Chain Mail"], 0.4), (I["Amethyst Ring"], 0.2), (MAJOR_HEALING, 0.4)])


def target_hits(level):
    return 4.0 + 3.0 * (level - 1) / 34.0


def build(m):
    level = m["level"]
    attrs = RAID_ATTRS if m["raid"] else MONSTER_ATTRS
    std = L2_STANDARD[level]
    patk_mul, def_mul, acc, eva, crit, atk_spd = ROLE[m["role"]]
    if m["elite"]:
        patk_mul *= ELITE[0]
        def_mul *= ELITE[1]
    hp = m["hp"]
    # Défense : le personnage du niveau tue un monstre ordinaire en target_hits coups.
    pdef_final = 70.0 * player_patk(level) * target_hits(level) / std[0] * def_mul
    mdef_final = pdef_final * std[4] / std[3]
    # Attaque : un Human Fighter du niveau meurt en ~12 coups.
    patk_final = fighter_hp(level) / 12.0 * player_pdef(level) / 70.0 * patk_mul
    gold = round(level * (4 + level * 0.2))
    xp = m["xp"]
    respawn = None
    if m["raid"]:
        # Boss de raid : défenses/attaque L2 relatives au monstre standard du niveau (frappe x 1.5 de\n        # plus : il se combat à plusieurs), PV
        # ramenés à 30 % (contenu de groupe, pas de quatre heures de frappe), XP à 5 %.
        pdef_final *= (m["pd"] / std[3]) ** 0.6
        mdef_final *= (m["md"] / std[4]) ** 0.6
        patk_final *= m["pa"] / std[1] * 1.5
        hp = hp * 0.3
        xp = xp * 0.05
        gold = 40 * level * 5
        acc, eva, crit, atk_spd = 4, 0, 4, 260
    stats = dict(
        maxHealth=max(1, round(hp)),
        pAtk=max(1, round(patk_final / (bonus("STR", attrs["STR"]) * level_factor(level)))),
        pDef=max(1, round(pdef_final - bonus("CON", attrs["CON"]) * 6.0)),
        mAtk=max(1, round(patk_final * std[2] / std[1] / (bonus("INT", attrs["INT"]) * level_factor(level)))),
        mDef=max(1, round(mdef_final - bonus("MEN", attrs["MEN"]) * 6.0)),
        accuracyBonus=acc, evasionBonus=eva, critBonus=crit, xpReward=round(xp),
    )
    loot = tier_loot(level) + m["loot"]
    return stats, attrs, gold, loot, atk_spd


def monster_id(name):
    return str(uuid.uuid5(NAMESPACE, name))


def xml_entry(m):
    stats, attrs, gold, loot, atk_spd = build(m)
    kind = "boss de raid" if m["raid"] else ("agressif" if m["aggro"] else "passif")
    lines = [f'    <!-- {m["name"]} (L2 npc {m["l2id"]}, niveau {m["level"]}, {kind}) -->',
             f'    <monster id="{monster_id(m["name"])}">',
             f'        <name>{m["name"]}</name>',
             f'        <race>{m["race"]}</race>',
             f'        <maxHealth>{stats["maxHealth"]}</maxHealth>',
             f'        <pAtk>{stats["pAtk"]}</pAtk>',
             f'        <pDef>{stats["pDef"]}</pDef>',
             f'        <mAtk>{stats["mAtk"]}</mAtk>',
             f'        <mDef>{stats["mDef"]}</mDef>',
             f'        <accuracyBonus>{stats["accuracyBonus"]}</accuracyBonus>',
             f'        <evasionBonus>{stats["evasionBonus"]}</evasionBonus>',
             f'        <critBonus>{stats["critBonus"]}</critBonus>',
             f'        <xpReward>{stats["xpReward"]}</xpReward>',
             '        <attributes>']
    lines += [f'            <{k}>{v}</{k}>' for k, v in attrs.items()]
    lines += ['        </attributes>', '        <loot>', f'            <gold>{gold}</gold>']
    lines += [f'            <item templateId="{item}" chance="{chance:g}" />' for item, chance in loot]
    lines += ['        </loot>']
    if m["res"]:
        lines += ['        <elementalResistances>']
        lines += [f'            <{k}>{v}</{k}>' for k, v in m["res"].items()]
        lines += ['        </elementalResistances>']
    lines += [f'        <aggroRadius>{6 if m["aggro"] else 0}</aggroRadius>',
              f'        <speed>{round(m["run"] * 1.3)}</speed>',
              f'        <atkSpd>{atk_spd}</atkSpd>',
              f'        <level>{m["level"]}</level>',
              '    </monster>']
    return "\n".join(lines)


def gd_table():
    lines = ['extends RefCounted',
             '## Généré par tools/monster_gen/build_monsters.py : nom de monstre L2 -> templateId serveur',
             '## (backend data/monsters.xml), pour les zones de chasse des générateurs de cartes',
             '## (MapGenBase._monster_zone). Ne pas éditer à la main.',
             '',
             'const IDS := {']
    lines += [f'\t"{m["name"]}": "{monster_id(m["name"])}",' for m in M]
    lines += ['\t# Fiches historiques (monstres de départ).',
              '\t"Gremlin": "dc803de5-e456-4e20-bbdc-ad16faf99af9",',
              '\t"Young Keltir": "8d3b7335-abf5-420e-abf7-3de4160f95ac",',
              '\t"Elpy": "e8553837-b812-4826-8740-72df0d9280fd",',
              '\t"Fox": "0a88e27c-5487-40d5-b494-b7ea49148171",',
              '\t"Brown Keltir": "de87e00a-eb3f-4885-b6a4-922c426d5fb8",',
              '}', '',
              '## Boss de raid : un seul point, réapparition longue.',
              'const RAID_BOSSES := [' + ", ".join(f'"{m["name"]}"' for m in M if m["raid"]) + ']', '',
              '',
              '## [[templateId, poids], ...] pour _monster_zone, depuis [[nom, poids], ...].',
              'static func mix(entries: Array) -> Array:',
              '\tvar result := []',
              '\tfor e in entries:',
              '\t\tresult.append([IDS[e[0]], e[1]])',
              '\treturn result', '']
    return "\n".join(lines)


def main():
    target = Path(sys.argv[1])
    text = target.read_text(encoding="utf-8")
    if BEGIN in text:
        text = text[:text.index(BEGIN)].rstrip() + "\n</monsters>\n"
    # Monstres historiques : passifs comme dans L2 (aggroRadius, jusqu'ici inutilisé, active
    # désormais l'agression).
    text = re.sub(r"<aggroRadius>\d+</aggroRadius>", "<aggroRadius>0</aggroRadius>", text)
    block = "\n".join([BEGIN] + [xml_entry(m) for m in M] + [END])
    text = text.replace("</monsters>", block + "\n</monsters>")
    target.write_text(text, encoding="utf-8", newline="\n")
    gd = Path(__file__).resolve().parents[1] / "map_gen" / "L2Monsters.gd"
    gd.write_text(gd_table(), encoding="utf-8", newline="\n")
    print(f"{len(M)} fiches écrites dans {target}, table {gd}")
    for m in M:
        s, _, gold, _, _ = build(m)
        print(f'  {m["name"]:<28} lv{m["level"]:>2} hp {s["maxHealth"]:>6} patk {s["pAtk"]:>3} pdef {s["pDef"]:>3} '
              f'mdef {s["mDef"]:>3} xp {s["xpReward"]:>6} gold {gold:>5} aggro {m["aggro"]}')


if __name__ == "__main__":
    main()
