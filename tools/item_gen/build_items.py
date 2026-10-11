"""Outil hors-ligne : stats des armes, armures et bijoux du serveur (backend data/items/
weapons.xml, armors.xml, jewellery.xml) recopiées de Lineage 2 High Five (datapack L2JMobius H5,
stats/items/*.xml).

Chaque objet du jeu prend l'identité de l'objet L2 du même nom quand il existe (Short Sword,
Saber, Tallum Blade, Doom Helmet...), sinon d'un objet L2 du même emplacement et du grade que
l'objet avait dans le jeu (Iron Helmet -> Helmet, Garnet Ring -> Magic Ring...). En sont repris :
P.Atk, M.Atk, critique et précision du type d'arme (accCombat arrondi), vitesse d'attaque,
P.Def, M.Def, bonus de PM des robes/bijoux, défense des boucliers (sDef, ajoutée seulement en cas
de blocage) et leur malus d'esquive (-8), armure d'une pièce (fullArmor), poids (g), prix (adena)
et grade (bloc <expect> Expertise Grade). Les objets « +N » sont l'objet L2 enchanté N fois
(règles FuncEnchant, cf. CombatFormulas.enchantPAtk/enchantMAtk/enchantDefense côté serveur).
Exception : Wooden Staff garde sa tenue de bâton (vitesse 325) avec les stats de l'Apprentice's
Wand, arme de départ des mystiques L2.

Usage : python -I tools/item_gen/build_items.py <backend>/src/main/resources/data/items
(réécrit les champs en place, conserve ids, noms, descriptions, sets, compétences et résistances).
"""
import re
import sys
from pathlib import Path

EXPERTISE_SKILL = "865a7263-fb06-48ef-89c1-9ccbad268215"
GRADE_LEVEL = {"D": 1, "C": 2, "B": 3, "A": 4, "S": 5}
ARMOR_CATEGORY = {"LIGHT": "LIGHT", "HEAVY": "HEAVY", "MAGIC": "ROBE"}
TWO_HANDED = {"BIG_SWORD", "BIG_BLUNT", "POLE", "STAFF", "BOW", "DUAL"}

# nom dans le jeu -> objet L2 de référence (id L2, grade, enchantement « +N », stats du datapack).
L2 = {
    'Wooden Sword': {'l2': "Squire's Sword", 'id': 2369, 'grade': 'NG', 'ench': 0, 'weight': 1600, 'price': 106, 'pAtk': 6, 'mAtk': 5, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Short Sword': {'l2': 'Short Sword', 'id': 1, 'grade': 'NG', 'ench': 0, 'weight': 1600, 'price': 590, 'pAtk': 8, 'mAtk': 6, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Long Sword +1': {'l2': 'Long Sword', 'id': 2, 'grade': 'NG', 'ench': 1, 'weight': 1560, 'price': 105000, 'pAtk': 24, 'mAtk': 17, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 2, 'sps': 2, 'hands': 'rhand'},
    'Long Sword +2': {'l2': 'Long Sword', 'id': 2, 'grade': 'NG', 'ench': 2, 'weight': 1560, 'price': 105000, 'pAtk': 24, 'mAtk': 17, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 2, 'sps': 2, 'hands': 'rhand'},
    'Saber': {'l2': 'Saber', 'id': 123, 'grade': 'D', 'ench': 0, 'weight': 1520, 'price': 315000, 'pAtk': 40, 'mAtk': 26, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 2, 'sps': 2, 'hands': 'rhand'},
    'Battle Axe': {'l2': 'Battle Axe', 'id': 160, 'grade': 'C', 'ench': 0, 'weight': 1720, 'price': 1762900, 'pAtk': 107, 'mAtk': 61, 'crit': 4, 'acc': 4.75, 'atkSpd': 379, 'shots': 2, 'sps': 2, 'hands': 'rhand'},
    'Tsurugi': {'l2': 'Tsurugi', 'id': 77, 'grade': 'C', 'ench': 0, 'weight': 1400, 'price': 3304300, 'pAtk': 139, 'mAtk': 76, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 3, 'sps': 3, 'hands': 'rhand'},
    'Sword of Valhalla': {'l2': 'Sword of Valhalla', 'id': 148, 'grade': 'B', 'ench': 0, 'weight': 900, 'price': 6680500, 'pAtk': 140, 'mAtk': 122, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Hammer of Ruin': {'l2': 'Ice Storm Hammer', 'id': 7900, 'grade': 'B', 'ench': 0, 'weight': 1950, 'price': 6680500, 'pAtk': 213, 'mAtk': 91, 'crit': 4, 'acc': 4.75, 'atkSpd': 325, 'shots': 1, 'sps': 1, 'hands': 'lrhand'},
    'Sword of Miracle': {'l2': 'Sword of Miracles', 'id': 151, 'grade': 'A', 'ench': 0, 'weight': 840, 'price': 20741000, 'pAtk': 186, 'mAtk': 152, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Tallum Blade': {'l2': 'Tallum Blade', 'id': 80, 'grade': 'A', 'ench': 0, 'weight': 1330, 'price': 14098000, 'pAtk': 213, 'mAtk': 107, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Dynasty Sword': {'l2': 'Dynasty Sword', 'id': 9442, 'grade': 'S', 'ench': 0, 'weight': 1520, 'price': 74946000, 'pAtk': 333, 'mAtk': 151, 'crit': 8, 'acc': 0.0, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Dynasty Dagger': {'l2': 'Dynasty Knife', 'id': 9446, 'grade': 'S', 'ench': 0, 'weight': 1520, 'price': 74946000, 'pAtk': 291, 'mAtk': 151, 'crit': 12, 'acc': -3.75, 'atkSpd': 433, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Wooden Dagger': {'l2': 'Dagger', 'id': 10, 'grade': 'NG', 'ench': 0, 'weight': 1160, 'price': 106, 'pAtk': 5, 'mAtk': 5, 'crit': 12, 'acc': -3.75, 'atkSpd': 433, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Dagger': {'l2': 'Dagger', 'id': 10, 'grade': 'NG', 'ench': 0, 'weight': 1160, 'price': 106, 'pAtk': 5, 'mAtk': 5, 'crit': 12, 'acc': -3.75, 'atkSpd': 433, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Wooden Staff': {'l2': "Apprentice's Wand", 'id': 6, 'grade': 'NG', 'ench': 0, 'weight': 1350, 'price': 106, 'pAtk': 5, 'mAtk': 7, 'crit': 4, 'acc': 4.75, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand', 'note': 'staff'},
    'Basic Wizard Staff': {'l2': 'Bone Staff', 'id': 178, 'grade': 'D', 'ench': 0, 'weight': 1060, 'price': 315000, 'pAtk': 39, 'mAtk': 39, 'crit': 4, 'acc': 4.75, 'atkSpd': 325, 'shots': 2, 'sps': 2, 'hands': 'lrhand'},
    'Wand of Flames': {'l2': 'Stick of Faith', 'id': 193, 'grade': 'C', 'ench': 0, 'weight': 1160, 'price': 1762900, 'pAtk': 85, 'mAtk': 81, 'crit': 4, 'acc': 4.75, 'atkSpd': 379, 'shots': 2, 'sps': 2, 'hands': 'rhand'},
    'Staff of Healing': {'l2': 'Crystal Staff', 'id': 192, 'grade': 'C', 'ench': 0, 'weight': 1020, 'price': 1762900, 'pAtk': 103, 'mAtk': 89, 'crit': 4, 'acc': 4.75, 'atkSpd': 325, 'shots': 2, 'sps': 2, 'hands': 'lrhand'},
    'Staff of the Magus': {'l2': "Sprite's Staff", 'id': 92, 'grade': 'B', 'ench': 0, 'weight': 960, 'price': 6680500, 'pAtk': 170, 'mAtk': 134, 'crit': 4, 'acc': 4.75, 'atkSpd': 325, 'shots': 1, 'sps': 1, 'hands': 'lrhand'},
    "Archmage's Staff": {'l2': "Dasparion's Staff", 'id': 212, 'grade': 'A', 'ench': 0, 'weight': 920, 'price': 14098000, 'pAtk': 207, 'mAtk': 157, 'crit': 4, 'acc': 4.75, 'atkSpd': 325, 'shots': 1, 'sps': 1, 'hands': 'lrhand'},
    'Staff of Arcana': {'l2': 'Imperial Staff', 'id': 6366, 'grade': 'S', 'ench': 0, 'weight': 910, 'price': 42759400, 'pAtk': 274, 'mAtk': 193, 'crit': 4, 'acc': 4.75, 'atkSpd': 325, 'shots': 1, 'sps': 1, 'hands': 'lrhand'},
    'Wooden Club': {'l2': 'Club', 'id': 4, 'grade': 'NG', 'ench': 0, 'weight': 1870, 'price': 590, 'pAtk': 8, 'mAtk': 6, 'crit': 4, 'acc': 4.75, 'atkSpd': 379, 'shots': 1, 'sps': 1, 'hands': 'rhand'},
    'Wooden Bow': {'l2': 'Short Bow', 'id': 13, 'grade': 'NG', 'ench': 0, 'weight': 1950, 'price': 590, 'pAtk': 16, 'mAtk': 6, 'crit': 12, 'acc': -3.75, 'atkSpd': 293, 'shots': 1, 'sps': 1, 'hands': 'lrhand'},
    'Spear': {'l2': 'Short Spear', 'id': 15, 'grade': 'NG', 'ench': 0, 'weight': 2140, 'price': 105000, 'pAtk': 24, 'mAtk': 17, 'crit': 8, 'acc': -3.75, 'atkSpd': 325, 'shots': 2, 'sps': 2, 'hands': 'lrhand'},
    'Pike': {'l2': 'Pike', 'id': 292, 'grade': 'D', 'ench': 0, 'weight': 2090, 'price': 495500, 'pAtk': 51, 'mAtk': 32, 'crit': 8, 'acc': -3.75, 'atkSpd': 325, 'shots': 2, 'sps': 2, 'hands': 'lrhand'},
    'Saber*Saber': {'l2': 'Saber*Saber', 'id': 2516, 'grade': 'D', 'ench': 0, 'weight': 2530, 'price': 674400, 'pAtk': 73, 'mAtk': 37, 'crit': 8, 'acc': 0.0, 'atkSpd': 325, 'shots': 2, 'sps': 2, 'hands': 'lrhand'},
    'Sword of Revolution*Sword of Revolution': {'l2': 'Sword of Revolution*Sword of Revolution', 'id': 2558, 'grade': 'C', 'ench': 0, 'weight': 2360, 'price': 2209700, 'pAtk': 148, 'mAtk': 68, 'crit': 8, 'acc': 0.0, 'atkSpd': 325, 'shots': 2, 'sps': 2, 'hands': 'lrhand'},
    'Bow of Peril': {'l2': 'Bow of Peril', 'id': 287, 'grade': 'B', 'ench': 0, 'weight': 1700, 'price': 10091400, 'pAtk': 400, 'mAtk': 99, 'crit': 12, 'acc': -3.75, 'atkSpd': 293, 'shots': 3, 'sps': 1, 'hands': 'lrhand'},
    'Leather Cap': {'l2': 'Leather Cap', 'id': 42, 'grade': 'NG', 'ench': 0, 'weight': 660, 'price': 700, 'pDef': 16, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Leather Tunic': {'l2': 'Leather Shirt', 'id': 22, 'grade': 'NG', 'ench': 0, 'weight': 4830, 'price': 1870, 'pDef': 43, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'LIGHT'},
    'Leather Gloves': {'l2': 'Leather Gloves', 'id': 50, 'grade': 'NG', 'ench': 0, 'weight': 650, 'price': 5210, 'pDef': 15, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'gloves', 'atype': None},
    'Leather Boots': {'l2': 'Leather Shoes', 'id': 37, 'grade': 'NG', 'ench': 0, 'weight': 1320, 'price': 2040, 'pDef': 13, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'feet', 'atype': None},
    'Leather Pants': {'l2': 'Leather Pants', 'id': 29, 'grade': 'NG', 'ench': 0, 'weight': 1730, 'price': 1170, 'pDef': 27, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'legs', 'atype': 'LIGHT'},
    'Wooden Shield': {'l2': 'Small Shield', 'id': 19, 'grade': 'NG', 'ench': 0, 'weight': 1420, 'price': 490, 'sDef': 56, 'eva': -8},
    "Apprentice's Robe": {'l2': "Apprentice's Tunic", 'id': 425, 'grade': 'NG', 'ench': 0, 'weight': 2150, 'price': 20, 'pDef': 17, 'mDef': 0, 'maxMp': 19, 'full': False, 'body': 'chest', 'atype': 'MAGIC'},
    'Iron Helmet': {'l2': 'Helmet', 'id': 47, 'grade': 'D', 'ench': 0, 'weight': 640, 'price': 58600, 'pDef': 37, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Leather Armor': {'l2': 'Reinforced Leather Shirt', 'id': 394, 'grade': 'D', 'ench': 0, 'weight': 4570, 'price': 117000, 'pDef': 73, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'LIGHT'},
    'Chain Mail': {'l2': 'Ring Mail Breastplate', 'id': 347, 'grade': 'D', 'ench': 0, 'weight': 8820, 'price': 64210, 'pDef': 77, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'HEAVY'},
    'Chain Mail +1': {'l2': 'Ring Mail Breastplate', 'id': 347, 'grade': 'D', 'ench': 1, 'weight': 8820, 'price': 64210, 'pDef': 77, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'HEAVY'},
    'Plate Armor': {'l2': 'Full Plate Armor', 'id': 356, 'grade': 'C', 'ench': 0, 'weight': 10480, 'price': 1788000, 'pDef': 239, 'mDef': 0, 'maxMp': 0, 'full': True, 'body': 'onepiece', 'atype': 'HEAVY'},
    'Plate Armor +2': {'l2': 'Full Plate Armor', 'id': 356, 'grade': 'C', 'ench': 2, 'weight': 10480, 'price': 1788000, 'pDef': 239, 'mDef': 0, 'maxMp': 0, 'full': True, 'body': 'onepiece', 'atype': 'HEAVY'},
    'Shield': {'l2': 'Bronze Shield', 'id': 626, 'grade': 'D', 'ench': 0, 'weight': 1370, 'price': 16900, 'sDef': 101, 'eva': -8},
    'Shield +1': {'l2': 'Bronze Shield', 'id': 626, 'grade': 'D', 'ench': 1, 'weight': 1370, 'price': 16900, 'sDef': 101, 'eva': -8},
    'Shield +3': {'l2': 'Bronze Shield', 'id': 626, 'grade': 'D', 'ench': 3, 'weight': 1370, 'price': 16900, 'sDef': 101, 'eva': -8},
    "Zealot's Armor": {'l2': 'Mithril Shirt', 'id': 397, 'grade': 'C', 'ench': 0, 'weight': 4470, 'price': 291000, 'pDef': 90, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'LIGHT'},
    'Helm of Terror': {'l2': 'Great Helmet', 'id': 500, 'grade': 'C', 'ench': 0, 'weight': 610, 'price': 185800, 'pDef': 51, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Padded Armor': {'l2': 'Puma Skin Shirt', 'id': 391, 'grade': 'D', 'ench': 0, 'weight': 4700, 'price': 48200, 'pDef': 58, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'LIGHT'},
    'Padded Helmet': {'l2': 'Bone Helmet', 'id': 45, 'grade': 'D', 'ench': 0, 'weight': 640, 'price': 24100, 'pDef': 29, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Doom Breastplate': {'l2': 'Leather Armor of Doom', 'id': 2392, 'grade': 'B', 'ench': 0, 'weight': 5500, 'price': 3017000, 'pDef': 202, 'mDef': 0, 'maxMp': 0, 'full': True, 'body': 'onepiece', 'atype': 'LIGHT'},
    'Doom Helmet': {'l2': 'Doom Helmet', 'id': 2417, 'grade': 'B', 'ench': 0, 'weight': 580, 'price': 928300, 'pDef': 66, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Doom Gloves': {'l2': 'Doom Gloves - Light Armor', 'id': 5723, 'grade': 'B', 'ench': 0, 'weight': 580, 'price': 618800, 'pDef': 44, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'gloves', 'atype': None},
    'Dark Crystal Breastplate': {'l2': 'Dark Crystal Breastplate', 'id': 365, 'grade': 'A', 'ench': 0, 'weight': 7700, 'price': 3562000, 'pDef': 171, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'chest', 'atype': 'HEAVY'},
    'Dark Crystal Helmet': {'l2': 'Dark Crystal Helmet', 'id': 512, 'grade': 'A', 'ench': 0, 'weight': 570, 'price': 1336000, 'pDef': 69, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Dark Crystal Leggings': {'l2': 'Dark Crystal Gaiters', 'id': 388, 'grade': 'A', 'ench': 0, 'weight': 3320, 'price': 2226000, 'pDef': 107, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'legs', 'atype': 'HEAVY'},
    'Dark Crystal Boots': {'l2': 'Dark Crystal Boots', 'id': 563, 'grade': 'A', 'ench': 0, 'weight': 1110, 'price': 890000, 'pDef': 45, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'feet', 'atype': None},
    'Tallum Tunic': {'l2': 'Tallum Tunic', 'id': 2400, 'grade': 'A', 'ench': 0, 'weight': 1860, 'price': 2671000, 'pDef': 86, 'mDef': 0, 'maxMp': 409, 'full': False, 'body': 'chest', 'atype': 'MAGIC'},
    'Tallum Hood': {'l2': 'Tallum Helm', 'id': 547, 'grade': 'A', 'ench': 0, 'weight': 570, 'price': 1336000, 'pDef': 69, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Major Arcana Robe': {'l2': 'Major Arcana Robe', 'id': 6383, 'grade': 'S', 'ench': 0, 'weight': 2300, 'price': 15577000, 'pDef': 166, 'mDef': 0, 'maxMp': 866, 'full': True, 'body': 'onepiece', 'atype': 'MAGIC'},
    'Major Arcana Circlet': {'l2': 'Major Arcana Circlet', 'id': 6386, 'grade': 'S', 'ench': 0, 'weight': 550, 'price': 4793000, 'pDef': 83, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Draconic Cuirass': {'l2': 'Draconic Leather Armor', 'id': 6379, 'grade': 'S', 'ench': 0, 'weight': 4950, 'price': 15577000, 'pDef': 249, 'mDef': 0, 'maxMp': 0, 'full': True, 'body': 'onepiece', 'atype': 'LIGHT'},
    'Draconic Helmet': {'l2': 'Draconic Leather Helmet', 'id': 6382, 'grade': 'S', 'ench': 0, 'weight': 550, 'price': 4793000, 'pDef': 83, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'head', 'atype': None},
    'Draconic Gauntlets': {'l2': 'Draconic Leather Gloves', 'id': 6380, 'grade': 'S', 'ench': 0, 'weight': 540, 'price': 3195000, 'pDef': 55, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'gloves', 'atype': None},
    'Draconic Boots': {'l2': 'Draconic Leather Boots', 'id': 6381, 'grade': 'S', 'ench': 0, 'weight': 1110, 'price': 3195000, 'pDef': 55, 'mDef': 0, 'maxMp': 0, 'full': False, 'body': 'feet', 'atype': None},
    'Draconic Shield': {'l2': 'Dragon Shield', 'id': 634, 'grade': 'S', 'ench': 0, 'weight': 1170, 'price': 1949000, 'sDef': 269, 'eva': -8},
    'Garnet Ring': {'l2': 'Magic Ring', 'id': 116, 'grade': 'NG', 'ench': 0, 'weight': 150, 'price': 25, 'pDef': 0, 'mDef': 7, 'maxMp': 0, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Garnet Earring': {'l2': "Apprentice's Earring", 'id': 112, 'grade': 'NG', 'ench': 0, 'weight': 150, 'price': 38, 'pDef': 0, 'mDef': 11, 'maxMp': 0, 'full': False, 'body': 'rear;lear', 'atype': None},
    'Garnet Necklace': {'l2': 'Necklace of Magic', 'id': 118, 'grade': 'NG', 'ench': 0, 'weight': 150, 'price': 51, 'pDef': 0, 'mDef': 15, 'maxMp': 0, 'full': False, 'body': 'neck', 'atype': None},
    'Amber Ring': {'l2': 'Enchanted Ring', 'id': 879, 'grade': 'D', 'ench': 0, 'weight': 150, 'price': 21800, 'pDef': 0, 'mDef': 18, 'maxMp': 0, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Amber Earring': {'l2': 'Enchanted Earring', 'id': 848, 'grade': 'D', 'ench': 0, 'weight': 150, 'price': 32800, 'pDef': 0, 'mDef': 27, 'maxMp': 0, 'full': False, 'body': 'rear;lear', 'atype': None},
    'Amber Necklace': {'l2': 'Enchanted Necklace', 'id': 911, 'grade': 'D', 'ench': 0, 'weight': 150, 'price': 43700, 'pDef': 0, 'mDef': 36, 'maxMp': 0, 'full': False, 'body': 'neck', 'atype': None},
    'Amethyst Ring': {'l2': 'Ring of Protection', 'id': 884, 'grade': 'C', 'ench': 0, 'weight': 150, 'price': 100300, 'pDef': 0, 'mDef': 28, 'maxMp': 0, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Amethyst Earring': {'l2': 'Earring of Protection', 'id': 853, 'grade': 'C', 'ench': 0, 'weight': 150, 'price': 150500, 'pDef': 0, 'mDef': 42, 'maxMp': 0, 'full': False, 'body': 'rear;lear', 'atype': None},
    'Amethyst Necklace': {'l2': 'Necklace of Protection', 'id': 916, 'grade': 'C', 'ench': 0, 'weight': 150, 'price': 200600, 'pDef': 0, 'mDef': 56, 'maxMp': 0, 'full': False, 'body': 'neck', 'atype': None},
    'Sapphire Ring': {'l2': 'Adamantite Ring', 'id': 887, 'grade': 'B', 'ench': 0, 'weight': 150, 'price': 310600, 'pDef': 0, 'mDef': 34, 'maxMp': 0, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Sapphire Earring': {'l2': 'Adamantite Earring', 'id': 856, 'grade': 'B', 'ench': 0, 'weight': 150, 'price': 465900, 'pDef': 0, 'mDef': 51, 'maxMp': 0, 'full': False, 'body': 'rear;lear', 'atype': None},
    'Sapphire Necklace': {'l2': 'Adamantite Necklace', 'id': 918, 'grade': 'B', 'ench': 0, 'weight': 150, 'price': 621200, 'pDef': 0, 'mDef': 68, 'maxMp': 0, 'full': False, 'body': 'neck', 'atype': None},
    'Ruby Ring': {'l2': 'Cerberus Ring', 'id': 903, 'grade': 'A', 'ench': 0, 'weight': 150, 'price': 999000, 'pDef': 0, 'mDef': 40, 'maxMp': 0, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Ruby Earring': {'l2': 'Cerberus Earring', 'id': 872, 'grade': 'A', 'ench': 0, 'weight': 150, 'price': 1498000, 'pDef': 0, 'mDef': 60, 'maxMp': 0, 'full': False, 'body': 'rear;lear', 'atype': None},
    'Ruby Necklace': {'l2': 'Cerberus Necklace', 'id': 934, 'grade': 'A', 'ench': 0, 'weight': 150, 'price': 1998000, 'pDef': 0, 'mDef': 80, 'maxMp': 0, 'full': False, 'body': 'neck', 'atype': None},
    'Diamond Ring': {'l2': 'Tateossian Ring', 'id': 889, 'grade': 'S', 'ench': 0, 'weight': 150, 'price': 2180000, 'pDef': 0, 'mDef': 48, 'maxMp': 21, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Diamond Earring': {'l2': 'Tateossian Earring', 'id': 858, 'grade': 'S', 'ench': 0, 'weight': 150, 'price': 3270000, 'pDef': 0, 'mDef': 71, 'maxMp': 31, 'full': False, 'body': 'rear;lear', 'atype': None},
    'Diamond Necklace': {'l2': 'Tateossian Necklace', 'id': 920, 'grade': 'S', 'ench': 0, 'weight': 150, 'price': 4361000, 'pDef': 0, 'mDef': 95, 'maxMp': 42, 'full': False, 'body': 'neck', 'atype': None},
    'Ring of Embers': {'l2': 'Ring of Ages', 'id': 885, 'grade': 'C', 'ench': 0, 'weight': 150, 'price': 151100, 'pDef': 0, 'mDef': 30, 'maxMp': 0, 'full': False, 'body': 'rfinger;lfinger', 'atype': None},
    'Necklace of the Depths': {'l2': 'Necklace of Mermaid', 'id': 917, 'grade': 'C', 'ench': 0, 'weight': 150, 'price': 302100, 'pDef': 0, 'mDef': 60, 'maxMp': 0, 'full': False, 'body': 'neck', 'atype': None},
}

# Ajustements propres au jeu : tenue/type d'arme (Tsurugi est une épée à une main dans L2),
# catégorie d'armure (le Draconic L2 est une armure légère), vitesse du bâton de départ.
WEAPON_TYPE = {"Tsurugi": "SWORD"}
CATEGORY = {"Draconic Cuirass": "LIGHT"}
ATK_SPD = {"Wooden Staff": 325}


def enchant_steps(enchant, per_level):
    return per_level * min(enchant, 3) + 2 * per_level * max(0, enchant - 3)


def enchant_patk(base, enchant, grade, weapon_type):
    """FuncEnchant L2J (p.atk), cf. CombatFormulas.enchantPAtk."""
    if base <= 0 or enchant <= 0:
        return base
    bow, two = weapon_type == "BOW", weapon_type in TWO_HANDED
    if grade == "S":
        per = 10 if bow else 6 if two else 5
    elif grade == "A":
        per = 8 if bow else 5 if two else 4
    elif grade in ("B", "C"):
        per = 6 if bow else 4 if two else 3
    else:
        per = 4 if bow else 2
    return base + enchant_steps(enchant, per)


def enchant_matk(base, enchant, grade):
    if base <= 0 or enchant <= 0:
        return base
    return base + enchant_steps(enchant, 4 if grade == "S" else 3 if grade in ("A", "B", "C") else 2)


def enchant_def(base, enchant):
    if base <= 0 or enchant <= 0:
        return base
    return base + min(enchant, 3) + 3 * max(0, enchant - 3)


def set_tag(body, tag, value, after="name"):
    """Remplace <tag>…</tag>, ou l'insère après <after> s'il manque (None : supprime)."""
    pattern = re.compile(r"\n\s*<%s>[^<]*</%s>" % (tag, tag))
    if value is None:
        return pattern.sub("", body)
    line = f"\n        <{tag}>{value}</{tag}>"
    if pattern.search(body):
        return pattern.sub(lambda _: line, body, count=1)
    anchor = re.search(r"\n\s*<%s>[^<]*</%s>" % (after, after), body)
    return body[:anchor.end()] + line + body[anchor.end():]


def set_expect(body, grade):
    body = re.sub(r"\n\s*<expect>.*?</expect>", "", body, flags=re.S).rstrip()
    if grade != "NG":
        body += ("\n        <expect>\n            <conditions>\n"
                 f"                <!-- Expertise Grade - {grade} -->\n"
                 f'                <skill id="{EXPERTISE_SKILL}" level="{GRADE_LEVEL[grade]}" />\n'
                 "            </conditions>\n        </expect>")
    return body + "\n    "


def rewrite(name, body):
    ref = L2[name]
    grade, ench = ref["grade"], ref["ench"]
    body = re.sub(r"\n\s*<!-- L2 H5 : [^>]*-->", "", body)
    label = f"{ref['l2']} +{ench}" if ench else ref["l2"]
    note = f"<!-- L2 H5 : {label} (#{ref['id']}, {'sans grade' if grade == 'NG' else 'grade ' + grade}) -->"
    body = re.sub(r"(\n\s*<name>[^<]*</name>)", lambda m: m.group(1) + "\n        " + note, body, count=1)
    stats = dict(pAtk=0, mAtk=0, pDef=0, mDef=0, accuracyBonus=0, evasionBonus=0, critBonus=0, atkSpd=0)
    max_mp, full = 0, False
    if "pAtk" in ref:
        weapon_type = WEAPON_TYPE.get(name) or re.search(r"<weaponType>(\w+)</weaponType>", body).group(1)
        if name in WEAPON_TYPE:
            body = set_tag(body, "weaponType", weapon_type)
        stats.update(pAtk=enchant_patk(ref["pAtk"], ench, grade, weapon_type),
                     mAtk=enchant_matk(ref["mAtk"], ench, grade), accuracyBonus=round(ref["acc"]),
                     critBonus=ref["crit"], atkSpd=ATK_SPD.get(name, ref["atkSpd"]))
    elif "sDef" in ref:
        stats.update(pDef=enchant_def(ref["sDef"], ench), evasionBonus=ref["eva"])
    else:
        stats.update(pDef=enchant_def(ref["pDef"], ench), mDef=enchant_def(ref["mDef"], ench))
        max_mp, full = ref["maxMp"], ref["full"]
        category = CATEGORY.get(name) or ARMOR_CATEGORY.get(ref["atype"] or "")
        if category and "<armorCategory>" in body:
            body = set_tag(body, "armorCategory", category)
    for tag, value in stats.items():
        body = set_tag(body, tag, value)
    body = set_tag(body, "weight", ref["weight"])
    body = set_tag(body, "price", ref["price"])
    body = set_tag(body, "maxMp", max_mp or None, after="atkSpd")
    body = set_tag(body, "fullArmor", "true" if full else None, after="atkSpd")
    return set_expect(body, grade)


def main():
    folder = Path(sys.argv[1])
    seen = set()
    for file in ("weapons.xml", "armors.xml", "jewellery.xml"):
        path = folder / file
        text = path.read_text(encoding="utf-8")

        def repl(match):
            name = re.search(r"<name>([^<]*)</name>", match.group(3)).group(1)
            if name not in L2:
                raise SystemExit(f"{file}: {name} absent de la table L2")
            seen.add(name)
            return match.group(1) + rewrite(name, match.group(3)) + match.group(4)

        text = re.sub(r'(<(weapon|armor|piece) id="[^"]+">)(.*?)(</\2>)', repl, text, flags=re.S)
        path.write_text(text, encoding="utf-8", newline="\n")
    missing = set(L2) - seen
    if missing:
        raise SystemExit(f"Objets de la table introuvables : {sorted(missing)}")
    print(f"{len(seen)} objets recalés sur L2 H5 dans {folder}")


if __name__ == "__main__":
    main()
