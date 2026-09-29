// Tests for the total-pages sheet — the only reader-facing editor of `books.page_count`.
//
// Five properties matter here and none of them is visible in a screenshot.
//
// **It opens on the keypad.** A total is read off the back of the book and typed, not
// scrolled to, so there is no wheel in front of the typing and no Percent/Page segment
// above it: a total has exactly one unit.
//
// **Untouched means unreported.** Opening the sheet on a 462-page book and agreeing with
// what it shows must hand nothing back. The progress wheel had the equivalent bug — merely
// opening it and confirming walked the bookmark back a page — and the consequence is worse
// on this column, because every derived page in the app is computed from it.
//
// **The bounds hold at both ends.** A book with no pages is not a book, and a five-digit
// slip must not become a permanent fact, so the field clamps as it is typed rather than
// raising an error there is no state for.
//
// **It says nothing about position, and cannot.** The fraction is the position and the
// page is derived from it, so correcting a total re-derives the page and leaves the
// position alone. This sheet's part of that contract is structural: there is no parameter,
// field or callback here a fraction could travel in, which is what the last group pins.
//
// **It fits the shortest phone the app supports.** `flutter_test`'s default 800×600
// surface is shorter than any of them, so every case sets a real size.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show kMaxTotalPages, kMinTotalPages;
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_total_pages_bottom_sheet.dart';

/// Opens the sheet on an iPhone SE, which is **the shortest phone this app supports and
/// shorter than the 800×600 default**.
///
/// Every case runs at this size rather than only the fit case: the sheet is 138pt plus
/// whatever the keyboard takes, so if it ever stops fitting here the failure should land
/// on whichever assertion is nearest the change rather than only on the one case that
/// measures.
Future<void> _openSheet(
  WidgetTester tester, {
  required int? initialTotalPages,

  /// Collected as `Object?` on purpose — see the last group. A typed list would hide the
  /// thing being asserted, which is that nothing but an `int` can come out.
  List<Object?>? reported,
  Size surface = const Size(375, 667),
  double keyboard = 0,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  // The real number pad's height is the platform's to choose and is much larger than the
  // 216pt the drawings assumed — nearer 290 on a large iPhone, with its letter
  // sub-captions and the home indicator.
  if (keyboard > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  }
  addTearDown(tester.view.reset);

  // **Typed `int` on purpose, and it is a compile-time assertion.** This is what the
  // sheet's `onTotalPagesSelected` is handed, so the file stops compiling if that
  // callback ever starts carrying a fraction or a record — which is the guarantee the
  // last group tests from the other side.
  void sink(int value) => reported?.add(value);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSelectTotalPagesBottomSheet(
                context,
                initialTotalPages: initialTotalPages,
                onTotalPagesSelected: sink,
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

/// What the field currently holds, read off its controller.
///
/// **Not `find.text`**, because an empty field renders no `Text` at all and a clamped one
/// has to be told apart from the identical numeral in the clamp line under it.
String _fieldText(WidgetTester tester) => tester
    .widget<CupertinoTextField>(find.byType(CupertinoTextField))
    .controller!
    .text;

/// Replaces the field's contents, the way select-all-then-type does.
///
/// `enterText` sets the whole editing value rather than delivering keystrokes, which is
/// exactly the seeded-and-selected case, and it still runs `inputFormatters` — so the
/// clamp and the leading-zero rule are genuinely exercised.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(CupertinoTextField), text);
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  group('the sheet opens on the keypad', () {
    testWidgets('Given a stored count, Then the field holds it, focused', (
      tester,
    ) async {
      await _openSheet(tester, initialTotalPages: 462);

      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(_fieldText(tester), '462');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.keyboardType, TextInputType.number);
      expect(find.text('Total pages'), findsOneWidget);
    });

    testWidgets(
      'Given the field opens, Then the digits are selected so the first keystroke replaces',
      (tester) async {
        // Opening a 462-page book and typing 5 must mean 5, not 4625 — which would clamp
        // and look broken.
        await _openSheet(tester, initialTotalPages: 462);

        final selection = tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .controller!
            .selection;
        expect(selection.baseOffset, 0);
        expect(selection.extentOffset, 3);
      },
    );

    testWidgets(
      'Given no stored count, Then the field is empty rather than inventing a total',
      (tester) async {
        // The common case: about two books in three have no count at all. A seeded guess
        // would be a plausible-looking number the reader never said, drawn under a
        // "Total pages" title — which is also the reason there is no wheel behind the
        // keypad for it to fall back to.
        await _openSheet(tester, initialTotalPages: null);

        expect(_fieldText(tester), isEmpty);
        // Still has a caret to aim at rather than collapsing to a point.
        expect(
          tester.getSize(find.byType(CupertinoTextField)).width,
          greaterThanOrEqualTo(56.0),
        );
      },
    );

    testWidgets('and there is no wheel and no unit segment', (tester) async {
      // A total has one unit, so the segment the progress wheel carries would be a
      // control with one choice; and a wheel over 1–20000 is the "tens of flicks"
      // problem the keypad exists to solve.
      await _openSheet(tester, initialTotalPages: 462);

      expect(find.byType(CupertinoPicker), findsNothing);
      expect(find.text('Percent'), findsNothing);
      expect(find.text('Page'), findsNothing);
    });

    testWidgets('and the pad can be dismissed without losing what was typed', (
      tester,
    ) async {
      // The way back to a readable sheet, since the iOS number pad has no Done key. With
      // no wheel behind the keypad there is nothing for the field to be swapped *for*, so
      // what dismissing has to preserve is the field itself and the number in it.
      final reported = <Object?>[];
      await _openSheet(tester, initialTotalPages: null, reported: reported);
      await _type(tester, '462');

      final field = tester.getRect(find.byType(CupertinoTextField));
      await tester.tapAt(Offset(field.center.dx, field.bottom + 8));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .focusNode!
            .hasFocus,
        isFalse,
      );
      expect(_fieldText(tester), '462');

      await _confirm(tester);
      expect(reported, [462]);
    });
  });

  group('the no-op guard', () {
    testWidgets(
      'Given a pre-filled total, When confirmed untouched, Then nothing is reported',
      (tester) async {
        // The regression this exists for, in the sibling sheet: Confirm wrote
        // unconditionally, so agreeing with a pre-filled value rewrote the column. Here
        // that would move every derived page read-out for the book.
        final reported = <Object?>[];
        await _openSheet(tester, initialTotalPages: 462, reported: reported);

        await _confirm(tester);

        expect(reported, isEmpty);
      },
    );

    testWidgets(
      'Given a typed total, When confirmed, Then it is reported once',
      (tester) async {
        final reported = <Object?>[];
        await _openSheet(tester, initialTotalPages: null, reported: reported);

        await _type(tester, '462');
        expect(_fieldText(tester), '462');

        await _confirm(tester);

        expect(reported, [462]);
      },
    );

    testWidgets(
      'Given a total is typed over a stored one, Then the new one is reported',
      (tester) async {
        // The correction case the sheet is mostly for: "this book is 462 pages, not 500".
        final reported = <Object?>[];
        await _openSheet(tester, initialTotalPages: 500, reported: reported);

        await _type(tester, '462');
        await _confirm(tester);

        expect(reported, [462]);
      },
    );

    testWidgets(
      'Given the field is emptied, When confirmed, Then nothing is reported',
      (tester) async {
        // An empty field is not an answer, so Confirm must not fall back to what was in it
        // before. Clearing and confirming is an abandon.
        final reported = <Object?>[];
        await _openSheet(tester, initialTotalPages: 462, reported: reported);

        await _type(tester, '');
        expect(_fieldText(tester), isEmpty);

        await _confirm(tester);

        expect(reported, isEmpty);
      },
    );

    testWidgets('dismissing without confirming reports nothing', (
      tester,
    ) async {
      final reported = <Object?>[];
      await _openSheet(tester, initialTotalPages: null, reported: reported);

      await _type(tester, '462');
      Navigator.of(tester.element(find.byType(CupertinoTextField))).pop();
      await tester.pumpAndSettle();

      expect(reported, isEmpty);
    });
  });

  group('the bounds', () {
    testWidgets(
      'Given a number past the ceiling, When typed, Then it clamps and says so',
      (tester) async {
        // A typo guard rather than a bibliographic claim: the longest single volumes in
        // print run to a few thousand pages, so this catches the reader who meant 462 and
        // typed it twice. Clamped as it is typed, so there is no invalid state to report.
        final reported = <Object?>[];
        await _openSheet(tester, initialTotalPages: null, reported: reported);

        await _type(tester, '99999');

        expect(kMaxTotalPages, 20000);
        expect(_fieldText(tester), '20000');
        expect(find.text('At most 20000 pages'), findsOneWidget);

        await _confirm(tester);
        expect(reported, [kMaxTotalPages]);
      },
    );

    testWidgets(
      'Given zero, When typed, Then it does not take — a book with no pages is not a book',
      (tester) async {
        // The floor is enforced by refusal rather than by clamping up to 1, because
        // emptying is what lets a leading zero be a slip: "0462" means 462, where
        // clamping "0" to "1" would leave the next keystroke building 14 out of 1 and 4.
        final reported = <Object?>[];
        await _openSheet(tester, initialTotalPages: null, reported: reported);

        await _type(tester, '0');
        expect(_fieldText(tester), isEmpty);
        expect(kMinTotalPages, 1);

        await _type(tester, '0462');
        expect(_fieldText(tester), '462');

        await _confirm(tester);
        // Never 0, and never a total below the floor.
        expect(reported, [462]);
      },
    );

    testWidgets(
      'Given a stored count outside the bounds, When opened, Then the field is already clamped',
      (tester) async {
        // The field must never display a number Confirm would silently change. This is
        // also where a sub-floor value does get clamped rather than refused: a stored 0
        // is bad data the sheet has to render something for.
        await _openSheet(tester, initialTotalPages: 0);
        expect(_fieldText(tester), '1');

        Navigator.of(tester.element(find.byType(CupertinoTextField))).pop();
        await tester.pumpAndSettle();

        await _openSheet(tester, initialTotalPages: 99999);
        expect(_fieldText(tester), '20000');
      },
    );

    testWidgets(
      'Given a paste too long for an int, When applied, Then it clamps rather than throwing',
      (tester) async {
        // The number pad cannot produce this; paste and dictation can, and `int.parse`
        // would throw on it.
        await _openSheet(tester, initialTotalPages: null);

        await _type(tester, '9' * 40);

        expect(_fieldText(tester), '20000');
      },
    );

    testWidgets('strips anything that is not a digit', (tester) async {
      await _openSheet(tester, initialTotalPages: null);

      await _type(tester, '4 62 pages');

      expect(_fieldText(tester), '462');
    });
  });

  // The contract is `recordTotalPages`': **changing the total must not move `progress`.**
  // The sheet's share of it is that it has nowhere to put a position — no parameter to
  // take one, no callback to emit one, and nothing on screen derived from one.
  group('the sheet says nothing about position', () {
    testWidgets('reports a bare int and nothing else', (tester) async {
      final reported = <Object?>[];
      await _openSheet(tester, initialTotalPages: 500, reported: reported);

      await _type(tester, '462');
      await _confirm(tester);

      // An int, not a record and not a double: a one-field record would be an invitation
      // to add a second field, and on this sheet the second field is the one the contract
      // forbids.
      expect(reported.single, isA<int>());
      expect(reported.single, isNot(isA<double>()));
      expect(reported.single, 462);
    });

    testWidgets('and draws no percent, no derived page and no rider', (
      tester,
    ) async {
      // The progress wheel's rider translates an answer into the other unit. Every
      // translation available here — "~ p.213", "46%" — would need the position, so the
      // absence of the line is the absence of the value.
      await _openSheet(tester, initialTotalPages: 462);

      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('~'), findsNothing);
      expect(find.textContaining('p.'), findsNothing);
    });
  });

  group('the sheet fits the phones this app supports', () {
    for (final phone in const [Size(375, 667), Size(393, 852)]) {
      testWidgets(
        'Given a ${phone.width.toInt()}×${phone.height.toInt()} surface, Then it fits at 138pt',
        (tester) async {
          // A RenderFlex overflow is reported as a test failure, so reaching the
          // assertion is most of it. The height pins down *why* it fits: 64 of header
          // plus a 56pt field plus the 18pt clamp band, with no wheel and no segment.
          await _openSheet(tester, initialTotalPages: 462, surface: phone);

          expect(tester.getSize(find.byKey(kTotalPagesSheetKey)).height, 138);
        },
      );
    }

    for (final pad in const [216.0, 290.0, 340.0]) {
      testWidgets(
        'Given a ${pad.toInt()}pt pad on the shortest phone, Then nothing overflows',
        (tester) async {
          // The bug the sibling sheet found on device and not in any test: `CNBottomSheet`
          // caps a sheet at 9/16 of the screen and pays the keyboard inset out of that
          // same budget, so the field's column overflowed. `isScrollControlled` lifts the
          // cap; these cases are what would notice it being dropped.
          await _openSheet(tester, initialTotalPages: 462, keyboard: pad);

          expect(tester.getSize(find.byKey(kTotalPagesSheetKey)).height, 138);
          // The sheet sits *on top of* the pad rather than under it, which is the
          // assertion a bare overflow check cannot make: the box's own height is 138
          // whether or not the inset is applied.
          expect(
            tester.getRect(find.byKey(kTotalPagesSheetKey)).bottom,
            667 - pad,
          );
        },
      );
    }

    testWidgets('and the clamp line does not change its height', (
      tester,
    ) async {
      // The band is reserved in every state rather than grown into, so what the reader
      // typed can never move the sheet under their thumb.
      await _openSheet(tester, initialTotalPages: 462);
      expect(tester.getSize(find.byKey(kTotalPagesSheetKey)).height, 138);

      await _type(tester, '99999');

      expect(find.text('At most 20000 pages'), findsOneWidget);
      expect(tester.getSize(find.byKey(kTotalPagesSheetKey)).height, 138);
    });
  });
}
