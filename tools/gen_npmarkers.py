"""Generates the elite and boss markers for the nameplate quest icons.

    python tools/gen_npmarkers.py

Writes Media/Textures/np-crown.tga (worn on top of the icon's head) and np-ring.tga (drawn
around the icon). Modules/Nameplates/QuestIcons.lua sizes the crown at 46% of the icon and the
ring at 125%, which puts the icon's edge at radius 0.40 of the ring, just outside the ring's dark
inner line (0.365 to 0.385) and over the start of its gold band.

Output format matches tools/gen_mapicons.py: uncompressed true color TGA, 128x128, 32bpp BGRA,
descriptor 0x08. No third-party imaging library, so this runs anywhere Python does.
"""

import math
import os
import struct

SIZE = 128
SS = 4
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Media", "Textures")

INK = (42, 26, 6)
BAND = (214, 160, 32)
PEARL = (255, 236, 140)
RUBY = (220, 40, 50)
SAPPHIRE = (60, 150, 230)

SILHOUETTE = [(0.08, 0.86), (0.12, 0.34), (0.33, 0.58), (0.50, 0.16), (0.67, 0.58),
              (0.88, 0.34), (0.92, 0.86)]
INNER = [(0.5 + (x - 0.5) * 0.84, 0.6 + (y - 0.6) * 0.84) for x, y in SILHOUETTE]
TIPS = [(0.12, 0.31), (0.50, 0.13), (0.88, 0.31)]
GEMS = [(0.30, SAPPHIRE), (0.50, RUBY), (0.70, SAPPHIRE)]
GEM_Y = 0.845


def inside(poly, x, y):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def dot(x, y, cx, cy, r):
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def gold(y):
    return (255 - 40 * y, 222 - 70 * y, max(92 - 70 * y, 10))


def crown(x, y):
    """The color of the topmost layer at (x, y), or None outside the crown. y runs downward."""
    color = None
    if inside(SILHOUETTE, x, y):
        color = INK
    if inside(INNER, x, y):
        color = gold(y)
    if rounded_rect(x, y, 0.06, 0.76, 0.94, 0.93, 0.03):
        color = INK
    if rounded_rect(x, y, 0.10, 0.785, 0.90, 0.905, 0.02):
        color = BAND
    for tx, ty in TIPS:
        if dot(x, y, tx, ty, 0.055):
            color = PEARL if dot(x, y, tx, ty, 0.035) else INK
    for gx, gem in GEMS:
        if dot(x, y, gx, GEM_Y, 0.045):
            color = gem if dot(x, y, gx, GEM_Y, 0.03) else INK
    return color


def ring(x, y):
    r = math.hypot(x - 0.5, y - 0.5)
    if r < 0.365 or r > 0.485:
        return None
    if r < 0.385 or r > 0.465:
        return INK
    return (255 - 59 * y, 226 - 86 * y, 110 - 86 * y)


def render(shape):
    step = 1.0 / (SIZE * SS)
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            ar = ag = ab = 0.0
            covered = 0
            for sy in range(SS):
                y = (py * SS + sy + 0.5) * step
                for sx in range(SS):
                    x = (px * SS + sx + 0.5) * step
                    src = shape(x, y)
                    if src is None:
                        continue
                    covered += 1
                    ar, ag, ab = ar + src[0], ag + src[1], ab + src[2]
            if covered == 0:
                row += b"\x00\x00\x00\x00"
                continue
            a = int(round(covered * 255.0 / (SS * SS)))
            row += bytes((int(round(ab / covered)), int(round(ag / covered)),
                          int(round(ar / covered)), a))
        rows.append(bytes(row))
    # Descriptor 0x08 declares a bottom-left origin, so the first row written is the bottom one
    rows.reverse()
    return b"".join(rows)


def write_tga(path, pixels):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x08)
    with open(path, "wb") as fh:
        fh.write(header + pixels)
    return len(header) + len(pixels)


def main():
    for name, shape in (("np-crown", crown), ("np-ring", ring)):
        path = os.path.join(OUT_DIR, name + ".tga")
        size = write_tga(path, render(shape))
        print("wrote %-38s %d bytes" % (path, size))


if __name__ == "__main__":
    main()
