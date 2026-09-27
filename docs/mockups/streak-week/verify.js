// Verification for docs/mockups/streak-week/index.html.
//
//     node docs/mockups/streak-week/verify.js
//
// The page is static, so most of it is checkable without a browser: extract the
// script, run it under a DOM stub so every top-level render path executes, then
// assert on the pure parts — the renderer, search, version inheritance and the
// diff. The engine's real API is `resolveView(vid, kind)` / `resolveOpen(vid)` /
// `diffMap(a, b, kind)`; screen and element search indexes name + note, flows go
// through `flowSearchText`.
//
// What this cannot check: hover, keyboard focus movement, scroll-spy. Those were
// looked at by eye; everything below is mechanical.

const fs = require("fs");
const path = require("path");

const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const m = html.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) {
  console.error("FAIL  could not extract the script block");
  process.exit(1);
}

let bad = 0;
const fail = (msg) => {
  console.error("FAIL  " + msg);
  bad++;
};
const ok = (msg) => console.log("ok    " + msg);
const eq = (actual, expected, msg) => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) ok(msg);
  else fail(`${msg}\n        expected ${e}\n        got      ${a}`);
};

// ---- the DOM stub ------------------------------------------------------------
const mk = () => ({
  _v: "",
  set innerHTML(v) {
    this._v = v;
  },
  get innerHTML() {
    return this._v;
  },
  textContent: "",
  hidden: false,
  value: "",
  placeholder: "",
  dataset: {},
  style: {},
  classList: {
    toggle() {},
    add() {},
    remove() {},
    contains() {
      return false;
    },
  },
  addEventListener() {},
  focus() {},
  blur() {},
  select() {},
  contains() {
    return false;
  },
  querySelectorAll() {
    return [];
  },
  querySelector() {
    return null;
  },
  closest() {
    return null;
  },
  getBoundingClientRect() {
    return { top: 0 };
  },
  scrollIntoView() {},
  nextElementSibling: null,
  tagName: "DIV",
});
const nodes = {};
global.document = {
  getElementById: (id) => (nodes[id] ||= mk()),
  querySelectorAll: () => [],
  addEventListener() {},
  body: { scrollHeight: 1000 },
  activeElement: null,
};
global.window = {
  addEventListener() {},
  scrollTo() {},
  innerHeight: 800,
  scrollY: 0,
};
global.requestAnimationFrame = (f) => f();
global.Event = class {
  constructor(t) {
    this.type = t;
  }
};

let api;
try {
  api = new Function(
    m[1] +
      `;return {SCREENS,FLOWS,ELEMENTS,VERSIONS,OPEN,block,frame,resolveView,
                resolveOpen,diffMap,matchWords,stripTags,flowSearchText};`,
  )();
  ok("the script loads under the DOM stub with no error");
} catch (e) {
  fail("load threw: " + e.message);
  process.exit(1);
}

const {
  SCREENS,
  FLOWS,
  ELEMENTS,
  OPEN,
  block,
  resolveView,
  resolveOpen,
  diffMap,
  matchWords,
  stripTags,
  flowSearchText,
} = api;

// ---- the data is shaped as the engine expects --------------------------------
const ids = (base) => base.flatMap(([, items]) => items.map((i) => i[0]));
const screenIds = ids(SCREENS);
const flowIds = ids(FLOWS);
const elIds = ids(ELEMENTS);

eq(new Set(screenIds).size, screenIds.length, "screen ids are unique");
eq(new Set(flowIds).size, flowIds.length, "flow ids are unique");
eq(new Set(elIds).size, elIds.length, "element ids are unique");
eq(screenIds.length, 21, "21 screens in the root version");
eq(flowIds.length, 2, "2 flows");
eq(elIds.length, 12, "12 elements");

// An OPEN key that names nothing renders no callout — the decision silently
// disappears, which is the failure mode the map exists to prevent.
const known = new Set([...screenIds, ...flowIds, ...elIds]);
const strays = Object.keys(OPEN).filter((id) => !known.has(id));
eq(strays, [], "every OPEN key names a real screen, flow or element");

// An OPEN key naming a real id is necessary but was not sufficient: the shell
// emitted the callout **only in the Flows view**, so a decision attached to a
// screen or an element rendered nothing whatsoever. Found by looking at the page,
// not by any assertion — the same class of defect as the shell's own note about a
// removed item being silently invisible. `render()` is patched; this pins it.
// `OPEN` here covers two screens, one element and one flow, so all three paths are
// exercised.
const rendered = {
  screens: nodes["screens"] && nodes["screens"].innerHTML,
  elements: nodes["elements"] && nodes["elements"].innerHTML,
  flows: nodes["flows"] && nodes["flows"].innerHTML,
};
for (const [kind, id] of [
  ["screens", "e-wait"],
  ["screens", "ctx-shipped"],
  ["elements", "el-label"],
  ["flows", "flow-record"],
]) {
  const html = rendered[kind] || "";
  const marker = OPEN[id].slice(0, 28);
  if (html.includes('class="pend"') && html.includes(marker))
    ok(`the open callout for ${id} actually renders in the ${kind} view`);
  else fail(`the open callout for ${id} renders nothing in the ${kind} view`);
}

// ---- the renderer draws what the notes claim --------------------------------
const w = (days, opts = {}) =>
  block(Object.assign({ t: "week", labels: days.map(() => "Sa"), days }, opts));

const read = w(["read"]);
if (read.includes("tok on") && read.includes("<svg"))
  ok("a read day is a filled token carrying the drawn check");
else fail("a read day did not render a filled token with a check");

const dashed = w(["today"], { dashed: true });
if (dashed.includes("dash") && !dashed.includes("<svg"))
  ok("a dashed today is a ring with no check");
else fail("dashed today rendered wrongly");

if (!w(["today"]).includes("dash"))
  ok("without the flag today is a flat disc — which is option A's cost, drawn");
else fail("today drew a ring without the dashed flag");

// Today is marked on the label in every variant, dashed or not.
if (w(["today"]).includes("lab now") && dashed.includes("lab now"))
  ok("today's label is marked in both A and B");
else fail("today's label lost its marker");

// The chain must span only *consecutive* read days, or it states something false.
const links = (s) => (s.match(/class="ln"/g) || []).length;
eq(
  links(w(["read", "read", "missed", "read"], { chain: true })),
  1,
  "read-read-missed-read draws one link, not two",
);
eq(
  links(w(["read", "read", "read"], { chain: true })),
  2,
  "a run of three draws two links",
);
eq(links(w(["read", "read"])), 0, "no chain without the flag");
// The last cell can never link forward off the end of the row.
eq(
  links(w(["missed", "read"], { chain: true })),
  0,
  "the final read day draws no link past the end of the row",
);
// A freshly stamped day joins the run it just extended.
eq(
  links(w(["read", "fresh"], { chain: true })),
  1,
  "a fresh stamp joins the run it extends",
);

// A circle cannot be raked. This is the whole reason option E exists, so pin it:
// the transform IS emitted on a circle, so the invisibility is geometry, not a
// missing branch that someone could "fix".
const rc = w(["read", "read"], { rake: true });
const rs = w(["read", "read"], { rake: true, token: "square" });
if (rc.includes("rotate") && !rc.includes("tok sq"))
  ok("the rake is emitted on circles too, so its invisibility is geometry");
else fail("expected a rake transform on the circle token");
if (rs.includes("sq") && rs.includes("rotate"))
  ok("the square token carries both its radius class and the rake");
else fail("the square token lost its class or its rake");
eq(
  w(["read"], { rake: true }),
  w(["read"], { rake: true }),
  "the rake is deterministic across renders, never random",
);

// The card's three Duolingo changes travel together per flag.
const card = block({ t: "card", edge: true, caption: "x", body: [] });
if (card.includes("card edge") && card.includes("rule") && card.includes("cap"))
  ok("an edged card draws its border, its divider and the caption inside");
else fail("the card is missing its edge, divider or inside caption");
const plain = block({ t: "card", body: [] });
if (!plain.includes("edge") && !plain.includes("rule"))
  ok("the shipped card has no edge and no divider");
else fail("the plain card drew chrome it should not have");

// The shipped row keeps its four distinct states, which is the thing being
// compared against — if these collapse, the comparison is against nothing.
const ship = block({
  t: "shipped",
  labels: ["S", "M", "T", "W"],
  days: ["read", "fresh", "today", "missed"],
});
for (const cls of ["on", "fresh", "today"])
  if (ship.includes(`class="${cls}"`))
    ok(`the shipped row still draws "${cls}"`);
  else fail(`the shipped row lost its "${cls}" state`);
if (ship.includes('class=""'))
  ok("a shipped missed day gets no class — the hairline only");
else fail("a shipped missed day picked up a class");

// ---- search resolves words a reader can see ---------------------------------
// Same predicate the combobox uses: a group name pulls in its whole contents,
// otherwise an item needs every query word in its own name or note.
function hits(kind, q, vid = "main") {
  const ql = q.trim().toLowerCase();
  const out = [];
  for (const [g, items] of resolveView(vid, kind)) {
    const gm = matchWords(g.toLowerCase(), ql);
    for (const [id, nm, ds] of items)
      if (gm || matchWords(stripTags(`${nm} ${ds || ""}`).toLowerCase(), ql))
        out.push(id);
  }
  return out;
}
function flowHits(q, vid = "main") {
  const ql = q.trim().toLowerCase();
  const out = [];
  for (const [g, items] of resolveView(vid, "flows"))
    for (const [id, nm, ds, steps] of items)
      if (matchWords(flowSearchText(g, nm, ds, steps), ql)) out.push(id);
  return out;
}

eq(
  hits("screens", "affordance"),
  ["a-wait"],
  '"affordance" finds where it is lost',
);
eq(
  hits("elements", "1.67"),
  ["el-read"],
  "the measured contrast figures are searchable",
);
eq(
  hits("elements", "korean").sort(),
  ["el-label", "el-span"],
  '"korean" finds both places a Korean noun is a problem',
);
// **The record of what shipped has to be findable from the defect, not only from the
// feature.** Both entries below exist because a rendering found something a green suite
// could not, and the point of writing them down is that the next person searching for the
// symptom lands on the cause.
eq(
  hits("elements", "7.41"),
  ["el-built"],
  "the shipped label's measured contrast is searchable",
);
eq(
  hits("elements", "fractionallysizedbox"),
  ["el-found"],
  "the collapsed progress bar is findable by the widget that caused it",
);
eq(
  hits("elements", "narrowweekdays"),
  ["el-label"],
  "the one-letter decision is findable by the API it rests on",
);
eq(flowHits("stamp"), ["flow-stamp"], '"stamp" finds the stamping flow');
eq(flowHits("tap"), ["flow-record"], '"tap" finds the recording flow');
eq(hits("screens", "zzz"), [], "a nonsense query matches nothing");
// Order-independent AND, which is what the engine promises.
eq(
  hits("screens", "chain run").sort(),
  hits("screens", "run chain").sort(),
  "search is order-independent",
);
for (const q of ["rake", "chain", "duolingo"])
  if (hits("screens", q).length >= 2) ok(`"${q}" finds more than one screen`);
  else fail(`"${q}" found ${hits("screens", q).length} screens, expected >= 2`);

// ---- versions: inheritance, removal, and the diff ---------------------------
const flat = (vid, kind = "screens") => {
  const map = new Map();
  resolveView(vid, kind).forEach(([, l]) =>
    l.forEach((it) => map.set(it[0], it)),
  );
  return map;
};
const main = flat("main");
const fwd = flat("forward");

eq(main.size, 21, "main resolves to its own 21 screens");
eq(fwd.size, 18, "forward drops the three gap screens (21 - 3)");
eq(
  ["shipped-gap", "a-gap", "c-gap"].filter((id) => fwd.has(id)),
  [],
  "null in a patch removes the screen",
);

// Unmentioned items must be inherited by value, not restated in the patch —
// restating is what reintroduces drift and makes the diff report false changes.
const untouched = ["ctx-shipped", "el-read"];
eq(
  JSON.stringify(main.get("ctx-shipped")),
  JSON.stringify(fwd.get("ctx-shipped")),
  "an unmentioned screen is inherited unchanged",
);
eq(
  JSON.stringify(flat("main", "elements").get("el-read")),
  JSON.stringify(flat("forward", "elements").get("el-read")),
  "elements are untouched by the window patch",
);
void untouched;

if (JSON.stringify(main.get("a-read")) !== JSON.stringify(fwd.get("a-read")))
  ok("a patched screen really differs from its parent");
else fail("a-read is identical in both versions — the patch did nothing");

// The diff must mirror exactly when run both ways, or the labels read backwards
// (a screen the other version deleted gets badged as new).
const d1 = diffMap("main", "forward", "screens");
const d2 = diffMap("forward", "main", "screens");
const pick = (d, kind) =>
  [...d.entries()]
    .filter(([, k]) => k === kind)
    .map(([id]) => id)
    .sort();

eq(
  pick(d1, "changed"),
  pick(d2, "changed"),
  "the changed set is direction-free",
);
eq(
  pick(d1, "onlyHere"),
  pick(d2, "onlyThere"),
  "only-here one way equals only-there the other",
);
eq(
  pick(d1, "onlyThere"),
  pick(d2, "onlyHere"),
  "and the mirror holds for the other side",
);
eq(
  pick(d1, "onlyHere"),
  ["a-gap", "c-gap", "shipped-gap"],
  "the gap screens exist only in main, viewed from main",
);
eq(pick(d1, "onlyThere"), [], "forward adds no screens of its own");

// Flows are patched too, and the patch must actually land.
const fd = diffMap("main", "forward", "flows");
eq(
  pick(fd, "changed"),
  ["flow-record"],
  "only the recording flow is repatched",
);

// The window decision has to be reachable as a callout from `forward`, and must
// not leak into `main`, where it would be claiming a decision that isn't posed.
const openF = resolveOpen("forward");
const openM = resolveOpen("main");
if (openF["a-read"])
  ok("the window decision renders as an open callout in forward");
else fail("forward's open callout for a-read is missing");
if (!openM["a-read"]) ok("and it does not appear in main");
else fail("the window callout leaked into main");
eq(
  Object.keys(openM).sort(),
  ["ctx-shipped", "e-wait", "el-label", "flow-record", "span-none", "span-row"],
  "main poses exactly the six open questions it should",
);

// (b)'s proposals are drawn in both windows, because leaving them on the backward
// week under `forward` would quietly make that version incoherent — and patching
// them is what surfaced the third argument against the forward window: it cannot
// show the span it is celebrating.
for (const id of ["ctx-record", "span-night"]) {
  if (
    fwd.has(id) &&
    JSON.stringify(main.get(id)) !== JSON.stringify(fwd.get(id))
  )
    ok(`${id} is redrawn for the forward window rather than inherited stale`);
  else fail(`${id} draws the backward week under forward`);
}

console.log(bad ? `\n${bad} check(s) failed` : "\nall checks passed");
process.exit(bad ? 1 : 0);
