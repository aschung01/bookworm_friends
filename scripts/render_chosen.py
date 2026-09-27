#!/usr/bin/env python3
"""Render the chosen ladder -- the actual day, assembled from a submission.

    .venv/bin/python scripts/render_chosen.py

Reads `docs/mockups/streak-widget/_submissions/latest.json` and draws the eight tiles a
reader would really see, in order, on the real ground. Everything else on the grid page is
a comparison; this is the only view that shows the decision as a *sequence*, which is the
one thing a matrix cannot show and the thing a day-long escalation has to be judged as.

Why a separate script rather than another sheet on the grid page: the grid is generated
from index.html and knows nothing about submissions, and wiring a submission back into it
would make the comparison page depend on a particular answer to the comparison. This reads
both and joins them, so neither has to know about the other.

Output: docs/mockups/streak-widget/_chosen.html
"""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import build_widget_grid as bwg  # noqa: E402  -- after the path insert, necessarily

SUB = pathlib.Path("docs/mockups/streak-widget/_submissions/latest.json")
OUT = pathlib.Path("docs/mockups/streak-widget/_chosen.html")

# The eight slots, in the order a day runs through them. `none` and `done` are not hours;
# they are the two states that replace the whole day, so they sit apart at the end.
ORDER = ["dawn", "morning", "afternoon", "evening", "late", "final"]
APART = ["none", "done"]

# Moves read out of the submission's free-text note, encoded here rather than parsed.
#
# The note said: "P-morning for afternoon (with m05-puddle)". A note is prose and prose is
# not a schema, so rather than pattern-match English this states the interpretation as data
# where it can be seen and contradicted. If this is the wrong reading of the note, it is
# wrong in one visible line instead of invisibly inside a regex.
MOVES = {"P-morning": "afternoon"}


def flame_for(data: dict, state: str) -> str:
    return data["flameLit"] if state == "done" else data["flameUnlit"]


def run_for(state: str) -> int:
    # Matches mxSpec: recorded shows the incremented run, no-run shows zero.
    return 4 if state == "done" else 0 if state == "none" else 3


def tile(data: dict, style: str, state: str, pose: str, line: str) -> str:
    lit = state == "done"
    cls = "fr hascat" + (" hasline" if line else "")
    line_html = f'<div class="line">{esc(line)}</div>' if line else ""
    return (
        f'<div class="{cls}" style="{style}">'
        f'<div class="cat"><img src="cats/{pose}.png" alt=""></div>'
        f'<div class="runrow{"" if lit else " glass"}">{flame_for(data, state)}'
        f'<span class="fig{" recorded" if lit else ""}">{run_for(state)}</span></div>'
        f"{line_html}"
        '<div class="grow"></div>'
        "</div>"
    )


def esc(s: str) -> str:
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def assemble(sub: dict) -> tuple[dict, list[str]]:
    """Submission -> {slot: pick}, plus whatever is still unfilled."""
    slots: dict[str, dict] = {}
    clashes = []
    for pick in sub.get("posePicks") or []:
        slot = MOVES.get(pick["label"], pick["state"])
        if slot in slots:
            clashes.append(f"{pick['label']} and {slots[slot]['label']} both claim {slot}")
        slots[slot] = pick
    missing = [s for s in ORDER + APART if s not in slots]
    return slots, missing + clashes


def build(data: dict, grain: str, faces: str, slots: dict, sub: dict) -> str:
    style = {t["key"]: t["style"] for t in data["tiers"]}
    style["none"] = data["none"]
    style["done"] = data["done"]

    def row(states: list[str]) -> str:
        out = []
        for s in states:
            p = slots.get(s)
            if not p:
                out.append(
                    f'<td class="cell"><div class="hole">{s}<br><span>nothing '
                    f"picked</span></div></td>"
                )
                continue
            flags = []
            if p.get("reposed"):
                flags.append('<span class="flag repose">reposed</span>')
            if MOVES.get(p["label"]):
                flags.append(f'<span class="flag moved">moved from {p["state"]}</span>')
            out.append(
                f'<td class="cell">{tile(data, style[s], s, p["pose"], p.get("text") or "")}'
                f'<span class="tag">{p["label"]}</span>'
                f'<span class="meta">{p["voice"]}<br>{p["pose"]}</span>'
                f'{"".join(flags)}</td>'
            )
        return "".join(out)

    heads = "".join(f"<th>{s}</th>" for s in ORDER)
    heads_apart = "".join(f"<th>{s}</th>" for s in APART)

    # The voice sequence, which is the thing this view exists to expose: the picks are not
    # one voice, they are a walk through four, and a walk only reads as an escalation or a
    # mess when it is seen in order.
    walk = " &rarr; ".join(
        f'<b>{slots[s]["voice"]}</b>' if s in slots else "?" for s in ORDER
    )
    poses = [slots[s]["pose"] for s in ORDER if s in slots]
    distinct = len(set(poses)) == len(poses)

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>The chosen ladder</title>
<style>
  {faces}
  :root {{ color-scheme: dark; }}
  body {{ margin: 0; padding: 22px 20px 40px; background: #23292e; color: #e8edf2;
         font: 13px/1.45 ui-sans-serif, -apple-system, sans-serif; }}
  h1 {{ font-size: 15px; letter-spacing: .06em; text-transform: uppercase; margin: 0 0 6px; }}
  h2 {{ font-size: 12px; letter-spacing: .06em; text-transform: uppercase; color: #9fb0bd;
        margin: 26px 0 0; }}
  p {{ margin: 0 0 14px; color: #9fb0bd; max-width: 112ch; }}
  p b {{ color: #e8edf2; }}
  code {{ color: #cbd6df; }}
  table {{ border-collapse: separate; border-spacing: 10px; }}
  th {{ font-size: 11px; font-weight: 600; color: #9fb0bd; text-align: left;
        vertical-align: bottom; padding: 0 0 2px; }}
  .cell {{ width: 158px; vertical-align: top; }}
  .tag {{ display: block; margin: 6px 0 0;
         font: 600 11px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace; color: #7ee2b8; }}
  .meta {{ display: block; margin-top: 2px; font-size: 10.5px; line-height: 1.35; color: #8fa3b2; }}
  .flag {{ display: inline-block; margin-top: 4px; padding: 1px 6px; border-radius: 999px;
          font-size: 10px; font-weight: 600; }}
  .flag.repose {{ background: #43301a; color: #f4dcb4; border: 1px solid #8a6535; }}
  .flag.moved {{ background: #1d3340; color: #a8d8ef; border: 1px solid #3b6b85; }}
  .hole {{ width: 158px; height: 158px; border-radius: 22px; border: 2px dashed #56616b;
          display: flex; flex-direction: column; align-items: center; justify-content: center;
          color: #7f909d; font-size: 12px; text-align: center; }}
  .hole span {{ font-size: 10.5px; }}

  /* index.html's tile geometry, copied rule for rule -- same reason as the grid builder. */
  .fr {{ --tile: #ffffff; --ink: #212529; --dim: #626a72; --div: #e9ecef;
        --flame: #f2a93f; --core: #ffd479;
        {grain}
        width: 158px; height: 158px; border-radius: 22px; background: var(--tile);
        padding: 14px; box-sizing: border-box; position: relative; overflow: hidden;
        display: flex; flex-direction: column;
        box-shadow: 0 1px 2px rgba(0,0,0,.2), 0 10px 24px rgba(0,0,0,.18);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }}
  .cat {{ position: absolute; left: 0; right: 0; bottom: -8%; height: 70%;
         display: flex; align-items: flex-end; justify-content: center; z-index: 0; }}
  .cat img {{ height: 100%; width: auto; display: block; }}
  .fr.hascat.hasline .cat {{ justify-content: flex-end; right: -6%; }}
  .fr.hascat.hasline .line {{ max-width: 52%; }}
  .fr .runrow, .fr .line {{ position: relative; z-index: 1; }}
  .runrow {{ display: flex; align-items: center; gap: 8px; }}
  .runrow.glass {{ opacity: .5; }}
  .fig {{ font-family: "Nunito", ui-rounded, -apple-system, sans-serif; font-weight: 800;
         color: var(--ink); letter-spacing: -.5px; font-size: 40px; line-height: 1; }}
  .fig.recorded {{ font-family: "Nunito", ui-rounded, cursive; font-weight: 900;
                  letter-spacing: normal; color: #fff;
                  -webkit-text-stroke: 6px var(--flame); paint-order: stroke fill; }}
  .line {{ font-size: 11px; font-style: italic; color: var(--dim); line-height: 1.25;
          margin-top: 3px; }}
  .grow {{ flex: 1; }}
</style>
</head>
<body>
<h1>The chosen ladder</h1>
<p>
  The eight tiles as actually picked, in the order a day runs through them. Assembled from
  <code>_submissions/latest.json</code> by <code>scripts/render_chosen.py</code>; the tile
  geometry and the ground are index.html's own. Green label = the card that was ticked,
  amber = its pose was swapped off the proposal, blue = the card was moved to a different
  hour than the one it was shown at.
</p>
<p>
  <b>Voice walk:</b> {walk}. <b>Poses distinct across the open day:</b>
  {"yes" if distinct else "NO &mdash; " + ", ".join(poses)}.
</p>

<h2>The day</h2>
<table><tr>{heads}</tr><tr>{row(ORDER)}</tr></table>

<h2>The two states that replace the day</h2>
<table><tr>{heads_apart}</tr><tr>{row(APART)}</tr></table>

<h2 id="note">The note, as read</h2>
<p><code>{esc(sub.get("notes") or "").strip()}</code> &rarr; applied as
  {", ".join(f"<code>{k}</code> &rarr; <b>{v}</b>" for k, v in MOVES.items()) or "nothing"}.
</p>
</body>
</html>
"""


def main() -> int:
    if not SUB.exists():
        sys.exit(f"no submission at {SUB} -- submit from the grid page first")
    sub = json.loads(SUB.read_text())
    html = bwg.SRC.read_text()
    data = bwg.run_node(bwg.extract_script(html))
    slots, problems = assemble(sub)
    OUT.write_text(
        build(data, bwg.extract_grain(html), bwg.extract_font_faces(html), slots, sub)
    )

    print(f"{OUT}")
    for s in ORDER + APART:
        p = slots.get(s)
        if not p:
            print(f"  {s:<10} -- EMPTY")
            continue
        flags = []
        if p.get("reposed"):
            flags.append("reposed")
        if MOVES.get(p["label"]):
            flags.append(f"moved from {p['state']}")
        note = f"  [{', '.join(flags)}]" if flags else ""
        print(f"  {s:<10} {p['label']:<10} {p['voice']:<10} {p['pose']:<12} "
              f"{p.get('text') or '--'!r}{note}")

    poses = [slots[s]["pose"] for s in ORDER if s in slots]
    print(f"\ndistinct open poses: {len(set(poses))}/{len(poses)}")
    voices = sorted({slots[s]["voice"] for s in slots})
    print(f"voices used: {', '.join(voices)}")
    # The constraint this submission crosses, named rather than silently accepted. See the
    # note in COPY_SETS: the puddle is 145px wide in a 158px tile and overlaps the copy
    # column, which is why every ladder proposed here kept it on `done` alone.
    for s, p in slots.items():
        if p["pose"] == "m05-puddle" and (p.get("text") or "").strip():
            print(f"\nWARNING: m05-puddle on {s}, which carries copy "
                  f"({p['text']!r}) -- measure the overlap before accepting")
    for problem in problems:
        print(f"PROBLEM: {problem}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
