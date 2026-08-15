// Tests for the library's back-navigation behaviour.
//
// Entering edit mode makes a system back (Android's back gesture / button, iOS
// predictive back) *leave edit mode* instead of leaving the page.
//
// Note what carries the weight here. `HomePage` is the root route, so there is
// nothing to pop to and `find.byType(HomePage)` survives whether `canPop` is
// true or false — that assertion alone would be tautological. The real signal is
// the *side effect* of `onPopInvokedWithResult` running: edit mode ends.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/pages/home_page.dart';

import 'support/home_page_harness.dart';

void main() {
  testWidgets(
    'Given the library is in edit mode, When the system back fires, Then edit mode is exited and the page stays',
    (tester) async {
      await pumpHome(tester);
      expect(isEditing(), isFalse);

      await enterEditMode(tester);
      expect(isEditing(), isTrue);

      await simulateSystemBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(isEditing(), isFalse);
      // Still on the library, not popped to a blank route.
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'Given the library is not in edit mode, When the system back fires, Then the page is left alone',
    (tester) async {
      await pumpHome(tester);

      await simulateSystemBack();
      await tester.pumpAndSettle();

      // Nothing to pop to, so the route survives and no mode change happens.
      expect(find.byType(HomePage), findsOneWidget);
      expect(isEditing(), isFalse);
    },
  );
}
