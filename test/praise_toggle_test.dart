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
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart'
    show kSearchPillRadius;

import 'support/book_details_harness.dart' show compliment, meId, otherId;

/// Named so the search-field test can pass a `const` picker.
void _ignore(String _) {}

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

  group('emojiGridHeight', () {
    // 800pt of screen -> 440 of grid before any keyboard.
    test(
      'Given no keyboard, When the grid is sized, Then it takes its share of the '
      'screen',
      () {
        expect(
          emojiGridHeight(screenHeight: 800, keyboardInset: 0),
          closeTo(440, 0.01),
        );
      },
    );

    test('Given the keyboard is up, When the grid is sized, Then it shrinks by the '
        'inset rather than being covered by it', () {
      // The bug this replaces: the grid kept its full height and the keyboard
      // drew over it, leaving about two visible rows.
      //
      // 120 deliberately, not a full-height keyboard: the inset has to be small
      // enough that the result lands between the floor and the ceiling, or this
      // would be testing the clamp and only looking like it tested the shrink.
      const unobstructed = 800 * 0.55; // 440
      expect(
        emojiGridHeight(screenHeight: 800, keyboardInset: 120),
        closeTo(unobstructed - 120, 0.01),
      );
      expect(
        emojiGridHeight(screenHeight: 800, keyboardInset: 120),
        lessThan(emojiGridHeight(screenHeight: 800, keyboardInset: 0)),
      );
    });

    test(
      'Given a keyboard tall enough to squeeze the grid flat, When it is sized, '
      'Then it stops at the floor',
      () {
        // Small phone, tall keyboard: 352 of share less 340 of keyboard is 12,
        // which is not a grid. Better to overflow into the sheet's own scroll
        // than to collapse to a sliver.
        expect(emojiGridHeight(screenHeight: 640, keyboardInset: 340), 240);
      },
    );

    test(
      'Given a very tall screen, When the grid is sized, Then it stops at the '
      'ceiling',
      () {
        expect(emojiGridHeight(screenHeight: 1200, keyboardInset: 0), 460);
      },
    );
  });

  group('the search field', () {
    testWidgets(
      'Given the picker is open, When the search field is themed, Then it is a '
      'borderless filled pill in every state',
      (tester) async {
        useFakePrefs();
        await pumpInApp(
          tester,
          const SizedBox(
            height: 400,
            child: PraiseEmojiPicker(onEmojiSelected: _ignore),
          ),
        );
        await tester.pumpAndSettle();

        // The package's field sets no border, no fill and no hint style, so what
        // it renders is whatever the ambient theme says. Before this it was
        // Material's default underline -- which turned brand-green on focus, the
        // one search field in the app that did not match the other two.
        final decoration = Theme.of(
          tester.element(find.byType(TextField)),
        ).inputDecorationTheme;

        final colors = AppTheme.light.extension<AppColors>()!;
        expect(decoration.filled, isTrue);
        expect(decoration.fillColor, colors.surfaceVariant);

        for (final border in [
          decoration.border,
          decoration.enabledBorder,
          // The focused one is the whole point: it is where the green underline
          // came from.
          decoration.focusedBorder,
        ]) {
          expect(border, isA<OutlineInputBorder>());
          expect((border as OutlineInputBorder).borderSide, BorderSide.none);
          expect(
            border.borderRadius,
            BorderRadius.circular(kSearchPillRadius),
            reason: 'has to be the same shape as SearchFieldPill',
          );
        }
      },
    );
  });

  group('PraiseEmojiPicker', () {
    testWidgets(
      'Given praise you hold, When the picker opens, Then your cell is marked '
      'and others are not',
      (tester) async {
        // This is now the *whole* of the toggle's legibility. A strip above the
        // grid used to repeat your praise with an explicit "Remove" button; it
        // was deleted as duplication, so the marked cell carries the meaning
        // alone and this test is the guard on it.
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
