#!/usr/bin/env python3
"""Probe a keyed RGBA PNG: is the chalk grain in the alpha channel or the colour?

This decides how many assets ship. The art is a single-hue chalk drawing, so if
the background keying left the grain as *partial alpha* then one asset can be
tinted per theme with `BlendMode.srcIn` and the texture survives -- one file per
piece, light and dark for free, and guaranteed composition parity between them.
If instead the grain is colour variation inside a fully-opaque mass, srcIn would
flatten it to a solid slab and each theme needs its own generated asset.

Pure Python: this machine has no PIL and no ImageMagick, so the PNG is unpacked
here with zlib plus the scanline filters from the spec (types 0-4).

    python3 scripts/png_probe.py docs/.../cut/rest-grok-paper-v1.png
"""

from __future__ import annotations

import struct
import sys
import zlib
from collections import Counter
from pathlib import Path


def chunks(data: bytes):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG")
    pos = 8
    while pos + 12 <= len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        yield data[pos + 4 : pos + 8], data[pos + 8 : pos + 8 + length]
        pos += 12 + length


def unfilter(line: bytearray, prev: bytearray, f: int, nch: int, stride: int) -> None:
    """Reverse one scanline's filter in place (PNG spec 9.2, types 0-4)."""
    if f == 0:  # None
        return
    if f == 1:  # Sub
        for i in range(nch, stride):
            line[i] = (line[i] + line[i - nch]) & 0xFF
    elif f == 2:  # Up
        for i in range(stride):
            line[i] = (line[i] + prev[i]) & 0xFF
    elif f == 3:  # Average
        for i in range(stride):
            a = line[i - nch] if i >= nch else 0
            line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
    elif f == 4:  # Paeth
        for i in range(stride):
            a = line[i - nch] if i >= nch else 0
            b = prev[i]
            c = prev[i - nch] if i >= nch else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            line[i] = (line[i] + pr) & 0xFF
    else:
        raise SystemExit(f"bad PNG filter type {f}")


def decode_rgba(path: Path) -> tuple[int, int, bytearray]:
    """Return (w, h, rgba bytes). Only 8-bit truecolour(+alpha), no interlace."""
    raw = path.read_bytes()
    idat = bytearray()
    w = h = depth = ctype = 0
    for kind, payload in chunks(raw):
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", payload[:13])
            if depth != 8 or ctype not in (2, 6) or interlace:
                raise SystemExit(f"unsupported: depth={depth} ctype={ctype} interlace={interlace}")
        elif kind == b"IDAT":
            idat += payload
        elif kind == b"IEND":
            break

    nch = 4 if ctype == 6 else 3
    data = zlib.decompress(bytes(idat))
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = data[pos]
        pos += 1
        line = bytearray(data[pos : pos + stride])
        pos += stride
        unfilter(line, prev, f, nch, stride)
        out[y * stride : (y + 1) * stride] = line
        prev = line

    if nch == 3:  # normalise to RGBA so callers need only one path
        rgba = bytearray(w * h * 4)
        for i in range(w * h):
            rgba[i * 4 : i * 4 + 3] = out[i * 3 : i * 3 + 3]
            rgba[i * 4 + 3] = 255
        return w, h, rgba
    return w, h, out


def report(path: Path) -> None:
    w, h, px = decode_rgba(path)
    n = w * h
    alpha = Counter()
    lum_of_opaque = Counter()
    for i in range(n):
        a = px[i * 4 + 3]
        alpha[a // 16] += 1
        if a > 240:
            r, g, b = px[i * 4], px[i * 4 + 1], px[i * 4 + 2]
            lum_of_opaque[(r * 299 + g * 587 + b * 114) // 1000 // 16] += 1

    transparent = alpha[0]
    opaque = alpha[15]
    partial = n - transparent - opaque
    print(f"\n{path.name}  {w}x{h}")
    print(f"  fully transparent : {transparent / n:6.1%}")
    print(f"  partial alpha     : {partial / n:6.1%}   <- grain here means srcIn tinting works")
    print(f"  fully opaque      : {opaque / n:6.1%}")
    if lum_of_opaque:
        spread = sorted(lum_of_opaque)
        lo, hi = spread[0] * 16, spread[-1] * 16 + 15
        # A wide luminance spread inside the opaque mass is grain that a flat
        # tint would destroy; a narrow one means the mass is already uniform.
        print(f"  luminance of opaque pixels: {lo}..{hi} over {len(spread)} buckets")
        top = lum_of_opaque.most_common(3)
        print("  dominant: " + ", ".join(f"~{b * 16 + 8} ({c / max(opaque,1):.0%})" for b, c in top))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for arg in sys.argv[1:]:
        report(Path(arg))
