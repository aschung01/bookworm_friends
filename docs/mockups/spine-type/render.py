"""Draws the read pile's spine typography five ways, at the real geometry.

Run with the Python that has fontTools/PIL -- the same one `build_fonts.py` wants:

    /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 \
        docs/mockups/spine-type/render.py

Why a drawing rather than a description
---------------------------------------
Every number here is taken from the shipped code, not invented:

  * heights 110-124pt and widths 28-39pt are `BookMetrics.from` at
    `ReadPile.spineBase` (~117) under `BookJitter`'s factor ranges, which is what
    `docs/superpowers/specs/2026-08-22-read-pile-spines-design.md` records.
  * the 5pt arched head is `bookSpinePath`.
  * the 28%-black 1pt right-edge separator is `BookVertical`'s `separator`.
  * `now` is `AppTextStyles.label` exactly: Pretendard SemiBold 13pt, tracking 0,
    `EdgeInsets.only(top: 15, bottom: 15)`, `Center`, one line, ellipsis.

So the first row should match a screenshot of the app, and the differences in the
rows below it are only the ones named in the row label.

The inks are `spineToneFor`'s rule -- whichever of #FFFFFF and #212529 scores
better against the fill -- so a pale book gets dark type here as it does on device.
"""

from pathlib import Path

# Both of these resolve only under the interpreter this script is meant to run on
# -- the Framework Python 3.10 that `scripts/build_fonts.py` also names, which is
# where `fontTools` and `Pillow` live. The editor resolves imports against the
# project's own `.venv`, so it flags them; the alternative to silencing that is
# adding two build-time dependencies to a runtime venv for the sake of a drawing.
from PIL import Image, ImageChops, ImageDraw, ImageFont  # type: ignore[import]

ROOT = Path(__file__).resolve().parents[3]
FONTS = ROOT / "assets" / "fonts"
OUT = Path(__file__).resolve().parent

SCALE = 3  # logical pt -> px, so the type is judgeable rather than aliased
#
# 3 rather than 5. At 5 these two PNGs came to 2.6MB, which is a lot of repo for a
# static record of what `index.html` shows live and interactively; at 3 a 13pt
# title still renders 39px tall, which is more than enough to judge a letterform.

SHEET = (43, 45, 47)  # the dark sheet the screenshot was taken on
INK_LIGHT = (255, 255, 255)
INK_DARK = (33, 37, 41)  # kSpineInkDark

# (title, thickness pt, height pt, cover tone)
#
# **Real titles off the shelves in the screenshot**, not invented short ones.
# That matters: a corpus of six-syllable titles makes any measure rule look fine,
# which is the mistake `test/spine_tone_test.dart` documents at the top of the
# file. These are the lengths the pile actually has to set, plus one
# parenthetical original title -- a very common shape in a Korean catalogue and
# the case the strip rule exists for.
BOOKS = [
    ("The Hard Thing About Hard Things", 31, 121, "#16110E"),
    ("인공지능, 머신러닝, 딥러닝 입문", 34, 118, "#F4F6F7"),
    ("이더리움과 솔리디티 입문", 30, 115, "#FAFAFA"),
    ("The Zero Marginal Cost Society", 36, 124, "#0A0A0C"),
    ("권도균의 스타트업 경영 수업", 29, 113, "#29A8D8"),
    ("Crossing the Chasm", 33, 120, "#F2F5F8"),
    ("무조건 팔리는 카피", 28, 110, "#123C8C"),
    ("세계를 바꾼 테크놀로지 10", 38, 123, "#B0299E"),
    ("그로스 해킹(Growth Hacking)", 32, 117, "#F7F5F0"),
    ("Shoe Dog", 31, 116, "#111214"),
]

PRETENDARD_SEMIBOLD = FONTS / "Pretendard-SemiBold.otf"
PRETENDARD_REGULAR = FONTS / "Pretendard-Regular.otf"
DESIGNHOUSE_LIGHT = FONTS / "designhouseOTFLight.otf"

# Serif candidates, built by `build_serifs.py` into `./fonts/`.
#
# **Not app assets**, and not in `assets/fonts/`: subset to exactly the text this
# drawing sets, so their size is no evidence about what shipping a serif costs.
# They exist because the app's own serif cannot set a book title -- which is the
# finding, not a thing to route around.
MOCKUP_FONTS = OUT / "fonts"
GOWUN_FULL = MOCKUP_FONTS / "GowunBatangFull-400.ttf"
GOWUN_FULL_BOLD = MOCKUP_FONTS / "GowunBatangFull-700.ttf"
NOTO_SERIF = MOCKUP_FONTS / "NotoSerifKR-400.ttf"
NANUM_MYEONGJO = MOCKUP_FONTS / "NanumMyeongjo-400.ttf"
SONG_MYUNG = MOCKUP_FONTS / "SongMyung-400.ttf"
HAHMLET = MOCKUP_FONTS / "Hahmlet-400.ttf"
HAHMLET_MEDIUM = MOCKUP_FONTS / "Hahmlet-500.ttf"

UI_FONT = FONTS / "Pretendard-SemiBold.otf"


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i : i + 2], 16) for i in (0, 2, 4))


def luminance(rgb):
    def ch(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def ink_for(fill):
    """`spineToneFor`'s choice: the ink that reads better on the fill."""
    return (
        INK_LIGHT
        if contrast(fill, INK_LIGHT) >= contrast(fill, INK_DARK)
        else INK_DARK
    )


def font(path, pt):
    return ImageFont.truetype(str(path), int(round(pt * SCALE)))


def advance(text, f, tracking=0.0):
    if not tracking:
        return f.getlength(text)
    return sum(f.getlength(c) for c in text) + tracking * SCALE * max(
        0, len(text) - 1
    )


def draw_run(d, xy, text, f, fill, tracking=0.0):
    """Tracking has to be applied per glyph; PIL has no letterSpacing.

    At tracking 0 the string is drawn in one call so Latin keeps its kerning --
    the tracked path loses it, which is an artefact of this renderer and not of
    the proposal.
    """
    if not tracking:
        d.text(xy, text, font=f, fill=fill)
        return
    x, y = xy
    for c in text:
        d.text((x, y), c, font=f, fill=fill)
        x += f.getlength(c) + tracking * SCALE


def ellipsize(text, f, limit, tracking=0.0):
    if advance(text, f, tracking) <= limit:
        return text
    for n in range(len(text) - 1, 0, -1):
        candidate = text[:n] + "…"
        if advance(candidate, f, tracking) <= limit:
            return candidate
    return "…"


# Where a Korean catalogue title stops being the title. `(원제)`, `: 부제`,
# ` - 부제`, `[양장]` -- cutting here is what turns
# "그로스 해킹(Growth Hacking)" into a title that fits whole.
SUBTITLE_MARKS = ("(", ":", "[", " - ", " ~ ", "~", "―", "—")


def strip_subtitle(text):
    cut = len(text)
    for mark in SUBTITLE_MARKS:
        i = text.find(mark)
        if 0 < i < cut:
            cut = i
    return text[:cut].strip() or text


def wrap_two(text, f, limit, tracking=0.0):
    """The most balanced two-line break, or None if one line does or none fits.

    Breaks after a comma as well as on a space, because a Korean catalogue title
    is often a comma list -- `인공지능, 머신러닝, 딥러닝 입문` has no useful
    space break but three good comma ones.
    """
    if advance(text, f, tracking) <= limit:
        return [text]
    points = []
    for i, c in enumerate(text):
        if c == " ":
            points.append((i, i + 1))
        elif c == "," and i + 1 < len(text):
            points.append((i + 1, i + 2 if text[i + 1] == " " else i + 1))
    best, best_cost = None, None
    for end, start in points:
        a, b = text[:end].strip(), text[start:].strip()
        if not a or not b:
            continue
        wa, wb = advance(a, f, tracking), advance(b, f, tracking)
        if wa > limit or wb > limit:
            continue
        cost = abs(wa - wb)
        if best_cost is None or cost < best_cost:
            best, best_cost = [a, b], cost
    return best


def apply_tail_fade(layer, fade_pt):
    """Ramp the layer's alpha to nothing over its last [fade_pt].

    Applied before the 90deg turn, so it lands at the spine's tail. The argument
    for it over `TextOverflow.ellipsis`: rotated, `…` is three dots stacked down
    the spine, and it *costs* about a syllable of the measure it is apologising
    for. A fade costs none and reads as the title running under the shelf.
    """
    fade = max(1, int(fade_pt * SCALE))
    w, h = layer.size
    ramp = Image.new("L", (w, h), 255)
    dr = ImageDraw.Draw(ramp)
    for i in range(min(fade, w)):
        x = w - fade + i
        dr.line([(x, 0), (x, h)], fill=int(255 * (1 - i / fade)))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), ramp))
    return layer


def is_hangul(c):
    return "\uac00" <= c <= "\ud7a3"


def mostly_hangul(text):
    letters = [c for c in text if not c.isspace()]
    if not letters:
        return False
    return sum(1 for c in letters if is_hangul(c)) / len(letters) > 0.5


def spine_mask(w, h, arch=5):
    """`bookSpinePath`: a rectangle with a 5pt arched head, bezier sampled."""
    a = arch * SCALE
    pts: list[tuple[float, float]] = [(0.0, float(a))]
    for i in range(1, 33):
        t = i / 32
        # quadratic bezier (0,a) -> control (w/2, 0) -> (w, a)
        x = (1 - t) ** 2 * 0 + 2 * (1 - t) * t * (w / 2) + t**2 * w
        y = (1 - t) ** 2 * a + 2 * (1 - t) * t * 0 + t**2 * a
        pts.append((float(x), float(y)))
    pts += [(float(w), float(h)), (0.0, float(h))]
    mask = Image.new("L", (int(w) + 1, int(h) + 1), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask


def rotated_title(box_w, box_h, render):
    """Render into a horizontal box, then turn it 90deg clockwise.

    `RotatedBox(quarterTurns: 1)`, which is what the app uses: the title reads
    from the head down, head tilted right. Kept as the plain case; the fade path
    in [make_spine] inlines this so it can touch the alpha before the turn.
    """
    layer = Image.new("RGBA", (int(box_w), int(box_h)), (0, 0, 0, 0))
    render(ImageDraw.Draw(layer))
    return layer.transpose(Image.Transpose.ROTATE_270)


def make_spine(title, thickness, height, tone, variant):
    w, h = int(thickness * SCALE), int(height * SCALE)
    fill = hex_rgb(tone)
    ink = ink_for(fill)

    spine = Image.new("RGBA", (w, h), fill + (255,))
    d = ImageDraw.Draw(spine)

    pad_head = variant["pad_head"] * SCALE
    pad_tail = variant["pad_tail"] * SCALE
    measure = h - pad_head - pad_tail

    text = strip_subtitle(title) if variant["strip"] else title

    size = variant["size"]
    if variant.get("size_by_thickness"):
        lo, hi = variant["size_by_thickness"]
        t = max(0.0, min(1.0, (thickness - 28) / (39 - 28)))
        size = lo + t * (hi - lo)

    if variant.get("upright") and mostly_hangul(text):
        # Hangul set upright, one syllable per line, reading down -- how a Korean
        # spine is actually set. Latin on the same shelf still rotates.
        f = font(variant["font"], size)
        step = size * SCALE * 1.04
        y = pad_head
        limit = pad_head + measure
        for c in text:
            # A space is a gap in the column rather than a dropped character --
            # without it `권도균의 스타트업 경영 수업` sets as one unbroken run.
            if c.isspace():
                y += step * 0.42
                continue
            if y + step > limit:
                break
            gw = f.getlength(c)
            d.text(((w - gw) / 2, y), c, font=f, fill=ink)
            y += step
    else:
        f = font(variant["font"], size)
        tracking = variant["tracking"]
        ascent, descent = f.getmetrics()
        line_h = (ascent + descent) * 1.04

        lines = None
        if variant["max_lines"] == 2 and thickness >= variant["two_line_min_pt"]:
            lines = wrap_two(text, f, measure, tracking)
        faded = False
        if lines is None:
            if variant.get("fade"):
                # No ellipsis: set the whole string, let the layer clip it, and
                # ramp the tail away.
                lines = [text]
                faded = advance(text, f, tracking) > measure
            else:
                lines = [ellipsize(text, f, measure, tracking)]

        box_w, box_h = measure, line_h * len(lines)

        def render(dd):
            for i, line in enumerate(lines):
                run = advance(line, f, tracking)
                x = 0 if variant["align"] == "head" else (box_w - run) / 2
                draw_run(dd, (x, i * line_h), line, f, ink, tracking)

        layer = Image.new("RGBA", (int(box_w), int(box_h)), (0, 0, 0, 0))
        render(ImageDraw.Draw(layer))
        if faded:
            apply_tail_fade(layer, 15)
        layer = layer.transpose(Image.Transpose.ROTATE_270)
        spine.alpha_composite(layer, (int((w - layer.width) / 2), int(pad_head)))

    # The 1pt 28%-black hairline on the right edge, in every row, so the type is
    # the only thing changing.
    ImageDraw.Draw(spine, "RGBA").rectangle(
        [w - SCALE, 0, w, h], fill=(0, 0, 0, 71)
    )

    spine.putalpha(spine_mask(w, h).crop((0, 0, w, h)))
    return spine


VARIANTS = [
    {
        "id": "now",
        "label": "now  ·  AppTextStyles.label: Pretendard SemiBold 13pt, tracking 0, pad 15/15, centred, 1 line",
        "font": PRETENDARD_SEMIBOLD,
        "size": 13,
        "tracking": 0.0,
        "pad_head": 15,
        "pad_tail": 15,
        "align": "centre",
        "max_lines": 1,
        "two_line_min_pt": 999,
        "strip": False,
    },
    {
        "id": "measure",
        "label": "1. measure only  ·  same face, pad 8/9, head-aligned, subtitle stripped at ( : [ —",
        "font": PRETENDARD_SEMIBOLD,
        "size": 13,
        "tracking": 0.0,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 1,
        "two_line_min_pt": 999,
        "strip": True,
    },
    {
        "id": "book",
        "label": "2. + book voice  ·  Pretendard Regular 14pt, tracking +0.2, 2 lines when the spine is >=33pt thick",
        "font": PRETENDARD_REGULAR,
        "size": 14,
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
    },
    {
        "id": "thickness",
        "label": "3. + size follows thickness  ·  12.5pt at 28pt thick -> 15pt at 39pt, so page count reads as type size",
        "font": PRETENDARD_REGULAR,
        "size": 14,
        "size_by_thickness": (12.5, 15.0),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
    },
    {
        "id": "designhouse",
        "label": "4. DesignHouse Light 14.5pt  ·  already in the bundle, full Hangul, currently unused — 0 added bytes",
        "font": DESIGNHOUSE_LIGHT,
        "size": 14.5,
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
    },
    {
        "id": "upright",
        "label": "5. Hangul set upright, one syllable per line  ·  the Korean shelf convention; Latin still rotates",
        "font": PRETENDARD_REGULAR,
        "size": 14,
        "upright": True,
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
    },
    {
        "id": "fade",
        "label": "6. row 3 again, but the tail fades instead of ellipsising  ·  '...' rotated is three stacked dots that cost a syllable",
        "font": PRETENDARD_REGULAR,
        "size": 14,
        "size_by_thickness": (12.5, 15.0),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
        "fade": True,
    },
    # The serifs, all at row 3's layout so the face is the only thing changing.
    # `size` carries an optical-size nudge: these faces do not share a Hangul
    # body ratio, and setting them all at 14pt would compare the numbers rather
    # than the type.
    {
        "id": "gowun",
        "label": "7. Gowun Batang, whole  ·  the app's own serif as it would look if it were not subset to app_ko.arb",
        "font": GOWUN_FULL,
        "size": 14,
        "size_by_thickness": (13.6, 16.4),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
        "fade": True,
    },
    {
        "id": "noto",
        "label": "8. Noto Serif KR  ·  the workhorse; the most legible of the serifs at this size",
        "font": NOTO_SERIF,
        "size": 14,
        "size_by_thickness": (12.5, 15.0),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
        "fade": True,
    },
    {
        "id": "nanum",
        "label": "9. Nanum Myeongjo  ·  narrower than Noto, which buys measure — the one place a serif beats Pretendard here",
        "font": NANUM_MYEONGJO,
        "size": 14,
        "size_by_thickness": (13.1, 15.8),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
        "fade": True,
    },
    {
        "id": "song",
        "label": "10. Song Myung  ·  a display myeongjo; the most book-jacket of the set and the likeliest to fall apart small",
        "font": SONG_MYUNG,
        "size": 14,
        "size_by_thickness": (13.4, 16.1),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
        "fade": True,
    },
    {
        "id": "hahmlet",
        "label": "11. Hahmlet  ·  heavier stems and squarer Hangul, so it holds a small size better than the myeongjos",
        "font": HAHMLET,
        "size": 14,
        "size_by_thickness": (12.3, 14.7),
        "tracking": 0.2,
        "pad_head": 8,
        "pad_tail": 9,
        "align": "head",
        "max_lines": 2,
        "two_line_min_pt": 33,
        "strip": True,
        "fade": True,
    },
]


def render_row(variant, gap=4, side=25):
    spines = [make_spine(t, w, h, c, variant) for (t, w, h, c) in BOOKS]
    row_w = int(side * 2 * SCALE + sum(s.width for s in spines) + gap * SCALE * (len(spines) - 1))
    row_h = int(124 * SCALE)
    shelf = 8 * SCALE
    row = Image.new("RGBA", (row_w, row_h + shelf), (0, 0, 0, 0))
    x = int(side * SCALE)
    for s in spines:
        row.alpha_composite(s, (x, row_h - s.height))  # standing on the shelf
        x += s.width + int(gap * SCALE)
    ImageDraw.Draw(row).rectangle(
        [0, row_h + SCALE, row_w, row_h + int(3.5 * SCALE)], fill=(120, 126, 130, 255)
    )
    return row


GOWUN_BATANG = FONTS / "GowunBatang-Bold.ttf"

# The faces to show side by side, largest first: what a spine is set in today,
# what it could be set in for free, and the one that looks like the right answer
# and is not available.
SPECIMENS = [
    ("Pretendard SemiBold", PRETENDARD_SEMIBOLD, "today, via AppTextStyles.label — also the tab bar's face and weight"),
    ("Pretendard Regular", PRETENDARD_REGULAR, "shipped; the same family stepped down to a reading weight"),
    ("DesignHouse Light", DESIGNHOUSE_LIGHT, "shipped, 376KB, full Hangul, referenced nowhere — free to use"),
    ("DesignHouse Bold", FONTS / "designhouseOTFBold.otf", "shipped; the auth wordmark's face"),
    ("GowunBatang Bold", GOWUN_BATANG, "the shipped serif — subset to 262 of 11,172 syllables, so a title tofus"),
    ("Gowun Batang, whole", GOWUN_FULL, "mockup-only — the same face uncut, i.e. what subsetting is costing"),
    ("Gowun Batang Bold, whole", GOWUN_FULL_BOLD, "mockup-only — stem 250/1000, lighter than most families' regular"),
    ("Noto Serif KR", NOTO_SERIF, "mockup-only — the workhorse Korean serif"),
    ("Nanum Myeongjo", NANUM_MYEONGJO, "mockup-only — a classic myeongjo, narrower than Noto"),
    ("Song Myung", SONG_MYUNG, "mockup-only — a display myeongjo with high stroke contrast"),
    ("Hahmlet", HAHMLET, "mockup-only — a modern serif with noticeably heavier stems"),
    ("Hahmlet Medium", HAHMLET_MEDIUM, "mockup-only — the only cut here between regular and semibold"),
    ("Hahmlet SemiBold", MOCKUP_FONTS / "Hahmlet-600.ttf", "mockup-only — the heaviest serif here; 400/500/600 bracket the answer"),
]


def serif_coverage_report():
    """Why the obvious answer -- 'set a book spine in the serif' -- is unavailable.

    `AppFonts.serif` is cut to the Hangul in `app_ko.arb`, and a book title is
    catalogue text. `AppTextStyles.title` carries `fontFamilyFallback: [sans]` so
    the miss is a silent family swap rather than a box -- which for a *title* is
    worse, because it happens mid-word. `titleUser` exists for exactly this
    reason and its doc already says so.
    """
    from fontTools.ttLib import TTFont  # type: ignore[import]  # ty: ignore[unresolved-import]

    covered = set(TTFont(str(GOWUN_BATANG), lazy=True).getBestCmap())
    print("\nGowunBatang coverage of the titles above:")
    total_missing = 0
    for title, *_ in BOOKS:
        hangul = [c for c in title if is_hangul(c)]
        if not hangul:
            continue
        missing = [c for c in hangul if ord(c) not in covered]
        total_missing += len(missing)
        print(
            f"  {title:<26} {len(hangul) - len(missing):>2}/{len(hangul)} syllables"
            f"   missing: {''.join(missing) or '-'}"
        )
    print(
        f"  -> {total_missing} syllables would fall back to Pretendard mid-title."
    )


def render_specimens():
    """The faces at a size where the letterforms are arguable, plus at 13pt."""
    latin = "Crossing the Chasm"
    hangul = "인공지능 딥러닝 입문"
    big, small = 30, 13

    name_font = ImageFont.truetype(str(UI_FONT), int(12 * SCALE))
    note_font = ImageFont.truetype(str(PRETENDARD_REGULAR), int(10 * SCALE))

    row_h = int(62 * SCALE)
    width = int(770 * SCALE)
    sheet = Image.new("RGB", (width, row_h * len(SPECIMENS) + int(14 * SCALE)), SHEET)
    d = ImageDraw.Draw(sheet)

    y = int(9 * SCALE)
    for name, path, note in SPECIMENS:
        d.text((int(22 * SCALE), y), name, font=name_font, fill=(150, 214, 186))
        d.text(
            (int(180 * SCALE), y + int(1 * SCALE)),
            note,
            font=note_font,
            fill=(138, 144, 148),
        )
        fb, fs = font(path, big), font(path, small)
        d.text((int(22 * SCALE), y + int(18 * SCALE)), latin, font=fb, fill=(238, 241, 243))
        d.text((int(330 * SCALE), y + int(18 * SCALE)), hangul, font=fb, fill=(238, 241, 243))
        # The same strings at the size a spine actually sets them, because a face
        # that reads well at 30pt can close up entirely at 13.
        d.text((int(620 * SCALE), y + int(20 * SCALE)), latin, font=fs, fill=(238, 241, 243))
        d.text((int(620 * SCALE), y + int(36 * SCALE)), hangul, font=fs, fill=(238, 241, 243))
        y += row_h

    path = OUT / "spine-faces.png"
    sheet.save(path)
    print(f"wrote {path.relative_to(ROOT)}  ({sheet.width}x{sheet.height})")


def main():
    label_font = ImageFont.truetype(str(UI_FONT), int(11.5 * SCALE))
    lead = int(30 * SCALE)
    rows = [(v, render_row(v)) for v in VARIANTS]

    width = max(r.width for _, r in rows)
    height = sum(r.height + lead for _, r in rows) + int(18 * SCALE)
    sheet = Image.new("RGB", (width, height), SHEET)
    d = ImageDraw.Draw(sheet)

    y = int(9 * SCALE)
    for variant, row in rows:
        d.text(
            (int(25 * SCALE), y),
            variant["label"],
            font=label_font,
            fill=(150, 214, 186),
        )
        y += lead
        sheet.paste(row, (0, y), row)
        y += row.height

    path = OUT / "spine-type.png"
    sheet.save(path)
    print(f"wrote {path.relative_to(ROOT)}  ({sheet.width}x{sheet.height})")

    render_specimens()

    # The numbers the prose leans on, printed rather than asserted in text.
    print("\nmeasure available to the title, in pt of spine length:")
    for name, (head, tail) in (("now", (15, 15)), ("proposed", (8, 9))):
        print(f"  {name:>9}: {110 - head - tail} - {124 - head - tail}pt")
    f13 = font(PRETENDARD_SEMIBOLD, 13)
    f14 = font(PRETENDARD_REGULAR, 14)
    print("\nhow much of each title survives:")
    for title, w, h, _ in BOOKS:
        now = ellipsize(title, f13, (h - 30) * SCALE)
        prop = strip_subtitle(title)
        lines = wrap_two(prop, f14, (h - 17) * SCALE, 0.2) if w >= 33 else None
        if lines is None:
            lines = [ellipsize(prop, f14, (h - 17) * SCALE, 0.2)]
        print(f"  {title!r:<34} now {now!r:<22} -> {' / '.join(lines)!r}")

    serif_coverage_report()


if __name__ == "__main__":
    main()
