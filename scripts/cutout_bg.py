#!/usr/bin/env python3
"""Key the flat white background out of generated art, producing RGBA PNGs.

`scripts/gen_empty_state_art.py --surface paper` draws dark chalk on a flat
white field, because the xAI image endpoint returns **JPEG** and so cannot carry
an alpha channel itself. This strips that white and writes real transparency, so
the illustrations sit directly on `pageBackground` / the mint sheet / the dark
page instead of carrying a plate of their own.

Uses Bedrock `stability.stable-image-remove-background-v1:0`, which is one of
the few image models actually enabled on this account (see
scripts/chalkify_empty_state_art.py for the survey). Verified output: colour
type 6, 8-bit RGBA. The white ribbon knockout keys out too, so the background
shows through it -- which is exactly how the icon's ribbon reads.

There is no local fallback: this machine has neither PIL nor ImageMagick, and
the inputs are JPEG, so pure-Python keying would need a JPEG decoder.

Auth: AWS_BEARER_TOKEN_BEDROCK (AWS_REGION optional, default us-east-1).

    python3 scripts/cutout_bg.py                     # every *-paper-*.jpg
    python3 scripts/cutout_bg.py --glob 'invite-*'   # a subset
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import os
import struct
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / "docs" / "mockups" / "empty-states" / "art" / "gen"
OUT = GEN / "cut"
MODEL = "us.stability.stable-image-remove-background-v1:0"


def has_alpha(png: bytes) -> bool:
    """True when the PNG's IHDR declares a colour type carrying alpha (4 or 6)."""
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        return False
    pos = 8
    while pos + 12 <= len(png):
        length = struct.unpack(">I", png[pos : pos + 4])[0]
        if png[pos + 4 : pos + 8] == b"IHDR":
            return struct.unpack(">IIBBBBB", png[pos + 8 : pos + 8 + length])[3] in (4, 6)
        pos += 12 + length
    return False


def cutout(src: Path) -> str:
    tok = os.environ.get("AWS_BEARER_TOKEN_BEDROCK")
    if not tok:
        sys.exit("AWS_BEARER_TOKEN_BEDROCK is not set.")
    region = os.environ.get("AWS_REGION", "us-east-1")
    body = {
        "image": base64.b64encode(src.read_bytes()).decode(),
        "output_format": "png",
    }
    req = urllib.request.Request(
        f"https://bedrock-runtime.{region}.amazonaws.com/model/{MODEL}/invoke",
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
        return f"  {src.name}: HTTP {e.code} {e.read().decode(errors='replace')[:180]}"
    except urllib.error.URLError as e:
        return f"  {src.name}: network {e.reason}"
    imgs = payload.get("images") or []
    if not imgs:
        return f"  {src.name}: no image (finish={payload.get('finish_reasons')})"
    png = base64.b64decode(imgs[0])
    if not has_alpha(png):
        return f"  {src.name}: REJECTED - result has no alpha channel"
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / (src.stem + ".png")
    dst.write_bytes(png)
    return f"  wrote cut/{dst.name} ({len(png) // 1024} KB, RGBA)"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--glob",
        default="*-paper-*.jpg",
        help="which files in art/gen/ to key (default: the paper-surface set)",
    )
    args = ap.parse_args()

    srcs = sorted(GEN.glob(args.glob))
    if not srcs:
        sys.exit(f"nothing matched {args.glob} in {GEN.relative_to(REPO)}")
    print(f"model={MODEL}\nkeying {len(srcs)} file(s)")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        for line in ex.map(cutout, srcs):
            print(line)
    print(f"\noutput: {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
