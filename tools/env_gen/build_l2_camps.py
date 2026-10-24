"""Générateur des props de camp et de lieux d'exécution « façon Lineage 2 » (camp abandonné
des Ol Mahum au lac de Fellmere, terrain d'exécution, château de Dion, zone neutre),
exportés en glTF binaire pour Godot. Réutilise les outils de maillage et les matériaux de
build_environment.py / build_village.py / build_l2_structures.py.

Usage (depuis la racine du projet, après fetch_textures.py) :
    blender -b --python tools/env_gen/build_l2_camps.py

Sortie : assets/environment/models/l2/ (un modèle par fichier, assemblé dans
scenes/maps/props/<Nom>.tscn)
    tent.glb                tente de peaux en A (3 x 4 m, 2,4 m), ouverture côté -Y (rabats
                            relevés), perches croisées, pierres de lestage.
    tent_large.glb          pavillon du chef (ellipse 6 x 7 m, mât central à 5,8 m et flamme),
                            porte et auvent côté -Y, lambrequin rouge, étendard et totem.
    palisade.glb            tronçon de palissade de 4 m (X), pieux appointés ~3 m, 0,6 m
                            d'épaisseur ; mis bout à bout (et étiré) le long d'une enceinte.
    palisade_gate.glb       porte de palissade : passage libre de 4 m (|x| < 2) traversé selon
                            Y, gros poteaux, linteau à crâne cornu, vantaux ouverts côté +Y,
                            tronçons de palissade jusqu'à |x| = 3,5.
    campfire.glb            feu de camp : cercle de pierres, bûches, braises ; campfire_flames
                            = langues de feu (objet séparé, émissif).
    watch_tower_wood.glb    tour de guet sur quatre pieds (plate-forme à 6 m, toit de peaux),
                            échelle côté -Y.
    gallows.glb             gibet : estrade, deux montants, poutre, trois nœuds coulants,
                            trappe ; marches côté +X.
    scaffold.glb            échafaud 6 x 6 m (plancher à 1,5 m) : billot et hache, guillotine,
                            braseros d'angle, tentures ; marches côté -Y.
    gravestone.glb          stèle cintrée usée (0,6 x 0,3 x 1 m) ; gravestone_cross.glb croix
                            de pierre à anneau (1,4 m).
    cage.glb                cage de prisonnier (2 x 2 x 2,2 m), barreaux de fer, porte -Y.
    weapon_rack.glb         râtelier de lances (2 m selon X), armes appuyées côté -Y.

Conventions : identiques à build_environment.py (Blender Z haut, +Y Blender = -Z Godot,
façade/porte côté -Y Blender = +Z Godot, 1 case = 1 m, aucune image embarquée : matériaux
remplacés par nom côté Godot, voir scenes/maps/common/EnvMaterials.gd). Nouveaux noms de
matériaux : log_bark (écorce des rondins, sans balancement), cloth_hide / cloth_hide_dark
(peaux tendues), rope (cordages). Toiles fines : polygones double face (face intérieure en
cloth_hide_dark, fausse ombre).
"""

import math
import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True  # pas de __pycache__ dans tools/env_gen

from mathutils import Matrix, Vector  # noqa: E402

import build_environment as be  # noqa: E402
import build_l2_structures as bl  # noqa: E402
from build_environment import UP, MeshBuilder  # noqa: E402
from build_l2_structures import TAU, Wall, banner, blob, moss_patch, wbox  # noqa: E402
from build_village import face  # noqa: E402


# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------

def cmats():
    m = bl.lmats()
    m.update({
        # Écorce des rondins (pas de préfixe bark_ : immobile au vent côté Godot).
        "log_bark": be.pbr("log_bark", "Bark012"),
        "cloth_hide": be.material("cloth_hide", base=(0.62, 0.45, 0.3)),
        "cloth_hide_dark": be.material("cloth_hide_dark", base=(0.38, 0.27, 0.18)),
        "rope": be.material("rope", base=(0.55, 0.45, 0.3)),
    })
    return m


# ---------------------------------------------------------------------------
# Outils géométriques
# ---------------------------------------------------------------------------

def log(mb, a, b, r, mat, sides=6, cap=None, r_end=None):
    """Rondin (tube droit) de a à b ; bouts fermés par `cap` (cernes) si donné."""
    mb.tube([a, b], [r, r if r_end is None else r_end], sides, mat, cap_top=cap is not None,
            cap_bottom=cap is not None, cap_mat=cap)


def stake(mb, m, base, top, r, tip=0.45, sides=6):
    """Pieu appointé : fût d'écorce de `base` à `top`, pointe taillée (bois clair) au-dessus."""
    base, top = Vector(base), Vector(top)
    d = (top - base).normalized()
    mb.tube([base, top], [r, r * 0.95], sides, m["log_bark"])
    mb.tube([top, top + d * tip], [r * 0.95, 0.01], sides, m["planks_fresh"])


def rope(mb, m, pts, r=0.015, sides=4):
    mb.tube(pts, [r] * len(pts), sides, m["rope"])


def cloth(mb, pts, normal, outer, inner, texel=2.0, inset=0.006):
    """Polygone de toile double face : `outer` vers `normal`, `inner` (sombre) de l'autre côté."""
    pts = [Vector(p) for p in pts]
    n = Vector(normal).normalized()
    u_ax = UP.cross(n).normalized() if abs(n.z) < 0.95 else Vector((1, 0, 0))
    v_ax = n.cross(u_ax).normalized()
    uv = [(p.dot(u_ax) / texel, p.dot(v_ax) / texel) for p in pts]
    face(mb, pts, n, outer, uv)
    face(mb, [p - n * inset for p in pts], -n, inner, uv)


def cloth_grid(mb, fn, nu, nv, outer, inner, size=(1.0, 1.0), texel=2.0, inset=0.006):
    """Toile double face paramétrée : fn(u, v) -> point, (dP/du x dP/dv) vers l'extérieur."""
    grid = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            a, b, c, d = grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]
            n = (b - a).cross(d - a).normalized()
            uv = [(x * size[0] / nu / texel, y * size[1] / nv / texel)
                  for x, y in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            ia = [mb.add_vert(p) for p in (a, b, c, d)]
            mb.add_face(ia, uv, outer)
            ib = [mb.add_vert(p - n * inset) for p in (d, c, b, a)]
            mb.add_face(ib, list(reversed(uv)), inner)


def slab(mb, pts, y0, y1, mat, texel=1.0):
    """Dalle : profil convexe (x, z) extrudé selon Y de y0 (face avant -Y) à y1."""
    cx = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)
    face(mb, [(x, y0, z) for x, z in pts], (0, -1, 0), mat, [(x / texel, z / texel) for x, z in pts])
    face(mb, [(x, y1, z) for x, z in pts], (0, 1, 0), mat, [(-x / texel, z / texel) for x, z in pts])
    run = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        seg = math.hypot(dx, dz)
        n = Vector((dz, 0, -dx))
        mid = Vector(((a[0] + b[0]) / 2 - cx, 0, (a[1] + b[1]) / 2 - cz))
        if n.dot(mid) < 0:
            n = -n
        quad = [(a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1])]
        d = (y1 - y0) / texel
        face(mb, quad, n, mat, [(run / texel, 0), ((run + seg) / texel, 0), ((run + seg) / texel, d), (run / texel, d)])
        run += seg


def stone(mb, m, center, size, rng, mat="rock"):
    """Pierre basse irrégulière (ellipsoïde aplati bosselé, peu de faces)."""
    k = [rng.uniform(0.85, 1.15) for _ in range(6)]
    blob(mb, center, size, m[mat], segs=6, rings=4,
         deform=lambda d, p: Vector(p) + d * 0.04 * k[int((math.atan2(d.y, d.x) + math.pi) / TAU * 6) % 6],
         texel=0.8)


def horned_skull(mb, m, c, scale=1.0, facing=-1):
    """Crâne cornu (os pâle, orbites sombres) regardant vers `facing` * Y."""
    c = Vector(c)
    s = scale
    blob(mb, c, (0.2 * s, 0.22 * s, 0.2 * s), m["bone"], segs=8, rings=6, texel=0.5)
    blob(mb, c + Vector((0, facing * 0.17 * s, -0.08 * s)), (0.12 * s, 0.12 * s, 0.1 * s), m["bone"], segs=6,
         rings=4, texel=0.5)
    for sx in (-1, 1):
        mb.box(c + Vector((sx * 0.08 * s, facing * 0.19 * s, 0.02 * s)), (0.08 * s, 0.02 * s, 0.07 * s),
               m["shadow_dark"])
        p0 = c + Vector((sx * 0.16 * s, 0, 0.1 * s))
        mb.tube([p0, p0 + Vector((sx * 0.25 * s, facing * 0.05 * s, 0.12 * s)),
                 p0 + Vector((sx * 0.38 * s, facing * 0.2 * s, 0.32 * s))],
                [0.06 * s, 0.04 * s, 0.008], 6, m["bone"])


def torch(mb, m, base, d_out):
    """Torche murale : support de fer, manche, tête de flamme émissive."""
    b = Vector(base)
    o = Vector(d_out)
    mb.box(b + o * 0.08, (0.08, 0.08, 0.08), m["iron"])
    mb.tube([b + o * 0.16 - UP * 0.15, b + o * 0.22 + UP * 0.35], [0.03, 0.035], 5, m["wood_dark"])
    tip = b + o * 0.23 + UP * 0.38
    mb.tube([tip, tip + UP * 0.12], [0.05, 0.055], 5, m["rope"])
    mb.tube([tip + UP * 0.12, tip + UP * 0.22, tip + UP * 0.38], [0.07, 0.05, 0.0], 5, m["forge_fire"])


# ---------------------------------------------------------------------------
# Tentes
# ---------------------------------------------------------------------------

def build_tent(m):
    """Tente de peaux en A : faîtage selon Y (4 m), pans jusqu'au sol (3 m de large), ouverture
    -Y aux rabats relevés, perches croisées devant et derrière, piquets et pierres de lestage."""
    rng = random.Random(3)
    mb = MeshBuilder()
    hide, dark = m["cloth_hide"], m["cloth_hide_dark"]
    W, D, H = 1.45, 2.0, 2.4

    def panel(s):
        def fn(u, v):
            y = D - 2 * D * u if s > 0 else -D + 2 * D * u
            a = v
            sag = 0.09 * math.sin(math.pi * a) * (0.5 + 0.5 * math.sin(math.pi * (y + D) / (2 * D)))
            x = s * (W * a - sag * 0.8)
            z = H * (1 - a) - sag * 0.4 + 0.02
            return (x, y, z)
        return fn

    for s in (-1, 1):
        cloth_grid(mb, panel(s), 4, 3, hide, dark, size=(2 * D, 2.8), texel=1.6)
    # Pignon arrière fermé (+Y), sol intérieur sombre.
    cloth(mb, [(-W, D - 0.02, 0.02), (W, D - 0.02, 0.02), (0, D - 0.02, H)], (0, 1, 0), hide, dark, texel=1.6)
    mb.box((0, 0.1, 0.012), (2 * W - 0.4, 2 * D - 0.4, 0.02), dark)
    # Rabats de l'entrée, rabattus contre l'extérieur des pans (face intérieure, sombre, visible)
    # et noués par une corde.
    for s in (-1, 1):
        nrm = Vector((s * H, 0, W)).normalized()
        ridge = Vector((0, -D - 0.02, H + 0.02)) + nrm * 0.05
        foot = Vector((s * (W + 0.02), -D - 0.02, 0.04)) + nrm * 0.05
        tip = Vector((s * W * 0.5, -D + 0.85, H * 0.5)) + nrm * 0.06
        cloth(mb, [ridge, foot, tip], nrm, dark, hide, texel=1.6)
        rope(mb, m, [tip + nrm * 0.01 + Vector((0, -0.1, 0.1)), tip + nrm * 0.01 + Vector((0, 0.1, -0.1))], r=0.025)
    # Rapiéçages sur les pans.
    for s, y, z, w, h in ((1, 0.3, 1.1, 0.7, 0.5), (1, 1.2, 0.5, 0.5, 0.4), (-1, 0.3, 1.4, 0.6, 0.45)):
        a = 1 - z / H
        nrm = Vector((s * H, 0, W)).normalized()
        x = s * W * a + nrm.x * 0.05
        z += nrm.z * 0.05
        u_ax = Vector((0, 1, 0))
        v_ax = nrm.cross(u_ax) * -s
        c = Vector((x, y, z))
        pts = [c - u_ax * w / 2 - v_ax * h / 2, c + u_ax * w / 2 - v_ax * h / 2, c + u_ax * w / 2 + v_ax * h / 2,
               c - u_ax * w / 2 + v_ax * h / 2]
        face(mb, pts, nrm, dark, [(0, 0), (1, 0), (1, 1), (0, 1)])
    # Faîtière et perches croisées.
    log(mb, (0, -D - 0.3, H + 0.06), (0, D + 0.3, H + 0.06), 0.055, m["wood_dark"], cap=m["wood_rings"])
    for y in (-D - 0.04, D + 0.04):
        for s in (-1, 1):
            g = Vector((s * (W + 0.05), y, 0))
            r_ = Vector((0, y, H + 0.06))
            log(mb, g, g + (r_ - g) * 1.22, 0.045, m["wood_dark"], sides=5)
        rope(mb, m, [(-0.08, y, H + 0.04), (0.08, y, H + 0.12), (0.08, y, H)], r=0.02)
    # Hauban arrière, piquets et pierres de lestage le long des pans.
    rope(mb, m, [(0, D + 0.3, H + 0.06), (0, D + 0.95, 0.05)])
    mb.box((0, D + 0.95, 0.12), (0.06, 0.06, 0.3), m["wood_dark"])
    for s in (-1, 1):
        for y in (-1.3, 0.0, 1.3):
            stone(mb, m, (s * (W + 0.12), y + rng.uniform(-0.2, 0.2), 0.08),
                  (rng.uniform(0.14, 0.2), rng.uniform(0.12, 0.17), 0.12), rng)
    # Fourrure étalée devant l'entrée.
    pts = [(0.75 * math.cos(a) * rng.uniform(0.8, 1.0), -D - 0.45 + 0.4 * math.sin(a) * rng.uniform(0.8, 1.0), 0.015)
           for a in (i / 9 * TAU for i in range(9))]
    face(mb, pts, (0, 0, 1), m["cloth_hide_dark"], [(p[0], p[1]) for p in pts])
    return mb.build("tent")


def build_tent_large(m):
    """Pavillon du chef : paroi elliptique (6 x 6,8 m) de 1,7 m, toit conique à rayures vers le
    mât central (5,8 m, flamme rouge), lambrequin festonné, porte et auvent côté -Y, haubans,
    étendard à droite de l'entrée et totem au crâne cornu à gauche."""
    rng = random.Random(9)
    mb = MeshBuilder()
    hide, dark, red = m["cloth_hide"], m["cloth_hide_dark"], m["cloth_red"]
    RX, RY, HW, HR, N = 2.9, 3.3, 1.7, 4.0, 16

    def ell(a, k=1.0):
        return Vector((math.cos(a) * RX * k, math.sin(a) * RY * k, 0))

    angles = [i / N * TAU + math.pi / N for i in range(N + 1)]
    # Paroi (évasée au pied) et toit en deux anneaux (léger creux entre les perches).
    for i in range(N):
        a0, a1 = angles[i], angles[i + 1]
        quad = [ell(a0, 1.05), ell(a1, 1.05), ell(a1) + UP * HW, ell(a0) + UP * HW]
        mid = (a0 + a1) / 2
        nrm = Vector((math.cos(mid) / RX, math.sin(mid) / RY, 0.05)).normalized()
        cloth(mb, quad, nrm, hide, dark, texel=1.6)
        mat = hide if i % 2 == 0 else dark
        e0, e1 = ell(a0, 1.1) + UP * (HW - 0.15), ell(a1, 1.1) + UP * (HW - 0.15)
        m0, m1 = ell(a0, 0.55) + UP * (HW + (HR - HW) * 0.5 - 0.08), ell(a1, 0.55) + UP * (HW + (HR - HW) * 0.5 - 0.08)
        apex = Vector((0, 0, HR))
        for pts in ([e0, e1, m1, m0], [m0, m1, apex]):
            n = (pts[1] - pts[0]).cross(pts[-1] - pts[0]).normalized()
            cloth(mb, pts, n, mat, dark, texel=1.6)
        # Lambrequin festonné (un feston par pan) et perche de paroi.
        hang = [e0 + UP * 0.01, e1 + UP * 0.01, (e0 + e1) / 2 - UP * 0.35]
        n = Vector((math.cos(mid), math.sin(mid), 0))
        cloth(mb, [e0 - UP * 0.02, e1 - UP * 0.02, e1 + UP * 0.08, e0 + UP * 0.08], n, red, red)
        cloth(mb, [e0, e1, hang[2]], n, red, red)
        log(mb, ell(a0, 1.06) - UP * 0.05, ell(a0, 1.1) + UP * (HW - 0.12), 0.05, m["wood_dark"], sides=5)
    # Mât central et flamme.
    log(mb, (0, 0, HR - 0.4), (0, 0, 5.8), 0.09, m["wood_dark"], sides=6)
    mb.prism((0, 0, 5.8), 0.11, 0.0, 0.25, 6, m["iron"])
    rope(mb, m, [(0, 0, HR + 0.05), (0, 0, HR + 0.2)], r=0.12, sides=6)
    pts = []
    for k in range(4):
        x = 0.1 + k * 0.45
        w = 0.32 * (1 - k / 3.4)
        z = 5.55 + 0.06 * math.sin(k * 1.7)
        pts.append(((x, 0.06 * math.sin(k * 2.1), z + w), (x, 0.06 * math.sin(k * 2.1), z - w)))
    for k in range(3):
        a, b = pts[k], pts[k + 1]
        cloth(mb, [a[1], b[1], b[0], a[0]], (0, -1, 0), red, red)
    # Porte (-Y) : ouverture sombre, rabats noués, auvent sur deux perches.
    yd = -RY * 1.0
    face(mb, [(-0.7, yd - 0.03, 0.0), (0.7, yd - 0.03, 0.0), (0.6, yd - 0.06, 1.6), (-0.6, yd - 0.06, 1.6)],
         (0, -1, 0), m["shadow_dark"])
    for s in (-1, 1):
        cloth(mb, [(s * 0.7, yd - 0.08, 0.0), (s * 1.1, yd - 0.04, 0.0), (s * 0.95, yd - 0.06, 1.62),
                   (s * 0.6, yd - 0.09, 1.62)], (0, -1, 0), red, dark)
        rope(mb, m, [(s * 0.62, yd - 0.12, 0.85), (s * 1.0, yd - 0.1, 0.8)], r=0.025)
    yf = yd - 1.4
    awn = [(-1.2, yd - 0.05, 2.05), (1.2, yd - 0.05, 2.05), (1.2, yf, 2.25), (-1.2, yf, 2.25)]
    cloth(mb, awn, (0, -0.25, 1), hide, dark)
    cloth(mb, [(-1.2, yf, 2.27), (1.2, yf, 2.27), (1.2, yf, 2.0), (-1.2, yf, 2.0)], (0, -1, 0), red, red)
    for s in (-1, 1):
        log(mb, (s * 1.2, yf, 0), (s * 1.2, yf, 2.45), 0.05, m["wood_dark"], sides=5)
        rope(mb, m, [(s * 1.2, yf, 2.4), (s * 1.75, yf - 0.6, 0.02)])
        mb.box((s * 1.75, yf - 0.6, 0.1), (0.06, 0.06, 0.25), m["wood_dark"])
    # Haubans du toit.
    for k in range(6):
        a = (k + 0.5) / 6 * TAU
        if abs(a - 1.5 * math.pi) < 0.6:
            continue
        p0 = ell(a, 1.1) + UP * (HW - 0.1)
        p1 = ell(a, 1.33)
        rope(mb, m, [p0, p1 + UP * 0.02])
        mb.box(p1 + UP * 0.1, (0.06, 0.06, 0.25), m["wood_dark"])
    # Étendard (droite de l'entrée) : hampe, traverse, bannière à pointe en V.
    sx, sy = 2.45, yd - 0.15
    log(mb, (sx, sy, 0), (sx, sy, 4.2), 0.06, m["wood_dark"], sides=6)
    mb.prism((sx, sy, 4.2), 0.07, 0.0, 0.3, 4, m["iron"])
    log(mb, (sx - 0.55, sy - 0.04, 3.85), (sx + 0.55, sy - 0.04, 3.85), 0.03, m["wood_dark"], sides=5)
    st = Wall(mb, (sx, sy - 0.07, 0), (0, -1, 0))
    banner(st, m, 0.0, 3.85, 1.9, "cloth_red", trim="shadow_dark", width=1.0, d=0.0)
    # Totem (gauche de l'entrée) : poteau, crâne cornu, plumes de peau.
    tx, ty = -1.85, yd - 0.55
    log(mb, (tx, ty, 0), (tx, ty, 2.3), 0.08, m["log_bark"], sides=6, cap=m["wood_rings"])
    horned_skull(mb, m, (tx, ty - 0.05, 2.45), scale=1.1)
    for k in range(3):
        a = k * 2.1
        rope(mb, m, [(tx + 0.09 * math.cos(a), ty + 0.09 * math.sin(a), 2.0),
                     (tx + 0.14 * math.cos(a), ty + 0.14 * math.sin(a), 1.4)], r=0.03)
    # Pierres et coffre devant.
    for k in range(5):
        a = rng.uniform(0, TAU)
        if abs(a - 1.5 * math.pi) < 0.7:
            a += 1.4
        stone(mb, m, ell(a, 1.16) + UP * 0.06, (0.2, 0.16, 0.12), rng)
    return mb.build("tent_large")


# ---------------------------------------------------------------------------
# Palissade, porte, tour de guet
# ---------------------------------------------------------------------------

def palisade_run(mb, m, x0, x1, rng, h=(2.75, 3.2), r=(0.15, 0.18)):
    """Rangée de pieux jointifs de x0 à x1 (selon X), centrée sur y = 0."""
    count = max(1, round((x1 - x0) / 0.34))
    step = (x1 - x0) / count
    for i in range(count):
        x = x0 + (i + 0.5) * step
        rr = min(rng.uniform(*r), step * 0.55)
        hh = rng.uniform(*h)
        lean = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.04, 0.04), 0))
        stake(mb, m, (x, rng.uniform(-0.03, 0.03), -0.1), Vector((x, 0, hh - 0.4)) + lean * hh, rr, tip=0.4 + 0.1 * rng.random())


def build_palisade(m):
    """Tronçon de 4 m selon X (raccords exacts à x = ±2) : 12 pieux appointés, deux lisses
    clouées (une de chaque côté), quelques liens de corde."""
    rng = random.Random(17)
    mb = MeshBuilder()
    palisade_run(mb, m, -2.0, 2.0, rng)
    for y, z in ((0.2, 0.8), (-0.2, 2.1)):
        mb.box((0, y, z), (4.0, 0.1, 0.18), m["wood_dark"], texel=1.0)
    for x in (-1.2, 0.4):
        rope(mb, m, [(x, -0.22, 2.0), (x, -0.22, 2.2)], r=0.03, sides=5)
    return mb.build("palisade")


def build_palisade_gate(m):
    """Porte de palissade (7 m selon X) : passage libre |x| < 2 traversé selon Y, poteaux de
    4,4 m (r 0,26) à x = ±2,25, linteau double et crâne cornu, bannières côté -Y, torches,
    vantaux de rondins ouverts vers +Y, tronçons de palissade de 2,5 à 3,5 m de chaque côté."""
    rng = random.Random(23)
    mb = MeshBuilder()
    for s in (-1, 1):
        palisade_run(mb, m, s * 2.5 if s > 0 else -3.5, 3.5 if s > 0 else -2.5, rng)
        mb.box((s * 3.0, 0.2, 0.8), (1.0, 0.1, 0.18), m["wood_dark"])
        mb.box((s * 3.0, -0.2, 2.1), (1.0, 0.1, 0.18), m["wood_dark"])
        stake(mb, m, (s * 2.25, 0, -0.1), (s * 2.25, 0, 4.2), 0.26, tip=0.5, sides=8)
        torch(mb, m, (s * 2.25, -0.26, 2.3), (0, -1, 0))
        # Vantail ouvert (charnière à x = ±1.95), plaqué le long du passage côté +Y.
        for k in range(5):
            y = 0.25 + k * 0.38
            stake(mb, m, (s * 1.88, y, 0.05), (s * 1.88, y, 2.75 - 0.05 * (k % 2)), 0.17, tip=0.3)
        for z in (0.6, 2.1):
            mb.box((s * 1.72, 1.05, z), (0.08, 1.95, 0.16), m["wood_dark"])
        mb.box((s * 1.72, 1.05, 1.35), (0.08, 2.1, 0.12), m["wood_dark"],
               rot=Matrix.Rotation(s * 0.62, 3, "X"))
    log(mb, (-2.75, 0, 3.75), (2.75, 0, 3.75), 0.2, m["log_bark"], sides=8, cap=m["wood_rings"])
    log(mb, (-2.6, 0.02, 3.3), (2.6, 0.02, 3.3), 0.14, m["log_bark"], sides=6, cap=m["wood_rings"])
    for s in (-1, 1):
        rope(mb, m, [(s * 2.25 - 0.27, -0.27, 3.6), (s * 2.25 + 0.27, -0.27, 3.9)], r=0.035, sides=5)
    horned_skull(mb, m, (0, -0.3, 3.95), scale=1.6)
    for s in (-1, 1):
        wall = Wall(mb, (0, -0.24, 0), (0, -1, 0))
        banner(wall, m, s * 1.15, 3.6, 1.45, "cloth_red", trim="shadow_dark", width=0.85, d=0.0)
    return mb.build("palisade_gate")


def build_watch_tower(m):
    """Tour de guet : quatre pieds inclinés (3 m au pied), croisillons sur deux niveaux,
    plate-forme à 6 m bordée de planches, toit de peaux en pyramide et flamme, échelle -Y."""
    mb = MeshBuilder()
    wood, bark = m["wood_dark"], m["log_bark"]
    B, Tp, ZT, ZP = 1.45, 1.1, 8.0, 6.0

    def leg(sx, sy, z):
        k = z / ZT
        return Vector((sx * (B + (Tp - B) * k), sy * (B + (Tp - B) * k), z))

    for sx in (-1, 1):
        for sy in (-1, 1):
            log(mb, leg(sx, sy, -0.1), leg(sx, sy, ZT), 0.15, bark, sides=7, cap=m["wood_rings"])
    for (ax, ay), (bx, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
        for z0, z1 in ((0.5, 3.2), (3.2, 5.75)):
            log(mb, leg(ax, ay, z0), leg(bx, by, z1), 0.07, wood, sides=5)
            log(mb, leg(bx, by, z0), leg(ax, ay, z1), 0.07, wood, sides=5)
        for z in (0.5, 3.2, 5.8):
            log(mb, leg(ax, ay, z), leg(bx, by, z), 0.08, wood, sides=5)
    # Plate-forme, poutres, garde-corps de planches (ouvert au-dessus de l'échelle).
    P = 1.65
    mb.box((0, 0, ZP + 0.05), (2 * P, 2 * P, 0.14), m["planks_old"], texel=1.2)
    for s in (-1, 1):
        mb.box((0, s * 1.1, ZP - 0.1), (2 * P + 0.2, 0.16, 0.18), wood)
        mb.box((s * 1.1, 0, ZP - 0.1), (0.16, 2 * P + 0.2, 0.18), wood)
    wbox(mb, (0, P - 0.04, ZP + 0.6), (2 * P, 0.08, 0.95), m["planks_old"], texel=1.2)
    for s in (-1, 1):
        wbox(mb, (s * (P - 0.04), 0, ZP + 0.6), (0.08, 2 * P, 0.95), m["planks_old"], texel=1.2)
    for x0, x1 in ((-P, -0.45), (0.45, P)):
        wbox(mb, ((x0 + x1) / 2, -(P - 0.04), ZP + 0.6), (x1 - x0, 0.08, 0.95), m["planks_old"], texel=1.2)
    for (ax, ay), (bx, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
        a, b = Vector((ax * P, ay * P, ZP + 1.12)), Vector((bx * P, by * P, ZP + 1.12))
        log(mb, a, b, 0.06, wood, sides=5)
    # Bannière accrochée au garde-corps avant.
    front = Wall(mb, (0, -P - 0.05, 0), (0, -1, 0))
    banner(front, m, -1.0, ZP + 1.0, 2.0, "cloth_red", trim="shadow_dark", width=0.8, d=0.0)
    # Toit pyramidal de peaux, flamme au sommet.
    R_, ZA = 2.0, ZT + 1.5
    corners = [Vector((sx * R_, sy * R_, ZT - 0.15)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    apex = Vector((0, 0, ZA))
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        n = (b - a).cross(apex - a).normalized()
        cloth(mb, [a, b, apex], n, m["cloth_hide"] if i % 2 == 0 else m["cloth_hide_dark"], m["cloth_hide_dark"])
        log(mb, a, apex, 0.05, wood, sides=4)
    log(mb, (0, 0, ZA - 0.3), (0, 0, ZA + 1.0), 0.05, wood, sides=5)
    cloth(mb, [(0.03, 0, ZA + 0.95), (0.03, 0, ZA + 0.6), (0.85, 0.05, ZA + 0.8)], (0, -1, 0), m["cloth_red"],
          m["cloth_red"])
    # Échelle (-Y) du sol au bord de la plate-forme.
    y0, y1 = -2.15, -P - 0.02
    for s in (-1, 1):
        log(mb, (s * 0.28, y0, 0), (s * 0.28, y1, ZP + 0.9), 0.045, wood, sides=5)
    n_rungs = 17
    for k in range(1, n_rungs + 1):
        f = k / (n_rungs + 1)
        y = y0 + (y1 - y0) * f
        z = (ZP + 0.9) * f
        log(mb, (-0.3, y, z), (0.3, y, z), 0.025, m["planks_fresh"], sides=4)
    return mb.build("watch_tower_wood")


# ---------------------------------------------------------------------------
# Feu de camp
# ---------------------------------------------------------------------------

def build_campfire(m):
    """Feu de camp (Ø 1,6 m) : cercle de 10 pierres, lit de cendres, bûches en étoile aux bouts
    charbonneux, braises émissives, broche sur deux fourches ; campfire_flames à part."""
    rng = random.Random(5)
    mb = MeshBuilder()
    for k in range(10):
        a = k / 10 * TAU + rng.uniform(-0.1, 0.1)
        stone(mb, m, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.07),
              (rng.uniform(0.15, 0.19), rng.uniform(0.12, 0.15), rng.uniform(0.1, 0.13)), rng)
    mb.disc((0, 0, 0.012), 0.52, 10, m["shadow_dark"])
    for k in range(5):
        a = k / 5 * TAU + 0.3
        out = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.06))
        mid = Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, 0.2))
        inner = Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0.3))
        log(mb, out, mid, 0.065, m["log_bark"], sides=6, cap=m["wood_rings"])
        log(mb, mid, inner, 0.06, m["shadow_dark"], sides=6)
    for k in range(9):
        a = rng.uniform(0, TAU)
        d = rng.uniform(0.05, 0.32)
        mb.box((math.cos(a) * d, math.sin(a) * d, 0.035), (0.09, 0.07, 0.05), m["forge_fire"],
               rot=Matrix.Rotation(rng.uniform(0, 3), 3, "Z"))
    mb.disc((0, 0, 0.02), 0.26, 8, m["forge_fire"])
    for s in (-1, 1):
        x = s * 0.78
        log(mb, (x, 0, 0), (x, 0, 0.75), 0.03, m["wood_dark"], sides=5)
        for d in (-1, 1):
            log(mb, (x, 0, 0.7), (x, d * 0.1, 0.9), 0.022, m["wood_dark"], sides=4)
    log(mb, (-0.9, 0, 0.8), (0.9, 0, 0.8), 0.022, m["wood_sign"], sides=5)
    blob(mb, (0.05, 0, 0.8), (0.24, 0.12, 0.11), m["wood_sign"], segs=8, rings=5, texel=0.4)
    mb.build("campfire")

    fl = MeshBuilder()
    for k, (h, r, ox) in enumerate(((0.75, 0.17, 0.0), (0.5, 0.13, 0.12), (0.45, 0.12, -0.1))):
        a = k * 2.2
        c = Vector((math.cos(a) * ox, math.sin(a) * abs(ox), 0.15))
        bend = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 0))
        fl.tube([c, c + UP * h * 0.4 + bend * 0.3, c + UP * h * 0.75 + bend, c + UP * h + bend * 1.4],
                [r, r * 0.8, r * 0.4, 0.0], 5, m["forge_fire"], twist=0.4)
    fl.build("campfire_flames")


# ---------------------------------------------------------------------------
# Gibet, échafaud
# ---------------------------------------------------------------------------

def noose(mb, m, x, y, z_top, drop=1.4):
    rope(mb, m, [(x, y, z_top), (x, y, z_top - drop)], r=0.022, sides=5)
    mb.tube([(x, y, z_top - drop - 0.02), (x, y, z_top - drop + 0.2)], [0.04, 0.04], 6, m["rope"])
    c = Vector((x, y, z_top - drop - 0.17))
    pts = [c + Vector((0.13 * math.sin(a), 0, 0.15 * math.cos(a))) for a in (i / 8 * TAU for i in range(9))]
    mb.tube(pts, [0.022] * 9, 4, m["rope"])
    rope(mb, m, [(x - 0.04, y - 0.16, z_top + 0.02), (x - 0.04, y + 0.16, z_top + 0.02)], r=0.03)


def build_gallows(m):
    """Gibet (5 x 3 m) : estrade à 1,2 m (x -2,5..1,5) sur poteaux et croix de Saint-André,
    trappe, deux montants, poutre et contrefiches, trois nœuds coulants ; marches côté +X."""
    mb = MeshBuilder()
    wood, planks = m["wood_dark"], m["planks_old"]
    X0, X1, Y, ZD = -2.5, 1.5, 1.5, 1.2
    for i in range(8):
        x = X0 + 0.25 + i * 0.5
        mb.box((x, 0, ZD - 0.04), (0.47, 2 * Y, 0.08), planks, texel=1.2)
    for x in (X0 + 0.1, -0.5, X1 - 0.1):
        for y in (-Y + 0.1, Y - 0.1):
            mb.box((x, y, (ZD - 0.08) / 2), (0.2, 0.2, ZD - 0.08), wood)
    for y in (-Y + 0.1, Y - 0.1):
        mb.box(((X0 + X1) / 2, y, ZD - 0.17), (X1 - X0, 0.16, 0.18), wood)
        for xa, xb in ((X0 + 0.1, -0.5), (-0.5, X1 - 0.1)):
            log(mb, (xa, y, 0.1), (xb, y, ZD - 0.25), 0.05, wood, sides=4)
            log(mb, (xb, y, 0.1), (xa, y, ZD - 0.25), 0.05, wood, sides=4)
    # Trappe : liseré sombre, charnières.
    tx0, tx1, ty = -1.95, 0.95, 0.45
    for (cx, cy, sx, sy) in (((tx0 + tx1) / 2, -ty, tx1 - tx0, 0.04), ((tx0 + tx1) / 2, ty, tx1 - tx0, 0.04),
                             (tx0, 0, 0.04, 2 * ty), (tx1, 0, 0.04, 2 * ty), ((tx0 + tx1) / 2, 0, tx1 - tx0, 0.03)):
        mb.box((cx, cy, ZD + 0.002), (sx, sy, 0.01), m["shadow_dark"])
    for x in (-1.5, -0.5, 0.5):
        mb.box((x, ty + 0.05, ZD + 0.01), (0.25, 0.1, 0.03), m["iron"])
    # Montants, poutre, contrefiches, nœuds.
    ZB = 4.5
    for x in (-2.15, 1.15):
        mb.box((x, 0, ZB / 2), (0.26, 0.26, ZB), wood, texel=1.0)
    mb.box((-0.5, 0, ZB - 0.05), (3.9, 0.26, 0.3), wood, texel=1.0)
    for x, d in ((-2.15, 1), (1.15, -1)):
        log(mb, (x + d * 0.12, 0, ZB - 0.85), (x + d * 0.75, 0, ZB - 0.2), 0.07, wood, sides=4)
    for x in (-1.4, -0.5, 0.4):
        noose(mb, m, x, 0, ZB - 0.2)
    # Marches (+X) et main courante.
    for k in range(1, 5):
        h = ZD * k / 5
        x = 2.5 - 0.25 * k + 0.125
        mb.box((x, 0, h / 2), (0.25, 1.2, h), planks, texel=1.0)
    log(mb, (2.4, 0.65, 0), (2.4, 0.65, 1.0), 0.04, wood, sides=4)
    log(mb, (2.4, 0.65, 0.95), (1.45, 0.65, ZD + 0.95), 0.035, wood, sides=4)
    log(mb, (1.45, 0.65, ZD), (1.45, 0.65, ZD + 1.0), 0.04, wood, sides=4)
    # Levier de la trappe.
    log(mb, (0.95, -0.9, ZD), (0.75, -0.9, ZD + 0.9), 0.03, m["iron"], sides=4)
    return mb.build("gallows")


def build_scaffold(m):
    """Échafaud 6 x 6 m, plancher à 1,5 m : coffrage de planches et tentures rouges, braseros
    aux angles, billot à la hache plantée, guillotine (lame, mouton, lunette, bascule,
    panier), taches de sang ; marches côté -Y (y de -3 à -4,25)."""
    mb = MeshBuilder()
    wood, planks = m["wood_dark"], m["planks_old"]
    S, ZD = 3.0, 1.5
    wbox(mb, (0, 0, (ZD - 0.12) / 2), (2 * S - 0.1, 2 * S - 0.1, ZD - 0.12), planks, texel=1.4, skip=("-z", "+z"))
    mb.box((0, 0, ZD - 0.06), (2 * S + 0.1, 2 * S + 0.1, 0.12), planks, texel=1.5)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * (S - 0.1), sy * (S - 0.1), 1.3), (0.3, 0.3, 2.6), wood, texel=1.0)
            c = Vector((sx * (S - 0.1), sy * (S - 0.1), 2.6))
            mb.prism(c, 0.14, 0.32, 0.28, 8, m["iron"], cap_top=False, cap_bottom=True)
            mb.disc(c + UP * 0.22, 0.27, 8, m["forge_fire"])
            mb.tube([c + UP * 0.2, c + UP * 0.45, c + UP * 0.65], [0.2, 0.12, 0.0], 5, m["forge_fire"], twist=0.5)
    for s in (-1, 1):
        mb.box((0, s * (S - 0.1), ZD - 0.25), (2 * S, 0.12, 0.2), wood)
    front = Wall(mb, (0, -S - 0.02, 0), (0, -1, 0))
    for u in (-2.1, 2.1):
        banner(front, m, u, ZD - 0.05, 1.25, "cloth_red", trim="cloth_red", width=1.3, d=0.0)
    for sx in (-1, 1):
        side = Wall(mb, (sx * (S + 0.02), 0, 0), (sx, 0, 0))
        for u in (-1.5, 1.5):
            banner(side, m, u, ZD - 0.05, 1.25, "cloth_red", trim="cloth_red", width=1.3, d=0.0)
    # Marches.
    for k in range(5):
        h = ZD * (5 - k) / 5
        y = -S - 0.125 - k * 0.25
        mb.box((0, y, h / 2), (1.8, 0.25, h), planks, texel=1.0)
    # Billot et hache.
    bx, by = -1.2, 0.3
    log(mb, (bx, by, ZD), (bx, by, ZD + 0.55), 0.3, m["log_bark"], sides=8, cap=m["wood_rings"])
    mb.box((bx, by, ZD + 0.555), (0.62, 0.12, 0.012), m["shadow_dark"])
    mb.box((bx + 0.12, by + 0.05, ZD + 0.6), (0.06, 0.3, 0.16), m["iron"], rot=Matrix.Rotation(0.4, 3, "X"))
    log(mb, (bx + 0.12, by + 0.0, ZD + 0.6), (bx + 0.2, by - 0.75, ZD + 0.95), 0.03, m["wood_sign"], sides=5)
    # Guillotine.
    gx, gy = 1.3, 0.9
    for s in (-1, 1):
        mb.box((gx + s * 0.42, gy, ZD + 1.9), (0.18, 0.2, 3.8), wood, texel=1.0)
        log(mb, (gx + s * 0.42, gy + 0.1, ZD), (gx + s * 0.42, gy + 0.9, ZD + 1.0), 0.05, wood, sides=4)
        log(mb, (gx + s * 0.42, gy - 0.1, ZD), (gx + s * 0.42, gy - 0.7, ZD + 0.9), 0.05, wood, sides=4)
    mb.box((gx, gy, ZD + 3.9), (1.25, 0.32, 0.28), wood)
    mb.box((gx, gy, ZD + 3.35), (0.66, 0.16, 0.35), wood)
    with bl.Xf(mb, bl.T(gx, gy, ZD + 2.75)):
        slab(mb, [(-0.33, 0.0), (0.33, 0.28), (0.33, 0.45), (-0.33, 0.45)], -0.02, 0.02, m["iron"], texel=0.6)
    mb.box((gx, gy, ZD + 0.42), (0.66, 0.16, 0.2), wood)
    mb.box((gx, gy, ZD + 0.66), (0.66, 0.16, 0.18), wood)
    face(mb, [(gx + 0.1 * math.cos(a), gy - 0.082, ZD + 0.54 + 0.1 * math.sin(a)) for a in (i / 8 * TAU for i in range(8))],
         (0, -1, 0), m["shadow_dark"])
    mb.box((gx, gy + 0.9, ZD + 0.4), (0.42, 1.6, 0.08), m["planks_fresh"])
    for y in (gy + 0.4, gy + 1.5):
        mb.box((gx, y, ZD + 0.18), (0.36, 0.08, 0.36), wood)
    mb.tube([(gx, gy - 0.5, ZD), (gx, gy - 0.5, ZD + 0.28)], [0.22, 0.26], 8, planks, cap_bottom=True)
    rope(mb, m, [(gx, gy, ZD + 3.2), (gx, gy, ZD + 3.75), (gx + 0.5, gy - 0.12, ZD + 3.76),
                 (gx + 0.52, gy - 0.12, ZD + 1.2)])
    # Taches de sang.
    for (x, y, sx, sy, a) in ((bx + 0.35, by - 0.4, 0.7, 0.45, 0.3), (bx - 0.2, by + 0.4, 0.4, 0.3, -0.6),
                              (gx, gy - 0.45, 0.6, 0.5, 0.2), (gx - 0.3, gy - 1.0, 0.35, 0.25, 1.0)):
        mb.box((x, y, ZD + 0.005), (sx, sy, 0.01), m["cloth_red"], rot=Matrix.Rotation(a, 3, "Z"))
    return mb.build("scaffold")


# ---------------------------------------------------------------------------
# Tombes, cage, râtelier
# ---------------------------------------------------------------------------

def build_gravestone(m):
    """Stèle cintrée (0,6 x 0,25 x 1 m) un peu penchée, socle, croix gravée, mousse."""
    mb = MeshBuilder()
    with bl.Xf(mb, bl.R(0.07, "Y") @ bl.R(-0.05, "X")):
        r, z0 = 0.29, 0.72
        pts = [(-r, -0.15), (r, -0.15)]
        pts += [(r * math.cos(a), z0 + r * 0.9 * math.sin(a)) for a in (i / 6 * math.pi for i in range(7))]
        slab(mb, pts, -0.11, 0.11, m["ruin_smooth"], texel=0.8)
        mb.box((0, -0.115, 0.68), (0.05, 0.01, 0.34), m["shadow_dark"])
        mb.box((0, -0.115, 0.74), (0.24, 0.01, 0.05), m["shadow_dark"])
        for k, z in enumerate((0.38, 0.3)):
            mb.box((0, -0.115, z), (0.34 - 0.1 * k, 0.01, 0.025), m["shadow_dark"])
        moss_patch(mb, m, (0.08, 0.0, 0.993), (0.3, 0.2, 0.025))
    wbox(mb, (0, 0, 0.06), (0.72, 0.4, 0.14), m["ruin_stone"], texel=1.0, skip=("-z",))
    return mb.build("gravestone")


def build_gravestone_cross(m):
    """Croix de pierre à anneau (0,5 x 0,3 x 1,4 m) sur socle à degré."""
    mb = MeshBuilder()
    st, sm = m["ruin_smooth"], m["ruin_stone"]
    wbox(mb, (0, 0, 0.09), (0.5, 0.3, 0.18), sm, texel=1.0, skip=("-z",))
    with bl.Xf(mb, bl.T(0, 0, 0.18) @ bl.R(-0.06, "Y")):
        wbox(mb, (0, 0, 0.04), (0.34, 0.22, 0.08), st, texel=1.0)
        mb.box((0, 0, 0.62), (0.16, 0.13, 1.1), st, texel=0.8)
        mb.box((0, 0, 0.88), (0.5, 0.13, 0.15), st, texel=0.8)
        pts = [(0.19 * math.cos(a), 0, 0.88 + 0.19 * math.sin(a)) for a in (i / 12 * TAU for i in range(13))]
        mb.tube(pts, [0.035] * 13, 4, st)
        moss_patch(mb, m, (0, 0, 1.175), (0.15, 0.12, 0.02))
    return mb.build("gravestone_cross")


def build_cage(m):
    """Cage de prisonnier 2 x 2 x 2,2 m : socle de planches, poteaux d'angle, barreaux de fer,
    toit, anneau de suspension, porte cadenassée (-Y), ossements à l'intérieur."""
    mb = MeshBuilder()
    wood, iron = m["wood_dark"], m["iron"]
    H = 2.05
    mb.box((0, 0, 0.12), (2.0, 2.0, 0.24), m["planks_old"], texel=1.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 0.92, sy * 0.92, (0.24 + H) / 2), (0.16, 0.16, H - 0.24), wood, texel=0.8)
    for s in (-1, 1):
        mb.box((0, s * 0.92, H), (2.0, 0.16, 0.16), wood)
        mb.box((s * 0.92, 0, H), (0.16, 2.0, 0.16), wood)
    mb.box((0, 0, H + 0.12), (2.15, 2.15, 0.08), m["planks_old"], texel=1.0)
    for k in range(7):
        t = -0.72 + k * 0.24
        for (x, y) in ((t, -0.92), (t, 0.92), (-0.92, t), (0.92, t)):
            mb.prism((x, y, 0.24), 0.022, 0.022, H - 0.32, 4, iron, cap_top=False)
    for z in (0.9, 1.6):
        for s in (-1, 1):
            mb.box((0, s * 0.92, z), (1.7, 0.05, 0.04), iron)
            mb.box((s * 0.92, 0, z), (0.05, 1.7, 0.04), iron)
    for x in (-0.38, 0.38):
        mb.box((x, -0.93, 1.07), (0.05, 0.05, 1.6), iron)
    mb.box((0.3, -0.98, 1.2), (0.12, 0.05, 0.14), iron)
    pts = [(0.14 * math.cos(a), 0, H + 0.32 + 0.14 * math.sin(a)) for a in (i / 8 * TAU for i in range(9))]
    mb.tube(pts, [0.025] * 9, 4, iron)
    # Ossements.
    blob(mb, (0.45, 0.4, 0.34), (0.11, 0.13, 0.1), m["bone"], segs=7, rings=5, texel=0.3)
    mb.box((0.45, 0.29, 0.34), (0.1, 0.02, 0.04), m["shadow_dark"])
    for a, b in (((-0.4, 0.5, 0.27), (0.2, 0.2, 0.27)), ((-0.5, -0.3, 0.27), (0.1, 0.1, 0.28)),
                 ((0.2, 0.55, 0.27), (0.6, -0.1, 0.27))):
        log(mb, a, b, 0.025, m["bone"], sides=4)
    return mb.build("cage")


def build_weapon_rack(m):
    """Râtelier (2 m selon X) : deux chevalets, lisses haute et basse, cinq lances appuyées côté
    -Y, une hache et un bouclier rond."""
    rng = random.Random(29)
    mb = MeshBuilder()
    wood = m["wood_dark"]
    for x in (-0.95, 0.95):
        for s in (-1, 1):
            log(mb, (x, s * 0.35, 0), (x, s * 0.03, 1.3), 0.045, wood, sides=5)
        mb.box((x, 0, 1.28), (0.1, 0.14, 0.1), wood)
    mb.box((0, 0, 1.22), (2.05, 0.1, 0.1), m["planks_old"], texel=1.0)
    log(mb, (-0.95, -0.25, 0.3), (0.95, -0.25, 0.3), 0.04, wood, sides=5)
    log(mb, (-0.95, 0.25, 0.3), (0.95, 0.25, 0.3), 0.04, wood, sides=5)
    for k in range(5):
        x = -0.72 + k * 0.32
        foot = Vector((x + rng.uniform(-0.05, 0.05), -0.36, 0.0))
        lean = Vector((x + rng.uniform(-0.08, 0.08), -0.02, 1.28))
        d = (lean - foot).normalized()
        top = foot + d * rng.uniform(2.1, 2.35)
        mb.tube([foot, top], [0.025, 0.022], 5, m["wood_sign"])
        mb.tube([top - d * 0.02, top + d * 0.08, top + d * 0.32], [0.03, 0.045, 0.002], 4, m["iron"])
    # Hache appuyée à droite.
    foot, top = Vector((0.75, -0.3, 0.0)), Vector((0.62, -0.08, 1.15))
    mb.tube([foot, top], [0.03, 0.03], 5, m["wood_sign"])
    mb.box(top + Vector((0.12, -0.02, -0.05)), (0.24, 0.04, 0.28), m["iron"], rot=Matrix.Rotation(0.2, 3, "Y"))
    # Bouclier rond appuyé à gauche.
    with bl.Xf(mb, bl.T(-0.6, -0.42, 0.4) @ bl.R(math.pi / 2 - 0.25, "X")):
        mb.prism((0, 0, 0), 0.38, 0.38, 0.05, 10, m["planks_old"], texel=0.8, cap_bottom=True)
        mb.prism((0, 0, 0.05), 0.4, 0.4, 0.02, 10, m["iron"], cap_top=False)
        mb.prism((0, 0, 0.05), 0.1, 0.06, 0.07, 8, m["iron"])
        mb.disc((0, 0, 0.051), 0.3, 10, m["cloth_red"])
    return mb.build("weapon_rack")


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def main():
    os.makedirs(bl.OUT, exist_ok=True)
    be.clear_scene()
    m = cmats()
    singles = [
        build_tent(m), build_tent_large(m), build_palisade(m), build_palisade_gate(m), build_watch_tower(m),
        build_gallows(m), build_scaffold(m), build_gravestone(m), build_gravestone_cross(m), build_cage(m),
        build_weapon_rack(m),
    ]
    for obj in singles:
        bl.export(f"{obj.name}.glb", [obj.name])
    build_campfire(m)
    bl.export("campfire.glb", ["campfire", "campfire_flames"])


if __name__ == "__main__":
    main()
