#!/usr/bin/env python3
"""A systematic sweep, not three hand-picked points.

The corner mix only ever tried ONE placement (bottom-right) and ONE fix (a
180deg flip) for the toes-cross-the-band defect. This sweeps the two axes
that actually exist:

  - WHICH CORNER the accent sits in (bottom-right, bottom-left, top-right,
    top-left) -- the box's own "outward" direction changes with it, so a
    flip that helps one corner can hurt another.
  - WHAT ANGLE the paw is rotated to, every 45deg around the full circle --
    not just 0 and 180, because the die is not radially symmetric (the pad
    is wide, the toes lean), so the angle that best plants the pad on the
    band is not guaranteed to be exactly opposite the unflipped pose.

Throwaway, like shot_paw_overlap.py -- not part of the checked design record.
Run: ../../.venv/bin/python docs/mockups/streaks/shot_paw_sweep.py
Output: docs/mockups/streaks/_paw_sweep.png -- LOOK at it.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
PAGE = HERE / "index.html"
OUT = HERE / "_paw_sweep.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def const_array(js, name):
    m = re.search(r"const " + name + r"\s*=\s*\[(.*?)\n\s*\];", js, re.S)
    if not m:
        sys.exit(f"could not find {name}")
    first = re.search(r'"(data:image[^"]*)"', m.group(1))
    if not first:
        sys.exit(f"could not read the first element of {name}")
    return first.group(1)


CORNERS = [
    ("BR", "right:3px;bottom:3px;"),
    ("BL", "left:3px;bottom:3px;"),
    ("TR", "right:3px;top:3px;"),
    ("TL", "left:3px;top:3px;"),
]
ANGLES = [0, 45, 90, 135, 180, 225, 270, 315]


def main():
    html = PAGE.read_text()
    m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
    js = m.group(1)

    ring = const_array(js, "PATCH_DOUBLE_MASKS")
    paw = const_array(js, "PATCH_PAW_TIDY_MASKS")

    RING = "#8C4A3A"
    CELL = 42
    BOX = 16

    rows = []
    for angle in ANGLES:
        cells = []
        for label, pos in CORNERS:
            cells.append(
                f'<div class="sw">'
                f'<div class="swcell">'
                f'<i class="ring" style="mask-image:url({ring});'
                f"-webkit-mask-image:url({ring})\"></i>"
                f'<i class="paw" style="{pos}width:{BOX}px;height:{BOX}px;'
                f"transform:rotate({angle}deg);"
                f"mask-image:url({paw});-webkit-mask-image:url({paw})\"></i>"
                f'<span class="num">9</span>'
                f"</div>"
                f'<p>{label}</p>'
                f"</div>"
            )
        rows.append(
            f'<div class="swrow"><div class="swangle">{angle}\u00b0</div>'
            f'<div class="swcells">{"".join(cells)}</div></div>'
        )

    sheet = f"""<!doctype html><meta charset="utf-8">
<style>
  body {{ margin:0; padding:20px; background:#2b2b2f; font:12px -apple-system,sans-serif; }}
  .swrow {{ display:flex; align-items:center; gap:10px; margin-bottom:10px; }}
  .swangle {{ width:36px; color:#e8e4dc; font-size:13px; font-weight:600;
              text-align:right; flex-shrink:0; }}
  .swcells {{ display:flex; gap:14px; }}
  .sw {{ width:64px; color:#a8a4a0; text-align:center; }}
  .sw p {{ margin:4px 0 0; font-size:10px; }}
  .swcell {{ position:relative; width:{CELL}px; height:{CELL}px;
             margin:0 auto; background:#fdfaf4; border-radius:8px; }}
  .swcell .ring {{
    position:absolute; left:1px; right:1px; top:1px; bottom:1px;
    background:{RING}; opacity:.65;
    -webkit-mask-size:100% 100%; mask-size:100% 100%;
  }}
  .swcell .paw {{
    position:absolute; background:{RING};
    -webkit-mask-size:100% 100%; mask-size:100% 100%;
  }}
  .swcell .num {{
    position:absolute; inset:0; display:flex; align-items:center;
    justify-content:center; font:600 15px -apple-system,sans-serif;
    color:#3a352f;
  }}
</style>
<div style="display:flex;gap:10px;margin:0 0 8px 46px;color:#e8e4dc;font-weight:600;font-size:13px;">
  {"".join(f'<div style="width:64px;text-align:center;">{l}</div>' for l, _ in CORNERS)}
</div>
{"".join(rows)}
"""
    page = Path(tempfile.mkdtemp()) / "paw_sweep.html"
    page.write_text(sheet)

    width = 20 + 46 + len(CORNERS) * (64 + 14)
    height = 20 + len(ANGLES) * (42 + 24) + 40

    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=4",
            f"--window-size={width},{height}",
            f"--screenshot={OUT}",
            page.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    from PIL import Image

    im = Image.open(OUT)
    im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(OUT)
    print(f"wrote {OUT.name} -- LOOK at it")


if __name__ == "__main__":
    main()
