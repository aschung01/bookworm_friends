// Praise is one-per-person-per-book, so a tap on the palette is a decision, not
// an insert: it can add, swap, or withdraw. `book_compliments` gained
// `UNIQUE (book_id, from_user_id)` in migration 005, which means the old
// unguarded `insert` would have thrown on a second tap — the toggle is what
// keeps that from happening, and the highlight is what makes it legible.
//
// The write itself goes through the global `supabase` client, which this repo's
// tests cannot fake (only providers get overridden), so the decision is pulled
// out as a pure function and pinned here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/ui/widgets/praise_palette.dart';

import 'support/book_details_harness.dart' show compliment, meId, otherId;

void main() {
  group('praiseTapFor', () {
    test('Given no praise yet, When an emoji is tapped, Then it is added', () {
      expect(praiseTapFor(current: null, tapped: '🔥'), PraiseTap.add);
    });

    test(
      'Given praise already given, When the same emoji is tapped, Then it is '
      'withdrawn',
      () {
        expect(praiseTapFor(current: '🔥', tapped: '🔥'), PraiseTap.remove);
      },
    );

    test(
      'Given praise already given, When a different emoji is tapped, Then it '
      'replaces the old one rather than adding a second',
      () {
        expect(praiseTapFor(current: '🔥', tapped: '👏'), PraiseTap.replace);
      },
    );
  });

  group('praiseBy', () {
    test('Given praise from several people, Then only yours is returned', () {
      final all = [
        compliment('👏', from: otherId),
        compliment('🔥', id: 'c2', from: meId),
      ];

      expect(praiseBy(all, meId), '🔥');
      expect(praiseBy(all, 'nobody'), isNull);
    });

    test('Given a signed-out viewer, Then nothing is theirs', () {
      expect(praiseBy([compliment('🔥')], null), isNull);
    });
  });

  group('PraisePalette', () {
    Future<void> pumpPalette(
      WidgetTester tester, {
      String? selected,
      void Function(String emoji)? onPick,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              PraisePalette(selected: selected, onPick: onPick ?? (_) {}),
            ],
          ),
        ),
      ),
    );

    BoxDecoration decorationOf(WidgetTester tester, String emoji) =>
        tester
                .widget<Container>(find.byKey(ValueKey('praise-$emoji')))
                .decoration
            as BoxDecoration;

    testWidgets(
      'Given praise you already gave, When the palette opens, Then your emoji '
      'is marked and the rest are not',
      (tester) async {
        await pumpPalette(tester, selected: '🔥');

        final mine = decorationOf(tester, '🔥');
        final other = decorationOf(tester, '👏');

        expect(
          mine.border,
          isNotNull,
          reason: 'the emoji you hold has to be distinguishable',
        );
        expect(other.border, isNull);
        expect(mine.color, isNot(other.color));
      },
    );

    testWidgets(
      'Given no praise yet, When the palette opens, Then nothing is marked',
      (tester) async {
        await pumpPalette(tester);

        for (final emoji in praiseEmojis) {
          expect(decorationOf(tester, emoji).border, isNull);
        }
      },
    );

    testWidgets(
      'Given the emoji you already hold, When it is tapped, Then the tap is '
      'still reported so it can be withdrawn',
      (tester) async {
        final picks = <String>[];
        await pumpPalette(tester, selected: '🔥', onPick: picks.add);

        await tester.tap(find.byKey(const ValueKey('praise-🔥')));

        expect(picks, ['🔥']);
      },
    );
  });
}
