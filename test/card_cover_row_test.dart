// Tests for the shelf: the Library Card's signature visual, and the one part of the
// artifact whose failure mode is invisible.
//
// **This file is about the drawing; `card_shelf_plan_test.dart` is about the geometry.**
// The plan is a pure function and its numbers are pinned there — capacities, floors, the
// refusal to squeeze. What is asserted here is that the widget draws that plan
// faithfully: the same count, at the same aspect, inside the same 98 units, with the
// count of what it left out printed on it.
//
// Three of those are about the export rather than the screen, and none of them can be
// eyeballed:
//
//  - **The crop.** The shipped row handed out 0.36-aspect boxes for 0.67-aspect covers
//    and `BoxFit.cover` threw 20.7pt of jacket off each one. No test caught it, because
//    the widget was doing exactly what it meant to do. So the aspect of every drawn box
//    is asserted directly, at every count and in every setting.
//  - **The precache.** `RepaintBoundary.toImage` paints only what is already decoded, so
//    a provider missing from `cardCoverProviders` is a hole in a PNG that has already
//    left the phone.
//  - **The overflow.** A shelf wider than the well is a cover clipped in half by the
//    well's own `ClipRect`, with nothing on screen to explain it.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/services/cover_image.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_shelf_plan.dart';

/// The width the row is given, matching the exported card's own 360pt.
const double _rowWidth = 360;

/// Points per drawing unit **on the exported card**.
///
/// The card is [kCardUnits] wide and 360pt across, so this is the artifact's own scale
/// and every absolute figure below is the size a reader would actually get. Passed
/// explicitly rather than left to the row's `LayoutBuilder`, which would take the 360pt
/// box for a board and draw everything 8% large — the shelf is [kCardShelfUnits] wide,
/// not [kCardUnits], because the well insets it.
const double _u = _rowWidth / kCardUnits;

/// The board's width in points: what nothing may exceed.
const double _shelfWidth = kCardShelfUnits * _u;

/// Resolves on the first frame, so no test depends on decode timing. The same shape
/// `avatar_circle_test.dart` uses, and for the same reason: `MemoryImage` keys on its
/// bytes, so a second test would get a synchronous cache hit and stop exercising
/// anything.
class _LoadedImage extends ImageProvider<_LoadedImage> {
  _LoadedImage(this.image);

  final ui.Image image;

  @override
  Future<_LoadedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_LoadedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _LoadedImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
  );
}

Book _book(String isbn, {String thumbnail = '', DateTime? finish}) => Book(
  id: isbn,
  userId: 'u',
  shelfId: 's',
  isbn: isbn,
  title: 'Title $isbn',
  thumbnail: thumbnail,
  status: 2,
  position: 0,
  finishDate: finish ?? DateTime(2024, 3, 1),
  createdAt: DateTime(2024),
);

/// A book the reader still has open: **no finish date**, which is what makes
/// `cardStampMonth` return null for it. That is one of the two things marking a cover the
/// hero has not counted, so it has to be modelled rather than faked with a flag.
Book _open(String isbn, {String thumbnail = ''}) => Book(
  id: isbn,
  userId: 'u',
  shelfId: 's',
  isbn: isbn,
  title: 'Open $isbn',
  thumbnail: thumbnail,
  status: 1,
  position: 0,
  createdAt: DateTime(2024),
);

/// [count] books, each finished a day apart so their order is unambiguous.
List<Book> _books(int count, {String thumbnail = ''}) => [
  for (var i = 0; i < count; i++)
    _book('b$i', thumbnail: thumbnail, finish: DateTime(2024, 3, 1 + i)),
];

Future<void> _pump(
  WidgetTester tester,
  List<Book> books, {
  List<Book> reading = const [],
  CardLighting lighting = CardLighting.daylight,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // The delegates are not decoration. `cardStampMonth` uses `DateFormat` with a
      // forced `en`, and `intl` throws `LocaleDataException` until a localisation
      // delegate has initialised its date symbols — which the app's own `MaterialApp`
      // always has and a bare test one does not.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _rowWidth,
            child: CardCoverRow(
              books: books,
              reading: reading,
              lighting: lighting,
              unit: _u,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The furniture a cover carries, keyed under the same prefix as the cover itself.
///
/// A bare `startsWith('cover-')` counts a stamped row twice and a shelf of open books
/// three times, which would make every count below quietly wrong in the direction of
/// passing.
const List<String> _furniture = [
  'cover-stamp-',
  'cover-mark-',
  'cover-bookmark-',
];

/// The books the shelf actually drew, in paint order.
List<String> _drawn(WidgetTester tester) => [
  for (final element
      in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate())
    if (_isCover((element.widget.key as ValueKey<String>).value))
      (element.widget.key as ValueKey<String>).value.substring('cover-'.length),
];

bool _isCover(String key) =>
    key.startsWith('cover-') && !_furniture.any((f) => key.startsWith(f));

Rect _boxOf(WidgetTester tester, String isbn) =>
    tester.getRect(find.byKey(ValueKey('cover-$isbn')));

/// How far the shelf reaches, measured from the leftmost book: the number that must stay
/// inside [_shelfWidth]. Measured off the rendered boxes rather than off the plan,
/// because the plan already claims to fit and the question here is whether the widget
/// honoured it.
double _extent(WidgetTester tester) {
  final rects = [for (final isbn in _drawn(tester)) _boxOf(tester, isbn)];
  final plate = find.textContaining('+');
  final left = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
  var right = rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
  if (plate.evaluate().isNotEmpty) {
    right = [
      right,
      tester.getRect(plate.first).right,
    ].reduce((a, b) => a > b ? a : b);
  }
  return right - left;
}

void main() {
  late ui.Image testImage;

  setUp(() async {
    testImage = await createTestImage(width: 2, height: 3);
    coverImageProvider = (_) => _LoadedImage(testImage);
  });

  tearDown(() {
    // Otherwise a later test in the same process quietly keeps the fake.
    coverImageProvider = networkCoverImage;
    imageCache.clear();
  });

  group('CardCoverRow geometry', () {
    testWidgets('Given any count in any setting, When the shelf renders, '
        'Then no cover box is a shape a jacket has to be cropped into', (
      tester,
    ) async {
      // **The regression test for the reported defect.** Every box a cover is drawn in
      // is exactly `kDefaultCoverAspect`, so `BoxFit.cover` has nothing to trim. It is
      // swept across the counts because the old fault was per-tier and per-book: three
      // tiers at three wrong aspects, and a jitter that moved each box's aspect
      // independently on top.
      for (final count in const [1, 2, 5, 6, 11, 22, 60]) {
        await _pump(tester, _books(count));

        for (final isbn in _drawn(tester)) {
          final box = _boxOf(tester, isbn);
          expect(
            box.width / box.height,
            closeTo(kDefaultCoverAspect, 1e-6),
            reason: '$isbn at $count books is $box',
          );
        }
      }
    });

    testWidgets('Given a small library, When the shelf renders, '
        'Then the covers are grown to fill it', (tester) async {
      // Refusing to squeeze is not refusing to fill. The median reader has two finished
      // books, and two covers at the fixed size would read as a gap where the shelf
      // should be rather than as an object.
      await _pump(tester, _books(2));
      final atTwo = _boxOf(tester, 'b0');

      expect(atTwo.width, greaterThan(kCardFaceUnits * _u));
      expect(
        atTwo.width,
        closeTo(
          kCardOneBoardCoverUnits *
              kDefaultCoverAspect *
              cardShelfScaleFor('b0') *
              _u,
          0.01,
        ),
        reason:
            'the widest a single board carries, less this book\'s own jitter: '
            'a grown cover has headroom to vary in and a fixed one does not, so '
            'the variation is only ever spent where it is free',
      );
    });

    testWidgets('Given the eleventh book, When the shelf renders, '
        'Then the first ten do not shrink to make room', (tester) async {
      // Where growing stops. Eleven covers cannot be drawn side by side on two boards
      // above `kCardMinFaceUnits`, so from here the *step* absorbs the count and the
      // covers hold their size for good — a reader does not watch their shelf shrink
      // every time they finish something.
      await _pump(tester, _books(10));
      final atTen = _boxOf(tester, 'b0').width;

      await _pump(tester, _books(11));
      final atEleven = _boxOf(tester, 'b0').width;

      await _pump(tester, _books(60));
      // The newest, because at sixty books the shelf is not showing b0 at all.
      final atSixty = _boxOf(tester, 'b59').width;

      expect(atTen, closeTo(kCardFaceUnits * _u, 0.01));
      expect(atEleven, closeTo(kCardFaceUnits * _u, 0.01));
      expect(atSixty, closeTo(kCardFaceUnits * _u, 0.01));
    });

    testWidgets('Given the fixed size, When a cover renders, '
        'Then it is still wide enough to carry its own title', (tester) async {
      // `kCardFaceUnits` is derived from this floor and clears it by 0.7pt, which is the
      // entire reason a third board is impossible. If this fails, the shelf is drawing
      // covers that cannot say what they are.
      await _pump(tester, _books(22));

      expect(
        _boxOf(tester, 'b0').width,
        greaterThanOrEqualTo(kGeneratedCoverMinWidth),
      );
      expect(find.byType(GeneratedCover), findsWidgets);
    });

    testWidgets('Given any count, When the shelf renders, '
        'Then it never reaches past the board it stands on', (tester) async {
      // An overflow here is not a debug banner; it is a cover sliced in half by the
      // well's `ClipRect` in a file that has already been shared. The plate is included
      // in the measurement because its width is reserved out of the same 98 units, and
      // it was overhanging until it was.
      for (final count in const [1, 5, 10, 11, 34, 60, 200]) {
        await _pump(tester, _books(count));

        expect(
          _extent(tester),
          lessThanOrEqualTo(_shelfWidth + 0.01),
          reason: '$count books',
        );
        expect(tester.takeException(), isNull, reason: '$count books');
      }
    });

    testWidgets('Given a single book, When the shelf renders, '
        'Then it fits the width it was given', (tester) async {
      await _pump(tester, _books(1));

      expect(_boxOf(tester, 'b0').width, lessThan(_rowWidth));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Given the shelf renders, When a board is drawn, '
        'Then it is a plank with a shadow, not a rounded underline', (
      tester,
    ) async {
      // Two defects in one guard, and both shipped. The board wore
      // `BorderRadius.circular(1 * unit)` on a bar 1.6 units tall — a pill, which is
      // precisely the underline `_Board`'s own comment says a board must not be — and it
      // cast no shadow at all, which is the thing that makes books read as standing *on*
      // a shelf rather than in front of a bar. `ShelfWidget` has neither problem, and the
      // card's board is meant to be recognised as the library's plank.
      await _pump(tester, _books(22));

      final boards = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color ==
                cardPalette(CardLighting.daylight).shelf,
      );
      expect(boards, findsNWidgets(2), reason: '22 books stand on two boards');

      final box =
          tester.widget<DecoratedBox>(boards.first).decoration as BoxDecoration;
      expect(box.borderRadius, isNull, reason: 'a board has square ends');

      // The unit is read back off the board rather than assumed, because the reach below
      // is only comparable with [kCardShelfFloorUnits] in units.
      final unit = tester.getSize(boards.first).height / kCardBoardUnits;
      final shadow = box.boxShadow!.single;
      expect(shadow.offset.dy, closeTo(kCardBoardShadowUnits * unit, 1e-6));
      expect(shadow.blurRadius, closeTo(kCardBoardShadowUnits * unit, 1e-6));
      // **Why the gap and the shadow are one number.** A shadow reaching further than
      // the air `_Well` leaves under the bottom board is eaten by the well's `ClipRect`
      // on that board alone, and the card ships one shadowed board above one unshadowed
      // one.
      expect(
        (shadow.offset.dy + shadow.blurRadius) / unit,
        closeTo(kCardShelfFloorUnits, 1e-6),
      );
    });
  });

  group('CardCoverRow overflow', () {
    testWidgets('Given more books than the shelf holds, When it renders, '
        'Then it prints the count it is not showing instead of squeezing', (
      tester,
    ) async {
      // The decision this design turns on. Two rejected layouts absorbed a large library
      // by thinning the books until they stopped being books; this one states the
      // shortfall and leaves the books alone.
      await _pump(tester, _books(60));

      final drawn = _drawn(tester).length;
      expect(
        drawn,
        30,
        reason: 'the overlapping capacity with the plate and the seal reserved',
      );
      expect(find.text('+${60 - drawn}'), findsOneWidget);
      expect(_boxOf(tester, 'b59').width, closeTo(kCardFaceUnits * _u, 0.01));
    });

    testWidgets('Given a library past capacity, When the shelf renders, '
        'Then it draws what fits and accounts for the rest', (tester) async {
      // Thirty **with the plate reserved**, which is why it is one under the 31
      // `card_shelf_plan_test.dart` pins: the count of what is missing is paid for out of
      // the same 98 units as the books. That 31 already carries the seal's corner, which
      // the top board pays for — see `kCardSealReserveUnits`.
      await _pump(tester, _books(90));

      expect(_drawn(tester).length, 30);
      // The plate counts the reader's whole shelf, not the truncated list the row draws
      // from: `cardCoverBooks` keeps at most `kCardCoverMax` books to bound the precache,
      // and planning against that number would tell a reader with 90 books that the shelf
      // is hiding one.
      expect(find.text('+${90 - 30}'), findsOneWidget);
    });

    testWidgets('Given a library the shelf holds exactly, When it renders, '
        'Then there is no count of missing books at all', (tester) async {
      await _pump(tester, _books(31));

      expect(_drawn(tester).length, 31);
      expect(find.textContaining('+'), findsNothing);
    });
  });

  group('CardCoverRow layout', () {
    testWidgets('Given any count, When the shelf renders, '
        'Then every book on it is a cover', (tester) async {
      // **The card draws covers and nothing else.** A `Covers | Spines` control shipped in
      // the share preview and was withdrawn: the card exists to be recognised as the
      // reader's own shelf, and a shelf of spines is a different object. Asserted at a
      // count on both sides of the grown/leaning threshold, because the spine renderer
      // used to be reachable from either.
      for (final count in const [4, 22]) {
        await _pump(tester, _books(count));

        expect(find.byType(BookVertical), findsNothing);
        expect(
          find.byType(GeneratedCover),
          findsNWidgets(_drawn(tester).length),
          reason: 'at $count books',
        );
      }
    });

    testWidgets('Given few books, When the covers render, '
        'Then none of them leans', (tester) async {
      // Overlapping is permission to lean, not an instruction: below eleven books the
      // shelf has room to stand them apart, so it does. **That is why the side-by-side
      // setting could be withdrawn without costing the reader it was aimed at anything** —
      // for a small library the two settings drew the same shelf, and above eleven the
      // one that survived is the one that shows the books.
      await _pump(tester, _books(6));
      // Pairwise rather than left-to-right: six grown covers land on two boards of three,
      // so "the next one along" is not simply the next in the list — and the claim is
      // about overlap in both axes anyway.
      final boxes = [for (final isbn in _drawn(tester)) _boxOf(tester, isbn)];

      expect(boxes, hasLength(6));
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          expect(
            boxes[i].overlaps(boxes[j]),
            isFalse,
            reason: 'cover $i and cover $j overlap',
          );
        }
      }
    });
  });

  group('CardCoverRow open books', () {
    testWidgets('Given a book the reader has open, When the shelf renders, '
        'Then it is a whole cover wearing a bookmark whatever the setting', (
      tester,
    ) async {
      // The hero counts books *read*, and that figure has to keep meaning what it says.
      // What stops a card reading "22 books" over 24 covers as a mistake is that an open
      // book is visibly a different class of thing, so the bookmark is load-bearing and
      // cannot be dropped for looks.
      await _pump(tester, _books(6), reading: [_open('r0'), _open('r1')]);

      expect(find.byKey(const ValueKey('cover-bookmark-r0')), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-bookmark-r1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cover-bookmark-b0')),
        findsNothing,
        reason: 'a finished book must not wear one',
      );
    });

    testWidgets('Given a book the reader has open, When it renders, '
        'Then the mark is the library shelf\'s own ribbon', (tester) async {
      // **Not a mark of the card's own.** The card used to draw a red rectangle where
      // `shelf_row.dart` hangs `bookmarkIcon.svg` — one state with two appearances, on a
      // card whose whole job is to look like the shelf it is a picture of. Asserting the
      // widget rather than a colour is the point: they are one object now, so a change to
      // the ribbon lands on both.
      await _pump(tester, _books(4), reading: [_open('r0')]);

      expect(find.byType(ReadingBookmark), findsOneWidget);

      // And at the library's proportions rather than a size of its own: a fixed 22 x 38
      // ribbon over a book [kReadingBookmarkBook] tall is a fraction of that book, and the
      // card's cover has to get the same fraction.
      final cover = _boxOf(tester, 'r0');
      final scale = cover.height / kReadingBookmarkBook;
      final ribbon = tester.getRect(find.byType(ReadingBookmark));
      expect(ribbon.width, closeTo(kReadingBookmarkWidth * scale, 0.01));
      expect(ribbon.height, closeTo(kReadingBookmarkHeight * scale, 0.01));
      // Hung from the cover's head at the shelf's own inset, so it reads as a ribbon in
      // the book rather than a flag beside it.
      expect(ribbon.top, closeTo(cover.top, 0.01));
      expect(
        cover.right - ribbon.right,
        closeTo(kReadingBookmarkInset * scale, 0.01),
      );
    });

    testWidgets('Given an open book under a candle, When the shelf renders, '
        'Then it carries no month stamp', (tester) async {
      // The second of the two marks, and the same argument: a stamp reading a date
      // nobody recorded is worse than a cover without one.
      await _pump(
        tester,
        _books(3),
        reading: [_open('r0')],
        lighting: CardLighting.candlelight,
      );

      expect(find.byKey(const ValueKey('cover-stamp-b0')), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-stamp-r0')), findsNothing);
      expect(find.text('MAR'), findsNWidgets(3));
    });

    testWidgets('Given open books, When the shelf renders, '
        'Then they stand at the front of it', (tester) async {
      await _pump(tester, _books(3), reading: [_open('r0')]);

      expect(_boxOf(tester, 'r0').left, lessThan(_boxOf(tester, 'b2').left));
    });

    testWidgets('Given more open books than a board holds, When the shelf renders, '
        'Then it draws what fits instead of throwing', (tester) async {
      // **The crash a real card shipped with.** The front group is capped at what one
      // board carries, so a reader with six books on the go had five drawn — and the
      // read books were then numbered from *five* while the drawing looked them up by
      // subtracting *six*. `ordered[-1]`, a `RangeError` in place of the shelf, and
      // because a thrown widget is offered unbounded height, `BOTTOM OVERFLOWED BY
      // 99901 PIXELS` under it.
      //
      await _pump(
        tester,
        _books(22),
        reading: [for (var i = 0; i < 6; i++) _open('r$i')],
      );

      expect(tester.takeException(), isNull, reason: 'six open books');
      // The newest read book is drawn, which is the proof the lookup is right rather
      // than merely not throwing: an off-by-one here would draw somebody else's book.
      expect(find.byKey(const ValueKey('cover-b21')), findsOneWidget);
      expect(_drawn(tester), isNotEmpty);
    });

    testWidgets('Given a shelf that cannot fit every open book, When it renders, '
        'Then the ones it drew are the reader\'s own', (tester) async {
      // The front group is `reading` in order, so the books drawn have to be its first
      // few and not an arbitrary window into it.
      await _pump(
        tester,
        _books(4),
        reading: [for (var i = 0; i < 8; i++) _open('r$i')],
      );

      expect(find.byKey(const ValueKey('cover-r0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cover-r7')),
        findsNothing,
        reason: 'past what a board holds, and dropped rather than squeezed',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Given a book that fails to draw, When the shelf renders, '
        'Then the damage is the size of the shelf', (tester) async {
      // The second half of the same defect, and the half that made it unmissable. A
      // thrown widget inside an unbounded box takes `ErrorWidget`'s default enormous
      // size; the shelf states its own height now, which the plan knows exactly, so a
      // failure is a red rectangle where a shelf was rather than 99,901 pixels of one.
      await _pump(tester, _books(22));

      final shelf = tester.getSize(find.byType(CardCoverRow));
      expect(
        shelf.height,
        closeTo(
          cardShelfPlan(
                reading: 0,
                read: 22,
                plateUnits: kCardPlateUnits,
              ).heightUnits() *
              _u,
          0.01,
        ),
      );
      expect(shelf.height, lessThan(kCardUnits * _u));
    });
  });

  group('CardCoverRow selection', () {
    testWidgets('Given no books at all, When the row renders, '
        'Then it draws nothing', (tester) async {
      await _pump(tester, const []);

      expect(_drawn(tester), isEmpty);
      expect(find.byType(BookVertical), findsNothing);
    });

    testWidgets(
      'Given several books, When the shelf renders, Then the newest is leftmost',
      (tester) async {
        // The leftmost cover is the one a reader's eye lands on, the one that survives a
        // crop, and — when the covers lean — the only one shown whole.
        await _pump(tester, _books(3));

        expect(_boxOf(tester, 'b2').left, lessThan(_boxOf(tester, 'b0').left));
      },
    );

    testWidgets('Given books with covers, When providers are collected, '
        'Then there is one per drawn face and none for the rest', (
      tester,
    ) async {
      // The precache contract. A provider missing here is a hole in the export, and
      // nothing on screen would show it.
      final withCovers = _books(14, thumbnail: 'https://example.test/c.jpg');
      expect(cardCoverProviders(withCovers).length, 14);

      final many = _books(90, thumbnail: 'https://example.test/c.jpg');
      expect(
        cardCoverProviders(many).length,
        30,
        reason:
            'the faces the overlapping setting actually draws, and no more: '
            'a reader with 90 books must not fetch 90 images to export one card',
      );

      final mixed = [
        _book('has', thumbnail: 'https://example.test/c.jpg'),
        _book('none'),
      ];
      expect(cardCoverProviders(mixed).length, 1);
      expect(cardCoverProviders(const []), isEmpty);
    });
  });

  group('CardCoverRow fallbacks', () {
    testWidgets('Given a book with no thumbnail, When it renders, '
        'Then it draws a generated cover', (tester) async {
      await _pump(tester, _books(2));

      expect(find.byType(GeneratedCover), findsNWidgets(2));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
      'Given books with thumbnails, When they render, Then the images are drawn',
      (tester) async {
        await _pump(tester, _books(3, thumbnail: 'https://example.test/c.jpg'));

        expect(find.byType(Image), findsNWidgets(3));
        expect(find.byType(GeneratedCover), findsNothing);
      },
    );

    testWidgets('Given a thumbnail that fails to load, When it renders, '
        'Then the cover falls back rather than leaving a hole', (tester) async {
      coverImageProvider = (_) => _FailingImage();

      await _pump(tester, _books(2, thumbnail: 'https://example.test/c.jpg'));
      await tester.pump();

      // The visual half of the precache contract: the shelf keeps both of its books, and
      // at this size the fallback still draws each title.
      expect(_drawn(tester).length, 2);
      expect(find.byType(GeneratedCover), findsNWidgets(2));
    });
  });
}

/// Fails immediately, standing in for a dead URL or a thumbnail Google has moved.
class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(Exception('cover unavailable')),
  );
}
