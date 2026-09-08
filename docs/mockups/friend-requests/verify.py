"""Extract the page's inline script, syntax-check it, then run engine assertions.

Run: python3 docs/mockups/friend-requests/verify.py
Writes nothing permanent outside .tmp-verify/ (gitignored scratch).
"""

import json
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(ROOT, "index.html")
TMP = os.path.join(ROOT, ".tmp-verify")
os.makedirs(TMP, exist_ok=True)

html = open(PAGE, encoding="utf-8").read()
m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
if not m:
    raise SystemExit("no inline <script> found")
script = m.group(1)

# The stylesheet, handed to the assertions as a string so they can check that
# every `var()` the frames reference is actually declared. There is no layout
# engine here, so this is the only way an undefined custom property — which CSS
# resolves silently by inheriting — can be caught at all.
styles = re.findall(r"<style>\s*\n(.*?)\n\s*</style>", html, re.S)
if not styles:
    raise SystemExit("no inline <style> found")
style_text = "\n".join(styles)

sp = os.path.join(TMP, "script.js")
open(sp, "w", encoding="utf-8").write(script)
r = subprocess.run(["node", "--check", sp], capture_output=True, text=True)
print("node --check:", "ok" if r.returncode == 0 else "FAIL")
if r.returncode != 0:
    print(r.stderr)
    raise SystemExit(1)

STUB = r"""
// Minimal DOM stub: the script only needs these to not throw at load time.
const _el = () => {
  const e = {
    style: {},
    value: "",
    checked: false,
    scrollTop: 0,
    offsetTop: 0,
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    dataset: {},
    children: [],
    appendChild(c) { this.children.push(c); return c; },
    append(...c) { this.children.push(...c); },
    addEventListener() {},
    removeEventListener() {},
    setAttribute() {},
    getAttribute: () => null,
    removeAttribute() {},
    querySelector: () => null,
    querySelectorAll: () => [],
    closest: () => null,
    focus() {},
    blur() {},
    scrollIntoView() {},
    getBoundingClientRect: () => ({ top: 0, left: 0, width: 0, height: 0 }),
    set innerHTML(v) { this._h = v; },
    get innerHTML() { return this._h || ""; },
    set textContent(v) { this._t = v; },
    get textContent() { return this._t || ""; },
    insertAdjacentHTML() {},
  };
  return e;
};
globalThis.document = {
  createElement: _el,
  createDocumentFragment: _el,
  getElementById: () => _el(),
  querySelector: () => _el(),
  querySelectorAll: () => [],
  addEventListener() {},
  body: _el(),
  documentElement: _el(),
  location: { hash: "" },
};
globalThis.window = globalThis;
globalThis.location = { hash: "", href: "" };
globalThis.history = { replaceState() {}, pushState() {} };
globalThis.addEventListener = () => {};
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
globalThis.requestAnimationFrame = (f) => f();
globalThis.scrollTo = () => {};
globalThis.getComputedStyle = () => ({ getPropertyValue: () => "" });
"""

ASSERT = r"""
// ---- assertions -------------------------------------------------------
let pass = 0;
const fails = [];
function ok(cond, msg) {
  if (cond) pass++;
  else fails.push(msg);
}
function eq(a, b, msg) {
  ok(a === b, msg + " (got " + JSON.stringify(a) + ", want " + JSON.stringify(b) + ")");
}

const KINDS = ["screens", "flows", "elements"];

// VERSIONS is [id, label, note, parentId, patch].
ok(Array.isArray(VERSIONS) && VERSIONS.length >= 2, "VERSIONS has >= 2 entries");
eq(VERSIONS.filter((v) => v[3] == null).length, 1, "exactly one root version");
eq(VERSIONS[0][3], null, "the root is first");
const vids = new Set(VERSIONS.map((v) => v[0]));
for (const v of VERSIONS) {
  ok(typeof v[0] === "string" && v[0].length > 0, "version has an id");
  ok(typeof v[1] === "string" && v[1].length > 0, "version " + v[0] + " has a label");
  ok(typeof v[2] === "string" && v[2].length > 20, "version " + v[0] + " has a real note");
  ok(typeof v[4] === "object" && v[4], "version " + v[0] + " has a patch object");
  if (v[3] != null) ok(vids.has(v[3]), "version " + v[0] + " parent resolves");
  ok(chainOf(v[0])[0] === VROOT, "version " + v[0] + " chains back to the root");
}

// Base data shape.
for (const [nm, base] of [["SCREENS", SCREENS], ["FLOWS", FLOWS], ["ELEMENTS", ELEMENTS]]) {
  ok(Array.isArray(base) && base.length > 0, nm + " is a non-empty array");
}

// resolveView must return well-formed groups for every version x kind.
for (const v of VERSIONS) {
  for (const k of KINDS) {
    const groups = resolveView(v[0], k);
    ok(Array.isArray(groups), v[0] + "/" + k + " resolves to an array");
    let n = 0;
    const seen = new Set();
    for (const [g, items] of groups) {
      ok(typeof g === "string" && g.length > 0, v[0] + "/" + k + " group has a name");
      ok(items.length > 0, v[0] + "/" + k + " group '" + g + "' is non-empty");
      for (const [id, name, note, payload] of items) {
        ok(typeof id === "string" && /^[a-z0-9-]+$/.test(id), v[0] + "/" + k + " id is a slug: " + id);
        ok(typeof name === "string" && name.length > 0, "item " + id + " has a name");
        ok(!seen.has(id), "item id unique within view: " + id);
        seen.add(id);
        ok(payload != null, "item " + id + " has a payload");
      }
      n += items.length;
    }
    ok(n > 0, v[0] + "/" + k + " is non-empty (" + n + ")");
  }
}

// Expected counts on the root version.
const count = (k) => resolveView(VROOT, k).reduce((a, [, i]) => a + i.length, 0);
eq(count("screens"), 13, "root screen count");
eq(count("flows"), 4, "root flow count");
eq(count("elements"), 6, "root element count");

// Every open-question id must name a real screen, or its callout never draws.
const screenIds = new Set(
  resolveView(VROOT, "screens").flatMap(([, l]) => l.map((it) => it[0])),
);
for (const id of Object.keys(resolveOpen(VROOT)))
  ok(screenIds.has(id), "open question '" + id + "' names a real screen");

// diffMap: a version against itself is empty; the patch differs somewhere.
for (const k of KINDS) eq(diffMap(VROOT, VROOT, k).size, 0, "self-diff empty for " + k);
const patchV = VERSIONS.find((v) => v[3] != null)[0];
let anyDiff = 0;
for (const k of KINDS) {
  const d = diffMap(VROOT, patchV, k);
  ok(d instanceof Map, "diffMap returns a Map for " + k);
  for (const [id, state] of d) {
    ok(["changed", "onlyHere", "onlyThere"].includes(state), "diff state valid for " + id + ": " + state);
    anyDiff++;
  }
}
ok(anyDiff > 0, "the patch version differs from the root somewhere");

// Search must reach copy rendered on the frames, not just names and notes.
const hay = resolveView(VROOT, "screens")
  .flatMap(([g, l]) => l.map(([id, nm, ds, sp]) => flowSearchText(g, nm, ds, [[nm, ds, sp]])))
  .join(" ");
ok(hay.includes("libstack"), "search text reaches on-frame copy (libstack)");
ok(!hay.includes('"t":') && !/\bemoji\b/.test(hay), "search text leaks no spec keys");
ok(!/[<>]/.test(hay), "search text is tag-stripped");

// The hero primitive replaced h2b everywhere; spacers are gone.
const raw = JSON.stringify([SCREENS, FLOWS, ELEMENTS, VERSIONS]);
ok(!raw.includes('"h2b"'), "no h2b primitives remain");
ok(raw.includes('"hero"'), "the hero primitive is in use");
ok(!raw.includes("&nbsp;"), "no crude nbsp spacers remain");

// On a full-screen hero sheet the fine print sits directly above the CTA,
// which is where Flighty puts it. Scoped to sheets carrying a `hero`: on a
// settings page a `fine` is a footnote *under* the row it explains, which is
// the opposite order and equally correct.
let sheets = 0;
for (const v of VERSIONS)
  for (const [, l] of resolveView(v[0], "screens"))
    for (const [id, , , sp] of l) {
      const body = (sp && sp.body) || [];
      if (!body.some((b) => b && b.t === "hero")) continue;
      const fine = body.findIndex((b) => b && b.t === "fine");
      const btn = body.findIndex((b) => b && b.t === "plrow" && b.full);
      if (fine >= 0 && btn >= 0) {
        ok(fine < btn, v[0] + "/" + id + ": fine print precedes the CTA");
        sheets++;
      }
    }
ok(sheets > 0, "found hero sheets with both fine print and a CTA (" + sheets + ")");

// A `push` pins content to the floor. Only a real mark — `sduo` or `illus` —
// can carry the space that opens up; a `hero` is just a headline. Without one
// the pin frames the emptiness instead of using it, which is what made
// `manage-friend`, `invite-code` and `invite-dead` read as broken.
//
// Checked over flow steps as well as screens: the steps carry their own specs,
// so fixing a screen does not reach the strip that redraws it, and the first
// version of this assertion missed three pinned steps for exactly that reason.
let pinned = 0;
const pinCheck = (where, sp) => {
  const body = (sp && sp.body) || [];
  if (!body.some((b) => b && b.t === "push")) return;
  pinned++;
  ok(
    body.some((b) => b && ["sduo", "illus"].includes(b.t)),
    where + ": pins to the floor, so it must carry a mark",
  );
};
for (const v of VERSIONS) {
  for (const [, l] of resolveView(v[0], "screens"))
    for (const [id, , , sp] of l) pinCheck(v[0] + "/" + id, sp);
  for (const [, l] of resolveView(v[0], "flows"))
    for (const [id, , , steps] of l)
      (steps || []).forEach(([sn, , sp], i) =>
        pinCheck(v[0] + "/" + id + " step " + (i + 1) + " (" + sn + ")", sp),
      );
}
ok(pinned > 0, "found frames that pin to the floor (" + pinned + ")");

// A headline with no copy under it is a thin frame. This is the rule that three
// separate stale flow steps broke: a step carries its own spec, so fixing a
// screen never reaches the strip that redraws it, and "invite-sheet" step 01
// slipped past the pin rule above precisely *because* it carries a mark. Checked
// over steps as well as screens, for the same reason.
let headlined = 0;
const thinCheck = (where, sp) => {
  const body = (sp && sp.body) || [];
  if (!body.some((b) => b && b.t === "hero")) return;
  headlined++;
  const copy = body.filter((b) => b && (b.t === "text" || b.t === "hint"));
  ok(copy.length > 0, where + ": has a headline, so it must carry copy");
  for (const c of copy)
    ok(
      typeof c.v === "string" && c.v.length > 25,
      where + ": copy is a real sentence, not a stub",
    );
};
for (const v of VERSIONS) {
  for (const [, l] of resolveView(v[0], "screens"))
    for (const [id, , , sp] of l) thinCheck(v[0] + "/" + id, sp);
  for (const [, l] of resolveView(v[0], "flows"))
    for (const [id, , , steps] of l)
      (steps || []).forEach(([sn, , sp], i) =>
        thinCheck(v[0] + "/" + id + " step " + (i + 1) + " (" + sn + ")", sp),
      );
}
ok(headlined > 0, "found frames carrying a headline (" + headlined + ")");

// The invite step is an explicit projection of the screen body, not a copy.
// Three duplicates drifted before these bodies were shared; the only allowed
// difference now is the typed-code fallback, which cannot be read at the flow
// strip's review scale. Everything retained is the same object, in the same
// order, so copy still cannot drift.
for (const v of VERSIONS) {
  const screen = new Map(
    resolveView(v[0], "screens").flatMap(([, l]) => l.map((it) => [it[0], it[3]])),
  ).get("invite-sheet");
  const step = resolveView(v[0], "flows")
    .flatMap(([, l]) => l)
    .find((it) => it[0] === "invite-installed")[3][0][2];
  ok(screen && step, v[0] + ": both the invite sheet and its first step exist");
  const expected = screen.body.filter((b) => !b.code);
  eq(step.body.length, expected.length, v[0] + ": the compact invite omits exactly one block");
  ok(
    step.body.every((b, i) => b === expected[i]),
    v[0] + ": every retained invite block is the screen's exact object",
  );
  eq(
    screen.body.filter((b) => b.code).length,
    1,
    v[0] + ": the full screen has exactly one code fallback to omit",
  );
  eq(
    step.body.filter((b) => b.t === "text").length,
    2,
    v[0] + ": the compact invite keeps both descriptive paragraphs",
  );
  eq(
    step.body.filter((b) => b.t === "fine").length,
    1,
    v[0] + ": the compact invite keeps the expiry/removal contract",
  );
}

// The confirm is the app's native alert, not a page.
const byId = new Map(
  resolveView(VROOT, "screens").flatMap(([, l]) => l.map((it) => [it[0], it[3]])),
);
const confirm = byId.get("manage-remove");
ok(confirm && confirm.alert, "manage-remove is drawn as an alert");
eq(confirm.alert.actions.length, 2, "the alert has two actions");
eq(confirm.alert.actions[0].l, "Cancel", "Cancel comes first, as iOS orders it");
eq(confirm.alert.actions[1].k, "dgr", "the destructive action is marked");
ok(
  confirm.body === byId.get("manage-friend").body,
  "the confirm reuses the screen underneath rather than a second copy",
);

// A visit keeps its tab bar, and Friends stays lit. This was drawn without one
// on the strength of a handoff note; `shell_chrome_provider.dart:56-62` records
// that hiding it existed and was deliberately removed, because no tab changes
// meaning inside a visit and selecting Library or Card is how you leave. The
// bug was structural — `frame()` made `bar.visit` imply no tabs — so it was
// wrong on every visit frame at once, which is why this is asserted and not
// merely fixed.
let visits = 0;
const visitCheck = (where, sp) => {
  if (!(sp && sp.bar && sp.bar.visit)) return;
  visits++;
  ok(sp.tabs !== false, where + ": a visit keeps its tab bar");
  eq(sp.tab, "Friends", where + ": Friends is the live tab on a visit");
};
for (const v of VERSIONS) {
  for (const [, l] of resolveView(v[0], "screens"))
    for (const [id, , , sp] of l) visitCheck(v[0] + "/" + id, sp);
  for (const [, l] of resolveView(v[0], "flows"))
    for (const [id, , , steps] of l)
      (steps || []).forEach(([sn, , sp], i) =>
        visitCheck(v[0] + "/" + id + " step " + (i + 1) + " (" + sn + ")", sp),
      );
}
ok(visits > 0, "found frames drawing a visit (" + visits + ")");

// The visit bar's trailing group, asserted against rendered markup rather than
// spec data, because `frame()` builds it and no spec field describes it. Poke is
// a `brandFill` pill (home_page.dart:1009-1023), not the circular icon this page
// drew for a while, and the gear beside it is where `manage-friend` is reached
// from now that the long press is gone.
const visitHtml = frame({
  bar: { visit: true, title: "지수's Library" },
  tab: "Friends",
  body: [],
});
ok(visitHtml.includes("&#9881;"), "a visit bar carries the gear");
ok(
  visitHtml.includes('<span class="pl brand">Poke</span>'),
  "Poke is a brandFill pill, not an icon",
);
ok(
  visitHtml.indexOf("&#9881;") < visitHtml.indexOf('class="pl brand"'),
  "the gear sits inboard of Poke, so the primary action is outermost",
);
ok(!visitHtml.includes("\u{1F449}"), "the old pointing-hand Poke icon is gone");
ok(visitHtml.includes("&#10005;"), "a visit bar still leads with the close");

// The long press is retired, not merely bypassed: two paths to one screen is
// worse than one invisible path.
const allNotes = JSON.stringify([SCREENS, FLOWS, ELEMENTS, VERSIONS]);
ok(
  !/long-press(ing)? a Friends row/i.test(allNotes),
  "nothing still describes the long press as the way in",
);

// Backticks are markdown, and nothing here renders markdown. A note written
// with `code` spans instead of <code> ships the punctuation to the reader —
// visible in the flow strip as a literal `AlertDialog.adaptive`. Notes are
// checked, not the CSS comments above them, so this walks the data only.
const noteFields = [];
for (const v of VERSIONS) {
  for (const k of ["screens", "elements"])
    for (const [, l] of resolveView(v[0], k))
      for (const [id, nm, ds] of l) noteFields.push([v[0] + "/" + id, nm, ds]);
  for (const [, l] of resolveView(v[0], "flows"))
    for (const [id, nm, ds, steps] of l) {
      noteFields.push([v[0] + "/" + id, nm, ds]);
      (steps || []).forEach(([sn, sc], i) =>
        noteFields.push([v[0] + "/" + id + " step " + (i + 1), sn, sc]),
      );
    }
}
for (const [where, nm, ds] of noteFields) {
  ok(!/`/.test(nm || ""), where + ": name has no literal backtick");
  ok(!/`/.test(ds || ""), where + ": note uses <code>, not a markdown backtick");
}
ok(noteFields.length > 0, "walked the notes (" + noteFields.length + ")");

// Every var() the frames reference must actually be declared on :root. An
// undefined custom property inherits silently rather than failing, which is how
// the destructive alert action rendered in Cancel's near-black: the rule said
// `--softRed`, after the Dart name, and this file calls it `--danger`.
const cssText = STYLE_TEXT;
const declared = new Set(
  [...cssText.matchAll(/^\s*(--[a-z0-9-]+)\s*:/gim)].map((m) => m[1]),
);
const referenced = new Set(
  [...cssText.matchAll(/var\(\s*(--[a-z0-9-]+)/g)].map((m) => m[1]),
);
// Set per-element by the renderer rather than on :root — a book's cover colour
// and its height jitter. Both always ship with a fallback-free inline value on
// the same element, so they cannot inherit from nothing.
const INLINE_VARS = new Set(["--c", "--hf"]);
ok(declared.size > 10, "found the custom properties (" + declared.size + ")");
for (const name of [...referenced].sort()) {
  if (INLINE_VARS.has(name)) {
    ok(
      new RegExp('style="[^"]*' + name + ':').test(block({ t: "shelf", n: 1 })),
      "var(" + name + ") is set inline by the renderer",
    );
    continue;
  }
  ok(declared.has(name), "var(" + name + ") is declared, not silently inherited");
}

console.log("assertions passed:", pass);
if (fails.length) {
  console.log("FAILURES (" + fails.length + "):");
  for (const f of fails.slice(0, 40)) console.log("  - " + f);
  process.exit(1);
}
"""

bundle = os.path.join(TMP, "bundle.js")
open(bundle, "w", encoding="utf-8").write(
    STUB
    + "\nglobalThis.STYLE_TEXT = "
    + json.dumps(style_text)
    + ";\n"
    + script
    + "\n"
    + ASSERT
)
r = subprocess.run(["node", bundle], capture_output=True, text=True)
print(r.stdout.strip())
if r.stderr.strip():
    print("stderr:", r.stderr.strip()[:4000])
raise SystemExit(r.returncode)
