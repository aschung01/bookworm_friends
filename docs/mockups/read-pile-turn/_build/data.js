   SECTION 2: FRAME RENDERER — the collapsed read sheet, drawn from data
   by one function.

   The geometry below is not a redrawing of the app's, it is a *port* of
   it: `bookHash`, `bookThicknessPositionFromPages` and the two jitter
   ranges are transcribed from lib/ui/widgets/book/book_geometry.dart, and
   `_build/assert.js` checks the port against the same golden values
   test/book_geometry_test.dart pins. So every spine width and height on
   this page is the number the widget would produce for that ISBN, not an
   impression of one. If the port drifts, the build fails.
   ================================================================== */
            /* ---- BookJitter's ranges, verbatim ---- */
            const HF0 = 0.94,
                HF1 = 1.06; /* heightFactor    */
            const TF0 = 0.36,
                TF1 = 0.52; /* thicknessFactor */

            /* kDefaultCoverAspect. Every book here uses it, because the pile
               has no decoded image to take a real ratio from — the spines load
               no covers at all today, which is one of the costs the proposal
               has to answer for. */
            const ASPECT = 2 / 3;

            /* kBookPerspectiveRatio: perspective is 4.6x the cover width, held
               as a ratio so the effect is identical at every size. */
            const PERSP = 4.6;

            /* kBookTurnAngle, in degrees. 16 is the angle the reference
               component rotates to on hover, and the angle a held book
               reaches on the shelves. */
            const HOLD = 16;

            /* Air either side of the book that has been turned out, at full
               turn. Nothing at rest, so the pile's density is unaffected until
               someone taps. */
            const kTurnMargin = 8;

            /* kBookBoardSquareRatio (3/240 of the height) and
               kBookForeEdgeSquareRatio (6/196 of the width). */
            const BOARD_SQ = 3 / 240,
                FORE_SQ = 6 / 196;

            /* bookOpacityList, from lib/constants/constants.dart. */
            const OPS = [0.4, 0.7, 1.0];

            /* kGeneratedCoverPalette, verbatim. Every book in the read pile is
               drawn with a generated cover, which is the honest choice: these
               are the app's own six swatches, harmonised with the brand green,
               and `generatedCoverColor` picks one with `bookHash(isbn) % 6`. */
            const COVER_PALETTE = [
                "#09BC8A" /* brand green */,
                "#0E7C7B" /* deep teal   */,
                "#2F6690" /* slate blue  */,
                "#E0644E" /* coral       */,
                "#F2B544" /* amber       */,
                "#7C5CBF" /* violet      */,
            ];
            function generatedCoverColor(isbn) {
                if (!isbn) return COVER_PALETTE[0];
                return COVER_PALETTE[bookHash(isbn) % COVER_PALETTE.length];
            }

            /* bookBoardColorFor: the cover darkened by `0.18 + 0.30 * luminance`,
               so a black cover barely needs darkening to separate from paper and
               a white one needs a lot. Luminance is the sRGB relative luminance
               Flutter's `Color.computeLuminance` computes, threshold and all. */
            function hexRgb(h) {
                return [
                    parseInt(h.slice(1, 3), 16),
                    parseInt(h.slice(3, 5), 16),
                    parseInt(h.slice(5, 7), 16),
                ];
            }
            function lin(v) {
                v /= 255;
                return v <= 0.03928
                    ? v / 12.92
                    : Math.pow((v + 0.055) / 1.055, 2.4);
            }
            function luminance(hex) {
                const c = hexRgb(hex);
                return (
                    0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
                );
            }
            function bookBoardColorFor(hex) {
                const t = 0.18 + 0.3 * luminance(hex);
                const c = hexRgb(hex).map(function (v) {
                    return Math.round(v * (1 - t));
                });
                return (
                    "#" +
                    c
                        .map(function (v) {
                            return v.toString(16).padStart(2, "0");
                        })
                        .join("")
                );
            }

            /* WCAG 1.4.3, so the tinted spines can be measured rather than
               eyeballed. `brand` is decoration-only by contract precisely
               because it scores 2.45:1; a spine that carries a title is not
               decoration, and the same test has to be applied to whatever
               tone replaces it. */
            function contrastRatio(a, b) {
                const l1 = Math.max(luminance(a), luminance(b));
                const l2 = Math.min(luminance(a), luminance(b));
                return (l1 + 0.05) / (l2 + 0.05);
            }

            function hex(c) {
                return (
                    "#" +
                    c
                        .map(function (v) {
                            return Math.max(0, Math.min(255, Math.round(v)))
                                .toString(16)
                                .padStart(2, "0");
                        })
                        .join("")
                );
            }
            function mix(a, b, t) {
                const x = hexRgb(a),
                    y = hexRgb(b);
                return hex([
                    x[0] + (y[0] - x[0]) * t,
                    x[1] + (y[1] - x[1]) * t,
                    x[2] + (y[2] - x[2]) * t,
                ]);
            }
            /* Chroma as a fraction of the brightest channel — HSV saturation.
               Cheap, and it is the axis that matters here: what makes a tint
               read as a book rather than as a hole in the shelf is whether it
               has any colour left at all, not how light it is. */
            function saturation(h) {
                const c = hexRgb(h);
                const mx = Math.max.apply(null, c),
                    mn = Math.min.apply(null, c);
                return mx === 0 ? 0 : (mx - mn) / mx;
            }

            /* The floor under a low-chroma cover's tint.

               These four constants and the function below are a port of
               `spineTintFor` in lib/ui/widgets/book/book_chassis.dart. Keep them
               in step: this page is the design record for the shipped function,
               and a drawing that disagrees with the code is worse than no
               drawing. */
            const kTintMinSaturation = 0.18;
            /* Borrowed from the brand, not invented: a pale cover's tint ends up
               a desaturated version of the app's own green rather than an
               arbitrary hue. */
            const kTintChromaLift = 0.45;
            /* A hair over AA's 4.5, so rounding cannot leave a tint just short. */
            const kTintMinContrast = 4.6;

            /* The colour a *spine* is filled with, as against the colour the
               chassis paints its back board.

               `bookBoardColorFor` alone is not enough here and the rendered row
               is what showed it. It multiplies toward black, so a cover
               averaging #DCD8D1 lands on a dead neutral grey: in a row of
               coloured spines that reads as a gap in the shelf, and it misses
               AA for the 12pt title it now has to carry. Darkening further fixes
               the contrast and makes the grey deader.

               So two steps before the board tone, each one a no-op for a cover
               that does not need it:

                 1. Lift the chroma of a washed-out cover by blending it toward
                    `brand`. Scaled by how far below `kTintMinSaturation` it sits
                    *and by its luminance*. The second factor is not decoration:
                    gated on chroma alone the lift fires on a **black** cover as
                    hard as on a white one — black has no chroma either — and a
                    black jacket came out a dark green spine. A pale neutral goes
                    dead; a dark neutral already reads as a book.
                 2. Darken until white clears `kTintMinContrast`. A bounded
                    stepwise walk rather than a closed form, because the target
                    is a contrast ratio and the ratio is not linear in the mix.
                    This step fires on some fully saturated covers too — the
                    amber in `kGeneratedCoverPalette` boards at 4.02:1.

               A board is unaffected by either: nothing is written on it, and it
               is seen against the cover it came from rather than against type. */
            function spineTintFor(cover) {
                const s = saturation(cover);
                const lift =
                    Math.max(0, (kTintMinSaturation - s) / kTintMinSaturation) *
                    luminance(cover) *
                    kTintChromaLift;
                let c = bookBoardColorFor(mix(cover, "#09BC8A", lift));
                for (
                    let i = 0;
                    i < 24 && contrastRatio(c, "#FFFFFF") < kTintMinContrast;
                    i++
                ) {
                    c = mix(c, "#000000", 0.06);
                }
                return c;
            }

            /* Today's spine: BookVertical's defaults. */
            const SPINE_W = 26,
                SPINE_H = 124;

            /* ReadPile's parts. _rowExtent is 124 + the 13 a praised spine
               grows by, so praise cannot change the pile's height. */
            const TOP_GAP = 14,
                ROW_EXTENT = 137,
                SHELF_H = 8,
                BOTTOM_PAD = 10;
            const PILE_EXTENT = TOP_GAP + ROW_EXTENT + SHELF_H + BOTTOM_PAD;

            /* The proposal's spine-width range. Mapped from the book's
               *position* in the thickness range rather than from the resolved
               factor, which is the same move `bookThicknessPositionFromPages`
               already makes and for the same reason: thicknessFactor is tuned
               for a 3D fore-edge a few pixels wide, and 0.36-0.52 of the cover
               is 28-43pt on a flat spine. Centred on 26 so the pile's density
               is exactly today's. */
            const NARROW = [21, 31];

            /* ---- bookHash: 32-bit FNV-1a, split so no intermediate exceeds
               2^53. Written with * and % rather than << and &, because JS
               bitwise operators coerce to *signed* int32 and `(h & 0xff) << 24`
               goes negative for any high byte >= 128 — which silently produced
               a different hash than the Dart for about half of all inputs. ---- */
            function mulFnvPrime(h) {
                return ((h & 0xff) * 0x1000000 + h * 403) % 0x100000000;
            }
            function bookHash(s) {
                let h = 0x811c9dc5;
                for (let i = 0; i < s.length; i++) {
                    const u = s.charCodeAt(i);
                    h = mulFnvPrime((h ^ (u & 0xff)) >>> 0);
                    if (u > 0xff) h = mulFnvPrime((h ^ ((u >> 8) & 0xff)) >>> 0);
                }
                return h;
            }

            /* bookThicknessPositionFromPages. Log-scaled between 100 and 900,
               so 300 pages — the archetypal trade book — lands mid-range, and
               a 1,500-page reference book clamps instead of pinning the top.
               Anything under 20 pages is treated as absent, because Google
               Books answers `pageCount: 0` rather than omitting the key. */
            function pagePos(p) {
                if (p == null || p < 20) return null;
                const lo = Math.log(100),
                    hi = Math.log(900);
                return Math.min(
                    1,
                    Math.max(0, (Math.log(p) - lo) / (hi - lo)),
                );
            }

            /* BookJitter.fromIsbn, as normalised positions in [0,1].
               Positions rather than factors for the same reason the golden test
               pins positions: the ranges are design values that have been
               retuned three times, the hash is the part that must never move. */
            function bookPos(isbn, pages) {
                const fp = pagePos(pages);
                if (!isbn) {
                    /* No ISBN means no hash worth taking: bookHash('') is just
                       the FNV offset basis, identical for every such book. So
                       height falls back to neutral — factor 1.0, which is
                       position 0.5 — but a page count is still real data. */
                    return { h: 0.5, t: fp == null ? 0 : fp, fromPages: fp != null };
                }
                const hash = bookHash(isbn);
                /* Two draws from disjoint 16-bit halves, so height and
                   thickness do not correlate — otherwise every tall book
                   would also be a thick one. */
                return {
                    h: (hash & 0xffff) / 0xffff,
                    t: fp == null ? ((hash >>> 16) & 0xffff) / 0xffff : fp,
                    fromPages: fp != null,
                };
            }

            /* Everything needed to draw one book in the pile.
               opt = { base, wmode, uniform } where base is the pre-jitter spine
               height, wmode is 'narrow' or 'true', and uniform draws today's
               fixed 26x124 instead. */
            function geom(bk, opt, index) {
                const o = opt || {};
                const p = bookPos(bk.isbn, bk.pages);
                const h = o.uniform
                    ? SPINE_H
                    : (o.base || 117) * (HF0 + p.h * (HF1 - HF0));
                const cw = h * ASPECT;
                const tk = o.uniform
                    ? SPINE_W
                    : o.wmode === "true"
                      ? cw * (TF0 + p.t * (TF1 - TF0))
                      : NARROW[0] + p.t * (NARROW[1] - NARROW[0]);
                const op = OPS[index % OPS.length];
                /* A real thumbnail's average colour where there is one, and the
                   generated cover's swatch where there is not. `bookBoardColorFor`
                   of it either way, which is exactly what the chassis does for
                   its back board. */
                const cover = bk.avg || generatedCoverColor(bk.isbn);
                return {
                    p,
                    h,
                    cw,
                    tk,
                    op,
                    cover,
                    gen: !bk.avg,
                    /* The chassis's back board: `bookBoardColorFor`, unchanged. */
                    board: bookBoardColorFor(cover),
                    /* The spine's fill, which has a title on it and therefore a
                       floor. Equal to `board` for every cover that needs no
                       help, which is most of them. */
                    tintc: spineTintFor(cover),
                    /* The title's box before RotatedBox turns it: the spine's
                       height less the 15pt padding at each end. */
                    th: h - 30,
                    sq: h * BOARD_SQ,
                    fes: cw * FORE_SQ,
                };
            }

            /* The width the row must give a turning book.
               cover*|cos| + thickness*|sin|: at 0 it is the cover, at -90 it is
               the spine, and in between it is what makes the neighbours slide
               rather than being overlapped. */
            function projected(g, deg) {
                const r = (deg * Math.PI) / 180;
                return (
                    Math.abs(g.cw * Math.cos(r)) + Math.abs(g.tk * Math.sin(r))
                );
            }

            function px(n) {
                return Math.round(n * 100) / 100 + "px";
            }

            /* Which way the title on a spine has to go.

               Untinted, this is BookVertical's own rule: white above opacity
               0.7, `primaryText` at or below, because a 0.4 spine cannot carry
               white text.

               Tinted, it is always white, and that is a consequence of
               `spineTintFor` rather than a coincidence: the floor exists so that
               every tint can carry one colour of type. Choosing per spine was
               the earlier answer and it left exactly one dark-on-pale label in a
               row of white ones, which looked like a mistake. */
            function paleFill(bk, g) {
                return bk.tint ? false : g.op <= 0.7;
            }

            /* ---------- a resting spine: today's BookVertical ---------- */
            function spine(bk, g) {
                const pale = paleFill(bk, g) ? " pale" : "";
                /* Tinted spines take `bookBoardColorFor(coverColour)` rather
                   than the cover colour raw: that is the tone the chassis
                   already paints its board with, and an untinted swatch beside
                   the cover it came from reads as two objects. */
                const bg = bk.tint ? g.tintc : "rgba(9,188,138," + g.op + ")";
                return (
                    '<s class="sp' +
                    pale +
                    (bk.tint ? " tint" : "") +
                    '" style="--sw:' +
                    px(g.tk) +
                    ";--sh:" +
                    px(g.h) +
                    ";--th:" +
                    px(g.th) +
                    ";--bg:" +
                    bg +
                    ';"><b><span>' +
                    bk.title +
                    "</span></b></s>"
                );
            }

            /* ---------- a book part-way through the turn ----------
               Four faces under one rotation, exactly as BookChassis composes
               three: back board, page block, cover, and the spine face this
               proposal adds.

               `deg` is the *Flutter* turn, so it reads the same as
               `kBookTurnAngle` and the same as the widget's own field: -90 is
               spine-on, 0 is cover-on, +16 is the held book. CSS turns the
               other way (see frame.css), so the angle handed to the transform
               is -deg. */
            function turned(bk, g, deg) {
                const pale = paleFill(bk, g) ? " pale" : "";
                const bg = bk.tint ? g.tintc : "rgba(9,188,138," + g.op + ")";
                const css = -deg;
                const r = (css * Math.PI) / 180;
                /* The pivot is the cover's left edge, so at rest the spine hangs
                   a thickness to the left of it. Shift the drawing back so its
                   left edge is the box's. Only for a positive CSS angle: past
                   cover-on the spine is behind the cover and contributes
                   nothing to the left. */
                const ox = Math.max(0, g.tk * Math.sin(r));
                /* Air either side of a book that has been pulled out.

                   Flush was wrong and it took seeing it: the turned cover sat
                   hard against the spines on both sides, which reads as a book
                   wedged in place rather than one taken off the shelf — and it
                   clipped the stacked shadows that are the only thing separating
                   a cover from the plank. Driven by the same progress as the
                   turn, so the resting pile is untouched and the gap opens as
                   the book comes out. */
                const t = Math.max(0, Math.min(1, (deg + 90) / 90));
                const sm = kTurnMargin * t;
                const vars =
                    "--sh:" +
                    px(g.h) +
                    ";--cw:" +
                    px(g.cw) +
                    ";--tk:" +
                    px(g.tk) +
                    ";--pw:" +
                    px(projected(g, deg)) +
                    ";--ox:" +
                    px(ox) +
                    ";--sm:" +
                    px(sm) +
                    ";--persp:" +
                    px(g.cw * PERSP) +
                    ";--sq:" +
                    px(g.sq) +
                    ";--fes:" +
                    px(g.fes) +
                    ";--fs:" +
                    px(g.cw * 0.135) +
                    ";--turn:" +
                    css +
                    "deg;--c:" +
                    g.cover +
                    ";--boardc:" +
                    g.board;
                const coverFace = g.gen
                    ? '<span class="cf"><span class="cblk"></span>' +
                      '<span class="ctit">' +
                      bk.title +
                      "</span>"
                    : '<span class="cf art' +
                      (luminance(g.cover) > 0.45 ? " dk" : "") +
                      '"><span class="aband"></span>' +
                      '<span class="atit">' +
                      bk.title +
                      "</span>";
                /* Written in BookChassis's paint order &mdash; board, pages,
                   spine, cover &mdash; even though CSS sorts a preserve-3d
                   context by depth and would accept any order. The drawing is
                   the record of the implementation, and a reader who sees the
                   spine last here will write it last there, where it is wrong.
                   See the paint-order note in frame.css. */
                return (
                    '<span class="bk" style="' +
                    vars +
                    '"><span class="in">' +
                    '<span class="bb"></span>' +
                    '<span class="pb"></span>' +
                    '<span class="sf sp' +
                    pale +
                    '" style="--bg:' +
                    bg +
                    ";--th:" +
                    px(g.th) +
                    '"><b><span>' +
                    bk.title +
                    "</span></b></span>" +
                    coverFace +
                    '<span class="bind"></span>' +
                    '<span class="hair"></span></span>' +
                    "</span></span>"
                );
            }

            /* ---------- a top-down plan of the turn ----------
               Looking down on the book, reader at the bottom of the box. The
               cover's direction is the +x axis turned by `deg` (clockwise on
               screen is toward the reader), and the spine is always 90 behind
               it, so at rest the spine lies along the box and the cover points
               straight away. The hinge is held fixed here, unlike the drawn
               item, which is shifted so its left edge is its box's. */
            function plan(deg, label) {
                const r = (deg * Math.PI) / 180;
                const cov = Math.abs(62 * Math.cos(r));
                const spn = Math.abs(22 * Math.sin(r));
                return (
                    '<div class="plan"><span class="ang">' +
                    (deg > 0 ? "+" : "") +
                    deg +
                    "&deg;</span>" +
                    '<i class="cvl" style="transform:rotateZ(' +
                    deg +
                    'deg)"></i>' +
                    '<i class="spl" style="transform:rotateZ(' +
                    (deg - 90) +
                    'deg)"></i>' +
                    '<i class="hg"></i>' +
                    '<i class="prj" style="left:' +
                    px(46 - spn) +
                    ";width:" +
                    px(cov + spn) +
                    '"></i>' +
                    '<span class="pl">' +
                    label +
                    "</span></div>"
                );
            }

            /* ---------- the corpus ----------
               The first six ISBNs are the ones test/book_geometry_test.dart
               pins goldens for, so their drawn proportions are checkable
               against the app's own test file. The rest come from that test's
               own `_syntheticIsbns` generator, `978${1000000000 + i * 7919}`.

               The titles are labels, chosen for legibility on a 26pt spine and
               to match the corpus the earlier mockup sets use. They are NOT a
               claim about which book each ISBN identifies — the geometry comes
               from the ISBN alone, and swapping a title changes nothing here.

               `pages` is set on two of them on purpose. Where a credible page
               count exists it replaces the hash for thickness, so those two
               books are the only ones on the page whose width is real data.
               The measurement table marks them.

               `avg` is the colour `_sampleCoverColor` would average out of the
               book's artwork — the 1x1 GPU downsample the chassis already does
               to pick its back board. **Most read books have a real cover**, so
               most of these carry one, and it is what a tinted spine would be
               derived from. These particular values are estimates for a cover of
               that kind, not measurements: measuring needs the artwork, and the
               artwork is not in this repo. Two books deliberately have no `avg`
               at all — the coverless case, which falls back to
               `generatedCoverColor` and the six swatches — and one is
               deliberately pale, because that is the case where darkening the
               cover does not produce a tint white type can sit on. */
            const CORPUS = [
                {
                    isbn: "9788936434120",
                    title: "Shoe Dog",
                    pages: 224,
                    avg: "#2A1C14",
                },
                { isbn: "9780451524935", title: "Eragon", avg: "#2E4E7A" },
                {
                    isbn: "9780141439518",
                    title: "Brisingr",
                    pages: 640,
                    avg: "#8A6A2E",
                },
                { isbn: "9791188331796", title: "Eldest", avg: "#8E2F2A" },
                {
                    isbn: "9788954682152",
                    title: "\uc77c\uc744 \uc798 \ub9e1\uae34\ub2e4\ub294 \uac83",
                    avg: "#1E3A5C",
                },
                { isbn: "OL12345W", title: "Start With Why", avg: "#B03A2E" },
                /* A pale cover. The one that stresses the contrast floor. */
                { isbn: "9781000000000", title: "The White Book", avg: "#DCD8D1" },
                { isbn: "9781000007919", title: "Kim Jiyoung", avg: "#4E6EA8" },
                /* Coverless: no thumbnail, so a generated cover and a palette
                   swatch. Roughly the proportion the corpus has. */
                { isbn: "9781000015838", title: "The Hole" },
                { isbn: "9781000023757", title: "Norwegian Wood", avg: "#20553F" },
                { isbn: "9781000031676", title: "Tokyo Ueno Station", avg: "#3A3F4B" },
                { isbn: "9781000039595", title: "Please Look After Mom", avg: "#A8465F" },
                { isbn: "9781000047514", title: "Convenience Store Woman" },
            ];

            /* ---------- the pile ----------
               b = { style, tint, open, turn, h, empty }

               `style` names a set of geometry options rather than spelling them
               out at every call site. That indirection is what lets a rejected
               version restate one short field instead of a whole spec, and it
               is derived from the decided spec rather than copied, so a change
               to the decided design cannot leave a branch drawing the old one.

               `open` is an index into CORPUS; that book is drawn turning and
               every other one is a resting spine. One at a time by
               construction, which is also what keeps the hero tag unique — see
               the callout on the `turn-out` flow. */
            const PILE_STYLES = {
                /* Today, for reference: a fixed 26x124 and the opacity cycle. */
                shipped: { uniform: true },
                /* The decided design: real chassis thickness, cover-toned. */
                decided: { wmode: "true", tint: true },
                /* Rejected: true widths, brand spines. */
                green: { wmode: "true" },
                /* Rejected: widths remapped to 21-31, brand spines. */
                remap: { wmode: "narrow" },
            };

            function pileBlock(b) {
                const style = PILE_STYLES[b.style || "decided"];
                const opt = {
                    uniform: !!style.uniform,
                    base: b.base || 117,
                    wmode: style.wmode || "narrow",
                };
                const tint = style.tint === true;
                let inner;
                if (b.empty) {
                    inner =
                        '<div class="pempty">' +
                        (b.year
                            ? "No books recorded for " + b.year
                            : "No books read yet &#129394;") +
                        "</div>";
                } else {
                    inner =
                        '<div class="prow">' +
                        CORPUS.map(function (bk, i) {
                            const g = geom(bk, opt, i);
                            const tinted = tint
                                ? Object.assign({}, bk, { tint: true })
                                : bk;
                            return i === b.open
                                ? turned(tinted, g, b.turn === undefined ? 0 : b.turn)
                                : spine(tinted, g);
                        }).join("") +
                        "</div>";
                }
                return (
                    '<div class="pile" style="--pile:' +
                    px(b.h || PILE_EXTENT) +
                    '">' +
                    inner +
                    '<div class="plank"></div><div class="ppad"></div></div>'
                );
            }

            function block(b) {
                switch (b.t) {
                    case "pile":
                        return pileBlock(b);
                    case "text":
                        return (
                            '<div class="txt' +
                            (b.dim ? " dim" : "") +
                            '">' +
                            b.v +
                            "</div>"
                        );
                    default:
                        return "";
                }
            }
            function blocks(list) {
                return (list || []).map(block).join("");
            }

            /* The library behind the card. Two shelves, dimmed: a backdrop, and
               the thing a taller pile takes its 7pt from. */
            function libBack() {
                let rows = "";
                for (let r = 0; r < 2; r++) {
                    rows +=
                        '<div class="lrow">' +
                        CORPUS.slice(r * 5, r * 5 + 5)
                            .map(function (bk, i) {
                                return (
                                    '<i class="lcv" style="--c:' +
                                    (bk.avg || generatedCoverColor(bk.isbn)) +
                                    ";height:" +
                                    (78 + ((i * 5 + r * 3) % 9)) +
                                    'px"></i>'
                                );
                            })
                            .join("") +
                        '</div><div class="lplank"></div>';
                }
                return '<div class="lib faded">' + rows + "</div>";
            }

            function tabBar(on) {
                return (
                    '<div class="tbb"><div class="tp">' +
                    ["Library", "Friends", "Card"]
                        .map(function (t) {
                            return (
                                '<s class="' +
                                (t === (on || "Library") ? "on" : "") +
                                '">' +
                                t +
                                "</s>"
                            );
                        })
                        .join("") +
                    '</div><div class="orb">&#128269;</div></div><div class="ind"></div>'
                );
            }

            /** Draw one screen from its spec. */
            function frame(s) {
                if (s.kind === "dtl") return detailsFrame(s);
                const pile = s.pile || {};
                /* The frame height is fixed and the card grows *upward* into
                   the library, which is the whole point of drawing the library
                   at all: a pile 7pt taller is 7pt the shelves lose. Sizing the
                   frame to the card instead kept the backdrop constant and hid
                   the only cost the height question has. */
                return (
                    '<div class="fr" style="--fh:' +
                    px(s.fh || 430) +
                    '">' +
                    libBack() +
                    '<div class="card">' +
                    '<div class="hdl"></div>' +
                    '<div class="hd"><span class="lt">Books read <i>' +
                    (s.count === undefined ? 42 : s.count) +
                    '</i></span><span class="pop">' +
                    (s.filter || "All time") +
                    " <u>&#9660;</u></span></div>" +
                    pileBlock(pile) +
                    "</div>" +
                    tabBar("Library") +
                    "</div>"
                );
            }

            /* The details page, for the last step of the turn-out flow. The
               cover here is the same `turned()` at 0 degrees and height 180,
               which is the point: it is the destination of a Hero flight, so
               the two ends have to be the same object at two sizes. */
            function detailsFrame(s) {
                const bk = CORPUS[s.book || 0];
                const g = geom(bk, { base: 180 / (HF0 + bookPos(bk.isbn, bk.pages).h * (HF1 - HF0)) }, s.book || 0);
                return (
                    '<div class="fr dtl" style="--fh:430px">' +
                    '<div class="nav"><span class="back">&#8249;</span></div>' +
                    '<div class="dhero">' +
                    turned(bk, g, 0) +
                    '<div class="drt"><div class="dt">' +
                    bk.title +
                    '</div><div class="da">' +
                    bk.isbn +
                    "</div></div></div>" +
                    '<div class="dshelf"></div>' +
                    '<div class="dcaps"><s class="on">Book info</s><s>Notes</s></div>' +
                    '<div style="padding-top:14px"><div class="dline" style="width:56%"></div>' +
                    '<div class="dline"></div><div class="dline"></div>' +
                    '<div class="dline" style="width:72%"></div></div>' +
                    "</div>"
                );
            }

            /* ==================================================================
   SECTION 3: DATA.

   SCREENS  [group, [ [id, name, note, spec], ... ] ]
   FLOWS    [group, [ [id, name, note, [ [stepName, stepNote, spec], ... ] ] ] ]
   ELEMENTS [group, [ [id, name, note, demoHTML], ... ] ]
   ================================================================== */
            /* Shared specs, so a corrected screen cannot leave a flow drawing
               the old one. Every pile on the page is one of these, and the
               rejected versions derive theirs from them with `restyle` below
               rather than restating them. */
            const OPEN_AT = 4; /* mid-row, so the slide is visible both ways */
            const SWITCH_AT = 8; /* the book opened second, in `switch-book`   */

            const TODAY = { t: "pile", style: "shipped" };
            const EMPTY = { t: "pile", empty: true, year: 2025 };
            const PILE = { t: "pile" };
            const PILE_STRETCH = { t: "pile", h: PILE_EXTENT + 40 };
            const TURN_MID = { t: "pile", open: OPEN_AT, turn: -45 };
            const TURN_REST = { t: "pile", open: OPEN_AT, turn: 0 };
            const TURN_HELD = { t: "pile", open: OPEN_AT, turn: HOLD };
            const SWITCH_MID = { t: "pile", open: SWITCH_AT, turn: -45 };
            const SWITCH_REST = { t: "pile", open: SWITCH_AT, turn: 0 };

            /* A pile block, restyled into a whole screen spec. Used only by the
               rejected versions: they differ from the decided design in the
               pile's style and in nothing else, so this is the whole of their
               patch, and it is *derived* from the decided block rather than
               copied — a correction to the decided design cannot leave a branch
               drawing the old one. */
            function restyle(pile, style) {
                return { pile: Object.assign({}, pile, { style }) };
            }

            /* The same, for the height budget: a different pre-jitter base, and
               the taller pile a taller row forces. A block that had raised `h`
               itself keeps the difference, so the stretched screen stays 40pt
               past its own detent rather than 40pt past the decided one. */
            function rebase(pile, base, extent) {
                const out = Object.assign({}, pile, { base });
                out.h =
                    pile.h === undefined ? extent : extent + (pile.h - PILE_EXTENT);
                return { pile: out };
            }

            const SCREENS = [
                [
                    "Decided",
                    [
                        [
                            "pile-jitter",
                            "Read pile &middot; hashed sizes, cover-toned",
                            "<b>The decided design.</b> Thirteen books whose height, width and tone all come from what the app already knows about them.<br /><br />Height is base 117 times a factor in [0.94, 1.06], so the tallest book is exactly today's 124 and <code>ReadPile.extent</code> does not move &mdash; <code>bookRowExtent()</code> already says a row must reserve <code>base &times; maxHeightFactor</code>, and 124&nbsp;/&nbsp;1.06 is 117. Width is <code>BookMetrics.thickness</code> itself, 28 to 39pt against today's flat 26, so the spine is as thick as the book it turns into and nothing has to be reconciled between the two states. Two of the thirteen take their thickness from a real page count rather than the hash. Tone is <code>bookBoardColorFor</code> of the book's own cover, from a stored <code>cover_color</code>; the two coverless ones fall back to their generated cover's swatch, which is a colour rather than an absence, so the row still reads as one material.<br /><br />The 1pt line down each spine's right edge is new and not optional: the horizontal <code>ListView</code> has no separator, which is invisible while the row is one green at three opacities and reads as a solid slab once every spine has its own tone.",
                            { pile: PILE },
                        ],
                        [
                            "pile-stretch",
                            "Read pile &middot; dragged up 40pt",
                            "The state between the collapsed detent and the month grid's swap point. The plank stays on the card's bottom edge and the headroom opens above the books, which is what the last change shipped &mdash; drawn here because a taller pile is where a jittered row could have gone wrong and did not: the books are bottom-aligned on the shelf, so a short book gains its headroom at the top like every other one.",
                            { pile: PILE_STRETCH },
                        ],
                    ],
                ],
                [
                    "Turning one out",
                    [
                        [
                            "pile-mid",
                            "Turning &middot; halfway",
                            "One tap in, 45&deg; of 90 &mdash; and this is the frame that caught the sign error the first draft shipped with. Turned the other way the book swung its fore-edge through the reader and the spine disappeared behind the cover, which is a book turning inside out. Turned correctly it is a three-quarter view: the spine on the left of the hinge, the cover foreshortened to its right, the two meeting along the hinge line and never overlapping, and the fore-edge never in sight. The hinge is the spine's own edge, so it stays put and the book opens toward the reader &mdash; the motion of pulling one off a shelf. The row gives the item <code>cover&times;|cos| + thickness&times;|sin|</code> of width, so its neighbours slide rather than being painted over.",
                            { pile: TURN_MID },
                        ],
                        [
                            "pile-open",
                            "Turned out &middot; at rest",
                            "The end of the turn: the book's cover, at the same 2:3 and with the same binding band, hairline and stacked shadows as a book on a shelf. Most read books have a real thumbnail, and that is what this is standing in for; the two coverless ones in the row get a <code>GeneratedCover</code> instead &mdash; a swatch block over a <code>surface</code>-toned title half, picked by <code>bookHash(isbn) % 6</code>. The tapped spine's tone and this cover are the same colour family by construction, because one is derived from the other. Note what it costs: this is the first cover the collapsed Library tab has ever had to load, and it loads exactly one.",
                            { pile: TURN_REST },
                        ],
                        [
                            "pile-hold",
                            "Turned out &middot; held",
                            "Stage one of the hold, +16&deg;, the same <code>kBookTurnAngle</code> the shelves use &mdash; and the same 140ms delay, so an ordinary tap produces no rotation at all. The fore-edge appears because the page block stands back from the boards on every side. There is no stage two here: <code>onLongPress</code> enters edit mode on the shelves, and the pile has no edit mode, so the hold is feedback and nothing else.",
                            { pile: TURN_HELD },
                        ],
                    ],
                ],
                [
                    "Unchanged",
                    [
                        [
                            "pile-today",
                            "Read pile &middot; as shipped",
                            "<b>Not a proposal &mdash; the baseline.</b> Thirteen identical 26&times;124 spines, flush against each other, the row a solid band of green graded 0.4&thinsp;/&thinsp;0.7&thinsp;/&thinsp;1.0 by index. Kept on the page because every claim above is a claim about a difference from this, and because it is the drawing that shows why the missing separator was never a problem before.",
                            { pile: TODAY },
                        ],
                        [
                            "pile-empty",
                            "Read pile &middot; empty",
                            "Unchanged, and included so it stays visible: the message is centred in the room <i>above the shelf</i>, which is the room that grows when the sheet is dragged. Nothing in this proposal touches it.",
                            { pile: EMPTY, count: 0, filter: "2025" },
                        ],
                    ],
                ],
            ];

            const FLOWS = [
                [
                    "Reading the pile",
                    [
                        [
                            "turn-out",
                            "Spine &rarr; cover &rarr; details",
                            "Two taps to the details page where there is one today. The first tap buys something the pile has never offered: seeing what a book looks like without leaving the tab.",
                            [
                                [
                                    "At rest",
                                    "Thirteen spines, each the tone of its own cover. The tap target is the full 137pt column, because the horizontal list gives its children tight cross-axis constraints &mdash; already true today.",
                                    { pile: PILE },
                                ],
                                [
                                    "Turning",
                                    "-45&deg;. Driven by one <code>AnimationController</code> at <code>kBookTurnDuration</code> 260ms, the same rate a shelf book turns at, so the two motions cannot look like different mechanisms.",
                                    { pile: TURN_MID },
                                ],
                                [
                                    "Turned out",
                                    "A cover on the shelf, in the colour family its spine was. Tapping another spine turns this one back &mdash; one open at a time.",
                                    { pile: TURN_REST },
                                ],
                                [
                                    "Held",
                                    "+16&deg; after 140ms of contact, then unwinds over 180ms on release. The fore-edge comes into view because the page block stands back from the boards. Release without moving is a tap, and a tap navigates.",
                                    { pile: TURN_HELD },
                                ],
                                [
                                    "Details",
                                    "The cover flies. Same <code>book_&lt;isbn&gt;</code> Hero tag the shelves use, same <code>MaterialRectCenterArcTween</code> and <code>FittedBox</code> shuttle, so the aspect ratio holds for the whole flight.",
                                    { kind: "dtl", book: OPEN_AT },
                                ],
                            ],
                        ],
                        [
                            "switch-book",
                            "Opening a second book",
                            "Why one at a time is the right rule, and not only for tidiness: the hero tag is <code>book_&lt;isbn&gt;</code>, and about fifteen migrated books have no ISBN at all. Tagging every spine would put several <code>book_</code> heroes in one subtree, which throws. Tagging only the open book makes the tag unique by construction.",
                            [
                                [
                                    "One open",
                                    "The mid-row book turned out, the rest spines.",
                                    { pile: TURN_REST },
                                ],
                                [
                                    "Tap another",
                                    "Both animate at once: the new one out, the old one back. Same controller timings in both directions.",
                                    { pile: SWITCH_MID },
                                ],
                                [
                                    "Settled",
                                    "The Hole is out and the first book is a spine again. Filtering by year, dragging past the grid's swap point, or entering edit mode all close it.",
                                    { pile: SWITCH_REST },
                                ],
                            ],
                        ],
                    ],
                ],
            ];

            /* The measurement table: every drawn number, per book, so the
               drawing can be checked rather than believed. */
            function mtable(opt) {
                const rows = CORPUS.slice(0, 6)
                    .map(function (bk, i) {
                        const g = geom(bk, opt, i);
                        return (
                            "<tr><td>" +
                            bk.title +
                            "</td><td>" +
                            bk.isbn +
                            "</td><td>" +
                            g.p.h.toFixed(4) +
                            "</td><td>" +
                            g.h.toFixed(1) +
                            "</td><td>" +
                            g.p.t.toFixed(4) +
                            (g.p.fromPages ? "*" : "") +
                            '</td><td class="hi">' +
                            g.tk.toFixed(1) +
                            "</td></tr>"
                        );
                    })
                    .join("");
                return (
                    '<table class="mtbl"><tr><th>Book</th><th>ISBN</th>' +
                    "<th>height pos</th><th>height</th><th>thick pos</th><th>spine w</th></tr>" +
                    rows +
                    "</table>"
                );
            }

            function spineStrip(opt, tint) {
                return (
                    '<div class="onwhite">' +
                    CORPUS.slice(0, 6)
                        .map(function (bk, i) {
                            const g = geom(bk, opt, i);
                            return spine(
                                tint ? Object.assign({}, bk, { tint: true }) : bk,
                                g,
                            );
                        })
                        .join("") +
                    "</div>"
                );
            }

            /* What a tinted pile actually costs, computed rather than typed so
               these numbers cannot go stale. Two things worth measuring: how
               many of the drawn books would need a *decoded image* before their
               spine had a colour at all, and whether every resulting tint can
               carry a title. */
            function tintContrastNote() {
                const drawn = CORPUS.map(function (bk, i) {
                    const g = geom(bk, { base: 117 }, i);
                    return {
                        title: bk.title,
                        cover: g.cover,
                        plain: bookBoardColorFor(g.cover),
                        tint: g.tintc,
                        gen: g.gen,
                        r: contrastRatio(g.tintc, "#FFFFFF"),
                        was: contrastRatio(bookBoardColorFor(g.cover), "#FFFFFF"),
                    };
                });
                const needsDecode = drawn.filter(function (x) {
                    return !x.gen;
                }).length;
                const worst = drawn.slice().sort(function (a, b) {
                    return a.r - b.r;
                })[0];
                const lifted = drawn.filter(function (x) {
                    return x.tint !== x.plain;
                });
                return (
                    '<div class="cap"><b>The tint needs a stored colour, and that is the whole of its cost.</b> ' +
                    needsDecode +
                    " of these " +
                    CORPUS.length +
                    " books have a real thumbnail, so their tone is <code>_sampleCoverColor</code>'s 1x1 downsample of artwork that has to be fetched and decoded. The collapsed pile loads no images today, and worse than the bytes is the timing: until each image resolves the spine has no colour, so a cold start would paint the pile grey and colour it in. <code>book_widget.dart</code> already refuses that bargain for a neighbouring value \u2014 <code>pageCount</code> must come from a stored column, because a count arriving mid-session would make a book visibly change thickness on screen. Hence <code>books.cover_color</code>, read from the row and never from a live decode.</div>" +
                    '<div class="cap"><b>Every tint clears AA, and ' +
                    lifted.length +
                    " of " +
                    CORPUS.length +
                    " needed help to.</b> <code>bookBoardColorFor</code> multiplies toward black, so a washed-out cover lands on a dead neutral grey \u2014 <code>" +
                    (lifted[0] ? lifted[0].cover + "</code> \u2192 <code>" + lifted[0].plain + "</code> at " + lifted[0].was.toFixed(2) + ":1, a colour with no chroma left, which in a row of coloured spines reads as a gap in the shelf rather than as a pale book. <code>spineTintFor</code> lifts the chroma toward <code>brand</code> below " + kTintMinSaturation + " saturation and then darkens until white clears " + kTintMinContrast + ":1, giving <code>" + lifted[0].tint + "</code> at " + lifted[0].r.toFixed(2) + ":1" : "nothing on this row") +
                    ". Both steps are no-ops for a cover that does not need them, so " +
                    (CORPUS.length - lifted.length) +
                    " of the " +
                    CORPUS.length +
                    " tints are exactly <code>bookBoardColorFor</code>. The worst on the row is now " +
                    worst.r.toFixed(2) +
                    ":1 (" +
                    worst.title +
                    "), so every spine carries white type and there is no per-spine text colour to choose.</div>"
                );
            }

            const ELEMENTS = [
                [
                    "The spine",
                    [
                        [
                            "el-spine-today",
                            "Spine &middot; as shipped",
                            "<code>BookVertical</code>: 26&times;124, <code>brand</code> at one of <code>bookOpacityList</code>'s three values, a 12pt title turned a quarter turn, and a shallow arch across the top &mdash; a quadratic from (0,5) to (w,5) through (w/2,0). The title colour flips at 0.7: white above, <code>primaryText</code> at or below, because a 0.4 spine cannot carry white text.",
                            spineStrip({ uniform: true }) +
                                '<div class="cap">Six identical spines. The only variation in the pile today is the opacity cycle, which repeats every three books.</div>',
                        ],
                        [
                            "el-spine-jitter",
                            "Spine &middot; decided",
                            "The six pinned books at their real chassis thickness, each toned from its own cover. Positions are the values <code>test/book_geometry_test.dart</code> pins, so this table is checkable line by line against that file. Widths are <code>BookMetrics.thickness</code> — 28 to 39pt — and the two rows marked * take theirs from a real page count rather than the hash. The two captions below are what the tone costs; both are computed from the drawn row.",
                            spineStrip({ base: 117, wmode: "true" }, true) +
                                '<div class="cap">Base 117, widths 28&ndash;39. About nine of these fit the 324pt row, against twelve and a half today. * marks a thickness from a real page count.</div>' +
                                tintContrastNote() +
                                mtable({ base: 117, wmode: "true" }),
                        ],
                    ],
                ],
                [
                    "The turn",
                    [
                        [
                            "el-turn-angles",
                            "One book, five angles",
                            "Left to right: the resting spine, two thirds and a third of the way out, the cover, and the held book. The leftmost is the spine face alone &mdash; at -90&deg; the cover is edge-on and projects to nothing &mdash; so it is the same drawing <code>spine()</code> makes, give or take the perspective foreshortening that a face sitting a thickness behind the projection plane picks up. That near-identity is what lets the pile keep drawing flat <code>BookVertical</code>s and swap in the chassis only for the book being turned, so twelve of thirteen books still load no image.",
                            (function () {
                                const bk = CORPUS[OPEN_AT];
                                const g = geom(bk, { base: 117 }, OPEN_AT);
                                return (
                                    '<div class="onwhite" style="gap:26px">' +
                                    [-90, -60, -30, 0, HOLD]
                                        .map(function (d) {
                                            return turned(bk, g, d);
                                        })
                                        .join("") +
                                    "</div>"
                                );
                            })(),
                        ],
                        [
                            "el-plan",
                            "The turn, from above",
                            "Why the interesting number is not the angle. Green is the spine, dark green the cover, the dot is the hinge, and the bracket is the width the row has to give the item: <code>cover&times;|cos| + thickness&times;|sin|</code>. <b>It is not monotonic, and the assertions are what found that:</b> it peaks at <code>&minus;atan(thickness/cover)</code> &mdash; 16.4&deg; for this book, within a degree of <code>kBookTurnAngle</code> by coincidence &mdash; at <code>hypot(cover,&nbsp;thickness)</code>, then narrows again as the cover comes square on. So the neighbours slide out about 3pt further than the cover's final width and settle back over the last third of the turn. That is what a real book does, and 3pt over 90ms is well under what reads as a wobble, but it is a fact about the layout rather than an impression of one.",
                            (function () {
                                const bk = CORPUS[OPEN_AT];
                                const g = geom(bk, { base: 117 }, OPEN_AT);
                                const w = function (d) {
                                    return projected(g, d).toFixed(1) + "pt";
                                };
                                const peak = -(
                                    (Math.atan(g.tk / g.cw) * 180) /
                                    Math.PI
                                );
                                return (
                                    '<div class="swatchrow">' +
                                    plan(-90, "spine on &middot; " + w(-90)) +
                                    plan(-45, "halfway &middot; " + w(-45)) +
                                    plan(
                                        Math.round(peak * 10) / 10,
                                        "widest &middot; " + w(peak),
                                    ) +
                                    plan(0, "cover on &middot; " + w(0)) +
                                    plan(HOLD, "held &middot; " + w(HOLD)) +
                                    "</div>" +
                                    '<div class="cap">Beloved on base 117: a ' +
                                    g.h.toFixed(1) +
                                    "pt book, " +
                                    g.cw.toFixed(1) +
                                    "pt of cover, " +
                                    g.tk.toFixed(1) +
                                    "pt of spine.</div>"
                                );
                            })(),
                        ],
                        [
                            "el-faces",
                            "Four faces, not three",
                            "<code>BookChassis</code> composes a back board, a fore-edge page block and a front cover. <b>There is no spine face</b>, which is why a spine cannot simply rotate into today's mock book &mdash; there is nothing on that side to rotate from. The addition is small: <code>bookPageLocalMatrix</code> already places a perpendicular strip at the fore-edge, and a spine is its mirror at the left edge. Note the sign: positive turn exposes the fore-edge, so the spine is revealed at <i>negative</i> turn, and the range simply extends from [0, +16&deg;] to [-90&deg;, +16&deg;].<br /><br /><b>The pivot has to move, and that is the second thing the chassis does not do today.</b> <code>_face</code> passes <code>alignment: Alignment.center</code>, so a book turns about its own middle &mdash; invisible at 16&deg;, and at 90&deg; it would slide the book about half a cover width sideways, straight through its neighbour. Drawn here about the spine's left edge instead, so the hinge stays put and the book opens toward the reader: the motion of pulling one off a shelf. That means <code>BookChassis</code> needs the pivot as a parameter, and that the pile's books turn about a different point from the shelves' &mdash; defensibly, since a book on a shelf is being looked at and a book in the pile is being pulled out.",
                            (function () {
                                const bk = CORPUS[1];
                                const g = geom(bk, { base: 117 }, 1);
                                return (
                                    '<div class="onwhite" style="gap:28px">' +
                                    turned(bk, g, -90) +
                                    turned(bk, g, -55) +
                                    turned(bk, g, -20) +
                                    turned(bk, g, HOLD) +
                                    "</div>" +
                                    '<div class="cap">The page block appears only at the last of these, once the turn goes positive; at every negative angle the boards hide it, which is correct and is why the fore-edge is not visible while a book is turning out.</div>'
                                );
                            })(),
                        ],
                    ],
                ],
            ];

            /* Mark an id as an unresolved decision; renders inline as a red callout. */
            const OPEN = {
                "turn-out":
                    "<b>Decided, and it reverses a written decision.</b> <code>book_details_tab_view.dart:151</code> says the opposite in as many words: &ldquo;The pile and the month grid fly no book either, for the same reason.&rdquo; That comment changes with this. Two things make it safe now: a finished book is kept off the shelves by <code>withoutFinishedBooks</code>, so there is no second <code>book_&lt;isbn&gt;</code> hero on the library route to collide with; and only the open book carries the tag, which matters because <code>book_&lt;isbn&gt;</code> collides across the fifteen migrated books with no ISBN. One-at-a-time is a correctness argument, not only a tidiness one. The month grid still flies nothing, and the pile's plank still flies nothing — it is shared by every book standing on it.",
                "el-spine-jitter":
                    "<b>Resolved &mdash; the tint has a floor, and a stored source.</b> Two things the drawing settled that the numbers alone did not. <i>Where it comes from:</i> a stored nullable <code>books.cover_color</code>, written at insert and filled in for existing rows the first time <code>BookWidget</code> decodes that book anywhere &mdash; the app's own sampler, so a stored colour and a live one cannot disagree. NULL falls back to <code>generatedCoverColor(isbn)</code>, so every spine has a colour on the first frame whatever state the backfill is in, and the pile never reads a live decode. Same argument as <code>books.page_count</code>. <i>What it is:</i> <code>spineTintFor</code> rather than <code>bookBoardColorFor</code> — chroma lifted toward <code>brand</code> below 0.18 saturation, then darkened until white clears 4.6:1. Both steps are no-ops for most covers. Two things this buys beyond the pile: the back board stops popping in after load on every shelf in the app, and a friend's books get a tone without your client decoding their library.",
                "pile-jitter":
                    "<b>Decided &mdash; base 117.</b> The tallest jittered book is then exactly today's 124, so <code>ReadPile.extent</code> stays 169, the collapsed sheet does not move, and no test or design-record number changes. Base 124 was the alternative &mdash; it centres the spread on today's height, which is arguably the truer reading of &ldquo;vary the heights&rdquo; &mdash; and it costs 7.4pt of shelf plus four test expectations. Kept browsable as <code>taller-pile</code> rather than deleted, because the 7pt is the only thing the two differ by and it is worth being able to see it.",
            };

            /* ==================================================================
   SECTION 4: VERSIONS.

   The root is the **decided design**, so the page's plain data is what
   was chosen rather than a starting point that has to be patched into
   the answer. The two width alternatives are kept as rejected branches
   because each one turned something up that the decision rests on, and
   a discarded option that is no longer browsable stops being evidence.
   ================================================================== */
            const VERSIONS = [
                [
                    "decided",
                    "decided",
                    "Heights on base 117, widths from BookMetrics.thickness, each spine toned from its own cover through spineTintFor, a 1pt line between them, and 8pt of air either side of a book turned out. Specced at docs/superpowers/specs/2026-08-22-read-pile-spines-design.md.",
                    null,
                    {},
                ],

                [
                    "green-true",
                    "green-true",
                    "Rejected: the same true widths with the pile left brand green. Kept because splitting the width from the tone is what made the decision legible \u2014 the width costs three books of density and nothing else, the tone costs a column and a colour function.",
                    "decided",
                    {
                        screens: {
                            "pile-jitter": {
                                name: "Read pile &middot; true widths, brand green",
                                note: "<b>Rejected.</b> Real chassis thickness, 28 to 39pt, with the spines still <code>brand</code> at 0.4&thinsp;/&thinsp;0.7&thinsp;/&thinsp;1.0. What this version is for: it is the cheapest thing on the page that answers &ldquo;should thick and thin books be distinguishable&rdquo; \u2014 no schema change, no sampled colour, no contrast floor, and the opacity cycle already separates neighbouring spines so it needs no hairline either. Set against the decided design it is also the control that shows how much of that design's character comes from the tone rather than from the size.",
                                spec: restyle(PILE, "green"),
                            },
                            "pile-stretch": { spec: restyle(PILE_STRETCH, "green") },
                            "pile-mid": { spec: restyle(TURN_MID, "green") },
                            "pile-open": {
                                note: "The turn is unaffected by the tone: the spine face takes the brand fill, the cover is the book's own either way. Which is the argument for treating them as two decisions.",
                                spec: restyle(TURN_REST, "green"),
                            },
                            "pile-hold": { spec: restyle(TURN_HELD, "green") },
                        },
                        flows: {
                            "turn-out": {
                                note: "Identical to the decided flow except for the resting colour, which is the point: none of the interaction depends on the tone.",
                                steps: [
                                    [
                                        "At rest",
                                        "Thirteen brand-green spines at true thickness. The tap target is the full 137pt column.",
                                        restyle(PILE, "green"),
                                    ],
                                    [
                                        "Turning",
                                        "-45&deg;, over <code>kBookTurnDuration</code> 260ms.",
                                        restyle(TURN_MID, "green"),
                                    ],
                                    [
                                        "Turned out",
                                        "The cover is the book's own, so this frame is the same in both versions.",
                                        restyle(TURN_REST, "green"),
                                    ],
                                    [
                                        "Held",
                                        "+16&deg;, fore-edge showing.",
                                        restyle(TURN_HELD, "green"),
                                    ],
                                    [
                                        "Details",
                                        "Same Hero, same tag, same shuttle.",
                                        { kind: "dtl", book: OPEN_AT },
                                    ],
                                ],
                            },
                        },
                        elements: {
                            "el-spine-jitter": {
                                name: "Spine &middot; true widths, brand green",
                                note: "<b>Rejected.</b> The six pinned books at real chassis thickness, still brand green. Same hash, same order as the decided strip \u2014 only the fill differs, so this is the pair to look at if the question is how much the tone is doing.",
                                demo:
                                    spineStrip({ base: 117, wmode: "true" }) +
                                    '<div class="cap">Widths 28&ndash;39. No hairline needed: the opacity cycle separates neighbours by itself, which is exactly why the shipped pile never needed one.</div>' +
                                    mtable({ base: 117, wmode: "true" }),
                            },
                        },
                        /* No tint, so the tint's unresolved piece does not exist
                           here. Leaving it would attach a red callout to a
                           version it cannot apply to. */
                        open: { "el-spine-jitter": null },
                    },
                ],

                [
                    "green-remap",
                    "green-remap",
                    "Rejected: brand green, and widths remapped to 21-31 instead of the real thickness. The most conservative option on the page \u2014 it changes neither the sheet's height nor the pile's density \u2014 and the one that showed the variation was too subtle to be worth the work.",
                    "green-true",
                    {
                        screens: {
                            "pile-jitter": {
                                name: "Read pile &middot; remapped widths",
                                note: "<b>Rejected.</b> Width is the book's <i>position</i> in the thickness range mapped onto 21&ndash;31 rather than the range itself, centred on today's 26 so the row holds the same twelve and a half books. It was the original recommendation, on the grounds that it moved nothing: same sheet height, same density, no new API. What killed it is visible here \u2014 a &plusmn;5pt spread on a 26pt spine barely reads as variation at all, so it paid the whole cost of hashing per-book sizes and collected almost none of the benefit. It also has to make the spine's width and the turned book's thickness agree by fiat, where the real thickness agrees by construction.",
                                spec: restyle(PILE, "remap"),
                            },
                            "pile-stretch": { spec: restyle(PILE_STRETCH, "remap") },
                            "pile-mid": { spec: restyle(TURN_MID, "remap") },
                            "pile-open": { spec: restyle(TURN_REST, "remap") },
                            "pile-hold": { spec: restyle(TURN_HELD, "remap") },
                        },
                        elements: {
                            "el-spine-jitter": {
                                name: "Spine &middot; remapped widths",
                                note: "<b>Rejected.</b> The same six books at 21&ndash;31. Compare with <code>green-true</code>: same hash, same order, a third of the spread. This is the strip that settled the width question.",
                                demo:
                                    spineStrip({ base: 117, wmode: "narrow" }) +
                                    '<div class="cap">Widths 21&ndash;31, mean exactly the shipped 26, so the pile holds twelve and a half books as it does now.</div>' +
                                    mtable({ base: 117, wmode: "narrow" }),
                            },
                        },
                    },
                ],

                [
                    "taller-pile",
                    "taller-pile",
                    "Open: the decided design with heights on base 124 instead of 117, so today's height becomes the average rather than the ceiling. Costs 7.4pt of shelf and moves ReadPile.extent to 176.4.",
                    "decided",
                    {
                        screens: {
                            "pile-jitter": {
                                name: "Read pile &middot; base 124",
                                note: "Books span 116.6 to 131.4 instead of 110 to 124. The row must then reserve <code>131.4 + 13</code> = 144.4 and <code>ReadPile.extent</code> becomes 176.4, so the collapsed card grows 7.4pt and the library above loses the same &mdash; visible against the shelves at the top of the frame. Set against the decided version: identical distribution, shifted up 7pt. The question is whether the pile should be unchanged in aggregate or visibly a little taller than the one shipped.",
                                spec: rebase(PILE, 124, 176.4),
                            },
                            "pile-stretch": { spec: rebase(PILE_STRETCH, 124, 176.4) },
                            "pile-mid": { spec: rebase(TURN_MID, 124, 176.4) },
                            "pile-open": { spec: rebase(TURN_REST, 124, 176.4) },
                            "pile-hold": { spec: rebase(TURN_HELD, 124, 176.4) },
                        },
                        elements: {
                            "el-spine-jitter": {
                                note: "Base 124: the spread is centred on today's height, and four tests plus the design record's &ldquo;169pt ReadPile&rdquo; move with it.",
                                demo:
                                    spineStrip({ base: 124, wmode: "true" }, true) +
                                    '<div class="cap">Base 124, tallest book 131.4pt, so the row reserves 144.4 and the pile is 176.4.</div>' +
                                    tintContrastNote() +
                                    mtable({ base: 124, wmode: "true" }),
                            },
                        },
                    },
                ],
            ];
