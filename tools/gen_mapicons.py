"""Generates the map objective pins EQ ships for the Classic quest map.

    python tools/gen_mapicons.py

Writes Media/Textures/slay.tga, loot.tga, object.tga and entrance.tga. Media/Textures/skull.tga
is NOT touched: it is the nameplate kill marker and keeps its own art.

The art is drawn at 18 units on the world map (Modules/MapPOI/Pin.xml) and 12 on the minimap
(Modules/Minimap/QuestPins.lua), so any detail added here has to survive that.

Output format is matched to skull.tga exactly, byte layout included: uncompressed true color TGA
(type 2), 128x128, 32bpp BGRA, descriptor 0x08.

No third-party imaging library on purpose, so this runs anywhere Python does.
"""

import math
import os
import struct

SIZE = 128
SS = 4                      # supersample factor, so edges get real coverage-based alpha
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Media", "Textures")

INK = (26, 22, 20)
GLYPH = (250, 246, 238)

R_OUTER = 0.478
R_INNER = 0.426

# Blue is the entrance because Modules/MapPOI/Pin.lua still tints the turn-in mark blue for a
# quest handed in inside an instance.
KINDS = {
    "slay":     {"top": (222, 86, 72),  "bottom": (186, 46, 38),  "deep": (112, 22, 18)},
    "loot":     {"top": (240, 160, 48), "bottom": (200, 116, 18), "deep": (128, 66, 8)},
    "object":   {"top": (64, 190, 150), "bottom": (30, 150, 116), "deep": (14, 88, 68)},
    "entrance": {"top": (92, 148, 232), "bottom": (48, 106, 202), "deep": (20, 54, 120)},
}


def _ellipse(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def _rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def _rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def disc(x, y, r):
    return (x - 0.5) ** 2 + (y - 0.5) ** 2 <= r * r


def slay(x, y):
    if _ellipse(x, y, 0.500, 0.452, 0.207, 0.196):
        return True
    return _rounded_rect(x, y, 0.386, 0.575, 0.614, 0.722, 0.036)


def slay_holes(x, y):
    if _ellipse(x, y, 0.434, 0.443, 0.056, 0.064):                 # eye sockets
        return True
    if _ellipse(x, y, 0.566, 0.443, 0.056, 0.064):
        return True
    if 0.505 <= y <= 0.566 and abs(x - 0.5) <= (y - 0.505) * 0.52:  # nose
        return True
    if 0.588 <= y <= 0.706 and abs(abs(x - 0.5) - 0.052) <= 0.017:  # teeth
        return True
    return False


def loot(x, y):
    if _ellipse(x, y, 0.500, 0.620, 0.246, 0.202):                 # body
        return True
    if 0.326 <= y <= 0.456:
        return abs(x - 0.5) <= 0.052 + (y - 0.326) * 0.46
    return False


def loot_holes(x, y):
    return 0.424 <= y <= 0.462 and abs(x - 0.5) <= 0.196           # cinch


def obj(x, y):
    cx, cy = 0.5, 0.5
    dx, dy = x - cx, y - cy
    d = math.hypot(dx, dy)
    if d <= 0.152:
        return True
    if d > 0.218:
        return False
    a = math.atan2(dy, dx)
    return math.cos(a * 8.0) >= -0.10                              # eight teeth


def obj_holes(x, y):
    return _ellipse(x, y, 0.500, 0.500, 0.068, 0.068)              # hub


def entrance(x, y):
    if _ellipse(x, y, 0.500, 0.474, 0.198, 0.198) and y <= 0.474:  # arch crown
        return True
    if _rect(x, y, 0.302, 0.474, 0.698, 0.760):                    # jambs
        return True
    return _rounded_rect(x, y, 0.262, 0.744, 0.738, 0.800, 0.022)  # threshold


def entrance_holes(x, y):
    if _ellipse(x, y, 0.500, 0.512, 0.116, 0.116) and y <= 0.512:  # doorway
        return True
    return _rect(x, y, 0.384, 0.512, 0.616, 0.744)


SHAPES = {
    "slay": (slay, slay_holes),
    "loot": (loot, loot_holes),
    "object": (obj, obj_holes),
    "entrance": (entrance, entrance_holes),
}


def render(kind):
    shape, holes = SHAPES[kind]
    c = KINDS[kind]
    step = 1.0 / (SIZE * SS)
    rows = []
    for py in range(SIZE):
        row = bytearray()
        t = py / float(SIZE - 1)
        fill = [c["top"][i] + (c["bottom"][i] - c["top"][i]) * t for i in range(3)]
        for px in range(SIZE):
            # Each sub-sample picks ONE color and the pixel is their mean. Compositing the layers
            # as successive blends instead over-weights the glyph wherever a hole reaches its
            # antialiased edge, which is what lightened the pouch cinch.
            ar = ag = ab = 0.0
            covered = 0
            for sy in range(SS):
                y = (py * SS + sy + 0.5) * step
                for sx in range(SS):
                    x = (px * SS + sx + 0.5) * step
                    if not disc(x, y, R_OUTER):
                        continue
                    covered += 1
                    if not disc(x, y, R_INNER):
                        src = INK
                    elif shape(x, y):
                        src = c["deep"] if holes(x, y) else GLYPH
                    else:
                        src = fill
                    ar, ag, ab = ar + src[0], ag + src[1], ab + src[2]
            if covered == 0:
                row += b"\x00\x00\x00\x00"
                continue
            a = int(round(covered * 255.0 / (SS * SS)))
            row += bytes((int(round(ab / covered)), int(round(ag / covered)),
                          int(round(ar / covered)), a))
        rows.append(bytes(row))

    # BOTTOM-UP. Descriptor 0x08 leaves bit 5 clear, which declares a BOTTOM-LEFT origin, so the
    # first row in the file is the BOTTOM of the image. Writing rows top-down under that header
    # renders the icon vertically mirrored - the coin bag came out as a hot air balloon, and a PNG
    # preview that assumed top-down agreed with the mistake instead of catching it. skull.tga uses
    # 0x08 and is authored this way, so this matches the art already shipping.
    rows.reverse()
    return b"".join(rows)


def write_tga(path, pixels):
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # id length
        0,      # no color map
        2,      # uncompressed true color
        0, 0, 0,
        0, 0,   # origin
        SIZE, SIZE,
        32,     # bits per pixel
        0x08,
    )
    with open(path, "wb") as fh:
        fh.write(header + pixels)
    return len(header) + len(pixels)


def main():
    for name in ("slay", "loot", "object", "entrance"):
        path = os.path.join(OUT_DIR, name + ".tga")
        size = write_tga(path, render(name))
        print("wrote %-38s %d bytes" % (path, size))


if __name__ == "__main__":
    main()
