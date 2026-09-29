// Tests for the one-line read-out above the reading track.
//
// Five properties matter here and none of them is visible in a type signature.
//
// **No value on this line is underlined, and `Add total pages` is.** This inverts what
// the file pinned for two rounds — it read *"only the page numerals are underlined ...
// pinned from both sides"* — and the mark moved to the sheet's two text actions. The rule
// that replaced it is narrower and is what these cases now hold from both sides: an
// underline marks an **action**, and the only action this line can contain is the offer to
// supply a total. Everything else here is a value.
//
// **A door nobody can open must not draw a handle**, which since the swap is only about the
// tap target and the ink — there is no underline left to drop. The page pair takes **one**
// ink for both spans, decided by the page's own door, because the merged sheet's Set aside
// state closes the position's doors while leaving the total's open and per-span ink drew one
// phrase in two colours.
//
// **No page count is the majority case** — about two reading books in three — so the
// interesting assertion is the absence of `p.213 of —` rather than the presence of the
// pair.
//
// **The tilde is provenance, not rounding noise.** A page derived from the fraction wears the
// tilde; one the reader typed does not. That distinction is the entire reason
// `progress_page` is stored, so a test that only checked "a page is printed" would pass
// on a version that had thrown it away.
//
// **It wraps rather than ellipsising.** The longest English case is
// `Set aside  46%  p.213 / 462` and Korean is longer. At 2× text scale on the smallest
// phone the page pair must drop to a second run with the status word intact — measured
// as geometry, because a `Wrap` clips silently instead of throwing the overflow error
// `tester.takeException` would catch.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_state_line.dart';

/// The smallest phone the app supports, which is also the narrowest measure this line
/// ever gets.
const Size _smallestPhone = Size(375, 667);

/// Taps, by door, so a test can tell which of the three fired.
late List<String> _taps;

Future<void> _pump(
  WidgetTester tester, {
  String statusLabel = 'Reading',
  double? progress = 0.46,
  int? progressPage,
  int? pageCount = 462,
  bool doors = true,
  TextScaler textScaler = TextScaler.noScaling,
  Size surface = _smallestPhone,
  Locale locale = const Locale('en'),
}) async {
  _taps = [];
  tester.view.physicalSize = surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            // The sheet's own measure: the full width, so a wrap here is a wrap
            // there. Left-aligned, or the runs would centre and the geometry
            // assertions would be about the alignment rather than the wrap.
            child: Align(
              alignment: Alignment.topLeft,
              child: ReadingStateLine(
                statusLabel: statusLabel,
                statusColor: context.colors.brandText,
                progress: progress,
                progressPage: progressPage,
                pageCount: pageCount,
                onPercentTap: doors ? () => _taps.add('percent') : null,
                onPageTap: doors ? () => _taps.add('page') : null,
                onTotalTap: doors ? () => _taps.add('total') : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// What the default `_pump` draws for its page.
///
/// **It read `~ p.213` and the tilde is gone**, deleted with `progressApproxPage`: a derived
/// page and a typed one print identically now. Kept as a named constant anyway, because the
/// cases below care *which* number is drawn and the `derived against given` group still has
/// something to say — the distinction moved from the format to the number.
const String _derivedPage = 'p.213';

/// The decoration actually drawn on a part, merged the way `Text` merges it.
TextDecoration? _decorationOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.decoration;

void main() {
  group('the underline', () {
    testWidgets(
      'Given all three doors, When the line is drawn, Then no value is underlined',
      (tester) async {
        await _pump(tester);

        // The two small spans inside a phrase, which is where the affordance is not
        // otherwise discoverable.
        // All three are doors and none of them advertises it. The cost is stated in the
        // widget's own doc: after this swap nothing announces that `p.213` opens a wheel.
        for (final label in ['Reading', '46%', _derivedPage, '/ 462']) {
          expect(
            _decorationOf(tester, label),
            TextDecoration.none,
            reason: label,
          );
        }

        // And the one that must stay unmarked however tappable it is. `isNot` would
        // pass on a null style, so this asserts the value.
        expect(_decorationOf(tester, '46%'), TextDecoration.none);
      },
    );

    testWidgets(
      'Given no callbacks, When the line is drawn, Then nothing is underlined and '
      'nothing is tappable',
      (tester) async {
        await _pump(tester, doors: false);

        // A friend's book. The read-out stays; the handles go.
        expect(_decorationOf(tester, _derivedPage), TextDecoration.none);
        expect(_decorationOf(tester, '/ 462'), TextDecoration.none);
        expect(_decorationOf(tester, '46%'), TextDecoration.none);

        // The pair also drops out of `primaryText` and into the ambient
        // `secondaryText`, so an inert span reads as the context it is rather than as
        // an underline someone forgot. The percent does not: it is the value on
        // anyone's book.
        final colors = AppTheme.light.extension<AppColors>()!;
        expect(
          tester.widget<Text>(find.text(_derivedPage)).style?.color,
          colors.secondaryText,
        );
        expect(
          tester.widget<Text>(find.text('/ 462')).style?.color,
          colors.secondaryText,
        );
        expect(
          tester.widget<Text>(find.text('46%')).style?.color,
          colors.primaryText,
        );

        // Not just unmarked — untappable. A `GestureDetector` left in place with a
        // null `onTap` would swallow nothing and look identical here.
        expect(
          find.descendant(
            of: find.byType(ReadingStateLine),
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Given the status word, When the line is drawn, Then it is never a door',
      (tester) async {
        await _pump(tester);

        // The word is a read-out of the position, not a control. There is no
        // `onStatusTap` to pass, so this pins that the word did not acquire the
        // percent's tap target by sitting next to it. Its `none` is stated rather
        // than left unset, so an ancestor cannot lend it one -- see `the ambient text
        // style` below for the render that made that necessary.
        expect(_decorationOf(tester, 'Reading'), TextDecoration.none);
        await tester.tap(find.text('Reading'), warnIfMissed: false);
        expect(_taps, isEmpty);
      },
    );
  });

  group('the ambient text style', () {
    testWidgets('Given an ancestor that underlines everything, When the line is drawn, Then '
        'nothing on it is marked', (tester) async {
      // **Found by looking at a render, not by a failing test.** `Text` merges its
      // own style onto the ambient `DefaultTextStyle`, so any property this line
      // leaves unset is the ancestor's to choose -- and `MaterialApp`'s fallback
      // default, in force wherever there is no `Material` or `Scaffold` above it,
      // is `_errorTextStyle`: `decoration: underline`, `decorationColor` yellow,
      // `decorationStyle: double`. A preview without a `Scaffold` therefore drew
      // the status word underlined and drew the page spans' rules as yellow double
      // lines, and nothing in this file noticed, because every assertion here reads
      // the widget's own style rather than the merged one.
      //
      // This case is the merged one. The style below is `_errorTextStyle`'s
      // decoration, which is both the realistic hostile ancestor and the worst one.
      tester.view.physicalSize = _smallestPhone * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DefaultTextStyle(
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFFFFF00),
              decorationStyle: TextDecorationStyle.double,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ReadingStateLine(
                statusLabel: 'Reading',
                statusColor: const Color(0xFF067657),
                progress: 0.46,
                pageCount: 462,
                onPercentTap: () {},
                onPageTap: () {},
                onTotalTap: () {},
              ),
            ),
          ),
        ),
      );

      // **Every part, now.** This case used to split the line into two that had to stay
      // unmarked and two that had to be marked; since the swap there is no second list, and
      // the hostile ancestor is a bigger risk than before rather than a smaller one — a
      // property left unset would now restore the exact mark this round removed, and it
      // would appear only in a harness with no `Material` above, which is every render
      // preview of this sheet.
      for (final label in ['Reading', '46%', _derivedPage, '/ 462']) {
        expect(
          tester.widget<Text>(find.text(label)).style?.decoration,
          TextDecoration.none,
          reason: label,
        );
      }
    });

    testWidgets('and the offer, which is marked, is marked in its own ink', (
      tester,
    ) async {
      // The one underline left on the line, under the same hostile ancestor: one solid
      // rule in the span's own colour rather than the ancestor's yellow double.
      tester.view.physicalSize = _smallestPhone * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DefaultTextStyle(
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFFFFF00),
              decorationStyle: TextDecorationStyle.double,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ReadingStateLine(
                statusLabel: 'Reading',
                statusColor: const Color(0xFF067657),
                progress: 0.46,
                onTotalTap: () {},
              ),
            ),
          ),
        ),
      );

      final colors = AppTheme.light.extension<AppColors>()!;
      final style = tester.widget<Text>(find.text('Add total pages')).style!;
      expect(style.decoration, TextDecoration.underline);
      expect(style.decorationStyle, TextDecorationStyle.solid);
      expect(style.decorationColor, colors.primaryText);
    });
  });

  group('the three doors', () {
    testWidgets(
      'Given all three, When each is tapped, Then each opens its own sheet',
      (tester) async {
        await _pump(tester);

        await tester.tap(find.text('46%'));
        await tester.tap(find.text(_derivedPage));
        await tester.tap(find.text('/ 462'));

        // Three callbacks, not one with a mode argument: the percent opens the wheel,
        // the page opens it in Page mode, the total opens a different sheet entirely.
        expect(_taps, ['percent', 'page', 'total']);
      },
    );

    testWidgets(
      'Given only the total door, When the page span is tapped, Then nothing fires',
      (tester) async {
        _taps = [];
        tester.view.physicalSize =
            _smallestPhone * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ReadingStateLine(
                  statusLabel: 'Reading',
                  statusColor: const Color(0xFF067657),
                  progress: 0.46,
                  pageCount: 462,
                  onTotalTap: () => _taps.add('total'),
                ),
              ),
            ),
          ),
        );

        // The three are independent, which is what lets the total ship before its
        // sheet exists — or after, while the wheel is being rebuilt.
        //
        // **This is also the merged sheet's Set aside state**, and the assertion that
        // matters most is the ink. The pair is one phrase and takes one colour, decided by
        // the page's door: without that, closing the position's doors while leaving the
        // total's open drew `p.213` grey beside `/ 462` dark, which reads as a rendering
        // fault. The total is still a door in either ink — since the underline left this
        // line, ink separates a live value from ambient context rather than marking what is
        // tappable.
        final colors = AppTheme.light.extension<AppColors>()!;
        for (final label in [_derivedPage, '/ 462']) {
          expect(
            _decorationOf(tester, label),
            TextDecoration.none,
            reason: label,
          );
          expect(
            tester.widget<Text>(find.text(label)).style?.color,
            colors.secondaryText,
            reason: label,
          );
        }

        await tester.tap(find.text(_derivedPage), warnIfMissed: false);
        expect(_taps, isEmpty);

        await tester.tap(find.text('/ 462'));
        expect(_taps, ['total']);
      },
    );
  });

  group('the page inside the total', () {
    testWidgets(
      'Given no page count, When the line is drawn, Then it offers the total and '
      'prints no page pair',
      (tester) async {
        await _pump(tester, pageCount: null);

        // ~65% of the corpus. The offer, underlined, in place of the pair.
        expect(find.text('Add total pages'), findsOneWidget);
        expect(
          _decorationOf(tester, 'Add total pages'),
          TextDecoration.underline,
        );

        // And emphatically not `p.213 of —`. A dash is not a total.
        expect(find.textContaining('p.'), findsNothing);
        expect(find.textContaining('/'), findsNothing);
        expect(find.textContaining('—'), findsNothing);

        // The position is still the position: losing the count loses the page, not
        // the percent.
        expect(find.text('46%'), findsOneWidget);

        await tester.tap(find.text('Add total pages'));
        expect(_taps, ['total']);
      },
    );

    testWidgets(
      'Given no page count and no total door, When the line is drawn, Then the '
      'offer is unmarked',
      (tester) async {
        await _pump(tester, pageCount: null, doors: false);

        // On a friend's book the offer is not an offer. It stays legible rather than
        // vanishing, because the alternative is a line whose length depends on whose
        // book it is.
        expect(_decorationOf(tester, 'Add total pages'), TextDecoration.none);
      },
    );

    testWidgets(
      'Given no page count but a typed page, When the line is drawn, Then the page '
      'is not printed alone',
      (tester) async {
        await _pump(tester, pageCount: null, progressPage: 213);

        // A lone `p.213` here would be the only place in the app a page survived its
        // count going missing.
        expect(find.text('Add total pages'), findsOneWidget);
        expect(find.textContaining('213'), findsNothing);
      },
    );
  });

  group('derived against given', () {
    // **The tilde is gone, and this group is about the number now rather than the format.**
    // A derived page printed `~ p.147` and a typed one `p.147`; `progressApproxPage` was
    // deleted on instruction, so both print `p.147` and the two cases that used to tell the
    // formats apart would now pass on a widget that had thrown the stored page away. They
    // assert the *value* instead, which is the claim worth holding: `given` still decides
    // which number is drawn, it just no longer decides how.
    testWidgets(
      'Given no typed page, Then the page is the arithmetic and is not marked as such',
      (tester) async {
        await _pump(tester, progress: 0.46, pageCount: 320);

        // 46% of 320 is p.147, and in percent mode a stop is 3.2 pages — so this page is
        // the arithmetic's rather than the reader's, and the line no longer says so. That
        // is the accepted cost of removing the mark: a reader who aimed at p.148 is shown
        // p.147 as flatly as if they had typed it.
        expect(find.text('p.147'), findsOneWidget);
        expect(find.textContaining('~'), findsNothing);
      },
    );

    testWidgets('Given a typed page, Then it is that page and not the derived one', (
      tester,
    ) async {
      // **The fraction is deliberately the one that does not agree.** 0.46 of 432
      // derives p.199, and this reader typed 200 -- which is what happens when a
      // total is corrected after the fact, or when the position was stored in
      // percent mode before a page was ever typed. Picking `200 / 432` here instead
      // would make the derived page and the stored one coincide, and the test would
      // then pass on a version that had thrown the stored one away.
      await _pump(tester, progress: 0.46, progressPage: 200, pageCount: 432);

      // **The reason `progress_page` is stored**, which the widget's doc used to credit to
      // the tilde: a page past a count it no longer divides evenly into is still the page
      // the reader said. Removing the mark did not touch this, and the pairing of 0.46 with
      // a typed 200 is what proves it — the two numbers cannot be confused for each other.
      expect(find.text('p.200'), findsOneWidget);
      expect(find.textContaining('199'), findsNothing);
    });

    testWidgets(
      'Given a position, When the derived page is printed, Then it is the shared '
      'rounding site that produced it',
      (tester) async {
        // Not a second opinion about rounding: the same free function the band and
        // the wheel's rider read, so the three cannot disagree about which page 46%
        // of 462 is.
        const progress = 0.46;
        const pageCount = 462;
        final page = bookProgressPage(progress, pageCount);
        expect(page, 213);

        await _pump(tester, progress: progress, pageCount: pageCount);
        expect(find.text('p.$page'), findsOneWidget);
      },
    );
  });

  group('no position yet', () {
    testWidgets(
      'Given a null position, When the line is drawn, Then only the status word is '
      'drawn',
      (tester) async {
        await _pump(tester, statusLabel: 'Not started', progress: null);

        // Null is not `0`. `0%` is a position the reader chose; this is the absence
        // of one, and the whole right-hand region answers "where in the book".
        expect(find.text('Not started'), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
        expect(find.textContaining('p.'), findsNothing);
        expect(find.text('Add total pages'), findsNothing);
      },
    );

    testWidgets(
      'Given a zero position, When the line is drawn, Then it reads 0%',
      (tester) async {
        await _pump(tester, progress: 0, pageCount: 462);

        // The other half of the same distinction, which a test on null alone would
        // let a `progress == 0` guard pass.
        expect(find.text('0%'), findsOneWidget);
        expect(find.text('p.0'), findsOneWidget);
      },
    );
  });

  group('the status word is the caller\'s', () {
    testWidgets(
      'Given a label and a colour, When the line is drawn, Then both are used as '
      'handed',
      (tester) async {
        const setAside = Color(0xFFF2A93F);
        await _pump(tester, statusLabel: 'Set aside');
        // Pumped again with an explicit colour so the assertion is about this
        // widget's plumbing rather than about the theme.
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ReadingStateLine(
                  statusLabel: 'Set aside',
                  statusColor: setAside,
                  progress: 0.46,
                  pageCount: 462,
                ),
              ),
            ),
          ),
        );

        // No int-to-word mapping here and no second copy of the badge's `switch`,
        // which ends in a soft `_ => statusOther` no test catches.
        expect(find.text('Set aside'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Set aside')).style?.color,
          setAside,
        );
      },
    );
  });

  group('Korean', () {
    testWidgets(
      'Given the ko locale, When the line is drawn, Then the page is a suffix and '
      'the total still follows a slash',
      (tester) async {
        await _pump(tester, statusLabel: '읽는 중', locale: const Locale('ko'));

        // `p.{page}` against `{page}쪽` is why the span rather than the digits was the
        // unit when this line was underlined, and it is still why the span is the tap
        // target: the number sits on the other side of the affix here, so there is no
        // locale-independent way to split the formatted string.
        expect(find.text('213쪽'), findsOneWidget);
        expect(find.text('/ 462'), findsOneWidget);
        expect(_decorationOf(tester, '213쪽'), TextDecoration.none);
        expect(_decorationOf(tester, '/ 462'), TextDecoration.none);
      },
    );
  });

  group('the page pair sits at the trailing edge', () {
    /// The line at a **tight** width, which is the one thing `_pump` cannot give it.
    ///
    /// `_pump` wraps the line in `Align(alignment: topLeft)`, so it is handed *loose*
    /// constraints and the `Wrap` shrink-wraps its content — which leaves no free space, and
    /// `WrapAlignment.spaceBetween` distributes free space. In the sheet the line sits in a
    /// `Column` with `CrossAxisAlignment.stretch`, so it gets the full width tight. Every
    /// case about the trailing edge therefore needs its own harness; every case about
    /// *wrapping* is fine in `_pump`, because `RenderWrap` decides runs from `maxWidth`
    /// either way.
    ///
    /// **500, not the sheet's 327, and the number is about the font rather than the design.**
    /// This file draws in `flutter_test`'s own face, where every glyph is a one-em square, so
    /// `Reading` sets to 151pt against about 75 on a phone and the two groups measure 396
    /// together. At 327 they do not fit, the pair drops to a second run, and the case would be
    /// measuring the wrap instead of the alignment. The real widths are in
    /// `book_status_bottom_sheet_test.dart`, which loads the app's faces, and in
    /// `book_status_sheet_render_preview.dart`.
    Future<void> pumpTight(WidgetTester tester, {double width = 500}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: ReadingStateLine(
                    statusLabel: 'Reading',
                    statusColor: context.colors.brandText,
                    progress: 0.46,
                    pageCount: 462,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Given room, Then the total ends flush with the line', (
      tester,
    ) async {
      // The ask was "the page index and count on the rightmost", and this is it stated as a
      // geometry rather than as an alignment enum: the last part's right edge is the line's.
      await pumpTight(tester);

      final line = tester.getRect(find.byType(ReadingStateLine));
      final total = tester.getRect(find.text('/ 462'));
      expect(total.right, moreOrLessEquals(line.right, epsilon: 0.5));
      // On one run, so this is the alignment and not a wrap that happens to end flush.
      expect(total.top, moreOrLessEquals(line.top, epsilon: 12));
    });

    testWidgets('and the percent stays beside the status word', (tester) async {
      // **The reason the two groups are nested rather than flat.** `spaceBetween` over the
      // flat list of four parts would spread all four and float the percent into the middle
      // of the line; over two groups it pins one to each edge. So this case is what rules out
      // the one-line version of the change.
      await pumpTight(tester);

      final word = tester.getRect(find.text('Reading'));
      final percent = tester.getRect(find.text('46%'));
      final page = tester.getRect(find.text(_derivedPage));

      expect(percent.left - word.right, moreOrLessEquals(8, epsilon: 0.5));
      // And a real gutter opened up before the page pair, which is what "rightmost" means.
      expect(page.left - percent.right, greaterThan(40));
    });

    testWidgets('Given no position, Then the status word is not pushed anywhere', (
      tester,
    ) async {
      // One child in a run sits at the start under `spaceBetween`, so the origin state needs
      // no special casing — but it is worth pinning, because a `spaceBetween` that centred or
      // stretched a lone child would put `Not started` somewhere absurd.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 500,
                  child: ReadingStateLine(
                    statusLabel: 'Not started',
                    statusColor: context.colors.secondaryText,
                    progress: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final line = tester.getRect(find.byType(ReadingStateLine));
      final word = tester.getRect(find.text('Not started'));
      expect(word.left, moreOrLessEquals(line.left, epsilon: 0.5));
    });
  });

  group('type pressure', () {
    testWidgets('Given the longest case at 2x text on the smallest phone, When the line is '
        'drawn, Then the page pair wraps and nothing leaves the measure', (tester) async {
      await _pump(
        tester,
        // The longest English case, and the status word is the part that must not
        // be sacrificed for it.
        statusLabel: 'Set aside',
        textScaler: const TextScaler.linear(2),
      );

      // A `Wrap` does not throw on overflow the way a `RenderFlex` does, so this
      // alone would pass on a clipped line. It is here to catch everything else.
      expect(tester.takeException(), isNull);

      final line = tester.getRect(find.byType(ReadingStateLine));
      expect(line.width, lessThanOrEqualTo(_smallestPhone.width));

      // Every part inside the measure, which is the assertion a clip would fail.
      for (final label in ['Set aside', '46%', _derivedPage, '/ 462']) {
        final rect = tester.getRect(find.text(label));
        expect(
          rect.right,
          lessThanOrEqualTo(_smallestPhone.width + precisionErrorTolerance),
          reason: '$label runs past the measure',
        );
      }

      // Wrapped, not ellipsised, in two halves.
      //
      // The page pair is on a lower run than the status word, so the degradation is
      // a wrap and the word did not give up room for it.
      expect(
        tester.getRect(find.text(_derivedPage)).top,
        greaterThan(tester.getRect(find.text('Set aside')).top),
        reason: 'the page pair should not share the status word\'s run',
      );

      // And nothing anywhere on the line sets an ellipsis or a line cap. **This is
      // the font-independent half and the one to trust.** `flutter_test`'s font is
      // much wider than Pretendard -- `Set aside` alone fills all 375pt here, where
      // on a device the whole line fits at 1x -- so exactly which run each part
      // lands on is a property of the harness rather than of the widget. What the
      // widget guarantees at any scale, in any font, is that no part is ever cut
      // short to make room for another.
      for (final label in ['Set aside', '46%', _derivedPage, '/ 462']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.overflow, isNot(TextOverflow.ellipsis), reason: label);
        expect(text.maxLines, isNull, reason: label);
      }
    });

    testWidgets(
      'Given the no-count case in Korean at 2x text, When the line is drawn, Then '
      'nothing leaves the measure',
      (tester) async {
        // `전체 쪽수 입력` is the longest single part, and a single part too wide for
        // the line is the one case a `Wrap` cannot fix by wrapping: it has to soft-wrap
        // inside itself, which it only does because `RenderWrap` hands each child the
        // Wrap's own `maxWidth`.
        await _pump(
          tester,
          statusLabel: '중단',
          pageCount: null,
          locale: const Locale('ko'),
          textScaler: const TextScaler.linear(2),
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(ReadingStateLine)).width,
          lessThanOrEqualTo(_smallestPhone.width),
        );
        expect(
          tester.getRect(find.text('전체 쪽수 입력')).right,
          lessThanOrEqualTo(_smallestPhone.width + precisionErrorTolerance),
        );
      },
    );
  });
}
