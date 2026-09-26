"""Compose les textures de cartes de feuillage (alpha scissor) à partir des atlas ambientCG
téléchargés par fetch_textures.py : chaque feuille/brin des atlas est découpé (composantes
connexes de l'opacité), puis recollé en grappes prêtes à poser sur des quads.

Usage (depuis la racine du projet, après fetch_textures.py) :
    uv run --with pillow --with numpy --with scipy python tools/env_gen/build_foliage.py [--preview <png>]

Sortie dans assets/environment/textures/ :
    foliage_oak.png    grappe de feuilles de hêtre/chêne (feuillus)
    foliage_birch.png  grappe de petites feuilles claires (bouleaux, buissons)
    foliage_fir.png    rameau de sapin (pointe à droite, attache à gauche)
    foliage_grass.png  touffe d'herbe (base en bas au centre)
    foliage_grass_seed.png  touffe de graminées en épis
    wood_rings.jpg     section de tronc scié (souches, bouts de bûches)

Le RGB des pixels transparents est étendu depuis les feuilles voisines (pas de liseré sombre
quand les mipmaps mélangent bord et fond).
"""

import argparse
import math
import os
import random

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "environment", "textures"))


def sprites(atlas: str, min_px: int = 500) -> list:
    """Découpe chaque élément (feuille, brin, rameau) d'un atlas RGBA en sprite rogné."""
    im = Image.open(os.path.join(TEX, f"{atlas}_color.png")).convert("RGBA")
    alpha = np.array(im)[:, :, 3]
    labels, count = ndimage.label(alpha > 30)
    result = []
    for index, box in enumerate(ndimage.find_objects(labels), start=1):
        if box is None:
            continue
        mask = labels[box] == index
        if mask.sum() < min_px:
            continue
        crop = np.array(im)[box].copy()
        crop[:, :, 3] = np.where(mask, crop[:, :, 3], 0)
        result.append(Image.fromarray(crop))
    return result


def tint(sprite: Image.Image, brightness: float, saturation: float = 1.0) -> Image.Image:
    rgb = sprite.convert("RGB")
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    out = rgb.convert("RGBA")
    out.putalpha(sprite.getchannel("A"))
    return out


def bleed(img: Image.Image) -> Image.Image:
    """Étend la couleur des pixels opaques dans les zones transparentes (moyenne pondérée
    par l'alpha à plusieurs rayons), alpha inchangé."""
    arr = np.array(img).astype(np.float32)
    a = (arr[:, :, 3:4] > 20).astype(np.float32)
    rgb = arr[:, :, :3] * a
    filled = rgb.copy()
    weight = a.copy()
    for sigma in (2, 6, 16, 40):
        num = np.stack([ndimage.gaussian_filter(rgb[:, :, c], sigma) for c in range(3)], axis=2)
        den = ndimage.gaussian_filter(a[:, :, 0], sigma)[:, :, None]
        take = (weight[:, :, 0] < 0.5) & (den[:, :, 0] > 1e-4)
        filled[take] = (num / np.maximum(den, 1e-4))[take]
        weight[take] = 1.0
    arr[:, :, :3] = np.where(a > 0, arr[:, :, :3], filled)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


def leaf_cluster(atlas: str, size: int, count: int, leaf_len: tuple, seed: int,
                 base_brightness: float, saturation: float) -> Image.Image:
    """Grappe arrondie : feuilles tournées au hasard, plus denses au centre, assombries vers
    le bas et le cœur (occlusion factice) — reste lisible une fois posée sur une carte."""
    rng = random.Random(seed)
    leaves = sprites(atlas)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    center = size / 2
    placed = []
    for i in range(count):
        r = (rng.random() ** 0.7) * size * 0.36
        ang = rng.uniform(0, math.tau)
        x = center + math.cos(ang) * r
        y = center + math.sin(ang) * r * 0.9
        placed.append((y, x, r, ang))
    placed.sort()  # du haut vers le bas : les feuilles du bas passent devant
    for y, x, r, ang in placed:
        leaf = rng.choice(leaves)
        length = rng.uniform(*leaf_len)
        scale = length / max(leaf.size)
        leaf = leaf.resize((max(1, int(leaf.width * scale)), max(1, int(leaf.height * scale))), Image.LANCZOS)
        # Feuille orientée vers l'extérieur de la grappe (+ bruit), comme sur une branche.
        rot = -math.degrees(ang) + rng.uniform(-50, 50) - 90
        leaf = leaf.rotate(rot, expand=True, resample=Image.BICUBIC)
        depth = 1.0 - 0.35 * (1.0 - r / (size * 0.36))  # cœur plus sombre
        low = 1.0 - 0.25 * max(0.0, (y - center) / (size * 0.4))  # bas plus sombre
        leaf = tint(leaf, base_brightness * depth * low * rng.uniform(0.85, 1.1), saturation)
        canvas.alpha_composite(leaf, (int(x - leaf.width / 2), int(y - leaf.height / 2)))
    return bleed(canvas)


def fir_branch(size_w: int, size_h: int, seed: int) -> Image.Image:
    """Rameau de sapin horizontal (attache à gauche, pointe à droite) : trois brins de
    LeafSet019 en éventail, le principal au centre."""
    rng = random.Random(seed)
    sprigs = sorted(sprites("LeafSet019"), key=lambda s: -s.width * s.height)
    canvas = Image.new("RGBA", (size_w, size_h), (0, 0, 0, 0))
    for k, (angle, length, dy) in enumerate(((14, 0.78, -0.12), (-14, 0.8, 0.12), (0, 1.0, 0.0))):
        sprig = sprigs[k % len(sprigs)]
        # Les brins de l'atlas sont horizontaux, tige à droite : on les retourne pour avoir
        # l'attache à gauche.
        if sprig.width < sprig.height:
            sprig = sprig.rotate(90, expand=True)
        sprig = sprig.transpose(Image.FLIP_LEFT_RIGHT)
        scale = size_w * length / sprig.width
        sprig = sprig.resize((int(sprig.width * scale), int(sprig.height * scale)), Image.LANCZOS)
        sprig = sprig.rotate(angle, expand=True, resample=Image.BICUBIC)
        sprig = tint(sprig, rng.uniform(0.85, 1.0) * (1.0 if k == 2 else 0.8), 1.05)
        canvas.alpha_composite(sprig, (0, int(size_h / 2 - sprig.height / 2 + dy * size_h)))
    return bleed(canvas)


def grass_tuft(atlases: list, size: int, count: int, seed: int, brightness: float) -> Image.Image:
    """Touffe : brins redressés, en éventail depuis le bas-centre, hauteurs variées."""
    rng = random.Random(seed)
    blades = []
    for atlas in atlases:
        blades += sprites(atlas, 300)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for i in range(count):
        blade = rng.choice(blades)
        if blade.width > blade.height:
            blade = blade.rotate(90, expand=True)
        height = size * rng.uniform(0.55, 0.98)
        scale = height / blade.height
        blade = blade.resize((max(1, int(blade.width * scale)), int(height)), Image.LANCZOS)
        if rng.random() < 0.5:
            blade = blade.transpose(Image.FLIP_LEFT_RIGHT)
        lean = rng.uniform(-22, 22)
        blade = blade.rotate(lean, expand=True, resample=Image.BICUBIC)
        blade = tint(blade, brightness * rng.uniform(0.8, 1.15), 1.0)
        x = size / 2 + rng.uniform(-0.18, 0.18) * size - blade.width / 2 - math.sin(math.radians(lean)) * height / 2
        canvas.alpha_composite(blade, (int(x), size - blade.height))
    return bleed(canvas)


def wood_rings(size: int, seed: int) -> Image.Image:
    """Section de tronc scié (souches, bouts de bûches) : cernes concentriques légèrement
    ondulés, cœur plus sombre, fentes radiales, écorce sombre sur le pourtour."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = size / 2
    dx, dy = (xx - cx) / (size / 2), (yy - cy) / (size / 2)
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    noise_r = ndimage.gaussian_filter(rng.standard_normal((size, size)), 6) * 0.03
    wobble = 0.006 * np.sin(ang * 5 + 1.3) + 0.004 * np.sin(ang * 11 + 0.4) + noise_r
    rings = 0.5 + 0.5 * np.sin((r + wobble) * 55.0)
    rings = rings ** 3
    noise = ndimage.gaussian_filter(rng.standard_normal((size, size)), 1.2) * 0.08
    base = np.array([0.72, 0.56, 0.38])
    dark = np.array([0.50, 0.36, 0.22])
    t = np.clip(rings * 0.55 + noise + (1 - r) * 0.1, 0, 1)[:, :, None]
    color = dark + (base - dark) * t
    color *= (0.85 + 0.15 * np.clip(r, 0, 1))[:, :, None]  # cœur plus sombre
    for crack in rng.uniform(0, math.tau, 4):
        d = np.abs(np.sin(ang - crack)) * r
        mask = (d < 0.006) & (r < rng.uniform(0.35, 0.7)) & (np.cos(ang - crack) > 0)
        color[mask] *= 0.7
    bark = r > 0.9
    color[bark] = np.array([0.24, 0.18, 0.13]) * (0.8 + 0.4 * rng.random((bark.sum(), 1)))
    return Image.fromarray((color.clip(0, 1) * 255).astype(np.uint8), "RGB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview")
    args = parser.parse_args()

    outputs = {
        "foliage_oak": leaf_cluster("LeafSet024", 512, 95, (70, 105), 11, 0.8, 0.95),
        "foliage_birch": leaf_cluster("LeafSet023", 512, 120, (48, 72), 23, 0.95, 1.0),
        "foliage_fir": fir_branch(512, 256, 5),
        "foliage_grass": grass_tuft(["Foliage001", "Foliage006"], 256, 26, 7, 0.95),
        "foliage_grass_seed": grass_tuft(["Foliage002", "Foliage006"], 256, 18, 9, 1.0),
    }
    for name, img in outputs.items():
        img.save(os.path.join(TEX, f"{name}.png"))
        print(name, img.size)
    rings = wood_rings(256, 3)
    rings.save(os.path.join(TEX, "wood_rings.jpg"), quality=92)
    outputs["wood_rings"] = rings.convert("RGBA")

    if args.preview:
        tiles = list(outputs.values())
        sheet = Image.new("RGB", (256 * len(tiles), 256), (140, 110, 160))
        for i, img in enumerate(tiles):
            thumb = img.copy()
            thumb.thumbnail((256, 256))
            bg = Image.new("RGBA", thumb.size, (140, 110, 160, 255))
            bg.alpha_composite(thumb)
            sheet.paste(bg.convert("RGB"), (i * 256, 0))
        sheet.save(args.preview)


if __name__ == "__main__":
    main()
