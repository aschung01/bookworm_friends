#!/usr/bin/env python3
"""Generate the empty-state illustrations in the app icon's chalk style (xAI Grok).

This is the route that works. The shipping icon
(`assets/branding/app_icon_source.png`) is an AI-generated raster, so its chalk
grain can't be hand-authored as SVG -- but Grok Imagine follows a written
composition *and* takes the icon as a reference, so the drawing is ours and the
hand is the icon's.

Endpoint: POST https://api.x.ai/v1/images/edits with the icon passed in `images`
and referenced as <IMAGE_0>. Measured against the alternatives:

  * `/v1/images/edits` + icon reference + explicit "draw NEW"  <- used here.
    Inherits the icon's exact plate green and book construction (spine strip,
    top edge curling over, cut-out ribbon) and keeps chalk grain.
  * `/v1/images/generations` (no reference). Good grain and full prompt
    adherence, but drifts the brand green and loses the curling-lip
    construction. Fine fallback; see --route generations.
  * Bedrock `stable-image-style-guide` -- style matcher, ignores composition
    entirely (four of six pieces came back byte-identical). See
    scripts/chalkify_empty_state_art.py for the full measurement.
  * Bedrock `stable-style-transfer` -- needs one of our vectors as the content
    image, so output quality is capped by that vector's geometry.

Auth: XAI_API_KEY in the environment. Never commit it.

    export XAI_API_KEY=...
    python3 scripts/gen_empty_state_art.py --list
    python3 scripts/gen_empty_state_art.py --variants 2
    python3 scripts/gen_empty_state_art.py --only nomatch --variants 4
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ICON = REPO / "assets" / "branding" / "app_icon_source.png"
OUT = REPO / "docs" / "mockups" / "empty-states" / "art" / "gen"
MODEL = "grok-imagine-image-2.0"
API = "https://api.x.ai/v1/images"

# The icon's construction, described so every piece inherits the same book.
BOOK = (
    "one closed book seen straight on from the front: a plain blank upright "
    "rectangle cover, a narrow chalk spine strip down its left edge with the "
    "cover's top edge curling over it, and a bookmark ribbon hanging from the "
    "top of the cover near the right - a long narrow vertical band ending in a "
    "V notch, cut out so the background shows through it"
)

# Surfaces. `board` is the logo's own reading (white chalk on the icon's green)
# and is only right for brand material -- in-app it reads as an app icon that
# fell into the UI. `paper` and `night` invert the mark colour so the drawing
# can live on pageBackground / the dark page; their flat backgrounds are key
# colours, stripped by scripts/cutout_bg.py before shipping.
SURFACES = {
    "paper": (
        "Drawn on a completely plain, flat, pure white background (#FFFFFF) with "
        "no texture, no paper grain, no vignette and no shading in the "
        "background at all. The drawing itself is made of MEDIUM GREY chalk, "
        "the grey of #626A72 - clearly grey, definitely not black and not dark "
        "charcoal. The background must stay perfectly uniform pure white "
        "everywhere so it can be keyed out."
    ),
    "night": (
        "Drawn on a completely plain, flat, pure black background (#000000) with "
        "no texture, no vignette and no shading in the background at all. The "
        "drawing itself is made of LIGHT GREY chalk, the grey of #949599 - "
        "clearly a light dusty grey, not pure white. The background must stay "
        "perfectly uniform pure black everywhere so it can be keyed out."
    ),
    "board": (
        "Drawn as white chalk on a flat mid-green chalkboard, background colour "
        "exactly #38B28A."
    ),
}

# The set drifted badly without this: rest came back near-black while nomatch
# and note came back as outline drawings. Every piece must agree on weight.
MASS = (
    "CONSISTENCY REQUIREMENT: every book and every rectangle is drawn as a "
    "SOLID FILLED mass of chalk, filled evenly right up to its edges. This is "
    "never an outline drawing, never a line drawing, never a hollow or unfilled "
    "shape - the only exceptions are shapes explicitly described as dashed "
    "outlines. Keep the chalk tone even and identical across the whole drawing."
)

# Consistency lever. Without an explicit weight the model free-styles per piece:
# a first pass returned near-black filled masses for rest/search/duo and light
# outline drawings for nomatch/note, which cannot ship as one family.
WEIGHT = (
    "WEIGHT, must be identical across the whole set: every book cover is filled "
    "solidly with MEDIUM grey chalk - clearly filled in, not left empty and not "
    "drawn as a thin outline, but not near-black either. Aim for a medium mid-grey "
    "tone. Any dashed slot, question mark, magnifier, rule line or pencil is drawn "
    "in the same medium grey chalk at a similar visual weight."
)

# Non-negotiable: without this the model returns clean vector shapes.
GRAIN = (
    "CRITICAL: this must look like real chalk drawn by hand, not a clean vector "
    "logo. Heavy dry chalk texture: powdery grain across every filled shape, "
    "visible chalk dust and speckle, slightly rough crumbly edges where the "
    "chalk stick dragged. Matte, dusty, hand-drawn. No smooth flat fills, no "
    "crisp vector edges, no gloss."
)
# "not an app icon" matters: a framed green square reads as an icon dropped
# into the UI, which is what killed an earlier direction.
FLAT = (
    "Completely flat and face-on: no depth, no drop shadow, no perspective, no "
    "3D thickness, no outlines. Centred with generous even margins, nothing "
    "cropped. No text, no letters, no numbers, no frame or border, not an app "
    "icon."
)

PIECES: dict[str, tuple[str, str]] = {
    "rest": (
        "empty library, a friend's (100pt) - library_view.dart",
        f"{BOOK}. The book sits alone, centred, nothing else in the frame.",
    ),
    "invite": (
        "empty library, yours (100pt) - library_view.dart",
        f"{BOOK}. To the left of the book stands a second upright rectangle of "
        "the same height drawn only as a dashed chalk outline, clearly empty, "
        "like a slot waiting for a book. Two small four-pointed chalk sparkles "
        "float above the gap between them.",
    ),
    "search": (
        "add-book sheet idle (100pt) - add_book_bottom_sheet.dart",
        f"{BOOK}. A simple round magnifying glass with a short straight handle "
        "is drawn in the same chalk over the lower right of the cover, its lens "
        "an empty circle showing the green through it.",
    ),
    "nomatch": (
        "no search results (40pt) - add_book_bottom_sheet.dart",
        # Was "a dashed outline, clearly empty and unfilled" -- inherited from the
        # earlier vector families' idea of an empty slot. Rendering it in Flutter
        # at its real 40pt settled the argument: thin dashed lines gave it ~7% ink
        # against ~28% for its siblings, so it read as a smudge beside them and
        # nearly vanished at the 34pt the scan card uses. It is now a solid mass
        # with the question mark KNOCKED OUT, which is the icon's own construction
        # (ribbon, magnifier lens) and the only thing in the set that reads at 34pt.
        "one upright closed book seen straight on from the front, its cover a "
        "SOLID FILLED mass of chalk with softly rounded corners. A single large "
        "bold question mark is CUT OUT of the middle of the cover, a clean hole "
        "right through the chalk so the plain background shows through it - the "
        "question mark is empty background, never drawn in chalk on top of the "
        "cover. The question mark is large and fills most of the cover's height. "
        "No bookmark ribbon. Nothing else in the frame.",
    ),
    "note": (
        "Notes tab empty (48pt) - book_details_tab_view.dart",
        f"{BOOK}, but with no ribbon. Two short horizontal chalk rule lines are "
        "written across the middle of the cover as if it were a page, and a "
        "simple pencil lies diagonally across the lower right of the cover with "
        "its tip pointing down and to the left.",
    ),
    "duo": (
        "no friends yet (40pt) - friends_sheet.dart",
        # Counted TWO separate books only 2 rolls in 6: the edits reference is a
        # single book, so the route collapses the pair unless the gap is stated
        # as a measurement. "Leaning until their corners nearly touch" was the
        # specific phrase that merged them - they now stand apart and upright.
        "EXACTLY TWO closed books, drawn as two completely separate objects "
        "standing apart from each other, like two people standing side by side. "
        "Between them is a WIDE EMPTY GAP of clean background, at least half as "
        "wide as one of the books - they must never touch, never overlap and "
        "never share an edge. This is TWO books, not one: it is NOT one open "
        "book, NOT a book spread flat, NOT a single book with a line down it. "
        "Each book is seen straight on from the front as a solid upright filled "
        "rectangle with softly rounded corners. The LEFT book is clearly "
        "SHORTER and its top edge sits lower; the RIGHT book is TALLER. Only "
        "the right-hand book has a bookmark ribbon hanging from the top of its "
        "cover, a narrow vertical band ending in a V notch, cut out so the "
        "background shows through. No other marks inside either cover: no spine "
        "line, no stripe, no panel.",
    ),
}


def prompt_for(subject: str, route: str, surface: str) -> str:
    surf = SURFACES[surface]
    if route == "edits":
        return (
            "Draw a NEW chalk illustration - do not copy or return <IMAGE_0>. "
            "Take from <IMAGE_0> only its chalk texture and its book "
            "construction (spine strip, top edge curling over, cut-out ribbon). "
            f"Ignore <IMAGE_0>'s colours completely. {surf} Draw: {subject} "
            f"{MASS} {GRAIN} {FLAT}"
        )
    return f"{surf} Draw: {subject} {MASS} {GRAIN} {FLAT}"


def call(route: str, body: dict) -> tuple[bytes | None, str, int | None, str]:
    key = os.environ.get("XAI_API_KEY")
    if not key:
        sys.exit("XAI_API_KEY is not set.")
    req = urllib.request.Request(
        f"{API}/{route}",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode(errors='replace')[:220]}", None, ""
    except urllib.error.URLError as e:
        return None, f"network: {e.reason}", None, ""
    items = payload.get("data") or []
    if not items or not items[0].get("b64_json"):
        return None, f"no image: {json.dumps(payload)[:200]}", None, ""
    ticks = (payload.get("usage") or {}).get("cost_in_usd_ticks")
    # The API decides the format and reports it; it currently returns JPEG even
    # though nothing requested that. Trust mime_type, never the filename.
    mime = items[0].get("mime_type") or "image/png"
    ext = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"}.get(mime, "bin")
    return base64.b64decode(items[0]["b64_json"]), "", ticks, ext


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--route", choices=["edits", "generations"], default="edits")
    ap.add_argument(
        "--surface",
        choices=["paper", "night", "board"],
        default="paper",
        help="paper: mid-grey chalk on keyable white, for the light theme "
        "(default). night: light-grey chalk on keyable black, for the dark "
        "theme. board: white chalk on the icon's green, brand material only.",
    )
    ap.add_argument("--only", nargs="+", metavar="PIECE")
    ap.add_argument("--variants", type=int, default=1)
    ap.add_argument("--resolution", choices=["1k", "2k"], default="1k")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for p, (site, _) in PIECES.items():
            print(f"{p:9s} {site}")
        return
    if not ICON.exists():
        sys.exit(f"reference icon missing: {ICON}")

    todo = args.only or list(PIECES)
    bad = [t for t in todo if t not in PIECES]
    if bad:
        sys.exit(f"unknown piece(s): {', '.join(bad)} (try --list)")

    OUT.mkdir(parents=True, exist_ok=True)
    ref_url = None
    if args.route == "edits":
        # 512px is plenty for a style reference and keeps the payload small.
        small = OUT / "_ref512.png"
        subprocess.run(
            ["sips", "-Z", "512", str(ICON), "--out", str(small)],
            check=True,
            capture_output=True,
        )
        ref_url = "data:image/png;base64," + base64.b64encode(small.read_bytes()).decode()
        small.unlink()

    mf_path = OUT / "manifest.json"
    manifest = json.loads(mf_path.read_text()) if mf_path.exists() else {}

    jobs = [(p, v + 1) for p in todo for v in range(args.variants)]

    def run(job):
        piece, v = job
        site, subject = PIECES[piece]
        prompt = prompt_for(subject, args.route, args.surface)
        body = {
            "model": MODEL,
            "prompt": prompt,
            "aspect_ratio": "1:1",
            "resolution": args.resolution,
            "response_format": "b64_json",
        }
        if ref_url:
            body["images"] = [{"url": ref_url}]
        img, err, ticks, ext = call(args.route, body)
        name = f"{piece}-grok-{args.surface}-v{v}"
        if img is None:
            return f"  {name}: {err}", None, 0
        (OUT / f"{name}.{ext}").write_bytes(img)
        cost = ticks / 1e10 if isinstance(ticks, int) else 0.0
        return (
            f"  wrote {name}.{ext} ({len(img) // 1024} KB, ${cost:.4f})",
            (
                name,
                {
                    "piece": piece,
                    "call_site": site,
                    "provider": "xai",
                    "model": MODEL,
                    "route": args.route,
                    "surface": args.surface,
                    "file": f"{name}.{ext}",
                    "reference": str(ICON.relative_to(REPO)) if ref_url else None,
                    "prompt": prompt,
                    "resolution": args.resolution,
                    "cost_usd": round(cost, 4),
                    "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
                },
            ),
            cost,
        )

    print(f"model={MODEL} route={args.route} surface={args.surface} resolution={args.resolution}")
    total = 0.0
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        for line, ok, cost in ex.map(run, jobs):
            print(line)
            total += cost
            if ok:
                manifest[ok[0]] = ok[1]

    mf_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"\ntotal ${total:.4f} | manifest: {mf_path.relative_to(REPO)}")
    print("Review at final size (34-48pt for nomatch/duo/note) before accepting.")


if __name__ == "__main__":
    main()
