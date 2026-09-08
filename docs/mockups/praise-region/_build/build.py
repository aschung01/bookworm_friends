#!/usr/bin/env python3
"""Splice the praise-region sections into a copy of the mockup shell.

Rebuilding from the pristine shell each time is deliberate: it keeps
SECTION 5 (the engine) byte-identical to the skill's version, so none of
the interaction bugs documented in reference/pitfalls.md can be
reintroduced by hand-editing a 2,600-line file. `verify.sh` asserts that
identity, so the guarantee is checked rather than hoped for.

    python3 _build/build.py && sh _build/verify.sh
"""
import pathlib
import re
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
# SECTION 2 lives in the <script> after the body, so anchoring there deleted
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
    "<title>Reactions on a book &mdash; seven directions</title>",
)
src = src.replace(
    ">PRODUCT &mdash; <span>design mockups</span></span",
    ">\uc9c4\ubc85\ub808 \uce5c\uad6c\ub4e4 &mdash; <span>reactions on a book</span></span",
)

LEAD_SCREENS = """                <h1>Reactions on a book &mdash; seven directions</h1>
                <p class="lead">
                    Every situation the reaction controls can be in, drawn at
                    <b>1px&nbsp;=&nbsp;1pt</b> on a 393pt frame, cropped to the
                    book-details hero because that is the unit under review:
                    the button and the record share a corner with the status
                    badge, the shelf label and the shelf. Three live directions
                    on one branch (<code>stack</code> &rarr;
                    <code>stack-status</code> &rarr; <code>stack-tint</code>,
                    each adding one decision) and three marked <i>rejected</i>,
                    kept browsable because of what they turned up. Colours are
                    <code>AppColors.light</code> verbatim &mdash;
                    <code>surfaceVariant #E9ECEF</code> for the hero,
                    <code>brandFill #067657</code> for the button,
                    <code>brand #09BC8A</code> at 30% for a chip's hairline. The
                    cover is 120&times;180 from <code>kDefaultCoverAspect</code>
                    2/3, the shelf 8pt with
                    <code>offset(0,2) blur 2 black@25%</code>, the badge
                    <code>h10/v4 radius 10</code>, the shelf label top-radius-3
                    only. The right column is 217pt: 393 less 40pt padding, the
                    cover and the 16pt gap. Switch direction with
                    <span class="kbd">v</span>, compare two with
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
                    The parts each direction is assembled from, and the corner
                    they have to live in. Real metrics; the emoji sheet's grid is
                    the one approximation on this page, because its columns and
                    category chrome belong to
                    <code>awesome_emoji_picker</code>.
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
                    Leaving, changing, withdrawing and receiving a reaction,
                    plus the two routes that only exist once the record is
                    capped. Every step is a real state from the Screens tab, so
                    a direction cannot have its screens corrected and its flows
                    left stale.
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
