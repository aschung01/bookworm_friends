#!/usr/bin/env python3
"""Splice the store-links sections into a copy of the mockup shell.

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
# The start anchor deliberately includes the comment's OPENING line, so that
# _build/data.js owns both ends of its own block comment and is therefore a
# syntactically valid standalone .js file. Anchoring after the opener (which
# is what the praise-region build does) leaves data.js beginning with bare
# prose and a stray `*/`, and an editor's TS server reports ~90 phantom
# syntax errors on it. The spliced output is byte-identical either way.
#
# The two-line form is load-bearing: the `/* ===` opener alone appears before
# every section, and str.find would match SECTION 1a's.
src = cut(
    src,
    "            /* ==================================================================\n"
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
    "<title>Where to read this &mdash; three homes for a store link</title>",
)
src = src.replace(
    ">PRODUCT &mdash; <span>design mockups</span></span",
    ">Libstack &mdash; <span>where to read this</span></span",
)

LEAD_SCREENS = """                <h1>Where to read this &mdash; three homes for a store link</h1>
                <p class="lead">
                    Opening a book in Kindle, Apple Books, Play Books or Libby
                    from the details page, drawn at
                    <b>1px&nbsp;=&nbsp;1pt</b> on a 393pt frame, cropped from
                    the back button down into the Book info tab &mdash; the
                    control competes with the hero for prominence and with the
                    description for space, so neither can be left out. Three
                    versions put it in three places:
                    <code>tab-section</code> (recommended),
                    <code>hero-row</code> and <code>bar-sheet</code>. Switch
                    with <span class="kbd">v</span>, compare two with
                    <span class="kbd">&#8679;Enter</span>.
                </p>
                <p class="lead">
                    Colours are <code>AppColors.light</code> verbatim &mdash;
                    <code>surfaceVariant #E9ECEF</code> for the hero,
                    <code>surface #FFFFFF</code> for the tab body,
                    <code>brandFill #067657</code> for the primary action,
                    <code>sheetBackground #EFF5EF</code> for sheets. Note
                    <code>secondaryText #626A72</code>: this frame is forked
                    from <code>docs/mockups/praise-region</code>, which still
                    carries the old <code>#ADB5BD</code> at 2.07:1, and the
                    store rows put real information on that token. Type is
                    <code>AppTextStyles</code> &mdash; headings
                    <code>subtitle</code> 17/w600/&minus;0.2 (the same token
                    the tab's own <i>Book description</i> and <i>Publisher</i>
                    headings use, so the section reads as their peer),
                    <code>body</code> 15/1.4, <code>label</code> 13/w600. The
                    cover is 120&times;180 from
                    <code>kDefaultCoverAspect</code> 2/3, the shelf 8pt with
                    <code>offset(0,2) blur 2 black@25%</code>, the tab body
                    <code>EdgeInsets.all(24)</code>, sheets
                    <code>kSheetCornerRadius</code> 24. The
                    <i>Interested</i> badge is unfilled with a 55% border,
                    which is what <code>book_status_badge.dart</code> ships
                    today.
                </p>
                <p class="lead">
                    <b>What the drawings settle.</b> A store row's second line
                    is load-bearing, not decoration: it is the only place
                    Kindle can admit it leads to a search results page rather
                    than to the book, because Amazon publishes no per-book deep
                    link. That single fact rules out the chips layout as a
                    default and rules out any design that shows the four stores
                    as interchangeable. It also explains the remembered state
                    &mdash; once the reader has told us where their copy lives,
                    &ldquo;launch the app&rdquo; is finally an honest promise
                    instead of a guess about ownership.
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
                    The parts the three versions are assembled from, and the two
                    decisions still open. The brand-mark discs are crude
                    stand-ins on purpose: embedding real Amazon, Apple or Google
                    marks in a mockup would be a licensing question and a claim
                    to have checked three sets of brand guidelines.
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
                    Acquiring, opening, changing a wrong guess, and finding what
                    a friend read. Every step is a real state from the Screens
                    tab, so a version cannot have its screens corrected and its
                    flows left stale. One step is deliberately undrawable and
                    says so: once the reader leaves for Kindle, the app is gone.
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
