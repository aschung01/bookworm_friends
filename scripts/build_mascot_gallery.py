#!/usr/bin/env python3
"""Build a browsable gallery of every generated mascot image.

Reads `docs/mockups/mascot/art/manifest.json` and emits a single self-contained
`docs/mockups/mascot/gallery.html`. No build step, no server, no network -- it
opens from disk.

Why generated rather than hand-written: `index.html` next to it was hand-edited
and is now ~14 rounds stale, and editing it kept orphaning blocks because the
editor reformats on save. A generated page cannot drift from the manifest.

Run it after any `gen_mascot_art.py` round:

    .venv/bin/python scripts/build_mascot_gallery.py

Two sources are stitched together:
  - every manifest entry whose PNG is still on disk (the xAI rounds), and
  - the ten Gemini comparison renders, which were downloaded with curl during
    the provider bake-off and so were never recorded in the manifest.

Manifest entries whose file is gone are listed in a footer rather than dropped,
because a missing file usually means it was overwritten by a later run at the
same key and that is worth seeing.
"""

from __future__ import annotations

import html
import json
import re
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ART = REPO / "docs" / "mockups" / "mascot" / "art"
OUT = REPO / "docs" / "mockups" / "mascot" / "gallery.html"

# Rounds in the order they happened, with what each was actually for. Anything
# not named here still renders, under its raw style key.
ROUNDS: dict[str, str] = {
    "chalk": "r1 · chalk, seeded from the app icon",
    "cute": "r2 · cute proportions",
    "character": "r3 · character construction",
    "probe": "r4 · route and parameter probes",
    "cat": "r5 · first cats",
    "geo": "r6 · geometric build",
    "geo5": "r7 · five-shape build",
    "face": "r8 · face construction sweep",
    "worm": "· bookworm (abandoned subject)",
    "mark": "· early identity marks",
    "lamp": "· reading lamp (abandoned subject)",
    "story": "r10 · mini-stories on the core template",
    "look": "r11 · palette switch to grey + apricot",
    "identity": "r12 · identity under deformation (eye mask, rejected)",
    "marks": "r13 · candidate cat marks",
    "marks2": "r14 · breed and behaviour marks",
    "fine": "r15 · fine head detail",
    "mix": "r16 · combinations, crown-count sweep",
    "twinkle": "r17 · TWINKLE CHOSEN (t02 notch); whiskers + crown dropped",
    "cats": "r18 · body sweep with the notch held",
    "poseable": "r19 · connected limbs; v10 jelly beans chosen",
    "poses": "r20 · 20 poses",
    "tailone": "r21 · single-tone tail; q06 chosen as reference",
    "core": "r22 · CORE prompt + the paw rule",
    "sketch": "r23 · chalk misread as white-on-green (wrong)",
    "chalktex": "r24 · chalk texture only, palette kept",
    "eyes": "r25 · eye construction sweep; y04 rim chosen",
    "eyes2": "r26 · failed sweep — varied adjectives, got identical eyes",
    "eyes3": "r27 · EYE LOCKED (k09 capsule); named shapes beat ratios",
    "edit": "r28 · short edit prompt per xAI guidance",
    "widget": "r29 · streak widget expression matrix",
}

GEMINI = {
    "nbpro": "Gemini 3 Pro Image (nano-banana-pro), via fal",
    "nb2": "Gemini 3.1 Flash Image (nano-banana-2) + thinking, via fal",
}


def variant_of(name: str) -> int:
    m = re.search(r"-v(\d+)$", name)
    return int(m.group(1)) if m else 0


def build() -> str:
    manifest = json.loads((ART / "manifest.json").read_text())
    on_disk = {p.name for p in ART.glob("*.png") if not p.name.startswith("_")}

    groups: dict[str, list[dict]] = defaultdict(list)
    missing: list[str] = []
    total_cost = 0.0

    for fname, e in manifest.items():
        if fname not in on_disk:
            missing.append(fname)
            continue
        style = e.get("style") or "unknown"
        total_cost += float(e.get("cost_usd") or 0)
        groups[style].append(
            {
                "file": fname,
                "name": fname.removesuffix(".png"),
                "label": e.get("label", ""),
                "prompt": e.get("prompt", ""),
                "route": e.get("route", "—"),
                "res": e.get("resolution", "—"),
                "aspect": e.get("aspect_ratio", "—"),
                "model": e.get("model", "—"),
                "ref": e.get("reference") or "",
                "when": e.get("generated", ""),
                "cost": float(e.get("cost_usd") or 0),
            }
        )

    for fname in sorted(on_disk - set(manifest)):
        suffix = fname.removesuffix(".png").rsplit("-", 1)[-1]
        if suffix not in GEMINI:
            continue
        groups["gemini"].append(
            {
                "file": fname,
                "name": fname.removesuffix(".png"),
                "label": "provider bake-off (xAI won)",
                "prompt": "CORE verbatim, same text as the r22 core round.",
                "route": "text-to-image",
                "res": "2K",
                "aspect": "3:4",
                "model": GEMINI[suffix],
                "ref": "",
                "when": "",
                "cost": 0.15 if suffix == "nbpro" else 0.08,
            }
        )

    order = [s for s in ROUNDS if s in groups]
    order += sorted(s for s in groups if s not in ROUNDS)

    sheets = sorted(p.name for p in ART.glob("_sheet_*.png"))
    n_images = sum(len(v) for v in groups.values())

    parts: list[str] = []
    parts.append(
        HEAD.replace("__N__", str(n_images))
        .replace("__ROUNDS__", str(len(order)))
        .replace("__COST__", f"{total_cost:,.2f}")
        .replace("__SHEETS__", str(len(sheets)))
    )

    # nav
    parts.append('<nav id="nav">')
    for style in order:
        lab = ROUNDS.get(style, style)
        parts.append(
            f'<a href="#{html.escape(style)}">{html.escape(lab)}'
            f'<span class="n">{len(groups[style])}</span></a>'
        )
    parts.append("</nav>")

    parts.append('<main>')

    # contact sheets first -- the fastest way to compare a whole round
    parts.append('<section id="sheets"><h2>Contact sheets</h2>')
    parts.append(
        '<p class="note">Start here. Each sheet is one round on a single image, '
        'which loads far faster than the individual 1&nbsp;MB renders below. '
        'Judge fine detail from the full-size PNG though &mdash; a 330px cell '
        'hid a pose error once already.</p>'
    )
    parts.append('<div class="grid sheetgrid">')
    for s in sheets:
        parts.append(
            f'<figure class="card" data-search="{html.escape(s)}">'
            f'<a href="art/{s}"><img loading="lazy" decoding="async" src="art/{s}" alt="{html.escape(s)}"></a>'
            f'<figcaption><b>{html.escape(s.removeprefix("_sheet_").removesuffix(".png"))}</b></figcaption>'
            f"</figure>"
        )
    parts.append("</div></section>")

    for style in order:
        items = sorted(groups[style], key=lambda d: (d["name"].split("-v")[0], variant_of(d["name"])))
        lab = ROUNDS.get(style, style)
        spend = sum(i["cost"] for i in items)
        parts.append(f'<section id="{html.escape(style)}">')
        parts.append(
            f"<h2>{html.escape(lab)}"
            f'<span class="meta">{len(items)} images · ${spend:,.2f}</span></h2>'
        )
        parts.append('<div class="grid">')
        for it in items:
            search = " ".join(
                [it["name"], it["label"], it["model"], style, it["prompt"][:400]]
            ).lower()
            badge = "edit" if it["route"] == "edits" else ""
            parts.append(
                f'<figure class="card" data-search="{html.escape(search)}">'
                f'<a href="art/{it["file"]}" title="open full size">'
                f'<img loading="lazy" decoding="async" src="art/{it["file"]}" alt="{html.escape(it["name"])}"></a>'
                f"<figcaption>"
                f'<b>{html.escape(it["name"])}</b>'
                + (f'<span class="badge">{badge}</span>' if badge else "")
                + f'<span class="lab">{html.escape(it["label"])}</span>'
                f'<span class="meta">{html.escape(str(it["res"]))} · {html.escape(str(it["aspect"]))}'
                + (' · ref' if it["ref"] else "")
                + f' · ${it["cost"]:.2f}</span>'
                f'<details><summary>prompt</summary><pre>{html.escape(it["prompt"])}</pre></details>'
                f"</figcaption></figure>"
            )
        parts.append("</div></section>")

    if missing:
        parts.append('<section id="missing"><h2>In the manifest, no file on disk</h2>')
        parts.append(
            '<p class="note">Usually means a later run reused the same key and '
            "overwrote it. Provenance survives in the manifest even though the "
            "image does not.</p><ul class=\"missing\">"
        )
        for f in sorted(missing):
            parts.append(f"<li>{html.escape(f)}</li>")
        parts.append("</ul></section>")

    parts.append("</main>")
    parts.append(TAIL)
    return "\n".join(parts)


HEAD = """<!doctype html>
<meta charset="utf-8">
<title>Libstack mascot — every generated image</title>
<style>
  :root{--bg:#14161a;--panel:#1c1f25;--line:#2b2f37;--ink:#e8eaed;--dim:#9aa0a8;--acc:#09BC8A}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);
       font:14px/1.5 ui-sans-serif,-apple-system,"Segoe UI",sans-serif}
  header{padding:26px 28px 16px;border-bottom:1px solid var(--line)}
  h1{margin:0 0 6px;font-size:19px;letter-spacing:.2px}
  .sub{color:var(--dim);font-size:13px;max-width:70ch}
  .tools{display:flex;gap:10px;align-items:center;margin-top:14px;flex-wrap:wrap}
  input[type=search]{flex:1;min-width:240px;background:var(--panel);border:1px solid var(--line);
      color:var(--ink);padding:9px 12px;border-radius:8px;font-size:14px}
  input[type=search]:focus{outline:2px solid var(--acc);outline-offset:1px}
  #count{color:var(--dim);font-size:13px;white-space:nowrap}
  nav{display:flex;flex-wrap:wrap;gap:6px;padding:14px 28px;border-bottom:1px solid var(--line);
      position:sticky;top:0;background:var(--bg);z-index:5}
  nav a{color:var(--dim);text-decoration:none;font-size:12px;padding:4px 9px;border-radius:999px;
      border:1px solid var(--line);white-space:nowrap}
  nav a:hover{color:var(--ink);border-color:var(--acc)}
  nav .n{color:var(--acc);margin-left:6px}
  main{padding:8px 28px 60px}
  section{padding-top:30px;scroll-margin-top:64px}
  h2{font-size:15px;margin:0 0 4px;display:flex;gap:12px;align-items:baseline;flex-wrap:wrap}
  h2 .meta{color:var(--dim);font-weight:400;font-size:12px}
  .note{color:var(--dim);font-size:13px;max-width:78ch;margin:6px 0 0}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:14px;margin-top:16px}
  .sheetgrid{grid-template-columns:repeat(auto-fill,minmax(320px,1fr))}
  .card{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden}
  .card img{width:100%;display:block;background:#fff}
  figcaption{padding:8px 10px 10px;font-size:12px;display:flex;flex-direction:column;gap:3px}
  figcaption b{font-weight:600;letter-spacing:.2px}
  .lab{color:var(--dim)}
  .meta{color:#6f757d;font-size:11px}
  .badge{align-self:flex-start;background:rgba(9,188,138,.14);color:var(--acc);
      border:1px solid rgba(9,188,138,.35);border-radius:999px;padding:0 7px;font-size:10px}
  details summary{cursor:pointer;color:#6f757d;font-size:11px;margin-top:2px}
  details pre{white-space:pre-wrap;word-break:break-word;color:var(--dim);font-size:11px;
      background:#111316;border:1px solid var(--line);border-radius:6px;padding:8px;margin:6px 0 0}
  .missing{color:var(--dim);font-size:12px;columns:3;gap:20px}
  .hide{display:none!important}
</style>
<header>
  <h1>Libstack mascot — every generated image</h1>
  <div class="sub">__N__ renders across __ROUNDS__ rounds, __SHEETS__ contact sheets,
    $__COST__ of generation. Generated from <code>art/manifest.json</code> by
    <code>scripts/build_mascot_gallery.py</code> — re-run it after any round rather than
    editing this file. Click any image for full size; expand <i>prompt</i> to see the exact
    text that produced it. The locked character is <code>REFERENCE.png</code>; the spec is
    <code>CHARACTER.md</code>.</div>
  <div class="tools">
    <input type="search" id="q" placeholder="Filter by name, label or prompt text —  e.g. capsule, jelly, puddle, sunglasses">
    <span id="count"></span>
  </div>
</header>"""

TAIL = """<script>
(function () {
  var q = document.getElementById('q');
  var count = document.getElementById('count');
  var cards = Array.prototype.slice.call(document.querySelectorAll('.card'));
  var sections = Array.prototype.slice.call(document.querySelectorAll('main section'));

  function apply() {
    var terms = q.value.toLowerCase().split(/\\s+/).filter(Boolean);
    var shown = 0;
    cards.forEach(function (c) {
      var hay = c.getAttribute('data-search') || '';
      var ok = terms.every(function (t) { return hay.indexOf(t) !== -1; });
      c.classList.toggle('hide', !ok);
      if (ok) shown++;
    });
    sections.forEach(function (s) {
      var any = s.querySelector('.card:not(.hide)');
      s.classList.toggle('hide', !any && s.querySelectorAll('.card').length > 0);
    });
    count.textContent = terms.length
      ? shown + ' of ' + cards.length + ' shown'
      : cards.length + ' images';
  }

  q.addEventListener('input', apply);
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== q) { e.preventDefault(); q.focus(); }
    if (e.key === 'Escape' && document.activeElement === q) { q.value = ''; apply(); q.blur(); }
  });
  apply();
})();
</script>"""


if __name__ == "__main__":
    OUT.write_text(build())
    kb = OUT.stat().st_size // 1024
    print(f"wrote {OUT.relative_to(REPO)} ({kb} KB)")
