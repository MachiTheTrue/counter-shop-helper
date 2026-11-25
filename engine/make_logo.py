"""Draws the mod logo src/icon.png (512 x 512, original art, no game assets).

Navy rounded tile, gold shield, three rank chevrons in the mod's own progress colours (green = advised
rank reached, amber = rank in progress, grey = not bought) and a blue dashed "+" badge for the optional
5th item. Drawn at 4x and downscaled for clean edges.
Run: python -I -B -X utf8 make_logo.py
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "src" / "icon.png"
SIZE, K = 512, 4
S = SIZE * K

NAVY_TOP, NAVY_BOT = (24, 42, 74), (9, 16, 31)
GOLD, GOLD_DARK = (240, 190, 84), (176, 128, 40)
SHIELD_FILL = (22, 38, 68)
GREEN, AMBER, GREY = (92, 208, 138), (240, 169, 64), (122, 136, 162)
BLUE = (127, 178, 255)


def p(x, y):
    return (x * K, y * K)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


def shield_points(cx, top, w, h, steps=40):
    """Heater shield: flat top with rounded shoulders, curved sides meeting at a point."""
    pts = []
    half = w / 2
    shoulder = h * 0.30
    pts.append((cx - half, top + 18))
    pts.append((cx - half + 18, top))
    pts.append((cx + half - 18, top))
    pts.append((cx + half, top + 18))
    pts.append((cx + half, top + shoulder))
    def side(t):   # straight-ish upper side, curving in to a pointed tip
        return half * (1 - t ** 2.6), top + shoulder + (h - shoulder) * t
    for i in range(1, steps + 1):          # right side down to the tip
        dx, y = side(i / steps)
        pts.append((cx + dx, y))
    for i in range(steps - 1, -1, -1):      # left side back up
        dx, y = side(i / steps)
        pts.append((cx - dx, y))
    return [p(x, y) for x, y in pts]


def chevron(draw, cx, y, w, thick, color):
    half = w / 2
    pts = [(cx - half, y + w * 0.42), (cx, y), (cx + half, y + w * 0.42),
           (cx + half, y + w * 0.42 + thick), (cx, y + thick), (cx - half, y + w * 0.42 + thick)]
    draw.polygon([p(x, yy) for x, yy in pts], fill=color)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # background: vertical gradient on a rounded tile
    bg = Image.new("RGBA", (S, S))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(NAVY_TOP, NAVY_BOT))
        bd.line([(0, y), (S, y)], fill=c + (255,))
    img.paste(bg, (0, 0), rounded_mask(S, 96 * K))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((6 * K, 6 * K, S - 6 * K, S - 6 * K), radius=90 * K, outline=(255, 255, 255, 28), width=3 * K)

    # shield: dark gold rim, gold rim, navy face
    cx, top, w, h = 236, 70, 300, 360
    d.polygon(shield_points(cx, top + 6, w + 8, h + 4), fill=GOLD_DARK)
    d.polygon(shield_points(cx, top, w, h), fill=GOLD)
    d.polygon(shield_points(cx, top + 22, w - 44, h - 46), fill=SHIELD_FILL)

    # rank chevrons, top = reached (green), middle = in progress (amber), bottom = not bought (grey)
    for i, col in enumerate((GREEN, AMBER, GREY)):
        chevron(d, cx, 116 + i * 62, 136, 34, col)

    # optional 5th item badge: solid disc, blue dashed ring, "+"
    bx, by, r = 388, 392, 70
    d.ellipse((p(bx - r, by - r), p(bx + r, by + r)), fill=(12, 22, 42))
    ring_r, dash = r - 10, 14
    for k in range(dash):
        a0 = k * 360 / dash
        d.arc((p(bx - ring_r, by - ring_r), p(bx + ring_r, by + ring_r)), a0, a0 + 360 / dash * 0.58,
              fill=BLUE, width=10 * K)
    arm, th = 26, 9
    d.rounded_rectangle((p(bx - arm, by - th), p(bx + arm, by + th)), radius=4 * K, fill=BLUE)
    d.rounded_rectangle((p(bx - th, by - arm), p(bx + th, by + arm)), radius=4 * K, fill=BLUE)

    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(OUT, optimize=True)
    print(f"{OUT} ({out.size[0]}x{out.size[1]}, {OUT.stat().st_size} octets)")


if __name__ == "__main__":
    main()
