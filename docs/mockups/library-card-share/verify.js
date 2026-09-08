/*
 * Verifies index.html without a browser. Run from the project root:
 *
 *     node docs/mockups/library-card-share/verify.js
 *
 * The page is static, so nearly all of it can be checked here: the script
 * parses, the data resolves, version inheritance and the diff direction behave,
 * search finds words a reader can see, the renderers emit what the notes claim,
 * and every emitted string is balanced and escaped.
 *
 * What it cannot check is what the page looks like. Three of the four bugs found
 * while building it were invisible to a check like this one and were caught by
 * screenshotting the page:
 *
 *   1. The strip's `<` filler was unescaped, so the browser read `<<<<` as a tag
 *      and swallowed the rest of the card. The markup "worked".
 *   2. The Photos destination was `class="ph"` -- the phone frame, 170x340 -- so
 *      all four destinations stretched to 340pt and left the stage 4pt tall.
 *   3. The issue-block labels wrapped, and the artifact's stat row wrapped.
 *
 * (1) and (2) now have guards below, added after the fact. (3) still cannot be
 * caught here, which is the honest limit of this file: layout needs eyes.
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
// `\s*\n` before the body, and `\n\s*` before the close: both tags are indented
// in this file, and the version of this regex in the skill's pitfalls doc is
// written for an unindented one and silently matches nothing.
const m = src.match(/<script>\s*\n([\s\S]*?)\n\s*<\/script>/);
if (!m) {
  console.log("FAIL no script block found");
  process.exit(1);
}
const js = m.group ? m.group(1) : m[1];
ok(
  "backticks balanced",
  js.count === undefined ? js.split("`").length % 2 === 1 : true,
);
ok("one generic .gone rule", /\.gone\s*\{\s*display:\s*none/.test(src));

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

/* The assertions run inside the same eval as the page, because the page's
   top-level `const`s are scoped to it and are not reachable from out here. */
const assertions = String.raw`
console.log("load: ok");

/* ---- search finds words a reader can see on the page ---- */
function flowHits(q) {
    const out = [];
    for (const [g, items] of FLOWS)
        for (const [id, nm, ds, steps] of items)
            if (matchWords(flowSearchText(g, nm, ds, steps), q.toLowerCase()))
                out.push(id);
    return out;
}
ok("search 'candlelight'", flowHits("candlelight").includes("share-card"), flowHits("candlelight").join(","));
ok("search 'kakaotalk'", flowHits("kakaotalk").join(",") === "share-kr", flowHits("kakaotalk").join(","));
ok("search 'precache'", flowHits("precache").includes("share-card"), flowHits("precache").join(","));
ok("search 'median reader'", flowHits("median reader").includes("share-thin"), flowHits("median reader").join(","));
ok("search 'framing'", flowHits("framing").includes("share-frame"), flowHits("framing").join(","));

/* ---- versions: inheritance, override, addition ---- */
const ids = (v, k) => resolveView(v, k).flatMap(([, l]) => l.map((i) => i[0]));
const mainScreens = ids("main", "screens");
const tileScreens = ids("tile-share", "screens");
ok("main has no sh-tile", !mainScreens.includes("sh-tile"));
ok("tile-share adds sh-tile", tileScreens.includes("sh-tile"));
ok("tile-share inherits every unchanged screen", mainScreens.every((i) => tileScreens.includes(i)));
const grp = (v, k, id) => resolveView(v, k).find(([, l]) => l.some((i) => i[0] === id))?.[0];
ok("an added screen honours its group", grp("tile-share", "screens", "sh-tile") === "Share preview", grp("tile-share", "screens", "sh-tile"));
ok("an added flow honours its group", grp("tile-share", "flows", "share-tile") === "Sharing the card");
const ghost = (v) => resolveView(v, "elements").flatMap(([, l]) => l).find((i) => i[0] === "el-ghost");
ok("a patched note overrides", ghost("main")[2] !== ghost("tile-share")[2]);
ok("an unpatched payload is inherited", ghost("main")[3] === ghost("tile-share")[3]);

/* ---- the diff reads the same both ways round ---- */
const d1 = diffMap("main", "tile-share", "screens");
const d2 = diffMap("tile-share", "main", "screens");
ok("sh-tile is 'only there' from main", d1.get("sh-tile") === "onlyThere", d1.get("sh-tile"));
ok("sh-tile is 'only here' from tile-share", d2.get("sh-tile") === "onlyHere", d2.get("sh-tile"));
ok("card-open reads changed both ways", d1.get("card-open") === "changed" && d2.get("card-open") === "changed");

/* ---- every open callout reaches the DOM ----
   Not just "the id exists", which is what this asserted at first and is why the
   real bug got through: the shell's engine consumed OPEN in the *flows* render
   only, so three of the four callouts on this page -- keyed to screens and to a
   UI element -- rendered nowhere at all while every id resolved perfectly. The
   engine now renders them in all three views; this asserts the text is actually
   in the markup of the view that owns the id. */
const OWNER = { screens: "screens", flows: "flows", elements: "elements" };
for (const v of ["main", "tile-share"]) {
    activeV = v;
    render();
    const openMap = resolveOpen(v);
    for (const [key, text] of Object.entries(openMap)) {
        const kind = ["screens", "flows", "elements"].find((k) =>
            ids(v, k).includes(key),
        );
        ok(v + ": OPEN '" + key + "' belongs to something", !!kind, kind);
        if (!kind) continue;
        const html = document.getElementById(OWNER[kind]).innerHTML;
        // A distinctive slice rather than the whole string, which carries markup
        // that the renderer interpolates verbatim anyway.
        ok(
            v + ": OPEN '" + key + "' renders in " + kind,
            html.includes('class="pend"') && html.includes(text.slice(0, 60)),
        );
    }
}
activeV = "main";
render();

/* ---- the renderers emit what the notes claim ---- */
const rich = artifact({ n: 12, seed: 0, days: 86, pace: "9d", authors: 9, shelves: 3, u: 2 });
ok("artifact prints the strip", rich.includes("amrz") && rich.includes("@LIBSTACK.APP"));
ok("artifact prints four stat cells", (rich.match(/<div><i>/g) || []).length === 4);
const thin = artifact({ n: 2, seed: 5, authors: 2, shelves: 1, u: 2 });
ok("thin artifact omits days and pace", !thin.includes("Days reading") && !thin.includes("Pace"));
// Floors, not just nulls: two authors and one shelf are true and say nothing, so
// the whole row goes rather than being half-filled.
ok("thin artifact drops the stat row entirely", !thin.includes("astats"));
ok("thin artifact still pins the strip to the bottom edge", thin.includes("aspring") && thin.includes("amrz"));
const cdl = artifact({ n: 6, seed: 0, dates: ["3/26", "3/26", "2/26", "2/26", "1/26", "1/26"], cdl: true, u: 2 });
// "<s>" also opens an issue-block row, so match a stamp specifically: a stamp's
// content starts with a digit and a row's with a tag.
ok("candlelight stamps dates at n=6", (cdl.match(/<s>\d/g) || []).length === 6);
const cdlMany = artifact({ n: 12, seed: 0, dates: ["3/26"], cdl: true, u: 2 });
ok("candlelight degrades to a mark at n=12", !/<s>\d/.test(cdlMany) && (cdlMany.match(/<u><\/u>/g) || []).length === 12);
ok("today's hero has no card furniture", !stats({}).includes("LIBRARY &middot; CARD") && !stats({}).includes("acvr"));
ok("proposed hero has both", cardHero({ n: 12, seed: 0 }).includes("LIBRARY &middot; CARD") && cardHero({ n: 12, seed: 0 }).includes("acvr"));
ok("median card has no tiles at all", cardBody({ n: 2, seed: 5, more: true, ghost: true }) === cardHero({ n: 2, seed: 5, more: true, ghost: true }));
ok("main's card has two tiles", (cardTiles({ pace: "9d", paceOf: 6, author: "Han Kang", authorN: 3 }).match(/st t2/g) || []).length === 2);
ok("tile-share's card has six", (cardTiles({ pace: "9d", paceOf: 6, author: "Han Kang", authorN: 3, more: true, n: 12, authors: 9, shelves: 3 }).match(/st t2/g) || []).length === 6);
ok("Korean row swaps Messages for KakaoTalk", destRow("kr").includes("KakaoTalk") && !destRow("kr").includes("Messages"));
ok("English row keeps Messages", destRow("en").includes("Messages") && !destRow("en").includes("KakaoTalk"));
ok("today's sheet has nothing pointing back", osSheet({ today: true }).includes("Nothing points back"));
// The payload is the image, deliberately: no text: argument, no URL. What replaced
// the link is the strip printed on the card, which is why this asserts an *absence*
// plus a pointer at where the return path actually lives. (No backticks in here --
// these lines sit inside a String.raw template, and one would close it.)
ok("the proposed sheet carries no link either", !/https?:|libstack\.app\/@/.test(osSheet({ payload: true })) && osSheet({ payload: true }).includes("printed on the card"));

/* ---- the decisions taken while reviewing ----
   the handle exists for the strip's Latin-only grid, not for a URL; the share is the
   image alone; nothing is hosted, so privacy does not change the destinations. */
// The record carries the display name, in the reader's own script; the strip carries
// the handle, because a machine-readable zone is Latin-only. That split is the whole
// reason profiles.handle exists, so both halves are asserted.
ok("the record names its holder in their own script", rich.includes("Holder") && /[^\x00-\x7F]/.test(rich));
ok("no card number is invented", !rich.includes("Card no."));
const strip = rich.match(/class="amrz"[^>]*>([\s\S]*?)<\/div>/)[1];
ok("the strip stays ASCII and URL-safe", !/[^\x00-\x7F]/.test(strip) && strip.includes("PAPER_FOX_412"));
// Kakao is the only destination that needs a hosted image, so it is the only one
// privacy can remove -- and Messages takes the Korean slot back.
// Privacy used to change this row, because Kakao's SDK needed a hosted image and a
// private profile could not have one. With nothing hosted, every destination is a
// local hand-off and the row cannot vary — pinned here so that reasoning cannot creep
// back in without someone re-deciding it.
ok("the destinations do not vary by privacy", destRow("private") === destRow("en"));
ok("all four destinations are local hand-offs", ["IG Stories", "Photos", "More", "Messages"].every((d) => destRow("en").includes(d)));

/* ---- no new class may collide with the shell's ----
   Guard for bug (2) in this file's header: the Photos destination was
   class="ph", which is the phone frame. */
const SHELL_CLASSES = new Set(["ph","sm","bar","well","sheet","hdl","sh2","caps","tb","tp","cc","st","r2","ic","bk","bks","shf","sl","cv","fld","pop","rail","pile","sp","mh","mg","erow","eav","etx","brow","bd","gly","done","poke","dim","on","hf","pr","h","l","b","s","w"]);
const emitted = new Set();
for (const html of [
    destRow("en"),
    destRow("kr", "ig"),
    previewScreen({ scope: "All-time", art: { n: 12, seed: 0 }, frame: "float" }),
    osSheet({}),
    chatBubble({ art: { n: 12, seed: 0 } }),
    artifact({ n: 12, seed: 0, u: 1 }),
    cardBody({ n: 12, seed: 0, days: 86 }),
])
    for (const mm of html.matchAll(/class="([^"]+)"/g))
        for (const t of mm[1].split(/\s+/)) if (t) emitted.add(t);
// The preview sits inside a phone frame and legitimately reuses shell markup, so
// only classes the new renderers introduce are checked.
const collisions = [...emitted].filter((c) => /^(a|sh|d-|bl|dst|fr|xb|gsh|kk|os|toast|cempty)/.test(c) && SHELL_CLASSES.has(c));
ok("no new class collides with the shell's", collisions.length === 0, collisions.join(","));
ok("destinations are namespaced", (destRow("en").match(/class="d-/g) || []).length === 4);

/* ---- every spec renders, balanced and escaped ----
   Guard for bug (1): a raw "<" in text nests the card's body inside its demo
   and the page still renders, just wrongly. */
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
    if (stack.length) {
        ok(label + " is balanced", false, "unclosed <" + stack.join("><") + ">");
        return false;
    }
    if (html.replace(/<\/?[a-z]+[^>]*>/g, "").includes("<")) {
        ok(label + " is escaped", false, "unescaped < in text");
        return false;
    }
    return true;
}
let drawn = 0;
let clean = true;
for (const v of ["main", "tile-share"]) {
    for (const [, l] of resolveView(v, "screens"))
        for (const [id, , , spec] of l) {
            const html = frame(spec);
            if (!html.startsWith('<div class="ph')) throw new Error("bad frame " + id);
            clean = balance(html, v + "/" + id) && clean;
            drawn++;
        }
    for (const [, l] of resolveView(v, "flows"))
        for (const [id, , , steps] of l)
            steps.forEach(([, , spec], i) => {
                clean = balance(frame(spec), v + "/" + id + "#" + (i + 1)) && clean;
                drawn++;
            });
    for (const [, l] of resolveView(v, "elements"))
        for (const [id, , , demo] of l) {
            if (typeof demo !== "string") throw new Error("bad element " + id);
            clean = balance(demo, v + "/" + id) && clean;
            drawn++;
        }
}
ok("every emitted string is balanced and escaped", clean);
ok("rendered " + drawn + " specs without throwing", drawn > 60);
`;

eval(js + "\n" + assertions);

console.log(
  fail
    ? `\n${fail} FAILURE(S)`
    : "\nall checks passed — layout still needs eyes, see the header",
);
process.exit(fail ? 1 : 0);
