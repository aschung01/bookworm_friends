import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_furniture.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_shelf_plan.dart';

/// The size the card is exported at, in logical pixels.
///
/// Fixed, and fixed in *both* dimensions. A width alone would be enough for layout,
/// but the capture needs a tight box, and pinning the height means every reader's
/// card is the same shape — which is the whole point of an artifact that leaves the
/// app and gets looked at beside other people's.
///
/// Portrait 4:5, which is what Instagram, KakaoTalk and iMessage all show without
/// cropping. At the 3x export in `captureWidgetToPng` this is 1080x1350.
const Size kShareableCardSize = Size(360, 450);

/// One drawing unit, in points.
///
/// `docs/mockups/library-card-share/index.html` lays the artifact out as `106 * --u`
/// and every measurement inside it is in the same units, so this is the one number
/// that converts the drawing into this file. Written out rather than derived from
/// [kShareableCardSize] because `Size.width` is not a constant expression.
const double _u = 360 / 106;

/// Fraction of the card's height the cover well takes.
///
/// 46%, against the drawings' 44% and Flighty's own roughly half. The record below it
/// is four rows now rather than five — the invented card number went, which Flighty
/// does not print either — and the strip is always two lines, so the space the body
/// gave back goes to the covers, which are the reason anyone looks at the card. Held
/// by the overflow test at the fullest card, which asserts the spring still has slack:
/// the metrics under the test font are not a device's, so zero slack would pass in CI
/// and clip on a phone.
const double _kWellFraction = 0.46;

/// The card stock, and it is **deliberately not a theme token**.
///
/// `app_theme.dart` has no cream, and it should not gain one: these values exist so
/// the artifact looks the same whoever exports it, which is the opposite of what a
/// theme colour is for. Today's export takes `colors.pageBackground`, so a
/// dark-mode reader ships a dark card and the product has two looks in circulation —
/// Flighty's passport is always cream.
///
/// The one colour still read from the theme is `brandFill`, on the title. That is
/// not an inconsistency: `brandFill` is documented as the same value in light and
/// dark, so taking it from the theme cannot vary the artifact and duplicating it
/// here would invite exactly the drift these constants exist to prevent.
const Color kCardStock = Color(0xFFF2EDE0);
const Color kCardStockLine = Color(0xFFDDD3BD);
const Color kCardInk = Color(0xFF1F2D27);

/// The well grades from the lighter stop down to the stock's own tone, so the covers
/// stand on something rather than floating on a flat field.
const Color kCardWellTop = Color(0xFFFAF6EC);
const Color kCardWellBottom = Color(0xFFEFE7D6);

/// Ink for the card's labels: `Holder`, `Days reading`, the bilingual stamp line.
///
/// **70%, not the 55% the drawings imply, and the difference is a WCAG failure.**
/// Composited on the stock, 55% measures **3.3:1** and 62% little better — under AA
/// for text this size, and these are 10pt labels on an image people will read at
/// thumbnail scale in a chat list. 70% measures 5.0:1. It is the same weight
/// `statTileMutedText` settled on for the same reason, which is reassuring rather
/// than coincidental: both are small print on a light ground.
///
/// A function rather than a `const`, because `withValues` is not a constant
/// expression — the same shape `stat_tile.dart` uses. Pinned by
/// `library_card_contrast_test.dart`.
Color cardLabelInk() => kCardInk.withValues(alpha: 0.7);

/// Ink for the machine-readable strip.
///
/// Darker than the labels, deliberately: the strip is the return path, and it is the
/// one element on the artifact that has to survive being read off a screenshot.
Color cardStripInk() => kCardInk.withValues(alpha: 0.78);

/// Width of the record's label column, in drawing units.
///
/// **26, and it was 21 until a device screenshot showed `Member sin…`.**
///
/// This constant is the one thing on the card that **no widget test can verify**, and it
/// is worth saying why rather than leaving the next person to rediscover it. The labels
/// are drawn with `TextOverflow.ellipsis`, so a column too narrow to hold one fails
/// *silently* — no `RenderFlex overflowed`, nothing for `takeException` to catch. And
/// `flutter test` renders in a fixed-width test font where every glyph is one em, so
/// measuring there measures the test font: under it `Member since` needs 126pt and no
/// column this card can afford would pass, while under a real proportional font it needs
/// about 75. The two fonts even disagree about which label is longest — `Date of issue` is
/// 13 characters and fitted at 21 units (thin `i`, `t`, `f`), `Member since` is 12 and did
/// not (wide `M`, `b`, `c`).
///
/// So it is measured on a device and given headroom: 26 rather than the 22 that would just
/// about clear it. Anything added to [_IssueBlock]'s label set has to be checked the same
/// way, on hardware, by looking at the exported file.
const double kCardMetaLabelUnits = 26;

/// Longest a stat-row label may be, in characters.
///
/// **A crude rule that is nonetheless the right one here, because the failure it prevents
/// is font-independent.** The stat row's cells are `Expanded`, so four cells make each one
/// about 72pt — the narrowest any label ever gets. `Days reading` (12) survived that on
/// device and `Pace, per book` (14) ellipsised to `Pace, per bo…`. Character count is a
/// poor proxy for width in general (see [kCardMetaLabelUnits], where it is actively
/// misleading), but every label in this row is short plain English at one size, so within
/// that set it holds — and unlike a width measurement it means the same thing under the
/// test font as on a phone, which is what makes it assertable at all.
const int kCardStatLabelMaxChars = 12;

/// Distinct authors before the stat row will name a count.
///
/// Three, in the same spirit as [kTopAuthorFloor]: "2 authors" over two books is a
/// restatement of the hero figure, not a fact about a library.
const int kCardAuthorsFloor = 3;

/// Distinct shelves before the stat row will name a count. One shelf is where every
/// reader starts, so it says nothing.
const int kCardShelvesFloor = 2;

/// How many distinct authors [books] have between them.
///
/// Derived here rather than added to [LibraryCardStats], which this phase leaves
/// alone: these two figures exist only on the artifact, and the sheet has no tile for
/// either.
int cardDistinctAuthors(List<Book> books) =>
    books.expand((book) => book.authors).map((a) => a.trim()).toSet().length;

/// How many distinct shelves [books] were finished from.
int cardDistinctShelves(List<Book> books) =>
    books.map((book) => book.shelfId).toSet().length;

/// The machine-readable strip, as two lines of fixed-width text.
///
/// A pure function because this is the part of the artifact whose correctness is
/// about strings rather than pixels, and the strings have three rules:
///
///  * **44 columns, both lines**, padded with `<` — which is what a real TD3 passport
///    uses, and what Flighty's own strip does.
///  * **Latin only, and the handle is what makes that possible.** 142 of the 153
///    migrated display names are non-ASCII, and a Korean name cannot go in a
///    fixed-width Latin grid at all — which is the whole reason `profiles.handle`
///    exists. [cardStripToken] therefore *rejects* rather than converts: anything that
///    is not already a handle is omitted, because a mangled remnant of someone's name
///    (`독서하는 08269f2d` → `08269F2D`) is worse than no identity at all.
///  * **One return path, right-aligned.** [kCardBrandHandle] hangs off the end of the
///    second line, exactly where Flighty puts `FLIGHTY.COM`. It is 13 columns and the
///    issued field is padded to fill the rest, so it always fits — there is no
///    per-reader path to make it variable.
List<String> cardStripLines({
  required String? handle,
  required int year,
  required DateTime issued,
  DateTime? memberSince,
}) {
  final token = cardStripToken(handle);
  final scope = year == 0 ? 'ALLTIME' : 'Y$year';

  String pad(String value, int columns) =>
      (value + '<' * columns).substring(0, columns);

  final identity = [
    scope,
    if (token.isNotEmpty) token,
    if (memberSince != null) 'MEMBER${_stripDate(memberSince)}',
  ].join('<<');

  return [
    pad(identity, 44),
    pad('ISSUED${_stripDate(issued)}', 44 - kCardBrandHandle.length) +
        kCardBrandHandle,
  ];
}

/// [handle] as the strip can print it, or empty when it cannot be printed at all.
///
/// **A guard, not a converter.** A handle is strip-safe by construction — Task 7's
/// format check is `^[a-z0-9_]{3,20}$` — so anything failing that is a display name
/// that wandered in, and the answer is to print nothing rather than a transliteration
/// this code is not qualified to make.
///
/// Public so the rejection is tested directly: it is what stands between a Korean
/// display name and a strip that cannot be read.
String cardStripToken(String? handle) {
  final value = (handle ?? '').trim();
  if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(value)) return '';
  return value.toUpperCase();
}

String _stripDate(DateTime date) => _issueDate(date).replaceAll(' ', '');

/// `19 AUG 26`, and always in English.
///
/// Forced locale, not the reader's: this is furniture on an object that travels, and
/// a Korean-locale export would print `8월` where every other card prints `AUG`.
String _issueDate(DateTime date) =>
    DateFormat('dd MMM yy', 'en').format(date).toUpperCase();

/// The Library Card as a shareable image: a library checkout card, not a chart.
///
/// **Its own widget tree, and that is a requirement rather than a convenience.**
/// `RepaintBoundary.toImage` cannot capture platform views, and the sheet's year
/// capsules are a real `UIView` on iOS 26 — capturing the live sheet would produce a
/// card with a hole in it.
///
/// Structurally Flighty's passport, with the parts this app can actually answer: a
/// cover well where the passport has its map, a perforation, a titled issue block,
/// a stat row, and a machine-readable strip along the bottom. What it does *not*
/// have is a place of issue — Flighty has a home airport and this app has no home
/// library — and no avatar, because a face on an image that leaves the app is a
/// different consent question from a figure.
///
/// Every label on it is fixed English furniture rather than an l10n string; see
/// `card_furniture.dart` for the argument, which applies to all of them.
class ShareableLibraryCard extends StatelessWidget {
  final LibraryCardStats stats;

  /// Every finished book, unfiltered. Filtered by [year] here through
  /// `booksInCardYear`, the same rule [libraryCardStats] counts by.
  final List<Book> books;

  /// Selected year, `0` for all time. Passed through so the exported card agrees
  /// with the one on screen.
  final int year;

  /// The reader's display name, printed as `Holder`. Korean is fine here — the record
  /// is set in the app's own type, unlike the strip. Null omits the row rather than
  /// substituting anything.
  final String? displayName;

  /// The reader's `profiles.handle`: the Latin identity the strip prints.
  ///
  /// Null until Task 7 adds the column, and null is a working state — the strip omits
  /// the identity segment rather than printing a mangled display name. This is the
  /// only reason the handle exists: a machine-readable zone is Latin-only and 142 of
  /// the 153 display names are not.
  final String? handle;

  /// `profiles.created_at`, already selected by every profile read. Null omits its
  /// row.
  final DateTime? memberSince;

  /// Injectable so the card is deterministic under test. Defaults to now, which is
  /// what a date of issue means.
  final DateTime? issuedOn;

  /// The books the reader has open right now.
  ///
  /// Drawn at the front of the shelf, and
  /// **not counted by [stats]** — the hero figure counts books *read* and has to keep
  /// meaning that. What stops the two from reading as a mistake is that an open book
  /// wears a bookmark and carries no month stamp. See [CardCoverRow.reading].
  final List<Book> reading;

  /// How the card is lit.
  ///
  /// Daylight by default, so every existing caller is unchanged. `ShareCardPage` passes
  /// the reader's choice and **the export carries it** — a delight toggle that changed
  /// only the screen would be a toy, and the reader who pressed it is precisely the one
  /// about to share.
  final CardLighting lighting;

  const ShareableLibraryCard({
    super.key,
    required this.stats,
    this.books = const [],
    this.reading = const [],
    this.year = 0,
    this.displayName,
    this.handle,
    this.memberSince,
    this.issuedOn,
    this.lighting = CardLighting.daylight,
  });

  @override
  Widget build(BuildContext context) {
    final selected = booksInCardYear(books, year);
    final issued = issuedOn ?? DateTime.now();
    final palette = cardPalette(lighting);
    // Null under `en`, where the title below already names the card. The same call
    // `LibraryCardBody`'s hero makes, so the preview and this cannot disagree.
    final stamp = cardStampLine(AppLocalizations.of(context));

    return SizedBox.fromSize(
      size: kShareableCardSize,
      // `Material`, and it is load-bearing rather than idiomatic.
      //
      // The capture hosts this subtree in the app's `Overlay`, which has no ancestor
      // `Material` — and `MaterialApp` deliberately installs a fallback
      // `DefaultTextStyle` for exactly that case, whose `debugLabel` reads "fallback
      // style; consider putting your text in a Material". It carries
      // `decoration: underline` with a yellow double line. Every `Text` here sets its
      // own size, weight and colour, so those were overridden and the *decoration*
      // was not: the first exported card came out with a yellow underline beneath
      // every glyph, app name and figures included.
      //
      // Invisible on screen, because the sheet is inside a `Scaffold`. Invisible to a
      // widget test that asserts strings and geometry. Only visible by opening the
      // exported PNG, which is why the plan made that the bar for this task.
      child: Material(
        type: MaterialType.canvas,
        // The darker stop, so the card is opaque even before the gradient paints.
        color: palette.stock.last,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3 * _u),
          side: BorderSide(color: palette.stockLine, width: 0.6 * _u),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Flat in daylight — both stops are the same cream — and graded under a
            // candle. **This gradient is the flame's falloff**, and it lives here rather
            // than in the overlay above the type for the reason `kCandleStockTop`
            // gives: the card's darkest region is its bottom edge, and the strip is
            // printed there.
            gradient: LinearGradient(
              // The drawings' 165°: nearly vertical with a lean to the right.
              begin: const Alignment(-0.26, -1),
              end: const Alignment(0.26, 1),
              colors: palette.stock,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Well(books: selected, reading: reading, palette: palette),
                  _Perforation(color: palette.perforationInk),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        6 * _u,
                        3.5 * _u,
                        6 * _u,
                        4 * _u,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            cardStampTitle(year),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 5 * _u,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: palette.titleInk(context.colors.brandFill),
                              shadows: palette.bloom,
                            ),
                          ),
                          // The gap belongs to the line, so an `en` card closes the
                          // title straight onto the 2.5 below rather than leaving a
                          // 0.8 shim where the sub-line used to be.
                          if (stamp != null) ...[
                            const SizedBox(height: 0.8 * _u),
                            Text(
                              stamp,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 2.9 * _u,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                letterSpacing: 0.1 * _u,
                                color: palette.labelInk,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2.5 * _u),
                          _IssueBlock(
                            books: stats.booksRead,
                            holder: displayName,
                            issued: issued,
                            memberSince: memberSince,
                            palette: palette,
                          ),
                          // A spring rather than `margin-top: auto` on the stat row:
                          // the stat row is not always there — the median reader has
                          // no figure that clears its floor — and the strip has to sit
                          // on the bottom edge either way.
                          const Spacer(),
                          _StatRow(
                            stats: stats,
                            books: selected,
                            palette: palette,
                          ),
                          _Strip(
                            lines: cardStripLines(
                              handle: handle,
                              year: year,
                              issued: issued,
                              memberSince: memberSince,
                            ),
                            palette: palette,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // The light itself, painted over the card because that is what light
              // does. **Highlight only, no dark stop** — see `kCandleBloomColors`. It
              // is therefore safe over the strip, which is the one thing the drawings
              // had to use a `z-index` to protect.
              if (palette.isLit)
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: kCandleBloomCenter,
                        radius: kCandleBloomRadius,
                        colors: kCandleBloomColors,
                        stops: kCandleBloomStops,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cover well: this card's equivalent of the passport's map page.
class _Well extends StatelessWidget {
  final List<Book> books;
  final List<Book> reading;
  final CardPalette palette;

  const _Well({
    required this.books,
    required this.reading,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kShareableCardSize.height * _kWellFraction,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: palette.well,
          ),
        ),
        // Clipped because the gilt hatching runs off the edges by construction — it is
        // drawn as two infinite rulings and cropped to the well, which is how ruled
        // stock actually works.
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GiltPainter(
                    strong: palette.giltStrong,
                    faint: palette.giltFaint,
                  ),
                ),
              ),
              Positioned(
                right: 4 * _u,
                top: 4 * _u,
                child: _Seal(palette: palette),
              ),
              Padding(
                // The bottom inset is [kCardShelfFloorUnits] and not zero, so the bottom
                // board's shadow has somewhere to fall. It is taken out of the well's
                // slack, not out of the covers: see that constant for why nothing about
                // the shelf's size or capacity moved.
                padding: const EdgeInsets.fromLTRB(
                  4 * _u,
                  4 * _u,
                  4 * _u,
                  kCardShelfFloorUnits * _u,
                ),
                child: Column(
                  // The shelf stands just clear of the bottom of the well, so the
                  // well's remaining slack goes above it.
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // No unit passed: the row measures the well's inner box and
                    // divides by `kCardShelfUnits`, which *is* that box in units
                    // by construction. The row used to divide by 106 instead,
                    // making its unit 7.5% smaller than the card's and every
                    // cover 7.5% smaller than the drawing said. It also draws its
                    // own boards now, because with two of them the boards have to
                    // interleave with the rows.
                    CardCoverRow(
                      books: books,
                      reading: reading,
                      lighting: palette.lighting,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gilt: fine ruled foil on the stock, at two weights crossing each other.
///
/// **Task 2 deliberately did not draw this, and it lands here for a reason rather than
/// as a leftover.** Gilt is foil, not ink: at 7% on cream it is very nearly invisible
/// with the lights on, which is exactly what it should look like, and being picked out by
/// a raking flame is its entire purpose. Drawing it in Task 2 would have added a pattern
/// nobody could see; drawing it only under the flame would make Candlelight a *filter*
/// that invents detail rather than a light that finds it.
class _GiltPainter extends CustomPainter {
  final Color strong;
  final Color faint;

  const _GiltPainter({required this.strong, required this.faint});

  /// The drawings' ±62°, at two spacings so the crossing is a moiré rather than a grid.
  static const double _angle = 62;
  static const double _strongSpacing = 2.4 * _u;
  static const double _faintSpacing = 3 * _u;

  @override
  void paint(Canvas canvas, Size size) {
    _hatch(canvas, size, _angle, strong, _strongSpacing);
    _hatch(canvas, size, -_angle, faint, _faintSpacing);
  }

  void _hatch(
    Canvas canvas,
    Size size,
    double degrees,
    Color color,
    double spacing,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.4 * _u;
    // Far enough that a rotated ruling still covers the corners.
    final reach = size.width + size.height;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(degrees * math.pi / 180);
    for (var x = -reach; x < reach; x += spacing) {
      canvas.drawLine(Offset(x, -reach), Offset(x, reach), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GiltPainter oldDelegate) =>
      oldDelegate.strong != strong || oldDelegate.faint != faint;
}

/// The blind-embossed stamp: pressed into the stock rather than printed on it.
///
/// **Barely visible in daylight and fully revealed under the flame**, which is what an
/// emboss does. Task 2 drew it at 10% opacity precisely so that this task had something
/// real to reveal rather than something new to add.
class _Seal extends StatelessWidget {
  final CardPalette palette;

  const _Seal({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -9 * math.pi / 180,
      child: Opacity(
        opacity: palette.sealOpacity,
        child: Container(
          // [kCardSealUnits], because `card_shelf_plan.dart` reserves the top board's
          // right-hand end for exactly this disc. A seal that grew here without that
          // constant moving would be covered again by the books the reserve was sized to
          // hold back.
          width: kCardSealUnits * _u,
          height: kCardSealUnits * _u,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.sealRing, width: 0.8 * _u),
            boxShadow: palette.isLit
                ? [
                    BoxShadow(
                      color: kCandleFlame.withValues(alpha: 0.6),
                      blurRadius: 3 * _u,
                    ),
                  ]
                : null,
          ),
          // Two rings rather than one, which is what CSS's `double` border draws and
          // what an embossing die actually leaves.
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.sealRing, width: 0.4 * _u),
            ),
            alignment: Alignment.center,
            // The brand mark rather than the `LS` monogram it replaced — see
            // [kCardSealMarkAsset]. Tinted from pure alpha with `sealInk`, so the emboss
            // trick is unchanged: 10% opacity in daylight, revealed under the flame.
            //
            // 10.5u against the ring's ~12.6u inner diameter: the artwork keeps its own
            // margins (the drawing's furthest opaque pixel sits at ~76% of the canvas),
            // so the visible book lands around 8u — the presence the two 4.4u letters
            // had — and cannot touch the ring.
            //
            // The chalk edge loses `palette.bloom`, which only `Shadow`s on text can
            // carry; under a candle the disc's own `BoxShadow` glow does that work.
            child: SizedBox(
              width: 10.5 * _u,
              height: 10.5 * _u,
              child: Image.asset(
                kCardSealMarkAsset,
                color: palette.sealInk,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tear line between the well and the record, as a library card has.
class _Perforation extends StatelessWidget {
  final Color color;

  const _Perforation({required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 0.6 * _u,
    child: CustomPaint(painter: _DashPainter(color)),
  );
}

class _DashPainter extends CustomPainter {
  final Color color;

  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    const dash = 2.5 * _u;
    const gap = 2 * _u;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}

/// The figure, and the record beside it.
///
/// Flighty prints Authority / Place of issue / Date of issue / Member since; this
/// prints what it can answer, and omits a row rather than inventing its value.
class _IssueBlock extends StatelessWidget {
  final int books;
  final String? holder;
  final DateTime issued;
  final DateTime? memberSince;
  final CardPalette palette;

  const _IssueBlock({
    required this.books,
    required this.holder,
    required this.issued,
    required this.memberSince,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    // Four rows, the same count Flighty prints, and every one of them answerable.
    // **No card number**, which the first version invented: Flighty has none either,
    // and a derived number is the same class of fiction as the place of issue this
    // deliberately leaves out.
    final rows = <(String, String)>[
      if (holder != null && holder!.isNotEmpty) ('Holder', holder!),
      // The one value in this block that is translated. Its *label* is not, and the
      // split is not an oversight: the labels are a fixed-width Latin column
      // ([kCardMetaLabelUnits] is sized for them), while the authority is the app's
      // own name and was the second of the two strings printing Hangul on an English
      // reader's card. See `card_furniture.dart`.
      ('Authority', AppLocalizations.of(context).libraryCardAuthority),
      ('Date of issue', _issueDate(issued)),
      if (memberSince != null) ('Member since', _issueDate(memberSince!)),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$books',
              maxLines: 1,
              style: TextStyle(
                fontSize: 15 * _u,
                fontWeight: FontWeight.w800,
                height: 0.95,
                letterSpacing: -0.45 * _u,
                color: palette.ink,
                shadows: palette.bloom,
              ),
            ),
            Text(
              books == 1 ? 'book' : 'books',
              maxLines: 1,
              style: TextStyle(
                fontSize: 5.5 * _u,
                fontWeight: FontWeight.w300,
                height: 1.1,
                color: palette.accentInk(context.colors.brandFill),
              ),
            ),
          ],
        ),
        const SizedBox(width: 5 * _u),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 0.7 * _u),
                _MetaRow(
                  label: rows[i].$1,
                  value: rows[i].$2,
                  palette: palette,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final CardPalette palette;

  const _MetaRow({
    required this.label,
    required this.value,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: kCardMetaLabelUnits * _u,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 3.1 * _u,
              height: 1.25,
              color: palette.labelInk,
            ),
          ),
        ),
        const SizedBox(width: 2 * _u),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 3.1 * _u,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// The stat row: variable length, every cell with a floor, absent when nothing
/// clears one.
///
/// That absence is the median reader's card — two books, both logged same-day, two
/// authors, one shelf — and it is the state the design has to survive. Nothing is
/// zero-filled, which is the rule [LibraryCardStats] already enforces for the
/// sheet's tiles, applied to the artifact.
class _StatRow extends StatelessWidget {
  final LibraryCardStats stats;
  final List<Book> books;
  final CardPalette palette;

  const _StatRow({
    required this.stats,
    required this.books,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final authors = cardDistinctAuthors(books);
    final shelves = cardDistinctShelves(books);

    final cells = <(String, String)>[
      if (stats.daysReading > 0) ('Days reading', '${stats.daysReading}'),
      // `Pace`, not `Pace, per book`: the stat row's cells are `Expanded`, so at four
      // cells each one is about 72pt and the longer label ellipsised on device to
      // `Pace, per bo…`. The unit is already in the value and the sheet's own tile
      // carries the sample size, so the qualifier was the least load-bearing thing on
      // the card. Same silent-ellipsis failure as the record's labels above.
      if (stats.hasPace) ('Pace', '${stats.pace!.round()}d'),
      if (authors >= kCardAuthorsFloor) ('Authors', '$authors'),
      if (shelves >= kCardShelvesFloor) ('Shelves', '$shelves'),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 3 * _u),
      padding: const EdgeInsets.only(top: 3 * _u),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.statRule, width: 0.5 * _u),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 3 * _u),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cells[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 3 * _u,
                      height: 1.2,
                      color: palette.labelInk,
                    ),
                  ),
                  Text(
                    cells[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 5 * _u,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The printed return path.
///
/// Printed rather than attached, because a shared image outlives its caption: it gets
/// screenshotted, re-saved, forwarded and cropped, and the only carrier that survives
/// all of that is the pixels.
class _Strip extends StatelessWidget {
  final List<String> lines;
  final CardPalette palette;

  const _Strip({required this.lines, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2 * _u),
      padding: const EdgeInsets.only(top: 1.6 * _u),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.stripRule, width: 0.5 * _u),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Text(
              line,
              maxLines: 1,
              // Clipped rather than ellipsised: an ellipsis in a machine-readable
              // zone reads as a rendering fault, and the line is composed to fit.
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                // The one place a monospace family is wanted rather than a
                // fallback. `shareable_library_card_test.dart` asserts that no
                // *other* text on the card is monospace, because that is what
                // falling back to the error style looks like.
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Courier'],
                fontSize: 2.7 * _u,
                height: 1.4,
                color: palette.stripInk,
              ),
            ),
        ],
      ),
    );
  }
}
