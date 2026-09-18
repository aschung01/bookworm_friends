/* Assertions appended to the stubbed load. Verifies the things that would
   otherwise only be checkable by eye AND would silently be wrong: version
   inheritance, the honesty claim the whole design rests on, the copy
   review's decisions, and that the searches a reviewer will type resolve. */
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
const V = ["bar-sheet", "tab-section", "hero-row"];

/* --- shape: the chosen design is the ROOT ---------------------------- */
ok(
  "bar-sheet is the root, so it cannot be a patch",
  VERSIONS[0][0] === "bar-sheet" && VERSIONS[0][3] === null,
);
ok(
  "every branch comes off bar-sheet, and each declares which kind it is",
  (() => {
    const rest = VERSIONS.slice(1);
    if (!rest.every((v) => v[3] === "bar-sheet")) return false;
    const superseded = rest.filter((v) => v[2].startsWith("SUPERSEDED"));
    const proposals = rest.filter((v) => v[2].startsWith("PROPOSAL"));
    const built = rest.filter((v) => v[2].startsWith("BUILT"));
    // Two rejected alternatives and one branch that shipped. Every branch must
    // declare which -- an unlabelled branch reads as current, which is the one thing
    // the design record must never do.
    //
    // The counts have moved twice and each move was a decision worth being forced to
    // edit here. `libby-library` was a PROPOSAL, was briefly marked SUPERSEDED on the
    // belief that a global OverDrive title id removed the need to ask for a library,
    // was reinstated when a device showed "View not found." without one, and is now
    // BUILT. It stays a branch rather than folding into the root because both states
    // ship: the root's sheet is the reader who has not answered, this is the reader
    // who has.
    return (
      superseded.length === 2 &&
      proposals.length === 0 &&
      built.length === 1 &&
      superseded.length + proposals.length + built.length === rest.length
    );
  })(),
  JSON.stringify(VERSIONS.slice(1).map((v) => v[0] + ":" + v[2].slice(0, 10))),
);
ok(
  "the root's own note says it was chosen",
  VERSIONS[0][2].startsWith("CHOSEN"),
);
ok(
  "bar-sheet resolves 15 screens; each alternative drops the 7 that only exist here",
  ids("bar-sheet").length === 15 &&
    ids("tab-section").length === 8 &&
    ids("hero-row").length === 8,
  JSON.stringify(V.map((v) => v + ":" + ids(v).length)),
);
/* The reported bug's state must be drawn, and must not claim to search. */
ok(
  "the id-less Play Books open row launches the app rather than searching",
  (() => {
    const h = frame(spec("bar-sheet", "remembered-play-noid"));
    return (
      h.includes("Open Play Books") &&
      h.includes("Opens your Play Books library") &&
      !h.includes("Searches Play Books")
    );
  })(),
);
ok(
  "every version keeps the friend's-book screen, because the entry point is not isSelf-gated",
  V.every((v) => ids(v).includes("friend-finished")),
);

/* --- the claim the design rests on ---------------------------------- */
/* If Kindle's row ever stops saying it is a search, the feature has begun
   promising a per-book link that does not exist. */
const open = frame(spec("bar-sheet", "sheet-open"));
ok(
  "Kindle admits it searches Amazon, not Kindle",
  open.includes("Searches Amazon"),
);
/* Both resolved rows reach the exact book, and they must NOT say it the same way:
   Apple lands in the app, Play Books lands in a browser. `/store/books/details` is
   claimed by no Google app, which was reported as "it never opens the Play Books
   app even though I have it installed" -- so the store-page wording is pinned, and
   the bare "Opens this book" is pinned to exactly one row. */
ok(
  "the app destination and the browser destination are worded differently",
  count(open, "Opens this book<") === 1 &&
    open.includes("store page in your browser") &&
    !open.includes("Searches Apple Books"),
  count(open, "Opens this book<") + " bare exact rows",
);
/* Apple answering "no edition" withdraws the row rather than degrading it. */
ok(
  "a confirmed absence removes the Apple row and leaves the rest",
  (() => {
    const h = frame(spec("bar-sheet", "apple-absent"));
    return (
      !h.includes("Apple Books") &&
      h.includes("Play Books") &&
      h.includes("Searches Amazon") &&
      h.includes("Borrow free from your library")
    );
  })(),
);
/* The other half, which is what stops "exact" from being drawn as guaranteed:
   both lookups can miss, and for a Korean book both usually do. The degraded
   sheet must give up its exact rows and keep the two that never had any. */
ok(
  "a missed lookup degrades both exact rows and leaves the other two alone",
  (() => {
    const h = frame(spec("bar-sheet", "sheet-open-noid"));
    return (
      count(h, "Opens this book<") === 0 &&
      !h.includes("store page in your browser") &&
      h.includes("Searches Apple Books") &&
      h.includes("Searches Play Books") &&
      h.includes("Searches Amazon") &&
      h.includes("Borrow free from your library")
    );
  })(),
);
ok(
  "Libby offers a free borrow, not a purchase",
  open.includes("Borrow free from your library"),
);
ok("nothing in the acquire list uses the word buy", !/\bbuy\b/i.test(open));
ok(
  "the acquire list never claims to open AT the book",
  !open.includes("Opens at this book"),
);

/* --- the copy review's central decision: the verb carries capability - */
ok(
  "Play Books says Read in, and lands at the book",
  (() => {
    const h = frame(spec("bar-sheet", "remembered-play"));
    return h.includes("Read in Play Books") && h.includes("Opens at this book");
  })(),
);
ok(
  "Kindle says Open, and names the library rather than the book",
  (() => {
    const h = frame(spec("bar-sheet", "remembered"));
    return (
      h.includes("Open Kindle") &&
      h.includes("Opens your Kindle library") &&
      !h.includes("Open in Kindle")
    );
  })(),
);
/* The rejected drafts, asserted absent so they cannot creep back. */
for (const dead of [
  "Opens the app, not the book",
  "Search results, no exact match",
  // The reviewed copy, rejected in the build: an article cannot agree with an
  // interpolated brand name, so this rendered "Opens a Amazon search".
  "Opens an Amazon search",
  "Get it elsewhere",
  "Forget where this lives",
  "Kindle Store",
  "Book description",
]) {
  ok(
    'the rejected draft "' + dead + '" is gone everywhere',
    V.every((v) => ids(v).every((id) => !frame(spec(v, id)).includes(dead))),
  );
}

/* --- states ---------------------------------------------------------- */
ok(
  "the sheet title reports the remembered state, since the glyph cannot",
  frame(spec("bar-sheet", "sheet-open")).includes(">Where to read<") &&
    frame(spec("bar-sheet", "remembered")).includes(">Your copy<"),
);
/* Scoped to the sheet's own empty block, NOT the whole frame: the page's
   Book info tab has a legitimate ISBN section of its own, so asserting on
   the frame checks the wrong thing and fails for the right reason. */
ok(
  "the empty state is title + body, and its copy never names the ISBN",
  (() => {
    const h = frame(spec("bar-sheet", "empty"));
    const block = h.slice(
      h.indexOf('class="snone"'),
      h.indexOf("</div></div>", h.indexOf('class="snone"')),
    );
    return (
      block.includes("No ebook edition of this one") &&
      block.includes("small-press") &&
      !/\d{10,13}/.test(block) &&
      !/isbn/i.test(block)
    );
  })(),
);
ok(
  "loading uses the ellipsis character, as app_en.arb does throughout",
  frame(spec("bar-sheet", "loading")).includes("Checking the stores\u2026"),
);
ok(
  "four shimmer rows, so the sheet does not resize when the answer lands",
  count(frame(spec("bar-sheet", "loading")), "<i></i>") === 4,
);
ok(
  "the remembered sheet checks one store, offers three, and can be cleared",
  (() => {
    const h = frame(spec("bar-sheet", "remembered"));
    return (
      h.includes("chk") &&
      count(h, 'class="srow') === 5 &&
      h.includes("Forget where I read this")
    );
  })(),
  "rows: " + count(frame(spec("bar-sheet", "remembered")), 'class="srow'),
);
ok(
  "clearing is not drawn as destructive",
  !frame(spec("bar-sheet", "remembered")).includes("cancelRed"),
);
ok(
  "a friend's book gets the acquire list only \u2014 no check, no forget row",
  (() => {
    const h = frame(spec("bar-sheet", "friend-sheet"));
    return (
      !h.includes("chk") && !h.includes("Forget") && !h.includes(">Your copy<")
    );
  })(),
);

/* --- what the chosen version costs and buys -------------------------- */
ok(
  "the icon is identical whether or not a store is remembered",
  (() => {
    const bare = frame(spec("bar-sheet", "bar-icon"));
    const known = frame(spec("bar-sheet", "icon-unmarked"));
    const nav = (h) =>
      h.slice(h.indexOf('class="nav"'), h.indexOf('class="hero"'));
    return nav(bare) === nav(known);
  })(),
);
ok(
  "only the marked variant differs, and only by the dot",
  frame(spec("bar-sheet", "icon-marked")).includes('class="dot"') &&
    !frame(spec("bar-sheet", "icon-unmarked")).includes('class="dot"'),
);
ok(
  "the tab body is untouched by the chosen design",
  (() => {
    const h = frame(spec("bar-sheet", "bar-icon"));
    return h.includes("About this book") && !h.includes(">Where to read<");
  })(),
);
ok(
  "the glyph survives the tab swipe; the superseded section does not",
  frame(spec("bar-sheet", "notes-tab")).includes("newctl") &&
    !frame(spec("tab-section", "notes-tab")).includes("newctl"),
);
ok(
  "bar-sheet creates the actions group on a friend's book",
  frame(spec("bar-sheet", "friend-finished")).includes("newctl") &&
    !frame(spec("tab-section", "friend-finished")).includes('class="acts"'),
);
ok(
  "only hero-row touches the band, and it must hide its control when empty",
  frame(spec("hero-row", "bar-icon")).includes("herostores") &&
    !frame(spec("hero-row", "empty")).includes("herostores") &&
    !frame(spec("bar-sheet", "bar-icon")).includes("herostores"),
);
ok(
  "the superseded chips screen still shows why chips lost",
  (() => {
    const h = frame(spec("tab-section", "sheet-open"));
    return h.includes("schip searchonly") && !h.includes("ssub");
  })(),
);

/* --- shipped chrome must not drift ---------------------------------- */
ok(
  "the tab's own headings are the real l10n strings",
  frame(spec("bar-sheet", "bar-icon")).includes("About this book"),
);
ok(
  "Interested draws unfilled, as book_status_badge.dart ships it",
  frame(spec("bar-sheet", "bar-icon")).includes("sbadge interested"),
);
ok(
  "status 0 gets a bare badge, status >= 1 gets the period card",
  frame(spec("bar-sheet", "bar-icon")).includes("barebadge") &&
    frame(spec("bar-sheet", "reading-book")).includes('class="period"'),
);
ok(
  "the reaction pill and capsule appear only on a friend's finished book",
  frame(spec("bar-sheet", "friend-finished")).includes('class="cap"') &&
    !frame(spec("bar-sheet", "bar-icon")).includes('class="cap"'),
);

/* --- open decisions are carried, and retired where answered --------- */
ok(
  "the chosen design carries the three live decisions",
  (() => {
    const o = resolveOpen("bar-sheet");
    return !!o["acquire-remember"] && !!o["icon-marked"] && !!o["el-row-libby"];
  })(),
);
/* `el-logos` was one of these and is now answered: marks where one can be
   sourced, the store's initial where one cannot. Asserted absent so that a
   settled decision cannot drift back into the red-callout list. */
ok(
  "the logo decision is retired rather than still open",
  !resolveOpen("bar-sheet")["el-logos"],
);

/* --- the leading mark: four real marks, no letters ------------------- */
/* An earlier round shipped `K` and `L` letter chips, having concluded no
   licence-clean mark existed for Kindle or Libby. Both halves of that were
   wrong, so both directions are pinned: the count catches a mark being dropped
   back to a letter, and the letter assertions catch them being reintroduced. */
ok(
  "every shop draws a real mark, and none falls back to a letter",
  (() => {
    const body = frame(spec("bar-sheet", "sheet-open"));
    const marks = (body.match(/<svg viewBox="0 0 (24 24|48 48)"/g) || [])
      .length;
    return marks === 4 && !body.includes(">K<") && !body.includes(">L<");
  })(),
);
/* Libby's is the only stroked mark, and is drawn larger to carry the same
   optical weight as the three solid fills. Flattening the sizes to one constant
   is the tidy-up that would silently reintroduce the imbalance. */
ok(
  "the stroked mark is drawn larger than the solid ones",
  (() => {
    const body = frame(spec("bar-sheet", "sheet-open"));
    return (
      body.includes('stroke-width="3"') &&
      body.includes('width="19"') &&
      body.includes('width="15"')
    );
  })(),
);
ok(
  "the shipped mark is tinted, not painted in the brand's colour",
  frame(spec("bar-sheet", "sheet-open")).includes('fill="currentColor"') &&
    !frame(spec("bar-sheet", "sheet-open")).includes("background:#1a73e8"),
);
ok(
  "the glyph decision does not follow into branches where the glyph does not exist",
  !resolveOpen("tab-section")["icon-marked"] &&
    !resolveOpen("hero-row")["icon-marked"],
);
ok(
  "each superseded branch records what rejected it",
  !!resolveOpen("tab-section")["sheet-open"] &&
    !!resolveOpen("hero-row")["empty"],
);

/* --- the libby-library proposal ------------------------------------- */
/* Drawn as a branch so it can be compared against the shipped Libby row rather
   than replacing it in the record. These pin the two things a reader of this page
   in six months would otherwise have to take on trust. */
ok(
  "the proposal adds the picker and the payoff, and leaves the root alone",
  (() => {
    const p = ids("libby-library");
    const root = ids("bar-sheet");
    return (
      [
        "libby-ask",
        "libby-typed",
        "libby-none",
        "libby-exact",
        "libby-settings",
      ].every((id) => p.includes(id)) &&
      // The root must NOT gain them: a proposal that leaks into the shipped
      // record is exactly the drift versions exist to prevent.
      !root.includes("libby-ask") &&
      !root.includes("libby-exact")
    );
  })(),
  JSON.stringify({
    proposal: ids("libby-library").length,
    root: ids("bar-sheet").length,
  }),
);
/* The payoff has to be visible in the copy, not just in the URL. If the line did
   not change, the reader would see an identical row and get a better destination
   they could not tell apart -- which is not worth a column and a sheet. */
ok(
  "a stored library upgrades the Libby line, and changes nothing else",
  (() => {
    const before = frame(spec("bar-sheet", "sheet-open"));
    const after = frame(spec("libby-library", "libby-exact"));
    return (
      before.includes("Borrow free from your library") &&
      after.includes("Borrow this book from your library") &&
      !after.includes("Borrow free from your library") &&
      // Kindle cannot be upgraded by anything, and must not appear to be.
      after.includes("Searches Amazon")
    );
  })(),
);
/* The risk is carried inline, where the decision is, rather than only in prose. */
ok(
  "the library-search API question is recorded as resolved, with the endpoint",
  (() => {
    const o = resolveOpen("libby-library");
    return (
      !!o["libby-first-run"] &&
      /^RESOLVED/.test(o["libby-first-run"]) &&
      // The endpoint itself, so the record does not merely claim to have found one.
      /locate\.libbyapp\.com/.test(o["libby-first-run"]) &&
      /preferredKey/.test(o["libby-first-run"])
    );
  })(),
);
ok(
  "the branch's open note does not leak into the shipped version",
  !resolveOpen("bar-sheet")["libby-first-run"],
);

/* --- search: queries a reviewer will actually type -------------------- */
/* matchWords requires a PRE-LOWERCASED haystack and does no stripping of
   its own, so these helpers must normalise exactly as flowSearchText
   does. Passing raw mixed-case text made 'kindle' and 'rls' return
   nothing while 'isbn' passed by luck, on a note containing `Book.isbn`. */
const norm = (s) =>
  stripTags(s)
    .toLowerCase()
    .replace(/["&<>]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
const hits = (kind, q, vid) => {
  const o = [];
  for (const [g, items] of resolveView(vid || "bar-sheet", kind))
    for (const [id, nm, ds, steps] of items) {
      const hay =
        kind === "flows"
          ? flowSearchText(g, nm, ds, steps)
          : norm([nm, g, ds].join(" "));
      if (matchWords(hay, q.toLowerCase())) o.push(id);
    }
  return o;
};
ok(
  "search 'kindle' finds screens",
  hits("screens", "kindle").length > 0,
  JSON.stringify(hits("screens", "kindle")),
);
ok(
  "search 'tooltip' finds the entry point",
  hits("screens", "tooltip").includes("bar-icon"),
);
ok(
  "search 'rls' finds the friend's book",
  hits("screens", "rls").includes("friend-sheet"),
);
ok(
  "search 'verb' finds the element about the verb split",
  hits("elements", "verb").includes("el-row-verbs"),
);
ok(
  "search 'localisation' finds the ko store-set question",
  hits("elements", "localisation").includes("el-row-libby"),
);
ok(
  "search 'scannomatch' finds the empty state",
  hits("elements", "scannomatch").includes("el-empty"),
);
ok(
  "search 'superseded' finds nothing in the root",
  hits("screens", "superseded").length === 0,
);
ok(
  "search 'superseded' finds every patched screen in a branch",
  hits("screens", "superseded", "tab-section").length === 8,
  JSON.stringify(hits("screens", "superseded", "tab-section")),
);
ok("flow search 'purchase' resolves", hits("flows", "purchase").length > 0);
ok(
  "flow search 'webreaderlink' resolves",
  hits("flows", "webreaderlink").includes("open-copy"),
);

console.log(fails ? "\n" + fails + " FAILED" : "\nall assertions passed");
if (fails) process.exit(1);
