#!/usr/bin/env python3
"""Report the alpha bounding box of a PNG, in pure stdlib.

Exists because a cut-out that carries transparent padding looks exactly like a
layout bug: the art is drawn where it was asked to be and the *ink* is not, so
a cat meant to crop at the tile's bottom edge floats clear of it instead. That
question cannot be answered by looking at `sips`' dimensions, and this worktree
has no PIL.

Prints, per file: pixel size, the alpha>threshold bounding box, and that box as
a fraction of the canvas. A cut-out with no padding reads `0,0 .. W,H`.

**Already answered for the eight shipped poses: all of them are flush, with zero
transparent padding on every edge** (`m05-puddle` is one row in at top and bottom,
which is a resample fringe and nothing else). So when the widget's cat looks like
it is not being cropped at the tile's bottom edge, the asset is not the reason --
that report turned out to be the run row above it having drifted down. Re-run this
only after regenerating or re-resampling art.
"""

from __future__ import annotations

import struct
import sys
import zlib

THRESHOLD = 8  # out of 255; ignore the near-nothing fringe a resample leaves.


def chunks(data: bytes):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    i = 8
    while i < len(data):
        (length,) = struct.unpack(">I", data[i : i + 4])
        kind = data[i + 4 : i + 8]
        yield kind, data[i + 8 : i + 8 + length]
        i += 8 + length + 4


def alpha_bbox(path: str):
    raw = open(path, "rb").read()
    header = None
    idat = b""
    for kind, payload in chunks(raw):
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat += payload
    assert header, "no IHDR"
    width, height, depth, colour, _, _, interlace = header
    # Only what the asset catalog actually holds: 8-bit RGBA, non-interlaced.
    assert (depth, colour, interlace) == (8, 6, 0), f"unsupported PNG {header}"

    data = zlib.decompress(idat)
    stride = width * 4
    prev = bytearray(stride)
    minx, miny, maxx, maxy = width, height, -1, -1
    pos = 0
    for y in range(height):
        filt = data[pos]
        pos += 1
        line = bytearray(data[pos : pos + stride])
        pos += stride
        # Undo the per-scanline filter (PNG spec 9.2). Only the alpha byte is
        # wanted, but every filter but 0 and 2 needs the earlier bytes of the
        # same row, so the whole row has to be reconstructed.
        if filt == 1:
            for x in range(4, stride):
                line[x] = (line[x] + line[x - 4]) & 0xFF
        elif filt == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif filt == 3:
            for x in range(stride):
                left = line[x - 4] if x >= 4 else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif filt == 4:
            for x in range(stride):
                a = line[x - 4] if x >= 4 else 0
                b = prev[x]
                c = prev[x - 4] if x >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        elif filt != 0:
            raise AssertionError(f"bad filter {filt}")
        prev = line

        row_min = -1
        row_max = -1
        for x in range(width):
            if line[x * 4 + 3] > THRESHOLD:
                if row_min < 0:
                    row_min = x
                row_max = x
        if row_max >= 0:
            miny = min(miny, y)
            maxy = y
            minx = min(minx, row_min)
            maxx = max(maxx, row_max)
    return width, height, (minx, miny, maxx, maxy)


def main(paths: list[str]) -> int:
    for path in paths:
        width, height, (minx, miny, maxx, maxy) = alpha_bbox(path)
        if maxx < 0:
            print(f"{path}: {width}x{height} — fully transparent")
            continue
        print(
            f"{path}: {width}x{height}  ink {minx},{miny}..{maxx + 1},{maxy + 1}"
            f"  pad L{minx / width:.3f} T{miny / height:.3f}"
            f" R{(width - maxx - 1) / width:.3f} B{(height - maxy - 1) / height:.3f}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
