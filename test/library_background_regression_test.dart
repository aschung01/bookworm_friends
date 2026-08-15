// Regression test for the library background not filling the whole library
// area when there are only a few shelves.
//
// `RefreshIndicator` wraps its child in a loose `Stack`, so a decorated
// container placed *inside* the indicator is sized by the scroll view's content
// instead of the slot it was given — leaving the rest of the library painted
// with the scaffold background. The background must therefore sit outside the
// RefreshIndicator (see `_LibraryWithFinishedBooks` in home_page.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _backgroundKey = Key('library_background');

Widget _libraryColumn({required double sheetHeight}) {
  // Background outside, RefreshIndicator + scroll view inside: the fixed order.
  final library = Container(
    key: _backgroundKey,
    width: double.infinity,
    decoration: const BoxDecoration(color: Color(0xffE9ECEF)),
    child: RefreshIndicator(
      onRefresh: () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Deliberately much shorter than the available height.
        child: Column(children: [Container(height: 80, color: Colors.white)]),
      ),
    ),
  );

  return MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: library),
          SizedBox(height: sheetHeight),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Given a library shorter than the viewport, When it is refreshable, Then the background still fills the available height',
    (tester) async {
      const sheetHeight = 200.0;
      await tester.pumpWidget(_libraryColumn(sheetHeight: sheetHeight));
      await tester.pumpAndSettle();

      final bodyHeight = tester.getSize(find.byType(Scaffold)).height;
      final backgroundHeight = tester
          .getSize(find.byKey(_backgroundKey))
          .height;

      expect(backgroundHeight, moreOrLessEquals(bodyHeight - sheetHeight));
    },
  );
}
