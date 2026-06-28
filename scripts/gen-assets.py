#!/usr/bin/env python3
"""Generate ghshot's store assets with the Python standard library only.

Produces a simple, recognizable "upload" mark (an up-arrow on a rounded brand
square) at the icon sizes Chrome requires, plus a placeholder store screenshot.
Re-run after tweaking the geometry/colors below:

    python3 scripts/gen-assets.py

Outputs:
    extension/icons/icon16.png, icon48.png, icon128.png
    store/screenshot-1.png   (1280x800 placeholder — replace with a real capture)
"""

import os
import struct
import zlib

BRAND = (99, 91, 255)      # ghshot purple
BRAND_DARK = (60, 54, 170)
FG = (255, 255, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def write_png(path, w, h, pixels):
    """pixels: flat list of (r, g, b, a) tuples, length w*h."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (none)
        for x in range(w):
            raw += bytes(pixels[y * w + x])

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def icon(size):
    s = float(size)
    r = 0.22 * s          # corner radius
    cx = s / 2
    shaft_half = max(1.0, 0.085 * s)
    shaft_top = 0.42 * s
    shaft_bot = 0.80 * s
    head_top = 0.20 * s
    head_bot = 0.50 * s
    head_half = 0.27 * s
    px = []
    for y in range(size):
        for x in range(size):
            fx, fy = x + 0.5, y + 0.5
            # rounded-square mask
            outside = False
            for ox, oy in ((r, r), (s - r, r), (r, s - r), (s - r, s - r)):
                in_corner = ((fx < r) == (ox == r)) and ((fy < r) == (oy == r)) \
                    and (fx < r or fx > s - r) and (fy < r or fy > s - r)
                if in_corner and (fx - ox) ** 2 + (fy - oy) ** 2 > r * r:
                    outside = True
                    break
            if outside:
                px.append((0, 0, 0, 0))
                continue
            bg = lerp(BRAND, BRAND_DARK, fy / s)
            is_arrow = False
            if shaft_top <= fy <= shaft_bot and abs(fx - cx) <= shaft_half:
                is_arrow = True
            elif head_top <= fy <= head_bot:
                hw = head_half * (fy - head_top) / (head_bot - head_top)
                if abs(fx - cx) <= hw:
                    is_arrow = True
            px.append((FG[0], FG[1], FG[2], 255) if is_arrow else (bg[0], bg[1], bg[2], 255))
    return px


def screenshot(w, h):
    px = []
    for y in range(h):
        bg = lerp((247, 247, 251), (231, 230, 246), y / h)
        for x in range(w):
            px.append((bg[0], bg[1], bg[2], 255))
    # centered brand tile with the upload mark, as a visual placeholder
    tile = 220
    tx, ty = (w - tile) // 2, (h - tile) // 2 - 30
    mark = icon(tile)
    for j in range(tile):
        for i in range(tile):
            r, g, b, a = mark[j * tile + i]
            if a:
                px[(ty + j) * w + (tx + i)] = (r, g, b, 255)
    return px


def main():
    icons_dir = os.path.join(ROOT, "extension", "icons")
    store_dir = os.path.join(ROOT, "store")
    os.makedirs(icons_dir, exist_ok=True)
    os.makedirs(store_dir, exist_ok=True)
    for sz in (16, 48, 128):
        write_png(os.path.join(icons_dir, "icon%d.png" % sz), sz, sz, icon(sz))
        print("wrote extension/icons/icon%d.png" % sz)
    write_png(os.path.join(store_dir, "screenshot-1.png"), 1280, 800,
              screenshot(1280, 800))
    print("wrote store/screenshot-1.png (placeholder)")


if __name__ == "__main__":
    main()
