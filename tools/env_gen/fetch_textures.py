"""Télécharge les textures d'environnement (sol, écorces, bois, pierre, feuillages) depuis
ambientCG (toutes CC0, voir assets/environment/CREDITS.md) et n'en garde que les cartes
utiles, redimensionnées, dans assets/environment/textures/.

Usage (depuis la racine du projet) :
    uv run --with pillow python tools/env_gen/fetch_textures.py

Les archives brutes sont mises en cache dans tools/env_gen/.cache/ (ignoré par git) : relancer
le script ne retélécharge rien. Sortie, par asset : <Asset>_color.jpg, <Asset>_normal.jpg
(convention OpenGL, celle de Godot), <Asset>_rough.jpg, et pour les atlas de feuillage
<Asset>_color.png (couleur + opacité fusionnées en RGBA, prête pour l'alpha scissor).
"""

import io
import os
import urllib.request
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(ROOT, "assets", "environment", "textures")

## asset ambientCG -> taille de sortie (px). Sols : 1024 (vus en permanence et de près) ;
## matériaux de props : 512 ; atlas de feuillage : 1024 (découpés ensuite par build_foliage.py).
MATERIALS = {
    # Sol (shader de terrain, voir scenes/maps/common/terrain_ground.gdshader)
    "Grass004": 1024,          # herbe
    "Ground037": 1024,         # sol forestier moussu
    "Ground067": 1024,         # chemin de terre
    "PavingStones138": 1024,   # pavés anciens moussus
    # Arbres
    "Bark012": 512,            # chêne
    "Bark014": 512,            # sapin
    "Bark001": 512,            # bouleau/écorce grise
    # Props
    "Planks023A": 512,         # vieilles planches grisées (scierie)
    "Planks021": 512,          # planches fraîches (piles, panneaux)
    "RoofingTiles001": 512,    # ardoises (toit de la scierie)
    "Wood051": 512,            # poutres sombres
    "Wood049": 512,            # bois clair (panneaux)
    "Bricks089": 512,          # maçonnerie moussue (fontaine)
    "Rock020": 512,            # pierre taillée lisse (fontaine, rochers)
    "Metal021": 512,           # fer rouillé (lampadaires, lame de scie)
    # Village fortifié (Place du village)
    "PavingStones151": 1024,   # pavés de ville en éventail (rues et place)
    "Bricks076A": 512,         # grand appareil gris (remparts, tours, porte)
    "Bricks102": 512,          # moellons (soubassements des maisons, puits)
    "Plaster003": 512,         # enduit à la chaux (murs à colombages)
    "RoofingTiles006": 512,    # tuiles de terre cuite (toits des maisons)
}
ATLASES = {
    "LeafSet024": 1024,        # feuilles de hêtre -> grappes de feuilles des feuillus
    "LeafSet023": 1024,        # feuilles claires -> bouleaux / buissons
    "LeafSet019": 1024,        # branches de sapin
    "Foliage001": 1024,        # brins d'herbe
    "Foliage006": 1024,        # brins d'herbe fins
    "Foliage002": 1024,        # graminées en épis
}


def fetch(asset_id: str) -> zipfile.ZipFile:
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{asset_id}_1K-JPG.zip")
    if not os.path.exists(path):
        url = f"https://ambientcg.com/get?file={asset_id}_1K-JPG.zip"
        print(f"  téléchargement {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "mud-godot-3d asset fetch"})
        with urllib.request.urlopen(req) as resp, open(path, "wb") as f:
            f.write(resp.read())
    return zipfile.ZipFile(path)


def find(zf: zipfile.ZipFile, suffix: str):
    for name in zf.namelist():
        if name.endswith(suffix):
            return name
    return None


def load(zf: zipfile.ZipFile, name: str) -> Image.Image:
    return Image.open(io.BytesIO(zf.read(name)))


def save_jpg(img: Image.Image, size: int, path: str) -> None:
    """`size` = plus grand côté : garde le ratio des textures non carrées (Bark001,
    Bricks089, PavingStones138 sont en 1:2), que le matériau répète tel quel."""
    img = img.convert("RGB")
    scale = size / max(img.width, img.height)
    if scale != 1.0:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    img.save(path, quality=90)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for asset_id, size in MATERIALS.items():
        print(asset_id)
        zf = fetch(asset_id)
        for suffix, tag in (("_Color.jpg", "color"), ("_NormalGL.jpg", "normal"), ("_Roughness.jpg", "rough")):
            name = find(zf, suffix)
            if name is None:
                print(f"  (pas de {suffix})")
                continue
            save_jpg(load(zf, name), size, os.path.join(OUT, f"{asset_id}_{tag}.jpg"))

    for asset_id, size in ATLASES.items():
        print(asset_id)
        zf = fetch(asset_id)
        color = load(zf, find(zf, "_Color.jpg")).convert("RGB")
        opacity = load(zf, find(zf, "_Opacity.jpg")).convert("L")
        rgba = color.copy()
        rgba.putalpha(opacity)
        if rgba.width != size:
            rgba = rgba.resize((size, size), Image.LANCZOS)
        rgba.save(os.path.join(OUT, f"{asset_id}_color.png"))
        normal = find(zf, "_NormalGL.jpg")
        if normal:
            save_jpg(load(zf, normal), size, os.path.join(OUT, f"{asset_id}_normal.jpg"))
    print("OK ->", OUT)


if __name__ == "__main__":
    main()
