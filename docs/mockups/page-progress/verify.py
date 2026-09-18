"""Terminal verification for the exact-page-entry mockup set.

Three layers, because each catches a different class of mistake:

  1. Python checks the STYLESHEET, which the JS harness cannot see.
  2. Python cross-checks the drawing against the real Dart source. This page is
     drawn at 1pt = 1px, so every metric in the CSS is claimed to be the number
     in the code — that claim is worth nothing unless it is enforced here.
  3. Node runs the page's own script against a DOM stub, renders every screen,
     and asserts the arithmetic the notes argue from plus real search queries.

    python3 docs/mockups/page-progress/verify.py

What it cannot check: anything visual, and every interaction. Two real defects
on the sibling streaks page got past earlier versions of its script — a
box-shadow clipped away by clip-path, and an entire invented ribbon colour.
Open the page.
"""

import pathlib
import re
import subprocess
import sys

SRC = "docs/mockups/page-progress/index.html"
ROOT = pathlib.Path(".")

html = pathlib.Path(SRC).read_text()
m = re.search(r"<script>\s*\n(.*?)\n\s*</script>", html, re.S)
if not m:
    sys.exit("could not find the script block")
js = m.group(1)

fails = []


def ok(cond, label, detail=""):
    print(("  ok   " if cond else "  FAIL ") + label + (f"   [{detail}]" if detail else ""))
    if not cond:
        fails.append(label)


print("script lines:", js.count("\n") + 1)
print("backticks:", "ok" if js.count("`") % 2 == 0 else "ODD")
if js.count("`") % 2:
    fails.append("odd backticks")

# ----------------------------------------------------------------- 1. the CSS
print("\n--- stylesheet ---")
css = html[html.index("<style>") : html.index("</style>")]

ok("--pt: 1px" in css, "scale is 1pt = 1px")
ok("calc(390 * var(--pt))" in css, "frame is 390pt wide")
# Every sheet metric must be expressed through --pt, or it silently stops
# scaling in compare mode and flow steps.
for n, what in [
    (24, "sheet corner radius"),
    (36, "rider height"),
    (92, "Confirm width"),
    (32, "Confirm height"),
    (10, "band row text inset"),
    (30, "band bottom corner radius"),
    (4, "progress edge thickness"),
]:
    ok(f"calc({n} * var(--pt))" in css, f"{what} = {n}, via --pt")

ok(
    css.count("var(--pt)") > 90,
    "the whole sheet is expressed in --pt, not raw px",
    f"{css.count('var(--pt)')} uses",
)
# The collision that would silently restyle the page's own version button.
ok(
    "min-width: calc(110 * var(--pt))" in css,
    "the header segment's 110pt floor is the same 110 the note measures",
)
ok(
    "347 into" in html and "129" in html,
    "seg-header quotes its browser measurements rather than an estimate",
)
ok(
    "system-ui</code>, not" in html and "Pretendard" in html,
    "the page admits it cannot render the app's font",
)
ok("outline: 1px solid" in css, "the frame uses an outline, so 390 means 390")
ok(
    ".bchev {" in css and not re.search(r"(?m)^\s*\.chev\s*\{", css),
    "band chevron does not squat on the page's .chev",
)  # indentation-agnostic: prettier reflows this file, and an indented literal
   # made this check vacuous once already.
ok("opacity: 0.447" in css, "off-centre rows use the framework's own fade constant")
ok("showDragHandle" in css, "the no-drag-handle finding is recorded where someone would draw one")

# ------------------------------------------------- 2. cross-check the Dart
print("\n--- does the drawing match the code? ---")


def src(p):
    f = ROOT / p
    if not f.exists():
        fails.append(f"missing source {p}")
        return ""
    return f.read_text()


percent = src("lib/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart")
theme = src("lib/constants/app_theme.dart")
styles = src("lib/constants/app_text_styles.dart")
brow = src("lib/ui/widgets/band_progress_row.dart")
bedge = src("lib/ui/widgets/band_progress_edge.dart")
prow = src("lib/ui/widgets/progress_field_row.dart")
en = src("lib/l10n/app_en.arb")
ko = src("lib/l10n/app_ko.arb")

ok("const int kProgressWheelStops = 101;" in percent, "101 stops is real")
ok("const double _kItemExtent = 34;" in percent, "extent 34 is real")
# The sheet's height stopped being a literal when the keypad gave it a third state:
# it is now a sum, so the states cannot drift apart. Check the terms rather than the
# total, and check that they still add back up to the 320 the drawing is built on.
ok(
    all(
        f"const {n} = {v};" in percent
        for n, v in [("header", "64.0"), ("wheel", "220.0"), ("rider", "36.0")]
    ),
    "sheet height 320 is real, as header 64 + wheel 220 + rider 36",
)
ok(64 + 220 + 36 == 320, "...and those three add up")
ok(
    "const segment = 48.0;" in percent,
    "the segment's 48pt cost is real",
)
ok(
    all(
        f"const double _k{n} = {v};" in percent
        for n, v in [("FieldHeight", "56"), ("ClampHeight", "18")]
    ),
    "the typing state's 56 + 18 are real",
)
ok(
    "_kKeypadHeight" not in percent and "_Keypad" not in percent,
    "the self-drawn keypad is gone, not merely unused",
)
ok(
    "keyboardType: TextInputType.number" in percent
    and "CupertinoTextField.borderless" in percent,
    "typing goes through a real field on the platform's number pad",
)
ok(
    "MediaQuery.viewInsetsOf(context).bottom" in percent,
    "the sheet lifts clear of the pad rather than being covered by it",
)
# Some checks below are about what the file *does*, and this file deliberately
# discusses what it no longer does — the reversals are recorded in prose. Matching
# against comments made two of these assertions fail on their own documentation, so
# strip them first.
def code_only(src):
    out = []
    for line in src.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("///") or stripped.startswith("//"):
            continue
        out.append(line)
    return "\n".join(out)


percent_code = code_only(percent)

ok(
    "isScrollControlled: true" in percent,
    "the cap is lifted, so any pad height fits under the sheet",
)
# One wheel for both modes, and the invariants that keeps honest.
ok(
    "GlassSegmentedControl(" in percent_code
    and "CupertinoSlidingSegmentedControl" not in percent_code,
    "the mode segment is the shared glass control, not a one-off",
)
ok(
    percent_code.count("CupertinoPicker.builder(") == 1
    and "CupertinoPicker(" not in percent_code,
    "there is exactly one wheel, shared by both modes",
)
ok(
    "key: ValueKey(_mode)" in percent,
    "...keyed by mode, so a switch cannot absorb the other mode's scroll offset",
)
ok(
    "behavior: HitTestBehavior.translucent" in percent,
    "...and its centre tap target does not block dragging the centre row",
)
ok(
    "_RangeFormatter({required this.min, required this.max})" in percent,
    "the clamp is parameterised, because percent floors at 0 and pages at 1",
)
ok(
    "_typing ? MediaQuery.viewInsetsOf(context).bottom : 0" in percent,
    "the inset is dropped with the mode, so dismissing the pad cannot balloon the sheet",
)
# The drawn pad must be the measured height, not the 216 that misled the first pass.
# Scoped to the `.syskb` rule: there is an unrelated `216px` grid column elsewhere in
# this stylesheet, and a whole-file search for "216" matches it.
_syskb = css.split(".syskb {", 1)[-1].split("}", 1)[0]
ok(
    "calc(290 * var(--pt))" in _syskb and "216" not in _syskb,
    "the drawing uses the measured pad height, not the 216 that misled it",
)
ok(
    64 + 48 + 56 + 18 + 36 == 222,
    "the typing state is 222pt, because the pad is not sheet content",
)
ok("width: 92," in percent and "height: 32," in percent, "Confirm 92x32 is real")
ok("height: 36," in percent, "rider 36 is real")
# Whitespace-insensitive on purpose: `dart format` wraps this constructor across four
# lines once the surrounding indentation grows, and a substring check for the one-line
# form silently started failing when it did. Same lesson the index.html anchors learned.
ok(
    re.search(
        r"EdgeInsets\.symmetric\(\s*horizontal:\s*20,\s*vertical:\s*16,?\s*\)",
        percent,
    )
    is not None,
    "header padding 20/16 is real",
)
ok(
    "const double kSheetCornerRadius = 24;" in theme,
    "sheet corner radius 24 is real",
)
ok("const double kBandProgressRowTextInset = 10;" in brow, "the 10pt inset is real")
ok("const double kBookBandCornerRadius = 30;" in bedge, "band radius 30 is real")
ok("const double kBandProgressEdgeThickness = 4;" in bedge, "edge 4pt is real")
ok(
    "EdgeInsets.symmetric(horizontal: 14, vertical: 10)" in prow
    and "BorderRadius.circular(10)" in prow,
    "field row 14/10 at radius 10 is real",
)

# Colours. The page claims to have copied them; prove it rather than trusting it.
for tok, hexv in [
    ("secondaryText", "626A72"),
    ("brandText", "067657"),
    ("sheetBackground", "EFF5EF"),
    ("surfaceVariant", "E9ECEF"),
    ("primaryText", "212529"),
]:
    ok(
        f"{tok}: Color(0xff{hexv})" in theme,
        f"{tok} is #{hexv} in the theme",
    )
    ok(hexv.lower() in css, f"...and #{hexv} appears in the mockup CSS")

# The stale-token trap this page exists downstream of. Checked as a VALUE, not
# as a substring — the comment in SECTION 1a names the stale hex deliberately.
ok("--text2: #adb5bd" not in css, "the mockup does NOT carry the stale #ADB5BD secondaryText")
streaks = ROOT / "docs/mockups/streaks/index.html"
if streaks.exists() and "adb5bd" in streaks.read_text().lower():
    print(
        "  NOTE  docs/mockups/streaks/index.html still says secondaryText is #ADB5BD,\n"
        "        which is stale (it is #626A72, app_theme.dart:103) — and that page\n"
        "        claims its tokens are 'copied verbatim from AppColors.light'.\n"
        "        NOT a one-token fix, which is why it is only reported here: the\n"
        "        same hex also backs a measured contrast argument about the\n"
        "        Interested badge (1.66:1 fill, 1.23:1 border). Swapping the token\n"
        "        without re-measuring those two ratios would move the error rather\n"
        "        than fix it. Needs a deliberate pass on that page."
    )

# The token constraint that forces the whole `page-figure` argument.
tstyle = src("test/text_style_test.dart")
ok("fontSize" in tstyle, "text_style_test.dart really does police fontSize in lib/ui")
ok(
    "FontFeature.tabularFigures()" in styles,
    "tabular figures exist as a feature in the token file",
)
# figure is 30/w700 and tabular; subtitle is 17/w600 and is NOT.
fig = styles[styles.index("static const TextStyle figure") :][:400]
ok("fontSize: 30" in fig and "w700" in fig and "_tabular" in fig, "figure is 30/w700 tabular")
sub = styles[styles.index("static const TextStyle subtitle") :][:400]
ok("fontSize: 17" in sub and "w600" in sub and "_tabular" not in sub, "subtitle is 17/w600, NOT tabular")
tu = styles[styles.index("static const TextStyle titleUser") :][:400]
ok("fontSize: 22" in tu and "w600" in tu and "_tabular" not in tu, "titleUser is 22/w600, NOT tabular")

# The localization asymmetry the `page-bare` screen turns on. The ko ARB stores
# escapes, not literal UTF-8, so assert the escaped form that is really on disk.
ok('"progressPage": "p.{page}"' in en, "English progressPage puts the unit BEFORE the number")
ok(r'"progressPage": "{page}\ucabd"' in ko, "Korean progressPage puts it AFTER")
ok('"yearSuffix": ""' in en, "yearSuffix really is empty in English")
ok(
    r'"howFarIn": "\uc5b4\ub514\uae4c\uc9c0 \uc77d\uc5c8\ub098\uc694?"' in ko,
    "the Korean title that overflows the header is real",
)

# The recovered widget must still be recoverable, and still say what we claim.
blob = subprocess.run(
    ["git", "--no-pager", "show", "a89ce73:lib/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart"],
    capture_output=True,
    text=True,
).stdout
ok(bool(blob), "the deleted wheel is still recoverable at a89ce73")
ok("itemExtent: 80," in blob, "...and its extent really was 80")
ok("fontSize: isSelected ? 28 : 20," in blob, "...and the centre really was 28 against 20")
ok("width: 0.5," in blob, "...and the overlay hairline really was 0.5pt")
ok("showYearMonthFilterBottomSheet" in blob, "...and it really was its own nested sheet")
ok(
    "showYearMonthFilterBottomSheet" not in src("lib/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart"),
    "...and it really is gone from the working tree",
)
# The nesting precedent the kp-sheet note leans on.
status = src("lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart")
ok(
    "showSelectPercentBottomSheet" in status and "CNBottomSheet.show" in status,
    "sheet-from-sheet is already live, so kp-sheet's precedent is real",
)

# ------------------------------------------------------------ 3. run the page
print("\n--- run the script ---")
STUB = r"""
const mk = () => ({ _v:'', set innerHTML(v){this._v=v;}, get innerHTML(){return this._v;},
  textContent:'', hidden:false, value:'', placeholder:'', dataset:{}, style:{},
  classList:{toggle(){},add(){},remove(){},contains(){return false;}},
  addEventListener(){}, focus(){}, blur(){}, select(){}, contains(){return false;},
  querySelectorAll(){return [];}, querySelector(){return null;}, closest(){return null;},
  getBoundingClientRect(){return {top:0};}, scrollIntoView(){}, nextElementSibling:null,
  tagName:'DIV' });
global.document = { getElementById: () => mk(), querySelectorAll: () => [],
  querySelector: () => mk(),
  addEventListener(){}, body:{scrollHeight:1000}, activeElement:null };
global.window = { addEventListener(){}, scrollTo(){}, innerHeight:800, scrollY:0 };
global.requestAnimationFrame = (f) => f();
global.Event = class { constructor(t){ this.type = t; } };
"""

TESTS = r"""
let bad = 0;
function ok(c, label, detail) {
  console.log((c ? '  ok   ' : '  FAIL ') + label + (detail ? '   [' + detail + ']' : ''));
  if (!c) bad++;
}

/* ---- the geometry the notes argue from ---- */
console.log('--- geometry ---');
ok(SHEET_H === 320, 'sheet is 320');
ok(HDR_H === 64, 'header is 64 (16+16 around a 32pt pill)', HDR_H);
ok(WHEEL_H === 220, 'wheel gets 220', WHEEL_H);
ok(HDR_H + WHEEL_H + RIDER_H === SHEET_H, 'and the three add back up to 320');
ok(OLD_WHEEL_H === WHEEL_H, 'the recovered wheel box was independently the same 220');
ok(SHEET_MAX === 474.75, 'the non-scroll-controlled ceiling is 474.75', SHEET_MAX);
ok(SEG_COST === 48 && SHEET_H_SEG === 368, 'segment costs 48, sheet becomes 368');
ok(SHEET_H_SEG < SHEET_MAX, 'seg-under fits under the ceiling without a flag change');
/* The rejections must actually be true, or they are just assertions. One of them
   was not: see below. */
ok(64 + 48 + 56 + 212 + 36 === 416 && 416 < SHEET_MAX,
   'a self-drawn keypad in place would have fit');
ok(64 + 48 + WHEEL_H + 212 + 36 === 580 && 580 > SHEET_MAX, 'kp-below really does NOT fit');
/* kp-system's rejection was WRONG, and this is where that is recorded rather than
   quietly corrected. The original sum kept the wheel on screen — which is kp-below's
   layout, not this one. When the pad replaces the wheel the way a keypad would, the
   sheet is header + segment + field + clamp + rider and the pad is viewInsets, not
   sheet content. Assert BOTH: that the old arithmetic is what it was, and that it was
   answering the wrong question. */
const KP_SYS_OLD = 64 + 48 + WHEEL_H + 216;
ok(KP_SYS_OLD === 548 && KP_SYS_OLD > SHEET_MAX,
   'the old kp-system sum really was 548 and really did overflow', KP_SYS_OLD);
const KP_SYS_REAL = 64 + 48 + 56 + 18 + 36;
ok(KP_SYS_REAL === 222 && KP_SYS_REAL < SHEET_MAX,
   '...but the sheet it actually needs is 222, which fits', KP_SYS_REAL);
/* And the 216 in that sum was itself wrong, which is the defect this feature shipped.
   The pad carries letter sub-captions and sits above the home indicator: ~290. Under
   the 9/16 cap — which the inset is paid out of — that does NOT fit, which is why
   isScrollControlled is not optional here. */
ok(KP_SYS_REAL + 290 > SHEET_MAX,
   '...and a real ~290pt pad does NOT fit under the 9/16 cap, so the flag is required',
   `${KP_SYS_REAL + 290} > ${SHEET_MAX}`);
ok(KP_SYS_REAL + 290 < 844,
   '...though it clears the screen once the cap is lifted',
   `${KP_SYS_REAL + 290} of 844`);
ok(Math.abs((1 - Math.pow(1 - 0.32, 3)) - 0.686) < 0.001,
   'three stacked scrims really do reach ~0.69', (1 - Math.pow(1 - 0.32, 3)).toFixed(3));
ok(HDR_INNER === 350, 'header content width is 350', HDR_INNER);
/* seg-header's note quotes browser measurements. Tie the prose to arithmetic so
   a future edit cannot leave a number that no longer adds up. The first draft of
   that note claimed an overflow the drawing did not show. */
ok(129 + 8 + 110 + 8 + CONFIRM_W === 347, 'the measured header parts really do sum to 347');
ok(347 < HDR_INNER, '...which really does fit, by ' + (HDR_INNER - 347) + 'pt');

/* ---- the quantisation that motivates the whole thing ---- */
console.log('--- quantisation ---');
ok(PCT === 46, 'p.200 of 432 snaps to stop 46', PCT);
ok(RT200 === 199, 'p.200 round-trips to p.199', RT200);
ok(RT201 === 203, 'p.201 round-trips to p.203', RT201);
ok([200, 201, 202].every((p) => roundTrip(p, PAGES) !== p),
   'p.200, p.201 and p.202 are all unsayable on a 432-page book');
ok(reachable(PAGES) === 101 && REACH === 101, '101 stops reach 101 distinct pages of 432', REACH);
ok(reachable(80) === 81, 'and fewer than 101 on a book shorter than 101 pages', reachable(80));
ok(pageAt(0, PAGES) === 0 && pageAt(100, PAGES) === PAGES, 'the ends are exact');
/* Storing page/pageCount as a double must round-trip for every page of every
   size the note claims. This is the "no migration needed" claim. */
let rt = 0;
for (const total of [320, 432, 912, 1000]) {
  for (let p = 0; p <= total; p++) if (Math.round((p / total) * total) !== p) rt++;
}
ok(rt === 0, 'page/pageCount as a double round-trips exactly for 320/432/912/1000', rt + ' failures');
ok(TRAVEL === 14688, 'page mode is 14,688pt of scroll on a 432-page book', TRAVEL);
ok(TRAVEL_LONG === 31008, '...and 31,008 on a 912-page one', TRAVEL_LONG);

/* ---- every screen and step must render ---- */
console.log('--- render ---');
const allScreens = [];
for (const [g, items] of SCREENS) for (const it of items) allScreens.push([g, it]);
let rendered = 0, threw = 0;
const out = {};
for (const [g, it] of allScreens) {
  try { out[it[0]] = frame(it[3]); rendered++; } catch (e) { threw++; console.log('    threw:', it[0], e.message); }
}
ok(threw === 0 && rendered === allScreens.length, 'every screen renders', rendered + ' screens');
let steps = 0;
for (const [g, items] of FLOWS)
  for (const it of items)
    for (const st of it[3]) { try { frame(st[2]); steps++; } catch (e) { threw++; console.log('    step threw:', it[0], e.message); } }
ok(threw === 0, 'every flow step renders', steps + ' steps');
ok(ELEMENTS.flatMap(([g, l]) => l).length >= 9, 'the element gallery is populated',
   ELEMENTS.flatMap(([g, l]) => l).length + ' elements');

/* Ids must be unique per view, or filtering and versioning collide. */
const dupe = (xs) => xs.length !== new Set(xs).size;
ok(!dupe(allScreens.map(([g, it]) => it[0])), 'screen ids are unique');
ok(!dupe(FLOWS.flatMap(([g, l]) => l.map((i) => i[0]))), 'flow ids are unique');
ok(!dupe(ELEMENTS.flatMap(([g, l]) => l.map((i) => i[0]))), 'element ids are unique');

/* Wheel windows must be odd, or the centre falls between two rows. */
console.log('--- the drawing says what the note says ---');
ok(!/class="stop mid"[\s\S]*class="stop mid"/.test(out['today']),
   'a wheel has exactly one centred row');
ok(out['today'].includes('ovl ios') && !out['today'].includes('ovl rules'),
   'the shipped screen wears the iOS default overlay');
ok(out['page-figure'].includes('ovl rules'), 'the page-mode screens wear the recovered hairlines');
ok(!out['seg-none'].includes('class="seg'), 'the no-page-count screen draws NO segment at all');
ok(out['seg-none'].includes('rider empty'), '...and its rider is reserved but empty');
ok(out['seg-under'].includes('class="seg'), 'the recommended screen does draw one');
ok(!out['page-bare'].includes('class="unit'),
   'page-bare really is a bare numeral — no unit span in the row');
ok(out['page-bare'].includes('collabel'), '...with the unit as a static column label instead');
ok(out['page-recovered'].includes('class="unit'), 'page-recovered does carry the unit in the row');
ok(out['band-answered'].includes('p.200') && out['band-answered'].includes('/ 432'),
   'the landing state prints the exact page, not the quantised one');
ok(out['noop'].includes('p.199'), 'the no-op screen shows the page it silently walks back to');
ok(out['page-dark'].includes('dev dark'), 'the dark screen is actually dark');
/* Clamping was chosen over reject-and-explain, so the frame must no longer draw
   an error: the number is the clamped one, in the calm style, not red. */
ok(!out['kp-invalid'].includes('disp bad'),
   'the clamp is NOT drawn as an error state');
ok(out['kp-invalid'].includes('badmsg calm'),
   '...it explains itself in secondaryText instead');
ok(out['kp-invalid'].includes('>' + PAGES_BAND + '<') &&
   !out['kp-invalid'].includes('>999<'),
   '...and shows the clamped value, not the rejected one');
/* The whole point of --pt: nothing may be a raw pixel inside a frame. */
const rawpx = Object.values(out).join('').match(/style="[^"]*\d+px/g) || [];
ok(rawpx.length === 0, 'no frame smuggles a raw px value', rawpx.slice(0, 3).join(' '));

/* A page wheel must never draw a page that cannot exist. The set-exact flow
   really did draw p.-2, p.-1 and p.0 before pageWin learned to clamp. Checked
   across screens AND flow steps, because the defect was only in a step. */
const everyHTML = [
  ...Object.values(out),
  ...FLOWS.flatMap(([g, l]) => l.flatMap((it) => it[3].map((st) => frame(st[2])))),
].join('');
const nums = [...everyHTML.matchAll(/class="num">([^<]*)</g)].map((m) => m[1]);
const nonsense = nums.filter((n) => n !== '' && !/^\d+%?$/.test(n));
ok(nonsense.length === 0, 'no wheel row draws a negative or malformed number',
   nonsense.slice(0, 5).join(' '));
/* And the clamp must actually be doing something, or the guard is vacuous. */
ok(pageWin(1, 7, undefined, PAGES).filter((v) => v === '').length === 3,
   'the wheel at p.1 really does blank the three rows above it',
   JSON.stringify(pageWin(1, 7, undefined, PAGES)));
ok(pageWin(PAGES, 7, undefined, PAGES).filter((v) => v === '').length === 3,
   '...and the three below the last page');
ok(pageWin(200, 7, undefined, PAGES).every((v) => v !== ''),
   '...and blanks nothing in the middle of a book');
/* The percent wheel needs the same clamp, and its rider must agree with it. The
   first fix here centred the wheel on 3% to dodge negative percents, which then
   contradicted its own "= p.0" rider. */
ok(pctWin(0).filter((v) => v === '').length === 3,
   'the percent wheel at 0% blanks the three rows above it', JSON.stringify(pctWin(0)));
ok(pctWin(100).filter((v) => v === '').length === 3, '...and the three past 100%');
ok(pctWin(46).every((v) => v !== ''), '...and blanks nothing mid-range');
const pctStep = (() => {
  for (const [g, l] of FLOWS)
    for (const it of l) if (it[0] === 'set-exact') return it[3][2];
  return null;
})();
const pctWheel = pctStep[2].sheet.body.find((b) => b.t === 'wheel');
const pctRider = pctStep[2].sheet.body.find((b) => b.t === 'rider');
ok(pctWheel.vals[(pctWheel.vals.length - 1) / 2] === '0%',
   'the opening step is centred on 0%', pctWheel.vals.join('|'));
ok(/p\.0/.test(pctRider.v),
   '...and its rider says p.0, which is what 0% of any book is');

/* ---- OPEN callouts must point at ids that exist ---- */
const allIds = new Set([
  ...allScreens.map(([g, it]) => it[0]),
  ...FLOWS.flatMap(([g, l]) => l.map((i) => i[0])),
  ...ELEMENTS.flatMap(([g, l]) => l.map((i) => i[0])),
]);
const orphan = Object.keys(OPEN).filter((k) => !allIds.has(k));
ok(orphan.length === 0, 'every OPEN callout attaches to a real id', orphan.join(', '));
ok(Object.keys(OPEN).length >= 3, 'each decided question records its resolution inline, not only in prose',
   Object.keys(OPEN).length + ' callouts');

/* ---- the three settled decisions, asserted so they cannot quietly drift ---- */
console.log('--- settled decisions ---');
const noteOf = (id) => {
  for (const [g, items] of SCREENS) for (const it of items) if (it[0] === id) return it[2];
  return '';
};
const stepsOf = (id) => {
  for (const [g, l] of FLOWS) for (const it of l) if (it[0] === id) return it[3];
  return [];
};
/* 3. Percent is always the default. */
ok(!('seg-under' in OPEN), 'the default-mode question is closed');
ok(/default is Percent/.test(noteOf('seg-under')), '...and recorded as Percent');
const openStep = stepsOf('set-exact')[2];
const openSeg = (openStep[2].sheet.body || []).find((b) => b.t === 'seg');
ok(openSeg && openSeg.on === 'Percent',
   '...and the flow actually opens on Percent, not just says so', openSeg && openSeg.on);
ok(/p\.0/.test(openStep[1]),
   '...and the p.0 wart that default exposes is recorded', openStep[1].slice(0, 40));
/* 4. Clamp, with only the typed-0 question left. */
ok('kp-invalid' in OPEN && /typed <code>0<\/code>/.test(OPEN['kp-invalid']),
   'clamping is settled and the typed-0 question is recorded with it');
ok(/DECIDED: clamp/.test(noteOf('kp-invalid')), '...and the note says so');
/* 5. Page only when a page count exists AND the reader typed a page — which needs
   provenance. The note quotes collision rates; recompute them here, because a
   number in prose that nobody checks is how the seg-header claim went wrong. */
const collide = (total) => {
  let c = 0;
  for (let p = 1; p <= total; p++) if ((p * 100) % total === 0) c++;
  return (100 * c) / total;
};
ok(collide(PAGES).toFixed(1) === '0.9', 'collision on a 432-page book is 0.9%', collide(PAGES).toFixed(1));
ok(collide(PAGES_BAND) === 6.25, '...exactly 6.25% on a 320-page one', collide(PAGES_BAND));
ok(collide(200) === 50, '...50% on a 200-page one', collide(200));
ok(collide(100) === 100 && collide(50) === 100,
   '...and 100% on a 50- or 100-page one, which is what kills inference');
const rp = noteOf('row-progress');
ok(/0\.9%/.test(rp) && /6\.25%/.test(rp) && /50%/.test(rp) && /100%/.test(rp),
   'row-progress quotes all four rates');
ok(/costs a\s*\n?\s*migration|costs a migration/.test(rp),
   '...and admits the migration the rule costs');
ok(/storage<\/i> needs/.test(noteOf('band-answered')),
   'band-answered no longer claims the whole feature is migration-free');

/* 1 + 2. Type and row height are settled, and exactly one frame is the answer. */
ok(!('page-figure' in OPEN), 'the token-pair question is closed');
ok(!('page-recovered' in OPEN), 'the row-height question is closed');
const chosen = SCREENS.flatMap(([g, l]) => l).filter((it) => /THE CHOSEN DESIGN/.test(it[1]));
ok(chosen.length === 1 && chosen[0][0] === 'page-bare',
   'exactly one frame is marked as the chosen design',
   chosen.map((c) => c[0]).join(', '));
/* The chosen frame must actually BE the decision: figure type, extent 34 (the
   default, so unset), hairline overlay, no unit in the row, a column label. */
const cw = chosen[0][3].sheet.body.find((b) => b.t === 'wheel');
ok(cw.style === 'figure', '...drawn with the figure/subtitle pairing', cw.style);
ok((cw.ext || EXTENT) === 34, '...at extent 34', cw.ext || EXTENT);
ok(cw.ovl === 'rules', '...with the recovered hairlines', cw.ovl);
ok(!cw.unitOnMid && cw.collabel === 'Page',
   '...and a bare numeral beside a static column label');
ok(cw.vals.every((v) => typeof v === 'string'),
   '...with no per-row unit object at all');
/* And the losers must say so, or the page presents discarded options as live. */
const superseded = ['page-recovered', 'page-recovered-34', 'page-titleuser'];
superseded.forEach((id) =>
  ok(/SUPERSEDED/.test(noteOf(id)), id + ' is marked superseded'));
ok(/DECIDED on the type, superseded on the unit/.test(noteOf('page-figure')),
   'page-figure records that its type won and its unit did not');

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
const eHits = (q) => hits(ELEMENTS, (g, it) => stripTags(g + ' ' + it[1] + ' ' + it[2]), q);
const fHits = (q) => hits(FLOWS, (g, it) => flowSearchText(g, it[1], it[2], it[3]), q);
const has = (got, want) => want.every((w) => got.includes(w)) && got.length > 0;

ok(has(sHits('tabular'), ['page-figure', 'page-titleuser']), 'screens "tabular"', JSON.stringify(sHits('tabular')));
ok(has(sHits('korean'), ['seg-header', 'page-bare']), 'screens "korean"', JSON.stringify(sHits('korean')));
ok(has(sHits('ceiling'), ['seg-under', 'kp-below']), 'screens "ceiling"', JSON.stringify(sHits('ceiling')));
ok(has(sHits('keypad'), ['kp-inplace']), 'screens "keypad"', JSON.stringify(sHits('keypad')));
ok(has(sHits('page_count'), ['seg-none']), 'screens "page_count"', JSON.stringify(sHits('page_count')));
ok(has(sHits('migration'), ['band-answered']), 'screens "migration"', JSON.stringify(sHits('migration')));
ok(has(eHits('prefix'), ['el-unit']), 'elements "prefix"', JSON.stringify(eHits('prefix')));
ok(has(eHits('platform view'), ['el-seg']), 'elements "platform view"', JSON.stringify(eHits('platform view')));
ok(has(fHits('backwards'), ['noop-flow']), 'flows "backwards"', JSON.stringify(fHits('backwards')));
ok(has(fHits('majority'), ['pct-only']), 'flows "majority"', JSON.stringify(fHits('majority')));
/* Order-independent AND, per the engine's contract. */
ok(has(sHits('exact page'), ['band-answered']), 'multi-word search is order-independent');

/* ---- versions ---- */
console.log('--- versions ---');
ok(VERSIONS.length === 1 && VERSIONS[0][0] === 'main',
   'one version, so the selector hides itself', VERSIONS.map((v) => v[0]).join(', '));
ok(VERSIONS[0][3] === null, 'the root has a null parent');

console.log(bad ? '\nJS FAILURES: ' + bad : '\nJS OK');
if (bad) process.exit(1);
"""

pathlib.Path("/tmp/pp_run.js").write_text(STUB + js + TESTS)
r = subprocess.run(["node", "/tmp/pp_run.js"], capture_output=True, text=True)
print(r.stdout.rstrip())
if r.stderr.strip():
    print(r.stderr.rstrip())
if r.returncode != 0:
    fails.append("node harness")

print()
if fails:
    print("FAILURES (%d): %s" % (len(fails), "; ".join(fails)))
    sys.exit(1)
print("VERIFY OK")
