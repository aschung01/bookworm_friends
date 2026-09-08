# Read-pile spine typography

`index.html` is the page to look at: **five layouts × twelve faces × nine sizes**
for the title on a spine, plus a Hangul-orientation toggle, drawn in real DOM with
real faces loaded off disk. No build, no server, no network — open it from disk
like the rest of `docs/mockups/`.

Layout, face and size are separate controls because they are separate decisions,
and because the interesting comparisons are diagonal: a serif at today's cramped
measure is not the same argument as a serif at a fixed one, and Song Myung is a
different verdict at 12.5pt than at 15. The defaults are the shipped drawing —
layout `now`, face Pretendard SemiBold, size `as laid out` — so the page opens on
something that should match a screenshot.

Two notes on the size axis. `as laid out` is the only value that leaves a layout's
own size rule alone, which is why it is the default; picking a number pins every
spine to it and therefore **overrides layout 3's size-by-thickness rule**, which is
the one thing that layout exists to show — the page says so in the rationale panel
rather than letting it quietly stop demonstrating itself. And the caption prints
the _nominal_ size, the number a `TextStyle` would carry, with the face's optical
nudge shown separately as a percentage.

`render.py` draws the layouts to PNG (`spine-type.png`), plus a face specimen
(`spine-faces.png`), and prints the measure arithmetic and the serif's per-title
coverage:

    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 \
        docs/mockups/spine-type/render.py

## The serif faces are not app assets

`build_serifs.py` fetches five serif families from Google Fonts and subsets them
into `./fonts/`:

    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 \
        docs/mockups/spine-type/build_serifs.py

It reuses `scripts/build_fonts.py`'s URL resolution, cache, fetch and subset, so
the mockup's faces are built the way the app's are. Three things about it are
deliberate:

- **Output is `docs/mockups/spine-type/fonts/`, never `assets/fonts/`**, so no
  amount of `pubspec.yaml` editing can accidentally ship a mockup's font.
- **Subset to exactly the text this page sets** — the ten corpus titles and the
  two specimen strings, read out of `render.BOOKS` rather than restated. That is
  ~35KB per face against 2–13MB upstream, and it means **their size is no evidence
  about what shipping a serif would cost**. For that number, add `ALL_HANGUL` to
  the GowunBatang job in `scripts/build_fonts.py` and read what it prints.
- **ASCII by range, not `build_fonts.LATIN`**. `LATIN` is right for the app and
  wrong here: it carries `U+3130-318F` compatibility jamo, which in a Korean serif
  are 96 full-width glyphs. Reusing it cost about 25KB per face for characters no
  drawing shows.

`Gowun Batang` among them is the app's own serif _whole_ — what the pile would look
like if `AppFonts.serif` were not cut to `app_ko.arb`. That is the comparison the
subsetting currently makes impossible to see.

### Which weights each family actually has

Read from `https://fonts.google.com/metadata/fonts/<Family>` rather than assumed,
because "is there a cut between regular and semibold" has a different answer per
family and only one of these five says yes:

| Family         | Weights served          | Variable       |
| -------------- | ----------------------- | -------------- |
| Hahmlet        | 100–900, every 100 step | `wght` 100–900 |
| Noto Serif KR  | 200–900, every 100 step | `wght` 200–900 |
| Nanum Myeongjo | 400, 700, 800           | no             |
| Gowun Batang   | 400, 700                | no             |
| Song Myung     | 400 only                | no             |

So **Hahmlet is the only family here with a cut between 400 and 600**, and it is
built at 500 for that reason — 400 thins out on a small spine and 600 starts
reading as a slab, so the answer is likely between them. Noto Serif KR also has a
500 if that comparison turns out to be worth making there, and Nanum Myeongjo has
an 800.

One caveat if any of this becomes a shipping decision rather than a drawing: these
are **static instances**, which is what `scripts/build_fonts.py` already requires
and explains — Flutter does not drive a variable font's `wght` axis from
`TextStyle.fontWeight`, that needs `fontVariations`. So "Hahmlet is variable
100–900" does not mean a Flutter app gets the whole axis; it means every weight
wanted is another upstream file to subset and ship.

## Fidelity

Everything geometric is the shipped code: heights 110–124pt and widths 28–39pt
from `BookMetrics.from` at `ReadPile.spineBase`, the 5pt arched head from
`bookSpinePath`, the 28%-black 1pt separator from `BookVertical`, and the ink rule
from `spineToneFor`. The titles are real ones off the shelves in the Library tab,
which matters for the reason `spine_tone_test.dart` says it does: a corpus of
six-syllable titles makes any measure rule look fine.

Each face carries an **optical-size nudge**, because these families do not share a
Hangul body ratio and setting them all at one `font-size` would compare the
numbers rather than the type — Song Myung's Hangul draws small in its em, Gowun
Batang's smaller still. Without it the serifs lose the comparison for a reason
that has nothing to do with being serifs.

Two deliberate differences between the page and the PNG. The page's arch is an
elliptical corner radius rather than `bookSpinePath`'s quadratic bezier, because
CSS has no cheap bezier clip and the two are indistinguishable at 5pt. And the
page wraps with the browser's greedy line breaker where `render.py` picks the most
balanced break — what is being compared is measure and voice, not the break
algorithm.

### Two traps in measuring the page, both hit and both fixed

Every number the page reports — the cut count, the table, the config readout — comes
out of one measurement block, so a measurement bug corrupts all of them together.
Two are worth knowing about, because both looked right:

- **Counting line boxes, not comparing `scrollWidth` to `clientWidth`.** The latter
  reads like a block-axis overflow test and is really "does the glyph ink exceed the
  line box", which is true of every CJK title here because `line-height: 1.04` is far
  tighter than these faces' natural line height. It demoted all ten titles to one
  line at every layout. `lineCount()` uses `Range.getClientRects()`, one rect per
  line box.
- **Measuring after `document.fonts.ready`, not after one frame.** `@font-face` files
  load asynchronously, so the first frame after a face changes can land while the
  title is still laid out in a fallback that breaks lines elsewhere. This bit _only_
  the mockup-only serifs — Pretendard is already loaded by the table cells, so its
  numbers were right and the serifs' were not, which is the worst shape for a bug
  like this to have. A config in Hahmlet Medium reported 7 of 10 titles cut when the
  true figure is 3.

## What the drawings settled

**A spine is set in a UI token.** `BookVertical` uses `AppTextStyles.label`, whose
own doc says "tab labels, shelf tabs, badges, capsules, buttons" — and in a
screenshot of the collapsed Library tab it is literally the same face and weight
as the `Library / Friends / Card` labels 40pt below it. The design record for this
feature says "the 12pt rotated title" in two places; the code ships 13, because
the token moved and the spine came with it. That drift is the symptom, not the
disease.

`label` also carries `FontFeature.tabularFigures()`, which is right for a count
and wrong for a title: `세계를 바꾼 테크놀로지 10` and `5000일 후의 세계` pay
monospaced digit advances out of a measure that has none to spare.

**The measure is 80–94pt and 30 of it is padding.** `EdgeInsets.only(top: 15,
bottom: 15)` on a 110–124pt spine spends a quarter of the book's length on margin,
to clear an arch that is 5pt deep. At 8/9 the measure becomes 93–107pt — about one
more Hangul syllable, for nothing.

**Half the truncation is avoidable and is not about measure at all.** A Korean
catalogue title carries its original title in parentheses and its subtitle after a
colon. `그로스 해킹(Growth Hacking)` truncates to `그로스 해킹(G…`; cut at the first
`(` `:` `[` `—` and it fits whole, with room left. This is the cheapest change here
and the most visible.

**The rest of the truncation is real and should stop apologising for itself.** No
30pt spine holds `인공지능, 머신러닝, 딥러닝 입문`, and no real one does either —
publishers set a short form. What can improve is the failure mode: rotated, `…` is
three dots stacked down the spine, and it costs about a syllable of the measure it
is apologising for. Row 6 fades the tail instead — free measure, and it reads as
the title running under the shelf rather than as a string that was cut.

**Centring hides the jitter this feature was built to add.** The spec's own
argument is that "a row of identical objects is the one thing a shelf never looks
like". `Center` puts every title at the middle of its own spine, so a short title
floats and the row has no shared datum. Head-aligning at a fixed 8pt lets the
ragged heads — which are the jitter, and were paid for — actually show.

**Nothing scales with thickness, so thickness reads as noise.** A book's width is
its page count (`bookThicknessPositionFromPages`), which is real data for a third
of the library. Sizing the title 12.5pt → 15pt across the 28–39pt range makes that
signal visible instead of merely present, and it composes with the measure fix:
thin books get smaller type and therefore _more_ measure, thick books get larger
type and a second line.

### On the face

The obvious move — set the most bookish surface in the app in the serif — is
**unavailable, and the code already knows why**. `AppFonts.serif` is cut to the 262
Hangul syllables in `app_ko.arb`, and a book title is catalogue text. Measured
against the ten real titles above, **17 syllables fall through**; because
`AppTextStyles.title` carries `fontFamilyFallback: [sans]`, that is not a box but a
silent family swap _mid-title_, which is exactly the defect `titleUser`'s doc
describes. The bottom row of `spine-faces.png` is that failure rendered.

#### What shipping one would actually cost

"Full-Hangul subset" is not a contradiction: **subset** because everything the app
will never set is dropped — hanja, kana, other scripts, hinting tables — and **full
Hangul** because the one thing that cannot be dropped is the Hangul syllable block,
`U+AC00-D7A3`, all 11,172 of them. A book title is arbitrary catalogue text, so any
syllable is reachable. That is exactly the cut `build_fonts.py` already makes for
Pretendard, and it is the smallest cut with no tofu risk for Korean.

Measured with `pyftsubset` on the upstream files in `build/.fontcache/`, not
estimated:

| Face             | Upstream | This library's 618 syllables | Asked for all 11,172 |
| ---------------- | -------- | ---------------------------- | -------------------- |
| Hahmlet 500      | 1.42MB   | 312KB                        | **1.32MB**           |
| Gowun Batang 400 | 8.04MB   | 364KB                        | **7.72MB**           |

**The last column is "asked for", not "got", and for Hahmlet those differ.** This
table originally called it "full Hangul block", which is wrong: Hahmlet's upstream
contains only 2,788 of the 11,172 precomposed syllables, so its 1.32MB _is_ the
whole face and a subsetter cannot conjure the rest. Gowun Batang genuinely has all
11,172, which is most of why it costs 6x more. See the survey below.

Two things fall out of that, and the second corrects an earlier guess in this file
that said "expect 1.5–3MB":

- **Hahmlet costs ~1.3MB per weight.** On a 4.97MB font bill that is +27% for one
  weight, which is a decision someone could reasonably say yes to.
- **Gowun Batang costs ~7.7MB per weight**, because a traditional batang's outlines
  are far heavier than a geometric serif's — subsetting to Latin + all Hangul barely
  shrinks the 8.04MB original. Shipping the app's own serif whole would more than
  double the app's font weight, which is almost certainly a no, and is the real
  reason `AppFonts.serif` is cut to `app_ko.arb` in the first place.

The middle column is worth reading but **not shippable**: 618 distinct syllables
cover the 624 titles currently in `migration_data/book.jsonl`, i.e. 5.5% of the
block, but the next book added could need any of the other 94.5%. Subsetting to a
library is a per-user build.

#### Every Korean serif on Google Fonts, measured

There are exactly **seven**, and only four ship a weight above 400. Coverage is the
count of precomposed Hangul syllables in the upstream file; "ink" is the share of
its own set area that the same Hangul string covers at the same point size, which
is the honest proxy for perceived weight (stem-width off standalone jamo is not —
it reports Pretendard Bold as _lighter_ than Gowun Batang Bold). "Subset" is
Latin-1 + `U+AC00-D7A3` through `pyftsubset`.

| Family          | Weight  | Syllables     | Ink       | Upstream | Subset     |
| --------------- | ------- | ------------- | --------- | -------- | ---------- |
| Gowun Batang    | 700     | 11,172 (100%) | 21.3%     | 8.18MB   | 7.85MB     |
| Nanum Myeongjo  | 800     | 11,172 (100%) | 23.1%     | 3.18MB   | **1.93MB** |
| Noto Serif KR   | 700     | 11,172 (100%) | 24.0%     | 14.05MB  | 8.37MB     |
| Noto Serif KR   | 900     | 11,172 (100%) | 28.1%     | 14.04MB  | 8.36MB     |
| **Hahmlet**     | **700** | 2,788 (25%)   | **32.2%** | 1.48MB   | **1.38MB** |
| Hahmlet         | 900     | 2,788 (25%)   | 40.4%     | 1.48MB   | 1.38MB     |
| Diphylleia      | 400     | 2,781 (25%)   | 13.5%     | 1.94MB   | 1.35MB     |
| Grandiflora One | 400     | 2,787 (25%)   | 5.1%      | 2.29MB   | 0.93MB     |
| Song Myung      | 400     | 2,350 (21%)   | 20.4%     | 2.03MB   | 1.15MB     |

For reference, Pretendard w700 — the sans the app already ships — draws **31.7%**.

**No Korean serif has both full coverage and a real bold.** The three
full-coverage families top out at 21–28% ink; the only face that reaches a sans
bold's weight is Hahmlet, and it carries a quarter of the block. That is the
tradeoff `AppTextStyles.spine` resolves in favour of weight, because a spine is
11pt white type on a saturated fill and the coverage gap is empirically empty (0
misses across this library's 618 syllables, `app_ko.arb`'s 290, and 39 deliberately
awkward loanwords and transliterated names).

Three things worth carrying forward:

- **~2,780 is the normal tier for a modern Korean font**, not a Hahmlet defect —
  Diphylleia has 2,781 and Grandiflora One 2,787. Song Myung's 2,350 is KS X 1001
  exactly. Hahmlet's 2,788 is a verified strict superset of KS X 1001 plus 438.
- **Gowun Batang was never the cheap way to buy full coverage.** Nanum Myeongjo 800
  gives the same 11,172 for **1.93MB against 7.85MB**, and is slightly _bolder_. If
  coverage ever outranks weight, that is the move — not the 7.85MB file.
- **Hahmlet 900 is free in bytes** (same 1.38MB) if more weight is ever wanted, but
  at 11pt its counters visibly fill: `능`, `링`, `용` start closing up. 700 is the
  last cut that stays open at this size.

Regenerate with `scripts/zz_serif_survey.py` — or rather, rewrite it; it was a
throwaway and is not in the tree.

#### Regenerating the page's `SERIF_GAPS`

`index.html` marks the substituted syllables in red from a literal it carries,
because **a browser cannot detect this**: it substitutes a system face silently,
`document.fonts.check()` answers about the face rather than the glyph, and Hangul
is full-width so advance-width probing cannot separate the two either. All three
were tried. The data therefore comes from the font's real `cmap`; regenerate it
after any change to the subset or to `BOOKS`, from **this directory**:

```sh
cd docs/mockups/spine-type
/Library/Frameworks/Python.framework/Versions/3.10/bin/python3 -c "
import json
from fontTools.ttLib import TTFont
cov = set(TTFont('../../../assets/fonts/GowunBatang-Bold.ttf', lazy=True).getBestCmap())
titles = [t for t, *_ in __import__('importlib').import_module('render').BOOKS]
out = [[t, ''.join(sorted({c for c in t
                           if 0xAC00 <= ord(c) <= 0xD7A3 and ord(c) not in cov}))]
       for t in titles]
print(json.dumps([o for o in out if o[1]], ensure_ascii=False))
"
```

It reads `BOOKS` out of `render.py` rather than restating the corpus, so the page
and the PNG cannot disagree about which titles they are arguing over.

**`designhouseOTFLight.otf` is already in the bundle, has all 11,172 Hangul
syllables, and is referenced nowhere.** The only `DesignHouse` call site is the
auth wordmark at `titleUser`'s w600, which resolves to the 700 file — so 376KB
ships and never renders a glyph. It is a genuine free option for a distinctive
spine, with two honest caveats visible in row 4: its Hangul is 탈네모꼴
(deconstructed, non-square), which is striking but wide, and Light is thin enough
that `kSpineTintMinContrast`'s 4.6:1 — a floor tuned for normal-weight text — is
no longer the right floor. DesignHouse _Bold_ holds up better at 13pt and is
already the wordmark's face. Either way: use it or drop it from `pubspec.yaml`.

### Rejected

**Hangul set upright, one syllable per line** (row 5). The Korean shelf convention,
and the most authentic-looking row in the drawing for short titles. Killed by
capacity: an upright column holds ~7 syllables against a rotated line's ~8, so the
titles that most need help get less, punctuation sets badly upright, and a mixed
title like `그로스 해킹(Growth Hacking)` has to switch orientation mid-string. Worth
revisiting if titles are ever stored with a short form.

**Losing the separator to a shadow gap.** Out of scope here — but note the hairline
is 28% black while `_kOutline` is 11%, and the last spine in the row gets one with
nothing to its right, where it reads as a drawn border rather than an edge.
