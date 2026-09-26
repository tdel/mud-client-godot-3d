"""Générateur des modèles du village fortifié (Place du village), exportés en glTF binaire
pour Godot. Réutilise les outils de maillage et les matériaux de build_environment.py.

Usage (depuis la racine du projet, après fetch_textures.py) :
    blender -b --python tools/env_gen/build_village.py

Sortie : assets/environment/models/village/
    rampart_wall.glb          tronçon de courtine de 4 m (X), 2,4 m d'épaisseur, créneaux des
                              deux côtés ; mis bout à bout (et étiré) le long des remparts.
    rampart_tower.glb         tour ronde crénelée ; rampart_tower_roofed.glb : même tour
                              coiffée d'une poivrière d'ardoise.
    gatehouse.glb             porte fortifiée : deux tours carrées reliées par un arc (passage
                              de 3,8 m selon Y, herse levée, vantaux ouverts côté +Y =
                              intérieur de l'enceinte), bannières.
    house_small/medium/large  maisons à colombages (porte en façade -Y Blender = +Z Godot).
    inn.glb                   auberge (grande maison, enseigne, auvent).
    forge.glb                 forge : maison + appentis ouvert (foyer, enclume, auge).
    teleporter.glb            socle de téléporteur (dallage runique au ras du sol, quatre
                              obélisques bas) ; teleporter_crystals = cristaux flottants
                              (animés côté Godot, voir scenes/maps/props/Teleporter.gd).
    market_stall_red/blue     étals à auvent de toile ; well.glb puits ; fence.glb clôture 2 m.

Conventions : identiques à build_environment.py (Blender Z haut, +Y Blender = -Z Godot,
1 case = 1 m, aucune image embarquée : matériaux remplacés par nom côté Godot, voir
scenes/maps/common/EnvMaterials.gd). Matériaux lumineux (window_glass, lamp_glass, rune_glow,
forge_fire) pilotés la nuit par EnvMaterials.set_night_factor.
"""

import math
import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True  # pas de __pycache__ dans tools/env_gen

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import build_environment as be  # noqa: E402
from build_environment import UP, MeshBuilder  # noqa: E402

OUT = os.path.join(be.OUT, "village")


def vmats():
    m = be.mats()
    m.update({
        "castle_stone": be.pbr("castle_stone", "Bricks076A"),
        "rubble_stone": be.pbr("rubble_stone", "Bricks102"),
        "plaster": be.pbr("plaster", "Plaster003"),
        "roof_tiles": be.pbr("roof_tiles", "RoofingTiles006"),
        "window_glass": be.material("window_glass", base=(0.06, 0.07, 0.1), roughness=0.2),
        "rune_glow": be.material("rune_glow", base=(0.3, 0.6, 1.0), emission=(0.3, 0.6, 1.0)),
        "forge_fire": be.material("forge_fire", base=(1.0, 0.45, 0.1), emission=(1.0, 0.45, 0.1)),
        "cloth_red": be.material("cloth_red", base=(0.55, 0.08, 0.07)),
        "cloth_blue": be.material("cloth_blue", base=(0.1, 0.2, 0.5)),
        "cloth_cream": be.material("cloth_cream", base=(0.8, 0.74, 0.6)),
        "shadow_dark": be.material("shadow_dark", base=(0.03, 0.03, 0.03)),
    })
    return m


# ---------------------------------------------------------------------------
# Outils géométriques
# ---------------------------------------------------------------------------

def face(mb, pts, normal, mat, uv=None):
    """Polygone plan orienté vers `normal` (ordre des sommets inversé au besoin)."""
    pts = [Vector(p) for p in pts]
    if uv is None:
        uv = [(0, 0)] * len(pts)
    n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
    if n.dot(Vector(normal)) < 0:
        pts = list(reversed(pts))
        uv = list(reversed(uv))
    idx = [mb.add_vert(p) for p in pts]
    mb.add_face(idx, uv, mat)


def planar_uv(pts, u_axis, v_axis, texel):
    return [(Vector(p).dot(u_axis) / texel, Vector(p).dot(v_axis) / texel) for p in pts]


def basis(u, n):
    """Matrice de rotation : X local -> u, Y local -> n, Z local -> haut."""
    u, n = Vector(u), Vector(n)
    return Matrix(((u.x, n.x, 0), (u.y, n.y, 0), (0, 0, 1)))


class Facade:
    """Repère d'une face de mur : origine au pied, au centre ; u horizontal le long de la
    face, n normale sortante. Place des boîtes (poutres, fenêtres...) en coordonnées
    (u, z, profondeur hors du mur)."""

    def __init__(self, mb, origin, u, n):
        self.mb = mb
        self.o = Vector(origin)
        self.u = Vector(u)
        self.n = Vector(n)
        self.rot = basis(u, n)

    def at(self, u, z, d=0.0):
        return self.o + self.u * u + UP * z + self.n * d

    def box(self, u, z, size, mat, d=None, texel=1.0, angle=0.0):
        """Boîte centrée en (u, z), de taille (le long de u, épaisseur, hauteur), posée contre
        le mur (dépasse de size[1] * 0.7 sauf `d` explicite)."""
        depth = size[1] * 0.2 if d is None else d
        rot = self.rot @ Matrix.Rotation(-angle, 3, "Y") if angle else self.rot
        self.mb.box(self.at(u, z, depth), size, mat, rot=rot, texel=texel)

    def beam(self, u0, z0, u1, z1, mat, width=0.16, thick=0.07):
        du, dz = u1 - u0, z1 - z0
        length = math.hypot(du, dz)
        self.box((u0 + u1) / 2, (z0 + z1) / 2, (length, thick, width), mat, d=thick * 0.25,
                 angle=math.atan2(dz, du))


def window(fac, m, u, z, w=0.8, h=1.0, shutters=True, rng=None):
    wood = m["wood_dark"]
    fac.box(u, z, (w, 0.05, h), m["window_glass"], d=0.0)
    t = 0.08
    for du in (-w / 2, w / 2):
        fac.box(u + du, z, (t, 0.09, h + t), wood, d=0.03)
    for dz in (-h / 2, h / 2):
        fac.box(u, z + dz, (w + t, 0.09, t), wood, d=0.03)
    fac.box(u, z, (0.05, 0.08, h), wood, d=0.03)
    fac.box(u, z + h * 0.1, (w, 0.08, 0.05), wood, d=0.03)
    fac.box(u, z - h / 2 - 0.08, (w + 0.25, 0.16, 0.08), m["stone_smooth"], d=0.06, texel=0.5)
    if shutters:
        mat = m["planks_old"]
        for side in (-1, 1):
            fac.box(u + side * (w / 2 + w / 4 + 0.07), z, (w / 2, 0.04, h + 0.05), mat, d=0.05, texel=0.8)


def door(fac, m, u, width=1.1, height=2.1, z0=0.5):
    wood = m["wood_dark"]
    fac.box(u, z0 + height / 2, (width, 0.08, height), m["planks_old"], d=0.0, texel=1.0)
    for du in (-width / 2 - 0.07, width / 2 + 0.07):
        fac.box(u + du, z0 + height / 2 + 0.05, (0.14, 0.12, height + 0.1), wood, d=0.04)
    fac.box(u, z0 + height + 0.1, (width + 0.4, 0.14, 0.18), wood, d=0.05)
    for dz in (0.5, height - 0.5):
        fac.box(u - width * 0.1, z0 + dz, (width * 0.7, 0.1, 0.05), m["iron"], d=0.03)
    # Marche de pierre.
    fac.mb.box(fac.at(u, z0 / 2 - 0.05, 0.3), (width + 0.5, 0.6, z0 + 0.1), m["stone_smooth"], rot=fac.rot,
               texel=0.8)


def wall_lantern(fac, m, u, z):
    iron = m["iron"]
    fac.box(u, z + 0.35, (0.05, 0.45, 0.05), iron, d=0.22)
    fac.box(u, z, (0.16, 0.16, 0.24), m["lamp_glass"], d=0.42)
    fac.box(u, z + 0.14, (0.22, 0.22, 0.05), iron, d=0.42)
    fac.box(u, z - 0.14, (0.18, 0.18, 0.04), iron, d=0.42)


def gable_roof(mb, m, L, D, z0, pitch=math.radians(40), overhang=0.4, gable_over=0.3, mat=None):
    """Toit à deux pans, faîtage selon X ; renvoie la hauteur du faîtage."""
    mat = mat or m["roof_tiles"]
    rise = D / 2 * math.tan(pitch)
    ridge_z = z0 + rise
    thick = 0.14
    for side in (-1, 1):
        eave = Vector((0, side * (D / 2 + overhang), z0 - overhang * math.tan(pitch)))
        ridge = Vector((0, 0, ridge_z))
        v = (ridge - eave)
        length = v.length
        v.normalize()
        n = Vector((0, v.z, -v.y)) * side
        rot = Matrix(((1, 0, 0), (0, v.y, n.y), (0, v.z, n.z)))
        mb.box((eave + ridge) / 2 + n * thick / 2, (L + 2 * gable_over, length + 0.05, thick), mat, rot=rot,
               texel=2.0)
    mb.box((0, 0, ridge_z + 0.12), (L + 2 * gable_over + 0.05, 0.26, 0.26), m["roof_tiles"],
           rot=Matrix.Rotation(math.pi / 4, 3, "X"), texel=1.0)
    return ridge_z


def gables(mb, m, L, D, z0, ridge_z, timber=True):
    for sx in (-1, 1):
        x = sx * L / 2
        pts = [(x, -D / 2, z0), (x, D / 2, z0), (x, 0, ridge_z)]
        face(mb, pts, (sx, 0, 0), m["plaster"], planar_uv(pts, Vector((0, 1, 0)), UP, 2.0))
        if timber:
            fac = Facade(mb, (x, 0, 0), (0, -sx, 0), (sx, 0, 0))
            fac.beam(0, z0, 0, ridge_z - 0.1, m["wood_dark"])
            fac.beam(-D / 4, z0 + (ridge_z - z0) / 2, D / 4, z0 + (ridge_z - z0) / 2, m["wood_dark"])
            fac.beam(-D / 2 + 0.1, z0, 0, ridge_z - 0.05, m["wood_dark"])
            fac.beam(D / 2 - 0.1, z0, 0, ridge_z - 0.05, m["wood_dark"])


def timber_storey(mb, m, L, D, z0, h, rng, windows_by_face, door_face=None, door_u=0.0, door_w=1.1):
    """Étage à colombages : poteaux, sablières, écharpes ; fenêtres aux positions données
    ({face: [u...]}, faces "front" (-Y), "back" (+Y), "left" (-X), "right" (+X))."""
    wood = m["wood_dark"]
    faces = {
        "front": Facade(mb, (0, -D / 2, 0), (1, 0, 0), (0, -1, 0)),
        "back": Facade(mb, (0, D / 2, 0), (-1, 0, 0), (0, 1, 0)),
        "left": Facade(mb, (-L / 2, 0, 0), (0, -1, 0), (-1, 0, 0)),
        "right": Facade(mb, (L / 2, 0, 0), (0, 1, 0), (1, 0, 0)),
    }
    for key, fac in faces.items():
        width = L if key in ("front", "back") else D
        fac.box(0, z0 + 0.08, (width + 0.1, 0.1, 0.16), wood, d=0.03)
        fac.box(0, z0 + h - 0.08, (width + 0.1, 0.1, 0.16), wood, d=0.03)
        wins = windows_by_face.get(key, [])
        openings = [(u, 0.95) for u in wins]
        if key == door_face:
            openings.append((door_u, door_w / 2 + 0.15))
        bays = max(2, round(width / 1.4))
        posts = [-width / 2 + i * width / bays for i in range(bays + 1)]
        for u in posts:
            if any(abs(u - ou) < r + 0.05 for ou, r in openings):
                continue
            fac.box(u, z0 + h / 2, (0.16, 0.1, h), wood, d=0.03)
        for i in range(bays):
            u0, u1 = posts[i], posts[i + 1]
            mid = (u0 + u1) / 2
            if any(abs(mid - ou) < (u1 - u0) / 2 + r for ou, r in openings):
                continue
            if rng.random() < 0.6:
                if rng.random() < 0.5:
                    fac.beam(u0 + 0.08, z0 + 0.16, u1 - 0.08, z0 + h - 0.16, wood, width=0.14)
                else:
                    fac.beam(u0 + 0.08, z0 + h - 0.16, u1 - 0.08, z0 + 0.16, wood, width=0.14)
            else:
                fac.box(mid, z0 + h * 0.5, (u1 - u0, 0.1, 0.14), wood, d=0.03)
        for u in wins:
            window(fac, m, u, z0 + h * 0.55, rng=rng)
    return faces


def chimney(mb, m, x, y, z0, z1):
    mb.box((x, y, (z0 + z1) / 2), (0.7, 0.7, z1 - z0), m["rubble_stone"], texel=1.5)
    mb.box((x, y, z1 + 0.06), (0.85, 0.85, 0.12), m["stone_smooth"], texel=0.8)
    mb.box((x, y, z1 + 0.13), (0.4, 0.4, 0.04), m["shadow_dark"])


def build_house(name, m, L, D, floors, seed, windows, door_u=0.0, door_w=1.1, chimney_x=None, extra=None,
                lantern=True):
    """Maison à colombages. `windows` : {étage: {face: [u...]}} (u le long de la face)."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    stone, plaster = m["rubble_stone"], m["plaster"]
    plinth = 0.5
    h1 = 2.9
    h2 = 2.5
    mb.box((0, 0, plinth / 2), (L + 0.2, D + 0.2, plinth), stone, texel=2.0, skip=("-z",))
    if floors >= 2:
        # Rez-de-chaussée en moellons, étage à colombages en encorbellement.
        mb.box((0, 0, plinth + (h1 - plinth) / 2), (L, D, h1 - plinth), stone, texel=2.0, skip=("-z", "+z"))
        ground = {
            "front": Facade(mb, (0, -D / 2, 0), (1, 0, 0), (0, -1, 0)),
            "back": Facade(mb, (0, D / 2, 0), (-1, 0, 0), (0, 1, 0)),
            "left": Facade(mb, (-L / 2, 0, 0), (0, -1, 0), (-1, 0, 0)),
            "right": Facade(mb, (L / 2, 0, 0), (0, 1, 0), (1, 0, 0)),
        }
        for key, us in windows.get(0, {}).items():
            for u in us:
                window(ground[key], m, u, plinth + 1.3, w=0.75, h=0.9)
        door(ground["front"], m, door_u, width=door_w, z0=plinth)
        jetty = 0.3
        Lu, Du = L + 2 * jetty, D + 2 * jetty
        mb.box((0, 0, h1 + 0.1), (Lu + 0.1, Du + 0.1, 0.2), m["wood_dark"], texel=1.0)
        for x in [-Lu / 2 + 0.3 + i * 0.6 for i in range(int((Lu - 0.4) / 0.6) + 1)]:
            for sy in (-1, 1):
                mb.box((x, sy * (D / 2 + jetty / 2), h1 - 0.05), (0.14, jetty + 0.1, 0.14), m["wood_dark"], texel=0.5)
        z_up = h1 + 0.2
        mb.box((0, 0, z_up + h2 / 2), (Lu, Du, h2), plaster, texel=2.0, skip=("-z", "+z"))
        timber_storey(mb, m, Lu, Du, z_up, h2, rng, windows.get(1, {}))
        top = z_up + h2
    else:
        Lu, Du = L, D
        mb.box((0, 0, plinth + (h1 - plinth) / 2), (L, D, h1 - plinth), plaster, texel=2.0, skip=("-z", "+z"))
        faces = timber_storey(mb, m, L, D, plinth, h1 - plinth, rng, windows.get(0, {}), door_face="front",
                              door_u=door_u, door_w=door_w)
        door(faces["front"], m, door_u, width=door_w, z0=plinth)
        top = h1
    ridge = gable_roof(mb, m, Lu, Du, top)
    gables(mb, m, Lu, Du, top, ridge)
    cx = chimney_x if chimney_x is not None else Lu / 2 - 1.0
    chimney(mb, m, cx, Du * 0.18, top - 0.5, ridge + 0.9)
    if lantern:
        wall_lantern(Facade(mb, (0, -D / 2, 0), (1, 0, 0), (0, -1, 0)), m, door_u + door_w / 2 + 0.55, plinth + 2.0)
    if extra:
        extra(mb, m, L, D, Lu, Du, top, ridge, rng)
    return mb.build(name)


# ---------------------------------------------------------------------------
# Maisons, auberge, forge
# ---------------------------------------------------------------------------

def build_houses(m):
    build_house("house_small", m, 6.0, 5.0, 1, 101,
                {0: {"front": [-1.7, 1.7], "back": [-1.2, 1.4], "left": [0.0], "right": [0.4]}})
    build_house("house_medium", m, 7.0, 6.0, 2, 102,
                {0: {"front": [-2.3, 2.3], "right": [0.0], "back": [1.5]},
                 1: {"front": [-2.4, 0.0, 2.4], "back": [-2.0, 1.6], "left": [0.0], "right": [0.0]}},
                door_u=0.0)
    build_house("house_large", m, 9.0, 6.5, 2, 103,
                {0: {"front": [-3.2, -1.6, 2.4], "back": [-2.8, 0.0, 2.8], "left": [0.0], "right": [0.9]},
                 1: {"front": [-3.4, -1.2, 1.2, 3.4], "back": [-3.0, 0.0, 3.0], "left": [-1.2, 1.2],
                     "right": [-1.2, 1.2]}},
                door_u=0.6)

    def inn_extra(mb, m, L, D, Lu, Du, top, ridge, rng):
        wood = m["wood_dark"]
        # Auvent sur poteaux au-dessus de la porte double.
        mb.box((0, -D / 2 - 1.1, 2.85), (3.6, 2.5, 0.1), m["roof_tiles"], rot=Matrix.Rotation(0.25, 3, "X"),
               texel=2.0)
        for sx in (-1, 1):
            mb.box((sx * 1.55, -D / 2 - 2.1, 1.3), (0.16, 0.16, 2.6), wood, texel=0.8)
            mb.box((sx * 1.55, -D / 2 - 2.1, 0.05), (0.3, 0.3, 0.1), m["stone_smooth"], texel=0.5)
        mb.box((0, -D / 2 - 2.1, 2.55), (3.3, 0.16, 0.16), wood, texel=1.0)
        # Enseigne pendue à une potence, à l'angle de la façade.
        x = -L / 2 + 0.6
        mb.box((x, -D / 2 - 0.65, 3.35), (0.06, 1.3, 0.06), m["iron"])
        mb.tube([(x, -D / 2, 3.0), (x, -D / 2 - 0.5, 3.33)], [0.025, 0.025], 5, m["iron"])
        mb.box((x, -D / 2 - 0.85, 2.85), (0.06, 0.9, 0.62), m["wood_sign"], texel=0.8)
        for dy in (-0.35, 0.35):
            mb.box((x, -D / 2 - 0.85 + dy, 3.24), (0.015, 0.015, 0.18), m["iron"])
        # Deux lanternes pendues sous l'auvent ; seconde cheminée.
        for sx in (-1, 1):
            mb.box((sx * 1.2, -D / 2 - 1.9, 2.45), (0.02, 0.02, 0.2), m["iron"])
            mb.box((sx * 1.2, -D / 2 - 1.9, 2.22), (0.16, 0.16, 0.24), m["lamp_glass"])
            mb.box((sx * 1.2, -D / 2 - 1.9, 2.36), (0.22, 0.22, 0.05), m["iron"])
            mb.box((sx * 1.2, -D / 2 - 1.9, 2.08), (0.18, 0.18, 0.04), m["iron"])
        chimney(mb, m, -Lu / 2 + 1.2, -Du * 0.18, top - 0.5, ridge + 0.7)

    build_house("inn", m, 12.0, 8.0, 2, 104,
                {0: {"front": [-4.3, -2.6, 2.6, 4.3], "back": [-4.0, -1.5, 1.5, 4.0], "left": [-1.8, 1.8],
                     "right": [-1.8, 1.8]},
                 1: {"front": [-4.6, -2.8, -1.0, 1.0, 2.8, 4.6], "back": [-4.2, -2.1, 0.0, 2.1, 4.2],
                     "left": [-2.2, 0.0, 2.2], "right": [-2.2, 0.0, 2.2]}},
                door_u=0.0, door_w=1.8, chimney_x=4.8, extra=inn_extra, lantern=False)

    def forge_extra(mb, m, L, D, Lu, Du, top, ridge, rng):
        wood, stone, iron = m["wood_dark"], m["rubble_stone"], m["iron"]
        # Appentis ouvert contre le pignon +X : 4 m de profondeur, toit en pente douce.
        x0, x1 = L / 2, L / 2 + 4.0
        for y in (-D / 2 + 0.2, 0.0, D / 2 - 0.2):
            mb.box((x1 - 0.15, y, 1.3), (0.2, 0.2, 2.6), wood, texel=0.8)
            mb.box((x1 - 0.15, y, 0.08), (0.34, 0.34, 0.16), m["stone_smooth"], texel=0.5)
        mb.box((x1 - 0.15, 0, 2.6), (0.2, D, 0.2), wood, texel=1.0)
        slope = math.atan2(3.0 - 2.55, x1 - x0)
        mb.box(((x0 + x1) / 2 + 0.1, 0, 2.85), ((x1 - x0) + 0.6, D + 0.5, 0.12), m["roof_tiles"],
               rot=Matrix.Rotation(slope, 3, "Y"), texel=2.0)
        mb.box(((x0 + x1) / 2, 0, 0.03), (x1 - x0, D, 0.06), m["stone_smooth"], texel=1.5)
        # Foyer de forge : massif de pierre, gueule rougeoyante, hotte et cheminée.
        fx, fy = x0 + 1.0, D / 2 - 1.0
        mb.box((fx, fy, 0.5), (1.6, 1.4, 1.0), stone, texel=1.2)
        mb.box((fx, fy, 1.02), (1.1, 0.9, 0.06), m["forge_fire"])
        mb.box((fx, fy - 0.71, 0.55), (0.8, 0.02, 0.45), m["forge_fire"])
        mb.prism((fx, fy, 1.9), 1.0, 0.45, 1.0, 4, stone, texel=1.2, rot_offset=math.pi / 4, cap_top=False)
        chimney(mb, m, fx, fy, 2.9, ridge + 0.4)
        # Enclume sur billot.
        ax, ay = x0 + 2.2, -0.9
        mb.tube([(ax, ay, 0.0), (ax, ay, 0.55)], [0.28, 0.26], 9, m["bark_oak"], cap_top=True, cap_mat=m["wood_rings"])
        mb.box((ax, ay, 0.62), (0.2, 0.34, 0.14), iron, texel=0.4)
        mb.box((ax, ay, 0.76), (0.28, 0.62, 0.14), iron, texel=0.4)
        mb.tube([(ax, ay - 0.31, 0.78), (ax, ay - 0.55, 0.8)], [0.07, 0.01], 6, iron)
        # Auge d'eau, râtelier d'armes.
        mb.box((x1 - 0.9, -D / 2 + 0.9, 0.3), (1.2, 0.6, 0.6), m["planks_old"], texel=0.8)
        mb.box((x1 - 0.9, -D / 2 + 0.9, 0.55), (1.05, 0.45, 0.02), m["water"])
        mb.box((x0 + 0.12, -0.6, 1.2), (0.1, 2.2, 0.08), wood, texel=0.8)
        for k in range(5):
            y = -1.5 + k * 0.45
            mb.box((x0 + 0.22, y, 1.05), (0.03, 0.06, 1.1), iron, rot=Matrix.Rotation(0.12, 3, "Y"))
            mb.box((x0 + 0.24, y, 1.62), (0.05, 0.22, 0.04), wood)

    build_house("forge", m, 7.0, 6.0, 1, 105,
                {0: {"front": [-1.9, 1.9], "back": [-1.8, 1.4], "left": [0.0]}},
                door_u=-0.2, chimney_x=-2.2, extra=forge_extra)


# ---------------------------------------------------------------------------
# Remparts
# ---------------------------------------------------------------------------

def build_wall(m):
    mb = MeshBuilder()
    st, sm = m["castle_stone"], m["stone_smooth"]
    L, T, H = 4.0, 2.4, 5.0
    # Glacis au pied, courtine, cordon, parapets crénelés des deux côtés.
    mb.box((0, 0, 0.45), (L, T + 0.5, 0.9), st, texel=2.0, skip=("+x", "-x", "-z"))
    mb.box((0, 0, 0.9 + (H - 0.9) / 2), (L, T, H - 0.9), st, texel=2.0, skip=("+x", "-x", "-z", "+z"))
    mb.box((0, 0, H - 0.1), (L, T + 0.2, 0.2), sm, texel=1.0, skip=("+x", "-x"))
    for side in (-1, 1):
        y = side * (T / 2 - 0.1)
        mb.box((0, y, H + 0.3), (L, 0.4, 0.6), st, texel=2.0, skip=("+x", "-x", "-z"))
        for x in (-1.0, 1.0):
            mb.box((x, y, H + 0.6 + 0.45), (1.0, 0.4, 0.9), st, texel=2.0, skip=("-z",))
            mb.box((x, y, H + 1.54), (1.08, 0.48, 0.08), sm, texel=1.0)
            mb.box((x, side * (T / 2 + 0.105), H + 1.0), (0.12, 0.02, 0.5), m["shadow_dark"])
        # Trous de boulin et fente d'archère sur la courtine.
        for x in (-1.2, 1.2):
            mb.box((x, side * (T / 2 + 0.005), 2.8), (0.14, 0.02, 0.8), m["shadow_dark"])
    # Chemin de ronde dallé.
    mb.box((0, 0, H + 0.02), (L, T - 0.8, 0.04), sm, texel=1.5, skip=("+x", "-x", "-z"))
    mb.build("rampart_wall")


def tower_body(mb, m, R, H, sides=16):
    st, sm = m["castle_stone"], m["stone_smooth"]
    # Décalage d'une demi-facette : une face (et non une arête) regarde chaque axe.
    ro = math.pi / sides
    mb.prism((0, 0, 0), R + 0.45, R, 1.2, sides, st, texel=2.0, cap_top=False, rot_offset=ro)
    mb.prism((0, 0, 1.2), R, R, H - 1.2, sides, st, texel=2.0, cap_top=False, rot_offset=ro)
    mb.prism((0, 0, H), R, R + 0.35, 0.4, sides, sm, texel=1.0, cap_top=False, rot_offset=ro)
    mb.ring_wall((0, 0, H + 0.4), R + 0.35, R - 0.05, 0.0, 0.6, sides, st, sm, texel=2.0, rot_offset=ro)
    mb.disc((0, 0, H + 0.4), R - 0.05, sides, sm, uv_scale=3.0, rot_offset=ro)
    apothem = R * math.cos(math.pi / sides)
    for k in range(4):
        for z, off in ((3.2, 1), (5.6, 3)):
            a = (4 * k + off) / sides * math.tau
            mb.box((math.cos(a) * (apothem + 0.005), math.sin(a) * (apothem + 0.005), z), (0.02, 0.15, 0.8),
                   m["shadow_dark"], rot=Matrix.Rotation(a, 3, "Z"))
    # Porte basse côté intérieur (+Y).
    mb.box((0, apothem + 0.01, 1.4), (0.02, 1.0, 1.9), m["planks_old"], rot=Matrix.Rotation(math.pi / 2, 3, "Z"))


def build_towers(m):
    R, H = 3.0, 7.0
    mb = MeshBuilder()
    tower_body(mb, m, R, H)
    for k in range(8):
        a = (k + 0.5) / 8 * math.tau
        c = Vector((math.cos(a) * (R + 0.15), math.sin(a) * (R + 0.15), H + 1.0 + 0.4))
        mb.box(c, (0.4, 1.2, 0.8), m["castle_stone"], rot=Matrix.Rotation(a, 3, "Z"), texel=2.0)
    mb.build("rampart_tower")

    mb = MeshBuilder()
    tower_body(mb, m, R, H)
    mb.prism((0, 0, H + 1.0), R + 0.7, 0.06, 5.2, 16, m["roof_slate"], texel=1.5, cap_top=False, cap_bottom=True)
    mb.prism((0, 0, H + 6.1), 0.08, 0.02, 1.0, 6, m["iron"], texel=0.5)
    mb.box((0.25, 0, H + 6.8), (0.5, 0.02, 0.3), m["cloth_red"])
    mb.build("rampart_tower_roofed")


def build_gatehouse(m):
    mb = MeshBuilder()
    st, sm, dark = m["castle_stone"], m["stone_smooth"], m["shadow_dark"]
    TW, TD, TH = 4.2, 4.8, 8.6
    PW, DD, AH = 4.6, 3.6, 7.0
    OW, SZ = 3.8, 2.8
    r = OW / 2
    ox = PW / 2 + TW / 2
    for sx in (-1, 1):
        x = sx * ox
        mb.box((x, 0, 0.5), (TW + 0.4, TD + 0.4, 1.0), st, texel=2.0, skip=("-z",))
        mb.box((x, 0, 1.0 + (TH - 1.0) / 2), (TW, TD, TH - 1.0), st, texel=2.0, skip=("-z", "+z"))
        mb.box((x, 0, TH + 0.15), (TW + 0.3, TD + 0.3, 0.3), sm, texel=1.0)
        W2, D2 = TW + 0.3, TD + 0.3
        for cy in (-D2 / 2 + 0.2, D2 / 2 - 0.2):
            mb.box((x, cy, TH + 0.6), (W2, 0.4, 0.6), st, texel=2.0, skip=("-z",))
            for mx in (-1.45, 0.0, 1.45):
                mb.box((x + mx, cy, TH + 1.3), (0.8, 0.4, 0.8), st, texel=2.0, skip=("-z",))
        for cx in (x - W2 / 2 + 0.2, x + W2 / 2 - 0.2):
            mb.box((cx, 0, TH + 0.6), (0.4, D2 - 0.8, 0.6), st, texel=2.0, skip=("-z",))
            for my in (-1.2, 1.2):
                mb.box((cx, my, TH + 1.3), (0.4, 0.8, 0.8), st, texel=2.0, skip=("-z",))
        mb.box((x, 0, TH + 0.31), (W2 - 0.8, D2 - 0.8, 0.02), sm, texel=1.5)
        for y in (-TD / 2 - 0.005, TD / 2 + 0.005):
            for z in (3.4, 6.0):
                mb.box((x, y, z), (0.15, 0.02, 0.85), dark)
            # Bannières rouges sur les deux faces.
            mb.box((x, y * 1.004 + (0.02 if y > 0 else -0.02), 5.2), (1.1, 0.03, 2.6), m["cloth_red"])
            mb.box((x, y * 1.004 + (0.03 if y > 0 else -0.03), 5.0), (0.36, 0.03, 0.9), m["cloth_cream"])
            mb.tube([(x - 0.7, y + (0.08 if y > 0 else -0.08), 6.55), (x + 0.7, y + (0.08 if y > 0 else -0.08), 6.55)],
                    [0.03, 0.03], 5, m["iron"])

    # Corps central : faces avant/arrière percées d'un arc, intrados, chemin de ronde.
    segs = 12
    arc = [(r * math.cos(math.pi - i / segs * math.pi), SZ + r * math.sin(math.pi - i / segs * math.pi))
           for i in range(segs + 1)]
    for sy in (-1, 1):
        y = sy * DD / 2
        nrm = (0, sy, 0)
        for x0, x1 in ((-PW / 2, -r), (r, PW / 2)):
            pts = [(x0, y, 0), (x1, y, 0), (x1, y, AH), (x0, y, AH)]
            face(mb, pts, nrm, st, planar_uv(pts, Vector((1, 0, 0)), UP, 2.0))
        for (ax, az), (bx, bz) in zip(arc[:-1], arc[1:]):
            pts = [(ax, y, az), (bx, y, bz), (bx, y, AH), (ax, y, AH)]
            face(mb, pts, nrm, st, planar_uv(pts, Vector((1, 0, 0)), UP, 2.0))
        # Claveaux autour de l'arc.
        for i in range(segs + 1):
            ang = math.pi - i / segs * math.pi
            c = Vector((math.cos(ang) * (r + 0.2), sy * (DD / 2 + 0.04), SZ + math.sin(ang) * (r + 0.2)))
            mb.box(c, (0.4, 0.1, 0.46), sm, rot=Matrix.Rotation(-ang, 3, "Y"), texel=0.6)
    for sx in (-1, 1):
        pts = [(sx * r, -DD / 2, 0), (sx * r, DD / 2, 0), (sx * r, DD / 2, SZ), (sx * r, -DD / 2, SZ)]
        face(mb, pts, (-sx, 0, 0), st, planar_uv(pts, Vector((0, 1, 0)), UP, 2.0))
    for (ax, az), (bx, bz) in zip(arc[:-1], arc[1:]):
        mid = Vector(((ax + bx) / 2, 0, (az + bz) / 2 - SZ))
        pts = [(ax, -DD / 2, az), (bx, -DD / 2, bz), (bx, DD / 2, bz), (ax, DD / 2, az)]
        face(mb, pts, -mid, sm, [(0, 0), (0.3, 0), (0.3, DD / 1.5), (0, DD / 1.5)])
    pts = [(-PW / 2, -DD / 2, AH), (PW / 2, -DD / 2, AH), (PW / 2, DD / 2, AH), (-PW / 2, DD / 2, AH)]
    face(mb, pts, (0, 0, 1), sm, planar_uv(pts, Vector((1, 0, 0)), Vector((0, 1, 0)), 1.5))
    for sy in (-1, 1):
        y = sy * (DD / 2 - 0.2)
        mb.box((0, y, AH + 0.3), (PW, 0.4, 0.6), st, texel=2.0, skip=("-z", "+x", "-x"))
        for mx in (-1.3, 0.0, 1.3):
            mb.box((mx, y, AH + 1.0), (0.8, 0.4, 0.8), st, texel=2.0, skip=("-z",))
    # Pavage sous le passage.
    mb.box((0, 0, 0.02), (OW, DD, 0.04), sm, texel=1.0, skip=("-z",))
    # Herse levée (visible dans le haut de l'arc) et ses pointes.
    iron = m["iron"]
    for i in range(7):
        x = -r + 0.25 + i * (OW - 0.5) / 6
        top = SZ + math.sqrt(max(r * r - x * x, 0.0)) - 0.02
        mb.box((x, 0, (3.7 + top) / 2), (0.07, 0.07, top - 3.7), iron, texel=0.5)
        mb.prism((x, 0, 3.52), 0.01, 0.05, 0.18, 4, iron)
    for z in (3.8, 4.25):
        half = math.sqrt(max(r * r - (z - SZ) ** 2, 0.0)) - 0.03 if z > SZ else r - 0.03
        mb.box((0, 0, z), (half * 2, 0.06, 0.07), iron, texel=0.5)
    # Vantaux ouverts contre les piédroits, côté intérieur (+Y).
    for sx in (-1, 1):
        mb.box((sx * (r - 0.09), DD / 2 - 1.05, 1.6), (0.12, 1.85, 3.2), m["planks_old"], texel=1.0)
        for z in (0.7, 2.8):
            mb.box((sx * (r - 0.16), DD / 2 - 1.05, z), (0.03, 1.8, 0.12), iron, texel=0.5)
    mb.build("gatehouse")


# ---------------------------------------------------------------------------
# Téléporteur, étals, puits, clôture
# ---------------------------------------------------------------------------

TELEPORTER_OBELISK_RADIUS = 3.4
TELEPORTER_CRYSTAL_Z = 2.95


def build_teleporter(m):
    """Socle de téléporteur, posé sous un portail de carte : dallage circulaire au ras du sol
    (le cercle animé du portail, PortalVfx, occupe le centre jusqu'à ~1,8 m), bordure de pierre,
    couronne de runes gravées lumineuses, quatre obélisques bas aux diagonales (loin du centre
    pour ne pas masquer la colonne d'énergie) portant chacun un cristal flottant
    (teleporter_crystals, animé côté Godot)."""
    mb = MeshBuilder()
    st, sm, rune, dark = m["castle_stone"], m["stone_smooth"], m["rune_glow"], m["shadow_dark"]
    # Dallage : bordure de grand appareil, disque lisse, gravures sombres + runes lumineuses.
    mb.prism((0, 0, 0), 3.05, 2.98, 0.07, 32, st, texel=1.5)
    mb.prism((0, 0, 0), 2.8, 2.8, 0.085, 32, sm, texel=1.8)
    mb.ring_wall((0, 0, 0.085), 2.72, 2.64, 0.0, 0.012, 64, rune, rune)
    mb.ring_wall((0, 0, 0.085), 2.06, 2.0, 0.0, 0.012, 64, rune, rune)
    mb.ring_wall((0, 0, 0.085), 1.95, 1.9, 0.0, 0.006, 64, dark, dark)
    rng = random.Random(7)
    for k in range(20):
        a = k / 20 * math.tau
        c = Vector((math.cos(a) * 2.35, math.sin(a) * 2.35, 0.09))
        rot = Matrix.Rotation(a, 3, "Z")
        mb.box(c, (0.26, 0.04, 0.012), rune, rot=rot)
        if rng.random() < 0.7:
            mb.box(c + rot @ Vector((0.0, 0.08 * rng.choice((-1, 1)), 0)), (0.04, 0.17, 0.012), rune, rot=rot)
        if rng.random() < 0.5:
            mb.box(c + rot @ Vector((0.09 * rng.choice((-1, 1)), 0.0, 0)), (0.04, 0.2, 0.012), rune,
                   rot=rot @ Matrix.Rotation(0.6, 3, "Z"))
    # Rainures rayonnantes entre la couronne et le cercle central.
    for k in range(8):
        a = (k + 0.5) / 8 * math.tau
        c = Vector((math.cos(a) * 2.35, math.sin(a) * 2.35, 0.088))
        mb.box(c, (0.55, 0.035, 0.006), dark, rot=Matrix.Rotation(a, 3, "Z"))
    R = TELEPORTER_OBELISK_RADIUS
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        rot = Matrix.Rotation(a + math.pi, 3, "Z")  # X local -> vers le centre
        mb.box(c + UP * 0.18, (1.0, 1.0, 0.36), st, rot=rot, texel=1.5)
        mb.box(c + UP * 0.39, (0.84, 0.84, 0.06), sm, rot=rot, texel=1.0)
        mb.prism(c + UP * 0.42, 0.36, 0.24, 1.9, 4, st, texel=1.5, rot_offset=a + math.pi / 4, cap_top=False)
        mb.prism(c + UP * 2.32, 0.24, 0.02, 0.32, 4, sm, texel=0.8, rot_offset=a + math.pi / 4, cap_top=False)
        # Coupelle de fer qui porte le cristal.
        mb.prism(c + UP * 2.62, 0.05, 0.16, 0.08, 6, m["iron"], texel=0.5, cap_top=False)
        inward = Vector((-math.cos(a), -math.sin(a), 0))
        for i, z in enumerate((0.8, 1.15, 1.5, 1.85, 2.15)):
            half_at = 0.36 - (0.36 - 0.24) * (z - 0.42) / 1.9
            p = c + inward * (half_at * math.cos(math.pi / 4) + 0.012) + UP * z
            mb.box(p, (0.012, 0.22 if i % 2 == 0 else 0.1, 0.2 if i % 2 == 0 else 0.06), rune, rot=rot)
    mb.build("teleporter")

    crystals = MeshBuilder()
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        c = Vector((math.cos(a) * R, math.sin(a) * R, TELEPORTER_CRYSTAL_Z - 0.2))
        crystals.prism(c, 0.001, 0.15, 0.2, 5, rune, rot_offset=a, cap_top=True)
        crystals.prism(c + UP * 0.2, 0.15, 0.001, 0.32, 5, rune, rot_offset=a, cap_top=False)
    crystals.build("teleporter_crystals")


def build_stall(m, name, cloth):
    mb = MeshBuilder()
    wood, planks = m["wood_dark"], m["planks_old"]
    W, D = 3.0, 1.8
    for sx in (-1, 1):
        for sy, h in ((-1, 2.3), (1, 2.7)):
            mb.box((sx * (W / 2 - 0.08), sy * (D / 2 - 0.08), h / 2), (0.12, 0.12, h), wood, texel=0.8)
    mb.box((0, -D / 2 + 0.45, 0.9), (W - 0.1, 0.8, 0.08), planks, texel=1.0)
    mb.box((0, -D / 2 + 0.08, 0.5), (W - 0.1, 0.05, 0.8), planks, texel=1.0)
    slope = math.atan2(0.4, D)
    mb.box((0, 0, 2.55), (W + 0.3, D + 0.5, 0.04), m[cloth], rot=Matrix.Rotation(slope, 3, "X"))
    strip = (W + 0.3) / 6
    for i in range(6):
        mb.box((-W / 2 - 0.15 + (i + 0.5) * strip, -D / 2 - 0.25, 2.2), (strip - 0.03, 0.03, 0.22),
               m[cloth if i % 2 == 0 else "cloth_cream"])
    rng = random.Random(len(name))
    for k in range(4):
        x = -1.1 + k * 0.72
        mb.box((x, -D / 2 + 0.45, 1.05), (0.5, 0.4, 0.22), m["planks_fresh"], texel=0.6)
        for j in range(5):
            col = rng.choice(("cloth_red", "cloth_cream", "wood_sign"))
            mb.box((x + rng.uniform(-0.15, 0.15), -D / 2 + 0.45 + rng.uniform(-0.1, 0.1), 1.2),
                   (0.12, 0.12, 0.1), m[col])
    mb.box((0.8, D / 2 - 0.4, 0.35), (0.7, 0.7, 0.7), m["planks_fresh"], texel=0.7)
    mb.build(name)


def build_well(m):
    mb = MeshBuilder()
    mb.ring_wall((0, 0, 0), 0.95, 0.72, 0.0, 0.8, 12, m["rubble_stone"], m["stone_smooth"], texel=1.5)
    mb.disc((0, 0, 0.35), 0.73, 12, m["water"])
    for sx in (-1, 1):
        mb.box((sx * 0.85, 0, 1.2), (0.14, 0.14, 2.4), m["wood_dark"], texel=0.8)
    mb.tube([(-0.9, 0, 1.75), (0.9, 0, 1.75)], [0.06, 0.06], 8, m["wood_dark"])
    mb.tube([(0.9, 0, 1.75), (1.15, 0, 1.75), (1.15, 0, 1.5)], [0.02, 0.02, 0.02], 5, m["iron"])
    mb.tube([(0, 0, 1.72), (0, 0, 1.1)], [0.01, 0.01], 4, m["wood_sign"])
    mb.tube([(0, 0, 0.85), (0, 0, 1.1)], [0.13, 0.15], 8, m["planks_old"], cap_bottom=True)
    gable_roof(mb, m, 1.9, 1.6, 2.35, pitch=math.radians(35), overhang=0.25, gable_over=0.15)
    mb.build("well")


def build_fence(m):
    mb = MeshBuilder()
    wood = m["wood_dark"]
    for x in (-1.0, 1.0):
        mb.box((x, 0, 0.55), (0.12, 0.12, 1.1), wood, texel=0.8)
        mb.prism((x, 0, 1.1), 0.085, 0.01, 0.1, 4, wood, rot_offset=math.pi / 4)
    for z in (0.4, 0.85):
        mb.box((0, 0.07, z), (2.1, 0.04, 0.12), m["planks_old"], texel=1.2)
    mb.build("fence")


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export(filename, names):
    bpy.ops.object.select_all(action="DESELECT")
    for n in names:
        bpy.data.objects[n].select_set(True)
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_normals=True, export_texcoords=True,
                              export_materials="EXPORT", export_image_format="NONE")
    print("écrit", path, len(names), "objets")


def main():
    os.makedirs(OUT, exist_ok=True)
    be.clear_scene()
    m = vmats()
    build_wall(m)
    build_towers(m)
    build_gatehouse(m)
    build_houses(m)
    build_teleporter(m)
    build_stall(m, "market_stall_red", "cloth_red")
    build_stall(m, "market_stall_blue", "cloth_blue")
    build_well(m)
    build_fence(m)
    for name in ("rampart_wall", "rampart_tower", "rampart_tower_roofed", "gatehouse", "house_small",
                 "house_medium", "house_large", "inn", "forge", "market_stall_red", "market_stall_blue", "well",
                 "fence"):
        export(f"{name}.glb", [name])
    export("teleporter.glb", ["teleporter", "teleporter_crystals"])


main()
