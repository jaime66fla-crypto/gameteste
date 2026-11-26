"""Paletas dos tênis do 01 (uma PNG 256 x 256 por modelo da loja).

    python godot/tools/characters/paint_tenis.py

O tênis (tools/blender/build_tenis.py) tem o UV de cada peça no centro de uma
célula 4 x 4 desta textura, na ordem de PARTS. Trocar a PNG = outro modelo.
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                   "assets", "personagens", "01", "roupas")
PARTS = ["cabedal", "biqueira", "calcanhar", "faixa", "entressola", "faixa_sola",
         "borracha", "cadarco", "ilhos", "lingua", "forro", "cano"]
CELL = 64

DESIGNS = {
    # Asfalto: grafite, solado off-white, faixa e cadarço cinza-claro.
    "tenis_asfalto": {
        "cabedal": "#3a3d40", "biqueira": "#2c2e31", "calcanhar": "#2c2e31", "faixa": "#b9b8b0",
        "entressola": "#c9c6bd", "faixa_sola": "#8a8a86", "borracha": "#2b2b2b", "cadarco": "#cfcdc4",
        "ilhos": "#8a8a86", "lingua": "#2f3236", "forro": "#1f2022", "cano": "#2a2c2f",
    },
    # Brasa: camurça preta, faixa e cadarço laranja-brasa, sola de borracha crua.
    "tenis_brasa": {
        "cabedal": "#1d1c1b", "biqueira": "#262422", "calcanhar": "#262422", "faixa": "#c4521c",
        "entressola": "#d8d2c4", "faixa_sola": "#c4521c", "borracha": "#7e5130", "cadarco": "#d46a2c",
        "ilhos": "#e0dccf", "lingua": "#2a2725", "forro": "#7a2e10", "cano": "#231f1d",
    },
    # Noturno: azul-marinho, biqueira e calcanhar prata refletivo, faixa verde-água.
    "tenis_noturno": {
        "cabedal": "#1c2433", "biqueira": "#a3abb5", "calcanhar": "#8d96a1", "faixa": "#2fa39a",
        "entressola": "#1d1f22", "faixa_sola": "#2fa39a", "borracha": "#111213", "cadarco": "#c2cad3",
        "ilhos": "#38c2b6", "lingua": "#222b3b", "forro": "#14303a", "cano": "#1c2433",
    },
}

def build(name, d):
    img = Image.new("RGB", (CELL * 4, CELL * 4), (0, 0, 0))
    for i, part in enumerate(PARTS):
        x, y = (i % 4) * CELL, (i // 4) * CELL
        img.paste(Image.new("RGB", (CELL, CELL), d[part]), (x, y))
    img.save(os.path.join(OUT, name + ".png"))
    print("tenis:", name)

if __name__ == "__main__":
    for name, d in DESIGNS.items():
        build(name, d)
    build("tenis", DESIGNS["tenis_asfalto"])  # textura de base da malha
