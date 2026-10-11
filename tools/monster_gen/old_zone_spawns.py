"""Outil hors-ligne : points d'apparition des monstres L2 ajoutés aux anciennes petites zones
(Sentier broussailleux, Repaire sauvage, Chemin du cimetière, Cimetière abandonné), qui
comblent la progression entre les monstres de départ (niveaux 1-2) et la région de Gludio
(niveaux 15+).

Ces cartes n'ont pas de générateur et leurs scènes client sont périmées par rapport au serveur
(voir tools/export_map_to_tmx.gd) : on écrit donc directement dans les .tmx du backend. Les
monstres historiques de ces cartes sont conservés ; les objets ajoutés ici portent le nom
"zone:<groupe>" et sont remplacés à chaque exécution (script rejouable).

Usage : python -I tools/monster_gen/old_zone_spawns.py <backend>/src/main/resources/data/maps
"""
import random
import re
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_monsters import monster_id  # noqa: E402

TILE = 32
# carte -> [(groupe, [(monstre, poids)], nombre, réapparition en s)]
ZONES = {
    "Sentier_broussailleux": [
        ("Sentier_Loups", [("Elder Keltir", 2), ("Wolf", 2), ("Elder Wolf", 1), ("Giant Toad", 1)], 10, 30),
    ],
    "Repaire_sauvage": [
        ("Repaire_Camp", [("Goblin", 2), ("Orc", 2), ("Orc Grunt", 2), ("Orc Archer", 1), ("Goblin Scout", 1),
                          ("Werewolf", 1), ("Orc Fighter", 1)], 12, 30),
    ],
    "Chemin_du_cimetière": [
        ("Chemin_Rodeurs", [("Werewolf Hunter", 1), ("Vuku Orc", 2), ("Vuku Orc Archer", 1), ("Shadow Beast", 1)], 9, 30),
    ],
    "Cimetière_abandonné": [
        ("Cimetiere_MortsVivants", [("Ruin Zombie", 2), ("Ruin Zombie Leader", 1), ("Skeleton Tracker", 1),
                                    ("Zombie Soldier", 1)], 9, 30),
    ],
}
SPAWN_CLEARANCE = 8.0
PORTAL_CLEARANCE = 6.0
SPACING = 3.0
GENERATED = re.compile(r'\s*<object id="\d+" name="zone:[^"]*".*?</object>', re.S)


def walkable_grid(text):
    tiles = {}
    first = int(re.search(r'<tileset firstgid="(\d+)"', text).group(1))
    for m in re.finditer(r'<tile id="(\d+)">(.*?)</tile>', text, re.S):
        walk = re.search(r'name="walkable" type="bool" value="(\w+)"', m.group(2))
        tiles[first + int(m.group(1))] = walk is None or walk.group(1) == "true"
    w = int(re.search(r'<map [^>]*?\swidth="(\d+)"', text).group(1))
    h = int(re.search(r'<map [^>]*?\sheight="(\d+)"', text).group(1))
    csv = re.search(r'<data encoding="csv">(.*?)</data>', text, re.S).group(1)
    gids = [int(v) for v in csv.replace("\n", "").split(",") if v.strip()]
    return w, h, [tiles.get(g, True) for g in gids]


def points(text, kind):
    return [(float(m.group(1)) / TILE, float(m.group(2)) / TILE)
            for m in re.finditer(rf'type="{kind}" x="([\d.]+)" y="([\d.]+)"', text)]


def reachable(w, h, walk, start):
    seen = [False] * (w * h)
    sx, sz = int(start[0]), int(start[1])
    queue = deque([sz * w + sx])
    seen[sz * w + sx] = True
    while queue:
        i = queue.popleft()
        x, z = i % w, i // w
        for nx, nz in ((x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)):
            j = nz * w + nx
            if 0 <= nx < w and 0 <= nz < h and not seen[j] and walk[j]:
                seen[j] = True
                queue.append(j)
    return seen


def dist(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5


def main():
    maps_dir = Path(sys.argv[1])
    for map_name, zones in ZONES.items():
        path = maps_dir / f"{map_name}.tmx"
        text = path.read_text(encoding="utf-8")
        text = GENERATED.sub("", text)
        w, h, walk = walkable_grid(text)
        spawn = points(text, "playerSpawn")[0]
        portals = points(text, "portal")
        taken = points(text, "monsterSpawn")
        ok = reachable(w, h, walk, spawn)
        next_id = max(int(v) for v in re.findall(r'<object id="(\d+)"', text)) + 1
        rng = random.Random(map_name)
        added = []
        for group, monsters, count, respawn in zones:
            cells = [(x + 0.5, z + 0.5) for z in range(h) for x in range(w) if ok[z * w + x]]
            rng.shuffle(cells)
            placed = 0
            for p in cells:
                if placed >= count:
                    break
                if dist(p, spawn) < SPAWN_CLEARANCE or any(dist(p, q) < PORTAL_CLEARANCE for q in portals):
                    continue
                if any(dist(p, q) < SPACING for q in taken):
                    continue
                # Un exemplaire de chaque espèce d'abord, puis tirage pondéré.
                name = monsters[placed][0] if placed < len(monsters) else \
                    rng.choices([m[0] for m in monsters], [m[1] for m in monsters])[0]
                added.append(
                    f'  <object id="{next_id}" name="zone:{group}" type="monsterSpawn" x="{p[0] * TILE:.1f}" y="{p[1] * TILE:.1f}">\n'
                    f'   <properties>\n'
                    f'    <property name="templateId" value="{monster_id(name)}"/>\n'
                    f'    <property name="spawnGroup" value="{group}"/>\n'
                    f'   </properties>\n'
                    f'  </object>')
                taken.append(p)
                next_id += 1
                placed += 1
            added.append(
                f'  <object id="{next_id}" name="zone:{group}" type="monsterSpawnGroup" x="0.0" y="0.0">\n'
                f'   <properties>\n'
                f'    <property name="groupId" value="{group}"/>\n'
                f'    <property name="maxMonsters" type="int" value="{placed}"/>\n'
                f'    <property name="respawnDelaySeconds" type="int" value="{respawn}"/>\n'
                f'   </properties>\n'
                f'  </object>')
            next_id += 1
            print(f"{map_name}: {group} {placed}/{count}")
        text = text.replace(" </objectgroup>", "\n".join(added) + "\n </objectgroup>", 1)
        text = re.sub(r'nextobjectid="\d+"', f'nextobjectid="{next_id}"', text, count=1)
        path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
