#!/usr/bin/env python3
"""Dessine le logo d'Encoche : Resources/Encoche/AppIcon.png (1024 x 1024).

« Ondes » : un carré arrondi en dégradé violet vers orange, une encoche blanche au bord haut et trois anneaux
qui en partent, comme un signal (alerte, son). Nécessite Pillow et numpy (le dégradé) ; la construction de l'app n'en a pas
besoin : elle utilise l'image commitée.
Lancer : python3 scripts/make-icon.py
"""

import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2  # on dessine en 2048 puis on réduit : bords lissés
CANVAS = SIZE * SCALE
BODY = (100, 100, 924, 924)  # la grille d'icône macOS : 824 px au centre d'un carré de 1024

GRADIENT_TOP_LEFT = (88, 44, 220)
GRADIENT_BOTTOM_RIGHT = (255, 150, 80)
NOTCH_DOT = (176, 50, 150)
RINGS = ((215, 240), (335, 150), (455, 80))  # (rayon, opacité sur 255)
RING_WIDTH = 22


def scaled(value):
    return int(round(value * SCALE))


def scaled_box(box):
    return tuple(scaled(value) for value in box)


def blank():
    return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))


def squircle_mask(box, radius=185):
    """Le carré arrondi des icônes macOS : des coins arrondis simples de 185 px sur un carré de 824 px.
    Cette forme est reconnue par macOS, qui affiche alors l'icône à pleine taille. Une superellipse, même proche,
    ne l'est pas : l'icône se retrouve réduite sur une plaque grise."""
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(scaled_box(box), radius=scaled(radius), fill=255)
    return mask


def diagonal_gradient(start, end, diagonal=0.3):
    ys, xs = np.mgrid[0:CANVAS, 0:CANVAS].astype(np.float32)
    progress = np.clip((ys / CANVAS) * (1 - diagonal) + (xs / CANVAS) * diagonal, 0, 1)[..., None]
    start, end = np.array(start, np.float32), np.array(end, np.float32)
    rgb = (start + (end - start) * progress).astype(np.uint8)
    opaque = np.full((CANVAS, CANVAS, 1), 255, np.uint8)
    return Image.fromarray(np.concatenate([rgb, opaque], axis=2), "RGBA")


def clipped(layer, mask):
    result = layer.copy()
    result.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return result


def drop_shadow(mask):
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(ImageChops.offset(mask.point(lambda value: int(value * 0.5)), 0, scaled(22)))
    return shadow.filter(ImageFilter.GaussianBlur(scaled(26)))


def main():
    mask = squircle_mask(BODY)
    canvas = blank()
    canvas.alpha_composite(drop_shadow(mask))

    body = clipped(diagonal_gradient(GRADIENT_TOP_LEFT, GRADIENT_BOTTOM_RIGHT), mask)

    # Les anneaux, centrés sur l'encoche : la moitié basse seule est visible, le reste sort du carré.
    rings = blank()
    ring_draw = ImageDraw.Draw(rings)
    center_x, center_y = 512, BODY[1] + 40
    for radius, alpha in RINGS:
        ring_draw.ellipse(
            scaled_box((center_x - radius, center_y - radius, center_x + radius, center_y + radius)),
            outline=(255, 255, 255, alpha),
            width=scaled(RING_WIDTH),
        )
    body.alpha_composite(clipped(rings, mask))

    # L'encoche blanche collée au bord haut, avec son petit voyant.
    notch = blank()
    notch_draw = ImageDraw.Draw(notch)
    notch_draw.rounded_rectangle(
        scaled_box((512 - 150, BODY[1] - 200, 512 + 150, BODY[1] + 130)), radius=scaled(65), fill=(255, 255, 255, 255)
    )
    notch_draw.ellipse(scaled_box((512 - 22, BODY[1] + 64, 512 + 22, BODY[1] + 108)), fill=NOTCH_DOT + (255,))
    body.alpha_composite(clipped(notch, mask))

    canvas.alpha_composite(body)

    destination = os.path.join(os.path.dirname(__file__), "..", "Resources", "Encoche", "AppIcon.png")
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(destination)
    print(f"Logo écrit : {os.path.normpath(destination)}")


if __name__ == "__main__":
    main()
