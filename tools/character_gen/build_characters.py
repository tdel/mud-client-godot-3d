"""Générateur des mannequins low-poly joueurs (homme/femme) — squelette, corps, garde-robe
d'équipement et animations, exportés en glTF binaire pour Godot.

Usage (depuis la racine du projet) :
    blender -b --python tools/character_gen/build_characters.py
    blender -b --python tools/character_gen/build_characters.py -- --preview <dossier> \
        [--gender male|female] [--equip torso_plate,helmet_plate,weapon_sword,...]

Sortie : assets/characters/mannequin/{male,female}.glb. Chaque fichier contient :
  - un Armature aux noms de bones du profil humanoïde Godot (Hips, Spine, Chest, UpperChest,
    Neck, Head, Left/RightShoulder, *UpperArm, *LowerArm, *Hand, *UpperLeg, *LowerLeg, *Foot)
    — permet un retargeting Godot (BoneMap/SkeletonProfileHumanoid) sans table de
    correspondance si on veut un jour brancher d'autres animations ;
  - "Body" (corps en sous-vêtements) et "Hair" (caché par Character.gd sous un casque) ;
  - un mesh par pièce d'équipement ("torso_plate", "weapon_sword", ...), tous skinnés sur le
    même squelette et cachés par défaut côté Godot (Character.gd les montre selon l'équipement)
    — c'est ce qui garantit que chaque pièce épouse le gabarit homme OU femme ;
  - les animations idle/run/cast/launch/death/attack_1h/attack_2h (clips séparés).

Le mannequin est volontairement "segmenté" (chaque vertex pèse 1.0 sur un seul bone, pièces
qui se chevauchent aux articulations, façon mannequin de bois) : aucune peau à pondérer, et
toute pièce d'armure suit exactement le segment qu'elle recouvre.

Conventions d'espace (Blender) : Z haut, personnage face à -Y, sa gauche en +X. En T-pose,
paumes vers le bas (-Z), pouces vers l'avant (-Y) : une arme tenue a sa lame le long de -Y
dans le repère de repos de la main (côté pouce).
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "characters", "mannequin"))
FPS = 30


# ---------------------------------------------------------------------------------------------
# Gabarits
# ---------------------------------------------------------------------------------------------

MALE = {
	"name": "male",
	"scale": 1.0,
	"shoulder_x": 0.185,
	"hip_x": 0.09,
	# (demi-largeur X, demi-profondeur Y) du tronc à chaque niveau
	"pelvis": (0.155, 0.10),
	"waist": (0.135, 0.09),
	"chest": (0.165, 0.105),
	"shoulders": (0.175, 0.095),
	"upper_arm_r": (0.048, 0.040),
	"forearm_r": (0.042, 0.032),
	"thigh_r": (0.085, 0.058),
	"calf_r": (0.060, 0.042),
	"neck_r": 0.052,
	"breasts": False,
	"hair": "short",
}

FEMALE = {
	"name": "female",
	"scale": 1.68 / 1.78,
	"shoulder_x": 0.165,
	"hip_x": 0.095,
	"pelvis": (0.165, 0.105),
	"waist": (0.115, 0.080),
	"chest": (0.140, 0.090),
	"shoulders": (0.150, 0.085),
	"upper_arm_r": (0.040, 0.034),
	"forearm_r": (0.036, 0.028),
	"thigh_r": (0.090, 0.055),
	"calf_r": (0.055, 0.038),
	"neck_r": 0.045,
	"breasts": True,
	"hair": "ponytail",
}

# Longueurs de segments (gabarit homme, multipliées par "scale").
UPPER_ARM_LEN = 0.29
FOREARM_LEN = 0.26
HAND_LEN = 0.17
# Centre du poing depuis le poignet, le long du bone de la main : l'axe de la poignée d'arme
# passe par ce point (voir _weapon_grip).
FIST_OFFSET = 0.05


def joints(g):
	"""Positions de repos (espace armature) de toutes les articulations du gabarit `g`."""
	s = g["scale"]
	z = lambda v: v * s
	j = {
		"hips": Vector((0, 0, z(0.95))),
		"spine": Vector((0, 0, z(1.05))),
		"chest": Vector((0, 0, z(1.17))),
		"upper_chest": Vector((0, 0, z(1.30))),
		"neck": Vector((0, 0, z(1.44))),
		"head": Vector((0, 0, z(1.54))),
		"head_top": Vector((0, 0, z(1.78))),
	}
	for side, sx in (("Left", 1.0), ("Right", -1.0)):
		shoulder = Vector((sx * g["shoulder_x"], 0, z(1.42)))
		j[side + "Clavicle"] = Vector((sx * 0.02, 0, z(1.40)))
		j[side + "Shoulder"] = shoulder
		j[side + "Elbow"] = shoulder + Vector((sx * UPPER_ARM_LEN * s, 0, 0))
		j[side + "Wrist"] = j[side + "Elbow"] + Vector((sx * FOREARM_LEN * s, 0, 0))
		j[side + "Fingers"] = j[side + "Wrist"] + Vector((sx * HAND_LEN * s, 0, 0))
		j[side + "Hip"] = Vector((sx * g["hip_x"], 0, z(0.93)))
		j[side + "Knee"] = Vector((sx * g["hip_x"], 0, z(0.50)))
		j[side + "Ankle"] = Vector((sx * g["hip_x"], 0, z(0.085)))
		j[side + "Toes"] = Vector((sx * g["hip_x"], -z(0.15), z(0.02)))
	return j


# ---------------------------------------------------------------------------------------------
# Squelette
# ---------------------------------------------------------------------------------------------

def build_armature(g, j):
	arm_data = bpy.data.armatures.new(g["name"] + "_rig")
	rig = bpy.data.objects.new("Armature", arm_data)
	bpy.context.scene.collection.objects.link(rig)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode="EDIT")
	eb = arm_data.edit_bones

	def bone(name, head, tail, parent=None, roll=0.0):
		b = eb.new(name)
		b.head, b.tail, b.roll = head, tail, roll
		if parent:
			b.parent = eb[parent]
			b.use_connect = False
		return b

	bone("Hips", j["hips"], j["spine"])
	bone("Spine", j["spine"], j["chest"], "Hips")
	bone("Chest", j["chest"], j["upper_chest"], "Spine")
	bone("UpperChest", j["upper_chest"], j["neck"], "Chest")
	bone("Neck", j["neck"], j["head"], "UpperChest")
	bone("Head", j["head"], j["head_top"], "Neck")
	for side in ("Left", "Right"):
		bone(side + "Shoulder", j[side + "Clavicle"], j[side + "Shoulder"], "UpperChest")
		bone(side + "UpperArm", j[side + "Shoulder"], j[side + "Elbow"], side + "Shoulder")
		bone(side + "LowerArm", j[side + "Elbow"], j[side + "Wrist"], side + "UpperArm")
		bone(side + "Hand", j[side + "Wrist"], j[side + "Fingers"], side + "LowerArm")
		bone(side + "UpperLeg", j[side + "Hip"], j[side + "Knee"], "Hips")
		bone(side + "LowerLeg", j[side + "Knee"], j[side + "Ankle"], side + "UpperLeg")
		bone(side + "Foot", j[side + "Ankle"], j[side + "Toes"], side + "LowerLeg")
	bpy.ops.object.mode_set(mode="OBJECT")
	return rig


# ---------------------------------------------------------------------------------------------
# Géométrie : chaque primitive est posée en espace armature (pose de repos) et pèse 1.0 sur
# un seul bone.
# ---------------------------------------------------------------------------------------------

class MeshBuilder:
	def __init__(self, name, materials):
		self.name = name
		self.materials = materials
		self.bm = bmesh.new()
		self.deform = self.bm.verts.layers.deform.verify()
		self.groups = []

	def _group(self, bone):
		if bone not in self.groups:
			self.groups.append(bone)
		return self.groups.index(bone)

	def _mat(self, mat):
		if mat not in self.materials:
			self.materials.append(mat)
		return self.materials.index(mat)

	def add(self, verts, faces, bone, mat, smooth=True):
		gi, mi = self._group(bone), self._mat(mat)
		new_verts = []
		for co in verts:
			v = self.bm.verts.new(co)
			v[self.deform][gi] = 1.0
			new_verts.append(v)
		for f in faces:
			face = self.bm.faces.new([new_verts[i] for i in f])
			face.material_index = mi
			face.smooth = smooth

	def add_bmesh(self, tmp, matrix, bone, mat, smooth=True):
		index = {v: i for i, v in enumerate(tmp.verts)}
		verts = [matrix @ v.co for v in tmp.verts]
		faces = [[index[v] for v in f.verts] for f in tmp.faces]
		tmp.free()
		self.add(verts, faces, bone, mat, smooth)

	def build(self, rig):
		bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
		mesh = bpy.data.meshes.new(self.name)
		self.bm.to_mesh(mesh)
		self.bm.free()
		obj = bpy.data.objects.new(self.name, mesh)
		bpy.context.scene.collection.objects.link(obj)
		for m in self.materials:
			mesh.materials.append(MATERIALS[m])
		for bone in self.groups:
			obj.vertex_groups.new(name=bone)
		obj.parent = rig
		mod = obj.modifiers.new("Armature", "ARMATURE")
		mod.object = rig
		return obj


def frame_for(axis, hint):
	"""Repère orthonormé (u, v) perpendiculaire à `axis`, u aligné au mieux sur `hint`."""
	a = axis.normalized()
	u = hint - a * hint.dot(a)
	if u.length < 1e-6:
		u = Vector((0, 1, 0)) - a * a.y
	u.normalize()
	v = a.cross(u)
	return u, v


def loft(mb, rings, bone, mat, n=8, cap_start=True, cap_end=True, smooth=True, mats=None):
	"""Suite d'anneaux elliptiques (centre, u, v, rx, ry) reliés en tube. `mats` optionnel :
	matériau par tronçon (len(rings)-1 entrées) pour peindre des bandes (ex. sous-vêtement)."""
	verts, faces_by_mat = [], {}
	for c, u, v, rx, ry in rings:
		for k in range(n):
			t = 2 * math.pi * k / n
			verts.append(c + u * (rx * math.cos(t)) + v * (ry * math.sin(t)))
	for i in range(len(rings) - 1):
		m = mats[i] if mats else mat
		for k in range(n):
			a, b = i * n + k, i * n + (k + 1) % n
			faces_by_mat.setdefault(m, []).append((a, b, b + n, a + n))
	caps = []
	if cap_start:
		caps.append(tuple(reversed(range(n))))
	if cap_end:
		last = (len(rings) - 1) * n
		caps.append(tuple(range(last, last + n)))
	faces_by_mat.setdefault(mat, []).extend(caps)
	# Un seul appel add() par matériau, mais les faces référencent des vertices communs :
	# on duplique les vertices par matériau (coutures invisibles en low-poly).
	for m, faces in faces_by_mat.items():
		used = sorted({i for f in faces for i in f})
		remap = {old: new for new, old in enumerate(used)}
		mb.add([verts[i] for i in used], [tuple(remap[i] for i in f) for f in faces], bone, m, smooth)


def tube(mb, p0, p1, r0, r1, bone, mat, hint=Vector((0, -1, 0)), n=8, smooth=True, caps=(True, True)):
	"""Tube tronconique de p0 à p1. r0/r1 : rayon, ou (rx, ry) pour une section elliptique
	(rx le long de `hint`)."""
	r0 = r0 if isinstance(r0, tuple) else (r0, r0)
	r1 = r1 if isinstance(r1, tuple) else (r1, r1)
	u, v = frame_for(p1 - p0, hint)
	loft(mb, [(p0, u, v, r0[0], r0[1]), (p1, u, v, r1[0], r1[1])], bone, mat, n, caps[0], caps[1], smooth)


def ellipsoid(mb, center, radii, bone, mat, rot=None, seg=8, rings=6, smooth=True):
	tmp = bmesh.new()
	bmesh.ops.create_uvsphere(tmp, u_segments=seg, v_segments=rings, radius=1.0)
	m = Matrix.Translation(center) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((*radii, 1.0))
	mb.add_bmesh(tmp, m, bone, mat, smooth)


def box(mb, center, size, bone, mat, rot=None, smooth=False):
	tmp = bmesh.new()
	bmesh.ops.create_cube(tmp, size=1.0)
	m = Matrix.Translation(center) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1.0))
	mb.add_bmesh(tmp, m, bone, mat, smooth)


def wedge(mb, base, tip_offset, half_w, half_d, bone, mat):
	"""Pyramide à base rectangulaire (pointe de lame, crête de casque...)."""
	b = base
	verts = [b + Vector((-half_w, -half_d, 0)), b + Vector((half_w, -half_d, 0)),
		b + Vector((half_w, half_d, 0)), b + Vector((-half_w, half_d, 0)), b + tip_offset]
	faces = [(0, 1, 2, 3), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
	mb.add(verts, faces, bone, mat, smooth=False)


# ---------------------------------------------------------------------------------------------
# Matériaux (couleur de base + métal/rugosité, exportés tels quels en glTF)
# ---------------------------------------------------------------------------------------------

MATERIAL_DEFS = {
	"skin": ((0.80, 0.60, 0.47), 0.0, 0.7),
	"underwear": ((0.78, 0.74, 0.64), 0.0, 0.9),
	"hair": ((0.25, 0.15, 0.08), 0.0, 0.8),
	"eyes": ((0.05, 0.05, 0.07), 0.0, 0.4),
	"cloth": ((0.55, 0.47, 0.33), 0.0, 0.95),
	"cloth_dark": ((0.32, 0.25, 0.17), 0.0, 0.95),
	"robe": ((0.18, 0.22, 0.45), 0.0, 0.9),
	"robe_trim": ((0.75, 0.60, 0.25), 0.3, 0.5),
	"leather": ((0.40, 0.24, 0.12), 0.0, 0.75),
	"leather_dark": ((0.20, 0.12, 0.07), 0.0, 0.75),
	"steel": ((0.70, 0.72, 0.75), 0.5, 0.4),
	"steel_dark": ((0.38, 0.39, 0.43), 0.5, 0.5),
	"gold": ((0.85, 0.65, 0.25), 0.6, 0.4),
	"wood": ((0.45, 0.30, 0.16), 0.0, 0.8),
	"blade": ((0.85, 0.87, 0.90), 0.6, 0.25),
	"gem": ((0.30, 0.55, 0.95), 0.2, 0.2),
	"string": ((0.85, 0.82, 0.70), 0.0, 0.9),
	# Couleurs de la garde (tabard, écu) : garance, distincte du bleu des robes de mage.
	"tabard": ((0.50, 0.09, 0.08), 0.0, 0.9),
}
MATERIALS = {}


def build_materials():
	for name, (color, metallic, roughness) in MATERIAL_DEFS.items():
		mat = bpy.data.materials.new(name)
		mat.use_nodes = True
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		bsdf.inputs["Base Color"].default_value = (*color, 1.0)
		bsdf.inputs["Metallic"].default_value = metallic
		bsdf.inputs["Roughness"].default_value = roughness
		mat.diffuse_color = (*color, 1.0)
		MATERIALS[name] = mat


# ---------------------------------------------------------------------------------------------
# Corps
# ---------------------------------------------------------------------------------------------

def torso_rings(g, j, inflate=0.0, z_from=None, z_to=None):
	"""Anneaux du tronc (bas -> haut) avec le bone qui porte chaque tronçon. inflate élargit
	(armures) ; z_from/z_to découpent une tranche."""
	s = g["scale"]
	levels = [
		(0.86, (g["pelvis"][0] * 0.72, g["pelvis"][1] * 0.8), "Hips"),
		(0.93, g["pelvis"], "Hips"),
		(1.00, (g["pelvis"][0] * 0.97, g["pelvis"][1] * 0.95), "Hips"),
		(1.05, ((g["pelvis"][0] + g["waist"][0]) / 2, g["waist"][1]), "Spine"),
		(1.12, g["waist"], "Spine"),
		(1.19, ((g["waist"][0] + g["chest"][0]) / 2, g["chest"][1] * 0.95), "Chest"),
		(1.28, g["chest"], "Chest"),
		(1.36, g["shoulders"], "UpperChest"),
		(1.43, (g["shoulders"][0] * 0.9, g["shoulders"][1] * 0.85), "UpperChest"),
		(1.47, (g["neck_r"] * 1.6, g["neck_r"] * 1.3), "UpperChest"),
	]
	out = []
	for zl, (rx, ry), bone in levels:
		if z_from is not None and zl < z_from - 1e-6:
			continue
		if z_to is not None and zl > z_to + 1e-6:
			continue
		out.append((Vector((0, 0, zl * s)), rx + inflate, ry + inflate, bone))
	return out


def loft_torso(mb, rings, mat, n=12, smooth=True, cap_start=True, cap_end=True, mats=None):
	"""Comme loft(), mais chaque tronçon est pesé sur le bone de son anneau inférieur :
	on découpe en petits lofts à 2 anneaux (coutures dupliquées, invisibles en low-poly)."""
	X, Y = Vector((1, 0, 0)), Vector((0, 1, 0))
	for i in range(len(rings) - 1):
		c0, rx0, ry0, bone = rings[i]
		c1, rx1, ry1, _ = rings[i + 1]
		loft(mb, [(c0, X, Y, rx0, ry0), (c1, X, Y, rx1, ry1)], bone,
			mats[i] if mats else mat, n,
			cap_start and i == 0, cap_end and i == len(rings) - 2, smooth)


def torso_arc(mb, rings, mat, t_center, half, thickness=0.01, steps=6, smooth=False):
	"""Pan épais épousant le tronc (tabard) : secteur d'anneaux torso_rings entre les angles
	t_center +/- half (degrés ; -90 = devant, 90 = dos), épaisseur vers l'intérieur. Chaque
	tronçon est un solide fermé pesé sur le bone de son anneau inférieur (voir loft_torso)."""
	angles = [math.radians(t_center - half + 2 * half * k / steps) for k in range(steps + 1)]
	m = len(angles)

	def ring_points(c, rx, ry):
		outer = [c + Vector((rx * math.cos(t), ry * math.sin(t), 0)) for t in angles]
		inner = [c + Vector(((rx - thickness) * math.cos(t), (ry - thickness) * math.sin(t), 0)) for t in angles]
		return outer + inner

	for i in range(len(rings) - 1):
		c0, rx0, ry0, bone = rings[i]
		c1, rx1, ry1, _ = rings[i + 1]
		verts = ring_points(c0, rx0, ry0) + ring_points(c1, rx1, ry1)
		ao, ai, bo, bi = 0, m, 2 * m, 3 * m
		faces = []
		for k in range(m - 1):
			faces.append((ao + k, ao + k + 1, bo + k + 1, bo + k))
			faces.append((ai + k + 1, ai + k, bi + k, bi + k + 1))
			faces.append((ao + k, ai + k, ai + k + 1, ao + k + 1))
			faces.append((bo + k + 1, bi + k + 1, bi + k, bo + k))
		faces.append((ao, bo, bi, ai))
		faces.append((ao + m - 1, ai + m - 1, bi + m - 1, bo + m - 1))
		mb.add(verts, faces, bone, mat, smooth)


def build_body(g, j, rig):
	mb = MeshBuilder("Body", [])
	s = g["scale"]
	rings = torso_rings(g, j)
	# Bandes de sous-vêtement : slip sur les 3 premiers tronçons (0.86 -> 1.05), brassière
	# (femme) sur le tronçon poitrine.
	band = ["underwear", "underwear", "skin", "skin", "skin", "skin", "skin", "skin", "skin"]
	if g["breasts"]:
		band[5] = "underwear"
		band[6] = "underwear"
	band[1] = "underwear"
	loft_torso(mb, rings, "skin", mats=band)
	chest_bulges(mb, g, 0.0, "underwear" if g["breasts"] else "skin")
	# Cou + tête
	tube(mb, j["neck"] - Vector((0, 0, 0.03 * s)), j["head"] + Vector((0, 0, 0.04 * s)),
		g["neck_r"], g["neck_r"] * 0.9, "Neck", "skin", hint=Vector((1, 0, 0)))
	head_c = Vector((0, -0.01 * s, 1.655 * s))
	ellipsoid(mb, head_c, (0.085 * s, 0.10 * s, 0.115 * s), "Head", "skin", seg=10, rings=7)
	# Mâchoire/menton + nez + yeux : juste de quoi lire l'orientation du visage.
	ellipsoid(mb, head_c + Vector((0, -0.035 * s, -0.06 * s)), (0.065 * s, 0.065 * s, 0.06 * s), "Head", "skin", seg=8, rings=5)
	wedge(mb, head_c + Vector((0, -0.095 * s, -0.01 * s)), Vector((0, -0.03 * s, -0.035 * s)), 0.012 * s, 0.01 * s, "Head", "skin")
	for sx in (1, -1):
		box(mb, head_c + Vector((sx * 0.035 * s, -0.088 * s, 0.01 * s)), (0.022 * s, 0.01 * s, 0.012 * s), "Head", "eyes")
	# Bras
	for side, sx in (("Left", 1), ("Right", -1)):
		sh, el, wr = j[side + "Shoulder"], j[side + "Elbow"], j[side + "Wrist"]
		ua, fa = g["upper_arm_r"], g["forearm_r"]
		ellipsoid(mb, sh + Vector((-sx * 0.01, 0, -0.005)), (ua[0] * 1.35,) * 3, side + "UpperArm", "skin")
		tube(mb, sh, el, ua[0], ua[1], side + "UpperArm", "skin")
		ellipsoid(mb, el, (fa[0] * 1.05,) * 3, side + "LowerArm", "skin")
		tube(mb, el, wr, (fa[0], fa[0] * 0.95), (fa[1], fa[1] * 0.8), side + "LowerArm", "skin")
		build_fist(mb, side, sx, wr, s, "skin", "skin")
	# Jambes
	for side, sx in (("Left", 1), ("Right", -1)):
		hp, kn, an = j[side + "Hip"], j[side + "Knee"], j[side + "Ankle"]
		th, ca = g["thigh_r"], g["calf_r"]
		top = hp + Vector((0, 0, 0.02 * s))
		mid = hp.lerp(kn, 0.35)
		u, v = frame_for(kn - top, Vector((1, 0, 0)))
		loft(mb, [(top, u, v, th[0] * 0.95, th[0] * 1.05), (mid, u, v, th[0], th[0] * 1.05), (kn, u, v, th[1], th[1])],
			side + "UpperLeg", "skin", n=8)
		ellipsoid(mb, kn, (th[1] * 1.02,) * 3, side + "LowerLeg", "skin")
		calf = kn.lerp(an, 0.3) + Vector((0, 0.01 * s, 0))
		loft(mb, [(kn, u, v, th[1] * 0.95, th[1] * 0.95), (calf, u, v, ca[0], ca[0] * 1.1), (an + Vector((0, 0, 0.02 * s)), u, v, ca[1], ca[1])],
			side + "LowerLeg", "skin", n=8)
		build_foot(mb, side, j, s, "skin", 0.0)
	return mb.build(rig)


def chest_bulges(mb, g, inflate, mat, smooth=True):
	"""Poitrine (femme) ou pectoraux (homme, sinon le torse paraît cylindrique) — repris
	gonflés par chaque haut d'armure pour qu'ils ne transpercent pas."""
	s = g["scale"]
	if g["breasts"]:
		for sx in (1, -1):
			ellipsoid(mb, Vector((sx * 0.06 * s, -0.07 * s, 1.30 * s)),
				(0.055 * s + inflate, 0.045 * s + inflate, 0.05 * s + inflate), "Chest", mat, seg=8, rings=5, smooth=smooth)
	else:
		ellipsoid(mb, Vector((0, -0.065, 1.31)), (0.135 + inflate, 0.045 + inflate, 0.06 + inflate), "Chest", mat,
			seg=10, rings=5, smooth=smooth)


def build_fist(mb, side, sx, wrist, s, mat, thumb_mat, inflate=0.0):
	"""Poing fermé (moufle) le long de +/-X en T-pose, paume vers -Z, pouce vers -Y."""
	c = wrist + Vector((sx * (FIST_OFFSET * s), 0, 0))
	box(mb, c, (0.095 * s + inflate, 0.085 * s + inflate, 0.05 * s + inflate), side + "Hand", mat, smooth=False)
	box(mb, c + Vector((-sx * 0.015 * s, -0.045 * s, -0.012 * s)), (0.045 * s + inflate, 0.022 * s + inflate, 0.022 * s + inflate),
		side + "Hand", thumb_mat, smooth=False)


def build_foot(mb, side, j, s, mat, inflate, height=None):
	an = j[side + "Ankle"]
	x = an.x
	h = (height or 0.09) * s
	heel_y, toe_y = 0.045 * s + inflate, -0.17 * s - inflate
	w = 0.045 * s + inflate
	# Semelle d'une botte (inflate > 0) sous celle du pied : sinon les deux faces se
	# confondent (z-fighting, peau visible sous les bottes d'un personnage à terre).
	sole = -inflate * 0.5
	verts = [
		Vector((x - w, heel_y, sole)), Vector((x + w, heel_y, sole)), Vector((x + w, toe_y, sole)), Vector((x - w, toe_y, sole)),
		Vector((x - w * 0.9, heel_y, h)), Vector((x + w * 0.9, heel_y, h)), Vector((x + w * 0.85, toe_y + 0.03 * s, 0.035 * s + inflate)),
		Vector((x - w * 0.85, toe_y + 0.03 * s, 0.035 * s + inflate)),
	]
	faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
	mb.add(verts, faces, side + "Foot", mat, smooth=False)


def build_hair(g, j, rig):
	mb = MeshBuilder("Hair", [])
	s = g["scale"]
	head_c = Vector((0, -0.01 * s, 1.655 * s))
	ellipsoid(mb, head_c + Vector((0, 0.012 * s, 0.025 * s)), (0.093 * s, 0.103 * s, 0.108 * s), "Head", "hair", seg=10, rings=7)
	if g["hair"] == "ponytail":
		base = head_c + Vector((0, 0.10 * s, 0.03 * s))
		tube(mb, base, base + Vector((0, 0.05 * s, -0.20 * s)), 0.035 * s, 0.015 * s, "Head", "hair", hint=Vector((1, 0, 0)), n=6)
		ellipsoid(mb, base, (0.04 * s,) * 3, "Head", "hair", seg=6, rings=4)
	return mb.build(rig)


# ---------------------------------------------------------------------------------------------
# Garde-robe. Nommage : "<slot>_<variante>" — voir Character.gd (EQUIPMENT_VISUALS) pour le
# choix de la variante à partir des objets du jeu.
# ---------------------------------------------------------------------------------------------

def arm_sleeve(mb, j, g, side, mat, inflate, upper_to=1.0, lower=False, flare=0.0, n=8):
	s = g["scale"]
	sh, el, wr = j[side + "Shoulder"], j[side + "Elbow"], j[side + "Wrist"]
	ua, fa = g["upper_arm_r"], g["forearm_r"]
	end = sh.lerp(el, upper_to)
	r_end = ua[0] + (ua[1] - ua[0]) * upper_to
	tube(mb, sh - (el - sh).normalized() * 0.03 * s, end, ua[0] * 1.3 + inflate, r_end + inflate, side + "UpperArm", mat, n=n)
	if lower:
		tube(mb, el, wr - (wr - el).normalized() * 0.02 * s, fa[0] + inflate, fa[1] + inflate + flare, side + "LowerArm", mat, n=n)


def leg_shell(mb, j, g, side, mat, inflate, upper=(0.0, 1.0), lower=None, flare=0.0, n=8, smooth=True):
	s = g["scale"]
	hp, kn, an = j[side + "Hip"], j[side + "Knee"], j[side + "Ankle"]
	th, ca = g["thigh_r"], g["calf_r"]
	if upper:
		# Même profil que la cuisse du corps (voir build_body), gonflé : un simple tronc de cône
		# laissait ressortir la peau au-dessus du genou.
		top = hp + Vector((0, 0, 0.03 * s))
		u, v = frame_for(kn - top, Vector((1, 0, 0)))
		mid = hp.lerp(kn, 0.35)
		rings = [(top, u, v, th[0] * 0.95 + inflate, th[0] * 1.05 + inflate),
			(mid, u, v, th[0] + inflate, th[0] * 1.05 + inflate),
			(kn, u, v, th[1] * 1.02 + inflate, th[1] * 1.02 + inflate)]
		loft(mb, rings, side + "UpperLeg", mat, n, smooth=smooth)
	if lower:
		p0, p1 = kn.lerp(an, lower[0]), kn.lerp(an, lower[1])
		tube(mb, p0, p1, ca[0] + inflate, ca[0] + (ca[1] - ca[0]) * lower[1] + inflate + flare, side + "LowerLeg", mat,
			hint=Vector((1, 0, 0)), n=n, smooth=smooth)


def build_torso_sets(g, j, rig):
	s = g["scale"]
	out = []

	# Tunique de tissu : buste + manches courtes + petite jupe.
	mb = MeshBuilder("torso_cloth", [])
	loft_torso(mb, torso_rings(g, j, 0.012, 0.93, 1.43), "cloth", cap_start=False)
	chest_bulges(mb, g, 0.012, "cloth")
	for side in ("Left", "Right"):
		arm_sleeve(mb, j, g, side, "cloth", 0.01, upper_to=0.45)
	belt = torso_rings(g, j, 0.02, 1.00, 1.05)
	loft_torso(mb, belt, "cloth_dark", cap_start=False, cap_end=False)
	out.append(mb.build(rig))

	# Cuir : plastron brun, ceinture, épaulières souples.
	mb = MeshBuilder("torso_leather", [])
	loft_torso(mb, torso_rings(g, j, 0.016, 0.93, 1.43), "leather", cap_start=False)
	chest_bulges(mb, g, 0.016, "leather")
	loft_torso(mb, torso_rings(g, j, 0.026, 1.00, 1.05), "leather_dark", cap_start=False, cap_end=False)
	for side, sx in (("Left", 1), ("Right", -1)):
		arm_sleeve(mb, j, g, side, "leather", 0.012, upper_to=0.55)
		ellipsoid(mb, j[side + "Shoulder"] + Vector((0, 0, 0.02 * s)), (0.075 * s, 0.07 * s, 0.045 * s), side + "UpperArm", "leather_dark", seg=8, rings=4)
	out.append(mb.build(rig))

	# Plaques : cuirasse facettée, épaulières, tassettes.
	mb = MeshBuilder("torso_plate", [])
	loft_torso(mb, torso_rings(g, j, 0.03, 1.00, 1.43), "steel", n=10, smooth=False, cap_start=False)
	chest_bulges(mb, g, 0.03, "steel", smooth=False)
	loft_torso(mb, torso_rings(g, j, 0.036, 1.00, 1.05), "gold", n=10, smooth=False, cap_start=False, cap_end=False)
	for side, sx in (("Left", 1), ("Right", -1)):
		sh = j[side + "Shoulder"]
		ellipsoid(mb, sh + Vector((sx * 0.02 * s, 0, 0.025 * s)), (0.095 * s, 0.085 * s, 0.06 * s), side + "UpperArm", "steel", seg=8, rings=4, smooth=False)
		ellipsoid(mb, sh + Vector((sx * 0.03 * s, 0, 0.035 * s)), (0.07 * s, 0.07 * s, 0.05 * s), side + "UpperArm", "gold", seg=8, rings=4, smooth=False)
		arm_sleeve(mb, j, g, side, "steel_dark", 0.015, upper_to=0.8, n=6)
	# Tassettes : plaques devant/derrière/côtés sur le bassin
	pel = g["pelvis"]
	for angle in (0, 60, 120, 180, 240, 300):
		a = math.radians(angle)
		c = Vector((math.sin(a) * (pel[0] + 0.03), -math.cos(a) * (pel[1] + 0.03), 0.92 * s))
		rot = Matrix.Rotation(-a, 4, "Z")
		box(mb, c, (0.085 * s, 0.015 * s, 0.12 * s), "Hips", "steel", rot=rot)
	out.append(mb.build(rig))

	# Garde (PNJ de type GUARD, voir Character.NPC_OUTFITS) : cuirasse de plaques sous un tabard
	# garance à losange doré (pans devant/derrière, le métal reste visible sur les flancs),
	# gorgerin, grosses épaulières à deux lames, manches de mailles, ceinture de cuir.
	mb = MeshBuilder("torso_guard", [])
	loft_torso(mb, torso_rings(g, j, 0.03, 1.00, 1.47), "steel", n=10, smooth=False, cap_start=False)
	chest_bulges(mb, g, 0.03, "steel", smooth=False)
	for t_center, half in ((-90, 55), (90, 60)):
		torso_arc(mb, torso_rings(g, j, 0.055, 1.00, 1.43), "tabard", t_center, half, thickness=0.01)
	loft_torso(mb, torso_rings(g, j, 0.07, 1.00, 1.05), "leather_dark", n=10, smooth=False, cap_start=False, cap_end=False)
	pel = g["pelvis"]
	box(mb, Vector((0, -(pel[1] * 0.95 + 0.075), 1.025 * s)), (0.05 * s, 0.012, 0.04 * s), "Hips", "gold")
	chest_ry = g["chest"][1] + 0.065
	box(mb, Vector((0, -chest_ry, 1.27 * s)), (0.07 * s, 0.01, 0.07 * s), "Chest", "gold",
		rot=Matrix.Rotation(math.radians(45), 4, "Y"))
	tube(mb, j["neck"] - Vector((0, 0, 0.04 * s)), j["neck"] + Vector((0, 0, 0.04 * s)),
		(g["neck_r"] * 1.75, g["neck_r"] * 1.55), (g["neck_r"] * 1.45, g["neck_r"] * 1.3), "UpperChest", "steel",
		hint=Vector((1, 0, 0)), n=10, smooth=False)
	for side, sx in (("Left", 1), ("Right", -1)):
		sh = j[side + "Shoulder"]
		ellipsoid(mb, sh + Vector((sx * 0.02 * s, 0, 0.03 * s)), (0.105 * s, 0.095 * s, 0.065 * s), side + "UpperArm", "steel", seg=8, rings=4, smooth=False)
		ellipsoid(mb, sh + Vector((sx * 0.045 * s, 0, -0.015 * s)), (0.09 * s, 0.088 * s, 0.05 * s), side + "UpperArm", "steel_dark", seg=8, rings=4, smooth=False)
		ellipsoid(mb, sh + Vector((sx * 0.02 * s, 0, 0.09 * s)), (0.018 * s,) * 3, side + "UpperArm", "gold", seg=6, rings=4, smooth=False)
		arm_sleeve(mb, j, g, side, "steel_dark", 0.015, upper_to=1.0, n=6)
		# Pans du tabard sous la ceinture : un par cuisse, devant et derrière, qui suivent la
		# jambe (segments rigides, même compromis que la robe) ; ourlet doré.
		hp = j[side + "Hip"]
		for fy in (-1, 1):
			y = fy * (pel[1] + 0.055)
			box(mb, Vector((hp.x * 0.92, y, 0.84 * s)), (0.135 * s, 0.012, 0.26 * s), side + "UpperLeg", "tabard")
			box(mb, Vector((hp.x * 0.92, y, 0.705 * s)), (0.14 * s, 0.016, 0.022 * s), side + "UpperLeg", "gold")
	for angle in (60, 120, 240, 300):
		a = math.radians(angle)
		c = Vector((math.sin(a) * (pel[0] + 0.03), -math.cos(a) * (pel[1] + 0.03), 0.92 * s))
		box(mb, c, (0.085 * s, 0.015 * s, 0.12 * s), "Hips", "steel", rot=Matrix.Rotation(-a, 4, "Z"))
	out.append(mb.build(rig))

	# Robe de mage : longue, manches évasées, bordure dorée ; les pans de jupe suivent les
	# cuisses/tibias (segments rigides), un compromis low-poly contre le clipping en course.
	mb = MeshBuilder("torso_robe", [])
	loft_torso(mb, torso_rings(g, j, 0.014, 0.86, 1.43), "robe", cap_start=False)
	chest_bulges(mb, g, 0.014, "robe")
	loft_torso(mb, torso_rings(g, j, 0.024, 1.03, 1.07), "robe_trim", cap_start=False, cap_end=False)
	for side in ("Left", "Right"):
		arm_sleeve(mb, j, g, side, "robe", 0.012, upper_to=1.0, lower=True, flare=0.03)
		leg_shell(mb, j, g, side, "robe", 0.035, upper=(0.0, 1.0), lower=(0.0, 0.85), flare=0.035)
		kn, an = j[side + "Knee"], j[side + "Ankle"]
		hem = kn.lerp(an, 0.85)
		tube(mb, hem, hem + Vector((0, 0, -0.03 * s)), g["calf_r"][1] + 0.075 * s, g["calf_r"][1] + 0.075 * s,
			side + "LowerLeg", "robe_trim", hint=Vector((1, 0, 0)))
	out.append(mb.build(rig))
	return out


def build_legs_sets(g, j, rig):
	s = g["scale"]
	out = []
	for variant, mat, inflate, smooth in (("cloth", "cloth_dark", 0.01, True), ("leather", "leather", 0.014, True), ("plate", "steel", 0.024, False)):
		mb = MeshBuilder("legs_" + variant, [])
		loft_torso(mb, torso_rings(g, j, inflate, 0.86, 1.05), mat, smooth=smooth, cap_end=False)
		for side in ("Left", "Right"):
			leg_shell(mb, j, g, side, mat, inflate, upper=(0.0, 1.0), lower=(0.0, 0.8), smooth=smooth)
			if variant == "plate":
				ellipsoid(mb, j[side + "Knee"] + Vector((0, -0.03 * s, 0)), (0.07 * s, 0.06 * s, 0.07 * s), side + "LowerLeg", "gold", seg=8, rings=4, smooth=False)
		out.append(mb.build(rig))
	return out


def build_helmet_sets(g, j, rig):
	s = g["scale"]
	head_c = Vector((0, -0.01 * s, 1.655 * s))
	out = []
	# Calotte de cuir
	mb = MeshBuilder("helmet_leather", [])
	ellipsoid(mb, head_c + Vector((0, 0.01 * s, 0.03 * s)), (0.1 * s, 0.112 * s, 0.11 * s), "Head", "leather", seg=10, rings=6)
	tube(mb, head_c + Vector((0, 0.005 * s, 0.0)), head_c + Vector((0, 0.005 * s, 0.025 * s)), (0.105 * s, 0.117 * s), (0.105 * s, 0.117 * s),
		"Head", "leather_dark", hint=Vector((1, 0, 0)), n=10)
	out.append(mb.build(rig))
	# Heaume : cylindre facetté, visière sombre, crête dorée
	mb = MeshBuilder("helmet_plate", [])
	tube(mb, head_c + Vector((0, 0, -0.11 * s)), head_c + Vector((0, 0, 0.09 * s)), (0.115 * s, 0.125 * s), (0.11 * s, 0.12 * s),
		"Head", "steel", hint=Vector((1, 0, 0)), n=10, smooth=False)
	ellipsoid(mb, head_c + Vector((0, 0, 0.08 * s)), (0.11 * s, 0.12 * s, 0.07 * s), "Head", "steel", seg=10, rings=5, smooth=False)
	box(mb, head_c + Vector((0, -0.12 * s, 0.0)), (0.13 * s, 0.02 * s, 0.022 * s), "Head", "eyes")
	box(mb, head_c + Vector((0, 0, 0.15 * s)), (0.02 * s, 0.2 * s, 0.03 * s), "Head", "gold")
	out.append(mb.build(rig))
	# Chapel de fer de la garde : calotte au-dessus des sourcils, large bord incliné, bandeau
	# doré et arête. Visage dégagé et cheveux visibles dessous (queue de cheval de la femme
	# comprise, voir HAIR_VISIBLE_HELMETS) : c'est ce qui distingue gardes hommes et femmes.
	mb = MeshBuilder("helmet_guard", [])
	base = head_c + Vector((0, 0.012 * s, 0.03 * s))
	r0x, r0y, dome_h = 0.106 * s, 0.117 * s, 0.13 * s
	X, Y = Vector((1, 0, 0)), Vector((0, 1, 0))
	dome = []
	for k in range(6):
		h = dome_h * k / 6
		f = math.sqrt(max(0.0, 1.0 - (h / dome_h) ** 2))
		dome.append((base + Vector((0, 0, h)), X, Y, r0x * f, r0y * f))
	loft(mb, dome, "Head", "steel", n=12, cap_start=False, smooth=False)
	brim_in, brim_out, drop = 0.004 * s, 0.06 * s, 0.03 * s
	brim = [
		(base, X, Y, r0x + brim_in, r0y + brim_in),
		(base + Vector((0, 0, -drop)), X, Y, r0x + brim_out, r0y + brim_out),
		(base + Vector((0, 0, -drop - 0.012 * s)), X, Y, r0x + brim_out, r0y + brim_out),
		(base + Vector((0, 0, -0.012 * s)), X, Y, r0x + brim_in, r0y + brim_in),
		(base, X, Y, r0x + brim_in, r0y + brim_in),
	]
	loft(mb, brim, "Head", "steel_dark", n=12, cap_start=False, cap_end=False, smooth=False)
	tube(mb, base + Vector((0, 0, 0.005 * s)), base + Vector((0, 0, 0.03 * s)), (r0x + 0.006 * s, r0y + 0.006 * s),
		(r0x * 0.98 + 0.006 * s, r0y * 0.98 + 0.006 * s), "Head", "gold", hint=X, n=12, smooth=False)
	box(mb, base + Vector((0, 0, dome_h - 0.005 * s)), (0.022 * s, 0.2 * s, 0.025 * s), "Head", "steel")
	out.append(mb.build(rig))
	# Capuche de mage
	mb = MeshBuilder("helmet_hood", [])
	ellipsoid(mb, head_c + Vector((0, 0.015 * s, 0.02 * s)), (0.108 * s, 0.12 * s, 0.125 * s), "Head", "robe", seg=10, rings=7)
	wedge(mb, head_c + Vector((0, 0.08 * s, 0.05 * s)), Vector((0, 0.08 * s, -0.06 * s)), 0.05 * s, 0.03 * s, "Head", "robe")
	tube(mb, head_c + Vector((0, 0, -0.12 * s)), head_c + Vector((0, 0.01 * s, -0.16 * s)), (0.1 * s, 0.1 * s), (0.14 * s, 0.13 * s),
		"Neck", "robe", hint=Vector((1, 0, 0)), n=10)
	out.append(mb.build(rig))
	# Diadème : laisse les cheveux visibles (voir Character.gd, HAIR_VISIBLE_HELMETS).
	mb = MeshBuilder("helmet_circlet", [])
	tube(mb, head_c + Vector((0, 0.01 * s, 0.035 * s)), head_c + Vector((0, 0.01 * s, 0.055 * s)), (0.1 * s, 0.112 * s), (0.098 * s, 0.11 * s),
		"Head", "gold", hint=Vector((1, 0, 0)), n=10, smooth=False)
	ellipsoid(mb, head_c + Vector((0, -0.105 * s, 0.05 * s)), (0.018 * s, 0.012 * s, 0.022 * s), "Head", "gem", seg=6, rings=4, smooth=False)
	out.append(mb.build(rig))
	return out


def build_gloves_sets(g, j, rig):
	s = g["scale"]
	out = []
	for variant, mat, cuff_mat, inflate, bracer in (("leather", "leather", "leather_dark", 0.012, 0.35), ("plate", "steel", "gold", 0.02, 0.7)):
		mb = MeshBuilder("gloves_" + variant, [])
		for side, sx in (("Left", 1), ("Right", -1)):
			build_fist(mb, side, sx, j[side + "Wrist"], s, mat, mat, inflate)
			el, wr = j[side + "Elbow"], j[side + "Wrist"]
			fa = g["forearm_r"]
			start = wr.lerp(el, bracer)
			tube(mb, start, wr + (wr - el).normalized() * 0.01 * s, fa[0] * 0.9 + inflate, fa[1] + inflate + 0.012 * s, side + "LowerArm", cuff_mat,
				n=8, smooth=variant != "plate")
		out.append(mb.build(rig))
	return out


def build_boots_sets(g, j, rig):
	s = g["scale"]
	out = []
	for variant, mat, trim, inflate, height in (("leather", "leather", "leather_dark", 0.012, 0.55), ("plate", "steel", "gold", 0.02, 0.95)):
		mb = MeshBuilder("boots_" + variant, [])
		for side in ("Left", "Right"):
			build_foot(mb, side, j, s, mat, inflate, height=0.1)
			leg_shell(mb, j, g, side, mat, inflate + 0.004, upper=None, lower=(1.0 - height, 1.0), smooth=variant != "plate")
			kn, an = j[side + "Knee"], j[side + "Ankle"]
			top = kn.lerp(an, 1.0 - height)
			r = g["calf_r"][0] + inflate + 0.012 * s
			tube(mb, top, top + Vector((0, 0, -0.025 * s)), r, r, side + "LowerLeg", trim, hint=Vector((1, 0, 0)))
		out.append(mb.build(rig))
	return out


# --- Armes : géométrie dans le repère de repos de la main (voir _weapon_grip). ---

def _weapon_grip(j, side, s):
	"""(centre du poing, axe lame, axe latéral) en espace armature, pose de repos."""
	sx = 1 if side == "Left" else -1
	c = j[side + "Wrist"] + Vector((sx * FIST_OFFSET * s, 0, 0))
	return c, Vector((0, -1, 0)), Vector((sx, 0, 0))


def _blade(mb, c, d, lat, start, length, width, thick, bone, mat="blade"):
	"""Lame plate de `start` à `start+length` le long de d, pointe comprise."""
	up = Vector((0, 0, 1))
	p0 = c + d * start
	body_len = length * 0.85
	half = [lat * width, up * thick]
	verts = []
	for p in (p0, p0 + d * body_len):
		verts += [p - half[0], p - half[1], p + half[0], p + half[1]]
	verts.append(p0 + d * length)
	faces = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 8), (5, 6, 8), (6, 7, 8), (7, 4, 8), (3, 2, 1, 0)]
	mb.add(verts, faces, bone, mat, smooth=False)


def build_weapons(g, j, rig):
	"""Armes en main droite (arc : main gauche, bouclier : avant-bras gauche). Les armes ne
	suivent pas le gabarit : même taille pour l'homme et la femme."""
	out = []
	c, b, lat = _weapon_grip(j, "Right", g["scale"])
	p = -b  # vers le pommeau
	up = Vector((0, 0, 1))  # plat de la lame en T-pose
	hand = "RightHand"

	def handle(length_pommel, length_blade, r, mat="leather_dark"):
		tube(mb, c + p * length_pommel, c + b * length_blade, r, r, hand, mat, hint=lat, n=6)

	mb = MeshBuilder("weapon_sword", [])
	handle(0.09, 0.06, 0.016)
	ellipsoid(mb, c + p * 0.1, (0.025,) * 3, hand, "gold", seg=6, rings=4, smooth=False)
	box(mb, c + b * 0.065, (0.2, 0.03, 0.035), hand, "gold")
	_blade(mb, c, b, lat, 0.08, 0.72, 0.028, 0.008, hand)
	out.append(mb.build(rig))

	# Épée courte de la garde : lame large et courte, garde et pommeau d'acier.
	mb = MeshBuilder("weapon_shortsword", [])
	handle(0.075, 0.05, 0.016)
	ellipsoid(mb, c + p * 0.085, (0.022,) * 3, hand, "steel_dark", seg=6, rings=4, smooth=False)
	box(mb, c + b * 0.058, (0.16, 0.028, 0.032), hand, "steel")
	_blade(mb, c, b, lat, 0.07, 0.5, 0.032, 0.008, hand)
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_dagger", [])
	handle(0.06, 0.05, 0.015)
	box(mb, c + b * 0.055, (0.1, 0.025, 0.025), hand, "steel_dark")
	_blade(mb, c, b, lat, 0.065, 0.3, 0.022, 0.006, hand)
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_mace", [])
	handle(0.1, 0.45, 0.018, "wood")
	ellipsoid(mb, c + b * 0.5, (0.06, 0.06, 0.06), hand, "steel_dark", seg=6, rings=4, smooth=False)
	for k in range(6):
		a = math.radians(60 * k)
		off = lat * math.cos(a) + up * math.sin(a)
		ellipsoid(mb, c + b * 0.5 + off * 0.055, (0.022,) * 3, hand, "steel", seg=4, rings=3, smooth=False)
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_axe", [])
	handle(0.1, 0.5, 0.017, "wood")
	head = c + b * 0.45
	# Fer côté "dos de la main" (-lat) pour que le tranchant frappe vers l'avant en attaque.
	e = -lat
	t_in, t_out = up * 0.012, up * 0.005
	verts = [head + t_in, head - t_in,
		head + e * 0.17 - b * 0.09 + t_out, head + e * 0.17 - b * 0.09 - t_out,
		head + e * 0.19 + b * 0.1 + t_out, head + e * 0.19 + b * 0.1 - t_out,
		head + e * 0.03 + b * 0.04 + t_in, head + e * 0.03 + b * 0.04 - t_in]
	faces = [(0, 2, 4, 6), (1, 7, 5, 3), (0, 1, 3, 2), (2, 3, 5, 4), (4, 5, 7, 6), (6, 7, 1, 0)]
	mb.add(verts, faces, hand, "steel", smooth=False)
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_wand", [])
	handle(0.05, 0.3, 0.012, "wood")
	ellipsoid(mb, c + b * 0.33, (0.03, 0.03, 0.03), hand, "gem", seg=6, rings=4, smooth=False)
	out.append(mb.build(rig))

	# Deux mains : la main droite tient la poignée près de la garde, la main gauche vient se
	# placer à TWO_HAND_SPACING côté pommeau (voir solve_two_hand_grip).
	mb = MeshBuilder("weapon_greatsword", [])
	handle(0.24, 0.06, 0.018)
	ellipsoid(mb, c + p * 0.25, (0.03,) * 3, hand, "gold", seg=6, rings=4, smooth=False)
	box(mb, c + b * 0.07, (0.3, 0.035, 0.04), hand, "gold")
	_blade(mb, c, b, lat, 0.09, 1.0, 0.04, 0.01, hand)
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_hammer", [])
	handle(0.24, 0.7, 0.02, "wood")
	box(mb, c + b * 0.72, (0.3, 0.13, 0.13), hand, "steel_dark")
	box(mb, c + b * 0.72, (0.32, 0.08, 0.08), hand, "steel")
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_staff", [])
	handle(0.7, 0.75, 0.019, "wood")
	ellipsoid(mb, c + b * 0.83, (0.05, 0.07, 0.05), hand, "gem", seg=6, rings=4, smooth=False)
	for k in range(4):
		a = math.radians(90 * k + 45)
		off = lat * math.cos(a) + up * math.sin(a)
		tube(mb, c + b * 0.72, c + b * 0.86 + off * 0.055, 0.01, 0.006, hand, "gold", hint=lat, n=4, smooth=False)
	out.append(mb.build(rig))

	mb = MeshBuilder("weapon_spear", [])
	handle(0.6, 1.1, 0.016, "wood")
	_blade(mb, c, b, lat, 1.08, 0.28, 0.035, 0.01, hand, "steel")
	out.append(mb.build(rig))

	# Arc : main GAUCHE, branches le long du poing (verticales une fois le bras baissé), ventre
	# de l'arc côté pouce (vers l'avant).
	cl, bl, _latl = _weapon_grip(j, "Left", g["scale"])
	mb = MeshBuilder("weapon_bow", [])
	along = Vector((1, 0, 0))
	pts = []
	for k in range(9):
		t = (k - 4) / 4.0
		pts.append(cl + along * (t * 0.6) + bl * (0.12 * (1 - t * t)))
	for a, e in zip(pts, pts[1:]):
		tube(mb, a, e, 0.016, 0.016, "LeftHand", "wood", hint=up, n=5)
	tube(mb, pts[0], pts[-1], 0.003, 0.003, "LeftHand", "string", hint=up, n=4)
	out.append(mb.build(rig))

	# Bouclier : sur l'avant-bras gauche, face vers l'extérieur (+Z en T-pose = dos de la main).
	el, wr = j["LeftElbow"], j["LeftWrist"]
	mb = MeshBuilder("shield_round", [])
	X, Y = Vector((1, 0, 0)), Vector((0, 1, 0))
	sc = el.lerp(wr, 0.55) + up * 0.06
	loft(mb, [(sc, X, Y, 0.27, 0.27), (sc + up * 0.04, X, Y, 0.24, 0.24)], "LeftLowerArm", "wood", n=12, smooth=False)
	tube(mb, sc + up * 0.0, sc + up * 0.025, 0.28, 0.28, "LeftLowerArm", "steel_dark", hint=X, n=12, smooth=False)
	ellipsoid(mb, sc + up * 0.04, (0.07, 0.07, 0.04), "LeftLowerArm", "gold", seg=8, rings=4, smooth=False)
	out.append(mb.build(rig))

	# Écu de la garde : bord plat côté coude, pointe côté poignet (vers le bas bras baissé),
	# légèrement bombé ; chant d'acier, champ garance, croix dorée.
	mb = MeshBuilder("shield_guard", [])
	outline = [(-0.26, 0.22), (-0.26, -0.22)]
	for k in range(7):
		t = k / 6 * math.pi / 2
		outline.append((0.34 * math.sin(t), -0.22 * math.cos(t)))
	for k in range(1, 7):
		t = math.pi / 2 - k / 6 * math.pi / 2
		outline.append((0.34 * math.sin(t), 0.22 * math.cos(t)))
	shield_slab(mb, sc, X, Y, up, outline, 1.0, 0.0, 0.03, "steel_dark")
	shield_slab(mb, sc, X, Y, up, outline, 0.88, 0.02, 0.038, "tabard")
	box(mb, sc + X * 0.03 + up * 0.041, (0.4, 0.055, 0.012), "LeftLowerArm", "gold")
	box(mb, sc + X * -0.08 + up * 0.041, (0.055, 0.3, 0.012), "LeftLowerArm", "gold")
	out.append(mb.build(rig))
	return out


# Bombé de l'écu : recul (vers le bras) = SHIELD_CURVE * v².
SHIELD_CURVE = 0.3


def shield_slab(mb, sc, U, V, N, outline, scale, z0, z1, mat, center=(0.03, 0.0)):
	"""Plaque épaisse (z0 -> z1 le long de N) au contour convexe `outline` [(u, v)], réduit
	de `scale` autour de `center`, bombée selon SHIELD_CURVE."""
	uc, vc = center

	def point(u, v, z):
		u, v = uc + (u - uc) * scale, vc + (v - vc) * scale
		return sc + U * u + V * v + N * (z - SHIELD_CURVE * v * v)

	n = len(outline)
	verts = [point(uc, vc, z1), point(uc, vc, z0)]
	verts += [point(u, v, z1) for u, v in outline]
	verts += [point(u, v, z0) for u, v in outline]
	faces = []
	for k in range(n):
		a, b = k, (k + 1) % n
		faces.append((0, 2 + a, 2 + b))
		faces.append((1, 2 + n + b, 2 + n + a))
		faces.append((2 + a, 2 + n + a, 2 + n + b, 2 + b))
	mb.add(verts, faces, "LeftLowerArm", mat, smooth=False)


# ---------------------------------------------------------------------------------------------
# Animation
#
# Les rotations sont exprimées en espace armature "parent au repos" : R appliquée au bone
# comme si ses parents étaient en pose de repos, puis la pose des parents s'y ajoute. Axes :
#   X (+ = gauche du perso), Y (+ = dos), Z (+ = haut).
#   - rotation +X : un bone vertical vers le haut bascule vers l'avant ; un bone pointant vers
#     le bas bascule vers l'arrière (jambe tendue vers l'arrière).
#   - rotation +Y : le bras gauche (T-pose) descend ; bras droit : -Y.
# Les helpers ci-dessous résolvent les signes gauche/droite.
# ---------------------------------------------------------------------------------------------

def R(axis, deg):
	return Quaternion(Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]), math.radians(deg))


def seq(*rots):
	"""Compose des rotations appliquées dans l'ordre donné (la première d'abord)."""
	q = Quaternion()
	for r in rots:
		q = r @ q
	return q


def sgn(side):
	return 1 if side == "Left" else -1


def upper_arm(side, down=0, fwd=0, across=0, twist=0):
	"""down : abaisse le bras depuis la T-pose ; fwd : lève vers l'avant (après abaissement) ;
	across : ramène vers l'axe du corps ; twist : rotation autour du bras."""
	k = sgn(side)
	return seq(R("X", twist * k), R("Y", down * k), R("X", -fwd), R("Z", -across * k))


def lower_arm(side, flex=0, twist=0):
	"""flex : plie le coude (avant-bras vers l'avant quand le bras pend) ; twist : pronation."""
	k = sgn(side)
	return seq(R("X", twist * k), R("Z", -flex * k))


def hand(side, bend=0, dev=0, twist=0):
	"""bend : flexion vers la paume ; dev : inclinaison côté pouce (-) / auriculaire (+), qui
	fait pivoter la lame d'une arme tenue."""
	k = sgn(side)
	return seq(R("X", twist * k), R("Y", bend * k), R("Z", dev * k))


def upper_leg(side, fwd=0, out=0):
	return seq(R("X", -fwd), R("Y", -out * sgn(side)))


def lower_leg(flex=0):
	return R("X", flex)


def foot(point=0):
	return R("X", point)


def spine(bend=0, side=0, twist=0):
	return seq(R("X", bend), R("Y", side), R("Z", twist))


def base_pose():
	"""Posture neutre bras le long du corps (toutes les poses partent de là)."""
	p = {}
	for side in ("Left", "Right"):
		p[side + "UpperArm"] = upper_arm(side, down=78, fwd=4)
		p[side + "LowerArm"] = lower_arm(side, flex=15)
		p[side + "Hand"] = hand(side, dev=65)
	return p


def merged(*dicts):
	out = {}
	for d in dicts:
		out.update(d)
	return out


class Animator:
	def __init__(self, rig):
		self.rig = rig
		self.rest = {b.name: b.matrix_local.to_quaternion() for b in rig.data.bones}
		self.rest_mat = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}

	def new_action(self, name):
		act = bpy.data.actions.new(name)
		act.use_fake_user = True
		self.rig.animation_data_create()
		self.rig.animation_data.action = act
		return act

	def key(self, frame, pose, hips_offset=Vector()):
		"""pose : {bone: Quaternion armature-space} ; les bones absents reviennent au repos
		(chaque clé fixe tous les bones pour que les clips ne se contaminent pas)."""
		for pb in self.rig.pose.bones:
			q_world = pose.get(pb.name, Quaternion())
			qb = self.rest[pb.name]
			pb.rotation_mode = "QUATERNION"
			pb.rotation_quaternion = qb.inverted() @ q_world @ qb
			pb.keyframe_insert("rotation_quaternion", frame=frame)
			if pb.name == "Hips":
				pb.location = self.rest_mat["Hips"].inverted() @ hips_offset
				pb.keyframe_insert("location", frame=frame)

	def finish(self, act, cyclic):
		for fc in _fcurves(act):
			for kp in fc.keyframe_points:
				kp.interpolation = "BEZIER"
		track = self.rig.animation_data.nla_tracks.new()
		track.name = act.name
		strip = track.strips.new(act.name, int(act.frame_range[0]), act)
		track.mute = True
		self.rig.animation_data.action = None


def _fcurves(act):
	"""Actions à slots (Blender 4.4+) : les F-curves vivent dans les channelbags des layers."""
	if hasattr(act, "layers") and act.layers:
		out = []
		for layer in act.layers:
			for strip in layer.strips:
				for bag in strip.channelbags:
					out.extend(bag.fcurves)
		return out
	return list(act.fcurves)


def anim_idle(an):
	act = an.new_action("idle")
	for f, breath in ((0, 0.0), (30, 1.0), (60, 0.0)):
		p = base_pose()
		p["Chest"] = spine(bend=-1.5 * breath)
		p["UpperChest"] = spine(bend=-1.0 * breath)
		p["Neck"] = spine(bend=2 * breath)
		for side in ("Left", "Right"):
			p[side + "UpperArm"] = upper_arm(side, down=78 - 2 * breath, fwd=4)
			p[side + "UpperLeg"] = upper_leg(side, out=3)
			p[side + "Foot"] = foot(0)
		an.key(f, p, Vector((0, 0, -0.004 * breath)))
	an.finish(act, True)


def anim_run(an):
	act = an.new_action("run")
	# 0 : jambe gauche devant ; 10 : jambe droite devant ; 5/15 : passage (corps haut).
	n = 20
	for f in range(0, n + 1, 5):
		phase = (f % n) / n * 2 * math.pi
		sw = math.cos(phase)  # +1 : gauche devant
		p = {}
		p["Hips"] = spine(twist=-8 * sw)
		p["Spine"] = spine(bend=10, twist=4 * sw)
		p["Chest"] = spine(bend=4, twist=6 * sw)
		p["Neck"] = spine(bend=-8, twist=-6 * sw)
		for side in ("Left", "Right"):
			k = sw if side == "Left" else -sw
			lift = math.sin(phase) if side == "Left" else -math.sin(phase)
			p[side + "UpperLeg"] = upper_leg(side, fwd=38 * k - 5)
			# genou très plié quand la jambe revient vers l'avant (lift > 0 : jambe en vol)
			p[side + "LowerLeg"] = lower_leg(20 + 55 * max(0.0, -k * 0.2 + lift * 0.9) + (10 if k < 0 else 0))
			p[side + "Foot"] = foot(10 * k)
			p[side + "UpperArm"] = upper_arm(side, down=72, fwd=-38 * k + 8)
			p[side + "LowerArm"] = lower_arm(side, flex=75 + 10 * k)
			p[side + "Hand"] = hand(side, dev=10)
		bob = 0.03 * abs(math.sin(phase))
		an.key(f, p, Vector((0, 0, -0.03 + bob)))
	an.finish(act, True)


def cast_pose(t):
	"""Canalisation : mains réunies devant la poitrine, qui tournent doucement."""
	a = t * 2 * math.pi
	p = {}
	p["Spine"] = spine(bend=-3)
	p["Chest"] = spine(bend=-2 + 1.5 * math.sin(a))
	p["Neck"] = spine(bend=6)
	for side in ("Left", "Right"):
		k = 1 if side == "Left" else -1
		p[side + "UpperArm"] = upper_arm(side, down=82, fwd=40 + 6 * math.cos(a) * k, across=12 + 4 * math.sin(a))
		p[side + "LowerArm"] = lower_arm(side, flex=68 + 8 * math.sin(a) * k, twist=-50)
		p[side + "Hand"] = hand(side, bend=-25, dev=10)
		p[side + "UpperLeg"] = upper_leg(side, fwd=8 if side == "Left" else -6, out=6)
		p[side + "LowerLeg"] = lower_leg(8)
	return p


def anim_cast(an):
	act = an.new_action("cast")
	for f in range(0, 37, 6):
		an.key(f, cast_pose(f / 36.0), Vector((0, 0, -0.02)))
	an.finish(act, True)


def anim_launch(an):
	"""Libération du sort : armé bras droit en arrière, puis poussée des deux paumes."""
	act = an.new_action("launch")
	an.key(0, cast_pose(0), Vector((0, 0, -0.02)))
	p = cast_pose(0)
	p["Spine"] = spine(bend=-6, twist=18)
	p["Chest"] = spine(bend=-4, twist=12)
	p["RightUpperArm"] = upper_arm("Right", down=80, fwd=-25)
	p["RightLowerArm"] = lower_arm("Right", flex=110, twist=-40)
	p["LeftUpperArm"] = upper_arm("Left", down=85, fwd=60, across=15)
	an.key(7, p, Vector((0, 0.02, -0.03)))
	p = merged(cast_pose(0), {})
	p["Spine"] = spine(bend=12, twist=-10)
	p["Chest"] = spine(bend=6, twist=-6)
	p["Neck"] = spine(bend=-10)
	for side in ("Left", "Right"):
		p[side + "UpperArm"] = upper_arm(side, down=88, fwd=82, across=14)
		p[side + "LowerArm"] = lower_arm(side, flex=8)
		p[side + "Hand"] = hand(side, bend=-60)
	p["LeftUpperLeg"] = upper_leg("Left", fwd=25, out=6)
	p["LeftLowerLeg"] = lower_leg(30)
	p["RightUpperLeg"] = upper_leg("Right", fwd=-18, out=4)
	p["RightLowerLeg"] = lower_leg(10)
	an.key(12, p, Vector((0, -0.08, -0.06)))
	an.key(17, p, Vector((0, -0.08, -0.06)))
	an.key(28, merged(base_pose(), {"LeftUpperLeg": upper_leg("Left", out=3), "RightUpperLeg": upper_leg("Right", out=3)}))
	an.finish(act, False)


def anim_death(an):
	act = an.new_action("death")
	idle = merged(base_pose(), {"LeftUpperLeg": upper_leg("Left", out=3), "RightUpperLeg": upper_leg("Right", out=3)})
	an.key(0, idle)
	# Impact : recul, tête en arrière, bras qui s'écartent
	p = merged(base_pose())
	p["Spine"] = spine(bend=-12)
	p["Chest"] = spine(bend=-8)
	p["Neck"] = spine(bend=-20)
	for side in ("Left", "Right"):
		p[side + "UpperArm"] = upper_arm(side, down=50, fwd=25)
		p[side + "LowerArm"] = lower_arm(side, flex=40)
	p["LeftUpperLeg"] = upper_leg("Left", fwd=15)
	p["RightUpperLeg"] = upper_leg("Right", fwd=-10)
	an.key(6, p, Vector((0, 0.06, -0.02)))
	# Genoux qui lâchent
	p = merged(p)
	p["Hips"] = spine(bend=-15)
	p["Spine"] = spine(bend=10)
	p["Neck"] = spine(bend=15)
	for side in ("Left", "Right"):
		p[side + "UpperLeg"] = upper_leg(side, fwd=70, out=8)
		p[side + "LowerLeg"] = lower_leg(110)
		p[side + "Foot"] = foot(-20)
		p[side + "UpperArm"] = upper_arm(side, down=60, fwd=10)
	an.key(16, p, Vector((0, 0.10, -0.42)))
	# Au sol, sur le dos
	p = {}
	p["Hips"] = spine(bend=-88)
	p["Spine"] = spine(bend=-2)
	p["Neck"] = spine(bend=-6, twist=20)
	p["Head"] = spine(twist=10)
	for side in ("Left", "Right"):
		k = 1 if side == "Left" else -1
		p[side + "UpperArm"] = upper_arm(side, down=35 if side == "Left" else 60, fwd=-5)
		p[side + "LowerArm"] = lower_arm(side, flex=25 if side == "Left" else 60)
		p[side + "UpperLeg"] = upper_leg(side, fwd=8 if side == "Left" else 20, out=10)
		p[side + "LowerLeg"] = lower_leg(5 if side == "Left" else 30)
		p[side + "Foot"] = foot(-15)
	s = an.scale
	an.key(26, p, Vector((0, 0.45, -0.80 * s)))
	an.key(30, p, Vector((0, 0.46, -0.82 * s)))
	an.key(40, p, Vector((0, 0.46, -0.82 * s)))
	an.finish(act, False)


def weapon_ready():
	"""Garde, lame tenue devant, main droite."""
	p = merged(base_pose())
	p["RightUpperArm"] = upper_arm("Right", down=75, fwd=15)
	p["RightLowerArm"] = lower_arm("Right", flex=60)
	p["RightHand"] = hand("Right", dev=0)
	return p


def anim_attack_1h(an):
	act = an.new_action("attack_1h")
	legs = {
		"LeftUpperLeg": upper_leg("Left", fwd=18, out=6), "LeftLowerLeg": lower_leg(20),
		"RightUpperLeg": upper_leg("Right", fwd=-12, out=6), "RightLowerLeg": lower_leg(12),
	}
	an.key(0, merged(weapon_ready(), legs))
	# Armé : épée levée au-dessus de l'épaule droite, lame vers l'arrière
	p = merged(weapon_ready(), legs)
	p["Spine"] = spine(bend=-4, twist=25)
	p["Chest"] = spine(twist=15)
	p["RightUpperArm"] = upper_arm("Right", down=-10, fwd=35)
	p["RightLowerArm"] = lower_arm("Right", flex=100)
	p["RightHand"] = hand("Right", dev=35)
	p["LeftUpperArm"] = upper_arm("Left", down=55, fwd=35)
	p["LeftLowerArm"] = lower_arm("Left", flex=50)
	an.key(9, p, Vector((0, 0.03, -0.03)))
	# Frappe : diagonale vers l'avant-bas gauche
	p = merged(weapon_ready(), legs)
	p["Spine"] = spine(bend=14, twist=-25)
	p["Chest"] = spine(bend=4, twist=-15)
	p["RightUpperArm"] = upper_arm("Right", down=85, fwd=55, across=30)
	p["RightLowerArm"] = lower_arm("Right", flex=10)
	p["RightHand"] = hand("Right", dev=45)
	p["LeftUpperArm"] = upper_arm("Left", down=70, fwd=-20)
	p["LeftLowerArm"] = lower_arm("Left", flex=40)
	an.key(14, p, Vector((0, -0.06, -0.06)))
	an.key(18, p, Vector((0, -0.06, -0.06)))
	an.key(27, merged(weapon_ready(), legs))
	an.finish(act, False)


# Écart entre les deux poings sur une poignée à deux mains (vers le pommeau, +d en repos).
TWO_HAND_SPACING = 0.11


def two_hand_right(down, fwd, across, flex, dev, twist=0):
	return {
		"RightUpperArm": upper_arm("Right", down=down, fwd=fwd, across=across),
		"RightLowerArm": lower_arm("Right", flex=flex, twist=twist),
		"RightHand": hand("Right", dev=dev),
	}


def anim_attack_2h(an):
	act = an.new_action("attack_2h")
	legs = {
		"LeftUpperLeg": upper_leg("Left", fwd=22, out=8), "LeftLowerLeg": lower_leg(25),
		"RightUpperLeg": upper_leg("Right", fwd=-15, out=8), "RightLowerLeg": lower_leg(15),
	}
	ready = merged(base_pose(), legs, two_hand_right(70, 30, 30, 55, -5))
	keys = [(0, ready, Vector((0, 0, -0.03)))]
	# Armé : arme au-dessus de l'épaule droite, lame vers l'arrière
	p = merged(base_pose(), legs, two_hand_right(-5, 55, 25, 110, 45))
	p["Spine"] = spine(bend=-8, twist=30)
	p["Chest"] = spine(bend=-4, twist=12)
	keys.append((13, p, Vector((0, 0.04, -0.04))))
	# Frappe verticale vers l'avant-bas
	p = merged(base_pose(), legs, two_hand_right(85, 55, 35, 10, 50))
	p["Spine"] = spine(bend=22, twist=-12)
	p["Chest"] = spine(bend=8, twist=-6)
	keys.append((20, p, Vector((0, -0.08, -0.10))))
	keys.append((25, p, Vector((0, -0.08, -0.10))))
	keys.append((36, ready, Vector((0, 0, -0.03))))
	for f, pose, off in keys:
		an.key(f, pose, off)
	solve_two_hand_grip(an, act, 0, 36)
	an.finish(act, False)


def solve_two_hand_grip(an, act, f0, f1):
	"""IK analytique du bras gauche, image par image : le poing gauche se place sur la poignée
	(TWO_HAND_SPACING sous le poing droit) avec la même orientation que la main droite."""
	rig = an.rig
	scene = bpy.context.scene
	rig.animation_data.action = act
	pb = rig.pose.bones
	bones = rig.data.bones
	s = an.scale
	L_ua, L_fa = UPPER_ARM_LEN * s, FOREARM_LEN * s
	for f in range(f0, f1 + 1):
		scene.frame_set(f)
		bpy.context.view_layer.update()
		rh = pb["RightHand"].matrix
		r_rot = rh.to_3x3()
		r_rest = bones["RightHand"].matrix_local.to_3x3()
		# Repère "monde" de la main droite -> rotation delta depuis le repos
		delta = r_rot @ r_rest.inverted()
		right_fist = rh.to_translation() + delta @ Vector((-FIST_OFFSET * s, 0, 0))
		handle_up = delta @ Vector((0, 1, 0))  # vers le pommeau
		left_fist = right_fist + handle_up * TWO_HAND_SPACING
		# Même orientation que la droite (poings empilés, voir docstring) :
		left_delta = delta
		left_wrist = left_fist - left_delta @ Vector((FIST_OFFSET * s, 0, 0))
		shoulder = pb["LeftUpperArm"].head
		# Deux os : coude sur le plan contenant la direction "bas-arrière-extérieur".
		to_t = left_wrist - shoulder
		dist = min(to_t.length, (L_ua + L_fa) * 0.999)
		dir_t = to_t.normalized()
		pole = Vector((0.6, 0.5, -0.6)).normalized()
		pole = (pole - dir_t * pole.dot(dir_t)).normalized()
		cos_a = (L_ua ** 2 + dist ** 2 - L_fa ** 2) / (2 * L_ua * dist)
		cos_a = max(-1.0, min(1.0, cos_a))
		a = math.acos(cos_a)
		elbow = shoulder + dir_t * (math.cos(a) * L_ua) + pole * (math.sin(a) * L_ua)
		_aim_bone(rig, "LeftUpperArm", elbow - shoulder)
		bpy.context.view_layer.update()
		_aim_bone(rig, "LeftLowerArm", left_wrist - elbow)
		bpy.context.view_layer.update()
		_orient_bone(rig, "LeftHand", left_delta @ bones["LeftHand"].matrix_local.to_3x3())
		for name in ("LeftUpperArm", "LeftLowerArm", "LeftHand"):
			pb[name].keyframe_insert("rotation_quaternion", frame=f)
	rig.animation_data.action = act


def _parent_rest_frame(rig, name):
	"""Orientation (espace armature) du bone `name` avec rotation locale nulle."""
	pb = rig.pose.bones[name]
	b = rig.data.bones[name]
	if pb.parent is None:
		return b.matrix_local.to_3x3()
	return pb.parent.matrix.to_3x3() @ b.parent.matrix_local.to_3x3().inverted() @ b.matrix_local.to_3x3()


def _orient_bone(rig, name, desired3):
	base = _parent_rest_frame(rig, name)
	rig.pose.bones[name].rotation_quaternion = (base.inverted() @ desired3).to_quaternion()


def _aim_bone(rig, name, direction):
	base = _parent_rest_frame(rig, name)
	y0 = base.col[1].normalized()
	swing = y0.rotation_difference(direction.normalized()).to_matrix()
	_orient_bone(rig, name, swing @ base)


# ---------------------------------------------------------------------------------------------
# Construction / export / aperçu
# ---------------------------------------------------------------------------------------------

def build_character(g):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.render.fps = FPS
	build_materials()
	j = joints(g)
	rig = build_armature(g, j)
	objs = [build_body(g, j, rig), build_hair(g, j, rig)]
	objs += build_torso_sets(g, j, rig)
	objs += build_legs_sets(g, j, rig)
	objs += build_helmet_sets(g, j, rig)
	objs += build_gloves_sets(g, j, rig)
	objs += build_boots_sets(g, j, rig)
	objs += build_weapons(g, j, rig)
	an = Animator(rig)
	an.scale = g["scale"]
	anim_idle(an)
	anim_run(an)
	anim_cast(an)
	anim_launch(an)
	anim_death(an)
	anim_attack_1h(an)
	anim_attack_2h(an)
	return rig, objs


def export(g, rig):
	os.makedirs(OUT_DIR, exist_ok=True)
	path = os.path.join(OUT_DIR, g["name"] + ".glb")
	for obj in bpy.data.objects:
		obj.hide_set(False)
		obj.hide_render = False
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format="GLB",
		export_animation_mode="ACTIONS",
		export_force_sampling=True,
		export_frame_step=1,
		export_def_bones=False,
		export_apply=False,
		export_yup=True,
		export_skins=True,
		export_morph=False,
		export_materials="EXPORT",
		export_reset_pose_bones=True,
	)
	print("EXPORTED", path)


def preview(g, rig, out_dir, equip, anim_frames):
	"""Planche contact : pour chaque animation, quelques images vues de 3/4 face et de profil."""
	import numpy as np
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "MATERIAL"
	scene.render.resolution_x = 260
	scene.render.resolution_y = 360
	scene.render.film_transparent = False
	world = bpy.data.worlds.new("w")
	scene.world = world
	world.color = (0.12, 0.12, 0.14)
	visible = {"Body", "Hair"} | set(equip)
	for obj in bpy.data.objects:
		if obj.type == "MESH":
			obj.hide_render = obj.name not in visible
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = 2.6
	views = [("3q", math.radians(-35)), ("side", math.radians(90))]
	rows = []
	for anim, frames in anim_frames:
		act = bpy.data.actions[anim]
		rig.animation_data.action = act
		for view_name, ang in views:
			tiles = []
			for f in frames:
				scene.frame_set(f)
				d = 6.0
				cam.location = Vector((math.sin(ang) * d, -math.cos(ang) * d, 0.9))
				cam.rotation_euler = (math.radians(90), 0, ang)
				path = os.path.join(out_dir, "_tile.png")
				scene.render.filepath = path
				bpy.ops.render.render(write_still=True)
				img = bpy.data.images.load(path)
				arr = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
				bpy.data.images.remove(img)
				tiles.append(arr)
			rows.append(np.concatenate(tiles, axis=1))
		rig.animation_data.action = None
	width = max(r.shape[1] for r in rows)
	rows = [np.pad(r, ((0, 0), (0, width - r.shape[1]), (0, 0))) for r in rows]
	sheet = np.concatenate(rows[::-1], axis=0)  # pixels Blender : origine en bas
	img = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0])
	img.pixels = sheet.ravel()
	img.filepath_raw = os.path.join(out_dir, "sheet_%s.png" % g["name"])
	img.file_format = "PNG"
	img.save()
	print("PREVIEW", img.filepath_raw)


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	preview_dir, genders, equip, anims = None, ["male", "female"], [], None
	i = 0
	while i < len(argv):
		if argv[i] == "--preview":
			preview_dir = argv[i + 1]; i += 1
		elif argv[i] == "--gender":
			genders = [argv[i + 1]]; i += 1
		elif argv[i] == "--equip":
			equip = [e for e in argv[i + 1].split(",") if e]; i += 1
		elif argv[i] == "--anims":
			anims = argv[i + 1].split(","); i += 1
		i += 1
	for name in genders:
		g = {"male": MALE, "female": FEMALE}[name]
		rig, _objs = build_character(g)
		if preview_dir:
			frames = {
				"idle": [0, 30], "run": [0, 5, 10, 15], "cast": [0, 12, 24], "launch": [0, 7, 12, 28],
				"death": [0, 6, 16, 26, 40], "attack_1h": [0, 9, 14, 27], "attack_2h": [0, 13, 20, 36],
			}
			sel = [(a, frames[a]) for a in (anims or frames.keys())]
			preview(g, rig, preview_dir, equip, sel)
		else:
			export(g, rig)


main()
