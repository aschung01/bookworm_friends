// Covers the clear ("x") button inside the shared search field.
//
// It lives on `SearchTextField`, so both search surfaces get it — the Add Book
// sheet and the friends header — but the sheet is where the interesting cases
// are: it is the field that can be filled by something other than the user (a
// cover read), and the field whose *results* have to go away along with the text.

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
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';

import 'support/home_page_harness.dart';

/// The reference device the sheet's geometry was reasoned in.
const Size _phone = Size(402, 874);

/// The button, found by tooltip — which on Material *is* the accessible name.
final clearButton = find.byTooltip('Clear search');

/// Always answers with one book.
///
/// `thumbnail` is empty on purpose: [BookWidget] falls back to the generated
/// cover rather than reaching for a `NetworkImage`, which `flutter test` has no
/// answer for.
class OneResultSearchProvider implements BookSearchProvider {
  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async => const [
    BookSearchResult(title: 'Dune', isbn: '9788937473135', thumbnail: ''),
  ];

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async => null;
}

Future<void> pumpAddBook(
  WidgetTester tester, {
  ScanOutcome? scanReturns,
}) async {
  tester.view.physicalSize = _phone * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryProvider.overrideWith(
          () => FakeLibraryNotifier([testShelf('s1', [], name: 'Dev')]),
        ),
        bookSearchProvider.overrideWithValue(OneResultSearchProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routes: {
          AppRoutes.scanBook: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.pop<ScanOutcome>(context, scanReturns),
                child: const Text('leave scanner'),
              ),
            ),
          ),
        },
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

/// Types [query] and presses the keyboard's search key, as a user would.
Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

/// Fills the field from a cover read, which leaves it unfocused and marked.
Future<void> readCover(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Scan a book's barcode"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('leave scanner'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('there is no clear button until there is something to clear', (
    tester,
  ) async {
    await pumpAddBook(tester);
    expect(clearButton, findsNothing);

    await tester.enterText(find.byType(TextField), 'Dun');
    await tester.pumpAndSettle();

    // Appears on the first character, not on submit: what it offers to undo is
    // the typing, and a half-typed query is exactly what people abandon.
    expect(clearButton, findsOneWidget);
  });

  testWidgets('it takes the results with it, not just the text', (
    tester,
  ) async {
    await pumpAddBook(tester);
    await search(tester, 'Dune');
    expect(find.byType(BookWidget), findsWidgets);

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
    // A grid still answering a query that is no longer on screen is the failure
    // this guards: the empty state comes back, scan action and all.
    expect(find.byType(BookWidget), findsNothing);
    expect(
      find.widgetWithText(ElevatedActionButton, 'Scan a book'),
      findsOneWidget,
    );
    expect(clearButton, findsNothing);
  });

  testWidgets('it sits at the field\'s trailing edge', (tester) async {
    await pumpAddBook(tester);
    final emptyHeight = tester.getSize(find.byType(SearchFieldPill)).height;

    await tester.enterText(find.byType(TextField), 'Dune');
    await tester.pumpAndSettle();

    // 12 is [SearchFieldPill]'s own horizontal padding, so the button is flush
    // against the inside of the pill. Left to Material's default `suffixIcon`
    // constraints this measures 24: the 48pt minimum width pads the 36pt button
    // out and parks it in the middle of nothing.
    final pill = tester.getRect(find.byType(SearchFieldPill));
    expect(pill.right - tester.getRect(clearButton).right, 12);
    // And the button is short enough that appearing cannot resize the pill.
    expect(pill.height, emptyHeight);
  });

  testWidgets('it stays the rightmost thing in the pill', (tester) async {
    await pumpAddBook(tester, scanReturns: const ScanFoundQuery('Dune'));
    await readCover(tester);
    expect(find.text('from cover'), findsOneWidget);

    // The provenance chip is passed *through* the field rather than placed
    // beside it, so this holds in the one state where the pill has two things
    // after the text. A control at the edge trailed by a badge reads as a
    // layout accident.
    expect(
      tester.getRect(find.text('from cover')).right,
      lessThanOrEqualTo(tester.getRect(clearButton).left),
    );
    expect(
      tester.getRect(clearButton).right,
      lessThanOrEqualTo(tester.getRect(find.byType(SearchFieldPill)).right),
    );
  });

  testWidgets('clearing a cover read does not raise the keyboard', (
    tester,
  ) async {
    await pumpAddBook(tester, scanReturns: const ScanFoundQuery('Dune'));
    await readCover(tester);
    final focus = tester.widget<TextField>(find.byType(TextField)).focusNode;
    expect(focus?.hasFocus, isFalse, reason: 'a cover read does not focus');

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    // Same restraint the scanner shows on the way back: emptying the field is
    // not a request to type, and the tap must not fall through to the field.
    expect(focus?.hasFocus, isFalse);
  });
}
