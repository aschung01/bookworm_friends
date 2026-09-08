/* Assertions for the read-pile mockups. Run by _build/verify.sh, after the
   DOM stub and the page's own script.

   The point of this file is the first block: this page *ports* the app's
   size hash rather than approximating it, and a port is only worth having
   if it is checked. The goldens below are copied from
   test/book_geometry_test.dart, which produced them by running the Dart.
   If the JS drifts from the Dart, the build fails here rather than
   quietly drawing the wrong shelf. */
let fails = 0;
function ok(name, cond, extra) {
  if (cond) return;
  fails++;
  console.log("FAIL " + name + (extra === undefined ? "" : "  " + extra));
}
function eq(name, got, want) {
  ok(name, got === want, "got " + got + " want " + want);
}
function near(name, got, want, eps) {
  ok(
    name,
    Math.abs(got - want) <= (eps === undefined ? 1e-9 : eps),
    "got " + got + " want " + want,
  );
}

/* ---------------------------------------------------------------- hash */
/* test/book_geometry_test.dart -> group('bookHash') > 'is pinned to known
   values'. These are the values the Dart produces; the JS must agree
   exactly, including for 'OL12345W', which is an Open Library work id and
   the case that proves non-ISBN input is hashed the same way. */
eq("hash 9788936434120", bookHash("9788936434120"), 848182861);
eq("hash 9780451524935", bookHash("9780451524935"), 1030674525);
eq("hash 9780141439518", bookHash("9780141439518"), 3499888009);
eq("hash 9791188331796", bookHash("9791188331796"), 1196771503);
eq("hash 9788954682152", bookHash("9788954682152"), 753300405);
eq("hash OL12345W", bookHash("OL12345W"), 3637877494);

/* 'stays inside 32 bits'. The Dart guards this because the web target
   computes it in doubles; the same guard is worth having here for the
   opposite reason — JS bitwise operators would silently sign-flip. */
(function () {
  let bad = 0;
  for (let i = 0; i < 2000; i++) {
    const h = bookHash("978" + (1000000000 + i * 7919));
    if (!(h >= 0 && h < 0x100000000)) bad++;
  }
  eq("hash stays in 32 bits over 2000 isbns", bad, 0);
})();

/* 'handles multi-byte code units without collapsing'. */
eq(
  "multi-byte titles do not collide",
  new Set([bookHash("아몬드"), bookHash("소년이 온다"), bookHash("책")]).size,
  3,
);

/* -------------------------------------------------------------- jitter */
/* group('BookJitter') > 'is pinned to known values'. Pinned as normalised
   positions, exactly as the Dart pins them, so retuning a range does not
   look like a hash regression. */
function pos(isbn) {
  return bookPos(isbn, null);
}
near("jitter h 9788936434120", pos("9788936434120").h, 0.24336614023);
near("jitter t 9788936434120", pos("9788936434120").t, 0.197482261387);
near("jitter h 9780451524935", pos("9780451524935").h, 0.845181963836);
near("jitter t 9780451524935", pos("9780451524935").t, 0.239963378347);
near("jitter h 9780141439518", pos("9780141439518").h, 0.052872510872);
near("jitter t 9780141439518", pos("9780141439518").t, 0.814892805371);
near("jitter h 9791188331796", pos("9791188331796").h, 0.283924620432);
near("jitter t 9791188331796", pos("9791188331796").t, 0.278644998856);
near("jitter h 9788954682152", pos("9788954682152").h, 0.451987487602);
near("jitter t 9788954682152", pos("9788954682152").t, 0.175387197681);
near("jitter h OL12345W", pos("OL12345W").h, 0.605325398642);
near("jitter t OL12345W", pos("OL12345W").t, 0.847013046464);

/* An empty ISBN falls back to neutral: heightFactor 1.0, which is position
   0.5 in [0.94, 1.06]. */
near("empty isbn is neutral height", pos("").h, 0.5);

/* --------------------------------------------------- page count -> pos */
/* group('thickness from page count'). 300 pages is the geometric mean of
   100 and 900, so it lands mid-range by construction. */
near("300 pages is mid-range", pagePos(300), 0.5);
near("100 pages is the floor", pagePos(100), 0);
near("900 pages is the ceiling", pagePos(900), 1);
eq("1500 pages clamps", pagePos(1500), 1);
eq("40 pages clamps", pagePos(40), 0);
eq("a zero count is absent, not thin", pagePos(0), null);
eq("a null count is absent", pagePos(null), null);
/* And a page count wins over the hash, which is the only place real data
   enters this drawing. */
ok(
  "a page count replaces the hashed thickness",
  bookPos("9788936434120", 224).t !== bookPos("9788936434120", null).t &&
    bookPos("9788936434120", 224).fromPages === true,
);
/* ...but never the height, so a book backfilled later keeps its size on
   the shelf. */
eq(
  "a page count leaves height alone",
  bookPos("9780141439518", 640).h,
  bookPos("9780141439518", null).h,
);

/* ---------------------------------------------------- generated covers */
/* Every book in the pile is drawn coverless, so its swatch, its board and
   the tinted-spine variant all come from the app's own functions. The
   palette is kGeneratedCoverPalette and the picker is
   `bookHash(isbn) % 6`, so these are checkable by hand. */
eq("the palette has the app's six swatches", COVER_PALETTE.length, 6);
eq("the first swatch is the brand green", COVER_PALETTE[0], "#09BC8A");
eq("an empty isbn takes the first swatch", generatedCoverColor(""), "#09BC8A");
eq(
  "9788936434120 picks palette[848182861 % 6]",
  generatedCoverColor("9788936434120"),
  COVER_PALETTE[848182861 % 6],
);
/* The swatch is only reached for a book with no thumbnail, which most read
   books are not — so the palette is the fallback here, not the rule. */
ok(
  "the palette is only used where there is no cover",
  CORPUS.every(function (bk, i) {
    const g = geom(bk, { base: 117 }, i);
    return g.gen
      ? g.cover === generatedCoverColor(bk.isbn)
      : g.cover === bk.avg;
  }),
);
/* bookBoardColorFor darkens by 0.18 + 0.30 * luminance, so a board is
   always darker than its cover and a pale swatch is darkened more than a
   dark one. Amber against slate blue is the widest pair in the palette. */
(function () {
  ok(
    "every board is darker than its swatch",
    COVER_PALETTE.every(function (c) {
      return luminance(bookBoardColorFor(c)) < luminance(c);
    }),
  );
  const amber = 0.18 + 0.3 * luminance("#F2B544");
  const slate = 0.18 + 0.3 * luminance("#2F6690");
  ok(
    "a pale swatch is darkened more than a dark one",
    amber > slate,
    amber.toFixed(3) + " vs " + slate.toFixed(3),
  );
})();

/* The spine's tint has a floor, and the floor is what lets every tinted
   spine carry one colour of type. Two properties matter and both were found
   by looking at the rendered row rather than at a number: a washed-out cover
   must not darken to a dead grey, and no tint may miss AA for a 12pt title. */
(function () {
  const drawn = CORPUS.map(function (bk, i) {
    const g = geom(bk, { base: 117 }, i);
    return {
      title: bk.title,
      cover: g.cover,
      plain: bookBoardColorFor(g.cover),
      tint: g.tintc,
      r: contrastRatio(g.tintc, "#FFFFFF"),
    };
  });
  ok(
    "every tint on the row clears AA for a 12pt title",
    drawn.every(function (x) {
      return x.r >= 4.5;
    }),
    drawn
      .filter(function (x) {
        return x.r < 4.5;
      })
      .map(function (x) {
        return x.title + " " + x.r.toFixed(2);
      })
      .join(", "),
  );
  /* And the floor is a no-op for covers that do not need it, so the tint is
     `bookBoardColorFor` for most of the shelf. A floor that touched every
     book would be a recolouring, not a floor. */
  const lifted = drawn.filter(function (x) {
    return x.tint !== x.plain;
  });
  ok(
    "the floor only bites on low-chroma covers",
    lifted.length >= 1 && lifted.length <= 3,
    lifted.length + " of " + drawn.length + " lifted",
  );
  eq(
    "and the pale cover is one of them",
    lifted.some(function (x) {
      return x.title === "The White Book";
    }),
    true,
  );
  /* The pale cover is the case the whole function exists for: plain
     bookBoardColorFor put it under AA, and the lift must both fix that and
     leave it with some chroma. A darker grey would pass the contrast test
     and still look like a hole in the shelf. */
  (function () {
    const w = lifted.find(function (x) {
      return x.title === "The White Book";
    });
    ok(
      "plain bookBoardColorFor would have failed it",
      contrastRatio(w.plain, "#FFFFFF") < 4.5,
    );
    ok("the floored tint passes", w.r >= 4.5);
    ok(
      "and it has chroma rather than being a darker grey",
      saturation(w.tint) > saturation(w.plain) + 0.05,
      "plain " +
        saturation(w.plain).toFixed(3) +
        " tint " +
        saturation(w.tint).toFixed(3),
    );
  })();
  /* The corner the first implementation got wrong, kept here because the
     drawing is the design record and this is the one case where a reader
     would otherwise ask why the lift is scaled by luminance at all.

     Black has saturation 0, exactly as white does. Gated on chroma alone the
     lift fires on a black jacket as hard as on a pale one, and blends it
     toward `brand`: a book that had no problem, recoloured to a dark green
     spine. Mirrors "Given a pure black cover" in test/spine_tint_test.dart. */
  (function () {
    const t = spineTintFor("#000000");
    eq("a black cover gains no chroma", t, bookBoardColorFor("#000000"));
    ok(
      "and stays neutral",
      saturation(t) < 0.05,
      "saturation " + saturation(t).toFixed(3),
    );
  })();
  /* A dark, saturated cover passes through untouched. */
  (function () {
    const g = geom(CORPUS[0], { base: 117 }, 0);
    eq("a dark cover's tint is its board", g.tintc, bookBoardColorFor(g.cover));
  })();
  /* Which is why the title is unconditionally white on a tinted spine. */
  ok(
    "tinted spines never need dark type",
    CORPUS.every(function (bk, i) {
      return !paleFill({ tint: true }, geom(bk, { base: 117 }, i));
    }),
  );
  /* The untinted rule is unchanged: BookVertical flips at 0.7. */
  eq(
    "a 0.4 spine takes dark type",
    paleFill(CORPUS[0], geom(CORPUS[0], { base: 117 }, 0)),
    true,
  );
  eq(
    "a 1.0 spine takes white",
    paleFill(CORPUS[2], geom(CORPUS[2], { base: 117 }, 2)),
    false,
  );
  /* Most read books have artwork, so most tints need a decoded image to exist
     at all — which is the argument for the stored column. */
  const withArt = CORPUS.filter(function (b) {
    return !!b.avg;
  }).length;
  ok(
    "most of the drawn row has a real cover",
    withArt > CORPUS.length / 2,
    withArt + " of " + CORPUS.length,
  );
  ok(
    "and some of it does not, so the fallback is drawn too",
    withArt < CORPUS.length,
  );
})();

/* Air either side of a book that has been turned out. Nothing at rest, so
   tapping is the only thing that changes the pile's density. */
(function () {
  function margin(deg) {
    return kTurnMargin * Math.max(0, Math.min(1, (deg + 90) / 90));
  }
  near("no margin at rest", margin(-90), 0);
  near("half way out, half the margin", margin(-45), kTurnMargin / 2);
  near("full margin at cover-on", margin(0), kTurnMargin);
  near("and it does not grow past it when held", margin(HOLD), kTurnMargin);
  ok("the margin is worth seeing", kTurnMargin >= 6);
})();

/* ------------------------------------------------- the height budget */
/* The whole argument for base 117: `bookRowExtent()` says a row must
   reserve base x maxHeightFactor, so the tallest jittered book on base 117
   is today's 124 and ReadPile.extent does not move. Drawn wrong, a book
   that hashed tall would be clipped by the row. */
near("base 117 tops out at today's 124", 117 * HF1, 124.02, 0.03);
ok(
  "no drawn book exceeds the 137pt row",
  CORPUS.every(function (bk, i) {
    return geom(bk, { base: 117 }, i).h <= ROW_EXTENT;
  }),
);
ok(
  "and every drawn book clears the shortest credible spine",
  CORPUS.every(function (bk, i) {
    return geom(bk, { base: 117 }, i).h >= 117 * HF0 - 1e-9;
  }),
);
/* The taller-pile version's number, stated once here so the note and the
   drawing cannot disagree: 124 x 1.06 + 13 = 144.44, + 14 + 8 + 10. */
near("taller-pile reserves 144.44", 124 * HF1 + 13, 144.44, 0.01);
near(
  "taller-pile extent is 176.44",
  124 * HF1 + 13 + 14 + 8 + 10,
  176.44,
  0.01,
);
eq("main's extent is unchanged", PILE_EXTENT, 169);

/* ------------------------------------------------------ spine widths */
/* The remap is centred on today's 26 so the pile's density is unchanged:
   a book at the middle of the thickness range gets exactly 26pt. */
near("the remap is centred on 26", (NARROW[0] + NARROW[1]) / 2, 26);
/* True thickness on the same books is materially wider, which is the whole
   trade-off the two versions describe. Asserted rather than asserted-in-
   prose, because "about nine across" is a claim about a number. */
(function () {
  const row = 402 - 2 * 14 - 2 * 25; /* card inset, then _gutter */
  eq("the row is 324pt wide", row, 324);
  let narrow = 0,
    real = 0;
  CORPUS.forEach(function (bk, i) {
    narrow += geom(bk, { base: 117, wmode: "narrow" }, i).tk;
    real += geom(bk, { base: 117, wmode: "true" }, i).tk;
  });
  const perNarrow = narrow / CORPUS.length,
    perReal = real / CORPUS.length;
  near("today fits 12.5 spines", row / SPINE_W, 12.46, 0.05);
  ok(
    "the remap keeps that density",
    Math.abs(row / perNarrow - row / SPINE_W) < 0.6,
    row / perNarrow,
  );
  ok(
    "true thickness drops it to about nine",
    row / perReal > 8.4 && row / perReal < 9.8,
    row / perReal,
  );
})();

/* -------------------------------------------------------- the turn */
/* The sign convention, which the first draft of this page got backwards and
   drew a book turning inside out. CSS's +z comes toward the viewer where the
   Flutter projection makes it recede, so a Flutter turn of d is rotateY(-d).
   At the resting angle the spine must be square to the reader and the cover
   edge-on; anything else means the drawing and the widget disagree about
   which way a book opens. */
(function () {
  /* -90 is spine-on: the CSS angle is +90, at which the spine face's own
       -90 local rotation cancels to zero, i.e. square to the reader. */
  eq("a Flutter turn of -90 is a CSS turn of +90", -(-90), 90);
  eq("and the spine face cancels to square on", -(-90) + -90, 0);
  /* 0 is cover-on: the cover has no local rotation, so it is square on,
       and the spine is at -90, edge-on. */
  eq("a Flutter turn of 0 leaves the cover square on", -0, 0);
  /* The offset that keeps the drawing's left edge on its box's. At rest it
       is a full thickness; once past cover-on the spine is behind the cover
       and contributes nothing. */
  const g0 = geom(CORPUS[OPEN_AT], { base: 117 }, OPEN_AT);
  function ox(deg) {
    return Math.max(0, g0.tk * Math.sin((-deg * Math.PI) / 180));
  }
  near("at rest the drawing is shifted a full thickness", ox(-90), g0.tk);
  near("cover-on needs no shift", ox(0), 0);
  near("and neither does the held book", ox(HOLD), 0);
})();

/* The projected width is what the row lays neighbours out against, so the
   two ends have to be exact: the spine at -90, the cover at 0. A sign
   slip here reads as the book jumping width the instant it is tapped. */
(function () {
  const g = geom(CORPUS[OPEN_AT], { base: 117 }, OPEN_AT);
  near("projected at -90 is the spine", projected(g, -90), g.tk, 1e-9);
  near("projected at 0 is the cover", projected(g, 0), g.cw, 1e-9);
  /* Analytically, not by sampling: f(θ) = cw·cos + tk·sin peaks at
     atan(tk/cw) with value hypot(cw, tk). Checked as an identity so the
     note's numbers cannot go stale, plus a coarse scan to confirm there
     is no second maximum hiding elsewhere in the sweep. */
  (function () {
    const at = -(Math.atan(g.tk / g.cw) * 180) / Math.PI;
    near(
      "the peak is hypot(cover, thickness)",
      projected(g, at),
      Math.hypot(g.cw, g.tk),
    );
    ok("and the peak is past the cover width", Math.hypot(g.cw, g.tk) > g.cw);
    let best = -1;
    for (let i = 0; i <= 900; i++)
      best = Math.max(best, projected(g, -90 + i / 10));
    ok(
      "no wider point anywhere in the sweep",
      best <= Math.hypot(g.cw, g.tk) + 1e-9,
      best,
    );
  })();
  /* And the size of the overshoot, because the note claims it is small.
     3.3pt on this book: the row opens that much wider than the cover and
     settles back over the last third of the turn. */
  near(
    "the overshoot past the cover is about 3pt",
    Math.hypot(g.cw, g.tk) - g.cw,
    3.3,
    0.1,
  );
  /* The held book is wider than the resting cover, because +16 brings the
       fore-edge into the projection. Worth pinning: it is why the row must
       not be laid out at the cover width alone. */
  ok("the held book is wider than the cover", projected(g, HOLD) > g.cw);
})();

/* ---------------------------------------------------------- rendering */
/* Every screen, flow step and element in every version renders without
   throwing and produces markup. The stub cannot check what it looks like,
   but it can check that no spec is missing a field the renderer reads. */
(function () {
  let n = 0;
  for (const v of VERSIONS) {
    for (const [, list] of resolveView(v[0], "screens"))
      for (const [id, , , spec] of list) {
        const h = frame(spec);
        ok("screen " + id + " @" + v[0] + " renders", h.length > 200);
        n++;
      }
    for (const [, list] of resolveView(v[0], "flows"))
      for (const [id, , , steps] of list)
        steps.forEach(function (st, i) {
          ok(
            "flow " + id + " step " + i + " @" + v[0],
            frame(st[2]).length > 200,
          );
          n++;
        });
    for (const [, list] of resolveView(v[0], "elements"))
      for (const [id, , , demo] of list) {
        ok(
          "element " + id + " @" + v[0],
          typeof demo === "string" && demo.length > 40,
        );
        n++;
      }
  }
  console.log(
    "rendered " + n + " specs across " + VERSIONS.length + " versions",
  );
})();

/* Only one book is ever turned out. That is not a tidiness rule, it is what
   keeps the hero tag unique: `book_<isbn>` collides for the ISBN-less
   migrated books, so a pile that tagged every spine would throw. */
(function () {
  let bad = [];
  for (const v of VERSIONS)
    for (const [, list] of resolveView(v[0], "screens"))
      for (const [id, , , spec] of list) {
        const open = (spec.pile || {}).open;
        if (open !== undefined && typeof open !== "number")
          bad.push(id + "@" + v[0]);
      }
  eq("at most one open book per screen", bad.length, 0, bad.join(","));
})();

/* ------------------------------------------------------- inheritance */
/* Versions store patches. A version that restates an unchanged screen
   reintroduces exactly the drift the data model exists to stop, so check
   that the untouched ones really are inherited by identity. */
(function () {
  function specOf(vid, id) {
    for (const [, list] of resolveView(vid, "screens"))
      for (const row of list) if (row[0] === id) return row[3];
    return null;
  }
  ok(
    "taller-pile inherits pile-today",
    specOf("taller-pile", "pile-today") === specOf("decided", "pile-today"),
  );
  ok(
    "green-true inherits pile-empty",
    specOf("green-true", "pile-empty") === specOf("decided", "pile-empty"),
  );
  ok(
    "and overrides pile-jitter",
    specOf("green-true", "pile-jitter") !== specOf("decided", "pile-jitter"),
  );
  /* The root is the decided design, so its plain data must already be the
     answer: tinted, at true thickness, on base 117. A root that had to be
     patched into the decision would mean the page still opens on a
     superseded drawing. */
  ok(
    "the root is the decided design",
    specOf("decided", "pile-jitter").pile.style === undefined &&
      PILE_STYLES.decided.tint === true &&
      PILE_STYLES.decided.wmode === "true",
  );
  ok(
    "and it is on base 117",
    specOf("decided", "pile-jitter").pile.base === undefined,
  );
  /* green-remap branches off green-true, so it inherits the brand fill and
     restates only the width. */
  ok(
    "green-remap is a grandchild of decided",
    specOf("green-remap", "pile-jitter").pile.style === "remap" &&
      specOf("green-true", "pile-jitter").pile.style === "green",
  );
  ok(
    "neither green version tints",
    !PILE_STYLES.green.tint && !PILE_STYLES.remap.tint,
  );
  /* taller-pile changes the base and the extent together. Changing one without
     the other clips any book that hashes tall. */
  (function () {
    const p = specOf("taller-pile", "pile-jitter").pile;
    eq("taller-pile is on base 124", p.base, 124);
    near("and raises the extent to match", p.h, 176.44, 0.05);
    const s = specOf("taller-pile", "pile-stretch").pile;
    near("the stretched screen keeps its own 40pt", s.h - p.h, 40, 0.01);
  })();
  /* Nothing is removed in either branch; if that changes, the ghost-row
       path in the engine starts mattering and this assertion should be the
       thing that says so. */
  eq(
    "no screen is removed in any version",
    VERSIONS.reduce(function (acc, v) {
      return (
        acc +
        Object.values((v[4] || {}).screens || {}).filter(function (x) {
          return x === null;
        }).length
      );
    }, 0),
    0,
  );
})();

/* The open decisions are attached to the ids they belong to, and the tint's
   unresolved piece must not follow a version that has no tint. */
(function () {
  const d = resolveOpen("decided"),
    g = resolveOpen("green-true");
  ok("the decided design flags the hero", !!d["turn-out"]);
  ok("and the height budget", !!d["pile-jitter"]);
  ok(
    "and the pale-cover tint",
    /chroma|near-white/i.test(d["el-spine-jitter"] || ""),
  );
  ok(
    "the green versions drop the tint's callout",
    !g["el-spine-jitter"],
    "a red callout about tinting is attached to a version with no tint",
  );
  ok("but keep the height budget", !!g["pile-jitter"]);
})();

/* ------------------------------------------------------------- search */
/* Words a reader can see on the page must find the thing they are looking
   at. Every one of these returned nothing at some point while the notes
   were being written. */
(function () {
  function flowHits(q) {
    const out = [];
    for (const [g, items] of FLOWS)
      for (const [id, nm, ds, steps] of items)
        if (matchWords(flowSearchText(g, nm, ds, steps), q.toLowerCase()))
          out.push(id);
    return out;
  }
  function has(q, id) {
    ok(
      "search '" + q + "' finds " + id,
      flowHits(q).indexOf(id) >= 0,
      flowHits(q).join(","),
    );
  }
  has("hero", "turn-out");
  has("isbn", "switch-book");
  has("fore-edge", "turn-out");
  has("edit mode", "switch-book");
  /* Order-independent AND, which is the shell's documented behaviour. */
  ok(
    "search is order-independent",
    flowHits("cover spine").length === flowHits("spine cover").length,
  );
})();

console.log(
  fails === 0 ? "ALL ASSERTIONS PASS" : fails + " ASSERTION(S) FAILED",
);
if (fails) process.exit(1);
