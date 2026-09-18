/**
 * Terminal verification for `index.html`.
 *
 * The page is static, so most of it can be checked without a browser: the
 * script is extracted, run against a DOM stub (which exercises every
 * top-level render path), and then the pure functions and the rendered
 * markup are asserted directly.
 *
 * Run: node verify.js
 *
 * What this CANNOT check: hover, keyboard, scroll-spy, and anything about how
 * the drawing actually looks. Those were checked by eye.
 *
 * The assertions worth knowing about are the last block, which pins the
 * *argument* rather than the plumbing: that `main` can show three statuses in
 * one list, and that `read-sheet-filter` cannot — its month grid holds one
 * cover while the nine books it is unable to search are drawn on the shelves
 * behind the very sheet the field sits in. If that stops being true, the page
 * has stopped making its case and the note beside it is a lie.
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
const EXPORTS = ["SCREENS", "FLOWS", "ELEMENTS", "VERSIONS", "OPEN", "B", "S"];
vm.runInContext(
  js + "\n;globalThis.__x={" + EXPORTS.join(",") + "};",
  sandbox,
  {
    filename: "index.html<script>",
  },
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
function eq(label, got, want) {
  const a = JSON.stringify(got),
    b = JSON.stringify(want);
  ok(label, a === b, a + "   want " + b);
}

const {
  FLOWS,
  ELEMENTS,
  frame,
  resolveView,
  resolveOpen,
  diffMap,
  matchWords,
  flowSearchText,
  stripTags,
} = sandbox;

const VIDS = ["main", "read-sheet-filter", "scope-toggle"];
const ids = (vid, kind) =>
  resolveView(vid, kind).flatMap(([, items]) => items.map((i) => i[0]));
const item = (vid, id, kind) =>
  resolveView(vid, kind || "screens")
    .flatMap(([, l]) => l)
    .find((i) => i[0] === id);

/* ---- search: every query below returned nothing before the text it matches
   was written, which is the pitfall this guards. ---------------------------- */
console.log("\nsearch");
const fhits = (q) => {
  const o = [];
  for (const [g, items] of FLOWS)
    for (const [id, nm, ds, steps] of items)
      if (matchWords(flowSearchText(g, nm, ds, steps), q.toLowerCase()))
        o.push(id);
  return o;
};
const ehits = (q) => {
  const o = [];
  for (const [g, items] of ELEMENTS)
    for (const [id, nm, note] of items)
      if (
        matchWords(
          stripTags(nm + " " + g + " " + note).toLowerCase(),
          q.toLowerCase(),
        )
      )
        o.push(id);
  return o;
};
eq("flow 'interested'", fhits("interested"), ["already-added", "dup-today"]);
eq("flow 'duplicate'", fhits("duplicate"), ["dup-today"]);
eq("flow 'shelves eye'", fhits("shelves eye"), ["already-added"]);
eq("flow 'catalogue'", fhits("catalogue"), ["already-added", "dup-today"]);
/* Hangul, because the matcher card is the one place 초성 is documented and it
   is the detail most likely to be dropped in implementation. */
eq("element '초성'", ehits("초성"), ["el-matcher"]);
eq("element 'magnifier'", ehits("magnifier"), ["el-onemag"]);
eq("element 'isbn-10'", ehits("isbn-10"), ["el-owned"]);
eq("element '1.66'", ehits("1.66"), ["el-badges"]);

/* ---- versions: resolution, inheritance, removal ------------------------- */
console.log("\nversions");
eq("main screens", ids("main", "screens"), [
  "today-add",
  "today-read",
  "search-empty",
  "search-all-three",
  "search-interested",
  "search-none-local",
  "search-local-first",
  "search-pending",
  "search-all-owned",
]);
eq("read-sheet-filter screens", ids("read-sheet-filter", "screens"), [
  "today-add",
  "today-read",
  "search-empty",
  "search-all-three",
]);
eq("scope-toggle screens", ids("scope-toggle", "screens"), [
  "today-add",
  "today-read",
  "search-empty",
  "search-all-three",
  "search-none-local",
]);
eq("main elements", ids("main", "elements"), [
  "el-onemag",
  "el-sections",
  "el-localrow",
  "el-badges",
  "el-nolocal",
  "el-invite",
  "el-owned",
  "el-matcher",
]);
/* The matcher survives into both alternatives, because 초성 is a question
   either shape has to answer. `el-owned`, `el-nolocal` and `el-invite` do not,
   because neither alternative has a two-section list to put them in. */
eq("read-sheet-filter elements", ids("read-sheet-filter", "elements"), [
  "el-onemag",
  "el-sections",
  "el-localrow",
  "el-badges",
  "el-matcher",
]);
ok(
  "an unpatched screen is inherited byte-identical",
  JSON.stringify(item("read-sheet-filter", "today-add")) ===
    JSON.stringify(item("main", "today-add")),
);
ok(
  "a patched screen differs",
  JSON.stringify(item("scope-toggle", "search-all-three")) !==
    JSON.stringify(item("main", "search-all-three")),
);
eq("OPEN keys resolve", Object.keys(resolveOpen("main")).sort(), [
  "add-new",
  "already-added",
  "dup-today",
]);
ok(
  "read-sheet-filter overrides the already-added callout",
  resolveOpen("read-sheet-filter")["already-added"].includes(
    "Closed by drawing it",
  ),
);

/* ---- diff: label from the point of view of the version on screen, and
   verify by running it both ways and checking it mirrors. ------------------ */
console.log("\ndiff");
const d1 = diffMap("main", "read-sheet-filter", "screens");
const d2 = diffMap("read-sheet-filter", "main", "screens");
eq("a->b: only here", d1.get("search-interested"), "onlyHere");
eq("b->a: only there", d2.get("search-interested"), "onlyThere");
eq(
  "changed reads the same both ways",
  [d1.get("search-all-three"), d2.get("search-all-three")],
  ["changed", "changed"],
);
eq(
  "an untouched screen is in neither diff",
  [d1.has("today-add"), d2.has("today-add")],
  [false, false],
);

/* ---- every frame and demo in every version renders --------------------- */
console.log("\nrendering");
let n = 0;
for (const vid of VIDS) {
  for (const [, l] of resolveView(vid, "screens"))
    for (const it of l) {
      const h = frame(it[3]);
      ok(vid + "/" + it[0] + " renders", !!h && h.length > 400);
      n++;
    }
  for (const [, l] of resolveView(vid, "flows"))
    for (const [id, , , steps] of l)
      steps.forEach((st, i) => {
        const h = frame(st[2]);
        ok(
          vid + "/" + id + " step " + (i + 1) + " renders",
          !!h && h.length > 400,
        );
        n++;
      });
  for (const [, l] of resolveView(vid, "elements"))
    for (const it of l) {
      ok(vid + "/" + it[0] + " demo renders", !!it[3] && it[3].length > 80);
      n++;
    }
}
console.log("  " + n + " frames/demos across " + VIDS.length + " versions");

/* ---- the argument itself ------------------------------------------------ */
console.log("\nthe argument");
const has = (h, s) => h.includes(s);
const count = (h, re) => (h.match(re) || []).length;
const mainAll = frame(item("main", "search-all-three")[3]);
const rsAll = frame(item("read-sheet-filter", "search-all-three")[3]);

ok(
  "main: one query draws all three status badges",
  ["b0", "b1", "b2"].every((c) => has(mainAll, "bdg " + c)),
);
eq("main: three owned books listed", count(mainAll, /class="lrow"/g), 3);
ok(
  "main: both sections present",
  has(mainAll, "In your library") && has(mainAll, "Add a new book"),
);
ok("read-sheet-filter: carries the MISSING band", has(rsAll, "gapmark"));
ok(
  "read-sheet-filter: cannot draw a status badge at all",
  !has(rsAll, 'class="bdg'),
);
/* Scoped to the month grid on purpose. The frame also draws the library
   BEHIND the sheet, and those nine books are exactly the ones this surface
   cannot search — so counting the whole frame would prove the opposite of
   what the note claims. */
const mgridOf = (h) => h.slice(h.indexOf('class="mgrid"'));
eq(
  "read-sheet-filter: month grid holds 1 of the 3 한강 books",
  count(mgridOf(rsAll), /<u /g),
  1,
);
eq(
  "read-sheet-filter: the 9 unreachable books are still drawn behind it",
  count(rsAll, /<u /g),
  10,
);
ok(
  "main: catalogue cover carries the ownership mark",
  has(frame(item("main", "search-interested")[3]), "In your library</b>"),
);
/* The lower section exists from the first keystroke, but before submit it holds
   an offer rather than results. This assertion used to demand the opposite — that
   there be no catalogue section at all until submit — and a screenshot of the
   built sheet is what overturned it: the reader was left with a sentence saying
   the search failed and no way to run one. */
const localFirst = frame(item("main", "search-local-first")[3]);
ok(
  "main: local-only state offers the catalogue instead of listing it",
  has(localFirst, "Add a new book") &&
    has(localFirst, 'class="invite"') &&
    !has(localFirst, 'class="rrow"'),
);
/* The frame the bug was reported from. Its two lines must both be there and must
   not be confused for each other: one states what the library holds, the other
   offers what has not been asked. */
const pending = frame(item("main", "search-pending")[3]);
ok(
  "pending: states the local miss and offers the query by name",
  has(pending, "Nothing in your library matches.") &&
    has(pending, "Search for \u201cgood thing\u201d"),
);
ok(
  "pending: draws no keyboard, which is why the offer has to be tappable",
  !has(pending, 'class="keyb"'),
);
/* The positive control for the assertion above. Without it that one passes
   whether or not the class name is still right, which is how it was first
   written — against `class="kb"`, a string this page has never contained. */
ok(
  "local-first: does draw one, so the absence above is a fact about the frame",
  has(localFirst, 'class="keyb"'),
);
/* Suppression's own empty state. A header over nothing reads as a failed
   request, so the copy is load-bearing rather than decorative. */
const allOwned = frame(item("main", "search-all-owned")[3]);
ok(
  "all-owned: catalogue section is present but holds no covers",
  has(allOwned, "Add a new book") && !has(allOwned, 'class="rrow"'),
);
/* The two empty-ish lower sections must never be confused: this one *answered*
   and had nothing new, so it must not also be offering to search. */
ok(
  "all-owned: an answered section carries no offer",
  !has(allOwned, 'class="invite"'),
);
ok("all-owned: says 'Nothing new to add'", has(allOwned, "Nothing new to add"));
eq(
  "all-owned: still lists the 3 owned books",
  count(allOwned, /class="lrow"/g),
  3,
);
ok(
  "scope-toggle: draws the segmented track",
  has(frame(item("scope-toggle", "search-all-three")[3]), 'class="scope"'),
);
ok("main: draws no segmented track", !has(mainAll, 'class="scope"'));
ok(
  "matcher demo shows the jamo query",
  has(item("main", "el-matcher", "elements")[3], "ㅎㄹㅍ"),
);

console.log("\n" + (fails ? fails + " FAILED" : "all passed") + "\n");
process.exit(fails ? 1 : 0);
