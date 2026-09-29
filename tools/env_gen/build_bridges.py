"""Générateur des ponts posés sur les rivières des cartes décorées (Orée de la forêt),
exportés en glTF binaire pour Godot. Réutilise les outils de maillage et les matériaux de
build_environment.py.

Usage (depuis la racine du projet, après fetch_textures.py) :
    blender -b --python tools/env_gen/build_bridges.py

Sortie : assets/environment/models/props/
    bridge_stone.glb  pont de pierre à trois arches segmentaires (route pavée) : 15 m de long
                      (X), chaussée praticable de 5 m entre deux parapets.
    bridge_wood.glb   passerelle de planches sur pilotis (chemins de terre) : 13 m de long (X),
                      tablier praticable de 3 m entre deux garde-corps.

Le dessus du tablier est au ras du sol (z = 0,03) : le personnage, toujours posé à y = 0,
marche dessus sans rampe. C'est la rivière qui est creusée sous le niveau du sol (voir
scenes/maps/common/TerrainGround.gd : eau à -1,1 m, lit à -2 m) ; piles et arches descendent
donc jusqu'à -2,4 m. Largeurs praticables = nombre entier impair de cases, parapets juste à
l'extérieur : l'emprise serveur (cases "bridge" du GridMap + ObstacleFootprint3D des parapets,
voir scenes/maps/props/Bridge*.tscn) tombe pile sur le modèle.

Conventions : identiques à build_environment.py (Blender Z haut, +Y Blender = -Z Godot,
1 case = 1 m, aucune image embarquée : matériaux remplacés par nom côté Godot, voir
scenes/maps/common/EnvMaterials.gd).
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

OUT = os.path.join(be.OUT, "props")
DECK_TOP = 0.03
FOOT = -2.4  # bas des piles / murs, sous le lit de la rivière


def bmats():
    m = be.mats()
    m.update({
        "castle_stone": be.pbr("castle_stone", "Bricks076A"),
        "rubble_stone": be.pbr("rubble_stone", "Bricks102"),
    })
    return m


# ---------------------------------------------------------------------------
# Pont de pierre
# ---------------------------------------------------------------------------

STONE_LENGTH = 15.0
STONE_WALK = 5.0
STONE_PARAPET = 0.45
STONE_ARCHES = (-4.2, 0.0, 4.2)  # centres des arches (X)
STONE_ARCH_SPAN = 3.3
STONE_SPRING_Z = -1.35  # naissance des arches (sous l'eau, à -1,1 m)
STONE_CROWN_Z = -0.62  # clef de voûte (intrados)


def _intrados(x):
    """Hauteur du bas du corps du pont en `x` : l'intrados d'une arche segmentaire au-dessus
    de chaque ouverture, le pied des piles ailleurs."""
    for cx in STONE_ARCHES:
        half = STONE_ARCH_SPAN / 2
        if abs(x - cx) < half:
            rise = STONE_CROWN_Z - STONE_SPRING_Z
            radius = (half * half + rise * rise) / (2 * rise)
            centre_z = STONE_CROWN_Z - radius
            return centre_z + math.sqrt(max(radius * radius - (x - cx) ** 2, 0.0))
    return FOOT


def build_bridge_stone(m):
    mb = MeshBuilder()
    st, sm, paving = m["castle_stone"], m["stone_smooth"], m["rubble_stone"]
    L = STONE_LENGTH
    half_w = STONE_WALK / 2 + STONE_PARAPET  # faces extérieures des tympans
    body_top = -0.42
    # Corps du pont (tympans percés de trois arches) : bandes verticales de 0,25 m sur les
    # deux faces, intrados (voûte) entre elles.
    steps = int(L / 0.25)
    for i in range(steps):
        x0 = -L / 2 + i * L / steps
        x1 = x0 + L / steps
        b0, b1 = _intrados(x0 + 1e-4), _intrados(x1 - 1e-4)
        for side in (-1, 1):
            y = side * half_w
            pts = [(x0, y, b0), (x1, y, b1), (x1, y, body_top), (x0, y, body_top)]
            uv = [(x0 / 1.6, b0 / 1.6), (x1 / 1.6, b1 / 1.6), (x1 / 1.6, body_top / 1.6), (x0 / 1.6, body_top / 1.6)]
            if side > 0:
                pts.reverse()
                uv.reverse()
            idx = [mb.add_vert(p) for p in pts]
            mb.add_face(idx, uv, st)
        if b0 > FOOT + 0.01 or b1 > FOOT + 0.01:
            # Voûte : face tournée vers le bas.
            pts = [(x0, half_w, b0), (x1, half_w, b1), (x1, -half_w, b1), (x0, -half_w, b0)]
            idx = [mb.add_vert(p) for p in pts]
            mb.add_face(idx, [(x0 / 1.6, 0), (x1 / 1.6, 0), (x1 / 1.6, 2 * half_w / 1.6), (x0 / 1.6, 2 * half_w / 1.6)], st)
    # Flancs des piles et des culées sous chaque arche (murs verticaux le long de Y, tournés
    # vers l'ouverture).
    for cx in STONE_ARCHES:
        for sx in (-1, 1):
            x = cx + sx * STONE_ARCH_SPAN / 2
            pts = [(x, -half_w, FOOT), (x, half_w, FOOT), (x, half_w, STONE_SPRING_Z), (x, -half_w, STONE_SPRING_Z)]
            if sx > 0:
                pts.reverse()
            idx = [mb.add_vert(p) for p in pts]
            mb.add_face(idx, [(0, FOOT), (2 * half_w, FOOT), (2 * half_w, STONE_SPRING_Z), (0, STONE_SPRING_Z)], st)
    # Rouleaux des arches : bandeau de claveaux légèrement saillant sur chaque face.
    for cx in STONE_ARCHES:
        n = 13
        half = STONE_ARCH_SPAN / 2
        for k in range(n):
            xa = cx - half + (k + 0.5) * STONE_ARCH_SPAN / n
            za = _intrados(xa)
            slope = (_intrados(xa + 0.01) - _intrados(xa - 0.01)) / 0.02
            ang = math.atan(slope)
            for side in (-1, 1):
                c = Vector((xa, side * (half_w + 0.03), za + 0.17))
                mb.box(c, (STONE_ARCH_SPAN / n - 0.03, 0.08, 0.36), sm, rot=Matrix.Rotation(-ang, 3, "Y"), texel=0.8)
    # Avant-becs des deux piles centrales, amont et aval (losange à demi engagé dans la pile).
    for i in range(len(STONE_ARCHES) - 1):
        pier_x = (STONE_ARCHES[i] + STONE_ARCHES[i + 1]) / 2
        pier_half = (STONE_ARCHES[i + 1] - STONE_ARCHES[i] - STONE_ARCH_SPAN) / 2
        top = STONE_SPRING_Z + 0.3
        for side in (-1, 1):
            base = Vector((pier_x, side * half_w, FOOT))
            mb.prism(base, pier_half, pier_half, top - FOOT, 4, st, texel=1.6, rot_offset=math.pi / 4, cap_top=False)
            mb.prism(base + UP * (top - FOOT), pier_half, 0.03, 0.4, 4, sm, texel=1.0, rot_offset=math.pi / 4,
                     cap_top=False)
    # Tablier : dalle + pavage, parapets à chaperon, piliers d'extrémité.
    mb.box((0, 0, (body_top + DECK_TOP - 0.03) / 2), (L, 2 * half_w, DECK_TOP - 0.03 - body_top), st, texel=1.6, skip=("+z",))
    mb.box((0, 0, DECK_TOP - 0.015), (L, STONE_WALK, 0.03), paving, texel=1.8)
    rng = random.Random(3)
    for side in (-1, 1):
        y = side * (STONE_WALK / 2 + STONE_PARAPET / 2)
        mb.box((0, y, DECK_TOP + 0.36), (L - 1.0, STONE_PARAPET, 0.72), st, texel=1.4)
        mb.box((0, y, DECK_TOP + 0.76), (L - 0.9, STONE_PARAPET + 0.1, 0.08), sm, texel=1.0)
        # Cordon mouluré sous le parapet, côté extérieur.
        mb.box((0, side * (half_w + 0.04), DECK_TOP - 0.06), (L, 0.1, 0.12), sm, texel=1.0)
        for sx in (-1, 1):
            # Décalé vers l'extérieur : la face intérieure reste alignée sur le parapet.
            c = Vector((sx * (L / 2 - 0.45), y + side * 0.07, 0))
            mb.box(c + UP * (DECK_TOP + 0.5), (0.9, STONE_PARAPET + 0.14, 1.0), st, texel=1.2)
            mb.box(c + UP * (DECK_TOP + 1.04), (1.0, STONE_PARAPET + 0.24, 0.08), sm, texel=1.0)
            mb.prism(c + UP * (DECK_TOP + 1.08), 0.42, 0.02, 0.28, 4, sm, texel=1.0, rot_offset=math.pi / 4, cap_top=False)
        # Quelques pierres descellées sur le chaperon (vieux pont moussu).
        for k in range(4):
            x = rng.uniform(-L / 2 + 1.5, L / 2 - 1.5)
            mb.box((x, y + rng.uniform(-0.08, 0.08), DECK_TOP + 0.83), (rng.uniform(0.25, 0.45), 0.3, 0.06), st,
                   rot=Matrix.Rotation(rng.uniform(-0.2, 0.2), 3, "Z"), texel=0.8)
    # Chasse-roues au pied des parapets.
    for side in (-1, 1):
        mb.box((0, side * (STONE_WALK / 2 - 0.12), DECK_TOP + 0.05), (L - 1.0, 0.24, 0.1), sm, texel=1.0)
    mb.build("bridge_stone")


# ---------------------------------------------------------------------------
# Passerelle de bois
# ---------------------------------------------------------------------------

WOOD_LENGTH = 13.0
WOOD_WALK = 3.0
WOOD_PILES = (-3.6, 0.0, 3.6)


def build_bridge_wood(m):
    mb = MeshBuilder()
    wood, planks = m["wood_dark"], m["planks_old"]
    L = WOOD_LENGTH
    half = WOOD_WALK / 2
    rng = random.Random(11)
    # Planches du tablier, posées en travers (le long de Y), un peu disjointes et gauchies.
    x = -L / 2
    while x < L / 2 - 0.05:
        w = rng.uniform(0.24, 0.32)
        w = min(w, L / 2 - x)
        length = 2 * half + 0.35 + rng.uniform(-0.12, 0.12)
        mb.box((x + w / 2, rng.uniform(-0.05, 0.05), DECK_TOP - 0.035 - rng.uniform(0.0, 0.015)),
               (w - 0.035, length, 0.07), planks, rot=Matrix.Rotation(rng.uniform(-0.03, 0.03), 3, "Z"), texel=1.1)
        x += w
    # Longerons sous les planches.
    for y in (-half + 0.1, 0.0, half - 0.1):
        mb.box((0, y, DECK_TOP - 0.22), (L, 0.2, 0.3), wood, texel=1.2)
    # Palées : deux pieux par rangée, chapeau, croix de Saint-André.
    for px in WOOD_PILES:
        for sy in (-1, 1):
            mb.tube([(px, sy * (half + 0.15), FOOT), (px, sy * (half + 0.15), DECK_TOP - 0.2)], [0.15, 0.13], 8, wood,
                    v_scale=0.5, cap_top=True)
        mb.box((px, 0, DECK_TOP - 0.45), (0.26, 2 * half + 0.7, 0.24), wood, texel=1.0)
        span = 2 * half + 0.3
        ang = math.atan2(1.1, span)
        for s in (-1, 1):
            mb.box((px + 0.16, 0, -1.15), (0.08, math.hypot(span, 1.1), 0.14), wood,
                   rot=Matrix.Rotation(s * ang, 3, "X"), texel=1.0)
    # Culées : poutre de seuil en rondin sur chaque berge.
    for sx in (-1, 1):
        mb.tube([(sx * (L / 2 - 0.35), -half - 0.4, DECK_TOP - 0.3), (sx * (L / 2 - 0.35), half + 0.4, DECK_TOP - 0.3)],
                [0.2, 0.2], 8, wood, v_scale=0.5, cap_top=True, cap_bottom=True)
    # Garde-corps : poteaux, main courante, lisse basse.
    n_posts = 9
    for side in (-1, 1):
        y = side * (half + 0.08)
        for k in range(n_posts):
            px = -L / 2 + 0.3 + k * (L - 0.6) / (n_posts - 1)
            h = 1.0 + (0.1 if k in (0, n_posts - 1) else 0.0)
            mb.box((px, y, DECK_TOP + h / 2), (0.13, 0.13, h), wood, texel=0.8)
        mb.box((0, y, DECK_TOP + 0.95), (L - 0.5, 0.1, 0.09), wood, texel=1.2)
        mb.box((0, y, DECK_TOP + 0.5), (L - 0.5, 0.06, 0.07), planks, texel=1.2)
        # Écharpes en X dans les travées des deux bouts.
        for k in (0, n_posts - 2):
            x0 = -L / 2 + 0.3 + k * (L - 0.6) / (n_posts - 1)
            x1 = x0 + (L - 0.6) / (n_posts - 1)
            d = math.hypot(x1 - x0, 0.4)
            mb.box(((x0 + x1) / 2, y, DECK_TOP + 0.72), (d, 0.05, 0.06), planks,
                   rot=Matrix.Rotation(math.atan2(0.4, x1 - x0), 3, "Y"), texel=1.0)
    mb.build("bridge_wood")


def main():
    os.makedirs(OUT, exist_ok=True)
    be.clear_scene()
    m = bmats()
    build_bridge_stone(m)
    build_bridge_wood(m)
    be.export("props/bridge_stone.glb", ["bridge_stone"])
    be.export("props/bridge_wood.glb", ["bridge_wood"])


main()
