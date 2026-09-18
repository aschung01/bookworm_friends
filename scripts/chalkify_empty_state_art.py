#!/usr/bin/env python3
"""Generate the empty-state illustrations in the app icon's chalk style, on Bedrock.

Two routes. Both send `assets/branding/app_icon_source.png` -- the shipping
icon, itself an AI-generated raster -- so the chalk hand comes from the brand
mark rather than from a description of it.

  --route styleguide
      Icon as the *style reference*, plus a per-piece text prompt. The model
      invents the drawing; nothing of ours constrains the composition.
      Model: us.stability.stable-image-style-guide-v1:0

      DOES NOT WORK on this account, measured -- kept only so the finding is
      reproducible. style-guide is a style matcher, not a compositional model:
      with a strong reference it reduces any prompt to "a book on green". At
      fidelity 0.9, four of six pieces came back BYTE-IDENTICAL (same md5) --
      only the two whose prompts omit the shared book description differed. A
      sweep at 0.3 / 0.5 / 0.7 / 0.9 produced one plain white book every time:
      the dashed slot, sparkles, magnifier and pencil never appeared at all.
      Low fidelity additionally reintroduces 3D notebooks with cast shadows.

      The underlying reason is account-level: there is no general
      text-to-image model available here. `amazon.nova-canvas-v1:0` is the only
      one and it 404s as Legacy; every other image model is an edit/control
      model that needs an input image. Prompt-driven generation needs either a
      current image model enabled in the Bedrock console, or a multimodal model
      that follows instructions alongside a reference image (Gemini
      gemini-2.5-flash-image -- see scripts/gen_empty_state_art.py -- or
      OpenAI gpt-image).

  --route transfer     (default; the only route that produces usable output here)
      Icon as the style image, and one of our cmass-*.svg vectors -- recoloured
      to the icon's polarity and rasterised -- as the content image. Keeps exact
      compositional control, which on this account is the *only* way to get a
      composition at all.
      Model: us.stability.stable-style-transfer-v1:0
      Known cost: it faithfully reproduces whatever the vector got wrong. The
      first run inherited a crown-shaped ribbon and lost every green detail,
      because build_plate() maps all accents to the plate colour. Fix the
      vector, not the parameters.

Auth: a Bedrock API key in AWS_BEARER_TOKEN_BEDROCK (AWS_REGION selects the
region, default us-east-1). The bundled aws CLI is from 2022 and has no
`bedrock` command, so this talks to the REST endpoint directly.

Rejected earlier, do not retry: amazon.nova-canvas-v1:0 (404, marked Legacy on
this account) and control-structure / control-sketch (they read filled masses
as outlines and render physical chalk sticks on a photographed board).

    python3 scripts/chalkify_empty_state_art.py --list
    python3 scripts/chalkify_empty_state_art.py --variants 2
    python3 scripts/chalkify_empty_state_art.py --only duo --seed 23
    python3 scripts/chalkify_empty_state_art.py --route styleguide --only rest
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ART = REPO / "docs" / "mockups" / "empty-states" / "art"
OUT = ART / "gen"
PLATES = OUT / "plates"
ICON = REPO / "assets" / "branding" / "app_icon_source.png"

MODEL_STYLEGUIDE = "us.stability.stable-image-style-guide-v1:0"
MODEL_TRANSFER = "us.stability.stable-style-transfer-v1:0"

PLATE_GREEN = "#38b28a"  # sampled from the icon's plate
INK = "#626A72"  # AppColors.light.secondaryText, as used in cmass-*.svg
ACCENT = "#09BC8A"  # AppColors brand

# styleguide: 0.2-0.5 produced 3D books on desks and invented scribbled titles;
# 0.8-1.0 gave flat, face-on, blank-cover chalk. transfer: 0.8/0.9 keeps our
# geometry while letting grain through.
FIDELITY = 0.9
STYLE_STRENGTH = 0.8
COMPOSITION_FIDELITY = 0.9

# The book, described so the model builds the icon's own construction. The
# ribbon gets explicit dimensions because at high fidelity the model kept
# dropping it -- it is the one element that must survive.
BOOK = (
    "one closed book seen perfectly straight on from the front, with no "
    "perspective and no thickness. Its cover is a plain blank upright "
    "rectangle of solid white chalk with absolutely nothing written or drawn "
    "on it. A separate narrow vertical strip of chalk runs down the left edge "
    "as the spine. A bookmark ribbon hangs from the top edge of the cover near "
    "the right side: a long narrow vertical band, roughly one sixth as wide as "
    "the cover and half as tall, ending in a V notch cut into its bottom. The "
    "ribbon is the same green as the background, cut out of the white cover so "
    "the background shows through it."
)

PIECES: dict[str, tuple[str, str]] = {
    "rest": (
        "empty library, a friend's (100pt) - library_view.dart",
        f"A flat white chalk pictogram of {BOOK} The book sits alone, centred, "
        "nothing else in the frame.",
    ),
    "invite": (
        "empty library, yours (100pt) - library_view.dart",
        f"A flat white chalk pictogram of {BOOK} To its left stands a second "
        "upright rectangle of the same height drawn only as a dashed chalk "
        "outline, clearly empty and unfilled, like a slot waiting for a book. "
        "Two small four-pointed chalk sparkles float above the gap between "
        "them.",
    ),
    "search": (
        "add-book sheet idle (100pt) - add_book_bottom_sheet.dart",
        f"A flat white chalk pictogram of {BOOK} A simple round magnifying "
        "glass with a short straight handle is drawn in white chalk over the "
        "lower right of the cover, its lens an empty circle.",
    ),
    "nomatch": (
        "no search results (40pt) - add_book_bottom_sheet.dart",
        "A flat white chalk pictogram of one upright book-shaped rectangle "
        "drawn only as a dashed chalk outline, clearly empty and unfilled, "
        "with one large white chalk question mark centred inside it. Nothing "
        "else in the frame.",
    ),
    "note": (
        "Notes tab empty (48pt) - book_details_tab_view.dart",
        f"A flat white chalk pictogram of {BOOK} Two short horizontal chalk "
        "rule lines are written across the middle of the cover as if it were a "
        "page, and a simple pencil lies diagonally across the lower right of "
        "the cover with its tip pointing down and left.",
    ),
    "duo": (
        "no friends yet (40pt) - friends_sheet.dart",
        "A flat white chalk pictogram of two closed books seen straight on "
        "from the front, standing side by side and leaning gently towards each "
        "other so they touch, drawn as solid white chalk rectangles of "
        "slightly different heights with a narrow gap of background between "
        "them. The right-hand book has a bookmark ribbon hanging from the top "
        "of its cover: a long narrow vertical band ending in a V notch, in the "
        "same green as the background so it reads as cut out of the white.",
    ),
}

STYLE_TAIL = (
    " Drawn in dry white chalk on a flat green chalkboard, matching the "
    "reference exactly: powdery chalk grain, slightly irregular hand-drawn "
    "edges, bold simple filled shapes, completely flat. Centred with generous "
    "even margins, nothing cropped."
)

NEGATIVE = (
    "photograph, photorealistic, realistic, 3d render, depth, shadow, drop "
    "shadow, perspective, thickness, physical notebook, real object, mockup, "
    "desk, table, paper texture, stationery, open book, visible pages, "
    "gradient, vignette, blur, bokeh, frame, border, squircle, rounded "
    "rectangle frame, app icon, ui card, text, letters, numbers, words, "
    "handwriting, scribble, title on cover, watermark, signature, smudge"
)

TRANSFER_PROMPT = (
    "white chalk drawn on a green chalkboard, dry powdery chalk grain, softly "
    "irregular hand-drawn chalk edges, bold solid white filled shapes, flat, "
    "no depth"
)


def build_plate(piece: str) -> Path:
    """vector SVG -> 1024px white-on-green plate matching the icon's polarity."""
    src = ART / f"cmass-{piece}.svg"
    if not src.exists():
        sys.exit(f"missing {src.relative_to(REPO)} - regenerate the mockup art first")
    svg = src.read_text()
    svg = svg.replace(INK, "#FFFFFF").replace(ACCENT, PLATE_GREEN)
    svg = re.sub(
        r"(<svg[^>]*>)",
        r'\1<rect width="120" height="120" fill="' + PLATE_GREEN + '"/>',
        svg,
        count=1,
    )
    PLATES.mkdir(parents=True, exist_ok=True)
    sp = PLATES / f"plate-{piece}.svg"
    sp.write_text(svg)
    pp = PLATES / f"plate-{piece}.png"
    subprocess.run(
        ["rsvg-convert", "-w", "1024", "-h", "1024", str(sp), "-o", str(pp)],
        check=True,
    )
    return pp


def post(model: str, body: dict) -> bytes | str:
    region = os.environ.get("AWS_REGION", "us-east-1")
    tok = os.environ.get("AWS_BEARER_TOKEN_BEDROCK")
    if not tok:
        sys.exit("AWS_BEARER_TOKEN_BEDROCK is not set.")
    url = f"https://bedrock-runtime.{region}.amazonaws.com/model/{model}/invoke"
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=240) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}: {e.read().decode(errors='replace')[:200]}"
    except urllib.error.URLError as e:
        return f"network: {e.reason}"
    imgs = payload.get("images") or []
    if not imgs:
        return f"no image (finish_reasons={payload.get('finish_reasons')})"
    return base64.b64decode(imgs[0])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--route", choices=["styleguide", "transfer"], default="transfer")
    ap.add_argument("--only", nargs="+", metavar="PIECE")
    ap.add_argument("--variants", type=int, default=1)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--fidelity", type=float, default=FIDELITY)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for p, (site, _) in PIECES.items():
            print(f"{p:9s} {site}")
        return
    if not ICON.exists():
        sys.exit(f"style reference missing: {ICON}")

    todo = args.only or list(PIECES)
    bad = [t for t in todo if t not in PIECES]
    if bad:
        sys.exit(f"unknown piece(s): {', '.join(bad)} (try --list)")

    icon_b64 = base64.b64encode(ICON.read_bytes()).decode()
    OUT.mkdir(parents=True, exist_ok=True)
    mf_path = OUT / "manifest.json"
    manifest = json.loads(mf_path.read_text()) if mf_path.exists() else {}
    sg = args.route == "styleguide"
    model = MODEL_STYLEGUIDE if sg else MODEL_TRANSFER
    tag = "sg" if sg else "tr"

    jobs = []
    for piece in todo:
        plate = None if sg else build_plate(piece)
        for v in range(args.variants):
            jobs.append((piece, plate, args.seed + v * 16, v + 1))

    def run(job):
        piece, plate, seed, v = job
        site, subject = PIECES[piece]
        prompt = subject + STYLE_TAIL
        if sg:
            body = {
                "prompt": prompt,
                "image": icon_b64,
                "negative_prompt": NEGATIVE,
                "aspect_ratio": "1:1",
                "output_format": "png",
                "fidelity": args.fidelity,
                "seed": seed,
            }
        else:
            body = {
                "init_image": base64.b64encode(plate.read_bytes()).decode(),
                "style_image": icon_b64,
                "prompt": TRANSFER_PROMPT,
                "negative_prompt": NEGATIVE,
                "output_format": "png",
                "seed": seed,
                "style_strength": STYLE_STRENGTH,
                "composition_fidelity": COMPOSITION_FIDELITY,
            }
        res = post(model, body)
        name = f"{piece}-{tag}-v{v}"
        if isinstance(res, str):
            return f"  {name}: {res}", None
        (OUT / f"{name}.png").write_bytes(res)
        entry = {
            "piece": piece,
            "call_site": site,
            "route": args.route,
            "model": model,
            "style_image": str(ICON.relative_to(REPO)),
            "prompt": prompt if sg else TRANSFER_PROMPT,
            "negative_prompt": NEGATIVE,
            "seed": seed,
            "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
        if sg:
            entry["fidelity"] = args.fidelity
            entry["content_input"] = "none - model generates from the icon + prompt"
        else:
            entry["content_plate"] = f"cmass-{piece}.svg -> white-on-{PLATE_GREEN}"
            entry["style_strength"] = STYLE_STRENGTH
            entry["composition_fidelity"] = COMPOSITION_FIDELITY
        return f"  wrote {name}.png ({len(res) // 1024} KB)", (name, entry)

    print(f"route={args.route} model={model} fidelity={args.fidelity}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        for line, ok in ex.map(run, jobs):
            print(line)
            if ok:
                manifest[ok[0]] = ok[1]

    mf_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"\nmanifest: {mf_path.relative_to(REPO)}")
    print("Review at final size (34-48pt for nomatch/duo/note) before accepting.")


if __name__ == "__main__":
    main()
