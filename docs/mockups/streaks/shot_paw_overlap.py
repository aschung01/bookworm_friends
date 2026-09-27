#!/usr/bin/env python3
"""Throwaway comparison sheet for ONE question: which part of the paw print
should cross the ring's band?

Not part of the checked design record -- no `screens` entry, no verify.py
coverage, nothing spliced into index.html. This exists to let a human look at
several candidates before any of them earns a formal frame. Reuses the ring's
own PATCH_DOUBLE_MASKS and the paw dies' own mask arrays verbatim out of
index.html (regex-extracted, not retyped), so what renders is the real
stencils, not an approximation of them.

Run: ../../.venv/bin/python docs/mockups/streaks/shot_paw_overlap.py
Output: docs/mockups/streaks/_paw_overlap.png -- LOOK at it.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
PAGE = HERE / "index.html"
OUT = HERE / "_paw_overlap.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def const_array(js, name):
    m = re.search(r"const " + name + r"\s*=\s*\[(.*?)\n\s*\];", js, re.S)
    if not m:
        sys.exit(f"could not find {name}")
    # one element is enough -- every candidate uses the SAME day (index 0),
    # so this is a comparison of position/rotation, not of which stencil.
    first = re.search(r'"(data:image[^"]*)"', m.group(1))
    if not first:
        sys.exit(f"could not read the first element of {name}")
    return first.group(1)


def main():
    html = PAGE.read_text()
    m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
    js = m.group(1)

    ring = const_array(js, "PATCH_DOUBLE_MASKS")
    paw_raw = const_array(js, "PATCH_PAW_MASKS")
    paw_tidy = const_array(js, "PATCH_PAW_TIDY_MASKS")

    RING = "#8C4A3A"
    CELL = 42

    # Each candidate is one `.cmk2`-equivalent rule: which paw stencil, and
    # where/how it sits relative to the ring. `note` is shown under the cell.
    candidates = [
        (
            "shipped (last round)",
            paw_raw,
            "right:4px;bottom:4px;width:15px;height:15px;transform:rotate(6deg);",
            "toes cross the band, pad sits mostly past it",
        ),
        (
            "A \u2014 paw flipped 180\u00b0",
            paw_raw,
            "right:3px;bottom:3px;width:16px;height:16px;"
            "transform:rotate(186deg);",
            "flips which end is which: pad now leads, crosses the band; "
            "toes trail behind it, inside the ring",
        ),
        (
            "B \u2014 tidy paw, flipped",
            paw_tidy,
            "right:3px;bottom:3px;width:16px;height:16px;"
            "transform:rotate(186deg);",
            "same flip, symmetric toes \u2014 the crossing toe is one shape "
            "instead of three uneven ones",
        ),
        (
            "C \u2014 no flip, pulled inward",
            paw_raw,
            "right:8px;bottom:8px;width:15px;height:15px;"
            "transform:rotate(6deg);",
            "toes tucked fully inside the ring's own interior; only the "
            "pad's edge reaches the band",
        ),
        (
            "D \u2014 tidy paw, pulled inward",
            paw_tidy,
            "right:8px;bottom:8px;width:15px;height:15px;"
            "transform:rotate(6deg);",
            "same idea as C with the symmetric print",
        ),
        (
            "E \u2014 flipped + larger",
            paw_raw,
            "right:1px;bottom:1px;width:19px;height:19px;"
            "transform:rotate(186deg);",
            "pad crosses the band by more; toes end up well inside, clear "
            "of the numeral",
        ),
        (
            "F -- tidy, flipped + larger",
            paw_tidy,
            "right:1px;bottom:1px;width:19px;height:19px;"
            "transform:rotate(186deg);",
            "B's symmetric toes at E's size -- the biggest pad overlap in "
            "the set, toes read as one small cluster",
        ),
        (
            "G -- tidy, flipped, lighter touch",
            paw_tidy,
            "right:5px;bottom:5px;width:15px;height:15px;"
            "transform:rotate(186deg);",
            "same flip, pulled back toward the shipped size -- a smaller "
            "bite of the band than B",
        ),
    ]

    cells = []
    for label, mask, style, note in candidates:
        cells.append(
            f'<div class="ov"><b>{label}</b>'
            f'<div class="ovcell">'
            f'<i class="ring" style="mask-image:url({ring});'
            f"-webkit-mask-image:url({ring})\"></i>"
            f'<i class="paw" style="{style}mask-image:url({mask});'
            f"-webkit-mask-image:url({mask})\"></i>"
            f'<span class="num">9</span>'
            f"</div>"
            f'<p>{note}</p>'
            f"</div>"
        )

    sheet = f"""<!doctype html><meta charset="utf-8">
<style>
  body {{ margin:0; padding:24px; background:#2b2b2f; display:flex;
          flex-wrap:wrap; gap:20px; font:12px -apple-system,sans-serif; }}
  .ov {{ width:170px; color:#e8e4dc; }}
  .ov b {{ display:block; margin:0 0 8px; font-size:13px; }}
  .ov p {{ color:#a8a4a0; font-size:11px; line-height:1.4; margin:8px 0 0; }}
  .ovcell {{ position:relative; width:{CELL}px; height:{CELL}px;
             margin:0 auto; background:#fdfaf4; border-radius:8px; }}
  .ovcell .ring {{
    position:absolute; left:1px; right:1px; top:1px; bottom:1px;
    background:{RING}; opacity:.65;
    -webkit-mask-size:100% 100%; mask-size:100% 100%;
  }}
  .ovcell .paw {{
    position:absolute; left:auto; top:auto; background:{RING};
    -webkit-mask-size:100% 100%; mask-size:100% 100%;
  }}
  .ovcell .num {{
    position:absolute; inset:0; display:flex; align-items:center;
    justify-content:center; font:600 15px -apple-system,sans-serif;
    color:#3a352f;
  }}
</style>
{"".join(cells)}
"""
    page = Path(tempfile.mkdtemp()) / "paw_overlap.html"
    page.write_text(sheet)

    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=4",
            "--window-size=1560,420",
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
