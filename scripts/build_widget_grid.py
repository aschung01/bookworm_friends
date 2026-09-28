#!/usr/bin/env python3
"""Build the full widget-graphics grid from index.html's own data.

    .venv/bin/python scripts/build_widget_grid.py

Why generate rather than hand-write: the grid crosses three axes that all live in
index.html already -- the ground ramp, the copy sets and the expression mapping --
and a hand-copied sheet would drift from the page the moment either changed. So this
extracts the page's script, runs it under the same DOM stub verify.py uses, and calls
`groundVars` directly. The backgrounds in the output are therefore byte-identical to
what the real tiles render: the mesh, the 0.3 blob alpha, the vignette, the grain
reference, all of it.

The same argument applies to the tile itself, and the first cut of this script got it
wrong by not applying it. It hand-wrote the tile CSS from memory, centred the cat, and
every row came back with the copy printed across the cat's face -- a layout the real
page does not have, because `.fr.hascat.hasline` already moves the character to the
right and caps the line to the column it leaves. So the geometry below is copied from
index.html rule for rule, the flame comes from the page's own `flame()` via the node
dump, and the @font-face blocks are lifted out of the stylesheet verbatim. If a tile
here looks wrong, it is wrong on the real page too.

Output: docs/mockups/streak-widget/_widget_grid.html
  rows    = the eight states a tile can be in (six copy tiers, recorded, no run)
  columns = the eight expression cut-outs
  switch  = the eight copy voices, which is the third axis
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
import tempfile

SRC = pathlib.Path("docs/mockups/streak-widget/index.html")
OUT = pathlib.Path("docs/mockups/streak-widget/_widget_grid.html")
CATS = pathlib.Path("docs/mockups/streak-widget/cats")

# The same minimal DOM stub verify.py uses, so the page's top-level code can run.
STUB = """
const mk = () => ({ _v:"", set innerHTML(v){this._v=v;}, get innerHTML(){return this._v;},
  textContent:"", hidden:false, value:"", placeholder:"", dataset:{}, style:{},
  classList:{toggle(){},add(){},remove(){},contains(){return false;}},
  addEventListener(){}, focus(){}, blur(){}, select(){}, contains(){return false;},
  querySelectorAll(){return [];}, querySelector(){return null;}, closest(){return null;},
  getBoundingClientRect(){return {top:0};}, scrollIntoView(){},
  nextElementSibling:null, tagName:"DIV" });
global.document = { getElementById:()=>mk(), querySelectorAll:()=>[], addEventListener(){},
  body:{scrollHeight:1000}, activeElement:null, querySelector:()=>mk() };
global.window = { addEventListener(){}, scrollTo(){}, innerHeight:800, scrollY:0 };
global.requestAnimationFrame = (f)=>f();
global.Event = class { constructor(t){ this.type=t; } };
"""

# Representative hour per tier: the first hour the tier covers, so the ground shown is
# the one that tier actually opens on.
DUMP = r"""
const HOUR = { dawn: 7, morning: 10, afternoon: 14, evening: 18, late: 21, final: 23 };
const payload = { tiers: [], voices: {}, ramp: RAMPS.stages.label, cutouts: CUTOUTS };
for (const [tier, hour] of Object.entries(HOUR)) {
  const g = rampAt("stages", hour);
  const ahead = rampAt("stages", hour + 3);
  payload.tiers.push({
    key: tier, hour,
    style: groundVars(g[0], g[1], false, ahead ? ahead[0] : undefined),
  });
}
payload.done = groundVars(RAMPS.stages.done[0], RAMPS.stages.done[1], true);
// The no-run tile borrows the 21:00 unrecorded ground, which is what mxSpec does.
{
  const g = rampAt("stages", 21);
  const ahead = rampAt("stages", 24);
  payload.none = groundVars(g[0], g[1], false, ahead ? ahead[0] : undefined);
}
const COPY_STATES = Object.keys(HOUR).concat(["none"]);
for (const [voice, set] of Object.entries(COPY_SETS)) {
  payload.voices[voice] = {
    code: set.code,
    label: set.label,
    gloss: set.gloss,
    poses: set.poses,
    // [label, text] pairs straight from the page's own copyVariants, so the labels on
    // the sheet are the labels verify.py asserts are unique.
    variants: Object.fromEntries(COPY_STATES.map((t) => [t, copyVariants(voice, t)])),
  };
}
// The page's own flame, at the size and core the streak layout uses (28px, knockout --
// which is what every version in index.html passes). Taken from `flame()` rather than
// redrawn, so the core's knock-out to var(--tile) is the real one.
payload.flameUnlit = flame(28, false, "knockout");
payload.flameLit = flame(28, true);
console.log("@@JSON@@" + JSON.stringify(payload));
"""


def extract_script(html: str) -> str:
    m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
    if not m:
        sys.exit("could not find the script block in index.html")
    return m.group(1)


def extract_grain(html: str) -> str:
    """Pull the --grain declaration out of the stylesheet verbatim."""
    m = re.search(r"(--grain:\s*url\(\"data:image/svg\+xml,.*?\"\);)", html, re.S)
    if not m:
        sys.exit("could not find the --grain declaration")
    return m.group(1)


def extract_font_faces(html: str) -> str:
    """Lift the @font-face blocks so the grid sets type in the page's own faces.

    Nunito is the one that matters -- it is the run figure, and without it the 40px
    number falls back to a system face and the tile stops looking like the tile."""
    blocks = re.findall(r"@font-face\s*\{.*?\}", html, re.S)
    if not blocks:
        sys.exit("could not find any @font-face blocks")
    return "\n  ".join(b.strip() for b in blocks)


def run_node(js: str) -> dict:
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as fh:
        fh.write(STUB + js + DUMP)
        path = fh.name
    proc = subprocess.run(["node", path], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit("node failed:\n" + proc.stderr[:2000])
    for line in proc.stdout.splitlines():
        if line.startswith("@@JSON@@"):
            return json.loads(line[len("@@JSON@@") :])
    sys.exit("no JSON payload in node output:\n" + proc.stdout[:1000])


STATE_NOTE = {
    "dawn": "07:00 &middot; the day opens",
    "morning": "10:00",
    "afternoon": "14:00",
    "evening": "18:00",
    "late": "21:00 &middot; the warning tier",
    "final": "23:00 &middot; last hour",
    "done": "recorded &middot; lit flame, no line",
    "none": "signed in, nothing recorded yet",
}


def build(data: dict, grain: str, faces: str, cats: list[str]) -> str:
    states = [(t["key"], t["style"]) for t in data["tiers"]]
    states.append(("none", data["none"]))
    # `done` is last and is kept out of the copy sheet entirely: it carries no line in any
    # voice, so it has nothing to compare and a column of three identical tiles per voice
    # would only dilute the sheet. It appears once, on the pose sheet.
    states.append(("done", data["done"]))

    rows = json.dumps(states)
    voices = json.dumps(data["voices"])
    cats_json = json.dumps(cats)

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Widget graphics &mdash; full grid</title>
<style>
  {faces}

  :root {{ color-scheme: dark; }}
  body {{ margin: 0; padding: 22px 20px 60px; background: #23292e; color: #e8edf2;
         font: 13px/1.45 ui-sans-serif, -apple-system, sans-serif; }}
  h1 {{ font-size: 15px; letter-spacing: .06em; text-transform: uppercase; margin: 0 0 4px; }}
  h2 {{ font-size: 13px; letter-spacing: .06em; text-transform: uppercase; color: #e8edf2;
        margin: 34px 0 0; padding-top: 18px; border-top: 1px solid #333c44; }}
  h2 small {{ text-transform: none; letter-spacing: 0; color: #7f909d; font-weight: 400;
              margin-left: 8px; }}
  p.lede {{ margin: 0 0 16px; color: #9fb0bd; max-width: 108ch; }}
  p.lede code {{ color: #cbd6df; }}
  .bar {{ display: flex; gap: 6px; flex-wrap: wrap; align-items: center;
          margin: 0 0 6px; padding: 10px 0; border-top: 1px solid #333c44; }}
  .bar span.lab {{ font-size: 11px; letter-spacing: .1em; text-transform: uppercase;
                   color: #7f909d; margin-right: 6px; }}
  button {{ font: inherit; font-size: 12px; padding: 5px 11px; border-radius: 999px;
            border: 1px solid #3d4750; background: #2b333a; color: #cbd6df; cursor: pointer; }}
  button.on {{ background: #e8edf2; color: #1d2328; border-color: #e8edf2; font-weight: 600; }}
  p.gloss {{ margin: 2px 0 18px; color: #7f909d; max-width: 108ch; font-size: 12px; }}

  table {{ border-collapse: separate; border-spacing: 10px; }}
  th {{ font-size: 11px; font-weight: 600; letter-spacing: .04em; color: #9fb0bd;
        text-align: left; vertical-align: bottom; padding: 0 0 2px; }}
  th.state {{ width: 148px; vertical-align: middle; }}
  th.state b {{ display: block; color: #e8edf2; font-size: 12.5px; }}
  th.state i {{ display: block; color: #7f909d; font-style: normal; font-size: 11px; margin-top: 2px; }}
  th.state em {{ display: block; color: #cbd6df; font-style: italic; font-size: 11.5px; margin-top: 5px; }}

  /* Everything below is index.html's own tile geometry, copied rule for rule. See the
     module docstring for why it is copied rather than approximated. */
  .fr {{ --tile: #ffffff; --ink: #212529; --dim: #626a72; --div: #e9ecef;
        --flame: #f2a93f; --core: #ffd479;
        {grain}
        width: 158px; height: 158px; border-radius: 22px; background: var(--tile);
        padding: 14px; box-sizing: border-box; position: relative; overflow: hidden;
        flex: 0 0 auto; display: flex; flex-direction: column;
        box-shadow: 0 1px 2px rgba(0,0,0,.2), 0 10px 24px rgba(0,0,0,.18);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }}
  .cat {{ position: absolute; left: 0; right: 0; bottom: -8%; height: 70%;
         display: flex; align-items: flex-end; justify-content: center;
         z-index: 0; pointer-events: none; }}
  .cat img {{ height: 100%; width: auto; display: block; }}
  /* The rule the first cut of this script was missing: with copy on the tile the
     character gives up the centre and the line is capped to what it leaves. */
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

  /* The label chip. This is the reason the sheet exists in this shape: a line can be
     chosen by naming `G-late-2` rather than by quoting it back, so the chip is as
     load-bearing as the tile it sits under. */
  .cell {{ width: 158px; vertical-align: top; }}
  .tag {{ display: flex; align-items: center; gap: 5px; margin: 5px 0 0;
         font: 600 10.5px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace;
         letter-spacing: .02em; color: #8fa3b2; cursor: pointer; }}
  .tag input {{ margin: 0; accent-color: #7ee2b8; cursor: pointer; }}
  .cell textarea {{ display: block; width: 158px; margin-top: 3px; box-sizing: border-box;
                   background: #1d2328; color: #cbd6df; border: 1px solid #3d4750;
                   border-radius: 6px; padding: 4px 5px; resize: vertical;
                   font: 10.5px/1.3 ui-sans-serif, -apple-system, sans-serif; }}
  .cell textarea:focus {{ outline: none; border-color: #7ee2b8; }}
  /* Picked and edited are separate signals and both need to be visible at a glance --
     a cell can be edited without being picked, which is a state worth seeing. */
  .cell.picked .fr {{ box-shadow: 0 0 0 3px #7ee2b8, 0 10px 24px rgba(0,0,0,.18); }}
  .cell.picked .tag {{ color: #7ee2b8; }}
  .cell.edited textarea {{ border-color: #e8b86b; color: #f4dcb4; }}
  .cell.edited .tag::after {{ content: "edited"; color: #e8b86b; font-weight: 400; }}
  th.vh {{ width: 148px; vertical-align: middle; }}
  th.vh b {{ display: block; color: #e8edf2; font-size: 12.5px; }}
  th.vh i {{ display: block; color: #7f909d; font-style: normal; font-size: 11px; margin-top: 2px; }}
  th.vh code {{ color: #e8edf2; font-size: 11px; }}
  .cell select {{ display: block; width: 158px; margin-top: 5px; box-sizing: border-box;
                 background: #1d2328; color: #cbd6df; border: 1px solid #3d4750;
                 border-radius: 6px; padding: 3px 4px;
                 font: 10.5px ui-monospace, SFMono-Regular, Menlo, monospace; }}
  .cell.repose select {{ border-color: #e8b86b; color: #f4dcb4; }}

  /* The submit bar. Fixed, because the sheet is ~6000px tall and a button at the bottom
     of that is a button nobody finds. */
  #bar2 {{ position: fixed; left: 0; right: 0; bottom: 0; z-index: 50;
          display: flex; gap: 12px; align-items: flex-start;
          padding: 10px 20px; background: #1a1f24; border-top: 1px solid #3d4750;
          box-shadow: 0 -8px 24px rgba(0,0,0,.4); }}
  #bar2 textarea {{ flex: 1; min-height: 34px; max-height: 90px; background: #23292e;
                   color: #e8edf2; border: 1px solid #3d4750; border-radius: 8px;
                   padding: 7px 9px; resize: vertical;
                   font: 12px/1.35 ui-sans-serif, -apple-system, sans-serif; }}
  #send {{ background: #7ee2b8; color: #10231c; border-color: #7ee2b8; font-weight: 700;
          padding: 9px 20px; white-space: nowrap; }}
  #send:disabled {{ opacity: .5; cursor: default; }}
  #tally {{ font-size: 11.5px; color: #9fb0bd; white-space: nowrap; align-self: center;
           min-width: 15ch; }}
  #tally b {{ color: #7ee2b8; }}
  #warn {{ margin: 0 0 14px; padding: 9px 12px; border-radius: 8px;
          background: #43301a; border: 1px solid #8a6535; color: #f4dcb4; font-size: 12px; }}
</style>
</head>
<body>
<h1>Widget graphics &mdash; full grid</h1>
<p class="lede">
  Four voices, on the live <code>stages</code> ground. <b>Sheet A</b> is the copy comparison:
  three labelled variants of every voice at every hour, with the pose held constant down each
  column so only the words change. <b>Sheet B</b> is the pairing &mdash; each voice's proposed
  pose ladder across the day, which is the answer to not wanting to pick a face per line.
  <b>Sheet C</b> keeps the character axis for the fur decision still outstanding.
  <b>Generated from index.html</b> by <code>scripts/build_widget_grid.py</code>, which runs the
  page's own script and calls <code>groundVars</code>, <code>flame</code> and
  <code>copyVariants</code>, and copies the tile geometry rule for rule &mdash; so these are the
  real tiles: mesh, 0.3 blob alpha, vignette, grain, the washed-back flame, and the character
  moved right to clear the copy. The fur is the provisional grey.
</p>
<p class="lede">
  <b>Every line has a label</b> of the form <code>&lt;voice&gt;-&lt;tier&gt;-&lt;variant&gt;</code>
  &mdash; <code>D</code> Duolingo cadence, <code>G</code> guilt, <code>P</code> pleads
  (desperate), <code>U</code> unhinged. Variant&nbsp;1 is always the line from the previous
  round, so nothing already judged has moved. <code>done</code> is absent from Sheet A on
  purpose: it carries no line in any voice.
</p>
<p class="lede">
  <b>Tick what you want and edit anything you want changed.</b> Typing in a box redraws the
  tile live and ticks it for you, so what you see is what gets submitted &mdash; no line is
  retyped anywhere between here and the answer. Selections survive a reload. On Sheet B
  every card is its own checkbox &mdash; ticking one picks that voice at that hour
  specifically, never a whole row &mdash; and its dropdown swaps the pose, so the ladder is
  a proposal you can overrule one face at a time. Press <b>Submit</b> at the bottom when
  you are done.
</p>
<div id="warn" hidden></div>

<h2>Sheet A &mdash; the copy <small>3 variants &times; 7 states, per voice</small></h2>
<div id="copy"></div>

<h2 id="sheetB">Sheet B &mdash; the pairing <small>each voice's proposed pose ladder</small></h2>
<p class="gloss">
  One row per voice at variant&nbsp;1, so the ladder is readable as a sequence. Tick a card
  to pick it &mdash; that voice, at that hour, nothing else in the row. The six open poses
  are distinct within every voice &mdash; the mapping this replaces used
  <code>m03-reading</code> for four consecutive tiers, so two thirds of the day differed only
  in its ground. <code>m05-puddle</code> appears nowhere but <code>done</code>: at 145px wide
  it overlaps the copy column by 59.5px, where every other cut-out stays under 10px.
</p>
<div id="poses"></div>

<h2>Sheet C &mdash; character axis <small>states &times; every cut-out, one voice at a time</small></h2>
<div class="bar" id="bar"><span class="lab">voice</span></div>
<p class="gloss" id="gloss"></p>
<div id="grid"></div>

<div id="bar2">
  <span id="tally"></span>
  <textarea id="notes" placeholder="Anything else — a line you want written differently, a pose that is wrong, a voice to drop entirely."></textarea>
  <button id="send">Submit</button>
</div>

<script>
const ROWS = {rows};
const VOICES = {voices};
const CATS = {cats_json};
const NOTE = {json.dumps(STATE_NOTE)};
const FLAME_UNLIT = {json.dumps(data["flameUnlit"])};
const FLAME_LIT = {json.dumps(data["flameLit"])};
// Sheet A's columns. `done` is excluded -- see the note where `states` is built.
const COPY_STATES = ROWS.map(([s]) => s).filter((s) => s !== "done");
const STYLE = Object.fromEntries(ROWS);
let voice = "duoLike";

/* Text going into an attribute or a tile. Every line here is authored, not user data, but
   the edit boxes make that untrue the moment someone types a `<` -- so this is escaping a
   real input, not being decorative about a constant. */
function esc(s) {{
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}}

function tile(state, style, cat, text) {{
  const lit = state === "done";
  // The run the tile actually shows. `none` means there is no live streak, so it is 0 --
  // mxSpec says `kind === "none" ? 0 : 3` and an earlier cut of this sheet hard-coded 3,
  // which drew eight "3" tiles under "Start a streak!" and quietly contradicted the copy.
  const run = lit ? 4 : state === "none" ? 0 : 3;
  // hascat is always on here; hasline follows the copy, exactly as `frame()` sets them.
  const cls = "fr hascat" + (text ? " hasline" : "");
  const flame = lit ? FLAME_LIT : FLAME_UNLIT;
  const line = text ? `<div class="line">${{esc(text)}}</div>` : "";
  return `<div class="${{cls}}" style="${{style}}">
    <div class="cat"><img src="cats/${{cat}}.png" alt=""></div>
    <div class="runrow${{lit ? "" : " glass"}}">${{flame}}<span class="fig${{lit ? " recorded" : ""}}">${{run}}</span></div>
    ${{line}}
    <div class="grow"></div>
  </div>`;
}}

/* Sheet A. One table per voice: columns are the hours, rows are the three variants, and
   the pose is the voice's own for that hour -- held constant down a column so the only
   thing changing within a column is the sentence. That is the comparison; varying the
   face at the same time would make it two. */
function renderCopy() {{
  let html = "";
  for (const [k, v] of Object.entries(VOICES)) {{
    html += `<div class="vblock" id="v-${{k}}">` +
      `<h3 style="margin:26px 0 2px;font-size:12.5px">${{v.label}} &nbsp;<code style="color:#8fa3b2">${{v.code}}-*</code></h3>` +
      `<p class="gloss" style="margin:2px 0 10px">${{v.gloss}}</p>` +
      "<table><tr><th class='vh'></th>" +
      COPY_STATES.map((s) =>
        `<th>${{s}}<br><span style="color:#7f909d;font-weight:400">${{v.poses[s]}}</span></th>`
      ).join("") + "</tr>";
    for (let i = 0; i < 3; i++) {{
      html += `<tr><th class="vh"><b>variant ${{i + 1}}</b>` +
        (i === 0 ? "<i>the line from the last round</i>" : "") + "</th>" +
        COPY_STATES.map((s) => {{
          const [label, text] = v.variants[s][i];
          return `<td class="cell" data-label="${{label}}" data-voice="${{k}}"` +
            ` data-state="${{s}}" data-variant="${{i + 1}}" data-orig="${{esc(text)}}">` +
            tile(s, STYLE[s], v.poses[s], text) +
            `<label class="tag"><input type="checkbox" class="pick">${{label}}</label>` +
            `<textarea class="edit" rows="2">${{esc(text)}}</textarea></td>`;
        }}).join("") + "</tr>";
    }}
    html += "</table></div>";
  }}
  document.getElementById("copy").innerHTML = html;
}}

/* Sheet B. Variant 1 only, all four voices, so the pose ladders can be read against each
   other. `done` is included here because this is the sheet where it belongs. Each card is
   its own checkbox -- ticking one picks that voice at that hour and nothing else in the
   row, which is the point: the row is a proposed ladder, not a unit of selection. The
   dropdown lets a proposal be overruled one face at a time, independently of whether the
   card is picked. */
function renderPoses() {{
  let html = "<table><tr><th class='vh'></th>" +
    ROWS.map(([s]) => `<th>${{s}}</th>`).join("") + "</tr>";
  for (const [k, v] of Object.entries(VOICES)) {{
    html += `<tr><th class="vh"><b>${{v.label.split(" \u2014 ")[0]}}</b>` +
      `<i>${{v.label.split(" \u2014 ")[1] || ""}}</i><code>${{v.code}}</code></th>` +
      ROWS.map(([s, style]) => {{
        const text = s === "done" ? "" : v.variants[s][0][1];
        const label = v.code + "-" + s;
        const opts = CATS.map((c) =>
          `<option value="${{c}}"${{c === v.poses[s] ? " selected" : ""}}>${{c}}</option>`
        ).join("");
        return `<td class="cell pose" data-voice="${{k}}" data-state="${{s}}"` +
          ` data-label="${{label}}" data-orig="${{v.poses[s]}}" data-text="${{esc(text)}}">` +
          tile(s, style, v.poses[s], text) +
          `<label class="tag"><input type="checkbox" class="posepick">${{label}}</label>` +
          `<select class="posesel">${{opts}}</select></td>`;
      }}).join("") + "</tr>";
  }}
  document.getElementById("poses").innerHTML = html + "</table>";
}}

/* Sheet C. Held over from the round that chose the poses, and kept after the fur was
   settled (neutral grey, 2026-09-27) because the sweep it does -- every state against
   every drawing on the real ground -- is what a pose or ramp change still needs. The
   note here used to say the sheet existed BECAUSE the fur was undecided; it is not. */
function render() {{
  document.getElementById("gloss").textContent = VOICES[voice].gloss;
  document.querySelectorAll("#bar button").forEach((b) =>
    b.classList.toggle("on", b.dataset.v === voice));
  let html = "<table><tr><th class='state'></th>" +
    CATS.map((c) => `<th>${{c}}</th>`).join("") + "</tr>";
  for (const [state, style] of ROWS) {{
    const text = state === "done" ? "" : VOICES[voice].variants[state][0][1];
    html += `<tr><th class="state"><b>${{state}}</b><i>${{NOTE[state] || ""}}</i>` +
      (text ? `<em>&ldquo;${{text}}&rdquo;</em>` : "<em>&mdash;</em>") + "</th>" +
      CATS.map((c) => `<td>${{tile(state, style, c, text)}}</td>`).join("") + "</tr>";
  }}
  document.getElementById("grid").innerHTML = html + "</table>";
}}

const bar = document.getElementById("bar");
for (const [k, v] of Object.entries(VOICES)) {{
  const b = document.createElement("button");
  b.textContent = v.label;
  b.dataset.v = k;
  b.onclick = () => {{ voice = k; render(); }};
  bar.appendChild(b);
}}
renderCopy();
renderPoses();
render();

/* ---- Collecting the decision ------------------------------------------------

   Three things are gathered: which labels are ticked, what any edited line now says, and
   any pose swapped away from the proposal. All three are read out of the DOM at submit
   time rather than accumulated in a parallel model, because the DOM is already the source
   of truth here -- a tile shows its own current line -- and a second copy of that state is
   a second thing to get out of sync.

   localStorage is the one exception and it earns it: this sheet is ~6000px tall and losing
   a half-finished pass to an accidental reload would be the difference between the tool
   being used and abandoned. */
const KEY = "libstack-widget-picks-v1";

function cellState() {{
  const picks = [];
  for (const td of document.querySelectorAll("#copy td.cell")) {{
    const box = td.querySelector(".pick");
    const text = td.querySelector(".edit").value.trim();
    const orig = td.dataset.orig;
    if (!box.checked && text === orig) continue;
    picks.push({{
      label: td.dataset.label,
      voice: td.dataset.voice,
      tier: td.dataset.state,
      variant: Number(td.dataset.variant),
      picked: box.checked,
      edited: text !== orig,
      original: orig,
      text,
    }});
  }}
  // Sheet B. `poses` is the full ladder regardless of picking, so a submission always
  // carries what every voice currently proposes; `posePicks` is only the cards actually
  // ticked -- per card, never per row, which is the whole point of this sheet now.
  const poses = {{}}, poseChanges = [], posePicks = [];
  for (const td of document.querySelectorAll("#poses td.cell.pose")) {{
    const to = td.querySelector(".posesel").value;
    (poses[td.dataset.voice] ||= {{}})[td.dataset.state] = to;
    const reposed = to !== td.dataset.orig;
    if (reposed)
      poseChanges.push({{ voice: td.dataset.voice, state: td.dataset.state,
                        from: td.dataset.orig, to }});
    if (td.querySelector(".posepick").checked)
      posePicks.push({{
        label: td.dataset.label,
        voice: td.dataset.voice,
        state: td.dataset.state,
        pose: to,
        reposed,
        text: td.dataset.text,
      }});
  }}
  return {{
    submittedAt: new Date().toISOString(),
    picks, posePicks, poses, poseChanges,
    notes: document.getElementById("notes").value,
  }};
}}

function refreshCell(td) {{
  const text = td.querySelector(".edit").value.trim();
  td.classList.toggle("edited", text !== td.dataset.orig);
  td.classList.toggle("picked", td.querySelector(".pick").checked);
  const line = td.querySelector(".line");
  const fr = td.querySelector(".fr");
  if (text && line) line.textContent = text;
  else if (text && !line) {{
    // The tile was rendered without a line (an empty variant); give it one so an edit is
    // visible rather than silently accepted into a tile that cannot show it.
    const d = document.createElement("div");
    d.className = "line";
    d.textContent = text;
    fr.querySelector(".runrow").insertAdjacentElement("afterend", d);
    fr.classList.add("hasline");
  }} else if (!text && line) {{
    line.remove();
    fr.classList.remove("hasline");
  }}
}}

function tally() {{
  const s = cellState();
  const picked = s.picks.filter((p) => p.picked).length;
  const edited = s.picks.filter((p) => p.edited).length;
  document.getElementById("tally").innerHTML =
    `<b>${{s.posePicks.length}}</b> pose pick${{s.posePicks.length === 1 ? "" : "s"}} &middot; ` +
    `${{s.poseChanges.length}} repose${{s.poseChanges.length === 1 ? "" : "d"}} &middot; ` +
    `${{picked}} copy picked &middot; ${{edited}} edited`;
  try {{ localStorage.setItem(KEY, JSON.stringify(s)); }} catch (e) {{}}
}}

// One listener on the document rather than per control: there are 84 checkboxes on Sheet
// A, 32 checkboxes and 32 dropdowns on Sheet B, and 200-odd listeners to do what
// delegation does is 200-odd things to leak when a sheet re-renders.
document.addEventListener("input", (e) => {{
  const td = e.target.closest("td.cell");
  if (td && td.classList.contains("pose")) {{
    const sel = td.querySelector(".posesel");
    td.querySelector(".cat img").src = "cats/" + sel.value + ".png";
    td.classList.toggle("repose", sel.value !== td.dataset.orig);
    // The checkbox and the dropdown are independent controls on the same card, so either
    // one changing has to re-read the other to keep `.picked` correct.
    td.classList.toggle("picked", td.querySelector(".posepick").checked);
  }} else if (td) {{
    // Editing a line is a statement of interest, so it ticks the box. Not ticking it
    // would mean an edit could be submitted as "changed but not wanted", which is a
    // state nobody means.
    if (e.target.classList.contains("edit")) td.querySelector(".pick").checked = true;
    refreshCell(td);
  }}
  tally();
}});

// Restore. Sheet A is matched on label rather than on position, so adding a variant to a
// voice does not silently shift a saved pick onto a different line. Sheet B is matched on
// voice+state for the same reason.
try {{
  const saved = JSON.parse(localStorage.getItem(KEY) || "null");
  if (saved) {{
    for (const p of saved.picks || []) {{
      const td = document.querySelector(`#copy td.cell[data-label="${{p.label}}"]`);
      if (!td) continue;
      td.querySelector(".pick").checked = !!p.picked;
      td.querySelector(".edit").value = p.text;
      refreshCell(td);
    }}
    for (const c of saved.poseChanges || []) {{
      const td = document.querySelector(
        `#poses td.cell[data-voice="${{c.voice}}"][data-state="${{c.state}}"]`);
      if (!td) continue;
      td.querySelector(".posesel").value = c.to;
      td.querySelector(".cat img").src = "cats/" + c.to + ".png";
      td.classList.add("repose");
    }}
    for (const pp of saved.posePicks || []) {{
      const td = document.querySelector(
        `#poses td.cell[data-voice="${{pp.voice}}"][data-state="${{pp.state}}"]`);
      if (!td) continue;
      td.querySelector(".posepick").checked = true;
      td.classList.add("picked");
    }}
    document.getElementById("notes").value = saved.notes || "";
  }}
}} catch (e) {{}}
tally();

// Sheet B is the one being judged right now, so land there rather than at the top.
document.getElementById("sheetB").scrollIntoView();

// Opened as a file:// URL there is nothing to POST to, and a Submit button that silently
// fails is worse than one that is not there -- so say so up front.
if (location.protocol === "file:") {{
  const w = document.getElementById("warn");
  w.hidden = false;
  w.innerHTML = "Opened from the filesystem, so <b>Submit will not work</b>. " +
    "Run <code>.venv/bin/python scripts/mockup_server.py</code> from the repo root and " +
    "open <code>http://127.0.0.1:8765/_widget_grid.html</code> instead. " +
    "Ticking and editing still work here, and are saved locally.";
  document.getElementById("send").disabled = true;
}}

document.getElementById("send").onclick = async () => {{
  const btn = document.getElementById("send");
  const payload = cellState();
  btn.disabled = true;
  btn.textContent = "Sending...";
  try {{
    const res = await fetch("/submit", {{
      method: "POST",
      headers: {{ "Content-Type": "application/json" }},
      body: JSON.stringify(payload),
    }});
    const out = await res.json();
    if (!res.ok || !out.ok) throw new Error(out.error || res.status);
    btn.textContent = "Sent \u2713 " + out.saved;
    setTimeout(() => {{ btn.textContent = "Submit"; btn.disabled = false; }}, 2500);
  }} catch (err) {{
    btn.textContent = "Failed \u2014 " + err.message;
    btn.disabled = false;
  }}
}};
</script>
</body>
</html>
"""


def main() -> int:
    html = SRC.read_text()
    data = run_node(extract_script(html))
    cats = sorted(p.stem for p in CATS.glob("*.png"))
    if not cats:
        sys.exit("no cut-outs found in " + str(CATS))
    OUT.write_text(build(data, extract_grain(html), extract_font_faces(html), cats))
    n_lines = sum(len(v["variants"]) * 3 for v in data["voices"].values())
    print(f"{OUT}")
    print(f"sheet A: {len(data['voices'])} voices x 7 states x 3 variants = {n_lines} labelled lines")
    print(f"sheet B: {len(data['voices'])} pose ladders")
    print(f"sheet C: {len(data['tiers']) + 2} states x {len(cats)} expressions")
    for k, v in data["voices"].items():
        ladder = ", ".join(
            v["poses"][t] for t in
            ["dawn", "morning", "afternoon", "evening", "late", "final"]
        )
        print(f"  {v['code']}  {k:<10} {ladder}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
