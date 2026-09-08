#!/usr/bin/env python3
"""Splice the scan-to-add sections into a copy of the mockup shell.

Rebuilding from the pristine shell each time is deliberate: it keeps
SECTION 5 (the engine) byte-identical to the skill's version, so none of
the interaction bugs documented in reference/pitfalls.md can be
reintroduced by hand-editing a 2,600-line file. `verify.sh` asserts that
identity, so the guarantee is checked rather than hoped for.

    python3 _build/build.py && sh _build/verify.sh
"""
import pathlib
import sys

SHELL = pathlib.Path.home() / ".agents/skills/design-mockups/assets/shell.html"
HERE = pathlib.Path(__file__).parent
OUT = HERE.parent / "index.html"

src = SHELL.read_text()
tokens = (HERE / "tokens.css").read_text()
frame_css = (HERE / "frame.css").read_text()
data_js = (HERE / "data.js").read_text()


def cut(text, start, end, replacement, label):
    """Replace text[start:end] where both are literal anchors."""
    i = text.find(start)
    j = text.find(end)
    if i < 0 or j < 0 or j <= i:
        sys.exit(f"anchor miss for {label}: start={i} end={j}")
    return text[:i] + replacement + text[j:]


# --- SECTION 1a: tokens -------------------------------------------------
src = cut(
    src,
    "                /* ---- SECTION 1a",
    "                /* ---- page chrome (safe to leave) ---- */",
    tokens,
    "1a",
)

# --- SECTION 1b: device / frame styles ---------------------------------
# The end anchor is the close of the <style> block, NOT the SECTION 2 header:
# SECTION 2 lives in the <script> after the body, so anchoring there deletes
# the entire page markup, h1s and all.
src = cut(
    src,
    "   SECTION 1b: DEVICE / FRAME STYLES",
    "        </style>",
    frame_css,
    "1b",
)

# --- SECTIONS 2-4: renderer, data, versions ----------------------------
src = cut(
    src,
    "   SECTION 2: FRAME RENDERER",
    "            /* ==================================================================\n   SECTION 5: ENGINE",
    data_js,
    "2-4",
)

# --- page copy ----------------------------------------------------------
src = src.replace(
    "  Design mockup shell. Self-contained: no build, no server, no network.",
    "  GENERATED. Edit _build/{tokens.css,frame.css,data.js} and run\n"
    "    python3 _build/build.py && sh _build/verify.sh\n"
    "  Hand edits here are lost on the next build. The output is still fully\n"
    "  self-contained: no build step, no server, no network to view it.",
)
src = src.replace(
    "<title>Design mockups</title>",
    "<title>Scan to add a book &mdash; one flow or two doors</title>",
)
src = src.replace(
    ">PRODUCT &mdash; <span>design mockups</span></span",
    ">\uc9c4\ubc85\ub808 \uce5c\uad6c\ub4e4 &mdash; <span>scan to add</span></span",
)

LEAD_SCREENS = """                <h1>Scan to add a book &mdash; one flow or two doors</h1>
                <p class="lead">
                    Every state a camera-driven Add Book can be in, drawn at
                    <b>1px&nbsp;=&nbsp;1pt</b> on a 402&times;874 frame &mdash;
                    that device because both things this set has to place were
                    measured on it:
                    <code>add_book_bottom_sheet.dart</code> reasons in it, and
                    every figure in <code>ShellTabBarGeometry</code> comes from
                    an iPhone&nbsp;17&nbsp;Pro / iOS&nbsp;26.4 simulator.
                    Colours are <code>AppColors</code> verbatim &mdash;
                    <code>sheetBackground&nbsp;#EFF5EF</code> for the sheet,
                    <code>surfaceVariant&nbsp;#E9ECEF</code> for the search
                    pill, and the <b>dark</b> map for the scanner, because a
                    camera preview is dark whatever the theme says (which is
                    what lets the reticle use the vivid
                    <code>#09BC8A</code> as text at 6.8:1). The sheet's top
                    edge is at 62pt from
                    <code>max(viewPadding.top,&nbsp;24)</code>; the tab bar's
                    frame is <code>(0,791)&ndash;(402,874)</code> with the
                    search orb at <code>x&nbsp;319.2&ndash;381.1</code>, both
                    read off the <code>UITabBar</code> accessibility tree. The
                    search pill is radius
                    <code>kSearchPillRadius&nbsp;=&nbsp;10</code>, books are
                    131&times;82 (15% of height, divided by 1.6), the shelf 8pt
                    with <code>offset(0,2) blur 2 black@25%</code>. Switch
                    direction with <span class="kbd">v</span>, compare two with
                    <span class="kbd">&#8679;Enter</span>.
                </p>
"""
src = cut(
    src,
    "                <h1>Screens</h1>",
    '                <div id="screens"></div>',
    LEAD_SCREENS,
    "screens lead",
)

LEAD_ELEMENTS = """                <h1>UI elements</h1>
                <p class="lead">
                    The parts the entry point is assembled from, and the 352pt
                    of search row they have to share. The one number worth
                    arguing over is in <b>Search row</b>: 300pt of pill with one
                    button, 248 with two.
                </p>
"""
src = cut(
    src,
    "                <h1>UI elements</h1>",
    '                <div id="elements"></div>',
    LEAD_ELEMENTS,
    "elements lead",
)

LEAD_FLOWS = """                <h1>UX flows</h1>
                <p class="lead">
                    The happy path, the escalation that removes its dead end,
                    and the three ways it fails. Every step is a real state from
                    the Screens tab &mdash; the specs are shared consts, so a
                    corrected screen cannot leave a flow drawing the old one.
                    Red callouts are decisions that are genuinely still open.
                </p>
"""
src = cut(
    src,
    "                <h1>UX flows</h1>",
    '                <div class="flowlayout">',
    LEAD_FLOWS,
    "flows lead",
)

OUT.write_text(src)
print(f"wrote {OUT} ({len(src)} bytes)")
