#!/usr/bin/env python3
"""Check the listing draft's fields against App Store Connect's character limits.

Reads `docs/store/listing-1.1.0.md`, finds each `### <Field> (limit N)` heading, and
measures every fenced block beneath it up to the next heading. Run after editing the
draft and before publishing anything.

Apple counts characters, not bytes, so Korean is measured per glyph -- which is why
this uses len() on the decoded string and not len(s.encode()).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

DRAFT = Path(__file__).resolve().parent.parent / "docs" / "store" / "listing-1.1.0.md"

HEADING = re.compile(r"^###\s+(?P<field>.+?)\s*\(limit\s+(?P<limit>\d+)[^)]*\)", re.M)
FENCE = re.compile(r"^```\s*$\n(?P<body>.*?)^```\s*$", re.M | re.S)


def main() -> int:
    if not DRAFT.exists():
        print(f"draft not found: {DRAFT}", file=sys.stderr)
        return 2

    text = DRAFT.read_text(encoding="utf-8")
    headings = list(HEADING.finditer(text))
    if not headings:
        print("no '### Field (limit N)' headings found", file=sys.stderr)
        return 2

    # Locale comes from the enclosing `## <locale>` section. Every `##` heading is a
    # boundary, and only one shaped like a locale names one -- so a section such as
    # `## App Review notes`, whose field belongs to the version rather than to any
    # locale, reports `?` instead of inheriting whichever locale preceded it.
    LOCALE = re.compile(r"^[a-z]{2}(?:-[A-Z]{2})?$")
    sections = [
        (m.start(), m.group(1).strip())
        for m in re.finditer(r"^##\s+(.+?)\s*$", text, re.M)
    ]

    failures = 0
    for i, h in enumerate(headings):
        start = h.end()
        end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        section = text[start:end]

        enclosing = next(
            (name for pos, name in reversed(sections) if pos < h.start()), ""
        )
        locale = enclosing if LOCALE.match(enclosing) else "?"
        field = h.group("field")
        limit = int(h.group("limit"))

        blocks = [m.group("body") for m in FENCE.finditer(section)]
        if not blocks:
            print(f"  !! {locale:6} {field:22} no fenced block found")
            failures += 1
            continue

        for n, body in enumerate(blocks):
            value = body.rstrip("\n")
            length = len(value)
            ok = length <= limit
            failures += 0 if ok else 1
            label = field if n == 0 else f"{field} (alt {n})"
            mark = "ok  " if ok else "OVER"
            print(
                f"  {mark} {locale:6} {label:26} {length:>5} / {limit}"
                + ("" if ok else f"  -- {length - limit} over")
            )

    print()
    if failures:
        print(f"{failures} field(s) need attention")
        return 1
    print("all fields within limits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
