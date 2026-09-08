"""Fetch and subset serif candidates for the spine-type mockup.

    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 \
        docs/mockups/spine-type/build_serifs.py

Why this exists, and why the output is not an app asset
------------------------------------------------------
The page needs to *show* a book title set in a serif, and the app cannot: the
shipped `GowunBatang-Bold.ttf` is cut to the 262 Hangul syllables in
`app_ko.arb`, so a real title comes out part serif and part Pretendard. That is
the finding, not a thing to work around -- but it also means a mockup that wants
to argue about serifs has to carry its own faces.

So these are cut to **exactly the text this page sets** -- the ten corpus titles
plus the two specimen strings -- rather than to a script range. That is a few KB
per face instead of a few MB, and it is the honest size for a drawing: nothing
here is evidence about what shipping a serif would cost. For that number, run
`scripts/build_fonts.py` with `ALL_HANGUL` added to the GowunBatang job and read
what it prints.

Output goes to `docs/mockups/spine-type/fonts/`, deliberately **not** to
`assets/fonts/`, so no amount of `pubspec.yaml` editing can accidentally ship a
mockup's font. Reuses `scripts/build_fonts.py`'s fetch, cache, subset and URL
resolution rather than restating them, so the mockup's faces are built the same
way the app's are.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(HERE))

# `ty` cannot follow the `sys.path` insert above, so the `scripts/` import needs
# its own suppression; `render` sits beside this file and resolves normally.
from build_fonts import (  # type: ignore[import]  # ty: ignore[unresolved-import]
    fetch,
    gf_ttf_url,
    subset,
)
from render import BOOKS  # type: ignore[import]

OUT = HERE / "fonts"

# ASCII, and nothing else by range -- the rest comes from `--text`.
#
# Deliberately **not** `build_fonts.LATIN`, which is right for the app and wrong
# here: it carries Latin-1 accents the page never sets and, more expensively,
# `U+3130-318F` compatibility jamo, which in a Korean serif are 96 full-width
# glyphs. Reusing it cost about 25KB per face for characters no drawing shows.
ASCII = "U+0020-007E"

# Latin and Hangul serif candidates, all from Google Fonts.
#
# Two weights where the family has them, because a spine sets 12.5-15pt type and
# the whole question is whether a serif holds up there -- `AppTextStyles.title`'s
# doc already records that Gowun Batang Bold's stem measures 250/1000, lighter
# than most families' regular, which is exactly the kind of thing one weight
# would hide.
#
# (file stem, Google Fonts family, weights)
SERIFS = [
    # The app's own serif, whole. The direct answer to "what if we shipped it".
    ("GowunBatangFull", "Gowun Batang", [400, 700]),
    # The workhorse Korean serif; what most Korean sites reach for.
    ("NotoSerifKR", "Noto Serif KR", [400, 600]),
    # A classic myeongjo, warmer and narrower than Noto.
    ("NanumMyeongjo", "Nanum Myeongjo", [400, 700]),
    # A display myeongjo with high stroke contrast -- the most "book jacket" of
    # the set, and the one most likely to fall apart at 13pt.
    ("SongMyung", "Song Myung", [400]),
    # A modern serif with noticeably heavier stems, named in the spine spec as
    # the comparison that made Gowun Batang look light. The only family here with
    # a cut *between* regular and semibold -- it is variable wght 100-900, so
    # Google serves a static instance at every 100 step.
    ("Hahmlet", "Hahmlet", [400, 500, 600]),
]

# Everything the page and the PNG actually set in these faces.
SPECIMEN_STRINGS = ["Crossing the Chasm", "인공지능 딥러닝 입문"]


def corpus_text() -> str:
    """Every character the mockup sets, so the subset can be exactly that.

    Read from `render.BOOKS` rather than restated, for the reason the coverage
    snippet in README.md is: the page, the PNG and these fonts have to be arguing
    over the same ten books.
    """
    joined = "".join(t for t, *_ in BOOKS) + "".join(SPECIMEN_STRINGS)
    return "".join(sorted(set(joined)))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    text = corpus_text()
    hangul = [c for c in text if "\uac00" <= c <= "\ud7a3"]
    print(
        f"subsetting to the mockup's own text: {len(text)} distinct chars, "
        f"{len(hangul)} of them Hangul"
    )

    total = 0
    for stem, family, weights in SERIFS:
        for weight in weights:
            name = f"{stem}-{weight}.ttf"
            print(f"  {name}")
            url = gf_ttf_url(family, weight)
            src = fetch(url, f"mockup-{stem}-{weight}.src.ttf")
            dst = OUT / name
            subset(src, dst, ASCII, text)
            size = dst.stat().st_size
            total += size
            print(
                f"    {src.stat().st_size / 1048576:6.2f} MB upstream"
                f"  ->  {size / 1024:6.1f} KB subset"
            )

    print(f"\n{OUT.relative_to(ROOT)} total: {total / 1024:.1f} KB")
    print("Not an app asset. Do not add these to pubspec.yaml.")


if __name__ == "__main__":
    main()
