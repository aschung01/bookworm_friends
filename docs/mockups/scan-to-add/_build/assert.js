/* Assertions appended to the stubbed load. These cover the claims the page
   makes that would otherwise only be checkable by eye AND would silently be
   wrong: that the shutter is present on every live scanner state (the whole
   argument rests on it), that the two-buttons fork really does converge,
   that version inheritance and diff direction behave, and that the searches
   a reviewer will type resolve. */
let fails = 0;
function ok(label, cond, extra) {
  if (!cond) {
    fails++;
    console.log("FAIL  " + label + (extra ? "  " + extra : ""));
  } else {
    console.log("ok    " + label);
  }
}
const count = (hay, needle) => hay.split(needle).length - 1;
const spec = (vid, id) => {
  for (const [, items] of resolveView(vid, "screens"))
    for (const it of items) if (it[0] === id) return it[3];
  return null;
};
const ids = (vid) =>
  resolveView(vid, "screens").flatMap(([, items]) => items.map((i) => i[0]));
const ALLV = ["main", "two-buttons", "scanner-sheet"];

/* --- shape ---------------------------------------------------------- */
ok("20 screens in 4 groups", ids("main").length === 20 && SCREENS.length === 4);
ok(
  "every version resolves all 20 screens",
  ALLV.every((v) => ids(v).length === 20),
  JSON.stringify(ALLV.map((v) => ids(v).length)),
);
ok(
  "3 core + 3 recovery flows",
  FLOWS[0][1].length === 3 && FLOWS[1][1].length === 3,
);

/* --- the load-bearing claim: the shutter is never hidden ------------- */
const LIVE = [
  "scan-first",
  "scan-idle",
  "scan-lock",
  "scan-nudge",
  "scan-multi",
];
for (const id of LIVE) {
  ok(
    id + " shows the cover control",
    frame(spec("main", id)).includes('class="coverbtn idle"'),
  );
}
ok(
  "scan-first shows the cover control AND the teaching hint, together",
  frame(spec("main", "scan-first")).includes('class="coverbtn idle"') &&
    frame(spec("main", "scan-first")).includes("read the cover"),
);
ok(
  "the nudge escalates a control that is already drawn",
  count(frame(spec("main", "scan-nudge")), 'class="coverbtn') === 1 &&
    frame(spec("main", "scan-nudge")).includes("nudge"),
);
// The correction implementation forced: a shutter glyph promises an instant
// in-place capture, and `mobile_scanner` cannot give one. Nothing may draw one.
ok(
  "no frame draws a shutter anywhere",
  ALLV.every((v) =>
    ids(v).every(
      (id) =>
        !frame(spec(v, id)).includes('class="shut ') &&
        // Quote closed deliberately: `class="slab` also matches `class="slabel"`,
        // the shelf-row label, which is the same substring trap as counting
        // `class="ean` and catching `eanwrap`.
        !frame(spec(v, id)).includes('class="slab"'),
    ),
  ),
);
ok(
  "the cover control is always labelled, never a bare glyph",
  LIVE.every((id) => frame(spec("main", id)).includes("Read the cover")),
);
ok(
  "busy replaces the reticle rather than keeping it",
  frame(spec("main", "scan-busy")).includes('class="coverbtn busy"') &&
    !frame(spec("main", "scan-busy")).includes('class="retic'),
);

/* --- scan-multi: two symbols, not three, and the window stays green --- */
ok(
  "scan-multi draws exactly the two symbols a Korean back cover has",
  count(frame(spec("main", "scan-multi")), 'class="bars"') === 2,
  "symbols=" + count(frame(spec("main", "scan-multi")), 'class="bars"'),
);
ok(
  "scan-multi marks a winner on the symbol itself",
  frame(spec("main", "scan-multi")).includes("eanwrap cand") &&
    frame(spec("main", "scan-multi")).includes('class="ean won"'),
);
ok(
  "a resolved read never colours the whole window as a failure",
  frame(spec("main", "scan-multi")).includes('class="retic lock"'),
);
ok(
  "no amber reticle state survives anywhere",
  ALLV.every((v) =>
    ids(v).every((id) => !frame(spec(v, id)).includes("retic multi")),
  ),
);
ok(
  "scan-lock and scan-multi differ only in the candidate marks and readout",
  frame(spec("main", "scan-lock")) !== frame(spec("main", "scan-multi")) &&
    frame(spec("main", "scan-lock")).includes('class="retic lock"'),
);

/* --- the lookup wait: proof stays, spinner carries the time ----------
   The state the mockup was missing. Asserting the digits *survive* is the
   point: replacing them with "Looking it up…" was the tempting version and
   it throws away the user's only evidence at the moment they'd check it. */
ok(
  "scan-lookup keeps the decoded ISBN on screen while it waits",
  frame(spec("main", "scan-lookup")).includes("978 89 546 9991 4") &&
    frame(spec("main", "scan-lookup")).includes('class="isbn busy"'),
);
ok(
  "scan-lookup keeps the window locked, because nothing has gone wrong",
  frame(spec("main", "scan-lookup")).includes('class="retic lock"') &&
    !frame(spec("main", "scan-lookup")).includes('class="card'),
);
ok(
  "only the lookup state marks the readout busy",
  ids("main").filter((id) => frame(spec("main", id)).includes("isbn busy"))
    .length === 1,
);

/* --- the two lookup failures are told apart ---------------------------
   Both arrive as `null` in code. Drawing one card for both is how you end
   up telling an offline user their book does not exist. */
ok(
  "a missing catalogue entry and an unreachable catalogue are different cards",
  frame(spec("main", "scan-noisbn")) !==
    frame(spec("main", "scan-lookupfail")) &&
    frame(spec("main", "scan-lookupfail")).includes("Try again"),
);
ok(
  "the unreachable-catalogue card never blames the book",
  !frame(spec("main", "scan-lookupfail")).includes("No catalogue has this"),
);

/* --- a discarded option must never be drawn as a live one -------------
   "Add it by hand" was cut from v1. `info-manual` still draws what it
   would have needed, deliberately, but no *offered action* may promise it. */
ok(
  "no failure card offers the by-hand action that was cut",
  ALLV.every((v) =>
    ids(v)
      .filter((id) => id !== "info-manual")
      .every((id) => !frame(spec(v, id)).includes("Add it by hand")),
  ),
);
ok(
  "every failure card still offers two ways onward, and no OK",
  [
    "scan-denied",
    "scan-nocover",
    "scan-noisbn",
    "scan-lookupfail",
    "scan-coverlimit",
  ].every(
    (id) =>
      count(frame(spec("main", id)), 'class="ca2') === 2 &&
      !frame(spec("main", id)).includes(">OK<"),
  ),
);

/* --- terminal asymmetry: exact goes to the save sheet, fuzzy does not - */
ok(
  "barcode lands on the save sheet",
  frame(spec("main", "info-barcode")).includes("isheet"),
);
ok(
  "the cover path lands on the results grid, not the save sheet",
  frame(spec("main", "sheet-prefilled")).includes("rbooks") &&
    !frame(spec("main", "sheet-prefilled")).includes("isheet"),
);
ok(
  "a query the app wrote is marked as such",
  frame(spec("main", "sheet-prefilled")).includes("from cover") &&
    !frame(spec("main", "sheet-results")).includes("prov"),
);

/* --- the two backdrops the flows were getting wrong ------------------
   Both save-sheet screens draw the same sheet; only what is behind it
   differs, and that is what says how the user got there. A flow step
   reusing the wrong one is invisible in the data and obvious on screen,
   which is exactly the class of error these two assertions exist for. */
ok(
  "info-barcode sits over the viewfinder it was scanned from",
  frame(spec("main", "info-barcode")).includes('class="cam"') &&
    frame(spec("main", "info-barcode")).includes('class="retic lock"'),
);
ok(
  "info-cover sits over the results grid, with no viewfinder anywhere",
  frame(spec("main", "info-cover")).includes("rbooks") &&
    frame(spec("main", "info-cover")).includes("from cover") &&
    !frame(spec("main", "info-cover")).includes('class="cam"') &&
    !frame(spec("main", "info-cover")).includes("retic"),
);
ok(
  "the two save sheets share their sheet and differ only behind it",
  frame(spec("main", "info-cover")).includes(infoSheet(BOOK)) &&
    frame(spec("main", "info-barcode")).includes(infoSheet(BOOK)),
);
ok(
  "a save sheet over the Add Book sheet still drops the tab bar",
  !frame(spec("main", "info-cover")).includes('class="tb"') &&
    frame(spec("main", "sheet-prefilled")).includes('class="tb"'),
);

/* --- the keyboard finding, asserted rather than asserted-about -------
   The Scan a book action is the discoverable half of the single-button
   recommendation. If it can be drawn behind the keyboard, that is a fact
   about the design, not about the drawing. */
ok(
  "sheet-focused draws the keyboard and the empty-state action together",
  frame(spec("main", "sheet-focused")).includes('class="keyb"') &&
    frame(spec("main", "sheet-focused")).includes("Scan a book"),
);
ok(
  "the empty state is drawn with no keyboard compensation, as in code",
  frame(spec("main", "sheet-focused")).includes(
    emptyState({ hint: HINT, act: "Scan a book" }),
  ),
);
ok(
  "a focused field shows a caret, an unfocused one does not",
  frame(spec("main", "sheet-focused")).includes('class="caret"') &&
    !frame(spec("main", "sheet-empty")).includes('class="caret"'),
);

/* --- the clear button ------------------------------------------------
   Two facts, both about the design rather than the drawing: it exists
   only when there is something to clear, and it is the last thing in the
   pill even when the provenance chip is there too. */
ok(
  "a field with a query draws a clear button, an empty one does not",
  frame(spec("main", "sheet-prefilled")).includes('class="clr"') &&
    !frame(spec("main", "sheet-empty")).includes('class="clr"'),
);
ok(
  "the clear button comes after the provenance chip, not before it",
  (() => {
    const pill = srow({ value: "\ud55c\uac15", prov: "from cover" }, [
      "viewfinder",
    ]);
    return pill.indexOf('class="prov"') < pill.indexOf('class="clr"');
  })(),
);
ok(
  "the tab bar yields to the keyboard",
  !frame(spec("main", "sheet-focused")).includes('class="tb"') &&
    frame(spec("main", "sheet-empty")).includes('class="tb"'),
);

ok(
  "user-facing copy uses CFBundleDisplayName, not the repo name",
  frame(spec("main", "scan-denied")).includes("Libstack") &&
    !ids("main").some((id) =>
      frame(spec("main", id)).includes("Bookworm Friends"),
    ),
);

/* --- the screen that does not exist is marked as such ---------------- */
ok(
  "info-manual is marked, loudly",
  frame(spec("main", "info-manual")).includes('class="notreal"') &&
    frame(spec("main", "info-manual")).includes("does not exist"),
);
ok(
  "info-manual claims no metadata the scan could not have given it",
  !frame(spec("main", "info-manual")).includes(BOOK.title) &&
    !frame(spec("main", "info-manual")).includes(BOOK.publisher) &&
    frame(spec("main", "info-manual")).includes("ISBN 9788954699914"),
);
ok(
  "info-manual uses a generated cover with an empty title half",
  frame(spec("main", "info-manual")).includes("icover gcover") &&
    frame(spec("main", "info-manual")).includes('class="ttl"></div>'),
);
ok(
  "info-manual cannot be saved",
  frame(spec("main", "info-manual")).includes('class="isave off"') &&
    frame(spec("main", "info-barcode")).includes('class="isave"'),
);
ok(
  "only the imaginary screen carries the marking",
  ids("main").filter((id) => frame(spec("main", id)).includes("notreal"))
    .length === 1,
);

/* --- landing back in the shell -------------------------------------- */
ok(
  "library-landed has no Add Book sheet at all",
  !frame(spec("main", "library-landed")).includes('class="sheet"') &&
    !frame(spec("main", "library-landed")).includes("Add book"),
);
ok(
  "library-landed unlights the orb and selects Library",
  !frame(spec("main", "library-landed")).includes("orb lit") &&
    frame(spec("main", "library-landed")).includes('<s class="on">'),
);
ok(
  "the sheet screens do the opposite: orb lit, Library not selected",
  frame(spec("main", "sheet-empty")).includes("orb lit") &&
    !frame(spec("main", "sheet-empty")).includes('<s class="on">'),
);
ok(
  "library-landed rests on the collapsed read pile",
  frame(spec("main", "library-landed")).includes('class="lsheet"') &&
    frame(spec("main", "library-landed")).includes("Books read"),
);
ok(
  "one shelf fixture, shared by the background and the subject",
  ALLV.every((v) =>
    ids(v).every((id) => !frame(spec(v, id)).includes("lbooks")),
  ) && frame(spec("main", "sheet-empty")).includes('class="srow3"'),
);
ok(
  "the shelves never paint over the 118pt app-bar band",
  ALLV.every((v) =>
    ids(v).every((id) => {
      const h = frame(spec(v, id));
      return !h.includes('class="lib"') || h.includes('class="chrome"');
    }),
  ),
);
ok(
  "the landed shelf gained a book over the plain library",
  count(frame(spec("main", "library-landed")), "<u style") ===
    count(frame(spec("main", "sheet-empty")), "<u style") + 1,
);
ok(
  "the added book is on a row short enough to show it",
  SHELVES[SHELVES.length - 1][1].length === 2,
  "last row has " + SHELVES[SHELVES.length - 1][1].length,
);

/* --- no dead ends: every failure card offers two ways onward --------- */
for (const id of ["scan-denied", "scan-nocover", "scan-noisbn"]) {
  const h = frame(spec("main", id));
  ok(
    id + " offers two actions, neither an OK",
    count(h, 'class="ca2 ') === 2 && !/>\s*OK\s*</.test(h),
    "acts=" + count(h, 'class="ca2 '),
  );
}

/* --- the tab bar appears exactly where the shell puts it ------------- */
ok(
  "the bar floats over Add Book (autoHideOnModal: false)",
  frame(spec("main", "sheet-empty")).includes('class="tb"'),
);
ok(
  "no bar on a pushed scanner route",
  !frame(spec("main", "scan-idle")).includes('class="tb"'),
);
ok(
  "no bar under a second modal",
  !frame(spec("main", "info-barcode")).includes('class="tb"'),
);

/* --- two-buttons: the fork converges, which is the argument ---------- */
ok(
  "two-buttons draws a barcode AND a camera glyph in the row",
  frame(spec("two-buttons", "sheet-empty")).includes(PATHS.barcode) &&
    frame(spec("two-buttons", "sheet-empty")).includes(PATHS.camera),
);
ok(
  "main draws exactly one button in the search row",
  frame(spec("main", "sheet-empty")).includes(
    srow({ placeholder: PLACEHOLDER }, ["viewfinder"]),
  ) &&
    !frame(spec("main", "sheet-empty")).includes(PATHS.barcode) &&
    !frame(spec("main", "sheet-empty")).includes(PATHS.camera),
);
ok(
  "the camera door opens the SAME screen as the barcode door",
  frame(spec("two-buttons", "scan-first")) ===
    frame(spec("main", "scan-first")),
);
ok(
  "the pill measurement actually differs between the two",
  frame(spec("main", "sheet-empty")).includes("pill 300pt") &&
    frame(spec("two-buttons", "sheet-empty")).includes("pill 248pt"),
);
ok(
  "the fall-through survives into two-buttons unchanged",
  JSON.stringify(
    resolveView("two-buttons", "flows").flatMap(([, l]) =>
      l.filter((i) => i[0] === "fall-through").map((i) => i[3]),
    ),
  ) ===
    JSON.stringify(
      resolveView("main", "flows").flatMap(([, l]) =>
        l.filter((i) => i[0] === "fall-through").map((i) => i[3]),
      ),
    ),
);

/* --- scanner-sheet: the framing room really does collapse ----------- */
ok(
  "LAY holds two layouts, not one",
  LAY.page.retic === 250 && LAY.sheet.retic === 150,
);
ok(
  "the sheet variant is 717pt of preview, not 874",
  frame(spec("scanner-sheet", "scan-first")).includes("height:717px") &&
    frame(spec("main", "scan-first")).includes("height:874px"),
);
ok(
  "the sheet variant gives the preview itself a height, not just its host",
  count(frame(spec("scanner-sheet", "scan-first")), "height:717px") === 2,
  "got " + count(frame(spec("scanner-sheet", "scan-first")), "height:717px"),
);
ok(
  "every text over the preview carries its own backdrop",
  frame(spec("main", "scan-lock")).includes(
    'class="isbn" style="top:470px"><span>',
  ) &&
    frame(spec("main", "scan-first")).includes(
      'class="shint" style="top:470px"><span>',
    ) &&
    // The cover control carries its own dark pill rather than relying on a
    // separate label element, so the backdrop is on the button itself now.
    frame(spec("main", "scan-idle")).includes(
      'class="coverbtn idle" style="top:768px"',
    ),
);
ok(
  "the sheet variant keeps the library behind it",
  frame(spec("scanner-sheet", "scan-first")).includes('class="lib"'),
);
ok(
  "scan-busy is inherited untouched by scanner-sheet",
  frame(spec("scanner-sheet", "scan-busy")) ===
    frame(spec("main", "scan-busy")),
);

/* --- patch honesty: unchanged ids stay out of the patches ----------- */
const patchOf = (v) => VERSIONS.find((x) => x[0] === v)[4];
ok(
  "two-buttons patches only the five screens it changes",
  Object.keys(patchOf("two-buttons").screens).sort().join(",") ===
    "info-cover,scan-first,sheet-empty,sheet-prefilled,sheet-results",
  Object.keys(patchOf("two-buttons").screens).join(","),
);
ok(
  "two-buttons keeps the row behind the save sheet consistent with itself",
  frame(spec("two-buttons", "info-cover")).includes(PATHS.camera) &&
    frame(spec("two-buttons", "info-cover")).includes(PATHS.barcode),
);
ok(
  "scanner-sheet patches only the four screens it changes",
  Object.keys(patchOf("scanner-sheet").screens).sort().join(",") ===
    "info-barcode,scan-first,scan-lock,scan-nudge",
  Object.keys(patchOf("scanner-sheet").screens).join(","),
);
ok(
  "no version restates a flow it does not change",
  !patchOf("two-buttons").flows && !patchOf("scanner-sheet").flows,
);
ok("scanner-sheet touches no elements", !patchOf("scanner-sheet").elements);

/* --- diff direction mirrors (the label-reads-backwards pitfall) ------ */
const changed = (m) =>
  [...m.entries()]
    .filter(([, k]) => k === "changed")
    .map(([k]) => k)
    .sort()
    .join(",");
for (const v of ["two-buttons", "scanner-sheet"]) {
  const ab = diffMap("main", v, "screens");
  const ba = diffMap(v, "main", "screens");
  ok(
    "diff main<->" + v + " is symmetric on changed ids",
    changed(ab) === changed(ba),
    changed(ab),
  );
  ok(
    "diff main<->" + v + " finds no phantom additions",
    ![...ab.values()].includes("onlyHere") &&
      ![...ab.values()].includes("onlyThere"),
  );
}

/* --- open callouts land on ids the engine will actually render ------- */
const flowIds = new Set(
  resolveView("main", "flows").flatMap(([, items]) => items.map((i) => i[0])),
);
ok(
  "every OPEN key is a flow id",
  Object.keys(OPEN).every((k) => flowIds.has(k)),
  Object.keys(OPEN)
    .filter((k) => !flowIds.has(k))
    .join(","),
);
for (const v of ALLV) {
  const o = resolveOpen(v);
  ok(
    v + " keeps all three base callouts",
    o["cover-read"] && o["no-match"] && o["fall-through"],
  );
}
ok(
  "two-buttons overrides the fall-through callout rather than adding a new id",
  resolveOpen("two-buttons")["fall-through"] !== OPEN["fall-through"] &&
    resolveOpen("main")["fall-through"] === OPEN["fall-through"],
);
ok(
  "scanner-sheet adds its callout to a real flow id",
  flowIds.has("barcode-happy") && resolveOpen("scanner-sheet")["barcode-happy"],
);

/* --- every flow step is a spec the Screens tab also draws ----------- */
const drawn = new Set(ids("main").map((id) => frame(spec("main", id))));
let orphans = [];
for (const [, items] of resolveView("main", "flows"))
  for (const [fid, , , steps] of items)
    for (const [sn, , sp] of steps)
      if (!drawn.has(frame(sp))) orphans.push(fid + "/" + sn);
ok(
  "no flow step draws a state absent from Screens",
  orphans.length === 0,
  orphans.join(" "),
);

/* --- search: mirrors visibleOpts() — a group name pulls in its whole
       contents, otherwise an item is judged on its own name and note. -- */
function screenHits(q) {
  const out = [];
  for (const [g, items] of resolveView("main", "screens")) {
    const wholeGroup = matchWords(g.toLowerCase(), q.toLowerCase());
    for (const [id, nm, note] of items)
      if (
        wholeGroup ||
        matchWords(stripTags(nm + " " + note).toLowerCase(), q.toLowerCase())
      )
        out.push(id);
  }
  return out;
}
function flowHits(q) {
  const out = [];
  for (const [g, items] of resolveView("main", "flows"))
    for (const [id, nm, ds, steps] of items)
      if (matchWords(flowSearchText(g, nm, ds, steps), q.toLowerCase()))
        out.push(id);
  return out;
}
for (const [q, want] of [
  ["shutter", ["scan-first"]],
  ["nudge", ["scan-nudge"]],
  ["permission", ["scan-denied"]],
  ["getByIsbn", ["scan-noisbn"]],
  ["add-on", ["scan-multi"]],
  ["provenance", ["sheet-prefilled"]],
  ["300pt", ["sheet-empty"]],
  ["978", ["scan-multi"]],
]) {
  const got = screenHits(q);
  ok(
    'search "' + q + '"',
    want.every((w) => got.includes(w)) && got.length > 0,
    "-> " + got.join(","),
  );
}
for (const [q, want] of [
  ["escalation", "fall-through"],
  ["denied", "denied"],
  ["catalogue", "no-match"],
  ["identifier", "barcode-happy"],
  ["fuzzy", "cover-read"],
]) {
  const got = flowHits(q);
  ok('flow search "' + q + '"', got.includes(want), "-> " + got.join(","));
}

console.log(fails ? "\n" + fails + " FAILURES" : "\nall assertions passed");
process.exit(fails ? 1 : 0);
