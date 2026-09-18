#!/usr/bin/env python3
"""Bake chalk coverage into the alpha channel, so one asset serves both themes.

`cutout_bg.py` keys the plate out but leaves the drawing as an opaque grey mass
whose grain is *colour* variation (measure it with `png_probe.py`: ~1% partial
alpha, opaque luminance spread over ~10 buckets). Tinting that with
`BlendMode.srcIn` would flatten every speckle into a solid slab.

This rewrites each pixel so darkness becomes opacity and the RGB goes flat:

    alpha = existing_alpha * (how dark the pixel was)
    rgb   = one flat colour

The result is a stencil of chalk coverage. Consequences worth the trouble:

  * One file per piece instead of one per piece per theme, so the light and dark
    empty states cannot drift apart -- they are literally the same geometry.
  * Flutter tints it per theme (`secondaryText`: #626A72 light, #949599 dark)
    and the grain survives, because the grain is now alpha.
  * It composites correctly over any background, including the mint sheet.

Input must be the `paper` surface (dark chalk on keyed white). The `night`
surface is the same drawing inverted, so it is redundant once this exists --
which is the point.

    python3 scripts/alpha_from_luma.py                    # every cut/*-paper-*.png
    python3 scripts/alpha_from_luma.py --gamma 0.8        # denser chalk
    python3 scripts/alpha_from_luma.py --tint '#949599'   # preview colour only
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from png_probe import decode_rgba  # noqa: E402  (shares the pure-Python decoder)

REPO = Path(__file__).resolve().parent.parent
CUT = REPO / "docs" / "mockups" / "empty-states" / "art" / "gen" / "cut"
OUT = CUT / "stencil"


def write_rgba(path: Path, w: int, h: int, px: bytes) -> None:
    """Minimal RGBA PNG writer: filter type 0 on every scanline."""
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += px[y * stride : (y + 1) * stride]

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def stencil(src: Path, dst: Path, tint: tuple[int, int, int], gamma: float, floor: int) -> str:
    w, h, px = decode_rgba(src)
    n = w * h

    # Anchor the darkest chalk at full opacity rather than assuming pure black.
    # The generator returns mid-grey, so a naive 1-luma/255 would cap the mass
    # at ~50% opacity and the whole drawing would come out washed out.
    lumas = []
    for i in range(n):
        if px[i * 4 + 3] > 240:
            r, g, b = px[i * 4], px[i * 4 + 1], px[i * 4 + 2]
            lumas.append((r * 299 + g * 587 + b * 114) // 1000)
    if not lumas:
        return f"  {src.name}: nothing opaque to convert"
    lumas.sort()
    lo = lumas[len(lumas) // 50]  # 2nd percentile: darkest real chalk, not noise
    hi = 255  # paper white -> fully transparent
    span = max(hi - lo, 1)

    tr, tg, tb = tint
    out = bytearray(n * 4)
    for i in range(n):
        a0 = px[i * 4 + 3]
        o = i * 4
        out[o], out[o + 1], out[o + 2] = tr, tg, tb
        if a0 == 0:
            continue
        r, g, b = px[o], px[o + 1], px[o + 2]
        luma = (r * 299 + g * 587 + b * 114) // 1000
        cov = (hi - luma) / span
        cov = 0.0 if cov <= 0 else (1.0 if cov >= 1 else cov)
        if gamma != 1.0:
            cov = cov**gamma
        a = int(cov * 255 * (a0 / 255) + 0.5)
        # Speckle below the floor is keying noise, not chalk; leaving it in
        # shows up as a faint rectangular haze around the drawing.
        out[o + 3] = 0 if a < floor else a

    dst.parent.mkdir(parents=True, exist_ok=True)
    write_rgba(dst, w, h, bytes(out))
    ink = sum(1 for i in range(n) if out[i * 4 + 3] > 0) / n
    return f"  wrote {dst.name} ({dst.stat().st_size // 1024} KB, lo={lo}, ink={ink:.1%})"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--glob", default="*-paper-*.png")
    ap.add_argument("--gamma", type=float, default=1.0, help="<1 denser, >1 lighter")
    ap.add_argument("--floor", type=int, default=8, help="drop alpha below this")
    ap.add_argument(
        "--tint",
        default="#626A72",
        help="flat RGB written into the file; only a preview default, since the "
        "app re-tints at runtime",
    )
    args = ap.parse_args()

    t = args.tint.lstrip("#")
    tint = (int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16))

    srcs = sorted(p for p in CUT.glob(args.glob) if not p.name.startswith("sheet"))
    if not srcs:
        sys.exit(f"no inputs matching {args.glob} in {CUT}")
    print(f"stencilling {len(srcs)} file(s) gamma={args.gamma} tint={args.tint}")
    for src in srcs:
        # Drop the surface/variant suffix: the stencil is theme-independent, so
        # `rest-grok-paper-v1.png` becomes just `rest.png`.
        piece = src.name.split("-grok-")[0]
        print(stencil(src, OUT / f"{piece}.png", tint, args.gamma, args.floor))
    print(f"\noutput: {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
