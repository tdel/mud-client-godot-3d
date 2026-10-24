"""Outil hors-ligne : fiches monstres du serveur (backend data/monsters.xml) tirées des PNJ de
Lineage 2 High Five (datapack L2JMobius H5, stats/npcs/*.xml) pour les zones de la région de
Gludio (anciennes petites zones de départ comprises), plus la table nom -> templateId utilisée par
les générateurs de cartes (tools/map_gen/L2Monsters.gd).

Repris tels quels de L2 (table L2_NPC) : nom, niveau, race, agressivité, valeurs de base PV,
P.Atk, M.Atk, P.Def, M.Def, précision, esquive, critique, vitesses d'attaque et de course,
attributs STR/DEX/CON/INT/WIT/MEN, modificateurs propres au PNJ inclus. Ce sont les valeurs
d'avant les fonctions de stats : le serveur les passe par les mêmes formules que L2J (PV x CON,
P.Atk x STR x (niveau+89)/100... cf. CombatFormulas.stats), un monstre y affiche donc ses stats
L2. Les boss de raid gardent leurs PV L2 (contenu de groupe). Propres au jeu : XP (celle de L2,
à 5 % pour un boss de raid), or, butin, éléments faibles/forts. Rayon d'aggro : 6 cases pour un
monstre agressif, 0 sinon (MonsterAiEngine.scanAggro). Les fiches historiques (Gremlin...) sont
réécrites en place avec leurs stats L2 (HISTORIC).

Les identifiants sont des UUID v5 dérivés du nom : relancer le script redonne les mêmes.

Usage : python -I tools/monster_gen/build_monsters.py <backend>/src/main/resources/data/monsters.xml
(réécrit les fiches générées en fin de fichier, conserve les fiches historiques, régénère
tools/map_gen/L2Monsters.gd).
"""
import re
import sys
import uuid
from pathlib import Path

NAMESPACE = uuid.UUID("6f1e3c52-2b8a-4c7e-9d41-0a5b7e3f9c18")
BEGIN = "    <!-- ===== Fiches générées par tools/monster_gen/build_monsters.py : ne pas éditer à la main ===== -->"
END = "    <!-- ===== Fin des fiches générées ===== -->"

# Stats de base L2 H5 de chaque PNJ (datapack L2JMobius H5, stats/npcs/*.xml) : PV, P.Atk,
# M.Atk, P.Def, M.Def, précision, esquive, critique, vitesse d'attaque et de course, attributs
# STR/DEX/CON/INT/WIT/MEN. Les modificateurs propres au PNJ (compétences passives 4408-4413 :
# "HP x0.5", "Strong P. Atk."...) y sont déjà repliés. Le serveur leur applique les fonctions de
# stats L2 (PV x CON, P.Atk x STR x niveau... cf. CombatFormulas.stats, MonsterCatalog).
L2_NPC = {
    20544: dict(name='Elder Keltir', level=3, hp=57.55, pAtk=11.27, mAtk=8.47, pDef=43.6, mDef=29.03, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20120: dict(name='Wolf', level=4, hp=68.21, pAtk=11.25, mAtk=7.68, pDef=49.73, mDef=33.11, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20442: dict(name='Elder Wolf', level=5, hp=80.17, pAtk=12.34, mAtk=8.43, pDef=51.61, mDef=34.36, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20121: dict(name='Giant Toad', level=5, hp=80.17, pAtk=12.34, mAtk=8.43, pDef=51.61, mDef=34.36, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=100.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20003: dict(name='Goblin', level=5, hp=80.17, pAtk=12.34, mAtk=8.43, pDef=51.61, mDef=34.36, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20130: dict(name='Orc', level=6, hp=93.54, pAtk=13.52, mAtk=9.24, pDef=53.53, mDef=35.64, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20131: dict(name='Orc Grunt', level=7, hp=108.42, pAtk=14.81, mAtk=10.11, pDef=55.52, mDef=36.97, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20006: dict(name='Orc Archer', level=8, hp=124.93, pAtk=16.2, mAtk=11.06, pDef=57.56, mDef=38.33, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20326: dict(name='Goblin Scout', level=8, hp=124.93, pAtk=16.2, mAtk=11.06, pDef=57.56, mDef=38.33, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20132: dict(name='Werewolf', level=9, hp=143.18, pAtk=17.71, mAtk=12.09, pDef=59.66, mDef=39.72, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20093: dict(name='Orc Fighter', level=10, hp=163.29, pAtk=19.34, mAtk=13.21, pDef=61.83, mDef=41.16, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20343: dict(name='Werewolf Hunter', level=10, hp=163.29, pAtk=21.27, mAtk=15.98, pDef=56.26, mDef=37.46, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20009: dict(name='Vuku Orc', level=14, hp=230.39, pAtk=27.25, mAtk=18.61, pDef=71.08, mDef=47.33, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20011: dict(name='Vuku Orc Archer', level=15, hp=246.95, pAtk=29.62, mAtk=20.22, pDef=73.55, mDef=48.97, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20023: dict(name='Shadow Beast', level=15, hp=246.95, pAtk=32.58, mAtk=24.47, pDef=66.93, mDef=44.56, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20026: dict(name='Ruin Zombie', level=15, hp=246.95, pAtk=32.58, mAtk=24.47, pDef=66.93, mDef=95.01, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=15.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20029: dict(name='Ruin Zombie Leader', level=16, hp=264.34, pAtk=29.27, mAtk=18.23, pDef=83.69, mDef=108.41, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=15.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20035: dict(name='Skeleton Tracker', level=17, hp=282.57, pAtk=38.39, mAtk=28.84, pDef=71.6, mDef=47.67, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20042: dict(name='Skeleton Tracker Leader', level=18, hp=301.67, pAtk=41.61, mAtk=31.26, pDef=74.03, mDef=49.29, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20045: dict(name='Skeleton Scout', level=19, hp=321.64, pAtk=37.28, mAtk=23.22, pDef=92.48, mDef=61.58, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20051: dict(name='Skeleton Bowman', level=20, hp=342.51, pAtk=40.34, mAtk=25.12, pDef=95.56, mDef=63.62, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20054: dict(name='Ruin Spartoi', level=21, hp=364.3, pAtk=43.61, mAtk=27.16, pDef=98.7, mDef=65.72, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20060: dict(name='Raging Spartoi', level=22, hp=387.03, pAtk=47.1, mAtk=29.33, pDef=101.92, mDef=67.86, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20064: dict(name='Tumran Bugbear Warrior', level=24, hp=435.34, pAtk=66.22, mAtk=49.74, pDef=89.83, mDef=59.81, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    25369: dict(name='Soul Scavenger', level=25, hp=43316.31, pAtk=74.22, mAtk=4.68, pDef=305.51, mDef=149.04, acc=4.75, eva=-18.0, crit=4, atkSpd=253, run=190.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    20514: dict(name='Shield Skeleton', level=15, hp=246.95, pAtk=32.58, mAtk=24.47, pDef=66.93, mDef=44.56, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20515: dict(name='Skeleton Infantryman', level=16, hp=264.34, pAtk=35.38, mAtk=26.58, pDef=69.24, mDef=46.1, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20506: dict(name='Ruin Imp', level=17, hp=282.57, pAtk=38.39, mAtk=28.84, pDef=71.6, mDef=47.67, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=80.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20411: dict(name='Scavenger Bat', level=18, hp=301.67, pAtk=41.61, mAtk=31.26, pDef=74.03, mDef=49.29, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=80.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20457: dict(name='Zombie Soldier', level=19, hp=321.64, pAtk=45.07, mAtk=33.85, pDef=76.51, mDef=108.6, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=15.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20505: dict(name='Ruin Bat', level=20, hp=342.51, pAtk=48.76, mAtk=36.63, pDef=79.05, mDef=52.63, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=80.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20507: dict(name='Ruin Imp Elder', level=21, hp=364.3, pAtk=52.71, mAtk=39.59, pDef=81.65, mDef=54.37, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=80.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20458: dict(name='Zombie Warrior', level=22, hp=387.03, pAtk=56.93, mAtk=42.76, pDef=84.32, mDef=119.68, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=15.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20401: dict(name='Veelan Bugbear', level=23, hp=410.7, pAtk=50.82, mAtk=31.65, pDef=105.21, mDef=70.05, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20402: dict(name='Veelan Bugbear Warrior', level=24, hp=435.34, pAtk=66.22, mAtk=49.74, pDef=89.83, mDef=59.81, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    25149: dict(name='Zombie Lord Crowl', level=25, hp=43316.31, pAtk=74.22, mAtk=4.68, pDef=305.51, mDef=149.04, acc=4.75, eva=-18.0, crit=4, atkSpd=253, run=190.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    20225: dict(name='Giant Mist Leech', level=25, hp=460.96, pAtk=64.83, mAtk=44.27, pDef=101.84, mDef=67.8, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20226: dict(name='Gray Ant', level=26, hp=487.57, pAtk=63.48, mAtk=39.54, pDef=115.53, mDef=76.92, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20227: dict(name='Horror Mist Ripper', level=27, hp=515.18, pAtk=82.49, mAtk=61.96, pDef=98.54, mDef=65.61, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=100.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20228: dict(name='Giant Crimson Ant', level=28, hp=543.8, pAtk=88.59, mAtk=66.55, pDef=101.57, mDef=67.63, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20157: dict(name='Marsh Stakato', level=29, hp=573.43, pAtk=95.06, mAtk=71.41, pDef=104.66, mDef=69.68, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20229: dict(name='Stinger Wasp', level=30, hp=604.08, pAtk=84.3, mAtk=52.51, pDef=130.31, mDef=86.76, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=90.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20230: dict(name='Marsh Stakato Worker', level=31, hp=635.76, pAtk=99.22, mAtk=67.75, pDef=121.99, mDef=81.22, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20231: dict(name='Toad Lord', level=32, hp=668.47, pAtk=96.61, mAtk=60.17, pDef=138.13, mDef=91.97, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=100.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20232: dict(name='Marsh Stakato Soldier', level=33, hp=702.2, pAtk=103.28, mAtk=64.32, pDef=142.15, mDef=94.65, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=155.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20233: dict(name='Marsh Spider', level=34, hp=736.96, pAtk=121.21, mAtk=82.77, pDef=132.95, mDef=88.52, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20234: dict(name='Marsh Stakato Drone', level=35, hp=772.74, pAtk=142.26, mAtk=106.86, pDef=124.42, mDef=82.84, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=174.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    25023: dict(name='Stakato Queen Zyrnna', level=34, hp=87402.97, pAtk=284.02, mAtk=41.78, pDef=398.85, mDef=194.58, acc=4.75, eva=-18.0, crit=4, atkSpd=253, run=170.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    20919: dict(name='Maille Lizardman', level=20, hp=171.26, pAtk=44.33, mAtk=30.27, pDef=86.87, mDef=57.84, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20920: dict(name='Maille Lizardman Scout', level=22, hp=193.51, pAtk=51.75, mAtk=35.34, pDef=92.66, mDef=61.69, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20921: dict(name='Maille Lizardman Guard', level=24, hp=217.67, pAtk=60.2, mAtk=41.11, pDef=98.71, mDef=65.72, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20925: dict(name='Giant Araneid', level=24, hp=217.67, pAtk=60.2, mAtk=41.11, pDef=98.71, mDef=65.72, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20926: dict(name='Poison Araneid', level=25, hp=230.48, pAtk=64.83, mAtk=44.27, pDef=101.84, mDef=67.8, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20922: dict(name='Maille Lizardman Warrior', level=26, hp=243.79, pAtk=69.76, mAtk=47.64, pDef=105.03, mDef=69.93, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20927: dict(name='King of the Araneid', level=27, hp=257.59, pAtk=74.99, mAtk=51.21, pDef=108.29, mDef=72.1, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20923: dict(name='Maille Lizardman Shaman', level=28, hp=271.9, pAtk=80.54, mAtk=55.0, pDef=111.61, mDef=74.31, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20924: dict(name='Maille Lizardman Matriarch', level=30, hp=302.04, pAtk=92.64, mAtk=63.26, pDef=118.46, mDef=78.87, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20360: dict(name='Ratman Spy', level=16, hp=264.34, pAtk=35.38, mAtk=26.58, pDef=69.24, mDef=46.1, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20032: dict(name='Pinrul', level=17, hp=282.57, pAtk=38.39, mAtk=28.84, pDef=71.6, mDef=47.67, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20775: dict(name='Bugbear Raider', level=17, hp=282.57, pAtk=38.39, mAtk=28.84, pDef=71.6, mDef=47.67, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20358: dict(name='Ratman Hunter', level=18, hp=301.67, pAtk=34.42, mAtk=21.44, pDef=89.48, mDef=59.58, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21093: dict(name='Ratman Sub Chieftain', level=19, hp=321.64, pAtk=45.07, mAtk=33.85, pDef=76.51, mDef=50.94, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=150.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21094: dict(name='Ratman Chieftain', level=20, hp=342.51, pAtk=40.34, mAtk=25.12, pDef=95.56, mDef=63.62, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=155.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    25357: dict(name='Sukar Wererat Chief', level=21, hp=37886.49, pAtk=53.13, mAtk=3.17, pDef=269.19, mDef=131.32, acc=0.0, eva=-18.0, crit=8, atkSpd=253, run=190.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    18342: dict(name='Gremlin', level=1, hp=39.75, pAtk=8.47, mAtk=5.79, pDef=44.44, mDef=29.59, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=50.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20545: dict(name='Young Keltir', level=1, hp=39.75, pAtk=8.47, mAtk=5.79, pDef=44.44, mDef=29.59, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20432: dict(name='Elpy', level=1, hp=39.75, pAtk=8.47, mAtk=5.79, pDef=44.44, mDef=29.59, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=80.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20116: dict(name='Fox', level=2, hp=48.09, pAtk=9.32, mAtk=6.37, pDef=46.15, mDef=30.73, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20532: dict(name='Brown Keltir', level=2, hp=48.09, pAtk=9.32, mAtk=6.37, pDef=46.15, mDef=30.73, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20410: dict(name='Scavenger Spider', level=15, hp=246.95, pAtk=32.58, mAtk=24.47, pDef=66.93, mDef=44.56, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20369: dict(name='Moonstone Beast', level=17, hp=282.57, pAtk=38.39, mAtk=28.84, pDef=71.6, mDef=47.67, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20039: dict(name='Scavenger Wererat', level=18, hp=301.67, pAtk=41.61, mAtk=31.26, pDef=74.03, mDef=49.29, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20043: dict(name='Arachnid Tracker', level=19, hp=321.64, pAtk=37.28, mAtk=23.22, pDef=92.48, mDef=61.58, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20049: dict(name='Lycanthrope', level=20, hp=342.51, pAtk=48.76, mAtk=36.63, pDef=79.05, mDef=52.63, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20008: dict(name='Felim Lizardman', level=14, hp=230.39, pAtk=24.79, mAtk=15.44, pDef=78.19, mDef=52.06, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20010: dict(name='Felim Lizardman Scout', level=15, hp=246.95, pAtk=32.58, mAtk=24.47, pDef=66.93, mDef=44.56, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20014: dict(name='Felim Lizardman Warrior', level=17, hp=282.57, pAtk=38.39, mAtk=28.84, pDef=71.6, mDef=47.67, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20021: dict(name='Red Bear', level=14, hp=230.39, pAtk=29.97, mAtk=22.51, pDef=64.68, mDef=43.07, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20012: dict(name='Gora Werewolf', level=16, hp=264.34, pAtk=35.38, mAtk=26.58, pDef=69.24, mDef=46.1, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20335: dict(name='Grizzly Bear', level=17, hp=282.57, pAtk=31.76, mAtk=19.78, pDef=86.55, mDef=57.63, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20050: dict(name='Arachnid Predator', level=20, hp=342.51, pAtk=48.76, mAtk=36.63, pDef=79.05, mDef=52.63, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=140.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20359: dict(name='Ratman Warrior', level=19, hp=321.64, pAtk=45.07, mAtk=33.85, pDef=76.51, mDef=50.94, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20782: dict(name='Ol Mahum Novice', level=17, hp=282.57, pAtk=34.9, mAtk=23.83, pDef=78.68, mDef=52.39, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20437: dict(name='Ol Mahum Recruit', level=21, hp=364.3, pAtk=43.61, mAtk=27.16, pDef=98.7, mDef=65.72, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20053: dict(name='Ol Mahum Patrol', level=21, hp=364.3, pAtk=47.92, mAtk=32.72, pDef=89.73, mDef=59.74, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20058: dict(name='Ol Mahum Guard', level=22, hp=387.03, pAtk=56.93, mAtk=42.76, pDef=84.32, mDef=56.14, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20436: dict(name='Ol Mahum Supplier', level=23, hp=410.7, pAtk=50.82, mAtk=31.65, pDef=105.21, mDef=70.05, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20061: dict(name='Ol Mahum Straggler', level=23, hp=410.7, pAtk=55.84, mAtk=38.13, pDef=95.65, mDef=63.68, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20439: dict(name='Ol Mahum Officer', level=24, hp=435.34, pAtk=54.78, mAtk=34.12, pDef=108.58, mDef=72.29, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20066: dict(name='Ol Mahum Captain', level=25, hp=460.96, pAtk=71.32, mAtk=53.57, pDef=92.67, mDef=61.7, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20059: dict(name='Hungry Eye', level=22, hp=387.03, pAtk=56.93, mAtk=42.76, pDef=84.32, mDef=56.14, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=159.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20055: dict(name='Wandering Eye', level=21, hp=364.3, pAtk=43.61, mAtk=27.16, pDef=98.7, mDef=65.72, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=159.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    25076: dict(name='Princess Molrang', level=25, hp=43316.31, pAtk=74.22, mAtk=4.68, pDef=305.51, mDef=149.04, acc=9.0, eva=-18.0, crit=1, atkSpd=253, run=170.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    25001: dict(name='Greyclaw Kutus', level=23, hp=40330.26, pAtk=62.85, mAtk=3.96, pDef=286.95, mDef=139.98, acc=4.75, eva=-18.0, crit=4, atkSpd=253, run=170.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    20171: dict(name='Specter', level=26, hp=487.57, pAtk=69.76, mAtk=47.64, pDef=105.03, mDef=69.93, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=100.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20197: dict(name='Sorrow Maiden', level=27, hp=515.18, pAtk=74.99, mAtk=51.21, pDef=108.29, mDef=72.1, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=60.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20160: dict(name='Neer Crawler', level=28, hp=543.8, pAtk=88.59, mAtk=66.55, pDef=101.57, mDef=67.63, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=90.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20198: dict(name='Neer Ghoul Berserker', level=29, hp=573.43, pAtk=95.06, mAtk=71.41, pDef=104.66, mDef=69.68, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=90.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20199: dict(name='Amber Basilisk', level=30, hp=604.08, pAtk=84.3, mAtk=52.51, pDef=130.31, mDef=86.76, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=131.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20200: dict(name='Strain', level=31, hp=635.76, pAtk=109.14, mAtk=81.98, pDef=111.01, mDef=73.91, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=120.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20201: dict(name='Ghoul', level=32, hp=668.47, pAtk=116.78, mAtk=87.72, pDef=114.28, mDef=162.2, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=15.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20083: dict(name='Granite Golem', level=33, hp=702.2, pAtk=103.28, mAtk=64.32, pDef=276.55, mDef=94.65, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=23.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20202: dict(name='Dead Seeker', level=34, hp=736.96, pAtk=121.21, mAtk=82.77, pDef=132.95, mDef=88.52, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=80.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20144: dict(name='Hangman Tree', level=35, hp=772.74, pAtk=129.33, mAtk=88.31, pDef=136.73, mDef=91.04, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=174.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    25118: dict(name='Guillotine, Warden of the Execution Grounds', level=35, hp=138899.14, pAtk=327.39, mAtk=51.72, pDef=410.19, mDef=200.1, acc=4.75, eva=-18.0, crit=4, atkSpd=253, run=170.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    25383: dict(name='Revenant of Sir Calibus', level=34, hp=65791.67, pAtk=151.74, mAtk=12.04, pDef=398.85, mDef=194.58, acc=4.75, eva=-18.0, crit=4, atkSpd=253, run=190.0,
            attrs=(60, 73, 57, 76, 70, 80)),
    20062: dict(name='Tumran Bugbear', level=23, hp=410.7, pAtk=50.82, mAtk=31.65, pDef=105.21, mDef=70.05, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=130.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20205: dict(name='Dire Wolf', level=24, hp=435.34, pAtk=66.22, mAtk=49.74, pDef=89.83, mDef=59.81, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=110.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20266: dict(name='Monster Eye Gazer', level=25, hp=460.96, pAtk=59.0, mAtk=36.75, pDef=112.02, mDef=74.58, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=159.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21102: dict(name='Watchman of the Plains', level=30, hp=604.08, pAtk=92.64, mAtk=63.26, pDef=118.46, mDef=78.87, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=160.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21103: dict(name='Roughly Hewn Rock Golem', level=31, hp=635.76, pAtk=99.22, mAtk=67.75, pDef=121.99, mDef=81.22, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=23.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21104: dict(name='Delu Lizardman Supplier', level=32, hp=668.47, pAtk=106.17, mAtk=72.5, pDef=125.58, mDef=83.61, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=135.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21105: dict(name='Delu Lizardman Special Agent', level=33, hp=702.2, pAtk=124.84, mAtk=93.77, pDef=117.6, mDef=78.3, acc=0.0, eva=0.0, crit=8, atkSpd=253, run=135.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21106: dict(name='Cursed Seer', level=34, hp=736.96, pAtk=121.21, mAtk=82.77, pDef=132.95, mDef=88.52, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=160.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    20781: dict(name='Delu Lizardman Shaman', level=35, hp=772.74, pAtk=142.26, mAtk=106.86, pDef=124.42, mDef=82.84, acc=9.0, eva=0.0, crit=1, atkSpd=253, run=174.0,
            attrs=(40, 30, 43, 21, 20, 20)),
    21107: dict(name='Delu Lizardman Commander', level=35, hp=1545.48, pAtk=129.33, mAtk=88.31, pDef=136.73, mDef=91.04, acc=4.75, eva=0.0, crit=4, atkSpd=253, run=135.0,
            attrs=(40, 30, 43, 21, 20, 20)),
}

# Fiches historiques (hors bloc généré) : stats réécrites en place depuis L2_NPC.
HISTORIC = {"Gremlin": 18342, "Young Keltir": 20545, "Elpy": 20432, "Fox": 20116, "Brown Keltir": 20532}

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
    "Basic Wizard Staff": "ac9fe757-ab75-47ef-b413-8844d5c5ed73",
    "Long Sword +1": "019fe3f6-b1ee-78f8-a681-d288c7f87511",
    "Saber*Saber": "7d3f4a5b-8c9e-4a01-bc23-4d5e6f708192",
}


# Butin d'équipement : grade cohérent avec le niveau du monstre comme dans L2 (sans grade avant
# le niveau 15, D jusqu'au 29, C au-delà ; un grade de plus pour un boss de raid).


def tier_loot(level):
    """Consommables communs selon la tranche de niveau."""
    if level <= 10:
        return [(HEALING, 0.10)]
    if level <= 24:
        return [(HEALING, 0.12), (GREATER_HEALING, 0.03), (MANA, 0.05), (ESCAPE, 0.01)]
    return [(GREATER_HEALING, 0.10), (GREATER_MANA, 0.05), (ESCAPE, 0.02)]


# (nom L2, id L2, race, agressif, XP L2, résistances, butin propre [(objet, chance)]) ; niveau
# et stats viennent de L2_NPC.
M = []


def mob(name, l2id, race, aggro, xp, res=None, loot=()):
    M.append(dict(name=name, l2id=l2id, level=L2_NPC[l2id]["level"], race=race, aggro=aggro, xp=xp,
                  res=res or {}, loot=list(loot), raid=False))


def raid(name, l2id, race, xp, res=None, loot=()):
    M.append(dict(name=name, l2id=l2id, level=L2_NPC[l2id]["level"], race=race, aggro=False, xp=xp,
                  res=res or {}, loot=list(loot), raid=True))


I = ITEMS
# --- Anciennes petites zones (retirées du monde, fiches gardées sans point d'apparition) -------
# Niveaux 3-5 : keltirs, loups et crapauds des bois.
mob("Elder Keltir", 20544, "ANIMAL", False, 105, loot=[(I["Leather Pants"], 0.03), (I["Leather Tunic"], 0.03)])
mob("Wolf", 20120, "ANIMAL", False, 141, loot=[(I["Wooden Bow"], 0.02)])
mob("Elder Wolf", 20442, "ANIMAL", False, 176, loot=[(I["Leather Gloves"], 0.03)])
mob("Giant Toad", 20121, "ANIMAL", False, 178, loot=[(I["Leather Boots"], 0.03)])
# Niveaux 5-10 : orques, gobelins et loups-garous.
mob("Goblin", 20003, "HUMANOID", False, 176, loot=[(I["Garnet Ring"], 0.03), (I["Garnet Earring"], 0.02)])
mob("Orc", 20130, "HUMANOID", False, 213, loot=[(I["Wooden Club"], 0.03)])
mob("Orc Grunt", 20131, "HUMANOID", False, 249, loot=[(I["Wooden Shield"], 0.04)])
mob("Orc Archer", 20006, "HUMANOID", False, 293, loot=[(I["Wooden Bow"], 0.05)])
mob("Goblin Scout", 20326, "HUMANOID", False, 284, loot=[(I["Leather Cap"], 0.04), (I["Leather Tunic"], 0.01)])
mob("Werewolf", 20132, "HUMANOID", False, 321, loot=[(I["Leather Cap"], 0.03)])
mob("Orc Fighter", 20093, "HUMANOID", True, 363, loot=[(I["Short Sword"], 0.04), (I["Long Sword +1"], 0.01)])
# Niveaux 10-15 : loups-garous chasseurs, orques Vuku, bêtes d'ombre.
mob("Werewolf Hunter", 20343, "HUMANOID", True, 363, loot=[(I["Garnet Ring"], 0.02)])
mob("Vuku Orc", 20009, "HUMANOID", False, 650, loot=[(I["Spear"], 0.02)])
mob("Vuku Orc Archer", 20011, "HUMANOID", False, 700, loot=[(I["Wooden Bow"], 0.04)])
mob("Shadow Beast", 20023, "BEAST", False, 720, res={"DARK": 20, "HOLY": -20}, loot=[(I["Leather Armor"], 0.02)])
# --- Ruins of Agony (niveaux 15-25) -----------------------------------------------------------
mob("Ruin Zombie", 20026, "UNDEAD", False, 755, UNDEAD_RES, [(I["Padded Armor"], 0.03)])
mob("Ruin Zombie Leader", 20029, "UNDEAD", False, 807, UNDEAD_RES, [(I["Leather Armor"], 0.03)])
mob("Skeleton Tracker", 20035, "UNDEAD", False, 605, UNDEAD_RES, [(I["Dagger"], 0.04), (I["Wooden Shield"], 0.03)])
mob("Skeleton Tracker Leader", 20042, "UNDEAD", True, 652, UNDEAD_RES, [(I["Dagger"], 0.05), (I["Shield"], 0.02)])
mob("Skeleton Scout", 20045, "UNDEAD", False, 698, UNDEAD_RES, [(I["Wooden Bow"], 0.05)])
mob("Skeleton Bowman", 20051, "UNDEAD", False, 734, UNDEAD_RES, [(I["Wooden Bow"], 0.004)])
mob("Ruin Spartoi", 20054, "UNDEAD", False, 917, UNDEAD_RES, [(I["Saber"], 0.04), (I["Saber*Saber"], 0.004)])
mob("Raging Spartoi", 20060, "UNDEAD", True, 1005, UNDEAD_RES, [(I["Iron Helmet"], 0.03), (I["Saber*Saber"], 0.005)])
mob("Tumran Bugbear Warrior", 20064, "GIANT", True, 1145, loot=[(I["Pike"], 0.04), (I["Chain Mail"], 0.01)])
raid("Soul Scavenger", 25369, "UNDEAD", 2541012, UNDEAD_RES,
     [(I["Tsurugi"], 0.35), (I["Sword of Valhalla"], 0.2), (I["Doom Gloves"], 0.3), (I["Amethyst Ring"], 0.25), (MAJOR_HEALING, 0.5)])
# --- Ruins of Despair (niveaux 15-25) ---------------------------------------------------------
mob("Shield Skeleton", 20514, "UNDEAD", False, 534, UNDEAD_RES, [(I["Shield"], 0.04), (I["Wooden Club"], 0.04)])
mob("Skeleton Infantryman", 20515, "UNDEAD", False, 570, UNDEAD_RES, [(I["Wooden Shield"], 0.05)])
mob("Ruin Imp", 20506, "FAIRY", False, 605, FAIRY_RES, [(I["Amber Earring"], 0.02)])
mob("Scavenger Bat", 20411, "ANIMAL", False, 640, BAT_RES, [(I["Garnet Earring"], 0.03)])
mob("Zombie Soldier", 20457, "UNDEAD", False, 958, UNDEAD_RES, [(I["Iron Helmet"], 0.03), (I["Chain Mail"], 0.008)])
mob("Ruin Bat", 20505, "ANIMAL", False, 712, BAT_RES, [(I["Amber Ring"], 0.02)])
mob("Ruin Imp Elder", 20507, "FAIRY", True, 935, FAIRY_RES, [(I["Basic Wizard Staff"], 0.02), (I["Amber Necklace"], 0.02)])
mob("Zombie Warrior", 20458, "UNDEAD", True, 1421, UNDEAD_RES, [(I["Chain Mail"], 0.01), (I["Iron Helmet"], 0.004)])
mob("Veelan Bugbear", 20401, "GIANT", False, 1054, loot=[(I["Pike"], 0.04)])
mob("Veelan Bugbear Warrior", 20402, "GIANT", True, 1145, loot=[(I["Spear"], 0.04), (I["Chain Mail"], 0.01)])
raid("Zombie Lord Crowl", 25149, "UNDEAD", 2541012, UNDEAD_RES,
     [(I["Sword of Valhalla"], 0.25), (I["Plate Armor"], 0.15), (I["Doom Helmet"], 0.3), (I["Amethyst Necklace"], 0.2), (MAJOR_HEALING, 0.5)])
# --- Cruma Marshlands (niveaux 25-35) ---------------------------------------------------------
mob("Giant Mist Leech", 20225, "BUG", False, 1190, BUG_RES, [(I["Leather Armor"], 0.02)])
mob("Gray Ant", 20226, "BUG", False, 1268, BUG_RES, [(I["Iron Helmet"], 0.02)])
mob("Horror Mist Ripper", 20227, "UNDEAD", True, 1349, UNDEAD_RES, [(I["Amber Necklace"], 0.02)])
mob("Giant Crimson Ant", 20228, "BUG", False, 1555, BUG_RES, [(I["Leather Armor"], 0.01)])
mob("Marsh Stakato", 20157, "HUMANOID", True, 1811, BUG_RES, [(I["Amber Ring"], 0.008), (I["Dagger"], 0.03)])
mob("Stinger Wasp", 20229, "BUG", True, 1744, BUG_RES, [(I["Amethyst Ring"], 0.004)])
mob("Marsh Stakato Worker", 20230, "HUMANOID", False, 1995, BUG_RES, [(I["Helm of Terror"], 0.008), (I["Chain Mail"], 0.015)])
mob("Toad Lord", 20231, "ANIMAL", False, 1946, loot=[(I["Helm of Terror"], 0.01)])
mob("Marsh Stakato Soldier", 20232, "HUMANOID", False, 1900, BUG_RES, [(I["Tsurugi"], 0.004), (I["Shield +1"], 0.004)])
mob("Marsh Spider", 20233, "BUG", True, 2241, BUG_RES, [(I["Zealot's Armor"], 0.004)])
mob("Marsh Stakato Drone", 20234, "HUMANOID", True, 2267, BUG_RES, [(I["Battle Axe"], 0.003), (I["Amethyst Necklace"], 0.004)])
raid("Stakato Queen Zyrnna", 25023, "HUMANOID", 2316589, BUG_RES,
     [(I["Sword of Miracle"], 0.15), (I["Hammer of Ruin"], 0.2), (I["Plate Armor"], 0.3), (I["Doom Breastplate"], 0.35), (MAJOR_HEALING, 0.6)])
# --- Gludio Castle : bois de l'ouest (lézards Maille, araignées) et de l'est (hommes-rats) ---
mob("Maille Lizardman", 20919, "HUMANOID", False, 320, loot=[(I["Spear"], 0.03)])
mob("Maille Lizardman Scout", 20920, "HUMANOID", False, 712, loot=[(I["Wooden Bow"], 0.04)])
mob("Maille Lizardman Guard", 20921, "HUMANOID", True, 515, loot=[(I["Spear"], 0.04), (I["Pike"], 0.003)])
mob("Giant Araneid", 20925, "BUG", False, 525, BUG_RES, [(I["Leather Armor"], 0.03)])
mob("Poison Araneid", 20926, "BUG", False, 607, BUG_RES, [(I["Leather Armor"], 0.01)])
mob("Maille Lizardman Warrior", 20922, "HUMANOID", False, 570, loot=[(I["Pike"], 0.004)])
mob("King of the Araneid", 20927, "BUG", True, 872, BUG_RES, [(I["Amber Earring"], 0.01)])
mob("Maille Lizardman Shaman", 20923, "HUMANOID", False, 835, loot=[(I["Basic Wizard Staff"], 0.03)])
mob("Maille Lizardman Matriarch", 20924, "HUMANOID", True, 1025, loot=[(I["Shield +1"], 0.006), (I["Helm of Terror"], 0.01)])
mob("Ratman Spy", 20360, "HUMANOID", False, 570, loot=[(I["Dagger"], 0.04)])
mob("Pinrul", 20032, "BUG", False, 605, BUG_RES, [(I["Padded Armor"], 0.03)])
mob("Bugbear Raider", 20775, "GIANT", True, 599, loot=[(I["Pike"], 0.03)])
mob("Ratman Hunter", 20358, "HUMANOID", False, 640, loot=[(I["Leather Armor"], 0.02)])
mob("Ratman Sub Chieftain", 21093, "HUMANOID", True, 691, loot=[(I["Saber"], 0.03)])
mob("Ratman Chieftain", 21094, "HUMANOID", False, 712, loot=[(I["Saber"], 0.003), (I["Iron Helmet"], 0.03)])
raid("Sukar Wererat Chief", 25357, "HUMANOID", 2646357, None,
     [(I["Tsurugi"], 0.3), (I["Chain Mail"], 0.4), (I["Amethyst Ring"], 0.2), (MAJOR_HEALING, 0.4)])
# --- Neutral Zone (niveaux 15-20) : araignées charognardes, bêtes de pierre de lune, lycanthropes --
mob("Scavenger Spider", 20410, "BUG", True, 545, BUG_RES, [(I["Leather Armor"], 0.02)])
mob("Moonstone Beast", 20369, "BEAST", False, 599, loot=[(I["Amber Earring"], 0.02)])
mob("Scavenger Wererat", 20039, "HUMANOID", False, 640, loot=[(I["Dagger"], 0.04)])
mob("Arachnid Tracker", 20043, "BUG", True, 760, BUG_RES, [(I["Padded Armor"], 0.03)])
mob("Lycanthrope", 20049, "HUMANOID", True, 726, loot=[(I["Iron Helmet"], 0.03), (I["Saber"], 0.01)])
# --- Fellmere Lake (niveaux 14-25) : lézards Felim des rives, ours et loups-garous des bois, camp
# abandonné des Ol Mahum au sud du lac ---------------------------------------------------------
mob("Felim Lizardman", 20008, "HUMANOID", False, 498, loot=[(I["Spear"], 0.03)])
mob("Red Bear", 20021, "ANIMAL", False, 498, loot=[(I["Leather Armor"], 0.02)])
mob("Felim Lizardman Scout", 20010, "HUMANOID", False, 534, loot=[(I["Wooden Bow"], 0.04)])
mob("Gora Werewolf", 20012, "HUMANOID", True, 582, loot=[(I["Leather Cap"], 0.03), (I["Padded Helmet"], 0.02)])
mob("Felim Lizardman Warrior", 20014, "HUMANOID", False, 605, loot=[(I["Pike"], 0.02), (I["Shield"], 0.02)])
mob("Grizzly Bear", 20335, "ANIMAL", False, 599, loot=[(I["Padded Helmet"], 0.03)])
mob("Ol Mahum Novice", 20782, "HUMANOID", True, 618, loot=[(I["Short Sword"], 0.04)])
mob("Ratman Warrior", 20359, "HUMANOID", False, 678, loot=[(I["Saber"], 0.03)])
mob("Arachnid Predator", 20050, "BUG", True, 799, BUG_RES, [(I["Amber Ring"], 0.02)])
mob("Wandering Eye", 20055, "CONSTRUCT", False, 917, loot=[(I["Amber Earring"], 0.02)])
mob("Ol Mahum Recruit", 20437, "HUMANOID", False, 917, loot=[(I["Spear"], 0.03)])
mob("Ol Mahum Patrol", 20053, "HUMANOID", False, 944, loot=[(I["Iron Helmet"], 0.03)])
mob("Hungry Eye", 20059, "CONSTRUCT", False, 985, loot=[(I["Amber Necklace"], 0.015)])
mob("Ol Mahum Guard", 20058, "HUMANOID", False, 985, loot=[(I["Shield"], 0.03), (I["Chain Mail"], 0.008)])
mob("Ol Mahum Supplier", 20436, "HUMANOID", False, 1054, loot=[(GREATER_HEALING, 0.08), (ESCAPE, 0.03)])
mob("Ol Mahum Straggler", 20061, "HUMANOID", True, 1075, loot=[(I["Battle Axe"], 0.003), (I["Leather Armor"], 0.02)])
mob("Ol Mahum Officer", 20439, "HUMANOID", False, 1122, loot=[(I["Tsurugi"], 0.004), (I["Chain Mail"], 0.01)])
mob("Ol Mahum Captain", 20066, "HUMANOID", True, 1263, loot=[(I["Helm of Terror"], 0.01), (I["Pike"], 0.02)])
raid("Greyclaw Kutus", 25001, "HUMANOID", 2690116, None,
     [(I["Sword of Valhalla"], 0.2), (I["Doom Helmet"], 0.3), (I["Chain Mail"], 0.4), (MAJOR_HEALING, 0.4)])
raid("Princess Molrang", 25076, "ANIMAL", 2541012, None,
     [(I["Bow of Peril"], 0.25), (I["Zealot's Armor"], 0.3), (I["Amethyst Necklace"], 0.2), (MAJOR_HEALING, 0.5)])
# --- Execution Grounds (niveaux 26-35) : spectres et goules des suppliciés, golems, pendus ------
mob("Specter", 20171, "UNDEAD", True, 1293, UNDEAD_RES, [(I["Amber Necklace"], 0.015)])
mob("Sorrow Maiden", 20197, "ELEMENTAL", False, 1322, {"DARK": 20, "HOLY": -20}, [(I["Wand of Flames"], 0.01)])
mob("Neer Crawler", 20160, "UNDEAD", True, 1442, UNDEAD_RES, [(I["Chain Mail"], 0.01)])
mob("Neer Ghoul Berserker", 20198, "UNDEAD", True, 1522, UNDEAD_RES, [(I["Battle Axe"], 0.004)])
mob("Amber Basilisk", 20199, "BEAST", False, 1869, loot=[(I["Amber Ring"], 0.02)])
mob("Strain", 20200, "UNDEAD", False, 1660, UNDEAD_RES, [(I["Iron Helmet"], 0.03)])
mob("Ghoul", 20201, "UNDEAD", False, 2502, UNDEAD_RES, [(I["Helm of Terror"], 0.01)])
mob("Granite Golem", 20083, "CONSTRUCT", False, 2687, {"EARTH": 30, "WIND": -20}, [(I["Plate Armor"], 0.004)])
mob("Dead Seeker", 20202, "ANIMAL", False, 1997, loot=[(I["Zealot's Armor"], 0.004)])
mob("Hangman Tree", 20144, "PLANT", True, 2180, {"FIRE": -30}, [(I["Doom Gloves"], 0.006)])
raid("Revenant of Sir Calibus", 25383, "UNDEAD", 1918616, UNDEAD_RES,
     [(I["Hammer of Ruin"], 0.2), (I["Doom Helmet"], 0.3), (I["Amethyst Ring"], 0.25), (MAJOR_HEALING, 0.5)])
raid("Guillotine, Warden of the Execution Grounds", 25118, "UNDEAD", 1912394, UNDEAD_RES,
     [(I["Sword of Miracle"], 0.15), (I["Doom Breastplate"], 0.3), (I["Plate Armor"], 0.2), (MAJOR_HEALING, 0.5)])
# --- Dion Castle : plaines de Dion et abords de Floran (niveaux 23-35), lézards Delu, golems ----
mob("Tumran Bugbear", 20062, "GIANT", False, 1054, loot=[(I["Pike"], 0.03)])
mob("Dire Wolf", 20205, "ANIMAL", True, 1145, loot=[(I["Leather Armor"], 0.02)])
mob("Monster Eye Gazer", 20266, "CONSTRUCT", False, 1190, loot=[(I["Amber Earring"], 0.02)])
mob("Watchman of the Plains", 21102, "CONSTRUCT", True, 1602, loot=[(I["Amethyst Ring"], 0.005)])
mob("Roughly Hewn Rock Golem", 21103, "CONSTRUCT", False, 1677, {"EARTH": 30, "WIND": -20}, [(I["Shield +1"], 0.006)])
mob("Delu Lizardman Supplier", 21104, "HUMANOID", False, 2105, loot=[(I["Dagger"], 0.04), (I["Chain Mail"], 0.01)])
mob("Delu Lizardman Special Agent", 21105, "HUMANOID", False, 2426, loot=[(I["Bow of Peril"], 0.004)])
mob("Cursed Seer", 21106, "CONSTRUCT", True, 2057, loot=[(I["Wand of Flames"], 0.008)])
mob("Delu Lizardman Shaman", 20781, "HUMANOID", False, 2137, loot=[(I["Basic Wizard Staff"], 0.03)])
mob("Delu Lizardman Commander", 21107, "HUMANOID", False, 4354, loot=[(I["Tsurugi"], 0.006), (I["Helm of Terror"], 0.01)])


ATTRS = ("STR", "DEX", "CON", "INT", "WIT", "MEN")


def num(value):
    """Nombre du datapack sans zéros inutiles (39.75, 253)."""
    return f"{value:g}"


def build(m):
    """Fiche serveur : valeurs de base L2 telles quelles, XP/or propres au jeu."""
    npc = L2_NPC[m["l2id"]]
    level = m["level"]
    gold = round(level * (4 + level * 0.2))
    xp = m["xp"]
    if m["raid"]:
        # Boss de raid : XP ramenée à 5 % (rythme de progression du jeu), or forfaitaire.
        xp = xp * 0.05
        gold = 40 * level * 5
    stats = dict(maxHealth=npc["hp"], pAtk=npc["pAtk"], pDef=npc["pDef"], mAtk=npc["mAtk"], mDef=npc["mDef"],
                 accuracyBonus=npc["acc"], evasionBonus=npc["eva"], critBonus=npc["crit"], xpReward=round(xp))
    attrs = dict(zip(ATTRS, npc["attrs"]))
    loot = tier_loot(level) + m["loot"]
    return stats, attrs, gold, loot, npc


def monster_id(name):
    return str(uuid.uuid5(NAMESPACE, name))


def xml_entry(m):
    stats, attrs, gold, loot, npc = build(m)
    kind = "boss de raid" if m["raid"] else ("agressif" if m["aggro"] else "passif")
    lines = [f'    <!-- {m["name"]} (L2 npc {m["l2id"]}, niveau {m["level"]}, {kind}) -->',
             f'    <monster id="{monster_id(m["name"])}">',
             f'        <name>{m["name"]}</name>',
             f'        <race>{m["race"]}</race>',
             f'        <maxHealth>{num(stats["maxHealth"])}</maxHealth>',
             f'        <pAtk>{num(stats["pAtk"])}</pAtk>',
             f'        <pDef>{num(stats["pDef"])}</pDef>',
             f'        <mAtk>{num(stats["mAtk"])}</mAtk>',
             f'        <mDef>{num(stats["mDef"])}</mDef>',
             f'        <accuracyBonus>{num(stats["accuracyBonus"])}</accuracyBonus>',
             f'        <evasionBonus>{num(stats["evasionBonus"])}</evasionBonus>',
             f'        <critBonus>{num(stats["critBonus"])}</critBonus>',
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
              f'        <speed>{num(npc["run"])}</speed>',
              f'        <atkSpd>{npc["atkSpd"]}</atkSpd>',
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


def rewrite_historic(text):
    """Stats L2 des fiches historiques (monstres de départ), réécrites en place."""
    for name, l2id in HISTORIC.items():
        npc = L2_NPC[l2id]
        start = text.index(f"<name>{name}</name>")
        end = text.index("</monster>", start)
        body = text[start:end]
        values = dict(maxHealth=npc["hp"], pAtk=npc["pAtk"], pDef=npc["pDef"], mAtk=npc["mAtk"], mDef=npc["mDef"],
                      accuracyBonus=npc["acc"], evasionBonus=npc["eva"], critBonus=npc["crit"], speed=npc["run"],
                      atkSpd=npc["atkSpd"], level=npc["level"], **dict(zip(ATTRS, npc["attrs"])))
        for tag, value in values.items():
            body = re.sub(rf"<{tag}>[^<]*</{tag}>", f"<{tag}>{num(value)}</{tag}>", body, count=1)
        text = text[:start] + body + text[end:]
    return text


def main():
    target = Path(sys.argv[1])
    text = target.read_text(encoding="utf-8")
    if BEGIN in text:
        text = text[:text.index(BEGIN)].rstrip() + "\n</monsters>\n"
    # Monstres historiques : passifs comme dans L2 (aggroRadius, jusqu'ici inutilisé, active
    # désormais l'agression).
    text = re.sub(r"<aggroRadius>\d+</aggroRadius>", "<aggroRadius>0</aggroRadius>", text)
    text = rewrite_historic(text)
    block = "\n".join([BEGIN] + [xml_entry(m) for m in M] + [END])
    text = text.replace("</monsters>", block + "\n</monsters>")
    target.write_text(text, encoding="utf-8", newline="\n")
    gd = Path(__file__).resolve().parents[1] / "map_gen" / "L2Monsters.gd"
    gd.write_text(gd_table(), encoding="utf-8", newline="\n")
    print(f"{len(M)} fiches écrites dans {target}, table {gd}")
    for m in M:
        s, _, gold, _, _ = build(m)
        print(f'  {m["name"]:<28} lv{m["level"]:>2} hp {num(s["maxHealth"]):>8} patk {num(s["pAtk"]):>6} '
              f'pdef {num(s["pDef"]):>6} mdef {num(s["mDef"]):>6} xp {s["xpReward"]:>6} gold {gold:>5} aggro {m["aggro"]}')


if __name__ == "__main__":
    main()
