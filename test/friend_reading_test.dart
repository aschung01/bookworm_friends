// Tests for the Friends tab's Everyone row: what each friend is reading, and how many
// books they have read.
//
// Two layers, tested separately. `groupFriendReading` is a pure regrouping of rows, so
// it is a plain unit test. The row on top of it is a widget test, and what it has to
// prove is mostly about **absence**: a friend with nothing in progress gets a
// placeholder and no cover, and a friend whose data has not arrived gets neither a
// subtitle nor a count — but occupies exactly the same height either way.
//
// The height invariant is the one worth being blunt about. The batched query fills
// every row at once, so if the row grows when data lands, the whole list jumps in a
// single frame. That is why the subtitle is always rendered, even empty.
//
// `FriendReading.none` (loaded, nothing to show) and a **missing map entry** (still
// loading) are different states that are easy to conflate. RLS makes the second one
// real rather than theoretical: `is_profile_visible` filters per row, so a friend who
// has gone private is absent from the response instead of returning zero books.
//
// Two groups here are not about the row at all, and are here because Friends is the tab
// that exercises them: where the sheet rests when collapsed, and who a vertical swipe
// inside the body belongs to. Friends states no separate collapsed body, so the same
// scrollable list shows at every position — which makes it the one tab where "does the
// sheet move or does the list?" has a visible answer at three different heights.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/friend_reading.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

const _surface = Size(400, 900);

// Inlined rather than imported from the provider library, so a pure grouping test does
// not pull Supabase in.
const _reading = 1;
const _finished = 2;

Book _book(String id, String owner, int status, {String title = 'Book'}) =>
    Book(
      id: id,
      userId: owner,
      shelfId: 's',
      isbn: id,
      title: title,
      thumbnail: '',
      status: status,
      position: 0,
      createdAt: DateTime(2024),
    );

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Future<void> _pump(
  WidgetTester tester, {
  required List<Profile> following,
  required Map<String, FriendReading> reading,
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            FriendsSheet(
              following: following,
              reading: reading,
              selectedFriend: null,
              maxExtent: _surface.height,
              onSelectFriend: (_) {},
              onAddFriend: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The row's highlight box — the thing that tints under a finger, and the handle this
/// file uses to measure a row.
final _rowBox = find
    .descendant(
      of: find.byType(FriendsSheet),
      matching: find.byType(AnimatedContainer),
    )
    .first;

/// The colour the row is currently painted, or null when it is transparent.
Color? _rowColour(WidgetTester tester) {
  final colour = _paintedRowColour(tester);
  return colour == null || colour.a == 0 ? null : colour;
}

/// The row's tint **as actually painted this frame**, including mid-animation.
///
/// Read off the `DecoratedBox` that `AnimatedContainer` builds, not off the
/// `AnimatedContainer` itself: the latter carries the *target* decoration, so a test
/// that reads it sees only the endpoints and can never catch a bad interpolation.
Color? _paintedRowColour(WidgetTester tester) {
  final box = find
      .descendant(of: _rowBox, matching: find.byType(DecoratedBox))
      .first;
  final decoration = tester.widget<DecoratedBox>(box).decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

/// Runs the press fade all the way to its end.
///
/// Two pumps, and that second one is the whole subtlety. The frame built straight
/// after a state change is where `AnimatedContainer` *starts* its animation: it still
/// paints the old value, and only the frames after it interpolate. So a lone
/// `pump(Duration(milliseconds: 200))` reads the colour from *before* the press, no
/// matter how long the duration is. The press tests missed this at first because they
/// read the target decoration off the `AnimatedContainer`, which is right immediately
/// and animates nothing.
Future<void> _settlePress(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('the collapsed position', () {
    // Friends has no second, collapsed body: the same list shows at every position
    // and collapsing only shortens the viewport onto it. Both halves of that are
    // worth pinning, because both have been wrong.
    //
    // It showed *nothing* at rest for one commit. Collapsed used to mean "handle and
    // header alone", which was invisible while nothing floored the position — and
    // `LibrarySheet.minHeightFraction` floors it at a fifth of the screen, so the
    // difference became a card of blank space with seven friends hidden behind it.
    // The fix was in `LibrarySheet`: a capped sheet stating no collapsed body keeps
    // its bounded, scrollable body there, so the rows are simply cut off at the
    // card's edge.
    testWidgets(
      'Given the sheet is collapsed, When it rests, Then the list is still what it '
      'shows, cut off rather than swapped away',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'jisoo'), _friend('b', 'minho')],
          reading: const {
            'a': FriendReading(finishedCount: 3),
            'b': FriendReading(finishedCount: 1),
          },
        );

        // The handle toggles the two ends, and Friends opens at the middle detent,
        // so one tap puts it away.
        await tester.tap(find.byType(SheetGrabHandle));
        await tester.pumpAndSettle();

        final sheet = tester.getRect(find.byType(LibrarySheet));
        expect(
          sheet.height,
          closeTo(_surface.height * 0.2, 1),
          reason:
              'the floor, so this also fails if Friends stops passing '
              'minHeightFraction',
        );
        expect(
          find.text('jisoo'),
          findsOneWidget,
          reason: 'a collapsed sheet that shows none of its list is the bug',
        );
        expect(
          tester.getRect(find.text('jisoo')).top,
          lessThan(sheet.bottom),
          reason: 'and the row is inside the card, not clipped away above it',
        );
      },
    );
  });

  // Who a vertical swipe inside the body belongs to: the sheet, until there is no more
  // sheet to open. Tested here rather than in `library_sheet_test.dart` because Friends
  // is the tab that has all three of the pieces at once — three real detents, a body
  // that genuinely overflows, and a floating bar over the bottom of it.
  group('a swipe in the body: the sheet first, then the list', () {
    testWidgets('Given the collapsed sheet, When the body is swiped up, Then the sheet '
        'opens a detent instead of scrolling the list', (tester) async {
      // The rule this pins is the one Flighty's sheet follows, and it replaces an
      // earlier test that asserted the opposite. A swipe up inside the body belongs
      // to the *sheet* until there is no more sheet to open: one swipe from collapsed
      // reaches the middle detent, a second reaches the cap, and only a third moves
      // the list. The tail of a list is reached by opening the sheet, not by
      // scrolling a viewport a fifth of the screen tall.
      //
      // Before this, the body scrolled at every position and did it badly: the sheet
      // was laid out at its cap on any frame it was not at rest, which collapsed
      // `maxScrollExtent` to zero and clamped the offset with it — the list snapped
      // back to the top on every touch that moved the sheet at all.
      await _pump(
        tester,
        following: [for (var i = 0; i < 20; i++) _friend('f$i', 'friend$i')],
        reading: const {},
      );
      await tester.tap(find.byType(SheetGrabHandle));
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(FriendsSheet),
        matching: find.byType(Scrollable),
      );
      // `tester.state`, not `Scrollable.of`: the latter walks *up* from the finder and
      // in the shell reports the library's scroller behind the sheet, which returns a
      // healthy offset while this list has not moved at all.
      double offset() => tester.state<ScrollableState>(list).position.pixels;
      double height() => tester.getRect(find.byType(LibrarySheet)).height;

      // Started near the top of the list so the drag cannot land on the floating tab
      // bar, which sits over the bottom of the collapsed viewport and swallows a
      // gesture whole.
      Future<void> swipeUp() async {
        final body = tester.getRect(list);
        await tester.flingFrom(
          Offset(body.center.dx, body.top + 12),
          const Offset(0, -120),
          800,
        );
        await tester.pumpAndSettle();
      }

      final collapsed = height();
      await swipeUp();
      final medium = height();
      expect(
        medium,
        greaterThan(collapsed + 20),
        reason: 'the first swipe opens the sheet',
      );
      expect(
        offset(),
        0,
        reason: 'and does not scroll the list past the reader on the way',
      );

      await swipeUp();
      final expanded = height();
      expect(
        expanded,
        greaterThan(medium + 20),
        reason: 'the second swipe takes it the rest of the way',
      );
      expect(offset(), 0, reason: 'still the sheet moving, not the list');

      await swipeUp();
      expect(
        height(),
        closeTo(expanded, 0.5),
        reason: 'the sheet has nowhere left to go, so it stays put',
      );
      expect(
        offset(),
        greaterThan(1),
        reason: 'and only now does the list underneath move',
      );
    });

    testWidgets('Given the list scrolled at the cap, When it is swiped down past its top, '
        'Then the sheet takes the drag back', (tester) async {
      // The other half of the rule. Without it a scrolled list at the cap is a trap:
      // the sheet can only be put away by finding the header, because every downward
      // drag in the body dies the moment the list runs out of offset.
      //
      // Read from the body's overscroll rather than by fighting for the gesture — by
      // then it belongs to the `Scrollable` and will not be given up — which is why
      // the body is on clamping physics: a bouncing overscroll rubber-bands the list
      // and reports nothing to hand over.
      await _pump(
        tester,
        following: [for (var i = 0; i < 20; i++) _friend('f$i', 'friend$i')],
        reading: const {},
      );

      final list = find.descendant(
        of: find.byType(FriendsSheet),
        matching: find.byType(Scrollable),
      );
      double offset() => tester.state<ScrollableState>(list).position.pixels;
      double height() => tester.getRect(find.byType(LibrarySheet)).height;

      Future<void> swipe(double dy) async {
        final body = tester.getRect(list);
        await tester.flingFrom(
          Offset(body.center.dx, body.top + 12),
          Offset(0, dy),
          800,
        );
        await tester.pumpAndSettle();
      }

      // Friends opens at the medium detent, so one swipe up reaches the cap and the
      // next actually scrolls.
      await swipe(-120);
      await swipe(-120);
      final expanded = height();
      expect(
        offset(),
        greaterThan(1),
        reason:
            'the list has to be scrolled for the hand-back to mean anything',
      );

      // Enough to run the list out of offset and keep pulling.
      await swipe(400);
      expect(offset(), 0, reason: 'the list unwinds to its top first');
      expect(
        height(),
        lessThan(expanded - 20),
        reason:
            'and the same drag carries on into the sheet rather than stopping '
            'dead at the top of the list',
      );
    });
  });

  group('the Everyone row responds to a press', () {
    testWidgets(
      'Given a finger goes down on a row, When it is held, Then the row is tinted',
      (tester) async {
        // What a tap looked like before this: nothing at all. The row was an `InkWell`,
        // and `LibrarySheet` paints its background with a `DecoratedBox` rather than a
        // `Material` — so the splash rendered on the `Scaffold`'s material *behind* the
        // sheet and was never visible. A test that only checked an `InkWell` was
        // present would have passed the whole time.
        await _pump(
          tester,
          following: [_friend('a', 'jisoo')],
          reading: const {'a': FriendReading(finishedCount: 3)},
        );

        expect(_rowColour(tester), isNull, reason: 'untouched, so no tint');

        final gesture = await tester.startGesture(tester.getCenter(_rowBox));
        await _settlePress(tester);

        expect(
          _rowColour(tester),
          isNotNull,
          reason: 'a press with no visible answer is the bug this fixes',
        );

        await gesture.up();
        await _settlePress(tester);

        expect(_rowColour(tester), isNull, reason: 'and it lets go');
      },
    );

    testWidgets(
      'Given the press lands on the avatar, When it is held, Then the row still tints',
      (tester) async {
        // The reason the press is driven by raw pointer events rather than `onTapDown`.
        // `AvatarCircle` has its own gesture detector and wins the arena for taps that
        // land on it, so a tap-based press state would leave the row looking dead when
        // you press the most obviously pressable thing in it.
        await _pump(
          tester,
          following: [_friend('a', 'jisoo')],
          reading: const {'a': FriendReading(finishedCount: 3)},
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(AvatarCircle)),
        );
        await _settlePress(tester);

        expect(_rowColour(tester), isNotNull);

        await gesture.up();
        await _settlePress(tester);
        expect(_rowColour(tester), isNull);
      },
    );

    testWidgets('Given the highlight is fading in, When a frame mid-animation is inspected, '
        'Then only its alpha has moved — it never darkens', (tester) async {
      // Reported from a device: the row "flashes dark gray for a quarter sec upon tap
      // then shows a lighter gray". The cause was fading from `Colors.transparent`,
      // which is transparent *black* — `Color.lerp` walks the RGB channels along with
      // the alpha, so every intermediate frame was a semi-opaque dark grey on its way
      // to a light one.
      //
      // The two press tests above passed throughout, because they looked at the
      // endpoints and never at a frame in between. This is the assertion that had to
      // exist.
      await _pump(
        tester,
        following: [_friend('a', 'jisoo')],
        reading: const {'a': FriendReading(finishedCount: 3)},
      );

      final gesture = await tester.startGesture(tester.getCenter(_rowBox));

      // The frame that *starts* the fade, which still paints the old colour.
      await tester.pump();
      // And a frame partway through it, well short of the 110ms the fade takes.
      await tester.pump(const Duration(milliseconds: 40));
      final mid = _paintedRowColour(tester)!;

      // Settled.
      await tester.pump(const Duration(milliseconds: 300));
      final settled = _paintedRowColour(tester)!;

      expect(
        mid.a,
        greaterThan(0),
        reason:
            'a frame still at the start value would prove nothing either way',
      );
      expect(
        mid.a,
        lessThan(settled.a),
        reason: 'the fade must still be in progress for this to mean anything',
      );
      expect(
        [mid.r, mid.g, mid.b],
        [settled.r, settled.g, settled.b],
        reason:
            'the hue must be constant through the fade; drifting RGB is what made '
            'the row flash dark before settling light',
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets(
      'Given a cancelled press, When the finger slides off, Then the tint lets go',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'jisoo')],
          reading: const {'a': FriendReading(finishedCount: 3)},
        );

        final gesture = await tester.startGesture(tester.getCenter(_rowBox));
        await _settlePress(tester);
        expect(_rowColour(tester), isNotNull);

        await gesture.cancel();
        await _settlePress(tester);

        expect(
          _rowColour(tester),
          isNull,
          reason: 'a stuck highlight is worse than none — it looks selected',
        );
      },
    );

    testWidgets(
      'Given the sheet is inert, When a row is pressed, Then it does not tint',
      (tester) async {
        // During an edit the sheet is inert as a whole. A row that lit up under the
        // finger while doing nothing would be a worse lie than one that ignores you.
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  FriendsSheet(
                    following: [_friend('a', 'jisoo')],
                    reading: const {'a': FriendReading(finishedCount: 3)},
                    selectedFriend: null,
                    isEditMode: true,
                    maxExtent: _surface.height,
                    onSelectFriend: (_) {},
                    onAddFriend: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(_rowBox));
        await _settlePress(tester);

        expect(_rowColour(tester), isNull);

        await gesture.up();
      },
    );

    testWidgets(
      'Given a row is tapped, When the gesture completes, Then the friend is selected',
      (tester) async {
        Profile? selected;
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  FriendsSheet(
                    following: [_friend('a', 'jisoo')],
                    reading: const {'a': FriendReading(finishedCount: 3)},
                    selectedFriend: null,
                    maxExtent: _surface.height,
                    onSelectFriend: (profile) => selected = profile,
                    onAddFriend: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Adding the press state must not have cost the tap. Tapping the text rather
        // than the centre, so this also proves the opaque hit area still works where
        // there is no glyph.
        await tester.tap(find.text('jisoo'));
        await tester.pumpAndSettle();

        expect(selected?.username, 'jisoo');
      },
    );
  });

  group('groupFriendReading', () {
    test(
      'Given books for several friends, When grouped, Then each gets their own',
      () {
        final result = groupFriendReading(
          ['a', 'b'],
          [
            _book('1', 'a', _reading, title: 'Snow'),
            _book('2', 'a', _finished),
            _book('3', 'a', _finished),
            _book('4', 'b', _finished),
          ],
          readingStatus: _reading,
          finishedStatus: _finished,
        );

        expect(result['a']!.inProgress.map((b) => b.title), ['Snow']);
        expect(result['a']!.finishedCount, 2);
        expect(result['b']!.inProgress, isEmpty);
        expect(result['b']!.finishedCount, 1);
      },
    );

    test(
      'Given a friend reading two books at once, When grouped, Then both are kept',
      () {
        // A drawn state, not an edge case: the `EVERYONE` fixture's `minho` row is
        // "Reading Snow · Circe".
        final result = groupFriendReading(
          ['a'],
          [
            _book('1', 'a', _reading, title: 'Snow'),
            _book('2', 'a', _reading, title: 'Circe'),
          ],
          readingStatus: _reading,
          finishedStatus: _finished,
        );

        expect(result['a']!.inProgress.length, 2);
        expect(result['a']!.hasInProgress, isTrue);
      },
    );

    test(
      'Given a friend with no rows at all, When grouped, Then they still get an entry',
      () {
        // The case RLS makes real. Omitting the key would push the widget down a
        // different path for "invisible friend" than for "friend with no books", and
        // one of the two would go untested.
        final result = groupFriendReading(
          ['a', 'ghost'],
          [_book('1', 'a', _finished)],
          readingStatus: _reading,
          finishedStatus: _finished,
        );

        expect(result.containsKey('ghost'), isTrue);
        expect(result['ghost']!.finishedCount, 0);
        expect(result['ghost']!.hasInProgress, isFalse);
      },
    );

    test(
      'Given rows for someone not in the list, When grouped, Then they are ignored',
      () {
        final result = groupFriendReading(
          ['a'],
          [_book('1', 'a', _finished), _book('2', 'stranger', _finished)],
          readingStatus: _reading,
          finishedStatus: _finished,
        );

        expect(result.keys, ['a']);
        expect(result['a']!.finishedCount, 1);
      },
    );

    test(
      'Given a book that is neither reading nor finished, When grouped, Then it counts '
      'for nothing',
      () {
        // Status 0 is want-to-read, and 213 of the corpus rows are that. Counting them
        // as read would inflate every friend's figure.
        final result = groupFriendReading(
          ['a'],
          [_book('1', 'a', 0)],
          readingStatus: _reading,
          finishedStatus: _finished,
        );

        expect(result['a']!.finishedCount, 0);
        expect(result['a']!.hasInProgress, isFalse);
      },
    );
  });

  group('the Everyone row', () {
    testWidgets('Given a friend reading one book, When the row renders, '
        'Then it names the book and their read count', (tester) async {
      await _pump(
        tester,
        following: [_friend('a', 'jisoo')],
        reading: {
          'a': FriendReading(
            inProgress: [_book('1', 'a', _reading, title: 'The Vegetarian')],
            finishedCount: 24,
          ),
        },
      );

      expect(find.text('jisoo'), findsOneWidget);
      expect(find.text('Reading The Vegetarian'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
    });

    testWidgets('Given a friend reading two books, When the row renders, '
        'Then the titles are joined rather than one being dropped', (
      tester,
    ) async {
      await _pump(
        tester,
        following: [_friend('a', 'minho')],
        reading: {
          'a': FriendReading(
            inProgress: [
              _book('1', 'a', _reading, title: 'Snow'),
              _book('2', 'a', _reading, title: 'Circe'),
            ],
            finishedCount: 9,
          ),
        },
      );

      expect(find.text('Reading Snow · Circe'), findsOneWidget);
    });

    testWidgets(
      'Given a friend with nothing in progress, When the row renders, '
      'Then it says so and draws no cover',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'sora')],
          reading: {'a': const FriendReading(finishedCount: 6)},
        );

        expect(find.text('Nothing in progress'), findsOneWidget);
        expect(find.text('6'), findsOneWidget);
        // The fixture's `sora` row has an explicit null where the others have a
        // colour, so the absent cover is drawn, not incidental.
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets('Given data has not arrived, When the row renders, '
        'Then it shows neither a subtitle nor a count', (tester) async {
      await _pump(
        tester,
        following: [_friend('a', 'jisoo')],
        reading: const {},
      );

      expect(find.text('jisoo'), findsOneWidget);
      expect(find.text('Nothing in progress'), findsNothing);
      expect(
        find.text('0'),
        findsNothing,
        reason: 'a count of zero we do not have yet is worse than no count',
      );
    });

    testWidgets('Given data arrives, When the row is measured before and after, '
        'Then its height has not changed', (tester) async {
      // The invariant that matters. One batched query fills every row at once, so a
      // row that grows on arrival makes the entire list jump in one frame.
      final friends = [_friend('a', 'jisoo')];

      await _pump(tester, following: friends, reading: const {});
      final loading = tester.getSize(_rowBox);

      await _pump(
        tester,
        following: friends,
        reading: {
          'a': FriendReading(
            inProgress: [_book('1', 'a', _reading, title: 'The Vegetarian')],
            finishedCount: 24,
          ),
        },
      );
      final loaded = tester.getSize(_rowBox);

      expect(loaded.height, loading.height);
    });

    testWidgets(
      'Given several friends, When the list renders, Then each row shows its own data',
      (tester) async {
        await _pump(
          tester,
          following: [
            _friend('a', 'jisoo'),
            _friend('b', 'minho'),
            _friend('c', 'sora'),
          ],
          reading: {
            'a': FriendReading(
              inProgress: [_book('1', 'a', _reading, title: 'Dune')],
              finishedCount: 24,
            ),
            'b': const FriendReading(finishedCount: 9),
            // 'c' deliberately absent — still loading, or invisible to us.
          },
        );

        expect(find.text('Reading Dune'), findsOneWidget);
        expect(find.text('24'), findsOneWidget);
        expect(find.text('Nothing in progress'), findsOneWidget);
        expect(find.text('9'), findsOneWidget);
        expect(find.text('sora'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Given a book in progress, When the row renders, '
        'Then it draws the same book the shelves draw, in miniature', (
      tester,
    ) async {
      // This reverses what the previous test here asserted — that the mini cover was a
      // plain colour swatch with no title in it, because `GeneratedCover` sets its
      // title at 13.5% of the width and 3pt of type is a smudge. That was right about
      // the type and wrong about the book: it threw away the 3D chassis to solve a
      // font-size problem. Reinstated at an explicit request. The type is still tiny,
      // and that is now a known cost rather than a bug.
      await _pump(
        tester,
        following: [_friend('a', 'jisoo')],
        reading: {
          'a': FriendReading(
            inProgress: [_book('1', 'a', _reading, title: 'The Vegetarian')],
            finishedCount: 24,
          ),
        },
      );

      final book = tester.widget<BookWidget>(find.byType(BookWidget));
      expect(book.isbn, '1', reason: 'the same book, so the same hash');
      expect(book.title, 'The Vegetarian');
      expect(
        book.jitter,
        isTrue,
        reason:
            'the hashed height and page-count thickness are most of what makes it '
            'recognisably the same object as the one on the shelf',
      );
      expect(
        book.pressEffect,
        isFalse,
        reason:
            'the row owns the gesture; the book must not compete for the pointer',
      );
      expect(
        book.turnDrive,
        isNotNull,
        reason:
            'the turn comes from the row, since the finger is never on the book',
      );

      // The title is painted inside the cover now, and the subtitle is a different
      // string, so both are present and neither is the other.
      expect(find.text('Reading The Vegetarian'), findsOneWidget);
      expect(find.text('The Vegetarian'), findsOneWidget);
    });

    testWidgets('Given the row is held, When the book turns, '
        'Then it turns while the finger is down and falls back on release', (
      tester,
    ) async {
      // Driven by the press and not by the tap, and that is a correction. A tap looked
      // like the right trigger until the device showed otherwise: `onSelectFriend`
      // also flips the library mode, so the shell replaces the whole Friends sheet
      // and this row unmounts within a frame or two of release. A turn played on tap
      // is never seen by anyone.
      //
      // So this asserts the turn is under way *while the finger is still down*, which
      // is the only window in which it is visible. Moving the drive back onto the tap
      // fails here.
      await _pump(
        tester,
        following: [_friend('a', 'jisoo')],
        reading: {
          'a': FriendReading(
            inProgress: [_book('1', 'a', _reading, title: 'Dune')],
            finishedCount: 24,
          ),
        },
      );

      double turn() =>
          tester.widget<BookWidget>(find.byType(BookWidget)).turnDrive!.value;

      expect(turn(), 0, reason: 'at rest the book faces you');

      final gesture = await tester.startGesture(tester.getCenter(_rowBox));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));

      expect(
        turn(),
        greaterThan(0),
        reason: 'half way through the shelf\'s 260ms turn, so well under way',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        turn(),
        0,
        reason: 'a book left turned reads as broken, not as selected',
      );
    });

    testWidgets(
      'Given accessibility text sizes, When the rows render, Then nothing overflows',
      (tester) async {
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: Column(
                  children: [
                    const Expanded(child: SizedBox.expand()),
                    FriendsSheet(
                      following: [_friend('a', 'jisoo')],
                      reading: {
                        'a': FriendReading(
                          inProgress: [
                            _book('1', 'a', _reading, title: 'The Vegetarian'),
                          ],
                          finishedCount: 24,
                        ),
                      },
                      selectedFriend: null,
                      maxExtent: _surface.height,
                      onSelectFriend: (_) {},
                      onAddFriend: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The test font makes every glyph one em wide, so this is a strict upper bound
        // on real text.
        expect(tester.takeException(), isNull);
      },
    );
  });
}
