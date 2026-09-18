// Guards for the type scale.
//
// The defect this file exists to prevent is not "a wrong font size". It is the
// original one: `AppTheme` setting no `textTheme`, so every `Text` in the app
// silently inherited Material 3's Roboto metrics — `letterSpacing: 0.25`,
// `height: 1.43`, `black87` in light and pure white in dark — and eighty-eight
// call sites each merged their own size onto that without anyone choosing it.
// So the assertions here are mostly about the *inherited* style being right, and
// about the scale staying a scale rather than drifting back into thirteen sizes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';

void main() {
  group('the scale', () {
    test(
      'Given the tokens, Then each is the size and weight the scale says',
      () {
        const expected = <String, (double, FontWeight)>{
          'display': (46, FontWeight.w800),
          'figure': (30, FontWeight.w700),
          'hero': (30, FontWeight.w700),
          'title': (22, FontWeight.w700),
          'titleVisit': (20, FontWeight.w700),
          'titleUser': (22, FontWeight.w600),
          'subtitle': (17, FontWeight.w600),
          'body': (15, FontWeight.w400),
          'label': (13, FontWeight.w600),
          'spine': (12, FontWeight.w700),
          'caption': (11, FontWeight.w700),
        };
        for (final entry in expected.entries) {
          final style = AppTextStyles.all[entry.key]!;
          expect(style.fontSize, entry.value.$1, reason: '${entry.key} size');
          expect(
            style.fontWeight,
            entry.value.$2,
            reason: '${entry.key} weight',
          );
        }
      },
    );

    test('Given the tokens, Then they use four weights and no more', () {
      // Before the scale there were six spellings across the app, of which
      // `bold` and `w700` are the same weight written two ways, and `bold` alone
      // appeared 44 times — which is the same as nothing being emphasised.
      final weights = AppTextStyles.all.values.map((s) => s.fontWeight).toSet();
      expect(weights, {
        FontWeight.w400,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
      });
    });

    test('Given the tokens, Then none of them carries Roboto tracking', () {
      // `0.25` is the exact value that leaked in from `englishLike2021`, and the
      // reason "My Library" read loose at 18pt bold. Nothing may reintroduce it.
      for (final entry in AppTextStyles.all.entries) {
        expect(
          entry.value.letterSpacing,
          isNot(0.25),
          reason: '${entry.key} must not carry the inherited Roboto tracking',
        );
        expect(
          entry.value.letterSpacing,
          isNotNull,
          reason:
              '${entry.key} must state its tracking rather than inherit one',
        );
      }
    });

    test('Given the tokens, Then every one pins family, height and baseline', () {
      for (final entry in AppTextStyles.all.entries) {
        final s = entry.value;
        expect(s.fontFamily, isNotNull, reason: '${entry.key} family');
        expect(s.height, isNotNull, reason: '${entry.key} height');
        // Pinned because `material_ko.arb` declares `scriptCategory: dense`, so
        // an unpinned baseline becomes `ideographic` under `ko` and rows mixing
        // Latin with Hangul align differently per locale.
        expect(
          s.textBaseline,
          TextBaseline.alphabetic,
          reason: '${entry.key} baseline',
        );
      }
    });

    test('Given the tokens, Then none of them bakes in a colour', () {
      // A const colour here would be a light-mode value that dark mode could
      // never override, which is the same class of bug as the theme inheriting
      // `black87`. Colour comes from the theme.
      for (final entry in AppTextStyles.all.entries) {
        expect(
          entry.value.color,
          isNull,
          reason: '${entry.key} must not set a colour',
        );
      }
    });

    test('Given the numeric tokens, Then they ask for tabular figures', () {
      // Pretendard's default figures are proportional: `1111` and `8888` differ
      // by 27px at 40px. That was the sheet count nudging its own title as books
      // were added, and `ReadMonthGrid`'s counts failing to line up.
      for (final name in ['display', 'figure', 'label']) {
        expect(
          AppTextStyles.all[name]!.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: '$name renders numbers and must fix their width',
        );
      }
    });
  });

  group('the serif', () {
    test('Given title, Then it is the serif and falls back to the sans', () {
      // The fallback is what makes a 185KB subset safe instead of fragile: a
      // Hangul syllable the serif does not carry renders in Pretendard rather
      // than as a box. Removing it turns a missing glyph into a shipped defect.
      expect(AppTextStyles.title.fontFamily, AppFonts.serif);
      expect(AppTextStyles.title.fontFamilyFallback, contains(AppFonts.sans));
    });

    test('Given titleUser, Then it is the sans at title metrics', () {
      // A username standing alone is the reader's content, not the app's voice, so
      // `ManageFriendPage` sets it in the UI face at the page-title size.
      const a = AppTextStyles.title;
      const b = AppTextStyles.titleUser;
      expect(b.fontFamily, AppFonts.sans);
      expect(b.fontSize, a.fontSize);
      expect(b.height, a.height);
      expect(b.letterSpacing, a.letterSpacing);
    });

    test('Given titleVisit, Then it is title one step down in the same face', () {
      // The library bar's two states, and the only differences between them that
      // are allowed to exist. Asserting the *relationship* rather than the number:
      // a visit title must stay smaller than your own — your library is the
      // permanent subject, a visit is temporary — while staying clear of
      // `subtitle`, which is the sheet title stacked over this same row.
      const own = AppTextStyles.title;
      const visit = AppTextStyles.titleVisit;
      expect(visit.fontFamily, own.fontFamily);
      expect(visit.fontFamilyFallback, contains(AppFonts.sans));
      expect(visit.fontWeight, own.fontWeight);
      expect(visit.height, own.height);
      expect(visit.fontSize, lessThan(own.fontSize!));
      expect(
        visit.fontSize,
        greaterThan(AppTextStyles.subtitle.fontSize! + 1),
        reason:
            'a page title one point off the sheet title above it is the exact '
            'collision the 22 in `title` was chosen to avoid. Going lower to '
            'stop a long Latin name truncating is the trade this floor refuses '
            '— see the ladder in library_bar_title_render_preview.dart',
      );
      // Tracking scales with the size rather than being carried over flat, so the
      // two read as one decision at two sizes.
      expect(
        visit.letterSpacing! / visit.fontSize!,
        closeTo(own.letterSpacing! / own.fontSize!, 0.001),
      );
    });

    test('Given the two titles, Then their weights differ on purpose', () {
      // Everything else about these two is identical, so an equality check on the
      // whole style is the obvious guard and would be the wrong one. Gowun Batang
      // ships a single cut at 700 and it is barely bold — 21.3% ink coverage where
      // Pretendard w700 draws 31.7% — so w700 serif and w600 sans are the same apparent
      // weight. Asserting the difference is what stops someone from tidying it
      // away.
      expect(AppTextStyles.title.fontWeight, FontWeight.w700);
      expect(AppTextStyles.titleUser.fontWeight, FontWeight.w600);
    });

    test('Given the Card hero figure, Then it is the sans at w800', () {
      // The decision, recorded: Gowun Batang tops out at w700 and even there draws
      // only 21.3% ink coverage, where Pretendard w700 draws 31.7%. `StatTile` says
      // this figure should be "the thing you see first", so it is Pretendard
      // w800 and the title beside it carries the serif instead.
      expect(AppTextStyles.display.fontFamily, AppFonts.sans);
      expect(AppTextStyles.display.fontWeight, FontWeight.w800);
    });

    test('Given the serif, Then only the four title-and-book tokens use it', () {
      // Four tokens, and what the list guards is the **coverage judgement**. The
      // face is cut to KS X 1001's 2,350 syllables, not the whole 11,172 block, so
      // every token here is a place a call site can hand it text outside that set.
      // For `hero` that cannot happen — it sets strings this repo authors. `spine`
      // and `titleVisit` can: a book title is catalogue text and the library bar's
      // visit title carries a username, and both are here because KS X 1001 was
      // verified against three corpora with 0 misses (see `AppFonts.serif`).
      //
      // A fifth token is not free. Check two things when one appears: whether its
      // text can leave KS X 1001, and whether it can live with 21.3% ink — this
      // face has no cut above 700 and 700 is barely bold.
      final serifTokens = AppTextStyles.all.entries
          .where((e) => e.value.fontFamily == AppFonts.serif)
          .map((e) => e.key)
          .toSet();
      expect(serifTokens, {'title', 'titleVisit', 'hero', 'spine'});
    });

    test('Given every serif token, Then it names the sans as its fallback', () {
      // The fallback is what makes a 2,350-syllable cut safe instead of fragile: a
      // syllable outside KS X 1001 renders in Pretendard rather than as a box.
      // `hero` is the token most likely to be handed a string nobody checked, and
      // `spine` is handed catalogue text by definition — an imported title can also
      // contain hanja, which this face does not have at all.
      for (final entry in AppTextStyles.all.entries) {
        if (entry.value.fontFamily != AppFonts.serif) continue;
        expect(
          entry.value.fontFamilyFallback,
          contains(AppFonts.sans),
          reason:
              '${entry.key} sets the subset serif and must fall back to the '
              'sans, or an uncovered syllable renders as a box',
        );
      }
    });

    test('Given every token, Then the cut it asks for is one that ships', () {
      // **The guard against faux-bolding, which is the failure mode this whole
      // pairing was chosen to avoid.** A token naming a weight with no asset
      // behind it does not fail, warn, or look obviously wrong — the engine
      // reaches for the nearest cut, or synthesises one by smearing the outline,
      // and the result is a title that is subtly muddier on one platform than
      // another. Nothing else in the suite would catch it, because the
      // `TextStyle` is perfectly valid.
      //
      // Reading `pubspec.yaml` rather than restating its contents, so the two
      // cannot drift: dropping a weight from the manifest to save a megabyte now
      // fails here instead of shipping.
      final manifest = File('pubspec.yaml').readAsLinesSync();
      final shipped = <String, Set<int>>{};
      String? family;
      for (final line in manifest) {
        final fam = RegExp(r'^\s*- family:\s*(\S+)').firstMatch(line);
        if (fam != null) {
          family = fam.group(1);
          shipped[family!] = <int>{};
          continue;
        }
        final weight = RegExp(r'^\s*weight:\s*(\d+)').firstMatch(line);
        if (weight != null && family != null) {
          shipped[family]!.add(int.parse(weight.group(1)!));
        }
      }

      // Sanity-check the parse itself, so a manifest reshuffle that silently
      // matched nothing cannot turn this into a test that always passes.
      expect(
        shipped.keys,
        containsAll(<String>[AppFonts.sans, AppFonts.serif]),
        reason: 'the pubspec parse found no such family',
      );

      for (final entry in AppTextStyles.all.entries) {
        final style = entry.value;
        expect(
          shipped[style.fontFamily!],
          contains(style.fontWeight!.value),
          reason:
              '${entry.key} asks ${style.fontFamily} for '
              'w${style.fontWeight!.value}, which pubspec.yaml does not '
              'register. Either ship that cut or move the token to one that '
              'exists — do not let the engine invent it.',
        );
      }
    });
  });

  group('what a bare Text inherits', () {
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      test(
        'Given $name, Then bodyMedium is the body token in the theme colour',
        () {
          // `Material` seeds `DefaultTextStyle` from `bodyMedium`, so this is the
          // style every unstyled `Text` in the app actually gets.
          final s = theme.textTheme.bodyMedium!;
          expect(s.fontFamily, AppFonts.sans);
          expect(s.fontSize, AppTextStyles.body.fontSize);
          expect(s.fontWeight, AppTextStyles.body.fontWeight);
          expect(s.height, AppTextStyles.body.height);
          expect(s.letterSpacing, 0);
          expect(
            s.color,
            (name == 'light' ? AppColors.light : AppColors.dark).primaryText,
            reason:
                'was black87 in light and pure white in dark before the theme '
                'set a textTheme at all',
          );
        },
      );

      test('Given $name, Then no role inherits Roboto metrics', () {
        final roles = <TextStyle?>[
          theme.textTheme.displayLarge,
          theme.textTheme.headlineLarge,
          theme.textTheme.titleLarge,
          theme.textTheme.titleMedium,
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.labelLarge,
          theme.textTheme.labelSmall,
        ];
        for (final s in roles) {
          expect(s, isNotNull);
          expect(s!.letterSpacing, isNot(0.25));
          expect(s.height, isNot(1.43));
          expect(s.fontFamily, anyOf(AppFonts.sans, AppFonts.serif));
        }
      });

      test('Given $name, Then titleLarge is the sans so the serif is opt-in', () {
        // `AppBar` reads `titleLarge` and can be handed any string; only a call
        // site knows whether its title is the app's own words.
        expect(theme.textTheme.titleLarge!.fontFamily, AppFonts.sans);
      });
    }
  });

  group('the migration', () {
    // The eighty-eight call sites are the reason this group exists. Tokenising
    // them once is worthless if the next `Text` written in this app spells out
    // `fontSize: 14` again — the scale would be back to thirteen sizes within a
    // few features, and nothing would fail to tell anyone.
    //
    // A source scan rather than a widget test, because the defect is textual:
    // there is no rendered output that distinguishes an inherited 15 from a
    // hardcoded one.

    /// Files allowed to state a size or weight directly, each because its numbers
    /// are **geometry rather than type** — a dimension derived from a box, not a
    /// step on the scale.
    const allowed = <String>{
      // The scale itself.
      'lib/constants/app_text_styles.dart',
      // Every size is `N * _u` on a fixed 360x450 export grid, so the artifact
      // renders identically at any device pixel ratio. A token would tie the
      // exported PNG to the phone that exported it.
      'lib/ui/widgets/library_card/shareable_library_card.dart',
      'lib/ui/widgets/library_card/card_cover_row.dart',
      // `titleSize` is computed from the cover's width, because a generated cover
      // is drawn at whatever size the shelf gives it.
      'lib/ui/widgets/book/generated_cover.dart',
      // An emoji glyph sized from the circle it sits in. See `kEmojiGlyphSize`
      // for the fixed-size case.
      'lib/ui/widgets/avatar_circle.dart',
    };

    test('Given lib/ui, Then no call site states its own size or weight', () {
      final offenders = <String>[];
      final dirs = [Directory('lib/ui'), Directory('lib/constants')];
      for (final dir in dirs) {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final path = entity.path;
          if (allowed.contains(path)) continue;
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            // `kEmojiGlyphSize` is the sanctioned spelling for a glyph drawn as a
            // graphic, so a line naming it is not a hardcoded size.
            if (line.contains('kEmojiGlyphSize')) continue;
            if (RegExp(r'^\s*(fontSize|fontWeight):').hasMatch(line)) {
              offenders.add('$path:${i + 1}: ${line.trim()}');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Use an AppTextStyles token. `.copyWith()` may set colour or '
            'decoration, never size or weight — a call site that needs a size '
            'the scale does not have is telling you the scale is wrong, not '
            'that it needs an exception.\n${offenders.join('\n')}',
      );
    });
  });
}
