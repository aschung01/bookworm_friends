// Praise is one-per-person-per-book, so a tap on the picker is a decision, not
// an insert: it can add, swap, or withdraw. `book_compliments` carries
// `UNIQUE (book_id, from_user_id)`, so the old unguarded `insert` would throw on
// a second tap -- the toggle is what keeps that from happening, and the sheet's
// strip and marked cell are what make it legible.
//
// The write itself goes through the global `supabase` client, which this repo's
// tests cannot fake (only providers get overridden), so the decision is pulled
// out as a pure function and pinned here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:awesome_emoji_picker/awesome_emoji_picker.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';

import 'support/book_details_harness.dart' show compliment, meId, otherId;

/// The picker and the seeding both reach for `SharedPreferences`, which has no
/// platform implementation in a widget test.
void useFakePrefs() => SharedPreferences.setMockInitialValues({});

Future<void> pumpInApp(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

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

    test('Given a legacy emoji from outside the old palette, When it is tapped '
        'again, Then it still withdraws', () {
      // 28 of the 39 praises in production are emoji the fixed palette never
      // offered, so the toggle cannot assume its argument came from a list.
      expect(praiseTapFor(current: '🦄', tapped: '🦄'), PraiseTap.remove);
      expect(praiseTapFor(current: '🦄', tapped: '🐲'), PraiseTap.replace);
    });
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

  group('CurrentPraiseStrip', () {
    testWidgets(
      'Given praise you hold, Then it is shown with a way to withdraw it',
      (tester) async {
        var removed = 0;
        await pumpInApp(
          tester,
          CurrentPraiseStrip(emoji: '🦄', onRemove: () => removed++),
        );

        expect(find.text('Your praise'), findsOneWidget);
        // A legacy emoji the grid would bury: the strip shows it regardless.
        expect(find.text('🦄'), findsOneWidget);

        await tester.tap(find.text('Remove'));
        expect(removed, 1);
      },
    );

    testWidgets('Given no way to withdraw, Then no withdrawal is offered', (
      tester,
    ) async {
      // The profile-emoji picker reuses this sheet and has no "remove".
      await pumpInApp(tester, const CurrentPraiseStrip(emoji: '🔥'));

      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });
  });

  group('PraiseEmojiPicker', () {
    testWidgets(
      'Given praise you hold, When the picker opens, Then your cell is marked '
      'and others are not',
      (tester) async {
        useFakePrefs();
        // Seeding puts the old palette in Recents, so 🔥 is on screen without
        // scrolling three thousand emoji.
        await seedRecentEmojis();
        await pumpInApp(
          tester,
          SizedBox(
            height: 400,
            child: PraiseEmojiPicker(selected: '🔥', onEmojiSelected: (_) {}),
          ),
        );
        await tester.pumpAndSettle();

        final mine = tester.widget<Container>(
          find.byKey(const ValueKey('praise-cell-🔥')).first,
        );
        final other = tester.widget<Container>(
          find.byKey(const ValueKey('praise-cell-👏')).first,
        );

        expect(
          mine.decoration,
          isNotNull,
          reason: 'the emoji you hold has to be distinguishable',
        );
        expect(other.decoration, isNull);
      },
    );

    testWidgets(
      'Given the emoji you already hold, When it is tapped, Then the tap is '
      'still reported so it can be withdrawn',
      (tester) async {
        useFakePrefs();
        await seedRecentEmojis();
        final picks = <String>[];
        await pumpInApp(
          tester,
          SizedBox(
            height: 400,
            child: PraiseEmojiPicker(
              selected: '🔥',
              onEmojiSelected: picks.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('praise-cell-🔥')).first);
        expect(picks, ['🔥']);
      },
    );
  });

  group('seedRecentEmojis', () {
    testWidgets('Given an empty store, Then the old palette seeds it', (
      tester,
    ) async {
      useFakePrefs();
      EmojiRepository.reset();

      await seedRecentEmojis();

      final recents = EmojiRepository().getRecents().map((e) => e.char);
      expect(recents, containsAll(seedEmojis));
    });

    testWidgets('Given praise you have used, Then the seed leaves it alone', (
      tester,
    ) async {
      // A real history must survive: seeding over it would wipe what the picker
      // exists to remember.
      useFakePrefs();
      EmojiRepository.reset();
      await EmojiRepository().setRecentEmojis([EmojiModel.fromString('🦄')]);

      await seedRecentEmojis();

      expect(EmojiRepository().getRecents().map((e) => e.char), ['🦄']);
    });
  });
}
