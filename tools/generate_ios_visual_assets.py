#!/usr/bin/env python3
"""Generate deterministic iOS visual assets using only the Python stdlib.

CI generates these before Godot export so the repository can keep source-like
assets while the IPA receives a real raster app icon and neutral launch screen.
"""

from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path


def _chunk(kind: bytes, data: bytes) -> bytes:
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)


def write_png(path: Path, width: int, height: int, pixel_fn) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # PNG filter: None
        for x in range(width):
            r, g, b = pixel_fn(x, y, width, height)
            raw.extend((r, g, b))

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += _chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def icon_pixel(x: int, y: int, width: int, height: int) -> tuple[int, int, int]:
    # Full-bleed square. iOS applies the rounded mask itself.
    bg = (2, 5, 6)
    mint = (113, 240, 196)
    white = (238, 246, 244)
    soft = (62, 112, 98)

    cx = width / 2.0
    cy = height / 2.0
    dx = x + 0.5 - cx
    dy = y + 0.5 - cy
    radius = math.hypot(dx, dy)

    # Very subtle technical depth without blur/shadow baked into the icon.
    color = bg
    for ring, half_width, ring_color in (
        (360.0, 6.0, (28, 50, 55)),
        (270.0, 5.0, (18, 34, 37)),
        (180.0, 5.0, (14, 28, 30)),
    ):
        if abs(radius - ring) <= half_width:
            color = ring_color

    if abs(radius - 248.0) <= 21.0:
        color = mint

    # Four short cardinal ticks.
    if abs(dx) <= 22.0 and (244.0 <= abs(dy) <= 376.0):
        color = white
    if abs(dy) <= 22.0 and (244.0 <= abs(dx) <= 376.0):
        color = white

    # Center target.
    if radius <= 82.0:
        color = mint
    if radius <= 38.0:
        color = bg

    # Four orbit markers.
    for angle in (45.0, 135.0, 225.0, 315.0):
        rr = 318.0
        px = rr * math.cos(math.radians(angle))
        py = rr * math.sin(math.radians(angle))
        if math.hypot(dx - px, dy - py) <= 18.0:
            color = soft
            break

    return color


def launch_pixel(_x: int, _y: int, _w: int, _h: int) -> tuple[int, int, int]:
    # Apple guidance: the launch screen should be neutral and not a branding ad.
    return (0, 2, 2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="assets/generated", help="Output directory")
    args = parser.parse_args()

    out = Path(args.output)
    write_png(out / "ios_app_icon_1024.png", 1024, 1024, icon_pixel)
    write_png(out / "launch_2x.png", 780, 1688, launch_pixel)
    write_png(out / "launch_3x.png", 1170, 2532, launch_pixel)

    for name in ("ios_app_icon_1024.png", "launch_2x.png", "launch_3x.png"):
        path = out / name
        print(f"GENERATED {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
