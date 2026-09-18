#!/usr/bin/env python3
"""Verify docs/mockups/empty-states/index.html without a browser.

The page is one big data structure plus a renderer, so most of what can break is
mechanically checkable: does the script parse, do the version patches inherit and
remove as intended, does every art name referenced by a screen actually exist,
and does every raster <img src> resolve to a file on disk. That last one matters
now that the page reads sibling files from art/gen/ and is no longer
self-contained -- a typo'd filename is an invisible broken image otherwise.

    python3 scripts/check_mockup.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PAGE = REPO / "docs" / "mockups" / "empty-states" / "index.html"

# A DOM stub: the page's engine touches document/window at load. Enough of each
# is faked to let the module evaluate, then the real assertions run against the
# data structures it built.
STUB = r"""
const _el = () => ({
  style:{}, dataset:{}, classList:{add(){},remove(){},toggle(){},contains(){return false}},
  children:[], appendChild(){}, removeChild(){}, insertBefore(){}, remove(){},
  setAttribute(){}, getAttribute(){return null}, removeAttribute(){},
  addEventListener(){}, removeEventListener(){}, focus(){}, blur(){}, click(){},
  querySelector(){return _el()}, querySelectorAll(){return []},
  getBoundingClientRect(){return {top:0,bottom:0,left:0,right:0,width:0,height:0}},
  scrollIntoView(){}, closest(){return null}, matches(){return false},
  set innerHTML(v){this._h=v}, get innerHTML(){return this._h||""},
  set textContent(v){this._t=v}, get textContent(){return this._t||""},
  set value(v){this._v=v}, get value(){return this._v||""},
  offsetTop:0, offsetHeight:0, scrollTop:0, scrollHeight:0,
});
globalThis.document = {
  documentElement:_el(), body:_el(), head:_el(),
  createElement:_el, createElementNS:_el, createDocumentFragment:_el,
  getElementById(){return _el()}, querySelector(){return _el()},
  querySelectorAll(){return []}, addEventListener(){}, removeEventListener(){},
};
globalThis.window = {
  addEventListener(){}, removeEventListener(){}, location:{hash:"",search:""},
  matchMedia(){return {matches:false, addEventListener(){}, addListener(){}}},
  requestAnimationFrame(f){return 0}, getComputedStyle(){return {}},
  scrollTo(){}, innerWidth:1400, innerHeight:900, devicePixelRatio:2,
};
globalThis.requestAnimationFrame = () => 0;
globalThis.matchMedia = window.matchMedia;
globalThis.localStorage = { getItem(){return null}, setItem(){}, removeItem(){} };
"""

CHECKS = r"""
/* ---- assertions ---- */
const fail = [];
const ok = [];
const must = (cond, msg) => (cond ? ok.push(msg) : fail.push(msg));

must(Array.isArray(VERSIONS) && VERSIONS.length > 0, "VERSIONS is a non-empty array");
must(VERSIONS[0][3] === null || VERSIONS[0][3] === undefined,
     "root version has no parent");

const ids = VERSIONS.map(v => v[0]);
must(new Set(ids).size === ids.length, "version ids are unique");

/* Every non-root parent must exist, or inheritance silently drops content. */
const idset = new Set(ids);
for (const v of VERSIONS.slice(1))
  must(idset.has(v[3]), `parent of ${v[0]} (${v[3]}) exists`);

/* The three new Grok versions must chain, not all hang off main. */
const parentOf = Object.fromEntries(VERSIONS.map(v => [v[0], v[3]]));
must(parentOf["grok-plate"] === "main", "grok-plate branches from main");
must(parentOf["grok-cutout"] === "grok-plate", "grok-cutout branches from grok-plate");
must(parentOf["grok-stencil"] === "grok-cutout", "grok-stencil branches from grok-cutout");

/* resolveView(vid, kind) -> [[group, [[id, nm, note, payload], ...]], ...] */
const flat = (vid, kind) => {
  const out = new Map();
  for (const [, list] of resolveView(vid, kind))
    for (const [id, nm, ds, payload] of list) out.set(id, {nm, ds, payload});
  return out;
};

const SIZES = {rest:100, invite:100, search:100, nomatch:40, note:48, duo:40};
let checkedArt = 0;
const rasterSrcs = new Set();

for (const id of ids) {
  let screens, elements;
  try { screens = flat(id, "screens"); elements = flat(id, "elements"); }
  catch (e) { fail.push(`resolveView(${id}) threw: ${e.message}`); continue; }
  must(screens.size > 0, `${id} resolves to a non-empty screen set`);
  must(elements.size > 0, `${id} resolves to a non-empty element set`);

  /* Walk every screen spec for {t:"art", name} nodes and render each one both
     ways. This is what catches a version pointing at an ART key that does not
     exist -- which renders as "undefined" in the page with no error. */
  const walk = (node) => {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) return node.forEach(walk);
    if (typeof node.name === "string" && (node.t === "art" || node.size !== undefined)) {
      const n = node.name;
      if (typeof ART[n] !== "function") {
        fail.push(`${id}: ART["${n}"] missing`);
      } else {
        for (const pal of ["light", "dark"]) {
          let html;
          try { html = ART[n](node.size || 46, pal); }
          catch (e) { fail.push(`${id}: ART["${n}"](${pal}) threw: ${e.message}`); continue; }
          if (typeof html !== "string" || !html.length) {
            fail.push(`${id}: ART["${n}"](${pal}) returned nothing`); continue;
          }
          const m = html.match(/src="([^"]+)"/);
          if (m) rasterSrcs.add(m[1]);
          checkedArt++;
        }
      }
    }
    for (const k of Object.keys(node)) walk(node[k]);
  };
  for (const s of screens.values()) walk(s.payload);

  /* Element demos are pre-rendered HTML strings; collect their srcs too so the
     on-disk check covers the element gallery, not just the screens. */
  for (const e of elements.values()) {
    if (typeof e.payload !== "string") { fail.push(`${id}: element demo not a string`); continue; }
    for (const m of e.payload.matchAll(/src="([^"]+)"/g)) rasterSrcs.add(m[1]);
  }
}
must(checkedArt > 0, `art callables exercised (${checkedArt})`);

/* Removals must actually remove: grok-cutout retires the gplate element cards,
   grok-stencil retires the gcut ones. If these survive, the page shows two
   generations of the same card side by side. */
const plate = flat("grok-plate", "elements");
const cut = flat("grok-cutout", "elements");
const sten = flat("grok-stencil", "elements");
must(plate.has("el-gplate-rest"), "grok-plate has el-gplate-rest");
must(!cut.has("el-gplate-rest"), "grok-cutout removed el-gplate-rest");
must(cut.has("el-gcut-rest"), "grok-cutout added el-gcut-rest");
must(!sten.has("el-gcut-rest"), "grok-stencil removed el-gcut-rest");
must(sten.has("el-gsten-rest"), "grok-stencil added el-gsten-rest");
must(!sten.has("el-gplate-rest"), "grok-stencil still has gplate removed (inherited removal)");

/* Inheritance two hops down: the stencil version never mentions main's own
   element cards, so all of them must still be present. */
const root = flat(ids[0], "elements");
const inheritedMissing = [...root.keys()].filter(e => !sten.has(e));
must(inheritedMissing.length === 0,
     `grok-stencil inherits all ${root.size} root element cards (missing ${inheritedMissing.length}: ${inheritedMissing.slice(0,3)})`);

/* Screens must be overridden in place, not added: all three Grok versions patch
   the same seven screens main defines, so the count must not grow. */
for (const v of ["grok-plate", "grok-cutout", "grok-stencil"]) {
  must(flat(v, "screens").size === flat(ids[0], "screens").size,
       `${v} overrides screens in place (no additions)`);
}

/* The stencil version must use ONE file per piece across both themes -- that is
   its entire claim, so assert it rather than trusting the note. */
for (const p of Object.keys(SIZES)) {
  const l = ART["gsten-" + p](40, "light"), d = ART["gsten-" + p](40, "dark");
  const sl = (l.match(/src="([^"]+)"/) || [])[1], sd = (d.match(/src="([^"]+)"/) || [])[1];
  must(sl === sd, `gsten-${p}: same file both themes (${sl} vs ${sd})`);
  must(/stencilInk\)/.test(l) && /stencilInkDark\)/.test(d), `gsten-${p}: tinted per theme`);
}
/* The cutout version must do the opposite: two files. Asserting the flaw keeps
   the version honest if someone later "fixes" it by pointing both at one file. */
for (const p of Object.keys(SIZES)) {
  const sl = (ART["gcut-" + p](40, "light").match(/src="([^"]+)"/) || [])[1];
  const sd = (ART["gcut-" + p](40, "dark").match(/src="([^"]+)"/) || [])[1];
  must(sl !== sd, `gcut-${p}: two files, one per theme`);
  must(/-night-/.test(sd), `gcut-${p}: dark chip uses the night generation`);
}

console.log(JSON.stringify({
  ok: ok.length, fail, versions: ids, srcs: [...rasterSrcs].sort(),
}, null, 2));
"""


def main() -> None:
    html = PAGE.read_text()
    scripts = re.findall(r"<script[^>]*>(.*?)</script>", html, re.S)
    body = max(scripts, key=len)  # the engine is by far the longest
    print(f"extracted {len(body)} chars of script from {PAGE.relative_to(REPO)}")

    with tempfile.TemporaryDirectory() as td:
        js = Path(td) / "page.mjs"
        js.write_text(STUB + body + CHECKS)

        syn = subprocess.run(["node", "--check", str(js)], capture_output=True, text=True)
        if syn.returncode != 0:
            sys.exit("node --check failed:\n" + syn.stderr)
        print("node --check: ok")

        run = subprocess.run(["node", str(js)], capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit("run failed:\n" + run.stdout[-3000:] + "\n" + run.stderr[-3000:])

    out = run.stdout[run.stdout.index("{") :]
    res = json.loads(out)
    print(f"versions ({len(res['versions'])}): {', '.join(res['versions'])}")
    print(f"assertions passed: {res['ok']}")

    # Every raster the page points at must exist, or it is an invisible 404.
    missing = [s for s in res["srcs"] if not (PAGE.parent / s).exists()]
    print(f"raster srcs referenced: {len(res['srcs'])}, missing: {len(missing)}")
    for m in missing:
        print(f"  MISSING {m}")

    if res["fail"] or missing:
        print("\nFAILURES:")
        for f in res["fail"]:
            print(f"  {f}")
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
