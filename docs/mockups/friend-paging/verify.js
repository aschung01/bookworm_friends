/*
 * Mechanical verification for docs/mockups/friend-paging/index.html.
 *
 *   node docs/mockups/friend-paging/verify.js
 *
 * Runs the page's own script against a DOM stub, so every top-level render
 * path executes, then asserts the things that broke while building it:
 *
 *  - version inheritance and removal, in both directions of the diff
 *  - that every flow step referencing a screen resolves (screenSpec throws
 *    loudly if it does not, but only for the root version)
 *  - that real search queries reach the ids a reviewer would expect
 *  - that the two claims the page is *about* are actually drawn: a mid-slide
 *    frame with a shifted pane exists in `main` and does not survive either
 *    fix, and no `swept` cell survives either fix
 *
 * Interactive behaviour (hover, keyboard, scroll-spy) is not checked here.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const FILE = path.join(__dirname, "index.html");
const html = fs.readFileSync(FILE, "utf8");

/* The \s*\n matters: without it this matches the literal "<script>" that the
   file mentions inside its own leading HTML comment. */
const m = html.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) fail("could not extract the page script");
const js = m[1];

let failures = 0;
function fail(msg) {
  failures++;
  console.log("  FAIL  " + msg);
}
function ok(msg) {
  console.log("  ok    " + msg);
}
function eq(actual, expected, msg) {
  const a = JSON.stringify(actual),
    b = JSON.stringify(expected);
  a === b ? ok(msg) : fail(`${msg}\n          got ${a}\n          want ${b}`);
}
function truthy(v, msg) {
  v ? ok(msg) : fail(msg);
}

/* ---------- 1. the script parses, and its template literals balance ---------- */
if (js.split("`").length % 2 === 0)
  fail("odd number of backticks — an unterminated template literal");
else ok("backticks balance");

/* ---------- 2. DOM stub, so load-time render paths execute ---------- */
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
const nodes = new Map();
const sandbox = {
  console,
  document: {
    getElementById(id) {
      if (!nodes.has(id)) nodes.set(id, mk());
      return nodes.get(id);
    },
    querySelectorAll: () => [],
    addEventListener() {},
    body: { scrollHeight: 1000 },
    activeElement: null,
  },
  window: {
    addEventListener() {},
    scrollTo() {},
    innerHeight: 800,
    scrollY: 0,
  },
  requestAnimationFrame: (f) => f(),
  Event: class {
    constructor(t) {
      this.type = t;
    }
  },
};
sandbox.globalThis = sandbox;

const ctx = vm.createContext(sandbox);
/* `const`/`function` at the top level of a script do not become properties of
   the global object, so the page's own identifiers are invisible from out here.
   Appending one assignment is enough, and it runs in the same script so the
   lexical scope is still in view. */
const EXPORTS = [
  "SCREENS",
  "FLOWS",
  "ELEMENTS",
  "VERSIONS",
  "OPEN",
  "resolveView",
  "resolveOpen",
  "diffMap",
  "matchWords",
  "flowSearchText",
  "frame",
  "track",
];
const probe = `\n;globalThis.__x = { ${EXPORTS.join(", ")} };\n`;
try {
  vm.runInContext(js + probe, ctx, {
    filename: "friend-paging/index.html",
  });
  ok("script runs to completion against the DOM stub");
} catch (e) {
  fail("script threw at load: " + e.message);
  console.log(e.stack);
  process.exit(1);
}

const {
  SCREENS,
  FLOWS,
  ELEMENTS,
  VERSIONS,
  OPEN,
  resolveView,
  resolveOpen,
  diffMap,
  matchWords,
  flowSearchText,
  frame,
} = ctx.__x;

/* ---------- 3. shape of the data ---------- */
const ids = (view, v) =>
  resolveView(v, view).flatMap(([, l]) => l.map(([id]) => id));

eq(
  VERSIONS.map((v) => v[0]),
  [
    "main",
    "visit-scoped",
    "pager-in-visit",
    "sheet-switcher",
    "switcher-drilldown",
  ],
  "five versions, main first",
);
eq(VERSIONS[0][3], null, "main is the root (null parent)");
eq(
  VERSIONS.find((v) => v[0] === "switcher-drilldown")[3],
  "sheet-switcher",
  "switcher-drilldown branches off sheet-switcher, not off main",
);
/* A chained patch must inherit through its whole ancestry: the drilldown branch
   never restates the rail's deletion, so if that stops arriving the chain has
   broken. */
truthy(
  !ids("screens", "switcher-drilldown").includes("swipe-mid") &&
    !ids("screens", "switcher-drilldown").includes("visit-swipe"),
  "switcher-drilldown inherits sheet-switcher's deletions through the chain",
);

/* ---------- 4. inheritance and removal ---------- */
const mainScreens = ids("screens", "main");
const vsScreens = ids("screens", "visit-scoped");
const pivScreens = ids("screens", "pager-in-visit");
const ssScreens = ids("screens", "sheet-switcher");

truthy(
  mainScreens.includes("swipe-mid") && mainScreens.includes("sweep-2"),
  "main draws the defect frames (swipe-mid, sweep-2)",
);
for (const [v, list] of [
  ["visit-scoped", vsScreens],
  ["pager-in-visit", pivScreens],
  ["sheet-switcher", ssScreens],
])
  truthy(
    !list.includes("swipe-mid") && !list.includes("sweep-2"),
    `${v} removes them`,
  );
truthy(
  vsScreens.includes("tap-adjacent"),
  "visit-scoped adds tap-adjacent, grouped with bug 2",
);
truthy(pivScreens.includes("visit-enter"), "pager-in-visit adds visit-enter");
/* The three screens the branch exists to show, plus the two that state its
   prerequisite and its majority case. If any of these vanish the branch is no
   longer making its own argument. */
for (const id of [
  "visit-browse",
  "visit-card",
  "switch-cold",
  "switch-warm",
  "empty-nofriends",
])
  truthy(ssScreens.includes(id), `sheet-switcher adds ${id}`);
/* The lateral gesture survives the two pager fixes and dies in this one — which
   is the whole difference between gating the axis and deleting it. */
truthy(
  vsScreens.includes("visit-swipe") && pivScreens.includes("visit-swipe"),
  "visit-swipe is inherited by both pager branches, not restated",
);
truthy(
  !ssScreens.includes("visit-swipe"),
  "sheet-switcher removes visit-swipe — the gesture is gone, not gated",
);

/* An addition must land in a real group, never in "Added in <label>". */
for (const v of ["visit-scoped", "pager-in-visit"]) {
  const groups = resolveView(v, "screens").map(([g]) => g);
  truthy(
    !groups.some((g) => g.startsWith("Added in")),
    `${v}: every addition names an existing group`,
  );
}

/* ---------- 5. the diff reads the same both ways ---------- */
const a = diffMap("main", "visit-scoped", "screens");
const b = diffMap("visit-scoped", "main", "screens");
eq(a.get("swipe-mid"), "onlyHere", "main vs visit-scoped: swipe-mid only here");
eq(
  b.get("swipe-mid"),
  "onlyThere",
  "visit-scoped vs main: swipe-mid only there (mirrored)",
);
eq(
  b.get("tap-adjacent"),
  "onlyHere",
  "visit-scoped vs main: tap-adjacent only here",
);
eq(a.get("visit-swipe"), undefined, "an inherited screen reports no change");
eq(a.get("lib-rest"), "changed", "a patched screen reports changed");
/* Branch-to-branch, not just against the root: the two proposals must be
   comparable with each other, since that is the choice being made. */
const c = diffMap("sheet-switcher", "visit-scoped", "screens");
eq(
  c.get("visit-browse"),
  "onlyHere",
  "sheet-switcher vs visit-scoped: visit-browse only here",
);
eq(
  c.get("tap-adjacent"),
  "onlyThere",
  "sheet-switcher vs visit-scoped: tap-adjacent only there",
);
eq(
  c.get("visit-swipe"),
  "onlyThere",
  "sheet-switcher vs visit-scoped: the swipe survives only in the other branch",
);

/* ---------- 6. open callouts ---------- */
truthy(
  "f-accidental" in resolveOpen("main"),
  "main flags the open question on f-accidental",
);
truthy(
  !("f-accidental" in resolveOpen("visit-scoped")),
  "visit-scoped clears it (the branch answers it)",
);
truthy(
  "tap-adjacent" in resolveOpen("visit-scoped"),
  "visit-scoped raises its own open question",
);
truthy(
  "visit-enter" in resolveOpen("pager-in-visit"),
  "pager-in-visit raises the exit question its shape creates",
);
truthy(
  "switch-cold" in resolveOpen("sheet-switcher") &&
    "visit-card" in resolveOpen("sheet-switcher"),
  "sheet-switcher raises its prerequisite and its loose end",
);
truthy(
  !("f-sweep" in resolveOpen("sheet-switcher")),
  "sheet-switcher clears the cut-or-fade question (nothing travels)",
);
/* Every callout must attach to something that is actually rendered. */
for (const v of VERSIONS.map((x) => x[0])) {
  const all = new Set([
    ...ids("screens", v),
    ...ids("flows", v),
    ...ids("elements", v),
  ]);
  const orphans = Object.keys(resolveOpen(v)).filter((k) => !all.has(k));
  eq(orphans, [], `${v}: no open callout points at a missing id`);
}

/* ---------- 7. every frame renders, and renders something ---------- */
let frames = 0;
for (const v of VERSIONS.map((x) => x[0])) {
  for (const [, list] of resolveView(v, "screens"))
    for (const [id, , , spec] of list) {
      const out = frame(spec);
      frames++;
      if (!out || out.length < 40) fail(`${v}/${id}: empty frame`);
    }
  for (const [, list] of resolveView(v, "flows"))
    for (const [id, , , steps] of list)
      steps.forEach(([, , spec], i) => {
        const out = frame(spec);
        frames++;
        if (!out || out.length < 40)
          fail(`${v}/${id} step ${i + 1}: empty frame`);
      });
}
ok(`${frames} frames render non-empty across all ${VERSIONS.length} versions`);

/* ---------- 8. the claims the page is about are really drawn ---------- */
const rendered = (v, kind) =>
  resolveView(v, kind)
    .flatMap(([, l]) => l)
    .map(([id, , , payload]) => [
      id,
      kind === "flows"
        ? payload.map(([, , s]) => frame(s)).join("")
        : frame(payload),
    ]);

const hasIn = (v, kind, needle) =>
  rendered(v, kind).filter(([, h]) => h.includes(needle)).length;

/* The 56pt shove: a pane drawn shifted, only reachable in main. */
truthy(
  hasIn("main", "screens", "pg shifted") > 0,
  "main draws a pane shifted by the rail row (bug 1's mid-drag frame)",
);
eq(
  hasIn("visit-scoped", "screens", "pg shifted"),
  0,
  "visit-scoped has no shifted pane left",
);
eq(
  hasIn("pager-in-visit", "screens", "pg shifted"),
  0,
  "pager-in-visit has no shifted pane left",
);

/* Swept pages: mounted and discarded. Must not survive either fix. */
truthy(
  hasIn("main", "screens", "tpg swept") > 0,
  "main marks the swept intermediate pages on the filmstrip",
);
eq(
  hasIn("visit-scoped", "screens", "tpg swept"),
  0,
  "visit-scoped sweeps nothing",
);
eq(
  hasIn("pager-in-visit", "screens", "tpg swept"),
  0,
  "pager-in-visit sweeps nothing",
);

/* A blocked gesture is the *proposal's* whole visible content, so if it is
   missing the fix is not drawn at all. */
eq(hasIn("main", "screens", "gs blocked"), 0, "main blocks no gesture");
truthy(
  hasIn("visit-scoped", "screens", "gs blocked") >= 3,
  "visit-scoped draws all three leak surfaces declined",
);

/* main's own filmstrip must show your own library as index 0 of the pager — the
   premise both bugs rest on. Neither restructuring branch may. */
truthy(
  hasIn("main", "screens", "tpg self") > 0,
  "main puts your own library on the pager axis",
);
eq(
  hasIn("pager-in-visit", "screens", "tpg self"),
  0,
  "pager-in-visit takes your library off the axis",
);

/* sheet-switcher's specific claims. The head row is the only exit once the rail
   is deleted, so it has to appear on every screen that shows the list — if it
   is missing from one, that screen is a visit with no way out. */
const ssListScreens = rendered("sheet-switcher", "screens").filter(([, h]) =>
  h.includes("erow"),
);
truthy(
  ssListScreens.length >= 4,
  "sheet-switcher draws the list on 4+ screens",
);
for (const [id, h] of ssListScreens)
  if (!h.includes("erow me") && !h.includes("emptymsg"))
    fail(`sheet-switcher/${id}: friends list with no My Library head row`);
ok("every sheet-switcher list carries the My Library head row");
/* The collapsed switcher must show the head row plus two friends. At the shared
   20% floor it would show 1.6 rows, so if this drops to 2 the drawing has
   silently gone back to claiming today's default is a usable switcher. */
for (const id of ["tap-landed", "switch-cold", "switch-warm"]) {
  const h = rendered("sheet-switcher", "screens").find(([i]) => i === id)?.[1];
  eq(
    (h?.match(/class="erow/g) || []).length,
    3,
    `sheet-switcher/${id}: collapsed switcher shows head row + 2 friends`,
  );
}

/* Rows must actually fit inside the sheet, above the tab bar's reserve.

   This exists because the switcher was first drawn at 44% and the third row sat
   *behind* the floating bar — invisible to every other check in this file and
   caught only by screenshotting. The constants mirror SECTION 1's CSS (.sheet
   padding 5/32, .hdl 3+6, .sh2 ~19, .caps ~21, .erow ~29), so this is arithmetic
   against the stylesheet rather than real layout: it catches a height that is
   clearly too small, not a one-pixel overlap. */
const SHEET_PAD_TOP = 5,
  SHEET_RESERVE = 32,
  HANDLE = 9,
  HDR = 19,
  CAPS = 21,
  ROW = 29;
/** Rows a spec's sheet renders, or 0 if it is not a row-bearing sheet. */
function sheetRowCount(spec) {
  const b = spec.sheet && spec.sheet.body;
  if (!b || b.type !== "everyone") return 0;
  return (b.rows ? b.rows.length : 4) + (b.me ? 1 : 0);
}
let fitted = 0;
for (const v of VERSIONS.map((x) => x[0])) {
  const check = (id, spec) => {
    const rows = sheetRowCount(spec);
    if (!rows) return;
    const sh = spec.sheet;
    const box = sh.px ?? (sh.h / 100) * (spec.sm ? 292 : 340);
    const need =
      SHEET_PAD_TOP +
      HANDLE +
      (sh.hdr ? HDR : 0) +
      (sh.caps ? CAPS : 0) +
      rows * ROW +
      SHEET_RESERVE;
    fitted++;
    if (box < need)
      fail(
        `${v}/${id}: sheet is ${box.toFixed(0)}px but ${rows} rows plus the ` +
          `tab-bar reserve need ~${need}px — the last row lands behind the bar`,
      );
  };
  for (const [, list] of resolveView(v, "screens"))
    for (const [id, , , spec] of list) check(id, spec);
  for (const [, list] of resolveView(v, "flows"))
    for (const [id, , , steps] of list)
      steps.forEach(([, , spec], i) => check(`${id} step ${i + 1}`, spec));
}
ok(`${fitted} row-bearing sheets are tall enough for their rows`);

/* ---------- main must describe the app as it is ----------

   The whole value of the version machinery is that `main` is reality and the
   branches are proposals. Nothing enforced that, and two proposed controls look
   enough like existing ones to leak: the Friends list's My Library head row
   (`friends_sheet.dart` builds `ListView.builder(itemCount: following.length)`
   and has no self row) and the bar's leading dismiss (the glyph exists, but in
   `FriendRail`, not in `_LibraryBar`, which sets
   `automaticallyImplyLeading: false` and has no leading widget). If either shows
   up in `main`, the page is lying about the current app. */
for (const [sel, what] of [
  ['class="erow me"', "a My Library head row"],
  ['class="dsm"', "a dismiss in the library bar"],
]) {
  for (const kind of ["screens", "flows"])
    eq(hasIn("main", kind, sel), 0, `main draws no ${what} in ${kind}`);
}
/* The pager branches change the axis, not the chrome, so neither may grow one
   either — those two controls belong to the switcher branches alone. */
for (const v of ["visit-scoped", "pager-in-visit"])
  eq(
    hasIn(v, "screens", 'class="erow me"') + hasIn(v, "screens", 'class="dsm"'),
    0,
    `${v} keeps the rail's chrome, so it adds neither new control`,
  );
/* And each switcher branch must carry its own inventory of what it is adding,
   since that is the claim a reviewer prices the branch against. */
for (const v of ["sheet-switcher", "switcher-drilldown"])
  truthy(
    ids("elements", v).includes("el-new-work"),
    `${v} states what does not exist yet`,
  );
truthy(
  !ids("elements", "main").includes("el-new-work"),
  "main has nothing to state — it is the app",
);

/* ---------- Every visit must have a visible way out ----------

   This is the check that would have caught the hole this branch shipped with:
   the exit was put in the Friends list's head row, which exists on one of three
   tabs, so a visit on the Library or Card tab was a state with no visible exit.
   `PopScope` handles the iOS back-swipe, but an invisible gesture is not an
   affordance. A screen counts as having an exit if it carries the bar's dismiss,
   the rail's x, a sheet-header back, or the My Library head row. */
const EXITS = [
  ['class="dsm"', "bar dismiss"],
  ['class="rlead glass"', "rail x"],
  ['class="hb"', "sheet back"],
  ['class="erow me"', "My Library row"],
];
let visits = 0;
for (const v of VERSIONS.map((x) => x[0])) {
  const check = (id, spec, html) => {
    /* A visit is any frame whose bar names a friend. */
    if (!spec.bar || spec.bar.kind !== "friend") return;
    visits++;
    if (!EXITS.some(([sel]) => html.includes(sel)))
      fail(
        `${v}/${id}: friend's library with no visible exit ` +
          `(no ${EXITS.map(([, n]) => n).join(", no ")})`,
      );
  };
  for (const [, list] of resolveView(v, "screens"))
    for (const [id, , , spec] of list) check(id, spec, frame(spec));
  for (const [, list] of resolveView(v, "flows"))
    for (const [id, , , steps] of list)
      steps.forEach(([, , spec], i) =>
        check(`${id} step ${i + 1}`, spec, frame(spec)),
      );
}
ok(`${visits} friend-library frames all carry a visible exit`);

/* And the exit must not be tab-dependent in the branches that delete the rail:
   the bar carries it, so it is there whichever tab is lit.

   The tab *coverage* differs between them, and that difference is each branch's
   defining claim rather than an accident. `sheet-switcher` lets Library and Card
   re-scope to the friend, so a visit exists on several tabs. `switcher-drilldown`
   makes those two tabs end the visit, so a visit can only ever be on Friends — if
   a friend's library ever showed up there on another tab, that branch would have
   collapsed into the other one. */
const VISIT_TABS = { "sheet-switcher": 3, "switcher-drilldown": 1 };
for (const [v, expected] of Object.entries(VISIT_TABS)) {
  const visitScreens = resolveView(v, "screens")
    .flatMap(([, l]) => l)
    .filter(([, , , spec]) => spec.bar && spec.bar.kind === "friend");
  const tabs = new Set(visitScreens.map(([, , , s]) => s.tab).filter(Boolean));
  eq(
    tabs.size,
    expected,
    `${v}: a visit appears on ${expected} tab(s) (${[...tabs].sort().join(", ")})`,
  );
  for (const [id, , , spec] of visitScreens)
    if (!frame(spec).includes('class="dsm"'))
      fail(`${v}/${id}: exit is not in the bar, so it depends on the tab`);
}
ok("both switcher branches carry the exit in the bar, on every tab");
/* No branch may keep a rail: the rail row is exactly what is being deleted. */
eq(
  hasIn("sheet-switcher", "screens", 'class="rail"'),
  0,
  "sheet-switcher draws no rail anywhere",
);
truthy(
  hasIn("main", "screens", 'class="rail"') > 0,
  "main does draw the rail (so the deletion is a real diff)",
);
/* The tab bar's return is the decision this branch reopens, so it must be
   visible on the visit screens rather than only asserted in prose. */
for (const id of ["tap-landed", "visit-rest", "visit-card", "visit-browse"]) {
  const h = rendered("sheet-switcher", "screens").find(([i]) => i === id)?.[1];
  truthy(
    h && h.includes('class="tb"'),
    `sheet-switcher/${id}: tab bar present inside a visit`,
  );
}
/* The prerequisite, drawn both ways round. */
truthy(
  hasIn("sheet-switcher", "screens", "spinlbl") > 0,
  "sheet-switcher draws the uncached switch (switch-cold)",
);
truthy(
  hasIn("sheet-switcher", "screens", "well stale") > 0,
  "sheet-switcher draws the held switch (switch-warm)",
);
truthy(
  hasIn("sheet-switcher", "screens", "emptymsg") > 0,
  "sheet-switcher draws the no-friends majority case",
);
/* A friend's Card must show *her* figures, not yours — the incoherent option. */
const card = rendered("sheet-switcher", "screens").find(
  ([i]) => i === "visit-card",
)?.[1];
truthy(
  card && card.includes("hana") && !card.includes("All-time library card"),
  "visit-card shows hers, not your all-time card",
);
truthy(
  card && !card.includes('<span class="ic">&#8593;</span>'),
  "visit-card suppresses the share button",
);

/* ---------- 9. overlays stay inside the frame, at both sizes ---------- */
/* The bug this catches: overlay coordinates are authored against the 340px
   frame, and flow steps render the same specs at `sm` (292px). Before frame()
   scaled them, the gesture glyph on `leak-pile` hung off the bottom of the
   phone in the Flows view while looking correct in Screens. */
let overlays = 0;
for (const v of VERSIONS.map((x) => x[0])) {
  const check = (id, spec) => {
    const phH = spec.sm ? 292 : 340;
    const html = frame(spec);
    for (const cls of ["gs", "tapring", "measured"]) {
      const re = new RegExp(
        `class="${cls}[^"]*"\\s+style="top:([0-9.]+)px`,
        "g",
      );
      let mm;
      while ((mm = re.exec(html))) {
        overlays++;
        const top = parseFloat(mm[1]);
        if (top < 0 || top > phH - 18)
          fail(
            `${v}/${id}: .${cls} at top ${top}px falls outside a ${phH}px frame`,
          );
      }
    }
  };
  for (const [, list] of resolveView(v, "screens"))
    for (const [id, , , spec] of list) check(id, spec);
  for (const [, list] of resolveView(v, "flows"))
    for (const [id, , , steps] of list)
      steps.forEach(([, , spec], i) => check(`${id} step ${i + 1}`, spec));
}
ok(`${overlays} overlay placements sit inside their frame`);

/* ---------- 10. search resolves to what a reviewer would type ---------- */
function flowHits(v, q) {
  const out = [];
  for (const [g, list] of resolveView(v, "flows"))
    for (const [id, nm, ds, steps] of list)
      if (matchWords(flowSearchText(g, nm, ds, steps), q.toLowerCase()))
        out.push(id);
  return out;
}
const cases = [
  ["swipe", ["f-accidental", "f-switch"]],
  ["sweep", ["f-sweep"]],
  ["shelf", ["f-leak"]],
  ["queries", ["f-sweep"]],
  ["visit", ["f-accidental", "f-switch"]],
];
for (const [q, want] of cases) {
  const got = flowHits("main", q);
  eq(got.sort(), want.slice().sort(), `search "${q}"`);
}
/* A term only the fix uses must find nothing in main and something in the fix. */
eq(flowHits("main", "jumpToPage"), [], 'main: "jumpToPage" finds nothing');
eq(
  flowHits("visit-scoped", "jumpToPage"),
  ["f-sweep"],
  'visit-scoped: "jumpToPage" finds the fixed sweep flow',
);

/* ---------- 11. counts, for the reply ---------- */
console.log(
  "\n  main: %d screens, %d flows, %d mechanisms",
  ids("screens", "main").length,
  ids("flows", "main").length,
  ids("elements", "main").length,
);
for (const v of [
  "visit-scoped",
  "pager-in-visit",
  "sheet-switcher",
  "switcher-drilldown",
])
  console.log(
    "  %s: %d screens, %d flows, %d changed vs main",
    v,
    ids("screens", v).length,
    ids("flows", v).length,
    [...diffMap(v, "main", "screens").values()].length,
  );

console.log(failures ? `\n${failures} FAILURE(S)\n` : "\nall checks passed\n");
process.exit(failures ? 1 : 0);
