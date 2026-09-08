// Tests for the who-reacted sheet.
//
// This sheet is what capping the capsule buys: the detail that no longer fits in
// a 217pt column, and the one thing an emoji alone cannot carry — whose reaction
// it is. It is also the only route to your own reaction, so the ordering of the
// rows and the tappability of yours alone are the contract worth pinning.
//
// Pumped directly rather than through the details page, because the row's
// destination is the emoji picker and that drags in `SharedPreferences` and the
// picker package. What belongs here is the callback: the sheet's job is to close
// itself and hand over, and that is testable without either.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/reactions_sheet.dart';

const _me = 'me';

BookCompliment _r(
  String emoji, {
  required String from,
  String? name = 'Jihyun',
  String? avatarPath,
  String? reactorEmoji,
}) => BookCompliment(
  id: 'c-$from',
  bookId: 'b1',
  fromUserId: from,
  compliment: emoji,
  createdAt: DateTime(2024),
  reactorName: name,
  reactorEmoji: reactorEmoji,
  reactorAvatarPath: avatarPath,
);

/// Opens the sheet over a trivial page and settles it.
Future<int> _open(
  WidgetTester tester, {
  required List<BookCompliment> compliments,
  String? userId = _me,
}) async {
  var edits = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showReactionsSheet(
                context,
                compliments: compliments,
                currentUserId: userId,
                onEditMine: () => edits++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return edits;
}

void main() {
  group('showReactionsSheet', () {
    testWidgets('Given several reactions, Then every one is named', (
      tester,
    ) async {
      await _open(
        tester,
        compliments: [
          _r('👏', from: 'a', name: 'Jihyun'),
          _r('🔥', from: 'b', name: 'Minsu'),
        ],
      );

      expect(find.text('Reactions'), findsOneWidget);
      expect(find.text('Jihyun'), findsOneWidget);
      expect(find.text('👏'), findsOneWidget);
      expect(find.text('Minsu'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.byType(AvatarCircle), findsNWidgets(2));
    });

    testWidgets(
      'Given one of them is yours, Then it leads the list and is marked',
      (tester) async {
        await _open(
          tester,
          compliments: [
            _r('👏', from: 'a', name: 'Jihyun'),
            _r('🦄', from: _me, name: 'Areum'),
          ],
        );

        expect(find.text('You'), findsOneWidget);
        // Ordered by `orderedReactions`, so yours is above theirs on screen.
        expect(
          tester.getCenter(find.text('Areum')).dy,
          lessThan(tester.getCenter(find.text('Jihyun')).dy),
        );
      },
    );

    testWidgets(
      'Given a row of your own, Then a chevron carries the drill-in unaided',
      (tester) async {
        await _open(tester, compliments: [_r('🦄', from: _me)]);

        // The help text that used to sit under the list is gone: it captioned a
        // control the row's own disclosure already announces, and it was the one
        // string in this sheet that needed translating to say anything.
        expect(find.text('Tap your row to change or remove it.'), findsNothing);
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      },
    );

    testWidgets("Given no row of your own, Then nothing offers a drill-in", (
      tester,
    ) async {
      await _open(tester, compliments: [_r('👏', from: 'a')]);

      expect(find.text('You'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('Given a profile the viewer cannot read, Then the row says so', (
      tester,
    ) async {
      await _open(tester, compliments: [_r('👏', from: 'a', name: null)]);

      // `book_compliments` is gated on the book while `profiles` is gated on
      // the follow graph, so seeing a reaction without its author is reachable.
      // A blank name beside an avatar placeholder would read as a bug.
      expect(find.text("Someone you don't follow"), findsOneWidget);
    });

    testWidgets(
      'Given you tap your own row, Then the sheet closes and hands over once',
      (tester) async {
        var edits = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showReactionsSheet(
                      context,
                      compliments: [_r('🦄', from: _me, name: 'Areum')],
                      currentUserId: _me,
                      onEditMine: () => edits++,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Areum'));
        await tester.pumpAndSettle();

        expect(edits, 1);
        // Popped, so the picker replaces it instead of stacking on top. Putting
        // it back when the picker is dismissed without a choice is the caller's
        // job — see `_onReactionsPressed`, which loops on exactly that.
        expect(find.text('Reactions'), findsNothing);
      },
    );

    testWidgets(
      "Given someone else's row, When it is tapped, Then nothing happens",
      (tester) async {
        var edits = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showReactionsSheet(
                      context,
                      compliments: [_r('👏', from: 'a', name: 'Jihyun')],
                      currentUserId: _me,
                      onEditMine: () => edits++,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Jihyun'));
        await tester.pumpAndSettle();

        // You cannot change or remove a reaction that is not yours, so the row
        // is passed a null `onTap` rather than an empty one — which also means it
        // shows no press feedback and does not pretend to be interactive.
        expect(edits, 0);
        expect(find.text('Reactions'), findsOneWidget);
      },
    );
  });
}
