// **Two empty states, not one**, and the difference between them is the point.
//
// `noFriendsYet` has a fix — invite someone — and offers it, because an invite is now
// the *only* way anyone gains a friend. "Nobody is mid-book" has no fix, and offering
// one there would answer a question nobody asked. For a reading app the second is the
// common state, not the edge case: people finish a book and start the next one days
// later, so a dozen friends showing nothing in progress is an ordinary Tuesday.
//
// Drawn as one state until Flighty's Friends tab pointed out there are two, which is
// why the distinction is pinned rather than left to whoever edits the copy next.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/friend_reading.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

const _surface = Size(400, 900);

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// Counts the taps on the sheet's invite affordance, whichever one was used.
int _invites = 0;

Future<void> _pump(
  WidgetTester tester, {
  required List<Profile> following,
  required Map<String, FriendReading> reading,
  Size surface = _surface,
  TextScaler? textScaler,
}) async {
  _invites = 0;
  tester.view.physicalSize = surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => textScaler == null
          ? child!
          : MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            FriendsSheet(
              following: following,
              reading: reading,
              selectedFriend: null,
              maxExtent: surface.height,
              onSelectFriend: (_) {},
              onAddFriend: () => _invites += 1,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('no friends at all', () {
    testWidgets(
      'Given an empty list, When the sheet is shown, Then it offers the one action '
      'that changes it',
      (tester) async {
        await _pump(tester, following: [], reading: const {});

        expect(find.text('No friends yet'), findsOneWidget);
        // Handle search is gone, so this is not one option among several — it is the
        // only way in, and a blank sheet with a 22pt icon in the corner is not an
        // answer to it.
        expect(find.text('Invite a friend'), findsOneWidget);

        await tester.tap(find.text('Invite a friend'));
        await tester.pumpAndSettle();
        expect(_invites, 1);
      },
    );

    // **The state is three things stacked, and the sheet's floor is a fifth of the
    // screen.** `SheetBodyCenter` used to pin its child to the visible slice's exact
    // height through an `OverflowBox` — correct for what its doc said it was for, *a
    // single line of text*, and wrong here: at the collapsed detent the column
    // overflowed its box by 20pt and pushed the button off the card. Nothing else in
    // the suite caught it, because "the CTA is present" was true of the broken
    // version too. It centres when the child fits and scrolls when it does not now,
    // which is a fix for every empty state rather than for this one.
    for (final (label, surface, scaler) in <(String, Size, TextScaler?)>[
      ('a large phone', Size(402, 874), null),
      ('the smallest phone', Size(375, 667), null),
      // The worst case by construction: least height, largest type.
      ('a small phone at 2x text', Size(375, 667), TextScaler.linear(2)),
    ]) {
      testWidgets(
        'Given $label, When the sheet is collapsed on the empty state, Then '
        'nothing overflows',
        (tester) async {
          await _pump(
            tester,
            following: [],
            reading: const {},
            surface: surface,
            textScaler: scaler,
          );

          await tester.tap(find.byType(SheetGrabHandle));
          await tester.pumpAndSettle();

          // `tester.takeException` rather than an assertion about geometry: an
          // overflow is a thrown `FlutterError`, and it is the thing that put a
          // yellow-and-black bar across the sheet in the screenshot.
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'Given the sheet at rest, When the empty state is shown, Then the invite '
      'button is on the card and can be tapped',
      (tester) async {
        // Not overflowing is only half of it — a button clipped to just inside the
        // card would also throw nothing. Friends opens at the medium detent, so this
        // is the position that actually has to work.
        await _pump(tester, following: [], reading: const {});

        final sheet = tester.getRect(find.byType(LibrarySheet));
        expect(
          tester.getRect(find.text('Invite a friend')).bottom,
          lessThanOrEqualTo(sheet.bottom),
          reason: 'the one action on a blank sheet has to be inside the card',
        );

        await tester.tap(find.text('Invite a friend'));
        await tester.pumpAndSettle();
        expect(_invites, 1);
      },
    );

    testWidgets(
      'Given the sheet at rest, When the empty state is shown, Then it is centred '
      'in the card rather than sitting at the top of it',
      (tester) async {
        // **The point of `SheetBodyCenter`, and the thing the overflow fix must not
        // cost.** A heading pinned under the header with a screen of blank card
        // below it reads as content that failed to load; centred, the same three
        // elements read as a deliberate state. Asserted as a ratio rather than a
        // number so it survives a copy edit: what matters is that the space is
        // shared top and bottom, not the exact pixels.
        await _pump(tester, following: [], reading: const {});

        final sheet = tester.getRect(find.byType(LibrarySheet));
        final above =
            tester.getRect(find.text('No friends yet')).top - sheet.top;
        final below =
            sheet.bottom - tester.getRect(find.text('Invite a friend')).bottom;

        expect(
          above,
          greaterThan(sheet.height * 0.2),
          reason: 'a top-aligned state would leave almost nothing above it',
        );
        expect(
          below,
          greaterThan(0),
          reason: 'and the space has to be shared with the bottom',
        );
      },
    );

    testWidgets(
      'Given a small phone at 2x text, When the state cannot fit, Then the CTA is '
      'still reachable by scrolling',
      (tester) async {
        // The case that rules out simply centring: at this size the three elements
        // are taller than the body at *every* detent, so something has to give. It
        // scrolls — which is strictly better than the alternatives, shrinking the
        // type or letting the reader reach nothing.
        await _pump(
          tester,
          following: [],
          reading: const {},
          surface: const Size(375, 667),
          textScaler: const TextScaler.linear(2),
        );

        final sheet = tester.getRect(find.byType(LibrarySheet));
        expect(
          tester.getRect(find.text('Invite a friend')).bottom,
          greaterThan(sheet.bottom),
          reason:
              'the premise: at this size it does not fit, so it must scroll',
        );

        // Two drags, because the first is partly eaten by the touch slop.
        for (var i = 0; i < 2; i++) {
          await tester.drag(find.text('No friends yet'), const Offset(0, -300));
          await tester.pumpAndSettle();
        }

        expect(
          tester.getRect(find.text('Invite a friend')).bottom,
          lessThanOrEqualTo(sheet.bottom),
        );
        await tester.tap(find.text('Invite a friend'));
        await tester.pumpAndSettle();
        expect(_invites, 1);
      },
    );
  });

  group('friends, none of them reading', () {
    // **There is no banner for this state, and removing it was the point.**
    //
    // The drawings call for a second empty state here, and the reasoning is sound —
    // for a reading app, friends between books is the common case. But it was drawn
    // against a row showing a *read count*, and the row this app ships already prints
    // "Nothing in progress" on its own second line. With three idle friends the sheet
    // said it four times: once per row, then again in a banner summarising the rows
    // directly beneath it.
    //
    // These tests survive the banner because they were never really about it: what
    // matters is that the state is legible and that it does not offer a fix it does
    // not have.

    testWidgets(
      'Given friends with nothing in progress, When the sheet is shown, Then each '
      'row says so itself',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'jisoo'), _friend('b', 'minho')],
          reading: const {
            'a': FriendReading(finishedCount: 24),
            'b': FriendReading(finishedCount: 9),
          },
        );

        // Once per friend, and nowhere else. A summary above the list would make it
        // three occurrences of one fact on a two-row sheet.
        expect(find.text('Nothing in progress'), findsNWidgets(2));
      },
    );

    testWidgets(
      'Given friends with nothing in progress, When the sheet is shown, Then it '
      'does not offer to invite anyone',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'jisoo'), _friend('b', 'minho')],
          reading: const {
            'a': FriendReading(finishedCount: 24),
            'b': FriendReading(finishedCount: 9),
          },
        );

        // Inviting is not the fix here, and suggesting it would misread the
        // situation as a shortage of friends rather than a quiet week.
        expect(find.text('Invite a friend'), findsNothing);
        expect(find.text('No friends yet'), findsNothing);
      },
    );

    testWidgets(
      'Given the quiet state, When the sheet is shown, Then the list is still '
      'there to be tapped',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'jisoo'), _friend('b', 'minho')],
          reading: const {
            'a': FriendReading(finishedCount: 24),
            'b': FriendReading(finishedCount: 9),
          },
        );

        // The whole difference from the no-friends state: there are people here and
        // every one of them has a finished shelf worth looking at, so a message
        // *instead of* the rows would hide the thing worth tapping.
        expect(find.text('jisoo'), findsOneWidget);
        expect(find.text('minho'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the batch query has not landed, When the sheet is shown, Then no row '
      'claims anything yet',
      (tester) async {
        // `reading` is empty until `friendsReadingProvider` resolves, and an empty
        // map is indistinguishable from "loaded, nobody reading" to anything that
        // only asks whether a book is in progress. The row draws a blank subtitle
        // rather than asserting "Nothing in progress" and then correcting itself a
        // frame later, which reads as a glitch rather than as information.
        await _pump(
          tester,
          following: [_friend('a', 'jisoo'), _friend('b', 'minho')],
          reading: const {},
        );

        expect(find.text('Nothing in progress'), findsNothing);
      },
    );
  });

  group('the header action', () {
    testWidgets(
      'Given any state, When the header icon is used, Then it invites rather than '
      'searches',
      (tester) async {
        await _pump(
          tester,
          following: [_friend('a', 'jisoo')],
          reading: const {'a': FriendReading(finishedCount: 3)},
        );

        // The tooltip used to say `searchFriends`, which is now wrong in both
        // senses: there is no handle search, and the only way to gain a friend is to
        // send a link.
        expect(
          find.byTooltip('Invite a friend'),
          findsOneWidget,
          reason: 'the header action is an invite, and must say so',
        );

        await tester.tap(find.byTooltip('Invite a friend'));
        await tester.pumpAndSettle();
        expect(_invites, 1);
      },
    );
  });
}
