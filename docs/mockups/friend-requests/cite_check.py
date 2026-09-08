"""Assert every `file.dart:line` / `file.sql:line` citation on the page is real.

A citation that names a missing file, or a line past the end of one, is worse
than no citation: it reads as authority. Run after every edit.

    python3 docs/mockups/friend-requests/cite_check.py
    python3 docs/mockups/friend-requests/cite_check.py --show

KNOWN LIMIT, and it has already bitten once. This validates that a cited line
EXISTS, not that it means what the prose claims. `home_page.dart:784` survived
this checker while pointing at a `Padding` in an unrelated widget, because the
file is long enough for line 784 to be real. Range checking cannot catch drift.

`--show` is the mitigation: it prints what is actually at each cited line, which
turns silent staleness into something a reader can scan. It also flags lines that
are blank or pure punctuation, since a citation landing on `);` is almost always
a line number that has moved.
"""

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
PAGE = os.path.join(ROOT, "docs", "mockups", "friend-requests", "index.html")

html = open(PAGE, encoding="utf-8").read()

# `path/to/file.ext:123` or `file.ext:12-34`, inside <code> or bare.
CITE = re.compile(
    r"([A-Za-z0-9_./-]+\.(?:dart|sql|ts|yaml|yml|json|kt|swift|plist)):(\d+)(?:-(\d+))?"
)

# Cache of basename -> candidate paths, so bare filenames resolve.
index = {}
SKIP = {".git", "build", ".dart_tool", "node_modules", ".tmp-verify", "ios/Pods"}
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".tmp")]
    for fn in filenames:
        index.setdefault(fn, []).append(os.path.join(dirpath, fn))


def lines_in(path):
    with open(path, "rb") as f:
        return sum(1 for _ in f)


seen, bad, okc = set(), [], 0
suspicious = []
show = "--show" in sys.argv
rows = []


def line_at(path, n):
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f, 1):
            if i == n:
                return line.rstrip()
    return ""


for m in CITE.finditer(html):
    ref, lo, hi = m.group(1), int(m.group(2)), m.group(3)
    hi = int(hi) if hi else lo
    key = (ref, lo, hi)
    if key in seen:
        continue
    seen.add(key)

    # Resolve: try as a repo-relative path, then by basename.
    direct = os.path.join(ROOT, ref)
    if os.path.isfile(direct):
        cands = [direct]
    else:
        cands = [p for p in index.get(os.path.basename(ref), []) if p.endswith(ref.replace("./", ""))]
        if not cands:
            cands = index.get(os.path.basename(ref), [])

    if not cands:
        bad.append(f"{ref}:{lo} -> no such file anywhere in the tree")
        continue
    if len(cands) > 1:
        rels = sorted(os.path.relpath(c, ROOT) for c in cands)
        bad.append(f"{ref}:{lo} -> ambiguous, matches {len(cands)}: {', '.join(rels[:4])}")
        continue

    n = lines_in(cands[0])
    if hi > n:
        bad.append(f"{ref}:{lo}{'-' + str(hi) if hi != lo else ''} -> file has only {n} lines")
        continue

    okc += 1
    text = line_at(cands[0], lo)
    rows.append((f"{ref}:{lo}", text.strip()))
    # A citation landing on a closing bracket, a blank line or a bare comment
    # marker is nearly always a number that has moved out from under the prose.
    stripped = text.strip()
    if not stripped or stripped in {");", "}", "};", ")", "],", "});", "/**", "*/", "//"}:
        suspicious.append(f"{ref}:{lo} -> {stripped!r}")

print(f"citations checked: {len(seen)}  ok: {okc}  bad: {len(bad)}")
for b in bad:
    print("  x " + b)
if suspicious:
    print(f"\nsuspicious ({len(suspicious)}) — cited line is blank or pure punctuation:")
    for s in suspicious:
        print("  ? " + s)
if show:
    print("\nwhat is at each cited line (range checking cannot verify meaning):")
    for ref, text in sorted(rows):
        print(f"  {ref:<46} {text[:96]}")
sys.exit(1 if bad else 0)
