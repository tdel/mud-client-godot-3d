"""Générateur des grandes structures « façon Lineage 2 » (ville de Gludio, château, ruines,
marais de Cruma), exportées en glTF binaire pour Godot. Réutilise les outils de maillage et
les matériaux de build_environment.py / build_village.py.

Usage (depuis la racine du projet, après fetch_textures.py) :
    blender -b --python tools/env_gen/build_l2_structures.py

Sortie : assets/environment/models/l2/ (un modèle par fichier, assemblé dans
scenes/maps/props/<Nom>.tscn)
    temple.glb              temple d'Einhasad : basilique de marbre, bas-côtés, arcs-boutants,
                            abside, clocher-porche à flèche d'ardoise en façade (porte -Y).
    monument.glb            monument de la place : bassin octogonal à gradins, piédestal,
                            chevalier de bronze brandissant l'épée ; monument_water (nappe) et
                            monument_water_fall (quatre filets d'eau) animés par Monument.gd.
    castle_keep.glb         donjon carré 22 m, tourelles d'angle à poivrières, porche crénelé.
    castle_wall.glb         tronçon de courtine 4 m (X), 3,6 m d'épaisseur, ~10 m.
    castle_tower.glb        grosse tour ronde crénelée, toit conique.
    castle_gatehouse.glb    châtelet : deux tours carrées, passage voûté de 5 m (selon Y).
    ruin_*.glb              ruines antiques (colonnes, murs, arche, statue, éboulis, autel aux
                            runes rouges, crâne cornu géant).
    marsh_tree*.glb         arbres morts des marais, mousse pendante (cartes alpha).

Écrit aussi assets/environment/textures/foliage_moss.png (filaments de mousse pendante,
attache en haut de l'image), générée procéduralement.

Conventions : identiques à build_environment.py (Blender Z haut, +Y Blender = -Z Godot,
façade/porte côté -Y Blender = +Z Godot, 1 case = 1 m, aucune image embarquée : matériaux
remplacés par nom côté Godot, voir scenes/maps/common/EnvMaterials.gd).
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
import build_village as bv  # noqa: E402
from build_environment import UP, MeshBuilder  # noqa: E402
from build_village import face  # noqa: E402

OUT = os.path.join(be.OUT, "l2")
TAU = math.tau


# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------

def build_moss_texture():
    """Texture de mousse pendante (256 x 512, alpha) : filaments ondulants accrochés en haut,
    plus fins vers le bas, quelques ramifications ; RGB des zones transparentes rempli par la
    teinte moyenne (pas de liseré sombre avec les mipmaps)."""
    import numpy as np
    W, H = 256, 512
    rng = np.random.default_rng(7)
    img = np.zeros((H, W, 4), np.float32)  # ligne 0 = haut de l'image

    def strand(x0, y0, length, width, col):
        phase = rng.uniform(0, TAU)
        amp = rng.uniform(2.0, 9.0)
        freq = rng.uniform(0.012, 0.035)
        drift = rng.uniform(-0.04, 0.04)
        n = int(length)
        for i in range(n):
            y = int(y0 + i)
            if y >= H:
                break
            x = x0 + amp * math.sin(i * freq + phase) + i * drift
            w = max(0.6, width * (1.0 - 0.75 * i / max(n, 1)))
            xa, xb = int(max(0, x - w)), int(min(W - 1, x + w)) + 1
            if xa >= xb:
                continue
            k = 0.85 + 0.3 * rng.random()
            img[y, xa:xb, :3] = col * k
            img[y, xa:xb, 3] = 1.0
            if rng.random() < 0.012 and n - i > 40:
                strand(x, y, (n - i) * rng.uniform(0.3, 0.6), w * 0.6, col * rng.uniform(0.85, 1.1))

    for _ in range(46):
        shade = rng.uniform(0.75, 1.15)
        col = np.array([0.46, 0.5, 0.36]) * shade
        x0 = rng.uniform(10, W - 10)
        strand(x0, rng.uniform(0, 30), H * rng.uniform(0.35, 0.98), rng.uniform(2.0, 4.5), col)
    # Bourrelet d'attache plus dense en haut.
    for _ in range(40):
        col = np.array([0.4, 0.45, 0.3]) * rng.uniform(0.8, 1.1)
        strand(rng.uniform(16, W - 16), 0, H * rng.uniform(0.08, 0.25), rng.uniform(3.0, 6.0), col)
    mask = img[..., 3] > 0
    img[~mask, :3] = img[mask, :3].mean(axis=0)
    path = os.path.join(be.TEX, "foliage_moss.png")
    im = bpy.data.images.new("foliage_moss_gen", W, H, alpha=True)
    im.pixels.foreach_set(img[::-1].ravel())  # bpy : ligne 0 = bas
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("écrit", path)


def lmats():
    m = bv.vmats()
    m.update({
        # Pierre claire du temple et du monument (blocs / moulures lisses).
        "marble": be.material("marble", base=(0.86, 0.84, 0.78)),
        "marble_smooth": be.material("marble_smooth", base=(0.9, 0.88, 0.82)),
        "bronze": be.material("bronze", base=(0.45, 0.33, 0.2), metallic=0.6, roughness=0.5),
        "gold_trim": be.material("gold_trim", base=(0.85, 0.65, 0.25), metallic=0.8, roughness=0.4),
        # Ruines : pierre usée verdie, mousse rase sur les arêtes, os pâle du crâne.
        "ruin_stone": be.material("ruin_stone", base=(0.5, 0.52, 0.45)),
        "ruin_smooth": be.material("ruin_smooth", base=(0.6, 0.62, 0.55)),
        "moss": be.material("moss", base=(0.3, 0.38, 0.2)),
        "bone": be.material("bone", base=(0.85, 0.8, 0.68)),
        "rune_red": be.material("rune_red", base=(0.9, 0.12, 0.08), emission=(0.9, 0.12, 0.08)),
        "bark_swamp": be.material("bark_swamp", base=(0.25, 0.24, 0.2)),
        "moss_hanging": be.material("moss_hanging", "foliage_moss.png", alpha=True),
    })
    return m


# ---------------------------------------------------------------------------
# Outils géométriques
# ---------------------------------------------------------------------------

class Xf:
    """Bloc `with` : applique `matrix` (rotation/translation/échelle uniforme) à tous les
    sommets ajoutés au MeshBuilder dans le bloc — on modélise en repère local puis on pose."""

    def __init__(self, mb, matrix):
        self.mb = mb
        self.matrix = matrix

    def __enter__(self):
        self.n0 = len(self.mb.verts)
        return self.mb

    def __exit__(self, *_):
        rot = self.matrix.to_3x3().normalized()
        for i in range(self.n0, len(self.mb.verts)):
            self.mb.verts[i] = self.matrix @ self.mb.verts[i]
        for i, n in self.mb.normal_override.items():
            if i >= self.n0:
                self.mb.normal_override[i] = rot @ Vector(n)


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(angle, axis):
    return Matrix.Rotation(angle, 4, axis)


def S(k):
    return Matrix.Scale(k, 4)


def wbox(mb, center, size, mat, texel=2.0, skip=()):
    """Pavé aligné sur les axes, UV projetées depuis les coordonnées monde : l'appareil de
    pierre se continue d'un bloc à l'autre (murs en tranches, tours)."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    x0, x1, y0, y1, z0, z1 = cx - hx, cx + hx, cy - hy, cy + hy, cz - hz, cz + hz
    faces = {
        "+z": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
        "-z": [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],
        "+x": [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
        "-x": [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
        "+y": [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
        "-y": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
    }
    for key, pts in faces.items():
        if key in skip:
            continue
        if key[1] == "z":
            uv = [(p[0] / texel, p[1] / texel) for p in pts]
        elif key[1] == "x":
            uv = [((p[1] if key[0] == "+" else -p[1]) / texel, p[2] / texel) for p in pts]
        else:
            uv = [((-p[0] if key[0] == "+" else p[0]) / texel, p[2] / texel) for p in pts]
        mb.quad(*pts, mat, uv)


class Wall:
    """Repère d'une face de mur (rotation propre, sans miroir) : origine au pied, `n` normale
    sortante, u horizontal vers la droite de qui regarde la face, z vers le haut."""

    def __init__(self, mb, origin, n):
        self.mb = mb
        self.o = Vector(origin)
        self.n = Vector(n).normalized()
        self.u = UP.cross(self.n).normalized()
        v = UP.cross(self.u)
        self.rot = Matrix(((self.u.x, v.x, 0), (self.u.y, v.y, 0), (0, 0, 1)))

    def at(self, u, z, d=0.0):
        return self.o + self.u * u + UP * z + self.n * d

    def box(self, u, z, size, mat, d=0.0, angle=0.0, texel=1.0):
        """Boîte centrée en (u, z, d) ; size = (le long de u, épaisseur, hauteur) ; `angle`
        incline l'axe u vers le haut dans le plan du mur."""
        rot = self.rot @ Matrix.Rotation(-angle, 3, "Y") if angle else self.rot
        self.mb.box(self.at(u, z, d), size, mat, rot=rot, texel=texel)

    def poly(self, pts, d, mat, texel=1.0):
        world = [self.at(u, z, d) for u, z in pts]
        face(self.mb, world, self.n, mat, [(u / texel, z / texel) for u, z in pts])

    def arch_pts(self, u, z0, w, h, segs=8):
        r = w / 2
        spring = z0 + h - r
        pts = [(u - r, z0), (u + r, z0), (u + r, spring)]
        for i in range(1, segs):
            a = i / segs * math.pi
            pts.append((u + r * math.cos(a), spring + r * math.sin(a)))
        pts.append((u - r, spring))
        return pts


def voussoirs(wall, u, spring, r, t, mat, d, depth=0.25, segs=7, a0=0.0, a1=math.pi):
    for i in range(segs):
        a = a0 + (a1 - a0) * (i + 0.5) / segs
        rr = r + t / 2
        wall.box(u + rr * math.cos(a), spring + rr * math.sin(a),
                 (rr * (a1 - a0) / segs * 1.04, depth, t), mat, d=d, angle=a + math.pi / 2, texel=0.8)


def lancet(wall, m, u, z0, w, h, frame, glass="window_glass", d=0.0, mullion=True, t=0.2):
    """Fenêtre en plein cintre : vitre, piédroits, claveaux, appui ; meneau et traverse."""
    r = w / 2
    spring = z0 + h - r
    wall.poly(wall.arch_pts(u, z0, w, h), d + 0.02, m[glass])
    for s in (-1, 1):
        wall.box(u + s * (r + t / 2), (z0 + spring) / 2, (t, 0.25, spring - z0), frame, d=d + 0.04, texel=0.8)
    voussoirs(wall, u, spring, r, t, frame, d + 0.04)
    wall.box(u, z0 - 0.08, (w + 2 * t + 0.12, 0.34, 0.16), frame, d=d + 0.08, texel=0.8)
    if mullion:
        iron = m["iron"]
        wall.box(u, (z0 + spring + r * 0.7) / 2, (0.06, 0.08, spring + r * 0.7 - z0), iron, d=d + 0.04)
        for k in range(1, int((spring - z0) / 0.9) + 1):
            wall.box(u, z0 + k * 0.9, (w, 0.08, 0.05), iron, d=d + 0.04)


def rose_window(wall, m, u, zc, r, frame, d=0.0):
    sides = 20
    pts = [(u + r * math.cos(a), zc + r * math.sin(a)) for a in (i / sides * TAU for i in range(sides))]
    wall.poly(pts, d + 0.02, m["window_glass"])
    voussoirs(wall, u, zc, r, 0.24, frame, d + 0.05, depth=0.3, segs=16, a0=0.0, a1=TAU)
    for k in range(6):
        wall.box(u, zc, (2 * r, 0.12, 0.08), frame, d=d + 0.07, angle=k * math.pi / 6)
    hub = [(u + r * 0.22 * math.cos(a), zc + r * 0.22 * math.sin(a)) for a in (i / 10 * TAU for i in range(10))]
    wall.poly(hub, d + 0.12, frame)
    # Couronne intérieure de la rosace (petits lobes).
    for k in range(12):
        a = (k + 0.5) / 12 * TAU
        wall.box(u + r * 0.62 * math.cos(a), zc + r * 0.62 * math.sin(a), (0.3, 0.1, 0.07), frame, d=d + 0.07,
                 angle=a + math.pi / 2)


def arched_door(wall, m, u, z0, w, h, frame, orders=3, leaf="planks_old"):
    """Grande porte à deux vantaux sous un portail à voussures en retrait."""
    r = w / 2
    spring = z0 + h - r
    wall.poly(wall.arch_pts(u, z0, w, h, 10), 0.03, m[leaf])
    wall.box(u, z0 + (h - 0.1) / 2, (0.06, 0.06, h - 0.1), m["shadow_dark"], d=0.05)
    for zz in (0.5, 1.6, spring - z0 - 0.3):
        for s in (-1, 1):
            wall.box(u + s * w * 0.25, z0 + zz, (w * 0.42, 0.06, 0.1), m["iron"], d=0.06)
    for s in (-1, 1):
        wall.box(u + s * 0.16, z0 + h * 0.42, (0.06, 0.08, 0.22), m["iron"], d=0.08)
    for k in range(orders):
        t = 0.28
        rr = r + k * t
        dd = 0.08 + k * 0.14
        for s in (-1, 1):
            wall.box(u + s * (rr + t / 2), (z0 + spring) / 2, (t, 0.3, spring - z0), frame, d=dd, texel=0.8)
        voussoirs(wall, u, spring, rr, t, frame, dd, depth=0.3, segs=9)


def parapet_rect(mb, cx, cy, W, D, z, mat, cap, t=0.45, low=0.7, mh=0.9, mw=0.9, step=1.8):
    """Parapet crénelé sur le pourtour d'un rectangle (sommet de mur à z)."""
    for sy in (-1, 1):
        y = cy + sy * (D / 2 - t / 2)
        wbox(mb, (cx, y, z + low / 2), (W, t, low), mat, skip=("-z",))
        n = max(2, round(W / step))
        for i in range(n):
            x = cx - W / 2 + W / n * (i + 0.5)
            wbox(mb, (x, y, z + low + mh / 2), (mw, t, mh), mat, skip=("-z",))
            wbox(mb, (x, y, z + low + mh + 0.04), (mw + 0.08, t + 0.08, 0.08), cap, texel=1.0)
    for sx in (-1, 1):
        x = cx + sx * (W / 2 - t / 2)
        wbox(mb, (x, cy, z + low / 2), (t, D - 2 * t, low), mat, skip=("-z",))
        n = max(2, round(D / step))
        for i in range(n):
            y = cy - D / 2 + D / n * (i + 0.5)
            if abs(y - cy) > D / 2 - t - mw / 2 + 0.05:
                continue
            wbox(mb, (x, y, z + low + mh / 2), (t, mw, mh), mat, skip=("-z",))
            wbox(mb, (x, y, z + low + mh + 0.04), (t + 0.08, mw + 0.08, 0.08), cap, texel=1.0)


def parapet_ring(mb, cx, cy, R_, z, mat, cap, sides=16, count=8, t=0.4, low=0.7, mh=0.9, mw=1.0):
    ro = math.pi / sides
    mb.ring_wall((cx, cy, z), R_, R_ - t, 0.0, low, sides, mat, cap, texel=2.0, rot_offset=ro)
    for k in range(count):
        a = (k + 0.5) / count * TAU
        c = Vector((cx + math.cos(a) * (R_ - t / 2), cy + math.sin(a) * (R_ - t / 2), z + low + mh / 2))
        mb.box(c, (t, mw, mh), mat, rot=Matrix.Rotation(a, 3, "Z"), texel=2.0)
        mb.box(c + UP * (mh / 2 + 0.04), (t + 0.08, mw + 0.08, 0.08), cap, rot=Matrix.Rotation(a, 3, "Z"))


def cone_roof(mb, m, cx, cy, z, r, h, sides=16, flag=None):
    mb.prism((cx, cy, z), r, 0.04, h, sides, m["roof_slate"], texel=1.5, cap_top=False, cap_bottom=True,
             rot_offset=math.pi / sides)
    mb.prism((cx, cy, z + h - 0.15), 0.08, 0.02, 1.4, 6, m["iron"], texel=0.5)
    mb.prism((cx, cy, z + h + 0.1), 0.12, 0.12, 0.12, 6, m["iron"], texel=0.5)
    if flag:
        mb.box((cx + 0.45, cy, z + h + 0.95), (0.85, 0.03, 0.45), m[flag])


def banner(wall, m, u, z_top, length, cloth, trim="cloth_cream", width=1.3, d=0.06):
    """Bannière pendue à une hampe de fer contre un mur, pointe en V en bas."""
    zc = z_top - length / 2
    wall.box(u, zc + 0.15, (width, 0.04, length - 0.3), m[cloth], d=d)
    for s in (-1, 1):
        wall.poly([(u + s * width / 2, z_top - length + 0.3), (u, z_top - length), (u, z_top - length + 0.3)],
                  d + 0.021, m[cloth])
    wall.box(u, zc + length * 0.12, (width * 0.36, 0.04, length * 0.28), m[trim], d=d + 0.012)
    wall.box(u, z_top - length * 0.18, (width, 0.04, 0.12), m[trim], d=d + 0.012)
    wall.box(u, z_top + 0.05, (width + 0.5, 0.08, 0.08), m["iron"], d=d + 0.08)


def fluted(mb, c, r0, r1, z0, z1, flutes, mat, depth=0.05, texel=1.0, cap=None, top_fn=None):
    """Fût cannelé vertical (rayons alternés) ; `top_fn(angle)` donne un sommet brisé
    (hauteur par sommet), refermé par un éventail vers le centre si `cap`."""
    cx, cy = c[0], c[1]
    n = flutes * 2
    ring_b, ring_t = [], []
    for s in range(n + 1):
        a = s / n * TAU
        k = 1.0 if s % 2 == 0 else 1.0 - depth / max(r0, 0.05)
        zt = top_fn(a) if top_fn else z1
        f = (zt - z0) / (z1 - z0) if z1 != z0 else 1.0
        rt = r0 + (r1 - r0) * f
        ring_b.append(Vector((cx + math.cos(a) * r0 * k, cy + math.sin(a) * r0 * k, z0)))
        ring_t.append(Vector((cx + math.cos(a) * rt * k, cy + math.sin(a) * rt * k, zt)))
    per = TAU * r0 / n
    for s in range(n):
        u0, u1 = s * per / texel, (s + 1) * per / texel
        mb.quad(ring_b[s], ring_b[s + 1], ring_t[s + 1], ring_t[s], mat,
                ((u0, z0 / texel), (u1, z0 / texel), (u1, ring_t[s + 1].z / texel), (u0, ring_t[s].z / texel)))
    if cap:
        zc = sum(p.z for p in ring_t[:-1]) / n
        ci = mb.add_vert((cx, cy, zc))
        for s in range(n):
            a, b = ring_t[s], ring_t[s + 1]
            ia, ib = mb.add_vert(a), mb.add_vert(b)
            mb.add_face((ci, ia, ib), ((0.5, 0.5), (0.5 + (a.x - cx) / texel, 0.5 + (a.y - cy) / texel),
                                       (0.5 + (b.x - cx) / texel, 0.5 + (b.y - cy) / texel)), cap)


def blob(mb, center, radii, mat, segs=14, rings=9, deform=None, texel=1.5):
    """Ellipsoïde lisse (sommets partagés -> normales adoucies) ; `deform(dir, p)` renvoie la
    position finale d'un sommet (dir : direction unitaire sur la sphère)."""
    c = Vector(center)
    grid = []
    for j in range(rings + 1):
        th = j / rings * math.pi
        row = []
        for i in range(segs):
            ph = i / segs * TAU
            d = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), -math.cos(th)))
            p = c + Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2]))
            if deform:
                p = deform(d, p)
            row.append(mb.add_vert(p))
            if j == 0 or j == rings:
                break
        grid.append(row)
    def tri_uv(idx):
        # Projection planaire selon l'axe dominant de la face : pas d'étoilement aux pôles.
        pts = [mb.verts[i] for i in idx]
        nrm = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        ax = max(range(3), key=lambda k: abs(nrm[k]))
        keep = [k for k in range(3) if k != ax]
        return [(p[keep[0]] / texel, p[keep[1]] / texel) for p in pts]

    for j in range(rings):
        a, b = grid[j], grid[j + 1]
        for i in range(segs):
            if len(a) == 1:
                idx = (a[0], b[(i + 1) % segs], b[i])
            elif len(b) == 1:
                idx = (a[i], a[(i + 1) % segs], b[0])
            else:
                idx = (a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i])
            mb.add_face(idx, tri_uv(idx), mat)


def half_ring_walls(mb, c, r, z0, z1, a0, a1, segs, mat, texel=2.0, cap=None):
    """Murs d'un polygone partiel (abside) entre les angles a0 et a1, faces vers l'extérieur ;
    renvoie les sommets du bord haut."""
    c = Vector(c)
    pts = [c + Vector((math.cos(a0 + (a1 - a0) * i / segs) * r, math.sin(a0 + (a1 - a0) * i / segs) * r, 0))
           for i in range(segs + 1)]
    run = 0.0
    for i in range(segs):
        p, q = pts[i], pts[i + 1]
        seg = (q - p).length
        mid = (a0 + (a1 - a0) * (i + 0.5) / segs)
        nrm = (math.cos(mid), math.sin(mid), 0)
        quad = [p + UP * z0, q + UP * z0, q + UP * z1, p + UP * z1]
        uv = [(run / texel, z0 / texel), ((run + seg) / texel, z0 / texel), ((run + seg) / texel, z1 / texel),
              (run / texel, z1 / texel)]
        face(mb, quad, nrm, mat, uv)
        if cap:
            face(mb, [p + UP * z1, q + UP * z1, c + UP * z1], (0, 0, 1), cap,
                 [(p.x / texel, p.y / texel), (q.x / texel, q.y / texel), (c.x / texel, c.y / texel)])
        run += seg
    return pts


_moss_rng = random.Random(11)


def moss_patch(mb, m, center, size, rot=None):
    """Plaque de mousse rase posée sur une arête/un dessus de pierre : deux plaques un peu
    décalées et tournées, pour casser le contour rectangulaire."""
    base = rot or Matrix.Identity(3)
    c = Vector(center)
    for k in range(2):
        jit = Matrix.Rotation(_moss_rng.uniform(-0.25, 0.25), 3, "Z")
        f = (_moss_rng.uniform(0.6, 0.85), _moss_rng.uniform(0.6, 0.9)) if k else (1.0, 1.0)
        off = base @ Vector((_moss_rng.uniform(-0.15, 0.15) * size[0], _moss_rng.uniform(-0.15, 0.15) * size[1],
                             0.004 * k))
        mb.box(c + off, (size[0] * f[0], size[1] * f[1], size[2]), m["moss"], rot=base @ jit, texel=1.0)


def moss_arc(mb, m, r, z0, z1, a_mid, spread, rng, steps=6):
    """Plaque de mousse épousant un fût couché (repère local du fût : axe z, rayon `r`),
    centrée sur l'angle `a_mid`, bords irréguliers."""
    rows = []
    for i in range(steps + 1):
        z = z0 + (z1 - z0) * i / steps
        half = spread * rng.uniform(0.55, 1.0)
        row = []
        for k in range(5):
            a = a_mid - half + 2 * half * k / 4
            row.append(mb.add_vert((math.cos(a) * r, math.sin(a) * r, z)))
        rows.append(row)
    for i in range(steps):
        for k in range(4):
            idx = (rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k])
            mb.add_face(idx, ((k / 4, i / steps), ((k + 1) / 4, i / steps), ((k + 1) / 4, (i + 1) / steps),
                              (k / 4, (i + 1) / steps)), m["moss"])


def glyphs(mb, rng, mat, center, radius, count, z, size=0.22, square=False):
    """Couronne de runes gravées (traits fins lumineux) au ras d'une surface horizontale."""
    for k in range(count):
        a = k / count * TAU
        if square:
            # Répartition sur le pourtour d'un carré de demi-côté `radius`.
            t = k / count * 4
            side, f = int(t), t - int(t)
            p = [(-1 + 2 * f, -1), (1, -1 + 2 * f), (1 - 2 * f, 1), (-1, 1 - 2 * f)][side]
            c = Vector((center[0] + p[0] * radius, center[1] + p[1] * radius, z))
            a = [0, math.pi / 2, math.pi, -math.pi / 2][side]
        else:
            c = Vector((center[0] + math.cos(a) * radius, center[1] + math.sin(a) * radius, z))
        rot = Matrix.Rotation(a, 3, "Z")
        mb.box(c, (size, 0.035, 0.012), mat, rot=rot)
        if rng.random() < 0.7:
            mb.box(c + rot @ Vector((0.0, size * 0.35 * rng.choice((-1, 1)), 0)), (0.035, size * 0.7, 0.012), mat,
                   rot=rot)
        if rng.random() < 0.5:
            mb.box(c + rot @ Vector((size * 0.4 * rng.choice((-1, 1)), 0.0, 0)), (0.035, size * 0.8, 0.012), mat,
                   rot=rot @ Matrix.Rotation(0.6, 3, "Z"))


# ---------------------------------------------------------------------------
# Ville de Gludio : temple d'Einhasad, monument
# ---------------------------------------------------------------------------

def build_temple(m):
    """Basilique de marbre (emprise X 14 x Y 26 centrée) : nef haute à toit d'ardoise, bas-côtés
    à appentis, contreforts à pinacles et arcs-boutants, abside à l'arrière (+Y), clocher-porche
    carré en façade (-Y) : portail à voussures, rosace, beffroi, flèche octogonale."""
    mb = MeshBuilder()
    wall, trim, slate = m["marble"], m["marble_smooth"], m["roof_slate"]
    NX, NY0, NY1, NH = 4.4, -7.0, 8.0, 11.0
    AX, AH = 6.4, 6.0
    # Soubassement, bas-côtés, nef.
    wbox(mb, (0, 0.5, 0.3), (2 * AX + 0.3, NY1 - NY0 + 0.6, 0.6), trim, texel=1.5, skip=("-z",))
    for sx in (-1, 1):
        wbox(mb, (sx * (NX + AX) / 2, 0.5, AH / 2), (AX - NX, 14.2, AH), wall, skip=("-z",))
        wbox(mb, (sx * (NX + AX) / 2 + sx * 0.05, 0.5, AH + 0.1), (AX - NX + 0.3, 14.5, 0.2), trim, texel=1.0)
    wbox(mb, (0, (NY0 + NY1) / 2, NH / 2), (2 * NX, NY1 - NY0, NH), wall, skip=("-z",))
    wbox(mb, (0, (NY0 + NY1) / 2, NH + 0.1), (2 * NX + 0.3, NY1 - NY0 + 0.2, 0.22), trim, texel=1.0)
    # Toits : appentis des bas-côtés, nef à deux pans (faîtage selon Y) et pignons.
    phi = math.atan2(1.7, AX + 0.3 - NX)
    span = math.hypot(1.7, AX + 0.3 - NX) + 0.1
    for sx in (-1, 1):
        mb.box((sx * (NX + AX + 0.3) / 2, 0.5, AH + 0.95), (span, 14.8, 0.14), slate,
               rot=Matrix.Rotation(sx * phi, 3, "Y"), texel=2.0)
    pitch = math.radians(52)
    with Xf(mb, T(0, (NY0 + NY1) / 2) @ R(math.pi / 2, "Z")):
        ridge = bv.gable_roof(mb, {"roof_tiles": slate}, NY1 - NY0, 2 * NX, NH + 0.2, pitch=pitch, overhang=0.45,
                              gable_over=0.25, mat=slate)
    for y, sy in ((NY0, -1), (NY1, 1)):
        face(mb, [(-NX, y, NH + 0.2), (NX, y, NH + 0.2), (0, y, ridge)], (0, sy, 0), wall,
             bv.planar_uv([(-NX, y, NH + 0.2), (NX, y, NH + 0.2), (0, y, ridge)], Vector((1, 0, 0)), UP, 2.0))
    # Fenêtres, contreforts, pinacles, arcs-boutants.
    bays = [-4.6, -1.2, 2.2, 5.6]
    butts = [-6.3, -2.9, 0.5, 3.9, 7.3]
    for sx in (-1, 1):
        aisle = Wall(mb, (sx * AX, 0, 0), (sx, 0, 0))
        clere = Wall(mb, (sx * NX, 0, 0), (sx, 0, 0))
        for y in bays:
            lancet(aisle, m, y * sx, 1.3, 1.1, 3.4, trim)
            lancet(clere, m, y * sx, 8.0, 1.0, 2.5, trim)
        for y in butts:
            wbox(mb, (sx * (AX + 0.3), y, 2.3), (0.6, 0.8, 4.6), trim, texel=1.5, skip=("-z",))
            mb.box((sx * (AX + 0.3), y, 4.75), (0.62, 0.82, 0.6), trim, rot=Matrix.Rotation(-sx * 0.6, 3, "Y"),
                   texel=1.0)
            wbox(mb, (sx * (AX + 0.2), y, 6.0), (0.4, 0.66, 2.6), trim, texel=1.5)
            mb.prism((sx * (AX + 0.2), y, 7.3), 0.42, 0.02, 1.7, 4, trim, texel=1.0, rot_offset=math.pi / 4)
            ang = math.atan2(9.8 - 6.9, AX + 0.1 - NX)
            length = math.hypot(9.8 - 6.9, AX + 0.1 - NX)
            mb.box((sx * (AX + 0.1 + NX) / 2, y, (6.9 + 9.8) / 2), (length, 0.45, 0.32), trim,
                   rot=Matrix.Rotation(sx * ang, 3, "Y"), texel=1.0)
    # Abside semi-circulaire (côté +Y) : murs, fenêtres, toit en demi-cône.
    APH = 9.0
    ac = Vector((0, NY1, 0))
    half_ring_walls(mb, ac, NX, 0.0, APH, 0.0, math.pi, 5, wall)
    half_ring_walls(mb, ac, NX + 0.15, 0.0, 0.6, 0.0, math.pi, 5, trim, texel=1.5)
    rim = half_ring_walls(mb, ac, NX + 0.12, APH, APH + 0.22, 0.0, math.pi, 5, trim, texel=1.0)
    apex = ac + UP * (APH + 0.2 + (NX + 0.5) * math.tan(math.radians(46)))
    for i in range(5):
        p = (rim[i] - ac) * 1.08 + ac + UP * (APH + 0.15)
        q = (rim[i + 1] - ac) * 1.08 + ac + UP * (APH + 0.15)
        mid = (i + 0.5) / 5 * math.pi
        pts = [p, q, apex]
        face(mb, pts, (math.cos(mid), math.sin(mid), 0.8), slate,
             bv.planar_uv(pts, Vector((-math.sin(mid), math.cos(mid), 0)), UP, 1.5))
    apothem = NX * math.cos(math.pi / 10)
    for i in (1, 2, 3):
        mid = (i + 0.5) / 5 * math.pi
        wa = Wall(mb, ac + Vector((math.cos(mid), math.sin(mid), 0)) * apothem, (math.cos(mid), math.sin(mid), 0))
        lancet(wa, m, 0.0, 1.8, 0.95, 3.6, trim)
    # Clocher-porche en façade.
    TX, TY0, TY1, TH = 2.8, -12.2, -6.8, 20.0
    tyc = (TY0 + TY1) / 2
    wbox(mb, (0, tyc, 0.3), (2 * TX + 0.3, TY1 - TY0 + 0.3, 0.6), trim, texel=1.5, skip=("-z",))
    wbox(mb, (0, tyc, TH / 2), (2 * TX, TY1 - TY0, TH), wall, skip=("-z",))
    for z in (7.2, 11.8, 15.0):
        wbox(mb, (0, tyc, z), (2 * TX + 0.25, TY1 - TY0 + 0.25, 0.22), trim, texel=1.0)
    wbox(mb, (0, tyc, TH + 0.15), (2 * TX + 0.5, TY1 - TY0 + 0.5, 0.3), trim, texel=1.0)
    # Contreforts d'angle de la tour (façade et flancs).
    for sx in (-1, 1):
        for (x, y, w, d) in ((sx * (TX - 0.35), TY0 - 0.3, 0.7, 0.6), (sx * (TX + 0.3), TY0 + 0.45, 0.6, 0.7)):
            wbox(mb, (x, y, 4.5), (w, d, 9.0), trim, texel=1.5, skip=("-z",))
            wbox(mb, (x, y, 11.5), (w * 0.75, d * 0.75, 5.0), trim, texel=1.5)
            mb.prism((x, y, 14.0), max(w, d) * 0.5, 0.02, 1.4, 4, trim, texel=1.0, rot_offset=math.pi / 4)
    # Avant-corps du portail (gâble), marches, porte, lanternes.
    PY = TY0 - 0.35
    wbox(mb, (0, (PY + TY0) / 2, 3.3), (4.4, TY0 - PY, 6.6), trim, texel=1.5, skip=("-z",))
    gpts = [(-2.3, PY, 6.6), (2.3, PY, 6.6), (0, PY, 8.6)]
    face(mb, gpts, (0, -1, 0), trim, bv.planar_uv(gpts, Vector((1, 0, 0)), UP, 1.5))
    for sx in (-1, 1):
        p0, p1 = Vector((sx * 2.3, PY, 6.6)), Vector((0, PY, 8.6))
        mid = (p0 + p1) / 2 + Vector((0, (TY0 - PY) / 2, 0))
        ang = math.atan2(2.0, 2.3)
        mb.box(mid + UP * 0.12, ((p1 - p0).length + 0.2, TY0 - PY + 0.1, 0.24), trim,
               rot=Matrix.Rotation(sx * ang, 3, "Y"), texel=1.0)
    mb.prism((0, TY0 - 0.2, 8.6), 0.25, 0.02, 0.9, 4, trim, rot_offset=math.pi / 4)
    for (y0, y1, h, w) in ((-13.0, PY, 0.15, 4.6), (-12.8, PY, 0.3, 4.2)):
        wbox(mb, (0, (y0 + y1) / 2, h / 2), (w, y1 - y0, h), trim, texel=1.0, skip=("-z",))
    porch = Wall(mb, (0, PY, 0), (0, -1, 0))
    arched_door(porch, m, 0.0, 0.3, 2.4, 4.4, trim, orders=3)
    for s in (-1, 1):
        bv.wall_lantern(porch, m, s * 1.95, 2.7)
    front = Wall(mb, (0, TY0, 0), (0, -1, 0))
    rose_window(front, m, 0.0, 9.6, 1.4, trim)
    faces = [front, Wall(mb, (TX, tyc, 0), (1, 0, 0)), Wall(mb, (-TX, tyc, 0), (-1, 0, 0))]
    for f in faces:
        for s in (-1, 1):
            lancet(f, m, s * 0.75, 12.4, 0.62, 2.0, trim, mullion=False, t=0.16)
    # Beffroi : baies géminées sombres à abat-sons sur les quatre faces.
    for f in faces + [Wall(mb, (0, TY1, 0), (0, 1, 0))]:
        for s in (-1, 1):
            u = s * 0.9
            f.poly(f.arch_pts(u, 15.6, 1.0, 3.4), 0.02, m["shadow_dark"])
            voussoirs(f, u, 15.6 + 3.4 - 0.5, 0.5, 0.2, trim, 0.04)
            for z in (16.0, 16.6, 17.2, 17.8):
                f.box(u, z, (0.98, 0.1, 0.12), m["wood_dark"], d=0.04, angle=0.0)
        f.box(0.0, 17.1, (0.35, 0.3, 3.0), trim, d=0.05, texel=0.8)
    # Pinacles d'angle et flèche octogonale d'ardoise, croix dorée.
    for sx in (-1, 1):
        for y in (TY0 + 0.2, TY1 - 0.2):
            wbox(mb, (sx * (TX - 0.2), y, TH + 0.8), (0.7, 0.7, 1.0), trim, texel=1.0)
            mb.prism((sx * (TX - 0.2), y, TH + 1.3), 0.45, 0.02, 2.4, 4, trim, texel=1.0, rot_offset=math.pi / 4)
    mb.prism((0, tyc, TH + 0.3), 2.55, 0.05, 7.0, 8, slate, texel=1.5, cap_top=False, cap_bottom=True,
             rot_offset=math.pi / 8)
    # Lucarnes de la flèche.
    for k in range(4):
        a = k * math.pi / 2 - math.pi / 2
        c = Vector((math.cos(a) * 1.9, tyc + math.sin(a) * 1.9, TH + 1.6))
        rot = Matrix.Rotation(a + math.pi / 2, 3, "Z")
        mb.box(c, (0.7, 0.7, 1.2), trim, rot=rot, texel=1.0)
        mb.box(c + Vector((math.cos(a), math.sin(a), 0)) * 0.36 + UP * 0.1, (0.36, 0.02, 0.6), m["shadow_dark"],
               rot=rot)
        mb.prism(c + UP * 0.6, 0.52, 0.02, 0.6, 4, slate, rot_offset=a + math.pi / 4)
    gold = m["gold_trim"]
    mb.prism((0, tyc, TH + 7.2), 0.14, 0.14, 0.12, 8, gold)
    mb.box((0, tyc, TH + 7.9), (0.1, 0.1, 1.2), gold)
    mb.box((0, tyc, TH + 8.15), (0.6, 0.1, 0.1), gold)
    return mb.build("temple")


def build_knight(mb, m):
    """Chevalier stylisé (repère humain : pieds en z=0, ~1,8 m, regard vers -Y) levant l'épée
    de la main droite (+X), bouclier au bras gauche, cape au dos."""
    metal, cloth = m["bronze"], m["bronze"]
    for sx, fy in ((1, 0.1), (-1, -0.14)):
        mb.tube([(sx * 0.13, fy, 0.08), (sx * 0.12, fy * 0.6, 0.48), (sx * 0.11, 0.0, 0.9)], [0.085, 0.09, 0.11], 8,
                metal)
        mb.box((sx * 0.13, fy - 0.06, 0.06), (0.15, 0.32, 0.12), metal, texel=0.5)
    mb.prism((0, 0, 0.5), 0.3, 0.22, 0.5, 8, cloth, texel=0.6, cap_bottom=True)
    mb.prism((0, 0, 0.98), 0.21, 0.27, 0.48, 8, metal, texel=0.6)
    mb.prism((0, 0, 1.46), 0.27, 0.12, 0.08, 8, metal, texel=0.6)
    mb.tube([(0, 0, 1.48), (0, 0, 1.56)], [0.07, 0.07], 6, metal)
    # Heaume : calotte, visière, cimier.
    mb.prism((0, 0, 1.55), 0.13, 0.135, 0.17, 8, metal, texel=0.4)
    mb.prism((0, 0, 1.72), 0.135, 0.02, 0.12, 8, metal, texel=0.4)
    mb.box((0, -0.12, 1.65), (0.16, 0.04, 0.03), m["shadow_dark"])
    mb.box((0, 0.02, 1.83), (0.04, 0.3, 0.12), metal, texel=0.4)
    for sx in (-1, 1):
        mb.prism((sx * 0.27, 0, 1.36), 0.12, 0.05, 0.14, 6, metal, texel=0.4, cap_bottom=True)
    # Bras droit levé et épée pointée vers le ciel.
    hand = Vector((0.36, -0.1, 2.02))
    mb.tube([(0.27, 0, 1.38), (0.4, -0.05, 1.68), hand], [0.075, 0.065, 0.055], 7, metal)
    mb.box(hand + UP * 0.03, (0.06, 0.06, 0.2), metal)
    mb.box(hand + UP * 0.15, (0.3, 0.06, 0.05), metal)
    mb.box(hand + UP * 0.66, (0.07, 0.02, 0.95), metal, texel=0.4)
    mb.prism(hand + UP * 1.13, 0.05, 0.005, 0.14, 4, metal, rot_offset=math.pi / 4)
    # Bras gauche et bouclier en écu.
    mb.tube([(-0.27, 0, 1.38), (-0.36, -0.06, 1.12), (-0.25, -0.24, 1.02)], [0.075, 0.065, 0.055], 7, metal)
    shield_rot = Matrix.Rotation(-0.35, 3, "Z") @ Matrix.Rotation(0.12, 3, "X")
    sc = Vector((-0.33, -0.3, 1.05))
    mb.box(sc, (0.46, 0.05, 0.5), metal, rot=shield_rot, texel=0.5)
    tip = [sc + shield_rot @ Vector((-0.23, 0, -0.25)), sc + shield_rot @ Vector((0.23, 0, -0.25)),
           sc + shield_rot @ Vector((0, 0, -0.55))]
    for off in (-0.026, 0.026):
        n = shield_rot @ Vector((0, 1, 0))
        face(mb, [p + n * off for p in tip], n * (1 if off > 0 else -1), metal)
    mb.box(sc + shield_rot @ Vector((0, -0.035, 0.05)), (0.06, 0.02, 0.45), m["gold_trim"], rot=shield_rot)
    mb.box(sc + shield_rot @ Vector((0, -0.035, 0.1)), (0.34, 0.02, 0.06), m["gold_trim"], rot=shield_rot)
    # Cape flottant derrière.
    cape = [Vector((-0.24, 0.13, 1.44)), Vector((0.24, 0.13, 1.44)), Vector((0.44, 0.5, 0.32)),
            Vector((-0.4, 0.42, 0.25))]
    for off, nrm in ((0.0, (0, 1, 0.3)), (-0.02, (0, -1, -0.3))):
        face(mb, [p + Vector((0, off, 0)) for p in cape], nrm, cloth)


def build_monument(m):
    """Monument central (~9 m) : bassin octogonal à gradins (rayon 4,3), quatre gargouilles qui
    déversent l'eau, piédestal mouluré, chevalier de bronze. Eau exportée à part."""
    mb = MeshBuilder()
    mar, sm, dark = m["marble"], m["marble_smooth"], m["stone_smooth"]
    oc = math.pi / 8
    mb.prism((0, 0, 0), 4.3, 4.3, 0.22, 8, sm, texel=1.5, rot_offset=oc)
    mb.ring_wall((0, 0, 0.22), 4.0, 3.62, 0.0, 0.6, 8, mar, sm, texel=1.5, rot_offset=oc)
    mb.ring_wall((0, 0, 0.82), 4.1, 3.55, 0.0, 0.12, 8, sm, sm, texel=1.0, rot_offset=oc)
    mb.disc((0, 0, 0.24), 3.65, 8, dark, uv_scale=3.0, rot_offset=oc)
    # Socle central à deux tambours, gargouilles de bronze.
    mb.prism((0, 0, 0.22), 1.75, 1.6, 1.0, 8, mar, texel=1.5, rot_offset=oc)
    mb.prism((0, 0, 1.22), 1.75, 1.75, 0.16, 8, sm, texel=1.0, rot_offset=oc)
    mb.prism((0, 0, 1.38), 1.25, 1.2, 1.0, 8, mar, texel=1.5, rot_offset=oc)
    mb.prism((0, 0, 2.38), 1.35, 1.35, 0.14, 8, sm, texel=1.0, rot_offset=oc)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        rot = Matrix.Rotation(a, 3, "Z")
        mb.box(d * 1.3 + UP * 1.95, (0.4, 0.34, 0.36), m["bronze"], rot=rot, texel=0.5)
        mb.prism(d * 1.55 + UP * 1.85, 0.1, 0.08, 0.06, 6, m["bronze"])
        mb.tube([d * 1.4 + UP * 1.92, d * 1.62 + UP * 1.9], [0.07, 0.06], 6, m["bronze"])
    # Piédestal : base, dé, corniche, plaques dorées.
    wbox(mb, (0, 0, 2.62), (1.9, 1.9, 0.34), sm, texel=1.0)
    wbox(mb, (0, 0, 3.5), (1.5, 1.5, 1.4), mar, texel=1.5)
    wbox(mb, (0, 0, 4.3), (1.9, 1.9, 0.22), sm, texel=1.0)
    wbox(mb, (0, 0, 4.47), (1.3, 1.3, 0.12), sm, texel=1.0)
    for k in range(4):
        a = k * math.pi / 2 - math.pi / 2
        w = Wall(mb, Vector((math.cos(a), math.sin(a), 0)) * 0.75, (math.cos(a), math.sin(a), 0))
        w.box(0.0, 3.55, (0.9, 0.04, 0.6), m["gold_trim"], d=0.02)
        w.box(0.0, 3.55, (0.7, 0.04, 0.04), m["bronze"], d=0.045)
    with Xf(mb, T(0, 0, 4.53) @ R(0.0, "Z") @ S(1.75)):
        mb.box((0, 0, 0.03), (0.75, 0.75, 0.06), m["bronze"], texel=0.5)
        build_knight(mb, m)
    mb.build("monument")

    # Nappe annulaire : couronne entre le socle et le muret (le socle émerge de l'eau).
    water = MeshBuilder()
    ring_o, ring_i = [], []
    for s in range(17):
        a = oc + s / 16 * TAU
        ring_o.append(water.add_vert((math.cos(a) * 3.66, math.sin(a) * 3.66, 0.72)))
        ring_i.append(water.add_vert((math.cos(a) * 1.6, math.sin(a) * 1.6, 0.72)))
    for s in range(16):
        water.add_face((ring_i[s], ring_o[s], ring_o[s + 1], ring_i[s + 1]),
                       ((0.8, s / 4), (2.6, s / 4), (2.6, (s + 1) / 4), (0.8, (s + 1) / 4)), m["water"])
    water.build("monument_water")

    # Filets d'eau des gargouilles : rubans courbes, v = 1 en haut, 0 en bas (défilement).
    fall = MeshBuilder()
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        pts = []
        for i in range(7):
            t = i / 6
            pts.append(d * (1.66 + 0.75 * t) + UP * (1.9 - 1.2 * t * t))
        for i in range(6):
            w0, w1 = 0.07 + 0.05 * i / 6, 0.07 + 0.05 * (i + 1) / 6
            p, q = pts[i], pts[i + 1]
            fall.add_face([fall.add_vert(p - side * w0), fall.add_vert(p + side * w0), fall.add_vert(q + side * w1),
                           fall.add_vert(q - side * w1)],
                          ((0, 1 - i / 6), (1, 1 - i / 6), (1, 1 - (i + 1) / 6), (0, 1 - (i + 1) / 6)), m["water"])
    fall.build("monument_water_fall")


# ---------------------------------------------------------------------------
# Château de Gludio
# ---------------------------------------------------------------------------

def round_turret(mb, m, cx, cy, r, h, sides=12, base=0.2, slits=True):
    st, sm = m["castle_stone"], m["stone_smooth"]
    ro = math.pi / sides
    mb.prism((cx, cy, 0), r + base, r, 1.4, sides, st, texel=2.0, cap_top=False, rot_offset=ro)
    mb.prism((cx, cy, 1.4), r, r, h - 1.4, sides, st, texel=2.0, cap_top=False, rot_offset=ro)
    for z in (h * 0.45, h - 0.3):
        mb.prism((cx, cy, z), r + 0.12, r + 0.12, 0.2, sides, sm, texel=1.0, cap_top=False, rot_offset=ro)
    if slits:
        ap = r * math.cos(math.pi / sides)
        for k in range(sides):
            if k % 3:
                continue
            a = (k + 0.5) / sides * TAU
            for z in (h * 0.3, h * 0.62):
                mb.box((cx + math.cos(a) * (ap + 0.005), cy + math.sin(a) * (ap + 0.005), z), (0.02, 0.15, 0.9),
                       m["shadow_dark"], rot=Matrix.Rotation(a, 3, "Z"))


def build_castle_keep(m):
    """Donjon de Gludio (emprise 22 x 22) : corps 18 x 18 haut de 22 m, étage supérieur en
    retrait coiffé d'un pavillon d'ardoise, quatre tourelles d'angle à poivrières, porche
    crénelé et grande porte en façade (-Y), fenêtres, bannières rouges et bleues."""
    mb = MeshBuilder()
    st, sm = m["castle_stone"], m["stone_smooth"]
    B, H = 9.0, 22.0
    mb.prism((0, 0, 0), (B + 0.4) * math.sqrt(2), B * math.sqrt(2), 1.6, 4, st, texel=2.0, cap_top=False,
             rot_offset=math.pi / 4)
    wbox(mb, (0, 0, 1.6 + (H - 1.6) / 2), (2 * B, 2 * B, H - 1.6), st, skip=("-z",))
    for z in (8.0, 14.0):
        wbox(mb, (0, 0, z), (2 * B + 0.25, 2 * B + 0.25, 0.25), sm, texel=1.0)
    # Mâchicoulis : bandeau en encorbellement sur consoles, parapet crénelé.
    wbox(mb, (0, 0, H - 0.3), (2 * B + 0.9, 2 * B + 0.9, 0.6), st)
    for k in range(-8, 9):
        for (x, y, sx, sy) in ((k, -B - 0.22, 0.3, 0.45), (k, B + 0.22, 0.3, 0.45), (-B - 0.22, k, 0.45, 0.3),
                               (B + 0.22, k, 0.45, 0.3)):
            if abs(x) > B - 0.6 and abs(y) > B - 0.6:
                continue
            wbox(mb, (x, y, H - 0.9), (sx, sy, 0.6), sm, texel=1.0)
    parapet_rect(mb, 0, 0, 2 * B + 0.9, 2 * B + 0.9, H, st, sm)
    # Étage supérieur en retrait + pavillon d'ardoise.
    U = 5.5
    wbox(mb, (0, 0, H + 2.2), (2 * U, 2 * U, 4.4), st, skip=("-z",))
    wbox(mb, (0, 0, H + 4.5), (2 * U + 0.4, 2 * U + 0.4, 0.25), sm, texel=1.0)
    mb.prism((0, 0, H + 4.6), (U + 0.6) * math.sqrt(2), 0.08, 6.5, 4, m["roof_slate"], texel=1.5, cap_top=False,
             cap_bottom=True, rot_offset=math.pi / 4)
    mb.prism((0, 0, H + 10.9), 0.1, 0.02, 1.8, 6, m["iron"], texel=0.5)
    mb.box((0.55, 0, H + 12.2), (1.0, 0.03, 0.55), m["cloth_red"])
    for n in ((0, -1, 0), (0, 1, 0), (1, 0, 0), (-1, 0, 0)):
        w = Wall(mb, Vector(n) * U, n)
        for u in (-2.6, 0.0, 2.6):
            lancet(w, m, u, H + 1.0, 0.8, 2.0, sm, t=0.16)
    # Tourelles d'angle à poivrière, fanions alternés.
    TR, TC, TH = 2.5, 8.4, 25.0
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        cx, cy = sx * TC, sy * TC
        round_turret(mb, m, cx, cy, TR, TH, base=0.2)
        mb.prism((cx, cy, TH - 0.1), TR, TR + 0.35, 0.5, 12, sm, texel=1.0, cap_top=True, rot_offset=math.pi / 12)
        cone_roof(mb, m, cx, cy, TH + 0.4, TR + 0.6, 6.0, sides=12, flag="cloth_blue" if i % 2 else "cloth_red")
    # Fenêtres des quatre faces, meurtrières basses.
    for n in ((0, -1, 0), (0, 1, 0), (1, 0, 0), (-1, 0, 0)):
        w = Wall(mb, Vector(n) * B, n)
        for u in (-4.6, 0.0, 4.6):
            if not (n[1] == -1 and u == 0.0):
                lancet(w, m, u, 9.3, 1.1, 3.0, sm)
            lancet(w, m, u, 15.0, 1.1, 3.4, sm)
            w.box(u, 4.5, (0.16, 0.02, 1.2), m["shadow_dark"], d=0.01)
        if n[1] == -1:
            for u, cloth in ((-2.3, "cloth_red"), (2.3, "cloth_red")):
                banner(w, m, u, 20.4, 6.8, cloth, trim="cloth_cream", width=1.5)
        else:
            banner(w, m, 0.0, 13.6, 5.0, "cloth_blue", trim="cloth_cream", width=1.4)
    # Porche crénelé et grande porte.
    PW, PD, PH = 7.6, 1.8, 10.0
    py = -B - PD / 2
    wbox(mb, (0, py, PH / 2), (PW, PD, PH), st, skip=("-z",))
    wbox(mb, (0, py, PH - 0.2), (PW + 0.4, PD + 0.4, 0.4), sm, texel=1.0)
    parapet_rect(mb, 0, py - 0.1, PW + 0.4, PD + 0.6, PH, st, sm, t=0.4, step=1.5)
    porch = Wall(mb, (0, -B - PD, 0), (0, -1, 0))
    arched_door(porch, m, 0.0, 0.0, 3.6, 6.2, sm, orders=2, leaf="planks_old")
    porch.box(0.0, 7.9, (1.2, 0.1, 0.9), m["cloth_red"], d=0.05)
    porch.box(0.0, 7.9, (0.5, 0.1, 0.4), m["cloth_cream"], d=0.09)
    for s in (-1, 1):
        bv.wall_lantern(porch, m, s * 2.9, 3.4)
        porch.box(s * 2.9, 7.4, (0.14, 0.02, 1.0), m["shadow_dark"], d=0.01)
    return mb.build("castle_keep")


def build_castle_wall(m):
    """Courtine de 4 m (X) x 3,6 m (Y), ~10 m : glacis, mur, cordon, parapets crénelés des
    deux côtés, chemin de ronde ; extrémités ouvertes (tronçons mis bout à bout)."""
    mb = MeshBuilder()
    st, sm = m["castle_stone"], m["stone_smooth"]
    L, Tk, H = 4.0, 3.6, 10.0
    mb.box((0, 0, 0.75), (L, Tk + 0.2, 1.5), st, texel=2.0, skip=("+x", "-x", "-z"))
    mb.box((0, 0, 1.5 + (H - 1.5) / 2), (L, Tk, H - 1.5), st, texel=2.0, skip=("+x", "-x", "-z", "+z"))
    mb.box((0, 0, 5.5), (L, Tk + 0.16, 0.22), sm, texel=1.0, skip=("+x", "-x"))
    mb.box((0, 0, H - 0.2), (L, Tk + 0.5, 0.4), sm, texel=1.0, skip=("+x", "-x"))
    for side in (-1, 1):
        y = side * (Tk / 2 + 0.25 - 0.22)
        mb.box((0, y, H + 0.35), (L, 0.44, 0.7), st, texel=2.0, skip=("+x", "-x", "-z"))
        for x in (-1.0, 1.0):
            mb.box((x, y, H + 0.7 + 0.5), (1.0, 0.44, 1.0), st, texel=2.0, skip=("-z",))
            mb.box((x, y, H + 1.74), (1.08, 0.52, 0.08), sm, texel=1.0)
            mb.box((x, side * (Tk / 2 + 0.25 + 0.005), H + 1.1), (0.12, 0.02, 0.55), m["shadow_dark"])
        for x in (-1.0, 1.0):
            mb.box((x, side * (Tk / 2 + 0.005), 3.6), (0.14, 0.02, 0.9), m["shadow_dark"])
            mb.box((x, side * (Tk / 2 + 0.005), 7.3), (0.14, 0.02, 0.9), m["shadow_dark"])
    mb.box((0, 0, H + 0.02), (L, Tk, 0.04), sm, texel=1.5, skip=("+x", "-x", "-z"))
    return mb.build("castle_wall")


def build_castle_tower(m):
    """Grosse tour ronde (rayon 4,5, ~15 m) : talus, cordons, meurtrières, parapet crénelé,
    tourelle intérieure coiffée d'un toit conique d'ardoise ; poterne côté intérieur (+Y)."""
    mb = MeshBuilder()
    st, sm = m["castle_stone"], m["stone_smooth"]
    Rr, H, sides = 4.5, 15.0, 20
    ro = math.pi / sides
    mb.prism((0, 0, 0), Rr + 0.1, Rr, 1.6, sides, st, texel=2.0, cap_top=False, rot_offset=ro)
    mb.prism((0, 0, 1.6), Rr, Rr, H - 1.6, sides, st, texel=2.0, cap_top=False, rot_offset=ro)
    mb.prism((0, 0, 6.0), Rr + 0.12, Rr + 0.12, 0.22, sides, sm, texel=1.0, cap_top=False, rot_offset=ro)
    mb.prism((0, 0, H), Rr, Rr + 0.4, 0.5, sides, sm, texel=1.0, cap_top=False, rot_offset=ro)
    for k in range(sides):
        a = (k + 0.5) / sides * TAU
        mb.box((math.cos(a) * (Rr + 0.15), math.sin(a) * (Rr + 0.15), H - 0.25), (0.3, 0.35, 0.5), sm,
               rot=Matrix.Rotation(a, 3, "Z"), texel=0.6)
    parapet_ring(mb, 0, 0, Rr + 0.4, H + 0.5, st, sm, sides=sides, count=10, t=0.45)
    mb.disc((0, 0, H + 0.5), Rr - 0.05, sides, sm, uv_scale=4.0, rot_offset=ro)
    ap = Rr * math.cos(math.pi / sides)
    for k in range(sides):
        if k % 4 != 1:
            continue
        a = (k + 0.5) / sides * TAU
        for z in (4.0, 9.0, 12.5):
            mb.box((math.cos(a) * (ap + 0.005), math.sin(a) * (ap + 0.005), z), (0.02, 0.16, 1.0), m["shadow_dark"],
                   rot=Matrix.Rotation(a, 3, "Z"))
    mb.box((0, ap + 0.01, 1.5), (1.2, 0.02, 2.4), m["planks_old"])
    # Tourelle intérieure et toit conique.
    mb.prism((0, 0, H + 0.5), 3.1, 3.1, 2.3, 16, st, texel=2.0, cap_top=False, rot_offset=math.pi / 16)
    mb.prism((0, 0, H + 2.8), 3.1, 3.35, 0.25, 16, sm, texel=1.0, cap_top=False, rot_offset=math.pi / 16)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        mb.box((math.cos(a) * 3.09, math.sin(a) * 3.09, H + 1.7), (0.02, 0.5, 0.8), m["window_glass"],
               rot=Matrix.Rotation(a, 3, "Z"))
    cone_roof(mb, m, 0, 0, H + 3.0, 3.9, 6.5, sides=16, flag="cloth_red")
    return mb.build("castle_tower")


def build_castle_gatehouse(m):
    """Châtelet (16 x 8 m, ~14 m) : tours carrées 5,5 x 8 en x = ±5,25, passage voûté de 5 m
    selon Y (praticable), herse levée, vantaux ouverts côté intérieur (+Y), bannières."""
    mb = MeshBuilder()
    st, sm, dark = m["castle_stone"], m["stone_smooth"], m["shadow_dark"]
    TW, TD, TH = 5.5, 8.0, 14.0
    OX = 5.25
    PW, AH = 5.0, 10.5
    r, SZ = PW / 2, 4.3
    for sx in (-1, 1):
        x = sx * OX
        wbox(mb, (x, 0, 0.6), (TW, TD + 0.2, 1.2), st, skip=("-z",))
        wbox(mb, (x, 0, 1.2 + (TH - 1.2) / 2), (TW, TD, TH - 1.2), st, skip=("-z", "+z"))
        wbox(mb, (x, 0, 7.0), (TW, TD + 0.2, 0.22), sm, texel=1.0)
        wbox(mb, (x, 0, TH + 0.2), (TW + 0.4, TD + 0.4, 0.4), sm, texel=1.0)
        for k in range(-3, 4):
            for y in (-TD / 2 - 0.12, TD / 2 + 0.12):
                wbox(mb, (x + k * 0.75, y, TH - 0.3), (0.3, 0.3, 0.5), sm, texel=1.0)
        parapet_rect(mb, x, 0, TW + 0.4, TD + 0.4, TH + 0.4, st, sm, t=0.42, step=1.6)
        mb.box((x, 0, TH + 0.42), (TW - 0.5, TD - 0.5, 0.04), sm, texel=1.5)
        mb.prism((x + sx * 1.6, 2.6, TH + 0.4), 0.08, 0.03, 4.0, 6, m["iron"])
        mb.box((x + sx * 1.6 + 0.55, 2.6, TH + 3.95), (1.1, 0.03, 0.6), m["cloth_red"])
        for ny in (-1, 1):
            w = Wall(mb, (x, ny * TD / 2, 0), (0, ny, 0))
            for u in (-1.4, 1.4):
                w.box(u, 4.0, (0.15, 0.02, 0.9), dark, d=0.005)
            lancet(w, m, 0.0, 9.0, 0.9, 2.2, sm, t=0.16)
            banner(w, m, 0.0, 8.0 if ny > 0 else 7.9, 4.6, "cloth_red" if ny < 0 else "cloth_blue",
                   trim="cloth_cream", width=1.4, d=0.07)
        side = Wall(mb, (x + sx * TW / 2, 0, 0), (sx, 0, 0))
        for u in (-2.0, 2.0):
            side.box(u, 5.0, (0.15, 0.02, 0.9), dark, d=0.005)
            lancet(side, m, u, 9.0, 0.9, 2.2, sm, t=0.16)
    # Corps central : faces percées de l'arc, intrados, dessus crénelé.
    segs = 14
    arc = [(r * math.cos(math.pi - i / segs * math.pi), SZ + r * math.sin(math.pi - i / segs * math.pi))
           for i in range(segs + 1)]
    for sy in (-1, 1):
        y = sy * TD / 2
        nrm = (0, sy, 0)
        for (ax, az), (bx, bz) in zip(arc[:-1], arc[1:]):
            pts = [(ax, y, az), (bx, y, bz), (bx, y, AH), (ax, y, AH)]
            face(mb, pts, nrm, st, bv.planar_uv(pts, Vector((1, 0, 0)), UP, 2.0))
        for i in range(segs + 1):
            ang = math.pi - i / segs * math.pi
            c = Vector((math.cos(ang) * (r + 0.25), sy * (TD / 2 + 0.05), SZ + math.sin(ang) * (r + 0.25)))
            mb.box(c, (0.5, 0.12, 0.55), sm, rot=Matrix.Rotation(-ang, 3, "Y"), texel=0.6)
        w = Wall(mb, (0, y, 0), (0, sy, 0))
        w.box(0.0, AH - 1.2, (1.6, 0.06, 1.2), m["cloth_blue" if sy < 0 else "cloth_red"], d=0.05)
        w.box(0.0, AH - 1.2, (0.6, 0.06, 0.6), m["cloth_cream"], d=0.08)
    for (ax, az), (bx, bz) in zip(arc[:-1], arc[1:]):
        mid = Vector(((ax + bx) / 2, 0, (az + bz) / 2 - SZ))
        pts = [(ax, -TD / 2, az), (bx, -TD / 2, bz), (bx, TD / 2, bz), (ax, TD / 2, az)]
        face(mb, pts, -mid, sm, [(0, 0), (0.3, 0), (0.3, TD / 1.5), (0, TD / 1.5)])
    pts = [(-r, -TD / 2, AH), (r, -TD / 2, AH), (r, TD / 2, AH), (-r, TD / 2, AH)]
    face(mb, pts, (0, 0, 1), sm, bv.planar_uv(pts, Vector((1, 0, 0)), Vector((0, 1, 0)), 1.5))
    for sy in (-1, 1):
        y = sy * (TD / 2 - 0.2)
        wbox(mb, (0, y, AH + 0.35), (PW, 0.42, 0.7), st, skip=("-z", "+x", "-x"))
        for mx in (-1.6, 0.0, 1.6):
            wbox(mb, (mx, y, AH + 0.7 + 0.45), (0.9, 0.42, 0.9), st, skip=("-z",))
            wbox(mb, (mx, y, AH + 1.64), (0.98, 0.5, 0.08), sm, texel=1.0)
    wbox(mb, (0, 0, 0.02), (PW, TD, 0.04), m["stone_bricks"], texel=1.0, skip=("-z",))
    # Arcs doubleaux sous la voûte.
    for yb in (-TD / 2 + 0.6, TD / 2 - 0.6):
        for i in range(segs + 1):
            ang = math.pi - i / segs * math.pi
            c = Vector((math.cos(ang) * (r - 0.12), yb, SZ + math.sin(ang) * (r - 0.12)))
            mb.box(c, (0.55, 0.5, 0.26), sm, rot=Matrix.Rotation(-ang, 3, "Y"), texel=0.6)
        for sx in (-1, 1):
            wbox(mb, (sx * (r - 0.12), yb, SZ / 2), (0.26, 0.5, SZ), sm, texel=1.0)
    # Herse levée et vantaux ouverts côté intérieur.
    iron = m["iron"]
    py = -TD / 2 + 1.3
    for i in range(9):
        x = -r + 0.3 + i * (PW - 0.6) / 8
        top = SZ + math.sqrt(max(r * r - x * x, 0.0)) - 0.15
        mb.box((x, py, (5.3 + top) / 2), (0.09, 0.09, top - 5.3), iron, texel=0.5)
        mb.prism((x, py, 5.1), 0.01, 0.06, 0.2, 4, iron)
    for z in (5.4, 6.0):
        half = math.sqrt(max(r * r - (z - SZ) ** 2, 0.0)) - 0.25
        mb.box((0, py, z), (half * 2, 0.07, 0.08), iron, texel=0.5)
    for sx in (-1, 1):
        mb.box((sx * (r - 0.4), TD / 2 - 1.8, 2.1), (0.14, 2.3, 4.2), m["planks_old"], texel=1.0)
        for z in (0.8, 2.2, 3.6):
            mb.box((sx * (r - 0.48), TD / 2 - 1.8, z), (0.03, 2.25, 0.14), iron, texel=0.5)
    return mb.build("castle_gatehouse")


# ---------------------------------------------------------------------------
# Ruines
# ---------------------------------------------------------------------------

def column_base(mb, m, size=1.3, h=0.4):
    wbox(mb, (0, 0, h / 2), (size, size, h), m["ruin_smooth"], texel=1.0, skip=("-z",))
    mb.prism((0, 0, h), 0.62, 0.55, 0.2, 16, m["ruin_smooth"], texel=1.0)
    return h + 0.2


def build_ruin_column(m):
    mb = MeshBuilder()
    sm = m["ruin_smooth"]
    z = column_base(mb, m)
    fluted(mb, (0, 0), 0.5, 0.44, z, 5.75, 12, sm, depth=0.05, texel=1.2)
    mb.prism((0, 0, 5.75), 0.46, 0.66, 0.4, 16, sm, texel=1.0, cap_top=False)
    wbox(mb, (0, 0, 6.32), (1.4, 1.4, 0.35), sm, texel=1.0)
    moss_patch(mb, m, (0.15, 0.1, 6.505), (1.1, 0.9, 0.04))
    moss_patch(mb, m, (-0.3, 0.35, 0.405), (0.6, 0.55, 0.03))
    mb.box((0.55, -0.55, 6.32), (0.4, 0.4, 0.4), m["shadow_dark"], rot=Matrix.Rotation(0.78, 3, "Z"))
    return mb.build("ruin_column")


def build_ruin_column_broken(m):
    mb = MeshBuilder()
    sm = m["ruin_smooth"]
    z = column_base(mb, m)
    fluted(mb, (0, 0), 0.5, 0.47, z, 2.2, 12, sm, depth=0.05, texel=1.2, cap=sm,
           top_fn=lambda a: 2.0 + 0.28 * math.sin(2 * a + 1.0) + 0.1 * math.sin(5 * a))
    with Xf(mb, T(0.78, -0.82, 0.36) @ R(0.75, "Z") @ R(math.pi / 2 + 0.12, "Y") @ T(0, 0, -0.35)):
        fluted(mb, (0, 0), 0.42, 0.42, 0.0, 0.7, 12, sm, depth=0.045, texel=1.2, cap=sm)
        mb.disc((0, 0, 0.0), 0.4, 12, sm, z_up=False)
        moss_arc(mb, m, 0.435, 0.12, 0.5, math.pi, 0.7, random.Random(4))
    moss_patch(mb, m, (-0.2, -0.3, 0.405), (0.7, 0.5, 0.03))
    return mb.build("ruin_column_broken")


def build_ruin_column_fallen(m):
    mb = MeshBuilder()
    sm = m["ruin_smooth"]
    rng = random.Random(17)
    r = 0.47
    zc = r - 0.06
    # Chapiteau renversé à l'extrémité -X.
    mb.box((-2.32, 0.0, 0.58), (0.34, 1.18, 1.18), sm, rot=Matrix.Rotation(0.12, 3, "X"), texel=1.0)
    with Xf(mb, T(-2.15, 0, 0.58) @ R(math.pi / 2, "Y")):
        mb.prism((0, 0, 0), 0.62, 0.45, 0.38, 16, sm, texel=1.0, cap_top=False)
    drums = [(-1.78, 1.5, 0.0, None), (-0.18, 1.32, 0.07, None), (1.24, 1.16, -0.05, True)]
    for x0, length, yaw, broken in drums:
        top = None
        if broken:
            top = (lambda a: length - 0.2 + 0.16 * math.sin(2 * a + 0.4) + 0.06 * math.sin(5 * a))
        with Xf(mb, T(x0, 0, zc) @ R(yaw, "Z") @ R(math.pi / 2, "Y")):
            fluted(mb, (0, 0), r, r * 0.985, 0.0, length, 12, sm, depth=0.045, texel=1.2, cap=sm, top_fn=top)
            mb.disc((0, 0, 0.0), r - 0.03, 12, sm, z_up=False)
            # Haut du fût couché = -X local (rotation de 90 degrés autour de Y).
            moss_arc(mb, m, r + 0.015, length * rng.uniform(0.1, 0.3), length * rng.uniform(0.55, 0.8),
                     math.pi + rng.uniform(-0.3, 0.3), 0.75, rng)
    return mb.build("ruin_column_fallen")


def ruin_wall(m, name, base, terms, thick=1.0, seed=1, plinth=True, loose=4, slices=16):
    """Mur ruiné de 4 m (X) découpé en tranches dont la hauteur suit un profil érodé
    base + somme(a * sin(k * pi * t)) (t de 0 à 1 : mêmes hauteurs aux deux extrémités, les
    tronçons se raccordent bout à bout), parements légèrement décalés, mousse sur les
    arêtes, pierres déchaussées au sommet et blocs tombés au pied."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    st, sm = m["ruin_stone"], m["ruin_smooth"]
    sw = 4.0 / slices
    if plinth:
        wbox(mb, (0, 0, 0.22), (4.0, thick + 0.16, 0.44), sm, texel=1.0, skip=("-z",))
    for i in range(slices):
        x = -2.0 + sw * (i + 0.5)
        t = (i + 0.5) / slices
        h = base + sum(a * math.sin(k * math.pi * t) for k, a in terms)
        if 0 < i < slices - 1:
            h += rng.uniform(-0.12, 0.12)
        th = thick - (rng.uniform(0.0, 0.08) if 0 < i < slices - 1 else 0.0)
        wbox(mb, (x, rng.uniform(-0.02, 0.02), h / 2), (sw, th, h), st, skip=("-z",))
        if rng.random() < 0.3:
            bw = rng.uniform(0.3, 0.45)
            bh = rng.uniform(0.16, 0.26)
            mb.box((x + rng.uniform(-0.05, 0.05), rng.uniform(-0.15, 0.15), h + bh / 2 - 0.04),
                   (bw, rng.uniform(0.45, 0.7) * thick, bh), sm,
                   rot=Matrix.Rotation(rng.uniform(-0.3, 0.3), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.1, 0.1), 3,
                                                                                         "X"), texel=1.0)
        elif rng.random() < 0.55:
            moss_patch(mb, m, (x, rng.uniform(-0.08, 0.08), h + 0.015),
                       (sw * 1.02, th * rng.uniform(0.6, 0.9), 0.04))
        # Pierres saillantes du parement.
        for side in (-1, 1):
            if h > 0.9 and rng.random() < 0.3:
                z = rng.uniform(0.6, h - 0.3)
                mb.box((x + rng.uniform(-0.05, 0.05), side * (th / 2 + 0.03), z), (rng.uniform(0.3, 0.45), 0.1, 0.24),
                       sm, texel=0.6)
    for k in range(loose):
        side = 1 if k % 2 == 0 else -1
        size = (rng.uniform(0.35, 0.6), rng.uniform(0.3, 0.45), rng.uniform(0.22, 0.35))
        mb.box((rng.uniform(-1.7, 1.7), side * (thick / 2 + rng.uniform(0.0, 0.12)), size[2] / 2 - 0.03), size,
               st if k % 3 else sm,
               rot=Matrix.Rotation(rng.uniform(0, math.pi), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.2, 0.2), 3, "X"),
               texel=1.0)
    return mb.build(name)


def build_ruin_arch(m):
    """Arche brisée : piliers 1,2 x 1,2 en x = ±2,4 ; l'arc ne tient plus que côté gauche, le
    pilier droit est rompu, ses claveaux gisent à l'extérieur (passage central dégagé)."""
    rng = random.Random(9)
    mb = MeshBuilder()
    st, sm = m["ruin_stone"], m["ruin_smooth"]
    PX, PH = 2.4, 4.2
    for sx, h in ((-1, PH), (1, 3.1)):
        x = sx * PX
        wbox(mb, (x, 0, 0.25), (1.4, 1.4, 0.5), sm, texel=1.0, skip=("-z",))
        wbox(mb, (x, 0, 0.5 + (h - 0.5) / 2), (1.2, 1.2, h - 0.5), st, skip=("-z",))
        if sx < 0:
            wbox(mb, (x, 0, h + 0.15), (1.45, 1.45, 0.3), sm, texel=1.0)
            moss_patch(mb, m, (x + 0.35, 0.1, h + 0.31), (0.6, 1.0, 0.04))
        else:
            for k in range(3):
                mb.box((x + rng.uniform(-0.25, 0.25), rng.uniform(-0.3, 0.3), h + 0.15 + k * 0.05),
                       (rng.uniform(0.4, 0.7), rng.uniform(0.4, 0.7), 0.32), st,
                       rot=Matrix.Rotation(rng.uniform(-0.4, 0.4), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.15, 0.15),
                                                                                              3, "X"), texel=1.0)
            moss_patch(mb, m, (x, 0, h + 0.03), (1.0, 1.0, 0.05))
    spring = PH + 0.3
    segs = 9
    for i in range(6):
        th = math.pi - (i + 0.5) / segs * math.pi
        rr = PX
        c = Vector((math.cos(th) * rr, rng.uniform(-0.04, 0.04), spring + math.sin(th) * rr))
        phi = -(th + math.pi / 2)
        tangent_len = rr * math.pi / segs
        size = (tangent_len * 0.98, 1.0, 1.15 if i % 2 else 1.05)
        mb.box(c, size, st if i % 2 else sm, rot=Matrix.Rotation(phi + rng.uniform(-0.04, 0.04), 3, "Y"), texel=1.0)
        if i < 5:
            top = c + Vector((math.cos(th), 0, math.sin(th))) * (size[2] / 2 + 0.02)
            if rng.random() < 0.6:
                moss_patch(mb, m, top, (tangent_len * 0.8, 0.8, 0.04), rot=Matrix.Rotation(phi, 3, "Y"))
    # Claveaux tombés, à l'extérieur du pilier droit.
    for k in range(4):
        mb.box((PX + 1.0 + rng.uniform(0.0, 0.6), rng.uniform(-1.0, 1.0), 0.35), (0.8, 1.0, 0.7), st if k % 2 else sm,
               rot=Matrix.Rotation(rng.uniform(0, math.pi), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.5, 0.5), 3, "X"),
               texel=1.0)
    return mb.build("ruin_arch")


def build_ruin_statue(m):
    """Statue géante décapitée (~7 m) sur piédestal 3 x 3 : silhouette drapée, mains jointes sur
    une épée pointe en bas, bras gauche rompu ; la tête gît sur le piédestal."""
    mb = MeshBuilder()
    st, sm = m["ruin_stone"], m["ruin_smooth"]
    wbox(mb, (0, 0, 0.25), (3.0, 3.0, 0.5), sm, texel=1.0, skip=("-z",))
    wbox(mb, (0, 0, 1.25), (2.5, 2.5, 1.5), st, skip=("-z",))
    wbox(mb, (0, 0, 2.1), (2.8, 2.8, 0.2), sm, texel=1.0)
    moss_patch(mb, m, (0.8, 0.9, 2.21), (1.0, 0.8, 0.04))
    moss_patch(mb, m, (-1.1, -0.6, 0.51), (0.6, 1.2, 0.03))
    z0 = 2.2
    fluted(mb, (0, 0), 0.98, 0.64, z0, z0 + 3.1, 9, sm, depth=0.1, texel=1.5)
    mb.prism((0, 0, z0 + 3.1), 0.64, 0.74, 0.65, 10, sm, texel=1.2)
    mb.box((0, 0, z0 + 3.95), (1.75, 0.82, 0.42), sm, texel=1.0)
    for sx in (-1, 1):
        mb.prism((sx * 0.85, 0, z0 + 3.74), 0.36, 0.3, 0.42, 8, sm, texel=1.0)
    fluted(mb, (0, 0), 0.28, 0.26, z0 + 4.16, z0 + 4.6, 5, sm, depth=0.03, cap=st,
           top_fn=lambda a: z0 + 4.42 + 0.12 * math.sin(2 * a + 0.5))
    # Bras droit replié, mains jointes sur la garde ; bras gauche rompu au coude.
    hands = Vector((0.0, -0.78, z0 + 2.45))
    mb.tube([(0.86, 0, z0 + 3.75), (1.0, -0.25, z0 + 2.9), (0.35, -0.7, z0 + 2.5), hands], [0.26, 0.24, 0.2, 0.2],
            8, sm)
    mb.tube([(-0.86, 0, z0 + 3.75), (-1.02, -0.18, z0 + 3.0)], [0.26, 0.24], 8, sm, cap_top=True, cap_mat=st)
    mb.box(hands + UP * 0.25, (0.12, 0.12, 0.5), st, texel=0.6)
    mb.box(hands + UP * 0.02, (0.7, 0.14, 0.12), sm, texel=0.6)
    mb.box(hands - UP * 1.08 + Vector((0, 0.04, 0)), (0.22, 0.06, 2.1), sm, texel=0.6)
    # Tête tombée sur le piédestal, coiffe rompue.
    hc = Vector((0.92, -0.92, z0 + 0.36))
    blob(mb, hc, (0.36, 0.4, 0.38), sm, segs=10, rings=7)
    with Xf(mb, T(*hc) @ R(1.2, "X") @ R(0.4, "Y")):
        mb.prism((0, 0, 0.3), 0.3, 0.22, 0.3, 8, st, texel=0.6)
    mb.box(hc + Vector((0.12, -0.2, 0.25)), (0.12, 0.02, 0.06), m["shadow_dark"])
    mb.box(hc + Vector((-0.12, -0.25, 0.22)), (0.12, 0.02, 0.06), m["shadow_dark"])
    return mb.build("ruin_statue")


def build_ruin_rubble(m):
    rng = random.Random(21)
    mb = MeshBuilder()
    st, sm = m["ruin_stone"], m["ruin_smooth"]
    layers = [(7, 1.0, 0.0), (4, 0.6, 0.38), (2, 0.25, 0.72)]
    for count, radius, z in layers:
        for k in range(count):
            a = k / count * TAU + rng.uniform(-0.3, 0.3)
            d = rng.uniform(0.2, 1.0) * radius
            size = (rng.uniform(0.5, 0.85), rng.uniform(0.4, 0.65), rng.uniform(0.32, 0.5))
            mb.box((math.cos(a) * d, math.sin(a) * d, z + size[2] / 2 - 0.04), size, st if rng.random() < 0.6 else sm,
                   rot=Matrix.Rotation(rng.uniform(0, math.pi), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.35, 0.35), 3,
                                                                                          "X"), texel=1.0)
            if rng.random() < 0.35:
                moss_patch(mb, m, (math.cos(a) * d, math.sin(a) * d, z + size[2] - 0.02),
                           (size[0] * 0.7, size[1] * 0.7, 0.04), rot=Matrix.Rotation(rng.uniform(0, 3), 3, "Z"))
    with Xf(mb, T(0.55, 0.75, 0.33) @ R(2.4, "Z") @ R(math.pi / 2 + 0.15, "Y") @ T(0, 0, -0.35)):
        fluted(mb, (0, 0), 0.36, 0.36, 0.0, 0.7, 10, sm, depth=0.04, cap=sm)
        mb.disc((0, 0, 0.0), 0.34, 10, sm, z_up=False)
    mb.box((-0.2, 0.1, 1.05), (0.5, 0.42, 0.3), sm, rot=Matrix.Rotation(0.5, 3, "Z") @ Matrix.Rotation(0.3, 3, "Y"),
           texel=1.0)
    return mb.build("ruin_rubble")


def build_ruin_altar(m):
    """Autel sacrificiel à degrés (6 x 6) : trois gradins, table d'autel tachée, runes rouges
    lumineuses sur la plate-forme et les flancs de l'autel, quatre bornes rompues aux angles."""
    rng = random.Random(13)
    mb = MeshBuilder()
    st, sm, rune = m["ruin_stone"], m["ruin_smooth"], m["rune_red"]
    for i, (w, z) in enumerate(((6.0, 0.0), (4.8, 0.4), (3.6, 0.8))):
        wbox(mb, (0, 0, z + 0.2), (w, w, 0.4), st if i == 1 else sm, texel=1.5, skip=("-z",))
    wbox(mb, (0, 0, 1.7), (2.2, 1.2, 1.0), st, skip=("-z",))
    wbox(mb, (0, 0, 2.28), (2.45, 1.4, 0.16), sm, texel=1.0)
    for (x, y, sx, sy, a) in ((0.25, 0.05, 0.8, 0.45, 0.3), (-0.05, -0.1, 0.5, 0.35, -0.5), (0.6, -0.25, 0.3, 0.3, 0.9)):
        mb.box((x, y, 2.364), (sx, sy, 0.01), m["cloth_red"], rot=Matrix.Rotation(a, 3, "Z"))
    mb.box((1.103, -0.2, 2.0), (0.012, 0.22, 0.5), m["cloth_red"])
    # Rigole et runes.
    glyphs(mb, rng, rune, (0, 0), 1.55, 24, 1.205, size=0.24, square=True)
    for sy in (-1, 1):
        for k in range(5):
            x = -0.8 + k * 0.4
            mb.box((x, sy * 0.605, 1.65), (0.04, 0.012, 0.35), rune)
            mb.box((x + 0.08 * rng.choice((-1, 1)), sy * 0.605, 1.72), (0.16, 0.012, 0.04), rune)
    for sx in (-1, 1):
        mb.box((sx * 1.105, 0, 1.7), (0.012, 0.5, 0.04), rune)
        mb.box((sx * 1.105, 0, 1.7), (0.012, 0.04, 0.5), rune)
    for k in range(4):
        a = k * math.pi / 2
        mb.box((math.cos(a) * 2.1, math.sin(a) * 2.1, 0.802), (0.6, 0.05, 0.01), rune, rot=Matrix.Rotation(a + math.pi / 2, 3, "Z"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            h = rng.uniform(1.0, 1.9)
            wbox(mb, (sx * 2.6, sy * 2.6, 0.4 + h / 2), (0.6, 0.6, h), st, skip=("-z",))
            mb.box((sx * 2.6, sy * 2.6, 0.4 + h + 0.08), (0.5, 0.45, 0.2), sm,
                   rot=Matrix.Rotation(rng.uniform(-0.5, 0.5), 3, "Z") @ Matrix.Rotation(0.15, 3, "X"))
    moss_patch(mb, m, (-2.2, 1.8, 0.405), (1.2, 1.4, 0.03))
    moss_patch(mb, m, (1.9, -2.3, 0.405), (1.5, 0.8, 0.03))
    return mb.build("ruin_altar")


def build_ruin_skull(m):
    """Crâne cornu géant à demi enterré (~6,5 m, regard vers -Y) : boîte crânienne, museau,
    orbites et fosse nasale sombres cernées d'os, arcades, pommettes, crocs plantés dans le
    sol, deux grandes cornes recourbées vers l'avant ; rochers à demi enfouis autour."""
    mb = MeshBuilder()
    bone, dark = m["bone"], m["shadow_dark"]
    C = Vector((0, 0.3, 1.6))

    def skull_shape(d, p):
        q = Vector(p)
        if d.z > 0.45:
            q.z = C.z + (q.z - C.z) * 0.9
        if d.y > 0.2 and d.z > -0.2:
            q.y += 0.3 * d.y
        if d.y < -0.2:
            k = 1.0 - 0.18 * max(0.0, 0.3 - d.z) * min(1.0, (-d.y - 0.2) * 2)
            q.x = C.x + (q.x - C.x) * k
        q.z = max(q.z, -0.6)
        return q

    blob(mb, C, (2.4, 2.4, 2.3), bone, segs=18, rings=12, deform=skull_shape, texel=2.0)
    # Museau (maxillaire) et pommettes.
    blob(mb, (0, -1.55, 1.45), (1.45, 1.2, 1.0), bone, segs=14, rings=8, texel=2.0)
    for sx in (-1, 1):
        mb.tube([(sx * 0.7, -2.2, 1.55), (sx * 1.5, -1.75, 1.75), (sx * 2.15, -0.9, 1.9), (sx * 2.35, 0.0, 1.8)],
                [0.3, 0.34, 0.3, 0.24], 8, bone)
    # Orbites : creux sombres aplatis, cernés d'un bourrelet d'os, arcade épaisse au-dessus.
    for sx in (-1, 1):
        ec = Vector((sx * 0.95, -1.72, 2.4))
        n = Vector((sx * 0.45, -1.0, 0.15)).normalized()
        blob(mb, ec, (0.58, 0.16, 0.5), dark, segs=10, rings=6)
        side = Vector((n.y, -n.x, 0)).normalized()
        ring = [ec + n * 0.05 + side * math.cos(a) * 0.66 + UP * math.sin(a) * 0.58
                for a in (i / 10 * TAU for i in range(11))]
        mb.tube(ring, [0.15] * 11, 6, bone)
        mb.tube([ec + side * -0.85 + UP * 0.45 + n * 0.0, ec + UP * 0.72 + n * 0.12, ec + side * 0.85 + UP * 0.5],
                [0.28, 0.34, 0.28], 8, bone)
    # Fosse nasale.
    nc = Vector((0, -2.62, 1.82))
    blob(mb, nc, (0.3, 0.12, 0.42), dark, segs=8, rings=6)
    mb.tube([nc + Vector((-0.35, 0.05, -0.45)), nc + Vector((-0.4, 0.0, 0.1)), nc + Vector((0, -0.05, 0.55)),
             nc + Vector((0.4, 0.0, 0.1)), nc + Vector((0.35, 0.05, -0.45))], [0.12] * 5, 6, bone)
    # Crocs de la mâchoire supérieure, plantés dans le sol.
    for k in range(9):
        t = (k - 4) / 4
        x = t * 1.2
        y = -2.45 + 0.6 * t * t
        big = k in (1, 7)
        h = 1.15 if big else 0.75
        mb.prism((x, y, 0.75 - h), 0.03, 0.2 if big else 0.14, h, 6, bone, texel=0.6, cap_top=False)
    # Cornes : des tempes vers l'extérieur, relevées puis ramenées vers l'avant.
    for sx in (-1, 1):
        pts = [Vector((sx * 1.8, 0.1, 3.0)), Vector((sx * 2.95, 0.15, 3.45)), Vector((sx * 3.65, -0.15, 4.3)),
               Vector((sx * 3.8, -0.65, 5.3)), Vector((sx * 3.45, -1.25, 6.1)), Vector((sx * 2.85, -1.75, 6.5)),
               Vector((sx * 2.3, -2.05, 6.45))]
        radii = [0.8, 0.7, 0.58, 0.45, 0.32, 0.18, 0.04]
        for p in pts:
            p.x *= 0.92
        mb.tube(pts, radii, 10, bone, v_scale=0.7)
        for i in (1, 2, 3, 4):
            d = (pts[i + 1] - pts[i - 1]).normalized()
            mb.tube([pts[i] - d * 0.07, pts[i] + d * 0.07], [radii[i] + 0.05, radii[i] + 0.05], 10, m["rock"])
    # Fissures sombres sur le crâne.
    for (p, a) in (((0.6, -1.0, 3.6), 0.4), ((-0.9, -0.2, 3.8), -0.6), ((1.5, 0.8, 3.5), 1.2)):
        mb.box(p, (0.9, 0.04, 0.04), dark, rot=Matrix.Rotation(a, 3, "Z") @ Matrix.Rotation(-0.5, 3, "X"))
    # Rochers à demi enfouis autour de la base.
    rng = random.Random(3)
    for k in range(10):
        a = k / 10 * TAU + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a) * 2.9, math.sin(a) * 2.0 + 0.3, 0))
        if d.y < -1.2 and abs(d.x) < 2.2:
            continue
        blob(mb, d + UP * -0.2, (rng.uniform(0.45, 0.8), rng.uniform(0.4, 0.65), rng.uniform(0.35, 0.55)), m["rock"],
             segs=7, rings=4)
    return mb.build("ruin_skull")


# ---------------------------------------------------------------------------
# Marais de Cruma
# ---------------------------------------------------------------------------

def build_marsh_tree(name, m, seed, height, branches=5, moss=10):
    """Arbre mort des marais : tronc tordu à racines-contreforts, branches nues tombantes,
    mousse pendante (cartes alpha accrochées aux branches)."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    bark = m["bark_swamp"]
    lean = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized()
    side = Vector((-lean.y, lean.x, 0))
    n = 8
    trunk = []
    for i in range(n + 1):
        t = i / n
        off = lean * height * 0.16 * math.sin(t * math.pi * 0.9) + side * height * 0.06 * math.sin(t * math.pi * 2.0)
        trunk.append(Vector((0, 0, -0.15)) + off + UP * height * 0.72 * t)
    base_r = 0.11 + height * 0.042
    radii = [base_r * (1.45 if i == 0 else 1.0 - 0.72 * i / n) for i in range(n + 1)]
    mb.tube(trunk, radii, 9, bark, v_scale=0.45, twist=0.15)
    # Racines-contreforts.
    for k in range(6):
        a = k / 6 * TAU + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        mb.tube([d * base_r * 0.75 + UP * 0.6, d * base_r * 1.5 + UP * 0.16, d * base_r * 2.5 - UP * 0.12],
                [base_r * 0.5, base_r * 0.36, base_r * 0.14], 5, bark, v_scale=0.45)
    hangs = []

    def branch(start, direction, length, r, depth):
        path = [Vector(start)]
        d = Vector(direction).normalized()
        for _ in range(4):
            d = (d + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(-0.35, 0.1)))).normalized()
            path.append(path[-1] + d * length / 4)
        mb.tube(path, [r, r * 0.75, r * 0.5, r * 0.3, r * 0.08], 5, bark, v_scale=0.45)
        hangs.extend(path[1:])
        if depth > 0:
            for _ in range(2):
                i = rng.randint(1, 3)
                dd = (d + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 0.5)))).normalized()
                branch(path[i], dd, length * 0.5, r * 0.45, depth - 1)

    for b in range(branches):
        ang = b / branches * TAU + rng.uniform(-0.4, 0.4)
        i = rng.randint(n // 2, n - 1)
        out = Vector((math.cos(ang), math.sin(ang), rng.uniform(0.0, 0.45)))
        branch(trunk[i], out, height * rng.uniform(0.3, 0.42), radii[i] * 0.55, 1)
    # Moignon cassé au sommet.
    mb.tube([trunk[-1], trunk[-1] + (trunk[-1] - trunk[-2]).normalized() * 0.4], [radii[-1], radii[-1] * 0.6], 6,
            bark, cap_top=True, cap_mat=m["wood_rings"])
    rng.shuffle(hangs)
    hangs.sort(key=lambda p: -p.z)
    chosen = [p for p in hangs if p.z > height * 0.35][:moss]
    for p in chosen:
        length = rng.uniform(1.0, 2.2) * min(1.0, p.z / 3.0)
        width = rng.uniform(0.45, 0.75)
        a = rng.uniform(0, math.pi)
        center = p - UP * (length / 2 - 0.08)
        out = Vector((p.x, p.y, 0))
        out = out.normalized() if out.length > 0.01 else Vector((1, 0, 0))
        for da in (0.0, math.pi / 2):
            right = Vector((math.cos(a + da), math.sin(a + da), 0)) * width
            mb.card(center, right, UP * length, m["moss_hanging"],
                    normal_fn=lambda q, o=out: (o * 0.7 + UP * 0.5).normalized())
    return mb.build(name)


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
    tris = sum(sum(len(p.vertices) - 2 for p in bpy.data.objects[n].data.polygons) for n in names)
    print("écrit", path, len(names), "objets,", tris, "triangles")


def main():
    os.makedirs(OUT, exist_ok=True)
    be.clear_scene()
    build_moss_texture()
    m = lmats()
    singles = [
        build_temple(m), build_castle_keep(m), build_castle_wall(m), build_castle_tower(m),
        build_castle_gatehouse(m), build_ruin_column(m), build_ruin_column_broken(m), build_ruin_column_fallen(m),
        ruin_wall(m, "ruin_wall", 2.3, [(1, 1.1), (2, 0.5), (3, -0.6), (4, 0.3), (7, 0.25)], seed=5),
        ruin_wall(m, "ruin_wall_low", 0.75, [(1, 0.2), (2, 0.25), (3, -0.2), (5, 0.12)], seed=6, plinth=False,
                  loose=3),
        build_ruin_arch(m), build_ruin_statue(m), build_ruin_rubble(m), build_ruin_altar(m), build_ruin_skull(m),
        build_marsh_tree("marsh_tree", m, 41, 9.2, branches=5, moss=12),
        build_marsh_tree("marsh_tree_small", m, 42, 5.4, branches=4, moss=7),
    ]
    for obj in singles:
        export(f"{obj.name}.glb", [obj.name])
    build_monument(m)
    export("monument.glb", ["monument", "monument_water", "monument_water_fall"])


if __name__ == "__main__":
    main()
