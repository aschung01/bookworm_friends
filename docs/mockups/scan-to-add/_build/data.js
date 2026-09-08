   SECTION 2: FRAME RENDERER — the Add Book sheet, the scanner, and the
   book info sheet, drawn from data by one function.

   Two chrome families, one renderer, because the whole argument of this
   set is that they are one flow. If the sheet's search row changes, it
   changes in `srow()` and every screen and every flow step follows.
   ================================================================== */
            /* Cover colours. Arbitrary, but fixed per position so a book
               does not change colour between a screen and a flow step. */
            const PAL = [
                "#C8402F",
                "#2F5FA8",
                "#4A7C59",
                "#D9A227",
                "#6B4E8F",
                "#31707A",
                "#B5563F",
                "#3E5C76",
            ];

            const PATHS = {
                viewfinder:
                    '<path d="M3 8V5.5A2.5 2.5 0 0 1 5.5 3H8"/><path d="M16 3h2.5A2.5 2.5 0 0 1 21 5.5V8"/><path d="M21 16v2.5A2.5 2.5 0 0 1 18.5 21H16"/><path d="M8 21H5.5A2.5 2.5 0 0 1 3 18.5V16"/><circle cx="12" cy="12" r="3.4"/>',
                barcode:
                    '<path d="M4 5v14M7.5 5v14M11 5v10M14.5 5v14M18 5v14M20.5 5v10"/>',
                camera:
                    '<path d="M3 9A2.5 2.5 0 0 1 5.5 6.5h1.3l1.1-1.9h6.2l1.1 1.9h3.3A2.5 2.5 0 0 1 21 9v7.5A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z"/><circle cx="12" cy="12.6" r="3.3"/>',
                close: '<path d="M6 6l12 12M18 6L6 18"/>',
                torch: '<path d="M9.2 3h5.6v2.6L13.6 8h-3.2L9.2 5.6z"/><path d="M10.4 8h3.2v10.4a1.6 1.6 0 0 1-3.2 0z"/>',
                photos: '<rect x="3" y="5" width="18" height="14" rx="2.4"/><path d="M3 15.6l4.6-4.2 3.6 3.2 3-2.6L21 16.2"/><circle cx="8.6" cy="9.4" r="1.4"/>',
                search: '<circle cx="10.6" cy="10.6" r="6.2"/><path d="M15.2 15.2 20.5 20.5"/>',
                clear: '<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6"/>',
                book: '<path d="M12 6.6C10.2 5.2 7.6 4.6 4 4.6v13c3.6 0 6.2.6 8 2 1.8-1.4 4.4-2 8-2v-13c-3.6 0-6.2.6-8 2z"/><path d="M12 6.6v12"/>',
                chevron: '<path d="M9 5l7 7-7 7"/>',
                type: '<path d="M4 7h16M4 12h11M4 17h7"/>',
                gear: '<circle cx="12" cy="12" r="3.1"/><path d="M12 2.6v2.6M12 18.8v2.6M4.4 12H1.8M22.2 12h-2.6M6.6 6.6 4.8 4.8M19.2 19.2l-1.8-1.8M17.4 6.6l1.8-1.8M4.8 19.2l1.8-1.8"/>',
            };
            const ic = (n, size) =>
                `<svg width="${size || 20}" height="${size || 20}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${n === "book" ? 1.3 : 1.7}" stroke-linecap="round" stroke-linejoin="round">${PATHS[n]}</svg>`;

            /* ---------------------------------------------------------------
               Vertical layout of the scanner, in points from the top of its
               own box. The only place these live, so the page and sheet
               variants cannot drift and frame.css cannot contradict them.

               `page` is the pushed-route case on a 402x874 device:
               viewPadding.top 62 for the button row, a 190pt scan window
               with 250pt of framing room above it, the barcode pair centred
               inside that window, and a 48pt cover-read pill clear of the 34pt
               home-indicator strip. `read` sits 30pt below the window's
               bottom edge, so the decoded value never lands on the symbol it
               came from.

               `sheet` is the same chrome inside a modal 82% of the screen
               tall. No status bar to clear, so the row starts at 20 — but
               the framing room above the window collapses from 250 to 150,
               which is the finding that variant exists to show.
               --------------------------------------------------------------- */
            const LAY = {
                page: {
                    camH: 874,
                    top: 62,
                    subj: 150,
                    retic: 250,
                    ean: 303,
                    read: 470,
                    nudge: 712,
                    shut: 768,
                    card: 268,
                },
                sheet: {
                    camH: 717,
                    top: 20,
                    subj: 96,
                    retic: 150,
                    ean: 203,
                    read: 370,
                    nudge: 555,
                    shut: 611,
                    card: 168,
                },
            };

            /* An EAN-13 and, beside it, the 5-digit add-on Korean books print
               next to it. `n` bars sized to fill 176pt / 64pt of white. */
            function bars(n) {
                return Array.from(
                    { length: n },
                    (_, i) =>
                        `<b class="${i % 3 === 0 ? "w" : ""}${i % 7 === 0 ? " s" : ""}"></b>`,
                ).join("");
            }
            function eanPair(cand) {
                return `<div class="ean${cand ? " won" : ""}"><div class="bars">${bars(38)}</div><div class="dig">9788954699914</div></div><div class="ean addon"><div class="bars">${bars(13)}</div><div class="dig">03810</div></div>`;
            }

            /* ---- shared pieces ------------------------------------------- */

            /** One ShelfRow: books bottom-aligned on a plank, label on the plank. */
            function shelfRow(name, heights, seed) {
                const books = heights
                    .map(
                        (h, i) =>
                            `<u style="--c:${PAL[(i + seed) % PAL.length]};height:${h}px;width:${(h * 2) / 3}px"><i></i></u>`,
                    )
                    .join("");
                return `<div class="srow3"><div class="bks">${books}</div>${name ? `<span class="slabel">${name}</span>` : ""}</div><div class="shelf"></div>`;
            }

            /* Heights are `screenHeight * 0.15` = 131 with BookJitter applied,
               which ranges 0.94..1.06 of the base, i.e. 123..139. Counts are
               chosen so the first row overflows (the ordinary case, and what
               puts the label on top of a cover) and the last one does not, so
               the book a scan just added is actually visible. */
            const SHELVES = [
                [
                    "\uc9d1\uc5d0 \uc788\ub294 \ubcf4\ubc30",
                    [131, 138, 124, 135],
                    0,
                ],
                ["\uc0c0\uc9c0\ub9cc \uc548 \uc77d\uc740", [126, 139, 130], 3],
                ["\uc2dc", [134, 127], 6],
            ];

            /** The library. `landed` adds the book a scan just saved. */
            function library(landed) {
                return `<div class="lib">${SHELVES.map(([n, hs, s], i) =>
                    shelfRow(
                        n,
                        landed && i === SHELVES.length - 1 ? [...hs, 132] : hs,
                        s,
                    ),
                ).join("")}</div>`;
            }

            /** AppBar + _LibraryBar: one unbroken band of surface, 0..118. */
            function libraryChrome() {
                return `<div class="chrome"></div><div class="lbar"><span class="av"></span><span class="sp"></span><span class="ib">${ic("book", 19)}</span><span class="ib">${ic("photos", 19)}</span></div>`;
            }

            /** The library as the band above a modal, dimmed by its scrim.
             *
             *  Almost none of it shows: the sheet's top edge is at 62 and the
             *  chrome runs to 118, so what is actually visible above the sheet is
             *  the app bar's own status-bar band under the scrim. Drawn in full
             *  anyway, because it is what is behind. */
            function libBehind() {
                return `${libraryChrome()}${library(false)}<div class="scrim"></div>`;
            }

            /** FinishedBooksSheet, collapsed: a floating card resting on the pile. */
            function collapsedLibrarySheet(count) {
                return `<div class="lsheet"><div class="hdl"></div><div class="lhdr"><span class="lt">Books read<i>${count}</i></span><span class="filt">All time${ic("chevron", 12)}</span></div><div class="pile"><div class="spines">${Array.from(
                    { length: 11 },
                    (_, i) =>
                        `<s style="opacity:${[1, 0.7, 0.4][i % 3]}"></s>`,
                ).join("")}</div><div class="shelf"></div><div class="pad"></div></div></div>`;
            }

            /** ShellTabBar, floating in front. `lit` = the search orb selected. */
            function tabBar(lit) {
                return `<div class="tb"><div class="tp"><s class="${lit ? "" : "on"}"><b>${ic("book", 19)}</b>Library</s><s><b>&#9679;&#9679;</b>Friends</s><s><b>&#9646;</b>Card</s></div><div class="orb${lit ? " lit" : ""}">${ic("search", 24)}</div></div>`;
            }

            /** The search row: pill plus one or two 44pt buttons. */
            function srow(f, buttons) {
                const glass = `<span style="color:var(--text2);flex:0 0 auto">${ic("search", 16)}</span>`;
                // The clear button rides on the field having anything in it, and
                // comes *after* the provenance chip: it is the rightmost thing in
                // the pill in every state, chip or no chip.
                const clear = `<span class="clr">${ic("clear", 18)}</span>`;
                const field = f.value
                    ? `${glass}<span class="val">${f.value}</span>${f.prov ? `<span class="prov">${f.prov}</span>` : ""}${clear}`
                    : `${glass}${f.focused ? '<span class="caret"></span>' : ""}<span class="ph">${f.placeholder}</span>`;
                return `<div class="srow"><div class="pill">${field}</div>${(
                    buttons || []
                )
                    .map((b) => `<div class="ib">${ic(b)}</div>`)
                    .join("")}</div>`;
            }

            /** The iOS keyboard, drawn over the sheet because it does not resize it. */
            function keyboard() {
                const row = (n, cls) =>
                    `<div class="krow">${Array.from({ length: n }, () => `<s class="${cls || ""}"></s>`).join("")}</div>`;
                return `<div class="keyb"><div class="qt"><span>\uc18c\uc0b4</span><span>\uc18c\uc0b4\ub9c8\uc74c\ub4e4</span><span>\uc18c\uc0b4\uac00</span></div>${row(10)}${row(9)}${row(9)}<div class="krow"><s class="dark"></s><s class="wide"></s><s class="dark"></s></div></div>`;
            }

            function resultRows(rows) {
                return `<div class="res">${rows
                    .map(
                        (r, ri) =>
                            `<div class="rrow"><div class="rbooks">${r
                                .map(
                                    (h, i) =>
                                        `<u style="--c:${PAL[(i + ri * 3) % PAL.length]};height:${h}px"><i></i></u>`,
                                )
                                .join("")}</div><div class="shelf"></div></div>`,
                    )
                    .join("")}</div>`;
            }

            function emptyState(e) {
                return `<div class="empty"><div class="bk">${ic("book", 100)}</div><div class="hint">${e.hint}</div>${e.act ? `<div class="act">${ic("viewfinder", 18)}${e.act}</div>` : ""}</div>`;
            }

            /** showBookInfoBottomSheet, stacked over whatever opened it. */
            function infoSheet(b) {
                const cover = b.manual
                    ? `<div class="icover gcover"><div class="blk"></div><div class="ttl"></div></div>`
                    : `<div class="icover"><i></i></div>`;
                const meta = b.manual
                    ? `<div class="imeta"><div class="tfield">Title${"&nbsp;".repeat(
                          0,
                      )}<span class="caret"></span></div><div class="ip" style="font-family:ui-monospace,Menlo,monospace">ISBN 9788954699914</div></div>`
                    : `<div class="imeta"><div class="it">${b.title}</div><div class="ia">${b.authors}</div>${b.publisher ? `<div class="ip">${b.publisher}</div>` : ""}</div>`;
                return `<div class="isheet"><div class="irow">${cover}${meta}</div><div class="isel"><span class="l">Shelf</span><span class="v">${b.shelf}${ic("chevron", 13)}</span></div><div class="ichips">${[
                    "Interested",
                    "Reading",
                    "Finished",
                ]
                    .map(
                        (s) =>
                            `<s class="${s === b.status ? "on" : ""}">${s}</s>`,
                    )
                    .join("")}</div><div class="isave${b.manual ? " off" : ""}">Save</div>${b.manual ? '<div class="notreal"><b>This screen does not exist</b></div>' : ""}</div>`;
            }

            /* ---- the two frame families ---------------------------------- */

            function sheetScreen(s) {
                const k = s.sheet;
                let h = `<div class="fr">${libBehind()}<div class="sheet">`;
                h += `<div class="hdl"></div>`;
                h += `<div class="trow"><span class="t">${k.title}</span><div class="ib">${ic("close", 17)}</div></div>`;
                h += srow(k.field, k.buttons);
                if (k.measure) h += `<div class="measure">${k.measure}</div>`;
                h += `<div class="sbody">${
                    k.body.t === "empty"
                        ? emptyState(k.body)
                        : resultRows(k.body.rows)
                }</div>`;
                h += `</div>`;
                // A save sheet stacked on top is a second modal, so the bar goes.
                if (s.isheet) h += infoSheet(s.isheet);
                if (s.keyboard) h += keyboard();
                if (s.bar !== false && !s.isheet && !s.keyboard)
                    h += tabBar(s.orbLit !== false);
                h += `<div class="ind"></div></div>`;
                return h;
            }

            /** The shell itself: library, its collapsed sheet, and the tab bar. */
            function libraryScreen(s) {
                return `<div class="fr">${libraryChrome()}${library(s.landed)}${collapsedLibrarySheet(s.count)}${tabBar(false)}<div class="ind"></div></div>`;
            }

            function scannerBody(s, L) {
                let h = "";
                if (s.subject)
                    h += `<div class="subj ${s.subject}" style="top:${L.subj}px">${
                        s.subject === "back"
                            ? `<div class="blurb"><u></u><u></u><u></u><u></u></div>`
                            : `<div class="ct">\uc18c\uc0b4<br />\ub9c8\uc74c\ub4e4</div><div class="ca">\ud55c\uac15</div>`
                    }</div>`;
                if (s.subject === "back")
                    h += `<div class="eanwrap${s.candidates ? " cand" : ""}" style="top:${L.ean}px">${eanPair(s.candidates)}</div>`;
                if (s.retic)
                    h += `<div class="retic ${s.retic}" style="top:${L.retic}px"><i></i><i></i><i></i><i></i></div>`;
                if (s.isbn)
                    h += `<div class="isbn${s.isbnBusy ? " busy" : ""}" style="top:${L.read}px"><span>${s.isbn}</span></div>`;
                if (s.hint)
                    h += `<div class="shint" style="top:${L.read}px"><span>${s.hint}</span></div>`;
                if (s.nudge)
                    h += `<div class="nudge" style="top:${L.nudge}px"><span>${ic("camera", 19)}</span><span>${s.nudge}</span></div>`;
                if (s.shutter)
                    h += `<div class="coverbtn ${s.shutter}" style="top:${L.shut}px">${s.shutter === "busy" ? '<span class="spin"></span>' : ic("camera", 19)}<span>${s.shutterLabel ?? ""}</span></div>`;
                if (s.top)
                    h += `<div class="stop" style="top:${L.top}px">${s.top
                        .map(
                            (b) =>
                                b === "gap"
                                    ? '<span class="gapfill"></span>'
                                    : `<div class="ib">${ic(b)}</div>`,
                        )
                        .join("")}</div>`;
                if (s.card)
                    h += `<div class="card" style="top:${L.card}px"><div class="ct2">${s.card.title}</div><div class="cb">${s.card.body}</div><div class="cacts">${s.card.acts
                        .map(
                            (a) =>
                                `<div class="ca2 ${a.k}">${a.icon ? ic(a.icon, 17) + "&nbsp;" : ""}${a.label}</div>`,
                        )
                        .join("")}</div></div>`;
                return h;
            }

            function scanner(s) {
                const L = LAY[s.inSheet ? "sheet" : "page"];
                const cam = `cam${s.subject ? "" : " blank"}`;
                if (s.inSheet) {
                    // A second modal over Add Book, so no tab bar here either.
                    return `<div class="fr">${libBehind()}<div class="camsheet" style="height:${L.camH}px"><div class="${cam}" style="height:${L.camH}px">${scannerBody(s, L)}</div>${s.isheet ? infoSheet(s.isheet) : ""}</div><div class="ind"></div></div>`;
                }
                return `<div class="fr"><div class="${cam}" style="height:${L.camH}px">${scannerBody(s, L)}</div>${s.isheet ? infoSheet(s.isheet) : ""}<div class="ind${s.isheet ? "" : " dk"}"></div></div>`;
            }

            /** Draw one screen from its spec. */
            function frame(s) {
                if (s.kind === "scanner") return scanner(s);
                if (s.kind === "library") return libraryScreen(s);
                return sheetScreen(s);
            }

            /* ==================================================================
   SECTION 3: DATA — the base version: one scan button, a cover pill that is
   visible from the first frame, and a nudge that escalates rather than
   reveals.

   Specs are named consts shared between SCREENS and FLOWS, so a flow step
   cannot keep a stale drawing of a screen that was corrected.
   ================================================================== */

            const HINT = "Search by book title,\nauthor, or publisher \u263a\ufe0f";
            const PLACEHOLDER = "Title, author, publisher\u2026";

            /* 402 - 25 - 25 = 352pt of row. One button leaves 300 for the pill. */
            const MEASURE_ONE =
                "row 352pt \u2192 pill 300pt + gap 8 + button 44";

            const ROWS = [
                [131, 138, 124],
                [136, 122, 131],
                [128, 134, 120],
            ];

            const S = {};

            /* ---- the sheet ---- */
            S.sheetEmpty = {
                kind: "sheet",
                sheet: {
                    title: "Add book",
                    field: { placeholder: PLACEHOLDER },
                    buttons: ["viewfinder"],
                    measure: MEASURE_ONE,
                    body: { t: "empty", hint: HINT, act: "Scan a book" },
                },
            };
            S.sheetResults = {
                kind: "sheet",
                sheet: {
                    title: "Add book",
                    field: { value: "\ud55c\uac15" },
                    buttons: ["viewfinder"],
                    body: { t: "results", rows: ROWS },
                },
            };
            S.sheetPrefilled = {
                kind: "sheet",
                sheet: {
                    title: "Add book",
                    field: {
                        value: "\uc18c\uc0b4\ub9c8\uc74c\ub4e4 \ud55c\uac15",
                        prov: "from cover",
                    },
                    buttons: ["viewfinder"],
                    body: { t: "results", rows: [ROWS[0], ROWS[1]] },
                },
            };
            /* Field focused, keyboard up, nothing typed yet — which is what
               "Type it instead" has to land on. */
            S.sheetFocused = {
                kind: "sheet",
                keyboard: true,
                sheet: {
                    title: "Add book",
                    field: { placeholder: PLACEHOLDER, focused: true },
                    buttons: ["viewfinder"],
                    body: { t: "empty", hint: HINT, act: "Scan a book" },
                },
            };

            /* ---- the scanner ---- */
            const TOPBAR = ["close", "gap", "torch", "photos"];

            S.scanFirst = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "idle",
                hint: "Point at the barcode \u2014 or read the cover instead",
                shutter: "idle",
                shutterLabel: "Read the cover",
            };
            S.scanIdle = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "idle",
                shutter: "idle",
                shutterLabel: "Read the cover",
            };
            S.scanLock = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "lock",
                isbn: "978 89 546 9991 4",
                shutter: "idle",
                shutterLabel: "Read the cover",
            };
            /* The gap the implementation opened up. `getByIsbn` is a network
               call, so between the lock and the save sheet there is a wait the
               mockup originally had no screen for — and it is the one moment the
               user has nothing to do and no idea whether anything is happening. */
            S.scanLookup = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "lock",
                isbn: "978 89 546 9991 4",
                isbnBusy: true,
                shutter: "idle",
                shutterLabel: "Read the cover",
            };
            S.scanNudge = {
                kind: "scanner",
                subject: "front",
                top: TOPBAR,
                retic: "idle",
                nudge: "No barcode? <em>Read the cover</em> instead.",
                shutter: "idle",
                shutterLabel: "Read the cover",
            };
            S.scanBusy = {
                kind: "scanner",
                subject: "front",
                top: TOPBAR,
                shutter: "busy",
                shutterLabel: "Reading the cover\u2026",
            };
            S.scanMulti = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "lock",
                candidates: true,
                isbn: "2 symbols \u2014 took the 13-digit one",
                shutter: "idle",
                shutterLabel: "Read the cover",
            };

            /* ---- where it can go wrong ---- */
            S.scanDenied = {
                kind: "scanner",
                top: ["close", "gap"],
                card: {
                    title: "Camera access is off",
                    body: "Libstack needs the camera to scan a barcode. You can turn it on in Settings \u2014 or just type the title.",
                    acts: [
                        { k: "pri", label: "Open Settings", icon: "gear" },
                        { k: "sec", label: "Type it instead", icon: "type" },
                    ],
                },
            };
            S.scanNoCover = {
                kind: "scanner",
                subject: "front",
                top: TOPBAR,
                card: {
                    title: "Couldn't read that cover",
                    body: "Try filling the frame with just the front cover, in even light. Or look for the barcode on the back.",
                    acts: [
                        { k: "pri", label: "Retake", icon: "camera" },
                        { k: "sec", label: "Type it instead", icon: "type" },
                    ],
                },
                shutter: "idle",
                shutterLabel: "Read the cover",
            };
            S.scanNoIsbn = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                card: {
                    title: "No catalogue has this one",
                    body: "<code>9788954699914</code> scanned cleanly, but Kakao, Google Books and Open Library all came back empty.",
                    acts: [
                        { k: "pri", label: "Scan another", icon: "barcode" },
                        { k: "sec", label: "Type it instead", icon: "type" },
                    ],
                },
            };
            /* The cost of the cover path being the one feature that bills per tap.
               No retry action, deliberately: the limit *is* the message, and a
               button that re-failed would be a lie. */
            S.scanCoverLimit = {
                kind: "scanner",
                subject: "front",
                top: TOPBAR,
                card: {
                    title: "That's enough cover reads for now",
                    body: "Cover reading is limited to keep it free. Barcodes still work as often as you like, and you can always type the title.",
                    acts: [
                        { k: "pri", label: "Scan another", icon: "barcode" },
                        { k: "sec", label: "Type it instead", icon: "type" },
                    ],
                },
            };
            /* Not the same failure, and it took building it to see that. A
               provider that throws and a provider that misses both arrive as
               `null`, but they need opposite advice — one is fixed by typing the
               title, the other by trying the same scan again on better wifi. */
            S.scanLookupFailed = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                card: {
                    title: "Couldn't reach the catalogue",
                    body: "The barcode read fine, but the lookup didn't get through. Check your connection and try again.",
                    acts: [
                        { k: "pri", label: "Try again", icon: "barcode" },
                        { k: "sec", label: "Type it instead", icon: "type" },
                    ],
                },
            };

            /* ---- landing ---- */
            const BOOK = {
                title: "\uc18c\uc0b4\ub9c8\uc74c\ub4e4",
                authors: "\ud55c\uac15",
                publisher: "\ubb38\ud559\ub3d9\ub124",
                shelf: "\uc9c0\uae08 \uc77d\ub294 \uc911",
                status: "Reading",
            };
            S.infoBarcode = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "lock",
                isheet: BOOK,
            };
            /* The same save sheet, over the Add Book sheet rather than over the
               scanner — which is where the cover path actually reaches it. */
            S.infoCover = { ...S.sheetPrefilled, isheet: BOOK };
            /* What "Add it by hand" would have to reach. Marked, because it is
               not a thing the app can currently show. */
            S.infoManual = {
                kind: "scanner",
                subject: "back",
                top: TOPBAR,
                retic: "lock",
                isheet: { ...BOOK, manual: true, status: "Interested" },
            };
            S.libraryLanded = { kind: "library", count: 24, landed: true };

            const SCREENS = [
                [
                    "Add Book sheet",
                    [
                        [
                            "sheet-empty",
                            "Add Book &middot; empty",
                            "The entry point, twice over: a 44pt button in the search row that is always there, and a <b>Scan a book</b> action in the empty state, which is the best real estate in the sheet and today spends it on a 100pt icon and a hint. Two placements, one destination. The measuring line is an annotation, not chrome \u2014 it is there so the cost of a second button is a number: one button leaves the pill <b>300pt</b> of the row's 352.",
                            S.sheetEmpty,
                        ],
                        [
                            "sheet-results",
                            "Add Book &middot; results",
                            "The scan button survives a search rather than being an empty-state-only affordance: a user who typed, skimmed and gave up is exactly who wants it. Books are 131pt tall (15% of 874) and 82pt wide \u2014 the sheet divides by 1.6, not by <code>kDefaultCoverAspect</code>.",
                            S.sheetResults,
                        ],
                        [
                            "sheet-prefilled",
                            "Add Book &middot; query from a cover",
                            "Where the cover path lands. The LLM's guess is written into the field a human could have typed, so <code>_searchQueryProvider</code> takes it and the existing results grid does the confirming \u2014 the cover path needs no new search code at all. The <b>from cover</b> provenance chip is the one new part: without it a query the user did not type is indistinguishable from one they did, and a wrong guess looks like their own typo.",
                            S.sheetPrefilled,
                        ],
                        [
                            "sheet-focused",
                            "Add Book &middot; field focused",
                            "<b>Drawing this found a real bug, now fixed.</b> The keyboard <i>overlays</i> this sheet rather than resizing it — the height is fixed at <code>screen - topInset</code> — and only the results list compensated, via <code>bottom: 20 + viewInsetsOf(context).bottom</code>. The empty state got no such treatment: it is a <code>Center</code> in an <code>Expanded</code>, so it stayed centred on the <i>full</i> sheet and the keyboard covered its lower half. At ~336pt of keyboard the <b>Scan a book</b> action landed entirely behind it — and that action is what pays for having only one button in the row. It had cost nothing until now only because the empty state held no controls, and it was masked further by the Add Book field being the one text field in the app that does <b>not</b> <code>autofocus</code> (<code>update_shelf_name</code>, <code>write_memo</code> and the settings username all do), so the sheet opens with the action visible and this state is reachable only by tapping the field. Fixed with the same inset the list already had, and pinned by a test that asserts the button's bottom edge clears the keyboard.",
                            S.sheetFocused,
                        ],
                    ],
                ],
                [
                    "Scanner",
                    [
                        [
                            "scan-first",
                            "Scanner &middot; first run",
                            "One line teaches both halves, then never returns. Note what is <i>already</i> on screen: <b>Read the cover</b>. The cover path is not hidden behind the nudge, only <i>named</i> by it — which is the whole reason a second entry button in Add Book's search row buys so little, and why a user who already knows the barcode is unusable never waits out the 4s timer. <b>Labelled, not a shutter glyph:</b> the capture happens in the system camera, because <code>mobile_scanner</code> cannot take a still — so a shutter icon would promise an instant in-place capture it cannot deliver. <b>Arrives from the bottom.</b> Still this full-screen page — all 874pt of it, one modal over the shell — but presented as a <code>fullscreenDialog</code> <code>CupertinoPageRoute</code> rather than a trailing-edge push, the same presentation <code>View and share</code> uses. The screen already dismissed with an ✕ and never carried a back chevron, so the horizontal slide was promising a hierarchy it did not have; what it gives up is the back-edge swipe, which is a sheet-and-push affordance and not one a cover has. See the <code>scanner-sheet</code> version for the other reading of “from the bottom”, which costs the viewfinder real geometry.",
                            S.scanFirst,
                        ],
                        [
                            "scan-idle",
                            "Scanner &middot; idle",
                            "Returning user. Barcode detection is running on every frame at no cost; nothing has been tapped and nothing needs to be. The best case for this flow is zero interactions after the button that opened it.",
                            S.scanIdle,
                        ],
                        [
                            "scan-lock",
                            "Scanner &middot; barcode locked",
                            "Brackets go brand green <i>and</i> the window gains a hairline, so the state is not carried by colour alone. The decoded value is shown before the sheet arrives \u2014 a 13-digit number appearing is the cheapest possible proof that the thing you pointed at is the thing it read. It sits on a dark pill, which drawing it forced: <code>#09BC8A</code> over a pale back cover measures under 2:1, and a camera preview is not a surface whose colour you get to choose. Same for the hint and the cover pill.",
                            S.scanLock,
                        ],
                        [
                            "scan-lookup",
                            "Scanner &middot; looking the ISBN up",
                            "<b>Added while building it — the mockup had no screen for this and the flow needs one.</b> <code>getByIsbn</code> is a network call, so a wait sits between the lock and the save sheet, and it is the one moment the user has nothing to do and no way to tell whether anything is happening. The ISBN <i>stays</i> and gains a spinner rather than being swapped for <i>Looking it up…</i>: those thirteen digits are the only proof the book about to appear is the one they aimed at, and removing them at the exact moment the app goes quiet takes the evidence away just when they would check it. The words are given to screen readers instead, which cannot see a spinner. The preview stays live and the window stays locked underneath, because nothing has gone wrong.",
                            S.scanLookup,
                        ],
                        [
                            "scan-nudge",
                            "Scanner &middot; nudge",
                            "~4s with no hit, and the book in frame is cover-out. The banner escalates the cover pill rather than revealing it, and sits directly above it so the sentence and its target are one glance apart. This is the piece that removes the dead end from a barcode-first entry.",
                            S.scanNudge,
                        ],
                        [
                            "scan-busy",
                            "Scanner &middot; reading the cover",
                            "<b>Read the cover</b> tapped. The wait drawn here is one thing to the user and two underneath: the system camera is up while they frame and confirm the shot, then 1\u20133s of network while Gemini reads it. The reticle is gone because barcode detection has nothing to say about a still, and leaving it would imply the wait might still resolve as a barcode. The pill itself becomes the progress indicator, so the wait is anchored to the control that caused it.",
                            S.scanBusy,
                        ],
                        [
                            "scan-multi",
                            "Scanner &middot; two symbols in frame",
                            "Drawing this corrected the model. The <i>ordinary</i> two-barcode case is not two books on a table \u2014 it is the ISBN and the 5-digit \ubd80\uac00\uae30\ud638 add-on Korean books print beside it, both inside the window, which a reader configured for more than one format returns as two hits. So the candidates are marked on the symbols themselves (green kept, amber dropped) and the window stays <b>green</b>: the scan succeeded, and an amber window would call a resolved read a failure. Filtering to 13 digits beginning 978/979 settles almost every real case; nearest-to-centre is only needed for genuinely separate books. <b>Open:</b> whether the rare true tie deserves a chooser.",
                            S.scanMulti,
                        ],
                    ],
                ],
                [
                    "Where it can go wrong",
                    [
                        [
                            "scan-denied",
                            "Camera denied",
                            "The state nobody draws. <b>Fixed since this was drawn:</b> <code>ios/Runner/Info.plist</code> had <code>NSPhotoLibraryUsageDescription</code> (from <code>image_picker</code>) but <b>no <code>NSCameraUsageDescription</code></b>, and <code>AndroidManifest.xml</code> had no <code>CAMERA</code> permission — so this screen was what the whole feature would have shown. Both are now declared, the prompt is localised in <code>ios/Runner/{en,ko}.lproj/InfoPlist.strings</code> alongside the photo-library one, and Android also declares <code>uses-feature android.hardware.camera required=\"false\"</code> so a camera-less device can still install. Permission is requested <i>explicitly</i> rather than by first camera access, because this card has to tell \"refused just now\" from \"refused permanently\" to know whether Settings is the way out. Both actions lead somewhere; neither is <i>OK</i>. Copy says <b>Libstack</b>, which is <code>CFBundleDisplayName</code> — not the repo name.",
                            S.scanDenied,
                        ],
                        [
                            "scan-nocover",
                            "Cover unreadable",
                            "The LLM answered but not usefully. Advice is specific enough to act on (fill the frame, even light, try the back) rather than <i>try again</i>. The pill stays live underneath, and <i>Retake</i> is the primary action — the advice is about how the photo was taken, so the action that retakes it has to be the obvious one.",
                            S.scanNoCover,
                        ],
                        [
                            "scan-noisbn",
                            "ISBN with no catalogue match",
                            "A clean decode that no provider knows. <code>FallbackBookSearchProvider.getByIsbn</code> walks Kakao, Google Books and Open Library and returns <code>null</code> silently, and a barcode entry makes that reachable far more often than the details page does today. Common for Korean small-press. <b>Corrected after implementation:</b> the primary action was <i>Add it by hand</i>, which has been <b>dropped from v1</b> — see <code>info-manual</code> for the screen it would have needed. So the card now offers the two things that actually exist: scan a different book, or go and type the title. Nothing here is a dead end, which was the requirement the by-hand promise was trying to meet.",
                            S.scanNoIsbn,
                        ],
                        [
                            "scan-lookupfail",
                            "Lookup couldn't get through",
                            "<b>Added while building it.</b> The mockup had one failure for a lookup and the code proved there are two: <code>FallbackBookSearchProvider</code> swallows each provider's throw and returns <code>null</code> once they have all missed, so an offline phone and a book no catalogue carries are indistinguishable if you only check for null. They need opposite advice — this one is fixed by retrying the <i>same</i> scan, the other by typing the title — and telling someone with no signal that their book does not exist is the worse of the two lies. <i>Try again</i> re-runs the lookup on the ISBN already locked rather than making them re-frame a barcode that read perfectly: that would be blaming the user for the network.",
                            S.scanLookupFailed,
                        ],
                        [
                            "scan-coverlimit",
                            "Cover reads used up",
                            "<b>Added because building the backend created this state.</b> The cover read is the only thing in the app that costs money per tap, and the button sits on a screen the user is already pointing at things with — so it is metered (<code>cover_read_events</code>, 30/hour, 100/day, generous enough that cataloguing a shelf never hits it). <b>No primary retry, on purpose:</b> the limit is the whole message and a button that re-failed would be a lie. Both actions lead to routes that are still free — barcode scanning is live behind this card, and typing always works — which is also what makes the copy true rather than consoling.",
                            S.scanCoverLimit,
                        ],
                        [
                            "info-manual",
                            "Add by hand &middot; cut from v1",
                            "<b>Superseded — kept as the record of why the action was dropped.</b> What <i>Add it by hand</i> would have to reach, drawn so the size of the promise is visible. The scan gave us the ISBN and nothing else, so: no title, no author, no publisher, and the cover is <code>GeneratedCover</code> with its title half <b>empty</b> — a colour block from <code>generatedCoverColor(isbn)</code> over blank <code>surface</code>. Save is inactive because <code>addBook</code> needs a title. The one genuinely new component is a title input, which no bottom sheet in the app has — and that is the cost that got the action cut: a whole new input, a new validation path and a book that would sit in the library with no metadata, to serve the rarest branch of the flow. <code>scan-noisbn</code> now sends the user to the search field instead, which reaches the same place through code that already exists.",
                            S.infoManual,
                        ],
                    ],
                ],
                [
                    "Landing",
                    [
                        [
                            "info-barcode",
                            "Book info &middot; over the scanner",
                            "An ISBN is an identifier, not a guess, so the barcode path skips the results grid entirely and opens the save sheet on the single match \u2014 over the scanner it came from, which is still behind it. The tab bar is absent and that is not an omission: this is a second modal, and <code>shellBarVisibleProvider</code> drops the bar once one is stacked, because the unclipped native container that lets the orb overhang also lets its glass bleed through a Flutter sheet above it.",
                            S.infoBarcode,
                        ],
                        [
                            "info-cover",
                            "Book info &middot; over the results grid",
                            "The same save sheet, reached the other way. <b>Added because a flow step was drawing the wrong one:</b> <code>cover-read</code> step 04 reused <code>info-barcode</code>, so it showed the sheet over a dark viewfinder with a locked barcode \u2014 a backdrop the cover path never has. By then the scanner is closed and the user is on the Add Book sheet picking from the grid. Same sheet, same fields; only what is behind it differs, and behind it is the thing that says how you got here.",
                            S.infoCover,
                        ],
                        [
                            "library-landed",
                            "Back in the library",
                            "Where <code>popUntil</code> leaves you: the Add Book sheet is <i>gone</i>, not showing results. The search orb is unlit and the Library item is selected again \u2014 <code>onAddBook</code> is awaited, so the native bar keeps search lit only while the sheet is open. Drawn from <code>ShelfRow</code>: a 381.9pt row box (95% of the screen) 139pt tall (131 base, plus <code>BookJitter.maxHeightFactor</code> 1.06 reserved so a tall hash is not clipped), books bottom-aligned with 15pt gutters and a 15pt separator, the label resting on the plank, 26pt between rows. Below it <code>FinishedBooksSheet</code> at <code>initialDetent: collapsed</code> \u2014 a card pulled 14pt in from three edges, resting on the 169pt <code>ReadPile</code>, reserving 57pt for the bar. <b>Disagrees with <code>docs/mockups/typography</code></b> on two numbers, and deliberately: that set measured a screenshot and has the plank at 5pt with a 10pt gap between covers, where <code>ShelfWidget</code> is <code>height: 8</code> and the separator is <code>SizedBox(width: 15)</code> in source. Cover size and the 27pt first-book offset agree to within a point either way. Worth reconciling on device \u2014 one of the two records is wrong.",
                            S.libraryLanded,
                        ],
                    ],
                ],
            ];

            const FLOWS = [
                [
                    "Core",
                    [
                        [
                            "barcode-happy",
                            "Barcode \u2014 the path that should carry most books",
                            "Free, offline, exact, and it plugs into the <code>getByIsbn</code> that already exists. Four taps from library to saved, one of which is Save.",
                            [
                                [
                                    "Add Book",
                                    "Scan button in the row; Scan a book in the empty state. Same destination.",
                                    S.sheetEmpty,
                                ],
                                [
                                    "Scanner",
                                    "Detection already running. Cover pill already visible.",
                                    S.scanIdle,
                                ],
                                [
                                    "Locked",
                                    "No tap needed — the frame did it. ISBN shown as proof.",
                                    S.scanLock,
                                ],
                                [
                                    "Looking it up",
                                    "getByIsbn over the network. Proof stays on screen; spinner carries the wait.",
                                    S.scanLookup,
                                ],
                                [
                                    "Save sheet",
                                    "Straight past the results grid: an exact identifier earns that. The scanner is still behind it.",
                                    S.infoBarcode,
                                ],
                                [
                                    "Back in the library",
                                    "popUntil the shell, so the sheet is gone rather than showing results. The book lands where the user was.",
                                    S.libraryLanded,
                                ],
                            ],
                        ],
                        [
                            "fall-through",
                            "Barcode misses \u2014 escalation in place",
                            "The correction that makes a barcode-first entry safe: when no barcode is found, the flow does not fail and does not send the user back to pick a different door. It gets louder about the control that was on screen the whole time.",
                            [
                                [
                                    "Cover-out",
                                    "Pointed at the front. Nothing to decode; detection keeps trying, silently.",
                                    S.scanIdle,
                                ],
                                [
                                    "Nudge",
                                    "~4s. Escalates the pill; does not reveal it.",
                                    S.scanNudge,
                                ],
                                [
                                    "Reading",
                                    "Same screen, same session, no navigation.",
                                    S.scanBusy,
                                ],
                                [
                                    "Query filled",
                                    "Lands in the field a human could have typed, marked as not-theirs.",
                                    S.sheetPrefilled,
                                ],
                            ],
                        ],
                        [
                            "cover-read",
                            "Cover \u2014 the fallback, deliberately fuzzy",
                            "An LLM can misread stylised type and can invent an author, so this path ends at the results grid rather than at the save sheet. The asymmetry is the point: exact identifiers skip confirmation, guesses do not.",
                            [
                                [
                                    "Read the cover",
                                    "Tapped straight away by a user who knows the barcode is unusable — no 4s wait needed.",
                                    S.scanNudge,
                                ],
                                [
                                    "Reading",
                                    "OS camera, then 1\u20133s of network. The pill is the progress indicator.",
                                    S.scanBusy,
                                ],
                                [
                                    "Results",
                                    "Guess in the field, grid does the confirming. Editable, because it will sometimes be wrong.",
                                    S.sheetPrefilled,
                                ],
                                [
                                    "Save sheet",
                                    "Over the grid, not over a viewfinder: the scanner closed two steps ago.",
                                    S.infoCover,
                                ],
                            ],
                        ],
                    ],
                ],
                [
                    "Recovery",
                    [
                        [
                            "denied",
                            "Camera denied",
                            "Reachable on the very first tap today, since neither platform has the permission declared. Never a wall: Settings for the fix, typing for the impatient.",
                            [
                                [
                                    "Scan tapped",
                                    "OS prompt, or an immediate denial if it was refused before.",
                                    S.sheetEmpty,
                                ],
                                [
                                    "Denied",
                                    "Two ways onward. Neither of them is an OK button.",
                                    S.scanDenied,
                                ],
                                [
                                    "Typing instead",
                                    "Field focused, keyboard up, nothing typed. Note what the keyboard covers.",
                                    S.sheetFocused,
                                ],
                            ],
                        ],
                        [
                            "no-match",
                            "Scanned, but no catalogue has it",
                            "The failure a barcode entry makes common: a clean decode that Kakao, Google Books and Open Library all miss. The exit is the search field, not a by-hand form — see <code>info-manual</code> for what that would have cost.",
                            [
                                [
                                    "Locked",
                                    "Decode succeeded. Nothing wrong with the scan.",
                                    S.scanLock,
                                ],
                                [
                                    "Looking it up",
                                    "The same wait as the happy path. Failure is not visible yet.",
                                    S.scanLookup,
                                ],
                                [
                                    "Empty",
                                    "getByIsbn returned null from all three providers.",
                                    S.scanNoIsbn,
                                ],
                                [
                                    "Typing instead",
                                    "Field focused on return, because the user asked for it. Same field, existing search.",
                                    S.sheetFocused,
                                ],
                            ],
                        ],
                        [
                            "lookup-failed",
                            "Scanned, but the lookup never landed",
                            "Split out of <code>no-match</code> during implementation: both arrive as <code>null</code> and they are not the same failure. Retry re-runs the lookup on the ISBN already locked — the decode was never the problem.",
                            [
                                [
                                    "Looking it up",
                                    "Identical to the happy path up to here.",
                                    S.scanLookup,
                                ],
                                [
                                    "No route out",
                                    "Offline, or every provider threw. Not the book's fault, and the copy says so.",
                                    S.scanLookupFailed,
                                ],
                                [
                                    "Retried",
                                    "Back to the same lock, same ISBN. No re-framing asked of the user.",
                                    S.scanLookup,
                                ],
                            ],
                        ],
                    ],
                ],
            ];

            const ELEMENTS = [
                [
                    "The entry point",
                    [
                        [
                            "el-srow",
                            "Search row &middot; one button",
                            "<code>Padding.fromLTRB(25, 4, 25, 12)</code> leaves 352pt. One 44pt <code>AdaptiveIconButton</code> plus the 8pt gap leaves the pill <b>300pt</b>. Compare the <code>two-buttons</code> version for the other number.",
                            `<div class="strip"><div class="fr" style="width:402px;height:auto;border:0;background:none;position:static">${srow({ placeholder: PLACEHOLDER }, ["viewfinder"])}<div class="measure">${MEASURE_ONE}</div></div></div>`,
                        ],
                        [
                            "el-emptyact",
                            "Empty-state action",
                            "The discoverable half. A 44pt pill under <code>searchBookHint</code>, filled <code>surface</code> on the sheet's mint <code>sheetBackground</code> so it reads as raised without competing with a primary CTA. This is what pays for having only one button in the row: the capability is advertised where the user has nothing else to do, not by a second 44pt glyph in a toolbar. <b>Was drawn as an outlined pill, and that was corrected in code, not in the drawing:</b> <code>ElevatedActionButton</code> has no enabled-outlined variant — <code>disabledStyleOutline</code> styles a genuinely <i>disabled</i> button, and reaching for it to get an outline sets <code>onPressed</code> to null. The outline version of this shipped dead. <b>The drawing's <code>padding: 0 20px</code> was also missing in code, now fixed:</b> <code>ElevatedActionButton</code> pads by zero — right for every other one in the app, which are stretched by a <code>SizedBox</code>, an <code>Expanded</code>, or a width tuned to the label, and where padding would only eat the room the label has to fit in. This is the one that sizes itself <i>to</i> its label, so zero put the text flush against a 50pt radius: no gap at all on the right, and a fake one on the left that was really the icon's own bearing. The widget now takes a <code>padding</code>, and a test pins the 20.",
                            `<div class="fr" style="width:auto;height:auto;border:0;background:none;position:static"><div class="empty" style="position:static;padding:0;gap:12px"><div class="hint">${HINT}</div><div class="act">${ic("viewfinder", 18)}Scan a book</div></div></div>`,
                        ],
                        [
                            "el-prov",
                            "Provenance chip",
                            "Marks a query the app wrote. <code>pageBackground</code> fill with a <code>brand</code>@30% hairline, borrowed from <code>ComplimentBlock</code>'s chip so it reads as the same class of object. Without it, a bad LLM guess is indistinguishable from the user's own typo \u2014 and they will try to fix their typing instead of retaking the photo. Passed <i>through</i> <code>SearchTextField</code> rather than placed beside it in the pill, so the clear button stays the rightmost thing in the field.",
                            `<div class="strip"><div class="fr" style="width:402px;height:auto;border:0;background:none;position:static">${srow({ value: "\uc18c\uc0b4\ub9c8\uc74c\ub4e4 \ud55c\uac15", prov: "from cover" }, ["viewfinder"])}</div></div>`,
                        ],
                        [
                            "el-clear",
                            "Clear button",
                            "On the field, not on the sheet, so the friends header gets it too. A 36pt square holding an 18pt filled x-circle, <code>secondaryText</code>, drawn only once the field holds something — and always <i>after</i> anything else in the field, so it is the rightmost thing in the pill whether or not the provenance chip is there. Three things it is deliberately not: it is not 44pt, because the target is bounded by the 37pt field it sits inside and the 44pt rule belongs to the pill's free-standing neighbours; it does not touch focus, so clearing mid-typing keeps the keyboard and clearing a cover read does not raise one; and it does not stop at the text — it submits an empty query, because a grid still answering a query that is no longer on screen is worse than an empty state. Sized by an explicit <code>suffixIconConstraints</code>: Material's default pads the 36pt square out to a 48pt minimum width and parks it 12pt short of the trailing edge.",
                            `<div class="strip"><div class="fr" style="width:402px;height:auto;border:0;background:none;position:static">${srow({ value: "\ud55c\uac15" }, ["viewfinder"])}</div></div>`,
                        ],
                    ],
                ],
                [
                    "Scanner controls",
                    [
                        [
                            "el-retic",
                            "Scan window &middot; idle and locked",
                            "300 x 190, which holds an EAN-13 at reading distance <i>and</i> the 5-digit add-on Korean books print beside it. Locked adds green brackets <b>and</b> a hairline, so the state survives a colourblind reader. <b>Two states, not three:</b> an early draft had an amber multiple-barcodes window, and drawing it showed that to be wrong \u2014 two symbols is the ordinary case for a Korean book, the tie-break resolves it, and an amber window would report a success as a problem. The rejected candidate is marked on the symbol instead. See <code>scan-multi</code>.",
                            `<div class="demorow">${["idle", "lock"]
                                .map(
                                    (st) =>
                                        `<div class="fr" style="width:150px;height:95px;border:0;background:#23262b;position:relative;overflow:hidden"><div class="retic ${st}" style="left:8px;top:8px;width:134px;height:79px"><i></i><i></i><i></i><i></i></div></div>`,
                                )
                                .join("")}</div>`,
                        ],
                        [
                            "el-shutter",
                            "Cover pill &middot; idle and busy",
                            "48pt, comfortably past the 44pt minimum, full width inside 20pt margins and clear of the 34pt home-indicator strip. <b>On screen from the first frame</b> \u2014 that single fact is what makes a second entry button redundant, and it is the thing most easily lost in implementation. <b>Labelled rather than a 72pt shutter glyph, which is what this was:</b> <code>mobile_scanner</code> has no still capture, so the photo is taken in the system camera, and a shutter promises an instant in-place capture it cannot deliver. Busy covers the OS camera being up <i>and</i> the network call \u2014 one wait to the user.",
                            `<div class="demorow" style="justify-content:center;gap:34px">${["idle", "busy"]
                                .map(
                                    (st) =>
                                        `<div class="fr" style="width:362px;height:88px;border:0;background:#23262b;position:relative"><div class="coverbtn ${st}" style="top:20px">${st === "busy" ? '<span class="spin"></span>' : ic("camera", 19)}<span>${st === "busy" ? "Reading the cover\u2026" : "Read the cover"}</span></div></div>`,
                                )
                                .join("")}</div>`,
                        ],
                        [
                            "el-nudge",
                            "Nudge banner",
                            "Fires at ~4s of no hit. Escalation, not revelation \u2014 it points at a control already present. Sits directly above the cover pill so the sentence and its target are one glance apart, and uses the dark map's <code>brandText</code> (#09BC8A, 6.8:1 on dark) for the emphasis, which the light sheet above could not do.",
                            `<div class="strip dk"><div class="fr" style="width:402px;height:64px;border:0;background:none;position:relative"><div class="nudge" style="top:8px"><span>${ic("camera", 19)}</span><span>No barcode? <em>Read the cover</em> instead.</span></div></div></div>`,
                        ],
                    ],
                ],
                [
                    "Dead-end insurance",
                    [
                        [
                            "el-card",
                            "Recovery card",
                            "One shape for all four failures — denied, unreadable, unknown ISBN, unreachable catalogue. Rule: <b>two actions, never an OK.</b> The primary fixes the cause, the secondary reaches a book anyway. Drawn on <code>AppColors.dark.surface</code> because it sits on a camera preview. <b>The implementation trap:</b> the secondary reads as outlined, and spelling that as <code>activated: false, disabledStyleOutline: true</code> gives the right picture and a <i>dead button</i> — <code>ElevatedActionButton</code> passes <code>activated ? onPressed : null</code>. On the denied card that is the only way out, so the mistake turns a recoverable error into a wall. Use the app's real secondary pattern instead: stay activated, mute the fill, set the label colour explicitly. Pinned by a test.",
                            `<div class="fr" style="width:340px;height:auto;border:0;background:#23262b;position:relative;padding:14px 0"><div class="card" style="position:static;left:auto;right:auto;top:auto;margin:0 14px"><div class="ct2">No catalogue has this one</div><div class="cb"><code>9788954699914</code> scanned cleanly, but all three providers came back empty.</div><div class="cacts"><div class="ca2 pri">${ic("barcode", 17)}&nbsp;Scan another</div><div class="ca2 sec">${ic("type", 17)}&nbsp;Type it instead</div></div></div></div>`,
                        ],
                    ],
                ],
            ];

            /* Unresolved decisions, rendered as a red callout inside the flow. */
            const OPEN = {
                "cover-read":
                    "<b>Working, verified end to end.</b> <code>supabase/functions/read-book-cover</code> takes image bytes, asks <code>gemini-3.5-flash-lite</code> for a title and author under a <code>responseSchema</code>, and returns a <i>search query string</i> — never a book, because a guess has to be confirmed against the grid. Metered per user (<code>cover_read_events</code>, 30/hour, 100/day). <b>43/43 checks pass</b> against four real covers, three runs each: title, author, cross-run stability, and a per-cover distractor list (publisher, series band, prize band, <i>Foreword by</i>, <i>A Novel</i>). Hangul is transcribed as Hangul — <code>소년이 온다</code> / <code>한강</code>, not romanised, not translated, publisher <code>창버</code> ignored — which was the biggest risk and the reason the prompt forbids translating. A photo that is not a book comes back <code>unreadable</code> rather than invented.<br><br><b>Three things testing caught that reading the documentation did not.</b> (1) <b><code>temperature: 0</code> is not determinism</b> — one run in three glued the subtitle onto the title (<i>Clean Code: A Handbook of Agile Software Craftsmanship</i>), which a single-shot check reports as fine and which would have quietly cost search recall, since a longer query matches fewer books. The prompt and schema now name the subtitle rule, and every cover is read three times. (2) <b>The model list is not an availability check</b> — <code>gemini-2.5-flash</code> and <code>gemini-2.5-flash-lite</code> are returned by <code>ListModels</code> but 404 on a real call with “no longer available to new users”, so treating an older id as the conservative fallback is wrong. (3) The live API exposes <code>gemini-3.7-flash</code>, which the models, pricing and rate-limit pages all omit — <b>the docs lag the API</b>. There is no 3.6 or 3.7 Flash-<i>Lite</i>: Flash and Flash-Lite advance on separate cadences, so <code>gemini-3.5-flash-lite</code> is the current Lite despite reading as older.<br><br><b>Running on the Gemini free tier, which is a live privacy obligation.</b> On the free tier every model's terms read ‘Used to improve our products: <b>Yes</b>’, and the image is a photo the user just took in their home, of their shelf, with whatever else was in frame. Paid tier says No, and costs a $10 prepay minimum. Free tier is a legitimate choice for a side project, but it has to be stated plainly in the privacy policy before this reaches real users — a PIPA question in Korea, not only a policy one.",
                "no-match":
                    "<b>Settled — manual entry is cut from v1.</b> <code>libraryActionsProvider.addBook</code> needs a title, no bottom sheet in the app has a title input, and a book added that way would sit in the library with no metadata and a blank generated cover (<code>info-manual</code> draws it). Too much new surface for the rarest branch of the flow, so the card sends the user to the search field instead — which reaches the same place through code that already exists, and keeps the no-dead-ends rule the by-hand action was there to satisfy.",
                "fall-through":
                    "<b>Open — the rare true tie.</b> Two <i>separate</i> books in frame is the only case a 978/979 + 13-digit filter cannot settle (see <code>scan-multi</code>); nearest-to-centre is one line, a chooser is a whole screen. Implemented as nearest-to-centre, with unmeasured candidates sorted last so a missing corner list cannot win by accident. Also still unsettled: whether the ~4s nudge timer should reset when the camera moves — shipped as fire-once, on the reasoning that a timer restarting on every wobble would never fire for the person who needs it most. <b>In v1 the nudge points at typing, not the shutter</b>, because the cover read is deferred; the shutter in these frames is the design, not what ships today.",
            };

            /* The three screens that carry the search row, in the two-buttons
               shape. Named so the version patch and the save sheet that stacks
               over one of them cannot disagree about how many buttons the row
               behind it has. */
            const TB = {
                empty: {
                    kind: "sheet",
                    sheet: {
                        title: "Add book",
                        field: { placeholder: PLACEHOLDER },
                        buttons: ["barcode", "camera"],
                        measure:
                            "row 352pt \u2192 pill 248pt + gap 8 + 44 + gap 8 + 44",
                        body: { t: "empty", hint: HINT, act: "Scan a book" },
                    },
                },
                results: {
                    kind: "sheet",
                    sheet: {
                        title: "Add book",
                        field: { value: "\ud55c\uac15" },
                        buttons: ["barcode", "camera"],
                        body: { t: "results", rows: ROWS },
                    },
                },
                prefilled: {
                    kind: "sheet",
                    sheet: {
                        title: "Add book",
                        field: {
                            value: "\uc18c\uc0b4\ub9c8\uc74c\ub4e4 \ud55c\uac15",
                            prov: "from cover",
                        },
                        buttons: ["barcode", "camera"],
                        body: { t: "results", rows: [ROWS[0], ROWS[1]] },
                    },
                },
            };

            /* ==================================================================
   SECTION 4: VERSIONS

   `main` is the recommendation. The other two are the live alternatives,
   each drawn so its cost is visible rather than argued.
   ================================================================== */
            const VERSIONS = [
                [
                    "main",
                    "main",
                    "One scan button; barcode passive and free; a labelled cover pill visible from the first frame; a nudge at ~4s that escalates it.",
                    null,
                    {},
                ],

                [
                    "two-buttons",
                    "two-buttons",
                    "Proposal: a barcode icon AND a camera icon at the right end of the search row, with the barcode route still falling through to the cover read.",
                    "main",
                    {
                        screens: {
                            "sheet-empty": {
                                note: "Two 44pt targets take the pill from <b>300pt to 248pt</b>, a 17% loss (256 on the Material fallback, where <code>AdaptiveIconButtonGap</code> collapses to 0). Drawn at 1:1 so the reviewer can judge whether that matters \u2014 and it is a fair test: the placeholder still fits at both widths, so the cost is in visible typed text, not a clipped hint. The two glyphs are the softer problem: at 44pt a barcode and a camera are both a small dark rectangle with detail inside.",
                                spec: TB.empty,
                            },
                            "sheet-results": { spec: TB.results },
                            "sheet-prefilled": {
                                note: "The provenance chip and the second button now compete for the same end of a 248pt pill. Whichever wins, the other is what gets truncated.",
                                spec: TB.prefilled,
                            },
                            "info-cover": {
                                note: "Patched only so the row <i>behind</i> the save sheet matches the rest of this version. Nothing about the sheet itself changes \u2014 which is the point: the fork is invisible by the time it matters.",
                                spec: { ...TB.prefilled, isheet: BOOK },
                            },
                            "scan-first": {
                                name: "Scanner &middot; opened by the camera button",
                                note: "Here is the fork's problem, drawn. If the camera door also detects barcodes passively \u2014 and why would it not \u2014 this screen is <b>byte-identical</b> to the one the barcode door opens, and the two buttons differ only in a hint string. If it does <i>not</i>, the door is strictly worse: slower, less accurate, and it costs money on a book whose barcode was right there.",
                                spec: S.scanFirst,
                            },
                        },
                        elements: {
                            "el-srow": {
                                name: "Search row &middot; two buttons",
                                note: "352pt of row, less 44 + 8 + 44 + 8, leaves <b>248pt</b> of pill against <code>main</code>'s 300. The row is drawn at the glass gap of 8; on the Material fallback the inter-button gap is 0 and the pill gets 256.",
                                demo: `<div class="strip"><div class="fr" style="width:402px;height:auto;border:0;background:none;position:static">${srow({ placeholder: PLACEHOLDER }, ["barcode", "camera"])}<div class="measure">row 352pt \u2192 pill 248pt + gap 8 + 44 + gap 8 + 44</div></div></div>`,
                            },
                        },
                        open: {
                            "fall-through":
                                "<b>The fall-through is why this version argues against itself.</b> It is kept here, unchanged, because it is correct in any version. But once the barcode door escalates to the cover read on its own, the camera door is answering a question the flow already answers better \u2014 see <code>scan-first</code> in this version, which is the same screen the barcode button opens.",
                        },
                    },
                ],

                [
                    "scanner-sheet",
                    "scanner-sheet",
                    "Alternative: the scanner is a stacked bottom sheet over Add Book instead of a pushed full-screen route.",
                    "main",
                    {
                        screens: {
                            "scan-first": {
                                note: "Consistent with every other secondary surface in the app, and it keeps the library visible. But the preview drops from 874 to 717pt and the framing room above the scan window collapses from <b>250pt to 150pt</b> \u2014 the book gets clipped by the sheet's own top edge, which is the one thing a viewfinder must not do.",
                                spec: { ...S.scanFirst, inSheet: true },
                            },
                            "scan-lock": { spec: { ...S.scanLock, inSheet: true } },
                            "scan-nudge": {
                                note: "The nudge and the shutter now sit in the lower third of a shortened box, 148pt closer to the scan window. Less room to be wrong in, and the banner starts to crowd the thing it points at.",
                                spec: { ...S.scanNudge, inSheet: true },
                            },
                            "info-barcode": {
                                note: "The cost that decides it: a save sheet over a scanner sheet is <b>three modals deep</b> over the shell. The scanner is already the second, which is what drops the tab bar; stacking the save sheet on top of a sheet-hosted camera means a platform view under two Flutter sheets \u2014 exactly the z-order bleed <code>autoHideOnModal</code> exists to work around.",
                                spec: { ...S.infoBarcode, inSheet: true },
                            },
                        },
                        open: {
                            "barcode-happy":
                                "<b>Settled — route type.</b> A pushed page hides the tab bar for free (<code>shellBarVisibleProvider</code> compares against the topmost <i>page</i> route). A sheet hides it too, via the stacked-modal counter, so either would have worked for the tab bar — but only the sheet path puts a live camera platform view under two Flutter sheets. <b>The answer was to take the direction and leave the sheet:</b> the scanner is a <code>fullscreenDialog</code> <code>CupertinoPageRoute</code>, so it rises from the bottom like the camera in every app that has one, while staying a single opaque page route with all 874pt of preview. This version's three costs — the clipped viewfinder, the crowded nudge, and the third modal — are all paid by the <i>sheet</i>, not by the direction.",
                        },
                    },
                ],
            ];
