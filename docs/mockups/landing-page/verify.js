/*
 * Verifies index.html without a browser. Run from the project root:
 *
 *     node docs/mockups/landing-page/verify.js
 *
 * The page is static, so most of it can be checked here: the script parses, the
 * data resolves, version inheritance and the diff behave, search finds words a
 * reader can see, the renderers emit what the notes claim, and every emitted
 * string is balanced and escaped.
 *
 * Four guards exist because the bug happened, not because it might:
 *
 *   1. The web frames render inside the SAME .ph the app screens use, so a new
 *      class colliding with the shell's would silently restyle the app mockups.
 *   2. .step is a hard 170px, so a 206px desktop browser in a flow step would
 *      overflow it. No flow step may be a desktop spec.
 *   3. Page structure: exactly one spring and a trailing footer. Two springs
 *      floated a call to action mid-frame; zero left a footer unpinned under a
 *      third of an empty page. Both were invisible to every other check here and
 *      were caught by screenshotting.
 *   4. The shelves and the card must agree on the book count. The first draft
 *      had three shelves totalling 13 with 6 marked finished, beside a card
 *      reading 12.
 *
 * What it cannot check is what the page looks like. Layout needs eyes.
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

const m = src.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) {
  console.log("FAIL no script block found");
  process.exit(1);
}
const js = m[1];
ok("backticks balanced", js.split("`").length % 2 === 1);
ok("one generic .gone rule", /\.gone\s*\{\s*display:\s*none/.test(src));
ok(
  "the phone frame opts into flex rather than changing .ph",
  /\.ph\.web\s*\{/.test(src) && /\.ph\s*\{/.test(src),
);

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
  classList: { toggle() {}, add() {}, remove() {}, contains: () => false },
  addEventListener() {},
  focus() {},
  blur() {},
  select() {},
  contains: () => false,
  querySelectorAll: () => [],
  querySelector: () => null,
  closest: () => null,
  getBoundingClientRect: () => ({ top: 0 }),
  scrollIntoView() {},
  nextElementSibling: null,
  tagName: "DIV",
});
const nodes = new Map();
global.document = {
  getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, mk());
    return nodes.get(id);
  },
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

const assertions = String.raw`
console.log("load: ok");

/* ---- the shape of the page ---- */
const all = (v, k) => resolveView(v, k).flatMap(([, l]) => l);
const ids = (v, k) => all(v, k).map((i) => i[0]);
const specOf = (v, k, id) => all(v, k).find((i) => i[0] === id)[3];
const noteOf = (v, k, id) => all(v, k).find((i) => i[0] === id)[2];
ok("13 screens", ids("main", "screens").length === 13, String(ids("main","screens").length));
ok("4 flows", ids("main", "flows").length === 4, String(ids("main","flows").length));
ok("8 elements", ids("main", "elements").length === 8, String(ids("main","elements").length));
ok("5 open callouts", Object.keys(OPEN).length === 5, Object.keys(OPEN).join(","));

/* ---- guard 4: the shelves and the card agree ---- */
const finished = (rows) => rows.filter((r) => r[4]).reduce((a, r) => a + r[1], 0);
const total = (rows) => rows.reduce((a, r) => a + r[1], 0);
ok("rich: finished shelves match the card", finished(SHELVES3) === RICH.n, finished(SHELVES3) + " vs " + RICH.n);
ok("rich: shelf count matches the card", SHELVES3.length === RICH.shelves);
ok("rich: the library holds more than the card counts", total(SHELVES3) > RICH.n, String(total(SHELVES3)));
ok("median: finished shelves match the card", finished(SHELVES1) === MEDIAN.n);
ok("median: shelf count matches the card", SHELVES1.length === MEDIAN.shelves);

/* ---- search finds words a reader can see ---- */
function hits(q, kind) {
    const out = [];
    for (const [, items] of resolveView("main", kind))
        for (const [id, nm, ds] of items)
            if (matchWords(stripTags(nm + " " + (ds || "")).toLowerCase(), q.toLowerCase()))
                out.push(id);
    return out;
}
function flowHits(q) {
    const out = [];
    for (const [g, items] of FLOWS)
        for (const [id, nm, ds, steps] of items)
            if (matchWords(flowSearchText(g, nm, ds, steps), q.toLowerCase()))
                out.push(id);
    return out;
}
ok("search 'hsts'", hits("hsts", "screens").includes("land-5a"), hits("hsts","screens").join(","));
ok("search 'byte-identical'", hits("byte-identical", "screens").includes("lib-private"), hits("byte-identical","screens").join(","));
ok("search 'face-out'", hits("face-out", "screens").includes("lib-mobile"), hits("face-out","screens").join(","));
ok("search 'enumerate'", hits("enumerate", "screens").includes("lib-private"), hits("enumerate","screens").join(","));
ok("search 'anon'", hits("anon", "elements").includes("el-anon"), hits("anon","elements").join(","));
ok("search 'web_public'", hits("web_public", "elements").includes("el-consent"), hits("web_public","elements").join(","));
ok("search 'generatedcover'", hits("generatedcover", "elements").includes("el-cover"), hits("generatedcover","elements").join(","));
ok("search 'screenshotted'", flowHits("screenshotted").includes("f-typed"), flowHits("screenshotted").join(","));
ok("search 'religion'", flowHits("religion").includes("f-crawler"), flowHits("religion").join(","));
ok("search 'pkce'", flowHits("pkce").includes("f-installed"), flowHits("pkce").join(","));

/* ---- the card is off the profile and on its own route ----
   The whole point of this revision. The profile carries the card's figures and a
   link; the artifact itself lives at /@handle/card, where it is drawn about two
   and a half times larger because nothing competes for the height. */
const card = frame(specOf("main", "screens", "lib-card"));
const inline = frame(specOf("main", "screens", "lib-inline"));
const libP = frame(specOf("main", "screens", "lib-mobile"));
ok("the profile carries no artifact", !libP.includes("amrz") && !libP.includes('class="art'));
ok("the profile carries the card's figures instead", libP.includes('class="wstat"') && libP.includes(">12<"));
ok("the profile links to the card's route", libP.includes('class="wcard"'));
ok("the card route carries the artifact", card.includes("amrz") && card.includes('class="art'));
ok("the card route carries nothing else", !card.includes('class="shf"') && !card.includes('class="wstat"'));
ok("the card route is a fold-fitting page", card.includes('class="wft"') && !card.includes('class="wstick"'));
ok("the card is drawn larger on its own route than it was inline", U_CARD > U_PHONE);
ok("the superseded stack is kept, and still shows the problem",
   inline.includes('class="wwho"') && inline.includes("amrz") && inline.includes('class="shf"'));
ok("the strip it prints is the address the visitor is already at",
   inline.includes("LIBSTACK.APP/@PAPER_FOX_412") && specOf("main","screens","lib-inline").web.url === "libstack.app/@paper_fox_412");

/* ---- the two alternatives differ in the way their notes claim ---- */
const heroP = frame(specOf("card-hero", "screens", "lib-mobile"));
const modalP = frame(specOf("card-modal", "screens", "lib-mobile"));
ok("card-hero replaces the profile head rather than adding to it",
   heroP.includes("amrz") && !heroP.includes('class="wwho"') && !heroP.includes('class="wstat"'));
ok("card-hero keeps the shelves", heroP.includes('class="shf"'));
ok("card-modal keeps main's profile and overlays the card",
   modalP.includes('class="wwho"') && modalP.includes('class="wstat"') && modalP.includes('class="wmod"'));
ok("card-modal's URL is unchanged, which is the objection to it",
   specOf("card-modal", "screens", "lib-mobile").web.url === specOf("main", "screens", "lib-mobile").web.url);
ok("both alternatives remove the card route, since neither has one",
   !ids("card-hero", "screens").includes("lib-card") && !ids("card-modal", "screens").includes("lib-card"));

/* ---- versions: inheritance, override, and a diff that reads both ways ---- */
const mainIds = ids("main", "screens");
const gridIds = ids("web-grid", "screens");
ok("web-grid adds and removes nothing", mainIds.length === gridIds.length && mainIds.every((i) => gridIds.includes(i)));
ok("main is not a grid", !JSON.stringify(specOf("main", "screens", "lib-mobile")).includes("grid"));
ok("web-grid is", JSON.stringify(specOf("web-grid", "screens", "lib-mobile")).includes("grid"));
ok("a patched note overrides", noteOf("main", "screens", "lib-mobile") !== noteOf("web-grid", "screens", "lib-mobile"));
ok("an unpatched note is inherited", noteOf("main", "screens", "lib-private") === noteOf("web-grid", "screens", "lib-private"));
const d1 = diffMap("main", "web-grid", "screens");
const d2 = diffMap("web-grid", "main", "screens");
ok("the three patched screens read changed both ways",
   ["lib-mobile","lib-desktop","lib-median"].every((i) => d1.get(i) === "changed" && d2.get(i) === "changed"));
ok("nothing is only-here or only-there", ![...d1.values(), ...d2.values()].some((x) => x === "onlyHere" || x === "onlyThere"));
ok("an unpatched screen is not reported as changed", d1.get("lib-installed") === undefined, String(d1.get("lib-installed")));

/* ---- every open callout reaches the DOM of the view that owns it ---- */
const OWNER = { screens: "screens", flows: "flows", elements: "elements" };
for (const v of ["main", "web-grid", "card-hero", "card-modal"]) {
    activeV = v;
    render();
    for (const [key, text] of Object.entries(resolveOpen(v))) {
        const kind = ["screens", "flows", "elements"].find((k) => ids(v, k).includes(key));
        ok(v + ": OPEN '" + key + "' belongs to something", !!kind, kind);
        if (!kind) continue;
        const html = document.getElementById(OWNER[kind]).innerHTML;
        ok(v + ": OPEN '" + key + "' renders in " + kind,
           html.includes('class="pend"') && html.includes(text.slice(0, 60)));
    }
}
activeV = "main";
render();

/* ---- the renderers emit what the notes claim ---- */
const land = frame(specOf("main", "screens", "land-desktop"));
const hold = frame(specOf("main", "screens", "land-5a"));
const lib = frame(specOf("main", "screens", "lib-mobile"));
const libM = frame(specOf("main", "screens", "lib-median"));
const libGrid = frame(specOf("web-grid", "screens", "lib-mobile"));

ok("the landing page leads with a hero, not a small mark", land.includes('class="wmk lg"'));
ok("the landing page shows the app, not the card", land.includes('class="wshots"') && !land.includes("amrz"));
ok("5a offers notify and no store badge", hold.includes('class="wnot"') && !hold.includes('class="wst"'));
ok("the listed landing page offers badges and no notify", land.includes('class="wst"') && !land.includes('class="wnot"'));

// The library page is a library, not a picture of one.
ok("the library draws the app's own plank", lib.includes('class="shf"'));
ok("the library draws face-out covers", (lib.match(/class="bk"/g) || []).length === 14, String((lib.match(/class="bk"/g) || []).length));
ok("the library names the reader's shelves", lib.includes('class="sl"') && lib.includes("Finished 2026"));
ok("the library heads with handle and counts", lib.includes('class="wwho"') && lib.includes("@paper_fox_412"));
ok("the library offers a way into the app", lib.includes('class="wstick"'));
ok("the median library is thin but still a shelf", libM.includes('class="shf"') && (libM.match(/class="bk"/g) || []).length === 2);

// web-grid: same books, shelf structure discarded.
ok("web-grid drops the plank", !libGrid.includes('class="shf"') && libGrid.includes('class="wgrid"'));
ok("web-grid drops the shelf names", !libGrid.includes('class="sl"'));
ok("web-grid keeps every book", (libGrid.match(/class="bk"/g) || []).length === 14, String((libGrid.match(/class="bk"/g) || []).length));

// Memos are drawn only to be struck out.
const memos = frame(specOf("main", "screens", "lib-memos"));
ok("the memo screen strikes the memo out", memos.includes("wmemo out") && memos.includes("excluded from the web client"));
ok("no other page renders a memo", !lib.includes("wmemo") && !land.includes("wmemo"));

const bannerP = frame(specOf("main", "screens", "lib-installed"));
ok("'banner' sits above the page's own content", bannerP.indexOf('class="wbn"') < bannerP.indexOf('class="wwho"'));

/* ---- the privacy property, asserted on the rendered body ---- */
const errOf = (h) => (h.match(/<div class="werr">.*?<\/div>/) || [""])[0];
const ePriv = errOf(frame(specOf("main", "screens", "lib-private")));
ok("the refusal page names neither cause", ePriv !== "" && /may be wrong/.test(ePriv) && /not made theirs public/.test(ePriv));
ok("it does not say the word private about the reader", !/is private/.test(ePriv));

/* ---- guards 2 and 3: frames, the 170px cap, and page structure ---- */
const webSpecs = [];
for (const kind of ["screens", "flows"])
    for (const [id, , , payload] of all("main", kind)) {
        const list = kind === "flows" ? payload.map((st) => st[2]) : [payload];
        list.forEach((s, i) => {
            const h = frame(s);
            ok(id + "#" + i + " has a known frame prefix",
               h.startsWith('<div class="ph') || h.startsWith('<div class="br"'));
            if (s.web) {
                webSpecs.push(s.web);
                ok(id + "#" + i + ": a web spec draws a browser or a webview",
                   s.web.desktop ? h.startsWith('<div class="br"') : h.startsWith('<div class="ph web'));
            }
            if (kind === "flows")
                ok(id + "#" + i + " is not a desktop frame in a flow step", !(s.web && s.web.desktop));
        });
    }
ok("every page ends with its footer",
   webSpecs.every((w) => w.blocks[w.blocks.length - 1].t === "foot"));
ok("every page has exactly one spring",
   webSpecs.every((w) => w.blocks.filter((b) => b.t === "sp").length === 1),
   webSpecs.map((w) => w.blocks.filter((b) => b.t === "sp").length).join(","));
/* A scrolling page keeps the footer in the document and adds a sticky bar over
   it: on a rich library the spring collapses and both footer and spring clip
   below the fold, and on the median reader's two-book page there is room and
   they show. One block list, two outcomes. The sticky bar exists because a
   footer CTA on a page taller than the viewport is a CTA nobody sees -- forcing
   the library page to fit the fold instead clipped its footer away entirely,
   which was caught by screenshotting and by nothing else in this file. */
ok("every scrolling page carries a sticky bar",
   webSpecs.filter((w) => w.scroll).every((w) => w.sticky === true));
ok("no fold-fitting page carries one",
   webSpecs.filter((w) => !w.scroll).every((w) => !w.sticky));
ok("the scrolling pages are exactly the ones with shelves",
   webSpecs.filter((w) => w.scroll).length >= 6 &&
   webSpecs.filter((w) => w.scroll).every((w) => w.blocks.some((b) => b.t === "shelves")) &&
   webSpecs.filter((w) => !w.scroll).every((w) => !w.blocks.some((b) => b.t === "shelves")),
   String(webSpecs.filter((w) => w.scroll).length));
ok("the card is drawn at one of the three named scales",
   webSpecs.filter((w) => w.blocks.some((b) => b.t === "art"))
           .every((w) => [U_PHONE, U_DESKTOP, U_CARD].includes(w.blocks.find((b) => b.t === "art").u)));
ok("the desktop card is drawn smaller than the phone one", U_DESKTOP < U_PHONE);
ok("two desktop screens", all("main", "screens").filter(([, , , s]) => s.web && s.web.desktop).length === 2);

/* ---- the head block is escaped, not live markup ---- */
const og = all("main", "elements").find((i) => i[0] === "el-og")[3];
ok("the OG demo escapes its angle brackets", og.includes("&lt;meta") && !/<meta/.test(og));
ok("the OG demo generates its own image rather than hosting one", og.includes("opengraph-image") && !og.includes("cards/"));

/* ---- guard 1: no new class may collide with the shell's ---- */
const SHELL_CLASSES = new Set(["ph","sm","bar","well","sheet","hdl","sh2","caps","tb","tp","cc","st","r2","ic","bk","bks","shf","sl","cv","fld","pop","rail","pile","sp","mh","mg","erow","eav","etx","brow","bd","gly","done","poke","dim","on","hf","pr","h","l","b","s","w","grp2","bkw","pb","art","artg","acvr","amrz","abody","ahd","ahd2","arow","afig","ameta","astats","aspring","awell","aseal","ashelf","aperf","agal","shv","shtop","shstage","toast","kkv","kkhd","kkrow","kkav","kkb","kklink","osv","ossh","oshd","ostx","ospay","osapps","osrow","osthumb","dsts","frb","cdp","cdl","tile","sk","skb","gen","txt","gsh","cempty","xb","tt","l3","hr","step","shot","el","demo","item","grid","view","lead","kbd","pend","gone","tag","flow","side","sbox","search","hint"]);
const NEW = new Set();
for (const html of [land, hold, lib, libM, libGrid, memos, bannerP, frame(specOf("main","screens","lib-private")), frame(specOf("main","screens","page-privacy"))])
    for (const mm of html.matchAll(/class="([^"]+)"/g))
        for (const t of mm[1].split(/\s+/)) if (t && /^(w|br)/.test(t)) NEW.add(t);
const collisions = [...NEW].filter((c) => SHELL_CLASSES.has(c));
ok("no new web class collides with the shell's", collisions.length === 0, collisions.join(","));
ok("the web classes are namespaced", NEW.size >= 12, [...NEW].sort().join(","));

/* ---- every spec renders, balanced and escaped ---- */
function balance(html, label) {
    const stack = [];
    let mm;
    const re = /<(\/?)([a-z]+)([^>]*)>/g;
    while ((mm = re.exec(html))) {
        const [, close, tag, rest] = mm;
        if (rest.endsWith("/") || tag === "br") continue;
        if (close) {
            const top = stack.pop();
            if (top !== tag) {
                ok(label + " is balanced", false, "</" + tag + "> closes <" + (top || "nothing") + ">");
                return false;
            }
        } else stack.push(tag);
    }
    if (stack.length) { ok(label + " is balanced", false, "unclosed <" + stack.join("><") + ">"); return false; }
    if (html.replace(/<\/?[a-z]+[^>]*>/g, "").includes("<")) {
        ok(label + " is escaped", false, "unescaped < in text");
        return false;
    }
    return true;
}
let drawn = 0, clean = true;
for (const v of ["main", "web-grid", "card-hero", "card-modal"]) {
    for (const [id, , , spec] of all(v, "screens")) { clean = balance(frame(spec), v + "/" + id) && clean; drawn++; }
    for (const [id, , , steps] of all(v, "flows"))
        steps.forEach(([, , spec], i) => { clean = balance(frame(spec), v + "/" + id + "#" + (i + 1)) && clean; drawn++; });
    for (const [id, , , demo] of all(v, "elements")) {
        if (typeof demo !== "string") throw new Error("bad element " + id);
        clean = balance(demo, v + "/" + id) && clean;
        drawn++;
    }
}
ok("every emitted string is balanced and escaped", clean);
ok("rendered " + drawn + " specs without throwing", drawn >= 60, String(drawn));
`;

eval(js + "\n" + assertions);

console.log(
  fail
    ? `\n${fail} FAILURE(S)`
    : "\nall checks passed — layout still needs eyes, see the header",
);
process.exit(fail ? 1 : 0);
