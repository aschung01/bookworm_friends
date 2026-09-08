// Tests for the capped reaction capsule and the ordering behind it.
//
// The capsule replaced a `Wrap` of one 28pt circle per reaction, which grew
// without limit, could not say whose reaction was whose, and did not read as a
// control. Three properties are load-bearing and each is asserted here:
//
// * it shows at most `kVisibleReactions`, then counts;
// * yours is pinned first, because the button that used to report your state is
//   gone and a reaction of yours hidden behind `+N` would leave nothing on screen
//   saying you had reacted at all;
// * it is tinted when one of the reactions is yours, using the same treatment
//   `PraiseEmojiPicker` marks your cell with.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/ui/widgets/reaction_capsule.dart';

BookCompliment _r(String emoji, {required String from, String id = 'c'}) =>
    BookCompliment(
      id: '$id-$from',
      bookId: 'b1',
      fromUserId: from,
      compliment: emoji,
      createdAt: DateTime(2024),
      reactorName: from,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<BookCompliment> compliments,
  String? userId = 'me',
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: ReactionCapsule(
            compliments: compliments,
            currentUserId: userId,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
}

/// The capsule's own fill, which is what carries "one of these is yours".
Color _fill(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(ReactionCapsule),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration as BoxDecoration).color!;
}

void main() {
  group('orderedReactions', () {
    test('Given a reaction of yours third, Then it is moved to the front', () {
      final all = [
        _r('👏', from: 'a'),
        _r('🔥', from: 'b'),
        _r('🦄', from: 'me'),
      ];

      final ordered = orderedReactions(all, 'me');

      expect(ordered.first.compliment, '🦄');
      // Everyone else keeps the provider's newest-first order behind it.
      expect(ordered.map((c) => c.compliment).toList(), ['🦄', '👏', '🔥']);
    });

    test('Given no reaction of yours, Then the order is untouched', () {
      final all = [_r('👏', from: 'a'), _r('🔥', from: 'b')];

      expect(orderedReactions(all, 'me').map((c) => c.compliment).toList(), [
        '👏',
        '🔥',
      ]);
    });

    test('Given nobody signed in, Then the order is untouched', () {
      final all = [_r('👏', from: 'a'), _r('🔥', from: 'b')];

      expect(orderedReactions(all, null).map((c) => c.compliment).toList(), [
        '👏',
        '🔥',
      ]);
    });
  });

  group('ReactionCapsule', () {
    testWidgets('Given no reactions, Then it collapses to nothing', (
      tester,
    ) async {
      await _pump(tester, compliments: const []);

      expect(tester.getSize(find.byType(ReactionCapsule)).height, 0);
    });

    testWidgets(
      'Given exactly $kVisibleReactions reactions, Then all of them show and no '
      'count appears',
      (tester) async {
        await _pump(
          tester,
          compliments: [
            _r('👏', from: 'a'),
            _r('🔥', from: 'b'),
          ],
        );

        expect(find.text('👏'), findsOneWidget);
        expect(find.text('🔥'), findsOneWidget);
        // `+1` is information; a bare `1` is not, so nothing is drawn when
        // there is no remainder.
        expect(find.textContaining('+'), findsNothing);
      },
    );

    testWidgets(
      'Given five reactions, Then two show and the rest become a count',
      (tester) async {
        await _pump(
          tester,
          compliments: [
            _r('🦄', from: 'me'),
            _r('👏', from: 'a'),
            _r('🔥', from: 'b'),
            _r('💯', from: 'c'),
            _r('🛸', from: 'd'),
          ],
        );

        // Yours, then the next most recent, then the count.
        expect(find.text('🦄'), findsOneWidget);
        expect(find.text('👏'), findsOneWidget);
        expect(find.text('+3'), findsOneWidget);
        expect(find.text('🔥'), findsNothing);
      },
    );

    testWidgets(
      'Given a reaction of yours that would fall past the cap, Then it is still '
      'visible',
      (tester) async {
        await _pump(
          tester,
          compliments: [
            _r('👏', from: 'a'),
            _r('🔥', from: 'b'),
            _r('🦄', from: 'me'),
          ],
        );

        // The one that must never be hidden. Nothing else on the page reports
        // that you have reacted — the button is gone by then.
        expect(find.text('🦄'), findsOneWidget);
        expect(find.text('+1'), findsOneWidget);
      },
    );

    testWidgets(
      'Given one of the reactions is yours, Then the capsule is tinted',
      (tester) async {
        await _pump(tester, compliments: [_r('🦄', from: 'me')]);
        final mine = _fill(tester);

        await _pump(tester, compliments: [_r('🦄', from: 'someone')]);
        final theirs = _fill(tester);

        expect(mine, isNot(theirs));
        expect(
          mine,
          AppColors.light.brand.withValues(alpha: 0.25),
          reason: "the picker's marked-cell treatment, reused deliberately",
        );
        expect(theirs, AppColors.light.pageBackground);
      },
    );

    testWidgets('Given nobody signed in, Then nothing is tinted as yours', (
      tester,
    ) async {
      await _pump(tester, compliments: [_r('🦄', from: 'me')], userId: null);

      expect(_fill(tester), AppColors.light.pageBackground);
    });

    testWidgets('Given a tap, Then it opens the sheet behind it', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        compliments: [_r('🦄', from: 'me')],
        onTap: () => taps++,
      );

      await tester.tap(find.byType(ReactionCapsule));

      expect(taps, 1);
    });

    testWidgets(
      'Given any reactions at all, Then the chevron states the affordance',
      (tester) async {
        await _pump(tester, compliments: [_r('🦄', from: 'me')]);

        // Not decoration: with the button hidden this capsule is the only route
        // to your own reaction, and on a book that is not finished it is the
        // only interactive thing in the hero.
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      },
    );
  });
}
