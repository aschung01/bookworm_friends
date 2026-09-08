      /* ==================================================================
      SECTION 2: FRAME RENDERER — replace with your product's chrome.

      Screens are declared as DATA and drawn by this one function. When a
      shared decision changes (a button leaves the header, a tab is
      renamed) you edit it here once instead of in every mockup, which is
      how hand-drawn sets go stale.
      ================================================================== */
      /* `kGeneratedCoverPalette`, verbatim — generated_cover.dart:12-19.
            Harmonised with the brand green rather than sampled at random, "so a
            shelf of coverless books still looks like it belongs to this app".
            What was here before was an invented blue/purple/grey set that
            belonged to no app at all, which is most of why these frames read as
            generic. Brand green leads, so the first book on every shelf is the
            brand colour. */
      const PAL = [
        "#09BC8A",
        "#0E7C7B",
        "#2F6690",
        "#E0644E",
        "#F2B544",
        "#7C5CBF",
      ];
      /* Illustrative, not ground truth: shelves and their books are entirely
            user-named, so there is nothing in the schema to be faithful to. Real
            titles rather than lorem, because a cover's lower half is a title and
            a Korean title sets at a completely different density than a Latin
            one — which is the whole reason `_kTitleSizeRatio` runs above the
            reference's 10.5%. */
      const BOOK_TITLES = [
        "소년이 온다",
        "아몬드",
        "달러구트 꿈 백화점",
        "여행의 이유",
        "불편한 편의점",
        "코스모스",
        "해변의 카프카",
        "작별인사",
        "파친코",
        "미움받을 용기",
      ];

      function block(b) {
        switch (b.t) {
          case "text":
            return `<div class="txt${b.dim ? " dim" : ""}">${b.v}</div>`;
          case "chat":
            return (
              `<div class="chat"><div class="who">${b.who}</div>` +
              b.msgs
                .map(
                  (m, i) =>
                    `<div class="msg"><span class="av">${i ? "" : b.e}</span>` +
                    `<span class="bub">${m}</span></div>`,
                )
                .join("") +
              `<div class="og"><div class="im"><u></u><u></u><u></u></div>` +
              `<div class="tx"><div class="ot">${b.card.t}</div>` +
              `<div class="od">${b.card.d}</div>` +
              `<div class="oh">${b.card.h}</div></div></div></div>`
            );
          case "store":
            return (
              `<div class="store"><div class="top">` +
              `<span class="ico">${b.e}</span>` +
              `<span class="meta"><span class="nm3">${b.name}</span>` +
              `<span class="sub3">${b.sub}</span></span>` +
              `<span class="get">${b.cta}</span></div>` +
              `<div class="shots">${[0, 3]
                .map(
                  (seed) =>
                    `<div class="shot">${[0, 1]
                      .map(
                        (row) =>
                          `<div class="r">${[0, 1, 2, 3]
                            .map(
                              (i) =>
                                `<u style="--c:${PAL[(seed + row * 3 + i) % PAL.length]}"></u>`,
                            )
                            .join("")}</div>`,
                      )
                      .join("")}</div>`,
                )
                .join("")}</div></div>`
            );
          case "shelf": {
            const titles = b.titles || BOOK_TITLES;
            let bs = "";
            for (let i = 0; i < (b.n ?? 4); i++) {
              const k = i + (b.seed || 0);
              // heightFactor's real range is [0.94, 1.06] —
              // book_geometry.dart:213-214. Hashed, so a shelf is not a
              // staircase and the same seed always draws the same shelf.
              const hf = (0.94 + ((k * 5) % 7) * 0.02).toFixed(3);
              bs +=
                `<i class="bk" style="--c:${b.color || PAL[k % PAL.length]};--hf:${hf}">` +
                `<b></b><em>${titles[k % titles.length]}</em></i>`;
            }
            return (
              `<div class="shelf"><div class="bks">${bs}</div>` +
              (b.label ? `<span class="stab">${b.label}</span>` : "") +
              `<div class="plank"></div></div>`
            );
          }
          case "rows":
            return b.items
              .map(
                (r, i) =>
                  `<div class="row"${i === b.items.length - 1 ? ' style="border:0"' : ""}>${
                    r.thumb !== undefined
                      ? `<span class="thumb" style="--c:${r.thumb || PAL[i % PAL.length]}"></span>`
                      : ""
                  }<span class="rt">${r.t}${r.s ? `<div class="rs">${r.s}</div>` : ""}</span>${
                    r.v ? `<span class="rv">${r.v}</span>` : ""
                  }</div>`,
              )
              .join("");
          case "stat":
            return `<div class="stat"><div class="l">${b.label}</div><div class="b">${b.big}</div>${
              b.sub ? `<div class="s">${b.sub}</div>` : ""
            }</div>`;
          case "caps":
            return `<div class="caps">${b.items
              .map((x) => `<s class="${x === b.on ? "on" : ""}">${x}</s>`)
              .join("")}</div>`;
          /* ---- friend-request primitives ---- */
          case "hdr":
            return `<div class="hdr"><span class="av">${b.emoji || "&#128293;"}</span><span class="who"><div class="nmx">${b.name}</div>${
              b.handle ? `<div class="hd">@${b.handle}</div>` : ""
            }<div class="st${b.stats.length > 1 ? " two" : ""}">${b.stats
              .map((s) => `${s.l}<i>${s.v}</i>`)
              .join("")}</div></span></div>`;
          case "plrow":
            return `<div class="plrow"${b.full ? ' style="width:100%"' : ""}>${b.items
              .map(
                (p) =>
                  `<span class="pl ${p.k || "vary"}${b.full ? " wide" : ""}">${p.l}</span>`,
              )
              .join("")}</div>`;
          case "sect":
            return `<div class="sect">${b.v}</div>`;
          case "hint":
            return `<div class="hint2">${b.v}</div>`;
          case "fld":
            return `<div class="fld">${b.v}</div>`;
          case "link":
            return `<div class="link">${b.v}</div>`;
          /* Eats the leftover height, pinning whatever follows to the floor.
                            Every full-screen sheet in the reference is laid out this way. */
          case "push":
            return `<div class="push"></div>`;
          case "h2b":
            return `<div class="h2b">${b.v}</div>`;
          case "hero":
            return `<div class="h1b">${b.v}</div>`;
          case "fine":
            return `<div class="fine${b.code ? " code" : ""}">${b.v}</div>`;
          case "tog":
            return `<div class="tog${b.on ? " on" : ""}">${b.v}<u></u></div>`;
          /* The signature. Two fans of covers meeting — see SECTION 1e. */
          case "sduo":
            return `<div class="sduo"><span class="fan l"><u></u><u></u><u></u><span class="chip">${b.a.e}</span><span class="nm2">${b.a.n}</span></span>${
              b.done ? '<span class="seal">&#10003;</span>' : ""
            }<span class="fan r"><u></u><u></u><u></u><span class="chip">${b.b.e}</span><span class="nm2">${b.b.n}</span></span></div>`;
          /* The payoff illustration — see SECTION 1f. */
          case "illus":
            return `<div class="illus">${b.items
              .map((g, gi) => {
                // Two books each, built the same way `shelf` builds them, so a
                // friend's shelf in the mark is the same object as a friend's
                // shelf in the app. Seeded off the group index so the three
                // read as different libraries rather than three copies of one.
                const books = [0, 1]
                  .map((i) => {
                    const k = gi * 2 + i + (b.seed || 0);
                    return (
                      `<i class="bk" style="--c:${PAL[k % PAL.length]}">` +
                      `<b></b><em>${BOOK_TITLES[k % BOOK_TITLES.length]}</em></i>`
                    );
                  })
                  .join("");
                return (
                  `<span class="ig"><span class="chip2">${g.e}</span>` +
                  `<span class="fan2">${books}</span>` +
                  `<span class="plank2"></span>` +
                  `<span class="st2 ${g.k || ""}">${g.s}</span></span>`
                );
              })
              .join("")}</div>`;
          /* People rows: avatar + name + @handle + trailing pills.
                          One primitive for search results, request rows and the
                          friends list, because they are the same row wearing
                          different actions. */
          case "people":
            return b.items
              .map(
                (p) =>
                  `<div class="prow"><span class="av sm">${p.e || "&#128218;"}</span><span class="pt"><div class="pn">${p.n}</div>${
                    p.h ? `<div class="ph">@${p.h}</div>` : ""
                  }</span>${
                    p.acts
                      ? `<span class="plrow">${p.acts
                          .map(
                            (a) =>
                              `<span class="pl ${a.k || "vary"}">${a.l}</span>`,
                          )
                          .join("")}</span>`
                      : ""
                  }</div>`,
              )
              .join("");
          default:
            return "";
        }
      }
      function blocks(list) {
        return (list || []).map(block).join("");
      }

      /** Draw one screen from its spec.
       *
       * Chrome is defined here once: app bar, sheet, and the three-tab
       * pill (Library / Friends / Card — `LibraryTab` has exactly three
       * values, `library_shell_provider.dart:30`).
       *
       * `bar.actions` / `sheet.actions` entries are either a string
       * (plain icon) or `{i, badge}`. The badge is what carries the
       * pending-request count, and it lives on an existing icon because
       * the tab bar cannot take a fourth item — the 4th native slot is
       * Add Book (`shell_tab_bar.dart:261`).
       *
       * `bar.pills` draws a trailing relationship affordance at intrinsic
       * width. `bar.visit: true` draws the shell's visit state instead —
       * ✕ in the leading slot, the friend's library as the title, Poke
       * trailing — which is what `_LibraryBar` renders now
       * (`home_page.dart:834`, contract at `:820`, Poke wired at `:376`).
       *
       * `bar.visit` does NOT imply `tabs: false`, and an earlier revision of
       * this file had that backwards. The tab bar stays up during a visit:
       * `shell_chrome_provider.dart:56-62` records that it used to be hidden
       * and that hiding it is *gone*, because no tab changes meaning inside a
       * visit — Library is your books, Card is your card, Friends is your list
       * or the friend one level down it. Selecting Library or Card ends the
       * visit, which is what makes the bar the way out rather than a claim
       * about where you are. Friends is therefore the live tab on a visit.
       */
      function frame(s) {
        let h = `<div class="fr${s.sm ? " sm" : ""}"><div class="status"></div>`;
        const icons = (list) =>
          (list || [])
            .map((a) =>
              typeof a === "string"
                ? `<span class="ic">${a}</span>`
                : `<span class="ic">${a.i}${a.badge ? `<span class="bd">${a.badge}</span>` : ""}</span>`,
            )
            .join("");
        const visit = s.bar && s.bar.visit;
        /* A visit's trailing group is the gear then the Poke pill. Poke is a
              `brandFill` pill and not an icon (`home_page.dart:1094-1112`), and it
              occupies the slot your own avatar would (`:1030`). The gear is where
              `manage-friend` is reached from: it replaced a long press that nothing
              on the row advertised. Gear inboard, Poke outermost, which is how iOS
              orders a trailing group -- secondary first, primary at the edge. */
        const visitTrail = visit
          ? `<span class="ic">&#9881;</span><span class="pl brand">Poke</span>`
          : "";
        if (s.bar !== false)
          h += `<div class="bar">${visit ? '<span class="ic">&#10005;</span>' : s.bar?.back ? '<span class="ic">&#8249;</span>' : ""}<span class="t">${s.bar?.title || ""}</span>${(
            s.bar?.pills || []
          )
            .map((p) => `<span class="pl ${p.k || "vary"}">${p.l}</span>`)
            .join("")}${visitTrail}${icons(visit ? [] : s.bar?.actions)}</div>`;
        if (s.body) h += `<div class="body">${blocks(s.body)}</div>`;
        if (s.sheet) {
          h += `<div class="sheet" style="height:${s.sheet.h}%"><div class="hdl"></div>`;
          if (s.sheet.title)
            h += `<div class="sh"><span class="lt">${s.sheet.title}${
              s.sheet.count !== undefined ? ` <i>${s.sheet.count}</i>` : ""
            }</span>${icons(s.sheet.actions)}</div>`;
          h += blocks(s.sheet.body) + `</div>`;
        }
        /* `AlertDialog.adaptive` over a scrim — the app's own confirm, at
              manage_friend_page.dart:195. Drawn
              after the body so it covers it, and before the tab bar because an
              iOS alert dims the tab bar too. */
        if (s.alert) {
          h +=
            `<div class="scrim"></div><div class="alert">` +
            `<div class="at">${s.alert.title}</div>` +
            (s.alert.msg ? `<div class="am">${s.alert.msg}</div>` : "") +
            `<div class="aa">${s.alert.actions
              .map(
                (a) =>
                  `<s class="${a.k || ""}">${typeof a === "string" ? a : a.l}</s>`,
              )
              .join("")}</div></div>`;
        }
        if (s.tabs !== false)
          h += `<div class="tb"><div class="tp${s.dim ? " dim" : ""}">${(
            s.tabs || ["Library", "Friends", "Card"]
          )
            .map((t) => `<s class="${t === s.tab ? "on" : ""}">${t}</s>`)
            .join("")}</div></div>`;
        return h + `</div>`;
      }

      /* ==================================================================
      SECTION 3: DATA — the base version. Replace all of it.

      SCREENS  [group, [ [id, name, note, spec], ... ] ]
      FLOWS    [group, [ [id, name, note, [ [stepName, stepNote, spec], ... ] ] ] ]
      ELEMENTS [group, [ [id, name, note, demoHTML], ... ] ]

      ids must be unique per view; they drive filtering and versioning.
      Notes are searchable, so put real reasoning in them.
      ================================================================== */
      /* Shared bodies, so a library looks the same everywhere it is drawn.
            Covers are face-out, not spines — `docs/mockups/library-shell/decided.html`.

            Four shelves, because that is what fits: the body is ~431px tall here
            and a shelf is ~103px, so a real visit shows four with the fourth
            cut off. Two shelves of tiny tiles was not a smaller library, it was
            a wrong one — and it left the emotional payoff screen 80% white. */
      const THEIR_LIB = [
        { t: "shelf", label: "소설", n: 5, seed: 0 },
        { t: "shelf", label: "에세이", n: 4, seed: 5 },
        { t: "shelf", label: "2026", n: 5, seed: 2 },
        { t: "shelf", label: "다시 읽기", n: 4, seed: 7 },
      ];
      const MY_LIB = [
        { t: "shelf", label: "읽는 중", n: 4, seed: 3 },
        { t: "shelf", label: "2026", n: 5, seed: 1 },
        { t: "shelf", label: "빌린 책", n: 4, seed: 6 },
        { t: "shelf", label: "언젠가", n: 5, seed: 4 },
      ];
      /* Shared so the confirm draws its own screen underneath rather than a
            second copy that can drift from it.

            No `push`: pinning the header to the top and the destructive action to
            the floor is what turned a short settings page into a framed 350px
            hole. Air below flowing content reads as a short page; air *between*
            two anchored things reads as a bug. Remove sits in its own group under
            the toggles, which is also where iOS Settings puts a destructive row. */
      const MANAGE_BODY = [
        {
          t: "hdr",
          emoji: "🦊",
          name: "지수",
          handle: "jisoo_reads",
          stats: [{ l: "Friends since", v: "Mar" }],
        },
        { t: "sect", v: "Notifications" },
        { t: "tog", v: "When they finish a book", on: true },
        { t: "tog", v: "When they start a book" },
        { t: "sect", v: "" },
        {
          t: "plrow",
          full: true,
          items: [{ l: "Remove friend", k: "dgrfill" }],
        },
        {
          t: "fine",
          v: "They will not get an alert.",
        },
      ];
      /* Shared with the "First launch" flow step, which was a stale copy of it:
            the step still pinned `Continue` to the floor after the screen stopped
            doing that, because a step carries its own spec and nothing connected
            the two. `verify.py` now walks steps as well as screens. */
      const CODE_BODY = [
        { t: "hero", v: "One last thing" },
        { t: "sect", v: "Have an invite code?" },
        { t: "fld", v: "<b>K7M2QP4X</b>" },
        { t: "hint", v: "Optional — you can invite friends later." },
        {
          t: "plrow",
          full: true,
          items: [{ l: "Continue", k: "brand" }],
        },
      ];
      /* Shared with flow step 01, which was `illus + hero + push + button` with
            no copy at all — a third stale duplicate of a screen, and one that got
            past the pin assertion precisely because it does carry a mark.

            The copy is rebuilt on Flighty's structure, which was doing more work
            than mine. Theirs enumerates three concrete capabilities, then spends a
            whole paragraph on one specific recurring annoyance it removes ("saves
            you from ever hearing 'Send me your flight info!' again"). Mine named
            two capabilities vaguely and then observed that shelves are nicer in
            pairs, which is a pleasant sentence that sells nothing. All three
            capabilities named here exist: the visit, the finished-books sheet, and
            praise — `book_compliments` is the app's only persisted social object. */
      /* Shared with every step that redraws them. Six duplicates have now drifted
            across three passes, always the same way: the screen gets fixed and the
            strip does not, because a step carries its own spec. `verify.py` asserts
            both the sharing and the "a headline must carry copy" rule that found
            the last three. */
      const CONSENT_BODY = [
        {
          t: "sduo",
          a: { e: "\u{1F98A}", n: "\uC9C0\uC218" },
          b: { e: "\u{1F525}", n: "YOU" },
        },
        { t: "hero", v: "\uC9C0\uC218 wants to share books with you" },
        {
          t: "text",
          v: "You'll both see what the other is reading and what you've finished, and you can react to each other's books.",
        },
        { t: "push" },
        {
          t: "fine",
          v: "You're in control. You can remove this friend at any time.",
        },
        {
          t: "plrow",
          full: true,
          items: [{ l: "Become friends", k: "brand" }],
        },
      ];
      /* Derived, not copied: the pending state differs from the screen in exactly
            one way — the button — so that is the only thing allowed to differ. The
            step used to draw the mark and a button and nothing else, which made the
            one moment where the user is waiting the emptiest frame in the flow. */
      const CONSENT_PENDING = [
        ...CONSENT_BODY.slice(0, -1),
        {
          t: "plrow",
          full: true,
          items: [{ l: "Becoming friends\u2026", k: "vary" }],
        },
      ];
      const DONE_BODY = [
        {
          t: "sduo",
          done: true,
          a: { e: "\u{1F98A}", n: "\uC9C0\uC218" },
          b: { e: "\u{1F525}", n: "YOU" },
        },
        { t: "hero", v: "You're now friends" },
        {
          t: "text",
          v: "You and \uC9C0\uC218 can see each other's shelves, what you're reading now, and what you've finished.",
        },
        { t: "push" },
        {
          t: "plrow",
          full: true,
          items: [{ l: "Done", k: "brand" }],
        },
        {
          t: "plrow",
          full: true,
          items: [{ l: "Notify me about \uC9C0\uC218", k: "out" }],
        },
      ];
      const INVITE_BODY = [
        {
          t: "illus",
          items: [
            { e: "\u{1F98A}", s: "READING", k: "now" },
            { e: "\u{1F423}", s: "24 READ" },
            { e: "\u{1F319}", s: "JUST JOINED", k: "new" },
          ],
        },
        { t: "hero", v: "Libstack friends" },
        {
          t: "text",
          v: "Send a link to anyone. You'll both see what the other is reading now, can browse each other's finished shelves, and can leave a reaction on any book.",
        },
        {
          t: "text",
          v: "It's free, and it saves you from screenshotting your shelf every time someone asks what you've been reading.",
        },
        {
          t: "fine",
          v: "Links last 48 hours and can be used up to 10 times. You can remove a friend at any time.",
        },
        { t: "push" },
        {
          t: "fine",
          code: true,
          v: "Or read them the code: <b>K7M2QP4X</b>",
        },
        {
          t: "plrow",
          full: true,
          items: [{ l: "Share invite", k: "brand" }],
        },
      ];
      /* Derived rather than copied. The strip is a review thumbnail, so it
         omits only the read-aloud fallback; both descriptive paragraphs and
         the expiry/removal contract remain. Every retained block is the exact
         object used by the full screen, so copy cannot drift between them. */
      const INVITE_FLOW_BODY = INVITE_BODY.filter((b) => !b.code);
      /* The cast, so no screen invents one. */
      const P_JISOO = { n: "지수", h: "jisoo_reads", e: "🦊" };
      const P_MINHO = { n: "민호", h: "minho", e: "🐣" };
      const P_HANA = { n: "하나", h: "hana_b", e: "🌙" };
      const ACCOUNT_ROWS_PRIVATE = {
        t: "rows",
        items: [{ t: "Email", v: "aschung1005@…" }],
      };

      const SCREENS = [
        [
          "Profile header",
          [
            [
              "header-now",
              "Profile &middot; today",
              "<b>Superseded.</b> Two numbers that a mutual model makes one number. Both are <code>GestureDetector</code>s opening <code>_FollowListSheet</code> at tab 0 or 1 (both gone; <code>settings_page.dart:577</code> is the one count that replaced them), so the labels, the tab indices and the <code>initialTab</code> plumbing retire together. The <code>@handle</code> line is current — it shipped just before this work.",
              {
                bar: { back: true, title: "" },
                tab: "Library",
                dim: true,
                body: [
                  {
                    t: "hdr",
                    name: "독서하는 유니콘",
                    handle: "unicorn_reads",
                    stats: [
                      { l: "Followers", v: "9" },
                      { l: "Following", v: "7" },
                    ],
                  },
                  {
                    t: "plrow",
                    full: true,
                    items: [{ l: "Edit profile", k: "vary" }],
                  },
                  { t: "sect", v: "Account" },
                  {
                    t: "rows",
                    items: [
                      { t: "Email", v: "aschung1005@…" },
                      {
                        t: "Allow profile search",
                        v: "On",
                      },
                    ],
                  },
                ],
              },
            ],
            [
              "header-next",
              "Profile &middot; one Friends stat",
              "One number, because under a mutual model there is only one. Tapping it opens a single list, so <code>_FollowListSheet</code> loses its <code>TabBar</code>, its <code>initialTab</code> and the 0/1 routing. <b>Allow profile search is gone too</b> — with no handle search there is nothing for it to gate. That row's survival is the version question; compare <code>public-profiles</code>.",
              {
                bar: { back: true, title: "" },
                tab: "Library",
                dim: true,
                body: [
                  {
                    t: "hdr",
                    name: "독서하는 유니콘",
                    handle: "unicorn_reads",
                    stats: [{ l: "Friends", v: "12" }],
                  },
                  {
                    t: "plrow",
                    full: true,
                    items: [{ l: "Edit profile", k: "vary" }],
                  },
                  { t: "sect", v: "Account" },
                  ACCOUNT_ROWS_PRIVATE,
                ],
              },
            ],
          ],
        ],
        [
          "Friends tab",
          [
            [
              "friends-list",
              "Friends &middot; the feed",
              "<b>No badge, because there is no queue.</b> The queue was never created by mutual friendship — it was created by handle search, and handle search is gone. The header icon is now unambiguously <i>Invite</i> rather than <i>Search friends</i>, which is what <code>friends_sheet.dart:152</code>'s tooltip now says. Rows lead to a visit; managing the relationship lives on its own screen.",
              {
                bar: { title: "My library", actions: ["👤"] },
                tab: "Friends",
                body: [
                  {
                    t: "shelf",
                    label: "읽는 중",
                    n: 4,
                    seed: 3,
                  },
                  {
                    t: "shelf",
                    label: "2026",
                    n: 5,
                    seed: 1,
                  },
                ],
                sheet: {
                  h: 62,
                  title: "Friends",
                  count: 12,
                  actions: ["✉"],
                  body: [
                    {
                      t: "people",
                      items: [
                        {
                          ...P_JISOO,
                          acts: [{ l: "24", k: "ghost" }],
                        },
                        {
                          ...P_MINHO,
                          acts: [{ l: "9", k: "ghost" }],
                        },
                        {
                          ...P_HANA,
                          acts: [{ l: "31", k: "ghost" }],
                        },
                      ],
                    },
                  ],
                },
              },
            ],
            [
              "friends-empty-none",
              "Friends &middot; empty, no friends",
              "Today this is a dead end: <code>_Empty(message: l10n.noFriendsYet)</code> at <code>friends_sheet.dart:163</code>, whose only escape is the header icon. With invite links as the sole path in, the empty state <i>must</i> carry the invite action or a new user has nothing to do. Flighty's equivalent does exactly this.",
              {
                bar: { title: "My library", actions: ["👤"] },
                tab: "Friends",
                body: [
                  {
                    t: "shelf",
                    label: "읽는 중",
                    n: 4,
                    seed: 3,
                  },
                  {
                    t: "shelf",
                    label: "2026",
                    n: 5,
                    seed: 1,
                  },
                ],
                sheet: {
                  h: 62,
                  title: "Friends",
                  count: 0,
                  actions: ["✉"],
                  body: [
                    {
                      t: "hint",
                      v: "No friends yet. Send someone an invite link and you'll both see what the other is reading.",
                    },
                    {
                      t: "plrow",
                      full: true,
                      items: [
                        {
                          l: "Invite a friend",
                          k: "brand",
                        },
                      ],
                    },
                  ],
                },
              },
            ],
            [
              "friends-empty-quiet",
              "Friends &middot; nobody reading (rejected)",
              "<b>Not built — and the reason is visible in this very frame.</b> Stolen from Flighty, which has two empty states where I had drawn one: friends exist but none are mid-book, which for a reading app is the <i>common</i> state, not the edge case. All of that still holds. What does not is the premise underneath it. <b>Flighty's row reports a flight status; the row above reports a read count</b> — neither says whether the person is reading <i>right now</i>, so a banner is the only thing that can. Libstack's shipped row prints <code>friendNothingInProgress</code> on its own second line, so with three idle friends the sheet said it four times: once per row, then again in a summary of the rows directly beneath it. A summary earns its place when it tells you something the list does not, and this one could not — nor could it offer an action, since inviting is not the fix for friends between books. <b>The state survives; the banner does not.</b> Note the rows drawn here carry <code>24</code> and <code>9</code> and no subtitle, which is exactly the row this screen was designed against.",
              {
                bar: { title: "My library", actions: ["👤"] },
                tab: "Friends",
                body: [
                  {
                    t: "shelf",
                    label: "읽는 중",
                    n: 4,
                    seed: 3,
                  },
                  {
                    t: "shelf",
                    label: "2026",
                    n: 5,
                    seed: 1,
                  },
                ],
                sheet: {
                  h: 62,
                  title: "Friends",
                  count: 12,
                  actions: ["✉"],
                  body: [
                    {
                      t: "hint",
                      v: "Nobody's mid-book right now. Their finished shelves are still here — tap anyone to look.",
                    },
                    {
                      t: "people",
                      items: [
                        {
                          ...P_JISOO,
                          acts: [{ l: "24", k: "ghost" }],
                        },
                        {
                          ...P_MINHO,
                          acts: [{ l: "9", k: "ghost" }],
                        },
                      ],
                    },
                  ],
                },
              },
            ],
          ],
        ],
        [
          "Inviting",
          [
            [
              "invite-sheet",
              "Invite &middot; create and share",
              "<b>Rebuilt after looking at Flighty's invite sheet properly.</b> Mine showed a URL in a field and a Share button — an administrative screen for what is actually the app's only growth surface. Flighty shows <i>no link and no code</i>: it shows a globe carrying three friends' flights, each with a live status pill (DELAYED / LANDED / IN 8H 55M), then two paragraphs where the second is the emotional one — <i>'saves you from ever hearing \"Send me your flight info!\" again'</i>. The sheet sells the payoff. <b>The reading analogue is a shelf</b>, and the status this app actually reports is what someone is reading and how much they have finished. 48h and a use cap are Flighty's numbers, stated on their sheet. <b>One deliberate divergence:</b> the code stays, demoted below the button — they have no typed fallback and we do, so a sender may need to read it aloud. <b>Second pass on both the mark and the copy.</b> The mark drew two blank rectangles per friend, which against Flighty's rendered globe is the reading equivalent of a grey box; each friend is now a real shelf of covers on a plank, drawn with the same <code>.bk</code> the library uses, sized at <code>kGeneratedCoverMinWidth</code> so the covers carry titles. The copy was two thin sentences: theirs names three concrete capabilities and then spends a paragraph on one specific annoyance it removes, so this now does the same — the visit, the finished shelves, praise, then the screenshot habit it replaces.",
              {
                bar: { actions: ["✕"] },
                tabs: false,
                body: INVITE_BODY,
              },
            ],
            [
              "invite-consent",
              "Invite &middot; the consent screen",
              "<b>The screen this redraw exists for, and where the one deliberate risk is spent.</b> Full-screen, because accepting grants someone access to your library and that cannot be explained on a 12pt pill in an app bar. <b>There is no Decline button</b> — the <code>✕</code> is the refusal, which is Flighty's exact structure. But not Flighty's <i>image</i>: they draw two portraits joined by a flight path because a flight is what they share. Libstack's subject is a <b>stack</b> — it is the name, and <code>assets/branding/app_icon.svg</code> is fanned covers — so what meets here is two libraries, one in <code>surfaceVariant</code> and one washed in brand green, interleaving at the seam. The headline is the app's only serif token (<code>AppTextStyles.title</code>, GowunBatang), which is the one place its voice shows.",
              {
                bar: { actions: ["✕"] },
                tabs: false,
                body: CONSENT_BODY,
              },
            ],
            [
              "invite-done",
              "Invite &middot; now friends",
              "<b>A screen I had missed entirely until looking at Flighty's flow properly.</b> They confirm the connection on its own screen — the two portraits with a green check dropped between them, 'You're Now Sharing Flights' — and then use the moment for something useful: an outlined <i>Customize Alerts for This Friend</i> beside <b>Done</b>. Both this screen and the step that redraws it now share one body, as do the consent screen and its three steps — including the pending one, which drew the mark and a button and no words at all, leaving the single moment where the user is actually waiting as the emptiest frame in the flow. That is the best possible introduction to per-friend settings, because it arrives exactly when you have just thought about this specific person. It also settles the open question on <code>manage-friend</code>: the notification toggles have a reason to exist if this is where they are first offered.",
              {
                bar: false,
                tabs: false,
                body: DONE_BODY,
              },
            ],
            [
              "invite-code",
              "Invite &middot; the code floor",
              "<b>The tier that makes the loop reliable, and the one no vendor sells.</b> Pre-filled from the clipboard when readable, typed when not. 8 characters from an alphabet without <code>O/0/I/1</code>. This is what works when the iOS paste prompt is declined, when Kakao's in-app webview swallows the Universal Link, and when someone reads the code aloud. <b>Continue with the field empty is the skip</b> — that is what 'optional' means here, and it is why there is no second action to draw. A Skip button beside Continue would only make it ambiguous which one declines. <b>No longer pinned to the floor:</b> it was, under 380px of white, and unlike the three sheets before it this screen has no mark to fill that space — so the pin framed the emptiness rather than using it.",
              {
                bar: false,
                tabs: false,
                body: CODE_BODY,
              },
            ],
            [
              "invite-dead",
              "Invite &middot; link no longer valid",
              "Expired, revoked and exhausted are told apart, because the recovery differs: two mean <i>ask for a new link</i> and one means <i>you already used this</i>. <b>And with search gone there is no fallback action to offer</b> — the old draft said 'add by handle instead', which no longer exists. All this screen can honestly do is explain and get out of the way, so it now does that from the top instead of pinning the way out to the floor. <b>Nothing here earns an illustration:</b> an error screen that draws a picture of itself is asking to be admired for failing.",
              {
                bar: { actions: ["✕"] },
                tabs: false,
                body: [
                  { t: "hero", v: "This link has expired" },
                  {
                    t: "hint",
                    v: "Invite links last 48 hours. Ask 지수 to send you a new one.",
                  },
                  {
                    t: "plrow",
                    full: true,
                    items: [
                      {
                        l: "Continue to my library",
                        k: "vary",
                      },
                    ],
                  },
                ],
              },
            ],
          ],
        ],
        [
          "A friend's library",
          [
            [
              "their-library",
              "Friend &middot; visiting",
              "The only relationship state that can exist on this page now: you are friends, or you could not be here. Two of the four states I drew last round (<code>outgoing</code>, <code>incoming</code>) are gone with the queue, and <code>none</code> is unreachable. And the friend-navigation redesign settled what this bar is: <code>✕</code>, the friend's library as the title, and Poke as a <code>brandFill</code> pill (<code>home_page.dart:834</code>, contract at <code>:820</code>, pill at <code>:1094-1112</code>, gear at <code>:1067-1093</code>). <b>The gear is new, and it is where managing a friend now starts.</b> An earlier draft said there was nowhere on this bar for a relationship affordance and put the action on a long press instead; that was wrong twice over — the bar's trailing group takes two items perfectly well, and a long press that nothing advertises is not an affordance at all. <b>Corrected: the tab bar stays up.</b> This was drawn without one, on the strength of a note claiming <code>shellBarVisibleProvider</code> goes false while a friend is selected — <code>shell_chrome_provider.dart:56-62</code> says that behaviour existed and was deliberately removed, because no tab changes meaning inside a visit, and selecting Library or Card is how you leave. So Friends stays lit and the bar is the way out. The hardcoded <code>width: 104</code> that used to sit in <code>user_library_page.dart</code> stopped being a problem to solve and became a file to delete: the page is gone, and a friend's library is a visit inside the shell.",
              {
                bar: { visit: true, title: "지수's Library" },
                tab: "Friends",
                body: THEIR_LIB,
              },
            ],
          ],
        ],
        [
          "Managing a friend",
          [
            [
              "manage-friend",
              "Manage friend",
              "Split out from the feed rows after seeing Flighty's <i>Manage Friend</i> screen. A feed row is for reading, not for administering a relationship. <b>Reached by the gear in the visit app bar</b>, beside Poke. It was drawn on a long press of the Friends row — a real gesture (<code>friends_sheet.dart:408</code>, inherited from the deleted <code>FriendRail</code>) but an invisible one, and reusing an existing gesture is not the same as advertising an action. <b>Rejected: the gear in her sheet header.</b> <code>home_page.dart:209-214</code> already declined a back control there because it &quot;costs no pixels in a header that has a title, a count and a year control in it&quot;, and said the point is that it &quot;leaves her read view identical to your own&quot;; <code>finished_books_sheet.dart:132-137</code> measures the slack at 5.8px and <code>test/library_clearance_test.dart</code> guards it at 2x. The app bar is the friend-level chrome — <code>✕</code>, her name, Poke all act on the person — so the gear joins a group it belongs to. This screen replaces that dialog, and with it <b>two</b> confirms with different button labels — No/Unfollow on the deleted <code>user_library_page.dart</code> and Cancel/Confirm in the deleted <code>friend_info_dialog.dart</code>; both files are gone, and <code>manage_friend_page.dart:198-207</code> is the one confirm left. <b>Note the ground moved under this while it was being drawn:</b> the friend-navigation redesign landed (2026-08-22), deleting <code>friend_rail.dart</code> and migrating its dialog to <code>dialogs/friend_info_dialog.dart</code>, which still carries both Followers/Following counts. All line numbers here were re-checked against the working tree, not the last commit. <b>Deliberately omitted:</b> Flighty's per-friend sharing toggle — see <code>el-toggle</code>.",
              {
                bar: { back: true, title: "Manage friend" },
                tabs: false,
                body: MANAGE_BODY,
              },
            ],
            [
              "manage-remove",
              "Manage friend &middot; remove confirm",
              "Copy taken almost directly from Flighty, whose version is better than mine was: I had 'you will both lose access', they add <b>'They will not get an alert.'</b> Telling you that removal is silent is what stops someone hesitating over it. One <code>DELETE</code> on the canonical row severs both directions at once — the half-friendship the current schema cannot detect stops being expressible. <b>Redrawn as the alert the app actually uses.</b> This was a full-screen page with the destructive button on the floor, which was wrong twice over: both confirms it replaced were <code>AlertDialog.adaptive</code>, and so is the one that replaces them (<code>manage_friend_page.dart:195</code>), and a full screen for a two-line question left 350px of white framed between a header and a floor button — the worst dead zone on this page. The native alert also settles the button-label question for free: iOS puts Cancel first and the destructive action second, in red and unbolded, so the No/Unfollow versus Cancel/Confirm split disappears into the platform.",
              {
                bar: { back: true, title: "Manage friend" },
                tabs: false,
                body: MANAGE_BODY,
                alert: {
                  title: "Remove 지수?",
                  msg: "Access to each other's libraries will be revoked for both of you. They will not get an alert.",
                  actions: [{ l: "Cancel" }, { l: "Remove", k: "dgr" }],
                },
              },
            ],
          ],
        ],
      ];

      const FLOWS = [
        [
          "Invites",
          [
            [
              "invite-installed",
              "Invite &middot; recipient already has the app",
              "The common case once you have a base, and fully deterministic — <b>once it exists</b>. None of this is wired today: <code>app_links</code> is not a dependency, <code>Runner.entitlements</code> carries no <code>associated-domains</code>, and Android has only the <code>bookworm-friends://</code> custom scheme (<code>AndroidManifest.xml:42</code>), no verified App Link. So this strip draws the tier that needs the most new plumbing, not the least. <b>Nothing here depends on push</b> — which is why invite-only can ship before the FCM v1 migration, and a request queue could not.",
              [
                [
                  "Invite sheet",
                  "Sells the payoff, not the link: three friends' shelves, each carrying the status this app actually reports. <b>Same body as the <code>invite-sheet</code> screen</b> — this step used to be a copy of it with the copy left out.",
                  {
                    sm: true,
                    bar: { actions: ["✕"] },
                    tabs: false,
                    body: INVITE_FLOW_BODY,
                  },
                ],
                [
                  "Tapped in KakaoTalk",
                  "The link preview is the whole tier: an unbranded URL in a group chat does not get tapped, so the card has to carry the inviter's name and show a shelf. <b>There is no button on this screen</b> — the card is the tap, and drawing an 'Open in app' CTA on somebody else's chat was inventing a control Kakao does not give us. What we do control is the OG tags the landing page serves, which is why this frame exists at all.",
                  {
                    sm: true,
                    bar: false,
                    tabs: false,
                    body: [
                      {
                        t: "chat",
                        who: "독서 모임",
                        e: "🦊",
                        msgs: [
                          "나 이거 쓰고 있는데 같이 볼래?",
                          "libstack.app/i/K7M2QP4X",
                        ],
                        card: {
                          t: "지수 invited you to Libstack",
                          d: "See what each other is reading, and what you've finished.",
                          h: "libstack.app",
                        },
                      },
                    ],
                  },
                ],
                [
                  "Consent",
                  "Full screen, one button, ✕ to refuse.",
                  {
                    sm: true,
                    bar: { actions: ["✕"] },
                    tabs: false,
                    body: CONSENT_BODY,
                  },
                ],
                [
                  "Accepting",
                  "Redemption writes a friendship, so the button holds a pending state rather than the screen flashing.",
                  {
                    sm: true,
                    bar: { actions: ["✕"] },
                    tabs: false,
                    body: CONSENT_PENDING,
                  },
                ],
                [
                  "Now friends",
                  "Confirmed on its own screen — and the one good moment to offer per-friend notifications.",
                  {
                    sm: true,
                    bar: false,
                    tabs: false,
                    body: DONE_BODY,
                  },
                ],
                [
                  "Their shelves",
                  "Done lands on their library — ✕ / title / Poke, no tab bar.",
                  {
                    sm: true,
                    bar: {
                      visit: true,
                      title: "지수's Library",
                    },
                    tab: "Friends",
                    body: [
                      {
                        t: "shelf",
                        label: "소설",
                        n: 5,
                        seed: 0,
                      },
                      {
                        t: "shelf",
                        label: "에세이",
                        n: 4,
                        seed: 5,
                      },
                      {
                        t: "shelf",
                        label: "2026",
                        n: 5,
                        seed: 2,
                      },
                    ],
                  },
                ],
              ],
            ],
            [
              "invite-deferred",
              "Invite &middot; recipient has to install",
              "The growth case, and the only genuinely hard tier. Android is deterministic through the Play Install Referrer; iOS uses clipboard-on-tap; the typed code is the floor under both. <b>Probabilistic IP matching is deliberately omitted</b> — it is the fastest-degrading part of the vendor offering, and Korean carrier NAT makes it worse than average.",
              [
                [
                  "Landing page",
                  "'Get the app' copies the token inside the click handler, then redirects — the copy has to happen in the same user gesture or Safari drops it. <b>Drawn, not designed:</b> the page itself is being built separately, so this frame commits only to what the invite tier depends on — the inviter named, the payoff shown, and a way past the copy for anyone who declines the paste prompt.",
                  {
                    sm: true,
                    bar: false,
                    tabs: false,
                    body: [
                      {
                        t: "sduo",
                        a: { e: "🦊", n: "지수" },
                        b: { e: "🔥", n: "YOU" },
                      },
                      {
                        t: "hero",
                        v: "지수 invited you",
                      },
                      {
                        t: "text",
                        v: "Libstack is a shelf you can show someone. See what each other is reading, and what you've finished.",
                      },
                      { t: "push" },
                      {
                        t: "fine",
                        v: "Your code is <b>K7M2QP4X</b> — we'll fill it in for you.",
                      },
                      {
                        t: "plrow",
                        full: true,
                        items: [
                          {
                            l: "Get the app",
                            k: "brand",
                          },
                        ],
                      },
                      {
                        t: "link",
                        v: "Continue without copying",
                      },
                    ],
                  },
                ],
                [
                  "Store",
                  "A campaign token on the redirect gives free install counts by source — <code>pt</code>/<code>ct</code> on the App Store, <code>referrer</code> on Play, which is the same parameter Android later reads back to recover the token. The screenshot strip is drawn because it is the only place the listing shows the shelf, and the shelf is the product.",
                  {
                    sm: true,
                    bar: false,
                    tabs: false,
                    body: [
                      {
                        t: "store",
                        e: "📚",
                        name: "Libstack",
                        sub: "A shelf you can show someone",
                        cta: "GET",
                      },
                    ],
                  },
                ],
                [
                  "First launch",
                  "Clipboard on iOS, Install Referrer on Android, typed if both fail. Same body as the <code>invite-code</code> screen, not a copy of it.",
                  {
                    sm: true,
                    bar: false,
                    tabs: false,
                    body: CODE_BODY,
                  },
                ],
                [
                  "Consent, then a populated app",
                  "A first screen with a real library in it, instead of the empty state.",
                  {
                    sm: true,
                    bar: {
                      visit: true,
                      title: "지수's Library",
                    },
                    tab: "Friends",
                    body: [
                      {
                        t: "shelf",
                        label: "소설",
                        n: 5,
                        seed: 0,
                      },
                      {
                        t: "shelf",
                        label: "에세이",
                        n: 4,
                        seed: 5,
                      },
                      {
                        t: "shelf",
                        label: "2026",
                        n: 5,
                        seed: 2,
                      },
                    ],
                  },
                ],
              ],
            ],
            [
              "invite-refused",
              "Invite &middot; dismissed rather than accepted",
              "<b>Worth drawing because it is the state with no button.</b> Dismissal is the decline, so nothing is written, no row is created, and — importantly — <code>used_count</code> is <i>not</i> incremented, so the inviter's link is not silently consumed by someone who changed their mind. The inviter is never told, which is the same silence Flighty chose for removal.",
              [
                [
                  "Consent",
                  "The only affirmative is the button; ✕ is the other answer.",
                  {
                    sm: true,
                    bar: { actions: ["✕"] },
                    tabs: false,
                    body: CONSENT_BODY,
                  },
                ],
                [
                  "Dismissed",
                  "Lands in their own library. No friendship, no record, link still valid.",
                  {
                    sm: true,
                    bar: { title: "My library" },
                    tab: "Library",
                    body: MY_LIB,
                  },
                ],
              ],
            ],
          ],
        ],
        [
          "Leaving",
          [
            [
              "remove-friend",
              "Removing a friend",
              "One path, from the visit's gear through Manage friend, replacing two dialogs with different labels that were reachable only by a long press nothing advertised. The eviction at the end is <code>home_page.dart:502-513</code>, which already clears a selected friend who has left the list — but under a mutual model it can now fire because <b>they</b> removed <b>you</b>, a case that could never happen before.",
              [
                [
                  "Tap the gear",
                  "In the visit bar, beside Poke. Was a long press on the Friends row, which nothing advertised.",
                  {
                    sm: true,
                    bar: {
                      visit: true,
                      title: "지수's Library",
                    },
                    tab: "Friends",
                    body: [
                      {
                        t: "shelf",
                        label: "소설",
                        n: 5,
                        seed: 0,
                      },
                      {
                        t: "shelf",
                        label: "에세이",
                        n: 4,
                        seed: 5,
                      },
                      {
                        t: "shelf",
                        label: "2026",
                        n: 5,
                        seed: 2,
                      },
                    ],
                  },
                ],
                [
                  "Manage friend",
                  "The gear opens it. Same body as the screen, so the two cannot drift.",
                  {
                    sm: true,
                    bar: {
                      back: true,
                      title: "Manage friend",
                    },
                    tabs: false,
                    body: MANAGE_BODY,
                  },
                ],
                [
                  "Confirm",
                  "The app's own <code>AlertDialog.adaptive</code>, over the screen it acts on. Cancel first, the destructive action second and red, as iOS orders them.",
                  {
                    sm: true,
                    bar: {
                      back: true,
                      title: "Manage friend",
                    },
                    tabs: false,
                    body: MANAGE_BODY,
                    alert: {
                      title: "Remove 지수?",
                      msg: "Access to each other's libraries will be revoked for both of you. They will not get an alert.",
                      actions: [{ l: "Cancel" }, { l: "Remove", k: "dgr" }],
                    },
                  },
                ],
                [
                  "Back to your own",
                  "Same eviction runs if they removed you mid-visit.",
                  {
                    sm: true,
                    bar: { title: "My library" },
                    tab: "Library",
                    body: MY_LIB,
                  },
                ],
              ],
            ],
          ],
        ],
      ];

      const ELEMENTS = [
        [
          "Consent",
          [
            [
              "el-consent",
              "The consent moment",
              "<b>Why full-screen and not a pill.</b> Accepting grants access to your library, so the screen has to name both people, state the consequence, and pre-answer 'can I undo this'. None of that fits in an app-bar button — which is what my first draft tried. <b>No Decline button:</b> dismissal is the refusal, so the screen has exactly one thing to press. The mark is two libraries interleaving rather than two portraits: it is the brand's own subject, and it says what is actually being merged.",
              `<div class="fr" style="width:190px;height:auto;border:0;background:#fff;padding:8px 9px;border-radius:8px">${block(
                {
                  t: "sduo",
                  a: { e: "🦊", n: "지수" },
                  b: { e: "🔥", n: "YOU" },
                },
              )}${block({ t: "hero", v: "지수 wants to share books with you" })}${block({ t: "plrow", full: true, items: [{ l: "Become friends", k: "brand" }] })}${block({ t: "fine", v: "You're in control. You can remove this friend at any time." })}</div>`,
            ],
            [
              "el-destructive",
              "Destructive confirm",
              "<b>Two objects, not one — and that split is the point.</b> The <i>row</i> lives on <code>manage-friend</code>: light red fill, red text, full width, never side by side with a green button. The <i>copy</i> moved into the alert, because the app confirms destructive things with <code>AlertDialog.adaptive</code> (<code>manage_friend_page.dart:195</code>) and an alert is where a consequence is stated. Drawing both together, as this demo does, is what exposed the earlier mistake: a fill button and a sentence explaining it were being drawn on the same full screen, which is a confirm pretending to be a page. What survives unchanged is the sentence. It states <i>both</i> facts — access is revoked mutually, and the other person is not told — and the second half is Flighty's, which is the half that stops people hesitating.",
              `<div class="fr" style="width:190px;height:auto;border:0;background:#fff;padding:8px 9px;border-radius:8px">${block({ t: "text", v: "Access will be revoked for both of you. They will not get an alert." })}${block({ t: "plrow", full: true, items: [{ l: "Remove friend", k: "dgrfill" }] })}</div>`,
            ],
          ],
        ],
        [
          "Chrome",
          [
            [
              "el-friendstat",
              "One stat, not two",
              "Under a mutual model Followers and Following are the same number, so the header states it once. Deleting the pair also removes two <code>.count()</code> round trips — the dialog that fired them on every long press is deleted, and <code>settings_page.dart:577</code> now states the one number.",
              `<div class="fr" style="width:190px;height:auto;border:0;background:#fff;padding:8px 9px;border-radius:8px">${block({ t: "hdr", name: "독서하는 유니콘", handle: "unicorn_reads", stats: [{ l: "Friends", v: "12" }] })}</div>`,
            ],
            [
              "el-prow",
              "Person row",
              "One primitive for the friends list and the roster. Carries the <code>@handle</code> even though search is gone, because two friends can share a display name — 40 of 136 profiles are auto-generated 독서하는 + hex, so collisions are the norm rather than the exception.",
              `<div class="fr" style="width:190px;height:auto;border:0;background:#fff;padding:6px 9px;border-radius:8px">${block(
                {
                  t: "people",
                  items: [
                    {
                      n: "지수",
                      h: "jisoo_reads",
                      e: "🦊",
                      acts: [{ l: "24", k: "ghost" }],
                    },
                    {
                      n: "민호",
                      h: "minho",
                      e: "🐣",
                      acts: [{ l: "9", k: "ghost" }],
                    },
                  ],
                },
              )}</div>`,
            ],
          ],
        ],
        [
          "Invites",
          [
            [
              "el-code",
              "Invite code field",
              "8 characters, alphabet without <code>O/0/I/1</code>. Pre-filled from the clipboard when readable. The tier that makes the loop reliable, and the one no link vendor sells.",
              `<div class="fr" style="width:190px;height:auto;border:0;background:#fff;padding:8px 9px;border-radius:8px">${block({ t: "sect", v: "Have an invite code?" })}${block({ t: "fld", v: "<b>K7M2QP4X</b>" })}</div>`,
            ],
            [
              "el-toggle",
              "Per-friend sharing toggle &mdash; not built",
              "<b>Recorded as a decision, not a component.</b> Flighty's Manage Friend has a 'Share My Flights' switch that can be off <i>while you are still friends</i>, so friendship and visibility are separable per direction. A shipped product in this shape found that necessary — but flights are near-real-time location and a finished-books list is not, and it would re-introduce the exact per-direction asymmetry this whole design removes. Would need a flag per direction on the friendship row. Revisit only if people ask.",
              `<div class="fr" style="width:190px;height:auto;border:0;background:#fff;padding:6px 9px;border-radius:8px;opacity:.45">${block({ t: "tog", v: "Share my library", on: true })}${block({ t: "tog", v: "Share my reactions" })}</div>`,
            ],
          ],
        ],
      ];

      /* Mark an id as an unresolved decision; renders inline as a red callout. */
      const OPEN = {
        "header-next":
          "<b>Open, and the biggest one left:</b> does public-by-default survive? Today <code>is_profile_visible()</code> grants access on <code>is_private = false</code> <i>before</i> checking any relationship — and with <code>auth.uid()</code> null that means an anonymous caller can read every non-private user's whole library. If the new rule is friends-only, <code>is_private</code> and the Allow-profile-search row both become vestigial and nobody can browse a stranger's shelves at all. Compare the <code>public-profiles</code> version.",
        "invite-consent":
          "Open: is the inviter told when someone redeems? It closes the loop and is the one notification this design would actually need — which also means it is the one thing still blocked on the FCM v1 migration.",
        "manage-friend":
          "<b>Narrowed, not closed.</b> The toggles were speculative until <code>invite-done</code> gave them a reason: Flighty offers per-friend alerts at the moment the friendship lands, which is the one time you are thinking about that specific person. Still open is whether they ship in Phase 1 at all — there is no per-friend notification preference anywhere in the app today, and the only push that exists is <code>poke</code>, which is itself unauthenticated. If they slip, this screen is identity plus Remove and <code>invite-done</code> loses its secondary button.",
      };

      /* ==================================================================
      SECTION 4: VERSIONS — named variants, git-branch style.

        [id, label, note, parentId, patch]

      The first entry is the root and must have parentId null; its data is
      SECTION 3 above. Every other version stores ONLY a patch over its
      parent, so unchanged screens stay defined once. That is what keeps
      versions from drifting, and it lets the page compute what changed.

      patch = {
        screens:  { id: {spec, name?, note?, group?} | null },
        flows:    { id: {steps, name?, note?, group?} | null },
        elements: { id: {demo, name?, note?, group?} | null },
        open:     { id: 'callout text' | null }
      }

      null removes. An id not present in the parent is an addition (give it
      a `group`, or it lands in "Added in <label>").

      To retire versioning entirely, leave just the root entry — the
      selector hides itself when there is only one version.
      ================================================================== */
      const VERSIONS = [
        [
          "friends-only",
          "friends-only",
          "Recommended. Visibility is gated on friendship, so nobody can browse a stranger's shelves. `is_private` and the Allow-profile-search row retire, because with no search there is nothing left for them to gate.",
          null,
          {},
        ],

        [
          "public-profiles",
          "public-profiles",
          "Alternative: public-by-default survives, as it works today. Non-private libraries stay readable — but with handle search gone, nothing inside the app links to one, so the reachable surface is web and deep links only.",
          "friends-only",
          {
            screens: {
              "header-next": {
                note: "Allow profile search survives, but it no longer describes what it does: there is no search to allow. It would have to be renamed to something like <i>Let anyone view my library</i>, because that is the switch it actually is once search is gone.",
                spec: {
                  bar: { back: true, title: "" },
                  tab: "Library",
                  dim: true,
                  body: [
                    {
                      t: "hdr",
                      name: "독서하는 유니콘",
                      handle: "unicorn_reads",
                      stats: [{ l: "Friends", v: "12" }],
                    },
                    {
                      t: "plrow",
                      full: true,
                      items: [
                        {
                          l: "Edit profile",
                          k: "vary",
                        },
                      ],
                    },
                    { t: "sect", v: "Account" },
                    {
                      t: "rows",
                      items: [
                        {
                          t: "Email",
                          v: "aschung1005@…",
                        },
                        {
                          t: "Let anyone view my library",
                          v: "On",
                        },
                      ],
                    },
                  ],
                },
              },
              "stranger-library": {
                group: "A friend's library",
                name: "Stranger &middot; public library",
                note: "Only exists in this version. <code>UserLibraryPage</code> exists for the case a visit cannot serve — a person who is not a friend — and with search deleted, <b>this version is the only thing keeping that page alive.</b> Note there is no action available: you cannot add them, so the bar carries nothing. A page you can reach but do nothing on is a strong argument for the friends-only version.",
                spec: {
                  bar: { back: true, title: "하나" },
                  tabs: false,
                  body: THEIR_LIB,
                },
              },
            },
            open: {
              "stranger-library":
                "Open: if this page survives, <b>how is it reached?</b> Search is gone. The remaining candidates are a reaction from a non-friend on one of your books, and a shared library-card link — both narrow. If neither is worth keeping, <code>UserLibraryPage</code> can be deleted outright, which is the single largest simplification available in this phase.",
            },
          },
        ],
      ];

      /* ==================================================================
      SECTION 5: ENGINE — behaviour is load-bearing.
      See reference/pitfalls.md in this skill before changing it.
      ================================================================== */
      function stripTags(s) {
        return String(s)
          .replace(/<[^>]*>/g, "")
          .replace(/&[a-z]+;/g, " ");
      }
      /* Every query term must appear somewhere (order-independent AND), so
      "cover book" finds "Book cover". Haystack must be pre-lowercased. */
      function matchWords(haystack, query) {
        return query
          .trim()
          .toLowerCase()
          .split(/\s+/)
          .filter(Boolean)
          .every((t) => haystack.includes(t));
      }
      function escapeReg(s) {
        return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      }
      function highlightText(text, query) {
        const terms = query.trim().split(/\s+/).filter(Boolean).map(escapeReg);
        if (!terms.length) return text;
        return text.replace(
          new RegExp(`(${terms.join("|")})`, "gi"),
          '<mark class="hl">$1</mark>',
        );
      }
      /** Every string *value* inside a screen spec.
       *
       * Added because the search index was names, groups, notes and step
       * captions only — so copy the reader can plainly see on a drawn
       * frame ("They will not get an alert") matched nothing. That is the
       * exact pitfall the shell's own reference documents.
       *
       * **Values, not keys.** Indexing keys would make `t`, `v`, `l` and
       * `k` match every flow. Note that a match found only in spec text
       * highlights nothing visible, since `highlightText` runs over the
       * name and caption — a hit with no highlight is still better than a
       * reader concluding the page is broken.
       */
      function specText(v) {
        if (typeof v === "string") return v;
        if (Array.isArray(v)) return v.map(specText).join(" ");
        if (v && typeof v === "object")
          return Object.values(v).map(specText).join(" ");
        return "";
      }
      function flowSearchText(g, nm, ds, steps) {
        return stripTags(
          [
            nm,
            g,
            ds,
            steps
              .map(([sn, sc, sp]) => `${sn} ${sc} ${specText(sp)}`)
              .join(" "),
          ].join(" "),
        )
          .toLowerCase()
          .replace(/["&<>]/g, " ")
          .replace(/\s+/g, " ")
          .trim();
      }

      /* ---- version resolution ---------------------------------------- */
      const VMAP = new Map(VERSIONS.map((v) => [v[0], v]));
      const VROOT = VERSIONS[0][0];

      function chainOf(vid) {
        const out = [];
        let cur = vid;
        const seen = new Set();
        while (cur && VMAP.has(cur) && !seen.has(cur)) {
          seen.add(cur);
          out.unshift(cur);
          cur = VMAP.get(cur)[3];
        }
        return out;
      }
      /* payload key per view: what a patch entry carries */
      const PAYLOAD = {
        screens: "spec",
        flows: "steps",
        elements: "demo",
      };

      /** Resolve one view for a version into [group, [[id,nm,ds,payload],...]]. */
      function resolveView(vid, kind) {
        const base =
          kind === "screens" ? SCREENS : kind === "flows" ? FLOWS : ELEMENTS;
        // flat map of id -> {group,nm,ds,payload}, preserving group order
        const groups = base.map(([g]) => g);
        const items = new Map();
        base.forEach(([g, list]) =>
          list.forEach(([id, nm, ds, payload]) =>
            items.set(id, { group: g, nm, ds, payload }),
          ),
        );

        for (const step of chainOf(vid).slice(1)) {
          const patch = (VMAP.get(step)[4] || {})[kind] || {};
          for (const [id, val] of Object.entries(patch)) {
            if (val === null) {
              items.delete(id);
              continue;
            }
            const prev = items.get(id);
            const group =
              val.group || prev?.group || `Added in ${VMAP.get(step)[1]}`;
            if (!groups.includes(group)) groups.push(group);
            items.set(id, {
              group,
              nm: val.name ?? prev?.nm ?? id,
              ds: val.note ?? prev?.ds ?? "",
              payload: val[PAYLOAD[kind]] ?? prev?.payload,
            });
          }
        }
        return groups
          .map((g) => [
            g,
            [...items.entries()]
              .filter(([, v]) => v.group === g)
              .map(([id, v]) => [id, v.nm, v.ds, v.payload]),
          ])
          .filter(([, l]) => l.length);
      }
      function resolveOpen(vid) {
        let out = { ...OPEN };
        for (const step of chainOf(vid).slice(1)) {
          const patch = (VMAP.get(step)[4] || {}).open || {};
          for (const [id, val] of Object.entries(patch))
            val === null ? delete out[id] : (out[id] = val);
        }
        return out;
      }
      /** id -> 'changed' | 'onlyHere' | 'onlyThere', reading a against b. */
      function diffMap(a, b, kind) {
        const A = new Map(),
          B = new Map();
        resolveView(a, kind).forEach(([, l]) =>
          l.forEach((it) => A.set(it[0], it)),
        );
        resolveView(b, kind).forEach(([, l]) =>
          l.forEach((it) => B.set(it[0], it)),
        );
        const out = new Map();
        for (const [id, it] of A) {
          if (!B.has(id)) out.set(id, "onlyHere");
          else if (JSON.stringify(it[3]) !== JSON.stringify(B.get(id)[3]))
            out.set(id, "changed");
        }
        for (const id of B.keys()) if (!A.has(id)) out.set(id, "onlyThere");
        return out;
      }

      let activeV = VROOT,
        compareV = null,
        onlyDiff = false;
      let view = "screens",
        cbOpen = false,
        kbIndex = -1,
        kbId = null,
        vbOpen = false,
        vkbIndex = -1,
        vkbId = null;
      const sel = { screens: new Set(), elements: new Set() };

      /**
       * One list per group of entries to draw, for the active version.
       *
       * In compare mode this also emits "ghost" entries for items the
       * compared version has and the active one doesn't. Without them a
       * removal is invisible: render only walks the active version, so a
       * deleted screen just silently isn't there.
       */
      function viewModel(kind) {
        const A = resolveView(activeV, kind);
        const cmp = compareV && compareV !== activeV;
        const d = cmp ? diffMap(activeV, compareV, kind) : new Map();
        const B = cmp ? resolveView(compareV, kind) : [];
        const bItem = new Map(),
          bGroup = new Map();
        B.forEach(([g, l]) =>
          l.forEach((it) => {
            bItem.set(it[0], it);
            bGroup.set(it[0], g);
          }),
        );
        const groups = A.map(([g]) => g);
        if (cmp) for (const [g] of B) if (!groups.includes(g)) groups.push(g);

        return groups
          .map((g) => {
            const own = (A.find(([n]) => n === g)?.[1] || []).map(
              ([id, nm, ds, payload]) => ({
                id,
                nm,
                ds,
                payload,
                diff: d.get(id) || null,
                ghost: false,
                other: bItem.get(id)?.[3] ?? null,
              }),
            );
            const ghosts = cmp
              ? [...d.entries()]
                  .filter(
                    ([id, k]) => k === "onlyThere" && bGroup.get(id) === g,
                  )
                  .map(([id]) => {
                    const it = bItem.get(id);
                    return {
                      id,
                      nm: it[1],
                      ds: it[2],
                      payload: it[3],
                      diff: "onlyThere",
                      ghost: true,
                      other: null,
                    };
                  })
              : [];
            return [g, own.concat(ghosts)];
          })
          .filter(([, l]) => l.length);
      }

      /* ---- render (re-runnable; version changes call this) ------------ */
      let CB = {},
        nScreens = 0,
        nFlows = 0,
        nEls = 0;

      function render() {
        const SM = viewModel("screens");
        const EM = viewModel("elements");
        const FM = viewModel("flows");
        const openMap = resolveOpen(activeV);
        const cmp = compareV && compareV !== activeV;
        const bLabel = cmp ? VMAP.get(compareV)[1] : "";
        const aLabel = VMAP.get(activeV)[1];

        // Labels read from the point of view of the version on screen.
        const TAGTEXT = {
          changed: "changed",
          onlyHere: "only here",
          onlyThere: `only in ${bLabel}`,
        };
        const tagFor = (d) =>
          d ? `<span class="tag ${d}">${TAGTEXT[d]}</span>` : "";
        const keep = (e) => !(onlyDiff && cmp && !e.diff);

        const count = (m) =>
          m.reduce((a, [, l]) => a + l.filter(keep).length, 0);
        nScreens = count(SM);
        nEls = count(EM);
        nFlows = count(FM);

        document.getElementById("screens").innerHTML = SM.map(
          ([g, entries]) => {
            const cells = entries
              .filter(keep)
              .map((e) => {
                let shot;
                if (cmp && e.diff === "changed")
                  shot = `<div class="pair"><div><div class="vl">${aLabel}</div><div class="shot">${frame({ ...e.payload, sm: true })}</div></div><div><div class="vl b">${bLabel}</div><div class="shot">${frame({ ...(e.other || e.payload), sm: true })}</div></div></div>`;
                else shot = `<div class="shot">${frame(e.payload)}</div>`;
                return `<div class="item${e.ghost ? " ghost" : ""}" data-id="${e.id}">${shot}<div class="cap"><div class="nm">${e.nm}${tagFor(e.diff)}</div><div class="ds">${e.ds}</div></div></div>`;
              })
              .join("");
            return cells
              ? `<div class="gsec" data-group="${g}"><h2 class="grp">${g}</h2><div class="grid${cmp ? " cmp" : ""}">${cells}</div></div>`
              : "";
          },
        ).join("");

        document.getElementById("elements").innerHTML = EM.map(
          ([g, entries]) => {
            const cells = entries
              .filter(keep)
              .map(
                (e) =>
                  `<div class="el${e.ghost ? " ghost" : ""}" data-id="${e.id}"><div class="demo">${e.payload}</div><div class="body"><div class="nm">${e.nm}${tagFor(e.diff)}</div><div class="ds">${e.ds}</div></div></div>`,
              )
              .join("");
            return cells
              ? `<div class="gsec" data-group="${g}"><h2 class="grp">${g}</h2><div class="egrid">${cells}</div></div>`
              : "";
          },
        ).join("");

        const stepRow = (steps) =>
          `<div class="steps">${steps
            .map(
              ([sn, sc, spec], i) =>
                (i ? '<div class="arrow">&rarr;</div>' : "") +
                `<div class="step"><div class="sn">${String(i + 1).padStart(2, "0")} &middot; ${sn}</div><div class="shot">${frame(spec)}</div><div class="sc">${sc}</div></div>`,
            )
            .join("")}</div>`;

        document.getElementById("flows").innerHTML = FM.map(([g, entries]) =>
          entries
            .filter(keep)
            .map((e) => {
              const rows =
                cmp && e.diff === "changed"
                  ? `<div class="vrow">${aLabel}</div>${stepRow(e.payload)}<div class="vrow b">${bLabel}</div>${stepRow(e.other || e.payload)}`
                  : stepRow(e.payload);
              return `<div class="flow${e.ghost ? " ghost" : ""}" id="f-${e.id}" data-f="${flowSearchText(g, e.nm, e.ds, e.payload)}"><p class="fh">${e.nm}${tagFor(e.diff)}</p><p class="fd">${e.ds}</p>${
                openMap[e.id] ? `<p class="pend">${openMap[e.id]}</p>` : ""
              }${rows}</div>`;
            })
            .join(""),
        ).join("");

        document.getElementById("sidenav").innerHTML = FM.map(
          ([g, entries]) => {
            const links = entries
              .filter(keep)
              .map(
                (e) =>
                  `<a href="#f-${e.id}" data-id="${e.id}" data-nm="${stripTags(e.nm)}" data-f="${flowSearchText(g, e.nm, e.ds, e.payload)}">${stripTags(e.nm)}</a>`,
              )
              .join("");
            return links ? `<div class="sh">${g}</div>${links}` : "";
          },
        ).join("");

        const cbGroups = (m) =>
          m
            .map(([g, entries]) => [
              g,
              entries.filter(keep).map((e) => [e.id, e.nm, e.ds]),
            ])
            .filter(([, l]) => l.length);

        CB = {
          screens: {
            label: "Screens",
            placeholder: "Search screens…",
            container: "screens",
            itemSel: ".item",
            none: "screens-none",
            groups: cbGroups(SM),
          },
          elements: {
            label: "UI Elements",
            placeholder: "Search elements…",
            container: "elements",
            itemSel: ".el",
            none: "elements-none",
            groups: cbGroups(EM),
          },
        };
        // drop filter selections for ids this version doesn't have
        for (const k of ["screens", "elements"]) {
          const live = new Set(
            CB[k].groups.flatMap(([, l]) => l.map(([id]) => id)),
          );
          [...sel[k]].forEach((id) => {
            if (!live.has(id)) sel[k].delete(id);
          });
        }

        const total = cmp
          ? ["screens", "elements", "flows"].reduce(
              (a, k) => a + diffMap(activeV, compareV, k).size,
              0,
            )
          : 0;
        document.getElementById("vinfo-lbl").textContent = cmp
          ? `${aLabel} ↔ ${bLabel}`
          : aLabel;
        document.getElementById("vinfo-note").innerHTML = cmp
          ? `${VMAP.get(activeV)[2]}`
          : VMAP.get(activeV)[2];
        document.getElementById("vinfo-diffs").textContent = cmp
          ? total
            ? `${total} difference${total === 1 ? "" : "s"}`
            : "identical"
          : "";
        document.getElementById("difftoggle").classList.toggle("gone", !cmp);
        document.getElementById("vbtn-label").textContent = cmp
          ? `${aLabel} ↔ ${bLabel}`
          : aLabel;
        document.getElementById("vcmp-clear").classList.toggle("gone", !cmp);
        if (view !== "flows") applyFilter();
        else updateCount(0);
        if (view === "flows" && fsearch.value)
          fsearch.dispatchEvent(new Event("input", { bubbles: true }));
        spy();
      }

      /* ---- filter combobox ---- */
      const cbox = document.getElementById("cbox"),
        cbtn = document.getElementById("cbtn"),
        cbtnLabel = document.getElementById("cbtn-label"),
        cbtnBadge = document.getElementById("cbtn-badge"),
        csearch = document.getElementById("csearch"),
        clist = document.getElementById("clist"),
        cfootN = document.getElementById("cfoot-n"),
        cclear = document.getElementById("cclear");

      function visibleOpts() {
        const q = csearch.value.trim().toLowerCase();
        if (!q) return CB[view].groups;
        return CB[view].groups
          .map(([g, items]) => [
            g,
            // A group's own name pulls in its whole contents (browse by category);
            // otherwise an item needs every query word in its name or note.
            matchWords(g.toLowerCase(), q)
              ? items
              : items.filter(([, nm, ds]) =>
                  matchWords(stripTags(`${nm} ${ds || ""}`).toLowerCase(), q),
                ),
          ])
          .filter(([, items]) => items.length);
      }
      function renderList() {
        const groups = visibleOpts(),
          q = csearch.value.trim();
        if (!groups.length) {
          kbIndex = -1;
          kbId = null;
          clist.innerHTML = '<div class="cempty">No matches.</div>';
          return;
        }
        clist.innerHTML = groups
          .map(
            ([g, items]) =>
              `<div class="cgrp" data-group="${g}">${g}</div>` +
              items
                .map(
                  ([id, nm]) =>
                    `<div class="copt${sel[view].has(id) ? " sel" : ""}" data-id="${id}"><span class="box">${
                      sel[view].has(id) ? "&#10003;" : ""
                    }</span><span class="lb">${highlightText(stripTags(nm), q)}</span></div>`,
                )
                .join(""),
          )
          .join("");
        // Keep keyboard focus on the same option across a re-render, so toggling
        // with Enter doesn't fling focus back to the top.
        const opts = [...clist.querySelectorAll(".copt")];
        let idx = kbId ? opts.findIndex((o) => o.dataset.id === kbId) : -1;
        if (idx < 0) idx = 0;
        if (opts.length) {
          kbIndex = idx;
          kbId = opts[idx].dataset.id;
          opts[idx].classList.add("kb");
        } else {
          kbIndex = -1;
          kbId = null;
        }
      }
      function applyFilter() {
        const cfg = CB[view],
          s = sel[view],
          root = document.getElementById(cfg.container);
        let shown = 0;
        root.querySelectorAll(cfg.itemSel).forEach((el) => {
          const on = s.size === 0 || s.has(el.dataset.id);
          el.classList.toggle("gone", !on);
          if (on) shown++;
        });
        root
          .querySelectorAll(".gsec")
          .forEach((g) =>
            g.classList.toggle(
              "gone",
              !g.querySelector(cfg.itemSel + ":not(.gone)"),
            ),
          );
        document.getElementById(cfg.none).classList.toggle("gone", shown > 0);
        const total = view === "screens" ? nScreens : nEls;
        cbtnBadge.hidden = s.size === 0;
        cbtnBadge.textContent = s.size;
        cfootN.textContent =
          s.size === 0
            ? `Showing all ${total}`
            : `Showing ${shown} of ${total}`;
        updateCount(shown);
      }
      function updateCount(shown) {
        const s = sel[view] ? sel[view].size : 0;
        document.getElementById("cnt").textContent = [
          `${view === "screens" && s ? shown + " of " : ""}${nScreens} screens`,
          `${nFlows} flows`,
          `${view === "elements" && s ? shown + " of " : ""}${nEls} elements`,
        ].join(" · ");
      }
      function openCB(focus) {
        if (view === "flows") return;
        closeVB(); // only one dropdown at a time
        cbOpen = true;
        cbox.classList.add("open");
        kbId = null;
        renderList();
        if (focus) csearch.focus();
      }
      function closeCB() {
        cbOpen = false;
        cbox.classList.remove("open");
        csearch.blur();
      }

      cbtn.addEventListener("click", (e) => {
        e.stopPropagation();
        cbOpen ? closeCB() : openCB(true);
      });
      csearch.addEventListener("input", () => {
        clist.scrollTop = 0;
        renderList();
      });
      clist.addEventListener("click", (e) => {
        const opt = e.target.closest(".copt");
        if (opt) {
          // stopPropagation is required: renderList() replaces clist.innerHTML,
          // detaching this node before the click finishes bubbling, which would
          // make the document listener below see a detached target and close.
          e.stopPropagation();
          const id = opt.dataset.id;
          sel[view].has(id) ? sel[view].delete(id) : sel[view].add(id);
          renderList();
          applyFilter();
          return;
        }
        const grp = e.target.closest(".cgrp");
        if (grp) {
          e.stopPropagation();
          const ids = CB[view].groups
            .find(([n]) => n === grp.dataset.group)[1]
            .map(([id]) => id);
          const allOn = ids.every((id) => sel[view].has(id));
          ids.forEach((id) =>
            allOn ? sel[view].delete(id) : sel[view].add(id),
          );
          renderList();
          applyFilter();
        }
      });
      cclear.addEventListener("click", (e) => {
        e.stopPropagation();
        sel[view].clear();
        csearch.value = "";
        renderList();
        applyFilter();
      });
      document.addEventListener("click", (e) => {
        if (cbOpen && !cbox.contains(e.target)) closeCB();
        if (vbOpen && !vbox.contains(e.target)) closeVB();
      });

      /* ---- version combobox (single-select, plus compare) ---- */
      const vbox = document.getElementById("vbox"),
        vbtn = document.getElementById("vbtn"),
        vsearch = document.getElementById("vsearch"),
        vlist = document.getElementById("vlist"),
        vfootN = document.getElementById("vfoot-n"),
        vcmpClear = document.getElementById("vcmp-clear"),
        diffToggle = document.getElementById("difftoggle");

      function renderVList() {
        const q = vsearch.value.trim(),
          ql = q.toLowerCase();
        const rows = VERSIONS.filter(
          ([id, label, note]) =>
            !ql ||
            matchWords(stripTags(`${label} ${note} ${id}`).toLowerCase(), ql),
        );
        if (!rows.length) {
          vkbIndex = -1;
          vkbId = null;
          vlist.innerHTML = '<div class="cempty">No matches.</div>';
          return;
        }
        vlist.innerHTML =
          `<div class="cgrp" style="cursor:default">Show version</div>` +
          rows
            .map(
              ([id, label, note, parent]) =>
                `<div class="copt radio${id === activeV ? " sel" : ""}" data-v="${id}">
           <span class="box">${id === activeV ? "&#10003;" : ""}</span>
           <span class="col"><span class="lb">${highlightText(label, q)}</span>${
             note
               ? `<div class="sub">${parent ? `from ${VMAP.get(parent)[1]} &middot; ` : ""}${note}</div>`
               : ""
           }</span>
           ${id !== activeV ? `<span class="tagn" data-cmp="${id}">${compareV === id ? "comparing" : "compare"}</span>` : ""}
         </div>`,
            )
            .join("");
        // Keep keyboard focus on the same version across a re-render
        // (toggling compare re-renders this list), falling back to the
        // first row only when the focused version is filtered out.
        const vopts = [...vlist.querySelectorAll(".copt")];
        let vi = vkbId ? vopts.findIndex((o) => o.dataset.v === vkbId) : -1;
        if (vi < 0) vi = 0;
        if (vopts.length) {
          vkbIndex = vi;
          vkbId = vopts[vi].dataset.v;
          vopts[vi].classList.add("kb");
        } else {
          vkbIndex = -1;
          vkbId = null;
        }

        const legend = "&#8629; show &middot; &#8679;&#8629; compare";
        vfootN.innerHTML = compareV
          ? `Comparing with ${VMAP.get(compareV)[1]} &middot; ${legend}`
          : `${VERSIONS.length} version${VERSIONS.length === 1 ? "" : "s"} &middot; ${legend}`;
      }
      function openVB(focus) {
        closeCB(); // only one dropdown at a time, or they fight over the arrow keys
        vbOpen = true;
        vbox.classList.add("open");
        vkbId = activeV; // open focused on where you already are
        renderVList();
        if (focus) vsearch.focus();
      }
      function closeVB() {
        vbOpen = false;
        vbox.classList.remove("open");
        vsearch.blur();
      }

      vbtn.addEventListener("click", (e) => {
        e.stopPropagation();
        vbOpen ? closeVB() : openVB(true);
      });
      vsearch.addEventListener("input", () => {
        vlist.scrollTop = 0;
        renderVList();
      });
      vlist.addEventListener("click", (e) => {
        e.stopPropagation();
        const cmpBtn = e.target.closest("[data-cmp]");
        if (cmpBtn) {
          const id = cmpBtn.dataset.cmp;
          compareV = compareV === id ? null : id;
          renderVList();
          render();
          return;
        }
        const opt = e.target.closest(".copt");
        if (opt) {
          activeV = opt.dataset.v;
          if (compareV === activeV) compareV = null;
          renderVList();
          render();
          closeVB();
        }
      });
      vcmpClear.addEventListener("click", (e) => {
        e.stopPropagation();
        compareV = null;
        onlyDiff = false;
        diffToggle.classList.add("off");
        renderVList();
        render();
      });
      diffToggle.addEventListener("click", () => {
        onlyDiff = !onlyDiff;
        diffToggle.classList.toggle("off", !onlyDiff);
        render();
      });

      /* ---- view switching ---- */
      function switchView(v) {
        const btn = document.querySelector(`.vtabs button[data-v="${v}"]`);
        if (!btn || view === v) return;
        view = v;
        document
          .querySelectorAll(".vtabs button")
          .forEach((x) => x.classList.toggle("on", x === btn));
        document
          .querySelectorAll(".view")
          .forEach((el) => el.classList.toggle("on", el.id === "v-" + view));
        closeCB();
        const isFlows = view === "flows";
        cbox.classList.toggle("hide", isFlows);
        if (!isFlows) {
          cbtnLabel.textContent = CB[view].label;
          csearch.placeholder = CB[view].placeholder;
          csearch.value = "";
          applyFilter();
        } else updateCount(0);
        window.scrollTo({ top: 0, behavior: "instant" });
      }
      document
        .querySelectorAll(".vtabs button")
        .forEach((b) =>
          b.addEventListener("click", () => switchView(b.dataset.v)),
        );

      /* ---- flow search + scroll-spy ---- */
      const fsearch = document.getElementById("fsearch"),
        sbox = document.getElementById("sbox");
      fsearch.addEventListener("focus", () => sbox.classList.add("focused"));
      fsearch.addEventListener("blur", () => sbox.classList.remove("focused"));
      fsearch.addEventListener("input", () => {
        sbox.classList.toggle("dirty", fsearch.value.length > 0);
        const q = fsearch.value.trim().toLowerCase();
        let any = false;
        document.querySelectorAll(".flow").forEach((f) => {
          const show = !q || matchWords(f.dataset.f, q);
          f.classList.toggle("gone", !show);
          if (show) any = true;
        });
        document.querySelectorAll("#sidenav a").forEach((a) => {
          a.classList.toggle("gone", !(!q || matchWords(a.dataset.f, q)));
          a.innerHTML = highlightText(a.dataset.nm, fsearch.value.trim());
        });
        document.querySelectorAll("#sidenav .sh").forEach((h) => {
          let n = h.nextElementSibling,
            on = false;
          while (n && n.tagName === "A") {
            if (!n.classList.contains("gone")) on = true;
            n = n.nextElementSibling;
          }
          h.classList.toggle("gone", !on);
        });
        document.getElementById("flows-none").classList.toggle("gone", any);
        spy();
      });

      /* Highlights whichever flow is under the header as you scroll, not only on
      click. Filter-aware, and clamps to the last section at the page bottom. */
      let spyRAF = null;
      function spy() {
        if (spyRAF) return;
        spyRAF = requestAnimationFrame(() => {
          spyRAF = null;
          if (view !== "flows") return;
          const flows = [...document.querySelectorAll(".flow:not(.gone)")];
          if (!flows.length) return;
          let cur = flows[0];
          for (const f of flows)
            if (f.getBoundingClientRect().top <= 100) cur = f;
          if (
            window.innerHeight + window.scrollY >=
            document.body.scrollHeight - 4
          )
            cur = flows[flows.length - 1];
          const id = cur.id.replace(/^f-/, "");
          document
            .querySelectorAll("#sidenav a")
            .forEach((a) => a.classList.toggle("cur", a.dataset.id === id));
        });
      }
      window.addEventListener("scroll", spy, { passive: true });
      window.addEventListener("resize", spy);

      /* ---- hotkeys: 1/2/3 views, v versions, / search, Esc clear-then-close ---- */
      function isTyping(el) {
        return (
          el &&
          (el.tagName === "INPUT" ||
            el.tagName === "TEXTAREA" ||
            el.isContentEditable)
        );
      }
      document.addEventListener("keydown", (e) => {
        const free =
          !isTyping(document.activeElement) && !e.metaKey && !e.ctrlKey;
        if (["1", "2", "3"].includes(e.key) && free) {
          e.preventDefault();
          switchView({ 1: "screens", 2: "elements", 3: "flows" }[e.key]);
          return;
        }
        if ((e.key === "v" || e.key === "V") && free) {
          e.preventDefault();
          vbOpen ? closeVB() : openVB(true);
          return;
        }
        if (e.key === "/" && free) {
          e.preventDefault();
          if (view === "flows") {
            fsearch.focus();
            fsearch.select();
          } else openCB(true);
          return;
        }
        if (e.key === "Escape") {
          if (vbOpen) {
            if (vsearch.value) {
              vsearch.value = "";
              renderVList();
            } else closeVB();
            return;
          }
          if (cbOpen) {
            if (csearch.value) {
              csearch.value = "";
              renderList();
            } else closeCB();
            return;
          }
          if (isTyping(document.activeElement)) {
            const el = document.activeElement;
            el.value = "";
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.blur();
          }
          return;
        }
        if (
          vbOpen &&
          (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter")
        ) {
          const vopts = [...vlist.querySelectorAll(".copt")];
          if (!vopts.length) return;
          if (e.key === "Enter") {
            if (vkbIndex < 0) return;
            e.preventDefault();
            const id = vopts[vkbIndex].dataset.v;
            if (e.shiftKey) {
              // Shift+Enter compares instead of switching. A letter
              // key can't be used here: the search field has focus,
              // so it would just be typed.
              if (id !== activeV) {
                compareV = compareV === id ? null : id;
                renderVList();
                render();
              }
            } else {
              activeV = id;
              if (compareV === activeV) compareV = null;
              renderVList();
              render();
              closeVB();
            }
            return;
          }
          e.preventDefault();
          vkbIndex =
            e.key === "ArrowDown"
              ? Math.min(vkbIndex + 1, vopts.length - 1)
              : Math.max(vkbIndex - 1, 0);
          vkbId = vopts[vkbIndex].dataset.v;
          vopts.forEach((o, i) => o.classList.toggle("kb", i === vkbIndex));
          vopts[vkbIndex].scrollIntoView({ block: "nearest" });
          return;
        }
        if (
          cbOpen &&
          (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter")
        ) {
          const opts = [...clist.querySelectorAll(".copt")];
          if (!opts.length) return;
          if (e.key === "Enter") {
            if (kbIndex >= 0) {
              e.preventDefault();
              opts[kbIndex].click();
            }
            return;
          }
          e.preventDefault();
          kbIndex =
            e.key === "ArrowDown"
              ? Math.min(kbIndex + 1, opts.length - 1)
              : Math.max(kbIndex - 1, 0);
          kbId = opts[kbIndex].dataset.id;
          opts.forEach((o, i) => o.classList.toggle("kb", i === kbIndex));
          opts[kbIndex].scrollIntoView({ block: "nearest" });
        }
      });

      /* one version means versioning is unused: hide the selector entirely */
      if (VERSIONS.length < 2) {
        vbox.classList.add("hide");
        document.querySelector(".vinfo").classList.add("gone");
      }
      renderVList();
      render();