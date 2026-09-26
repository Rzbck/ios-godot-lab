#!/usr/bin/env python3
from __future__ import annotations

import math
import pathlib
import struct
import sys
import zlib

SIZE = 1024


def _inside_ellipse(x: int, y: int, box: tuple[int, int, int, int]) -> bool:
    x0, y0, x1, y1 = box
    rx = (x1 - x0) / 2.0
    ry = (y1 - y0) / 2.0
    if rx <= 0 or ry <= 0:
        return False
    cx = (x0 + x1) / 2.0
    cy = (y0 + y1) / 2.0
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def _inside_round_rect(x: int, y: int, box: tuple[int, int, int, int], radius: int) -> bool:
    x0, y0, x1, y1 = box
    if x0 + radius <= x <= x1 - radius and y0 <= y <= y1:
        return True
    if y0 + radius <= y <= y1 - radius and x0 <= x <= x1:
        return True
    corners = (
        (x0 + radius, y0 + radius),
        (x1 - radius, y0 + radius),
        (x0 + radius, y1 - radius),
        (x1 - radius, y1 - radius),
    )
    return any((x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2 for cx, cy in corners)


def _png_bytes(width: int, height: int, rgb: bytearray) -> bytes:
    rows = bytearray()
    stride = width * 3
    for y in range(height):
        rows.append(0)
        start = y * stride
        rows.extend(rgb[start:start + stride])

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
        + chunk(b"IEND", b"")
    )


def generate(destination: pathlib.Path) -> None:
    rgb = bytearray(SIZE * SIZE * 3)

    cloud_parts = (
        (235, 420, 565, 710),
        (385, 300, 735, 690),
        (545, 390, 835, 710),
        (280, 520, 790, 735),
    )
    cloud_body = (250, 510, 805, 720)
    badge = (590, 620, 835, 800)

    for y in range(SIZE):
        t = y / (SIZE - 1)
        base_r = 12 * (1 - t) + 24 * t
        base_g = 28 * (1 - t) + 91 * t
        base_b = 55 * (1 - t) + 151 * t

        for x in range(SIZE):
            dx = (x - 500) / 700.0
            dy = (y - 440) / 700.0
            glow = max(0.0, 1.0 - math.sqrt(dx * dx + dy * dy))
            color = [
                min(255, int(base_r + 16 * glow)),
                min(255, int(base_g + 25 * glow)),
                min(255, int(base_b + 34 * glow)),
            ]

            cloud = any(_inside_ellipse(x, y, part) for part in cloud_parts)
            cloud = cloud or _inside_round_rect(x, y, cloud_body, 100)
            if cloud:
                color = [245, 249, 255]

            if _inside_round_rect(x, y, badge, 65):
                color = [14, 31, 59]

            offset = (y * SIZE + x) * 3
            rgb[offset:offset + 3] = bytes(color)

    def set_pixel(x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < SIZE and 0 <= y < SIZE:
            offset = (y * SIZE + x) * 3
            rgb[offset:offset + 3] = bytes(color)

    def line(x0: int, y0: int, x1: int, y1: int, width: int, color: tuple[int, int, int]) -> None:
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for index in range(steps + 1):
            x = round(x0 + (x1 - x0) * index / steps)
            y = round(y0 + (y1 - y0) * index / steps)
            radius = width // 2
            for yy in range(y - radius, y + radius + 1):
                for xx in range(x - radius, x + radius + 1):
                    set_pixel(xx, yy, color)

    for cx, cy, span in ((210, 260, 24), (805, 275, 17), (150, 650, 14)):
        line(cx - span, cy, cx + span, cy, 5, (205, 226, 247))
        line(cx, cy - span, cx, cy + span, 5, (205, 226, 247))

    line(632, 688, 692, 674, 11, (255, 255, 255))
    line(692, 674, 718, 682, 11, (255, 255, 255))
    line(632, 718, 692, 704, 11, (255, 255, 255))
    line(692, 704, 718, 712, 11, (255, 255, 255))

    line(754, 671, 754, 728, 13, (255, 255, 255))
    line(739, 689, 777, 689, 13, (255, 255, 255))
    line(754, 728, 778, 728, 13, (255, 255, 255))

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(_png_bytes(SIZE, SIZE, rgb))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: GENERATE_APP_ICON.py <output.png>")
    generate(pathlib.Path(sys.argv[1]))
