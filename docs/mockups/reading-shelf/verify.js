/*
 * Verifies index.html without a browser. Run from the project root:
 *
 *     node docs/mockups/reading-shelf/verify.js
 *
 * This page is a claim about *placement* rather than about arithmetic, so most of
 * what it asserts is that the drawings agree with each other and with the code
 * they cite. Three things are worth checking mechanically:
 *
 *  1. The two transforms are real functions, not typed-in numbers. `promote` is
 *     `withReadingFirst` and `queue`/`shelved` are the proposed filter, so a
 *     count on a name tab is derived from the same fixture the covers are drawn
 *     from. The previous round of mockups drifted precisely because a shelf's
 *     count was typed beside its covers.
 *
 *  2. The version patches inherit, remove and diff correctly. There are two
 *     answers to the zero state and the whole point of the branches is that
 *     ⇧Enter puts them side by side.
 *
 *  3. Search reaches the OPEN callouts. Those render as red text on the page,
 *     and `visibleOpts` was extended here to index them — before that, `hero`,
 *     which appears only in reading-one's callout, matched nothing. That is the
 *     "words plainly visible on screen match nothing" bug in the skill's
 *     reference/pitfalls.md.
 *
 * What it cannot check is what the page looks like: the ribbon's notch, the
 * spine type, whether an inert shelf reads as inert, and every hover, keyboard
 * and scroll-spy behaviour beyond the focus assertions below. Those need eyes.
 */
const fs = require("fs");
const path = require("path");

const file = path.join(__dirname, "index.html");
const src = fs.readFileSync(file, "utf8");

let fail = 0;
const ok = (label, cond, extra) => {
  if (!cond) fail++;
  console.log(`${cond ? "ok  " : "FAIL"} ${label}${extra ? "  " + extra : ""}`);
};
const head = (s) => console.log(`\n---- ${s} ----`);

/* ================================================================
   the script extracts, parses and loads
   ================================================================ */
head("the page loads");
const m = src.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) {
  console.log("FAIL no script block found");
  process.exit(1);
}
const js = m[1];
ok("backticks balanced", js.split("`").length % 2 === 1);
ok("one generic .gone rule", /\.gone\s*\{\s*display:\s*none/.test(src));
ok("no network references", !/https?:\/\/(?!www\.w3\.org)/.test(src));

/* The tokens are the theme file's. Not an approximation: drawing an invented
   brand green has cost this project whole review rounds. */
head("tokens are the codebase's");
[
  ["pageBackground", "#f8f9fa"],
  ["surface", "#ffffff"],
  ["surfaceVariant", "#e9ecef"],
  ["primaryText", "#212529"],
  ["secondaryText", "#626a72"],
  ["brand", "#09bc8a"],
  ["brandText", "#067657"],
  ["sheetBackground", "#eff5ef"],
].forEach(([name, hex]) =>
  ok(`AppColors.light ${name} is ${hex}`, src.includes(hex)),
);

/* The bookmark is the asset's geometry and the asset's colour. `shelf-overflow`
   draws it red and predates the unification in `reading_bookmark.dart`; getting
   this wrong here would re-establish the mistake. */
head("the bookmark is bookmarkIcon.svg's");
const bm = src.match(/\.fr \.bk i\.bm \{[\s\S]*?\n            \}/);
ok("the .bm rule exists", !!bm);
if (bm) {
  ok("white, not red", /background:\s*#ffffff/.test(bm[0]));
  ok("does not use --danger", !bm[0].includes("--danger"));
  ok("13.5 wide (x 4 to 17.5 of a 22 box)", bm[0].includes("13.5px"));
  ok("30 tall (y 0 to 30 of a 38 box)", bm[0].includes("30px"));
  ok(
    "12.5 in from the cover, allowing the 4.5 bleed",
    bm[0].includes("12.5px"),
  );
  ok("notch apex at 80.6% (y 24.2 of 30)", bm[0].includes("80.6%"));
  ok(
    "drop-shadow, not box-shadow, so the notch shows through",
    /drop-shadow/.test(bm[0]) && !/box-shadow/.test(bm[0]),
  );
}

/* ================================================================
   run it against a DOM stub — catches every top-level render path
   ================================================================ */
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
global.document = {
  getElementById: () => mk(),
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

const scope = {};
new Function(
  "__x",
  `${js}\nObject.assign(__x, {SCREENS,FLOWS,ELEMENTS,OPEN,VERSIONS,PER_SHELF,IT,STARTUP,NOVEL,HISTORY,ESSAY,R1,R3,R7,NONE,open_,promote,queue,shelved,shelfHTML,bookHTML,block,frame,libScreen,VMAP,stripTags,matchWords,flowSearchText,resolveView,resolveOpen,diffMap,renderList,visibleOpts,clist,csearch,setView:(v)=>{view=v},setKbId:(v)=>{kbId=v},kbState:()=>({kbId,kbIndex})});`,
)(scope);
const {
  SCREENS,
  FLOWS,
  ELEMENTS,
  OPEN,
  VERSIONS,
  PER_SHELF,
  IT,
  STARTUP,
  NOVEL,
  R1,
  R3,
  R7,
  NONE,
  open_,
  promote,
  queue,
  shelved,
  shelfHTML,
  bookHTML,
  frame,
  libScreen,
  VMAP,
  stripTags,
  matchWords,
  resolveView,
  resolveOpen,
  diffMap,
  renderList,
  clist,
  csearch,
  setView,
  setKbId,
  kbState,
} = scope;
head("the script runs at load");
ok("no throw on load", true);

/* ================================================================
   the two transforms — the whole reason nothing here is typed twice
   ================================================================ */
head("the transforms are the code's");
ok(
  "promote is a stable partition, in-progress first",
  promote(IT, R3)
    .slice(0, 2)
    .every((b) => b.reading) &&
    !promote(IT, R3)[2].reading &&
    promote(IT, R3).length === IT.length,
);
ok(
  "promote preserves authored order inside each group",
  promote(IT, R3)
    .map((b) => b.k)
    .join(",") === "6,10,1,2,3,4,5,7,8,9,11,12",
);
ok(
  "queue + open accounts for every book on a shelf",
  queue(IT, R3).length +
    R3.filter((o) => IT.some((b) => b.k === o.k)).length ===
    IT.length,
);
ok(
  "three open drops IT 12 -> 10 and 스타트업 6 -> 5",
  shelved(IT, R3) === 10 && shelved(STARTUP, R3) === 5,
  `${shelved(IT, R3)}/${shelved(STARTUP, R3)}`,
);
ok(
  "one open book touches only its own shelf",
  shelved(IT, R1) === 12 && shelved(STARTUP, R1) === 5,
);
ok(
  "a finished book never returns to its shelf",
  shelved(STARTUP, R1) === STARTUP.length - 1,
);

/* The row holds 3.57 covers, and the reading shelf is an ordinary row. */
head("the reading shelf is an ordinary row");
ok(
  "three open fills it to within half a cover",
  R3.length <= PER_SHELF && R3.length + 1 > PER_SHELF,
  `${R3.length} of ${PER_SHELF}`,
);
ok("seven open overflows it", R7.length > PER_SHELF);
ok(
  "kCardReadingMax's 3 and the row's 3 are stated as a coincidence",
  /coincidence/.test(
    SCREENS.flatMap(([, i]) => i).find(([id]) => id === "reading-three")[2],
  ),
);

/* ================================================================
   what the drawings actually emit
   ================================================================ */
head("the drawings");
const rs = (extra) =>
  shelfHTML(Object.assign({ books: R3, label: "Reading", reading: 1 }, extra));
ok("the reading tab is drawn as rtab", rs().includes("stab rtab"));
ok(
  "a queue tab is not",
  shelfHTML({ books: IT, label: "IT", count: 12 }).includes('class="stab"') &&
    !shelfHTML({ books: IT, label: "IT", count: 12 }).includes("rtab"),
);
ok(
  "every cover on it carries a ribbon",
  (rs().match(/class="bm"/g) || []).length === 3,
);
ok(
  "no book on it is ever drawn as a spine, even at spines density",
  !/bk spine/.test(rs({ spines: 1 })),
);
ok(
  "a queue row at spines density exempts only the in-progress head",
  (shelfHTML({ books: promote(IT, R3), spines: 1 }).match(/bk spine/g) || [])
    .length === 10,
);
ok(
  "and gives that head its full separator",
  shelfHTML({ books: promote(IT, R3), spines: 1 }).includes("fgap"),
);
ok(
  "an inert shelf draws no delete badges",
  !rs({ edit: 1, inert: 1 }).includes("del"),
);
ok(
  "an editable queue shelf draws one badge per book",
  (
    shelfHTML({ books: queue(IT, R3), label: "IT", edit: 1 }).match(
      /class="del"/g,
    ) || []
  ).length === 10,
);
ok(
  "origins draw one caption per cover",
  (rs({ origins: R3.map((b) => b.from) }).match(/<span>/g) || []).length === 3,
);
ok(
  "and name more than one shelf, or the caption proves nothing",
  new Set(R3.map((b) => b.from)).size > 1,
);
ok(
  "the empty plank carries its hint",
  shelfHTML({
    books: [],
    label: "Reading",
    reading: 1,
    empty: "Nothing in progress",
  }).includes("Nothing in progress"),
);

/* ================================================================
   the treatments — each drawing keeps the promises its note makes
   ================================================================ */
head("the treatments");
ok(
  "a lying book carries both hashes — length and thickness",
  /bk lie" style="--c:[^"]*--sw:\d+;--hf:0\.\d+/.test(
    shelfHTML({ books: R3, flat: 1 }),
  ),
);
ok(
  "the flat stack lies one book per level, bookmark out the fore-edge",
  (shelfHTML({ books: R3, flat: 1 }).match(/bk lie/g) || []).length === 3 &&
    (shelfHTML({ books: R3, flat: 1 }).match(/class="bms"/g) || []).length ===
      3,
);
ok(
  "a lying book draws no ribbon — the fore-edge tab replaces it",
  !shelfHTML({ books: R3, flat: 1 }).includes('class="bm"'),
);
ok(
  "the tent is two boards and a ridge",
  (shelfHTML({ books: R1, tent: 1 }).match(/board [lr]/g) || []).length === 2 &&
    shelfHTML({ books: R1, tent: 1 }).includes('class="ridge"'),
);
ok(
  "the alcove is the stock shelf plus one class",
  shelfHTML({ books: R3, label: "Reading", reading: 1, nook: 1 }).includes(
    "shelf nook",
  ) &&
    (
      shelfHTML({ books: R3, label: "Reading", reading: 1, nook: 1 }).match(
        /class="bm"/g,
      ) || []
    ).length === 3,
);
ok(
  "day stamps print D+n only when the book carries a day",
  (shelfHTML({ books: R3, days: 1 }).match(/class="ds"/g) || []).length === 3 &&
    shelfHTML({ books: R3, days: 1 }).includes("D+12") &&
    !shelfHTML({ books: promote(IT, R3) }).includes('class="ds"'),
);
ok(
  "promote does not leak day counts (map index bug)",
  promote(IT, R3).every((b) => b.d === undefined),
);
ok(
  "the hero treatment grows exactly the first book",
  (shelfHTML({ books: R1, hero: 1 }).match(/heroL/g) || []).length === 1 &&
    !shelfHTML({ books: R3.slice(1) }).includes("heroL"),
);
ok(
  "R3's day counts are the note's",
  R3.map((b) => b.d).join(",") === "12,4,23",
  R3.map((b) => b.d).join(","),
);

/* ---- the lean rests ON the plank, at every scale ----
   The bug this caught: with `transform-origin: 90% 100%` the counter-clockwise
   rotation drove the cover's lower-left corner BELOW the plank, so the hero
   pierced the shelf. Pivoting on the bottom-left corner makes that corner the
   lowest point of the transformed box by construction. Asserted on the CSS
   because the geometry cannot be measured without a browser. */
const screenById = (id) =>
  SCREENS.flatMap(([, i]) => i).find(([x]) => x === id);
const elementById = (id) =>
  ELEMENTS.flatMap(([, i]) => i).find(([x]) => x === id);
head("the lean");
const heroCss = src.match(/\.fr \.bk\.heroL \{[\s\S]*?\n            \}/);
ok("the heroL rule exists", !!heroCss);
if (heroCss) {
  ok(
    "it pivots on the bottom-left corner, the one still touching the board",
    /transform-origin:\s*0%\s+100%/.test(heroCss[0]),
    heroCss[0].match(/transform-origin:[^;]*/)?.[0],
  );
  ok(
    "and does NOT pivot near the bottom-right, which sank it through the plank",
    !/transform-origin:\s*9\d%/.test(heroCss[0]),
  );
  const deg = +heroCss[0].match(/rotate\((-?[\d.]+)deg\)/)[1];
  ok("it leans counter-clockwise", deg < 0, `${deg}deg`);
  /* Pivoting at the bottom-left, the top-left corner sweeps left by h*sin(theta).
     That has to land in slack, not on the wordmark, so it is worth pinning. */
  const sweep = 82.9 * Math.sin(Math.abs(deg) * (Math.PI / 180));
  ok(
    "the leftward sweep stays under 10pt, inside the gap beside the word",
    sweep < 10,
    `${sweep.toFixed(1)}pt`,
  );
}

/* ---- label scale: four variants, one renderer, same three books ---- */
head("label scale");
const labels = ["l-xl", "l-title", "l-sub", "l-eyebrow"];
ok(
  "the four label scales are all present",
  labels.every((id) => screenById(id)),
);
ok(
  "every label variant holds the SAME three books — only the word changes",
  labels.every((id) => {
    const led = screenById(id)[3].body[0];
    return led.t === "ledge" && led.books.length === 3;
  }),
);
ok(
  "the shelf's share grows monotonically as the word shrinks",
  (() => {
    const pct = labels.map((id) => {
      const led = screenById(id)[3].body[0];
      if (led.stack) return 100;
      return led.minw ? +led.minw.replace("%", "") : 58;
    });
    return pct.join(",") === "58,70,80,100";
  })(),
);
ok(
  "only the sub-serif sizes drop the serif",
  !screenById("l-xl")[3].body[0].sans &&
    !screenById("l-title")[3].body[0].sans &&
    screenById("l-sub")[3].body[0].sans === 1,
);
ok(
  "l-title uses the app's own title token rather than a new number",
  screenById("l-title")[3].body[0].w1 === "var(--f-title)",
);
ok(
  "the eyebrow returns the books to full size",
  /\.fr \.ledge\.stack \.mini \{[^}]*--bk-w:\s*51\.9px/.test(src),
);
ok(
  "the eyebrow renders a full-width row and no column",
  scope
    .block({
      t: "ledge",
      stack: 1,
      word: "Reading",
      sub: "3 books",
      books: R3,
    })
    .includes("ledge stack"),
);

/* ---- shelf-level attention devices ---- */
head("eye-catching");
const decos = [
  "s-lit",
  "s-tray",
  "s-board",
  "s-bookend",
  "s-mat",
  "s-big",
  "s-lamp-mat",
  "s-lamp-panel",
  "s-lamp-board",
  "s-lamp-drape",
];
ok(
  "the ten devices are all present",
  decos.every((id) => screenById(id)),
);
ok(
  "the seven devices are all present",
  decos.every((id) => screenById(id)),
);
ok(
  "every device sits on the chosen baseline — even lean, stamps, real tab",
  decos.every((id) => {
    const s = screenById(id)[3].body[0];
    const h = frame(screenById(id)[3]);
    return (
      s.lean === "even" &&
      s.days === 1 &&
      h.includes("stab rtab") &&
      !h.includes("heroL")
    );
  }),
);
ok(
  "only the furniture varies — same three books everywhere",
  decos.every((id) => screenById(id)[3].body[0].books.length === 3),
);
ok(
  "each device reaches the shelf as its own class",
  decos.every((id) => {
    const s = screenById(id)[3].body[0];
    return frame(screenById(id)[3]).includes(s.deco.split(" ")[0]);
  }),
);
ok(
  "the pair really is both devices",
  (() => {
    const h = frame(screenById("s-lamp-mat")[3]);
    return /shelf[^"]*\blit\b/.test(h) && /shelf[^"]*\bmat\b/.test(h);
  })(),
);
/* The lamp is the card's own light, not an invented warm. Pin the bloom colours
   against `card_lighting.dart`'s kCandleBloomColors so a theme change there is
   caught here rather than silently diverging. */
ok(
  "the lamp uses the Library Card's own bloom colours",
  /rgba\(255, 199, 106/.test(src) && /rgba\(255, 154, 46/.test(src),
  "#FFC76A / #FF9A2E",
);
ok(
  "the lamp scales the covers rather than washing over them",
  /\.fr \.shelf\.lit \.bk \{[^}]*filter:\s*brightness/.test(src) &&
    !/\.fr \.shelf\.lit \.bk::after/.test(src),
);
ok(
  "the tray is a real contrast, unlike the alcove it replaces",
  (() => {
    const hex = (h) => parseInt(h.slice(1), 16);
    const d = (a, b) => Math.abs(hex(a) - hex(b));
    /* surface vs surfaceVariant against sheetBackground vs surfaceVariant */
    return d("#ffffff", "#e9ecef") > d("#eff5ef", "#e9ecef");
  })(),
);
ok(
  "the runner is drawn in the page's own paper stock, not a new warm",
  /\.fr \.shelf\.mat::after \{[\s\S]*?--paper3[\s\S]*?--paper2/.test(src),
);
/* ---- the bookend, rewritten ----
   It was one near-black stick at `left: 3.2%` of the shelf: only the leftmost
   cover had anything to lean on, and even that one was leaning at a bookend 15px
   away from itself, because a percentage of the shelf and a book's slot are
   different coordinate systems. It is now one prop per book, positioned off the
   book's own pivot. Each assertion below pins one of those two fixes. */
ok(
  "there is a prop for every book, not one bookend for the shelf",
  (() => {
    const props = (n) =>
      (
        frame(
          libScreen(n === 1 ? R1 : n === 3 ? R3 : R7, {
            lean: "even",
            days: 1,
            deco: "bookend",
          }),
        ).match(/class="bnd"/g) || []
      ).length;
    return props(1) === 1 && props(3) === 3 && props(7) === 7;
  })(),
);
ok(
  "and the props are gone when there is nothing to prop",
  !frame({
    bar: { title: "My Library" },
    body: [
      {
        t: "shelf",
        books: [],
        label: "Reading",
        reading: 1,
        empty: "Nothing in progress",
        lean: "even",
        deco: "bookend",
      },
    ],
  }).includes('class="bnd"'),
  "the old fixed bookend would have stood on an empty plank holding nothing",
);
ok(
  "a prop is only drawn where there is a lean for it to explain",
  !frame(
    libScreen(R3, { days: 1, deco: "bookend" }), // no `lean`
  ).includes('class="bnd"'),
);
ok(
  "the device name is matched as a word, so `board` is not read as a bookend",
  !frame(libScreen(R3, { lean: "even", deco: "board" })).includes(
    'class="bnd"',
  ),
);
/* The contact geometry, which is the whole difference between a book resting ON
   a prop and a book near one. A cover tipped 6.5 degrees about its bottom-left
   corner has its left edge at `y sin 6.5` to the left of that corner, so a plate
   whose right face stands `sin(6.5) x H` to the left is met exactly at the
   plate's top corner. Read the two numbers out of the CSS and check the second
   really is the sine of the lean angle times the first. */
ok(
  "the prop's offset is the lean's own sine, not a number that looked right",
  (() => {
    const k = +(src.match(
      /--prp-x:\s*calc\(var\(--prp-h\)\s*\*\s*([\d.]+)\)/,
    ) || [])[1];
    const deg = +(src.match(
      /\.fr \.bk\.leanV \{[^}]*--lean,\s*(-?[\d.]+)deg/s,
    ) || [])[1];
    return (
      k > 0 &&
      deg < 0 &&
      Math.abs(k - Math.sin((-deg * Math.PI) / 180)) < 0.0005
    );
  })(),
  (() => {
    const k = +(src.match(
      /--prp-x:\s*calc\(var\(--prp-h\)\s*\*\s*([\d.]+)\)/,
    ) || [])[1];
    return `${k} vs sin 6.5 = ${Math.sin((6.5 * Math.PI) / 180).toFixed(4)}`;
  })(),
);
ok(
  "and it is placed from the same pivot the lean is, with no second copy of it",
  /\.fr \.prp \.bnd \{[^}]*left:\s*calc\(var\(--lean-ml\)/.test(src) &&
    /\.fr \.bk\.leanV \{[^}]*margin:[^;]*var\(--lean-ml\)/.test(src),
);
ok(
  "the prop is an L: a plate with a foot that runs out under the cover",
  /\.fr \.prp \.bnd::before \{[^}]*width:\s*calc\(var\(--prp-x\)/.test(src) &&
    /\.fr \.prp \.bnd::before \{[^}]*left:\s*0/.test(src),
);
ok(
  "it stands on the side the books lean toward, and under them",
  /\.fr \.prp \.bnd \{[^}]*left:/.test(src) &&
    !/\.fr \.prp \.bnd \{[^}]*right:/.test(src) &&
    /\.fr \.prp \.bnd \{[^}]*z-index:\s*0/.test(src) &&
    /\.fr \.prp \.bk \{[^}]*z-index:\s*1/.test(src),
);
ok(
  "its material is a ramp off secondaryText, not a new hue",
  /--metal2:\s*#626a72/i.test(src) &&
    /--text2:\s*#626a72/i.test(src) &&
    /\.fr \.prp \.bnd \{[\s\S]*?--metal1[\s\S]*?--metal2[\s\S]*?--metal3/.test(
      src,
    ),
);
ok(
  "and nothing is drawn in primaryText, which is the colour of type",
  !/\.fr \.prp[^{]*\{[^}]*background:\s*var\(--text\)/.test(src),
);
ok(
  "the props cost no width — only the row's left padding moves",
  /\.fr \.shelf\.bookend \.bks \{[^}]*padding-left:\s*calc\(var\(--bk-pad\)/.test(
    src,
  ) && !/\.fr \.prp \{[^}]*width:/.test(src),
);
ok(
  "a propped slot leaves the row's arithmetic alone",
  (() => {
    /* The wrapper shrink-wraps the book plus the margins the book already had, so
       a propped row and a plain leaning row hold the same number of covers. */
    const bare = frame(libScreen(R7, { lean: "even", days: 1 }));
    const prop = frame(
      libScreen(R7, { lean: "even", days: 1, deco: "bookend" }),
    );
    const covers = (h) => (h.match(/class="bk [^"]*leanV/g) || []).length;
    return covers(bare) === covers(prop) && covers(prop) === 7;
  })(),
);
ok("the element gallery shows the object on its own", !!elementById("el-prop"));
/* s-big's bill, which its note states as measured fact. */
ok(
  "bigger stock really does cost capacity",
  (() => {
    const th = 6.5 * (Math.PI / 180);
    const lean = (w, h) => w * Math.cos(th) + h * Math.sin(th);
    const norm = lean(84.4, 126.6);
    const big = lean(84.4 * 1.15, 126.6 * 1.15);
    const cap = (v) => (340.5 + 15) / (v + 15);
    return big > norm && cap(big) < cap(norm) && cap(big) < 3 && cap(norm) > 3;
  })(),
  (() => {
    const th = 6.5 * (Math.PI / 180);
    const lean = (w, h) => w * Math.cos(th) + h * Math.sin(th);
    const cap = (v) => ((340.5 + 15) / (v + 15)).toFixed(2);
    return `${cap(lean(84.4 * 1.15, 126.6 * 1.15))} big vs ${cap(lean(84.4, 126.6))} normal`;
  })(),
);
ok(
  "and s-big says so with a cut marker rather than hiding the clip",
  screenById("s-big")[3].body[0].cut !== undefined,
);
/* "Free" means: neither device changes the book size or the row's reserved
   height. The lamp's bloom does have a height of its own, but it is drawn on a
   pseudo-element outside the row's box — so the check has to look at `.bks` and
   `--bk-h`, not at any height at all. That distinction is what the first version
   of this assertion got wrong. */
ok(
  "the free devices really are free — no extra row height, no bigger books",
  !/\.fr \.shelf\.(lit|mat) \.bks \{[^}]*height:/.test(src) &&
    !/\.fr \.shelf\.(lit|mat)[^{]*\{[^}]*--bk-h/.test(src),
);
ok(
  "whereas the tray, the board and the bigger stock all do cost something",
  /\.fr \.shelf\.tray \{[^}]*padding:/.test(src) &&
    /\.fr \.shelf\.board \.plank \{[^}]*height:/.test(src) &&
    /\.fr \.shelf\.big \{[^}]*--bk-h/.test(src),
);

/* ---- board x tab: the seam, and the contrast that decides it ----
   WCAG relative luminance, so the three answers are judged by measurement
   rather than by eye. This project has form here: `app_theme.dart` records that
   `secondaryText` shipped as #ADB5BD at 2.07:1 until someone measured it. */
head("board x tab");
function lum(hex) {
  const v = hex.replace("#", "");
  const ch = [0, 2, 4].map((i) => {
    const s = parseInt(v.slice(i, i + 2), 16) / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}
const contrast = (a, b) => {
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
};
const BRAND_TEXT = "#067657";
const AA = 4.5;

/* Sanity-check the function against two ratios app_theme.dart states itself. */
ok(
  "the contrast function reproduces the theme's own stated numbers",
  Math.abs(contrast(BRAND_TEXT, "#ffffff") - 5.6) < 0.15 &&
    Math.abs(contrast(BRAND_TEXT, "#e9ecef") - 4.7) < 0.15,
  `white ${contrast(BRAND_TEXT, "#ffffff").toFixed(2)}, variant ${contrast(BRAND_TEXT, "#e9ecef").toFixed(2)}`,
);

const tabs = ["s-tab-seam", "s-tab-match", "s-tab-label", "s-tab-inset"];
ok(
  "the four tab answers are all present",
  tabs.every((id) => screenById(id)),
);
ok(
  "all four keep the lamp and the timber board",
  tabs.every((id) => {
    const d = screenById(id)[3].body[0].deco;
    return d.includes("lit") && d.includes("paperboard");
  }),
);
ok(
  "the seam screen deliberately applies no tab fix",
  !/tab(match|label|inset)/.test(screenById("s-tab-seam")[3].body[0].deco),
);
ok(
  "tabmatch takes the board's own stock, so the shelf is one material",
  /\.fr \.shelf\.paperboard\.tabmatch \.stab \{[\s\S]*?--paper3[\s\S]*?--paper2/.test(
    src,
  ),
);
ok(
  "tabmatch clears AA — and lands where surfaceVariant already sits",
  contrast(BRAND_TEXT, "#efeae0") >= AA,
  `${contrast(BRAND_TEXT, "#efeae0").toFixed(2)}:1 vs ${contrast(BRAND_TEXT, "#e9ecef").toFixed(2)}:1 on surfaceVariant`,
);
ok(
  "tablabel stays surface white and earns it with a drop shadow",
  /\.fr \.shelf\.paperboard\.tablabel \.stab \{[^}]*background:\s*var\(--surface\)[\s\S]*?box-shadow:\s*0 1px/.test(
    src,
  ),
);
ok(
  "tablabel has the best contrast of the three",
  contrast(BRAND_TEXT, "#ffffff") > contrast(BRAND_TEXT, "#efeae0") &&
    contrast(BRAND_TEXT, "#ffffff") > contrast(BRAND_TEXT, "#ded3bd"),
  `${contrast(BRAND_TEXT, "#ffffff").toFixed(2)}:1`,
);
/* The finding this group exists for. */
ok(
  "tabinset FAILS AA — which is why it is drawn and rejected",
  contrast(BRAND_TEXT, "#ded3bd") < AA,
  `${contrast(BRAND_TEXT, "#ded3bd").toFixed(2)}:1, under ${AA}`,
);
ok(
  "and its note says so rather than presenting it as an option",
  /fails?/i.test(screenById("s-tab-inset")[1]) &&
    /3\.79:1/.test(screenById("s-tab-inset")[2]),
);
ok(
  "the stated 3.79 is the measured 3.79",
  contrast(BRAND_TEXT, "#ded3bd").toFixed(2) === "3.79",
);
ok(
  "the escape route the note names really would clear AA",
  contrast("#212529", "#ded3bd") >= AA,
  `primaryText ${contrast("#212529", "#ded3bd").toFixed(2)}:1`,
);
/* Every tab stock this page introduces has to clear AA or be marked failing. */
ok(
  "no tab stock is shipped un-measured",
  [
    ["#ffffff", true],
    ["#efeae0", true],
    ["#ded3bd", false],
  ].every(([bg, shouldPass]) => contrast(BRAND_TEXT, bg) >= AA === shouldPass),
);

/* ---- the runner, relocated ----
   `s-mat` failed for one reason: the paper lay where the books stand, so they
   hid it. Each replacement has to put the paper somewhere the books are NOT,
   and that is what these assert — not that they look better, which needs eyes,
   but that they are structurally incapable of failing the same way. */
const runners = ["s-lamp-panel", "s-lamp-board", "s-lamp-drape"];
ok(
  "all three runner replacements keep the lamp",
  runners.every((id) => screenById(id)[3].body[0].deco.split(" ")[0] === "lit"),
);
ok(
  "and all three are drawn in the page's paper palette, not a new warm",
  [
    /\.fr \.shelf\.panel::after \{[\s\S]*?--paper3[\s\S]*?--paper2/,
    /\.fr \.shelf\.paperboard \.plank \{[\s\S]*?--paper3[\s\S]*?--paper2/,
    /\.fr \.shelf\.drape::after \{[\s\S]*?--paper2[\s\S]*?--paper1/,
  ].every((re) => re.test(src)),
);
ok(
  "the wall sits BEHIND the books — lower z-index than the lit row",
  (() => {
    const wall = +src.match(
      /\.fr \.shelf\.panel::after \{[^}]*z-index:\s*(\d+)/,
    )[1];
    const row = +src.match(
      /\.fr \.shelf\.lit \.bks \{[^}]*z-index:\s*(\d+)/,
    )[1];
    return wall < row;
  })(),
);
ok(
  "the wall is shorter than a book, so covers overtop it",
  +src.match(/\.fr \.shelf\.panel::after \{[^}]*--bk-h\) \* ([\d.]+)/)[1] < 1,
);
ok(
  "under the lamp the wall carries the bloom — it is what the light falls on",
  /\.fr \.shelf\.lit\.panel::after \{[\s\S]*?rgba\(255, 199, 106/.test(src),
);
ok(
  "the timber board is thicker than white, or it reads as a stain",
  +src.match(
    /\.fr \.shelf\.paperboard \.plank \{[^}]*--bk-plank\) \* ([\d.]+)/,
  )[1] > 1,
);
ok(
  "the drape hangs BELOW the board, into the row gap",
  /\.fr \.shelf\.drape::after \{[^}]*bottom:\s*(-\d|calc\(\s*-)/.test(src),
);
ok(
  "and is inset from both ends, so it reads as cloth laid across",
  /\.fr \.shelf\.drape::after \{[^}]*left:\s*17%[\s\S]*?right:\s*17%/.test(src),
);
ok(
  "none of the three costs row height or book size",
  !/\.fr \.shelf\.(panel|paperboard|drape)[^{]*\{[^}]*--bk-h:/.test(src) &&
    !/\.fr \.shelf\.(panel|paperboard|drape) \.bks \{/.test(src),
);
ok(
  "the timber board is the only one that cannot vary with the book count",
  /\.fr \.shelf\.paperboard \.plank/.test(src) &&
    !/\.fr \.shelf\.paperboard::(before|after)/.test(src),
);

/* The runner's size is derived from the frame scale, not hard-coded. This is the
   assertion that would have prevented the bad call: it was `height: 7px`, the one
   dimension on the page untied to the 0.615 scale, so the drawing showed a 7pt
   runner where the shipped one is 11.4pt — and at mockup scale it was written off
   as invisible. Every decoration measured in absolute pixels now has to say so
   through `--bm-k`. */
ok(
  "every fixed-size decoration is scale-derived, so the drawing cannot lie",
  ["mat::after", "drape::after"].every((sel) => {
    const rule = src.match(
      new RegExp(`\\.fr \\.shelf\\.${sel.replace("::", "::")} \\{[^}]*\\}`),
    );
    if (!rule) return false;
    /* No bare `<n>px` outside a calc that multiplies by --bm-k. Percentages and
       var() references are fine. */
    const bare = rule[0].match(/:\s*-?\d+(\.\d+)?px\s*;/g) || [];
    return bare.length === 0;
  }),
);

/* ---- the mixes: the real Reading shelf, leaning, stamped ---- */
head("mixes");
const mixes = ["m-one", "m-even", "m-settle", "m-nook", "m-many"];
const degsOf = (id) =>
  [...frame(screenById(id)[3]).matchAll(/--lean:(-?[\d.]+)deg/g)].map(
    (m) => +m[1],
  );
ok(
  "the five mixes are all present",
  mixes.every((id) => screenById(id)),
);
ok(
  "every mix uses the real shelf tab, not the wordmark",
  mixes.every((id) => {
    const h = frame(screenById(id)[3]);
    return h.includes("stab rtab") && !h.includes('class="w1"');
  }),
);
ok(
  "every mix stamps every open book",
  mixes.every((id) => {
    const s = screenById(id)[3].body[0];
    const h = frame(screenById(id)[3]);
    return (h.match(/class="ds"/g) || []).length === s.books.length;
  }),
);
ok(
  "no mix grows a book — the tilt is the only signal",
  mixes.every((id) => !frame(screenById(id)[3]).includes("heroL")),
);
ok(
  "the mixes reserve leanRow head-room, not the hero's",
  mixes.every((id) => {
    const h = frame(screenById(id)[3]);
    return h.includes("leanRow") && !h.includes("heroRow");
  }),
);
ok(
  "leanRow is cheaper than heroRow",
  (() => {
    const g = (c) =>
      +src.match(
        new RegExp(
          `\\.fr \\.shelf\\.${c} \\.bks \\{[^}]*--bk-h\\) \\* ([\\d.]+)`,
        ),
      )[1];
    return g("leanRow") < g("heroRow");
  })(),
  "1.12 vs 1.42",
);
ok(
  "even gives every book the same angle",
  degsOf("m-even").length === 3 && new Set(degsOf("m-even")).size === 1,
  degsOf("m-even").join(","),
);
ok(
  "settle ramps the angle down, steepest first, never past upright",
  (() => {
    const d = degsOf("m-settle");
    return (
      d.length === 3 &&
      d[0] === -6.5 &&
      d.every((x, i) => i === 0 || x > d[i - 1]) &&
      d[d.length - 1] < 0
    );
  })(),
  degsOf("m-settle").join(","),
);
/* The claim m-many rests on: at 6.5 degrees adjacent covers still clear each
   other, and steepening would reintroduce the withdrawn `leaning` density's
   overlap. The one number that bounds this whole design. */
ok(
  "at 6.5 degrees a leaning row does not shingle",
  126.6 * Math.sin(6.5 * (Math.PI / 180)) < 15,
  `${(126.6 * Math.sin(6.5 * (Math.PI / 180))).toFixed(1)}pt sweep vs 15pt separator`,
);
ok(
  "a leaning cover is wider than an upright one, so capacity falls",
  (() => {
    const th = 6.5 * (Math.PI / 180);
    const lean = 84.4 * Math.cos(th) + 126.6 * Math.sin(th);
    return lean > 84.4 && (340.5 + 15) / (lean + 15) < PER_SHELF;
  })(),
  `${((340.5 + 15) / (84.4 * Math.cos(6.5 * (Math.PI / 180)) + 126.6 * Math.sin(6.5 * (Math.PI / 180)) + 15)).toFixed(2)} leaning vs ${PER_SHELF} upright`,
);

/* ---- lean scope: which books tilt ---- */
head("lean scope");
const leans = ["n-first", "n-all", "n-cascade", "n-none"];
ok(
  "the four lean scopes are all present",
  leans.every((id) => screenById(id)),
);
ok(
  "every lean variant holds the SAME two books at the same label scale",
  leans.every((id) => {
    const l = screenById(id)[3].body[0];
    return (
      l.books.length === 2 && l.w1 === "var(--f-title)" && l.minw === "70%"
    );
  }),
);
const leanHtml = (id) => frame(screenById(id)[3]);
ok(
  "n-first tilts exactly one of the two",
  (leanHtml("n-first").match(/heroL|leanS|leanH/g) || []).length === 1,
);
ok(
  "n-all tilts both, at the same angle",
  (leanHtml("n-all").match(/heroL/g) || []).length === 1 &&
    (leanHtml("n-all").match(/leanS/g) || []).length === 1 &&
    !leanHtml("n-all").includes("leanH"),
);
ok(
  "n-cascade tilts both, the second at half the angle",
  (leanHtml("n-cascade").match(/heroL/g) || []).length === 1 &&
    (leanHtml("n-cascade").match(/leanH/g) || []).length === 1 &&
    !leanHtml("n-cascade").includes("leanS"),
);
ok(
  "n-none tilts nothing and pays no heroRow height",
  !/heroL|leanS|leanH/.test(leanHtml("n-none")) &&
    !leanHtml("n-none").includes("heroRow"),
);
ok(
  "the half angle really is half",
  (() => {
    const g = (c) =>
      +src.match(
        new RegExp(`\\.fr \\.bk\\.${c} \\{[^}]*rotate\\((-?[\\d.]+)deg`),
      )[1];
    return Math.abs(g("leanH") * 2 - g("leanS")) < 0.01;
  })(),
);
ok(
  "every lean shares the hero's pivot, so none can pierce the plank",
  /\.fr \.bk\.leanS,\s*\n\s*\.fr \.bk\.leanH \{[^}]*transform-origin:\s*0%\s+100%/.test(
    src,
  ),
);
ok(
  "only the hero grows — a leaning book is not also a bigger book",
  /o\.leanCls === "heroL" \? 1\.3 : 1/.test(js),
);
ok(
  '`hero: 1` still means "first", so no earlier screen was rewritten',
  (shelfHTML({ books: R3, hero: 1 }).match(/heroL/g) || []).length === 1 &&
    (shelfHTML({ books: R3, lean: "first" }).match(/heroL/g) || []).length ===
      1,
);

/* ---- the hybrids compose through one renderer ---- */
head("the hybrids");
const hybrids = ["h-lede", "h-duo", "h-yield", "h-type-days"];
ok(
  "the four hybrids are all present",
  hybrids.every((id) => screenById(id)),
);
const hLede = frame(screenById("h-lede")[3]);
ok(
  "the lede leans exactly one stamped book beside the wordmark",
  (hLede.match(/heroL/g) || []).length === 1 &&
    hLede.includes("D+12") &&
    hLede.includes('class="w1"'),
);
const hDuo = frame(screenById("h-duo")[3]);
ok(
  "the duo leans the newer book (D+4) and stands the older (D+12)",
  (hDuo.match(/heroL/g) || []).length === 1 &&
    hDuo.indexOf("D+4") < hDuo.indexOf("D+12") &&
    hDuo.indexOf("heroL") < hDuo.indexOf("D+4"),
);
const hType = frame(screenById("h-type-days")[3]);
ok(
  "the grammar-saving variant stamps no cover — the day lives in type",
  !hType.includes('class="ds"') && hType.includes("· D+12"),
);
const hYield = frame(screenById("h-yield")[3]);
ok(
  "the yield returns to a full-width tab — no wordmark at three",
  !hYield.includes('class="w1"') &&
    hYield.includes("stab rtab") &&
    (hYield.match(/class="ds"/g) || []).length === 3 &&
    (hYield.match(/heroL/g) || []).length === 1,
);
ok(
  "the duo's fit is the knife-edge the note claims — a third mini cannot enter",
  (() => {
    /* mini shelf: 58% of a 95% ledge in a 240px frame, minus 2*9.2 padding,
       all in css px at the frame's scale; convert nothing — compare in px. */
    const inner = 240 * 0.95 * 0.58 - 2 * 9.2;
    const hero = 39 * 1.3 + 4 + 10; /* width + margins */
    const gap = 9.2,
      mini = 39;
    return hero + gap + mini <= inner && hero + 2 * (gap + mini) > inner;
  })(),
);

head("every spec renders");
let drew = 0;
const bad = [];
for (const [, items] of SCREENS)
  for (const [id, , , spec] of items) {
    const h = frame(spec);
    drew++;
    if (h.includes("undefined") || h.includes("NaN")) bad.push(id);
  }
for (const [, items] of FLOWS)
  for (const [id, , , steps] of items)
    for (const [, , spec] of steps) {
      const h = frame(spec);
      drew++;
      if (h.includes("undefined") || h.includes("NaN")) bad.push(id);
    }
ok("56 frames drawn without throwing", drew === 60, `${drew}`);
ok("none emits undefined or NaN", bad.length === 0, bad.join(","));
ok(
  "every element demo is a non-empty string",
  ELEMENTS.flatMap(([, i]) => i).every(
    ([, , , html]) => typeof html === "string" && html.length > 40,
  ),
);

/* ================================================================
   versions: inheritance, removal, diff direction
   ================================================================ */
head("versions");
const ids = (v, k) => resolveView(v, k).flatMap(([, l]) => l.map((i) => i[0]));
const mainS = ids("main", "screens");
ok("main holds 50 screens", mainS.length === 50, `${mainS.length}`);
ok(
  "the seven treatments are all present",
  ["t-flat", "t-tent", "t-nook", "t-ledge", "t-band", "t-lean", "t-days"].every(
    (id) => mainS.includes(id),
  ),
);
ok(
  "both zero-state branches inherit every treatment and hybrid",
  ["vanish", "empty-plank"].every(
    (v) =>
      ids(v, "screens").filter((id) => id.startsWith("t-")).length === 7 &&
      ids(v, "screens").filter((id) => id.startsWith("h-")).length === 4,
  ),
);
ok("the root has a null parent", VERSIONS[0][3] === null);
/* The pitfall this guards is "restating an unchanged screen in a patch", which
   reintroduces the drift the data model exists to stop and makes the diff report
   a change where there is none. It used to be checkable as "every patch entry is
   a removal", because the only branches were the two zero-state ones. The two
   finalists ADD screens, so the general form is what has to be asserted: every
   non-null entry either introduces an id the parent does not have, or carries a
   payload that genuinely differs from the parent's. */
ok(
  "no patch restates an unchanged screen",
  VERSIONS.slice(1).every(([id, , , parent, p]) => {
    const before = new Map(
      resolveView(parent, "screens").flatMap(([, l]) =>
        l.map((i) => [i[0], i]),
      ),
    );
    return Object.entries(p.screens || {}).every(([sid, v]) => {
      if (v === null) return before.has(sid);
      const prev = before.get(sid);
      if (!prev) return true; // an addition
      return JSON.stringify(v.spec) !== JSON.stringify(prev[3]);
    });
  }),
);
ok(
  "vanish drops zero-plank and keeps zero-vanish",
  !ids("vanish", "screens").includes("zero-plank") &&
    ids("vanish", "screens").includes("zero-vanish") &&
    ids("vanish", "screens").length === mainS.length - 1,
);
ok(
  "empty-plank drops zero-vanish and keeps zero-plank",
  !ids("empty-plank", "screens").includes("zero-vanish") &&
    ids("empty-plank", "screens").includes("zero-plank") &&
    ids("empty-plank", "screens").length === mainS.length - 1,
);
ok(
  "vanish also drops el-empty",
  !ids("vanish", "elements").includes("el-empty"),
);
ok(
  "empty-plank keeps el-empty",
  ids("empty-plank", "elements").includes("el-empty"),
);
ok(
  "neither branch touches the flows",
  ids("vanish", "flows").length === ids("main", "flows").length &&
    ids("empty-plank", "flows").length === ids("main", "flows").length,
);
ok(
  "vanish adds an OPEN note main does not have",
  !!resolveOpen("vanish")["zero-vanish"] && !resolveOpen("main")["zero-vanish"],
);
ok(
  "every OPEN key names a real id",
  Object.keys(resolveOpen("main")).every(
    (k) => mainS.includes(k) || ids("main", "flows").includes(k),
  ),
  Object.keys(resolveOpen("main")).join(","),
);
/* The labels are point-of-view, not time — run it both ways and check it mirrors. */
const dA = diffMap("vanish", "empty-plank", "screens");
const dB = diffMap("empty-plank", "vanish", "screens");
ok(
  "the diff mirrors exactly",
  dA.get("zero-vanish") === "onlyHere" &&
    dB.get("zero-vanish") === "onlyThere" &&
    dA.get("zero-plank") === "onlyThere" &&
    dB.get("zero-plank") === "onlyHere",
);
ok(
  "and reports only the two zero-state screens",
  [...dA.keys()].sort().join(",") === "zero-plank,zero-vanish",
  [...dA.keys()].join(","),
);

/* ---- the two finalists ----
   These exist to be compared, so what has to hold is that the comparison is
   clean: the same three ids, in the same group, differing in exactly one
   property. If the two branches drift in any other way, ⇧Enter stops answering
   the question it was opened to answer. */
const FIN = ["f-one", "f-three", "f-many"];
const finalSpec = (v, id) =>
  resolveView(v, "screens")
    .flatMap(([, l]) => l)
    .find(([x]) => x === id)[3];
ok(
  "lamp and bookend both branch off main",
  ["lamp", "bookend"].every((v) => VMAP.get(v) && VMAP.get(v)[3] === "main"),
);
ok(
  "each carries the same three states, and main carries none of them",
  ["lamp", "bookend"].every((v) =>
    FIN.every((id) => ids(v, "screens").includes(id)),
  ) && FIN.every((id) => !mainS.includes(id)),
);
ok(
  "one book, three, and the overflow at seven — not three drawings of the same row",
  ["lamp", "bookend"].every(
    (v) =>
      finalSpec(v, "f-one").body[0].books.length === 1 &&
      finalSpec(v, "f-three").body[0].books.length === 3 &&
      finalSpec(v, "f-many").body[0].books.length === 7,
  ),
);
ok(
  "the finalists' screens land in one group, so the grid pairs them",
  (() => {
    const groupOf = (v, id) =>
      resolveView(v, "screens").find(([, l]) => l.some(([x]) => x === id))[0];
    return FIN.every((id) => groupOf("lamp", id) === groupOf("bookend", id));
  })(),
);
ok(
  "the ONLY thing that differs is the device",
  FIN.every((id) => {
    const a = finalSpec("lamp", id),
      b = finalSpec("bookend", id);
    const strip = (s) => {
      const c = JSON.parse(JSON.stringify(s));
      delete c.body[0].deco;
      return JSON.stringify(c);
    };
    return (
      a.body[0].deco === "lit" &&
      b.body[0].deco === "bookend" &&
      strip(a) === strip(b)
    );
  }),
);
ok(
  "and each state says something of its own about its device",
  (() => {
    const notes = ["lamp", "bookend"].flatMap((v) =>
      resolveView(v, "screens")
        .flatMap(([, l]) => l)
        .filter(([x]) => FIN.includes(x))
        .map(([, , ds]) => ds),
    );
    return new Set(notes).size === 6 && notes.every((n) => n && n.length > 200);
  })(),
);
ok(
  "the finalists inherit the whole exploration rather than replacing it",
  ["lamp", "bookend"].every(
    (v) => ids(v, "screens").length === mainS.length + FIN.length,
  ),
);
const dF = diffMap("lamp", "bookend", "screens");
ok(
  "comparing the two reports exactly the three states, all as changed",
  [...dF.keys()].sort().join(",") === FIN.slice().sort().join(",") &&
    FIN.every((id) => dF.get(id) === "changed"),
  [...dF.entries()].map(([k, v]) => `${k}:${v}`).join(","),
);
ok(
  "neither finalist disturbs the zero-state axis",
  ["lamp", "bookend"].every(
    (v) =>
      ids(v, "screens").includes("zero-vanish") &&
      ids(v, "screens").includes("zero-plank"),
  ),
  "a device can ship with either answer",
);

/* ================================================================
   search — including the OPEN callouts, which is why visibleOpts changed
   ================================================================ */
head("search");
function shits(q) {
  const o = [];
  const open = resolveOpen("main");
  for (const [g, items] of SCREENS)
    for (const [id, nm, ds] of items) {
      const hay = stripTags(
        `${nm} ${ds || ""} ${open[id] || ""}`,
      ).toLowerCase();
      if (
        matchWords(g.toLowerCase(), q.toLowerCase()) ||
        matchWords(hay, q.toLowerCase())
      )
        o.push(id);
    }
  return o;
}
[
  ["clampDropIndex", "reading-spines"],
  ["kCardReadingMax", "reading-three"],
  ["shelves.name", "collision"],
  ["hero", "reading-one"],
  ["168pt", "reading-one"],
  ["friendsReadingProvider", "visit"],
  ["kShelfLiftDelay", "edit-mode"],
  ["nightstand", "t-flat"],
  ["face-down", "t-tent"],
  ["alcove", "t-nook"],
  ["GowunBatang", "t-ledge"],
  ["idiom", "t-band"],
  ["staff pick", "t-lean"],
  ["start_date", "t-days"],
  ["month stamps", "t-days"],
  ["lede", "h-lede"],
  ["knife", "h-duo"],
  ["yields", "h-yield"],
  ["grammar-saving", "h-type-days"],
].forEach(([q, id]) =>
  ok(`'${q}' finds ${id}`, shits(q).includes(id), shits(q).join(",")),
);
ok(
  "'zero' finds both answers",
  shits("zero").length === 2,
  shits("zero").join(","),
);
ok(
  "term order does not matter",
  shits("shelf reading").length === shits("reading shelf").length,
);
ok("a nonsense query returns nothing", shits("wombat").length === 0);

/* ================================================================
   keyboard focus across the re-render visibleOpts() feeds
   ================================================================ */
head("keyboard focus");
let LAST = [];
clist.querySelectorAll = () => {
  const out = [];
  const re = /<div class="copt([^"]*)" data-id="([^"]+)"/g;
  let x;
  while ((x = re.exec(clist.innerHTML))) {
    const cls = new Set(x[1].trim().split(/\s+/).filter(Boolean));
    out.push({
      _cls: cls,
      dataset: { id: x[2] },
      classList: {
        add: (c) => cls.add(c),
        remove: (c) => cls.delete(c),
        contains: (c) => cls.has(c),
        toggle: () => {},
      },
      scrollIntoView() {},
    });
  }
  return (LAST = out);
};
const shown = () => LAST.map((r) => r.dataset.id);
const focused = () => LAST.find((r) => r._cls.has("kb"))?.dataset.id;
/* `renderList()` calls `clist.querySelectorAll('.copt')` itself and adds the `kb`
   class to one of the objects it gets back — so the harness must read THAT array,
   not build a fresh one afterwards, or the focus class is lost between them. */
const list = (q, id) => {
  setView("screens");
  csearch.value = q;
  if (id !== undefined) setKbId(id);
  renderList();
};

list("", null);
ok(
  "an unfiltered list focuses the first option",
  focused() === "today-covers",
  focused(),
);
list("reading", "reading-spines");
ok(
  "focus survives a narrowing that keeps it",
  focused() === "reading-spines",
  focused(),
);
/* "shelves.name" appears in exactly one screen, so the fallback target is
   unambiguous — "collision" itself stopped being unique once the ledge's note
   discussed the name-collision. */
list("shelves.name", "reading-spines");
ok(
  "focus falls back to the first row when narrowed out",
  focused() === "collision",
  focused(),
);
list("wombat", "collision");
ok(
  "no matches sets the focus state to null rather than indexing an empty list",
  kbState().kbId === null && kbState().kbIndex === -1,
  `${kbState().kbId}/${kbState().kbIndex}`,
);
ok("and renders the empty state", clist.innerHTML.includes("No matches"));
/* "flyShelfFromLibrary" lives only in reading-one's OPEN callout — "hero" itself now
   also appears in four treatment notes. (It was "shelfHeroTag" while that callout was
   still a question; the resolved note names the flag the details page actually reads.) */
list("flyShelfFromLibrary", null);
ok(
  "an OPEN-only term reaches its option",
  shown().join(",") === "reading-one",
  shown().join(","),
);
list("consequences", null);
ok(
  "a group name pulls exactly its own group and does not flood",
  shown().join(",") === "origin,edit-mode,collision,visit",
  shown().join(","),
);

console.log(
  fail
    ? `\n${fail} FAILURE(S)`
    : "\nall assertions passed (drawing still needs eyes)",
);
process.exit(fail ? 1 : 0);
