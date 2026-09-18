// Changing density turns the books. It does not swap the picture.
//
// The first version cross-faded: the row faded out over 90ms, the drawing was replaced
// while nothing was visible, and it faded back. Nothing moved, so nothing was explained
// — a reader saw one shelf become a different shelf and had to work out where their
// books had gone. `spines` and `covers` are the *same books from another angle*, and the
// transition now says so: every compressed book rotates on its binding, in a wave from
// the left, and the row narrows as they go. The narrowing is the answer to "why is this
// state denser".
//
// **The bug this file exists to prevent.** The tile choice — cover, part-way round, or
// spine — is made in `build`, and `build` runs on the frame the density changed, which is
// the frame the controller was started on, when it still stands at the endpoint it is
// leaving. Read the controller's *value* there and every book is chosen as a resting
// cover, nothing ever re-chooses, and the row animates its margins closed around books
// that never turn. It rendered as a shelf gently squeezing shut. Hence
// `_ShelfRowState._densityTurning`, a flag raised before the controller starts, and hence
// the mid-turn assertions below: they are the ones that failed.
//
// The frames that go with this are `flutter test test/shelf_density_render_preview.dart`
// → build/shelf_preview/turn_*.png. "Does this read as books turning" is not a number,
// and the measurements here do not claim to answer it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/turning_book.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_book_tile.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_density_turn.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_spine_tile.dart';

import 'support/home_page_harness.dart';
import 'support/prefs.dart';

/// One book in progress and five that compress.
///
/// In progress first because that is where the row promotes it, and because a reading
/// book is the control in every assertion here: it looks the same at both densities, so
/// it must not turn in either direction.
///
/// Five compressible, which is [kShelfDensityStaggerBooks] — enough that the first and
/// last are in different buckets of the wave and the stagger is observable.
List<Shelf> _shelf() => [
  testShelf('s1', [
    testBook(
      'r',
      's1',
      position: 0,
      title: 'Reading',
      status: bookStatusReading,
    ),
    for (var i = 0; i < 5; i++)
      testBook('b$i', 's1', position: i + 1, title: _compressed[i]),
  ], name: 'Dev'),
];

const _compressed = ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon'];

Future<void> _pump(
  WidgetTester tester, {
  ShelfDensity density = ShelfDensity.covers,
}) async => pumpHome(
  tester,
  shelves: _shelf(),
  extraOverrides: [
    await sharedPreferencesOverride({'shelf_density': density.name}),
  ],
);

/// The density button, by the glyph of the density it is *in*.
///
/// Scoped to the `AppBar` and found by icon, because `find.bySemanticsLabel` does not
/// reach an `AdaptiveIconButton` on the Material path — the label becomes a tooltip.
/// `shelf_density_button_test` finds it the same way.
Finder _button(ShelfDensity density) => find.descendant(
  of: find.byType(AppBar),
  matching: find.byIcon(
    density == ShelfDensity.covers ? Icons.book : Icons.view_week,
  ),
);

/// The face-out tile for the book titled [title], whatever angle it is standing at.
Finder _tileOf(String title) =>
    find.byWidgetPredicate((w) => w is ShelfBookTile && w.book.title == title);

/// How far the book titled [title] has turned, in radians, or null if it is not posed.
///
/// Magnitude, so a test reads "how far round" rather than carrying the sign of
/// [kSpineOnPose] through every comparison.
double? _turnOf(WidgetTester tester, String title) =>
    tester.widget<ShelfBookTile>(_tileOf(title)).pose?.value.abs();

/// Half a turn in, where every interesting assertion lives.
///
/// A tap and then half of [kShelfDensityTurnDuration]. Two pumps after the tap because
/// the density is persisted before it is applied — `set` awaits `prefs.setString` — so
/// the frame the row starts turning on is not the frame the button was hit on.
Future<void> _tapAndHalfTurn(WidgetTester tester, ShelfDensity from) async {
  await tester.tap(_button(from));
  await tester.pump();
  await tester.pump(kShelfDensityTurnDuration ~/ 2);
}

void main() {
  group('at rest', () {
    testWidgets('Given covers, When the row settles, Then no book is posed', (
      tester,
    ) async {
      await _pump(tester);

      // Null rather than zero. A pose of 0 would still cost every book a chassis
      // rendered at an angle and a spine face built beside its cover, for a row that
      // is not turning — and `ShelfBookTile` uses the null to decide the pivot, since
      // a press hold wants to tip about the middle and only a density turn is hinged.
      for (final title in [..._compressed, 'Reading']) {
        expect(_turnOf(tester, title), isNull, reason: title);
      }
      expect(find.byType(ShelfSpineTile), findsNothing);
    });

    testWidgets(
      'Given spines, When the row settles, Then the compressed books are spine tiles '
      'rather than posed covers',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);

        // **Not a detail.** `ShelfSpineTile` takes its width from the page count, so
        // `spines` needs no cover to decode and the row stays a lazy `ListView` that
        // builds about four tiles. Drawing the resting state with the turning tile would
        // read identically and forfeit that on every shelf in the library.
        expect(find.byType(ShelfSpineTile), findsWidgets);
        for (final title in _compressed) {
          expect(_tileOf(title), findsNothing, reason: title);
        }
        // The one book that is face-out at both densities.
        expect(_turnOf(tester, 'Reading'), isNull);
      },
    );
  });

  group('mid-turn', () {
    testWidgets(
      'Given covers, When the density button is tapped, Then the compressed books are '
      'part-way round',
      (tester) async {
        await _pump(tester);
        await _tapAndHalfTurn(tester, ShelfDensity.covers);

        // The assertion the value-reading version failed: it left every book at a pose
        // of null, standing square on, while the margins closed around them.
        for (final title in _compressed) {
          final turn = _turnOf(tester, title);
          expect(turn, isNotNull, reason: '$title should be turning');
          expect(
            turn,
            inExclusiveRange(0, kSpineOnPose.abs()),
            reason: '$title should be between cover-on and spine-on',
          );
        }
      },
    );

    testWidgets(
      'Given a turn in progress, When the poses are compared, Then the change runs '
      'across the row as a wave',
      (tester) async {
        await _pump(tester);
        await _tapAndHalfTurn(tester, ShelfDensity.covers);

        final turns = [
          for (final title in _compressed) _turnOf(tester, title)!,
        ];
        // Each book starts a little after the one to its left, so at any instant the
        // left of the row is further round. Unison is the same information delivered as
        // a jolt; a wave says *these are separate objects and each one turned*.
        for (var i = 1; i < turns.length; i++) {
          expect(
            turns[i],
            lessThanOrEqualTo(turns[i - 1]),
            reason: '${_compressed[i]} should trail ${_compressed[i - 1]}',
          );
        }
        expect(
          turns.first,
          greaterThan(turns.last),
          reason: 'a wave, not five books moving together',
        );
      },
    );

    testWidgets(
      'Given a turn in progress, When the in-progress book is checked, Then it has not '
      'moved',
      (tester) async {
        await _pump(tester);
        await _tapAndHalfTurn(tester, ShelfDensity.covers);

        // Face-out at both densities, so there is nowhere for it to turn to. Keyed off
        // the status rather than off the index, which is why this holds during the turn
        // and not only at the ends.
        expect(_turnOf(tester, 'Reading'), isNull);
      },
    );

    testWidgets(
      'Given a turn in progress, When the row is measured, Then it has begun to narrow',
      (tester) async {
        await _pump(tester);
        final before = tester.getTopLeft(_tileOf('Epsilon')).dx;

        await _tapAndHalfTurn(tester, ShelfDensity.covers);
        final midway = tester.getTopLeft(_tileOf('Epsilon')).dx;

        await tester.pumpAndSettle();
        final after = tester.getTopLeft(_spineOf('Epsilon')).dx;

        // The last book is dragged left by every book ahead of it turning edge-on. The
        // narrowing is the point of the animation — it is what makes "denser" something
        // a reader watches happen rather than something they infer from a new picture.
        expect(midway, lessThan(before));
        expect(after, lessThan(midway));
      },
    );
  });

  group('interrupting the turn', () {
    testWidgets(
      'Given a turn in progress, When the button is tapped back, Then the books reverse '
      'from where they stand',
      (tester) async {
        await _pump(tester);
        await _tapAndHalfTurn(tester, ShelfDensity.covers);
        final midway = _turnOf(tester, 'Alpha')!;

        await tester.tap(_button(ShelfDensity.spines));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        // `forward`/`reverse` rather than `forward(from: 0)`, which is the whole reason
        // the transition is one 0..1 controller and not two one-way animations: a book
        // caught half-way round unwinds from half-way round. Restarting would snap it
        // flat and turn it out again, at the exact moment a reader has said "no, back".
        final flicked = _turnOf(tester, 'Alpha')!;
        expect(flicked, lessThan(midway));
        expect(flicked, greaterThan(0));

        await tester.pumpAndSettle();
        expect(_turnOf(tester, 'Alpha'), isNull);
        expect(find.byType(ShelfSpineTile), findsNothing);
      },
    );

    testWidgets(
      'Given spines with a book turned out, When the row turns back to covers, Then '
      'that book sits the turn out',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);
        await tester.tap(_spineOf('Gamma'));
        await tester.pumpAndSettle();
        expect(find.byType(TurningBook), findsOne);

        await _tapAndHalfTurn(tester, ShelfDensity.spines);

        // It is the one book on the row that was already cover-on, so it is already
        // where every other book is going. Posed with the rest it would snap to spine-on
        // on the first frame and travel back through 90° a reader can see it did not
        // need to go.
        expect(_turnOf(tester, 'Gamma'), isNull);
        for (final title in _compressed.where((t) => t != 'Gamma')) {
          expect(_turnOf(tester, title), isNotNull, reason: title);
        }
      },
    );
  });

  group('reduced motion', () {
    testWidgets(
      'Given animations are disabled, When the density changes, Then the row is never '
      'caught between the two',
      (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        await _pump(tester);
        await tester.tap(_button(ShelfDensity.covers));
        await tester.pump();
        await tester.pump();

        // Straight to the endpoint, with no posed frame in between — and the endpoint
        // is the resting drawing, not a turning tile parked at spine-on, so the row
        // keeps its lazy width and its arched heads.
        expect(find.byType(ShelfSpineTile), findsWidgets);
        for (final title in _compressed) {
          expect(_tileOf(title), findsNothing, reason: title);
        }
      },
    );
  });
}

/// The spine drawn for the book titled [title].
Finder _spineOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ShelfSpineTile));
