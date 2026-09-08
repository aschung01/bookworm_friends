/*
 * Verifies index.html without a browser. Run from the project root:
 *
 *     node docs/mockups/card-cover-crop/verify.js
 *
 * This page is a claim about arithmetic, so unusually much of it can be checked
 * here: that the port of `bookHash` matches the Dart's pinned goldens, that the
 * numbers in the prose are the export's numbers, that every option's row fits
 * inside 106 drawing units and inside the well's height, and that only the two
 * options which are *supposed* to crop do crop.
 *
 * What it cannot check is what the page looks like, and on this page that limit
 * bites harder than usual: the entire bug being drawn was invisible to the
 * arithmetic in the original mockup, because that mockup filled its covers with
 * a flat colour. So there is one structural guard for exactly that -- every
 * cover must be drawn with a jacket that has a title in it -- and the rest needs
 * eyes.
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

/* ---- the script extracts and parses ---- */
const m = src.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) {
  console.log("FAIL no script block found");
  process.exit(1);
}
const js = m[1];
ok("backticks balanced", js.split("`").length % 2 === 1);
ok("one generic .gone rule", /\.gone\s*\{\s*display:\s*none/.test(src));
ok(
  "no raster images: every cover is drawn, so the crop is visible",
  !/<img[\s>]/i.test(src),
);

/* ---- a DOM stub, so the page's own load path runs ---- */
const mk = () => ({
  _v: "",
  set innerHTML(v) {
    this._v = v;
  },
  get innerHTML() {
    return this._v;
  },
  textContent: "",
  checked: false,
  dataset: {},
  style: {},
  classList: { toggle() {}, add() {}, remove() {}, contains: () => false },
  addEventListener() {},
  querySelectorAll: () => [],
  querySelector: () => null,
});
const nodes = new Map();
global.document = {
  getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, mk());
    return nodes.get(id);
  },
  querySelectorAll: () => [],
  addEventListener() {},
};
global.window = { addEventListener() {} };

/* The assertions run inside the same eval as the page, because the page's
   top-level `const`s are scoped to it and are not reachable from out here. */
const assertions = String.raw`
console.log("load: ok");

/* ---- the hash is the Dart's hash ----

   Golden values lifted from test/book_geometry_test.dart. If this fails, the
   jitter drawn on this page is not the jitter on the phone and nothing else on
   the page can be trusted. */
ok("bookHash 9788936434120", bookHash("9788936434120") === 848182861, String(bookHash("9788936434120")));
ok("bookHash 9780451524935", bookHash("9780451524935") === 1030674525, String(bookHash("9780451524935")));
ok("bookHash 9780141439518", bookHash("9780141439518") === 3499888009, String(bookHash("9780141439518")));
ok("bookHash 9791188331796", bookHash("9791188331796") === 1196771503, String(bookHash("9791188331796")));
ok("bookHash 9788954682152", bookHash("9788954682152") === 753300405, String(bookHash("9788954682152")));
ok("bookHash OL12345W", bookHash("OL12345W") === 3637877494, String(bookHash("OL12345W")));
ok("bookHash '' is the FNV basis", bookHash("") === 0x811c9dc5);
ok("bookHash is never negative over the corpus",
   CORPUS.every(b => bookHash(b.isbn) >= 0 && bookHash(b.isbn) < 0x100000000));
ok("multi-byte titles do not collapse",
   new Set(["아몬드","소년이 온다","책"].map(bookHash)).size === 3);

/* ---- the geometry is the export's geometry ---- */
ok("card is 360x450", CARD_W === 360 && CARD_H === 450);
ok("well is 207pt", Math.abs(WELL_H - 207) < 1e-9, String(WELL_H));
ok("row unit is 7.5% under the card unit",
   Math.abs(ROW_U / U - 0.9245) < 0.001, "ROW_U/U = " + (ROW_U / U).toFixed(4));
ok("today's smallest cover is ~17pt wide",
   Math.abs(5.4 * ROW_U - 16.96) < 0.05, (5.4 * ROW_U).toFixed(2) + "pt");
ok("the well has room the row does not use",
   H_BUDGET_U > 55 && 18 * ROW_U < 60,
   "budget " + H_BUDGET_U.toFixed(1) + "u vs tallest row " + (18 * ROW_U).toFixed(1) + "pt");
ok("kGeneratedCoverMinWidth is 51.85pt", Math.abs(GEN_MIN_W - 51.851) < 0.01);

/* ---- the tier table's claim ---- */
ok("tier 1 is exactly 2/3", Math.abs(tierFor(3).w / tierFor(3).h - ASPECT) < 1e-9);
ok("tier 2 is 0.50", Math.abs(tierFor(6).w / tierFor(6).h - 0.5) < 1e-9);
ok("tier 3 is 0.36", Math.abs(tierFor(12).w / tierFor(12).h - 0.36) < 1e-9);
(function () {
    const t = tierFor(12);
    const keep = (t.w / t.h) / ASPECT;
    ok("tier 3 keeps 54% of a jacket", Math.abs(keep - 0.54) < 0.005, (keep * 100).toFixed(1) + "%");
})();

/* ---- BoxFit.cover, reproduced ---- */
(function () {
    /* A box the same shape as the source crops nothing. */
    const same = fitCover(20, 30, 0.5, 0.5);
    ok("a 2/3 box crops nothing", same.vis > 0.9999, same.vis.toFixed(4));
    /* A narrower box crops horizontally and only horizontally. */
    const narrow = fitCover(10, 30, 0.5, 0.5);
    ok("a narrow box crops sideways", Math.abs(narrow.sh - 30) < 1e-9 && narrow.sw > 10);
    ok("centre alignment splits the loss", Math.abs(narrow.l - (10 - narrow.sw) / 2) < 1e-9);
    const left = fitCover(10, 30, 0, 0);
    ok("topLeft alignment keeps the left edge", left.l === 0 && left.t === 0);
    ok("aligning does not change how much is lost", Math.abs(left.vis - narrow.vis) < 1e-12);
})();

/* ---- every option fits, in both axes ---- */
function measure(opt, n) {
    const o = Object.assign({ lit: false, diag: false, sizeJitter: false }, opt.o || {});
    /* The phase-out is the only option handed the open books, so the fit checks have
       to hand them over too: they are the widest items in its front group. */
    const books = opt.reading
        ? READING.slice(0, 2).concat(booksFor(opt.take(n)))
        : booksFor(opt.take(n));
    /* The *owned* count, not the drawn one. Handing a layout its own output as the
       total is how an overflow plate silently disappears -- which it did, and two
       assertions caught it. */
    const total = opt.reading ? 2 + n : n;
    const lay = opt.lay(books, o, total);
    let usedU = 0, hPt = 0;
    lay.rows.forEach(function (r, ri) {
        const plateHere =
            ri === (lay.plateRow === undefined ? 0 : lay.plateRow) && lay.plate;
        /* A pressed row's air comes from the faces at its front, one gap each. */
        const gaps = r.pressed
            ? GAP_U * r.items.filter(i => i.gap).length
            : GAP_U * (r.items.length - 1);
        const u = r.stack
            ? Math.max.apply(null, r.items.map(i => i.xU + i.wU))
              + (plateHere ? lay.plate.wU + GAP_U : 0)
            : r.items.reduce((a, c) => a + c.wU, 0) + gaps
              + (plateHere ? lay.plate.wU + GAP_U : 0);
        usedU = Math.max(usedU, u);
        hPt += (Math.max.apply(null, r.items.map(i => i.hU)) + BOARD_U + BOARD_GAP_U) * ROW_U
             + (ri > 0 ? 6 : 0);
    });
    const items = lay.rows.reduce((a, r) => a.concat(r.items), []);
    const faces = items.filter(i => i.kind === "face");
    const worst = faces.length
        ? Math.min.apply(null, faces.map(function (i) {
              const a = i.wU / i.hU;
              return a < ASPECT ? a / ASPECT : ASPECT / a;
          }))
        : 1;
    return { usedU: usedU, hPt: hPt, worst: worst, items: items, faces: faces, lay: lay };
}

const COUNTS_T = [1, 2, 3, 4, 6, 7, 12, 22];
OPTS.forEach(function (opt) {
    let widest = 0, tallest = 0, minKeep = 1;
    COUNTS_T.forEach(function (n) {
        const r = measure(opt, n);
        widest = Math.max(widest, r.usedU);
        tallest = Math.max(tallest, r.hPt);
        minKeep = Math.min(minKeep, r.worst);
    });
    /* A row that overflows is a clipped cover in an image that has already left
       the phone, which is the one failure mode with no recovery. */
    ok("[" + opt.id + "] never exceeds 106 units", widest <= CARD_UNITS + 0.05, widest.toFixed(2) + "u");
    ok("[" + opt.id + "] never exceeds the well", tallest <= WELL_H - PAD + 0.5,
       tallest.toFixed(1) + "pt of " + (WELL_H - PAD).toFixed(1));
    /* The whole point: only the two options that are meant to crop do. */
    const meantTo = opt.id === "now" || opt.id === "align";
    ok("[" + opt.id + "] " + (meantTo ? "crops, as described" : "crops nothing"),
       meantTo ? minKeep < 0.7 : minKeep > 0.995,
       "keeps " + (minKeep * 100).toFixed(1) + "%");
});

/* ---- the options' specific claims ---- */
(function () {
    const mean = (r) => r.faces.reduce((a, i) => a + i.wU, 0) / r.faces.length;
    const now = measure(OPTS[0], 12);
    const cap = measure(OPTS.find(o => o.id === "cap"), 12);
    const rows = measure(OPTS.find(o => o.id === "rows"), 12);
    const nowW = mean(now), capW = mean(cap), rowsW = mean(rows);
    ok("cap is ~1.7x today's cover width", capW / nowW > 1.6 && capW / nowW < 1.8,
       (capW / nowW).toFixed(2) + "x");
    ok("two rows is wider still", rowsW > capW, (rowsW / nowW).toFixed(2) + "x today");
    ok("two rows clears the generated-title floor at 12",
       Math.max.apply(null, rows.faces.map(i => i.wU)) * ROW_U >= GEN_MIN_W - 1,
       (Math.max.apply(null, rows.faces.map(i => i.wU)) * ROW_U).toFixed(1) + "pt vs " + GEN_MIN_W.toFixed(1));
    ok("two rows draws two boards at 12", rows.lay.rows.length === 2);
    ok("two rows leaves the low tiers alone",
       measure(OPTS.find(o => o.id === "rows"), 6).lay.rows.length === 1);
})();
(function () {
    const cap = measure(OPTS.find(o => o.id === "cap"), 22);
    ok("cap draws " + CAP + " and states the rest", cap.items.length === CAP && cap.lay.plate.rest === 22 - CAP,
       "plate +" + cap.lay.plate.rest);
    const capSmall = measure(OPTS.find(o => o.id === "cap"), 4);
    ok("cap prints no plate when nothing is hidden", capSmall.lay.plate === null);
})();
(function () {
    const s12 = measure(OPTS.find(o => o.id === "stack"), 12);
    const s22 = measure(OPTS.find(o => o.id === "stack"), 22);
    ok("stack draws every book at 22", s22.items.length === 22);
    ok("stack tightens rather than shrinking",
       Math.abs(s12.lay.baseWU - s22.lay.baseWU) < 1e-9 && s22.lay.stepU < s12.lay.stepU,
       "cover " + (s12.lay.baseWU * ROW_U).toFixed(1) + "pt at both; step "
       + s12.lay.stepU.toFixed(2) + "u -> " + s22.lay.stepU.toFixed(2) + "u");
    ok("stack puts the newest on top and whole",
       s12.items[s12.items.length - 1].b.isbn === CORPUS[0].isbn &&
       s12.items[s12.items.length - 1].z === 12);
})();
(function () {
    const sp = measure(OPTS.find(o => o.id === "spines"), 12);
    ok("spines draw no faces", sp.faces.length === 0 && sp.items.length === 12);
    /* The tint has a contrast floor, which is what lets every spine carry white
       type. If this fails the vertical titles are not legible. */
    const worst = Math.min.apply(null, CORPUS.map(b =>
        contrastRatio(spineTintFor(b.thumb ? b.c : generatedCoverColor(b.isbn)), "#FFFFFF")));
    ok("every spine tint clears " + kTintMinContrast + ":1 against white",
       worst >= kTintMinContrast - 0.01, worst.toFixed(2) + ":1");
    /* And it is the shipped function, not an approximation of it: a washed-out
       cover must gain chroma, a black one must not. */
    ok("a pale neutral gains chroma", saturation(spineTintFor("#DCD8D1")) > 0.05);
    ok("a black cover gains none", saturation(spineTintFor("#000000")) < 0.05);
})();
(function () {
    const h = measure(OPTS.find(o => o.id === "hybrid"), 22);
    ok("hybrid faces the newest " + FACES, h.faces.length === FACES &&
       h.faces[0].b.isbn === CORPUS[0].isbn);
    ok("hybrid spines are legible or absent",
       h.items.filter(i => i.kind === "spine").every(i => i.wU >= MIN_SPINE_U - 1e-9),
       "min " + Math.min.apply(null, h.items.filter(i => i.kind === "spine").map(i => i.wU)).toFixed(2) + "u");
    ok("hybrid accounts for every book",
       FACES + h.items.filter(i => i.kind === "spine").length + (h.lay.plate ? h.lay.plate.rest : 0) === 22);
})();

/* ---- the jitter toggle does what the prose says ---- */
(function () {
    const opt = OPTS[0];
    const aspects = (sizeJitter) => {
        const lay = opt.lay(booksFor(12), { sizeJitter: sizeJitter });
        return lay.rows[0].items.map(i => i.wU / i.hU);
    };
    const shipped = aspects(false);
    const fixed = aspects(true);
    ok("the shipped jitter moves the aspect",
       new Set(shipped.map(a => a.toFixed(3))).size > 1,
       new Set(shipped.map(a => a.toFixed(2))).size + " distinct aspects");
    ok("size jitter holds it still",
       new Set(fixed.map(a => a.toFixed(6))).size === 1);
    ok("but size jitter does not fix the crop",
       Math.abs(fixed[0] - 0.36) < 1e-9);
})();

/* ---- the render path emits balanced, escaped markup ----

   The chevron filler in the strip is the specific trap: unescaped, a browser
   reads a run of them as a tag and swallows the rest of the card, and the markup
   still "works". That was bug 1 on the sharing mockup. */
(function () {
    let html = "";
    [2, 7, 12, 22].forEach(function (n) {
        [false, true].forEach(function (lit) {
            [false, true].forEach(function (diag) {
                OPTS.forEach(function (opt) {
                    const o = Object.assign(
                        { lit: lit, diag: diag, sizeJitter: false,
                          stamped: lit && opt.take(n) <= STAMP_MAX,
                          marked: lit && opt.take(n) > STAMP_MAX },
                        opt.o || {});
                    const lay = opt.lay(booksFor(opt.take(n)), o, n);
                    html += stageHtml(lay, o, n) + metricsOf(lay, o, n);
                });
            });
        });
    });
    const open = (html.match(/<(?!\/)[a-z]/g) || []).length;
    const close = (html.match(/<\//g) || []).length;
    const selfish = (html.match(/<br \/>/g) || []).length;
    ok("tags balanced across every state", open - selfish === close,
       open + " open, " + close + " close");
    ok("no raw < in the strip filler", !/MEMBER06MAY26<</.test(html));
    ok("no stray undefined or NaN", !/undefined|NaN/.test(html),
       (html.match(/undefined|NaN/g) || []).slice(0, 3).join(","));
    /* The structural guard for the bug this page exists to draw: a flat swatch
       cannot show a crop, so every face must carry a title. */
    const faces = (html.match(/class="jk s\d/g) || []).length;
    ok("every face is drawn as a jacket with type on it", faces > 200, faces + " jackets");
    ok("candlelight still reveals something", /class="stamp"/.test(html) && /class="mark"/.test(html));
})();

/* ---- the hybrid: two boards, overlapping only when the count demands it ---- */
(function () {
    const modeAt = (n) => boardPlan(n).mode;
    ok("one board up to 5", [1,2,3,4,5].every(n => modeAt(n) === "A"), [1,2,3,4,5].map(modeAt).join(""));
    ok("a second board from 6 to 10", [6,7,8,9,10].every(n => modeAt(n) === "B"), [6,7,8,9,10].map(modeAt).join(""));
    ok("overlap from 11", [11,12,22,40,60].every(n => modeAt(n) === "C"), [11,12,22,40,60].map(modeAt).join(""));

    /* The floors are the whole design, so they are asserted rather than trusted. */
    const gapped = COUNTS_T.filter(n => boardPlan(n).stepU === null);
    ok("no gapped regime goes under the face floor",
       gapped.every(n => boardPlan(n).wU >= MIN_FACE_U - 1e-9),
       "min " + Math.min.apply(null, gapped.map(n => boardPlan(n).wU)).toFixed(2) + "u of " + MIN_FACE_U.toFixed(2));
    const lapped = COUNTS_T.concat([200, 500]).filter(n => boardPlan(n).stepU !== null);
    ok("no sliver goes under the step floor",
       lapped.every(n => boardPlan(n).stepU >= MIN_STEP_U - 1e-9),
       "min " + Math.min.apply(null, lapped.map(n => boardPlan(n).stepU)).toFixed(2) + "u");

    /* The claim the hybrid is built on: past 11 the covers stop shrinking. */
    const widths = [11,12,22,30,40,60,100,500].map(n => boardPlan(n).wU);
    ok("covers stop shrinking once overlap starts",
       new Set(widths.map(w => w.toFixed(6))).size === 1,
       (widths[0] * ROW_U).toFixed(1) + "pt at every count");

    ok("every book is drawn or counted",
       COUNTS_T.concat([200]).every(n => { const p = boardPlan(n); return p.drawn + p.rest === n; }));
})();

/* ---- capacity ---- */
(function () {
    ok("MAX_BOOKS is the step floor's answer",
       MAX_BOOKS === 2 * (1 + Math.floor((CARD_UNITS - OVERLAP_W_U) / MIN_STEP_U)),
       MAX_BOOKS + " books, " + MAX_BOOKS / 2 + " per board");
    ok("the last book that fits, fits", boardPlan(MAX_BOOKS).rest === 0);
    ok("the next one does not",
       boardPlan(MAX_BOOKS + 1).rest > 0 && boardPlan(MAX_BOOKS + 1).atCeiling === true);
    /* The plate is paid for out of the same 106 units, so crossing the ceiling costs
       drawn covers. Pinned because a clipped plate is exactly the class of defect
       this page exists to catch, and it is invisible to the eye at a glance. */
    ok("the plate is reserved, not overhung",
       COUNTS_T.concat([61, 80, 200, 500]).every(function (n) {
           const p = boardPlan(n);
           if (!p.rest) return true;
           return (p.per - 1) * p.stepU + p.wU + GAP_U + PLATE_U <= CARD_UNITS + 1e-9;
       }));
    ok("and it costs a few covers to carry",
       boardPlan(MAX_BOOKS + 1).drawn < MAX_BOOKS,
       MAX_BOOKS + " drawn at the ceiling, " + boardPlan(MAX_BOOKS + 1).drawn + " once the plate appears");
    ok("the geometric limit is wider than the useful one",
       MAX_BOOKS_GEOMETRIC > MAX_BOOKS,
       MAX_BOOKS + " useful vs " + MAX_BOOKS_GEOMETRIC + " geometric");
    /* At the geometric limit a sliver is the binding band and nothing else, which is
       why it is a limit rather than a recommendation: there is no artwork in it. */
    const limitStep = (CARD_UNITS - OVERLAP_W_U) / (MAX_BOOKS_GEOMETRIC / 2 - 1);
    ok("the geometric limit's sliver is all binding band",
       Math.abs(limitStep - BIND_U) < 0.03, limitStep.toFixed(3) + "u vs " + BIND_U);
    ok("the ladder spans no-overflow to overflow",
       CAP_LADDER.some(n => boardPlan(n).rest === 0) &&
       CAP_LADDER.some(n => boardPlan(n).rest > 0));

    /* Two boards is the last legal layout, and only just. Both halves of that claim
       are load-bearing in the prose, so both are pinned. */
    ok("two boards clear the face floor",
       OVERLAP_W_U >= MIN_FACE_U,
       (OVERLAP_W_U * ROW_U).toFixed(1) + "pt vs " + GEN_MIN_W.toFixed(1) + "pt");
    ok("and only just",
       OVERLAP_W_U - MIN_FACE_U < 0.5,
       ((OVERLAP_W_U - MIN_FACE_U) * ROW_U).toFixed(2) + "pt of headroom");
    ok("a third board cannot carry a legible cover",
       CAP3_W_U < MIN_FACE_U,
       (CAP3_W_U * ROW_U).toFixed(1) + "pt vs " + GEN_MIN_W.toFixed(1) + "pt floor");
})();

/* ---- the hybrid beats each parent where that parent is weak ---- */
(function () {
    const mean = (r) => r.faces.reduce((a, i) => a + i.wU, 0) / r.faces.length;
    const boards = OPTS.find(o => o.id === "boards");
    const rows = OPTS.find(o => o.id === "rows");
    const stack = OPTS.find(o => o.id === "stack");
    ok("bigger covers than two-boards-alone at 22",
       mean(measure(boards, 22)) > mean(measure(rows, 22)) * 1.3,
       (mean(measure(boards, 22)) * ROW_U).toFixed(1) + "pt vs " +
       (mean(measure(rows, 22)) * ROW_U).toFixed(1) + "pt");
    ok("hides nothing where overlap-alone already hides",
       measure(boards, 10).lay.plan.stepU === null && measure(stack, 10).lay.shown < 1,
       "boards: nothing hidden; stack: " +
       (measure(stack, 10).lay.shown * 100).toFixed(0) + "% shown");
})();

/* ---- lean ---- */
(function () {
    const at = (lean) => layoutBoards(booksFor(22), { lean: lean }).rows[0].items;
    const L = at("left"), R = at("right");
    const topOf = (items) => items.reduce((a, c) => (c.z > a.z ? c : a));
    /* Whichever end is on top is the end that shows a whole jacket, and it is the
       newest book either way -- the toggle chooses which side of the *others* you
       see, not whether the newest is whole. */
    ok("lean left puts the newest leftmost and on top",
       L[0].b.isbn === CORPUS[0].isbn && topOf(L) === L[0] && L[0].xU === 0);
    ok("lean right puts the newest rightmost and on top",
       topOf(R).b.isbn === CORPUS[0].isbn && topOf(R) === R[R.length - 1]);
    ok("both draw the same books",
       L.length === R.length &&
       new Set(L.map(i => i.b.isbn)).size === new Set(R.map(i => i.b.isbn)).size);
})();

/* ---- the corpus stretches without tiling ---- */
(function () {
    const big = booksFor(MAX_BOOKS);
    ok("the ladder's longest row can be drawn", big.length === MAX_BOOKS);
    ok("every drawn book has its own hash",
       new Set(big.map(b => bookHash(b.isbn))).size === MAX_BOOKS,
       new Set(big.map(b => bookHash(b.isbn))).size + " distinct");
    ok("the first 22 are still the drawn corpus",
       big.slice(0, 22).every((b, i) => b === CORPUS[i]));
})();

/* ---- the phase-out ---- */
(function () {
    const plan = (nr, nf) => phasePlan(nr, nf);

    /* Spine geometry is derived from BookVertical rather than typed, so a change to
       the read pile's proportions has to move these together. */
    ok("a spine is the read pile's own proportion",
       Math.abs(SPINE_W_U - (26 / 124) * CAP2_U) < 1e-12,
       (SPINE_W_U * ROW_U).toFixed(1) + "pt on a " + (CAP2_U * ROW_U).toFixed(1) + "pt spine");
    ok("a titled spine's floor comes from its own type size",
       Math.abs(MIN_TITLED_SPINE_U * ROW_U * SPINE_TITLE_RATIO - 5) < 1e-9,
       (MIN_TITLED_SPINE_U * ROW_U).toFixed(1) + "pt carries 5pt type");

    /* The promise: the front group gives way, the open books do not. */
    const faceCounts = [12, 22, 28, 31, 33, 36, 40, 60, 90].map(n => plan(2, n - 2).faces);
    ok("the face count only ever falls as the library grows",
       faceCounts.every((f, i) => i === 0 || f <= faceCounts[i - 1]),
       faceCounts.join(" -> "));
    ok("it never falls below the open books",
       [12, 40, 90, 200].every(n => plan(2, n - 2).faces >= 2),
       [12, 40, 90, 200].map(n => plan(2, n - 2).faces).join(","));
    ok("one open book keeps one face", plan(1, 199).faces === 1);
    ok("and with nothing open there is still a face at the front",
       plan(0, 200).faces === 1);

    /* Spines hold at their natural width until the faces have finished falling --
       that ordering is what the whole option is built on. */
    ok("spines only thin once the front group is down to the open books",
       [12, 22, 31].every(n => {
           const p = plan(2, n - 2);
           return p.spineW === null || Math.abs(p.spineW - SPINE_W_U) < 1e-9;
       }));
    ok("then they thin rather than dropping books",
       plan(2, 58).spineW < SPINE_W_U && plan(2, 58).rest === 0,
       (plan(2, 58).spineW * ROW_U).toFixed(1) + "pt spine, " +
       plan(2, 58).rest + " dropped");
    ok("no spine goes under the sliver floor",
       [12, 40, 60, 90, 200, 500].every(n => {
           const p = plan(2, n - 2);
           return p.spineW === null || p.spineW >= MIN_SLIVER_U - 1e-9;
       }));

    /* The renderer follows the width, so the titled/untitled split is a consequence
       rather than a fourth decision. */
    ok("a titled spine is drawn wherever the width allows one",
       [22, 40].every(n => plan(2, n - 2).counts.spine > 0 && plan(2, n - 2).counts.sliver === 0));
    ok("and slivers appear only below that width",
       plan(2, 118).counts.sliver > 0 && plan(2, 118).counts.spine === 0,
       (plan(2, 118).spineW * ROW_U).toFixed(1) + "pt vs the " +
       (MIN_TITLED_SPINE_U * ROW_U).toFixed(1) + "pt floor");

    ok("every book is drawn or counted",
       [12, 22, 40, 60, 90, 200, 500].every(n => {
           const p = plan(2, n - 2);
           return p.drawn + p.rest === n;
       }));
})();

/* ---- what the phase-out buys over its two parents ---- */
(function () {
    const capacityAt = (nReading) => {
        let n = nReading + 1;
        while (n < 4000 && phasePlan(nReading, n - nReading).rest === 0) n++;
        return n - 1;
    };
    const cap2 = capacityAt(2);
    ok("the phase-out reaches further than boards",
       cap2 > MAX_BOOKS * 1.4,
       cap2 + " books vs " + MAX_BOOKS + " for boards");
    ok("the last book that fits, fits", phasePlan(2, cap2 - 2).rest === 0);
    ok("the next one goes on the plate", phasePlan(2, cap2 - 1).rest > 0);
    const mean = (r) => r.faces.reduce((a, i) => a + i.wU, 0) / r.faces.length;
    const ph = mean(measure(OPTS.find(o => o.id === "phase"), 22));
    const hy = mean(measure(OPTS.find(o => o.id === "hybrid"), 22));
    ok("bigger faces than face-out-and-spine at 22", ph > hy,
       (ph * ROW_U).toFixed(1) + "pt vs " + (hy * ROW_U).toFixed(1) + "pt");
})();

/* ---- the open books are drawn as a different class ---- */
(function () {
    const books = READING.slice(0, 2).concat(booksFor(20));
    const o = { lit: false, diag: false, stamped: false, marked: false };
    const lay = layoutPhase(books, o, 22);
    const items = lay.rows.reduce((a, r) => a.concat(r.items), []);
    ok("the open books are at the front",
       items[0].b.reading === true && items[1].b.reading === true);
    ok("and they are faces", items[0].kind === "face" && items[1].kind === "face");
    ok("they carry a bookmark",
       (stageHtml(lay, o, 22).match(/class="ribbon"/g) || []).length === 2);
    /* No finish date means no month, and the flame must not invent one. */
    ok("cardStampMonth has nothing to print for them", READING.every(b => b.m === null));
    const litO = { lit: true, diag: false, stamped: true, marked: false };
    const lit = stageHtml(layoutPhase(books, litO, 22), litO, 22);
    ok("a stamped row leaves them unstamped",
       (lit.match(/class="stamp"/g) || []).length === items.filter(i => i.b.m).length,
       (lit.match(/class="stamp"/g) || []).length + " stamps for " +
       items.filter(i => i.b.m).length + " dated books");
    ok("and marks them instead of skipping them",
       (lit.match(/class="mark"/g) || []).length === 2);

    /* RESOLVED: the bookmark carries the distinction and the figure does not move.

       The hero keeps counting finished books, so a card with two open books prints 22
       over 24 covers. Pinned because it is the kind of "inconsistency" a later reader
       would helpfully fix -- and fixing it would make the one number on the card that
       has to mean exactly what it says mean something else. */
    const shelfLay = layoutShelf(books, { readAs: "overlap" });
    const shelfItems = shelfLay.rows.reduce((a, r) => a.concat(r.items), []);
    const figure = 20;
    const card = stageHtml(shelfLay, { lit: false, diag: false }, figure);
    ok("the figure counts finished books, not covers on the shelf",
       card.indexOf('class="fig">' + figure) !== -1 && shelfItems.length > figure,
       figure + " printed over " + shelfItems.length + " covers");
    ok("and every uncounted cover wears a bookmark",
       shelfItems.filter(i => i.b.reading).length ===
           shelfItems.length - figure,
       shelfItems.filter(i => i.b.reading).length + " bookmarked, " +
           (shelfItems.length - figure) + " uncounted");
})();

/* ---- the decided shelf: fixed sizes, and a count for the remainder ----

   The whole design is a refusal, so these assertions are mostly about things NOT
   happening: no size below the fixed one, no book silently dropped, no lean before a
   board is full. */
(function () {
    const modes = SHELF_MODES.map(m => m[0]);
    const counts = [1, 2, 3, 5, 6, 10, 11, 12, 22, 30, 40, 60, 90, 200, 500];

    /* Nothing invented. A leaning cover advances by exactly a spine's width, which is
       the claim tying the two cover layouts to the spine one. */
    ok("a leaning cover advances by a spine's width",
       SHELF_STEP_U === SHELF_SPINE_U, (SHELF_STEP_U * ROW_U).toFixed(1) + "pt");
    ok("a cover is the widest a two-board card carries",
       Math.abs(SHELF_FACE_U - CAP2_U * ASPECT) < 1e-12 && SHELF_FACE_U >= MIN_FACE_U,
       (SHELF_FACE_U * ROW_U).toFixed(1) + "pt");

    modes.forEach(function (m) {
        const fixed = m === "spine" ? SHELF_SPINE_U : SHELF_FACE_U;
        const worst = Math.min.apply(null, counts.map(function (n) {
            return shelfPlan(2, Math.max(0, n - 2), m).readW;
        }));
        /* THE refusal: at no count does any mode draw anything narrower than its own
           fixed size, which is exactly what boards and phase both did. */
        ok("[" + m + "] never draws anything narrower than its fixed size",
           worst >= fixed - 1e-9,
           (worst * ROW_U).toFixed(1) + "pt vs " + (fixed * ROW_U).toFixed(1) + "pt");
        ok("[" + m + "] accounts for every book",
           counts.every(function (n) {
               const p = shelfPlan(2, Math.max(0, n - 2), m);
               return p.drawn + p.rest === Math.max(2, n);
           }));
        const cap = SHELF_MAX[m][2];
        ok("[" + m + "] holds " + cap + " with two open, and says so past that",
           shelfPlan(2, cap - 2, m).rest === 0 && shelfPlan(2, cap - 1, m).rest > 0,
           "capacity " + cap);
        /* An open book costs a slot, never the size of the read books. Side by side it
           costs exactly one slot -- which is all a read cover would have cost -- so
           capacity is unchanged there; in the other two it displaces several leaning
           covers or spines. Either way the read books do not get smaller. */
        ok("[" + m + "] an open book costs capacity, not size",
           SHELF_MAX[m][0] >= SHELF_MAX[m][2] &&
           shelfPlan(2, 200, m).readW === shelfPlan(0, 200, m).readW,
           SHELF_MAX[m][0] + " -> " + SHELF_MAX[m][2]);
    });

    /* Overlapping is permission to lean, not an instruction to. */
    ok("the two cover layouts are identical below 11 books",
       [1, 2, 5, 6, 10].every(function (n) {
           const a = shelfPlan(2, n - 2, "single"), b = shelfPlan(2, n - 2, "overlap");
           return a.readW === b.readW && a.boards === b.boards && a.grown === b.grown;
       }));
    ok("and diverge from 11",
       shelfPlan(2, 9, "overlap").readKind === "lean" &&
       shelfPlan(2, 9, "single").readKind === "face");

    /* Refusing to squeeze is not refusing to fill. */
    ok("a two-book card is still two large covers",
       shelfPlan(0, 2, "overlap").grown === true &&
       shelfPlan(0, 2, "overlap").readW > SHELF_FACE_U,
       (shelfPlan(0, 2, "overlap").readW * ROW_U).toFixed(1) + "pt");

    ok("spine mode never leans", counts.every(function (n) {
       return shelfPlan(2, Math.max(0, n - 2), "spine").readKind !== "lean";
    }));

    /* Side by side must be the tightest and spines the roomiest, or the panel is
       offering a choice that does not mean anything. */
    ok("the three settings are ordered as the prose claims",
       SHELF_MAX.single[2] < SHELF_MAX.overlap[2] &&
       SHELF_MAX.overlap[2] < SHELF_MAX.spine[2],
       SHELF_MAX.single[2] + " < " + SHELF_MAX.overlap[2] + " < " + SHELF_MAX.spine[2]);
    ok("an open book is free only where it costs what a read cover costs",
       SHELF_MAX.single[0] === SHELF_MAX.single[2] &&
       SHELF_MAX.overlap[0] > SHELF_MAX.overlap[2] &&
       SHELF_MAX.spine[0] > SHELF_MAX.spine[2],
       "single " + SHELF_MAX.single[0] + "=" + SHELF_MAX.single[2] +
       ", overlap " + SHELF_MAX.overlap[0] + ">" + SHELF_MAX.overlap[2] +
       ", spine " + SHELF_MAX.spine[0] + ">" + SHELF_MAX.spine[2]);

    /* **The same pair card_shelf_plan_test.dart pins**, and they are typed on both
       sides on purpose: they are the design record, and a record only catches drift if
       two independent statements of it have to agree. These carry the seal's reserved
       corner -- 34 and 40 are what the shelf held before the top board was shortened. */
    ok("the shipped capacities are the Dart's",
       SHELF_MAX.overlap[0] === 31 && SHELF_MAX.spine[0] === 36,
       SHELF_MAX.overlap[0] + " overlapping, " + SHELF_MAX.spine[0] + " as spines");
    ok("holding the seal's corner costs three books and four",
       SHELF_MAX.overlap[0] === 34 - 3 && SHELF_MAX.spine[0] === 40 - 4);
    /* And nothing at all while one board is enough, which is the whole reason the shelf is
       solved twice: a one-board shelf sits below the seal. */
    ok("a one-board shelf leaves the reserve unspent",
       shelfPlan(0, 17, "overlap").boards === 1 &&
       shelfPlan(0, 17, "overlap").rest === 0 &&
       shelfPlan(0, 18, "overlap").boards === 2,
       "17 on one board, 18 on two");
})();

/* ---- the front group's cap, and the guarantee it is derived from ----

   kCardReadingMax, in card_shelf_plan.dart. Nothing here is typed except the 3 itself,
   which is the whole point of a pin: the cap is derived from what the top board has left
   once SHELF_RESERVE_U and one whole SHELF_FACE_U are set aside, so if the seal grows or
   the cover width moves then the cap moves, and this block is what notices.

   No backticks in this file's assertion block, deliberately: it is a String.raw template,
   and one backtick ends it and reports a SyntaxError on some unrelated line. */
(function () {
    const modes = SHELF_MODES.map(m => m[0]);
    /* Asked with a large read pile and the reserve paid, which is the only case the cap
       exists for: a shelf small enough to grow its covers never reaches it. */
    const capOf = n => shelfPass(n, 200, "overlap", SHELF_RESERVE_U).reading;
    ok("the front group is capped at three open books", capOf(9) === 3, "cap " + capOf(9));

    /* WHY three, and the defect it prevents. A front group sized against the whole board
       takes five covers and leaves the top board nothing to show -- a reader with 22
       finished books and six on the go saw none of the 22 up there, and none at all on a
       one-board card. Three is the largest front group that still leaves room for one whole
       finished cover; four leaves room for none. Both sides are asserted, because only the
       pair says the cap is *tight* rather than merely safe. */
    const finishedOnTop = r => fitCount(
        CARD_UNITS - r * (SHELF_FACE_U + GAP_U) - SHELF_RESERVE_U,
        SHELF_FACE_U, SHELF_FACE_U + GAP_U);
    ok("three open books still leave the top board a finished cover",
       finishedOnTop(3) >= 1, finishedOnTop(3) + " fit beside three open");
    ok("four leave none, which is what makes three the cap",
       finishedOnTop(4) === 0, finishedOnTop(4) + " fit beside four open");
    /* The front group charges a gap per open book, so the cap is a plain division and not
       fitCount, which charges n-1. It lands at 3.875, nowhere near an integer, so no
       tolerance is involved -- asserted rather than only claimed in a comment, so a later
       change to the seal or the cover width that puts it on a boundary is caught here
       instead of turning into a rounding argument. */
    const exact = (CARD_UNITS - SHELF_RESERVE_U - SHELF_FACE_U) / (SHELF_FACE_U + GAP_U);
    ok("the cap needs no floating-point tolerance",
       Math.abs(exact - Math.round(exact)) > 0.05, exact.toFixed(3));

    /* However many books the reader has open, the front group is the cap and never more --
       in every mode, at every pile size, and in the one-board pass that pays no reserve. */
    ok("the front group never exceeds the cap, however many are open",
       modes.every(m => [0, 1, 2, 3, 5, 8, 40].every(r =>
           [0, 3, 22, 200].every(nRead =>
               shelfPlan(r, nRead, m).reading === Math.min(r, 3)))));

    /* The defect itself, in the drawing rather than in the arithmetic: at the cap's own
       three open books, finished books still reach the **top** board. If this fails, a
       reader with three on the go finds their finished library banished to the bottom
       board, which is the bug the cap exists to prevent. */
    modes.forEach(function (m) {
        const p = shelfPlan(3, 22, m);
        ok("[" + m + "] with three open, finished books still reach the top board",
           p.top > p.reading,
           (p.top - p.reading) + " finished on top of " + p.drawn + " drawn");
    });

    /* Capacity must fall monotonically as books are opened. A dip that recovers means a
       reader who opens one more book watches the card collapse and then partly come back,
       which is not a thing a share preview can explain. */
    modes.forEach(function (m) {
        ok("[" + m + "] capacity only ever falls as books are opened",
           SHELF_MAX[m][0] >= SHELF_MAX[m][1] &&
           SHELF_MAX[m][1] >= SHELF_MAX[m][2] &&
           SHELF_MAX[m][2] >= SHELF_MAX[m][3],
           SHELF_MAX[m].join(" -> "));
    });

    /* The reading control offers three now, so the three-open drawing has to fit the board
       like every other one. The fit checks below hand over two open books and cannot see
       this: the front group is the widest thing on the shelf, so if anything overflows 106
       units it is this case. */
    const widestRow = lay => Math.max.apply(null, lay.rows.map(function (r, ri) {
        const plateHere = ri === lay.plateRow && lay.plate;
        return (r.stack
            ? Math.max.apply(null, r.items.map(i => i.xU + i.wU))
            : r.items.reduce((a, c) => a + c.wU, 0)
              + GAP_U * r.items.filter(i => i.gap).length)
            + (plateHere ? lay.plate.wU + GAP_U : 0);
    }));
    modes.forEach(function (m) {
        const worst = Math.max.apply(null, [3, 5, 12, 22, 40, 200].map(function (n) {
            return widestRow(layoutShelf(
                READING.slice(0, 3).concat(booksFor(n - 3)),
                { lit: false, diag: false, readAs: m }));
        }));
        ok("[" + m + "] the three-open shelf still fits the board",
           worst <= CARD_UNITS + 1e-9, worst.toFixed(2) + "u of " + CARD_UNITS);
    });

    /* Typed on this side too, the way the nought-open pair above is, so that
       card_shelf_plan_test.dart has something it can disagree with. This is the cap's own
       row: the least the shelf will ever hold, whatever the reader is in the middle of. */
    ok("the three-open capacities are the Dart's",
       SHELF_MAX.overlap[3] === 24 && SHELF_MAX.spine[3] === 29,
       SHELF_MAX.overlap[3] + " overlapping, " + SHELF_MAX.spine[3] + " as spines");
})();
(function () {
    SHELF_MODES.forEach(function (pair) {
        const m = pair[0];
        [2, 12, 22, 40, 90, 200].forEach(function (n) {
            const o = { lit: false, diag: false, readAs: m };
            const books = READING.slice(0, 2).concat(booksFor(Math.max(0, n - 2)));
            const lay = layoutShelf(books, o);
            let usedU = 0, hPt = 0;
            lay.rows.forEach(function (r, ri) {
                const plateHere = ri === lay.plateRow && lay.plate;
                const u = r.stack
                    ? Math.max.apply(null, r.items.map(i => i.xU + i.wU))
                      + (plateHere ? lay.plate.wU + GAP_U : 0)
                    : r.items.reduce((a, c) => a + c.wU, 0)
                      + GAP_U * r.items.filter(i => i.gap).length
                      + (plateHere ? lay.plate.wU + GAP_U : 0);
                usedU = Math.max(usedU, u);
                hPt += (Math.max.apply(null, r.items.map(i => i.hU))
                        + BOARD_U + BOARD_GAP_U) * ROW_U + (ri > 0 ? 6 : 0);
            });
            const items = lay.rows.reduce((a, r) => a.concat(r.items), []);
            ok("[" + m + " @" + n + "] fits both axes",
               usedU <= CARD_UNITS + 0.05 && hPt <= WELL_H - PAD + 0.5,
               usedU.toFixed(1) + "u, " + hPt.toFixed(1) + "pt");
            ok("[" + m + " @" + n + "] draws exactly what the plan promised",
               items.length === lay.shelf.drawn, items.length + " vs " + lay.shelf.drawn);
            ok("[" + m + " @" + n + "] never leans a spine and never crops",
               items.every(i => !(i.kind === "spine" && i.xU !== undefined)) &&
               items.filter(i => i.kind === "face").every(i =>
                   Math.abs(i.wU / i.hU - ASPECT) < 1e-9));
            /* The open books keep their whole cover in every setting -- that is the one
               thing the read-books control must not be able to take away. */
            ok("[" + m + " @" + n + "] the open books stay whole covers",
               items[0].kind === "face" && items[0].b.reading === true &&
               Math.abs(items[0].wU - lay.shelf.faceW) < 1e-9);
        });
    });
})();

/* ---- the shelf draws what the plan says, in both axes ---- */
(function () {
    const html = displayMenu();
    ok("the panel offers both representations",
       html.indexOf('data-disp="readAs:@cover"') !== -1 &&
       html.indexOf('data-disp="readAs:spine"') !== -1);
    ok("and both cover layouts",
       html.indexOf('data-disp="readAs:overlap"') !== -1 &&
       html.indexOf('data-disp="readAs:single"') !== -1);
    /* Covers must read as selected under either layout, which the first attempt got
       wrong: it compared against one layout and left the group looking unset. */
    const was = S.readAs;
    S.readAs = "overlap";
    ok("Covers is selected under either layout",
       /readAs:@cover" class="on"/.test(displayMenu()));
    S.readAs = "single";
    ok("and still is under the other",
       /readAs:@cover" class="on"/.test(displayMenu()));
    /* A control that vanishes teaches nothing, so Layout is disabled under Spines
       rather than hidden. */
    S.readAs = "spine";
    const spineHtml = displayMenu();
    S.readAs = was;
    ok("Layout is disabled under Spines, not hidden",
       spineHtml.indexOf("Side by side") !== -1 &&
       spineHtml.indexOf("disabled") !== -1 &&
       spineHtml.indexOf('data-disp="readAs:overlap"') === -1);
    ok("Spines is selected there", /readAs:spine" class="on"/.test(spineHtml));
    ok("the panel states the capacity of the current setting",
       html.indexOf(String(SHELF_MAX[was][2])) !== -1,
       "expects " + SHELF_MAX[was][2]);
})();

/* ---- the corpus is what the page claims ---- */
ok("22 books, the count in the report", CORPUS.length === 22);
ok("two books have no thumbnail", CORPUS.filter(b => !b.thumb).length === 2);
ok("mixed script", CORPUS.some(b => /[가-힣]/.test(b.title)) && CORPUS.some(b => /^[ -~]+$/.test(b.title)));
ok("all three jacket layouts are used", new Set(CORPUS.map(b => b.st)).size === 3);
`;

try {
  eval(js + "\n" + assertions);
} catch (e) {
  console.log("FAIL threw: " + e.message);
  console.log(e.stack.split("\n").slice(0, 6).join("\n"));
  fail++;
}

console.log(fail === 0 ? "\nall ok" : `\n${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
