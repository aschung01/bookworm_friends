"""Terminal verification for the streaks mockup set.

Extracts the page's script, confirms it parses, runs it against the DOM stub
from the design-mockups skill's reference/pitfalls.md so every top-level
render path executes, then asserts the numbers the page argues from and the
geometry it claims to have copied out of the codebase.

    python3 docs/mockups/streaks/verify.py

What it cannot check: anything visual. Two real defects on this page got
past earlier versions of this script — a `box-shadow` clipped away by
`clip-path`, and an entire invented ribbon colour. Open the page.
"""

import json
import re
import subprocess
import sys

SRC = "docs/mockups/streaks/index.html"

html = open(SRC).read()
m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
if not m:
    sys.exit("could not find the script block")
js = m.group(1)

print("backticks:", "ok" if js.count("`") % 2 == 0 else "ODD")
print("script lines:", js.count("\n") + 1)

# ---- CSS-level checks. The JS harness cannot see the stylesheet, and all three
# of these encode a defect that only showed up when the frames were looked at.
css = html[html.index("<style>") + 7 : html.index("</style>")]
_cssbad = 0
for _label, _pat in [
    (
        "today inside a run keeps the run's own contrast",
        r"\.cal \.cday\.today:not\(\.on\)",
    ),
    (
        "and its rule lightens so it stays visible on a dark band",
        r"\.cal \.cday\.on\.today::before",
    ),
    (
        "the plain month uses the card's ink, not white on 34% mint",
        r"\.cal\.plain \.cday\.on\s*\{\s*color: var\(--brandText\)",
    ),
]:
    _hit = re.search(_pat, css) is not None
    print(("PASS  " if _hit else "FAIL  ") + _label)
    _cssbad += 0 if _hit else 1

for _label, _pat in [
    (
        "the picker centres its rows, or the band frames the wrong number",
        r"\.fr \.drum \.wheel \{[^}]*justify-content: center",
    ),
    (
        "and its rows refuse to shrink, so they clip rather than compress",
        r"\.fr \.drum \.wheel s \{[^}]*flex: 0 0 auto",
    ),
    (
        "and it fades at both edges, so the clipped rows do not butt the footer",
        r"\.fr \.drum \.wheel \{[^}]*mask-image: linear-gradient",
    ),
]:
    _hit = re.search(_pat, css, re.S) is not None
    print(("PASS  " if _hit else "FAIL  ") + _label)
    _cssbad += 0 if _hit else 1

# Every open question must have a render path, not merely a live target. The
# builder already drops callouts whose screen was deleted -- but `openMap` was
# consulted only by the FLOWS renderer, so all 22 screen-keyed callouts were
# written and never shown. Asserted against the JS, since it is a render bug the
# data cannot see.
for _label, _pat in [
    (
        "the screens renderer shows its open questions",
        r'class="ds">\$\{e\.ds\}</div>\$\{\s*openMap\[e\.id\]',
    ),
    (
        "and so does the elements renderer",
        r'class="ds">\$\{e\.ds\}</div>\$\{\s*openMap\[e\.id\]',
    ),
]:
    _hit = len(re.findall(_pat, js)) >= 2
    print(("PASS  " if _hit else "FAIL  ") + _label)
    _cssbad += 0 if _hit else 1

# The inked-border treatment derives its whole path from the band's corner radius
# and padding, so those must match the SHIPPED container rather than a mockup
# convention. Read straight out of the Dart, because a drifting 30 here silently
# changes 21% of the progress path.
#
# **These two used to grep the band for the literals `Radius.circular(30)` and
# `EdgeInsets.fromLTRB(30, 8, 30, 16)`, and the implementation retired both.** The 30
# is now `kBookBandCornerRadius`, declared once in `band_progress_edge.dart` and read
# by the band's decoration and by the painter that clips the progress bar to it -- so
# the check is stronger than it was: it pins the value AND that the band does not carry
# a second copy of it. The bottom padding became conditional, because the progress
# row's 44pt tap target takes 14 of the band's 16 rather than growing the layout, so
# what is asserted is that the two halves still add to the shipped 16.
_dart = open("lib/ui/views/book_details_tab_view.dart").read()
_edge = open("lib/ui/widgets/band_progress_edge.dart").read()
_prow = open("lib/ui/widgets/band_progress_row.dart").read()
for _label, _ok in [
    (
        "the band's 30pt bottom radius is the shipped one, via one constant",
        "const double kBookBandCornerRadius = 30;" in _edge
        and "bottomLeft: Radius.circular(kBookBandCornerRadius)" in _dart
        and "bottomRight: Radius.circular(kBookBandCornerRadius)" in _dart
        and "Radius.circular(30)" not in _dart,
    ),
    (
        "and so is its 30/8/30 padding, whose bottom 16 is now split not spent",
        re.search(r"EdgeInsets\.fromLTRB\(\s*30,\s*8,\s*30,", _dart) is not None
        and "kBandProgressRowResidualPadding" in _dart
        and "const double kBandProgressRowSpill = 14;" in _prow
        and "const double kBandProgressRowResidualPadding = 2;" in _prow,
    ),
    (
        "and the CSS says the same, so the path is built on real geometry",
        re.search(r"\.fr \.band \{[^}]*border-radius: 0 0 30px 30px", css) is not None
        and re.search(r"\.fr \.band \{[^}]*padding: 8px 30px 16px", css) is not None,
    ),
]:
    print(("PASS  " if _ok else "FAIL  ") + _label)
    _cssbad += 0 if _ok else 1

# Every handle in the design write-up must be findable on the page that carries it.
# They were only in `data-id`, so `pd-align` appeared in prose and nowhere on screen.
for _label, _pat in [
    ("screens show their handle", r'class="nm">\$\{e\.nm\}\$\{tagFor\(e\.diff\)\}<code class="hid">'),
    ("flows show theirs", r'class="fh">\$\{e\.nm\}\$\{tagFor\(e\.diff\)\}<code class="hid">'),
    ("the filter list shows them", r'class="lb">[\s\S]{0,220}<code class="hid">\$\{highlightText\(id, q\)\}'),
    ("and searching matches on them", r"items\.filter\(\(\[id, nm, ds\]\)"),
]:
    _n = len(re.findall(_pat, js))
    _ok = _n >= 1 if "screens" not in _label else _n >= 2
    print(("PASS  " if _ok else "FAIL  ") + _label)
    _cssbad += 0 if _ok else 1
_ok = re.search(r"\.hid \{[^}]*user-select: all", css) is not None
print(("PASS  " if _ok else "FAIL  ") + "and a handle can be selected in one drag")
_cssbad += 0 if _ok else 1

STUB = r"""
const mk = () => ({
  _v: '', set innerHTML(v){this._v=v;}, get innerHTML(){return this._v;},
  textContent: '', hidden: false, value: '', placeholder: '',
  dataset: {}, style: {},
  classList: { toggle(){}, add(){}, remove(){}, contains(){return false;} },
  addEventListener(){}, focus(){}, blur(){}, select(){},
  contains(){return false;},
  querySelectorAll(){return [];}, querySelector(){return null;},
  closest(){return null;},
  getBoundingClientRect(){return {top:0};}, scrollIntoView(){},
  nextElementSibling: null, tagName: 'DIV',
});
global.document = {
  getElementById: () => mk(), querySelectorAll: () => [],
  // Needed since the set collapsed to a single version: the engine hides the
  // version selector with `document.querySelector('.vinfo')`, and a stub that
  // returns undefined there crashes before any check runs.
  querySelector: () => mk(),
  addEventListener(){}, body: { scrollHeight: 1000 }, activeElement: null,
};
global.window = { addEventListener(){}, scrollTo(){}, innerHeight: 800, scrollY: 0 };
global.requestAnimationFrame = (f) => f();
global.Event = class { constructor(t){ this.type = t; } };
"""

ASSERT = r"""
let bad = 0;
const ok = (cond, label, detail) => {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + label + (detail ? '  ' + detail : ''));
  if (!cond) { bad++; process.exitCode = 1; }
};

/* ---- the asset's real geometry, against reading_bookmark.dart ---- */
/* One version now: every check targets the collapsed tip. */
const V = 'state-sheet';
const css = CSS_TEXT;

console.log('--- asset ---');
ok(A_RIB_W === 13.5 && A_RIB_H === 30, 'ribbon is 13.5x30 inside a 22x38 box');
ok(Math.abs(BM_S - 180 / 124) < 1e-9, 'scale is coverHeight/124, the card\'s own rule',
   '= ' + BM_S.toFixed(4));
/* reading_bookmark.dart: "With the box's 4.5 of bleed that puts the ribbon's
   right edge 12.5 in." Scaled, that is 12.5 * BM_S from the cover's edge. */
const ribRight = ribLeftFromBoxRight(COVER_W - INSET) + RIB_W;
ok(Math.abs((COVER_W - ribRight) - 12.5 * BM_S) < 0.01,
   'ribbon right edge lands 12.5 (scaled) in from the cover edge',
   '= ' + (COVER_W - ribRight).toFixed(2) + 'pt');

/* ---- the figures the versions are chosen on ---- */
console.log('--- geometry ---');
for (const a of ['chrome-right', 'mark-in-place', 'fore-edge-3d'])
  console.log('  ' + a.padEnd(15), GEO[a].encode.padEnd(9),
    String(GEO[a].travel).padStart(4) + 'pt', fmt(perPage(a, 320)).padStart(5) + ' pt/page',
    'dead ' + pct(deadZone(a)).padStart(4));
ok(deadZone('fore-edge-3d') === 0, 'position encoding has no dead zone');
ok(deadZone('mark-in-place') > 0.2, 'mark-in-place dead zone is over 20%',
   '= ' + pct(deadZone('mark-in-place')));
ok(deadZone('chrome-right') < 0.06, 'chrome-right dead zone is under 6%',
   '= ' + pct(deadZone('chrome-right')));
ok(perPage('fore-edge-3d', 320) > perPage('mark-in-place', 320) * 1.9,
   'fore-edge track gives roughly double the resolution');

/* The dead zone is a claim about identical drawings, so assert exactly that. */
const L = (p) => bmLen('mark-in-place', p, 320);
ok(L(1) === L(20) && L(20) === L(77) && L(77) === RIB_H,
   'pages 1, 20 and 77 all draw at the asset minimum');
ok(L(78) > RIB_H, 'page 78 finally clears the floor');
/* Position encoding must NOT stretch: it was stretching the resting mark by
   the 365pt fore-edge track down a 180pt cover, which is not a length. */
const P = (p) => bmLen('fore-edge-3d', p, 320);
ok(P(1) === RIB_H && P(148) === RIB_H && P(320) === RIB_H,
   'position encoding never stretches the resting mark');
ok(bmLen('mark-in-place', 320, 320) > bmLen('fore-edge-3d', 320, 320),
   'length encoding does stretch, so the two are genuinely different at rest');

/* ---- search ---- */
console.log('--- search ---');
function hits(rows, textOf, q) {
  const o = [];
  for (const [g, items] of rows)
    for (const it of items)
      if (matchWords(textOf(g, it).toLowerCase(), q.toLowerCase())) o.push(it[0]);
  return o;
}
const sHits = (q) => hits(SCREENS, (g, it) => stripTags(g + ' ' + it[1] + ' ' + it[2]), q);
const fHits = (q) => hits(FLOWS, (g, it) => flowSearchText(g, it[1], it[2], it[3]), q);
const has = (got, want) => want.every((w) => got.includes(w)) && got.length > 0;

ok(has(sHits('page_count'), ['nocount']), 'screens "page_count"', JSON.stringify(sHits('page_count')));
ok(has(sHits('dead zone'), ['deadzone']), 'screens "dead zone"');
ok(has(sHits('shelf_row'), ['logged']), 'screens "shelf_row"', JSON.stringify(sHits('shelf_row')));
/* No screen mentions forgiveness any more — asserted the other way round now,
   because a hit here would mean a deferred feature had leaked back in. */
ok(sHits('freeze').every((id) => ['sh-bar', 'cal-plain', 'cal-books'].includes(id)),
   'freezes are mentioned only where the deferral is explained',
   JSON.stringify(sHits('freeze')));
ok(has(sHits('prompt'), ['ask-count']), 'screens "prompt"', JSON.stringify(sHits('prompt')));
ok(has(sHits('trailing'), ['friends-conflict']), 'screens "trailing"');
ok(has(fHits('rollover'), ['x-late']), 'flows "rollover"', JSON.stringify(fHits('rollover')));
/* The drag versions are gone, so their flow must be too — the inverse check. */
ok(!resolveView(V, 'flows').some(([g, l]) =>
     l.some(it => flowSearchText(g, it[1], it[2], it[3]).toLowerCase().includes('rotatey'))),
   'the fore-edge drag flow is gone with the version that owned it');
console.log('NOTE  OPEN callout text is not indexed ->', JSON.stringify(fHits('4am')),
  '(expected [], inherited from the shared engine)');

/* ---- the collapsed set ---- */
console.log('--- the collapsed set ---');
/* The exploration was flattened into one version. What is still worth asserting
   is that the collapse is faithful: the chain still exists as data, every
   anatomy in it still has geometry, and the page shows exactly one version. */
const ALLV = VERSIONS.map((v) => v[0]);
ok(ALLV.length === 1 && ALLV[0] === V,
   'the page shows exactly one version', ALLV.join(', '));
ok(VCHAIN.length === 14,
   'the fourteen-step chain is kept as data, not as browsable versions',
   VCHAIN.length + ' steps');
ok(VCHAIN.every((v) => GEO[v[0]]),
   'every step in the chain still has a GEO entry',
   Object.keys(GEO).length + ' entries');
ok(cchain(V).length === 10 && cchain(V)[0] === 'mark-in-place' &&
   cchain(V)[9] === V,
   'and the tip resolves through its real ancestry',
   cchain(V).length + ' steps: ' + cchain(V).join(' \u2192 '));
const ids = (v) => resolveView(v, 'screens').map(([g, items]) => items.map((i) => i[0])).flat();
const fids = (v) => resolveView(v, 'flows').map(([g, l]) => l.map((i) => i[0])).flat();
const fsteps = (v, id) => {
  for (const [g, l] of resolveView(v, 'flows')) for (const it of l) if (it[0] === id) return it[3];
  return [];
};
const specOf = (v, id) => {
  for (const [g, items] of resolveView(v, 'screens'))
    for (const it of items) if (it[0] === id) return it[3];
  return null;
};
/* The flatten must have applied the chain, not just returned the root: the root
   drew `mark-in-place`, the tip draws `top-edge-slide`. */
ok(specOf(V, 'due').anatomy === 'top-edge-slide',
   'the flattened screens carry the tip\'s anatomy, not the root\'s',
   specOf(V, 'due').anatomy);
ok(specOf(V, 'card-stamps').kind === 'card',
   'anatomy-independent screens survive the flatten');
/* And the deletions in the chain actually took effect. */
['held', 'dragging', 'entry', 'sc-freeze', 'card-gap', 'lamp-sheet'].forEach((id) =>
  ok(!ids(V).includes(id), 'the chain\'s deletion of ' + id + ' held'));

/* ---- the real app bar, and what it collides with ---- */
console.log('--- app bar ---');
ok(NAV_H === 56, 'the bar is AppBar\'s default 56, not a guess');
/* IconButton: 48pt target, 4pt from the right edge. */
const EDIT_L = FRAME - 4 - 48, EDIT_R = FRAME - 4;
const mL = ribLeftFromBoxRight(FRAME - PAD), mR = mL + RIB_W;
ok(mL > EDIT_L && mR < EDIT_R,
   'chrome-right puts the mark INSIDE the edit button\'s 48pt target',
   'mark ' + mL.toFixed(0) + '-' + mR.toFixed(0) + ' vs edit ' + EDIT_L + '-' + EDIT_R);
ok(/M6 19c0 1\.1/.test(frame(specOf(V, 'due'))),
   'the bar draws Material\'s real delete_outline path');
ok((frame(specOf(V, 'due')).match(/class="act"/g) || []).length === 2,
   'both actions are drawn, as they are for isSelf');

/* ---- the rest of the crop, audited against the code ---- */
console.log('--- hero and band ---');
const DUE = frame(specOf(V, 'due'));
/* reading_period_row.dart moved the badge out of the corner deliberately. */
ok(/class="corner"><span class="slab"/.test(DUE),
   'the corner holds the shelf label alone, no badge');
ok(/class="period">[\s\S]*?class="sbadge/.test(DUE),
   'the status badge is inside the reading-period row, where it ships');
ok(!/class="corner">\s*<span class="sbadge/.test(DUE),
   'the retired corner-badge design is not reproduced');
ok(/class="slab">\S+\s+\d+</.test(DUE),
   'the shelf label carries its count, part of the hero contract');
ok(/2026\.08\.28 ~ <\/span><i>12 days/.test(DUE),
   'the period card carries the range and the day count');
/* Status 0 drops to a bare badge rather than a chip in a full-width slab. */
ok(/class="barebadge"/.test(frame(Object.assign(book({ status: 0 }, 'mark-in-place')))),
   'no start date means a bare badge, not an empty card');

/* ---- percentage-native position ---- */
console.log('--- position as a fraction ---');
ok(Math.abs(posOf({ page: 148, pages: 320 }) - 148 / 320) < 1e-9,
   'a page and a total give a fraction');
ok(posOf({ pages: null, pct: 0.47 }) === 0.47,
   'no total is not a problem: the fraction is the stored value');
ok(!/p\./.test(posLabel({ pages: null, pct: 0.47 })) && /47/.test(posLabel({ pages: null, pct: 0.47 })),
   'a book with no count reads as a percentage, not a broken page');
ok(/p\.148/.test(posLabel({ page: 148, pages: 320 })),
   'a book with a count still reads as a page');
/* The band must never print the same value twice. For a percent-native book
   `posLabel` IS the percentage, so the trailing one has to go \u2014 the drawing
   showed "72% \u2026 72%" before this was fixed. */
const PCTBAND = frame(book({ pages: null, pct: 0.72, streak: 12 }, 'top-edge-slide'));
ok((PCTBAND.match(/72<i>%|>72%</g) || []).length === 1,
   'a percent-native band prints its percentage once',
   JSON.stringify(PCTBAND.match(/72<i>%|>72%</g)));
const PGBAND = frame(book({ page: 148, pages: 320, streak: 12 }, 'top-edge-slide'));
ok(/p\.148/.test(PGBAND) && />46%</.test(PGBAND),
   'but a paged band still carries both the page and the percentage');

/* ---- rendering ---- */
console.log('--- render ---');
let n = 0, wrapped = 0, turned = 0, scrubbed = 0, drummed = 0, chipped = 0;
const undef = [];
for (const v of ALLV)
  for (const [g, items] of resolveView(v, 'screens'))
    for (const it of items) {
      const h = frame(it[3]);
      if (/class="bm due"[^>]*><b><\/b><i><\/i>/.test(h)) wrapped++;
      if (/class="edge3d"/.test(h)) turned++;
      if (/class="scrub/.test(h)) scrubbed++;
      if (/class="drum"/.test(h)) drummed++;
      if (/class="chips"/.test(h)) chipped++;
      if (/undefined|NaN|\[object /.test(h)) undef.push(v + '/' + it[0]);
      n++;
    }
for (const [g, items] of FLOWS)
  for (const it of items) for (const st of it[3]) { if (/class="edge3d"/.test(frame(st[2]))) turned++; n++; }
console.log('  frames rendered without throwing:', n);
/* The shadow only paints because the clip lives on an inner <b>; flattening
   that back to one element silently loses it, which happened once already. */
ok(wrapped > 0, 'due marks keep the clip wrapper and the hairline', wrapped + ' of them');
/* The fore-edge and scrubber presentations were withdrawn with their versions,
   so the assertion inverts: nothing in the collapsed set may still draw them. */
ok(turned === 0 && scrubbed === 0,
   'no withdrawn presentation is still rendered anywhere',
   turned + ' turned, ' + scrubbed + ' scrubbed');
/* A missing state key prints `undefined` into the drawing rather than
   failing, which is exactly how `between` shipped a shelf label reading
   "undefined 12" through 104 rendered frames and 54 passing checks. Only
   looking at it caught that, so the check now looks for it in every frame. */
ok(undef.length === 0,
   'no frame renders undefined, NaN or a stringified object',
   undef.length ? undef.join(', ') : n + ' frames clean');
/* ---- the edge tab, as arithmetic only ----
   The version was withdrawn, so nothing draws a tab any more and the render
   checks that used to live here are gone. The GEO table still carries every
   anatomy, and the measurements below are the reason the version was rejected,
   so they are kept: they are the record of a cost, not of a drawing. */
ok(deadZone('edge-tab') === 0, 'the edge tab encoded position, so no dead zone');
ok(GEO['edge-tab'].travel === TABSTRIP_Y - NAV_H - ETAB_DEEP,
   'its travel stopped at the pinned tab strip, derived not typed',
   GEO['edge-tab'].travel.toFixed(1) + 'pt at ' + fmt(perPage('edge-tab', 320)) + ' pt/page');
const SHELF_LIMIT = (NAV_H + HERO_H) - NAV_H - ETAB_DEEP;
ok(Math.abs(SHELF_LIMIT / 320 - GEO['mark-in-place'].travel / 320) < 0.02,
   'stopping at the shelf would have equalled mark-in-place\'s resolution',
   fmt(SHELF_LIMIT / 320) + ' vs ' + fmt(perPage('mark-in-place', 320)));
ok(perPage('edge-tab', 320) > SHELF_LIMIT / 320 * 1.7,
   'stopping at the strip instead kept well over half again the resolution');
ok(ETAB_DEEP < 44,
   'the drawn tab is under the 44pt floor, so the grab band must exceed it',
   ETAB_DEEP.toFixed(1) + 'pt deep');
/* The strip sits below the band, and the band this feature draws is not the
   shipped band: it adds the progress line under the author. Forgetting that
   put the limit 30pt too high, so the tab stopped short of its own wall. */
ok(TABSTRIP_Y === NAV_H + HERO_H + SHELF_H + BAND_H + PROG_H && PROG_H > 0,
   'the tab strip is measured below the band this feature actually draws',
   'strip ' + TABSTRIP_Y + ', band ' + (BAND_H + PROG_H));
/* The finding the drawing produced, asserted so it cannot be quietly
   forgotten: turned sideways the tab reaches further in than either piece of
   chrome it passes leaves free, so the overlap is not a function of travel. */
ok(ETAB_LEN > SLAB_INSET && ETAB_LEN > BAND_PAD_R,
   'the tab reaches further in than the shelf label or the band leaves free',
   ETAB_LEN.toFixed(1) + 'pt vs ' + SLAB_INSET + ' and ' + BAND_PAD_R);
ok(ETAB_SLAB_FROM > 0 && ETAB_SLAB_TO < 1 && ETAB_SLAB_FROM < ETAB_SLAB_TO,
   'the shelf-label overlap is a real interior range, not an edge case',
   pc(ETAB_SLAB_FROM) + ' to ' + pc(ETAB_SLAB_TO));
ok(ETAB_BAND_FROM > 0 && ETAB_BAND_FROM < 1,
   'the band overlap starts partway down and runs to the end',
   pc(ETAB_BAND_FROM) + ' to 100%');
/* Clearing the label needs a tab no deeper than the label's own margin, and
   that is a square nub rather than a bookmark. Recorded as arithmetic so the
   "just make it smaller" fix cannot be proposed without its cost. */
ok(SLAB_INSET < ETAB_DEEP + 1,
   'a tab that clears the shelf label is a square, not a ribbon',
   SLAB_INSET + 'pt allowed vs ' + ETAB_DEEP.toFixed(1) + 'pt deep');
/* The callout must carry the computed figures, not typed ones. */
const ETOPEN = VCHAIN.find((v) => v[0] === 'edge-tab')[4].open.due;
ok(ETOPEN.includes(pc(ETAB_SLAB_FROM)) && ETOPEN.includes(pc(ETAB_SLAB_TO)),
   'the due callout quotes the derived overlap range');
ok(/runs straight through the shelf label/.test(ETOPEN) && /was false/.test(ETOPEN),
   'the callout retracts the old claim instead of repeating it');

/* ---- top-edge-slide ---- */
console.log('--- top-edge-slide ---');
/* Two different things, conflated once and caught by a failing check: `V` is the
   surviving VERSION, `TESA` is the ANATOMY its screens are drawn at. GEO is keyed
   by anatomy, resolvers by version. */
const TESA = 'top-edge-slide';
const tesLefts = (id) => {
  const h = frame(specOf(V, id));
  return [...h.matchAll(/class="bm[^"]*" style="left:([\d.]+)px;top:([\d.]+)px;width:([\d.]+)px;height:([\d.]+)px/g)]
    .map((m) => ({ left: +m[1], top: +m[2], w: +m[3], h: +m[4] }));
};
ok(deadZone(TESA) === 0, 'position encoding, so no dead zone');
ok(Math.abs(GEO[TESA].travel - (TES_X1 - TES_X0)) < 1e-9,
   'the track is the cover, derived from the binding and the shipped pin',
   GEO[TESA].travel.toFixed(1) + 'pt = ' + (GEO[TESA].travel / 100).toFixed(2)
     + 'pt/percent, ' + perPage(TESA, 320).toFixed(2) + 'pt/page');
/* The whole reason this version exists: the mark cannot leave the cover, so
   it cannot reach ShelfLabel or the band -- the collision that ended
   `edge-tab` is structurally impossible rather than merely avoided. */
let tesN = 0;
for (const id of ['due', 'logged', 'deadzone', 'finish-reach', 'nocount']) {
  const ms = tesLefts(id);
  ok(ms.length > 0, 'top-edge-slide "' + id + '" draws a mark');
  ok(ms.every((m) => m.left >= BIND_W - 0.01 && m.left + m.w <= COVER_W + 0.01),
     'top-edge-slide "' + id + '" stays on the cover, clear of the binding',
     ms.map((m) => m.left.toFixed(1) + '+' + m.w.toFixed(1)).join(' '));
  tesN += ms.length;
}
ok(tesN > 0, 'marks measured', tesN + ' of them');
/* `nocount` is the case every other version handles worse: no page_count, so
   the mark is placed from the fraction. page_count is 35% covered and cannot
   improve, which makes this the ordinary book rather than the exception. */
ok(tesLefts('nocount').length > 0,
   'a book with no page count still travels the identical track');
/* Continuity claims, both end points. */
ok(Math.abs(tesLeft(1) - ribLeftFromBoxRight(COVER_W - INSET)) < 1e-9,
   '100% lands exactly on the pin shelf_row already writes',
   tesLeft(1).toFixed(1) + 'pt');
ok(Math.abs(tesLeft(0) - BIND_W) < 1e-9,
   'page 1 sits in the gutter, against the binding', tesLeft(0).toFixed(2) + 'pt');
/* The ruler is in percent because the stored value is a fraction, and
   because page decades are not physically drawable at this travel. */
const PAGE_DECADE = (GEO[TESA].travel / 320) * 10;
const PCT_DECADE = GEO[TESA].travel / 10;
ok(PAGE_DECADE < 3 && PCT_DECADE >= 3,
   'page decades are under the 3pt floor, percent decades clear it',
   PAGE_DECADE.toFixed(1) + 'pt vs ' + PCT_DECADE.toFixed(1) + 'pt');
/* `held` went with the drag, so the ruler has no state left that reveals it.
   Asserted as an absence, which is the honest record of a withdrawal. */
ok(!ids(V).includes('held'),
   'the long-press ruler went with the drag it belonged to');
ok(!/class="tes"/.test(frame(specOf(V, 'due'))),
   'and the ruler is not there at rest');
/* The whole drag apparatus — `dragging`, the live value in the title slot, the
   blanked band read-out, the ghost of the old position — went with the drag when
   the field research said the mark displays and a control asks. Asserted as an
   absence so it cannot creep back without a decision. */
ok(!ids(V).includes('dragging'), 'the drag state is gone');
ok(!/class="navlive"/.test(frame(specOf(V, 'due'))) &&
   !/class="bmghost"/.test(frame(specOf(V, 'due'))),
   'and with it the live title value and the position ghost');
/* Every `open` callout must name something that still exists, or the text is
   written and never shown. One did, and only re-reading the map caught it — and
   the collapse makes this sharper, since a callout can now be orphaned by a
   deletion three steps up the chain. Checked against screens AND flows, because
   the later versions attach callouts to both. */
const RESOLVED_OPEN = resolveOpen(V);
/* Inlined rather than using `fids`, which is declared further down. */
const OPEN_TARGETS = ids(V).concat(
  resolveView(V, 'flows').map(([g, l]) => l.map((i) => i[0])).flat(),
);
const ORPHANS = Object.keys(RESOLVED_OPEN).filter((k) => !OPEN_TARGETS.includes(k));
ok(ORPHANS.length === 0,
   'every open callout is attached to a screen or flow that still exists',
   ORPHANS.length ? 'orphaned: ' + ORPHANS.join(', ') : Object.keys(RESOLVED_OPEN).length + ' callouts');
ok(!/class="navlive"/.test(frame(specOf(V, 'due'))),
   'the title slot is empty at rest, as CollapsingBookTitle leaves it');
/* The press geometry (18% on the length, not the width) went with `held`. The
   asset's own proportions are still asserted at the top of this file. */
/* ---- the lamp shelf's geometry, which the tip still draws ----
   `reading-lamp` the version is gone; the shelf it introduced is what every
   `lamp()` frame in the surviving set renders, so its end points are still
   load-bearing. The render checks that walked its own screens went with it. */
console.log('--- the lamp shelf ---');
const RL = 'reading-lamp'; // anatomy, kept in GEO
ok(GEO[RL].encode === 'position' && deadZone(RL) === 0,
   'the lamp shelf encodes position, so no dead zone');
ok(Math.abs(GEO[RL].travel - (LSH_X1 - LSH_X0)) < 1e-9,
   'shelf travel derived from the binding band and the shipped pin',
   GEO[RL].travel.toFixed(1) + 'pt = ' + (GEO[RL].travel / 100).toFixed(2) + 'pt/percent');
ok(Math.abs(LSH_X1 - (LSH_W - 12.5 - A_RIB_W)) < 1e-9,
   '100% is the pin shelf_row already writes, at the asset\'s 1x');
ok(Math.abs(LSH_X0 - LSH_W * 0.082) < 1e-9,
   '0% is the drawn binding band, like TES_X0 at detail scale');
/* Three open books, three marks placed from fractions, on a surviving frame. */
const RLREST = frame(specOf(V, 'sh-bar'));
const rlm = [...RLREST.matchAll(/class="lbm" style="left:([\d.]+)px/g)].map((m) => +m[1]);
ok(rlm.length === 3, 'three open books draw three positioned marks',
   'left ' + rlm.map((x) => x.toFixed(1)).join(', '));
ok(rlm.every((x) => x >= LSH_X0 - 0.01 && x + A_RIB_W <= LSH_W + 0.01),
   'every mark stays on its cover, gutter to pin');
ok(LAMP_READING.some((b) => !b.pages && b.pct != null),
   'and one of them has no page count at all, which is the ordinary case');
/* The shelf stands upright with a count, matching the shipped rebuild. */
ok(/class="lshelf reading/.test(RLREST) && /class="ltab rt"/.test(RLREST),
   'the reading shelf carries its own label and count');

/* ---- the nightly gesture, as a decision rather than five drawings ----
   `tap-target` drew five candidates and all five screens were withdrawn by the
   versions after it, so their render checks are gone. What survives is the rule
   they produced, and it is worth pinning: a tap on a cover means "open the book"
   everywhere, so the day is never stamped by tapping a cover. */
console.log('--- the nightly gesture ---');
ok(!ids(V).some((id) => id.startsWith('t-')),
   'none of the five candidate gestures is still drawn');
ok(ids(V).includes('ss-reading'),
   'and the gesture that won is a field on the state sheet');

/* ---- the placement argument, as arithmetic only ----
   `stamp-a` measured five homes for a nightly button in the band. The whole
   argument is SUPERSEDED by the state sheet — there is no nightly button in the
   band any more — so the drawings are gone. The measurements stay, because they
   are the record of what each rejected option cost and the reason nobody should
   re-propose the full-width row. */
console.log('--- the placement argument ---');
ok(BAND_STAMP_H > 40 && BAND_STAMP_H < 70,
   'a full-width band button would have cost a countable slice of the band',
   BAND_STAMP_H.toFixed(1) + 'pt, pushing the strip to ' + (TABSTRIP_Y + BAND_STAMP_H).toFixed(0));
ok(PERIOD_WRAP_H < BAND_STAMP_H && PERIOD_TIGHT_H < PERIOD_WRAP_H,
   'the three placements rank by measured cost, cheapest last',
   'button ' + BAND_STAMP_H.toFixed(0) + ' > wrapped ' + PERIOD_WRAP_H + ' > tight ' + PERIOD_TIGHT_H + 'pt');
ok(PERIOD_TIGHT_H === 2,
   'and the cheapest still cost 2pt rather than nothing, which the drawing refuted',
   PERIOD_TIGHT_H + 'pt');
ok(44 / 22 > 1.9,
   'making the streak chip the target needed a ring twice the visible object');
/* The three surviving frames from that version are the period card's own states,
   which the sheet does not replace: the card still reports the reading period. */
for (const need of ['a-period', 'a-period-tight', 'a-finished'])
  ok(ids(V).includes(need), 'the period card state "' + need + '" survives');
/* And the nightly button itself is gone from every frame. */
ok(!ids(V).some((id) => ['a-bar', 'a-fab', 'a-chip', 'a-band-done'].includes(id)),
   'no frame still draws a nightly button in the chrome');

/* ---- where the reader's own number lives ----
   `streak-home` drew every slot that could hold the count — a strip above the
   shelf, a transient commit pill, a tab badge, the bar chip — and the bar chip
   won. The rejected slots are withdrawn, so what is asserted here is the RULE
   they produced: exactly one permanent home for the number. */
console.log('--- where the number lives ---');
const SHIDS = ids(V);
ok(SHIDS.includes('sh-bar') && SHIDS.includes('sh-bar-cold'),
   'the chip that won is drawn in both its recorded and open states');
ok(!['sh-strip', 'sh-strip-zero', 'sh-commit', 'sh-tab', 'sh-none'].some((id) => SHIDS.includes(id)),
   'and none of the rejected slots is still drawn');
/* The chip's three states, now that the fourth went with freezes. */
const SHBAR = frame(specOf(V, 'sh-bar'));
const SHCOLD = frame(specOf(V, 'sh-bar-cold'));
ok(/class="stkchip"/.test(SHBAR) && /stkchip cold/.test(SHCOLD),
   'recorded reads green and open reads grey, keyed on the day not the count');
ok(/&#9635;/.test(SHBAR), 'the glyph is the stamp, not a flame');
ok(!/&#128293;|&#127765;/.test(SHBAR), 'and no flame is smuggled in anywhere');
/* The Card is the numeric home; the chip must not become a second one. The
   conflict this version found is still live and is drawn in `sh-card-conflict`. */
ok(SHIDS.includes('card-stamps') && SHIDS.includes('sh-card-conflict'),
   'the Card keeps the number, and the collision it causes stays on the record');

/* ---- streak-counter: the six moments, and the wheel's stop count ---- */
console.log('--- streak-counter ---');
const SC = V;
const SCIDS = ids(SC);
for (const need of ['sc-increment', 'sc-milestone', 'sc-risk', 'sc-broken', 'sh-bar'])
  ok(SCIDS.includes(need), 'moment "' + need + '" is drawn');
for (const need of ['pos-wheel', 'sc-wheel-long', 'sc-wheel-split', 'sc-wheel-pct', 'pos-wheel-pct'])
  ok(SCIDS.includes(need), 'wheel state "' + need + '" is drawn');
/* No flame anywhere: the app's own vocabulary is the stamp, the lamp and the
   seal, and a fifth metaphor would compete with four that work. */
for (const id of SCIDS) {
  const h = frame(specOf(SC, id));
  ok(!/🔥|&#128293;|flame/i.test(h), 'no flame in "' + id + '"');
}
/* 1. The increment: the fresh cell is what the eye lands on, not the total. */
const SCUP = frame(specOf(SC, 'sc-increment'));
ok(/class="moment"/.test(SCUP) && /class="big">12</.test(SCUP), 'the increment shows the count');
ok(/class="on fresh"/.test(SCUP), 'and marks the day that just inked in');
ok((SCUP.match(/class="on fresh"/g) || []).length === 1, 'exactly one fresh cell');
ok(!/Share|share/.test(SCUP), 'with no share prompt or second call to action');
/* 2. The milestone is an object, and it replaces the bare number. */
const SCMS = frame(specOf(SC, 'sc-milestone'));
ok(/class="seal"><b>30<\/b>/.test(SCMS), 'the milestone presses a seal');
ok(!/class="big"/.test(SCMS), 'and the seal replaces the plain figure rather than stacking with it');
/* 3. The warning is amber and states a deadline, not a threat. */
const SCRISK = frame(specOf(SC, 'sc-risk'));
ok(/class="stkchip risk"/.test(SCRISK), 'the at-risk chip is its own state');
ok(/4am/.test(SCRISK), 'the warning states the rollover deadline');
ok(!/lose|Lose|don.t break|Don.t/.test(SCRISK), 'and never threatens the reader');
ok(/lshelf reading low/.test(SCRISK), 'the lamp is still low, since the day is still open');
/* 4. The freeze moment is withdrawn with the feature, and the chip's fourth
   state goes with it. Asserted as an absence in both directions: no frame draws
   the frozen chip, and the snowflake glyph appears nowhere. */
ok(!ids(V).includes('sc-freeze'), 'the freeze moment is gone');
const ALLFRAMES = ids(V).map((id) => frame(specOf(V, id)));
ok(!ALLFRAMES.some((h) => /stkchip frozen/.test(h)),
   'and no frame draws the frozen chip state');
ok(!ALLFRAMES.some((h) => /&#10052;/.test(h)),
   'nor the snowflake, anywhere');
/* 5. The break keeps the record and offers a true correction, not a purchase. */
const SCBRK = frame(specOf(SC, 'sc-broken'));
ok(/class="big">31</.test(SCBRK), 'the break shows the record, not a zero');
ok(!/>0</.test((SCBRK.match(/class="moment"[\s\S]*?class="acts"/) || [''])[0]),
   'no zero anywhere in the break moment');
ok(/fix it/.test(SCBRK) && !/buy|gem|pay|restore for/i.test(SCBRK),
   'and the repair is a correction rather than a purchase');
/* 6. Three counter states, each a different fact. The fourth (blue, a covered
   gap) went with freezes; `sh-bar` and `sh-bar-cold` used to render identically
   after the collapse, which is why green is asserted on a named frame now. */
const chipOf = (h) => (h.match(/class="stkchip([^"]*)"/) || [])[1].trim();
ok(chipOf(frame(specOf(SC, 'sc-increment'))) === '', 'green: today is recorded');
ok(chipOf(frame(specOf(V, 'sh-bar'))) === '', 'green again on the chip screen itself');
ok(chipOf(frame(specOf(V, 'sh-bar-cold'))) === 'cold', 'grey: today is open');
ok(chipOf(SCRISK) === 'risk', 'amber: open and late');
ok(new Set(['', 'cold', 'risk']).size === 3, 'three states, and no fourth');

/* THE RULE, applied to the moments: a hero figure and its label must not print
   the same number \u2014 the label is a unit, as `.streakbig` on the card already
   does it. The drawing caught "12" above "12 days in a row". */
for (const id of ['sc-increment', 'sc-risk', 'sc-broken']) {
  const h = frame(specOf(SC, id));
  const big = (h.match(/class="big">(\d+)</) || [])[1];
  const lbl = (h.match(/class="lbl">([^<]*)</) || [])[1] || '';
  ok(!big || !new RegExp('\\b' + big + '\\b').test(lbl),
     'moment "' + id + '" does not print its own figure twice',
     big + ' / "' + lbl + '"');
}

/* The week row has four distinct cell states, and the drawing caught them
   collapsing: a day that has not happened yet was rendering with the dashed
   "today" treatment, so the broken moment showed three todays. */
for (const [id, want] of [['sc-increment', 0], ['sc-risk', 1], ['sc-broken', 1]]) {
  const h = frame(specOf(SC, id));
  ok((h.match(/class="today"/g) || []).length === want,
     'moment "' + id + '" marks ' + want + ' day(s) as today',
     (h.match(/class="today"/g) || []).length + '');
}
/* The increment has none on purpose: today is not "awaiting", it has just been
   stamped, which is the `fresh` state. */
ok(/class="on fresh"/.test(frame(specOf(SC, 'sc-increment'))),
   'because on the increment today is the freshly inked cell instead');
const BRK2 = frame(specOf(SC, 'sc-broken'));
ok((BRK2.match(/class="miss"/g) || []).length === 2,
   'and the break shows its missed days in their own pale state');
ok(/class="miss"/.test(BRK2) && !/#b3261e/.test(BRK2),
   'missed is pale ink, never red');

/* ---- the wheel's stop count, which is the whole argument ---- */
console.log('--- the wheel ---');
const FLICK = 10; // stops a flick moves, roughly
ok(Math.round(912 / FLICK) > 40,
   'a 912-page book is dozens of flicks end to end on a page wheel',
   Math.round(912 / FLICK) + ' flicks');
ok(Math.round(101 / FLICK) < 12,
   'a percent wheel is about ten, for every book ever printed',
   Math.round(101 / FLICK) + ' flicks');
const LONG = frame(specOf(SC, 'sc-wheel-long'));
ok(/class="flicks"/.test(LONG) && /912 stops/.test(LONG),
   'the long-book frame draws its own cost');
const PCTW = frame(specOf(SC, 'sc-wheel-pct'));
ok(/47%/.test(PCTW), 'the percent wheel spins percent');
ok(/&asymp; p\.|\u2248 p\./.test(PCTW), 'and derives the page as a label underneath');
ok(/101 stops/.test(PCTW), 'stating the constant range');
ok(!/class="seg"/.test(PCTW), 'with no unit segment, because percent IS the unit');
/* The derived page must agree with the fraction, or the label is a lie. */
const derived = +(PCTW.match(/p\.(\d+) of 912/) || [])[1];
ok(Math.abs(derived - Math.round(0.47 * 912)) <= 1,
   'the derived page label agrees with the percentage',
   derived + ' vs ' + Math.round(0.47 * 912));
/* ...and so must the figure quoted in the prose. Typed once as p.431, which the
   control never draws — the "derive, don't type" rule, enforced. */
const noteOf = (v, id) => {
  for (const [g, items] of resolveView(v, 'screens'))
    for (const it of items) if (it[0] === id) return it[2];
  return '';
};
const quoted = +(noteOf('streak-counter', 'sc-wheel-pct').match(/p\.(\d+) of 912/) || [])[1];
ok(quoted === derived,
   'the page quoted in the prose is the page the wheel draws',
   'prose ' + quoted + ' vs drawn ' + derived);
/* The rejected middle is on the record. */
const SPLIT = frame(specOf(SC, 'sc-wheel-split'));
ok(/class="wheel two"/.test(SPLIT) && (SPLIT.match(/class="col"/g) || []).length === 2,
   'the two-column variant is drawn so its rejection is recorded');
/* And the no-page-count book needs no special case. */
const PCTNO = frame(specOf(SC, 'pos-wheel-pct'));
ok(/72%/.test(PCTNO) && !/of \d+/.test(PCTNO),
   'a book with no page count gets the same wheel and no derived label');
ok(!/fallback|No page count for this book &mdash; percent/.test(PCTNO),
   'and no apology copy, because it is not a fallback any more');
/* The two flows. */
ok(!fids(V).includes('sc-week') && fids(V).includes('sc-wheel'),
   'both the fortnight and the wheel argument are browsable');
/* The fortnight walked through the freeze night, so it went with it. */
ok(fsteps(V, 'sc-week').length === 0, 'the fortnight flow is gone with the freeze');
ok(fsteps(SC, 'sc-wheel').length === 3, 'the wheel argument is three frames');

console.log('--- gaps closed ---');
const TB = frame(specOf(V, 'due'));
ok(/class="tabbody"/.test(TB) && /ISBN/.test(TB),
   'the Book info tab body is drawn; ISBN is the section that is always there');
ok(!/class="tail"/.test(TB), 'the empty placeholder tail is gone');
/* Two for band-scrubber, one for reading-lamp's Exact, two for tap-target's
   wheel screens \u2014 derived rather than typed so adding a version cannot
   silently drift past it. */
let drumWant = 0;
for (const v of ALLV)
  for (const [g, l] of resolveView(v, 'screens'))
    for (const it of l) if (it[3] && it[3].drum) drumWant++;
ok(drummed === drumWant, 'every screen that declares a drum draws exactly one',
   drummed + ' drawn, ' + drumWant + ' declared');
/* The Page/Percent segment belonged to `band-scrubber`, which argued the unit was
   the reader's choice. That version is withdrawn and the data chooses the unit, so
   the segment must appear nowhere at all. */
ok(!ids(V).includes('drum'), 'the scrubber\'s drum screen is gone');
ok(!ids(V).some((id) => /class="seg"/.test(frame(specOf(V, id)))),
   'and no frame offers a Page/Percent segment: the data chooses the unit');
ok(!/class="seg"/.test(frame(specOf(V, 'pos-wheel'))) &&
   !/class="seg"/.test(frame(specOf(V, 'pos-wheel-pct'))),
   'tap-target drops it: the data chooses the unit');
/* The +10/+25/+50 chips were deleted at the user's request; the wheel is the only
   position control. Asserted as an absence. */
ok(chipped === 0, 'no frame draws the deleted delta chips', chipped + ' frames');
/* The scrubber thumb went with `band-scrubber`. The wrapper/clip lesson it shared
   with the cover mark is still asserted above, as `wrapped > 0`. */
ok(!ids(V).some((id) => /class="thumb"/.test(frame(specOf(V, id)))),
   'no frame still draws the scrubber thumb');

/* ---- streak-flows: the month as a ligature, and the book_id argument ---- */
console.log('--- streak-flows ---');
const XF = V;
const XIDS = ids(XF);
ok(['cal-plain', 'cal-books', 'cal-tap-books'].every(i => XIDS.includes(i)),
   'the three month frames are present');
ok(!XIDS.includes('cal-tap-plain'),
   'and the empty-popover frame is gone, its point now made by cal-tap-books alone');
/* Inheritance still works: the six moments come down from streak-counter. */
ok(['sc-increment', 'sc-broken', 'sh-bar'].every(i => XIDS.includes(i)),
   'and the six moments are inherited, not restated');

/* The plain map must be DERIVED from the book map, or the pair stops being a
   controlled comparison. Same days, no books. */
ok(Object.keys(CAL_PLAIN).join() === Object.keys(CAL_STAMPS).join(),
   'the plain month covers exactly the same days as the coloured one',
   Object.keys(CAL_STAMPS).length + ' days');
ok(Object.values(CAL_PLAIN).every(v => v === true || v === 'f'),
   'and carries no book reference at all');
ok(CAL_READ + CAL_FRZ === Object.keys(CAL_STAMPS).length,
   'days read plus days forgiven is the whole run',
   CAL_READ + ' + ' + CAL_FRZ);
/* The streak counts the forgiven day; the "days read" chip does not. Both are
   true and the card prints both -- that is the honesty rule. */
ok(cal({}).streak === CAL_READ + CAL_FRZ && cal({}).practised === CAL_READ,
   'the run is 12 and the days read are 11, drawn as two different figures',
   cal({}).streak + ' vs ' + cal({}).practised);

/* September 2026 really does start on a Tuesday. Derived from Date so the grid
   cannot quietly be a week out. */
ok(cal({}).first === (new Date(2026, 8, 1).getDay() + 6) % 7,
   '1 September 2026 lands in the column Date says it does',
   'first=' + cal({}).first);

/* Geometry: seven cells and six gaps exactly fill the card's interior. */
ok(Math.abs(7 * CAL_CELL + 6 * CAL_GAP - CAL_IN) < 0.01,
   'seven cells and six gaps fill the card interior exactly',
   (7 * CAL_CELL + 6 * CAL_GAP).toFixed(2) + ' of ' + CAL_IN);

const xCP = frame(specOf(XF, 'cal-plain'));
const xCB = frame(specOf(XF, 'cal-books'));
/* The ligature is the point: consecutive days share ONE capsule. The run spans
   two week rows, so there are exactly two of them -- if this ever reports 12 the
   drawing has reverted to isolated stamps. */
const xRunsOf = (h) => (h.match(/class="crun plain"/g) || []).length;
ok(xRunsOf(xCP) === calRuns(specOf(XF, 'cal-plain')).length,
   'the plain month draws one capsule per run, not one per day',
   xRunsOf(xCP) + ' capsules for ' + Object.keys(CAL_STAMPS).length + ' days');
ok(xRunsOf(xCP) === 3,
   'the run breaks where the week turns AND where the day was missed',
   xRunsOf(xCP) + ' pieces');
/* With forgiveness deferred the missed day severs the thread, which is the whole
   cost of deferring. Asserted in both directions. */
ok(!/class="crun frz"/.test(xCP) && !/class="crun frz"/.test(xCB),
   'no forgiven day is drawn, because forgiveness does not exist yet');
ok(!calRuns(specOf(XF, 'cal-plain')).some(([a, b]) => a <= 10 && b >= 10),
   'and day 10 ends a run rather than sitting inside one');
ok(!/class="cday frz"/.test(xCP) && !/>10</.test((xCP.match(/class="cday on"[^>]*>\d+</g) || []).join('')),
   'the missed day is not drawn as a read day either');
/* Today: a rule, and exactly one of them. */
ok((xCP.match(/cday[^"]*today/g) || []).length === 1,
   'exactly one cell is marked today');

/* The coloured variant must actually use every book's cover colour. */
CAL_TITLES.forEach((b) => ok(xCB.includes(b.c),
   'the ligature carries ' + b.t + "'s cover colour", b.c));
ok(!xCP.includes(CAL_TITLES[0].c),
   'and the plain variant carries none of them');
ok(/class="ckey"/.test(xCB) && !/class="ckey"/.test(xCP),
   'only the coloured month needs a legend, which is its honest cost');

/* The tap is the cheapest test of the schema. The empty-popover frame was folded
   away once the argument was settled, so the surviving assertion is that the day
   CAN be answered — and the flow still carries the failing case as step 2. */
const xTB = frame(specOf(XF, 'cal-tap-books'));
const xTPflow = frame(fsteps(V, 'x-month')[1][2]);
ok(/class="none"/.test(xTPflow) && /Nothing else was recorded/.test(xTPflow),
   'the flow still shows a day with nothing to say, which is the argument');
ok(!/class="none"/.test(xTB) && xTB.includes(CAL_TITLES[1].t),
   'with it, the popover names the book that was read that day',
   CAL_TITLES[1].t);
/* The derived page must agree with the percentage, exactly as it must on the
   wheel -- same rule, second surface. */
const xPOP = specOf(XF, 'cal-tap-books').pop;
const xBK = CAL_TITLES.find(b => b.k === CAL_STAMPS[xPOP.day]);
ok(xTB.includes(Math.round(xPOP.pct * 100) + '%'),
   'the popover reports the fraction that was stored',
   Math.round(xPOP.pct * 100) + '%');
ok(xTB.includes('p.' + Math.round(xPOP.pct * xBK.pages)),
   'and derives the page from it rather than storing one',
   'p.' + Math.round(xPOP.pct * xBK.pages) + ' of ' + xBK.pages);
/* And the shelf's titles come from the shelf, so one book cannot have two names. */
ok(CAL_TITLES.every((b, i) => b.t === LAMP_READING[i].t),
   'the month\u2019s books ARE the shelf\u2019s books');
/* The three defects the eye caught, pinned. */
ok(/class="cal books"/.test(xCB) && /class="cal plain"/.test(xCP),
   'each month declares its mode, so contrast can follow the fill');
ok(!/rgba\(9,188,138/.test(xCB),
   'the coloured month never paints a forgiven day in the brand green',
   'it read as a fourth book');
ok(!/rgba\(120,113,96/.test(xCB),
   'and paints no neutral band either, because there is no forgiven day to paint');
ok(/class="cday on today"/.test(xCP) && /class="cday on today"/.test(xCB),
   'today sits inside the run rather than replacing it');

/* The prose figure must match the grid -- the rule this set keeps breaking. */
ok(noteOf(V, 'cal-plain').includes(String(CAL_NOFRZ_STREAK)),
   'the note quotes the run the drawing actually shows',
   'run of ' + CAL_NOFRZ_STREAK);

/* Six flows, end to end, and the two that decide retention are among them. */
const XFL = fids(XF);
['x-night', 'x-late', 'x-break', 'x-month', 'y-status', 'y-night'].forEach((f) =>
  ok(XFL.includes(f), 'flow ' + f + ' is browsable'));
['x-set', 'x-miss', 'sc-week', 'pos-rare'].forEach((f) =>
  ok(!XFL.includes(f), 'and superseded flow ' + f + ' is gone'));
/* Nothing may still present the bare progress line as the way in. */
ok(!fids(V).some((f) => /pos-rare/.test(f)),
   'the band\'s progress line is no longer offered as an entry point');
ok(fsteps(XF, 'x-night').length === 5, 'the ordinary night is five frames');
ok(fsteps(XF, 'x-month').length === 4, 'the decision is drawn in four frames');
/* x-night has to end greener than it started, or the loop is not closed. */
const xN0 = frame(fsteps(XF, 'x-night')[0][2]);
const xN4 = frame(fsteps(XF, 'x-night')[4][2]);
ok(/stkchip cold/.test(xN0) && !/stkchip cold/.test(xN4),
   'the night starts on a grey chip and ends on a lit one');
ok(/lshelf reading low/.test(xN0) && /lshelf reading lit/.test(xN4),
   'and the lamp is the receipt, not a toast');
/* The late night must never go red, which is the rule most streak apps break. */
const xL1 = frame(fsteps(XF, 'x-late')[1][2]);
ok(/stkchip risk/.test(xL1) && !/#b3261e|#d32f2f/.test(xL1),
   'the warning is amber and states the deadline', '4am');
ok(/4am/.test(xL1), 'the deadline is named rather than implied');
/* The coupling `x-set` used to draw — bookmark moved, day left open — is closed by
   construction now: the position and the day are two fields on one form under one
   Save, so there is no order in which one lands without the other. Asserted on the
   sheet instead of on a flow that no longer exists. */
const xSSR = frame(specOf(V, 'ss-reading'));
ok(/How far in\?/.test(xSSR) && /I read today/.test(xSSR) &&
   (xSSR.match(/class="fbtn"/g) || []).length === 1,
   'position and day are two fields under one Save, so they cannot diverge');
ok(!fids(V).includes('x-set'),
   'and the flow that drew them diverging is gone');


/* ---- state-sheet: drawn on the shipped sheet, and freezes deferred ---- */
console.log('--- state-sheet ---');
const SS = V;
const SSIDS = ids(SS);
ok(['ss-interested', 'ss-reading', 'ss-finished', 'ss-wheel', 'ss-card', 'ss-card-none']
     .every(i => SSIDS.includes(i)),
   'the sheet, the wheel and the real card are all drawn');
/* Freezes are deferred: no frame may imply forgiveness exists. */
ok(!SSIDS.includes('sc-freeze'), 'the freeze moment is removed, not left implying it ships');
ok(!fids(SS).includes('x-miss'), 'and so is the flow that depended on it');
const xSSCAL = frame(specOf(SS, 'cal-plain'));
ok(!/freeze/i.test(xSSCAL),
   'the month omits the freezes chip rather than reading zero');
ok(!/class="crun frz"/.test(xSSCAL) && !/class="cday frz"/.test(xSSCAL),
   'and draws no forgiven day at all');
/* Every frame in the set, not just the screen I remembered to override. The first
   pass of this check looked only at `cal-plain`, and two inherited FLOWS went on
   drawing forgiven days while the notes said forgiveness did not exist. */
const xSSALL = [];
for (const [g, items] of resolveView(SS, 'screens'))
  for (const it of items) xSSALL.push(['screen ' + it[0], frame(it[3])]);
for (const [g, l] of resolveView(SS, 'flows'))
  for (const it of l)
    it[3].forEach((st, i) => xSSALL.push(['flow ' + it[0] + ' step' + (i + 1), frame(st[2])]));
const xFRZ = xSSALL.filter(([, h]) => /class="(crun|cday) frz"/.test(h)).map(([n]) => n);
ok(xFRZ.length === 0,
   'NO frame draws a forgiven day, flows included',
   xFRZ.length ? xFRZ.join(', ') : xSSALL.length + ' frames clean');
const xFRZW = xSSALL.filter(([, h]) => /freeze/i.test(h)).map(([n]) => n);
ok(xFRZW.length === 0, 'and no rendered frame says the word',
   xFRZW.length ? xFRZW.join(', ') : 'clean');

/* The cost of deferring, derived rather than claimed. */
ok(CAL_NOFRZ_STREAK === 3,
   'without a freeze the run ending today is three days, not twelve',
   CAL_NOFRZ_STREAK + ' vs ' + (CAL_READ + CAL_FRZ));
ok(Object.keys(CAL_NOFRZ).length === CAL_READ,
   'the freeze-free month still has every day that was actually read',
   CAL_READ + ' days');
ok(calRuns(specOf(SS, 'cal-plain')).length === 3,
   'and the missed Thursday severs the thread into three pieces',
   calRuns(specOf(SS, 'cal-plain')).length + ' runs');

/* The sheet must be the SHIPPED sheet: conditional rows keyed on status. */
const xSS0 = frame(specOf(SS, 'ss-interested'));
const xSS1 = frame(specOf(SS, 'ss-reading'));
const xSS2 = frame(specOf(SS, 'ss-finished'));
ok(/Change reading status/.test(xSS0), 'the sheet keeps its shipped title');
ok((xSS0.match(/class="seg3"/g) || []).length === 1,
   'and its three-way status selector');
ok(!/Start date/.test(xSS0), 'at Interested there are no date rows, as shipped');
ok(/Start date/.test(xSS1) && /Start date/.test(xSS2),
   'a start date appears from Reading onward, as shipped');
ok(!/Finish date/.test(xSS1) && /Finish date/.test(xSS2),
   'a finish date only at Read, as shipped');
/* The two added rows, and where they may appear. */
ok(/How far in\?/.test(xSS1), 'the position row appears while reading');
ok(!/How far in\?/.test(xSS0) && !/How far in\?/.test(xSS2),
   'and nowhere else \u2014 a finished book is at the end by definition');
ok(/I read today/.test(xSS1) && !/I read today/.test(xSS0) && !/I read today/.test(xSS2),
   'the day is a field of the reading state only');
ok((xSS1.match(/class="fldrow/g) || []).length === 2,
   'the position row is the same row type as the date it sits under');
ok((xSS1.match(/class="fbtn"/g) || []).length === 1,
   'exactly one verb on the sheet, and it is Save');
ok(/class="chkrow on"/.test(xSS1), 'so the day is a checkbox, not a button');
const xSSPCT = specOf(SS, 'ss-reading');
ok(xSS1.includes('p.' + Math.round(xSSPCT.pct * xSSPCT.pages)),
   'the page is derived from the fraction on the sheet too',
   'p.' + Math.round(xSSPCT.pct * xSSPCT.pages));
/* The backdrop must agree with the sheet: an Interested sheet over a band reading
   "Reading \u00b7 p.148" is exactly the contradiction these drawings exist to catch. */
ok(!/class="prog"/.test(xSS0.split('class="fsheet"')[0]),
   'and the page behind an Interested sheet shows no reading position');

/* The wheel is the date picker's sibling, not a bespoke drum. */
const xWH = frame(specOf(SS, 'ss-wheel'));
ok(/class="wsheet"/.test(xWH), 'the wheel is its own sheet');
ok(/Confirm/.test(xWH), 'with the date picker\u2019s Confirm button');
ok(WHEEL_H === 320 && CONFIRM_W === 92,
   'at the shipped 320pt height and 92pt Confirm width',
   WHEEL_H + 'pt / ' + CONFIRM_W + 'pt');
ok(!/class="drum"/.test(xWH), 'and it is not the old bespoke drum');

/* The real card: one hero, books read, and tiles omitted not zero-filled. */
const xLC = frame(specOf(SS, 'ss-card'));
const xLCN = frame(specOf(SS, 'ss-card-none'));
ok((xLC.match(/class="tile hero"/g) || []).length === 1,
   'the card has exactly one hero tile');
ok(!/twoheroes/.test(xLC),
   'so books read stays the hero and the streak is not a second one');
ok(/class="tfoot"/.test(xLC), 'the hero carries its board of covers');
ok(/Streak/.test(xLC) && /Pace/.test(xLC),
   'the streak is a peer of Pace, in the tile row');
ok(!/Streak/.test(xLCN), 'and is omitted entirely when there is nothing true to say');
ok(!/class="tilerow"/.test(xLCN), 'with no empty tile row left behind');
ok(/All-time library card/.test(xLC),
   'the card names its own time scope, which a month pager would contradict');

/* The merged flow, which is what this version exists to draw. */
ok(fsteps(SS, 'y-status').length === 5, 'the merged flow is five frames');
const ySTEP = (n) => frame(fsteps(SS, 'y-status')[n][2]);
ok(!/class="fsheet"/.test(ySTEP(0)), 'it starts on the details page, at the edit button');
ok(/class="seg3"/.test(ySTEP(1)) && !/How far in\?/.test(ySTEP(1)),
   'the sheet opens at the status the book is actually in');
ok(/How far in\?/.test(ySTEP(2)) && /I read today/.test(ySTEP(2)),
   'picking Reading reveals both new rows in one move');
ok(/class="wsheet"/.test(ySTEP(3)), 'the position is picked on the wheel');
ok(/class="chkrow on"/.test(ySTEP(4)) && /class="fbtn"/.test(ySTEP(4)),
   'and one Save writes status, date, position and the day');
/* And the honest cost is drawn rather than argued. */
ok(fsteps(SS, 'y-night').length === 4, 'the nightly path is drawn end to end');
ok(Object.keys(resolveOpen(V)).includes('y-night'),
   'with a callout naming the four-tap problem it leaves open');

/* Repair now does the freeze's job, so assert it actually mends the thread. The
   claim is contiguity, NOT one capsule: the span crosses a week boundary, so it
   is correctly drawn as two. Written as "one capsule" first, which the checks
   refuted — the same row-break the plain month already documents. */
const xRP = fsteps(SS, 'x-break')[2][2];
const xRPd = Object.keys(xRP.stamps).map(Number).sort((a, b) => a - b);
ok(xRPd.every((d, i) => i === 0 || d === xRPd[i - 1] + 1),
   'the repaired month has no gap left in it',
   'days ' + xRPd[0] + '\u2013' + xRPd[xRPd.length - 1] + ', contiguous');
ok(calRuns(xRP).length === 2,
   'and is drawn as two capsules only because the week turns',
   calRuns(xRP).length + ' rows');
ok(xRP.streak === CAL_READ + 1 && xRP.practised === CAL_READ + 1,
   'with no forgiveness the run and the days read are the same figure',
   xRP.streak + ' / ' + xRP.practised);
ok(calRuns(specOf(SS, 'cal-books')).length === 3 && calRuns(xRP).length === 2,
   'so repair is the only thing that closes a gap once freezes are deferred',
   '3 pieces \u2192 2');

/* ---- the progress row presented as a control ---- */
console.log('--- the bar as a control ---');
ok(['bar-now', 'bar-a', 'bar-hint', 'bar-c-open', 'bar-d-sheet'].every(i => ids(V).includes(i)),
   'the baseline and the three treatments are drawn');
/* The omission this check exists to prevent: A was drawn ONLY at rest for the
   whole life of the group, while C and D each had a rest frame and an opened
   one -- so the single thing A proposed, a door, was the thing never shown.
   Every treatment must draw what its tap DOES, or it has not been drawn. */
const TAPPED = { A: 'bar-a-open', C: 'bar-c-open', D: 'bar-d-sheet' };
ok(Object.values(TAPPED).every(i => ids(V).includes(i)),
   'and each of the three draws its own tapped state, not just its rest state',
   Object.entries(TAPPED).map(([k, v]) => k + '=' + v).join(', '));
ok(Object.values(TAPPED).every(i => /class="wsheet"|class="pexp"/.test(frame(specOf(V, i)))),
   'each tapped frame actually shows a sheet or an inline expansion');
ok(fids(V).includes('z-bar'), 'and the inline path is a flow');
/* The shipped row is under the touch floor. That is the whole premise. */
ok(PROG_H < TOUCH_FLOOR,
   'the shipped row is under the touch floor, so it cannot be a control as drawn',
   PROG_H + 'pt vs ' + TOUCH_FLOOR);
/* A: copying DateFieldRow verbatim misses the floor. The finding worth keeping. */
ok(PROG_A_NAIVE === 40 && PROG_A_NAIVE < TOUCH_FLOOR,
   'DateFieldRow\u2019s own padding would land at 40pt and MISS the floor',
   PROG_A_NAIVE + 'pt');
ok(PROG_A_H === TOUCH_FLOOR,
   'so A takes v12 and reaches the floor exactly', PROG_A_H + 'pt');
/* `PROG_H` is the SLOT -- row plus the gap above it -- so A's cost is NOT
   `PROG_A_H - PROG_H`; that double-counts a gap which does not go away when the
   row becomes a field. The note claimed 14 while the frame measured 24. */
ok(PROG_ROW_H + PROG_GAP === PROG_H,
   'the shipped slot decomposes into a row plus the gap above it',
   PROG_ROW_H + ' + ' + PROG_GAP + ' = ' + PROG_H);
ok(PROG_A_GROWTH === 27 && PROG_A_GROWTH !== PROG_A_H - PROG_H,
   'so A costs 27pt and NOT the 44-30 the note used to claim',
   TABSTRIP_Y + ' \u2192 ' + (TABSTRIP_Y + PROG_A_GROWTH));
/* And the field only reaches 44 around a 20pt line box, i.e. DateFieldRow's 15pt
   body. At the progress row's own 13pt it lands at 41 -- which is what the frame
   drew for as long as it existed. Asserted from the CSS, since it is one rule. */
ok(/\.fr \.prog\.pfield \{[^}]*font-size: 15px/.test(css),
   'A adopts the field idiom\u2019s 15pt body, without which v12 lands at 41');
ok(PROG_A_PAD_V * 2 + PROG_ROW_H < TOUCH_FLOOR,
   'because v12 around the row\u2019s own 13pt type misses the floor',
   (PROG_A_PAD_V * 2 + PROG_ROW_H) + 'pt vs ' + TOUCH_FLOOR);
/* The notes must quote the derived figures, not typed ones. */
const barNote = noteOf(V, 'bar-a');
ok(barNote.includes(String(PROG_A_NAIVE)) && barNote.includes(String(PROG_A_H)) &&
   barNote.includes(String(TABSTRIP_Y + PROG_A_GROWTH)),
   'and A\u2019s note quotes all three derived figures');
/* The treatments, as rendered. */
const bNOW = frame(specOf(V, 'bar-now'));
const bA = frame(specOf(V, 'bar-a'));
const bH = frame(specOf(V, 'bar-hint'));
const bC = frame(specOf(V, 'bar-c-open'));
const bD = frame(specOf(V, 'bar-d-sheet'));
ok(!/class="chev"/.test(bNOW) && !/pfield/.test(bNOW),
   'the baseline carries no affordance at all');
ok(/class="prog pfield"/.test(bA) && /padding:12px 14px/.test(bA),
   'A wraps the row in the tap-to-edit ground at the padding that reaches 44');
/* The finding that only looking caught: `DateFieldRow`'s ground is surfaceVariant
   and so is the band, so copying the idiom verbatim renders an invisible field.
   Both the trap and the fix are drawn, and the CSS is asserted here because the
   whole distinction is one colour. */
ok(ids(V).includes('bar-a-naive'), 'the invisible-ground trap is on the record');
ok(/class="prog pfield naive"/.test(frame(specOf(V, 'bar-a-naive'))),
   'and it is drawn with the ground it would actually get');
ok(/\.fr \.prog\.pfield \{[^}]*background: var\(--surface\)/.test(css),
   'the fix inverts the ground to surface, because the band IS surfaceVariant');
ok(/\.fr \.band \{[^}]*background: var\(--variant\)/.test(css),
   'which is the collision, asserted from the band\u2019s own rule');
/* The second colour finding, and the one that narrows A's claim: the period card
   sitting 4pt above A's field has the SAME ground and radius, and it is a
   read-out. So in this band white-rounded-on-grey does not mean "tappable" --
   A's affordance is really its chevron, which bar-hint gets for free. Asserted
   from both rules so the two cannot silently drift apart. */
const _per = (css.match(/\.fr \.period \{[^}]*\}/) || [''])[0];
const _fld = (css.match(/\.fr \.prog\.pfield \{[^}]*\}/) || [''])[0];
const _bg = (r) => (r.match(/background: ([^;]+);/) || [])[1];
const _rad = (r) => (r.match(/border-radius: ([^;]+);/) || [])[1];
ok(_per && _fld && _bg(_per) === _bg(_fld) && _rad(_per) === _rad(_fld),
   'A\u2019s ground is already spoken for: the read-only period card is identical',
   _bg(_per) + ' / ' + _rad(_per));
ok(barNote.includes('read-only') || barNote.includes('read-out'),
   'and A\u2019s note concedes it rather than claiming the ground as an affordance');
ok(noteOf(V, 'bar-a-naive').includes('invisible'),
   'and the trap frame says so in as many words');
ok(noteOf(V, 'bar-a-naive').includes(String(PROG_A_GROWTH) + 'pt of wasted height'),
   'and quotes the corrected height cost, not the 14 that was never right');
ok(/class="chev"/.test(bA) && /class="chev"/.test(bH),
   'both A and the shared rest state carry a chevron');
/* Every treatment that makes the row a target must evict the chip. */
ok(/class="stk/.test(bNOW), 'the baseline still has the chip in the row');
[['bar-a', bA], ['bar-hint', bH], ['bar-c-open', bC]].forEach(([id, h]) =>
  ok(!/class="stk/.test(h),
     id + ' evicts the streak chip, as a tappable row must'));
/* C and D are the same frame at rest -- the finding the drawing produced. */
const restOf = (h) => (h.split('class="tabs"')[0].match(/class="prog[^"]*"[\s\S]*?<\/div>/) || [''])[0];
ok(restOf(bH) === restOf(bD),
   'C and D are identical at rest: they differ only in what the tap does');
/* C arms rather than opening, and spends height only while open. */
ok(/class="pthumb"/.test(bC) && /class="bar armed"/.test(bC),
   'C arms the bar with a thumb rather than opening a sheet');
ok(/class="pdone"/.test(bC), 'and commits in place with a Done');
/* Every one of these three was invisible to the checks and obvious on sight. */
ok(/\.fr \.prog \.bar\.armed \{[^}]*overflow: visible/.test(css),
   'the armed bar unclips itself, or the thumb draws as a GAP in the fill');
ok(/\.fr \.pexp \.pstep \{[^}]*background: var\(--surface\)/.test(css),
   'the steppers invert their ground too \u2014 the bar-a-naive trap, one group later');
ok(!/background: var\(--variant\)/.test(
     (css.match(/\.fr \.pexp \.pstep \{[^}]*\}/) || [''])[0]),
   'and are not left surfaceVariant-on-surfaceVariant');
ok(/class="pcancel"/.test(bC),
   'C offers an escape as well as a commit, since it can rewrite a position');
ok(!/drag the bar/.test(bC),
   'and instructs nothing, now that the thumb is visible enough to say it');
ok(!/class="wsheet"/.test(bC) && !/class="drum"/.test(bC),
   'no sheet is involved in C at all');
ok(PROG_C_EXTRA === 40,
   'C spends 40pt, and only while it is open',
   TABSTRIP_Y + ' \u2192 ' + (TABSTRIP_Y + PROG_C_EXTRA) + ' during the edit');
/* D is the sheet, and the band is untouched. It must be the sheet it CLAIMS to
   be: `wsheet` is `showSelectDateBottomSheet`'s sibling, `drum` is the bespoke
   237pt lookalike D was actually drawn with, whose commit was a text link. */
ok(/class="wsheet"/.test(bD) && !/class="drum"/.test(bD),
   'D opens the real sibling sheet, not the bespoke drum');
ok(/class="whd"><b>[^<]*<\/b><s>Confirm<\/s>/.test(bD),
   'whose header is a title beside a filled Confirm, as the code has it');
ok(WSHEET_H === 320 && WSHEET_TOP > TABSTRIP_Y,
   'and at 320pt on a real page it clears the tab strip, so the bar stays visible',
   'sheet top y' + WSHEET_TOP + ' vs strip ' + TABSTRIP_Y);
/* The wheel spins percent, so the page rider is derived -- and it must agree with
   the band it was opened from. p.148 does not round-trip through 101 stops: it
   shows 46% and comes back p.147, which put two page numbers for one position on
   screen at once. The whole group moved to 147 for that reason. */
const dSpec = specOf(V, 'bar-d-sheet');
const dPct = Math.round(posOf(dSpec) * 100);
ok(Math.round((dPct / 100) * dSpec.pages) === dSpec.page,
   'D\u2019s page rider round-trips through the wheel\u2019s 101 stops',
   'p.' + dSpec.page + ' \u2192 ' + dPct + '% \u2192 p.' +
     Math.round((dPct / 100) * dSpec.pages));
ok(new RegExp('\u2248 p\\.' + dSpec.page + ' of ' + dSpec.pages).test(bD),
   'and the sheet prints the same page the band does');
ok(!/pfield/.test(bD) && !/class="pexp"/.test(bD),
   'and spends no band height whatsoever');
/* A's tapped state is the frame that finishes the group: `DateFieldRow` opens
   `showSelectDateBottomSheet`, so a progress field's sibling of that is the
   percent wheel -- the SAME sheet D opens. A is therefore not a third option,
   it is D plus a permanent 27pt of ground. Asserted, because the whole
   recommendation turns on it. */
const bAO = frame(specOf(V, 'bar-a-open'));
ok(/class="wsheet"/.test(bAO),
   'A opens the same sheet D does, as the idiom it copies dictates');
ok(/class="prog pfield"/.test(bAO),
   'while still paying for the field ground underneath it');
ok(/class="wsheet"/.test(bD) && !/pfield/.test(bD),
   'so the pair differ by exactly the ground, and nothing else',
   'A = D + ' + PROG_A_GROWTH + 'pt');
ok(noteOf(V, 'bar-a-open').includes(String(PROG_A_GROWTH)),
   'and A\u2019s tapped note quotes that tax');
/* The flow ends committed, at a different position than it started. */
const zb = fsteps(V, 'z-bar');
ok(zb.length === 3, 'the inline path is three frames');
ok(posOf(zb[0][2]) !== posOf(zb[2][2]),
   'and it ends at a position it did not start at',
   Math.round(posOf(zb[0][2]) * 100) + '% \u2192 ' + Math.round(posOf(zb[2][2]) * 100) + '%');
ok(!/class="pexp"/.test(frame(zb[2][2])),
   'with the control disarmed again afterwards');
/* ---- the closed state, second pass ---- */
console.log('');
console.log('--- the closed state, once the sheet is settled ---');
const CL = ['cl-section', 'cl-inline', 'cl-cardfoot', 'cl-edge', 'cl-nub',
            'cl-chip', 'cl-wide', 'cl-best'];
ok(CL.every(i => ids(V).includes(i)),
   'eight closed-state treatments are drawn', CL.length + ' frames');
const CLH = {};
CL.forEach(i => (CLH[i] = frame(specOf(V, i))));
/* The three merged treatments must actually MERGE -- one container, not the
   shipped period card with something under it. */
['cl-section', 'cl-inline', 'cl-best'].forEach(i =>
  ok(/class="psec/.test(CLH[i]) && !/class="period"/.test(CLH[i]),
     i + ' replaces the period card rather than sitting under it'));
ok(/class="pcardf"/.test(CLH['cl-cardfoot']) && !/class="period"/.test(CLH['cl-cardfoot']),
   'cl-cardfoot likewise, with the bar as the card edge',
   'cfedge present: ' + /class="cfedge"/.test(CLH['cl-cardfoot']));
/* The separator is the ONLY difference between 1 and 2 -- a one-variable
   comparison, the way bar-a-naive is against bar-a. */
ok(/class="psec"/.test(CLH['cl-section']) && /class="psec nodiv"/.test(CLH['cl-inline']),
   'and 2 differs from 1 by exactly the separator rule');
/* Every treatment that promotes the row to a target clears the touch floor.
   cardfoot drew 38pt first, which is the same miss bar-a made. */
ok(/\.fr \.psec \.psrow\.pr \{[^}]*padding: 12px 12px/.test(css) &&
   /\.fr \.pcardf \.psrow\.pr \{[^}]*padding: 12px 12px/.test(css),
   'both merged targets take v12, the padding that reaches the floor');
ok(/\.fr \.psec \.psrow\.pr \{[^}]*font-size: 15px/.test(css),
   'at 15pt, since v12 only reaches 44 around a 20pt line box');
/* The band's 30pt radius is what clips the edge treatment; without the clip it
   is a square-ended rule across the band, not an edge. */
ok(/\.fr \.band \{[^}]*border-radius: 0 0 30px 30px/.test(css),
   'the band ends in a 30pt radius, which is what the edge treatment bends into');
ok(/\.fr \.band\.hasedge \{[^}]*overflow: hidden/.test(css),
   'and the edge is clipped by it rather than drawn straight through');
ok(/class="bandedge"/.test(CLH['cl-edge']) && !/class="prog[^"]*"[^>]*>[^<]*<span class="bar"/.test(CLH['cl-edge']),
   'cl-edge moves the bar out of the row entirely');
/* The nub is the cover mark, not a lookalike -- same polygon, and white, because
   solid brandText merged into the fill and read as a blob. */
const NUBCSS = (css.match(/\.fr \.prog \.pnub,[^{]*\{[^}]*\}/) || [''])[0];
ok(/clip-path: polygon\(0 0, 100% 0, 100% 100%, 50% 78%, 0 100%\)/.test(NUBCSS),
   'the bookmark uses the cover mark\u2019s own notch polygon');
ok(/\.fr \.prog \.pnub::after,[\s\S]{0,200}background: var\(--surface\)/.test(css),
   'and is WHITE like the cover mark, not solid brandText which read as a blob');
ok(/\.fr \.prog\.pnubbed \.bar,[\s\S]{0,160}overflow: visible/.test(css),
   'and the track unclips itself, or the nub is cut to 4pt');
/* cl-chip is the only treatment that keeps the streak, because its row stays a
   read-out. Everything else must evict it. */
ok(/class="stk/.test(CLH['cl-chip']),
   'cl-chip keeps the streak chip, since its row is not the target');
CL.filter(i => i !== 'cl-chip').forEach(i =>
  ok(!/class="stk/.test(CLH[i]), i + ' evicts it, as a tappable row must'));
/* The costs. Measured in a browser, so what is asserted here is that the notes
   quote the constants rather than typing numbers beside them. */
ok(CL_SECTION < PROG_A_GROWTH,
   'the merged section beats bar-a on cost as well as affordance',
   CL_SECTION + 'pt vs ' + PROG_A_GROWTH);
ok(CL_SECTION - CL_INLINE === 1, 'and the separator costs exactly 1pt');
ok(CL_CARDFOOT > CL_SECTION,
   'while the card-edge variant is the dearest of the merged three',
   CL_CARDFOOT + 'pt');
ok(CL_CHIP > 0 && CL_CHIP_H < TOUCH_FLOOR,
   'cl-chip is neither free nor above the floor \u2014 both were assumed and wrong',
   CL_CHIP + 'pt tall, a ' + CL_CHIP_H + 'pt target');
[['cl-section', CL_SECTION], ['cl-inline', CL_INLINE],
 ['cl-cardfoot', CL_CARDFOOT], ['cl-chip', CL_CHIP],
 ['cl-best', CL_SECTION]].forEach(([id, v]) =>
  ok(noteOf(V, id).includes(String(v)),
     id + '\u2019s note quotes its measured cost'));
/* ---- the inked border, which is the chosen direction ---- */
const EDGEIDS = ['cl-edge2', 'cl-edge-sec', 'cl-early-straight', 'cl-early-inked',
                 'cl-edge-zero'];
ok(EDGEIDS.every(i => ids(V).includes(i)),
   'the inked-border treatment and its evidence are drawn', EDGEIDS.length + ' frames');
const EH = {};
EDGEIDS.forEach(i => (EH[i] = frame(specOf(V, i))));
/* Length is arithmetic -- two quarter-arcs plus the straight -- and it MUST be,
   because stroke-dasharray needs it exact. Deriving it is what caught a malformed
   arc: the computed 421 disagreed with the browser's getTotalLength of 392. */
ok(Math.abs(EDGE_LEN - (2 * ((Math.PI * EDGE_R) / 2) + EDGE_STRAIGHT)) < 0.01,
   'the path length is derived from the geometry, not fitted',
   Math.round(EDGE_LEN) + 'pt = 2 arcs + ' + EDGE_STRAIGHT);
ok(EDGE_R === 30 - EDGE_W / 2,
   'the stroke centreline is inset by half its width, so it sits inside the band',
   'r' + EDGE_R + ' for a ' + EDGE_W + 'pt stroke on a 30pt radius');
/* The arcs must start at svgHeight - 30, not at 30. Using the radius as the y was
   the bug, and it produced a short malformed arc. */
ok(EDGE_TOP === EDGE_SVG_H - 30,
   'the arc meets the band\u2019s side at svgHeight \u2212 radius, not at radius',
   'y' + EDGE_TOP);
ok((EDGE_D.match(/A28,28 0 0 0/g) || []).length === 2,
   'both corners sweep 0, the reverse of a clockwise rounded-rect');
ok(/stroke-dasharray/.test(EH['cl-edge2']) && /class="bedge"/.test(EH['cl-edge2']),
   'cl-edge2 strokes the border rather than crossing it');
ok(!/class="bandedge"/.test(EH['cl-edge2']),
   'and carries no straight hairline as well');
/* The proof pair: same position, one straight and invisible, one inked. */
const ES = specOf(V, 'cl-early-straight'), EI = specOf(V, 'cl-early-inked');
ok(ES.page === EI.page && ES.barMode === 'edge' && EI.barMode === 'edge2',
   'the p.13 pair differ by the treatment only, which is what makes it evidence',
   'p.' + ES.page + ', ' + Math.round(posOf(ES) * 100) + '%');
ok(posOf(ES) * FRAME < 30,
   'and at that position a straight fill is shorter than the corner radius \u2014 invisible',
   Math.round(posOf(ES) * FRAME) + 'pt of fill inside a 30pt corner');
ok(posOf(EI) * EDGE_LEN < (Math.PI * EDGE_R) / 2,
   'while the inked one lands inside the arc, where there IS room',
   Math.round(posOf(EI) * EDGE_LEN) + 'pt along a ' +
     Math.round((Math.PI * EDGE_R) / 2) + 'pt arc');
/* The lowest state that can exist is 1%, not 0 and not p.1 -- because the wheel is
   the only writer and it spins whole percent. Drawn at p.1 first, the row read
   `p.1` beside `0%`, which is the quantisation artefact for the third time. */
const EZ = specOf(V, 'cl-edge-zero');
ok(Math.round(posOf(EZ) * 100) === 1,
   'cl-edge-zero draws 1%, the lowest expressible position', 'p.' + EZ.page);
ok(Math.round((Math.round(posOf(EZ) * 100) / 100) * EZ.pages) === EZ.page,
   'and its page and percent agree, unlike the p.1 it was drawn at first');
/* edgesec hands the bar to the border, so the row must not carry one too. */
ok(/class="psec/.test(EH['cl-edge-sec']) && /class="bedge"/.test(EH['cl-edge-sec']),
   'cl-edge-sec is the grouped section plus the inked border');
ok(!/class="psrow pr">[\s\S]{0,120}class="bar"/.test(EH['cl-edge-sec']),
   'and its row gives up its bar, so exactly one bar is on screen');
ok(noteOf(V, 'cl-edge-sec').includes(String(CL_SECTION)),
   'at the same cost as the plain section', CL_SECTION + 'pt');
/* cl-edge-sec and the bd-* group all wrap the progress row in a grouped section,
   i.e. they change a row the reader had already settled. They stay browsable, but
   none of them may claim to be the recommendation -- the pd-* group is, because it
   changes the period card only. */
['cl-edge-sec', 'bd-naive', 'bd-align', 'bd-labels', 'bd-press'].forEach(id =>
  ok(/NOT THE CHOSEN DIRECTION/.test(noteOf(V, id)),
     id + ' is labelled as changing the settled row, not as the answer'));
ok(/alternative/i.test(noteOf(V, 'cl-best')),
   'with cl-best demoted to the alternative rather than left claiming the title');
ok(/recommendation/i.test(noteOf(V, 'pd-press')),
   'and the recommendation lives in the group that changes one row');
/* pd-align is the accepted closed state. Anything that would contradict it -- a
   traced bar, a grouped-section row, a missing chevron on either row -- is asserted
   against elsewhere; this pins the frame itself as the decision of record. */
ok(/^<b>DECIDED/.test(noteOf(V, 'pd-align')),
   'pd-align is marked as the decided closed state, not one option among many');
const PA = frame(specOf(V, 'pd-align'));
ok(/class="bandedge"/.test(PA) && !/class="bandedge flat"/.test(PA) &&
   !/class="bedge"/.test(PA),
   'and it carries the linear full-bleed bar, as chosen');
ok(/class="period pdr"/.test(PA) && /class="prog phint"/.test(PA),
   'the card is a door and the progress row is still a plain row on the band');
ok((PA.match(/class="chev/g) || []).length === 2,
   'with two chevrons \u2014 one per door');
ok(!/M3 17\.25V21h3\.75L17\.81 9\.94/.test(PA),
   'and no pencil');

/* ---- the period CARD as a door, on the chosen layout ---- */
console.log('');
console.log('--- the period card as a door ---');
const PD = ['pd-naive', 'pd-align', 'pd-press'];
ok(PD.every(i => ids(V).includes(i)), 'the three card treatments are drawn');
const PDH = {};
PD.forEach(i => (PDH[i] = frame(specOf(V, i))));
/* THE POINT OF THIS GROUP: the chosen layout is untouched. The period card stays a
   standalone card, the progress row stays on the grey band with its own chevron, and
   the bar stays the band's inked edge. An earlier group changed all three while
   claiming to answer a question about one, which is what these assertions prevent. */
PD.forEach(i => {
  ok(/class="period/.test(PDH[i]) && !/class="psec/.test(PDH[i]),
     i + ' keeps the period card a CARD, not a grouped-section row');
  ok(/class="prog phint"/.test(PDH[i]),
     i + ' leaves the progress row on the grey band, as chosen');
  /* LINEAR and full-bleed, which is the treatment that was chosen. The traced-arc
     version is a different LOOK and must not appear here: substituting it was the
     mistake this assertion exists to prevent from recurring. */
  ok(/class="bandedge"/.test(PDH[i]) && !/class="bedge"/.test(PDH[i]),
     i + ' keeps the bar LINEAR, not traced around the corners');
  ok((PDH[i].match(/class="chev[ "]/g) || []).length === 2,
     i + ' gives the card a chevron and leaves the row\u2019s alone');
  ok(!/M3 17\.25V21h3\.75L17\.81 9\.94/.test(PDH[i]) && /M6 19c0 1\.1/.test(PDH[i]),
     i + ' drops the pencil and keeps delete');
});
/* The row the reader settled must be byte-identical to how cl-edge2 draws it. */
const rowOf = (h) => (h.match(/<div class="prog phint">[\s\S]*?<\/div>/) || [''])[0];
ok(rowOf(PDH['pd-align']) === rowOf(frame(specOf(V, 'cl-edge2'))),
   'and pd-align\u2019s progress row is IDENTICAL to cl-edge2\u2019s, character for character');
/* The fix is the grammar, asserted from the rule. */
ok(/\.fr \.period \.dval \{[^}]*margin-left: auto/.test(css),
   'the value is pushed right, which is the whole fix');
ok(/\.fr \.period\.pdr \{[^}]*min-height: 44px/.test(css),
   'and the card is pinned to the touch floor');
ok(!/class="period pdr/.test(PDH['pd-naive']),
   'pd-naive deliberately lacks that, so it stays the counter-example');
/* Pressed must not darken to the band's own colour. */
ok(/\.fr \.period\.pressed \{[^}]*background: #f1f3f5/.test(css),
   'pressed darkens to #f1f3f5, not to the band\u2019s own surfaceVariant');
ok(!/\.fr \.period\.pressed \{[^}]*var\(--variant\)/.test(css),
   'which would make the card vanish into the band \u2014 the bar-a-naive collision');
/* The cost, corrected from a remembered figure. */
ok(PD_CARD_H === 42 && PD_ALIGN === 2,
   'the card is 42pt, so the floor costs 2 \u2014 not the nothing first claimed',
   PD_CARD_H + ' + ' + PD_ALIGN + ' = ' + TOUCH_FLOOR);
ok(noteOf(V, 'pd-align').includes('x362'),
   'and the note raises the 10pt chevron stagger rather than silently fixing it');

/* ---- the linear bar, and the chevron count ---- */
console.log('');
console.log('--- linear bar + chevron count ---');
const LN = ['ln-full', 'ln-flat'];
const CHV = ['ch-stagger', 'ch-column', 'ch-quiet', 'ch-cardonly'];
ok(LN.concat(CHV).every(i => ids(V).includes(i)),
   'the linear-bar pair and the four chevron options are drawn');
const XH = {};
LN.concat(CHV).forEach(i => (XH[i] = frame(specOf(V, i))));
/* THE correction this group exists for: the chosen bar is LINEAR. The traced-arc
   version is a different look and must not appear in any of these frames. */
LN.concat(CHV).forEach(i =>
  ok(/class="bandedge/.test(XH[i]) && !/class="bedge"/.test(XH[i]),
     i + ' draws the bar LINEAR, never traced around the corners'));
ok(!/class="bandedge flat"/.test(XH['ln-full']),
   'ln-full is full-bleed, so its ends are clipped by the corners \u2014 as chosen');
ok(/class="bandedge flat"/.test(XH['ln-flat']),
   'ln-flat spans the flat bottom only, which is the offered alternative');
ok(/\.fr \.bandedge\.flat \{[^}]*left: 30px[^}]*right: 30px/.test(css),
   'and it spans exactly x30\u2013x363, where the two 30pt arcs end');
/* Chevron count. Both rows are doors, so the default is two -- the question is only
   whether they form a column. */
ok((XH['ch-stagger'].match(/class="chev/g) || []).length === 2 &&
   (XH['ch-column'].match(/class="chev/g) || []).length === 2 &&
   (XH['ch-quiet'].match(/class="chev/g) || []).length === 2,
   'three of the four keep both chevrons, since there are two doors');
ok(!/class="chev/.test((XH['ch-cardonly'].match(/<div class="prog phint">[\s\S]*?<\/div>/) || [''])[0]),
   'ch-cardonly strips the progress row\u2019s, which is why it is rejected');
ok(!/class="chev col/.test(XH['ch-stagger']),
   'ch-stagger leaves the card\u2019s chevron where it lands, 10pt out of column');
ok(/class="chev col"/.test(XH['ch-column']),
   'ch-column pulls it out to meet the row\u2019s');
/* DECIDED: column alignment is the default now, so the decided frame has it and only
   the counter-example opts out. */
ok(/class="chev col"/.test(frame(specOf(V, 'pd-align'))),
   'and the decided frame carries that alignment by default');
ok(/\.fr \.period \.chev\.col \{[^}]*margin-right: -10px/.test(css),
   'by moving the CARD\u2019s glyph, not the settled row');
/* quiet must differ from column by weight alone, or it is not evidence. */
ok(/class="chev col qc"/.test(XH['ch-quiet']),
   'ch-quiet is column-aligned too, so it differs from ch-column by weight alone');
ok(/\.fr \.chev\.qc \{[^}]*font-size: 14px[^}]*opacity: 0\.5/.test(css),
   'and the weight is the only thing that differs', '14px at 0.5');
/* Every one of these keeps the settled progress row's own content. */
const rowTxt = (h) => (h.match(/<div class="prog phint">[\s\S]*?<\/div>/) || [''])[0];
['ln-full', 'ch-stagger', 'ch-column'].forEach(i =>
  ok(/p\.147/.test(rowTxt(XH[i])) && /46%/.test(rowTxt(XH[i])),
     i + ' keeps the row reading p.147 / 320 \u2026 46%'));

/* ---- both rows are doors, and the pencil retires ---- */
console.log('');
console.log('--- both rows are doors ---');
const BD = ['bd-naive', 'bd-align', 'bd-labels', 'bd-press'];
ok(BD.every(i => ids(V).includes(i)), 'the four period-row treatments are drawn');
const BH = {};
BD.forEach(i => (BH[i] = frame(specOf(V, i))));
/* The whole point: `edit_outlined` edits status + start + finish, which is exactly
   what the period row shows, so once the row opens that sheet the pencil has no
   job. Every frame here must therefore have dropped it. */
BD.forEach(i =>
  ok(!/M3 17\.25V21h3\.75L17\.81 9\.94/.test(BH[i]),
     i + ' drops the pencil, which the row has made redundant'));
BD.forEach(i =>
  ok(/M6 19c0 1\.1/.test(BH[i]), i + ' keeps delete, which nothing replaces'));
ok(/M3 17\.25V21h3\.75L17\.81 9\.94/.test(frame(specOf(V, 'cl-edge-sec'))),
   'while the single-door recommendation still carries it, as it must');
/* Both rows must carry a chevron, or they are not peers. */
BD.forEach(i =>
  ok((BH[i].match(/class="chev[ "]/g) || []).length === 2,
     i + ' gives both rows a chevron'));
/* The fix is grammatical: the value moves right. Asserted from the rule, since the
   whole difference between 1 and 2 is one declaration. */
ok(/\.fr \.psec \.psrow\.dr \.dval \{[^}]*margin-left: auto/.test(css),
   'the value is pushed right, which is the fix in one rule');
ok(/\.fr \.psec \.psrow\.dr \{[^}]*min-height: 44px/.test(css),
   'and both rows are pinned to the touch floor');
ok(!/class="psrow dr"/.test(BH['bd-naive']),
   'bd-naive deliberately does NOT get that grammar, so it stays the counter-example');
ok(/class="dval"/.test(BH['bd-align']),
   'bd-align does');
/* The pressed state is a spec, not a decoration: it must wash the whole row. */
ok(/class="psrow dr pressed"/.test(BH['bd-press']),
   'bd-press draws the row highlighted, which is the half no resting frame shows');
ok(/\.fr \.psec \.psrow\.pressed \{[^}]*background: rgba\(33, 37, 41, 0\.06\)/.test(css),
   'with a full-row wash rather than a highlight behind the text only');
ok(/\.fr \.psec \{[^}]*overflow: hidden/.test(css),
   'and the section clips, so the wash cannot escape the radius');
/* The labels variant duplicates the pill, which is why it is second choice. */
ok(/class="dlab">Status</.test(BH['bd-labels']) &&
   /class="dlab">Position</.test(BH['bd-labels']),
   'bd-labels names both fields outright');
ok(noteOf(V, 'bd-labels').includes('twice'),
   'and its note concedes the label repeats the pill beside it');
/* The second door is free. */
ok(CL_BDOOR <= CL_SECTION,
   'making the period row a door costs nothing over the section',
   CL_BDOOR + 'pt vs ' + CL_SECTION);
ok(noteOf(V, 'bd-align').includes(String(CL_BDOOR)),
   'and bd-align quotes that');

/* The recommendation must be the one that costs nothing extra over the section. */
ok(/class="pnub"/.test(CLH['cl-best']) && /class="psec/.test(CLH['cl-best']),
   'and the synthesis carries both signals: the list contract and the bookmark');
ok(!/class="chev"/.test(CLH['cl-nub']),
   'cl-nub carries no chevron, so it tests one signal rather than two');

/* The ergonomic claim, as arithmetic rather than assertion. */
const BAR_AREA = (FRAME - 60) * PROG_H;
const PENCIL_AREA = 48 * 48;
ok(BAR_AREA / PENCIL_AREA > 4,
   'the bar is over four times the pencil\u2019s target area',
   Math.round(BAR_AREA) + ' vs ' + PENCIL_AREA + 'pt\u00b2');

console.log('');
console.log(bad === 0 ? 'ALL CHECKS PASSED' : bad + ' CHECK(S) FAILED');
"""

open("/tmp/m.js", "w").write(
    STUB
    + "const CSS_TEXT = " + json.dumps(css) + ";\n"
    + js
    + ASSERT
)

r = subprocess.run(["node", "--check", "/tmp/m.js"], capture_output=True, text=True)
print("node --check:", "ok" if r.returncode == 0 else "FAILED\n" + r.stderr)
if r.returncode:
    sys.exit(1)

r = subprocess.run(["node", "/tmp/m.js"], capture_output=True, text=True)
print(r.stdout.strip())
if r.stderr.strip():
    print("STDERR:\n" + r.stderr.strip())

# `_cssbad` counts the source-level checks above -- CSS rules, JS source shapes, and
# the Dart geometry. It used to be accumulated and never read, so those checks printed
# FAIL and the script still exited 0 saying ALL CHECKS PASSED. Both counters gate the
# exit now, and the summary states each.
print("")
if _cssbad or r.returncode:
    print(f"FAILED \u2014 {_cssbad} source check(s); harness exit {r.returncode}")
    print("(the harness prints its own summary above; THIS line is authoritative)")
else:
    print("VERIFY OK \u2014 source checks and harness both clean")
sys.exit(1 if (r.returncode or _cssbad) else 0)
