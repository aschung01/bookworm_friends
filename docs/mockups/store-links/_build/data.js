/* ==================================================================
   SECTION 2: FRAME RENDERER — the book-details page, drawn once.

   The chosen design is `bar-sheet`: an app-bar icon that opens a sheet.
   That is the ROOT version, so the base data below is the settled design
   and the two rejected alternatives are patches over it.

   The chrome (bar, cover, corner, shelf, band, status card, tabs, tab
   body) is defined here once. `where` is still read in three places
   rather than switched at the top, because a frame per version is exactly
   how the chrome drifts.
   ================================================================== */
/* The four destinations, and the honest supporting line for each.

               `kind` is the capability, and it is the spine of this whole
               page:
                 exact   — a per-book URL exists and we have its id
                 search  — only a query, so the reader lands on results
                 library — a borrow lookup, not a purchase
                 app     — launches the reader app, cannot target the book

               Kindle is `search` for acquiring and `app` for opening, and no
               wording makes it otherwise: Amazon publishes no per-book deep
               link, and Kindle's only claimed URL reaches the library rather
               than a title.

               **The verb carries the capability.** `Read in Play Books`
               promises a book; `Open Kindle` promises an app. That split is
               the single most load-bearing decision in the copy — a reader
               who learns it once can trust every row afterwards. Reviewed
               against app_en.arb, whose voice is sentence case, contracted
               ("Couldn't load book info"), and states what DOES happen
               rather than apologising for what doesn't.

               **Which of the two lists the sheet shows has changed since this
               page was drawn, and it is not drawn here.** It used to turn on
               `reader_app` alone. `reader_app` and status are now read as two
               independent facts: `reader_app` decides which shop LEADS and
               carries the check, and status decides whether the OTHER shops are
               `open` rows or `acquire` rows. For your own book at Reading or
               Finished, every row is an open row.

               The numbers forced it -- of 473 books in production 342 are
               reading or finished and 3 carry a `reader_app`, so the acquire
               list was being shown for the large majority of a library the app
               knew had been read. And the first attempt only applied it when
               nothing was stored, which meant storing one shop sent every other
               shop back to the storefront: a book at Reading with Apple Books
               stored still offered `Opens this book's store page in your
               browser` for Play Books.

               Each row still reaches as far as it can -- Play Books says
               `Read in Play Books / Opens at this book` where a volume id
               exists, Kindle admits it can only reach the library. An earlier
               draft withheld the ids to hold every row at `app`, and checking
               that killed it: `play.google.com/books/reader` with no id IS the
               Play Books storefront, so the humbler row promised `Opens your
               Play Books library` and landed on a shop.

               Gated on ownership: a friend's finished book still shows the
               shops, which is the case this whole sheet was built for.

               No new rows and no new copy, which is why no screen was added --
               it is the same four shops with the `open` labels every
               stored-shop screen below already shows. */
const S = {
  play: {
    n: "Play Books",
    ico: "G",
    logo: "#1a73e8",
    /* A licence-clean monochrome mark exists (Simple Icons, CC0) and ships
       as `assets/icons/storePlayIcon.svg`. Drawn here from the same path
       data so this page shows what the app shows. */
    mark: "M22.018 13.298l-3.919 2.218-3.515-3.493 3.543-3.521 3.891 2.202a1.49 1.49 0 0 1 0 2.594zM1.337.924a1.486 1.486 0 0 0-.112.568v21.017c0 .217.045.419.124.6l11.155-11.087L1.337.924zm12.207 10.065l3.258-3.238L3.45.195a1.466 1.466 0 0 0-.946-.179l11.04 10.973zm0 2.067l-11 10.933c.298.036.612-.016.906-.183l13.324-7.54-3.23-3.21z",
    /* Exact, but a WEB STORE PAGE rather than the app -- which is the reported
       bug, and is proven rather than inferred. Apple's app-site-association for
       play.google.com claims exactly `/books/reader`, `/books/listen`,
       `/books/getapp2` and `/books/notes` for com.google.GoogleBooks;
       `/store/books/details` is claimed by nothing, so it opens Safari however
       installed the app is. It is also the *right* destination -- Google cannot
       sell books in-app on iOS -- so the URL stays and the copy changed. */
    get: [
      "Play Books",
      "Opens this book&rsquo;s store page in your browser",
      "storepage",
    ],
    /* Acquiring WITHOUT a volume id -- a Play Store search rather than the
       book's store page. The counterpart to `openNoId` below, and reached in
       the same circumstance: a Kakao-sourced book whose keyless Google Books
       lookup also came up empty. */
    getNoId: ["Play Books", "Searches Play Books", "search"],
    /* `/books/reader` IS claimed, so this one genuinely opens the app. The one
       row in the sheet that reaches a book inside the shop's own reader. */
    open: ["Read in Play Books", "Opens at this book", "exact"],
    /* Opening WITHOUT a volume id. This pair is the fix for the reported
       bug: Play Books was the only shop with no app fallback, so an
       id-less open fell through to a Play Store search while the sheet
       still labelled it "Open Play Books". A row promising the app and
       performing a search is exactly what StoreReach exists to prevent.

       Reachable less often now than it was: a Kakao-sourced book gets one
       keyless Google Books lookup to find an id, so this is the state
       after that lookup also comes up empty. */
    openNoId: ["Open Play Books", "Opens your Play Books library", "app"],
  },
  apple: {
    n: "Apple Books",
    ico: "A",
    logo: "#000000",
    /* The bare Apple mark, which is the only Apple glyph Simple Icons
       carries — there is no Apple Books icon. Acceptable because the row is
       already labelled "Apple Books"; the mark identifies the ecosystem and
       the label identifies the shop. */
    mark: "M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701",
    /* Exact and IN THE APP, since `books.apple.com` is a domain Books claims.
       One keyless iTunes lookup supplies the id -- by ISBN, then by a guarded
       title+author search for the many books Apple sells but has not indexed by
       ISBN. `getNoId` is the "we could not ask" case; when Apple answers that it
       has no edition the row is DROPPED entirely, because its fallback opens
       Books on an empty search tab and no wording makes that honest. See the
       `apple-absent` screen. */
    get: ["Apple Books", "Opens this book", "exact"],
    getNoId: ["Apple Books", "Searches Apple Books", "search"],
    open: ["Open Apple Books", "Opens your Books library", "app"],
  },
  kindle: {
    n: "Kindle",
    ico: "K",
    logo: "#ff9900",
    /* The AMAZON mark, not a Kindle one. Amazon publishes no Kindle glyph in
       any set that can be legally redistributed, and this row's own second
       line already reads "Searches Amazon" -- so the mark names the ecosystem
       and the label names the shop, which agree rather than compete. Simple
       Icons, CC0; ships as `assets/icons/storeKindleIcon.svg`. */
    mark: "M.045 18.02q.107-.174.348-.022q5.455 3.165 11.87 3.166q4.278-.001 8.447-1.595l.315-.14c.138-.06.234-.1.293-.13c.226-.088.39-.046.525.13c.12.174.09.336-.12.48c-.256.19-.6.41-1.006.654q-1.867 1.113-4.185 1.726a17.6 17.6 0 0 1-10.951-.577a17.9 17.9 0 0 1-5.43-3.35q-.15-.113-.151-.22c0-.047.021-.09.051-.13zm6.565-6.218q0-1.507.743-2.577c.495-.71 1.17-1.25 2.04-1.615c.796-.335 1.756-.575 2.912-.72c.39-.046 1.033-.103 1.92-.174v-.37c0-.93-.105-1.558-.3-1.875c-.302-.43-.78-.65-1.44-.65h-.182c-.48.046-.896.196-1.246.46c-.35.27-.575.63-.675 1.096c-.06.3-.206.465-.435.51l-2.52-.315c-.248-.06-.372-.18-.372-.39c0-.046.007-.09.022-.15q.372-1.935 1.82-2.88c.976-.616 2.1-.975 3.39-1.05h.54c1.65 0 2.957.434 3.888 1.29c.135.15.27.3.405.48c.12.165.224.314.283.45c.075.134.15.33.195.57c.06.254.105.42.135.51c.03.104.062.3.076.615c.01.313.02.493.02.553v5.28c0 .376.06.72.165 1.036q.157.471.315.674l.51.674q.136.204.136.36q0 .181-.18.314c-1.2 1.05-1.86 1.62-1.963 1.71q-.247.203-.63.045a6 6 0 0 1-.526-.496l-.31-.347a9 9 0 0 1-.317-.42l-.3-.435c-.81.886-1.603 1.44-2.4 1.665c-.494.15-1.093.227-1.83.227c-1.11 0-2.04-.343-2.76-1.034c-.72-.69-1.08-1.665-1.08-2.94l-.05-.076zm3.753-.438q-.001.848.425 1.364c.285.34.675.512 1.155.512c.045 0 .106-.007.195-.02c.09-.016.134-.023.166-.023c.614-.16 1.08-.553 1.424-1.178c.165-.28.285-.58.36-.91c.09-.32.12-.59.135-.8c.015-.195.015-.54.015-1.005v-.54c-.84 0-1.484.06-1.92.18c-1.275.36-1.92 1.17-1.92 2.43l-.035-.02zm9.162 7.027c.03-.06.075-.11.132-.17q.544-.365 1.05-.5a8 8 0 0 1 1.612-.24c.14-.012.28 0 .41.03c.65.06 1.05.168 1.172.33c.063.09.099.228.099.39v.15c0 .51-.149 1.11-.424 1.8q-.418 1.034-1.156 1.68q-.11.09-.197.09c-.03 0-.06 0-.09-.012c-.09-.044-.107-.12-.064-.24c.54-1.26.806-2.143.806-2.64c0-.15-.03-.27-.087-.344c-.145-.166-.55-.257-1.224-.257q-.364 0-.87.046c-.363.045-.7.09-1 .135q-.134 0-.18-.044c-.03-.03-.036-.047-.02-.077c0-.017.006-.03.02-.063v-.06z",
    /* Not "Kindle Store / Search results, no exact match", which was a
       clinical caveat in a voice that does not write them.

       Nor "Opens an Amazon search", which was the reviewed copy and
       shipped as `Searches {store}` instead: an article cannot agree with
       an interpolated brand name, and it rendered "Opens a Amazon
       search". Amazon and Apple Books are the two shops most often
       reached this way, so the article was wrong in the common case
       rather than the rare one. A widget test caught it and now pins it. */
    get: ["Kindle", "Searches Amazon", "search"],
    /* Not "Open in Kindle / Opens the app, not the book":
                       leads with what does happen, and is more accurate —
                       it opens the library. Dropping "in" matters too,
                       because you are not opening the book in Kindle.

       The destination is `read.amazon.com/application`, which replaced
       `kindle://` -- following the rule the Libby row below established after a
       device failure. That host matters: on `www.amazon.com` the Kindle app
       claims nothing, and `/bookshelf` there belongs to the *shopping* app, so
       the obvious-looking URL would open the wrong app. Uninstalled it reaches
       Kindle Cloud Reader, which is genuinely the reader's library -- so the
       line stays true through the fallback instead of dying on it.

       **Confirmed on a device: it opens Kindle at the library page.** So this
       line is earned rather than assumed, like Libby's below.

       Play Books moved the same way, to `play.google.com/books/reader`, though
       that one is not tapped yet. Apple Books is the sole remaining scheme:
       there is no Apple Books web reader, so no universal link could reach a
       reader's own library at all. */
    open: ["Open Kindle", "Opens your Kindle library", "app"],
  },
  libby: {
    n: "Libby",
    ico: "L",
    logo: "#c8102e",
    /* The one mark no CC0 set carries. From Arcticons (CC BY-SA 4.0), which
       is why the licence page in settings_page.dart now names it -- bundled
       SVGs never reach Flutter's aggregated page, so nothing else would.

       A STROKE where the other three are solid fills, so it carries less ink
       at equal size and `_Glyph` draws it at 20 of the 30pt box rather than
       16. `markStroke` reproduces that here; see
       `test/store_marks_probe_test.dart` for the side-by-side. */
    markBox: "0 0 48 48",
    markStroke: true,
    mark: "m39.85 14.43l-15.42 3.64a1.8 1.8 0 0 1-.86 0L8.15 14.43a1.87 1.87 0 0 0-1.87 1.86V38a1.87 1.87 0 0 0 1.87 1.86l15.42 3.62a1.8 1.8 0 0 0 .86 0l15.42-3.62A1.87 1.87 0 0 0 41.72 38V16.29a1.87 1.87 0 0 0-1.87-1.86m-17.28 3.41v25.37m2.86-25.37v25.37M37.56 15a15.1 15.1 0 0 0-27.12 0M30.17 7.82V4.5l2.53 1.63l2.53-1.63v7.02",
    get: ["Libby", "Borrow free from your library", "library"],
    /* Both lines ship, and which one a reader sees is derived from the reach like
       every other row's — `get` when no library is stored, `getExact` when one is.

       The four-character difference is load-bearing: without it the destination
       would get better (an exact in-app title instead of a browser page) and the row
       would look identical. `storeBorrowThisBook` is the shipped key.

       Neither line claims the copy is **available**. Availability is per-library --
       the same title is 87-of-87 at LAPL and eleven deep in holds at SFPL -- so the
       row names the book and the lender and lets Libby settle the outcome. */
    getExact: ["Libby", "Borrow this book from your library", "exact"],
    /* The rendered string is the generic `storeOpensLibraryApp`, not a
       Libby-specific line -- this used to read "Opens your Libby shelf" here and
       did not match what ships. It stays truthful: the destination is
       `libbyapp.com/shelf/loans`, the reader's own loans, and a title id does not
       upgrade it, because reaching one loan needs a library key we do not have.

       That URL replaced `libby://`, which was a guessed scheme, is not the app's
       (`com.overdrive.dewey`) and failed with "Something went wrong" even while
       declared in LSApplicationQueriesSchemes. Libby claims every path on its
       host, so a universal link opens the app -- and degrades to Libby's web
       shelf when it is missing, which a custom scheme can never do. Confirmed on
       a device: it is where the failed `title/<id>` attempt landed. */
    open: ["Open Libby", "Opens your Libby library", "app"],
  },
};
const ALL = ["play", "apple", "kindle", "libby"];

/* Every user-facing string, in one table, because that is what a
               copy review needs to be able to read. Keys are the names they
               would take in app_en.arb. */
const T = {
  whereToRead: "Where to read",
  yourCopy: "Your copy",
  forget: "Forget where I read this",
  checking: "Checking the stores\u2026",
  noneTitle: "No ebook edition of this one",
  noneBody:
    "None of the stores we check have one. Print-only and small-press books often aren't listed.",
  /* --- `libby-library` only. Copy is a first draft, NOT reviewed: the
     approved copy in the design doc covers the store rows only, and this
     version has not been through /ux-copy. --- */
  libTitle: "Which library?",
  libSearchHint: "Library name or postcode",
  /* Answers "why are you asking me this", once, where it is asked. Libby
     itself cannot search without a library either, so this is the
     product's own constraint rather than ours -- worth saying plainly
     instead of implying the app is nosy. */
  libWhy:
    "Libby searches one library at a time, so it needs to know yours. Saved for next time.",
  libNoneTitle: "No library by that name",
  libNoneBody:
    "Try the library system rather than a branch \u2014 \u201cKing County\u201d rather than \u201cAuburn\u201d.",
};

/* BookStatusBadge, all three shipped forms. */
function statusBadge(s) {
  const [cls, label] =
    s.status === 2
      ? ["read", "Read"]
      : s.status === 1
        ? ["reading", "Reading"]
        : ["interested", "Interested"];
  return `<span class="sbadge ${cls}">${label}</span>`;
}

/* ReadingPeriodRow. No dates means no card — a lone chip in a
               full-width white slab was drawn at 1:1 in the praise-region set
               and looked worse than nothing, so status 0 gets a bare badge in
               the same vertical position. */
function periodCard(s) {
  if (s.status < 1) return `<div class="barebadge">${statusBadge(s)}</div>`;
  return (
    `<div class="period">${statusBadge(s)}` +
    `<span>2023.09.04 ~ ${s.status === 2 ? "2023.09.05" : ""}</span>` +
    `<i>${s.status === 2 ? "1 day" : "12 days"}</i></div>`
  );
}

/* The hero's right column. Empty on your own book; on a friend's
               finished one it carries the reaction controls. */
function rcol(s) {
  if (!s.praise) return "";
  return (
    `<span class="pill"><span class="em">&#127881;</span>React</span>` +
    `<div class="caprow"><span class="cap"><span class="e">&#128079;</span>` +
    `<span class="e">&#128149;</span><span class="chev">&#8250;</span></span></div>`
  );
}

/* One store row. `mode` picks which of the two label pairs on S
               to use, so a store cannot say "opens at this book" in the
               acquire list and mean the search page. */
function storeRow(id, mode, opts) {
  const o = opts || {};
  const st = S[id];
  /* `noId` degrades a row to its unresolved pair where the store has one.
     Both lookups can miss, and a store that cannot be exact anyway has no
     second pair to fall back to -- so this is a lookup, not a branch.

     `libbyExact` is the mirror, and belongs to the `libby-library` proposal:
     it UPGRADES a row where a stored library key makes one possible. */
  const key =
    o.libbyExact && st[mode + "Exact"]
      ? mode + "Exact"
      : o.noId && st[mode + "NoId"]
        ? mode + "NoId"
        : mode;
  const [lbl, sub, kind] = st[key];
  /* The real mark for all four shops. An earlier round shipped letter chips for
     Kindle and Libby, on the conclusion that no licence-clean mark existed for
     either -- wrong twice over: Simple Icons still carries `amazon`, and
     Arcticons carries Libby. The letter (`st.ico`) survives only as the
     brand-colour comparison in `el-logos`.

     Tinted with `currentColor`, not painted in the brand's own colour: the sheet
     is otherwise entirely typographic, and a full-colour badge would be the
     loudest thing on it. `st.logo` is retained only for that rejected
     comparison.

     Libby's is a stroke rather than a fill, and is drawn larger for it -- see the
     note on its entry in S. */
  const box = st.markBox || "0 0 24 24";
  const px = st.markStroke ? 19 : 15;
  const paint = st.markStroke
    ? `fill="none" stroke="currentColor" stroke-width="3" ` +
      `stroke-linecap="round" stroke-linejoin="round"`
    : `fill="currentColor"`;
  const ico = o.brandColour
    ? `<span class="sico logo" style="background:${st.logo}">${st.ico}</span>`
    : `<span class="sico"><svg viewBox="${box}" width="${px}" height="${px}" ` +
      `${paint} aria-hidden="true"><path d="${st.mark}"/></svg></span>`;
  const trail = o.check
    ? `<span class="chk">&#10003;</span>`
    : `<span class="sgo">&#8599;</span>`;
  return (
    `<div class="srow${o.cls ? " " + o.cls : ""}" data-kind="${kind}">${ico}` +
    `<span class="stx"><span class="slbl">${lbl}</span>` +
    `<span class="ssub">${sub}</span></span>${trail}</div>`
  );
}

function storeRows(list, mode, opts) {
  return list.map((id) => storeRow(id, mode, opts)).join("");
}

/* The chips layout, kept only for the rejected tab-section
               branch. A chip has no second line, so a search-only
               destination has nowhere to admit it — drawn as a dashed
               outline instead, which is a weaker signal and is meant to
               look like one. */
function storeChips(list, mode) {
  return (
    `<div class="schips">` +
    list
      .map((id) => {
        const [lbl, , kind] = S[id][mode];
        const cls = kind === "search" ? " searchonly" : "";
        return `<span class="schip${cls}">${lbl}<span class="g">&#8599;</span></span>`;
      })
      .join("") +
    `</div>`
  );
}

/* The sheet's body, which is the whole of the chosen design.

               Rows get ListTile's real 56pt here: there is no competing
               content to buy space from, and 56 is what showMenuBottomSheet
               already draws for every other menu in the app. */
function sheetBody(s) {
  /* The library picker, `libby-library` only. Drawn as one more sheet
     rather than a page: it is a single choice made once, and it is
     reached from inside a sheet, so pushing a route would take the
     reader further from the book than the decision warrants. */
  if (s.state === "librarypick")
    return (
      `<div class="lsearch${s.typed ? " typed" : ""}">` +
      `<span class="mag">&#9906;</span>${s.typed || T.libSearchHint}</div>` +
      (s.libs && s.libs.length
        ? s.libs
            .map(
              (l) =>
                `<div class="lrow"><span class="lico">&#127968;</span>` +
                `<span class="ltx"><span class="lname">${l[0]}</span>` +
                `<span class="lmeta">${l[1]}</span></span>` +
                `<span class="sgo">&#8250;</span></div>`,
            )
            .join("")
        : `<div class="snone"><div class="snt">${T.libNoneTitle}</div>` +
          `<div class="snb">${T.libNoneBody}</div></div>`) +
      `<div class="lhint">${s.hint || T.libWhy}</div>`
    );
  if (s.state === "loading")
    return (
      `<div class="sload"><i></i><i></i><i></i><i></i></div>` +
      `<div class="sfoot">${T.checking}</div>`
    );
  if (s.state === "empty")
    return (
      `<div class="snone"><div class="snt">${T.noneTitle}</div>` +
      `<div class="snb">${T.noneBody}</div></div>`
    );
  if (s.state === "remembered") {
    const others = ALL.filter((x) => x !== s.remembered);
    /* `noId` draws the state where no per-book identifier could
         be found for the remembered shop. Only Play Books has a
         different pair for it; the rest cannot be exact anyway. */
    const mode = s.noId && S[s.remembered].openNoId ? "openNoId" : "open";
    return (
      storeRow(s.remembered, mode, { check: true }) +
      storeRows(others, "get", { noId: s.noId }) +
      /* Not drawn red. showMenuBottomSheet's own API makes
                           isDestructive one flag away, but forgetting a store
                           is not deleting a book. */
      `<div class="srow clear"><span class="sico">&#8722;</span>` +
      `<span class="stx"><span class="slbl">${T.forget}</span></span></div>`
    );
  }
  return storeRows(s.stores, "get", {
    noId: s.noId,
    libbyExact: s.libbyExact,
  });
}

function sheet(s) {
  /* The title is the only thing that can report the remembered
                   state, because the bar icon cannot. See the `icon-unmarked`
                   screen for what that costs. */
  const title =
    s.state === "librarypick"
      ? T.libTitle
      : s.state === "remembered"
        ? T.yourCopy
        : T.whereToRead;
  return `<div class="sheet"><div class="st">${title}</div>${sheetBody(s)}</div>`;
}

/* The rejected tab-section branch's in-tab section. */
function storeSection(s) {
  if (s.where !== "tab") return "";
  if (s.state === "loading")
    return (
      `<div class="blk"><div class="h3">${T.whereToRead}</div>` +
      `<div class="sload"><i></i><i></i><i></i></div></div>`
    );
  if (s.state === "empty")
    return (
      `<div class="blk"><div class="h3">${T.whereToRead}</div>` +
      `<div class="snb">${T.noneBody}</div></div>`
    );
  if (s.state === "remembered") {
    const [lbl, sub] = S[s.remembered].open;
    return (
      `<div class="blk"><div class="h3">${T.yourCopy}</div>` +
      `<div class="openbtn">${lbl}<span>&#8599;</span></div>` +
      `<div class="ssub" style="text-align:center;margin-top:6px">${sub}</div></div>`
    );
  }
  const body =
    s.layout === "chips"
      ? storeChips(s.stores, "get")
      : storeRows(s.stores, "get", {});
  return `<div class="blk"><div class="h3">${T.whereToRead}</div>${body}</div>`;
}

/* The Book info tab. In the chosen design this is exactly as it
               ships — the headings are the real l10n strings, and
               `bookDescription` is "About this book", not "Book
               description". */
function tabBody(s) {
  if (s.tab === "notes")
    return (
      `<div class="tabbody"><div class="blk">` +
      `<div class="prose" style="color:var(--text2)">No notes yet</div>` +
      `</div></div>`
    );
  return (
    `<div class="tabbody">` +
    storeSection(s) +
    `<div class="blk"><div class="h3">About this book</div>` +
    `<div class="prose clip">Live commerce is no longer a channel bolted onto retail. ` +
    `This book follows six sellers through their first year, and asks what ` +
    `actually changed about the work.</div></div>` +
    `<div class="blk"><div class="h3">Publisher</div>` +
    `<div class="prose">\uc0dd\uac01\uc758\ud798</div></div>` +
    `<div class="blk"><div class="h3">ISBN</div>` +
    `<div class="prose">9791161571188</div></div></div>`
  );
}

/* The rejected hero-row branch's control. */
function heroCtl(s) {
  if (s.where !== "hero") return "";
  if (s.state === "empty") return "";
  if (s.state === "remembered") {
    const [lbl] = S[s.remembered].open;
    return `<div class="herostores">${lbl}<span class="g">&#8599;</span></div>`;
  }
  return `<div class="herostores">${T.whereToRead}<span class="g">&#8250;</span></div>`;
}

/** Draw one screen from its spec. */
function frame(s) {
  /* The Settings page, `libby-library` only. A different page entirely, so it
     short-circuits the book-details frame rather than adding flags to it.
     Deliberately drawn beside the EXISTING book-source row: that row is
     already "which catalogue does this app talk to", so the library belongs
     with it and needs no new section. */
  if (s.settings) {
    const row = (name, meta) =>
      `<div class="lrow"><span class="ltx">` +
      `<span class="lname">${name}</span>` +
      `<span class="lmeta">${meta}</span></span>` +
      `<span class="sgo">&#8250;</span></div>`;
    return (
      `<div class="fr"><div class="nav"><span class="back">&#8249;</span></div>` +
      `<div class="tabbody" style="padding-top:8px">` +
      `<div class="blk"><div class="h3">Books</div>` +
      row("Book search", "Google Books") +
      row("Library for borrowing", "King County Library System") +
      `<div class="lhint">Used for the Libby row on a book. Clearing it puts ` +
      `that row back to a plain search.</div></div></div></div>`
    );
  }
  let h = `<div class="fr">`;
  h += `<div class="nav"><span class="back">&#8249;</span>`;
  /* The shipped bar is `isSelf ? [delete, edit] : null`, so a
                   friend's book has no actions at all. This version has to
                   CREATE the group on a friend's book rather than add to it —
                   the one place it costs more than it looks. */
  if (s.isSelf || s.where === "bar") {
    h += `<span class="acts">`;
    if (s.where === "bar")
      h +=
        `<span class="ai newctl${s.marked ? " marked" : ""}">&#8599;` +
        (s.marked ? `<i class="dot"></i>` : "") +
        `</span>`;
    if (s.isSelf)
      h += `<span class="ai">&#128465;</span><span class="ai">&#9998;</span>`;
    h += `</span>`;
  }
  h += `</div>`;
  h += `<div class="hero"><div class="hrow">`;
  h += `<div class="cover"><div class="k1">\ub77c\uc774\ube0c<br/>\ucee4\uba38\uc2a4</div><div class="k3"></div><span class="bind"></span><span class="hair"></span></div>`;
  h += `<div class="rcol">${rcol(s)}</div></div>`;
  h += `<div class="corner"><span class="slab">IT 12</span></div>`;
  h += `</div><div class="shelf"></div>`;
  h += `<div class="band"><div class="btitle">\ub77c\uc774\ube0c \ucee4\uba38\uc2a4 \uc131\uacf5 \uc804\ub7b5</div><div class="bauth">\uc774\ud604\uc219</div>`;
  h += periodCard(s);
  h += heroCtl(s);
  h += `</div>`;
  h += `<div class="tabs"><s class="${s.tab === "notes" ? "" : "on"}">Book info</s><s class="${s.tab === "notes" ? "on" : ""}">Notes</s></div>`;
  h += tabBody(s);
  if (s.sheet) h += `<div class="scrim"></div>${sheet(s)}`;
  return h + `</div>`;
}

/* ==================================================================
   SECTION 3: DATA — the chosen design. An app-bar icon opening a sheet.
   ================================================================== */
/* Base specs, named so the version patches can derive from them
               instead of restating them. Restating an unchanged screen in a
               patch is the drift the data model exists to prevent, and it
               makes the diff report changes that are not there. */
const B = {
  closed: {
    where: "bar",
    tab: "info",
    state: "acquire",
    stores: ALL,
    isSelf: true,
    status: 0,
  },
  open: {
    where: "bar",
    tab: "info",
    state: "acquire",
    stores: ALL,
    isSelf: true,
    status: 0,
    sheet: "stores",
  },
  reading: {
    where: "bar",
    tab: "info",
    state: "acquire",
    stores: ALL,
    isSelf: true,
    status: 1,
  },
  remembered: {
    where: "bar",
    tab: "info",
    state: "remembered",
    remembered: "kindle",
    stores: ALL,
    isSelf: true,
    status: 1,
    sheet: "stores",
  },
  friend: {
    where: "bar",
    tab: "info",
    state: "acquire",
    stores: ALL,
    isSelf: false,
    status: 2,
    praise: true,
  },
};

const SCREENS = [
  [
    "Own book &middot; nothing known yet",
    [
      [
        "bar-icon",
        "The entry point",
        "One 24pt glyph beside delete and edit. The tab body is exactly as it ships \u2014 no section, description unclipped, headings still the real l10n strings. That is the whole argument for this version: nothing is spent. The cost is that nothing is advertised either, and the glyph has to carry a novel action on its own, which is why its tooltip is real copy rather than an afterthought.",
        B.closed,
      ],
      [
        "sheet-open",
        "Where to read",
        "The design. Four destinations at ListTile's real 56pt, each with a second line that says what a tap actually does \u2014 and that second line is the only place Kindle can admit it leads to an Amazon search rather than to the book. If these four rows ever look interchangeable, the feature has started lying.",
        B.open,
      ],
      [
        "sheet-open-noid",
        "… when both lookups miss",
        "The same sheet after the two on-demand lookups come up empty, which is the ordinary case for a Korean book rather than an edge: Kakao supplies no Google volume id, and Apple's kr ISBN coverage is thin enough that most Korean titles miss. Two rows lose their exact promise and say so, and Kindle and Libby are unchanged because nothing could ever have upgraded them — which is the clearest demonstration on this page that the second line is derived from the reach rather than written per shop. Worth looking at next to sheet-open: the sheet degrades without changing shape, so nothing moves and nothing has to apologise.",
        { ...B.open, noId: true },
      ],
      [
        "apple-absent",
        "Apple says it has no edition",
        "The three-way answer, drawn. Apple's row is **gone**, not degraded, and that is the only honest option left: `books.apple.com/<cc>/search?term=` does open the Books app -- the domain is claimed -- and then ignores the term completely, landing the reader on an empty search box under a row that said \u201cSearches Apple Books\u201d. Since a bare app launch is banned for an acquire link, and no wording describes an empty search box as a way to get a book, the row is withdrawn. Compare sheet-open: only Apple leaves, the sheet keeps its shape, and nothing apologises. **The asymmetry is the point** -- this fires only when Apple *answered*; a timeout or an offline device keeps the row, because hiding a shop on the strength of a dropped connection would be the worse error.",
        { ...B.open, stores: ["play", "kindle", "libby"] },
      ],
      [
        "loading",
        "Checking the stores",
        "Availability resolves after the sheet is up, where a spinner is unremarkable and no layout above it moves. Strictly the best home for the async problem of the three versions considered \u2014 the tab-section branch has to reserve height and the hero-row branch cannot take a late height change at all.",
        { ...B.open, state: "loading" },
      ],
      [
        "empty",
        "Nothing found",
        "Title plus body, on the scanNoMatch pattern: what happened, why, and no blame. Deliberately does not name the ISBN \u2014 scanNoMatchBody does, but there the reader had just scanned a barcode so the number was salient. Here it is developer-facing. A real state, not an edge case: Book.isbn is sometimes a Google volume id.",
        { ...B.open, state: "empty" },
      ],
    ],
  ],
  [
    "Own book &middot; store remembered",
    [
      [
        "remembered",
        "Your copy &middot; Kindle",
        'After one tap on Kindle. The title changes because the icon cannot, the remembered store takes the check MenuAction.isSelected already draws, and the verb drops to Open because that is all Kindle can do. "Opens your Kindle library" is the honest line, and it is honest without apologising.',
        B.remembered,
      ],
      [
        "remembered-play",
        "Your copy &middot; Play Books",
        "The one store where opening can be exact: accessInfo.webReaderLink lands on this book. So the verb becomes Read in rather than Open, and the second line says at this book. That four-character difference is the most valuable copy on the page \u2014 a reader who learns it once can trust every row. Requires a Google Books volume id; see remembered-play-noid for when there isn't one.",
        { ...B.remembered, remembered: "play" },
      ],
      [
        "remembered-play-noid",
        "Your copy &middot; Play Books, no id",
        "**The reported bug, and its fix.** Play Books was the only shop with no app fallback, so an id-less open fell through to a Play Store search while this row still read \u201cOpen Play Books\u201d \u2014 a row promising the app and performing a search, which is precisely what StoreReach exists to prevent. It survived because the tests walked one happy path per shop rather than the grid; all sixteen store \u00d7 intent \u00d7 id combinations are asserted now, and the invariant is stated directly: no open link may ever be a search. Reached less often than it was, because a Kakao-sourced book now gets one keyless Google Books lookup first \u2014 this is the state after that comes up empty too.",
        { ...B.remembered, remembered: "play", noId: true },
      ],
      [
        "icon-unmarked",
        "The icon cannot say it knows",
        "This version's structural cost, drawn. A book whose store is remembered looks identical from the outside \u2014 same glyph, same tooltip, both equally true. So opening your own copy is always two taps and is never advertised, which is a real loss given that the remembered state is what makes opening a copy deliverable at all.",
        { ...B.remembered, sheet: null },
      ],
      [
        "icon-marked",
        "\u2026 unless the glyph changes",
        'The proposed fix, and an open decision. A dot on the glyph when reader_app is set. Cheap in Flutter and impossible later without users relearning the control, so it wants deciding now. Copy cannot solve this one: "Where to read" is equally true either way.',
        { ...B.remembered, sheet: null, marked: true },
      ],
    ],
  ],
  [
    "Friend's book",
    [
      [
        "friend-finished",
        "A friend's finished book",
        "The discovery moment, and the reason the entry point must not be isSelf-gated the way delete and edit are. Also the hidden cost: the shipped bar is isSelf ? [delete, edit] : null, so this version has to bring the actions group into existence for a single icon \u2014 and that icon is then the only action in the bar.",
        B.friend,
      ],
      [
        "friend-sheet",
        "A friend's book &middot; acquire only",
        "Always the acquire list, never Your copy: reader_app is the owner's fact, so showing \"Open Kindle\" here because your friend uses Kindle would be wrong \u2014 and RLS would block the write anyway, so a friend's book needs no write path at all. No check, no forget row.",
        { ...B.friend, sheet: "stores" },
      ],
    ],
  ],
  [
    "Reachability",
    [
      [
        "notes-tab",
        "Notes tab &middot; icon survives",
        "The strongest single argument for this version. The bar is pinned by SliverPersistentHeader, so the control is reachable from both tabs and at any scroll offset. The tab-section branch loses it entirely on this swipe.",
        { ...B.closed, tab: "notes" },
      ],
      [
        "reading-book",
        "On a Reading book",
        "The tallest hero \u2014 cover 180, shelf 8, title, author, status card \u2014 completely unchanged, because this version adds nothing below the bar. Worth drawing precisely because there is nothing to see.",
        B.reading,
      ],
    ],
  ],
];

const ELEMENTS = [
  [
    "The store row",
    [
      [
        "el-row-kinds",
        "Acquiring &middot; exact vs search",
        'The same row saying two different things. Play Books has a per-book URL and says "Opens this book"; Kindle has only a query and says "Searches Amazon". Check this element first after any copy change \u2014 it is the honesty the whole design rests on.',
        `<div class="fr" style="width:353px;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0">${storeRow("play", "get", {})}${storeRow("kindle", "get", {})}</div></div>`,
      ],
      [
        "el-row-verbs",
        "Opening &middot; the verb split",
        "Read in Play Books promises a book; Open Kindle promises an app. The second lines follow \u2014 \u201cOpens at this book\u201d against \u201cOpens your Kindle library\u201d. Both lead with what does happen, which is what app_en.arb does everywhere (\u201cCover reading is limited to keep it free\u201d) rather than warning about what doesn't.",
        `<div class="fr" style="width:353px;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0">${storeRow("play", "open", { check: true })}${storeRow("kindle", "open", { check: true })}</div></div>`,
      ],
      [
        "el-row-libby",
        "Libby",
        "The one destination with no App Store guideline 3.1.1 exposure at all, because nothing is being sold. Also the one that makes the sheet read as a service rather than an affiliate shelf. But see the localisation note: Libby maps to US and UK library systems and is meaningless in the ko build.",
        `<div class="fr" style="width:353px;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0">${storeRow("libby", "get", {})}</div></div>`,
      ],
      [
        "el-clear",
        "Forget where I read this",
        'The escape hatch that keeps a wrong guess from being a trap, since a tap is not a purchase. Not drawn red: showMenuBottomSheet makes isDestructive one flag away, but forgetting a store is not deleting a book. Chosen over "Forget where this lives", which is an idiom and would not survive translation.',
        `<div class="fr" style="width:353px;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0"><div class="srow clear"><span class="sico">&#8722;</span><span class="stx"><span class="slbl">${T.forget}</span></span></div></div></div>`,
      ],
    ],
  ],
  [
    "States",
    [
      [
        "el-empty",
        "Empty state",
        "Title plus body, matching scanNoMatchTitle/Body. Body is secondaryText at #626A72, which is 4.63:1 on the sheet. The praise-region frame this page forks still carries the old #ADB5BD at 2.07:1 \u2014 an empty state drawn in that token looks fine in a mockup and is unreadable on a device, which is how the original defect survived twenty-nine files.",
        `<div class="fr" style="width:353px;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0"><div class="snone"><div class="snt">${T.noneTitle}</div><div class="snb">${T.noneBody}</div></div></div></div>`,
      ],
      [
        "el-loading",
        "Checking the stores",
        "Ellipsis character, not three dots \u2014 app_en.arb uses \u2026 throughout (\u201cLooking it up\u2026\u201d, \u201cReading the cover\u2026\u201d). Four shimmer rows because four destinations are expected, so the sheet does not resize when they land.",
        `<div class="fr" style="width:353px;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0"><div class="sload"><i></i><i></i><i></i><i></i></div><div class="sfoot">${T.checking}</div></div></div>`,
      ],
    ],
  ],
  [
    "Open questions",
    [
      [
        "el-icon",
        "The glyph &middot; unmarked vs marked",
        "Left: what ships if nothing changes \u2014 identical whether or not a store is known. Right: a dot when reader_app is set. This is the one thing copy cannot fix, because the tooltip is equally true in both states.",
        `<div class="logocmp"><div><h5>Unmarked</h5><div class="fr" style="width:150px;height:auto;background:var(--surface)"><div class="nav"><span class="acts"><span class="ai newctl">&#8599;</span><span class="ai">&#9998;</span></span></div></div></div><div><h5>Marked</h5><div class="fr" style="width:150px;height:auto;background:var(--surface)"><div class="nav"><span class="acts"><span class="ai newctl marked">&#8599;<i class="dot"></i></span><span class="ai">&#9998;</span></span></div></div></div></div>`,
      ],
      [
        "el-logos",
        "Brand marks &middot; and the two that have none",
        "Settled: real marks where one can be sourced, the store's initial where one cannot. The split is a sourcing fact, not an unfinished job \u2014 Simple Icons (CC0, monochrome, tintable) has no `amazon*` icon at all and no Libby/OverDrive icon, so Play Books and Apple Books get marks and Kindle and Libby keep the letter. The two alternatives were both worse: drawing the missing marks invents a trademark, and the official brand kits are full-colour wordmark lockups whose clear-space rules a 30pt chip breaks. Right shows the rejected brand-colour treatment \u2014 in a sheet this typographic, a coloured chip is the loudest thing on the page, and it would not follow dark mode.",
        `<div class="logocmp"><div><h5>Tinted, with letter fallback (ships)</h5><div class="fr" style="width:100%;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0">${storeRows(["play", "apple", "kindle", "libby"], "get", {})}</div></div></div><div><h5>Brand colour (rejected)</h5><div class="fr" style="width:100%;height:auto;border:0;background:var(--sheet);padding:0"><div class="sheet" style="position:static;box-shadow:none;border-radius:0;padding:0">${storeRows(["play", "kindle"], "get", { brandColour: true })}</div></div></div></div>`,
      ],
    ],
  ],
];

/* Mark an id as an unresolved decision; renders inline as a red callout. */
const OPEN = {
  "acquire-remember":
    "Open decision: a tap is not a purchase. Tapping Kindle to look at the price and never buying leaves the book wrongly marked. The forget row is the mitigation, but the alternative \u2014 asking outright, or only remembering after a second visit \u2014 has not been ruled out. SHARPENED since: the recording gate now fires on open taps too, not just acquire ones, and Reading/Finished books lead with open rows -- so there are more writing taps, on books a reader may only be browsing.",
  "icon-marked":
    "Open decision: should the glyph change when a store is remembered? Cheap now, expensive after release. Copy cannot substitute.",
  "el-row-libby":
    "Open decision: the ko store set. Libby, Kindle and Apple Books are the wrong four for Korean readers, who use \ub9ac\ub514\ubd81\uc2a4, \ubc00\ub9ac\uc758\uc11c\uc7ac, \uc608\uc2a424 and \uad50\ubcf4. Needs settling before strings are written, because it is not a wording problem.",
};

/* ==================================================================
   SECTION 4: VERSIONS — the chosen design, and the two it beat.

   The root is the settled design. Both branches are SUPERSEDED and say so
   in their notes, so neither can be mistaken for current. Patches derive
   from the B specs rather than restating them.
   ================================================================== */
const VERSIONS = [
  [
    "bar-sheet",
    "bar-sheet",
    "CHOSEN. An app-bar icon opening a sheet. Costs the hero and the tab body nothing, resolves availability where a spinner is already normal, and is the only version reachable from both tabs because the bar is pinned. Its cost is that the glyph cannot report a remembered store \u2014 see icon-unmarked.",
    null,
    {},
  ],
  [
    "tab-section",
    "tab-section",
    "SUPERSEDED. A section at the top of the Book info tab, above the description. Showed all four second lines without a tap, which is its one real advantage over the chosen design \u2014 but it disappears on the Notes tab and spends 193pt of the tab body on a secondary action.",
    "bar-sheet",
    {
      screens: {
        "bar-icon": {
          name: "Acquire &middot; section in the tab",
          note: "SUPERSEDED. Four 48pt rows above the description, all four second lines visible on arrival with nothing to tap. 48 rather than ListTile's 56 because four 56pt rows pushed the description off a 393pt frame entirely.",
          spec: {
            ...B.closed,
            where: "tab",
            layout: "rows",
          },
        },
        "sheet-open": {
          name: "Acquire &middot; chips",
          note: "SUPERSEDED, and rejected within its own branch. Half the height, but a chip has no second line, so Kindle can only be marked with a dashed outline and never explained. Drawing it is what settled that the second line is not decoration.",
          spec: {
            ...B.closed,
            where: "tab",
            layout: "chips",
          },
        },
        loading: {
          name: "Resolving &middot; in the tab",
          note: "SUPERSEDED. Three shimmer rows inside bookInfoAsync.when, which already has a loading branch. Workable, but the height has to be reserved or the description jumps when the answer lands.",
          spec: {
            ...B.closed,
            where: "tab",
            layout: "rows",
            state: "loading",
          },
        },
        empty: {
          name: "Nothing found &middot; in place",
          note: "SUPERSEDED, and this branch's best state: the section can say so exactly where the reader is already looking, with no sheet to open. The chosen design makes this a sheet that opens onto a sentence.",
          spec: {
            ...B.closed,
            where: "tab",
            layout: "rows",
            state: "empty",
          },
        },
        remembered: {
          name: "Your copy &middot; in the tab",
          note: "SUPERSEDED. A 44pt filled button, the height ElevatedActionButton uses for Save. Loud for a secondary action, but it does what the chosen design cannot: shows on arrival that a store is already known.",
          spec: {
            ...B.remembered,
            where: "tab",
            sheet: null,
          },
        },
        "remembered-play": null,
        "remembered-play-noid": null,
        /* Dropped for the same reason the chips lost: a chip has no second
           line, so a degraded row has nowhere to admit it degraded. The
           state exists in this branch too and simply cannot be drawn. */
        "sheet-open-noid": null,
        /* Dropped for the same reason: this branch cannot show a row
           leaving the list without the list being the design. */
        "apple-absent": null,
        "icon-unmarked": null,
        "icon-marked": null,
        "friend-sheet": null,
        "notes-tab": {
          name: "Notes tab &middot; section gone",
          note: "SUPERSEDED, and the reason. Swipe to Notes and the control does not exist. The chosen design keeps it, because the bar is pinned and the tab body is not.",
          spec: {
            ...B.closed,
            where: "tab",
            layout: "rows",
            tab: "notes",
          },
        },
        "friend-finished": {
          name: "A friend's book &middot; in the tab",
          note: "SUPERSEDED. Reaction controls in the hero, acquire rows in the tab. No bar actions at all, which is the shipped behaviour \u2014 the chosen design has to change that.",
          spec: { ...B.friend, where: "tab", layout: "rows" },
        },
        "reading-book": {
          name: "On a Reading book &middot; in the tab",
          note: "SUPERSEDED. The status card plus the section, which is where the 193pt cost is easiest to see.",
          spec: {
            ...B.reading,
            where: "tab",
            layout: "rows",
          },
        },
      },
      open: {
        "icon-marked": null,
        "sheet-open":
          "Rejected: chips cannot carry a supporting line, so the search-only store is marked rather than explained.",
      },
    },
  ],
  [
    "hero-row",
    "hero-row",
    "SUPERSEDED. A 40pt row in the band under the status card. Read as first-class and survived the tab swipe, but spent permanent header height on every book, hid all four second lines behind a sheet anyway, and could not handle the empty state \u2014 hiding the row varies the header height, which moves the title handoff _handleScroll measures.",
    "bar-sheet",
    {
      screens: {
        "bar-icon": {
          name: "Acquire &middot; hero row",
          note: 'SUPERSEDED. One row in the band. The label can only say "Where to read" \u2014 which store does what is invisible until the sheet opens, so it pays the header cost and still buys none of the honesty the tab-section branch got for free.',
          spec: { ...B.closed, where: "hero" },
        },
        empty: {
          name: "Nothing found &middot; row hidden",
          note: "SUPERSEDED, and this branch's worst state. Hiding the row is the only honest option and it changes the header's height between books, which moves the title handoff _handleScroll computes. Reserving the space instead leaves a dead control.",
          spec: {
            ...B.closed,
            where: "hero",
            state: "empty",
          },
        },
        remembered: {
          name: "Your copy &middot; hero row",
          note: "SUPERSEDED. Where this branch was strongest: one tap from arrival, no scrolling, no tab, and visibly already known.",
          spec: {
            ...B.remembered,
            where: "hero",
            sheet: null,
          },
        },
        "remembered-play": null,
        "remembered-play-noid": null,
        /* Dropped: the band shows one destination, so there is no list in
           which a row could visibly lose its exact promise. */
        "sheet-open-noid": null,
        /* Dropped for the same reason: this branch cannot show a row
           leaving the list without the list being the design. */
        "apple-absent": null,
        "icon-unmarked": null,
        "icon-marked": null,
        "friend-sheet": null,
        loading: {
          name: "Resolving &middot; hero row",
          note: "SUPERSEDED. The row draws immediately and the sheet resolves when opened, which is how this branch dodged the height-change problem \u2014 at the price of never being able to hide the row when nothing is available.",
          spec: { ...B.closed, where: "hero" },
        },
        "sheet-open": {
          name: "Sheet &middot; opened from the band",
          note: "SUPERSEDED. Identical sheet to the chosen design's, reached from the band instead of the bar. That the sheet is shared is what made the entry point the only real question.",
          spec: { ...B.open, where: "hero" },
        },
        "notes-tab": {
          name: "Notes tab &middot; row survives",
          note: "SUPERSEDED. The band is above the tab strip, so this branch kept the control too. The chosen design gets the same property from a pinned bar without spending header height.",
          spec: {
            ...B.closed,
            where: "hero",
            tab: "notes",
          },
        },
        "friend-finished": {
          name: "A friend's book &middot; hero row",
          note: "SUPERSEDED. The row lands directly under the reaction capsule, so the hero carries two competing controls in the same 100pt. The densest real state in the app, and the one this branch was most likely to break.",
          spec: { ...B.friend, where: "hero" },
        },
        "reading-book": {
          name: "On a Reading book &middot; hero row",
          note: "SUPERSEDED. The tallest hero plus a 40pt control, all before the tab strip. The state to judge the branch on.",
          spec: { ...B.reading, where: "hero" },
        },
      },
      open: {
        "icon-marked": null,
        empty:
          "Rejected: this branch must either hide the row and vary the header height, or keep a control that leads nowhere.",
      },
    },
  ],
  /* ==================================================================
     BUILT. Asking the reader for their library once, so Libby can reach
     a book instead of a shelf.

     Kept as a branch rather than folded into the root because both
     states ship: the root's sheet screens are the reader who has not
     answered (or declined), and this branch is the reader who has. The
     root is not stale, it is the other half.

     Its one UNRESOLVED question -- "I could not find a library NAME
     search API" -- turned out to be answerable. See the flow's callout.
     ================================================================== */
  [
    "libby-library",
    "libby-library",
    "BUILT. Ask for the reader's library once, so Libby can reach the book rather than the shelf. **Required, not a nicety:** `libbyapp.com/title/<id>` shows \"View not found.\" because Libby resolves `title/<id>` only beneath `library/<key>`, taking the key from its ancestor route. With a key, `libbyapp.com/library/<key>/title/<id>` reaches the book *and* the loan; without one, acquiring stops at `overdrive.com/media/<id>` in a browser and opening stops at the Shelf. The ask is just-in-time on the first Libby tap, dismissible, and remembered either way. Stored in SharedPreferences beside the book-source preference rather than the drawn nullable column \u2014 see the spec. Note this is a **library**, not a library card: the card stays Libby's business.",
    "bar-sheet",
    {
      screens: {
        "libby-ask": {
          group: "Proposal &middot; asking once",
          name: "First tap on Libby",
          note: "The just-in-time ask, and the whole reason this is affordable. It is not onboarding and not a settings chore \u2014 it appears the first time the reader taps Libby, when they have just shown they want it, and never again. Drawn as a sheet rather than a pushed page because it is one choice made once, reached from inside a sheet; a route would take the reader further from the book than the decision warrants. The line at the bottom answers \u201cwhy are you asking me this\u201d in one sentence, and answers it with Libby's constraint rather than ours \u2014 Libby cannot search without a library either.",
          spec: {
            ...B.open,
            state: "librarypick",
            libs: [
              ["King County Library System", "Washington, US"],
              ["Kitsap Regional Library", "Washington, US"],
              ["Kings County Library", "California, US"],
            ],
          },
        },
        "libby-typed": {
          group: "Proposal &middot; asking once",
          name: "\u2026 narrowed by typing",
          note: "Two lines per result, for the same reason the store rows have two: the second line is the only thing that tells two similarly-named systems apart, and \u201cKing County\u201d vs \u201cKings County\u201d is exactly the confusion a reader would otherwise resolve by guessing. **This screen is where the risk lives** \u2014 it assumes a name search exists, and I could not find one. See the flow's open callout.",
          spec: {
            ...B.open,
            state: "librarypick",
            typed: "king count",
            libs: [
              ["King County Library System", "Washington, US"],
              ["Kings County Library", "California, US"],
            ],
          },
        },
        "libby-none": {
          group: "Proposal &middot; asking once",
          name: "Nothing by that name",
          note: "Takes the scanNoMatch shape every other failure in the app takes \u2014 what happened, why, no blame. **The second line was rewritten during the build**, and the reason is worth keeping: this used to spend it warning readers off searching a branch instead of the system that runs it. That warning would have been wrong. `locate.libbyapp.com/autocomplete` searches branches and resolves each to its parent system, so \u2018Mission Bay Branch Library\u2019 finds San Francisco Public Library and \u2018Auburn Library\u2019 finds King County Library System. The shipped line offers all three kinds of query \u2014 full name, town, nearby branch \u2014 because all three genuinely work.",
          spec: {
            ...B.open,
            state: "librarypick",
            typed: "auburn",
            libs: [],
          },
        },
        "libby-exact": {
          group: "Proposal &middot; what it buys",
          name: "Libby reaches the book",
          note: "The payoff, and the only screen worth comparing against the shipped build. With a library key the row can be exact: a title id from that library's catalogue resolves a per-book Libby link, and title ids are global \u2014 the same query against lapl, chipublib and nassau returns the same id \u2014 so one key serves any reader. Note what does NOT change: Kindle stays a search, because nothing can upgrade it. The sheet is the same shape, one row got better, and no copy was invented to celebrate it.",
          spec: { ...B.open, libbyExact: true },
        },
        "libby-settings": {
          group: "Proposal &middot; what it buys",
          name: "Changing it later",
          note: "A stored answer needs a way back, exactly as `Forget where I read this` does for the store \u2014 people move, join a second system, or mistype. Sits beside the existing book-source picker in Settings, which is already the row for \u201cwhich catalogue does this app talk to\u201d, so it needs no new section and nothing has to be explained twice.",
          spec: { ...B.open, settings: true },
        },
      },
      flows: {
        "libby-first-run": {
          group: "Proposal",
          note: "Four steps, once per reader, and then never again.",
          steps: [
            [
              "Tap Libby",
              "Nothing is stored yet, so the row still reads Borrow free from your library \u2014 truthful before and after.",
              { ...B.open, sheet: "stores" },
            ],
            [
              "Which library?",
              "Asked here and only here. Dismissing falls back to today's behaviour rather than blocking: overdrive.com search, which needs no library.",
              {
                ...B.open,
                state: "librarypick",
                libs: [
                  ["King County Library System", "Washington, US"],
                  ["Kitsap Regional Library", "Washington, US"],
                ],
              },
            ],
            [
              "Saved",
              "One nullable column, on the same reasoning as reader_app: NULL means never asked, which is a different state from asked-and-declined.",
              { ...B.open, libbyExact: true },
            ],
            [
              "Every book after this",
              "The ask never returns. Libby is exact when the library holds the book, and an honest search when it does not.",
              { ...B.open, libbyExact: true },
            ],
          ],
        },
      },
      open: {
        "libby-first-run":
          'RESOLVED, and the way it was wrong is the lesson. This said no library NAME search API existed. What had actually been established was narrower: `thunder.api.overdrive.com/v2/libraries` really is a 13,112-row directory filtering only by `libraryKeys` and `websiteIds`, and `/libraries/search` and `/libraries/autocomplete` really do 404. But Libby does not use `thunder` for this. Its bundle derives a **separate** service by rewriting its own root \u2014 `_createDeweyLocateService` does `ROOT_URI.replace("//", "//locate.")` \u2014 and calls `autocomplete/<query>` on it. `https://locate.libbyapp.com/autocomplete/<query>` is keyless and returns 200. Two hops are needed, because `locate` returns a system\'s `websiteId` and the URL wants its key: then `thunder/v2/libraries?websiteIds=\u2026` gives `preferredKey`. **\u2018This API does not exist\u2019 is a much stronger claim than \u2018I did not find it on the host I was looking at\u2019, and only the second one had been shown.** One bonus: the endpoint searches BRANCHES and resolves them to the system that runs them, so \u2018Mission Bay Branch Library\u2019 finds San Francisco Public Library \u2014 the branch-versus-system confusion this flow\'s empty state was drawn to warn about does not happen, and that copy was rewritten to offer all three kinds of query instead.',
      },
    },
  ],
];

const FLOWS = [
  [
    "Acquiring",
    [
      [
        "acquire-remember",
        "First tap, then remembered",
        "The whole design in four steps: the reader answers the ownership question by acting, and the sheet changes shape once they have. Nothing is asked outright, because nothing can be \u2014 canLaunchUrl proves an app is installed, never that the book is in it.",
        [
          [
            "Tap the glyph",
            "An Interested book. No reader_app on the row, so the sheet will offer the acquire list.",
            B.closed,
          ],
          [
            "Where to read",
            'Four destinations, each honest about what it opens. Kindle says "Searches Amazon" because Amazon publishes no per-book deep link.',
            B.open,
          ],
          [
            "Back in the app",
            "books.reader_app is now 'kindle'. The title becomes Your copy, Kindle takes the check, and the verb drops to Open \u2014 \"Opens your Kindle library\", which is all it can do.",
            B.remembered,
          ],
          [
            "Wrong guess, undone",
            "The forget row. A tap was never proof of purchase, so this is what keeps a wrong guess from being a trap.",
            B.remembered,
          ],
        ],
      ],
      [
        "nothing-found",
        "Nothing to offer",
        "Two steps, and the reason the empty state is drawn at all: Book.isbn is not always an ISBN \u2014 book_search_service.dart stores a Google volume id when no ISBN exists, and Kakao's mapper keeps only the first space-separated token \u2014 so this path is ordinary rather than exceptional.",
        [
          [
            "Checking the stores",
            "Four shimmer rows, so the sheet does not resize when the answer lands.",
            { ...B.open, state: "loading" },
          ],
          [
            "No ebook edition",
            "Title plus body, no blame, and no ISBN on screen. The reader learns the question was asked and answered.",
            { ...B.open, state: "empty" },
          ],
        ],
      ],
    ],
  ],
  [
    "Opening a copy",
    [
      [
        "open-copy",
        "Opening the copy you own",
        "Three steps, and the last cannot be drawn: the app is gone. Worth stating plainly \u2014 every claim this feature makes about opening a copy ends outside the process, so the only thing the design controls is whether the label promised something the launch can deliver.",
        [
          [
            "The glyph, unchanged",
            "A remembered book looks identical from the outside. This is the version's structural cost: opening your own copy is two taps and is never advertised.",
            { ...B.remembered, sheet: null },
          ],
          [
            "Your copy",
            "Play Books, the one store where opening is exact \u2014 accessInfo.webReaderLink lands on this book, so the verb is Read in rather than Open.",
            { ...B.remembered, remembered: "play" },
          ],
          [
            "Play Books takes over",
            "Not drawable. For Kindle and Apple Books this step is the app's own library rather than the book, which is precisely what their second line says.",
            { ...B.remembered, remembered: "play" },
          ],
        ],
      ],
    ],
  ],
  [
    "Discovery",
    [
      [
        "friend-discovery",
        "Finding what a friend read",
        "The case for not gating the entry point on isSelf. Two steps, no writes: a friend's book never records a store, because the column belongs to its owner and RLS would refuse the update anyway.",
        [
          [
            "Their finished book",
            "Reaction pill and capsule in the hero. The bar exists only because this version creates it \u2014 shipped, a friend's book has no actions at all.",
            B.friend,
          ],
          [
            "Acquire only",
            "Never Your copy, no check, no forget row. Their reader_app is theirs, and showing it here would be wrong even if RLS allowed the read.",
            { ...B.friend, sheet: "stores" },
          ],
        ],
      ],
    ],
  ],
];
