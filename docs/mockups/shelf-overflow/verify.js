/**
 * Terminal verification for `index.html`.
 *
 * The page is static, so most of it can be checked without a browser: the
 * script is extracted, run against a DOM stub (which exercises every
 * top-level render path), and then the pure functions are asserted directly.
 *
 * Run: node verify.js
 *
 * What this CANNOT check: hover, scroll-spy, and anything about how the
 * drawing actually looks. Those were checked by eye.
 */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const js = /<script>\s*\n([\s\S]*?)\n\s*<\/script>/.exec(html)[1];

/* ---- DOM stub ---------------------------------------------------------- */
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

const sandbox = {
  console,
  document: {
    getElementById: () => mk(),
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
vm.createContext(sandbox);

/* Top-level `const` does not attach to the sandbox global the way a function
   declaration does, so the values under test are handed out explicitly. This
   runs as the last statement of the real script, in the real scope. */
const EXPORTS = [
  "SCREENS",
  "FLOWS",
  "ELEMENTS",
  "VERSIONS",
  "OPEN",
  "PER_SHELF",
  "WHOLE",
  "IT",
];
vm.runInContext(
  js + "\n;globalThis.__x={" + EXPORTS.join(",") + "};",
  sandbox,
  { filename: "index.html<script>" },
);
Object.assign(sandbox, sandbox.__x);

/* ---- assertions -------------------------------------------------------- */
let fails = 0;
function ok(label, cond, extra) {
  if (cond) {
    console.log("  PASS  " + label);
  } else {
    fails++;
    console.log("  FAIL  " + label + (extra ? "  -> " + extra : ""));
  }
}

const {
  SCREENS,
  FLOWS,
  ELEMENTS,
  OPEN,
  resolveView,
  resolveOpen,
  diffMap,
  matchWords,
} = sandbox;

/** Flatten resolveView's [group,[items]] into a Map of id -> item. */
function viewIds(vid, kind) {
  const m = new Map();
  for (const [, items] of resolveView(vid, kind))
    for (const it of items) m.set(it[0], it);
  return m;
}
const resolve = (vid) => ({
  screens: viewIds(vid, "screens"),
  flows: viewIds(vid, "flows"),
  elements: viewIds(vid, "elements"),
});

console.log("\nload");
ok("script ran without throwing", true);

/* --- the packing constant is the page's thesis; check the arithmetic ---- */
console.log("\npacking arithmetic (the page's central claim)");
const screenW = 390,
  screenH = 844;
const bookH = screenH * 0.15;
const bookW = bookH * (2 / 3);
const rowW = screenW * 0.95 - 15 - 15;
const perBook = bookW + 15;
const fit = (rowW + 15) / perBook; // +15: the last book needs no trailing separator
ok(
  "bookHeight = screenHeight*0.15 = 126.6",
  Math.abs(bookH - 126.6) < 0.05,
  bookH,
);
ok("bookWidth = 2/3 of that = 84.4", Math.abs(bookW - 84.4) < 0.05, bookW);
ok("usable row width = 340.5", Math.abs(rowW - 340.5) < 0.05, rowW);
ok(
  "books that fit ~= 3.57, matching PER_SHELF",
  Math.abs(fit - sandbox.PER_SHELF) < 0.02,
  fit.toFixed(3) + " vs " + sandbox.PER_SHELF,
);
ok("WHOLE books per plank = 3", sandbox.WHOLE === 3, sandbox.WHOLE);

/* --- jitter stays inside the range bookRowExtent reserves --------------- */
console.log("\njitter (BookJitter range [0.94, 1.06])");
let lo = 2,
  hi = 0;
for (let i = 0; i < 500; i++) {
  const v = sandbox.hf(i);
  lo = Math.min(lo, v);
  hi = Math.max(hi, v);
}
ok("never below 0.94", lo >= 0.94, lo);
ok("never above 1.06", hi <= 1.06, hi);
ok(
  "deterministic: same index gives same factor",
  sandbox.hf(7) === sandbox.hf(7),
);

/* --- every screen actually renders -------------------------------------- */
console.log("\nrendering");
let drawn = 0;
for (const [, items] of SCREENS)
  for (const [id, , , spec] of items) {
    const h = sandbox.frame(spec);
    if (!h.includes('class="fr')) {
      ok("screen " + id + " renders a frame", false);
    }
    drawn++;
  }
ok("all " + drawn + " screens render", drawn === 8, drawn);

let steps = 0;
for (const [, items] of FLOWS)
  for (const [, , , st] of items)
    for (const [, , spec] of st) {
      sandbox.frame(spec);
      steps++;
    }
ok("all " + steps + " flow steps render", steps === 6, steps);

/* --- ids are unique per view -------------------------------------------- */
console.log("\nids");
for (const [nm, coll] of [
  ["screens", SCREENS],
  ["flows", FLOWS],
  ["elements", ELEMENTS],
]) {
  const ids = [];
  for (const [, items] of coll) for (const [id] of items) ids.push(id);
  ok(nm + " ids unique", new Set(ids).size === ids.length, ids.join(","));
}

/* --- OPEN callouts must point at ids that exist ------------------------- */
const allIds = new Set();
for (const coll of [SCREENS, FLOWS, ELEMENTS])
  for (const [, items] of coll) for (const [id] of items) allIds.add(id);
for (const id of Object.keys(OPEN))
  ok("OPEN['" + id + "'] targets a real id", allIds.has(id));

/* --- version inheritance and removal ------------------------------------ */
console.log("\nversions");
const main = resolve("main");
ok(
  "main has all 8 screens",
  main.screens.size === 8,
  [...main.screens.keys()].join(","),
);

const signal = resolve("signal-only");
ok(
  "signal-only removes the wrap screens",
  !signal.screens.has("b-wrap") && !signal.screens.has("c-capped"),
);
ok("signal-only keeps a-signal", signal.screens.has("a-signal"));
ok(
  "signal-only INHERITS today unchanged (not restated)",
  signal.screens.get("today")[2] === main.screens.get("today")[2],
);
ok("signal-only drops the el-more element", !signal.elements.has("el-more"));
ok("signal-only drops the capped flow", !signal.flows.has("reach-capped"));

const capped = resolve("capped-wrap");
ok(
  "capped-wrap keeps c-capped and drops b-wrap",
  capped.screens.has("c-capped") && !capped.screens.has("b-wrap"),
);
ok("capped-wrap keeps the shelf page", capped.screens.has("c-shelf-page"));

const full = resolve("full-wrap");
ok(
  "full-wrap keeps b-wrap and drops the capped screens",
  full.screens.has("b-wrap") && !full.screens.has("c-capped"),
);

/* --- diff direction mirrors (the 'labels read backwards' pitfall) -------
   The engine's own diffMap is asserted both ways round: a screen that is
   'onlyHere' reading A against B must be 'onlyThere' reading B against A,
   or the badges on the compare view are lying about which side owns what. */
console.log("\ndiff direction");
const ab = diffMap("main", "signal-only", "screens");
const ba = diffMap("signal-only", "main", "screens");
const onlyHere = [...ab.entries()]
  .filter(([, v]) => v === "onlyHere")
  .map(([k]) => k)
  .sort();
const onlyThere = [...ba.entries()]
  .filter(([, v]) => v === "onlyThere")
  .map(([k]) => k)
  .sort();
ok(
  "main holds the 5 screens signal-only drops",
  onlyHere.length === 5,
  onlyHere.join(","),
);
ok(
  "the diff mirrors exactly when read the other way",
  JSON.stringify(onlyHere) === JSON.stringify(onlyThere),
  onlyHere.join(",") + "  vs  " + onlyThere.join(","),
);
ok(
  "no screen is falsely reported 'changed'",
  ![...ab.values()].includes("changed"),
  [...ab.entries()].filter(([, v]) => v === "changed").join(","),
);

/* --- OPEN callouts follow their version --------------------------------- */
ok(
  "signal-only drops the wrap-only callouts",
  !resolveOpen("signal-only")["b-wrap"] &&
    !resolveOpen("signal-only")["c-capped"],
);
ok(
  "main keeps all three callouts",
  Object.keys(resolveOpen("main")).length === 3,
);

/* --- search resolves words a reader can literally see ------------------- */
console.log("\nsearch");
function screenHits(q) {
  const out = [];
  for (const [g, items] of SCREENS)
    for (const [id, nm, ds] of items)
      if (
        matchWords(
          sandbox.stripTags(g + " " + nm + " " + ds).toLowerCase(),
          q.toLowerCase(),
        )
      )
        out.push(id);
  return out;
}
for (const [q, expect] of [
  ["hero", ["b-wrap"]],
  ["chip", ["c-capped", "c-fits"]],
  ["fade", ["a-signal"]],
  ["reorderable", ["b-wrap"]],
]) {
  const got = screenHits(q);
  ok(
    "'" + q + "' -> " + expect.join(","),
    expect.every((e) => got.includes(e)) && got.length > 0,
    got.join(",") || "(none)",
  );
}
ok(
  "multi-word AND is order-independent",
  screenHits("wrap unbounded").includes("b-wrap"),
);

console.log(
  "\n" + (fails === 0 ? "ALL CHECKS PASSED" : fails + " CHECK(S) FAILED"),
);
process.exit(fails === 0 ? 0 : 1);
