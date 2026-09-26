"""Générateur des modèles d'environnement (végétation + props de carte), exportés en glTF
binaire pour Godot.

Usage (depuis la racine du projet, après fetch_textures.py et build_foliage.py) :
    blender -b --python tools/env_gen/build_environment.py

Sortie : assets/environment/models/
    nature.glb    arbres (chêne, bouleau, sapin, arbre mort), souches, bûche, buissons,
                  rochers, touffes d'herbe — un objet = un mesh (multi-matériaux), origine au
                  pied, instanciés en masse par scenes/maps/common/Vegetation.gd (MultiMesh).
    fountain.glb  fontaine (pierre) + ses trois nappes d'eau (fountain_water_*), animées côté
                  Godot par water.gdshader.
    lamp_post.glb lampadaire en fer forgé ; lamp_glass = vitres (émissives la nuit).
    signpost.glb  poteau + une planche fléchée (sign_board, origine au poteau, pointe vers +X).
    props/*.glb   un prop par fichier (scierie : sawmill_shed, saw_bench, log_pile, plank_pile,
                  cart_broken, crate, barrel ; nature posée à la main : rock_large, rock_medium,
                  log_fallen, stump, tree_dead), assemblés dans scenes/maps/props/*.tscn.

Conventions : Blender Z haut ; l'export glTF (Y haut) envoie +X Blender sur +X Godot et +Y
Blender sur -Z Godot. Unités en mètres (1 case de carte = 1 m). Les .glb n'embarquent AUCUNE
image : leurs matériaux ne portent qu'un nom stable, remplacé côté Godot par un matériau
partagé construit sur assets/environment/textures (scenes/maps/common/EnvMaterials.gd) ;
eau et vitres de lanterne sont gérées par Fountain.gd / LampPost.gd.
"""

import math
import os
import random

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
TEX = os.path.join(ROOT, "assets", "environment", "textures")
OUT = os.path.join(ROOT, "assets", "environment", "models")

UP = Vector((0, 0, 1))


# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------

_materials = {}


def material(name, color=None, normal=None, rough=None, alpha=False, metallic=0.0,
             roughness=0.9, base=(0.8, 0.8, 0.8), emission=None):
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    if color:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(os.path.join(TEX, color), check_existing=True)
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            # Motif "alpha clip" reconnu par l'exporteur glTF -> alphaMode MASK.
            cmp = nt.nodes.new("ShaderNodeMath")
            cmp.operation = "GREATER_THAN"
            cmp.inputs[1].default_value = 0.5
            nt.links.new(img.outputs["Alpha"], cmp.inputs[0])
            nt.links.new(cmp.outputs[0], bsdf.inputs["Alpha"])
    if normal:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(os.path.join(TEX, normal), check_existing=True)
        img.image.colorspace_settings.name = "Non-Color"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(img.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if rough:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = bpy.data.images.load(os.path.join(TEX, rough), check_existing=True)
        img.image.colorspace_settings.name = "Non-Color"
        nt.links.new(img.outputs["Color"], bsdf.inputs["Roughness"])
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    _materials[name] = mat
    return mat


def pbr(name, asset, **kw):
    return material(name, f"{asset}_color.jpg", f"{asset}_normal.jpg", f"{asset}_rough.jpg", **kw)


def mats():
    return {
        "bark_oak": pbr("bark_oak", "Bark012"),
        "bark_fir": pbr("bark_fir", "Bark014"),
        "bark_birch": pbr("bark_birch", "Bark001"),
        "foliage_oak": material("foliage_oak", "foliage_oak.png", alpha=True),
        "foliage_birch": material("foliage_birch", "foliage_birch.png", alpha=True),
        "foliage_fir": material("foliage_fir", "foliage_fir.png", alpha=True),
        "foliage_grass": material("foliage_grass", "foliage_grass.png", alpha=True),
        "foliage_grass_seed": material("foliage_grass_seed", "foliage_grass_seed.png", alpha=True),
        "wood_rings": material("wood_rings", "wood_rings.jpg", roughness=0.85),
        "rock": pbr("rock", "Rock020"),
        "stone_bricks": pbr("stone_bricks", "Bricks089"),
        "stone_smooth": pbr("stone_smooth", "Rock020"),
        "iron": pbr("iron", "Metal021", metallic=0.6),
        "lamp_glass": material("lamp_glass", base=(1.0, 0.8, 0.45), roughness=0.2,
                               emission=(1.0, 0.75, 0.4)),
        "wood_dark": pbr("wood_dark", "Wood051"),
        "wood_sign": pbr("wood_sign", "Wood049"),
        "planks_old": pbr("planks_old", "Planks023A"),
        "planks_fresh": pbr("planks_fresh", "Planks021"),
        "roof_slate": pbr("roof_slate", "RoofingTiles001"),
        "water": material("water", base=(0.2, 0.45, 0.6), roughness=0.05),
    }


# ---------------------------------------------------------------------------
# Construction de maillages
# ---------------------------------------------------------------------------

class MeshBuilder:
    """Accumule sommets/faces/UV/matériaux puis crée un objet Blender. `normal_override`
    (index sommet -> normale) sert aux cartes de feuillage (normales sphériques)."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.uvs = []
        self.face_mats = []
        self.mat_list = []
        self.normal_override = {}

    def _mat_index(self, mat):
        if mat not in self.mat_list:
            self.mat_list.append(mat)
        return self.mat_list.index(mat)

    def add_vert(self, co):
        self.verts.append(Vector(co))
        return len(self.verts) - 1

    def add_face(self, idx, uv, mat):
        self.faces.append(tuple(idx))
        self.uvs.append([tuple(u) for u in uv])
        self.face_mats.append(self._mat_index(mat))

    def quad(self, a, b, c, d, mat, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
        """Quad à sommets propres (arêtes vives)."""
        idx = [self.add_vert(p) for p in (a, b, c, d)]
        self.add_face(idx, uv, mat)
        return idx

    def box(self, center, size, mat, rot=None, texel=1.0, skip=()):
        """Pavé à faces indépendantes, UV à l'échelle du monde (`texel` m par répétition)."""
        rot = rot or Matrix.Identity(3)
        c = Vector(center)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        corners = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    corners[(sx, sy, sz)] = c + rot @ Vector((sx * hx, sy * hy, sz * hz))
        faces = {
            "+z": ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1), size[0], size[1]),
            "-z": ((-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1), size[0], size[1]),
            "+x": ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1), size[1], size[2]),
            "-x": ((-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1), size[1], size[2]),
            "+y": ((1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1), size[0], size[2]),
            "-y": ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1), size[0], size[2]),
        }
        for key, (a, b, cc, d, w, h) in faces.items():
            if key in skip:
                continue
            u, v = w / texel, h / texel
            self.quad(corners[a], corners[b], corners[cc], corners[d], mat,
                      ((0, 0), (u, 0), (u, v), (0, v)))

    def tube(self, points, radii, sides, mat, v_scale=1.0, cap_top=False, cap_bottom=False,
             cap_mat=None, twist=0.0):
        """Tube lisse le long d'une polyligne (repère transporté), UV : u autour, v le long
        (répété tous les `v_scale` m de circonférence moyenne pour garder l'écorce à
        l'échelle)."""
        pts = [Vector(p) for p in points]
        n = len(pts)
        tangents = []
        for i in range(n):
            if i == 0:
                t = pts[1] - pts[0]
            elif i == n - 1:
                t = pts[-1] - pts[-2]
            else:
                t = pts[i + 1] - pts[i - 1]
            tangents.append(t.normalized())
        ref = Vector((1, 0, 0)) if abs(tangents[0].dot(Vector((1, 0, 0)))) < 0.9 else Vector((0, 1, 0))
        normal = tangents[0].cross(ref).normalized()
        rings = []
        length = 0.0
        circumference = 2 * math.pi * (sum(radii) / len(radii))
        for i in range(n):
            if i > 0:
                length += (pts[i] - pts[i - 1]).length
                # Transport parallèle du repère le long de la courbe.
                axis = tangents[i - 1].cross(tangents[i])
                if axis.length > 1e-6:
                    ang = tangents[i - 1].angle(tangents[i])
                    normal = Matrix.Rotation(ang, 3, axis.normalized()) @ normal
            binormal = tangents[i].cross(normal).normalized()
            ring = []
            for s in range(sides + 1):
                a = (s / sides) * math.tau + twist * i
                d = normal * math.cos(a) + binormal * math.sin(a)
                vi = self.add_vert(pts[i] + d * radii[i])
                self.normal_override[vi] = d
                ring.append((vi, s / sides, length / max(circumference, 1e-3) / v_scale * 1.0))
            rings.append(ring)
        for i in range(n - 1):
            for s in range(sides):
                a0, a1 = rings[i][s], rings[i][s + 1]
                b0, b1 = rings[i + 1][s], rings[i + 1][s + 1]
                self.add_face((a0[0], a1[0], b1[0], b0[0]),
                              ((a0[1], a0[2]), (a1[1], a1[2]), (b1[1], b1[2]), (b0[1], b0[2])), mat)
        for cap, ring_i, sign in ((cap_bottom, 0, -1), (cap_top, n - 1, 1)):
            if not cap:
                continue
            ring = rings[ring_i][:-1]
            c = pts[ring_i]
            ci = self.add_vert(c)
            self.normal_override[ci] = tangents[ring_i] * sign
            m = cap_mat or mat
            for s in range(sides):
                p0, p1 = ring[s][0], ring[(s + 1) % sides][0]
                # Copie des sommets du bord : normale de coupe plane, pas celle du tube.
                q0 = self.add_vert(self.verts[p0])
                q1 = self.add_vert(self.verts[p1])
                self.normal_override[q0] = tangents[ring_i] * sign
                self.normal_override[q1] = tangents[ring_i] * sign
                a0 = (s / sides) * math.tau
                a1 = ((s + 1) / sides) * math.tau
                uv = ((0.5, 0.5), (0.5 + 0.45 * math.cos(a0), 0.5 + 0.45 * math.sin(a0)),
                      (0.5 + 0.45 * math.cos(a1), 0.5 + 0.45 * math.sin(a1)))
                if sign > 0:
                    self.add_face((ci, q0, q1), uv, m)
                else:
                    self.add_face((ci, q1, q0), (uv[0], uv[2], uv[1]), m)

    def prism(self, center, radius_bottom, radius_top, height, sides, mat, texel=1.0,
              cap_top=True, cap_bottom=False, rot_offset=0.0, cap_mat=None):
        """Prisme à facettes (colonnes, bases octogonales) : faces planes indépendantes."""
        c = Vector(center)
        per = 2 * math.pi * radius_bottom / sides
        for s in range(sides):
            a0 = rot_offset + s / sides * math.tau
            a1 = rot_offset + (s + 1) / sides * math.tau
            b0 = c + Vector((math.cos(a0) * radius_bottom, math.sin(a0) * radius_bottom, 0))
            b1 = c + Vector((math.cos(a1) * radius_bottom, math.sin(a1) * radius_bottom, 0))
            t0 = c + Vector((math.cos(a0) * radius_top, math.sin(a0) * radius_top, height))
            t1 = c + Vector((math.cos(a1) * radius_top, math.sin(a1) * radius_top, height))
            u0 = s * per / texel
            u1 = (s + 1) * per / texel
            self.quad(b0, b1, t1, t0, mat, ((u0, 0), (u1, 0), (u1, height / texel), (u0, height / texel)))
        for cap, z, r, flip in ((cap_top, height, radius_top, False), (cap_bottom, 0, radius_bottom, True)):
            if not cap:
                continue
            ring = []
            uvs = []
            for s in range(sides):
                a = rot_offset + s / sides * math.tau
                ring.append(self.add_vert(c + Vector((math.cos(a) * r, math.sin(a) * r, z))))
                uvs.append((0.5 + math.cos(a) * r / texel, 0.5 + math.sin(a) * r / texel))
            if flip:
                ring.reverse()
                uvs.reverse()
            self.add_face(ring, uvs, cap_mat or mat)

    def ring_wall(self, center, r_out, r_in, z0, z1, sides, mat_side, mat_top, texel=1.0, rot_offset=0.0):
        """Muret annulaire à facettes (bassin de fontaine) : faces externe, interne et dessus."""
        c = Vector(center)
        per = 2 * math.pi * r_out / sides
        for s in range(sides):
            a0 = rot_offset + s / sides * math.tau
            a1 = rot_offset + (s + 1) / sides * math.tau
            d0 = Vector((math.cos(a0), math.sin(a0), 0))
            d1 = Vector((math.cos(a1), math.sin(a1), 0))
            h = (z1 - z0) / texel
            u0, u1 = s * per / texel, (s + 1) * per / texel
            self.quad(c + d0 * r_out + UP * z0, c + d1 * r_out + UP * z0, c + d1 * r_out + UP * z1,
                      c + d0 * r_out + UP * z1, mat_side, ((u0, 0), (u1, 0), (u1, h), (u0, h)))
            self.quad(c + d1 * r_in + UP * z0, c + d0 * r_in + UP * z0, c + d0 * r_in + UP * z1,
                      c + d1 * r_in + UP * z1, mat_side, ((u1, 0), (u0, 0), (u0, h), (u1, h)))
            self.quad(c + d0 * r_out + UP * z1, c + d1 * r_out + UP * z1, c + d1 * r_in + UP * z1,
                      c + d0 * r_in + UP * z1, mat_top,
                      ((u0, 0), (u1, 0), (u1, (r_out - r_in) / texel), (u0, (r_out - r_in) / texel)))

    def disc(self, center, radius, sides, mat, z_up=True, uv_scale=1.0, rot_offset=0.0):
        c = Vector(center)
        ring, uvs = [], []
        for s in range(sides):
            a = rot_offset + s / sides * math.tau
            ring.append(self.add_vert(c + Vector((math.cos(a) * radius, math.sin(a) * radius, 0))))
            uvs.append((0.5 + math.cos(a) * 0.5 * uv_scale, 0.5 + math.sin(a) * 0.5 * uv_scale))
        if not z_up:
            ring.reverse()
            uvs.reverse()
        self.add_face(ring, uvs, mat)

    def card(self, center, right, up, mat, uv=(0, 0, 1, 1), normal_fn=None):
        """Carte de feuillage : quad `right` x `up` centré en `center`."""
        c = Vector(center)
        r, u = Vector(right) / 2, Vector(up) / 2
        pts = (c - r - u, c + r - u, c + r + u, c - r + u)
        u0, v0, u1, v1 = uv
        idx = [self.add_vert(p) for p in pts]
        self.add_face(idx, ((u0, v0), (u1, v0), (u1, v1), (u0, v1)), mat)
        if normal_fn:
            for i in idx:
                self.normal_override[i] = normal_fn(self.verts[i])

    def build(self, name):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        uv_layer = mesh.uv_layers.new(name="UVMap")
        li = 0
        for poly, face_uv in zip(mesh.polygons, self.uvs):
            for k in range(poly.loop_total):
                uv_layer.data[poly.loop_start + k].uv = face_uv[k]
            li += poly.loop_total
        for m in self.mat_list:
            mesh.materials.append(m)
        for poly, mi in zip(mesh.polygons, self.face_mats):
            poly.material_index = mi
            poly.use_smooth = True
        mesh.update()
        normals = [Vector(v.normal) for v in mesh.vertices]
        for i, n in self.normal_override.items():
            normals[i] = Vector(n).normalized()
        mesh.normals_split_custom_set_from_vertices([tuple(n) for n in normals])
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ---------------------------------------------------------------------------
# Végétation
# ---------------------------------------------------------------------------

def bent_path(start, direction, length, segments, bend, rng):
    pts = [Vector(start)]
    d = Vector(direction).normalized()
    step = length / segments
    for _ in range(segments):
        d = (d + Vector((rng.uniform(-bend, bend), rng.uniform(-bend, bend), rng.uniform(-bend, bend) * 0.3))).normalized()
        pts.append(pts[-1] + d * step)
    return pts


def canopy_cluster(mb, center, radius, mat, rng, cards, canopy_center, core=True):
    """Grappe de feuillage : cartes orientées vers l'extérieur + un noyau (icosaèdre) dont
    chaque triangle pointe sur le cœur dense de la texture, pour boucher les trous vus de
    dessus. Normales sphériques centrées sur `canopy_center` (éclairage doux, volumique)."""
    cc = Vector(canopy_center)

    def sph(p):
        return (p - cc).normalized() * 0.8 + UP * 0.35

    for _ in range(cards):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) * 0.7 + 0.2)).normalized()
        pos = Vector(center) + d * radius * rng.uniform(0.35, 0.9)
        size = radius * rng.uniform(1.0, 1.45)
        # Carte à peu près tangente à la grappe (face vers l'extérieur), tournée au hasard.
        tangent = d.cross(UP if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
        tangent = Matrix.Rotation(rng.uniform(0, math.tau), 3, d) @ tangent
        bitangent = d.cross(tangent).normalized()
        mb.card(pos, tangent * size, bitangent * size, mat, normal_fn=sph)
    if core:
        r = radius * 0.62
        phi = (1 + 5 ** 0.5) / 2
        ico = [(-1, phi, 0), (1, phi, 0), (-1, -phi, 0), (1, -phi, 0), (0, -1, phi), (0, 1, phi),
               (0, -1, -phi), (0, 1, -phi), (phi, 0, -1), (phi, 0, 1), (-phi, 0, -1), (-phi, 0, 1)]
        tris = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4),
                (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8),
                (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
        scale = Vector((1, 1, 0.8))
        pts = []
        for v in ico:
            p = Vector(v).normalized() * r * rng.uniform(0.85, 1.1)
            pts.append(Vector(center) + Vector((p.x * scale.x, p.y * scale.y, p.z * scale.z)))
        for a, b, c in tris:
            idx = [mb.add_vert(pts[a]), mb.add_vert(pts[b]), mb.add_vert(pts[c])]
            o = (rng.uniform(0.4, 0.5), rng.uniform(0.4, 0.5))
            mb.add_face(idx, ((o[0], o[1]), (o[0] + 0.12, o[1]), (o[0] + 0.06, o[1] + 0.12)), mat)
            for i in idx:
                mb.normal_override[i] = sph(mb.verts[i])


def build_deciduous(name, m, seed, height, bark, foliage, trunk_r, crown_r, clusters, slim=False):
    rng = random.Random(seed)
    mb = MeshBuilder()
    trunk_len = height * (0.55 if not slim else 0.7)
    trunk = bent_path((0, 0, -0.1), (0, 0, 1), trunk_len, 6, 0.08, rng)
    radii = [trunk_r * (1.35 if i == 0 else 1.0 - 0.45 * i / 6) for i in range(7)]
    mb.tube(trunk, radii, 9, bark, v_scale=0.5)
    top = trunk[-1]
    canopy_center = top + UP * crown_r * 0.45
    tips = []
    branch_count = 5 if not slim else 4
    for b in range(branch_count):
        ang = b / branch_count * math.tau + rng.uniform(-0.4, 0.4)
        out = Vector((math.cos(ang), math.sin(ang), rng.uniform(0.7, 1.3) if not slim else 1.8))
        base_i = rng.randint(3, 5)
        path = bent_path(trunk[base_i], out, crown_r * rng.uniform(0.75, 1.0), 3, 0.15, rng)
        r0 = radii[base_i] * 0.55
        mb.tube(path, [r0, r0 * 0.7, r0 * 0.45, r0 * 0.25], 6, bark, v_scale=0.5)
        tips.append(path[-1])
    tips.append(top + UP * crown_r * 0.6)
    # Grappes : une par extrémité de branche, puis des grappes de remplissage autour du
    # centre de la couronne.
    for tip in tips:
        canopy_cluster(mb, tip + UP * 0.2, crown_r * rng.uniform(0.5, 0.62), foliage, rng, 7, canopy_center)
    for _ in range(clusters - len(tips)):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.6))).normalized()
        pos = canopy_center + Vector((d.x * crown_r * 0.6, d.y * crown_r * 0.6, d.z * crown_r * 0.45))
        canopy_cluster(mb, pos, crown_r * rng.uniform(0.45, 0.58), foliage, rng, 6, canopy_center)
    return mb.build(name)


def build_fir(name, m, seed, height, base_r):
    rng = random.Random(seed)
    mb = MeshBuilder()
    trunk = [(0, 0, -0.1), (0, 0, height * 0.35), (0, 0, height * 0.7), (0, 0, height)]
    mb.tube(trunk, [0.24 * height / 10, 0.17 * height / 10, 0.1 * height / 10, 0.02], 7, m["bark_fir"], v_scale=0.5)
    whorls = int(height * 1.5)
    start = 1.2
    for w in range(whorls):
        t = w / (whorls - 1)
        z = start + (height - start - 0.3) * t
        length = base_r * (1 - t) ** 0.9 + 0.35
        count = max(4, int(7 - t * 3))
        off = rng.uniform(0, math.tau)
        for b in range(count):
            ang = off + b / count * math.tau + rng.uniform(-0.2, 0.2)
            out = Vector((math.cos(ang), math.sin(ang), 0))
            droop = rng.uniform(-0.35, -0.15)
            axis_dir = (out + UP * droop).normalized()
            center = Vector((0, 0, z)) + axis_dir * length * 0.5
            width = length * 0.55
            side = axis_dir.cross(UP).normalized()
            # Deux cartes en X le long du rameau : du volume vu de dessus comme de côté.
            for tilt in (0.35, -0.35):
                flat = (Matrix.Rotation(tilt, 3, axis_dir) @ side) * width
                mb.card(center, axis_dir * length, flat, m["foliage_fir"],
                        normal_fn=lambda p, zc=z: ((p - Vector((0, 0, zc - 0.6))).normalized() * 0.7 + UP * 0.4))
    # Pointe : quelques rameaux dressés.
    for b in range(3):
        ang = b / 3 * math.tau
        d = Vector((math.cos(ang) * 0.3, math.sin(ang) * 0.3, 1)).normalized()
        mb.card(Vector((0, 0, height - 0.2)) + d * 0.35, d * 0.8, d.cross(UP).normalized() * 0.45 if d.cross(UP).length > 0.01 else Vector((0.45, 0, 0)),
                m["foliage_fir"], normal_fn=lambda p: UP)
    return mb.build(name)


def build_dead_tree(name, m, seed, height):
    rng = random.Random(seed)
    mb = MeshBuilder()
    trunk = bent_path((0, 0, -0.1), (0, 0, 1), height * 0.75, 6, 0.12, rng)
    radii = [0.3 * (1.3 if i == 0 else 1 - 0.7 * i / 6) for i in range(7)]
    mb.tube(trunk, radii, 8, m["bark_oak"], v_scale=0.5)

    def branch(start, direction, length, r, depth):
        path = bent_path(start, direction, length, 3, 0.25, rng)
        mb.tube(path, [r, r * 0.7, r * 0.45, r * 0.15], 5, m["bark_oak"], v_scale=0.5)
        if depth > 0:
            for _ in range(2):
                i = rng.randint(1, 2)
                d = (Vector(direction) + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0, 0.8)))).normalized()
                branch(path[i], d, length * 0.55, r * 0.5, depth - 1)

    for b in range(4):
        ang = b / 4 * math.tau + rng.uniform(-0.5, 0.5)
        branch(trunk[rng.randint(3, 5)], Vector((math.cos(ang), math.sin(ang), rng.uniform(0.4, 1.0))), height * 0.35,
               radii[4] * 0.6, 1)
    return mb.build(name)


def build_stump(name, m, seed, radius, height):
    rng = random.Random(seed)
    mb = MeshBuilder()
    pts = [(0, 0, -0.05), (0, 0, height * 0.5), (0, 0, height)]
    mb.tube(pts, [radius * 1.35, radius * 1.05, radius], 10, m["bark_oak"], v_scale=0.5, cap_top=True,
            cap_mat=m["wood_rings"])
    # Racines apparentes.
    for r in range(4):
        ang = r / 4 * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        path = [d * radius * 0.8 + UP * 0.12, d * radius * 1.5 + UP * 0.02, d * radius * 2.1 - UP * 0.06]
        mb.tube(path, [radius * 0.35, radius * 0.22, radius * 0.08], 5, m["bark_oak"], v_scale=0.5)
    return mb.build(name)


def build_log(name, m, seed, length, radius):
    """Bûche couchée le long de X, posée au sol (origine au centre du contact)."""
    mb = MeshBuilder()
    pts = [(-length / 2, 0, radius), (0, 0, radius * 1.02), (length / 2, 0, radius)]
    mb.tube(pts, [radius, radius * 1.03, radius * 0.95], 9, m["bark_oak"], v_scale=0.5, cap_top=True,
            cap_bottom=True, cap_mat=m["wood_rings"])
    return mb.build(name)


def build_bush(name, m, seed, radius, foliage):
    rng = random.Random(seed)
    mb = MeshBuilder()
    center = Vector((0, 0, radius * 0.7))
    for _ in range(4):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.uniform(0, 0.4))).normalized()
        pos = center + Vector((d.x * radius * 0.5, d.y * radius * 0.5, d.z * radius * 0.3))
        canopy_cluster(mb, pos, radius * rng.uniform(0.55, 0.7), foliage, rng, 6, center - UP * radius * 0.3)
    return mb.build(name)


def build_rock(name, m, seed, size, flat=0.6):
    """Rocher : icosphère subdivisée, déformée par du bruit à basse fréquence, aplatie,
    enfoncée de 15 % dans le sol."""
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=size / 2)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    offsets = [(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized(), rng.uniform(0.1, 0.25))
               for _ in range(6)]
    for v in obj.data.vertices:
        n = v.co.normalized()
        k = 1.0
        for d, amp in offsets:
            k += amp * max(0.0, n.dot(d)) ** 2 - amp * 0.3
        v.co = n * (size / 2) * k
        v.co.z *= flat
        v.co.z += size * flat * 0.35
    obj.data.materials.append(m["rock"])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=1.5)
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def build_grass(name, m, seed, height, mat):
    """Touffe : 3 cartes croisées, normales vers le haut (éclairée comme le sol)."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    for k in range(3):
        ang = k / 3 * math.pi + rng.uniform(-0.2, 0.2)
        right = Vector((math.cos(ang), math.sin(ang), 0)) * height * 1.1
        mb.card(Vector((0, 0, height / 2 - 0.02)), right, UP * height, mat, normal_fn=lambda p: UP)
    return mb.build(name)


# ---------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------

def build_fountain(m):
    """Fontaine octogonale ~4,4 m : bassin en maçonnerie, colonne centrale, vasque haute,
    fleuron. Nappes d'eau exportées à part (fountain_water_low/high/fall)."""
    stone = MeshBuilder()
    oct_off = math.pi / 8
    # Socle et bassin.
    stone.prism((0, 0, 0), 2.45, 2.45, 0.12, 8, m["stone_smooth"], texel=1.5, rot_offset=oct_off)
    stone.ring_wall((0, 0, 0.12), 2.2, 1.9, 0.0, 0.52, 8, m["stone_bricks"], m["stone_smooth"], texel=1.0, rot_offset=oct_off)
    stone.ring_wall((0, 0, 0.64), 2.3, 1.85, 0.0, 0.1, 8, m["stone_smooth"], m["stone_smooth"], texel=1.0, rot_offset=oct_off)
    stone.disc((0, 0, 0.14), 1.95, 8, m["stone_smooth"], uv_scale=2.0, rot_offset=oct_off)
    # Colonne, vasque haute, fût supérieur, fleuron.
    stone.prism((0, 0, 0.1), 0.5, 0.42, 0.3, 8, m["stone_smooth"], texel=1.0)
    stone.prism((0, 0, 0.4), 0.3, 0.26, 1.0, 8, m["stone_bricks"], texel=0.8)
    stone.prism((0, 0, 1.4), 0.26, 0.95, 0.28, 12, m["stone_smooth"], texel=1.0, cap_top=False)
    stone.ring_wall((0, 0, 1.68), 0.95, 0.82, 0.0, 0.08, 12, m["stone_smooth"], m["stone_smooth"], texel=1.0)
    stone.disc((0, 0, 1.56), 0.84, 12, m["stone_smooth"])
    stone.prism((0, 0, 1.56), 0.16, 0.12, 0.55, 8, m["stone_smooth"], texel=0.6)
    stone.prism((0, 0, 2.11), 0.22, 0.05, 0.28, 8, m["stone_smooth"], texel=0.6)
    stone.build("fountain")

    water = MeshBuilder()
    water.disc((0, 0, 0.5), 1.9, 8, m["water"], uv_scale=1.0, rot_offset=oct_off)
    water.build("fountain_water_low")
    water = MeshBuilder()
    water.disc((0, 0, 1.72), 0.82, 12, m["water"])
    water.build("fountain_water_high")
    # Rideau d'eau qui déborde de la vasque haute : tronc de cône ouvert, UV v le long de
    # la chute (le shader fait défiler v).
    fall = MeshBuilder()
    sides = 24
    ring_top, ring_bot = [], []
    for s in range(sides + 1):
        a = s / sides * math.tau
        ring_top.append(fall.add_vert((math.cos(a) * 0.97, math.sin(a) * 0.97, 1.74)))
        ring_bot.append(fall.add_vert((math.cos(a) * 1.18, math.sin(a) * 1.18, 0.5)))
    for s in range(sides):
        u0, u1 = s / sides * 4, (s + 1) / sides * 4
        fall.add_face((ring_bot[s], ring_bot[s + 1], ring_top[s + 1], ring_top[s]),
                      ((u0, 0), (u1, 0), (u1, 1), (u0, 1)), m["water"])
    fall.build("fountain_water_fall")


def build_lamp_post(m):
    """Lampadaire ~3,1 m : socle de pierre, fût de fer octogonal, crosse et lanterne
    suspendue (cadre + vitres émissives `lamp_glass`, centre de lumière à ~2,55 m)."""
    mb = MeshBuilder()
    iron = m["iron"]
    mb.prism((0, 0, 0), 0.26, 0.22, 0.3, 8, m["stone_smooth"], texel=0.6)
    mb.prism((0, 0, 0.3), 0.07, 0.05, 2.75, 8, iron, texel=0.5)
    mb.prism((0, 0, 0.3), 0.11, 0.07, 0.25, 8, iron, texel=0.5)
    mb.prism((0, 0, 3.05), 0.09, 0.02, 0.14, 8, iron, texel=0.5)
    # Crosse vers +X.
    arm = [(0, 0, 2.95), (0.25, 0, 3.02), (0.5, 0, 3.0), (0.62, 0, 2.93)]
    mb.tube(arm, [0.03, 0.03, 0.028, 0.025], 6, iron)
    mb.tube([(0.1, 0, 2.62), (0.25, 0, 2.8), (0.45, 0, 2.98)], [0.018, 0.018, 0.018], 5, iron)
    # Lanterne suspendue sous la crosse.
    lx = 0.62
    mb.prism((lx, 0, 2.82), 0.2, 0.03, 0.12, 4, iron, texel=0.5, rot_offset=math.pi / 4)
    mb.box((lx, 0, 2.3), (0.2, 0.2, 0.04), iron, texel=0.4)
    mb.box((lx, 0, 2.8), (0.24, 0.24, 0.04), iron, texel=0.4)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((lx + sx * 0.1, sy * 0.1, 2.55), (0.025, 0.025, 0.5), iron, texel=0.4)
    mb.tube([(lx, 0, 2.86), (lx, 0, 2.93)], [0.012, 0.012], 4, iron)
    mb.build("lamp_post")
    glass = MeshBuilder()
    glass.box((lx, 0, 2.55), (0.18, 0.18, 0.46), m["lamp_glass"], texel=0.5)
    glass.build("lamp_glass")


def build_signpost(m):
    mb = MeshBuilder()
    mb.box((0, 0, 1.2), (0.12, 0.12, 2.5), m["wood_dark"], texel=0.8)
    mb.prism((0, 0, 2.45), 0.1, 0.02, 0.12, 4, m["wood_dark"], texel=0.5, rot_offset=math.pi / 4)
    # Pierres calant le pied.
    rng = random.Random(4)
    for k in range(5):
        ang = k / 5 * math.tau
        mb.box((math.cos(ang) * 0.14, math.sin(ang) * 0.14, 0.04),
               (rng.uniform(0.1, 0.16), rng.uniform(0.08, 0.13), 0.1), m["stone_smooth"],
               rot=Matrix.Rotation(ang, 3, "Z"), texel=0.4)
    mb.build("signpost")
    # Planche fléchée : de x=0.08 (contre le poteau) à la pointe x=1.15.
    board = MeshBuilder()
    w, h, t = 1.07, 0.24, 0.045
    x0 = 0.08
    body = 0.85
    outline = [(x0, -h / 2), (x0 + body, -h / 2), (x0 + w, 0), (x0 + body, h / 2), (x0, h / 2)]
    mat = m["wood_sign"]
    for y, flip in ((t / 2, False), (-t / 2, True)):
        idx = [board.add_vert((px, y, pz)) for px, pz in outline]
        uv = [((px - x0) / 1.2, (pz + h / 2) / 1.2 + 0.3) for px, pz in outline]
        if flip:
            board.add_face(list(idx), uv, mat)
        else:
            board.add_face(list(reversed(idx)), list(reversed(uv)), mat)
    n = len(outline)
    for i in range(n):
        (ax, az), (bx, bz) = outline[i], outline[(i + 1) % n]
        board.quad((ax, -t / 2, az), (bx, -t / 2, bz), (bx, t / 2, bz), (ax, t / 2, az), mat,
                   ((0, 0), (0.3, 0), (0.3, 0.03), (0, 0.03)))
    board.build("sign_board")


def build_sawmill(m):
    """Scierie abandonnée : hangar à ossature bois 10 x 6 m, plancher surélevé, murs de
    planches sur trois côtés (planches manquantes), façade avant ouverte, toit d'ardoise à deux
    pans dont un crevé (chevrons à nu). Axe long = X, façade ouverte vers -Y Blender (+Z
    Godot)."""
    rng = random.Random(12)
    mb = MeshBuilder()
    L, W, H, ridge = 10.0, 6.0, 2.8, 4.6
    wood, planks, roof = m["wood_dark"], m["planks_old"], m["roof_slate"]
    # Plancher sur plots.
    mb.box((0, 0, 0.28), (L + 0.2, W + 0.2, 0.12), planks, texel=2.0)
    for x in (-L / 2, -L / 6, L / 6, L / 2):
        for y in (-W / 2, 0, W / 2):
            mb.box((x, y, 0.11), (0.3, 0.3, 0.22), m["stone_smooth"], texel=0.6)
    # Poteaux et sablières.
    for x in (-L / 2, -L / 6, L / 6, L / 2):
        for y in (-W / 2, W / 2):
            mb.box((x, y, 0.34 + H / 2), (0.22, 0.22, H), wood, texel=1.0)
    for y in (-W / 2, W / 2):
        mb.box((0, y, 0.34 + H), (L + 0.4, 0.22, 0.2), wood, texel=1.5)
    for x in (-L / 2, L / 2):
        mb.box((x, 0, 0.34 + H), (0.22, W + 0.2, 0.2), wood, texel=1.5)
    # Murs de planches verticales : arrière (+Y), pignons (±X). Quelques planches manquent
    # ou pendent de travers.
    def plank_wall(start, end, height_fn, z0):
        s, e = Vector(start), Vector(end)
        length = (e - s).length
        count = int(length / 0.22)
        direction = (e - s).normalized()
        normal = direction.cross(UP)
        for i in range(count):
            if rng.random() < 0.12:
                continue
            p = s + direction * (i + 0.5) * (length / count)
            h = height_fn(p)
            rot = Matrix.Rotation(math.atan2(direction.y, direction.x), 3, "Z")
            tilt = Matrix.Identity(3)
            if rng.random() < 0.06:
                tilt = Matrix.Rotation(rng.uniform(-0.25, 0.25), 3, direction)
                h *= rng.uniform(0.5, 0.8)
            mb.box(p + UP * (z0 + h / 2) + normal * 0.02, (length / count * 0.95, 0.04, h), planks,
                   rot=tilt @ rot, texel=1.2)

    plank_wall((-L / 2, W / 2, 0), (L / 2, W / 2, 0), lambda p: H, 0.34)
    for x in (-L / 2, L / 2):
        plank_wall((x, W / 2, 0), (x, -W / 2, 0),
                   lambda p: H + (ridge - H) * (1 - abs(p.y) / (W / 2)), 0.34)
    # Faîtage et chevrons.
    zr = 0.34 + ridge
    mb.box((0, 0, zr), (L + 0.8, 0.2, 0.22), wood, texel=1.5)
    slope = math.atan2(ridge - H, W / 2)
    rafter_len = math.hypot(W / 2, ridge - H) + 0.5
    for x in [(-L / 2 - 0.3) + i * (L + 0.6) / 10 for i in range(11)]:
        for side in (-1, 1):
            rot = Matrix.Rotation(-side * slope, 3, "X")
            c = Vector((x, side * W / 4 + side * 0.12, 0.34 + (H + ridge) / 2 + 0.1))
            mb.box(c, (0.12, rafter_len, 0.14), wood, rot=rot, texel=1.2)
    # Pans de toit : l'arrière entier, l'avant crevé (trou en son milieu).
    for side in (-1, 1):
        rot = Matrix.Rotation(-side * slope, 3, "X")
        c = Vector((0, side * W / 4 + side * 0.12, 0.34 + (H + ridge) / 2 + 0.22))
        if side == 1:
            mb.box(c, (L + 0.8, rafter_len, 0.08), roof, rot=rot, texel=2.0)
        else:
            gap = (-1.2, 2.6)  # trou entre x=-1.2 et x=2.6, sur la moitié basse du pan
            seg_a = gap[0] - (-(L + 0.8) / 2)
            seg_b = (L + 0.8) / 2 - gap[1]
            mb.box(c + Vector((-(L + 0.8) / 2 + seg_a / 2, 0, 0)), (seg_a, rafter_len, 0.08), roof, rot=rot, texel=2.0)
            mb.box(c + Vector(((L + 0.8) / 2 - seg_b / 2, 0, 0)), (seg_b, rafter_len, 0.08), roof, rot=rot, texel=2.0)
            # Bande haute conservée au-dessus du trou.
            up_off = rot @ Vector((0, 1, 0)) * (rafter_len * 0.3)
            mb.box(c + Vector(((gap[0] + gap[1]) / 2, 0, 0)) - up_off * -1.0 * side,
                   (gap[1] - gap[0], rafter_len * 0.4, 0.08), roof, rot=rot, texel=2.0)
    mb.build("sawmill_shed")

    # Banc de scie : table longue + lame circulaire rouillée + une grume engagée.
    bench = MeshBuilder()
    bench.box((0, 0, 0.85), (5.0, 0.9, 0.1), planks, texel=1.5)
    for x in (-2.3, -0.8, 0.8, 2.3):
        for y in (-0.35, 0.35):
            bench.box((x, y, 0.4), (0.14, 0.14, 0.8), wood, texel=0.8)
    teeth = 28
    blade_pts = []
    for i in range(teeth * 2):
        a = i / (teeth * 2) * math.tau
        r = 0.62 if i % 2 == 0 else 0.55
        blade_pts.append((math.cos(a) * r, math.sin(a) * r))
    for yoff, flip in ((0.012, False), (-0.012, True)):
        idx = [bench.add_vert((0.4 + px, yoff, 0.95 + pz * 0.9 - 0.15)) for px, pz in blade_pts]
        uv = [(0.5 + px, 0.5 + pz) for px, pz in blade_pts]
        if flip:
            bench.add_face(idx, uv, m["iron"])
        else:
            bench.add_face(list(reversed(idx)), list(reversed(uv)), m["iron"])
    bench.tube([(-2.4, 0, 1.18), (-0.3, 0, 1.2)], [0.28, 0.27], 9, m["bark_oak"], cap_top=True, cap_bottom=True,
               cap_mat=m["wood_rings"])
    bench.build("saw_bench")

    # Pile de grumes : pyramide 4-3-2 le long de X, cales sur les côtés.
    pile = MeshBuilder()
    r = 0.26
    for row, count in enumerate((4, 3, 2)):
        for i in range(count):
            y = (i - (count - 1) / 2) * r * 2.02
            z = r + row * r * 1.72
            L2 = rng.uniform(3.4, 3.8)
            dx = rng.uniform(-0.15, 0.15)
            pile.tube([(-L2 / 2 + dx, y, z), (L2 / 2 + dx, y, z)], [r * rng.uniform(0.9, 1.05)] * 2, 9, m["bark_oak"],
                      cap_top=True, cap_bottom=True, cap_mat=m["wood_rings"])
    for sx in (-1.2, 1.2):
        for sy in (-1, 1):
            pile.box((sx, sy * 1.15, 0.3), (0.12, 0.12, 0.6), wood, texel=0.6)
    pile.build("log_pile")

    planks_pile = MeshBuilder()
    for layer in range(6):
        for i in range(4):
            if layer == 5 and i > 1:
                continue
            planks_pile.box((rng.uniform(-0.05, 0.05), (i - 1.5) * 0.3, 0.06 + layer * 0.07), (3.0, 0.28, 0.06),
                            m["planks_fresh"], rot=Matrix.Rotation(rng.uniform(-0.02, 0.02), 3, "Z"), texel=1.5)
    for x in (-1.2, 0, 1.2):
        planks_pile.box((x, 0, 0.02), (0.1, 1.3, 0.05), wood, texel=0.6)
    planks_pile.build("plank_pile")

    # Charrette cassée : plateau incliné, une roue au sol, l'autre en place.
    cart = MeshBuilder()
    tilt = Matrix.Rotation(0.2, 3, "Y") @ Matrix.Rotation(0.12, 3, "X")
    cart.box((0, 0, 0.55), (2.2, 1.2, 0.08), planks, rot=tilt, texel=1.2)
    for sy in (-1, 1):
        cart.box((0, sy * 0.58, 0.72), (2.2, 0.06, 0.3), planks, rot=tilt, texel=1.2)
    cart.box((1.7, 0.25, 0.35), (1.6, 0.07, 0.07), wood, rot=Matrix.Rotation(-0.35, 3, "Y"), texel=1.0)
    cart.box((1.7, -0.25, 0.35), (1.6, 0.07, 0.07), wood, rot=Matrix.Rotation(-0.35, 3, "Y"), texel=1.0)

    def wheel(center, axis_rot):
        spokes = 8
        rim = []
        for i in range(17):
            a = i / 16 * math.tau
            rim.append(Vector(center) + axis_rot @ Vector((math.cos(a) * 0.45, 0, math.sin(a) * 0.45)))
        cart.tube(rim, [0.045] * len(rim), 5, wood)
        for s in range(spokes):
            a = s / spokes * math.tau
            cart.tube([Vector(center), Vector(center) + axis_rot @ Vector((math.cos(a) * 0.43, 0, math.sin(a) * 0.43))],
                      [0.025, 0.025], 4, wood)

    wheel((-0.4, 0.68, 0.45), Matrix.Rotation(0.1, 3, "X"))
    wheel((-0.9, -1.2, 0.05), Matrix.Rotation(math.pi / 2, 3, "X"))
    cart.build("cart_broken")

    crate = MeshBuilder()
    crate.box((0, 0, 0.35), (0.7, 0.7, 0.7), m["planks_fresh"], texel=0.7)
    for z in (0.05, 0.65):
        for side in ("+x", "-x"):
            pass
    crate.build("crate")

    barrel = MeshBuilder()
    prof = [(0.28, 0.0), (0.33, 0.25), (0.34, 0.45), (0.33, 0.65), (0.28, 0.9)]
    barrel.tube([(0, 0, z) for _, z in prof], [r for r, _ in prof], 12, m["planks_old"], v_scale=0.8, cap_top=True,
                cap_mat=m["planks_old"])
    for z in (0.12, 0.78):
        barrel.tube([(0, 0, z - 0.03), (0, 0, z + 0.03)], [0.315 if z < 0.5 else 0.31] * 2, 12, m["iron"])
    barrel.build("barrel")


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


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
    os.makedirs(os.path.join(OUT, "props"), exist_ok=True)
    clear_scene()
    m = mats()

    nature = []
    for i, (h, cr, seed) in enumerate(((7.0, 2.6, 1), (8.2, 3.0, 2), (6.2, 2.4, 3))):
        nature.append(build_deciduous(f"tree_oak_{i}", m, seed, h, m["bark_oak"], m["foliage_oak"], 0.3, cr, 10).name)
    for i, (h, cr, seed) in enumerate(((8.5, 1.8, 7), (7.2, 1.6, 8))):
        nature.append(build_deciduous(f"tree_birch_{i}", m, seed, h, m["bark_birch"], m["foliage_birch"], 0.17, cr, 8,
                                      slim=True).name)
    for i, (h, r, seed) in enumerate(((10.0, 2.3, 11), (8.0, 1.9, 12), (12.0, 2.6, 13))):
        nature.append(build_fir(f"tree_fir_{i}", m, seed, h, r).name)
    nature.append(build_dead_tree("tree_dead_0", m, 21, 6.5).name)
    nature.append(build_stump("stump_0", m, 31, 0.35, 0.45).name)
    nature.append(build_stump("stump_1", m, 32, 0.28, 0.3).name)
    nature.append(build_log("log_0", m, 33, 3.2, 0.3).name)
    nature.append(build_bush("bush_0", m, 41, 0.9, m["foliage_oak"]).name)
    nature.append(build_bush("bush_1", m, 42, 0.7, m["foliage_birch"]).name)
    nature.append(build_rock("rock_0", m, 51, 0.6).name)
    nature.append(build_rock("rock_1", m, 52, 1.2, 0.55).name)
    nature.append(build_rock("rock_2", m, 53, 2.4, 0.5).name)
    nature.append(build_grass("grass_0", m, 61, 0.55, m["foliage_grass"]).name)
    nature.append(build_grass("grass_1", m, 62, 0.7, m["foliage_grass_seed"]).name)
    export("nature.glb", nature)

    # Éléments de nature posés à la main comme obstacles (scènes de props dédiées).
    for src, dst in (("rock_2", "rock_large"), ("rock_1", "rock_medium"), ("log_0", "log_fallen"),
                     ("stump_0", "stump"), ("tree_dead_0", "tree_dead")):
        export(f"props/{dst}.glb", [src])

    build_fountain(m)
    export("fountain.glb", ["fountain", "fountain_water_low", "fountain_water_high", "fountain_water_fall"])
    build_lamp_post(m)
    export("lamp_post.glb", ["lamp_post", "lamp_glass"])
    build_signpost(m)
    export("signpost.glb", ["signpost", "sign_board"])
    build_sawmill(m)
    for name in ("sawmill_shed", "saw_bench", "log_pile", "plank_pile", "cart_broken", "crate", "barrel"):
        export(f"props/{name}.glb", [name])


# Garde : build_village.py importe ce module pour ses outils (MeshBuilder, matériaux).
if __name__ == "__main__":
    main()
