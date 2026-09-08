#!/usr/bin/env python3
"""Generate `_build/fonts.css` — the candidate faces, subset and inlined.

Run with a Python that has `fontTools`:

    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 build-fonts.py

Why inline rather than link a CDN. Every other page in `docs/mockups` opens
straight from disk with no network, and the index promises exactly that. A
typography comparison is the *worst* page to break that promise on: with no
network it would not fail loudly, it would silently render all seven candidates
in the same fallback face and quietly answer the question wrongly. So the faces
are subset to the glyphs this page actually draws and base64'd into one CSS
file. The whole set lands in tens of kilobytes, well under the 217-243KB the
existing mockup pages already weigh.

WOFF, not WOFF2, because the only local fontTools has no `brotli`. WOFF is zlib
and needs nothing extra; every browser that can run this page reads it. The cost
is a couple of KB per face on a subset this small.

Sources are resolved at build time rather than pinned by URL hash: Google Fonts'
gstatic filenames carry a content hash that changes with every font revision, so
a pinned URL is a link that dies quietly. Asking `css2` for one weight with a
plain UA returns exactly one full TTF, which is the file we want to subset.
"""

from __future__ import annotations

import base64
import io
import re
import subprocess
import urllib.request
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE / "_build" / "fonts.css"
CACHE = HERE / "_build" / ".cache"

PYFTSUBSET = "/Library/Frameworks/Python.framework/Versions/3.10/bin/pyftsubset"

UA = "curl/8.7.1"

# Everything this page draws, in both locales, plus the Latin/digit/punctuation
# floor. Assembled as literal text rather than as unicode ranges so that adding
# a string to `index.html` and forgetting to add its glyphs here is a visible
# tofu box rather than a silent fallback to a *different candidate's* metrics —
# which is the one failure this page cannot afford.
TEXT = "".join(
    [
        # Latin floor: ASCII letters, digits, and the punctuation in use.
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abcdefghijklmnopqrstuvwxyz",
        "0123456789",
        " .,:;!?'\"’“”·—–-()[]{}/\\&%+*=#@_<>|~$",
        # English UI copy, from `app_en.arb`.
        "My Library Books read No books recorded for All time Friends Card",
        "'s Library Done Poke No finish date January February March April",
        "May June July August September October November December",
        "BOOKS READ IN Novel Textbook Pace per book Top author",
        # Korean UI copy, from `app_ko.arb`.
        "내 서재 읽은 책 전기간 친구 카드 의 서재 소설 교재 권 월 년에 기록된 책이 없어요",
        "다 읽은 날 미지정 읽은 책이 없어요 완료 콕 찌르기 올해 읽은 책",
        "가장 많이 읽은 작가 권당 며칠 쪽",
        # Sample book and author names, Latin and Korean.
        "Inheritance Christopher Paolini The Overstory Richard Powers",
        "사피엔스 유발 하라리 소년이 온다 한강 데미안 헤르만 헤세 코스모스 칼 세이건",
        # Specimen and control copy that the page itself sets in the candidates.
        "Display Figure Title Subtitle Body Label Caption Today system",
        "metrics fixed inherited scale proposed tabular proportional",
        "Pretendard Noto Sans KR IBM Plex Sans KR Gothic A1 Hahmlet",
        "Gowun Batang Apple SD Gothic Neo San Francisco Roboto",
        "The quick brown fox jumps over the lazy dog",
        "다람쥐 헌 쳇바퀴에 타고파",
        # Emoji appears in `noFinishedBooks`; it will not be in any of these
        # faces and is meant to fall through to the system emoji font. Listed so
        # that is a decision on the record rather than an oversight.
        "🥲",
    ]
)


@dataclass(frozen=True)
class Face:
    """One candidate family.

    A face is either a Google Fonts family at a list of discrete `weights`, or a
    single `url` to a variable file. `variable` carries the CSS `font-weight`
    range to declare for the latter.
    """

    family: str
    gf: str | None = None
    weights: tuple[int, ...] = ()
    url: str | None = None
    variable: str | None = None
    stem: str | None = None

    def jobs(self) -> list[tuple[str, str, str]]:
        """(css font-weight, source url, cache stem) per file to emit."""
        if self.url:
            assert self.variable and self.stem
            return [(self.variable, self.url, self.stem)]
        assert self.gf, f"{self.family}: needs either a url or a gf family"
        slug = self.family.lower().replace(" ", "-")
        return [
            (str(w), gf_ttf_url(self.gf, w), f"{slug}-{w}") for w in self.weights
        ]


FACES = [
    Face(
        family="Pretendard",
        url=(
            "https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9"
            "/packages/pretendard/dist/public/variable/PretendardVariable.ttf"
        ),
        # Kept variable. The weight range is half the argument for this face —
        # the app asks for w500 and w600 today and gets them synthesised.
        variable="45 920",
        stem="pretendard-var",
    ),
    Face(family="Noto Sans KR", gf="Noto Sans KR", weights=(400, 600, 700)),
    Face(family="IBM Plex Sans KR", gf="IBM Plex Sans KR", weights=(400, 600, 700)),
    Face(family="Gothic A1", gf="Gothic A1", weights=(400, 700, 800)),
    # Display candidates. All serifs with real Hangul — a Latin-only serif would
    # reintroduce the two-face mismatch this whole page argues against, so a
    # display face that cannot set 내 서재 is not a candidate.
    Face(family="Hahmlet", gf="Hahmlet", weights=(400, 600, 700)),
    Face(family="Gowun Batang", gf="Gowun Batang", weights=(400, 700)),
    Face(family="Noto Serif KR", gf="Noto Serif KR", weights=(400, 600, 700)),
    Face(family="Nanum Myeongjo", gf="Nanum Myeongjo", weights=(400, 700, 800)),
    # 400 only, which is the whole of what it can carry — recorded here rather
    # than discovered later, because a display face with one weight cannot do
    # both the 22pt title and the 46pt figure.
    Face(family="Song Myung", gf="Song Myung", weights=(400,)),
]


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def cached(name: str, url: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if not path.exists() or path.stat().st_size == 0:
        print(f"  fetch {url}")
        path.write_bytes(fetch(url))
    return path


def gf_ttf_url(family: str, weight: int) -> str:
    """The one full TTF Google Fonts serves for a single weight to a plain UA."""
    css = fetch(
        "https://fonts.googleapis.com/css2?family="
        + family.replace(" ", "+")
        + f":wght@{weight}"
    ).decode()
    urls = re.findall(r"url\((https://[^)]+?\.ttf)\)", css)
    if len(urls) != 1:
        raise SystemExit(
            f"{family} {weight}: expected 1 ttf url, got {len(urls)}. "
            "Google Fonts changed its plain-UA response; adjust the parser."
        )
    return urls[0]


def subset(src: Path, dst: Path) -> None:
    # No axis flag: `pyftsubset` carries `fvar`/`gvar` through untouched, so a
    # variable source stays variable. Pinning an axis is `varLib.instancer`'s
    # job, and pinning is the opposite of what Pretendard is here to show.
    subprocess.run(
        [
            PYFTSUBSET,
            str(src),
            f"--text={TEXT}",
            f"--output-file={dst}",
            "--flavor=woff",
            "--layout-features=kern,liga,tnum,calt",
            "--no-hinting",
            "--drop-tables+=DSIG",
        ],
        check=True,
    )


def main() -> None:
    if not Path(PYFTSUBSET).exists():
        raise SystemExit(f"pyftsubset not found at {PYFTSUBSET}")

    out = io.StringIO()
    out.write(
        "/* GENERATED by build-fonts.py — do not edit.\n"
        "   Candidate faces, subset to this page's glyphs and inlined so the\n"
        "   page answers correctly with no network. See build-fonts.py. */\n"
    )

    total = 0
    for face in FACES:
        print(face.family)
        for weight, url, stem in face.jobs():
            src = cached(stem + Path(url).suffix, url)
            dst = CACHE / (stem + ".woff")
            subset(src, dst)
            size = dst.stat().st_size
            total += size
            print(f"  {weight:>7}  {size / 1024:6.1f} KB")
            blob = base64.b64encode(dst.read_bytes()).decode()
            out.write(
                f"@font-face{{font-family:'{face.family}';font-style:normal;"
                f"font-weight:{weight};font-display:block;"
                f"src:url(data:font/woff;base64,{blob}) format('woff')}}\n"
            )

    OUT.write_text(out.getvalue())
    print(
        f"\n{OUT.relative_to(HERE)}: {OUT.stat().st_size / 1024:.0f} KB "
        f"({total / 1024:.0f} KB of font data)"
    )


if __name__ == "__main__":
    main()
