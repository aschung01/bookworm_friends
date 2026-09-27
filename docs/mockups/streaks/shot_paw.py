#!/usr/bin/env python3
"""Screenshot the (h) paw frames next to the die that ships.

`verify.py` runs the render path and asserts the numbers; `_paw_proof.png` shows
each stencil at cell size with a numeral on it. Neither shows the thing the group
actually has to be judged on: a paw in the real grid, beside its own neighbours,
under the weekend wash, in a month with gaps in it. The `gen_patch_marks.py`
proof sheet says whether a die is a shape; this says whether a month of them is
a calendar.

It reuses the page's own renderer rather than redrawing anything -- the script is
extracted from `index.html`, run under the same DOM stub `verify.py` uses, and
asked for `frame(specOf(V, id))` -- so a frame that looks right here is the frame
the record will show.

    ../../.venv/bin/python docs/mockups/streaks/shot_paw.py

Writes `_paw_shot.png`. Needs Chrome; nothing else.
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
PAGE = HERE / "index.html"
OUT = HERE / "_paw_shot.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# The shipped die first, as the control every frame here has to beat, then the
# candidates. `--all` draws the whole (h) family; the default is the tidy round
# plus the two frames a reader picked out of the first one, because a nine-frame
# sheet is a scroll and a five-frame sheet is a comparison.
IDS_MIX = [
    ("cp-f-stamp-double", "stamp-double — the control"),
    ("cp-h-paw-corner", "paw/corner alone — the ambiguity"),
    ("cp-i-stamp-corner", "ring + corner — both, overlaid"),
    ("cp-i-stamp-corner-swap", "ring + corner, swapped — pad crosses"),
    ("cp-i-stamp-corner-swap-tidy", "ring + corner, swapped — tidy, bigger"),
    ("cp-i-stamp-corner-swap-bold", "ring + corner, swapped — bigger bite"),
    ("cp-i-stamp-corner-br315", "bottom-right, 315°"),
    ("cp-i-stamp-corner-bl45", "bottom-left, 45°"),
    ("cp-i-stamp-corner-tr45", "top-right, 45°"),
    ("cp-i-stamp-corner-tl315", "top-left, 315°"),
    ("cp-i-stamp-crest", "ring + crest — toes on the rim"),
    ("cp-i-stamp-charm", "ring + charm — full print, attached"),
]
IDS_TIDY = [
    ("cp-f-stamp-double", "stamp-double — what ships (0.0% on the digit)"),
    ("cp-h-paw", "paw/print — the measured paw (55% on the digit)"),
    ("cp-h-paw-corner", "paw/corner — liked, but ambiguous whose day it is"),
    ("cp-h-paw-tidy", "paw/tidy — straightened; still 55% on the digit"),
    ("cp-h-paw-open", "paw/open — tidy + gap on the numeral (0.0%)"),
    ("cp-h-paw-ring", "paw/ring — the pad IS the circle (0.0%, 0.94x ink)"),
    ("cp-h-paw-thin", "paw/thin — hairline outline (9.6%)"),
    ("cp-h-paw-under", "paw/under — the gap dot's own lane"),
    ("cp-h-paw-tracks", "paw/tracks — the lane, walked"),
    ("cp-h-paw-beside", "paw/beside — print and date as a pair"),
]
IDS_ALL = [
    ("cp-f-stamp-double", "stamp-double — what ships"),
    ("cp-h-paw", "paw/print — ink parity, 0.20 (the refutation)"),
    ("cp-h-paw-strong", "paw/strong — the die's own 0.65"),
    ("cp-h-paw-lift", "paw/lift — pad set back, digit in the void"),
    ("cp-h-paw-toes", "paw/toes — no pad"),
    ("cp-h-paw-line", "paw/line — the die's ink AND its contrast"),
    ("cp-h-paw-walk", "paw/walk — the trail"),
    ("cp-h-paw-peach", "paw/peach — one ink, the cat's"),
    ("cp-h-paw-corner", "paw/corner — 16px, full strength"),
] + IDS_TIDY[3:]

STUB = r"""
const mk = () => ({
  _v: '', set innerHTML(v){this._v=v;}, get innerHTML(){return this._v;},
  textContent: '', hidden: false, value: '', placeholder: '',
  dataset: {}, style: {},
  classList: { toggle(){}, add(){}, remove(){}, contains(){return false;} },
  addEventListener(){}, focus(){}, blur(){}, select(){},
  contains(){return false;},
  querySelectorAll(){return [];}, querySelector(){return null;},
  closest(){return null;},
  getBoundingClientRect(){return {top:0};}, scrollIntoView(){},
  nextElementSibling: null, tagName: 'DIV',
});
global.document = {
  getElementById: () => mk(), querySelectorAll: () => [],
  querySelector: () => mk(),
  addEventListener(){}, body: { scrollHeight: 1000 }, activeElement: null,
};
global.window = { addEventListener(){}, scrollTo(){}, innerHeight: 800, scrollY: 0 };
global.requestAnimationFrame = (f) => f();
global.Event = class { constructor(t){ this.type = t; } };
"""


def main():
    ids = IDS_ALL if "--all" in sys.argv else IDS_MIX if "--mix" in sys.argv else IDS_TIDY
    html = PAGE.read_text()
    css = html[html.index("<style>") + 7 : html.index("</style>")]
    m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
    if not m:
        sys.exit("could not find the script block")
    js = m.group(1)

    # The page renders whole phone frames. Only the streak page's card is wanted,
    # so each frame is emitted as-is and the sheet scales them down -- cropping
    # the card out would mean re-deriving its box here, which is the kind of
    # second copy of a geometry this record keeps getting bitten by.
    emit = (
        "const V = 'cheap-path';\n"
        # `resolveView` is how the page applies the version chain; reaching into
        # SCREENS directly returns the ROOT's spec, and for this record the root
        # draws a different calendar entirely. Same lookup verify.py uses.
        "const specOf = (v, id) => {\n"
        "  for (const [g, items] of resolveView(v, 'screens'))\n"
        "    for (const it of items) if (it[0] === id) return it[3];\n"
        "  return null;\n"
        "};\n"
        # json rather than a quote swap: an apostrophe in a label ("the die's own
        # ink") closed the string and node reported a syntax error 8,947 lines
        # into a generated file.
        "const out = " + json.dumps(ids) + ";\n"
        "console.log(JSON.stringify(out.map(([id, label]) => "
        "({ id, label, html: frame(specOf(V, id)) }))));\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as fh:
        fh.write(STUB + js + "\n" + emit)
        script = fh.name
    res = subprocess.run(["node", script], capture_output=True, text=True)
    if res.returncode:
        sys.exit("node failed:\n" + res.stderr[-3000:])
    frames = json.loads(res.stdout.strip().split("\n")[-1])

    cells = "".join(
        f'<div class="pawshot"><b>{f["label"]}</b>'
        f'<div class="pawwrap">{f["html"]}</div></div>'
        for f in frames
    )
    # Zoomed and cropped to the month card. `.fr` already carries `zoom: var(--z)`
    # for exactly this, and zoom scales layout -- so the negative margin that
    # scrolls the card into view is written in the frame's OWN units and does not
    # have to be re-derived when the zoom changes. Cropping rather than rendering
    # a bare calendar because the wash, the legend and the stats above it are all
    # part of what a month looks like, and a die judged in isolation is how the
    # patch shipped.
    #
    # **The wrappers are `pawshot`/`pawwrap` and not `shot`/`wrap`, which cost a
    # round trip.** This sheet inlines the record's whole stylesheet, and the
    # record already styles `.wrap` -- so a wrapper called `wrap` silently took a
    # width and an offset from it, and every frame rendered shifted right and cut
    # off at the same place. It looked exactly like a frame that overflows its
    # phone, which is a defect this record has actually had.
    sheet = (
        "<!doctype html><meta charset='utf-8'><style>"
        + css
        + "body{margin:0;padding:22px;background:#2b2b2f;"
        "font:12px -apple-system,sans-serif;display:flex;flex-wrap:wrap;gap:20px}"
        ".pawshot{width:594px}"
        ".pawshot b{display:block;color:#e8e4dc;margin:0 0 7px;font-size:14px}"
        ".pawwrap{position:relative;width:594px;height:480px;overflow:hidden;"
        "border-radius:8px}"
        ".pawwrap .fr{--z:1.5;margin-top:-176px;border-radius:0}"
        "</style>"
        + cells
    )
    page = Path(tempfile.mkdtemp()) / "paw_sheet.html"
    page.write_text(sheet)

    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=2",
            # 480 for the crop, plus the label and the gap. Derived rather than
            # typed because the sheet grew from nine frames to ten and a typed
            # height silently cropped the last row -- which reads as a frame that
            # renders short.
            f"--window-size=1252,{60 + 528 * ((len(ids) + 1) // 2)}",
            f"--screenshot={OUT}",
            page.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    # Rendered at 2x and halved rather than shot at 1x: the dies are hairlines and
    # 11px numerals, and a 1x screenshot of those is the one thing that can make a
    # legible mark look like a smudge and an illegible one look fine.
    image = __import__("PIL.Image", fromlist=["Image"])
    im = image.open(OUT)
    im.resize((im.width // 2, im.height // 2), image.LANCZOS).save(OUT)
    print(f"wrote {OUT.name} -- LOOK at it")


if __name__ == "__main__":
    main()
