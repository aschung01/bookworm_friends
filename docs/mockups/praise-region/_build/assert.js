/* Assertions appended to the stubbed load. Verifies the things that would
   otherwise only be checkable by eye AND would silently be wrong: version
   inheritance, diff symmetry, the duplication claim itself, and that the
   searches a reviewer will actually type resolve. */
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

/* --- shape ---------------------------------------------------------- */
const CAPSULE_V = ["stack", "stack-status", "stack-tint"];
const CHIP_V = ["main", "owned", "named", "gift"];
ok("11 cases, 3 base groups", CASES.length === 11 && SCREENS.length === 3);
ok(
  "chip directions resolve 11 screens, capsule directions 14",
  CHIP_V.every((v) => ids(v).length === 11) &&
    CAPSULE_V.every((v) => ids(v).length === 14),
  JSON.stringify(CHIP_V.concat(CAPSULE_V).map((v) => v + ":" + ids(v).length)),
);
ok(
  "stack-tint inherits three levels deep, so the who screens survive",
  ids("stack-tint").includes("who") &&
    frame(spec("stack-tint", "interested")).includes("interested fixed"),
);
ok(
  "the who-reacted screens exist only where there is a capsule to tap",
  CAPSULE_V.every((v) => ids(v).includes("who")) &&
    CHIP_V.every((v) => !ids(v).includes("who")),
);

/* --- the reported bug, asserted rather than asserted-about ----------- */
const mainMine = frame(spec("main", "mine"));
ok(
  "main/mine draws the same emoji twice",
  count(mainMine, "\u{1f4a5}") === 2,
  "got " + count(mainMine, "\u{1f4a5}"),
);
for (const v of ["owned", "named", "gift", "stack", "stack-status"]) {
  const h = frame(spec(v, "mine"));
  ok(
    v + "/mine draws it once",
    count(h, "\u{1f4a5}") === 1,
    "got " + count(h, "\u{1f4a5}"),
  );
}

/* --- the capped capsule --------------------------------------------- */
const crowd = frame(spec("stack", "crowd"));
ok(
  "capsule shows two emoji and a +3, not five",
  crowd.includes(">+3<") && crowd.split('class="e"').length - 1 === 2,
  crowd.split('class="e"').length - 1 + " emoji slots",
);
ok(
  "no count when there is no remainder",
  !frame(spec("stack", "mine-plus")).includes('class="n"') &&
    !frame(spec("stack", "mine")).includes('class="n"'),
);
ok(
  "yours is pinned first so it can never fall behind the count",
  crowd.indexOf("\u{1f4a5}") < crowd.indexOf("\u{1f606}"),
);
ok(
  "the capsule survives a status change, so the record stays reachable",
  frame(spec("stack", "stranded")).includes('class="cap"') &&
    !frame(spec("stack", "stranded")).includes("pill"),
);
ok(
  "the who sheet names an unreadable reactor in words",
  frame(spec("stack", "who-owner")).includes("don't follow"),
);
ok(
  "your row is the only tappable one, and only when you hold a reaction",
  frame(spec("stack", "who")).includes("chev") &&
    !frame(spec("stack", "who-owner")).includes("chev"),
);

/* --- badge placement ------------------------------------------------ */
const sc = frame(spec("stack-status", "mine"));
ok(
  "stack-status moves the badge out of the corner into the card",
  sc.indexOf("sbadge") > sc.indexOf('class="period'),
);
ok(
  "and stops hoisting it up the column on your own book",
  frame(spec("stack-status", "owner")).indexOf("sbadge") >
    frame(spec("stack-status", "owner")).indexOf('class="period'),
);
ok(
  "status 0 puts the badge in the band with no card wrapped round it",
  frame(spec("stack-status", "interested")).includes("barebadge") &&
    !frame(spec("stack-status", "interested")).includes('class="period'),
);
ok(
  "and it sits in the band, not back up in the column",
  frame(spec("stack-status", "interested")).indexOf("sbadge") >
    frame(spec("stack-status", "interested")).indexOf('class="band"'),
);
ok(
  "main renders no card at status 0 at all",
  !frame(spec("main", "interested")).includes('class="period'),
);

/* --- status 0, the second most common status in the library ---------- */
/* The first draft of statusBadge() was a Read/Reading ternary, so every
   Interested screen silently drew a Reading badge. */
for (const v of CHIP_V.concat(CAPSULE_V))
  ok(
    v + " labels status 0 Interested, not Reading",
    frame(spec(v, "interested-friend")).includes(">Interested<") &&
      !frame(spec(v, "interested-friend")).includes(">Reading<"),
  );
ok(
  "an Interested book offers no button and shows no reading period",
  !frame(spec("main", "interested-friend")).includes("pill") &&
    !frame(spec("main", "interested-friend")).includes("2023.09.04"),
);
ok(
  "a reaction outlives a drop to Interested, and stack still reaches it",
  frame(spec("main", "interested-reacted")).includes("\u{1f340}") &&
    frame(spec("stack", "interested-reacted")).includes('class="cap"'),
);
ok(
  "the Interested badge is drawn with the treatment it actually ships",
  frame(spec("main", "interested-friend")).includes("sbadge interested") &&
    !frame(spec("main", "interested-friend")).includes("fixed"),
);

/* --- the badge repair, folded into stack-status only ----------------- */
for (const id of ["interested", "interested-friend", "interested-reacted"]) {
  ok(
    "stack-status repairs the Interested badge on " + id,
    frame(spec("stack-status", id)).includes("interested fixed"),
  );
  ok(
    "stack leaves it alone on " + id + ", so the two changes stay separable",
    !frame(spec("stack", id)).includes("fixed"),
  );
}
ok(
  "the repair touches status 0 only — Reading and Read are untouched everywhere",
  ["main", "stack", "stack-status"].every(
    (v) =>
      frame(spec(v, "stranded")).includes('sbadge reading"') &&
      frame(spec(v, "mine")).includes('sbadge read"'),
  ),
);

/* --- stack-tint: state moves from the button to the record ----------- */
ok(
  "stack-tint hides the button once you hold a reaction",
  !frame(spec("stack-tint", "mine")).includes("pill") &&
    !frame(spec("stack-tint", "mine")).includes("Reacted"),
);
ok(
  "but keeps it when there is still something to add",
  frame(spec("stack-tint", "theirs")).includes(">React<") &&
    frame(spec("stack-tint", "none")).includes(">React<"),
);
ok(
  "stack-status does say Reacted, so the two are genuinely different",
  frame(spec("stack-status", "mine")).includes("Reacted"),
);
ok(
  "the reacted corner holds a tinted capsule and the shelf label, no button",
  frame(spec("stack-tint", "mine")).includes("cap mine") &&
    frame(spec("stack-tint", "mine")).includes('class="slab"') &&
    !frame(spec("stack-tint", "mine")).includes("pill"),
);
/* The point is not that the two screens are byte-identical — the badge and the
   emoji differ — but that neither has a button, so "the button vanished and took
   the route with it" is no longer a state that exists. */
ok(
  "stranded stops being a special case: neither state has a button",
  ["mine", "stranded", "interested-reacted"].every(
    (id) =>
      !frame(spec("stack-tint", id)).includes("pill") &&
      frame(spec("stack-tint", id)).includes("cap mine"),
  ),
);
ok(
  "the capsule always carries the chevron in stack-tint, and never in stack",
  frame(spec("stack-tint", "theirs")).includes("chev") &&
    frame(spec("stack-tint", "mine")).includes("chev") &&
    !frame(spec("stack", "mine")).includes("chev"),
);
ok(
  "the chevron open question is retired in stack-tint only",
  !resolveOpen("stack-tint")["open-who"] &&
    !!resolveOpen("stack")["open-who"] &&
    !!resolveOpen("stack-status")["open-who"],
);
ok(
  "the capsule is tinted exactly when a reaction of yours is in it",
  ["mine", "mine-plus", "crowd", "stranded", "interested-reacted"].every((id) =>
    frame(spec("stack-tint", id)).includes("cap mine"),
  ) &&
    ["theirs", "unseen", "owner"].every(
      (id) => !frame(spec("stack-tint", id)).includes("cap mine"),
    ),
);
ok(
  "a book with no reactions has no capsule to tint",
  !frame(spec("stack-tint", "none")).includes('class="cap'),
);
ok(
  "the tint reaches states the button cannot, which is the argument for it",
  frame(spec("stack-tint", "stranded")).includes("cap mine") &&
    !frame(spec("stack-tint", "stranded")).includes("pill"),
);
/* --- the verb ------------------------------------------------------- */
ok(
  "capsule directions say React, the rest say Praise",
  CAPSULE_V.every((v) => frame(spec(v, "none")).includes(">React<")) &&
    CHIP_V.every((v) => frame(spec(v, "none")).includes(">Praise<")),
);

/* --- the trap in `owned` -------------------------------------------- */
ok(
  "owned/stranded keeps your praise on screen",
  count(frame(spec("owned", "stranded")), "\u{1f44f}") === 1,
);
ok(
  "owned/theirs is untouched by the exclusion",
  frame(spec("owned", "theirs")) === frame(spec("main", "theirs")),
);

/* --- patch honesty: unchanged cases stay out of the patch ----------- */
const ownedPatch = VERSIONS.find((v) => v[0] === "owned")[4];
ok(
  "owned patches only the three cases it changes",
  Object.keys(ownedPatch.screens).sort().join(",") === "crowd,mine,mine-plus",
  Object.keys(ownedPatch.screens).join(","),
);
ok(
  "no note is attached to a case its direction leaves alone",
  DROPPED.length === 0,
  DROPPED.join(" "),
);
ok(
  "shared elements are not restated in patches",
  !("el-badge" in ownedPatch.elements) && !("el-shelf" in ownedPatch.elements),
  Object.keys(ownedPatch.elements).join(","),
);

/* --- pill state is mode-correct ------------------------------------- */
ok(
  "gift outlines the pill once you hold a praise",
  frame(spec("gift", "mine")).includes("pill out") &&
    !frame(spec("gift", "none")).includes("pill out"),
);
ok(
  "no pill at all on your own book or below status 2",
  !frame(spec("main", "owner")).includes("pill") &&
    !frame(spec("main", "stranded")).includes("pill"),
);
ok(
  "status badge moves into the column on your own book",
  frame(spec("main", "owner")).indexOf("sbadge") <
    frame(spec("main", "owner")).indexOf("corner"),
);

/* --- diff direction mirrors (the label-reads-backwards pitfall) ------ */
const ab = diffMap("main", "gift", "screens");
const ba = diffMap("gift", "main", "screens");
const changed = (m) =>
  Object.keys(m)
    .filter((k) => m[k] === "changed")
    .sort()
    .join(",");
ok(
  "diff is symmetric on changed ids",
  changed(ab) === changed(ba),
  changed(ab),
);
ok("diff finds no phantom additions", !Object.values(ab).includes("onlyHere"));

/* --- search: mirrors visibleOpts() — a group name pulls in its whole
       contents, otherwise an item needs every query word in its own name or
       note. Judging each item on its own text is the fix for the pitfall
       where typing a group name flooded the results. ------------------- */
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
  ["stranded", ["stranded"]],
  ["private", ["unseen"]],
  ["anonymous", ["theirs", "unseen"]],
  ["217pt", ["crowd"]],
]) {
  const got = screenHits(q);
  ok(
    'search "' + q + '"',
    want.every((w) => got.includes(w)) && got.length > 0,
    "-> " + got.join(","),
  );
}
for (const [q, want] of [
  ["withdraw", "withdraw"],
  ["recents", "first-praise"],
  ["marked cell", "change-praise"],
  ["unreachable", "stranded-route"],
]) {
  const got = flowHits(q);
  ok('flow search "' + q + '"', got.includes(want), "-> " + got.join(","));
}

/* --- the flows must not contradict the screens ----------------------- */
/* When the button is hidden, changing and withdrawing route through the
   who-reacted sheet, so both flows gain a step. Leaving the three-step
   versions in place would have shown a picker opening from a button that is
   not on screen. */
for (const id of ["change-praise", "withdraw"]) {
  const steps = (v) => {
    for (const [, items] of resolveView(v, "flows"))
      for (const it of items) if (it[0] === id) return it[3];
    return [];
  };
  ok(
    id + " routes through the sheet in stack-tint and not in stack-status",
    steps("stack-tint").length === 4 && steps("stack-status").length === 3,
    "stack-tint " +
      steps("stack-tint").length +
      " / stack-status " +
      steps("stack-status").length,
  );
  ok(
    id + "'s first step in stack-tint shows no button to have opened it",
    !frame(steps("stack-tint")[0][2]).includes("pill"),
  );
}
/* A flow's prose travels with its steps. Without that, stack-tint's four-step
   withdraw flow inherited main's three-step note, which asserts that no Remove
   button exists — true of main, but it also framed the picker as the only route,
   which is exactly what the sheet changes. */
const flowNote = (v, id) => {
  for (const [, items] of resolveView(v, "flows"))
    for (const it of items) if (it[0] === id) return it[2];
  return "";
};
ok(
  "stack-tint's withdraw flow carries its own prose, not main's",
  flowNote("stack-tint", "withdraw").includes("property of the record") &&
    flowNote("main", "withdraw").includes("no Remove button anywhere"),
  flowNote("stack-tint", "withdraw").slice(0, 60),
);

/* The help text under the sheet's list was drawn, then cut in the build: it
   captioned a row that already carries You and a chevron. Asserted as an absence
   so the drawing cannot drift back to describing a string that no longer
   exists in either locale. */
ok(
  "no version's who-sheet draws the removed hint",
  ["main", "stack", "stack-status", "stack-tint"].every(
    (v) => !JSON.stringify(resolveView(v, "screens")).includes("Tap your row"),
  ),
);

/* --- open callouts land on ids the engine will actually render ------- */
/* Checked against every version, because open-who exists only where the
   capsule does — an OPEN key with no flow to attach to renders nothing. */
const allFlowIds = new Set();
for (const v of CHIP_V.concat(CAPSULE_V))
  for (const [, items] of resolveView(v, "flows"))
    for (const it of items) allFlowIds.add(it[0]);
ok(
  "every OPEN key is a flow id in some version",
  Object.keys(OPEN).every((k) => allFlowIds.has(k)),
  Object.keys(OPEN)
    .filter((k) => !allFlowIds.has(k))
    .join(","),
);
ok(
  "open callouts survive resolution in every version",
  CHIP_V.concat(CAPSULE_V).every((v) => {
    const o = resolveOpen(v);
    return o["stranded-route"] && o.withdraw;
  }),
);

console.log(fails ? "\n" + fails + " FAILURES" : "\nall assertions passed");
process.exit(fails ? 1 : 0);
