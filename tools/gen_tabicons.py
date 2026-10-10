"""Writes Media/Textures/icon-browser.tga, the Quest Browser's 16 px sidebar icon, white with the shape in alpha."""

import math
import os
import struct

SIZE = 16
SS = 8
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Media", "Textures")


def _segment_distance(x, y, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (x0 + t * dx), y - (y0 + t * dy))


def browser(x, y):
    lens = 3.5 <= math.hypot(x - 6.5, y - 6.5) <= 5.5
    handle = _segment_distance(x, y, 10.0, 10.0, 14.0, 14.0) <= 1.1
    return lens or handle


def render(shape):
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    if shape(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS):
                        hits += 1
            alpha = round(255 * hits / (SS * SS))
            row += bytes((255, 255, 255, alpha))
        rows.append(bytes(row))
    rows.reverse()
    return b"".join(rows)


def write_tga(path, pixels):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x08)
    with open(path, "wb") as fh:
        fh.write(header + pixels)
    return len(header) + len(pixels)


def main():
    path = os.path.join(OUT_DIR, "icon-browser.tga")
    print("wrote %s %d bytes" % (path, write_tga(path, render(browser))))


if __name__ == "__main__":
    main()
