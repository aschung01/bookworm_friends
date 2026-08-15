// Tests for the app bar's collapsing title on the book-details page.
//
// The page's title lives in the scrolling hero header, where long titles pan
// horizontally rather than truncate. Once that header scrolls under the app bar a
// second, truncated copy crossfades into the bar alongside a miniature cover, the
// way iOS collapses a large header.
//
// The handoff point is measured rather than hardcoded: the fade runs across the
// in-page title's own height, starting when its top meets the app bar's bottom
// edge. So what is asserted is that nothing is built at rest, that the bar copy is
// fully opaque once the in-page title has gone under, that it truncates instead of
// spilling past the action buttons, and that a partial scroll leaves it mid-fade.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/headers/collapsing_book_title.dart';

import 'support/home_page_harness.dart' show FakeLibraryNotifier;

const _me = 'me';
const _shelfId = 's1';

/// Long enough that it cannot fit the toolbar's middle slot, so truncation is
/// actually exercised.
const _longTitle =
    'Eldest: Inheritance, or the Vault of Souls, Book Two of the Cycle';

/// The catalogue lookup is irrelevant here, and a widget test must not hit the
/// network. Returning null also keeps the authors row out of the header.
class _NoBookInfo implements BookSearchProvider {
  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async => const [];

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async => null;
}

Book _book() => Book(
  id: 'b1',
  userId: _me,
  shelfId: _shelfId,
  isbn: '440238498',
  title: _longTitle,
  thumbnail: '', // empty keeps the network out; GeneratedCover stands in
  status: 2,
  position: 0,
  startDate: DateTime(2023, 12, 9),
  finishDate: DateTime(2023, 12, 23),
  createdAt: DateTime(2023, 12, 9),
);

List<Shelf> _shelves() => [
  Shelf(
    id: _shelfId,
    userId: _me,
    name: 'Novels',
    position: 0,
    createdAt: DateTime(2023),
    books: const [],
  ),
];

Future<void> _pumpDetails(WidgetTester tester, {required Book book}) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone-ish, 390x844 dp
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_me),
        bookSearchProvider.overrideWithValue(_NoBookInfo()),
        bookMemosProvider(book.id).overrideWith((ref) async => <BookMemo>[]),
        bookComplimentsProvider(
          book.id,
        ).overrideWith((ref) async => <BookCompliment>[]),
        userLibraryProvider(
          book.userId,
        ).overrideWith((ref) async => _shelves()),
        libraryProvider.overrideWith(() => FakeLibraryNotifier(_shelves())),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The view reads its `Book` off `ModalRoute.settings.arguments`.
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const BookDetailsTabView(),
          settings: RouteSettings(name: settings.name, arguments: book),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The title in the scrolling header.
///
/// A plain `find.text` is ambiguous: with no artwork every cover on the page is a
/// `GeneratedCover`, which paints the title as well. The header copy is the one in
/// the strip that pans horizontally.
Finder _heroTitle() => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    description: 'horizontally panning strip',
  ),
  matching: find.text(_longTitle, skipOffstage: false),
  skipOffstage: false,
);

/// The truncating title inside the app bar, as distinct from the copy painted on
/// its own mini cover. Matched on the single line that is the point of it.
Finder _barTitle() => find.descendant(
  of: find.byType(CollapsingBookTitle),
  matching: find.byWidgetPredicate(
    (w) => w is Text && w.data == _longTitle && w.maxLines == 1,
    description: 'single-line title',
  ),
);

/// The mini cover in the app bar.
Finder _barCover() => find.descendant(
  of: find.byType(CollapsingBookTitle),
  matching: find.byType(BookWidget),
);

/// The outermost opacity in the bar's row — the one driving the crossfade.
double _barOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byType(CollapsingBookTitle),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

/// Scrolls the page by exactly [dy].
///
/// Driven as an explicit gesture rather than through `tester.drag`, for two
/// reasons. The drag has to start inside the tab content: the centre of the
/// [NestedScrollView] lands on the pinned [TabBar], which swallows a vertical
/// drag without scrolling anything. And the first move of a drag is spent getting
/// it recognised — `tester.drag` folds that slop into the distance you ask for,
/// so sending it separately is what makes [dy] the distance actually scrolled.
Future<void> _scrollBy(WidgetTester tester, double dy) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('ISBN')),
  );
  await gesture.moveBy(const Offset(0, -kDragSlopDefault));
  await gesture.moveBy(Offset(0, -dy));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('BookDetailsTabView collapsing app bar title', () {
    testWidgets(
      'Given the header at rest, When the page is shown, Then the app bar carries no title or cover',
      (tester) async {
        await _pumpDetails(tester, book: _book());

        // The header copy is on screen...
        expect(_heroTitle(), findsOneWidget);
        // ...and the bar's copy is not built at all, so nothing paints over the
        // back button and the mini cover holds no image stream.
        expect(find.byType(CollapsingBookTitle), findsOneWidget);
        expect(_barTitle(), findsNothing);
        expect(_barCover(), findsNothing);
      },
    );

    testWidgets(
      'Given a scroll past the hero header, When the in-page title has gone under the app bar, Then the truncated title and mini cover are fully faded in',
      (tester) async {
        await _pumpDetails(tester, book: _book());

        // Well past the header, so the fade has certainly finished.
        await _scrollBy(tester, 400);

        expect(_barTitle(), findsOneWidget);
        expect(_barCover(), findsOneWidget);
        expect(_barOpacity(tester), 1.0);

        final text = tester.widget<Text>(_barTitle());
        expect(text.overflow, TextOverflow.ellipsis);

        // Truncated, not overflowing: the row sits inside the toolbar's middle
        // slot rather than spilling past the action buttons.
        final bar = tester.getRect(find.byType(AppBar));
        final row = tester.getRect(find.byType(CollapsingBookTitle));
        expect(row.width, lessThan(bar.width));
        expect(row.right, lessThanOrEqualTo(bar.right));
      },
    );

    testWidgets(
      'Given a partial scroll, When the in-page title is halfway under the app bar, Then the bar copy is mid-crossfade',
      (tester) async {
        await _pumpDetails(tester, book: _book());

        final title = tester.getRect(_heroTitle());
        final viewportTop = tester.getRect(find.byType(NestedScrollView)).top;

        // Land the in-page title's midpoint on the app bar's bottom edge, which
        // is by construction where the fade is half done.
        await _scrollBy(tester, title.center.dy - viewportTop);

        final opacity = _barOpacity(tester);
        expect(opacity, greaterThan(0.0));
        expect(opacity, lessThan(1.0));
        expect(opacity, closeTo(0.5, 0.15));
      },
    );
  });
}
