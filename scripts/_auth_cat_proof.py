#!/usr/bin/env python3
"""Proof sheet: the mascot emerging from the bottom of the sign-in screen.

Throwaway review aid for one question -- does a NEUTRAL GREY cat read on the
app's near-white `pageBackground`, or does it dissolve into it?

Why it has to be rendered rather than reasoned about: the body measures 1.42:1
against `#F8F9FA` and the belly 1.14:1, which says "invisible". But the drawing
is not one flat grey -- the ears and tail are `#A4A4A6` (2.36:1), the eyes and
mouth `#54575B` (~9:1), the nose apricot, and `m03-reading` adds a mid-grey book.
So the failure mode is not "you cannot see it", it is "the features read and the
BODY dissolves", which is a different defect and only judgeable by looking.

    .venv/bin/python scripts/_auth_cat_proof.py

Writes build/auth_cat/. Geometry is copied from `auth_page.dart` -- see LAYOUT.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# iPhone 15 logical points, and its safe area.
W, H = 393, 852
SAFE_TOP, SAFE_BOTTOM = 59, 34
SCALE = 2

# --- Tokens, copied from lib/constants/app_theme.dart (light) -----------------
PAGE_BG = "#F8F9FA"
BRAND = "#09BC8A"       # BrandMark's plate
BRAND_FILL = "#067657"  # the dark twin, authored to carry white text
PRIMARY_TEXT = "#212529"
CANDLE_FLAME = "#F2A93F"

# --- Layout, copied from auth_page.dart --------------------------------------
# BrandMark(96) / 20 / hero 30pt (height 1.2 -> 36) / 48 / 44 / 12 / 44
MARK = 96
GAP_MARK_TITLE = 20
TITLE_LINE = 36
GAP_TITLE_BUTTONS = 48
BUTTON_H = 44
GAP_BUTTONS = 12
BUTTON_PAD_X = 32
BUTTON_RADIUS = 8
CORNER_RATIO = 185 / 824  # BrandMark._cornerRatio

CONTENT_H = (
    MARK + GAP_MARK_TITLE + TITLE_LINE + GAP_TITLE_BUTTONS
    + BUTTON_H + GAP_BUTTONS + BUTTON_H
)

ROOT = Path(__file__).resolve().parent.parent
CAT = ROOT / "docs/mockups/streak-widget/cats/m03-reading.png"
MARK_ASSET = ROOT / "assets/branding/app_icon_mark.png"
SERIF = ROOT / "assets/fonts/GowunBatang-Bold.ttf"   # AppFonts.serif
SANS = ROOT / "assets/fonts/Pretendard-SemiBold.otf"
OUT = ROOT / "build/auth_cat"


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(path), size * SCALE)
    except OSError:
        return ImageFont.load_default()


def s(v: float) -> int:
    return round(v * SCALE)


def base_screen() -> tuple[Image.Image, float]:
    """The current sign-in screen, drawn to scale. Returns it and the y where
    the buttons end -- everything below that is the room the cat has."""
    img = Image.new("RGB", (s(W), s(H)), PAGE_BG)
    d = ImageDraw.Draw(img)

    usable = H - SAFE_TOP - SAFE_BOTTOM
    top = SAFE_TOP + (usable - CONTENT_H) / 2

    # BrandMark: brand plate, Apple's corner radius, white mark full-bleed.
    plate = (s(W / 2 - MARK / 2), s(top), s(W / 2 + MARK / 2), s(top + MARK))
    d.rounded_rectangle(plate, radius=s(MARK * CORNER_RATIO), fill=BRAND)
    if MARK_ASSET.exists():
        mark = Image.open(MARK_ASSET).convert("RGBA").resize(
            (s(MARK), s(MARK)), Image.LANCZOS
        )
        img.paste(mark, (plate[0], plate[1]), mark)

    y = top + MARK + GAP_MARK_TITLE
    title = font(SERIF, 30)
    tw = d.textlength("Libstack", font=title)
    d.text((s(W / 2) - tw / 2, s(y)), "Libstack", font=title, fill=PRIMARY_TEXT)

    y += TITLE_LINE + GAP_TITLE_BUTTONS
    label = font(SANS, 19)  # 19/44, the ratio the in-flight work establishes
    for text, bg, fg, border in (
        ("Continue with Apple", "#000000", "#FFFFFF", None),
        ("Continue with Google", "#FFFFFF", "#000000", "#E9ECEF"),
    ):
        box = (s(BUTTON_PAD_X), s(y), s(W - BUTTON_PAD_X), s(y + BUTTON_H))
        d.rounded_rectangle(box, radius=s(BUTTON_RADIUS), fill=bg, outline=border)
        lw = d.textlength(text, font=label)
        d.text(
            (s(W / 2) - lw / 2 + s(10), s(y + (BUTTON_H - 19) / 2 - 2)),
            text, font=label, fill=fg,
        )
        y += BUTTON_H + GAP_BUTTONS

    return img, y - GAP_BUTTONS


def place_cat(img: Image.Image, height: float, crop_frac: float) -> None:
    """Seat the cat on the bottom edge, `crop_frac` of it past the screen."""
    cat = Image.open(CAT).convert("RGBA")
    w = round(height * cat.width / cat.height)
    cat = cat.resize((s(w), s(height)), Image.LANCZOS)
    # Bottom `crop_frac` falls off the screen, as the widget's cut-outs do.
    y = s(H) - round(cat.height * (1 - crop_frac))
    img.paste(cat, (s(W / 2 - w / 2), y), cat)


def glow(img: Image.Image, height: float, colour: str, alpha: int) -> None:
    """A soft radial wash centred where the cat will sit."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = s(W / 2), s(H)
    r = s(height * 0.95)
    steps = 48
    rgb = tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5))
    for i in range(steps, 0, -1):
        rr = r * i / steps
        a = int(alpha * (1 - i / steps) ** 1.6)
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(*rgb, a))
    img.paste(Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB"), (0, 0))


def band(img: Image.Image, height: float, colour: str) -> None:
    d = ImageDraw.Draw(img)
    d.rectangle((0, s(H - height), s(W), s(H)), fill=colour)


def variants() -> dict[str, Image.Image]:
    out: dict[str, Image.Image] = {}

    # 0 -- the control: today's screen, no cat.
    out["0-control"], end = base_screen()

    # A -- the literal proposal: cat on the page, nothing behind it.
    img, _ = base_screen()
    place_cat(img, 210, 0.12)
    out["A-plain-210"] = img

    # B -- bigger, so more of the dark features are in play.
    img, _ = base_screen()
    place_cat(img, 265, 0.16)
    out["B-plain-265"] = img

    # C -- a candle-glow wash behind it, the app's own warm light.
    img, _ = base_screen()
    glow(img, 210, CANDLE_FLAME, 70)
    place_cat(img, 210, 0.12)
    out["C-glow-flame"] = img

    # D -- a brandFill band: the widget's answer, 3.74:1 on the body.
    img, _ = base_screen()
    band(img, 168, BRAND_FILL)
    place_cat(img, 210, 0.12)
    out["D-band-brandfill"] = img

    # E -- brandFill glow rather than a hard band edge.
    img, _ = base_screen()
    glow(img, 230, BRAND_FILL, 90)
    place_cat(img, 210, 0.12)
    out["E-glow-brandfill"] = img

    return out


def contact(sheet: dict[str, Image.Image]) -> Image.Image:
    pad, label_h = 24, 34
    cw, ch = s(W), s(H)
    cols = len(sheet)
    out = Image.new(
        "RGB", (cols * cw + (cols + 1) * pad, ch + label_h + 2 * pad), "#2C2C2E"
    )
    d = ImageDraw.Draw(out)
    f = font(SANS, 11)
    for i, (name, img) in enumerate(sheet.items()):
        x = pad + i * (cw + pad)
        out.paste(img, (x, pad + label_h))
        d.text((x, pad + 8), name, font=f, fill="#F1F3F5")
    return out


def pose_row() -> Image.Image:
    """All eight poses in situ, on the plain page, at the shipping placement.

    In situ rather than as bare cut-outs, because the thing being chosen is how a
    pose reads *at the bottom of this screen, cropped, under two buttons* -- and a
    pose sheet cannot show that. `m05-puddle` is the case in point: it is much wider
    than it is tall, so at a common HEIGHT it is enormous, which is the same trap the
    widget hit ("the cat is bounded by height, never width").

    Also answers whether a light ground is a property of the POSE: `m03-reading`
    holds a mid-grey book over the belly -- the weakest region at 1.14:1 -- where a
    bookless pose leaves it bare.
    """
    poses = [
        "m01-flex", "m03-reading", "m13-blush", "m15-smug",
        "m07-drowsy", "m06-snooze", "m05-puddle", "m12-panic",
    ]
    cells = []
    for name in poses:
        path = ROOT / f"docs/mockups/streak-widget/cats/{name}.png"
        img, _ = base_screen()
        cat = Image.open(path).convert("RGBA")
        h = 265
        w = round(h * cat.width / cat.height)
        cat = cat.resize((s(w), s(h)), Image.LANCZOS)
        y = s(H) - round(cat.height * (1 - 0.16))
        img.paste(cat, (s(W / 2 - w / 2), y), cat)
        ratio = cat.width / cat.height
        cells.append((f"{name}   {ratio:.2f}w/h",
                      img.crop((0, s(H * 0.60), s(W), s(H)))))

    pad, label_h, per_row = 20, 30, 4
    cw, ch = cells[0][1].size
    rows = (len(cells) + per_row - 1) // per_row
    out = Image.new(
        "RGB",
        (per_row * cw + (per_row + 1) * pad,
         rows * (ch + label_h + pad) + pad),
        "#2C2C2E",
    )
    d = ImageDraw.Draw(out)
    f = font(SANS, 11)
    for i, (name, cell) in enumerate(cells):
        col, row = i % per_row, i // per_row
        x = pad + col * (cw + pad)
        y = pad + row * (ch + label_h + pad)
        out.paste(cell, (x, y + label_h))
        d.text((x, y + 6), name, font=f, fill="#F1F3F5")
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = variants()
    for name, img in sheet.items():
        img.save(OUT / f"{name}.png")
    contact(sheet).save(OUT / "_sheet.png")
    pose_row().save(OUT / "_poses.png")

    cat = Image.open(CAT)
    print(f"cat source: {cat.size[0]}x{cat.size[1]}")
    print(f"content block: {CONTENT_H}pt; room below the buttons: "
          f"{H - SAFE_BOTTOM - (SAFE_TOP + (H - SAFE_TOP - SAFE_BOTTOM - CONTENT_H) / 2 + CONTENT_H):.0f}pt")
    for name in sheet:
        print(f"  wrote {name}.png")
    print(f"\n{OUT}/_sheet.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
