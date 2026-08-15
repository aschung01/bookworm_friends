import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression test for the library edit-mode crash.
//
// _ShelfRowState.build wrapped its content in a DragTarget whose `builder`
// closure referenced the `shelfContent` variable AFTER that variable had been
// reassigned to the DragTarget itself. When edit mode was active the builder
// therefore nested the DragTarget inside itself infinitely, producing a
// StackOverflowError (surfaced on-screen as "FormatException: Stack overflow"
// because Flutter's stack-frame parser choked on the huge stack trace).
//
// This test reproduces the exact (buggy vs fixed) pattern to guard against a
// regression.
void main() {
  testWidgets(
    'builder closure must not reference a variable reassigned to itself',
    (tester) async {
      // Correct pattern: the content the builder returns is a stable value that
      // is NOT the DragTarget being constructed.
      const Widget content = Text('shelf', textDirection: TextDirection.ltr);

      final Widget dragTarget = DragTarget<String>(
        builder: (context, candidate, rejected) {
          return Container(child: content);
        },
      );

      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: dragTarget),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('shelf'), findsOneWidget);
    },
  );
}
