"""Terminal verification for the streak-widget mockup set.

    python3 docs/mockups/streak-widget/verify.py

Extracts the page's script, confirms it parses, runs every top-level render path
against the DOM stub from the design-mockups skill's reference/pitfalls.md, then
asserts the values the page claims to have copied out of the codebase -- so a
token changed in Dart and not here shows up as a failed assertion rather than as
a mockup that quietly argues from a stale colour.

It also resolves each version by walking its ancestry the way the engine does,
and asserts what each variant is supposed to change. Patch inheritance, removal
and diff direction are where this skill's own pitfalls file says the bugs were.

What it cannot check: anything visual. The sibling streaks page records two real
defects that got past earlier versions of its own script -- a shadow clipped by
clip-path, and an invented ribbon colour. Everything this page exists to show is
visual. Open the page.
"""

import json
import pathlib
import re
import subprocess
import sys
import tempfile

SRC = "docs/mockups/streak-widget/index.html"

html = pathlib.Path(SRC).read_text()
m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
if not m:
    sys.exit("could not find the script block")
js = m.group(1)

print("script lines:", js.count("\n") + 1)
print("backticks:", "ok" if js.count("`") % 2 == 0 else "ODD")

STUB = """
const mk = () => ({ _v:"", set innerHTML(v){this._v=v;}, get innerHTML(){return this._v;},
  textContent:"", hidden:false, value:"", placeholder:"", dataset:{}, style:{},
  classList:{toggle(){},add(){},remove(){},contains(){return false;}},
  addEventListener(){}, focus(){}, blur(){}, select(){}, contains(){return false;},
  querySelectorAll(){return [];}, querySelector(){return null;}, closest(){return null;},
  getBoundingClientRect(){return {top:0};}, scrollIntoView(){},
  nextElementSibling:null, tagName:"DIV" });
global.document = { getElementById:()=>mk(), querySelectorAll:()=>[], addEventListener(){},
  body:{scrollHeight:1000}, activeElement:null,
  // Not in the skill's reference stub, and needed here: the engine hides the version
  // bar through document.querySelector('.vinfo') during load.
  querySelector:()=>mk() };
global.window = { addEventListener(){}, scrollTo(){}, innerHeight:800, scrollY:0 };
global.requestAnimationFrame = (f)=>f();
global.Event = class { constructor(t){ this.type=t; } };
"""

CHECKS = r"""
const out = { ok: [], bad: [] };
const ck = (name, cond, got) => (cond ? out.ok : out.bad).push(name + (cond ? "" : " -> " + got));

const ids = [];
const bySpec = {};
for (const [, items] of SCREENS) for (const [id, , , spec] of items) {
  ids.push(id);
  bySpec[id] = spec;
  const h = frame(spec);
  ck("renders " + id, typeof h === "string" && h.startsWith('<div class="fr'), String(h).slice(0, 40));
}
for (const want of ["sm-open","sm-late","sm-done","md-open","md-late","md-done",
                    "no-snapshot","zero-book","zero-nobook","broken",
                    "real-small","real-medium","dk-open","dk-done"])
  ck("has " + want, ids.includes(want), ids.join(","));
ck("unique ids", new Set(ids).size === ids.length, ids.length + " vs " + new Set(ids).size);

// main is the shipped state, defects and all. On systemSmall the two open states are
// byte-identical there because the status line is medium-only. If a fix lands in main,
// INVERT this assertion rather than deleting it -- it is the record of a known bug.
ck("main: sm-open and sm-late still identical (known defect)",
   frame(bySpec["sm-open"]) === frame(bySpec["sm-late"]), "they now differ");
ck("main: md-open and md-late differ",
   frame(bySpec["md-open"]) !== frame(bySpec["md-late"]), "identical");

ck("lit tile uses the core colour", frame(bySpec["sm-done"]).includes("var(--core)"), "missing core");
ck("main unlit draws the core at 55%", frame(bySpec["sm-open"]).includes('opacity="0.55"'), "missing 0.55");
ck("medium is the wide tile", frame(bySpec["md-open"]).includes("fr med"), "not med");
ck("real book has a near-white jacket", bySpec["real-small"].jacket === "#FDFDFB", String(bySpec["real-small"].jacket));
ck("real book has no progress", bySpec["real-medium"].progress === null, String(bySpec["real-medium"].progress));
ck("real medium draws no progress bar", !frame(bySpec["real-medium"]).includes("pbar"), "bar present");
ck("BOOK fixture does draw one", frame(bySpec["md-open"]).includes("pbar"), "no bar");

let steps = 0;
for (const [, items] of FLOWS) for (const [, , , list] of items) for (const [, , spec] of list) {
  steps++;
  ck("flow step renders", typeof frame(spec) === "string", "bad");
}
ck("flow steps present", steps === 7, String(steps));

for (const want of ["sm-late","broken","real-small"])
  ck("OPEN flags " + want, Object.prototype.hasOwnProperty.call(OPEN, want), Object.keys(OPEN).join(","));

// ---- Versions -------------------------------------------------------------
const V = {};
for (const [id, , , parent, patch] of VERSIONS) V[id] = { parent, patch };
ck("root has no parent", VERSIONS[0][3] === null, String(VERSIONS[0][3]));
for (const want of ["main","streak-only","streak-week","ember"])
  ck("version " + want, Object.prototype.hasOwnProperty.call(V, want), Object.keys(V).join(","));
ck("streak-week branches off streak-only", V["streak-week"].parent === "streak-only", String(V["streak-week"].parent));
ck("ember branches off streak-only", V["ember"].parent === "streak-only", String(V["ember"].parent));

/** Resolve a screen through a version's ancestry, as the engine does. */
function resolve(vid, sid) {
  const chain = [];
  for (let v = vid; v; v = V[v].parent) chain.unshift(v);
  let spec = bySpec[sid];
  let removed = false;
  for (const v of chain) {
    const p = (V[v].patch.screens || {})[sid];
    if (p === null) { removed = true; spec = undefined; }
    else if (p) { removed = false; spec = p.spec; }
  }
  return { spec, removed };
}

// The instruction: small shows streak only, medium keeps the book.
const so = resolve("streak-only", "sm-open").spec;
ck("streak-only small is streak-layout", so.layout === "streak", String(so.layout));
ck("streak-only small has no jacket in its spec", !so.jacket, String(so.jacket));
ck("streak-only small draws no jacket", !frame(so).includes('class="jk"'), "jacket present");
ck("streak-only small draws no title", !frame(so).includes('class="ttl"'), "title present");
const mo = resolve("streak-only", "md-open").spec;
ck("medium still carries the book", !!mo.jacket && frame(mo).includes('class="jk"'), "no jacket");

// The payoff: the freed room lets the line onto small, so the pair stops being identical.
const sl = resolve("streak-only", "sm-late").spec;
ck("streak-only small carries the line", frame(so).includes("midnight"), "no line");
ck("streak-only fixes the identical pair", frame(so) !== frame(sl), "still identical");

// Core treatments, the other half of the ask.
const shipped = flame(40, false, undefined);
ck("knockout differs from shipped", flame(40, false, "knockout") !== shipped, "same");
ck("ember differs from shipped", flame(40, false, "ember") !== shipped, "same");
ck("knockout uses the tile colour", flame(40, false, "knockout").includes("var(--tile)"), "no tile var");
ck("ember uses the artboard core", flame(40, false, "ember").includes("var(--core)"), "no core var");
ck("shipped core is still 55% grey", shipped.includes('opacity="0.55"'), "changed");
ck("lit core is never faded", !flame(40, true, "knockout").includes("opacity"), "faded");
ck("streak-only unlit is not the blob", !frame(so).includes('opacity="0.55"'), "still 55%");

// Every tile in the variant, not just the ones its patch happens to mention. An
// internally inconsistent version is worse than no version, because comparing it
// teaches the wrong thing -- and inheritance makes that easy to do by omission.
for (const sid of ids) {
  const r = resolve("streak-only", sid);
  if (r.removed || !r.spec) continue;
  ck("streak-only " + sid + " has no blob core",
     !frame(r.spec).includes('opacity="0.55"'), "55% grey core");
}
// And no tile in the variant may still carry a book on systemSmall.
for (const sid of ids) {
  const r = resolve("streak-only", sid);
  if (r.removed || !r.spec || r.spec.family === "medium") continue;
  ck("streak-only " + sid + " small has no jacket",
     !frame(r.spec).includes('class="jk"'), "jacket on small");
}

// streak-week trades the line back for the week, on purpose, and flags it.
const wo = resolve("streak-week", "sm-open").spec;
const wl = resolve("streak-week", "sm-late").spec;
ck("streak-week carries the week", frame(wo).includes("dashed"), "no dashed today");
ck("streak-week trades the line away again", frame(wo) === frame(wl), "they differ");
ck("streak-week flags that regression", (V["streak-week"].patch.open || {})["sm-late"] != null, "unflagged");

// Removal, and its dangling flag.
ck("streak-only removes real-small", resolve("streak-only", "real-small").removed, "still present");
ck("streak-only clears real-small's flag", (V["streak-only"].patch.open || {})["real-small"] === null, "dangling");

// ---- Visual variants ------------------------------------------------------
for (const want of ["typed","candle","lamp","mascot"])
  ck("version " + want, Object.prototype.hasOwnProperty.call(V, want), Object.keys(V).join(","));
ck("typed branches off streak-only", V["typed"].parent === "streak-only", String(V["typed"].parent));
ck("candle branches off typed", V["candle"].parent === "typed", String(V["candle"].parent));
ck("lamp branches off typed", V["lamp"].parent === "typed", String(V["lamp"].parent));
ck("mascot branches off lamp", V["mascot"].parent === "lamp", String(V["mascot"].parent));

// The variants must move on one axis at a time, or compare teaches nothing. typed
// changes faces only; candle adds a ground; lamp adds a different ground.
const t = resolve("typed", "sm-open").spec;
const c = resolve("candle", "sm-open").spec;
const l = resolve("lamp", "sm-open").spec;
ck("typed sets the face", t.typed === true, String(t.typed));
ck("typed adds no ground", !t.ground, String(t.ground));
ck("candle keeps the face", c.typed === true, String(c.typed));
ck("candle sets the candle ground", c.ground === "candle", String(c.ground));
ck("lamp sets the lamp ground", l.ground === "lamp", String(l.ground));
ck("typed and candle share a layout", t.layout === c.layout, t.layout + " vs " + c.layout);
ck("typed renders the typed class", frame(t).includes(" typed"), "no typed class");
ck("candle renders both classes", frame(c).includes("candle") && frame(c).includes("typed"), "missing one");
ck("lamp renders the lamp class", frame(l).includes("lamp"), "no lamp class");

// Every visual variant inherits streak-only's two guarantees.
for (const v of ["typed","candle","lamp","mascot"]) {
  for (const sid of ids) {
    const r = resolve(v, sid);
    if (r.removed || !r.spec) continue;
    ck(v + " " + sid + " has no blob core", !frame(r.spec).includes('opacity="0.55"'), "55% grey");
    if (r.spec.family !== "medium")
      ck(v + " " + sid + " small has no jacket", !frame(r.spec).includes('class="jk"'), "jacket");
  }
}

// ---- The mascot version ---------------------------------------------------
// Four invariants, each of which was broken at least once while building it.
const MASCOT_TILES = ["sm-open","sm-late","sm-done","md-open","zero-book"];
for (const sid of MASCOT_TILES) {
  const r = resolve("mascot", sid);
  ck("mascot " + sid + " resolves", !!r.spec && !r.removed, "missing");
  if (!r.spec) continue;
  const s = r.spec, out = frame(s);
  // 1. It inherits lamp's ground rather than quietly reverting to white.
  ck("mascot " + sid + " keeps the lamp ground", s.ground === "lamp", String(s.ground));
  // 2. Every tile actually carries a character.
  ck("mascot " + sid + " carries a cat", !!s.cat, "none");
  ck("mascot " + sid + " renders the cat plate", out.includes('class="cat"'), "no plate");
  // 3. The wash is applied to the UNLIT state only -- recording the night has to
  //    brighten the tile, which is the whole reason the flame has two tints.
  if (s.flame === "lit") {
    ck("mascot " + sid + " lit is not washed", !out.includes("glass"), "washed while lit");
    ck("mascot " + sid + " lit carries no nudge", !s.line, String(s.line));
  } else {
    ck("mascot " + sid + " unlit opts into glass", s.glass === true, String(s.glass));
    ck("mascot " + sid + " unlit renders glassy", out.includes(" glassy"), "no glassy class");
  }
}
// 4. The Duolingo-cadence copy has ONE source. COPY_SETS is declared far below
//    VERSIONS, so the lines were hoisted into DUO and COPY_SETS reads them back;
//    if someone re-inlines a literal these stop matching.
ck("duoLike reuses DUO.day", COPY_SETS.duoLike.morning === DUO.day, COPY_SETS.duoLike.morning);
ck("duoLike reuses DUO.late", COPY_SETS.duoLike.late === DUO.late, COPY_SETS.duoLike.late);
ck("duoLike reuses DUO.none", COPY_SETS.duoLike.none === DUO.none, COPY_SETS.duoLike.none);
ck("mascot open uses the duo cadence", resolve("mascot","sm-open").spec.line === DUO.day, "other copy");
ck("mascot late differs from open",
   frame(resolve("mascot","sm-late").spec) !== frame(resolve("mascot","sm-open").spec),
   "byte-identical, the defect this version exists to fix");

// ---- Matrix ---------------------------------------------------------------
// The grid is computed rather than authored, so what is worth asserting is that *every*
// combination produces a drawable tile. Checking the whole cross product is cheap here
// and impossible by eye: a missing tier key in one copy set, or a ramp that runs off the
// end of its anchors, would otherwise surface as one blank cell nobody happens to select.
for (const want of ["copy","type","core","family"])
  ck("axis " + want, !!AXES[want] && AXES[want].options.length > 1, Object.keys(AXES).join(","));

// ---- The mascot axis, and the voice ---------------------------------------
ck("axis cat", !!AXES.cat && AXES.cat.options.length === 2, Object.keys(AXES).join(","));
ck("the matrix speaks in Duolingo cadence by default", mx.copy === "duoLike", String(mx.copy));
ck("the mascot is on by default", mx.cat === "on", String(mx.cat));
ck("the matrix figure is Nunito", AXES.type.options.some(([k,l]) => k === "typed" && /Nunito/.test(l)),
   JSON.stringify(AXES.type.options));
// One expression per state, and never the same one twice -- if done, none and the two
// open tiers ever collapse onto one drawing the axis stops meaning anything.
{
  const seen = {
    done: mxCat("done", 12),
    none: mxCat("none", 21),
    day: mxCat("open", 12),
    late: mxCat("open", 21),
    final: mxCat("open", 23),
  };
  ck("each matrix state gets its own expression",
     new Set(Object.values(seen)).size === 5, JSON.stringify(seen));
  ck("the evening tile is the drowsy one", seen.late === "m07-drowsy", seen.late);
  ck("the dormant tile is asleep, not sad", seen.none === "m06-snooze", seen.none);
  // The escalation the round added: drowsy-at-midnight excused the miss, so the final
  // tier panics instead. Asserted on both sides -- that 23:00 panics AND that 21:00
  // does not -- because collapsing the two back together is the easy regression.
  ck("the final hour panics rather than dozing", seen.final === "m12-panic", seen.final);
  ck("and the late tier is still distinct from it", seen.late !== seen.final,
     seen.late + " / " + seen.final);
}
// The mascot and the shelf/week want the same 130pt, so only one may be drawn.
for (const under of ["none","shelf","shelf-noline","shelf-apart","week"]) {
  const s = mxSpec("candle", "open", 12, { ...mx, under });
  if (under === "none")
    ck("mascot draws when nothing is under the number", !!s.cat, "absent");
  else
    ck("mascot yields to " + under, !s.cat, String(s.cat));
}
ck("the mascot axis can be switched off", !mxSpec("candle", "open", 12, { ...mx, cat: "off" }).cat, "still drawn");
// Every ramp x hour x state must still produce a drawable tile with a cat on.
for (const [k] of MX_RAMPS)
  for (const hour of MX_HOURS)
    for (const kind of ["open","done","none"]) {
      const out = frame(mxSpec(k, kind, hour, mx));
      ck("mascot tile draws: " + k + " " + kind + " " + hour, out.includes("class=\"fr"), "blank");
    }
// The axes traded places when the voice was chosen: what is settled becomes a selector,
// what is open becomes the grid. Both halves of that are asserted so a half-done swap
// (a copy selector that the grid still varies) cannot pass.
ck("voice IS a selector now", !!AXES.copy, "missing");
ck("background is NOT a selector any more", !AXES.ramp && !AXES.scheme, "still a selector");
ck("the hour is not a selector", !AXES.hour, "still a selector");
ck("state is not a selector", !AXES.phase, "still a selector");
ck("the old three-state scheme axis is gone", typeof SCHEMES === "undefined", "SCHEMES still defined");
// The decisions this round recorded, as the page's own defaults.
ck("voice defaults to the Duolingo cadence", mx.copy === "duoLike", String(mx.copy));
ck("type defaults to Pretendard + GowunBatang", mx.type === "typed", String(mx.type));
ck("the unlit core defaults to divider grey", mx.core === "grey", String(mx.core));
ck("the default is drawn typed", frame(mxSpec("candle", "open", 12, mx)).includes(" typed"), "not typed");

// Rows are hours, columns are grounds.
ck("rows are the waking day", MX_HOURS.length === 17, String(MX_HOURS.length));
ck("rows run 07:00 to 23:00", MX_HOURS[0] === 7 && MX_HOURS[16] === 23, MX_HOURS.join(","));
ck("columns are the ramps", MX_RAMPS.length === Object.keys(RAMPS).length, String(MX_RAMPS.length));
// Four grounds were discarded this round -- step, dusk, brand and heat -- and `stages`
// replaced them, so the count is pinned to catch a quiet re-add as much as a loss.
ck("there are seven grounds to choose from", MX_RAMPS.length === 7, String(MX_RAMPS.length));
for (const gone of ["step","dusk","brand","heat"])
  ck("discarded ground " + gone + " is really gone", !RAMPS[gone], "still present");
ck("there are four voices to choose from", AXES.copy.options.length === 4, String(AXES.copy.options.length));
for (const gone of ["lowbar","invite","imperative","deadpan","bookish","shipped",
                    "stakes","countdown","hot","blank"])
  ck("discarded voice " + gone + " is really gone", !COPY_SETS[gone], "still present");
// The two ARB strings outlive the `shipped` voice: they are what every version row above
// still renders, which is where the long baseline is legible beside its replacement.
ck("the shipped baseline survives as a version, not a voice",
   typeof OPEN_LINE === "string" && OPEN_LINE.split(/\s+/).length > 5, String(OPEN_LINE));
ck("there are six tone tiers", TIER_KEYS.length === 6, TIER_KEYS.join(","));
// 17 hours + recorded + no-run, times seven grounds.
ck("the sheet is 133 tiles", MX_RAMPS.length * (MX_HOURS.length + 2) === 133,
   String(MX_RAMPS.length * (MX_HOURS.length + 2)));

// Tiers partition the day: every hour lands in exactly one, and the boundaries are where
// they were declared.
for (let h = 0; h <= 23; h++)
  ck("hour " + h + " has a tier", TIER_KEYS.includes(tierAt(h)), String(tierAt(h)));
ck("00:00 clamps to dawn", tierAt(0) === "dawn", tierAt(0));
ck("09 is still dawn, 10 is morning", tierAt(9) === "dawn" && tierAt(10) === "morning",
   tierAt(9) + "/" + tierAt(10));
ck("20 is evening, 21 is late", tierAt(20) === "evening" && tierAt(21) === "late",
   tierAt(20) + "/" + tierAt(21));
ck("23 is its own tier", tierAt(22) === "late" && tierAt(23) === "final",
   tierAt(22) + "/" + tierAt(23));

// Recorded carries no line, in any set. Asserted as an absence so a later set cannot
// quietly reintroduce one.
for (const [k, set] of Object.entries(COPY_SETS)) {
  ck("copy set " + k + " has no done key",
     !Object.prototype.hasOwnProperty.call(set, "done"), "done present");
  for (const tier of TIER_KEYS.concat(["none"]))
    ck("copy set " + k + " covers " + tier,
       Object.prototype.hasOwnProperty.call(set, tier), Object.keys(set).join(","));
  ck("copy set " + k + " has a gloss",
     typeof set.gloss === "string" && set.gloss.length > 40, "thin gloss");
}
// Every set that pushes past the design record has to say so where it is *picked*, not
// only in prose. `hot` used to shout "OUT OF BOUNDS" from its label; it was promoted this
// round because the harder nudge was asked for, so the honesty moved into the glosses --
// which means the glosses are now the thing under test. Each must name the rule it breaks.
//
// `desperate` is deliberately NOT in this list, and that is a finding rather than an
// oversight: it never mentions loss, never counts down, never scolds and is not red, so it
// passes all four rules on the letter while pushing as hard as anything here. Which is
// either the way through the conflict or proof that the four rules were the wrong test.
const OUT_OF_BOUNDS = ["guilt","unhinged"];
for (const k of OUT_OF_BOUNDS)
  ck("voice " + k + " names what it violates",
     /breaks?|violat|scold|countdown|lost|risk|rule/i.test(COPY_SETS[k].gloss),
     COPY_SETS[k].gloss.slice(0, 70));
ck("desperate's gloss records that it slips the rules rather than breaking them",
   /letter|spirit|in bounds/i.test(COPY_SETS.desperate.gloss),
   COPY_SETS.desperate.gloss.slice(0, 70));
ck("and it really does avoid all four -- no loss, no countdown",
   !TIER_KEYS.some((t) => /break|lose|lost|streak|hours? left/i.test(COPY_SETS.desperate[t])),
   JSON.stringify(TIER_KEYS.map((t) => COPY_SETS.desperate[t])));
// ...including in its variants, which is where a careless third line would leak a loss
// threat back in and quietly void the finding above.
ck("desperate's variants avoid them too",
   !TIER_KEYS.some((t) => (COPY_SETS.desperate.alts[t] || [])
     .some((s) => /break|lose|lost|streak|hours? left/i.test(s))),
   JSON.stringify(COPY_SETS.desperate.alts));
ck("and so does the one that shouts loudest on the ground",
   /amend/i.test(resolve("stages","sm-late").note) ||
   /amend/i.test(VMAP.get("stages")[4].open["sm-late"]), "no amendment named");
// duoLike is the only in-bounds voice left, so it is the only one exempt from the above --
// and the one whose own rules still need pinning.
ck("duoLike claims to be in bounds", /in bounds/i.test(COPY_SETS.duoLike.label),
   COPY_SETS.duoLike.label);
// Length is the register. Duolingo's lines are 2-4 words; ours drift long when they drift
// AI-written, so every voice gets the ceiling -- and now every VARIANT does too, which is
// the whole risk of tripling the line count.
for (const k of Object.keys(COPY_SETS))
  for (const tier of TIER_KEYS)
    for (const [label, text] of copyVariants(k, tier)) {
      const words = text.split(/\s+/).filter(Boolean).length;
      ck(label + " stays short", words > 0 && words <= 5, text + " (" + words + "w)");
    }

// ---- The variants, and the pose pairing -----------------------------------
// Three per tier, no exceptions: a voice with two variants somewhere is a voice that
// cannot be compared evenly against the others at that hour.
const ALL_TIERS = TIER_KEYS.concat(["none"]);
for (const k of Object.keys(COPY_SETS)) {
  ck("voice " + k + " has a one-letter code",
     typeof COPY_SETS[k].code === "string" && COPY_SETS[k].code.length === 1,
     String(COPY_SETS[k].code));
  for (const tier of ALL_TIERS)
    ck(k + "." + tier + " offers three variants", copyVariants(k, tier).length === 3,
       String(copyVariants(k, tier).length));
}
// Variant 1 is always the previously-judged line, so nothing already decided silently
// changes identity when the alts are added.
for (const k of Object.keys(COPY_SETS))
  for (const tier of ALL_TIERS)
    ck("variant 1 of " + k + "." + tier + " is the set's own line",
       copyVariants(k, tier)[0][1] === COPY_SETS[k][tier], copyVariants(k, tier)[0][1]);
// The labels are the whole point -- a choice is made by naming one -- so a collision
// would make a choice ambiguous.
{
  const labels = [];
  for (const k of Object.keys(COPY_SETS))
    for (const tier of ALL_TIERS)
      for (const [label] of copyVariants(k, tier)) labels.push(label);
  ck("every variant label is unique", new Set(labels).size === labels.length,
     String(labels.length) + " labels, " + new Set(labels).size + " distinct");
  ck("there are 84 labelled lines", labels.length === 84, String(labels.length));
}
// No duplicate text inside a tier either, or a "variant" is the same line twice and the
// comparison is a waste of a tile.
for (const k of Object.keys(COPY_SETS))
  for (const tier of ALL_TIERS) {
    const texts = copyVariants(k, tier).map(([, t]) => t);
    ck(k + "." + tier + "'s three variants really differ",
       new Set(texts).size === 3, JSON.stringify(texts));
  }
// The pose ladder. Every state a tile can be in needs a face, including the two that are
// not tiers.
const POSE_STATES = ALL_TIERS.concat(["done"]);
for (const k of Object.keys(COPY_SETS)) {
  for (const s of POSE_STATES)
    ck("voice " + k + " pairs a pose with " + s,
       typeof COPY_SETS[k].poses[s] === "string" && /^m\d\d-/.test(COPY_SETS[k].poses[s]),
       String(COPY_SETS[k].poses[s]));
  // Distinct across the open day, which is the fix for the old mapping: mxCat returned
  // m03-reading for dawn, morning, afternoon AND evening, so four of six tiers were the
  // same drawing and only the ground moved.
  const open = TIER_KEYS.map((t) => COPY_SETS[k].poses[t]);
  ck("voice " + k + "'s six open poses are all different",
     new Set(open).size === TIER_KEYS.length, open.join(","));
  // m05-puddle is excluded on measurement, not taste: 145px wide in a 158px tile, it
  // overlaps the copy column by 59.5px where every other cut-out stays under 10px. It is
  // therefore only usable on `done`, which carries no line.
  for (const s of ALL_TIERS)
    ck("voice " + k + " keeps the puddle off " + s + ", which carries copy",
       COPY_SETS[k].poses[s] !== "m05-puddle", COPY_SETS[k].poses[s]);
}
// Every pose named must be a cut-out that exists, or the grid renders a broken image.
for (const k of Object.keys(COPY_SETS))
  for (const s of POSE_STATES)
    ck("pose " + COPY_SETS[k].poses[s] + " (" + k + "." + s + ") is a real cut-out",
       CUTOUTS.includes(COPY_SETS[k].poses[s]), COPY_SETS[k].poses[s]);
// And the ladders must not all be the same ladder, or pairing was not a decision.
{
  const ladders = Object.keys(COPY_SETS).map((k) =>
    TIER_KEYS.map((t) => COPY_SETS[k].poses[t]).join(","));
  ck("the four voices propose four different ladders",
     new Set(ladders).size === 4, JSON.stringify(ladders));
  // `unhinged` is the one that deliberately does not end in alarm -- a cat that panics at
  // the deadline has conceded the deadline is in charge, which is the opposite of the bit.
  ck("unhinged alone does not end its day in panic",
     COPY_SETS.unhinged.poses.final !== "m12-panic" &&
     ["duoLike","guilt","desperate"].every((k) => COPY_SETS[k].poses.final === "m12-panic"),
     COPY_SETS.unhinged.poses.final);
}
// The chosen voice, specifically: it is the one that still ships in the page's default, so
// its own rules are worth pinning. Duolingo's cadence is exclaimed and never about loss.
ck("duoLike never threatens loss",
   !TIER_KEYS.some((t) => /break|lose|lost|risk|last chance/i.test(COPY_SETS.duoLike[t])),
   JSON.stringify(TIER_KEYS.map((t) => COPY_SETS.duoLike[t])));
ck("duoLike states the deadline rather than counting down",
   /midnight/i.test(COPY_SETS.duoLike.late) && !/\bleft\b|\bhour\b/i.test(COPY_SETS.duoLike.late),
   COPY_SETS.duoLike.late);
// ...and the inverse, which is the whole reason the new sets exist: at least one voice
// must actually threaten loss by the late tier, or the round changed nothing.
ck("some voice pushes hard by 21:00",
   Object.keys(COPY_SETS).some((k) =>
     /break|lose|lost|risk|last chance|midnight|forgot|begging|hours left/i.test(COPY_SETS[k].late)),
   "nothing escalates");

// Every copy set must differ from every other in at least one tier, or a selector option is
// a duplicate wearing a different name.
const sig = {};
for (const [set] of AXES.copy.options)
  sig[set] = TIER_KEYS.concat(["none"]).map((t) => COPY_SETS[set][t] || "").join("|");
ck("no two copy sets are identical",
   new Set(Object.values(sig)).size === AXES.copy.options.length,
   JSON.stringify(sig).slice(0, 160));
// And within a set the tiers have to actually move, or the finer tier bought nothing.
for (const k of Object.keys(COPY_SETS)) {
  ck("set " + k + " changes across the day",
     new Set(TIER_KEYS.map((t) => COPY_SETS[k][t])).size === TIER_KEYS.length,
     JSON.stringify(TIER_KEYS.map((t) => COPY_SETS[k][t])));
}

// ---- Ramps ----------------------------------------------------------------
// A ramp's claims are all measurable, which is the only reason this file can say anything
// about colour: it yields the number of distinct grounds it says it does, the recorded
// ground stays out of reach of the open ones, the ink on it is the better of two, and
// whether it crosses a sub-4.5:1 band is *declared* rather than discovered. That last one
// matters most -- a new ramp has to state its own hazard and be held to it.
for (const [k, r] of Object.entries(RAMPS)) {
  ck("ramp " + k + " has a note", typeof r.note === "string" && r.note.length > 40, "thin note");
  ck("ramp " + k + " declares hourly", typeof r.hourly === "boolean", String(r.hourly));
  ck("ramp " + k + " declares its contrast band", typeof r.band === "boolean", String(r.band));
  if (k === "flat") {
    ck("flat really is flat", r.anchors === null && r.done === null, "has colour");
    ck("flat produces no inline ground", rampAt("flat", 12) === null, "produced one");
    continue;
  }
  ck("ramp " + k + " has a recorded ground", Array.isArray(r.done) && r.done.length === 2, String(r.done));
  const seen = new Set();
  let below = [], inkWrong = 0;
  for (const h of MX_HOURS) {
    const g = rampAt(k, h);
    if (!g || !/^#[0-9a-f]{6}$/i.test(g[0]) || !/^#[0-9a-f]{6}$/i.test(g[1])) {
      ck("ramp " + k + " interpolates at " + h, false, String(g));
      continue;
    }
    seen.add(g.join("").toLowerCase());
    const vars = groundVars(g[0], g[1], false);
    const mid = mixHex(g[0], g[1], 0.5);
    // Read back out of groundVars rather than recomputed here. Recomputing it is how the
    // last bug hid: the page and this file agreed on a wrong threshold.
    const ink = (vars.match(/--ink:(#[0-9A-Fa-f]{6})/) || [])[1];
    const other = ink.toLowerCase() === INK_LIGHT.toLowerCase() ? INK_DARK : INK_LIGHT;
    // The threshold has to pick the *better* of the two inks at every hour. It cannot
    // promise 4.5:1, because a ground passing through the middle denies both.
    if (contrast(ink, mid) < contrast(other, mid)) inkWrong++;
    if (contrast(ink, mid) < 4.5) below.push(h);
    // The line is drawn in --dim, and the line is what the sheet exists to judge, so its
    // contrast is asserted rather than left to whatever the fade happened to give.
    const dim = (vars.match(/--dim:(#[0-9a-f]{6})/) || [])[1];
    ck("ramp " + k + " at " + h + " keeps the line legible", contrast(dim, mid) >= 3.2,
       dim + " on " + mid + " = " + contrast(dim, mid).toFixed(2) + ":1");
    // Counted as named declarations rather than as occurrences of "--": the mesh
    // references var(--grain) inside the background, so a raw count of "--" is 5 and
    // this assertion started failing for a reason that had nothing to do with the vars.
    ck("ramp " + k + " at " + h + " sets four vars",
       (vars.match(/--(?:tile|ink|dim|div):/g) || []).length === 4, vars);
  }
  ck("ramp " + k + " picks the better ink at every hour", inkWrong === 0, inkWrong + " hours wrong");
  // hourly ramps must be distinct at every hour; a stepped one must NOT be, or it is
  // claiming to be a step while behaving like a ramp.
  if (r.hourly)
    ck("ramp " + k + " yields a ground per hour", seen.size === MX_HOURS.length, seen.size + " distinct");
  else
    ck("ramp " + k + " steps rather than ramps",
       seen.size > 1 && seen.size < MX_HOURS.length, seen.size + " distinct");
  ck("ramp " + k + " band declaration matches measurement",
     (below.length > 0) === r.band, "declared " + r.band + ", measured at " + (below.join(",") || "none"));
  if (r.band)
    ck("ramp " + k + " admits the band in its note", /4\.5|contrast|legib/i.test(r.note),
       r.note.slice(0, 60));
}
// The inversion: the recorded ground must not be reachable by any open hour, or the whole
// recorded/unrecorded distinction collapses. `paper` is the counter-example, flagged.
for (const [k, r] of Object.entries(RAMPS)) {
  if (k === "flat") continue;
  // Lowercased on both sides: rampAt returns RGB()'s lowercase hex while the anchors are
  // written uppercase, so a case-sensitive compare would report "never collides" for every
  // ramp and quietly assert nothing.
  const doneSig = r.done.join("").toLowerCase();
  const collides = MX_HOURS.filter((h) => rampAt(k, h).join("").toLowerCase() === doneSig);
  if (k === "paper")
    ck("paper's inversion collapses at 20:00 (known defect, flagged in its note)",
       collides.includes(20) && /inversion vanishes|defect/i.test(r.note), collides.join(","));
  else
    ck("ramp " + k + " never reaches the recorded ground", collides.length === 0, collides.join(","));
}
// Direction: recorded is the pale end in every ramp that has one.
for (const [k, r] of Object.entries(RAMPS)) {
  if (k === "flat") continue;
  ck("ramp " + k + " recorded is paler than 23:00",
     lum(mixHex(r.done[0], r.done[1], 0.5)) > lum(mixHex(...rampAt(k, 23), 0.5)), k);
}
ck("candle darkens rather than brightens",
   lum(mixHex(...rampAt("candle", 23), 0.5)) < lum(mixHex(...rampAt("candle", 7), 0.5)), "brightens");
ck("sundown falls from light to dark",
   lum(mixHex(...rampAt("sundown", 7), 0.5)) > 0.6 &&
   lum(mixHex(...rampAt("sundown", 23), 0.5)) < 0.02, "no fall");
const inkAt = (k, h) =>
  (groundVars(...rampAt(k, h), false).match(/--ink:(#[0-9A-Fa-f]{6})/) || [])[1].toLowerCase();
// `dusk` used to carry this claim and was discarded; `stages` inherited it and has now
// outgrown it. The ramp no longer flips ink, because every hour is dark -- so the light
// ink wins from 07:00 to 23:00. That is the honest new claim and it is an improvement
// rather than a loss: an ink that flips mid-afternoon means the tile's type changes
// colour while you are looking at it across a day, which nothing on the sheet wanted.
ck("stages holds one ink all day rather than flipping",
   MX_HOURS.every((h) => inkAt("stages", h) === INK_LIGHT.toLowerCase()),
   MX_HOURS.map((h) => inkAt("stages", h)).join(","));
// rising's whole claim is that the tile's weight does not change -- only the bottom edge.
ck("rising holds its top edge all day",
   rampAt("rising", 7)[0].toLowerCase() === rampAt("rising", 23)[0].toLowerCase(),
   rampAt("rising", 7)[0] + " -> " + rampAt("rising", 23)[0]);
ck("rising warms its bottom edge",
   rampAt("rising", 7)[1].toLowerCase() !== rampAt("rising", 23)[1].toLowerCase() &&
   lum(rampAt("rising", 23)[1]) > lum(rampAt("rising", 7)[1]), "no warming");
ck("rising stays dark the whole day",
   MX_HOURS.every((h) => inkAt("rising", h) === INK_LIGHT.toLowerCase()), "goes light");
// stages is the round's answer to "pastel when recorded, vibrant when not", and every
// half of that claim is measurable, so none of it is left to prose.
//
// 1. It must NOT darken toward midnight -- that is the whole difference from every other
//    ramp on the sheet, all of which do. Asserted as saturation rather than lightness,
//    because a bright red and a bright blue can share a luminance.
const sat = (hex) => {
  const [r, g, b] = HEX(hex).map((v) => v / 255);
  const hi = Math.max(r, g, b), lo = Math.min(r, g, b);
  return hi === 0 ? 0 : (hi - lo) / hi;
};
ck("stages is saturated at every open hour",
   MX_HOURS.every((h) => sat(mixHex(...rampAt("stages", h), 0.5)) > 0.3),
   MX_HOURS.map((h) => sat(mixHex(...rampAt("stages", h), 0.5)).toFixed(2)).join(","));
// 2. ...and the recorded ground must be the pastel one. Not merely paler -- *calmer*,
//    which is the actual signal here, since the blue morning is light too.
ck("stages recorded is pastel where the open hours are not",
   sat(mixHex(RAMPS.stages.done[0], RAMPS.stages.done[1], 0.5)) < 0.3,
   String(sat(mixHex(RAMPS.stages.done[0], RAMPS.stages.done[1], 0.5)).toFixed(2)));
// 3. The inversion holds at EVERY hour, which is what sundown, paper and dusk could not
//    do -- they went pale in the morning and collided with recorded. Measured as a real
//    saturation gap rather than as "never exactly equal".
ck("stages keeps its inversion at every hour, not just the late ones",
   MX_HOURS.every((h) =>
     sat(mixHex(...rampAt("stages", h), 0.5)) -
     sat(mixHex(RAMPS.stages.done[0], RAMPS.stages.done[1], 0.5)) > 0.15),
   "collapses somewhere");
// 4. The ladder is the documented one: blue at the calm end, red at the deadline. Read off
//    the channels rather than named, so a later edit to the anchors cannot keep the claim
//    while losing the colours.
{
  const [r7, g7, b7] = HEX(mixHex(...rampAt("stages", 7), 0.5));
  const [r23, g23, b23] = HEX(mixHex(...rampAt("stages", 23), 0.5));
  ck("stages starts on a cool slate blue", b7 > g7 && g7 > r7, `${r7},${g7},${b7}`);
  ck("stages ends on a deep red", r23 > g23 && r23 > b23, `${r23},${g23},${b23}`);
}
// The arc's contract, and it CHANGED when the character did.
//
// This block used to assert that the ramp stayed on one side of the colour wheel and
// left a wide complement region. That was the right contract for a *chromatic* cat,
// which separates from the ground by hue. The fur is now going to be one of the four
// greys, and a neutral cat has no hue to oppose with -- its only weapon is lightness.
// So the wheel constraint is void and would be actively misleading if left in: the
// new ramp deliberately travels from a slate blue to a deep red, which spans more of
// the wheel than the old floor allowed and is fine, because nothing is trying to sit
// opposite it.
//
// What replaces it is the constraint that actually protects a neutral character: every
// open hour has to be DARK, so the cat reads as the light thing in the room. This is
// also the diagnosis of what was wrong before -- the old arc was saturated magenta and
// pink at mid lightness, i.e. the cat's own value band.
{
  const mids = MX_HOURS.map((h) => mixHex(...rampAt("stages", h), 0.5));
  const lums = mids.map(lum);
  ck("every stages hour is dark enough for a neutral character",
     Math.max(...lums) < 0.15,
     "brightest hour is " + Math.max(...lums).toFixed(4));
  // ...and the inversion still has to be a real step, measured against the darkest
  // rather than assumed: recorded is pale, so this is a large gap by construction, but
  // it is the number that makes recording the night feel like something happened.
  const doneLum = lum(mixHex(RAMPS.stages.done[0], RAMPS.stages.done[1], 0.5));
  ck("recording the night is a large lightness jump",
     doneLum / Math.max(...lums) > 5,
     (doneLum / Math.max(...lums)).toFixed(1) + "x");
  // The four grey candidates are the live shortlist, so the ramp is held to all of
  // them rather than to whichever one is eventually picked. Best-of-three-tones,
  // because a wide-spread cat separates via its belly.
  const GREYS = { grey: ["#A4A4A6", "#D6D2D1", "#ECE8E5"],
                  smoke: ["#3A3F46", "#7A828C", "#EDEFF2"],
                  bluepoint: ["#33404D", "#8794A1", "#E8EDF2"],
                  tuxedo: ["#1E2024", "#33373D", "#F2EEE9"] };
  for (const [name, tones] of Object.entries(GREYS)) {
    const worst = Math.min(...mids.map((m) => Math.max(...tones.map((t) => contrast(t, m)))));
    ck("stages keeps " + name + " legible at every hour", worst >= 4.5,
       "worst " + worst.toFixed(2) + ":1");
  }
  // Nothing above names a fur, deliberately -- the choice is open between those four.
  // What is asserted is that the ramp works for ALL of them, so picking one later
  // cannot invalidate the ground.
  ck("the ramp does not depend on which grey is chosen",
     (() => {
       const worsts = Object.values(GREYS).map((tones) =>
         Math.min(...mids.map((m) => Math.max(...tones.map((t) => contrast(t, m))))));
       return Math.max(...worsts) - Math.min(...worsts) < 1.0;
     })(), "the greys diverge");
  // The recorded end is not invented: it is kCandleGlow, which already ships.
  const CANDLE_GLOW = ["#fffdf8", "#ffe8c4"];
  ck("stages recorded reuses the candle glow rather than an invented pastel",
     RAMPS.stages.done.map((c) => c.toLowerCase()).join(",") === CANDLE_GLOW.join(","),
     JSON.stringify(RAMPS.stages.done));
}
// 5. It breaks "amber and never red", and has to say so in its own note rather than only
//    in the version's prose -- the note is what the matrix legend prints.
ck("stages admits it breaks the never-red rule",
   /never red/i.test(RAMPS.stages.note) && /amend/i.test(RAMPS.stages.note),
   RAMPS.stages.note.slice(0, 80));
// Invention, labelled in both places. The sibling streaks page records an invented ribbon
// colour as a defect that passed its own verifier; this is the guard against a repeat.
for (const k of ["stages","duo"]) {
  ck(k + " is labelled INVENTED in its label", /INVENTED/i.test(RAMPS[k].label), RAMPS[k].label);
  ck(k + " is labelled invented in its note", /invented/i.test(RAMPS[k].note), RAMPS[k].note.slice(0, 50));
}
for (const k of ["candle","sundown","rising","paper"])
  ck(k + " claims nothing invented", !/INVENTED/i.test(RAMPS[k].label), RAMPS[k].label);

// ---- The cross product ----------------------------------------------------
let cells = 0, badCells = 0, lineOnDone = 0, jacketOnSmall = 0;
const kinds = MX_HOURS.map((h) => ["open", h]).concat([["done", 23], ["none", 21]]);
for (const [rp] of MX_RAMPS)
 for (const [kind, hour] of kinds)
  for (const [cp] of AXES.copy.options)
   for (const [un] of AXES.under.options)
    for (const [t] of AXES.type.options)
     for (const [c] of AXES.core.options)
      for (const [f] of AXES.family.options) {
        const spec = mxSpec(rp, kind, hour, { copy:cp, under:un, type:t, core:c, family:f });
        const h = frame(spec);
        cells++;
        if (typeof h !== "string" || !h.startsWith('<div class="fr')) badCells++;
        // The decision streak-only settled: the book is medium's alone. A leaning shelf is
        // not a jacket in that sense -- it is the shelf, not "the book I am in" -- so it is
        // allowed on small and the check looks for the single-jacket composition instead.
        if (f === "small" && h.includes('class="jk"') && !h.includes('class="shelf"'))
          jacketOnSmall++;
        // And the decision the round before this one settled.
        if (kind === "done" && spec.line) lineOnDone++;
        // A computed ground must land as inline vars on the tile, or the interpolation is
        // being thrown away somewhere between mxSpec and frame.
        if (rp !== "flat" && !h.includes("--tile:")) badCells++;
        if (rp === "flat" && h.includes("--tile:")) badCells++;
      }
ck("every matrix cell renders", badCells === 0, badCells + " bad of " + cells);
ck("no small cell carries a lone book jacket", jacketOnSmall === 0, jacketOnSmall + " did");
// 7 ramps x 19 states x 4 voices x 5 unders x 2 types x 4 cores x 2 families. Was 85120
// when there were eight voices; cutting four halved it.
ck("the cross product is the expected size", cells === 42560, String(cells));
ck("no recorded cell carries a line", lineOnDone === 0, lineOnDone + " did");

// The treatments have to be genuinely orthogonal to the ramp and the hour, or the grid
// lies about what it isolates.
const mbase = { copy:"duoLike", type:"system", core:"shipped", family:"small" };
ck("shipped core is the 55% blob",
   frame(mxSpec("flat", "open", 12, mbase)).includes('opacity="0.55"'), "not blob");
ck("knockout reaches the ground",
   frame(mxSpec("flat", "open", 12, { ...mbase, core:"knockout" })).includes("var(--tile)"), "no tile var");
ck("divider grey is a third treatment",
   frame(mxSpec("flat", "open", 12, { ...mbase, core:"grey" })) !==
   frame(mxSpec("flat", "open", 12, { ...mbase, core:"knockout" })) &&
   frame(mxSpec("flat", "open", 12, { ...mbase, core:"grey" })) !==
   frame(mxSpec("flat", "open", 12, mbase)), "not distinct");
ck("type axis is isolated",
   frame(mxSpec("flat", "open", 12, { ...mbase, type:"typed" })).includes(" typed") &&
   !frame(mxSpec("flat", "open", 12, mbase)).includes(" typed"), "typed leaked or missing");
// Voice used to change the line and nothing else. It now changes the POSE as well, since
// the pairing moved into COPY_SETS.poses -- so both halves are asserted, because a voice
// that reposed nothing would mean the ladders are declared and ignored.
//
// At 07:00, not 12:00: the ladders are allowed to agree at any given hour and duoLike and
// guilt both happen to read at 12:00 (m03-reading). Dawn is where these two diverge --
// duoLike opens ready, guilt opens glad to see you -- so it is the hour that actually
// tests the wiring rather than the hour that happens to collide.
ck("voice changes the line",
   mxSpec("flat", "open", 12, mbase).line !==
   mxSpec("flat", "open", 12, { ...mbase, copy:"guilt" }).line, "same");
ck("voice changes the pose too",
   mxSpec("flat", "open", 7, { ...mbase, cat:"on", under:"none" }).cat !==
   mxSpec("flat", "open", 7, { ...mbase, cat:"on", under:"none", copy:"guilt" }).cat,
   String(mxSpec("flat", "open", 7, { ...mbase, cat:"on", under:"none" }).cat));
ck("the ground changes across the columns",
   frame(mxSpec("candle", "open", 12, mbase)) !== frame(mxSpec("stages", "open", 12, mbase)), "same");
ck("the ground changes down the rows",
   frame(mxSpec("stages", "open", 8, mbase)) !== frame(mxSpec("stages", "open", 22, mbase)), "same");
// `blank` was the no-line control and is gone with the other three cut voices. The
// question it answered -- is the line load-bearing at all -- is now answered by rendering
// any voice with its line suppressed, so what is asserted here is the inverse: every
// surviving voice really does draw one on an open tile, because a voice that silently
// rendered nothing would look like the control and be mistaken for it.
for (const [cp] of AXES.copy.options)
  ck("voice " + cp + " draws a line when the day is open",
     frame(mxSpec("flat", "open", 12, { ...mbase, copy:cp })).includes('class="line"'),
     "no line");
ck("medium carries the book",
   frame(mxSpec("flat", "open", 12, { ...mbase, family:"medium" })).includes('class="jk"'), "no jacket");
ck("flat scheme really is flat",
   !mxSpec("flat", "open", 12, mbase).groundStyle &&
   !mxSpec("flat", "done", 23, mbase).groundStyle, "has a ground");

// The ground is a function of the hour and the ramp alone; the line of the tier alone.
ck("the ground ignores the voice",
   mxSpec("stages", "open", 16, mbase).groundStyle ===
   mxSpec("stages", "open", 16, { ...mbase, copy:"unhinged" }).groundStyle, "differs");
ck("the line ignores the ground",
   mxSpec("stages", "open", 16, mbase).line === mxSpec("sundown", "open", 16, mbase).line, "differs");
ck("hours in one tier share a line",
   mxSpec("flat", "open", 18, mbase).line === mxSpec("flat", "open", 20, mbase).line, "differ");
ck("hours across a boundary do not",
   mxSpec("flat", "open", 20, mbase).line !== mxSpec("flat", "open", 21, mbase).line, "same");

// Recorded, and the no-run row.
ck("recorded is drawn lit", mxSpec("candle", "done", 23, mbase).flame === "lit", "unlit");
// The label is gone from the streak layout, in favour of "[flame] N" on one line, and the
// recorded run carries the flame's own colour as a stroke instead of a word saying so.
ck("streak layout draws no label, at any hour",
   !frame(mxSpec("candle", "open", 12, mbase)).includes('class="lbl"') &&
   !frame(mxSpec("candle", "done", 23, mbase)).includes('class="lbl"'), "lbl present");
ck("flame and run share one runrow",
   /<div class="runrow[^"]*"[^>]*><svg[^>]*class="fl"[\s\S]*?<\/svg><span class="fig/.test(
     frame(mxSpec("candle", "open", 12, mbase))), "not on one row");
ck("the unlit run has no recorded border",
   !frame(mxSpec("candle", "open", 12, mbase)).includes('class="fig recorded"'), "has one");
ck("the recorded run carries the border class",
   frame(mxSpec("candle", "done", 23, mbase)).includes('class="fig recorded"'), "missing");

// The glass treatment: on for an unrecorded tile with a real ground, off for flat and off
// once recorded (which already has its own answer -- the border). The CSS text itself
// (Comic Relief's font-face, the !important fix for the specificity fight with
// `.fr.typed .fig`, the widened stroke, and the white fill) is checked in Python below,
// where the raw HTML is already in scope -- it lives in <style>, outside the <script>
// block this file executes.
ck("glass is on for an unrecorded, grounded hour",
   frame(mxSpec("stages", "open", 16, mbase)).includes('class="runrow glass"'), "not glassy");
ck("glass is off on the flat ramp -- nothing to be glassy over",
   !frame(mxSpec("flat", "open", 16, mbase)).includes("glass"), "glassy anyway");
ck("glass is off once recorded, in favour of the border",
   !frame(mxSpec("stages", "done", 23, mbase)).includes("glass") &&
   frame(mxSpec("stages", "done", 23, mbase)).includes("recorded"), "both or neither");
ck("main's book layout never goes glassy",
   !frame({ family: "small", jacket: "#e9ecef", flame: "unlit", run: 3, groundStyle: groundVars("#000","#000",false) }).includes("glass"),
   "book layout picked it up");
ck("main's book layout is untouched -- still a label, no border class",
   frame({ family: "small", jacket: "#e9ecef", flame: "lit", run: 4, label: LABEL })
     .includes('class="lbl"'), "label dropped from main too");
ck("recorded uses the radial glow",
   (mxSpec("candle", "done", 23, mbase).groundStyle || "").includes("radial"), "not radial");
// The ground is a layered mesh now, not a single gradient. Three treatments were built
// and compared as real CSS in _ground_bakeoff.html; these pin what the winner is made of,
// because "looks richer" is not a thing a verifier can check but "has six layers, a
// diagonal base and a vignette" is.
{
  const open = mxSpec("candle", "open", 12, mbase).groundStyle || "";
  const done = mxSpec("candle", "done", 23, mbase).groundStyle || "";
  ck("the open ground is a mesh of several layers",
     (open.match(/gradient\(/g) || []).length >= 4,
     (open.match(/gradient\(/g) || []).length + " gradient layers");
  // The base is DIAGONAL. A vertical two-stop wash is what this replaced and is the
  // specific thing that read as a flat card, so the angle is asserted rather than the
  // mere presence of a linear-gradient.
  ck("the mesh's base layer is diagonal, not a vertical wash",
     /linear-gradient\(158deg,/.test(open) && !/linear-gradient\(#/.test(open), open.slice(0, 60));
  ck("the light sits upper-left rather than dead centre",
     /at 16% 10%/.test(open), "no upper-left lift");
  ck("there is an accent hue upper-right", /at 88% 22%/.test(open), "no accent");
  ck("the corners are vignetted", /at 50% 40%/.test(open) && /rgba\(0,0,0,\.36\)/.test(open),
     "no vignette");
  ck("and the gradient is dithered with grain",
     /var\(--grain\)/.test(open), "no grain layer");
  // The mesh's three blobs sit at a chosen alpha over the base. The value is pinned
  // because both ends of the range are visibly wrong and neither is a syntax error:
  // at 1 the accent is a separate blob on a differently coloured tile, and below ~0.2
  // the six layers cost nothing but a plain diagonal. Chosen by eye in
  // _mesh_blend.html, which renders the same tile at seven strengths.
  ck("all three mesh blobs are at the chosen alpha, not full opacity",
     (open.match(/rgba\([0-9]+,[0-9]+,[0-9]+,0\.3\)/g) || []).length === 3,
     (open.match(/rgba\([0-9]+,[0-9]+,[0-9]+,0\.3\)/g) || []).join(" ") || "none at 0.3");
  // Asserted as an absence too: a blob whose 0% stop is a bare hex is a blob at full
  // opacity, which is the state this replaced.
  ck("no mesh blob starts from an opaque hex",
     !/radial-gradient\([^)]*, ?#[0-9a-f]{6} 0%/i.test(open), "one is opaque");
  // The grain's data URI must NOT be inline. It contains double quotes, and groundStyle
  // is emitted into style="...", so inlining it silently killed the whole background
  // declaration and every stages tile rendered as bare white. Asserted as an absence so
  // the regression cannot come back quietly.
  ck("no ground inlines a quote that would break the style attribute",
     !open.includes('"') && !done.includes('"'), "a quote is inline");
  // The accent is the ramp read three hours later, so it must actually DIFFER from the
  // hour's own top -- otherwise the mesh has collapsed back to one hue and the layers
  // are decoration with nothing in them.
  {
    const now = rampAt("stages", 12)[0].toLowerCase();
    const ahead = rampAt("stages", 15)[0].toLowerCase();
    ck("the mesh accent is a genuinely different colour from the hour",
       now !== ahead, now + " vs " + ahead);
  }
  // Recorded is deliberately NOT a mesh: its single bottom-up radial is the Library
  // Card's light-from-below and means something specific.
  ck("recorded keeps its single bottom-up radial",
     /at 50% 112%/.test(done) && (done.match(/gradient\(/g) || []).length === 1,
     done.slice(0, 60));
}
ck("recorded ignores the hour",
   mxSpec("stages", "done", 7, mbase).groundStyle === mxSpec("stages", "done", 23, mbase).groundStyle,
   "hour leaked in");
ck("no-run is not a figure of zero", !!mxSpec("flat", "none", 21, mbase).nothing, "no nothing copy");
ck("no-run borrows the 21:00 unrecorded ground",
   mxSpec("stages", "none", 21, mbase).groundStyle === mxSpec("stages", "open", 21, mbase).groundStyle,
   "its own ground");
ck("no-run carries no label", mxSpec("flat", "none", 21, mbase).label === "", "labelled");

// ---- The reading shelf ----------------------------------------------------
// The shelf's whole defence is that it is not a new drawing: every number comes out of
// card_shelf_plan.dart, which solved the leaning shelf for the Library Card. So what is
// asserted here is the derivation, not the appearance -- if the read pile's spine changes
// shape, the card's overlap moves and this has to move with it.
const shbase = { copy:"duoLike", under:"shelf-noline", type:"typed", core:"grey", family:"small" };
ck("the reading shelf is a real set, ordered", READING.length >= 4, String(READING.length));
ck("the fixture keeps the near-white jacket",
   READING.some((b) => b.jacket.toUpperCase() === "#FDFDFB"), JSON.stringify(READING.map(b=>b.jacket)));
ck("cover aspect is the app's", Math.abs(COVER_ASPECT - 2/3) < 1e-9, String(COVER_ASPECT));
ck("the lean step is a spine's width", Math.abs(SPINE_RATIO - 26/124) < 1e-9, String(SPINE_RATIO));
ck("the title floor is kGeneratedCoverMinWidth",
   Math.abs(COVER_TITLE_FLOOR - 7/0.135) < 1e-9, COVER_TITLE_FLOOR.toFixed(2));
// The number that decides what this shelf can be: a cover in a 130pt tile is far under the
// width at which a cover's own title is worth drawing, so these are colour blocks by the
// app's own rule rather than by omission.
ck("a widget cover is well under the title floor",
   38 * COVER_ASPECT < COVER_TITLE_FLOOR / 2,
   (38 * COVER_ASPECT).toFixed(1) + "pt vs floor " + COVER_TITLE_FLOOR.toFixed(1));
const sh = shelf(READING, 38, 4);
ck("the shelf draws a board", sh.includes('class="board"'), "no board");
ck("the shelf draws four covers, not five",
   (sh.match(/class="jk"/g) || []).length === 4, String((sh.match(/class="jk"/g) || []).length));
ck("the shelf states what it is not showing", /class="plate">\+1</.test(sh), "no plate");
ck("no shelf cover carries a title", !/class="ttl"/.test(sh), "title drawn");
// depth: higher is nearer the front, leftmost whole. Painted with descending z-index so the
// first book is the one on top -- the card's documented reason is that the leftmost is the
// one that survives a crop.
const zs = [...sh.matchAll(/z-index:(\d+)/g)].map((m) => Number(m[1]));
ck("leftmost cover is nearest the front",
   zs.length === 4 && zs.every((z, i) => i === 0 || z < zs[i - 1]), JSON.stringify(zs));
const lefts = [...sh.matchAll(/left:([\d.]+)px/g)].map((m) => Number(m[1]));
ck("covers advance by exactly the spine step",
   lefts.length === 4 && lefts.every((l, i) => Math.abs(l - i * Math.round(SPINE_RATIO * 38 * 10) / 10) < 0.05),
   JSON.stringify(lefts));
// Nothing is ever squeezed: past capacity the step must not tighten, the plate must appear.
const shMany = shelf(READING.concat(READING), 38, 4);
const leftsMany = [...shMany.matchAll(/left:([\d.]+)px/g)].map((m) => Number(m[1]));
ck("a bigger library does not shrink the step",
   JSON.stringify(leftsMany) === JSON.stringify(lefts), JSON.stringify(leftsMany));
ck("a bigger library raises the count instead", /class="plate">\+6</.test(shMany), "wrong plate");
ck("one open book needs no plate and no overlap",
   !shelf([READING[0]], 38, 4).includes('class="plate"') &&
   [...shelf([READING[0]], 38, 4).matchAll(/left:([\d.]+)px/g)].length === 1, "overlapped");
ck("an empty reading shelf draws nothing", shelf([], 38, 4) === "", "drew something");

// The trade the axis exists to make visible: a shelf and a two-line status sentence are
// competing for the same 130pt, so one variant keeps the line and shrinks the covers and the
// other keeps the covers and drops the line.
const withLine = mxSpec("candle", "open", 12, { ...shbase, under:"shelf" });
const noLine = mxSpec("candle", "open", 12, { ...shbase, under:"shelf-noline" });
ck("shelf-with-line keeps the line", !!withLine.line, "line dropped");
ck("shelf-with-line pays for it in cover height", withLine.coverH < noLine.coverH,
   withLine.coverH + " vs " + noLine.coverH);
ck("shelf-no-line drops the line", noLine.line === "", noLine.line);
ck("both draw the shelf",
   frame(withLine).includes('class="shelf"') && frame(noLine).includes('class="shelf"'), "missing");
ck("the week option still trades the line away too",
   mxSpec("candle", "open", 12, { ...shbase, under:"week" }).line === "", "kept the line");
ck("nothing-under is still the plain tile",
   !frame(mxSpec("candle", "open", 12, { ...shbase, under:"none" })).includes('class="shelf"'),
   "shelf leaked");
ck("the shelf survives being recorded",
   frame(mxSpec("candle", "done", 23, shbase)).includes('class="shelf"'), "dropped");

// **The finding this axis exists to make unavoidable.** A true spine step at widget scale is
// thinner than the sliver card_shelf_plan.dart already rejected: that file records "one shrank
// the overlap step until covers were 9.4pt slivers" as a refused design, and a 30pt cover's
// spine step is 6.3pt. Pinned as an assertion rather than left in a comment, because it is
// the argument against the thing that was asked for and it should not quietly go away.
const SLIVER_FLOOR = 9.4; // the rejected width, card_shelf_plan.dart's own record
ck("the leaning step at 30pt is thinner than the rejected sliver",
   SPINE_RATIO * 30 < SLIVER_FLOOR, (SPINE_RATIO * 30).toFixed(2) + "pt");
ck("and at 38pt it is still thinner",
   SPINE_RATIO * 38 < SLIVER_FLOOR, (SPINE_RATIO * 38).toFixed(2) + "pt");
// Which matters only because the tile is not short of width. The card leaned to save width;
// this tile has width to spare at four books and is short of height instead.
const INTERIOR = 158 - 2 * 14; // 130pt, the small tile's interior
const apartSpan = (h, n) => n * Math.round(h * COVER_ASPECT) + (n - 1) * 3;
ck("four covers fit standing apart, no overlap needed",
   apartSpan(38, 4) < INTERIOR, apartSpan(38, 4) + "pt of " + INTERIOR);
ck("five do not, which is where leaning starts to pay",
   apartSpan(38, 5) > INTERIOR, apartSpan(38, 5) + "pt of " + INTERIOR);
ck("leaning four wastes most of the width it saved",
   Math.round(38 * COVER_ASPECT) + 3 * (SPINE_RATIO * 38) < INTERIOR / 2,
   (Math.round(38 * COVER_ASPECT) + 3 * (SPINE_RATIO * 38)).toFixed(1) + "pt of " + INTERIOR);
// The two settings are the card's own, picked by count rather than taste.
const shApart = shelf(READING, 38, 4, "apart");
const apartLefts = [...shApart.matchAll(/left:([\d.]+)px/g)].map((m) => Number(m[1]));
ck("standing apart, no cover is hidden",
   apartLefts.every((l, i) => i === 0 || l - apartLefts[i - 1] >= Math.round(38 * COVER_ASPECT)),
   JSON.stringify(apartLefts));
ck("leaning, every cover but the first is mostly hidden",
   lefts.every((l, i) => i === 0 || l - lefts[i - 1] < Math.round(38 * COVER_ASPECT) / 2),
   JSON.stringify(lefts));
ck("apart is wider than leaning for the same books",
   apartLefts[3] > lefts[3], apartLefts[3] + " vs " + lefts[3]);
ck("the apart option reaches the axis",
   AXES.under.options.some(([k]) => k === "shelf-apart"),
   JSON.stringify(AXES.under.options.map(([k]) => k)));
ck("apart still overflows to a plate rather than squeezing",
   /class="plate">\+1</.test(shApart), "no plate");

// And the grid itself renders, which is the one path the DOM stub can reach.
let mxThrew = null;
try { renderMatrix(); } catch (err) { mxThrew = String(err); }
ck("renderMatrix runs", mxThrew === null, String(mxThrew));

console.log(JSON.stringify(out));
"""

with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as fh:
    fh.write(STUB + js + CHECKS)
    path = fh.name

check = subprocess.run(["node", "--check", path], capture_output=True, text=True)
print("parses:", "ok" if check.returncode == 0 else "FAILED")
if check.returncode != 0:
    sys.exit(check.stderr)

run = subprocess.run(["node", path], capture_output=True, text=True)
if run.returncode != 0:
    sys.exit("load-time error:\n" + run.stderr[-2000:])

last = [ln for ln in run.stdout.strip().splitlines() if ln.startswith("{")][-1]
result = json.loads(last)
print(f"assertions: {len(result['ok'])} passed, {len(result['bad'])} failed")
for bad in result["bad"]:
    print("  FAIL", bad)

# The fonts are the point of the `typed` variant, and a broken relative path would
# silently fall back to a system face -- which is exactly the state being fixed, so the
# page would look "fixed" while proving nothing.
#
# Data URIs are excluded: the mesh's grain layer is an inline SVG in a url(), and it is
# not a file, so resolving it against the directory reported it permanently missing.
fonts = [
    f for f in re.findall(r'url\("([^"]+)"\)', html) if not f.startswith("data:")
]
missing = [f for f in fonts if not (pathlib.Path(SRC).parent / f).exists()]
print(f"fonts referenced: {len(fonts)}, missing: {len(missing)}")
for f in missing:
    print("  MISSING", f)

# The cut-outs the page names and the cut-outs on disk have to be the same set. The JS
# half of this file asserts every `poses` entry is in CUTOUTS; this half asserts CUTOUTS
# is the directory, which is the join that makes both halves mean something. Without it a
# rename in `cats/` would leave the page naming a drawing that is not there, and the only
# symptom would be a broken image in a grid nobody thought to re-screenshot.
cut_declared = re.search(r"const CUTOUTS = \[(.*?)\];", html, re.S)
if not cut_declared:
    print("  MISSING CUTOUTS declaration")
else:
    declared = set(re.findall(r'"([^"]+)"', cut_declared.group(1)))
    on_disk = {p.stem for p in (pathlib.Path(SRC).parent / "cats").glob("*.png")}
    print(f"cut-outs declared: {len(declared)}, on disk: {len(on_disk)}")
    for name in sorted(declared - on_disk):
        print("  DECLARED BUT ABSENT", name)
    for name in sorted(on_disk - declared):
        print("  ON DISK BUT UNDECLARED", name)

# ---- CSS text ---------------------------------------------------------------------
# Comic Relief, the widened stroke, and the white fill live in <style>, outside the
# <script> block the checks above run against -- so they are asserted here, on `html`
# directly, rather than inside the JS harness which has no access to it.
py_bad = []


def pyck(name, cond, got=""):
    if not cond:
        py_bad.append(f"{name} -> {got}")


pyck(
    "Comic Relief is loaded from this mockup's own fonts, not assets/fonts",
    re.search(r'@font-face\s*\{\s*font-family:\s*"Comic Relief"', html) is not None
    and 'url("fonts/ComicRelief-Bold.ttf")' in html,
)
pyck(
    "Nunito is loaded from this mockup's own fonts, not assets/fonts",
    re.search(r'@font-face\s*\{\s*font-family:\s*"Nunito"', html) is not None
    and 'url("fonts/Nunito.ttf")' in html,
)
# The OFL requires the licence to travel with the font file, so the file's presence
# is part of vendoring it correctly rather than housekeeping.
pyck(
    "Nunito ships its OFL licence alongside it",
    (SRC.rsplit("/", 1)[0] + "/fonts/OFL-Nunito.txt") and pathlib.Path("docs/mockups/streak-widget/fonts/OFL-Nunito.txt").exists(),
)
fig_recorded = (re.search(r"\.fig\.recorded\s*\{([^}]*)\}", html) or [None, ""])[1] if re.search(r"\.fig\.recorded\s*\{([^}]*)\}", html) else ""
pyck("the recorded rule names Nunito", "Nunito" in fig_recorded, fig_recorded)
# Every number, recorded or not, is the same face -- the recorded tile differs by
# stroke and weight, not by typeface. Comic Relief was the earlier answer here and is
# kept only as a switched-off @font-face, so nothing may still reference it.
pyck(
    "nothing still sets Comic Relief on a figure",
    "Comic Relief" not in fig_recorded,
    fig_recorded,
)
pyck(
    "the recorded rule's font properties are !important",
    "font-family" in fig_recorded
    and "!important" in fig_recorded.split("font-family")[1].split(";")[0]
    and "font-weight" in fig_recorded
    and "!important" in fig_recorded.split("font-weight")[1].split(";")[0],
    fig_recorded,
)
# .fr.typed .fig is three class selectors (0,3,0); .fig.recorded alone is two (0,2,0) and
# loses on specificity regardless of source order -- !important is what wins it back, and
# this file has no browser to compute the real cascade, so it is checked structurally: the
# losing rule must NOT also carry !important, or the fix cancels itself out.
typed_fig = (re.search(r"\.fr\.typed \.fig \{([^}]*)\}", html) or [None, ""])[1] if re.search(r"\.fr\.typed \.fig \{([^}]*)\}", html) else ""
pyck(
    "that actually beats .fr.typed .fig on specificity",
    "!important" in fig_recorded and "!important" not in typed_fig,
    "recorded=" + repr(fig_recorded)[:80] + " typed=" + repr(typed_fig)[:80],
)
pyck(
    "the stroke widened past the first pass's 3px",
    re.search(r"-webkit-text-stroke:\s*6px var\(--flame\)", fig_recorded) is not None,
    fig_recorded,
)
pyck("the fill is white, not the ground's ink", re.search(r"color:\s*#ffffff", fig_recorded, re.I) is not None, fig_recorded)
glass_rule = (re.search(r"\.runrow\.glass\s*\{([^}]*)\}", html) or [None, ""])[1] if re.search(r"\.runrow\.glass\s*\{([^}]*)\}", html) else ""
pyck(
    "glass is a plain opacity on the row, not a new colour",
    re.fullmatch(r"\s*opacity:\s*0\.5;?\s*", glass_rule) is not None,
    repr(glass_rule),
)

print(f"CSS-text assertions: {len(py_bad) == 0 and 'all passed' or f'{len(py_bad)} failed'}")
for bad in py_bad:
    print("  FAIL", bad)

sys.exit(1 if result["bad"] or missing or py_bad else 0)
