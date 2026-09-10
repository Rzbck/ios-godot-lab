#!/usr/bin/env python3
import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
BG = (13, 18, 24)
PANEL = (20, 27, 35)
MINT = (78, 242, 181)
WHITE = (239, 255, 249)


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def fill_circle(buf: bytearray, cx: int, cy: int, radius: int, color):
    r2 = radius * radius
    for y in range(max(0, cy - radius), min(SIZE, cy + radius + 1)):
        dy2 = (y - cy) * (y - cy)
        span = int(math.sqrt(max(0, r2 - dy2)))
        x0 = max(0, cx - span)
        x1 = min(SIZE - 1, cx + span)
        row = bytes(color) * (x1 - x0 + 1)
        i = (y * SIZE + x0) * 3
        buf[i:i + len(row)] = row


def fill_round_rect(buf: bytearray, x0: int, y0: int, x1: int, y1: int, radius: int, color):
    for y in range(y0, y1 + 1):
        if y < y0 + radius:
            dy = y0 + radius - y
        elif y > y1 - radius:
            dy = y - (y1 - radius)
        else:
            dy = 0
        inset = radius - int(math.sqrt(max(0, radius * radius - dy * dy))) if dy else 0
        xa, xb = x0 + inset, x1 - inset
        row = bytes(color) * (xb - xa + 1)
        i = (y * SIZE + xa) * 3
        buf[i:i + len(row)] = row


def draw_segment(buf: bytearray, a, b, width: int, color):
    x0, y0 = a
    x1, y1 = b
    steps = max(abs(x1 - x0), abs(y1 - y0))
    radius = width // 2
    if steps == 0:
        fill_circle(buf, x0, y0, radius, color)
        return
    for step in range(0, steps + 1, max(1, width // 6)):
        t = step / steps
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        fill_circle(buf, x, y, radius, color)
    fill_circle(buf, x1, y1, radius, color)


def render() -> bytes:
    pixels = bytearray(bytes(BG) * (SIZE * SIZE))
    fill_round_rect(pixels, 86, 86, 937, 937, 210, PANEL)

    route = [(245, 700), (360, 585), (445, 620), (535, 480), (620, 535), (755, 350)]
    for a, b in zip(route, route[1:]):
        draw_segment(pixels, a, b, 44, MINT)

    fill_circle(pixels, route[0][0], route[0][1], 42, WHITE)
    fill_circle(pixels, route[0][0], route[0][1], 22, MINT)
    fill_circle(pixels, route[-1][0], route[-1][1], 62, WHITE)
    fill_circle(pixels, route[-1][0], route[-1][1], 30, MINT)

    raw = bytearray()
    stride = SIZE * 3
    for y in range(SIZE):
        raw.append(0)
        start = y * stride
        raw.extend(pixels[start:start + stride])

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: GENERATE_APP_ICON.py <output.png>")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(render())
    print(f"Generated app icon: {output} ({SIZE}x{SIZE}, RGB, no alpha)")


if __name__ == "__main__":
    main()
