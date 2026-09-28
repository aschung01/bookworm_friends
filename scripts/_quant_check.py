#!/usr/bin/env python3
"""Does quantising a mascot cut-out band it? Throwaway check.

The 3x auth asset is 167 KB as RGBA and 18 KB quantised to 64 colours -- a 9x win
on a drawing CHARACTER.md calls "flat solid fills only". But the file holds 8574
distinct RGBA colours, which is antialiasing plus whatever tonal drift the
generator left in, so the win has to be paid for in banding or it is free.

Judge it by LOOKING at the head at 1:1. The error figures below rank the options;
they cannot tell you whether the fur went posterised, and a mean error of 0.4/255
is what a badly banded gradient looks like numerically when 95% of the frame is
flat.

    .venv/bin/python scripts/_quant_check.py <path-to-3x.png>
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

PAGE = (248, 249, 250, 255)  # AppColors.light.pageBackground


def flat(im: Image.Image) -> Image.Image:
    """Composite onto the page, which is where banding would actually show."""
    return Image.alpha_composite(Image.new("RGBA", im.size, PAGE), im).convert("RGB")


def main() -> int:
    src = Path(sys.argv[1])
    orig = Image.open(src).convert("RGBA")
    orig_kb = src.stat().st_size // 1024
    print(f"source {src}  {orig.size[0]}x{orig.size[1]}  {orig_kb} KB")

    rows = []
    for n in (32, 64, 128):
        q8 = orig.quantize(colors=n, method=Image.FASTOCTREE)
        buf = io.BytesIO()
        q8.save(buf, "PNG", optimize=True)
        q = q8.convert("RGBA")

        d = ImageChops.difference(flat(orig), flat(q))
        px = d.size[0] * d.size[1]
        mean = sum(
            sum(c.histogram()[i] * i for i in range(256)) for c in d.split()
        ) / (px * 3)
        worst = max(
            max(i for i, v in enumerate(c.histogram()) if v) for c in d.split()
        )
        # Alpha has to survive or the cut-out gains a white box on the page.
        a_shift = ImageChops.difference(orig.split()[3], q.split()[3]).getextrema()[1]
        kb = len(buf.getvalue()) // 1024
        rows.append((n, kb, q))
        print(
            f"{n:>4} colours: {kb:>3} KB   mean err {mean:5.2f}/255   "
            f"worst {worst:>3}   max alpha shift {a_shift:>3}"
        )

    # The head at 1:1 -- fur tone and the antialiased ear edges band first.
    box = (150, 60, 470, 330)
    cw, chh = box[2] - box[0], box[3] - box[1]
    sheet = Image.new("RGB", (4 * (cw + 10) + 10, chh + 40), "#2C2C2E")
    dr = ImageDraw.Draw(sheet)
    sheet.paste(flat(orig).crop(box), (10, 30))
    dr.text((10, 10), f"original  {orig_kb} KB", fill="#F1F3F5")
    for i, (n, kb, q) in enumerate(rows):
        x = 10 + (i + 1) * (cw + 10)
        sheet.paste(flat(q).crop(box), (x, 30))
        dr.text((x, 10), f"{n} colours  {kb} KB", fill="#F1F3F5")

    out = Path("build/auth_cat/_quant.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"\nwrote {out.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
