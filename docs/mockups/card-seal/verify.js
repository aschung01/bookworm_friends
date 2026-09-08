// Checks docs/mockups/card-seal/index.html against the shipped arithmetic.
//
//   node docs/mockups/card-seal/verify.js
//
// The page's whole argument is a measurement -- how much of the embossed seal the shelf
// now stands in front of -- so the measurement is what gets checked. A drawing that said
// "mostly covered" over a card that is 4% covered would be a drawing that decided the
// question by being wrong.
//
// The ported constants are checked by recomputation rather than against a typed copy:
// every number is derived from the same inputs `card_shelf_plan.dart` derives from.

"use strict";

const fs = require("fs");
const path = require("path");

const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

let failures = 0;
let checks = 0;

function ok(label, condition, detail) {
  checks += 1;
  console.log(
    (condition ? "ok   " : "FAIL ") + label + (detail ? "  " + detail : ""),
  );
  if (!condition) failures += 1;
}

function near(a, b, tol) {
  return Math.abs(a - b) <= (tol === undefined ? 1e-6 : tol);
}

// ---- the page loads and exposes its model ----

const scripts = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
ok(
  "the page has exactly one script block",
  scripts.length === 1,
  String(scripts.length),
);

const body = scripts[0].replace(/^<script>/, "").replace(/<\/script>$/, "");

// A DOM stub: the engine touches `document` on its last few lines and nothing under test
// depends on it. Everything asserted here is pure arithmetic above that point.
const stubNode = {
  addEventListener: () => {},
  classList: { toggle: () => {}, add: () => {}, remove: () => {} },
  querySelectorAll: () => [],
  getAttribute: () => null,
  innerHTML: "",
  checked: false,
};
const stub = { getElementById: () => stubNode, querySelectorAll: () => [] };

let m;
try {
  m = new Function(
    "document",
    body +
      "\n;return {U, CARD_U, SHELF_U, WELL_U, WELL_PAD, BOARD_U, BOARD_GAP_U, " +
      "SHELF_GAP_U, GAP_U, SLACK_U, PLATE_U, BOARD_SHADOW_U, FLOOR_U, " +
      "CAP1_U, CAP2_U, FACE_U, SPINE_U, LEAN_U, " +
      "SEAL_U, ASPECT, MIN_FACE_U, shelfPlan, boardExtent, wellTopOfShelf, sealDisc, " +
      "sealVisible, capacityOf, PLACEMENTS, SHIPPED, OPTS, MODES, CORPUS_MAX};",
  )(stub);
} catch (error) {
  console.log("FAIL the page evaluates  " + error.message);
  process.exit(1);
}
ok("the page evaluates", true);

// ---- what the card actually offers ----

// The card draws one thing: overlapping covers. `single` and `spine` are kept because they
// bracket the reserved corner's cost, and both must stay labelled `(withdrawn)` — an
// unlabelled third mode would have this page claiming a display setting that no longer
// exists in the app, which is the defect `card-cover-crop` was written to close.
const offered = m.MODES.filter(([, label]) => !/\(withdrawn\)/.test(label));
ok(
  "exactly one mode is offered, not a choice of modes",
  offered.length === 1,
  offered.map(([id]) => id).join(", "),
);
ok(
  "and the one offered is overlapping covers",
  offered.length === 1 && offered[0][0] === "overlap",
  offered.length === 1 ? offered[0][0] : "",
);
ok(
  "spines are drawn, but marked withdrawn",
  m.MODES.some(([id, label]) => id === "spine" && /\(withdrawn\)/.test(label)),
);

// ---- the tokens are the Dart's, recomputed ----

ok(
  "a board is 98 units, not the card's 106",
  m.SHELF_U === 98,
  String(m.SHELF_U),
);
ok(
  "the well is 60.95 units on a 4:5 card",
  near(m.WELL_U, ((106 * 450) / 360) * 0.46, 1e-9),
  m.WELL_U.toFixed(4),
);
ok(
  "a two-board cover is 23.22 units tall",
  near(
    m.CAP2_U,
    (m.WELL_U - m.WELL_PAD - 2 * (m.BOARD_U + m.BOARD_GAP_U) - m.SHELF_GAP_U) /
      2 -
      m.SLACK_U,
  ),
  m.CAP2_U.toFixed(4),
);
ok(
  "a cover is 15.48 wide, its height times the app's own aspect",
  near(m.FACE_U, m.CAP2_U * m.ASPECT),
  m.FACE_U.toFixed(4),
);
ok(
  "a spine is BookVertical's 26/124 at that height",
  near(m.SPINE_U, (26 / 124) * m.CAP2_U),
  m.SPINE_U.toFixed(4),
);
ok("a leaning cover advances by exactly a spine width", m.LEAN_U === m.SPINE_U);
ok("the seal is 15 units across", m.SEAL_U === 15);
ok(
  "the cover floor is generated_cover.dart's own",
  near(m.MIN_FACE_U, 7 / 0.135 / (360 / 106), 1e-9),
  m.MIN_FACE_U.toFixed(4),
);

// ---- where the shelf sits in the well ----

// The well's slack goes *above* the books, so a two-board shelf starts 6.2 units down and
// a one-board shelf starts far lower. That difference is the entire reason the seal is
// clear for a small library and covered for a large one. It was 7.0 until the bottom board
// was given FLOOR_U of air to cast its shadow into; the 0.8 came out of the slack above,
// so no capacity moved, but the seal's safe top band shrank by the same 0.8.
const twoBoardTop = m.wellTopOfShelf(m.shelfPlan(0, 22, "overlap"));
ok(
  "a two-board shelf starts 6.2 units below the well's top",
  near(twoBoardTop, 7 - m.FLOOR_U, 1e-9),
  twoBoardTop.toFixed(4),
);
const oneBoardTop = m.wellTopOfShelf(m.shelfPlan(0, 2, "overlap"));
ok(
  "a two-book shelf starts below the seal entirely",
  oneBoardTop > m.WELL_PAD + m.SEAL_U,
  oneBoardTop.toFixed(4),
);

// The gap under the bottom board is exactly the shadow's reach, and it is paid for out of
// the slack rather than out of the covers. A shorter gap ships one shadowed board above
// one unshadowed one; a longer one would have to come out of CAP2_U.
ok(
  "the floor gap is the board shadow's reach",
  near(m.FLOOR_U, 2 * m.BOARD_SHADOW_U, 1e-12),
  m.FLOOR_U.toFixed(4) + "u",
);
ok(
  "the floor gap fits the slack that was already unspent",
  m.FLOOR_U <= 2 * m.SLACK_U,
  m.FLOOR_U.toFixed(4) + " of " + (2 * m.SLACK_U).toFixed(4),
);

// The lowest board has to rest FLOOR_U clear of the well's floor, or the drawing has
// drifted from `_Well`'s bottom inset.
[2, 22, 90].forEach((n) => {
  const plan = m.shelfPlan(0, n, "overlap");
  const bottom =
    m.wellTopOfShelf(plan) +
    plan.boards.length * (plan.faceH + m.BOARD_GAP_U + m.BOARD_U) +
    (plan.boards.length - 1) * m.SHELF_GAP_U;
  ok(
    "at " + n + " books the lowest board stands clear of the floor",
    near(bottom, m.WELL_U - m.FLOOR_U, 1e-3),
    bottom.toFixed(4),
  );
});

// ---- capacities, which are what reserving the corner costs ----

const bare = { single: 10, overlap: 34, spine: 40 };
Object.keys(bare).forEach((mode) => {
  ok(
    "unreserved, " + mode + " holds " + bare[mode],
    m.capacityOf(m.PLACEMENTS.now, mode) === bare[mode],
    String(m.capacityOf(m.PLACEMENTS.now, mode)),
  );
});

const reserved = { single: 9, overlap: 31, spine: 36 };
Object.keys(reserved).forEach((mode) => {
  ok(
    "with the corner reserved, " + mode + " holds " + reserved[mode],
    m.capacityOf(m.PLACEMENTS.reserve, mode) === reserved[mode],
    String(m.capacityOf(m.PLACEMENTS.reserve, mode)),
  );
});

// Balancing redistributes and never removes, so it must cost nothing at all. This is the
// claim that makes it the cheapest option on the page.
Object.keys(bare).forEach((mode) => {
  ok(
    "balancing costs no capacity in " + mode,
    m.capacityOf(m.PLACEMENTS.balance, mode) === bare[mode],
    String(m.capacityOf(m.PLACEMENTS.balance, mode)),
  );
});

// Reserving must cost the *top* board only: a reservation that shortened both would be
// paying twice for one corner.
const reservedPlan = m.shelfPlan(m.SEAL_U + m.GAP_U, 90, "overlap");
ok(
  "the reservation shortens the top board and not the bottom one",
  reservedPlan.boards[0] < reservedPlan.boards[1],
  reservedPlan.boards.join(" + "),
);

// And it must cost nothing while the shelf needs one board, because nothing was covering
// the seal then.
ok(
  "reserving is free for a small library",
  m.shelfPlan(m.SEAL_U + m.GAP_U, 5, "overlap").boards.length === 1 &&
    m.shelfPlan(m.SEAL_U + m.GAP_U, 5, "overlap").boards[0] === 5,
  m.shelfPlan(m.SEAL_U + m.GAP_U, 5, "overlap").boards.join(" + "),
);

// ---- the measurement the page exists for ----

const visible = (placement, n, mode) =>
  m.sealVisible(
    m.PLACEMENTS[placement],
    m.shelfPlan(
      m.PLACEMENTS[placement].reserve,
      n,
      mode,
      m.PLACEMENTS[placement].balance,
    ),
  );

ok("at two books the seal is whole", near(visible("now", 2, "overlap"), 1), "");
ok(
  "side by side never reaches the corner, at any count",
  visible("now", 90, "single") > 0.95,
  visible("now", 90, "single").toFixed(4),
);
ok(
  "at 22 books overlapping, under half survives",
  visible("now", 22, "overlap") > 0.25 && visible("now", 22, "overlap") < 0.5,
  visible("now", 22, "overlap").toFixed(4),
);
ok(
  "a full board of spines leaves under a quarter",
  visible("now", 90, "spine") > 0.05 && visible("now", 90, "spine") < 0.25,
  visible("now", 90, "spine").toFixed(4),
);

// The fact that decides whether this is worth fixing: the seal survives intact until the
// top board *fills*, so it is the heaviest readers who lose the reveal. Measured against
// the page's own `CLEAR` — a tenth of the disc, which is a bite deeper than the seal's ring
// is wide — rather than against "any overlap at all", because the top board's right edge
// grazes the disc for several books before it damages it.
const CLEAR = 0.9;
function firstCovered(mode) {
  for (let n = 1; n <= 120; n += 1) {
    if (visible("now", n, mode) < CLEAR) return n;
  }
  return 0;
}
ok(
  "overlapping: the ring is intact until the 18th book",
  firstCovered("overlap") === 18,
  "first at " + firstCovered("overlap"),
);
ok(
  "spines: until the 21st",
  firstCovered("spine") === 21,
  "first at " + firstCovered("spine"),
);
ok(
  "side by side: never",
  firstCovered("single") === 0,
  "first at " + firstCovered("single"),
);

// The grazing itself, which the page has to describe rather than round away. It happens in
// exactly two places: a *grown* two-board shelf, whose five covers a board reach 0.8 units
// into the disc, and side by side at any count, which is the same five covers fixed.
[
  [9, "overlap"],
  [10, "overlap"],
  [11, "single"],
  [22, "single"],
  [90, "single"],
].forEach(([n, mode]) => {
  const v = visible("now", n, mode);
  ok(
    "at " + n + " " + mode + " the disc is grazed but its ring is whole",
    v > CLEAR && v < 1,
    v.toFixed(4),
  );
});

// And the counts where it is genuinely untouched, which is most of them.
[
  [2, "overlap"],
  [6, "overlap"],
  [8, "overlap"],
  [12, "overlap"],
  [17, "overlap"],
  [20, "spine"],
].forEach(([n, mode]) => {
  ok(
    "at " + n + " " + mode + " the seal is untouched",
    near(visible("now", n, mode), 1),
    visible("now", n, mode).toFixed(4),
  );
});

// The count each becomes a second board at is the count the seal goes at, which is the
// page's explanation for the cliff in the table.
[
  ["overlap", 18],
  ["spine", 21],
].forEach(([mode, n]) => {
  ok(
    mode + " opens its second board at " + n,
    m.shelfPlan(0, n - 1, mode).boards.length === 1 &&
      m.shelfPlan(0, n, mode).boards.length === 2,
    m.shelfPlan(0, n - 1, mode).boards.length +
      " then " +
      m.shelfPlan(0, n, mode).boards.length,
  );
});

// Reserving is not a partial fix: it has to be total, or it has bought nothing.
Object.keys(bare).forEach((mode) => {
  const v = visible("reserve", 90, mode);
  ok("reserved, " + mode + " leaves the seal whole", near(v, 1), v.toFixed(4));
});

// Balancing fixes the common range for free -- and stops at exactly the point the option
// admits to, which is a full shelf.
ok(
  "balanced, 22 books leave the seal whole",
  near(visible("balance", 22, "overlap"), 1),
  visible("balance", 22, "overlap").toFixed(4),
);
ok(
  "balanced, a full shelf covers it just as much",
  near(visible("balance", 34, "overlap"), visible("now", 34, "overlap"), 0.02),
  visible("balance", 34, "overlap").toFixed(4) +
    " vs " +
    visible("now", 34, "overlap").toFixed(4),
);

// On the body no shelf can reach it, whatever the reader has read.
ok(
  "on the body, nothing can reach it",
  near(visible("body", 90, "spine"), 1),
  "",
);

// The watermark's own measurement is the argument against it, and the page has to quote
// the case where that is true rather than the case where it is not.
ok(
  "on a full shelf the watermark shows less of itself than the corner seal does",
  visible("watermark", 34, "overlap") < visible("now", 34, "overlap"),
  visible("watermark", 34, "overlap").toFixed(4) +
    " vs " +
    visible("now", 34, "overlap").toFixed(4),
);

// ---- every option is drawn, costed and reachable ----

const wanted = ["now", "balance", "reserve", "body", "watermark", "adaptive"];
ok(
  "all six options are declared",
  wanted.every((k) => m.OPTS.some((o) => o.id === k)) &&
    m.OPTS.length === wanted.length,
  m.OPTS.map((o) => o.id).join(", "),
);
m.OPTS.forEach((o) => {
  ok(o.id + " states what it costs", /Cost:/.test(o.body));
  ok(
    o.id + " has a placement to draw",
    !!m.PLACEMENTS[o.placement],
    o.placement,
  );
});
ok(
  "exactly one option is marked as shipped",
  m.OPTS.filter((o) => o.now).length === 1,
);

// And it is the one that holds the corner. The page's lead quotes SHIPPED rather than
// naming a placement, so this is what stops the prose and the tag drifting apart.
ok(
  "the shipped placement is the reserved corner",
  m.SHIPPED === m.PLACEMENTS.reserve,
  m.OPTS.filter((o) => o.now)[0].id,
);
ok(
  "and it reserves the seal plus one gap, which is the Dart's kCardSealReserveUnits",
  near(m.SHIPPED.reserve, m.SEAL_U + m.GAP_U, 1e-12),
  m.SHIPPED.reserve.toFixed(2) + "u",
);
// The claim the whole page turns on, at every count in every mode: nothing the shelf
// draws touches the disc.
ok(
  "the shipped placement leaves the seal whole at every count",
  [1, 2, 5, 10, 17, 18, 22, 31, 36, 60, 90].every((n) =>
    ["single", "overlap", "spine"].every(
      (mode) =>
        m.sealVisible(m.SHIPPED, m.shelfPlan(m.SHIPPED.reserve, n, mode)) >= 1,
    ),
  ),
);

// The candle is the reason any of this matters: the seal is a blind emboss at 10% in
// daylight, so what the shelf covers is not the seal, it is the reveal.
ok(
  "the page says the seal is what the candle reveals",
  /blind emboss/i.test(html) && /reveal/i.test(html),
);
ok(
  "the page defines what counts as covered, and why",
  /const CLEAR = 0\.9/.test(html) && /ring/i.test(html),
);
ok("the page cites the palette that makes it faint", /sealOpacity/.test(html));
ok(
  "the corpus reaches the counts the table quotes",
  m.CORPUS_MAX >= 90,
  String(m.CORPUS_MAX),
);

// ---- house rules for these pages ----

ok("no network", !/https?:\/\/(?!www\.w3\.org)/.test(html));
ok("no raster images", !/<img\b/.test(html));
ok(
  "registered in the mockup index",
  fs
    .readFileSync(path.join(__dirname, "..", "index.html"), "utf8")
    .includes("card-seal/index.html"),
);

console.log("");
console.log(failures === 0 ? "all ok" : failures + " of " + checks + " failed");
process.exit(failures === 0 ? 0 : 1);
