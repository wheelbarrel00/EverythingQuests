"""Generates the map objective icons EQ ships for the Classic quest pins.

    python tools/gen_mapicons.py

Writes Media/Textures/loot.tga and object.tga. The kill icon is NOT generated - map pins
reuse the existing skull.tga, so a kill objective shows the same symbol on a nameplate and
on the map.

Output format is matched to skull.tga exactly, byte layout included: uncompressed true
colour TGA (type 2), 128x128, 32bpp BGRA, descriptor 0x08 meaning origin at top-left with
8 alpha bits. WoW rejects a bottom-up origin here, which is what descriptor 0x08 pins down.

No third-party imaging library on purpose, so this runs anywhere Python does.
"""

import os
import struct

SIZE = 128
SS = 4                      # supersample factor, so edges get real coverage-based alpha
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Media", "Textures")

FILL_TOP = (238, 240, 242)
FILL_BOTTOM = (165, 174, 182)
OUTLINE = (24, 24, 28)


def _rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def _ellipse(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def loot(x, y):
    """A cinched coin bag. Chosen over a coin stack because the silhouette stays readable
    at the ~16 pixels a map pin actually occupies."""
    if _ellipse(x, y, 0.50, 0.660, 0.340, 0.310):                  # body
        return True
    if 0.150 <= y <= 0.345:                                        # gathered neck
        if abs(x - 0.5) <= 0.110 + (y - 0.150) * 0.52:
            return True
    return False


def loot_detail(x, y):
    """Grooves. Without these the bag renders as one blank blob and reads as a flask."""
    if 0.306 <= y <= 0.340 and abs(x - 0.5) <= 0.235:              # tie band
        return True
    if 0.165 <= y <= 0.306 and abs(abs(x - 0.5) - 0.050) <= 0.011:  # cloth folds
        return True
    return False


def obj(x, y):
    """A chest. Reads as 'go click this' and is distinct from the bag at small sizes."""
    if _rounded_rect(x, y, 0.120, 0.455, 0.880, 0.865, 0.050):     # body
        return True
    if y <= 0.465 and _ellipse(x, y, 0.50, 0.465, 0.380, 0.235):   # domed lid
        return True
    return False


def obj_detail(x, y):
    if 0.448 <= y <= 0.492:                                        # lid seam
        return True
    if abs(abs(x - 0.5) - 0.105) <= 0.022 and y >= 0.245:          # strap edges
        return True
    if _rounded_rect(x, y, 0.432, 0.505, 0.568, 0.625, 0.028):     # latch
        return True
    return False


def render(shape, detail=None):
    # coverage-based alpha at SS x SS per output pixel
    alpha = [0] * (SIZE * SIZE)
    step = 1.0 / (SIZE * SS)
    for py in range(SIZE):
        for px in range(SIZE):
            hits = 0
            for sy in range(SS):
                y = (py * SS + sy + 0.5) * step
                for sx in range(SS):
                    x = (px * SS + sx + 0.5) * step
                    if shape(x, y):
                        hits += 1
            alpha[py * SIZE + px] = hits * 255 // (SS * SS)

    # A cheap dark rim: a pixel whose 5x5 neighbourhood contains transparency is near the
    # boundary, so it blends toward the outline colour. Doing it here rather than in the
    # shape functions keeps the shapes readable as plain geometry.
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            a = alpha[py * SIZE + px]
            if a == 0:
                row += b"\x00\x00\x00\x00"
                continue
            lowest = 255
            for ny in range(max(0, py - 2), min(SIZE, py + 3)):
                for nx in range(max(0, px - 2), min(SIZE, px + 3)):
                    v = alpha[ny * SIZE + nx]
                    if v < lowest:
                        lowest = v
            edge = 1.0 - (lowest / 255.0)

            if detail is not None:
                hits = 0
                for sy in range(SS):
                    yy = (py * SS + sy + 0.5) * step
                    for sx in range(SS):
                        xx = (px * SS + sx + 0.5) * step
                        if detail(xx, yy) and shape(xx, yy):
                            hits += 1
                if hits:
                    edge = max(edge, 0.88 * hits / float(SS * SS))

            t = py / float(SIZE - 1)
            base = [FILL_TOP[i] + (FILL_BOTTOM[i] - FILL_TOP[i]) * t for i in range(3)]
            rgb = [int(round(base[i] + (OUTLINE[i] - base[i]) * edge)) for i in range(3)]
            row += bytes((rgb[2], rgb[1], rgb[0], a))              # BGRA
        rows.append(bytes(row))

    # ⛔ BOTTOM-UP. Descriptor 0x08 leaves bit 5 clear, which declares a BOTTOM-LEFT origin, so
    # the first row in the file is the BOTTOM of the image. Writing rows top-down under that
    # header renders the icon vertically mirrored - the coin bag came out as a hot air balloon,
    # and a PNG preview that assumed top-down agreed with the mistake instead of catching it.
    # skull.tga uses 0x08 and is authored this way, so this matches the art already shipping.
    rows.reverse()
    return b"".join(rows)


def write_tga(path, pixels):
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # id length
        0,      # no colour map
        2,      # uncompressed true colour
        0, 0, 0,
        0, 0,   # origin
        SIZE, SIZE,
        32,     # bits per pixel
        0x08,   # top-left origin, 8 alpha bits
    )
    with open(path, "wb") as fh:
        fh.write(header + pixels)
    return len(header) + len(pixels)


def main():
    for name, shape, detail in (("loot", loot, loot_detail), ("object", obj, obj_detail)):
        path = os.path.join(OUT_DIR, name + ".tga")
        size = write_tga(path, render(shape, detail))
        print("wrote %-38s %d bytes" % (path, size))


if __name__ == "__main__":
    main()
