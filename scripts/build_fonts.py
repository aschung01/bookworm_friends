#!/usr/bin/env python3
"""Build the app's font assets: download upstream faces, subset, write to
`assets/fonts/`.

Run with a Python that has `fontTools`:

    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 scripts/build_fonts.py

Why a script rather than committing the upstream files
------------------------------------------------------
**Flutter does not subset text fonts.** `--tree-shake-icons` covers icon fonts
only, so whatever sits in `assets/fonts/` ships whole. Pretendard's upstream
statics are 1.50MB each and Gowun Batang's is 8.18MB, both carrying glyphs this
app never sets. Subsetting takes the five files from 14.2MB upstream to **6.4MB
shipped**, so it has to happen somewhere, and a checked-in script is the only
version of "somewhere" that is reviewable and repeatable.

Two faces, two different coverage rules
---------------------------------------
`Pretendard` sets **everything the serif does not**: usernames, book titles in
lists, memos, shelf names. That is arbitrary text, so it gets the full Hangul
syllable block plus Latin-1 -- the smallest cut with no tofu risk for Korean or
English. Hanja or kana in an imported book title still falls through to the
platform font, exactly as today.

`GowunBatang` sets [AppTextStyles.title], [AppTextStyles.hero] and
[AppTextStyles.spine]. The first two are the app's own words, where coverage is
guaranteed by construction; `spine` is a **book title**, which is catalogue text
and is not. So the cut is Latin-1 plus **KS X 1001's 2,350 syllables** -- see
`ks_x_1001_hangul` for what that set is, why it is derived rather than hardcoded,
and the three corpora it was verified against.

Why not the whole block, and why not a second face
--------------------------------------------------
Both were tried. The numbers are the whole argument:

| Gowun Batang 700, cut to           | Syllables | Shipped |
| ---------------------------------- | --------- | ------- |
| the whole Hangul block             |    11,172 |  7.85MB |
| KS X 1001 + 438 (Hahmlet's set)    |     2,788 |  1.66MB |
| **KS X 1001**                      | **2,350** | **1.39MB** |

The full block was shipped briefly and cost 7.85MB -- a traditional batang's
outlines are heavy, so Latin + all Hangul barely shrinks the 8.18MB original. It
bought 8,822 syllables that no corpus here reaches.

Hahmlet was then shipped instead, because Gowun Batang has no real bold: measured
as ink coverage of the same Hangul string at the same point size, Gowun Batang 700
draws **21.3%** against Hahmlet 700's **32.2%** (Pretendard w700 is 31.7%). But
Hahmlet's upstream has only 2,788 syllables, so its 1.38MB was never buying
coverage -- and at the KS X 1001 cut Gowun Batang costs **1.39MB**, within 10KB.
So the two faces cost the same and the choice is purely how the spine should look.
See `docs/mockups/spine-type/README.md` for the survey of all seven Korean serifs
on Google Fonts, none of which has both full coverage and a genuine bold.

Weights are the four the scale asks for
---------------------------------------
400 body, 600 subtitle/label, 700 figure/caption, 800 the Card's hero figure.
Statics rather than the variable file on purpose: Flutter does not drive a
variable font's `wght` axis from `TextStyle.fontWeight` -- that needs
`fontVariations` -- and four statics at ~1.2MB beat the 6.4MB variable file.
"""

from __future__ import annotations

import json
import re
import subprocess
import urllib.request
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fonts"
CACHE = ROOT / "build" / ".fontcache"
KO_ARB = ROOT / "lib" / "l10n" / "app_ko.arb"

PYFTSUBSET = "/Library/Frameworks/Python.framework/Versions/3.10/bin/pyftsubset"
UA = "curl/8.7.1"

PRETENDARD_URL = (
    "https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9"
    "/packages/pretendard/dist/public/static/Pretendard-{name}.otf"
)

# Latin-1, the punctuation the UI actually uses, won/euro, and Hangul
# compatibility jamo -- which a Korean IME can leave behind in a username.
LATIN = (
    "U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-201D,U+2026,"
    "U+00B7,U+20A9,U+20AC,U+3130-318F"
)
ALL_HANGUL = "U+AC00-D7A3"


@dataclass(frozen=True)
class Job:
    out: str
    url: str
    unicodes: str
    text: str = ""


def ko_arb_hangul() -> str:
    """Every Hangul syllable appearing in the app's own Korean strings.

    Read from the .arb rather than hardcoded, so adding a Korean string and
    rerunning this script is all it takes for the serif to cover it.
    """
    data = json.loads(KO_ARB.read_text(encoding="utf-8"))
    text = "".join(str(v) for k, v in data.items() if not k.startswith("@"))
    return "".join(sorted({c for c in text if 0xAC00 <= ord(c) <= 0xD7A3}))


def ks_x_1001_hangul() -> str:
    """The 2,350 precomposed Hangul syllables of KS X 1001.

    Derived rather than hardcoded, by asking whether a syllable is encodable in
    **ISO-2022-KR** -- which is exactly the KS X 1001 wansung repertoire. Note that
    Python's `euc_kr` codec is *not* usable for this: it is CP949/UHC-backed and
    happily encodes all 11,172, so a check built on it silently reports full
    coverage. That mistake was made once already.

    Why this set. KS X 1001 has been the practical repertoire for Korean
    typesetting since 1987, and the whole block is 4.8x the bytes for syllables no
    real text reaches. Verified against three corpora, with **0 misses** in each:
    the 618 distinct syllables across the 624 titles in `migration_data/book.jsonl`,
    the 290 in `app_ko.arb`, and 39 deliberately awkward words -- loanword
    transliterations, foreign names, double-consonant finals.
    """
    out = []
    for cp in range(0xAC00, 0xD7A4):
        ch = chr(cp)
        try:
            ch.encode("iso2022_kr")
        except UnicodeEncodeError:
            continue
        out.append(ch)
    return "".join(out)


def gf_ttf_url(family: str, weight: int) -> str:
    """The one full TTF Google Fonts serves for a single weight to a plain UA.

    Resolved at build time rather than pinned: gstatic filenames carry a content
    hash that changes with every font revision, so a pinned URL is a link that
    dies quietly.
    """
    req = urllib.request.Request(
        "https://fonts.googleapis.com/css2?family="
        + family.replace(" ", "+")
        + f":wght@{weight}",
        headers={"User-Agent": UA},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        css = r.read().decode()
    urls = re.findall(r"url\((https://[^)]+?\.ttf)\)", css)
    if len(urls) != 1:
        raise SystemExit(
            f"{family} {weight}: expected 1 ttf url, got {len(urls)}. "
            "Google Fonts changed its plain-UA response; adjust the parser."
        )
    return urls[0]


def fetch(url: str, name: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    dst = CACHE / name
    if not dst.exists() or dst.stat().st_size == 0:
        print(f"    fetch {url}")
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=180) as r:
            dst.write_bytes(r.read())
    return dst


def subset(src: Path, dst: Path, unicodes: str, text: str) -> None:
    args = [
        PYFTSUBSET,
        str(src),
        f"--unicodes={unicodes}",
        f"--output-file={dst}",
        # `tnum` is not optional: `AppTextStyles.display`, `figure` and `label`
        # ask for tabular figures and would silently get proportional ones if the
        # feature were dropped here.
        "--layout-features=kern,liga,tnum,calt",
        "--no-hinting",
        "--drop-tables+=DSIG",
    ]
    if text:
        args.append(f"--text={text}")
    subprocess.run(args, check=True)


def main() -> None:
    if not Path(PYFTSUBSET).exists():
        raise SystemExit(f"pyftsubset not found at {PYFTSUBSET}")

    serif_text = ko_arb_hangul()
    print(f"serif Hangul from app_ko.arb: {len(serif_text)} syllables")

    jobs: list[Job] = [
        Job(
            out=f"Pretendard-{name}.otf",
            url=PRETENDARD_URL.format(name=name),
            unicodes=f"{LATIN},{ALL_HANGUL}",
        )
        for name in ("Regular", "SemiBold", "Bold", "ExtraBold")
    ]
    jobs.append(
        Job(
            out="GowunBatang-Bold.ttf",
            url=gf_ttf_url("Gowun Batang", 700),
            # Latin-1 by range; Hangul by literal text, because KS X 1001 is not a
            # contiguous range. The app's own syllables are unioned in even though
            # all 290 are already inside KS X 1001 -- a future Korean string need
            # not be, and this is the belt-and-braces that stops a new `.arb` entry
            # from silently falling through to Pretendard mid-title.
            unicodes=LATIN,
            text=ks_x_1001_hangul() + serif_text,
        )
    )

    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for job in jobs:
        print(f"  {job.out}")
        src = fetch(job.url, job.out.replace(".otf", ".src.otf").replace(".ttf", ".src.ttf"))
        dst = OUT / job.out
        subset(src, dst, job.unicodes, job.text)
        size = dst.stat().st_size
        total += size
        print(
            f"    {src.stat().st_size / 1048576:6.2f} MB upstream"
            f"  ->  {size / 1048576:6.2f} MB shipped"
        )

    print(f"\nassets/fonts total: {total / 1048576:.2f} MB across {len(jobs)} files")


if __name__ == "__main__":
    main()
