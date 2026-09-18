"""Falsifiability check: each mutation below MUST turn verify.py red, and the
file is restored whether or not it does. A green suite proves nothing unless
the assertions can fail.

Mutations are matched by REGEX on distinctive content, never by multi-line
blocks with baked-in indentation — anchoring on leading whitespace broke three
of these the first time the data was reformatted, which is the same lesson
recorded in AGENTS.md about the streaks checks.

    python3 docs/mockups/page-progress/falsify.py

The page is a single self-contained file, edited directly — same convention as
docs/mockups/streaks/. It was originally assembled from the design-mockups
shell by a splice script, which has been removed on purpose: keeping the parts
around would have made index.html a generated file that a later splice run
could silently revert.
"""

import pathlib
import re
import subprocess
import sys

SRC = pathlib.Path("docs/mockups/page-progress/index.html")
VERIFY = "docs/mockups/page-progress/verify.py"
original = SRC.read_text()

# (label, pattern, replacement, expected substring in verify's output)
MUTATIONS = [
    (
        "rider height drifts from the code",
        re.compile(r"height: calc\(36 \* var\(--pt\)\);"),
        "height: calc(35 * var(--pt));",
        "rider height = 36",
    ),
    (
        "a stale secondaryText creeps back in",
        re.compile(r"--text2: #626a72;"),
        "--text2: #adb5bd;",
        "stale #ADB5BD",
    ),
    (
        "the column label starts claiming to be a unit in the row",
        re.compile(r'<div class="collabel">'),
        '<div class="unit collabel">',
        "page-bare really is a bare numeral",
    ),
    (
        "an OPEN callout points at nothing",
        # Must target a CURRENT key: this mutation previously pointed at
        # "page-figure", which stopped being an open decision.
        re.compile(r'"row-progress":'),
        '"row-progres":',
        "every OPEN callout attaches to a real id",
    ),
    (
        "the no-op screen stops showing the walked-back page",
        # The SECOND rider that prints RT200 is the no-op screen's; the first
        # belongs to `today`. Anchor on the id so the right one is hit.
        re.compile(r'("noop",.*?v: `&#8776; p\.)\$\{RT200\}', re.S),
        r"\g<1>200",
        "the no-op screen shows the page it silently walks back to",
    ),
    (
        "the page wheel loses its clamp and draws p.0 and below",
        re.compile(r"if \(v < 1 \|\| \(total && v > total\)\) return \"\";"),
        'if (false) return "";',
        "no wheel row draws a negative or malformed number",
    ),
    (
        "the wheel loses its zero-width guard",
        re.compile(r"min-width: calc\(160 \* var\(--pt\)\);"),
        "min-width: 0;",
        "",  # not asserted by verify.py — see the note printed below
    ),
]

bad = []
notcaught = []
try:
    for label, pat, repl, expect in MUTATIONS:
        found = len(pat.findall(original))
        if found != 1:
            print(f"  SKIP  {label}   [pattern matches {found}x, not 1]")
            bad.append(label + " (pattern)")
            continue
        SRC.write_text(pat.sub(repl, original, count=1))
        r = subprocess.run(
            [sys.executable, VERIFY], capture_output=True, text=True
        )
        failed = r.returncode != 0
        named = (expect in r.stdout) if expect else True
        if not expect:
            # Deliberate control: a mutation the terminal checks CANNOT see.
            print(
                ("  ok   " if not failed else "  huh  ")
                + label
                + "   [expected to slip past verify.py — visual only]"
            )
            if failed:
                notcaught.append(label)
            continue
        print(
            ("  ok   " if (failed and named) else "  BAD  ")
            + label
            + ("" if failed else "   [verify stayed GREEN]")
            + ("" if named else f"   [no assertion mentioned {expect!r}]")
        )
        if not (failed and named):
            bad.append(label)
finally:
    SRC.write_text(original)
    print("\nrestored:", "clean" if SRC.read_text() == original else "MISMATCH")

r = subprocess.run([sys.executable, VERIFY], capture_output=True, text=True)
print("verify on the restored file:", "OK" if r.returncode == 0 else "FAILING")
if r.returncode != 0:
    bad.append("restored file does not verify")

print(
    "\nNOTE  the last mutation is a control: removing the wheel's min-width\n"
    "      collapses every element demo to an empty box, and no terminal check\n"
    "      notices. That defect was real, and only opening the page caught it."
)

if bad:
    print("\nNOT FALSIFIABLE (%d): %s" % (len(bad), "; ".join(bad)))
    sys.exit(1)
print("\nFALSIFY OK — every asserted mutation was caught")
