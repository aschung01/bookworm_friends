#!/usr/bin/env python3
"""Draw the widget as it now ships -- every state, both locales, on one page.

    python3 scripts/render_final_widget.py

Output: `docs/mockups/streak-widget/final.html`, openable straight from disk.

Why this exists when the directory already has three sheets
-----------------------------------------------------------
`index.html` is the comparison (four voices, ten grounds, three type axes),
`_widget_grid.html` is the submission form, and `_chosen.html` is the ladder as
picked. All three are *exploration*: they read their tiles out of index.html's own
script, which knows nothing about the app. So none of them can answer the only
question left -- "what does the thing we built actually look like" -- and after
the wiring landed all three became records of a decision rather than views of a
product.

**Everything here is read out of the shipped sources, and nothing is retyped.**

    the copy            lib/l10n/app_en.arb, app_ko.arb    (streakWidgetLine*)
    the ground ramp     ios/StreakWidget/StreakWidget.swift (StreakGroundRamp.anchors)
    the recorded ground ios/StreakWidget/StreakWidget.swift (StreakGround.recorded)
    the poses           ios/StreakWidget/StreakWidget.swift (StreakCatPose)
    the tier hours      ios/StreakWidget/StreakSnapshot.swift (StreakTier.forHour)
    the cut-outs        ios/StreakWidget/Assets.xcassets/<pose>.imageset/<pose>@3x.png
    the flame           rive/streak_flame/icon.py --svg

That is the point: a tile drawn here is wrong exactly when the app is wrong, and
a decision that drifts out of the code drifts off this page with it. The one thing
it cannot check is what SwiftUI does with those numbers -- see "What this page is
not" in the output.

The ground recipe is a port of `groundVars()` in index.html, which the Swift is
also a port of. Two ports of one recipe is a drift risk, so `--check` asserts the
two agree on all six hours plus recorded, and it is worth running after either
side moves.
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/mockups/streak-widget/final.html"
WIDGET_SWIFT = ROOT / "ios/StreakWidget/StreakWidget.swift"
SNAPSHOT_SWIFT = ROOT / "ios/StreakWidget/StreakSnapshot.swift"
ASSETS = ROOT / "ios/StreakWidget/Assets.xcassets"

# The order a day runs through, then the two states that replace the whole day.
TIERS = ["dawn", "morning", "afternoon", "evening", "late", "final"]
APART = ["none", "recorded"]

# ARB key per state. `recorded` has none, in any voice: the lit flame says it, and a
# sentence under it would be the tile explaining its own drawing.
ARB_KEY = {t: f"streakWidgetLine{t.capitalize()}" for t in TIERS}
ARB_KEY["none"] = "streakWidgetLineNone"

INK_LIGHT = "#FFF7EA"
INK_DARK = "#212529"

# The two jacket colours the medium tiles are drawn with.
#
# **`PALE_COVER` is measured off a device, and it is here because the page could not show the
# defect it caused.** `cover_color` is sampled from the real jacket, so a book whose cover is
# white paper comes back near-white -- this value is what the app wrote for
# "월급쟁이 부자로 은톴하라" -- and a near-white rectangle on the recorded tile's cream ground was
# invisible. The page drew only `DARK_COVER`, which is the flattering case, so it showed a
# working jacket where the device showed what looked like a cover that had failed to load.
# Every medium section now draws both.
DARK_COVER = "#8A5A2B"
PALE_COVER = "#FDFDFB"


# ---------------------------------------------------------------- reading the sources


def read(path: pathlib.Path) -> str:
    if not path.exists():
        sys.exit(f"missing {path.relative_to(ROOT)} -- nothing to draw from")
    return path.read_text()


def ramp_anchors(swift: str) -> list[tuple[float, str, str]]:
    """`StreakGroundRamp.anchors`, as (hour, top, bottom)."""
    block = re.search(
        r"static let anchors:.*?= \[(.*?)\n  \]", swift, re.S
    )
    if not block:
        sys.exit("could not find StreakGroundRamp.anchors -- has the ramp moved?")
    found = re.findall(
        r"\(\s*(\d+),\s*StreakRGB\(0x([0-9A-Fa-f]{6})\),\s*StreakRGB\(0x([0-9A-Fa-f]{6})\)\s*\)",
        block.group(1),
    )
    return [(float(h), f"#{t.upper()}", f"#{b.upper()}") for h, t, b in found]


def recorded_ground(swift: str) -> tuple[str, str]:
    match = re.search(
        r"static let recorded = StreakGround\(\s*top: StreakRGB\(0x([0-9A-Fa-f]{6})\),"
        r"\s*bottom: StreakRGB\(0x([0-9A-Fa-f]{6})\)",
        swift,
        re.S,
    )
    if not match:
        sys.exit("could not find StreakGround.recorded")
    return f"#{match.group(1).upper()}", f"#{match.group(2).upper()}"


def poses(swift: str) -> dict[str, str]:
    out = {}
    for tier, pose in re.findall(
        r"case \.`?(\w+)`?: return \"([\w-]+)\"", swift
    ):
        if tier in TIERS:
            out[tier] = pose
    for name, key in (("recorded", "recorded"), ("noRun", "none")):
        match = re.search(rf"static let {name} = \"([\w-]+)\"", swift)
        if match:
            out[key] = match.group(1)
    missing = [s for s in TIERS + APART if s not in out]
    if missing:
        sys.exit(f"no pose found for {', '.join(missing)}")
    return out


def tier_hours(snapshot: str) -> dict[str, int]:
    """`StreakTier.forHour`'s boundaries, read off the function rather than assumed."""
    body = re.search(r"static func forHour.*?\n  \}", snapshot, re.S)
    if not body:
        sys.exit("could not find StreakTier.forHour")
    found = re.findall(r"if hour >= (\d+) \{ return \.`?(\w+)`? \}", body.group(0))
    hours = {tier: int(h) for h, tier in found}
    # The `return .dawn` fall-through carries no number, so dawn's boundary is the
    # rollover -- 0 in the shipped constant. Shown as 05:00 nowhere: the tier below the
    # first `if` is whatever is left, and pretending otherwise would invent a boundary.
    hours.setdefault("dawn", 0)
    return hours


def copy_lines() -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for locale in ("en", "ko"):
        arb = json.loads(read(ROOT / f"lib/l10n/app_{locale}.arb"))
        out[locale] = {}
        for state, key in ARB_KEY.items():
            if key not in arb:
                sys.exit(f"{key} is missing from app_{locale}.arb")
            out[locale][state] = arb[key]
    return out


def bookmark_path() -> str:
    """The ribbon's `d`, straight out of the asset the app draws.

    Read rather than retyped for the same reason everything else here is: this is the third copy
    of one shape -- the SVG, `BookmarkRibbon` in Swift, and this page -- and the Swift one is
    already held to the asset by `test/streak_widget_palette_test.dart`.
    """
    svg = read(ROOT / "assets/icons/bookmarkIcon.svg")
    paths = re.findall(r'<path d="([^"]+)"', svg)
    if len(paths) != 1:
        sys.exit(f"expected one path in bookmarkIcon.svg, got {len(paths)}")
    return paths[0]


def bookmark_svg(
    path_d: str, cover_w: float, cover_h: float, progress: float | None
) -> str:
    """The ribbon, placed on a cover -- a port of `readingBookmarkInsetFor`.

    The same arithmetic as `ReadingBookmarkTrack.trailingInset` in the Swift, and a third copy of
    it. Unlike the other two this one is not guarded by a test, because what it exists to show is
    whether the mark *looks* right on a 40pt cover; the number it is drawn at is already pinned on
    both sides that ship.
    """
    scale = cover_h / 124  # kReadingBookmarkBook
    ribbon_w = 13.5 * scale
    pinned = (8 + 4.5) * scale  # kReadingBookmarkInset + the asset's right bleed
    inset = pinned
    if progress is not None:
        travel = cover_w - pinned - ribbon_w - cover_w * 0.082  # _kBindingFraction
        if travel > 0:
            inset = pinned + (1 - min(max(progress, 0.0), 1.0)) * travel
    shadow = f"drop-shadow(0 {4 * scale:.2f}px {4 * scale:.2f}px rgba(0,0,0,.5))"
    # The viewBox crops the asset's 22x38 box to the visible ribbon, x4..17.5 and y0..30 -- the
    # rest is bleed its own drop-shadow filter needed, and drawing it would offset the mark.
    return (
        f'<svg class="bm" width="{ribbon_w:.2f}" height="{30 * scale:.2f}"'
        f' viewBox="4 0 13.5 30"'
        f' style="right:{inset:.2f}px;filter:{shadow}" aria-hidden="true">'
        f'<path d="{path_d}" fill="white"/></svg>'
    )


def flame_paths() -> tuple[str, str]:
    """The body and core paths, printed by the generator every other surface uses."""
    svg = subprocess.run(
        [sys.executable, str(ROOT / "rive/streak_flame/icon.py"), "--svg"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    if svg.returncode != 0:
        sys.exit(f"icon.py --svg failed:\n{svg.stderr}")
    paths = re.findall(r'<path d="([^"]+)"', svg.stdout)
    if len(paths) != 2:
        sys.exit(f"expected two flame paths from icon.py, got {len(paths)}")
    return paths[0], paths[1]


# ---------------------------------------------------------------- the ground recipe


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) for i in (0, 2, 4))
    return r, g, b


# Takes floats, because `mix` hands it interpolated channels and the rounding here is the
# whole point: `mixHex` in index.html rounds to 8 bits, which is what makes this port
# reproduce the sheet's hexes to the digit rather than to the eye.
def to_hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{round(c):02X}" for c in rgb)


def mix(a: str, b: str, t: float) -> str:
    """`mixHex`, including its 8-bit rounding -- which is why this reproduces the
    sheet's own hexes to the digit rather than to the eye."""
    x, y = hex_rgb(a), hex_rgb(b)
    return to_hex(
        (
            x[0] + (y[0] - x[0]) * t,
            x[1] + (y[1] - x[1]) * t,
            x[2] + (y[2] - x[2]) * t,
        )
    )


def luminance(value: str) -> float:
    def channel(c: float) -> float:
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = hex_rgb(value)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a: str, b: str) -> float:
    first, second = luminance(a), luminance(b)
    hi, lo = max(first, second), min(first, second)
    return (hi + 0.05) / (lo + 0.05)


def sample(anchors: list[tuple[float, str, str]], hour: float) -> tuple[str, str]:
    if hour <= anchors[0][0]:
        return anchors[0][1], anchors[0][2]
    if hour >= anchors[-1][0]:
        return anchors[-1][1], anchors[-1][2]
    for (h0, t0, b0), (h1, t1, b1) in zip(anchors, anchors[1:]):
        if h0 <= hour <= h1:
            t = (hour - h0) / (h1 - h0)
            return mix(t0, t1, t), mix(b0, b1, t)
    return anchors[-1][1], anchors[-1][2]


def ground(top: str, bottom: str, accent: str | None = None, radial: bool = False) -> dict:
    """`groundVars()`, ported. The ink is compared rather than thresholded and the dim
    is backed off until it clears 3.2:1, both for the reasons index.html records."""
    mid = mix(top, bottom, 0.5)
    ink = INK_LIGHT if contrast(INK_LIGHT, mid) >= contrast(INK_DARK, mid) else INK_DARK
    dim = mix(ink, mid, 0.42)
    t = 0.42
    while t > 0 and contrast(dim, mid) < 3.2:
        t -= 0.06
        dim = mix(ink, mid, max(0.0, t))
    div = mix(mid, ink, 0.16)

    if radial:
        background = (
            f"radial-gradient(130% 105% at 50% 112%, {bottom} 0%, {mid} 52%, {top} 100%)"
        )
    else:
        def rgba(value: str, alpha: float) -> str:
            r, g, b = hex_rgb(value)
            return f"rgba({r},{g},{b},{alpha})"

        lift = mix(top, "#FFFFFF", 0.2)
        deep = mix(bottom, "#000000", 0.18)
        acc = accent or top

        def blob(geom: str, colour: str, stop: int) -> str:
            return (
                f"radial-gradient({geom}, {rgba(colour, 0.3)} 0%, "
                f"{rgba(colour, 0)} {stop}%)"
            )

        background = ",".join(
            [
                "radial-gradient(115% 95% at 50% 40%, rgba(0,0,0,0) 40%,"
                " rgba(0,0,0,.16) 78%, rgba(0,0,0,.36) 100%)",
                blob("75% 60% at 16% 10%", lift, 62),
                blob("70% 58% at 88% 22%", acc, 60),
                blob("95% 80% at 50% 112%", deep, 70),
                f"linear-gradient(158deg, {top} 0%, {mid} 52%, {bottom} 100%)",
            ]
        )
    return {"top": top, "bottom": bottom, "mid": mid, "ink": ink, "dim": dim,
            "div": div, "background": background}


# ---------------------------------------------------------------- drawing


def esc(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def flame_svg(body: str, core: str, *, lit: bool, size: int = 28) -> str:
    """Lit is the amber pair; unlit is the hour's own dim with the core knocked out to
    the tile, which is what keeps the notch and the low fat core legible."""
    fill = "var(--flame)" if lit else "var(--dim)"
    core_fill = "var(--core)" if lit else "var(--tile)"
    return (
        f'<svg class="fl" width="{size}" height="{size}" viewBox="0 0 100 100" aria-hidden="true">'
        f'<path d="{body}" fill="{fill}"/><path d="{core}" fill="{core_fill}"/></svg>'
    )


def style_for(g: dict) -> str:
    return (
        f"--tile:{g['top']};--ink:{g['ink']};--dim:{g['dim']};--div:{g['div']};"
        f"background:var(--grain),{g['background']}"
    )


def tile(
    g: dict,
    pose: str,
    line: str,
    run: int | None,
    *,
    lit: bool,
    flame: tuple[str, str],
    medium: bool = False,
    book: bool = False,
    quad: bool = False,
    cover: str = DARK_COVER,
    bookmark: str = "",
) -> str:
    classes = ["fr", "hascat"]
    if medium:
        classes.append("md")
    if quad:
        classes.append("quad")
    if line:
        classes.append("hasline")
    img = ASSETS / f"{pose}.imageset/{pose}@3x.png"
    rel = "../../../" + str(img.relative_to(ROOT)) if img.exists() else ""
    cat = f'<div class="cat"><img src="{rel}" alt=""></div>' if rel else ""
    # **No figure at all when there is no run**, which is `showsFigure: false` in the
    # Swift: a "0" beside a flame announces that the reader has nothing, where the line
    # beside it is an invitation. Drawing one here made this page disagree with the app
    # about the state the app is in most often -- 136 of 137 profiles.
    figure = (
        f'<span class="fig{" recorded" if lit else ""}">{run}</span>'
        if run is not None
        else ""
    )
    run_row = (
        f'<div class="runrow{"" if lit else " glass"}">'
        f"{flame_svg(*flame, lit=lit)}{figure}</div>"
    )
    jacket = (
        '<div class="book"><div class="jkwrap">'
        f'<div class="jk" style="background:{cover}"></div>{bookmark}</div>'
        '<div class="bt">'
        "<b>Piranesi</b><i>Susanna Clarke</i><u><s></s></u></div></div>"
        if book
        else ""
    )
    line_html = f'<div class="line">{esc(line)}</div>' if line else ""
    if quad:
        # Four corners rather than two columns: the run stays where the eye lands, the copy
        # takes the opposite corner, the book anchors the floor and the cat keeps the
        # remaining one. Absolutely positioned rather than a grid because three of the four
        # are corner-anchored and the cat is already out of flow.
        return (
            f'<div class="{" ".join(classes)}" style="{style_for(g)}">'
            f"{cat}{run_row}{line_html}{jacket}</div>"
        )
    return (
        f'<div class="{" ".join(classes)}" style="{style_for(g)}">{cat}'
        f'<div class="col">{run_row}{line_html}<div class="grow"></div></div>'
        f"{jacket}</div>"
    )


def build(data: dict) -> str:
    anchors = data["anchors"]
    flame = data["flame"]
    lines = data["lines"]
    pose = data["poses"]
    hours = data["hours"]
    rec = ground(*data["recorded"], radial=True)

    def tier_ground(tier: str) -> dict:
        hour = hours[tier] if tier != "dawn" else anchors[0][0]
        top, bottom = sample(anchors, hour)
        accent, _ = sample(anchors, hour + 3)
        return ground(top, bottom, accent=accent)

    grounds = {t: tier_ground(t) for t in TIERS}
    grounds["none"] = ground(
        anchors[0][1], anchors[0][2], accent=sample(anchors, anchors[0][0] + 3)[0]
    )
    grounds["recorded"] = rec

    # The hours a tier actually owns, rather than the boundary the sheet labelled it with.
    #
    # **`dawn` starts at the rollover, not at 05:00, and that is the clamp rather than a
    # bug.** `StreakTier.forHour` has no 05:00 test: every hour below the first boundary
    # falls through to dawn, because a reader up at 03:00 is either very late or very
    # early and neither of them wants the 23:00 voice. The design record's 05:00 is the
    # nominal start of the tier; this prints what the code does.
    def span(state: str) -> str:
        if state in APART:
            return "any hour"
        index = TIERS.index(state)
        start = 0 if index == 0 else hours[state]
        end = 24 if index == len(TIERS) - 1 else hours[TIERS[index + 1]]
        return f"{start:02d}:00 \u2013 {end - 1:02d}:59"

    def cells(
        states: list[str],
        locale: str,
        *,
        medium: bool = False,
        quad: bool = False,
        cover: str = DARK_COVER,
        progress: float | None = 0.41,
    ) -> str:
        out = []
        for state in states:
            lit = state == "recorded"
            run = 4 if lit else None if state == "none" else 3
            line = "" if lit else lines[locale][state]
            # The quad jacket is 40x58 and the two-column one 44x64, and the ribbon is sized and
            # placed from those -- so the same position reads at the same place at both sizes,
            # which is the property `ReadingBookmark.scale` exists for.
            mark = (
                bookmark_svg(
                    data["bookmark"],
                    40 if quad else 44,
                    58 if quad else 64,
                    progress,
                )
                if medium
                else ""
            )
            out.append(
                '<td class="cell">'
                + tile(
                    grounds[state],
                    pose[state],
                    line,
                    run,
                    lit=lit,
                    flame=flame,
                    medium=medium,
                    book=medium,
                    quad=quad,
                    cover=cover,
                    bookmark=mark,
                )
                + "</td>"
            )
        return "".join(out)

    def heads(states: list[str]) -> str:
        out = []
        for state in states:
            out.append(
                f'<th>{state}<i>{span(state)}</i><code>{pose[state]}</code></th>'
            )
        return "".join(out)

    # The list view, which is the thing a grid cannot be read as: one row per state with
    # every value that decides it, so a wrong pose or a stale line is findable by eye.
    rows = []
    for state in TIERS + APART:
        g = grounds[state]
        against = contrast(max(g["top"], g["bottom"], key=luminance), rec["bottom"])
        rows.append(
            f"<tr><td><b>{state}</b></td>"
            f"<td>{span(state)}</td>"
            f"<td><code>{pose[state]}</code></td>"
            f'<td>{esc(lines["en"].get(state, "\u2014 none \u2014"))}</td>'
            f'<td>{esc(lines["ko"].get(state, "\u2014 none \u2014"))}</td>'
            f'<td><code>{g["top"]}</code> \u2192 <code>{g["bottom"]}</code></td>'
            f'<td>{"\u2014" if state == "recorded" else f"{against:.2f}:1"}</td></tr>'
        )

    strip = "".join(
        f'<div class="sw" style="background:{ground(*sample(anchors, h), accent=sample(anchors, h + 3)[0])["background"]}">'
        f"<span>{h:02d}</span></div>"
        for h in range(7, 24)
    )

    worst = min(
        contrast(max(g["top"], g["bottom"], key=luminance), rec["bottom"])
        for key, g in grounds.items()
        if key != "recorded"
    )

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Streak widget &middot; as it ships</title>
<style>
  /* Nunito, the figure's face, loaded from the file the *extension* bundles -- so a
     numeral that looks wrong here looks wrong on the phone. Subset to digits, which is
     all a run is. */
  @font-face {{ font-family: "Nunito"; src: url("../../../assets/fonts/Nunito-ExtraBold.ttf") format("truetype"); font-weight: 800; }}
  :root {{ color-scheme: dark; }}
  body {{ margin: 0; padding: 24px 22px 60px; background: #23292e; color: #e8edf2;
         font: 13px/1.5 ui-sans-serif, -apple-system, sans-serif; }}
  h1 {{ font-size: 15px; letter-spacing: .06em; text-transform: uppercase; margin: 0 0 8px; }}
  h2 {{ font-size: 12px; letter-spacing: .06em; text-transform: uppercase; color: #9fb0bd;
        margin: 34px 0 10px; }}
  p {{ margin: 0 0 14px; color: #9fb0bd; max-width: 108ch; }}
  p b, td b {{ color: #e8edf2; }}
  code {{ color: #cbd6df; font: 11.5px ui-monospace, SFMono-Regular, Menlo, monospace; }}
  .locale {{ font: 600 11px/1 ui-monospace, Menlo, monospace; color: #7ee2b8;
            letter-spacing: .08em; margin: 14px 0 6px; }}
  table.tiles {{ border-collapse: separate; border-spacing: 10px 6px; margin-left: -10px; }}
  table.tiles th {{ font-size: 11px; font-weight: 700; color: #cbd6df; text-align: left;
        vertical-align: bottom; padding: 0 0 3px; }}
  table.tiles th i {{ display: block; font-style: normal; font-weight: 400; color: #8fa3b2; }}
  table.tiles th code {{ display: block; font-size: 10.5px; color: #7f909d; }}
  .cell {{ vertical-align: top; }}
  /* The list. Every value that decides a tile, in one place. */
  table.list {{ border-collapse: collapse; font-size: 12px; margin: 0 0 8px; }}
  table.list th {{ text-align: left; font-size: 10.5px; letter-spacing: .06em;
        text-transform: uppercase; color: #8fa3b2; padding: 0 14px 6px 0; }}
  table.list td {{ padding: 5px 14px 5px 0; border-top: 1px solid #333c44;
        vertical-align: top; }}
  .strip {{ display: flex; gap: 3px; margin: 0 0 10px; }}
  .sw {{ width: 52px; height: 52px; border-radius: 7px; display: flex;
        align-items: flex-end; justify-content: center; }}
  .sw span {{ font: 600 10px ui-monospace, Menlo, monospace; color: rgba(255,255,255,.72);
        padding-bottom: 3px; }}

  /* The tile, at the real geometry: 158x158 for systemSmall and 338x158 for
     systemMedium, radius 22, 14pt inset -- the sizes a 393pt phone hands out. */
  .fr {{ --flame: #F2A93F; --core: #FFD479;
        --grain: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.8' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)' opacity='.05'/%3E%3C/svg%3E");
        width: 158px; height: 158px; border-radius: 22px; padding: 14px;
        box-sizing: border-box; position: relative; overflow: hidden; display: flex;
        box-shadow: 0 1px 2px rgba(0,0,0,.2), 0 10px 24px rgba(0,0,0,.18);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }}
  .fr.md {{ width: 338px; }}
  .col {{ position: relative; z-index: 1; display: flex; flex-direction: column;
         flex: 1; min-width: 0; }}
  .cat {{ position: absolute; left: 0; right: 0; bottom: -8%; height: 70%;
         display: flex; align-items: flex-end; justify-content: center; z-index: 0; }}
  .cat img {{ height: 100%; width: auto; display: block; }}
  .fr.hascat.hasline .cat {{ justify-content: flex-end; right: -6%; }}
  .fr.hascat.hasline .line {{ max-width: 52%; }}
  .fr.md .cat {{ justify-content: flex-end; right: 4%; }}
  .runrow {{ display: flex; align-items: center; gap: 8px; }}
  .runrow.glass {{ opacity: .5; }}
  /* `line-height: 1` is load-bearing and is *not* the browser's default here. Nunito
     ExtraBold's own metrics are ascent 1011 / descent -353 on a 1000 em, so its natural
     line box is 1.364em -- which is what SwiftUI lays a `Text` out in. Keeping this at 1
     while the app used the natural box put the run row 7.3pt lower on device than on this
     page, and that was the entire difference between the two. The Swift now pins the
     figure to `.frame(height: figureSize)`, which is this rule spelled in SwiftUI. */
  .fig {{ font-family: "Nunito", ui-rounded, -apple-system, sans-serif; font-weight: 800;
         color: var(--ink); letter-spacing: -.5px; font-size: 40px; line-height: 1; }}
  .fig.recorded {{ color: #fff; -webkit-text-stroke: 6px var(--flame);
                  paint-order: stroke fill; }}
  .line {{ font-size: 11px; font-style: italic; color: var(--dim); line-height: 1.25;
          margin-top: 3px;
          /* Korean breaks at spaces, not between syllables. CSS's default for CJK is to
             break anywhere, which split \u201c\uc77d\uae30\ub85c \ud588\uc796\uc544\uc694.\u201d after \ud588\uc796\uc544 \u2014 a break CoreText
             would not make, so the page was showing a defect the app does not have. */
          word-break: keep-all; }}
  .grow {{ flex: 1; }}
  /* systemMedium's right-hand half: the jacket it keeps and small gave up. */
  .book {{ position: relative; z-index: 1; display: flex; gap: 9px; margin-left: 14px;
          align-items: flex-start; }}
  .jkwrap {{ position: relative; flex: 0 0 auto; }}
  /* The ribbon hangs from the cover's top edge and is **not** clipped by it -- "a bookmark a
     clip swallows is not a bookmark", in `card_cover_row.dart`'s own words. `top: 0` against
     the wrapper rather than the jacket, so the jacket's 1px border does not shift it. */
  .bm {{ position: absolute; top: 0; display: block; }}
  .jk {{ width: 44px; height: 64px; border-radius: 3px; background: #8A5A2B;
        box-shadow: inset 3px 0 0 rgba(0,0,0,.18);
        /* The edge, which the Swift draws as a 1pt `strokeBorder` in the ground's own ink at
           28%. Without it a near-white `cover_color` -- which is what a white-paper jacket
           samples to -- is invisible on the recorded tile's cream ground and reads as a cover
           that failed to load. `currentColor` carries `--ink`, so it works on all seven
           grounds rather than only on the cream one. */
        border: 1px solid color-mix(in srgb, var(--ink) 28%, transparent);
        box-sizing: border-box; flex: 0 0 auto; }}
  .bt {{ min-width: 0; }}
  .bt b {{ display: block; font-size: 13px; font-weight: 600; color: var(--ink);
          white-space: nowrap; }}
  .bt i {{ display: block; font-style: normal; font-size: 11px; color: var(--dim);
          margin-top: 1px; }}
  .bt u {{ display: block; text-decoration: none; height: 3px; border-radius: 2px;
          background: var(--div); margin-top: 7px; width: 96px; }}
  .bt s {{ display: block; text-decoration: none; height: 3px; border-radius: 2px;
          background: var(--flame); width: 41%; }}
  /* ---- the four-corner medium, which is what ships ---------------------------
     Book bottom-left, copy top-right, run top-left, cat bottom-right. Corner-anchored
     rather than a grid, because three of the four hug an edge and the cat is already out
     of flow. */
  .fr.quad .runrow {{ position: absolute; z-index: 1; left: 14px; top: 14px; }}
  /* **133px, not 43%.** The Swift's cap is 43% of the *content box*; a CSS percentage on an
     absolutely positioned box resolves against the padding box, so `43%` here would be 43%
     of the whole 338px tile -- 145px against the app's 133px, and a copy column 9% wider
     than the one that ships. Same trap as `.bt` below, and the reason both are pinned in
     points: the two sides measure from different origins, so only an absolute value can be
     read as agreeing. */
  .fr.quad .line {{ position: absolute; z-index: 1; right: 14px; top: 16px;
                   max-width: 133px; text-align: right; margin: 0; }}
  .fr.quad .book {{ position: absolute; z-index: 1; left: 14px; bottom: 14px;
                   margin-left: 0; align-items: flex-end; }}
  /* The cat comes down from 70% to 62%: at 70% it reaches the copy's corner, and the copy
     is the one thing on the tile that cannot be sat behind. Percentages are right here --
     the cat is in the container background, which is the whole tile on both sides. */
  .fr.quad .cat {{ height: 62%; justify-content: flex-end; right: 2%; }}
  .fr.quad .jk {{ width: 40px; height: 58px; }}
  /* 146px is 47% of the 310px content box, which is the cap the Swift applies. Invisible
     with a title as short as Piranesi, and the only thing standing between a long one and
     the cat -- a one-line title takes whatever width it is offered. */
  .fr.quad .bt {{ max-width: 146px; }}
  .fr.quad .bt u {{ margin-top: 5px; width: 88px; }}
</style>
</head>
<body>
<h1>Streak widget &middot; as it ships</h1>
<p>
  Every state the tile can be in, in both locales, at the real
  <b>158&times;158</b> and <b>338&times;158</b>. <b>Nothing here is retyped.</b> The copy is read
  out of <code>app_en.arb</code> / <code>app_ko.arb</code>, the ground ramp and the poses out of
  <code>StreakWidget.swift</code>, the tier hours out of <code>StreakSnapshot.swift</code>, the
  cut-outs are the extension's own <code>Assets.xcassets</code> at 3x, and the flame is printed by
  <code>rive/streak_flame/icon.py --svg</code>. Rebuild with
  <code>scripts/render_final_widget.py</code>.
</p>
<p>
  <b>What this page is not:</b> a rendering of SwiftUI. It is the same numbers drawn by a browser,
  so it settles copy, colour, pose and crop — and cannot settle what
  <code>lineLimit(3)</code>, <code>minimumScaleFactor</code> or the sticker numeral's twelve
  offset copies actually do on a device. Those need a simulator.
</p>
<p>
  <b>It also cannot see anything WidgetKit or CoreText does around the tile</b>, and two defects
  have already got through that gap — both found by measuring a simulator screenshot against this
  page with <code>scripts/measure_widget_shot.py</code>, and neither visible as an error anywhere.
  The 14pt inset is drawn here directly, where on iOS 17 the system adds <i>its own</i> ~16pt
  content margins unless the widget calls <code>contentMarginsDisabled()</code>. And the numeral is
  set <code>line-height: 1</code> here, where SwiftUI uses Nunito's natural <b>1.364em</b> line box
  — which put the run row <b>7.3pt</b> lower on device, measured 23.0pt from the tile's edge
  against the 15.5pt this page draws. A tile with either defect renders as a smaller, more timid
  version of the design rather than as anything broken.
</p>

<h2>The day &mdash; systemSmall</h2>
<p>
  <code>dawn</code> owns every hour below the first boundary as well as its own, because a reader
  up at 03:00 is either very late or very early and neither of them wants the 23:00 voice.
</p>
<div class="locale">EN</div>
<table class="tiles"><tr>{heads(TIERS)}</tr><tr>{cells(TIERS, "en")}</tr></table>
<div class="locale">KO</div>
<table class="tiles"><tr>{cells(TIERS, "ko")}</tr></table>

<h2>The two states that replace the day</h2>
<table class="tiles"><tr>{heads(APART)}</tr>
<tr>{cells(APART, "en")}</tr><tr>{cells(APART, "ko")}</tr></table>

<h2>systemMedium &mdash; the family that kept the book</h2>
<p>
  <b>Book bottom-left, copy top-right</b>, which leaves the run in the corner the eye lands on and
  the cat the one opposite it. Small dropped the jacket, and that is what bought it a line at all;
  medium keeps the jacket, title, author and progress, and puts them along the floor so they read as
  one object rather than as a sidebar. The copy gets <b>133pt</b> here against the two-column
  version's 76pt &mdash; <b>1.74&times;</b>, and wider than on small, which the layout it replaced
  was not. Copy is right-aligned because it hugs the right edge; flipping it to leading is one line.
</p>
<p>
  What it costs is that <b>the cat comes down from 70% of the tile to 62%</b> to stay out of the
  copy's corner, so the character is smaller here than in any other tile. The run row is small's, at
  28 and 40 &mdash; there is no jacket beside it to make room for any more. The recorded tile leaves
  the top-right corner empty, because <code>recorded</code> has no line in any locale.
</p>
<p>
  <b>The bookmark is the library's own ribbon</b>, at the tile's scale, slid in from the fore-edge by
  how far through the book the reader is &mdash; the same track the shelf and the Library Card use,
  so the mark reads the same position at three sizes. Drawn here at <b>41%</b>, matching the progress
  bar beside it.
</p>
<table class="tiles"><tr>{heads(["late", "recorded"])}</tr>
<tr>{cells(["late", "recorded"], "en", medium=True, quad=True)}</tr>
<tr>{cells(["late", "recorded"], "ko", medium=True, quad=True)}</tr></table>
<p>
  <b>The same two with a pale jacket</b>, <code>{PALE_COVER}</code> &mdash; what the app actually
  wrote for a Korean paperback whose cover is white paper. <code>cover_color</code> is sampled from
  the real jacket, so this is a common case and not an edge, and on the recorded tile's cream ground
  an unbordered rectangle of it is invisible. The 1pt edge is the whole fix; the page drew only the
  brown above until the device showed otherwise.
</p>
<p>
  These two also carry <b>no recorded position</b>, which is the other end of the bookmark's track:
  a null <code>progress</code> pins the ribbon at the fore-edge rather than sending it to the
  gutter, because every book has a null position until someone answers the percent wheel and a mark
  at the gutter would claim the reader had barely started. Note the ribbon draws here while the
  progress bar does not &mdash; a bar at zero is a claim, the ribbon at its pin is the absence of one.
</p>
<table class="tiles">
<tr>{cells(["late", "recorded"], "en", medium=True, quad=True, cover=PALE_COVER, progress=None)}</tr></table>

<h2>systemMedium &mdash; the two-column version, which lost</h2>
<p>
  Kept rather than deleted, because it is the arrangement the four-corner one is an argument
  against. The jacket is a column of its own at the far left with the run, title, author, progress
  and line stacked beside it, and it cost twice over. The line inherited small's <i>52% of the
  column</i> cap &mdash; but the column starts a jacket and a gap in from the left, so the copy came
  out <b>76pt</b> wide, narrower on the wide tile than on the narrow one. And a jacket at the left
  margin with everything else to its right reads as a sidebar rather than as part of the tile.
</p>
<table class="tiles"><tr>{heads(["late", "recorded"])}</tr>
<tr>{cells(["late", "recorded"], "en", medium=True)}</tr>
<tr>{cells(["late", "recorded"], "ko", medium=True)}</tr></table>

<h2>The ground, hour by hour</h2>
<p>
  The copy and the pose step at the six tier boundaries; the ground interpolates between anchors,
  so it travels continuously while the sentence holds. 07:00 to 23:00, which is the waking day.
</p>
<div class="strip">{strip}</div>

<h2>Every state, as a list</h2>
<table class="list">
<tr><th>state</th><th>from</th><th>pose</th><th>en</th><th>ko</th><th>ground</th><th>vs recorded</th></tr>
{"".join(rows)}
</table>
<p>
  The last column is the amended <code>sc-risk</code> rule, measured: the lightest stop of the open
  ground against the darkest stop of the recorded one, which is the worst pairing there is. Worst
  hour on the whole ramp is <b>{worst:.2f}:1</b>, and
  <code>test/streak_widget_palette_test.dart</code> fails below 4.5:1.
</p>
</body>
</html>
"""


# The numbers the four-corner medium is built from, and the CSS above draws. Each is a
# literal in both places, so `--check` reads the Swift back and asserts they still agree.
#
# This is the same drift guard as the ground ramp, for a layout rather than a palette --
# and it is worth having because the way this page goes stale is silently: a `0.62` edited
# in the Swift and not in the CSS leaves a page that still renders, still looks plausible,
# and no longer describes the tile.
QUAD_NUMBERS = {
    "the cat's height, as a share of the tile": "heightFraction: family == .systemMedium ? 0.62 : 0.70",
    "the cat's trailing overhang": "trailingOverhang: family == .systemMedium ? -0.02 : 0.06",
    "the copy's width cap": "geometry.size.width * 0.43",
    "the book column's width cap": "geometry.size.width * 0.47",
    "the jacket": "width: 40, height: 58",
    "the progress bar": ".frame(width: 88)",
    "the run row": "flameSize: 28,",
    "the figure": "figureSize: 40",
    "the copy anchored top-right": "alignment: .topTrailing",
    "the book anchored bottom-left": "alignment: .bottomLeading",
    # Not a number, and the reason this list exists at all: the tile drew correct-but-timid
    # on device for want of this one call, and nothing on the page could show it.
    "content margins turned off": ".contentMarginsDisabled()",
    # The other half of the same lesson. `.fig` below sets `line-height: 1`; SwiftUI uses
    # Nunito's natural 1.364em line box unless the figure is given an explicit height, and
    # the difference put the run row 7.3pt lower on device than on this page.
    "the figure's line box pinned to its font size": ".frame(height: figureSize)",
    # The bookmark's shape and track. The numbers themselves are held to the SVG and to
    # `reading_bookmark.dart` by `test/streak_widget_palette_test.dart`; these two only assert
    # that the tile still *draws* them, since deleting the overlay would leave every constant
    # correct and the ribbon absent.
    "the bookmark drawn on the jacket": "BookmarkRibbon()",
    "the bookmark's track": "ReadingBookmarkTrack.trailingInset(",
}


def check(data: dict) -> int:
    """Assert this port and the Swift agree, and that the page has everything it draws."""
    problems: list[str] = []
    anchors = data["anchors"]
    for hour, top, bottom in anchors:
        g = ground(top, bottom, accent=sample(anchors, hour + 3)[0])
        if g["top"] != top or g["bottom"] != bottom:
            problems.append(f"{hour:02.0f}:00 ground stops do not round-trip")
    for state, pose in data["poses"].items():
        if not (ASSETS / f"{pose}.imageset/{pose}@3x.png").exists():
            problems.append(f"{state}: {pose} has no @3x in the asset catalog")
    # The Korean budget: about 7 full-width syllables a line over three lines.
    for state, text in data["lines"]["ko"].items():
        wide = sum(1 for ch in text if ord(ch) > 0x1100)
        if wide > 21:
            problems.append(f"ko {state}: {wide} full-width syllables, over a 3-line box")
    widget = data["widget"]
    for what, needle in QUAD_NUMBERS.items():
        if needle not in widget:
            problems.append(
                f"{what}: `{needle}` is not in StreakWidget.swift any more, "
                "so this page is drawing a medium tile the app does not"
            )
    for problem in problems:
        print(f"PROBLEM: {problem}")
    return 1 if problems else 0


def main() -> int:
    widget = read(WIDGET_SWIFT)
    data = {
        "anchors": ramp_anchors(widget),
        "recorded": recorded_ground(widget),
        "poses": poses(widget),
        "hours": tier_hours(read(SNAPSHOT_SWIFT)),
        "lines": copy_lines(),
        "flame": flame_paths(),
        "bookmark": bookmark_path(),
        "widget": widget,
    }
    if "--check" in sys.argv:
        return check(data)

    OUT.write_text(build(data))
    print(f"{OUT.relative_to(ROOT)}")
    print(f"  anchors   {len(data['anchors'])} hours, "
          f"{data['anchors'][0][1]} \u2192 {data['anchors'][-1][1]}")
    print(f"  recorded  {data['recorded'][0]} \u2192 {data['recorded'][1]}")
    for state in TIERS + APART:
        line = data["lines"]["en"].get(state) or "\u2014"
        print(f"  {state:<10} {data['poses'][state]:<12} {line}")
    return check(data)


if __name__ == "__main__":
    raise SystemExit(main())
