#!/usr/bin/env python3
"""Writes a plain, static HTML comparison sheet -- open it in a browser and
zoom/scroll yourself. Not a screenshot, not judged by the agent: every combo
is real HTML+CSS using the ring's and paw's own masks out of index.html, so
what you see is what the mockup would actually draw.

Sweeps the two axes that "swap" alone did not touch:
  - corner: which corner of the cell the accent sits in
  - angle: the die's rotation, every 45deg around the circle

Run: ../../.venv/bin/python docs/mockups/streaks/gen_paw_sweep.py
Open: docs/mockups/streaks/paw_sweep.html
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
PAGE = HERE / "index.html"
OUT = HERE / "paw_sweep.html"


def const_array(js, name):
    m = re.search(r"const " + name + r"\s*=\s*\[(.*?)\n\s*\];", js, re.S)
    if not m:
        sys.exit(f"could not find {name}")
    first = re.search(r'"(data:image[^"]*)"', m.group(1))
    if not first:
        sys.exit(f"could not read the first element of {name}")
    return first.group(1)


CORNERS = [
    ("bottom-right", "right:6px;bottom:6px;"),
    ("bottom-left", "left:6px;bottom:6px;"),
    ("top-right", "right:6px;top:6px;"),
    ("top-left", "left:6px;top:6px;"),
]
ANGLES = [0, 45, 90, 135, 180, 225, 270, 315]


def main():
    html = PAGE.read_text()
    m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
    js = m.group(1)

    ring = const_array(js, "PATCH_DOUBLE_MASKS")
    paw_tidy = const_array(js, "PATCH_PAW_TIDY_MASKS")
    paw_raw = const_array(js, "PATCH_PAW_MASKS")

    RING = "#8C4A3A"
    CELL = 64
    BOX = 24

    def grid(paw_mask, box):
        head = "<tr><th></th>" + "".join(
            f"<th>{label}</th>" for label, _ in CORNERS
        ) + "</tr>"
        body = []
        for angle in ANGLES:
            cells = []
            for _, pos in CORNERS:
                cells.append(
                    f"<td><div class='cell'>"
                    f"<i class='ring' style=\"mask-image:url({ring});"
                    f"-webkit-mask-image:url({ring})\"></i>"
                    f"<i class='paw' style=\"{pos}width:{box}px;height:{box}px;"
                    f"transform:rotate({angle}deg);"
                    f"mask-image:url({paw_mask});-webkit-mask-image:url({paw_mask})\">"
                    f"</i><span class='num'>9</span></div></td>"
                )
            body.append(f"<tr><th class='ang'>{angle}\u00b0</th>{''.join(cells)}</tr>")
        return head + "".join(body)

    page = f"""<!doctype html><meta charset="utf-8">
<title>paw + ring sweep</title>
<style>
  body {{ margin:0; padding:28px; background:#2b2b2f; color:#e8e4dc;
          font:14px -apple-system,sans-serif; }}
  h1 {{ font-size:18px; margin:0 0 4px; }}
  h2 {{ font-size:14px; margin:36px 0 10px; color:#cfcac2; }}
  p.lede {{ color:#a8a4a0; max-width:640px; margin:0 0 20px; }}
  table {{ border-collapse:separate; border-spacing:14px; }}
  th {{ font-weight:600; font-size:13px; color:#cfcac2; text-align:center; }}
  th.ang {{ text-align:right; padding-right:6px; color:#e8e4dc; }}
  .cell {{ position:relative; width:{CELL}px; height:{CELL}px;
           background:#fdfaf4; border-radius:12px; }}
  .cell .ring {{
    position:absolute; left:2px; right:2px; top:2px; bottom:2px;
    background:{RING}; opacity:.65;
    -webkit-mask-size:100% 100%; mask-size:100% 100%;
  }}
  .cell .paw {{
    position:absolute; background:{RING};
    -webkit-mask-size:100% 100%; mask-size:100% 100%;
  }}
  .cell .num {{
    position:absolute; inset:0; display:flex; align-items:center;
    justify-content:center; font:600 22px -apple-system,sans-serif;
    color:#3a352f;
  }}
</style>
<h1>ring + paw, every corner x every 45\u00b0</h1>
<p class="lede">Real HTML/CSS using the ring's and paw's own masks out of
<code>index.html</code> -- zoom with your browser, nothing here is a
screenshot. Two tables: the tidy (symmetric) print, then the raw measured
print for comparison. Box is {BOX}px in a {CELL}px cell, {6}px inset from
whichever two edges the corner names.</p>

<h2>tidy print (PATCH_PAW_TIDY_MASKS)</h2>
<table>{grid(paw_tidy, BOX)}</table>

<h2>raw print (PATCH_PAW_MASKS)</h2>
<table>{grid(paw_raw, BOX)}</table>
"""
    OUT.write_text(page)
    print(f"wrote {OUT.name} -- open it in a browser")


if __name__ == "__main__":
    main()
