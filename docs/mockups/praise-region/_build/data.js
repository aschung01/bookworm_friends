   SECTION 2: FRAME RENDERER — the book-details hero, drawn once.

   Every screen on this page is the same hero with a different praise
   treatment, so the treatment is the only thing declared per screen. The
   chrome around it (cover, corner, shelf, band, tabs) is defined here
   once, which is what stops a corrected detail from surviving in half the
   drawings.
   ================================================================== */
            /* People. `a` is the avatar mode, and there are exactly the two
               AvatarCircle has: 'photo' (avatar_path set) and 'emoji'
               (avatar_path null, profile emoji). 'unknown' is a third thing —
               not a mode but an absence: a profile the profiles RLS policy will
               not let this viewer read at all.

               Photos are drawn as a tinted disc with the initial. The page
               embeds no images by design, and a crude stand-in is safer than a
               convincing one nobody can check. */
            const ME = { n: "아름", a: "photo", c: "#2f6f63", me: true };
            const P = {
                jihyun: { n: "지현", a: "photo", c: "#7c5cd6" },
                minsu: { n: "민수", a: "emoji", g: "🐳" },
                seoyeon: { n: "서연", a: "emoji", g: "📚" },
                haneul: { n: "하늘", a: "photo", c: "#d4685a" },
                taeho: { n: "태호", a: "emoji", g: "🍊" },
                unseen: { n: null, a: "unknown" },
            };
            const pr = (who, e) => ({ who, e });

            /* Icons.person_rounded at 0.6 diameter in secondaryText: what
               AvatarCircle._PhotoPending draws for a photo that has not
               arrived. Reused for an unreadable profile, deliberately — both
               mean "a person, no picture", and inventing a second glyph would
               make them look like different kinds of problem. */
            function personGlyph(d) {
                const s = Math.round(d * 0.6);
                return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="#adb5bd"><circle cx="12" cy="8" r="4.2"/><path d="M12 13.6c-4.3 0-7.4 2.6-7.4 5.6 0 .5.4.8.9.8h13c.5 0 .9-.3.9-.8 0-3-3.1-5.6-7.4-5.6z"/></svg>`;
            }

            function avatar(p, d) {
                const box = `width:${d}px;height:${d}px`;
                if (p.a === "photo")
                    return `<span class="av photo" style="${box};background:${p.c};font-size:${Math.round(d * 0.44)}px">${p.n.slice(0, 1)}</span>`;
                if (p.a === "unknown")
                    return `<span class="av" style="${box}">${personGlyph(d)}</span>`;
                return `<span class="av" style="${box};font-size:${d / 2}px">${p.g}</span>`;
            }

            const mineOf = (s) =>
                (s.praises.find((x) => x.who.me) || {}).e || null;
            const othersOf = (s) => s.praises.filter((x) => !x.who.me);
            /* Yours first. The provider orders by created_at desc, so this is a
               display decision, not the data's — it puts your face directly
               under the pill that changes it. */
            const ordered = (s) =>
                s.praises.filter((x) => x.who.me).concat(othersOf(s));

            /* _ComplimentButton is behind `if (!isSelf)` and returns an empty
               box unless status == 2. Both conditions, in one place, because
               three treatments below need to ask. */
            const pillShown = (s) => !s.isSelf && s.status === 2;

            /* Three statuses, not two. The first draft of this function had only
               a Read/Reading ternary, so the Interested screen drew a Reading
               badge — wrong, and invisible in the grid because nobody had a
               reason to look twice at a grey chip.

               `badgefix` repairs status 0 only. Reading is left exactly as it
               ships despite measuring 4.14:1 against its own tint, which is a
               knowing near-miss rather than an oversight: brandText really is
               4.74:1 on surfaceVariant — the figure app_theme.dart documents and
               color_contrast_test.dart asserts — and it is the badge's own 10%
               tint that darkens the background under it. Fixing it means giving
               up either the green text or the green fill, and green-means-reading
               is load-bearing across the app. Recorded, not silently absorbed. */
            function statusBadge(s) {
                const [cls, label] =
                    s.status === 2
                        ? ["read", "Read"]
                        : s.status === 1
                          ? ["reading", "Reading"]
                          : [
                                "interested" + (s.badgefix ? " fixed" : ""),
                                "Interested",
                            ];
                return `<span class="sbadge ${cls}">${label}</span>`;
            }

            function pill(s) {
                if (!pillShown(s)) return "";
                const mine = mineOf(s);
                const add = `<span class="pill"><span class="em">🎉</span>${s.verb}</span>`;
                if (!mine) return add;
                /* Hidden outright once you hold a reaction. You can only hold
                   one, so a button labelled React would be promising to add
                   something it cannot add — what it actually does is replace or
                   withdraw, and both of those belong to the reaction you already
                   have rather than to a fresh action. The tinted capsule owns
                   them.

                   An intermediate draft kept the button filled and unchanged and
                   let the tint alone carry the state. It read fine, but it left a
                   large green button in the corner whose label described
                   something you could not do. */
                if (s.tintMine) return "";
                /* chips and owned carry your emoji on the button face. The rest
                   cannot: the record below already shows it, and showing it
                   twice is the whole reason this page exists. */
                return s.record === "chips" || s.record === "owned"
                    ? `<span class="pill"><span class="em">${mine}</span>${s.verb}</span>`
                    : `<span class="pill out">${s.verb}ed</span>`;
            }

            function chips(list) {
                if (!list.length) return "";
                return `<div class="chips">${list
                    .map((x) => `<span class="chip">${x.e}</span>`)
                    .join("")}</div>`;
            }

            function gifts(list) {
                if (!list.length) return "";
                return `<div class="gifts">${list
                    .map(
                        (x) =>
                            `<span class="gift">${avatar(x.who, 24)}<span class="bdg">${x.e}</span></span>`,
                    )
                    .join("")}</div>`;
            }

            /* The capped record. Two emoji is not arbitrary: no book in
               production holds more than two, so the collapsed form is the
               complete form for every real book today and +N is the escape hatch
               rather than the normal case.

               Yours is pinned first. It has to be: if it fell behind +N you
               could hold a reaction with nothing on screen showing it, and the
               pill's state label would be the only clue. */
            function capsule(s, opts) {
                const list = ordered(s);
                if (!list.length) return "";
                const shown = list.slice(0, 2);
                const rest = list.length - shown.length;
                const yours = s.tintMine && mineOf(s) ? " mine" : "";
                /* The chevron is not decoration in tintMine. Once the button is
                   hidden, this capsule is the only route to changing or
                   withdrawing your reaction — and on a book at any status other
                   than Read, the only interactive thing in the hero at all. It
                   was an open question while the button was still there as a
                   second route. It is not one now. */
                const chev =
                    s.tintMine || (opts || {}).chevron
                        ? `<span class="chev">&#8250;</span>`
                        : "";
                return (
                    `<div class="caprow"><span class="cap${yours}">` +
                    shown.map((x) => `<span class="e">${x.e}</span>`).join("") +
                    (rest ? `<span class="n">+${rest}</span>` : "") +
                    chev +
                    `</span></div>`
                );
            }

            function rightColumn(s) {
                /* With the badge in the status card there is nothing to hoist
                   here on your own book, which also retires the oddity of the
                   badge living in two different places depending on isSelf. */
                const head =
                    s.isSelf && s.badge === "corner" ? statusBadge(s) : "";
                switch (s.record) {
                    case "chips":
                        return head + pill(s) + chips(ordered(s));
                    case "owned":
                        /* Your praise leaves the strip only when the pill is
                           actually on screen to carry it. Keyed to pillShown,
                           not to `mine != null` — the `stranded` screen is what
                           the unconditional version does. */
                        return (
                            head +
                            pill(s) +
                            chips(pillShown(s) ? othersOf(s) : ordered(s))
                        );
                    case "gift":
                        return head + pill(s) + gifts(ordered(s));
                    case "capsule":
                        return head + pill(s) + capsule(s);
                    case "named":
                        return head + pill(s);
                }
                return "";
            }

            function bandPraise(s) {
                if (s.record !== "named" || !s.praises.length) return "";
                const one = (x) =>
                    `<span class="p${x.who.me ? " mine" : ""}"><em>${x.e}</em>${
                        x.who.me ? "You" : x.who.n || "Someone you can't see"
                    }</span>`;
                return `<div class="named"><span class="lbl">Praise</span>${ordered(
                    s,
                )
                    .map(one)
                    .join("")}</div>`;
            }

            /* The reading-period card, which becomes the status card when the
               badge moves into it. It only renders at status >= 1 with a start
               date, so a status-0 book has no card to put the badge in.

               First answer was to render the card anyway with the badge alone.
               Drawn at 1:1 that is a full-width white slab containing one small
               chip — worse than the corner it replaced. So at status 0 the badge
               sits in the band *without* a card. The rule that matters is "status
               lives in the band, under the author", and that holds either way;
               the card is for dates, and when there are none there is no card. */
            function statusCard(s) {
                const inCard = s.badge === "card";
                const dated = s.status >= 1;
                if (!inCard && !dated) return "";
                if (inCard && !dated)
                    return `<div class="barebadge">${statusBadge(s)}</div>`;
                const dates = `<span>2023.09.04 ~ ${
                    s.status === 2 ? "2023.09.05" : ""
                }</span><i>${s.status === 2 ? "1 day" : "12 days"}</i>`;
                return `<div class="period${inCard ? " withbadge" : ""}">${
                    inCard ? statusBadge(s) : ""
                }<b>Reading period</b>${dates}</div>`;
            }

            /* The praise sheet. Title and hint are the real strings
               (selectComplimentEmoji, emojiSearchHint); the column count and
               category chrome belong to awesome_emoji_picker, so this grid is
               approximate and says so in its element note. */
            const SHEET_EMOJI = [
                "👏", "🎉", "❤️", "🔥", "⭐", "💪", "😍", "🥰",
                "👍", "✨", "🎊", "💯", "🙌", "😎", "🤩", "💐",
                "💥", "😆", "🦄", "💗", "🤑", "😉", "📚", "🍀",
            ];
            function pickerSheet(s) {
                const sel = s.sheet.selected;
                /* Not `verb.toLowerCase()`: that rendered "Choose a react emoji"
                   on every React version. The picker's title takes the noun, and
                   the noun is not the button's verb — which is exactly the seam
                   where the shipped English was found still saying "praise"
                   under a button saying "React". */
                return (
                    `<div class="sheet"><div class="st">Choose a ${
                        s.verb === "React" ? "reaction" : "praise"
                    } emoji</div>` +
                    `<div class="sf">Search</div>` +
                    `<div class="egrid2">${SHEET_EMOJI.map(
                        (e) =>
                            `<s class="${e === sel ? "mine" : ""}">${e}</s>`,
                    ).join("")}</div></div>`
                );
            }

            /* Who reacted, and with what. The thing the capped capsule buys, and
               the reason capping costs nothing: detail moves somewhere it has
               room instead of being crammed into a 217pt column.

               It also gives withdrawal its first real home. Your row opens the
               picker, and because the capsule is visible whether or not the
               button is, this route survives a book going back to Reading — the
               one state where the shipped build strands your reaction.

               A line of help text under the list was drawn here and cut in the
               build: it captioned a single row that already carries You and a
               chevron, which is the disclosure every other drill-in row in the
               app uses unexplained. The chevron is the whole affordance. */
            function whoSheet(s) {
                const rows = ordered(s)
                    .map(
                        (x) =>
                            `<div class="r">${avatar(x.who, 40)}<span class="nm">${
                                x.who.me
                                    ? `${x.who.n} <i>You</i>`
                                    : x.who.n || "Someone you don't follow"
                            }</span><span class="em">${x.e}</span>${
                                x.who.me ? `<span class="chev">&#8250;</span>` : ""
                            }</div>`,
                    )
                    .join("");
                return (
                    `<div class="sheet rsheet"><div class="st">${
                        s.verb === "React" ? "Reactions" : "Praise"
                    }</div>${rows}` +
                    `</div>`
                );
            }

            function sheet(s) {
                return s.sheet.kind === "who" ? whoSheet(s) : pickerSheet(s);
            }

            /** Draw one screen from its spec. */
            function frame(s) {
                let h = `<div class="fr">`;
                h += `<div class="nav"><span class="back">&#8249;</span></div>`;
                h += `<div class="hero"><div class="hrow">`;
                h += `<div class="cover"><div class="k1">라이브<br/>커머스</div><div class="k2"></div><div class="k3"></div><span class="bind"></span><span class="hair"></span></div>`;
                h += `<div class="rcol">${rightColumn(s)}</div></div>`;
                /* The badge is in the corner only when this direction leaves it
                   there. Missing this condition drew it twice in stack-status,
                   once here and once in the status card, and only the assertion
                   noticed — in the grid it looked like a deliberate repeat. */
                h += `<div class="corner">${
                    !s.isSelf && s.badge === "corner" ? statusBadge(s) : ""
                }<span class="slab">${s.shelf}</span></div>`;
                h += `</div><div class="shelf"></div>`;
                h += `<div class="band"><div class="btitle">라이부 코머스 성공 전략</div><div class="bauth">이현숙</div>`;
                h += statusCard(s);
                h += bandPraise(s) + `</div>`;
                h += `<div class="tabs"><s class="on">Book info</s><s>Notes</s></div><div class="tail"></div>`;
                if (s.sheet) h += `<div class="scrim"></div>${sheet(s)}`;
                return h + `</div>`;
            }

            /* ==================================================================
   SECTION 3: DATA — the base version, which is the shipped build.

   One case table drives everything. A case is a *situation* (who is
   looking, what praise exists, what status the book is in) and is
   independent of the four praise treatments; the treatment comes from the
   version. So each direction is one line of configuration rather than a
   restated set of screens, and adding a case adds it to all four at once.
   ================================================================== */
            /* The two axes a direction can move on, plus the verb it uses.
               Kept as a table rather than baked into the renderer so a version
               is one line of configuration and the badge's placement can be
               varied independently of the record's treatment. */
            const STYLE = {
                main: { record: "chips", badge: "corner", verb: "Praise" },
                owned: { record: "owned", badge: "corner", verb: "Praise" },
                named: { record: "named", badge: "corner", verb: "Praise" },
                gift: { record: "gift", badge: "corner", verb: "Praise" },
                stack: { record: "capsule", badge: "corner", verb: "React" },
                "stack-status": {
                    record: "capsule",
                    badge: "card",
                    verb: "React",
                    badgefix: true,
                },
                "stack-tint": {
                    record: "capsule",
                    badge: "card",
                    verb: "React",
                    badgefix: true,
                    tintMine: true,
                },
            };
            const hero = (cfg, style) =>
                Object.assign(
                    {
                        style,
                        shelf: "쇼호스트",
                        status: 2,
                        isSelf: false,
                        praises: [],
                    },
                    STYLE[style],
                    cfg,
                );

            /* [id, group, name, note-for-main, config] */
            const CASES = [
                [
                    "none",
                    "A friend's finished book",
                    "No reaction yet",
                    "The baseline, and the one state no direction changes: nothing is duplicated when there is nothing to duplicate. Note how much of the 217pt column is empty here — the crowding only arrives with content.",
                    { praises: [] },
                ],
                [
                    "mine",
                    "A friend's finished book",
                    "One reaction &middot; yours",
                    "The reported state, at real scale. 💥 twice, 40pt apart, in two shapes that mean different things: the pill face is <b>your</b> praise (the only thing telling you the sheet will withdraw rather than add) and the chip is <b>the book's</b>. 31 of the 35 praised books in production hold exactly one praise, so this is the ordinary case, not an edge one.",
                    { praises: [pr(ME, "💥")] },
                ],
                [
                    "mine-plus",
                    "A friend's finished book",
                    "Two praises &middot; one yours",
                    "Two identical chips, nothing marking which is yours, so the pill's emoji is the only key. All four two-praise books in production have two different emoji, so at least the chips never collide — but the reader still has to match one against the button.",
                    { praises: [pr(ME, "🥰"), pr(P.jihyun, "😆")] },
                ],
                [
                    "theirs",
                    "A friend's finished book",
                    "Two praises &middot; none yours",
                    "Where the shipped design is at its best: no pill emoji, so nothing is duplicated, and two anonymous chips cost nothing when neither of them is yours to find. Any change has to not break this state.",
                    { praises: [pr(P.jihyun, "😆"), pr(P.minsu, "🔥")] },
                ],
                [
                    "crowd",
                    "A friend's finished book",
                    "Five praises &middot; one yours",
                    "A stress test, not a real state — no book in production has more than two. Five chips still fit one row (5&times;28 + 4&times;4 = 156 of 217pt), so nothing collides with the corner: overlap needs about three rows, and the shelf only drops away from the book if this column passes the cover's 180pt, which takes roughly a dozen praises. The problem at this volume is noise, not collision.",
                    {
                        praises: [
                            pr(ME, "💥"),
                            pr(P.jihyun, "😆"),
                            pr(P.minsu, "🔥"),
                            pr(P.seoyeon, "💗"),
                            pr(P.haneul, "🦄"),
                        ],
                    },
                ],
                [
                    "unseen",
                    "A friend's finished book",
                    "A reaction you can't attribute",
                    "The praiser is private and you don't follow them, so the profiles policy hides the row: <code>is_private = false OR id = auth.uid() OR id IN (who you follow)</code>. The shipped design handles this for free, because an anonymous chip needs no profile. This is the one thing it does better than every attributed alternative below. Currently hypothetical — 0 of the 8 praisers are private — but 15 of 136 profiles are.",
                    { praises: [pr(P.unseen, "👏")] },
                ],
                [
                    "interested-friend",
                    "Before it is finished",
                    "A friend's book &middot; Interested",
                    "Status 0, and the second most common status in the library — 133 of 472 books. No button, because you cannot react to a book nobody has finished; no reactions; and no reading-period card, since <code>ReadingPeriodRow</code> renders nothing below status 1. So the whole hero is a cover, a badge, a shelf label and two lines of text, and the right column is entirely empty. <b>Look at the badge.</b> Status 0 draws it in <code>secondaryText</code> at 10% fill and 40% border, which measures 1.66:1 against its own fill with a 1.23:1 border — the one thing on screen naming the state is the one thing you cannot read. Not caused by anything on this page, and not covered by <code>color_contrast_test.dart</code>, which only guards the brand tokens.",
                    { status: 0, praises: [] },
                ],
                [
                    "interested-reacted",
                    "Before it is finished",
                    "Interested, and still carrying your reaction",
                    "The extreme form of <code>stranded</code>: a book you reacted to when it was finished, moved all the way back to <i>Interested</i>. Your reaction survives, the button is gone, and in main there is no route to it at all. The capsule directions reach it anyway, because the record is not part of the button. Rare, but reachable in two taps by the owner.",
                    { status: 0, praises: [pr(ME, "🍀")] },
                ],
                [
                    "stranded",
                    "Before it is finished",
                    "Your reaction, book back to Reading",
                    "The owner moved the book back to Reading. <code>_ComplimentButton</code> returns an empty box unless <code>status == 2</code>, so your reaction is stranded: on screen, with no route to the sheet that would withdraw it. Present in the shipped build, and not caused by anything on this page — but every direction here has to answer for it.",
                    { status: 1, praises: [pr(ME, "👏")] },
                ],
                [
                    "owner",
                    "Your own book",
                    "Your own book &middot; two reactions",
                    "No button: you can't react to yourself. The record is therefore the owner's only sight of the reactions they were given, which is why it isn't behind the same <code>!isSelf</code> guard as the button — it used to be, and the person reacted to never saw it anywhere in the app. The status badge moves up into this column because the corner belongs to the button that isn't here.",
                    {
                        isSelf: true,
                        praises: [pr(P.jihyun, "😆"), pr(P.taeho, "💯")],
                    },
                ],
                [
                    "interested",
                    "Your own book",
                    "Your own book &middot; Interested",
                    "The emptiest state the hero has: no dates, no reactions, no button, and on your own book the badge is hoisted to the top of the right column instead of sitting in the corner. Drawn because it is the case that decides where the badge can live — a direction that moves it into the reading-period card has to say what happens when there is no card.",
                    { isSelf: true, status: 0, praises: [] },
                ],
            ];

            /* Screens that only exist once the record is capped: a capsule can
               be tapped, so there is a sheet behind it to draw. Added per
               version rather than defined here, since main has nothing to put
               in them. */
            const CAPSULE_ONLY = [
                [
                    "who",
                    "The sheet behind the capsule",
                    "Who reacted &middot; three, one yours",
                    "What the cap buys. Detail moves somewhere it has room instead of being crammed into a 217pt column, and every reaction gets the one thing an emoji alone cannot carry: whose it is. Your row leads, is the only one that drills in, and says so with <i>You</i> and a chevron. Dismissing the picker it opens comes back here rather than to the book — the sheet is the hub, not one leg of a chain.",
                    {
                        praises: [
                            pr(ME, "🦄"),
                            pr(P.jihyun, "🎊"),
                            pr(P.minsu, "🦙"),
                        ],
                        sheet: { kind: "who" },
                    },
                ],
                [
                    "who-owner",
                    "The sheet behind the capsule",
                    "Who reacted &middot; your own book",
                    "The recipient's version, and the strongest argument for the sheet. There is no notification and no history anywhere in the app, so before this the entire experience of being reacted to was two anonymous circles beside a cover. No row is yours, so no row is tappable and nothing drills in.",
                    {
                        isSelf: true,
                        praises: [
                            pr(P.jihyun, "🎊"),
                            pr(P.taeho, "💯"),
                            pr(P.unseen, "🦙"),
                        ],
                        sheet: { kind: "who" },
                    },
                ],
                [
                    "who-reading",
                    "The sheet behind the capsule",
                    "Who reacted &middot; book back to Reading",
                    "The same sheet, reached from a book at status 1 where the button does not render. This is the fix for <code>stranded</code>, and it costs nothing extra: the capsule is part of the record, not part of the button, so it is on screen at every status. Compare <code>stranded</code> in <b>main</b>, where the same state has no route at all.",
                    {
                        status: 1,
                        praises: [pr(ME, "👏")],
                        sheet: { kind: "who" },
                    },
                ],
            ];

            function screensFor(style) {
                const groups = new Map();
                const rows = CASES.concat(
                    STYLE[style].record === "capsule" ? CAPSULE_ONLY : [],
                );
                for (const [id, g, nm, note, cfg] of rows) {
                    if (!groups.has(g)) groups.set(g, []);
                    groups.get(g).push([id, nm, note, hero(cfg, style)]);
                }
                return Array.from(groups, ([g, items]) => [g, items]);
            }
            const SCREENS = screensFor("main");

            /* Flows are generated the same way, so a direction cannot have its
               screens updated and its flows left behind. */
            function flowsFor(style) {
                const H = (cfg) => hero(cfg, style);
                /* With the button hidden once you hold a reaction, changing and
                   withdrawing route through the who-reacted sheet rather than
                   straight into the picker. Branching the steps here rather than
                   leaving the old three matters: a flow that contradicts the
                   screens is the exact drift this page is built to prevent. */
                const viaSheet = !!STYLE[style].tintMine;
                return [
                    [
                        "Leaving a reaction",
                        [
                            [
                                "first-praise",
                                "Reacting for the first time",
                                "The happy path. The sheet is the only way in, and it is the only way out again.",
                                [
                                    [
                                        "Nothing given",
                                        "The button is the whole affordance.",
                                        H({ praises: [] }),
                                    ],
                                    [
                                        "Sheet open",
                                        "3,500 emoji behind a search field, seeded with sixteen Recents so the first visit isn't blank. Nothing is marked, because you hold nothing.",
                                        H({
                                            praises: [],
                                            sheet: { selected: null },
                                        }),
                                    ],
                                    [
                                        "Praised",
                                        "Where the two treatments of your reaction land next to each other — or, in the capsule directions, where the button leaves and the record takes over.",
                                        H({ praises: [pr(ME, "💥")] }),
                                    ],
                                ],
                            ],
                            [
                                "change-praise",
                                "Changing your reaction",
                                "One reaction per person, so picking a different emoji replaces rather than adds. <code>created_at</code> is deliberately untouched: swapping the emoji is not a new reaction.",
                                viaSheet
                                    ? [
                                          [
                                              "Holding 💥",
                                              "No button here — the tinted capsule is the whole control.",
                                              H({ praises: [pr(ME, "💥")] }),
                                          ],
                                          [
                                              "Who reacted",
                                              "Tapping the capsule always lands here, whether or not one of the reactions is yours. One control, one destination.",
                                              H({
                                                  praises: [pr(ME, "💥")],
                                                  sheet: { kind: "who" },
                                              }),
                                          ],
                                          [
                                              "Your row opens the picker",
                                              "One tap further than it used to be. Acceptable for an action taken 39 times in the app's life, and the cost of the button not lying about what it does.",
                                              H({
                                                  praises: [pr(ME, "💥")],
                                                  sheet: {
                                                      kind: "picker",
                                                      selected: "💥",
                                                  },
                                              }),
                                          ],
                                          [
                                              "Replaced",
                                              "praiseTapFor reads a tap on anything else as replace.",
                                              H({ praises: [pr(ME, "🥰")] }),
                                          ],
                                      ]
                                    : [
                                          [
                                              "Holding 💥",
                                              "The state you start from.",
                                              H({ praises: [pr(ME, "💥")] }),
                                          ],
                                          [
                                              "Yours is the marked cell",
                                              "brand@25% on radius 8 with a 2pt brandFill border. Usually visible without hunting, since your own reaction is in Recents.",
                                              H({
                                                  praises: [pr(ME, "💥")],
                                                  sheet: { selected: "💥" },
                                              }),
                                          ],
                                          [
                                              "Replaced",
                                              "praiseTapFor reads a tap on anything else as replace.",
                                              H({ praises: [pr(ME, "🥰")] }),
                                          ],
                                      ],
                            ],
                            [
                                "withdraw",
                                "Taking your reaction back",
                                viaSheet
                                    ? "Reachable, and for the first time somewhere you would think to look. Your own row is the first thing in the sheet and the only one that drills in, so withdrawal stops being a property of the picker and becomes a property of the record."
                                    : "Tapping the emoji you already hold removes it. There is no Remove button anywhere — the strip that used to carry one was deleted, on the grounds that the marked cell already says which is yours and tapping it already withdraws.",
                                viaSheet
                                    ? [
                                          [
                                              "Holding 💥",
                                              "",
                                              H({ praises: [pr(ME, "💥")] }),
                                          ],
                                          [
                                              "Your row, and only yours",
                                              "<i>You</i> and a chevron on the row wearing your own name. Everyone else's row is inert.",
                                              H({
                                                  praises: [pr(ME, "💥")],
                                                  sheet: { kind: "who" },
                                              }),
                                          ],
                                          [
                                              "Tap the marked cell",
                                              "Same picker, same mark, same rule — but reached from the record rather than found in a 3,500-cell grid. Backing out here returns to the sheet, not to the book.",
                                              H({
                                                  praises: [pr(ME, "💥")],
                                                  sheet: {
                                                      kind: "picker",
                                                      selected: "💥",
                                                  },
                                              }),
                                          ],
                                          [
                                              "Withdrawn",
                                              "No reactions left, so no capsule, and the button comes back — there is something to add again.",
                                              H({ praises: [] }),
                                          ],
                                      ]
                                    : [
                                          [
                                              "Holding 💥",
                                              "",
                                              H({ praises: [pr(ME, "💥")] }),
                                          ],
                                          [
                                              "Tap the marked cell",
                                              "The mark is the entire instruction. Nothing on screen uses the word remove.",
                                              H({
                                                  praises: [pr(ME, "💥")],
                                                  sheet: { selected: "💥" },
                                              }),
                                          ],
                                          [
                                              "Withdrawn",
                                              "Back to the empty state.",
                                              H({ praises: [] }),
                                          ],
                                      ],
                            ],
                        ],
                    ],
                    [
                        "Receiving one",
                        [
                            [
                                "receive",
                                "Being reacted to",
                                "The owner's side. No button in either step — you cannot react to yourself — so the recipient is a spectator of their own reactions, which is what makes the record's legibility their whole experience of the feature.",
                                [
                                    [
                                        "Before",
                                        "Your finished book, no reactions yet.",
                                        H({ isSelf: true, praises: [] }),
                                    ],
                                    [
                                        "After",
                                        "Two friends reacted. This is the only place they appear — there is no notification and no history anywhere in the app.",
                                        H({
                                            isSelf: true,
                                            praises: [
                                                pr(P.jihyun, "😆"),
                                                pr(P.taeho, "💯"),
                                            ],
                                        }),
                                    ],
                                ],
                            ],
                        ],
                    ],
                    [
                        "When the status changes",
                        [
                            [
                                "stranded-route",
                                "A reaction that outlives the status",
                                "The owner can move a finished book back to Reading, and the reaction rows survive it. Drawn as a flow because the problem is a route, not a state: nothing on the second screen is wrong to look at, there is simply no longer a way off it.",
                                STYLE[style].record === "capsule"
                                    ? [
                                          [
                                              "Back to Reading",
                                              "The button is gone, because you cannot react to a book nobody has finished. The capsule is not part of the button, so it stays.",
                                              H({
                                                  status: 1,
                                                  praises: [pr(ME, "👏")],
                                              }),
                                          ],
                                          [
                                              "Tap the capsule",
                                              "Reached without the button. Your row is still tappable, so the reaction is still yours to change or take back.",
                                              H({
                                                  status: 1,
                                                  praises: [pr(ME, "👏")],
                                                  sheet: { kind: "who" },
                                              }),
                                          ],
                                          [
                                              "Withdrawn",
                                              "No reactions left, so no capsule, and the corner is back to the shelf label.",
                                              H({ status: 1, praises: [] }),
                                          ],
                                      ]
                                    : [
                                          [
                                              "Finished, reacted to by you",
                                              "The pill is the only entry to the sheet, and the sheet is the only way to withdraw.",
                                              H({ praises: [pr(ME, "👏")] }),
                                          ],
                                          [
                                              "Back to Reading",
                                              "status 1, so the pill returns an empty box. Your reaction is still there, still counted, and now unreachable.",
                                              H({
                                                  status: 1,
                                                  praises: [pr(ME, "👏")],
                                              }),
                                          ],
                                      ],
                            ],
                        ],
                    ],
                ].concat(
                    STYLE[style].record !== "capsule"
                        ? []
                        : [
                              [
                                  "Reading who reacted",
                                  [
                                      [
                                          "open-who",
                                          "Finding out who reacted",
                                          "The route the cap creates. Two emoji and a +1 say what the book collected; the sheet says who. Note that the capsule is the affordance and nothing labels it as one — the open question below.",
                                          [
                                              [
                                                  "Capped record",
                                                  "Three reactions, two shown, +1 for the rest. Yours is pinned first so it can never fall behind the count.",
                                                  H({
                                                      praises: [
                                                          pr(ME, "🦄"),
                                                          pr(P.jihyun, "🎊"),
                                                          pr(P.minsu, "🦙"),
                                                      ],
                                                  }),
                                              ],
                                              [
                                                  "Who reacted",
                                                  "Avatar, nickname, emoji. Yours is marked and is the only tappable row.",
                                                  H({
                                                      praises: [
                                                          pr(ME, "🦄"),
                                                          pr(P.jihyun, "🎊"),
                                                          pr(P.minsu, "🦙"),
                                                      ],
                                                      sheet: { kind: "who" },
                                                  }),
                                              ],
                                              [
                                                  "Your row opens the picker",
                                                  "Same sheet as the button opens, with your emoji marked. Tapping it withdraws; tapping another replaces.",
                                                  H({
                                                      praises: [
                                                          pr(ME, "🦄"),
                                                          pr(P.jihyun, "🎊"),
                                                          pr(P.minsu, "🦙"),
                                                      ],
                                                      sheet: {
                                                          kind: "picker",
                                                          selected: "🦄",
                                                      },
                                                  }),
                                              ],
                                          ],
                                      ],
                                  ],
                              ],
                          ],
                );
            }
            const FLOWS = flowsFor("main");

            function elementsFor(style) {
                const S = STYLE[style];
                const panel = (inner, align) =>
                    `<div class="fr" style="width:auto;border:0;border-radius:0;background:none"><div class="demopanel" style="align-items:${align || "flex-end"}">${inner}</div></div>`;
                const row = (inner) =>
                    `<div class="fr" style="width:auto;border:0;border-radius:0;background:none"><div class="demorow">${inner}</div></div>`;

                const carries = S.record === "chips" || S.record === "owned";
                const pillStates = carries
                    ? row(
                          `<span class="pill"><span class="em">🎉</span>${S.verb}</span><span class="pill"><span class="em">💥</span>${S.verb}</span>`,
                      )
                    : S.tintMine
                      ? row(
                            `<span class="pill"><span class="em">🎉</span>${S.verb}</span><span style="font:600 12px system-ui;color:#212529">then nothing</span>`,
                        )
                      : row(
                            `<span class="pill"><span class="em">🎉</span>${S.verb}</span><span class="pill out">${S.verb}ed</span>`,
                        );
                const pillNote = carries
                    ? "brandFill with white text, radius 20, h12/v6, label 13 bold. The icon slot is Icons.celebration at 18 until you react, then your emoji at 15. The label is the same in both states, so a pill you have already used still reads as an invitation."
                    : S.tintMine
                      ? "<b>One state, then none.</b> The button exists only while there is something to add; once you hold a reaction it is gone and the capsule owns replacing and withdrawing. That is the honest shape, because you can only hold one reaction — a button still saying <i>React</i> would be offering an action it cannot perform. It also removes the second string entirely: no <code>reacted</code> key, and no Korean wording to settle, which was one of the two things blocking implementation."
                      : "The state moved from the icon slot to the pill's weight: filled is an invitation, outlined is a record. Padding drops by exactly the 1.5pt border so the box stays 34pt — the same inset trap as <code>Border.all</code> on AvatarCircle. Needs one new string per locale; the Korean wording is an open question for a native speaker.";

                const record =
                    S.record === "capsule"
                        ? panel(
                              capsule({
                                  tintMine: S.tintMine,
                                  praises: [pr(P.jihyun, "🎊")],
                              }) +
                                  capsule({
                                      tintMine: S.tintMine,
                                      praises: [
                                          pr(ME, "🦄"),
                                          pr(P.jihyun, "🎊"),
                                      ],
                                  }) +
                                  capsule({
                                      tintMine: S.tintMine,
                                      praises: [
                                          pr(ME, "🦄"),
                                          pr(P.jihyun, "🎊"),
                                          pr(P.minsu, "🦙"),
                                          pr(P.seoyeon, "🤑"),
                                          pr(P.haneul, "🛸"),
                                      ],
                                  }),
                          )
                        : S.record === "gift"
                          ? panel(
                                gifts([
                                    pr(ME, "💥"),
                                    pr(P.jihyun, "😆"),
                                    pr(P.minsu, "🔥"),
                                    pr(P.unseen, "👏"),
                                ]),
                            )
                          : S.record === "named"
                            ? `<div class="fr" style="width:333px;border:0;border-radius:0;background:var(--variant);padding:10px 0">${bandPraise(
                                  {
                                      record: "named",
                                      praises: [
                                          pr(ME, "💥"),
                                          pr(P.jihyun, "😆"),
                                      ],
                                  },
                              )}</div>`
                            : panel(
                                  chips([
                                      pr(ME, "💥"),
                                      pr(P.jihyun, "😆"),
                                      pr(P.minsu, "🔥"),
                                  ]),
                              );
                const recordNote =
                    S.record === "capsule"
                        ? (S.tintMine
                              ? "One reaction that is not yours, then two and five that are. "
                              : "One, two, and five reactions. ") +
                          "Same material as the chip it replaces — pageBackground fill, brand@30% hairline — but one capsule rather than N loose circles, which is what fixes both the ragged cluster and the unbounded width. The <code>+N</code> appears only when there is a remainder: <code>+1</code> is information, a bare <code>1</code> is not. It takes primaryText, because secondaryText measures 2.0:1 on pageBackground." +
                          (S.tintMine
                              ? " The tinted state is the picker's marked-cell treatment, and the numbers are better than they look: the two fills are only 1.37:1 apart in luminance, but the border goes from 1.3:1 to 3.88:1, so the cue that survives a dim screen is the border becoming visible rather than the hue changing."
                              : "")
                        : S.record === "gift"
                          ? "The shipped chip, widened into a capsule that holds the reactor beside the emoji — same pageBackground fill and brand@30% hairline, 24pt avatar, emoji at 15. The first attempt notched the emoji onto the avatar as a 16pt badge, which put it at 9px: drawing it at 1:1 is the only reason that did not ship."
                          : S.record === "named"
                            ? "Text, in the band, under the reading period. Yours reads You in brandText; the eyebrow says what the line is, which it needs. It started in secondaryText and had to change: measured against surfaceVariant that is 1.75:1, unusable for a label. primaryText (13.01:1) instead, subordinate by size and tracking."
                            : "28pt circle, pageBackground fill, brand@30% hairline, emoji 14. Anonymous by construction: it cannot say who gave what, which is exactly why the button has to carry a copy of yours.";

                const extras =
                    S.record !== "capsule"
                        ? []
                        : [
                              [
                                  "el-chevron",
                                  S.tintMine
                                      ? "Chevron &middot; settled"
                                      : "Does the capsule need a chevron?",
                                  S.tintMine
                                      ? "<b>Settled by hiding the button.</b> While the button stayed on screen it was a second route to the sheet, so the chevron was a nice-to-have — reaction pills work without one everywhere else, and most people never discover that they reveal who. With the button gone the moment you react, this capsule is the only way to change or withdraw your reaction, and on any book that is not <i>Read</i> it is the only interactive thing in the hero. So it ships with the chevron. Left is the version without, kept to show what it costs: 8pt, and a device iOS normally reserves for rows rather than inline pills."
                                      : "Left, as drawn: nothing says the capsule is tappable, which is how reaction pills work everywhere else — most people never discover that a long press reveals who, and lose nothing by it. Right, with a chevron: unambiguous, costs 8pt, and borrows a device iOS reserves for rows rather than for inline pills. <b>The case that decides it is one reaction, not five:</b> at a single emoji the capsule is 33pt and near-circular, visually identical to the chip it replaces, and 31 of the 35 reacted-to books in production are in exactly that state. So the weakest affordance falls in the commonest state. <b>Open here; settled in stack-tint.</b>",
                                  panel(
                                      capsule({
                                          praises: [
                                              pr(ME, "🦄"),
                                              pr(P.jihyun, "🎊"),
                                              pr(P.minsu, "🦙"),
                                          ],
                                      }) +
                                          capsule(
                                              {
                                                  praises: [
                                                      pr(ME, "🦄"),
                                                      pr(P.jihyun, "🎊"),
                                                      pr(P.minsu, "🦙"),
                                                  ],
                                              },
                                              { chevron: true },
                                          ),
                                  ),
                              ],
                              [
                                  "el-verb",
                                  "What the button should say",
                                  "The word is not cosmetic here. 35 distinct emoji across 39 rows in production, and only about 8 of them are praise (👏🥳🎉🎊⭐🤩); another 8 are affection; the rest are ☃️ 🌪️ 🐙 🦕 🦙 🧸 🪐 🛸 🤑 🤪. People are already using this as a free-form reaction, so <b>React</b> is the label that matches the affordance behind it — a 3,500-emoji picker — and the warmth belongs to the emoji rather than to a label the picker contradicts. <i>Praise</i> also reads oddly to a native English speaker: slightly grand, and a verb almost no interface uses. <i>Cheer</i> is the warm alternative if the register matters more than the accuracy.",
                                  row(
                                      `<span class="pill"><span class="em">🎉</span>Praise</span><span class="pill"><span class="em">🎉</span>React</span><span class="pill"><span class="em">🎉</span>Cheer</span>`,
                                  ),
                              ],
                          ];

                return [
                    [
                        "The reaction itself",
                        [
                            [
                                "el-pill",
                                "The button &middot; both states",
                                pillNote,
                                pillStates,
                            ],
                            ["el-record", "The record", recordNote, record],
                            [
                                "el-cell",
                                "Marked cell in the sheet",
                                "brand@25% on radius 8 with a 2pt brandFill border, from emojiRenderer. Load-bearing rather than decorative: since the Your-praise strip was deleted, this mark is the only thing in the sheet telling you where you stand, and tapping it is the only way to withdraw.",
                                `<div class="fr" style="width:220px;border:0;border-radius:0;background:var(--sheet);padding:8px"><div class="egrid2" style="grid-template-columns:repeat(4,1fr)"><s>👏</s><s class="mine">💥</s><s>❤️</s><s>🔥</s></div></div>`,
                            ],
                        ].concat(extras),
                    ],
                    [
                        "The corner they share",
                        [
                            [
                                "el-corner",
                                "The stack, at real scale",
                                S.badge === "card"
                                    ? "Two objects in the column and one on the shelf, down from four. The badge left for the status card, the record is one capsule instead of a cluster, and the two capsules are close enough in width that the right edge stops reading as a staircase. This is the crowding fix; the record change alone does not get here."
                                    : "Pill, record, status badge, shelf label: four shapes, four widths, four alignments, nothing relating them. Switch to <b>stack-status</b> to see this with the badge moved out.",
                                `<div class="fr" style="width:237px;border:0;border-radius:0;background:var(--variant);padding:10px"><div class="demopanel">${pill(
                                    {
                                        ...S,
                                        status: 2,
                                        praises: [pr(ME, "🦄")],
                                    },
                                )}${
                                    S.record === "capsule"
                                        ? capsule({
                                              praises: [
                                                  pr(ME, "🦄"),
                                                  pr(P.jihyun, "🎊"),
                                              ],
                                          })
                                        : S.record === "gift"
                                          ? gifts([pr(ME, "🦄")])
                                          : S.record === "named"
                                            ? ""
                                            : chips([pr(ME, "🦄")])
                                }${
                                    S.badge === "card"
                                        ? ""
                                        : `<span class="sbadge read" style="margin-top:14px">Read</span>`
                                }<span class="slab" style="margin-top:14px">쇼호스트</span></div></div>`,
                            ],
                            [
                                "el-badge",
                                "Status badge &middot; all three",
                                S.badgefix
                                    ? "With status 0 repaired. The three now read as a <b>progression of weight</b> — empty outline, green fill, dark fill — rather than as three pale tints. Text measures 13.01:1 / 4.14:1 / 10.78:1 against what sits behind it; the Interested border is held to 3:1 (3.41:1) because with no fill it is the thing that identifies the badge as a badge. Reading is untouched and is the one knowing near-miss: see the note in <code>statusBadge</code>."
                                    : "h10/v4, radius 10, the status colour at 10% fill and 40% border, text in the same colour. Measured against its own composited fill: <b>Read 10.78:1</b>, <b>Reading 4.14:1</b>, <b>Interested 1.66:1</b>. Only the first clears AA, and Interested is not marginal — it is unreadable. Moving it into the white status card does not fix it either (1.95:1 there). Switch to <b>stack-status</b> for the repair.",
                                `<div class="fr" style="width:auto;border:0;border-radius:0;background:var(--variant)"><div class="demorow"><span class="sbadge interested${
                                    S.badgefix ? " fixed" : ""
                                }">Interested</span><span class="sbadge reading">Reading</span><span class="sbadge read">Read</span></div></div>`,
                            ],
                            [
                                "el-badge-fix",
                                "Interested &middot; shipped vs repaired",
                                "Left is what ships: <code>secondaryText</code> for the text, its own colour at 10% fill and 40% border. <b>1.66:1</b> text, <b>1.23:1</b> border. Right drops the fill and takes the text to <code>primaryText</code>: <b>13.01:1</b> text, <b>3.41:1</b> border. Dropping the fill is the part that matters, not the darker text — the shipped Interested and Read tints composite to <code>#E3E6EA</code> and <code>#D5D8DB</code>, two near-identical greys, so the two ends of the progression were only ever separated by a text colour you could not read. An intermediate version that darkened only the text was drawn and cut for exactly that reason: legible, but it made <i>Interested</i> look like <i>Read</i>. Folded into <b>stack-status</b>; affects 133 books.",
                                `<div class="fr" style="width:auto;border:0;border-radius:0;background:var(--variant)"><div class="demorow"><span class="sbadge interested">Interested</span><span class="sbadge interested fixed">Interested</span></div></div>`,
                            ],
                            [
                                "el-card",
                                "Reading period card, both ways",
                                "Top: as shipped, with a <i>Reading period</i> label. Bottom: the badge standing in for that label. Status, dates and duration are one class of fact, so they belong in one card — and the badge does more work than the label did, so this <b>removes</b> a string rather than adding one. It also retires an oddity: today the badge sits in the corner on a friend's book and at the top of the column on your own, two places for one thing. The catch is status 0, where the card does not render at all — see the <code>interested</code> screen.",
                                `<div class="fr" style="width:333px;border:0;border-radius:0;background:var(--variant)"><div class="demopanel" style="align-items:stretch;gap:12px"><div class="period"><b>Reading period</b><span>2023.09.04 ~ 2023.09.05</span><i>1 day</i></div><div class="period withbadge"><span class="sbadge read">Read</span><b>Reading period</b><span>2023.09.04 ~ 2023.09.05</span><i>1 day</i></div></div></div>`,
                            ],
                            [
                                "el-shelf",
                                "Shelf label and shelf",
                                "surface, top radius 3 only, h9/v5, bold 14, capped at 140 then ellipsized. It reads as a tab because it sits on the 8pt shelf, whose shadow is offset(0,2) blur 2 at black@25%.",
                                `<div class="fr" style="width:180px;border:0;border-radius:0;background:var(--variant);padding:14px 0 0"><div class="demopanel" style="align-items:center;gap:0"><span class="slab">쇼호스트</span></div><div class="shelf"></div></div>`,
                            ],
                        ],
                    ],
                ];
            }
            const ELEMENTS = elementsFor("main");

            /* Unresolved decisions. Keyed by *flow* id: the engine only renders
               this callout in the flows view, so an entry under a screen id is
               dead configuration. That is why `stranded-route` exists as a flow
               rather than as a note on the `stranded` screen. */
            const OPEN = {
                "stranded-route":
                    "Pre-existing, and <b>fixed by the two capsule directions</b>: in main a reaction you left on a book that has since gone back to <i>Reading</i> is visible and unreachable, because the sheet only opens from a button that hides at <code>status != 2</code>. Switch to <b>stack</b> to see the route the capsule restores. Still open in main, owned, named and gift.",
                withdraw:
                    "Open in main: withdrawal is reachable only by recognising your own emoji among 3,500 and tapping it, with nothing anywhere using the word <i>remove</i>. Acceptable while reactions are dormant (39 in total, 8 people, 0 in the last 90 days), and answered properly by the who-reacted sheet in <b>stack</b>, where your row is the first thing in it.",
                "open-who":
                    "Open: nothing labels the capsule as tappable. Reaction pills work this way everywhere else — most people never learn that a long press reveals who, and lose nothing — but on your own book the capsule is the only object in the corner and the only thing standing in for a notification the app does not have. See <code>el-chevron</code> for the version that spells it out.",
            };

            /* ==================================================================
   SECTION 4: VERSIONS — four directions for the same region.

   Each is a whole answer, not a variation in padding. The axis they
   differ on is where the record of a praise lives and how much it says:

     main   the record is an anonymous chip beside the button
     owned  the record splits by owner: button holds yours, chips theirs
     named  the record leaves the corner for the band, as text
     gift   the record stays, and becomes the praiser's face

   Compare any two with Shift+Enter in the version panel.
   ================================================================== */
            function byId(id) {
                for (const [i, , , , cfg] of CASES) if (i === id) return cfg;
                return {};
            }
            const flatScreens = (S) =>
                new Map(
                    S.flatMap(([g, items]) =>
                        items.map(([id, nm, note, spec]) => [
                            id,
                            [g, nm, note, spec],
                        ]),
                    ),
                );
            const flatFlows = (F) =>
                new Map(
                    F.flatMap(([g, items]) =>
                        items.map(([id, nm, note, steps]) => [
                            id,
                            [g, nm, note, steps],
                        ]),
                    ),
                );
            const renderSteps = (steps) =>
                steps.map(([n, c, sp]) => n + "|" + c + "|" + frame(sp)).join("~");
            const flatEls = (E) =>
                new Map(
                    E.flatMap(([g, items]) =>
                        items.map(([id, nm, note, demo]) => [
                            id,
                            [g, nm, note, demo],
                        ]),
                    ),
                );

            /* Notes attached to a case a direction does not actually change.
               Collected rather than silently honoured: see patch(). */
            const DROPPED = [];

            /* Builds a version's patch against its <b>parent</b>, and leaves out
               anything the two draw identically.

               The baseline is a parameter because the version tree is no longer
               flat: stack-tint hangs off stack-status, which hangs off stack.
               Diffing every version against main would have made stack-tint
               restate the whole capsule direction as if it had invented it, and
               the compare view would then report a dozen changes where there are
               six.

               Ids the parent does not have are additions and carry their own
               group, name and note. A note written for a case this version draws
               identically to its parent goes to DROPPED rather than dragging the
               screen into the diff — that check has now caught three notes
               claiming changes that were not there. */
            function patch(style, notes, base) {
                base = base || "main";
                const out = { screens: {}, flows: {}, elements: {} };

                const mineS = flatScreens(screensFor(style));
                const baseS = flatScreens(screensFor(base));
                for (const [id, [g, nm, note, spec]] of mineS) {
                    const b = baseS.get(id);
                    if (b && frame(spec) === frame(b[3])) {
                        if (notes[id]) DROPPED.push(style + "/" + id);
                        continue;
                    }
                    out.screens[id] = b
                        ? notes[id]
                            ? { spec, note: notes[id] }
                            : { spec }
                        : { group: g, name: nm, note: notes[id] || note, spec };
                }

                const mineF = flatFlows(flowsFor(style));
                const baseF = flatFlows(flowsFor(base));
                for (const [id, [g, nm, note, steps]] of mineF) {
                    const b = baseF.get(id);
                    if (!b) {
                        out.flows[id] = { group: g, name: nm, note, steps };
                        continue;
                    }
                    const sameSteps = renderSteps(steps) === renderSteps(b[3]);
                    const sameText = nm === b[1] && note === b[2];
                    if (sameSteps && sameText) continue;
                    /* Name and note travel with the steps. Dropping them left the
                       four-step withdraw flow in stack-tint captioned with main's
                       three-step prose, which claimed nothing anywhere uses the
                       word remove — on a screen whose sheet says exactly that. */
                    out.flows[id] = sameText
                        ? { steps }
                        : { name: nm, note, steps };
                }

                const mineE = flatEls(elementsFor(style));
                const baseE = flatEls(elementsFor(base));
                for (const [id, [g, nm, note, demo]] of mineE) {
                    const b = baseE.get(id);
                    if (b && b[1] === nm && b[2] === note && b[3] === demo)
                        continue;
                    out.elements[id] = b
                        ? { name: nm, note, demo }
                        : { group: g, name: nm, note, demo };
                }
                return out;
            }

            const VERSIONS = [
                [
                    "main",
                    "main",
                    "The shipped build. The button carries your emoji on its face; ComplimentBlock lists every reaction on the book as anonymous 28pt chips underneath. When you are the only one — 31 of 35 reacted-to books — the two are the same emoji, twice.",
                    null,
                    {},
                ],

                [
                    "stack",
                    "stack",
                    "Cap the record and put the detail behind it. Up to two emoji plus <code>+N</code> in one capsule; tapping it opens a sheet listing who reacted with what. Isolates the record change — the badge stays in the corner — so the two decisions can be judged apart. Renames the verb to <b>React</b>, which the production data argues for: of 39 reactions only about 8 are praise, and the rest are ☃️ 🌪️ 🐙 🦕 🦙 🧸 🪐 🛸 🤑 🤪.",
                    "main",
                    patch("stack", {
                        mine: "One capsule where there were a pill-emoji and a chip. The button drops the emoji and takes the state into its weight, because the capsule already shows what you left.",
                        "mine-plus":
                            "Two reactions, both visible, no <code>+N</code> yet — and no book in production holds more than two, so this is the complete form for every real book today. Which means the capsule is not a truncation in practice; it is a cap that has not yet had to bite.",
                        theirs: "Two emoji, one object. Compare against main's two loose circles: same information, half the shapes.",
                        crowd: "Where the cap earns itself. Five reactions become <code>💥 😆 +3</code> at a fixed 96pt instead of a 156pt row that grows without limit, and the detail is one tap away rather than crammed into a 217pt column.",
                        unseen: "Unchanged on the surface — a lone emoji in a capsule needs no profile. The unreadable praiser only becomes visible in the sheet, where it can be said in words instead of guessed from a glyph.",
                        owner: "The recipient's corner is now one capsule, and it is the only object there. That is an argument for the chevron: see <code>el-chevron</code>.",
                        stranded:
                            "Fixed, and almost incidentally. The capsule belongs to the record rather than to the button, so it survives the status change and the sheet behind it still has your row in it. See the <code>who-reading</code> screen and the <b>stranded-route</b> flow.",
                        "interested-reacted":
                            "Compare this against <b>main</b> and the two are nearly identical — a lone emoji at the top of an empty column. The difference is entirely invisible: here it opens the sheet, there it does nothing. That makes this the sharpest version of the chevron question in <code>el-chevron</code>, because the capsule is the only interactive thing in the whole hero and nothing whatsoever marks it as one. It also shows the record floating at the top of a 180pt column with nothing above it, which is how the shipped layout has always behaved when the button is absent.",
                    }),
                ],

                [
                    "stack-status",
                    "stack-status",
                    "The capsule, plus the status badge moved out of the corner and into the reading-period card — where it stands in for the <i>Reading period</i> label rather than being added beside it. Status, dates and duration are one class of fact. Takes the corner from four objects to three, retires the oddity of the badge living in two different places depending on whose book it is, and removes a string instead of adding one. <b>Also repairs the Interested badge</b>, which measures 1.66:1 as shipped and appears on 133 of 472 books — folded in here rather than tracked separately, because moving the badge and being able to read it are the same job. My recommendation.",
                    "stack",
                    patch("stack-status", {
                        none: "The empty state is where the decrowding is easiest to see: a single button in the corner and a shelf label, against main's button-plus-badge-plus-label.",
                        mine: "The whole proposal in one screen. Two capsules of similar width in the column, one tab on the shelf, and the status where the dates are.",
                        owner: "The badge no longer has to be hoisted to the top of this column on your own book, because it is not in this column at all. One rule for both viewers.",
                        interested:
                            "The case that tests the relocation. <code>ReadingPeriodRow</code> renders nothing below status 1, so there is no card to move into. First answer was to render the card anyway with the badge alone; at 1:1 that is a full-width white slab holding one small chip, worse than the corner it replaced. So at status 0 the badge sits in the band <i>without</i> a card. The rule holds either way — status lives in the band, under the author — and the card stays what it always was, a container for dates.",
                        "interested-friend":
                            "Same answer on a friend's book, where the right column is now completely empty and the corner is a single shelf label. The badge is also the repaired one here, so compare against <b>main</b>: the state is finally named by something you can read, and it is the only text in the hero that was not legible before.",
                        "interested-reacted":
                            "Both changes at once, on the state that had neither: the reaction is reachable through the capsule and the status is readable. In <b>main</b> this screen has an unreachable emoji and an illegible badge.",
                    }),
                ],

                [
                    "stack-tint",
                    "stack-tint",
                    "Once you hold a reaction the button <b>goes away</b>, and the tinted capsule is the whole control. You can only hold one reaction, so a button saying <i>React</i> is offering to add something it cannot add — what it really does is replace or withdraw, and both of those belong to the reaction you already have. Hiding it removes the lie, takes the reacted corner down to a capsule and a shelf label, and needs no second string, so <b>no Korean wording to settle</b>. The tint is the emoji picker's own marked-cell treatment, so the record and the sheet finally say <i>this one is yours</i> the same way. My recommendation, replacing stack-status.",
                    "stack-status",
                    Object.assign(
                        patch(
                            "stack-tint",
                            {
                                mine: "The reacted state, with nothing in the corner but the reaction itself and the shelf label. Compare against <b>stack-status</b>, where a relabelled outlined button sat above the same capsule saying a second time what the capsule already said.",
                                "mine-plus":
                                    "Two reactions, one yours, tinted as a whole rather than marking which emoji inside it is yours. Deliberate — yours is pinned first, so per-emoji marking would repeat what the order already says at a size too small to read. The cost is real: the tint means <i>you are in this set</i>, not <i>this emoji is yours</i>.",
                                theirs: "Reactions exist but none are yours, so the button stays — there is still something to add — and the capsule stays untinted. This is the state that shows the two capsule treatments against each other in one glance.",
                                crowd: "Tinted, with a +3, and no button. The corner is now quieter with five reactions than main was with one.",
                                stranded:
                                    "The stranded problem does not get fixed here so much as <b>dissolved</b>. There is no longer a state where the button vanishes and takes the route with it, because the button is already gone the moment you react. This screen and <code>mine</code> now differ only in what the status badge says.",
                                "interested-reacted":
                                    "The same, at status 0. One tinted capsule alone in the hero, carrying that a reaction exists, that it is yours, and that there is more behind it.",
                            },
                            "stack-status",
                        ),
                        {
                            /* Resolved, not inherited: the chevron question was
                               open while the button was still a second route to
                               the sheet. With the button hidden it is the only
                               route, so the capsule ships with the chevron and
                               the callout comes off this version. */
                            open: { "open-who": null },
                        },
                    ),
                ],

                [
                    "owned",
                    "owned (rejected)",
                    "<b>Rejected in review.</b> Split the record by owner: the button holds yours, the strip holds everyone else's. Cheapest possible fix — no query change, no new string, three of eight cases touched — but it only removes the duplication; the corner stays as crowded and the record stays anonymous. Kept browsable because the hazard it exposed still applies to anything that hides your own reaction: with no button on screen, an unconditional exclusion hides your reaction completely, so the exclusion has to be keyed to whether the button rendered and passed in as a <b>required</b> parameter.",
                    "main",
                    patch("owned", {
                        mine: "Duplication gone by construction rather than by marking: there is only one place your reaction can appear. The cost is that the strip stops being the book's total — the total is now button plus strip, and nothing says so.",
                        "mine-plus":
                            "One chip means one other person, and yours is on the button. Compare against <b>main</b>, where the same state is two identical circles.",
                        crowd: "Four chips instead of five. Slightly quieter, same fundamental shape — this direction fixes an ambiguity, not the crowding.",
                    }),
                ],

                [
                    "named",
                    "named (rejected)",
                    "<b>Rejected in review.</b> The record leaves the corner for the title band, as an attributed text line. Decrowds the most and scales best, but it grows the hero by about 21pt — and the hero's height is what the title-collapse threshold is measured against — and it separates the record from the button that creates it. Its good idea survives in <b>stack-status</b>: move something out of that corner.",
                    "main",
                    patch("named", {
                        mine: "Your reaction reads as a sentence rather than a token. Cost: the hero grows about 21pt, and the hero's height is exactly what the title-collapse threshold is measured against (see the comment at book_details_tab_view.dart:321).",
                        "mine-plus":
                            "Where attribution starts paying: two names, two emoji, no matching exercise.",
                        theirs: "Strictly better than main's two anonymous chips — you learn who, for free.",
                        crowd: "Scales in the one direction that has room, at the cost of a taller hero.",
                        unseen: "The fallback has to be prose, and prose is worse at being vague than a glyph is.",
                        owner: "The recipient reads a list of friends rather than a row of tokens.",
                        stranded:
                            "Still stranded, and now further away: the record is in the band while the missing route back is in the corner.",
                    }),
                ],

                [
                    "gift",
                    "gift (rejected)",
                    "<b>Rejected in review.</b> Every reaction carries its giver's face inline: the shipped chip widened into a capsule holding a 24pt avatar. Most informative at a glance and it uses the avatar work that just shipped, but it puts attribution in the one place with no room for it, and it widens without limit — which is exactly what <b>stack</b> caps. Worth keeping for the finding that killed the first draft: a 16pt emoji badge notched onto a 26pt avatar puts the emoji at 9px.",
                    "main",
                    patch("gift", {
                        mine: "One emoji, once, on the face of the person who left it. Which reaction is yours needs no marking because it is wearing your photo.",
                        "mine-plus":
                            "Two faces, two emoji. Immediate in a way the two-chip version never is.",
                        theirs: "Two friends, named by their faces.",
                        crowd: "A 56pt capsule fits three per row against the chips' five, so five reactions wrap to two lines — the unbounded growth stack exists to cap.",
                        unseen: "The price of inline attribution: a reactor you can't read has no face and no name, so it falls back to the person glyph AvatarCircle already uses for a photo that hasn't arrived.",
                        owner: "For the recipient, the reactions on your book have faces on it.",
                        stranded:
                            "Still stranded, though this direction hinted at the fix stack takes: make the record itself tappable.",
                    }),
                ],
            ];
