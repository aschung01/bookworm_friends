#!/usr/bin/env node
/**
 * Checks index.html without a browser.
 *
 *   node docs/mockups/status-progress-merge/verify.js
 *
 * Covers what the design-mockups skill's reference/pitfalls.md says is worth
 * covering and nothing that needs a renderer: the script parses, it survives a
 * load against a DOM stub, every screen and flow spec renders, search resolves
 * real queries, and the version patch model inherits / removes / diffs both
 * ways. Hover, keyboard and scroll-spy cannot be checked here and were checked
 * by eye.
 *
 * The version assertions are the ones that earn their keep: a patch that
 * restates an unchanged screen reports a false "changed", and a diff whose
 * labels read backwards badges a removal as new. Both are recorded bugs.
 *
 * The three-reversal assertions near the end are the other kind: the feature is
 * built, so these pin the drawing to the code rather than to an intention --
 * the thumb is the platform's disc, the heading is the sheet's own title, and
 * the one text action is centred. Each mirrors the page's REAL predicate (the
 * renderer's classes and the data's blocks) rather than grepping the prose; a
 * previous session introduced a bug by reimplementing one loosely.
 */
const fs = require("fs");
const path = require("path");

const file = path.join(__dirname, "index.html");
const src = fs.readFileSync(file, "utf8");

/* Note the \s*\n and the \n\s* -- the closing tag is indented, and a looser
   regex also matches the literal "<script>" mentioned in the page's header
   comment. */
const m = src.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) fail("could not extract the <script> block");
const js = m[1];

let bad = 0;
function ok(cond, msg) {
  console.log((cond ? "  ok   " : "  FAIL ") + msg);
  if (!cond) bad++;
}
function fail(msg) {
  console.error("FATAL: " + msg);
  process.exit(1);
}

console.log("-- source --");
ok(js.split("`").length % 2 === 1, "backticks balanced");
ok(!js.includes("</scr" + "ipt>"), "no literal closing script tag in the JS");
ok(/--pt/.test(src), "frame is scaled by --pt (1pt = 1px)");

/* Tokens must match app_theme.dart. Invented brand colours are the documented
   mistake that wasted three review rounds, so this is asserted rather than
   trusted. */
console.log("-- tokens against lib/constants/app_theme.dart --");
const theme = fs.readFileSync(
  path.join(__dirname, "..", "..", "..", "lib", "constants", "app_theme.dart"),
  "utf8",
);
const light = theme.slice(
  theme.indexOf("AppColors light"),
  theme.indexOf("AppColors dark"),
);
for (const [name, hex] of [
  ["pageBackground", "#f8f9fa"],
  ["surface", "#ffffff"],
  ["surfaceVariant", "#e9ecef"],
  ["primaryText", "#212529"],
  ["secondaryText", "#626a72"],
  ["brand", "#09bc8a"],
  ["brandText", "#067657"],
  ["brandFill", "#067657"],
  ["flame", "#b54708"],
  ["sheetBackground", "#eff5ef"],
]) {
  const re = new RegExp(name + ":\\s*Color\\(0x[fF]{2}([0-9a-fA-F]{6})\\)");
  const got = light.match(re);
  ok(
    !!got && "#" + got[1].toLowerCase() === hex,
    `${name} is ${hex} in the Dart` +
      (got ? "" : " (NOT FOUND -- theme moved?)"),
  );
  ok(src.toLowerCase().includes(hex), `${name} ${hex} appears in the page`);
}

/* ---- load against a DOM stub ---- */
console.log("-- load --");
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
  console,
};
const vm = require("vm");
const ctx = vm.createContext(sandbox);
try {
  vm.runInContext(
    js +
      "\n;globalThis.__api={resolveView,resolveOpen,diffMap,frame,matchWords,flowSearchText,stripTags,SCREENS,FLOWS,ELEMENTS,VERSIONS};",
    ctx,
    { filename: "index.html" },
  );
  ok(true, "no throw at load (every top-level render path ran)");
} catch (e) {
  ok(false, "threw at load: " + e.message);
  process.exit(1);
}
const A = sandbox.__api;
const all = (v, k) =>
  A.resolveView(v, k).flatMap(([, l]) => l.map((i) => i[0]));

console.log("-- inventory --");
ok(
  all("track", "screens").length === 23,
  "23 screens (" + all("track", "screens").length + ")",
);
ok(all("track", "flows").length === 4, "4 flows");
ok(
  all("track", "elements").length === 9,
  "9 elements (" + all("track", "elements").length + ")",
);
ok(A.VERSIONS.length === 3, "3 versions, so the selector is shown");
ok(A.VERSIONS[0][3] === null, "root version has a null parent");
ok(
  A.VERSIONS.slice(1).every((v) => A.VERSIONS.some((p) => p[0] === v[3])),
  "every branch names a parent that exists",
);

console.log("-- the day-stamp row is gone from every PROPOSED screen --");
const readTodayIn = (v) => {
  const hits = [];
  for (const [g, l] of A.resolveView(v, "screens"))
    for (const it of l)
      if (JSON.stringify(it[3]).includes("I read today"))
        hits.push(g + "/" + it[0]);
  return hits;
};
const rt = readTodayIn("track");
ok(
  !rt.some((h) => h.startsWith("Proposed")),
  "no proposed screen draws it (" + rt.join(" ") + ")",
);
ok(
  rt.some((h) => h.endsWith("/today-status-reading")),
  "the shipped sheet still shows it, since that is what ships",
);
ok(
  rt.some((h) => h.endsWith("/rej-readtoday")),
  "the deletion is kept browsable as its own rejection",
);

console.log("-- no plus/minus steppers outside the rejection --");
const stpIn = [];
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l)
    if (JSON.stringify(it[3]).includes('"stp"')) stpIn.push(it[0]);
ok(
  stpIn.join() === "rej-plusminus",
  "steppers appear only in rej-plusminus (" + stpIn.join() + ")",
);

console.log("-- the three numeral doors exist as their own sheets --");
for (const id of ["sub-percent", "sub-page", "sub-total"])
  ok(all("track", "screens").includes(id), id + " is drawn");

console.log("-- version patch: inherit / override / remove --");
const dv = all("derived", "screens");
ok(dv.length === 23, "derived overrides without adding or removing screens");
const setAside = (v) =>
  A.resolveView(v, "screens")
    .flatMap(([, l]) => l)
    .find((i) => i[0] === "one-setaside");
ok(
  setAside("derived")[2].includes("blast radius"),
  "derived states the blast-radius argument that lost it",
);
ok(
  setAside("track")[2].includes("value 3"),
  "track states set aside is its own status value",
);
ok(
  setAside("derived")[3].over === true,
  "derived's version is flagged rejected",
);
ok(setAside("track")[3].over !== true, "track's version is not");

const dw = all("derived-wheel", "screens");
ok(!dw.includes("one-armed"), "derived-wheel still removes one-armed");
ok(dw.includes("today-wheel"), "derived-wheel inherits today-wheel untouched");
ok(
  !all("derived-wheel", "elements").includes("el-track"),
  "derived-wheel removes the track element",
);

console.log("-- the percent is tappable but NOT underlined --");
const readouts = [];
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l) {
    const h = A.frame(it[3]);
    if (h.includes('class="pc')) readouts.push([it[0], h]);
  }
ok(readouts.length >= 6, readouts.length + " screens draw a read-out");
ok(
  readouts.every(([, h]) => !h.includes('class="pc tap"')),
  "no percent carries the underline class",
);
ok(
  readouts.some(([, h]) => h.includes("<u>213</u>")),
  "the page numerals do carry underlines",
);

console.log("-- the page pair shares the status line, not its own --");
let inlinePair = 0,
  ownLine = 0;
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l) {
    for (const b of it[3].body || []) {
      if (b.t === "status" && b.page) inlinePair++;
      if (b.t === "pg") ownLine++;
    }
  }
ok(inlinePair >= 5, inlinePair + " screens fold the pair into the status line");
ok(ownLine === 0, "no screen puts it on a line of its own (" + ownLine + ")");

console.log("-- Save is absent until dirty --");
const hasSave = (id) => {
  for (const [, l] of A.resolveView("track", "screens"))
    for (const it of l) if (it[0] === id) return A.frame(it[3]).includes("cfm");
  return null;
};
ok(hasSave("one-rest") === false, "one-rest (clean) has no Save");
ok(hasSave("one-null") === false, "one-null (clean) has no Save");
ok(hasSave("one-nopages") === false, "one-nopages (clean) has no Save");
ok(hasSave("one-armed") === true, "one-armed (dirty) has Save");

console.log("-- Interested keeps a bar, undotted, thumb at the origin --");
const specOf = (id) =>
  A.resolveView("track", "screens")
    .flatMap(([, l]) => l)
    .find((i) => i[0] === id)[3];
const nullSpec = specOf("one-null");
const nullTrack = nullSpec.body.find((b) => b.t === "track");
ok(!!nullTrack, "the track is present");
ok(nullTrack && nullTrack.mode === "rest", "not the dashed 'null' treatment");
ok(nullTrack && nullTrack.pct === 0, "thumb at the origin, not the right end");
ok(
  !nullSpec.body.some((b) => b.page || b.t === "pg"),
  "and no page numerals are shown",
);
/* The two corrections that account for 76 of the 246 - 170 gap. Asserted on the
   BLOCKS rather than on the rendered html: `status` renders its right-hand
   region from whichever of `page` / `add` / `sub` / `pc` it was given, so the
   claim "the read-out is the word alone" is a claim about the spec. */
ok(
  !nullSpec.body.some((b) => b.t === "fld"),
  "no date row draws at the origin",
);
ok(
  !nullSpec.body.some((b) => b.pc || b.sub || b.add || b.page),
  "and the read-out collapses to the status word alone",
);

console.log("-- the pt badges are measured, not estimated --");
for (const [id, want] of [
  ["one-rest", 275],
  ["one-armed", 286],
  ["one-finished", 276],
  ["one-setaside", 276],
  ["one-null", 170],
  ["one-nopages", 275],
])
  ok(specOf(id).pt === want, `${id} is ${want}pt (${specOf(id).pt})`);

console.log("-- the thumb is the platform's disc, not the bookmark ribbon --");
/* Mirrors the renderer: `block()`'s `track` case always emits `.thm` inside
   `.rail`, and adds the `ribbon` class only for `thumb: "rib"`. Read off
   frame() so it is the drawn markup rather than the spec's intent. */
const trackScreens = [];
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l)
    if ((it[3].body || []).some((b) => b.t === "track"))
      trackScreens.push([it[0], A.frame(it[3])]);
ok(trackScreens.length >= 8, trackScreens.length + " screens draw the track");
ok(
  trackScreens.every(([, h]) => h.includes('class="thm"')),
  "every one of them draws the disc thumb",
);
ok(
  !/class="rib"/.test(js),
  "the ribbon thumb element is gone from the renderer",
);
const ribbons = trackScreens
  .filter(([, h]) => / ribbon"/.test(h))
  .map((x) => x[0]);
ok(
  ribbons.join() === "rej-drawn",
  "and the ribbon survives only as rej-drawn (" + ribbons.join() + ")",
);
/* The CSS half, because "a disc" is a shape rather than a class name. */
ok(
  /\.dev \.trk \.thm \{[^}]*border-radius: 50%/.test(src),
  "the default thumb is round in the CSS too",
);
ok(
  /\.dev \.trk\.ribbon \.thm \{[^}]*clip-path/.test(src),
  "and the notch is confined to the .ribbon variant",
);
/* `_kPadding` 8 + `CupertinoThumbPainter.radius` 14. Without this inset the
   disc hangs half off the bar at one-null's 0% and one-finished's 100%. */
ok(
  /\.dev \.trk \.rail \{[^}]*left: calc\(22 \* var\(--pt\)\)/.test(src),
  "the thumb's travel is inset 22pt, which is the platform's own geometry",
);

console.log("-- the heading is the sheet's title, not the book's --");
const BOOK = "&#49828;&#48197;!";
const headOf = (spec) =>
  (spec.body || []).find((b) => b.t === "title" || b.t === "head");
const proposedHeads = [];
for (const [g, l] of A.resolveView("track", "screens"))
  if (g.startsWith("Proposed"))
    for (const it of l) {
      const h = headOf(it[3]);
      if (h) proposedHeads.push([it[0], h.v]);
    }
ok(
  proposedHeads.length >= 6,
  proposedHeads.length + " proposed sheets carry a heading",
);
ok(
  proposedHeads.every(([, v]) => v === "Reading progress"),
  "all of them are readingProgressTitle (" +
    proposedHeads
      .filter(([, v]) => v !== "Reading progress")
      .map(([id]) => id)
      .join() +
    ")",
);
ok(
  !proposedHeads.some(([, v]) => v === BOOK),
  "and none of them is the book's own title",
);
/* The flows walk through the same sheet, which is the thing that goes stale. */
const flowHeads = [];
for (const [, l] of A.resolveView("track", "flows"))
  for (const it of l)
    for (const st of it[3])
      if ((st[2].body || []).some((b) => b.t === "track")) {
        const h = headOf(st[2]);
        flowHeads.push([it[0] + "/" + st[0], h && h.v]);
      }
ok(flowHeads.length >= 5, flowHeads.length + " flow steps draw the sheet");
ok(
  flowHeads.every(([, v]) => v === "Reading progress"),
  "and every one of them says it too (" +
    flowHeads
      .filter(([, v]) => v !== "Reading progress")
      .map(([id]) => id)
      .join() +
    ")",
);
ok(
  headOf(specOf("rej-drawn")).v === BOOK,
  "the book title survives as rej-drawn's heading, so the reversal is browsable",
);

console.log("-- the band card has two slots and one green value --");
/* The card shipped with four values in it -- range, position, day count -- and wrapped
   onto two lines on a 390pt phone, which is not a wrap valve opening. Two facts are
   pinned here. First, every card that carries a position says so in the `dates` slot
   *instead of* a date, so no screen can quietly go back to printing both. Second, the
   emphasis inverts with `.pos`: the position is the answer and the day count recedes,
   because two green values beside a green chip is what "messy" turned out to mean.

   Every version, and flow steps as well as screens: half the cards live inside a flow's
   states, and a sweep of `track`'s screens alone found two and called the rule broken. */
const cards = [];
for (const v of A.VERSIONS.map((x) => x[0])) {
  for (const [, l] of A.resolveView(v, "screens"))
    for (const it of l)
      for (const b of it[3].body || []) if (b.t === "prd") cards.push([it[0], b]);
  for (const [, l] of A.resolveView(v, "flows"))
    for (const it of l)
      for (const st of it[3])
        for (const b of st[2].body || [])
          if (b.t === "prd") cards.push([it[0] + "/" + st[0], b]);
}
ok(cards.length >= 6, cards.length + " period cards drawn");
const bothSlots = cards.filter(
  ([, b]) => /%/.test(b.dates) && /\d{4}\./.test(b.dates),
);
ok(
  bothSlots.length === 0,
  "no card prints a date and a position in the same slot (" +
    bothSlots.map(([id]) => id).join() +
    ")",
);
const positional = cards.filter(([, b]) => /%/.test(b.dates));
ok(
  positional.length >= 3 && positional.every(([, b]) => b.pos === true),
  positional.length + " cards with a position all carry the .pos emphasis",
);
ok(
  cards.filter(([, b]) => !/%/.test(b.dates)).every(([, b]) => !b.pos),
  "and the CURRENT cards, which lead with a range, do not",
);
ok(
  /\.dev \.prd\.pos \.dt \{[^}]*color: var\(--brandText\)/.test(src) &&
    /\.dev \.prd\.pos \.dy \{[^}]*color: var\(--text2\)/.test(src),
  "the .pos rule makes the position green and the day count recede",
);

console.log("-- Stop reading this is centred and full width --");
/* The page's real predicates for both halves: the `.lnk` rule centres the text,
   and its 8pt vertical padding on a full-width block is what makes the target a
   band rather than the glyphs. `.left` is the superseded alignment. */
ok(
  /\.dev \.lnk \{[^}]*text-align: center/.test(src),
  "the .lnk rule centres it",
);
ok(
  /\.dev \.lnk \{[^}]*padding: calc\(8 \* var\(--pt\)\) 0/.test(src),
  "with the shipped 8pt vertical padding, so the target is a band",
);
const leftLnk = [];
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l)
    if (/class="lnk left"/.test(A.frame(it[3]))) leftLnk.push(it[0]);
ok(
  leftLnk.join() === "rej-drawn",
  "only rej-drawn draws it left-aligned (" + leftLnk.join() + ")",
);
ok(
  A.frame(specOf("one-rest")).includes('class="lnk"'),
  "and one-rest carries no alignment override at all",
);

console.log("-- the grey secondary action --");
const links = [];
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l)
    for (const b of it[3].body || []) if (b.t === "lnk") links.push(b);
ok(links.length >= 3, links.length + " secondary actions drawn");
ok(
  links.every((b) => !b.flame),
  "none of them use the flame tone",
);
ok(
  links.every((b) => b.v === "Stop reading this"),
  "and the only one left is Stop reading this",
);

console.log("-- the read sheet: the title IS the filter read-out --");
/* Mirrors the structural claim the drawing makes rather than re-deriving it:
   `expandedHeader` is `Column[title, ReadFilter(expanded: true)]`, so the year
   rail is the row DIRECTLY under the title row and nothing may come between
   them. `gap` is spacing and `pop` is the popover layer -- absolutely
   positioned in the page's own CSS, so it is not a row either. */
const rowsOf = (spec) =>
  spec.body
    .filter((b) => b.t && b.t !== "gap" && b.t !== "pop")
    .map((b) => b.t);
const shdOf = (id) => specOf(id).body.find((b) => b.t === "shd");
for (const id of ["sheet-read", "sheet-popover", "sheet-all"]) {
  const r = rowsOf(specOf(id));
  ok(
    r[0] === "shd" && r[1] === "caps",
    id + ": the year rail is the row under the title (" + r.join(">") + ")",
  );
  ok(
    specOf(id).body.find((b) => b.t === "caps").items[0] === "All time",
    id + ": the year rail is the real one",
  );
  ok(shdOf(id).chev === true, id + ": the title row carries the chevron");
}

/* The superseded `Finished` / `All` segment. Checked as a block KEY across every
   version, not as a substring of the page -- the word "filter" is all over the
   prose, and a loose test there would pass on a drawing that still had it. */
const blockKeys = new Set();
for (const v of A.VERSIONS.map((x) => x[0])) {
  for (const [, l] of A.resolveView(v, "screens"))
    for (const it of l)
      for (const b of it[3].body || [])
        Object.keys(b).forEach((k) => blockKeys.add(k));
  for (const [, l] of A.resolveView(v, "flows"))
    for (const it of l)
      for (const st of it[3])
        for (const b of st[2].body || [])
          Object.keys(b).forEach((k) => blockKeys.add(k));
}
ok(
  !blockKeys.has("filter"),
  "no screen or step still draws the Finished/All segment",
);
ok(!/b\.filter/.test(js), "and the renderer has no branch left for it");

ok(
  shdOf("sheet-read").t2 === "Books finished" &&
    shdOf("sheet-all").t2 === "Books read",
  "the title text is the mode (Books finished / Books read)",
);
ok(
  shdOf("sheet-read").n === "23" && shdOf("sheet-all").n === "29",
  "the count follows the visible list (23 / 29)",
);
ok(
  shdOf("sheet-popover").t2 === shdOf("sheet-read").t2 &&
    shdOf("sheet-popover").n === shdOf("sheet-read").n,
  "the popover opens over the default state, not a third mode",
);
const pop = specOf("sheet-popover").body.find((b) => b.t === "pop");
ok(
  !!pop &&
    pop.items.map((x) => x.v).join(" / ") ===
      "Show finished only / Show all read",
  "the popover offers exactly the two modes, in that order",
);
ok(
  !!pop &&
    pop.items.filter((x) => x.on).length === 1 &&
    pop.items[0].on === true,
  "exactly one row is checked, and it is the default",
);
ok(
  A.frame(specOf("sheet-popover")).includes("&#10003;"),
  "and the check is actually drawn",
);

/* The flow walks through the same drawing, which is the thing that goes stale. */
const flowStep = A.resolveView("track", "flows")
  .flatMap(([, l]) => l)
  .find((f) => f[0] === "flow-setaside")[3]
  .find((st) => (st[2].body || []).some((b) => b.t === "shd"));
ok(!!flowStep, "flow-setaside still ends in the read sheet");
ok(
  flowStep && flowStep[2].body.find((b) => b.t === "shd").t2 === "Books read",
  "and it draws the inclusive title, not a segment set to All",
);
ok(
  flowStep && rowsOf(flowStep[2])[1] === "caps",
  "with the year rail still directly under it",
);

console.log("-- diff: no false positives, and it mirrors --");
const d1 = A.diffMap("track", "derived", "screens");
const d2 = A.diffMap("derived", "track", "screens");
ok(!d1.has("today-wheel"), "an unrestated screen is not reported as changed");
ok(!d1.has("one-rest"), "derived does not touch one-rest, so no diff");
ok(d1.get("one-setaside") === "changed", "one-setaside changed");
ok(d1.size === 1, "exactly one screen differs (" + d1.size + ")");
ok(
  [...d1.keys()].sort().join() === [...d2.keys()].sort().join(),
  "same id set in both directions",
);
const d3 = A.diffMap("track", "derived-wheel", "screens");
const d4 = A.diffMap("derived-wheel", "track", "screens");
ok(d3.get("one-armed") === "onlyHere", "viewing track: one-armed is onlyHere");
ok(
  d4.get("one-armed") === "onlyThere",
  "viewing derived-wheel: one-armed is onlyThere",
);

console.log("-- OPEN callouts --");
const o1 = A.resolveOpen("track"),
  o2 = A.resolveOpen("derived"),
  o3 = A.resolveOpen("derived-wheel");
ok(Object.keys(o1).length === 3, "track carries 3 open decisions");
ok(
  o1["flow-nudge-new"].includes("setRead(read: false)"),
  "the nudge callout names the un-stamp that leaves with the checkbox",
);
ok(
  o1["flow-setaside"].includes("unreachable"),
  "the set-aside callout names the Reading -> Interested gap",
);
ok(
  o2["flow-setaside"].includes("Superseded"),
  "derived overrides the set-aside callout",
);
ok(
  o3["flow-nudge-new"].includes("170pt"),
  "derived-wheel keeps its own height argument",
);
ok(
  o1["flow-finish"].includes("ss-finished"),
  "the callout names the drawn decision it inverts",
);

console.log("-- every spec renders --");
let n = 0;
for (const v of A.VERSIONS.map((x) => x[0])) {
  for (const [, l] of A.resolveView(v, "screens"))
    for (const it of l) {
      if (!A.frame(it[3]).startsWith('<div class="dev'))
        ok(false, "bad frame: " + it[0]);
      n++;
    }
  for (const [, l] of A.resolveView(v, "flows"))
    for (const it of l) for (const st of it[3]) (A.frame(st[2]), n++);
}
ok(n === 96, `${n} specs rendered without throwing`);

console.log("-- pt badges --");
let withPt = 0,
  over = 0;
for (const [, l] of A.resolveView("track", "screens"))
  for (const it of l) {
    if (it[3].pt) withPt++;
    if (it[3].over) over++;
  }
ok(withPt === 23, "every screen carries a measured height (" + withPt + ")");
ok(over === 6, "6 screens flagged as rejected / overflowing (" + over + ")");

console.log("-- search resolves words visible on the page --");
const hits = (q) => {
  const o = [];
  for (const [g, items] of A.FLOWS)
    for (const [id, nm, ds, steps] of items)
      if (A.matchWords(A.flowSearchText(g, nm, ds, steps), q.toLowerCase()))
        o.push(id);
  return o;
};
for (const [q, want] of [
  ["set aside", "flow-setaside"],
  ["dog", "flow-setaside"],
  ["wheel", "flow-nudge-today"],
  ["drag", "flow-nudge-new"],
  ["stopped on", "flow-setaside"],
])
  ok(hits(q).includes(want), `"${q}" -> ${want}`);
ok(hits("zzzz").length === 0, '"zzzz" -> [] so the empty state is reachable');

const shits = (q) => {
  const o = [];
  for (const [g, items] of A.SCREENS)
    for (const [id, nm, ds] of items)
      if (
        A.matchWords(g.toLowerCase(), q) ||
        A.matchWords(A.stripTags(`${nm} ${ds || ""}`).toLowerCase(), q)
      )
        o.push(id);
  return o;
};
ok(shits("null").includes("one-null"), '"null" -> one-null');
ok(shits("606").includes("rej-inline-wheel"), '"606" -> rej-inline-wheel');
ok(shits("rejected").length >= 3, '"rejected" -> the kept counter-arguments');
ok(shits("total pages").includes("sub-total"), '"total pages" -> sub-total');
ok(shits("65%").includes("one-nopages"), '"65%" -> one-nopages');
ok(
  shits("uislider").includes("one-rest"),
  '"uislider" -> one-rest, so the shipped control is searchable',
);
ok(shits("popover").includes("sheet-popover"), '"popover" -> sheet-popover');
ok(
  shits("chevron").includes("sheet-read"),
  '"chevron" -> sheet-read, so the new control is searchable',
);

const ehits = (q) => {
  const o = [];
  for (const [g, items] of A.ELEMENTS)
    for (const [id, nm, ds] of items)
      // Mirrors visibleOpts(): a group's own name pulls in its whole
      // contents, otherwise an item is judged on its own text.
      if (
        A.matchWords(g.toLowerCase(), q) ||
        A.matchWords(A.stripTags(`${nm} ${ds || ""}`).toLowerCase(), q)
      )
        o.push(id);
  return o;
};
ok(
  ehits("native slider").includes("el-track"),
  'element "native slider" -> el-track',
);
ok(
  ehits("deleted").join() === "el-readtoday,el-seg,el-wheel",
  'element "deleted" pulls the whole group (' + ehits("deleted").join() + ")",
);

console.log(bad ? `\n${bad} FAILURE(S)` : "\nall checks passed");
process.exit(bad ? 1 : 0);
