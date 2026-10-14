"""Rewrites the Thai lettering of the opening comic in English.

The artwork (tools/comic/intro_comic_source.jpg) has its text painted into the
panels, so every line is removed by inpainting the glyphs away and drawing the
English over the repaired art. The result, scenes/cutscenes/intro_comic.jpg, is
what the opening cutscene slices into panels.

    python tools/comic/localize_comic.py

Coordinates are in source-image pixels (1536 x 1024).
"""

from __future__ import annotations

import os
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "comic" / "intro_comic_source.jpg"
TARGET = ROOT / "scenes" / "cutscenes" / "intro_comic.jpg"
## The cutscene only plays the first six panels, so the game ships the top two
## rows; the whole translated page is kept beside the source for reference.
REFERENCE = ROOT / "tools" / "comic" / "intro_comic_en_full.jpg"
SHIPPED = (0, 0, 1536, 556)

FONTS = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
COMIC = str(FONTS / "comic.ttf")
COMIC_BOLD = str(FONTS / "comicbd.ttf")

# The twelve panels, left to right then top to bottom: x0, y0, x1, y1.
PANELS = [
    (10, 8, 493, 303), (505, 8, 992, 303), (1006, 8, 1502, 303),
    (6, 310, 451, 548), (459, 310, 853, 548), (865, 310, 1535, 548),
    (10, 558, 433, 752), (461, 558, 875, 752), (888, 558, 1535, 752),
    (10, 769, 451, 1017), (462, 769, 929, 1017), (959, 769, 1529, 1017),
]

# Title plates: the cream box in each panel's top-left corner (x, y, w, h).
PLATES = [
    ((10, 9, 154, 33), "1. After class one day..."),
    ((506, 9, 102, 33), "2. Back home..."),
    ((1010, 8, 148, 34), "3. The wrong carton..."),
    ((10, 313, 185, 35), "4. He never checked the date..."),
    ((462, 313, 120, 34), "5. One big gulp..."),
    ((866, 315, 132, 32), "6. Something feels off..."),
    ((10, 559, 151, 30), "7. The hallucinations start..."),
    ((461, 558, 171, 31), "8. His friends turn into..."),
    ((889, 558, 156, 30), "9. The teacher from another dimension"),
    ((8, 771, 91, 32), "10. Peak panic!"),
    ((463, 771, 100, 31), "11. Waking up..."),
    ((962, 769, 178, 34), "12. Kopiko's lesson"),
]

# Speech balloons: the white blob is refilled, so only a seed box is needed.
# (box, inset fraction, text, font, max size)
BALLOONS = [
    ((15, 58, 152, 115), 0.17, "So stressed...\nway too much\nwork, my brain\nis melting", COMIC, 16),
    ((837, 43, 156, 127), 0.17, "A yoghurt drink\nwould take the\nedge off...", COMIC, 16),
    ((1391, 25, 115, 80), 0.16, "This one!", COMIC_BOLD, 19),
    ((21, 821, 150, 153), 0.20, "I just drank\nEXPIRED milk\nDIDN'T I?!!", COMIC_BOLD, 17),
    ((798, 800, 120, 99), 0.15, "A dream...?\nor was that\nfor real?!", COMIC, 18),
]

# Lettering painted straight onto the art: (x0, y0, x1, y1, polarity, text,
# font, size, fill, outline, anchor, angle). Polarity says whether the glyphs
# are lighter or darker than the art behind them, which is what the inpainting
# mask keys off.
ART_TEXT = [
    # 4 - the expiry label on the carton, tilted with the box.
    (155, 356, 305, 404, "dark", "EXPIRED", COMIC_BOLD, 26, (38, 30, 36), None, "center", -9),
    (158, 398, 338, 450, "dark", "02/05/23", COMIC_BOLD, 38, (34, 28, 34), None, "center", -9),
    (150, 452, 340, 498, "dark", "(7 MONTHS AGO)", COMIC_BOLD, 21, (38, 30, 36), None, "center", -9),
    # 5 - the drinking sound effect.
    (748, 418, 858, 472, "light", "GULP~", COMIC_BOLD, 30, (24, 22, 26), (248, 246, 240), "center", 0),
    # 6 - 9: white lettering over the hallucination.
    (1222, 380, 1330, 455, "light", "Hmmm...\nwhat is this?", COMIC, 20, (245, 243, 240), (18, 14, 22), "center", 0),
    (28, 610, 190, 670, "light", "The classroom...\nit's floating?!", COMIC, 17, (240, 238, 236), (18, 14, 22), "left", 0),
    (268, 680, 436, 716, "light", "The books can fly?!", COMIC, 17, (240, 238, 236), (18, 14, 22), "right", 0),
    (492, 700, 664, 752, "light", "What happened\nto everyone?!", COMIC, 17, (240, 238, 236), (18, 14, 22), "left", 0),
    (945, 662, 1036, 700, "light", "Homework =", COMIC, 22, (214, 216, 214), None, "left", -2),
    (1344, 548, 1512, 736, "light", "Remember...\nhomework never ends.\nYou will study...\nforever...", COMIC, 19, (242, 240, 238), (18, 14, 22), "left", 0),
    # 12 - the closing lesson on the flat yellow card.
    (980, 836, 1176, 980, "dark", "Always check the\nexpiry date before\nyou drink yoghurt milk,\nfor your own sanity...", COMIC_BOLD, 21, (40, 32, 28), None, "center", 0),
    (1440, 974, 1526, 1012, "light", "THE END", COMIC_BOLD, 17, (242, 240, 236), None, "center", 0),
]

PLATE_FILL = (238, 234, 222)
PLATE_EDGE = (28, 24, 24)


def inpaint_text(img: np.ndarray, box: tuple[int, int, int, int], polarity: str) -> None:
    """Erases the glyphs inside `box` by painting the surrounding art over them."""
    x0, y0, x1, y1 = box
    patch = img[y0:y1, x0:x1]
    gray = cv2.cvtColor(patch, cv2.COLOR_BGR2GRAY).astype(np.int16)
    # A wide median keeps the artwork but loses the thin strokes, so the
    # difference against it is the lettering and nothing else.
    background = cv2.medianBlur(cv2.cvtColor(patch, cv2.COLOR_BGR2GRAY), 31).astype(np.int16)
    diff = gray - background if polarity == "light" else background - gray
    mask = (diff > 22).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((7, 7), np.uint8), iterations=2)
    img[y0:y1, x0:x1] = cv2.inpaint(patch, mask, 7, cv2.INPAINT_TELEA)


def fill_balloon(img: np.ndarray, box: tuple[int, int, int, int]) -> None:
    """Blanks a speech balloon, keeping its drawn outline."""
    x, y, w, h = box
    pad = 14
    x0, y0 = max(x - pad, 0), max(y - pad, 0)
    x1, y1 = min(x + w + pad, img.shape[1]), min(y + h + pad, img.shape[0])
    patch = img[y0:y1, x0:x1]
    hsv = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV)
    white = ((hsv[:, :, 2] > 205) & (hsv[:, :, 1] < 55)).astype(np.uint8)
    white = cv2.morphologyEx(white, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(white, 8)
    if count < 2:
        return
    biggest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    blob = (labels == biggest).astype(np.uint8)
    # The letters are holes in the blob: refill them by flooding the outside.
    contours, _ = cv2.findContours(blob, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    solid = np.zeros_like(blob)
    cv2.drawContours(solid, contours, -1, 1, cv2.FILLED)
    solid = cv2.erode(solid, np.ones((3, 3), np.uint8), iterations=1)
    patch[solid == 1] = (255, 255, 255)


def fitted_font(path: str, size: int, lines: list[str], box: tuple[int, int]) -> ImageFont.FreeTypeFont:
    """Largest font at or below `size` whose block of lines fits the box."""
    width, height = box
    for candidate in range(size, 6, -1):
        font = ImageFont.truetype(path, candidate)
        line_height = int(candidate * 1.26)
        widest = max(font.getbbox(line)[2] - font.getbbox(line)[0] for line in lines)
        if widest <= width and line_height * len(lines) <= height:
            return font
    return ImageFont.truetype(path, 7)


def draw_block(draw: ImageDraw.ImageDraw, lines: list[str], font: ImageFont.FreeTypeFont,
               box: tuple[int, int, int, int], fill, outline, anchor: str) -> None:
    x0, y0, x1, y1 = box
    line_height = int(font.size * 1.26)
    y = y0 + ((y1 - y0) - line_height * len(lines)) // 2
    for line in lines:
        bbox = font.getbbox(line)
        width = bbox[2] - bbox[0]
        if anchor == "left":
            x = x0
        elif anchor == "right":
            x = x1 - width
        else:
            x = x0 + ((x1 - x0) - width) // 2
        if outline:
            draw.text((x, y), line, font=font, fill=fill,
                      stroke_width=max(2, font.size // 9), stroke_fill=outline)
        else:
            draw.text((x, y), line, font=font, fill=fill)
        y += line_height


def draw_rotated(base: Image.Image, lines: list[str], font: ImageFont.FreeTypeFont,
                 box: tuple[int, int, int, int], fill, outline, anchor: str, angle: float) -> None:
    x0, y0, x1, y1 = box
    pad = 40
    layer = Image.new("RGBA", (x1 - x0 + pad * 2, y1 - y0 + pad * 2), (0, 0, 0, 0))
    draw_block(ImageDraw.Draw(layer), lines, font,
               (pad, pad, pad + x1 - x0, pad + y1 - y0), fill, outline, anchor)
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=False)
    base.paste(layer, (x0 - pad, y0 - pad), layer)


def main() -> None:
    img = cv2.imread(str(SOURCE))
    if img is None:
        raise SystemExit(f"cannot read {SOURCE}")

    for x0, y0, x1, y1, polarity, *_ in ART_TEXT:
        inpaint_text(img, (x0, y0, x1, y1), polarity)
    for box, *_ in BALLOONS:
        fill_balloon(img, box)

    base = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(base)

    for (x, y, w, h), text in PLATES:
        font = ImageFont.truetype(COMIC_BOLD, int(h * 0.56))
        text_w = font.getbbox(text)[2] - font.getbbox(text)[0]
        plate_w = max(w, text_w + 18)
        draw.rectangle([x, y, x + plate_w, y + h], fill=PLATE_FILL, outline=PLATE_EDGE, width=2)
        draw_block(draw, [text], font, (x + 9, y, x + plate_w - 9, y + h), (24, 20, 20), None, "left")

    for (x, y, w, h), inset, text, font_path, size in BALLOONS:
        lines = text.split("\n")
        dx, dy = int(w * inset), int(h * inset)
        box = (x + dx, y + dy, x + w - dx, y + h - dy)
        font = fitted_font(font_path, size, lines, (box[2] - box[0], box[3] - box[1]))
        draw_block(draw, lines, font, box, (22, 18, 18), None, "center")

    for x0, y0, x1, y1, _polarity, text, font_path, size, fill, outline, anchor, angle in ART_TEXT:
        lines = text.split("\n")
        font = fitted_font(font_path, size, lines, (x1 - x0, y1 - y0))
        if angle:
            draw_rotated(base, lines, font, (x0, y0, x1, y1), fill, outline, anchor, angle)
        else:
            draw_block(draw, lines, font, (x0, y0, x1, y1), fill, outline, anchor)

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    base.save(REFERENCE, quality=90, subsampling=0, optimize=True)
    base.crop(SHIPPED).save(TARGET, quality=90, subsampling=0, optimize=True)
    print(f"wrote {TARGET} ({TARGET.stat().st_size // 1024} KB)")
    print(f"wrote {REFERENCE} ({REFERENCE.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
