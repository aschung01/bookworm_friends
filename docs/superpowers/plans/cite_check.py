"""Assert every `file.ext:line` cited by a spec or plan names a real, in-range line.

The mockup page has had this since a citation pointed at an unrelated `Padding`
for a whole session. The spec and plan cite far more line numbers than the
drawings do, at files this very plan edits, so they need it more.

    python3 docs/superpowers/plans/cite_check.py           # all 2026-08-28-* docs
    python3 docs/superpowers/plans/cite_check.py --show     # print each cited line

Same known limit as the mockup checker: this proves a line EXISTS, not that it
means what the prose claims. `--show` is the mitigation — read the output.
"""

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
DOCS = [
    "docs/superpowers/specs/2026-08-28-friends-invites-design.md",
    "docs/superpowers/plans/2026-08-28-friends-invites-plan.md",
    "docs/superpowers/specs/2026-09-08-shelf-density-design.md",
    "docs/superpowers/plans/2026-09-08-shelf-density-plan.md",
]

CITE = re.compile(
    r"([A-Za-z0-9_./-]+\.(?:dart|sql|ts|arb|yaml|yml|json|plist|xml|gradle)):(\d+)(?:[-,]\s*(\d+))?"
)

SKIP = {".git", "build", ".dart_tool", "node_modules", "Pods", ".symlinks"}
index = {}
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".tmp")]
    for fn in filenames:
        index.setdefault(fn, []).append(os.path.join(dirpath, fn))


def resolve(ref):
    direct = os.path.join(ROOT, ref)
    if os.path.isfile(direct):
        return [direct]
    base = os.path.basename(ref)
    cands = [p for p in index.get(base, []) if p.endswith(ref)]
    return cands or index.get(base, [])


def lines_of(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read().split("\n")


show = "--show" in sys.argv
total_bad = 0

for doc in DOCS:
    path = os.path.join(ROOT, doc)
    if not os.path.isfile(path):
        print(f"!! missing: {doc}")
        total_bad += 1
        continue

    text = open(path, encoding="utf-8").read()
    # Ignore fenced code blocks: a migration filename being *created* is not a
    # citation, and `20260828120000_friendships.sql` does not exist yet.
    text = re.sub(r"```.*?```", "", text, flags=re.S)

    seen, bad, rows, suspicious = set(), [], [], []
    for m in CITE.finditer(text):
        ref, lo = m.group(1), int(m.group(2))
        hi = int(m.group(3)) if m.group(3) else lo
        if (ref, lo, hi) in seen:
            continue
        seen.add((ref, lo, hi))

        cands = resolve(ref)
        if not cands:
            # A file this plan creates cannot be cited yet; flag only if it
            # looks like an existing-code reference.
            bad.append(f"{ref}:{lo} -> no such file")
            continue
        if len(cands) > 1:
            rels = sorted(os.path.relpath(c, ROOT) for c in cands)
            bad.append(f"{ref}:{lo} -> ambiguous ({len(cands)}): {', '.join(rels[:3])}")
            continue

        src = lines_of(cands[0])
        if hi > len(src):
            bad.append(f"{ref}:{lo}-{hi} -> file has {len(src)} lines")
            continue

        body = src[lo - 1].strip()
        rows.append((f"{ref}:{lo}" + (f"-{hi}" if hi != lo else ""), body))
        if not body or body in {");", "}", "};", ")", "],", "});", "//", "/**", "*/", "*"}:
            suspicious.append(f"{ref}:{lo} -> {body!r}")

    name = os.path.basename(doc)
    print(f"{name}: {len(seen)} citations, {len(seen) - len(bad)} ok, {len(bad)} bad")
    for b in bad:
        print("  x " + b)
    for s in suspicious:
        print("  ? " + s + "  (blank or punctuation — likely drifted)")
    if show:
        for ref, body in sorted(rows):
            print(f"    {ref:<44} {body[:88]}")
    total_bad += len(bad)

sys.exit(1 if total_bad else 0)
