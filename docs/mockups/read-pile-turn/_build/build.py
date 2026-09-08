#!/usr/bin/env python3
"""Splice the read-pile sections into a copy of the mockup shell.

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
    "<title>The read pile &mdash; hashed spines, and turning one out</title>",
)
src = src.replace(
    ">PRODUCT &mdash; <span>design mockups</span></span",
    ">\uc9c4\ubc85\ub808 \uce5c\uad6c\ub4e4 &mdash; <span>read pile</span></span",
)

LEAD_SCREENS = """                <h1>The read pile &mdash; hashed spines, and turning one out</h1>
                <p class="lead">
                    Two proposals for the collapsed &ldquo;Books read&rdquo;
                    sheet, drawn at <b>1px&nbsp;=&nbsp;1pt</b> on a 402pt frame
                    &mdash; that width because
                    <code>ShellTabBarGeometry</code>'s figures were measured on
                    it, and the tab bar's band is what the pile has to clear.
                    Colours are <code>AppColors.light</code> and
                    <code>BookChassisColors.of</code> verbatim:
                    <code>surface&nbsp;#FFFFFF</code> for the card and the
                    plank, <code>brand&nbsp;#09BC8A</code> for the spines,
                    <code>backBoard&nbsp;#E3E3E3</code> and
                    <code>pageEdge&nbsp;#EAEAEA</code> for the turned book.
                    The card floats at <code>_gutterInset&nbsp;=&nbsp;14</code>
                    with corners concentric with the display's 55, i.e. 41, and
                    reserves <code>57&nbsp;+&nbsp;34&nbsp;&minus;&nbsp;14</code>
                    = 77pt below the pile.
                    <code>ReadPile.extent</code> is
                    <code>14&nbsp;+&nbsp;137&nbsp;+&nbsp;8&nbsp;+&nbsp;10</code>
                    = 169.
                    <b>Every spine width and height here is computed, not
                    drawn:</b> <code>bookHash</code> and
                    <code>BookJitter</code> are ported into this page and
                    checked by <code>_build/verify.sh</code> against the golden
                    values <code>test/book_geometry_test.dart</code> pins.
                    Switch proposals with <span class="kbd">v</span>, compare
                    two with <span class="kbd">&#8679;Enter</span>.
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
                    The spine, the four faces of the turn, and the measurement
                    tables behind both. The number worth arguing over is in
                    <b>Spine &middot; hashed</b>: the base height, which decides
                    whether <code>ReadPile.extent</code> stays at 169.
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
                    Two taps to the details page where there is one today, and
                    what happens when a second book is opened. Every step is a
                    real state from the Screens tab &mdash; the specs are shared
                    consts, so a corrected screen cannot leave a flow drawing
                    the old one. Red callouts are decisions that are genuinely
                    still open.
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
