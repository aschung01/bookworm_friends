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
ok(has(sHits('freeze'), ['card-gap']), 'screens "freeze"');
ok(has(sHits('prompt'), ['ask-count']), 'screens "prompt"', JSON.stringify(sHits('prompt')));
ok(has(sHits('trailing'), ['friends-conflict']), 'screens "trailing"');
ok(has(fHits('rotateY'), ['turn-to-edge']), 'flows "rotateY"', JSON.stringify(fHits('rotateY')));
ok(has(fHits('rollover'), ['daily']), 'flows "rollover"');
console.log('NOTE  OPEN callout text is not indexed ->', JSON.stringify(fHits('4am')),
  '(expected [], inherited from the shared engine)');

/* ---- versions ---- */
console.log('--- versions ---');
const ALLV = ['mark-in-place', 'band-scrubber', 'chrome-right', 'fore-edge-3d'];
const ids = (v) => resolveView(v, 'screens').map(([g, items]) => items.map((i) => i[0])).flat();
ok(ids('mark-in-place').length === ids('fore-edge-3d').length,
   'unpatched screens inherit', ids('mark-in-place').length + ' each');
ok(ids('band-scrubber').length === ids('mark-in-place').length + 2,
   'band-scrubber adds the two drum screens',
   ids('band-scrubber').length + ' vs ' + ids('mark-in-place').length);
ok(!ids('mark-in-place').includes('drum'),
   'the added screens do not leak into the parent');
const specOf = (v, id) => {
  for (const [g, items] of resolveView(v, 'screens'))
    for (const it of items) if (it[0] === id) return it[3];
  return null;
};
ok(specOf('mark-in-place', 'due').anatomy !== specOf('chrome-right', 'due').anatomy,
   'anatomy is patched per version');
ok(specOf('fore-edge-3d', 'card-stamps').kind === 'card',
   'anatomy-independent screens survive the patch');
ok(resolveOpen('chrome-right').deadzone !== resolveOpen('mark-in-place').deadzone &&
   resolveOpen('fore-edge-3d').deadzone !== resolveOpen('mark-in-place').deadzone,
   'each version overrides the deadzone callout with its own text');

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

/* ---- rendering ---- */
console.log('--- render ---');
let n = 0, wrapped = 0, turned = 0, scrubbed = 0, drummed = 0, chipped = 0;
for (const v of ALLV)
  for (const [g, items] of resolveView(v, 'screens'))
    for (const it of items) {
      const h = frame(it[3]);
      if (/class="bm due"[^>]*><b><\/b><i><\/i>/.test(h)) wrapped++;
      if (/class="edge3d"/.test(h)) turned++;
      if (/class="scrub/.test(h)) scrubbed++;
      if (/class="drum"/.test(h)) drummed++;
      if (/class="chips"/.test(h)) chipped++;
      n++;
    }
for (const [g, items] of FLOWS)
  for (const it of items) for (const st of it[3]) { if (/class="edge3d"/.test(frame(st[2]))) turned++; n++; }
console.log('  frames rendered without throwing:', n);
/* The shadow only paints because the clip lives on an inner <b>; flattening
   that back to one element silently loses it, which happened once already. */
ok(wrapped > 0, 'due marks keep the clip wrapper and the hairline', wrapped + ' of them');
ok(turned > 0, 'the fore-edge presentation renders', turned + ' frames');
ok(scrubbed > 0, 'the band scrubber renders', scrubbed + ' frames');
ok(drummed === 2, 'exactly the two drum screens render one', drummed + ' frames');
ok(chipped > 0, 'the delta chips render', chipped + ' frames');
/* The thumb has the same wrapper/clip split as the cover mark, for the same
   reason: a notched shape's box-shadow shows through the notch. */
ok(/class="thumb"[^>]*><b><\/b>/.test(frame(specOf('band-scrubber', 'due'))),
   'the scrubber thumb keeps the clip wrapper');

console.log('');
console.log(bad === 0 ? 'ALL CHECKS PASSED' : bad + ' CHECK(S) FAILED');
"""

open("/tmp/m.js", "w").write(STUB + js + ASSERT)

r = subprocess.run(["node", "--check", "/tmp/m.js"], capture_output=True, text=True)
print("node --check:", "ok" if r.returncode == 0 else "FAILED\n" + r.stderr)
if r.returncode:
    sys.exit(1)

r = subprocess.run(["node", "/tmp/m.js"], capture_output=True, text=True)
print(r.stdout.strip())
if r.stderr.strip():
    print("STDERR:\n" + r.stderr.strip())
sys.exit(r.returncode)
