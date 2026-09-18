// Tests for the progress sheet — the only writer of `books.progress` and
// `books.progress_page`.
//
// Four properties matter here and none is visible in a type signature.
//
// **Percent is always the default**, on every book, including one whose page count is
// known. Page mode is one tap away and never presumed, so a reader who already knows
// this sheet opens it to exactly what they saw before.
//
// **The percent wheel writes whole percents.** A stored 46.3% has no stop, so the
// initial value is snapped before the wheel sees it — otherwise a row holding 0.463
// would be *shown* as 46% and *saved* as 0.463.
//
// **Untouched means unwritten.** Opening the sheet on a book stored at 200/432 and
// simply agreeing with what it shows must not write 0.46, which would walk the
// bookmark back to p.199. Comparing values cannot detect that — the value the wheel
// can represent genuinely differs from the one stored — so the sheet tracks whether
// anything was touched.
//
// **The rider is derived, never recomputed.** It reads `bookProgressPage`, and it is
// absent rather than substituted when the book has no page count — which is about
// two reading books in three, so the absent case is the ordinary one.
//
// The Android platform override is what the sibling sheet's tests use: the iOS 26
// native controls have no Flutter-side hit target.

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/glass_segmented_control.dart';

Future<void> _openWheel(
  WidgetTester tester, {
  required double? initialProgress,
  int? initialPage,
  int? pageCount,
  List<ProgressAnswer>? picked,
  double keyboard = 0,
}) async {
  // **An iPhone-sized surface, not the 800×600 default.**
  //
  // `CNBottomSheet` caps its height at 9/16 of the screen, which on the default test
  // view is 337.5pt — less than the 368pt this sheet wants once the mode segment is
  // there, so the `Expanded` wheel silently shrank to 189.5 and two size assertions
  // disagreed for a reason that has nothing to do with the sheet. 844 gives the real
  // 474.75pt ceiling, which every state of this sheet fits under: 320 bare, 368 with
  // the segment, 434 with the keypad.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  // A keyboard, when one is asked for. The real number pad's height is the
  // platform's to choose and it is much larger than the 216pt the drawings assumed.
  if (keyboard > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  }
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSelectPercentBottomSheet(
                context,
                initialProgress: initialProgress,
                initialPage: initialPage,
                pageCount: pageCount,
                onProgressSelected: (p) => picked?.add(p),
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
}

/// Dismisses the sheet. Needed between two opens in one test: `pumpWidget` keeps
/// the navigator's state, so the first sheet is still up and covers the button.
Future<void> _closeWheel(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(CupertinoPicker))).pop();
  await tester.pumpAndSettle();
}

/// Turns the wheel one stop down, which is also the cheapest way to make the sheet
/// consider itself touched.
Future<void> _nudge(WidgetTester tester, {double by = 34}) async {
  await tester.drag(find.byType(CupertinoPicker), Offset(0, by));
  await tester.pumpAndSettle();
}

/// The mode segment.
///
/// **[GlassSegmentedControl], the same control the reading-status sheet uses** —
/// native `CNSegmentedControl` on iOS 26+, the app's pill chips elsewhere. Tests drive
/// the chips, because `useNativeGlass` is false under `flutter test` (which reports
/// Android) and a native segmented control is a platform view with no Flutter hit
/// target.
final Finder _segment = find.byType(GlassSegmentedControl);

/// Switches to Page mode.
///
/// Scoped to the segment because `progressModePage` and `progressPageColumn` are both
/// "Page" in English — the mode button and the wheel's static column label — so a
/// bare `find.text('Page')` matches two widgets once the switch has happened.
Future<void> _tapPageMode(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _segment, matching: find.text('Page')).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPercentMode(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _segment, matching: find.text('Percent')).first,
  );
  await tester.pumpAndSettle();
}

/// Opens the field by tapping the wheel's centred number, which is the only door to
/// it.
Future<void> _tapCentre(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(CupertinoPicker)));
  await tester.pumpAndSettle();
}

/// The value under the wheel's hairlines.
///
/// **Not `find.text`**, which cannot tell a selection from its neighbours — moving one
/// stop from 50 to 49 leaves `50` on screen as a sibling, which quietly made a
/// drag-does-nothing assertion pass. The selected row is the only one drawn in
/// `figure`, so its size is the discriminator.
String _selectedValue(WidgetTester tester) {
  final rows = tester.widgetList<Text>(
    find.descendant(
      of: find.byType(CupertinoPicker),
      matching: find.byType(Text),
    ),
  );
  return rows
      .firstWhere((t) => t.style?.fontSize == AppTextStyles.figure.fontSize)
      .data!;
}

/// What the page field currently holds, read off its controller.
///
/// **Not `find.text`**, because an empty field renders no `Text` at all and a
/// clamped one has to be distinguished from the identical numeral in the clamp
/// line beside it.
String _fieldText(WidgetTester tester) => tester
    .widget<CupertinoTextField>(find.byType(CupertinoTextField))
    .controller!
    .text;

/// Replaces the field's contents, the way select-all-then-type does.
///
/// `enterText` sets the whole editing value rather than delivering keystrokes, which
/// is exactly the seeded-and-selected case, and it still runs `inputFormatters` — so
/// the clamp and the leading-zero rule are genuinely exercised.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(CupertinoTextField), text);
  await tester.pumpAndSettle();
}

/// Dismisses the number pad by tapping the sheet around the field, which is the
/// affordance the pad's missing Done key forces.
Future<void> _dismissPad(WidgetTester tester) async {
  final field = tester.getRect(find.byType(CupertinoTextField));
  await tester.tapAt(Offset(field.center.dx, field.bottom + 24));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Given 100%, When pushed further, Then there is no 101%', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      expect(kProgressWheelStops, 101);

      // Asserted through the wheel's behaviour rather than its child count,
      // because that is what a reader can reach: the ends are hard stops.
      await _openWheel(tester, initialProgress: 1);
      expect(find.text('100'), findsOneWidget);

      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.text('100'), findsOneWidget);
      expect(find.text('101'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Given 0%, When pushed further, Then it stays at 0%', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _openWheel(tester, initialProgress: 0);
      expect(find.text('0'), findsOneWidget);

      await tester.drag(find.byType(CupertinoPicker), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('opens on the book\'s stored stop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _openWheel(tester, initialProgress: 0.46);
      expect(find.text('46'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Given no stored position, When opened, Then it starts at 0% rather than refusing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // Null means "never asked", and the wheel's whole job is to take a first
        // answer — so it opens rather than showing an empty state.
        await _openWheel(tester, initialProgress: null);
        expect(find.text('0'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Given a value between stops, When opened, Then it shows the stop it will write',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // The column's CHECK permits any fraction, and page mode writes ones that are
        // not whole percents — 200/432 = 0.4629... A stop-less value must not be
        // *displayed* as one thing and *written* as another, so it is snapped for the
        // wheel. What stops it being written back on a bare Confirm is the no-op
        // guard below, not the snap.
        final picked = <ProgressAnswer>[];
        await _openWheel(tester, initialProgress: 0.463, picked: picked);

        expect(find.text('46'), findsOneWidget);

        await _nudge(tester, by: -34);
        await _confirm(tester);

        expect(picked.single.progress, closeTo(0.47, 1e-9));
        expect(picked.single.page, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Confirm hands back a fraction, not a percent', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final picked = <ProgressAnswer>[];
      await _openWheel(tester, initialProgress: 0.99, picked: picked);

      await _nudge(tester, by: -34);
      await _confirm(tester);

      // 1.0, not 100 — the column stores a fraction and its CHECK would reject
      // the percent.
      expect(picked.single.progress, 1.0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('dismissing without confirming writes nothing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final picked = <ProgressAnswer>[];
      await _openWheel(tester, initialProgress: 0.46, picked: picked);

      await _closeWheel(tester);

      expect(picked, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('the no-op guard', () {
    testWidgets(
      'Given a page-mode position, When Confirm is tapped untouched, Then nothing is written',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The regression this exists for. 200/432 = 0.462963 has no stop; the wheel
          // opens on 46%, which is p.199. Agreeing with what is shown must not move
          // the bookmark back a page.
          final picked = <ProgressAnswer>[];
          await _openWheel(
            tester,
            initialProgress: 200 / 432,
            initialPage: 200,
            pageCount: 432,
            picked: picked,
          );

          await _confirm(tester);

          expect(picked, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('a touched wheel does write, so the guard is not a wall', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final picked = <ProgressAnswer>[];
        await _openWheel(tester, initialProgress: 0.46, picked: picked);

        await _nudge(tester);
        await _confirm(tester);

        expect(picked, hasLength(1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given the wheel is turned and put back, When confirmed, Then it still writes',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Touched, not changed. The guard is deliberately about the gesture and not
          // about the value: it cannot compare values, because the whole point is that
          // the stored value may be one the wheel cannot represent.
          final picked = <ProgressAnswer>[];
          await _openWheel(tester, initialProgress: 0.46, picked: picked);

          await _nudge(tester);
          await _nudge(tester, by: -34);
          await _confirm(tester);

          expect(picked.single.progress, closeTo(0.46, 1e-9));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('the derived page rider', () {
    testWidgets('reads the page for the selected stop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openWheel(tester, initialProgress: 0.46, pageCount: 320);
        // Approximate on purpose: a stop is 3.2 pages here, so p.148 cannot be
        // aimed at. The tilde is where that cost is admitted.
        expect(find.text('≈ p.147'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given no page count, When opened, Then the rider is absent with no substitute',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await _openWheel(tester, initialProgress: 0.46);
          expect(find.textContaining('p.'), findsNothing);
          expect(find.textContaining('≈'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the sheet is 320pt, When there is no rider, Then it is still 320pt',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The rider's box is held either way, so a book with no count does not
          // get a wheel of a different size.
          await _openWheel(tester, initialProgress: 0.46, pageCount: 320);
          final withRider = tester.getSize(find.byType(CupertinoPicker)).height;

          await _closeWheel(tester);
          await _openWheel(tester, initialProgress: 0.46);
          expect(
            tester.getSize(find.byType(CupertinoPicker)).height,
            withRider,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('follows the wheel as it turns', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openWheel(tester, initialProgress: 0.46, pageCount: 320);
        expect(find.text('≈ p.147'), findsOneWidget);

        // Down one stop. The rider is the only thing in the sheet that has to
        // react, which is the whole reason this sheet carries state and its date
        // sibling does not.
        await tester.drag(find.byType(CupertinoPicker), const Offset(0, 34));
        await tester.pumpAndSettle();

        expect(find.text('≈ p.147'), findsNothing);
        expect(find.text('≈ p.144'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('the mode segment', () {
    testWidgets(
      'Given no page count, When opened, Then there is no segment at all',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Absent rather than disabled: a greyed-out control advertises something
          // this book cannot do. For the ~65% of books with no count this sheet is
          // the one that shipped before.
          await _openWheel(tester, initialProgress: 0.46);

          expect(_segment, findsNothing);
          expect(find.text('Percent'), findsNothing);
          expect(find.text('Page'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a page count, When opened, Then the segment is there and Percent is on',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Decision 3, and the one most likely to be "improved" later: percent is the
          // default on *every* book, so a reader who already knows this sheet sees
          // exactly what they saw before and the new capability costs no relearning.
          await _openWheel(
            tester,
            initialProgress: 200 / 432,
            initialPage: 200,
            pageCount: 432,
          );

          expect(_segment, findsOneWidget);
          expect(find.text('46'), findsOneWidget);
          // Bare numeral beside a static unit, the same treatment the page wheel gets.
          expect(find.text('%'), findsOneWidget);
          // And the percent wheel is up, so the stored page is not on screen.
          expect(find.text('200'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('Given a stored page, When Page is tapped, Then it seeds there', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // Not the page the percent works out to — that would be p.199, and walking
        // the reader's own answer back by one is the whole defect this column fixes.
        await _openWheel(
          tester,
          initialProgress: 200 / 432,
          initialPage: 200,
          pageCount: 432,
        );

        await _tapPageMode(tester);

        expect(find.text('200'), findsOneWidget);
        expect(find.text('46%'), findsOneWidget); // now the rider, no tilde
        expect(find.textContaining('≈'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given only a percent, When Page is tapped, Then it seeds from the derived page',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // A reader crossing over for the first time lands where they already were,
          // rather than at p.1.
          await _openWheel(tester, initialProgress: 0.46, pageCount: 432);
          expect(find.text('≈ p.199'), findsOneWidget);

          await _tapPageMode(tester);

          expect(find.text('199'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given an unstarted book, When Page is tapped, Then it seeds at p.1 and never p.0',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // 0% derives p.0, which no book has. The floor is the wheel's first item,
          // and it is mirrored by `books_progress_page_positive` in the database.
          await _openWheel(tester, initialProgress: 0, pageCount: 432);
          await _tapPageMode(tester);

          expect(kProgressPageFloor, 1);
          expect(find.text('1'), findsOneWidget);
          expect(find.text('0'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('Given Page mode, When confirmed, Then the page rides along', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final picked = <ProgressAnswer>[];
        await _openWheel(
          tester,
          initialProgress: 200 / 432,
          initialPage: 200,
          pageCount: 432,
          picked: picked,
        );

        await _tapPageMode(tester);
        await _confirm(tester);

        // Both halves of one answer. The fraction is the position and the page is the
        // provenance that lets `ProgressFieldRow` print p.200 back.
        expect(picked.single.page, 200);
        expect(picked.single.progress, closeTo(200 / 432, 1e-9));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given a page was typed, When Percent is tapped, Then the answer stops claiming a page',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Provenance is news, not an absence of it: a reader who switches back to
          // percent is saying they no longer mean a page, and the row must stop
          // printing one.
          final picked = <ProgressAnswer>[];
          await _openWheel(
            tester,
            initialProgress: 200 / 432,
            initialPage: 200,
            pageCount: 432,
            picked: picked,
          );

          await _tapPageMode(tester);
          await _tapPercentMode(tester);
          await _confirm(tester);

          expect(picked.single.page, isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('the page field', () {
    testWidgets(
      'Given the page wheel, When the centre is tapped, Then the field replaces it',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The case that decides typing at all: a 912-page book is tens of flicks
          // from an arbitrary page, so scrolling cannot be the only path.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 912);
          await _tapPageMode(tester);
          expect(find.byType(CupertinoPicker), findsOneWidget);
          expect(find.byType(CupertinoTextField), findsNothing);

          await _tapCentre(tester);

          // The field replaces the wheel in the same sheet rather than stacking a
          // third one on top, and it opens on the page the centre was showing, so the
          // value being edited does not vanish at the moment of reaching for it.
          expect(find.byType(CupertinoPicker), findsNothing);
          expect(find.byType(CupertinoTextField), findsOneWidget);
          expect(_fieldText(tester), '456');
          expect(find.text('/ 912'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('raises the number pad and takes focus', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // The whole point of the reversal: this is the platform's keyboard, so a
        // hardware keyboard, dictation and VoiceOver all work without us drawing keys.
        await _openWheel(tester, initialProgress: 0.5, pageCount: 912);
        await _tapPageMode(tester);
        await _tapCentre(tester);

        final field = tester.widget<CupertinoTextField>(
          find.byType(CupertinoTextField),
        );
        expect(field.keyboardType, TextInputType.number);
        expect(field.focusNode!.hasFocus, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given the field opens, Then the digits are selected so the first keystroke replaces',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Tapping p.456 and typing 8 must mean p.8, not 4568 — which would clamp to
          // the last page and look broken. Select-on-focus is the platform's own
          // behaviour here rather than a flag the sheet maintains.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 912);
          await _tapPageMode(tester);
          await _tapCentre(tester);

          final selection = tester
              .widget<CupertinoTextField>(find.byType(CupertinoTextField))
              .controller!
              .selection;
          expect(selection.baseOffset, 0);
          expect(selection.extentOffset, 3);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('types a page the wheel could not reasonably be scrolled to', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final picked = <ProgressAnswer>[];
        await _openWheel(
          tester,
          initialProgress: 0.5,
          pageCount: 912,
          picked: picked,
        );
        await _tapPageMode(tester);
        await _tapCentre(tester);

        await _type(tester, '807');
        expect(_fieldText(tester), '807');

        await _confirm(tester);
        expect(picked.single.page, 807);
        expect(picked.single.progress, closeTo(807 / 912, 1e-9));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given a number past the end, When typed, Then it clamps and says so',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Clamped by the formatter as it is typed, so there is no invalid state to
          // report: no error styling, no red, and no inert Confirm — three pieces of
          // UI that then do not have to exist.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
          await _tapPageMode(tester);
          await _tapCentre(tester);

          await _type(tester, '999');

          expect(_fieldText(tester), '432');
          expect(find.text('This book ends at p.432'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a paste too long for an int, When applied, Then it clamps rather than throwing',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The number pad cannot produce this, but paste and dictation can, and
          // `int.parse` would throw on it.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
          await _tapPageMode(tester);
          await _tapCentre(tester);

          await _type(tester, '9' * 40);

          expect(_fieldText(tester), '432');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('strips anything that is not a digit', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // Same reason: the pad cannot type these, but paste and dictation can.
        await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
        await _tapPageMode(tester);
        await _tapCentre(tester);

        await _type(tester, 'p. 21x');

        expect(_fieldText(tester), '21');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Given a leading zero, When typed, Then it does not take', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // p.0 does not exist. 0% does — "opened it and got nowhere" is a real
        // position — so a reader who means the very start says so in Percent mode.
        await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
        await _tapPageMode(tester);
        await _tapCentre(tester);

        await _type(tester, '0');
        expect(_fieldText(tester), isEmpty);
        expect(kProgressPageFloor, 1);

        // And a zero in front of a real page is dropped rather than the whole entry.
        await _type(tester, '007');
        expect(_fieldText(tester), '7');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given the field is emptied, When confirmed, Then nothing is written',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // An empty field is not an answer, so Confirm must not fall back to whatever
          // was in it before. The field, the rider and what is written all agree on
          // "nothing".
          final picked = <ProgressAnswer>[];
          await _openWheel(
            tester,
            initialProgress: 0.5,
            pageCount: 432,
            picked: picked,
          );
          await _tapPageMode(tester);
          await _tapCentre(tester);

          await _type(tester, '');
          expect(_fieldText(tester), isEmpty);

          // The field keeps a width when empty, so the total beside it does not slide
          // left over a vanished caret.
          expect(
            tester.getSize(find.byType(CupertinoTextField)).width,
            greaterThanOrEqualTo(56.0),
          );

          await _confirm(tester);

          expect(picked, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the pad is dismissed, Then the wheel comes back where the typing left it',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The way back, and it is the platform's: the iOS number pad has no Done
          // key, so dismissing it is the gesture. Confirm stays in the header in every
          // state and remains the way *out*.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
          await _tapPageMode(tester);
          await _tapCentre(tester);
          await _type(tester, '31');

          await _dismissPad(tester);

          expect(find.byType(CupertinoTextField), findsNothing);
          expect(find.byType(CupertinoPicker), findsOneWidget);
          expect(find.text('/ 432'), findsNothing);
          // The wheel is where the typing left it, not back at the seed.
          expect(find.text('31'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the field was emptied, When the pad is dismissed, Then the wheel still has a page',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The wheel cannot display "no page", so returning to it adopts the seed
          // rather than rendering a null.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
          await _tapPageMode(tester);
          await _tapCentre(tester);
          await _type(tester, '');

          await _dismissPad(tester);

          expect(find.byType(CupertinoPicker), findsOneWidget);
          expect(find.text('216'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given typing, When Percent is tapped, Then the pad goes and the percent wheel is up',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Leaving page mode with the pad up would strand a number pad over a percent
          // wheel it cannot edit.
          await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
          await _tapPageMode(tester);
          await _tapCentre(tester);

          await _tapPercentMode(tester);

          expect(find.byType(CupertinoTextField), findsNothing);
          expect(find.text('50'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given no page count at all, When the centre is tapped, Then percent still types',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Typing is not a page-mode feature that percent borrows — it belongs to the
          // wheel, and the wheel every book gets is the percent one. A book with no
          // count has no segment and no page mode, and can still be typed into.
          await _openWheel(tester, initialProgress: 0.46);
          expect(_segment, findsNothing);

          await _tapCentre(tester);

          expect(find.byType(CupertinoTextField), findsOneWidget);
          expect(_fieldText(tester), '46');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // The bug this group exists for, found on device and not by any of the tests above.
  //
  // `CNBottomSheet` caps a sheet at 9/16 of the screen, and the keyboard inset is paid
  // out of that same budget rather than from the screen below it. The iOS number pad is
  // nowhere near the 216pt the drawings assumed — with its letter sub-captions and the
  // home indicator it is nearer 290 on a large iPhone — so 290 + a 222pt sheet is 512
  // against a 474.75 cap and the field's column overflowed by ~32pt. `isScrollControlled`
  // is what lifts the cap.
  //
  // None of the earlier cases caught it because they run with no keyboard at all, where
  // the sheet is 368 and the cap never binds.
  group('the sheet survives any keyboard the platform gives it', () {
    for (final pad in const [216.0, 290.0, 340.0]) {
      testWidgets('Given a ${pad.toInt()}pt pad, Then nothing overflows', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await _openWheel(
            tester,
            initialProgress: 0.55,
            initialPage: 238,
            pageCount: 432,
            keyboard: pad,
          );
          await _tapPageMode(tester);
          await _tapCentre(tester);

          // A RenderFlex overflow is reported as a test failure, so reaching here is
          // most of the assertion. The height pins down *why* it fits: the sheet is
          // its own 222 and the pad sits under it, rather than inside its budget.
          expect(tester.getSize(find.byType(AnimatedSize)).height, pad + 222);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets(
      'Given the pad is dismissed, Then the sheet drops the inset with it rather than ballooning',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Focus is lost the instant the pad starts leaving, so the body swaps back to
          // the 220pt wheel while the inset is still ~290. Reading the inset
          // unconditionally would make the sheet 658pt for a frame — a visible bounce.
          await _openWheel(
            tester,
            initialProgress: 0.55,
            initialPage: 238,
            pageCount: 432,
            keyboard: 290,
          );
          await _tapPageMode(tester);
          await _tapCentre(tester);
          expect(tester.getSize(find.byType(AnimatedSize)).height, 512);

          await _dismissPad(tester);

          // The wheel state's own height, with no trace of the inset still in it.
          expect(tester.getSize(find.byType(AnimatedSize)).height, 368);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // The centre row carries the tap-to-type target, which sits *over* the picker. If it
  // ends the hit test, the wheel cannot be dragged by the very row a thumb lands on.
  // That shipped in the page wheel and no test caught it, because none of them dragged
  // from the centre — `_nudge` happens to grab the picker's centre, which is the same
  // point, and only started failing once the percent wheel inherited the overlay too.
  group('the centre row scrolls as well as types', () {
    for (final mode in const ['Percent', 'Page']) {
      testWidgets('Given $mode, When dragged from the centre, Then it moves', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await _openWheel(
            tester,
            initialProgress: 0.5,
            initialPage: 216,
            pageCount: 432,
          );
          if (mode == 'Page') await _tapPageMode(tester);
          expect(_selectedValue(tester), mode == 'Percent' ? '50' : '216');

          // Exactly the centre, where the tap target is, and far enough to be a drag
          // rather than a tap.
          await tester.dragFrom(
            tester.getCenter(find.byType(CupertinoPicker)),
            const Offset(0, 34),
          );
          await tester.pumpAndSettle();

          // The neighbours are still on screen; it is the *selection* that moved.
          expect(_selectedValue(tester), mode == 'Percent' ? '49' : '215');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('and a stationary press on the centre still types', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // The other half of the arena: translucent means both recognisers get the
        // pointer, so this must not have turned tapping into a no-op.
        await _openWheel(tester, initialProgress: 0.5, pageCount: 432);
        await _tapPageMode(tester);
        await _tapCentre(tester);

        expect(find.byType(CupertinoTextField), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // Percent typing, which the wheel did not have until the two modes were unified. The
  // range differs from Page in exactly one place and it is the interesting one: 0 is a
  // legal percent and p.0 is not.
  group('the percent field', () {
    testWidgets('types a percent and hands back the fraction', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final picked = <ProgressAnswer>[];
        await _openWheel(tester, initialProgress: 0.46, picked: picked);
        await _tapCentre(tester);

        await _type(tester, '73');
        await _confirm(tester);

        expect(picked.single.progress, closeTo(0.73, 1e-9));
        // Percent answers never carry provenance, however they were entered.
        expect(picked.single.page, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Given a value over 100, When typed, Then it clamps to 100', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openWheel(tester, initialProgress: 0.46);
        await _tapCentre(tester);

        await _type(tester, '999');

        expect(_fieldText(tester), '100');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Given 0, When typed, Then it takes — unlike a page', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // The one asymmetry between the modes. "Opened it and got nowhere" is a real
        // position, so Percent is where a reader says it; p.0 is refused.
        final picked = <ProgressAnswer>[];
        await _openWheel(tester, initialProgress: 0.46, picked: picked);
        await _tapCentre(tester);

        await _type(tester, '0');
        expect(_fieldText(tester), '0');

        await _confirm(tester);
        expect(picked.single.progress, 0.0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given the pad is dismissed, Then the percent wheel returns to what was typed',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The percent wheel keeps a single controller for the whole sheet, so this is
          // the case that proves returning from the field repositions it rather than
          // absorbing its old offset.
          await _openWheel(tester, initialProgress: 0.46, pageCount: 432);
          await _tapCentre(tester);
          await _type(tester, '73');

          await _dismissPad(tester);

          expect(find.byType(CupertinoPicker), findsOneWidget);
          expect(_selectedValue(tester), '73');
          expect(find.text('≈ p.315'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('the unit stays a static label, not a suffix on the numeral', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // `100` is wider than `55`, so an inline `%` slides sideways as the wheel
        // turns. The page wheel solved that with a static column label and percent now
        // wears the same one, even though `%` is a suffix in both shipped locales.
        await _openWheel(tester, initialProgress: 1);

        expect(_selectedValue(tester), '100');
        expect(find.text('100%'), findsNothing);
        expect(find.text('%'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
