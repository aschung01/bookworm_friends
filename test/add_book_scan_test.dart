// Covers the scan entry point in the Add Book sheet.
//
// The Add Book sheet had no test coverage at all before this; these are its
// first. They stop at the scanner's door on purpose — `ScanBookPage` opens a
// camera through a platform view, which `flutter test` has no answer for, so the
// route is stubbed and what is verified here is the *wiring*: that both doors
// lead to it, that "type instead" is honoured on the way back, and that the
// empty-state action is somewhere a thumb can actually reach.

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/pages/scan_book_page.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

import 'support/home_page_harness.dart';

/// Never called by these tests, but [bookSearchProvider] must be overridden
/// regardless: its real body reaches `sharedPreferencesProvider`, which throws
/// unless `main()` has overridden it.
class _UnusedSearchProvider implements BookSearchProvider {
  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async => [];

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async => null;
}

/// The reference device the sheet's geometry was reasoned in.
const Size _phone = Size(402, 874);

/// Roughly an iOS keyboard. Only the order of magnitude matters.
const double _keyboardHeight = 336;

/// The scan button in the search row.
///
/// Found by tooltip rather than semantics label because a test always renders
/// [AdaptiveIconButton]'s Material fallback — `usesNativeGlass` is false off
/// iOS 26 — and on Material the tooltip *is* the accessible name (the glass path
/// attaches a `Semantics` wrapper instead, since a platform view cannot carry
/// one). So this asserts the icon-only control is named, which is the thing worth
/// asserting.
final scanButton = find.byTooltip("Scan a book's barcode");

/// Pumps the Add Book sheet with the scanner route stubbed out.
///
/// [scanReturns] is what the stub pops, standing in for how the user left the
/// scanner.
///
/// The stub is normally registered in a `routes` table, which builds a
/// `Route<dynamic>` — fine for everything here, and *unlike* production, where
/// `AppRoutes.onGenerateRoute` builds a typed `CupertinoPageRoute<ScanOutcome>` so
/// the scanner can rise from the bottom. Pass [likeProduction] to stub it that way
/// instead: it is the shape the untyped `pushNamed` in `_openScanner` has to
/// survive, and the only shape a real tap ever meets.
Future<void> pumpAddBook(
  WidgetTester tester, {
  ScanOutcome? scanReturns,
  double bottomViewInset = 0,
  bool likeProduction = false,
}) async {
  tester.view.physicalSize = _phone * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  if (bottomViewInset > 0) {
    tester.view.viewInsets = FakeViewPadding(
      bottom: bottomViewInset * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
  }

  Widget scanner(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.pop<ScanOutcome>(context, scanReturns),
        child: const Text('leave scanner'),
      ),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryProvider.overrideWith(
          () => FakeLibraryNotifier([testShelf('s1', [], name: 'Dev')]),
        ),
        bookSearchProvider.overrideWithValue(_UnusedSearchProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routes: likeProduction
            ? const <String, WidgetBuilder>{}
            : {AppRoutes.scanBook: scanner},
        onGenerateRoute: likeProduction
            ? (settings) => settings.name == AppRoutes.scanBook
                  ? CupertinoPageRoute<ScanOutcome>(
                      settings: settings,
                      fullscreenDialog: true,
                      builder: scanner,
                    )
                  : null
            : null,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAddBookBottomSheet(context),
                child: const Text('open add book'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open add book'));
  await tester.pumpAndSettle();
}

void main() {
  group('the scanner rises from the bottom', () {
    // Not a test of the animation — of the route that produces it. The scanner is a
    // full-screen cover rather than a trailing-edge push because it is an errand you
    // come back from and it carries an ✕, not a back chevron. `docs/mockups/scan-to-add`
    // rejected the other reading of "from the bottom" — an actual sheet — for reasons a
    // cover does not pay: 250pt of framing room above the scan window collapsing to 150
    // and clipping the book, and a save sheet putting a live camera platform view under
    // two Flutter sheets.

    test('and is therefore absent from the routes table', () {
      // **The silent-revert guard.** `MaterialApp` consults `routes` first and falls
      // through to `onGenerateRoute` only for a name the table does not hold, so an
      // entry in both would not conflict, would not throw, and would not look wrong —
      // the table would simply win and the scanner would go back to sliding in from
      // the side. Nothing else in the suite would notice.
      expect(AppRoutes.routes.containsKey(AppRoutes.scanBook), isFalse);
      expect(
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.scanBook),
        ),
        isNotNull,
      );
    });

    test('as a full-screen cover carrying the scanner\'s own result type', () {
      final route =
          AppRoutes.onGenerateRoute(
                const RouteSettings(name: AppRoutes.scanBook),
              )!
              as CupertinoPageRoute<ScanOutcome>;

      // `fullscreenDialog` is what buys both halves: the upward direction, and the
      // page below being covered rather than transformed. `CupertinoPageRoute` rather
      // than the Material one because `ZoomPageTransitionsBuilder` — the Android
      // default, and this app sets no `PageTransitionsTheme` — never consults the
      // flag, so the same push would still arrive from the side there.
      expect(route.fullscreenDialog, isTrue);
      // Still a `PageRoute`, which is the whole reason the floating tab bar keeps
      // getting out of the way without anyone matching on this route's name.
      expect(route, isA<PageRoute<ScanOutcome>>());
    });

    testWidgets('and an untyped push still carries the outcome back', (
      tester,
    ) async {
      // The rest of this file stubs the scanner in a `routes` table, which builds a
      // `Route<dynamic>`. Production no longer does: the route is a typed
      // `CupertinoPageRoute<ScanOutcome>`, and `pushNamed` with no type argument
      // casts whatever it gets to `Route<Object?>`. That cast is the thing that
      // throws on the first tap when the two ends disagree, so it is worth meeting
      // the typed shape once.
      await pumpAddBook(
        tester,
        scanReturns: const ScanFoundQuery('Dune'),
        likeProduction: true,
      );

      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave scanner'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Dune',
      );
      expect(find.text('from cover'), findsOneWidget);
    });
  });

  testWidgets('the search row carries exactly one scan button', (tester) async {
    await pumpAddBook(tester);

    // One, not two. A barcode icon and a camera icon side by side would cost the
    // pill 52pt and ask the user which kind of reading will work before they have
    // pointed the phone at anything.
    expect(scanButton, findsOneWidget);
  });

  testWidgets('the empty state advertises scanning too', (tester) async {
    await pumpAddBook(tester);

    // The discoverable half, and what pays for there being only one glyph above.
    expect(
      find.widgetWithText(ElevatedActionButton, 'Scan a book'),
      findsOneWidget,
    );
  });

  testWidgets('both doors reach the scanner', (tester) async {
    await pumpAddBook(tester);

    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    expect(find.text('leave scanner'), findsOneWidget);

    await tester.tap(find.text('leave scanner'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedActionButton, 'Scan a book'));
    await tester.pumpAndSettle();
    expect(find.text('leave scanner'), findsOneWidget);
  });

  testWidgets('the Add Book sheet survives a round trip to the scanner', (
    tester,
  ) async {
    await pumpAddBook(tester);

    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave scanner'));
    await tester.pumpAndSettle();

    // The scanner is pushed *over* the sheet rather than replacing it, so coming
    // back lands on the sheet and not on the library.
    expect(find.text('Add book'), findsOneWidget);
  });

  testWidgets('the search field takes focus on open', (tester) async {
    await pumpAddBook(tester);

    // Selecting the search tab *is* the request to search, so the cursor starts
    // where the user was going to put it. The empty state this keyboard covers
    // scrolls and pads for the view insets, which is what makes it affordable —
    // see 'the empty-state action clears the keyboard' below.
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('choosing "type instead" focuses the field on return', (
    tester,
  ) async {
    await pumpAddBook(tester, scanReturns: const ScanTypeInstead());

    final field = find.byType(TextField);

    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave scanner'));
    await tester.pumpAndSettle();

    // Opening the scanner drops the focus the field opened with, deliberately, so
    // that the two outcomes which do not want a keyboard do not silently inherit
    // one. That makes honouring this choice an explicit request. Returning them to
    // an unfocused field after they asked to type would make them tap it themselves.
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
  });

  testWidgets('a plain dismissal does not raise the keyboard', (tester) async {
    await pumpAddBook(tester);

    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave scanner'));
    await tester.pumpAndSettle();

    // Backing out of the scanner is not a request to type. This is the whole
    // reason the outcome is a type rather than a nullable ISBN — and the reason
    // `_openScanner` drops focus on the way *in*, since a pop otherwise restores
    // the keyboard the field opened with all by itself.
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isFalse,
    );
  });

  group('a query read off a cover', () {
    testWidgets('lands in the field and runs', (tester) async {
      await pumpAddBook(tester, scanReturns: const ScanFoundQuery('소년이 온다 한강'));

      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave scanner'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '소년이 온다 한강',
      );
    });

    testWidgets('is marked as coming from the app, not the user', (
      tester,
    ) async {
      await pumpAddBook(tester, scanReturns: const ScanFoundQuery('Dune'));

      expect(find.text('from cover'), findsNothing);

      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave scanner'));
      await tester.pumpAndSettle();

      // Without this a misread title looks like the user's own typo — and a model
      // reading stylised cover type will sometimes misread.
      expect(find.text('from cover'), findsOneWidget);
    });

    testWidgets('stops being marked once the user edits it', (tester) async {
      await pumpAddBook(tester, scanReturns: const ScanFoundQuery('Dune'));

      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave scanner'));
      await tester.pumpAndSettle();
      expect(find.text('from cover'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Dune Herbert');
      await tester.pumpAndSettle();

      // From here it is their query, so claiming it came from a cover would be
      // wrong — and would leave the chip stuck there for the rest of the session.
      expect(find.text('from cover'), findsNothing);
    });

    testWidgets('does not raise the keyboard over the results', (tester) async {
      await pumpAddBook(tester, scanReturns: const ScanFoundQuery('Dune'));

      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave scanner'));
      await tester.pumpAndSettle();

      // The answer to a cover read is the grid. Focusing the field would cover it
      // with a keyboard nobody asked for — the opposite of ScanTypeInstead.
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isFalse,
      );
    });
  });

  testWidgets('the empty-state action clears the keyboard', (tester) async {
    await pumpAddBook(tester, bottomViewInset: _keyboardHeight);

    // Regression: the keyboard overlays this sheet rather than resizing it, and
    // only the *results list* ever compensated. The empty state is a `Center` in
    // an `Expanded`, so at ~336pt of keyboard its contents sat squarely behind
    // it — which cost nothing while the empty state held only an icon and a line
    // of text, and became a dead control the moment it held a button.
    final button = tester.getRect(
      find.widgetWithText(ElevatedActionButton, 'Scan a book'),
    );
    expect(button.bottom, lessThanOrEqualTo(_phone.height - _keyboardHeight));
  });

  testWidgets('the empty-state action is padded around its label', (
    tester,
  ) async {
    await pumpAddBook(tester);

    // Regression: [ElevatedActionButton] pads by zero, which is right for every
    // other one in the app — they are stretched by a `SizedBox`, an `Expanded`,
    // or a width tuned to the label, and padding would only eat the room the
    // label has. This one sizes itself *to* its label, so zero padding put
    // "Scan a book" flush against a 50pt radius: no gap on the right at all, and
    // a fake one on the left that was really the icon's own bearing.
    final pill = find.widgetWithText(ElevatedActionButton, 'Scan a book');
    final label = find.descendant(of: pill, matching: find.text('Scan a book'));
    expect(
      tester.getRect(pill).right - tester.getRect(label).right,
      closeTo(20, 0.5),
    );
  });

  testWidgets('ElevatedActionButton(activated: false) is genuinely disabled', (
    tester,
  ) async {
    // Not a test of this feature — a guard on the trap that broke it. `activated`
    // reads like a styling flag next to `disabledStyleOutline`, and it is not:
    // the widget passes `activated ? onPressed : null`. Spelling an *enabled*
    // outlined button that way produced two dead controls here, one of them the
    // only way out of the scanner's camera-denied card. Anyone reaching for that
    // pair again should trip over this.
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: ElevatedActionButton(
              buttonText: 'nope',
              activated: false,
              disabledStyleOutline: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('nope'));
    await tester.pumpAndSettle();
    expect(taps, 0);

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });
}
