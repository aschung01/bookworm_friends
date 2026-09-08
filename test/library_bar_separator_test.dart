// The bar's shadow, and the one thing worth asserting about it: it is always there.
//
// `library_view.dart` explains at length why `_BarShadow` exists at all — the bar went
// behind the pane so a sheet could rise over it, which put its `Material` elevation
// somewhere it could not be seen, so the shadow is re-cast from the library's own top
// edge instead.
//
// **This file exists because that shadow was briefly made conditional.** It was faded
// in with the library's scroll offset, on the reasoning that an iOS nav bar earns its
// separator by having content pass under it. That is the wrong model here: the shadow
// is the bottom edge of the encasing — "white surface bar with elevation 4 above,
// `#F8F9FA` well between, white sheet with an upward shadow below" — and the sheet at
// the other end casts upward whatever the library is doing. An encasing that comes and
// goes is not an encasing, and a library at rest looked unfinished without it.
//
// So these tests pin the *unconditionality*, which is the property that was lost and
// is not obvious from reading `LibraryPaneFrame`: the shadow survives scrolling, an
// overscroll at the top, and every state the library can be in. What it looks like is
// `Canvas.drawShadow`'s business and is not meaningfully assertable in a widget test.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/views/library_view.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';

import 'support/home_page_harness.dart';

/// A small phone, so the shelves below overflow it and there is something to scroll.
const _smallPhone = Size(375, 667);

/// Enough shelves to make the library taller than the viewport. One book each is
/// enough — it is the number of *rows* that decides whether the column overflows.
List<Shelf> _tallLibrary() => List.generate(
  8,
  (i) => testShelf('s$i', [
    testBook('b$i', 's$i', position: 0, title: 'Book $i'),
  ], name: 'Shelf $i'),
);

Finder _shadow() => find.byKey(kBarShadowKey);

Future<void> _pump(WidgetTester tester, {List<Shelf>? shelves}) => pumpHome(
  tester,
  shelves: shelves ?? _tallLibrary(),
  surfaceSize: _smallPhone,
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref) async => const <Book>[]),
  ],
);

void main() {
  group('the bar shadow', () {
    testWidgets(
      'Given the library at top scroll height, When it has not been touched, Then the '
      'bar still casts its shadow',
      (tester) async {
        // The state this file was written for. At rest is not a state where the
        // encasing goes away — it is the state most readers see most of the time, and
        // the one where a missing bottom edge reads as an unfinished bar.
        await _pump(tester);

        expect(_shadow(), findsOneWidget);
      },
    );

    testWidgets(
      'Given a library taller than the screen, When it is scrolled and returned, Then '
      'the shadow is unmoved throughout',
      (tester) async {
        await _pump(tester);
        expect(_shadow(), findsOneWidget);

        await tester.drag(find.byType(RefreshIndicator), const Offset(0, -200));
        await tester.pump();
        expect(_shadow(), findsOneWidget);

        await tester.drag(find.byType(RefreshIndicator), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(_shadow(), findsOneWidget);
      },
    );

    testWidgets(
      'Given a library shorter than the screen, When it is pulled down, Then the '
      'shadow rides the overscroll',
      (tester) async {
        // `AlwaysScrollableScrollPhysics` means even a one-shelf library rubber-bands.
        // Nothing about the shadow depends on offset any more, so a pull down is not a
        // state it has an opinion about — asserted because the reverted version did.
        await _pump(
          tester,
          shelves: [
            testShelf('s1', [
              testBook('b1', 's1', position: 0, title: 'Dune'),
            ], name: 'Dev'),
          ],
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(RefreshIndicator)),
        );
        await gesture.moveBy(const Offset(0, 80));
        await tester.pump();

        expect(_shadow(), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Given an empty library, When there are no shelves to scroll, Then the bar is '
      'still encased',
      (tester) async {
        // The state with no scrollable content at all, which is where a scroll-driven
        // shadow could never have appeared. `LibraryPaneFrame`'s whole reason for
        // existing is that the chrome does not depend on what the library contains.
        await _pump(tester, shelves: const []);

        expect(_shadow(), findsOneWidget);
      },
    );

    testWidgets(
      'Given the library has not loaded, When the skeleton is on screen, Then the bar '
      'is encased already',
      (tester) async {
        // Same rule, at the other end of the library's life. The bar is on screen from
        // the first frame, so its bottom edge has to be too — otherwise the encasing
        // assembles itself as the data arrives.
        //
        // Held on the *reads* rather than the shelves, which is how
        // `friend_navigation_test` reaches this state: the pane waits for the two as a
        // pair, and `libraryProvider` is a notifier rather than a plain future.
        final reads = Completer<List<Book>>();
        await pumpHome(
          tester,
          shelves: _tallLibrary(),
          surfaceSize: _smallPhone,
          // `LoadingLibrary` shimmers forever, so this must not settle.
          settle: false,
          extraOverrides: [
            finishedBooksProvider.overrideWith((ref) => reads.future),
          ],
        );

        expect(find.byType(LoadingLibrary), findsOneWidget);
        expect(_shadow(), findsOneWidget);

        reads.complete(const []);
        await tester.pumpAndSettle();
        expect(_shadow(), findsOneWidget);
      },
    );
  });
}
