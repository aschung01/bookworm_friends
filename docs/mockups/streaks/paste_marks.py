#!/usr/bin/env python3
"""Splice `_marks.js` into `index.html`, in place.

`gen_patch_marks.py` writes the dies to `_marks.js` and the record draws them
from arrays inlined in `index.html`. That last hop used to be a copy-paste, and
a copy-paste of nine arrays of data-URIs is not a step anyone will do twice
correctly: the first paw roll went in by hand and put 43kB of URI on the wrong
side of `PATCH_BRAND_MASK`, where the page still parsed and `d % 3` silently
indexed the disc dies.

So the hop is a script. It finds each `const PATCH_*_MASKS = [ ... ];` block in
the page and replaces it with the generated one, re-indented to the page's own
depth; arrays the page does not have yet are inserted before the brand mask,
which is the end of the die section. Running it with no regeneration in between
is a byte-for-byte no-op, which is the property that makes it safe to run.

    ../../.venv/bin/python docs/mockups/streaks/gen_patch_marks.py
    ../../.venv/bin/python docs/mockups/streaks/paste_marks.py
"""

import re
from pathlib import Path

HERE = Path(__file__).parent
PAGE = HERE / "index.html"
MARKS = HERE / "_marks.js"
# The page indents this section twelve spaces deep; the array's items sit four
# deeper. Read off the file rather than assumed, below, so a reformat of the
# page does not silently reflow 40kB of URIs.
FALLBACK_INDENT = " " * 12


def arrays(src):
    """Every `const NAME = [...];` in the generator's output, name -> items."""
    out = {}
    for m in re.finditer(r"const (\w+) = \[\n(.*?)\n\];", src, re.S):
        items = [
            line.strip().rstrip(",")
            for line in m.group(2).split("\n")
            if line.strip()
        ]
        out[m.group(1)] = items
    return out


def render(name, items, indent):
    inner = indent + "    "
    body = "\n".join(f"{inner}{it}," for it in items)
    return f"{indent}const {name} = [\n{body}\n{indent}];"


def main():
    page = PAGE.read_text()
    generated = arrays(MARKS.read_text())
    if not generated:
        raise SystemExit("no arrays in _marks.js -- run gen_patch_marks.py first")

    anchor = re.search(r"^([ \t]*)const PATCH_BRAND_MASK", page, re.M)
    if not anchor:
        raise SystemExit("PATCH_BRAND_MASK not found -- where is the die section?")
    indent = anchor.group(1) or FALLBACK_INDENT

    replaced, added = [], []
    for name, items in generated.items():
        block = re.compile(
            r"^[ \t]*const " + name + r" = \[\n.*?^[ \t]*\];", re.S | re.M
        )
        new = render(name, items, indent)
        if block.search(page):
            # `\g<0>`-free: the URIs are full of backslash-free but regex-hot
            # characters, so substitute with a function rather than a template.
            page = block.sub(lambda _m, new=new: new, page, count=1)
            replaced.append(name)
        else:
            page = page[: anchor.start()] + new + "\n" + page[anchor.start() :]
            anchor = re.search(r"^([ \t]*)const PATCH_BRAND_MASK", page, re.M)
            added.append(name)

    PAGE.write_text(page)
    print(f"replaced {len(replaced)}: {', '.join(replaced) or '-'}")
    print(f"added    {len(added)}: {', '.join(added) or '-'}")


if __name__ == "__main__":
    main()
