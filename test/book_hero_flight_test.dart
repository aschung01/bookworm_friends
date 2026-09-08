// Guards the shape of a book while it flies between two routes.
//
// The bug this pins: tapping a book on a shelf cropped its cover mid-flight —
// roughly a third of the artwork's height disappeared and slid back in as the
// details header landed. Nothing about the book was wrong at either end, so it
// was only visible in motion.
//
// Two independent causes, both about the flight rect rather than the book:
//
//   1. `MaterialApp` installs `MaterialRectArcTween` as the default hero rect
//      tween, and it arcs the rect's top-left and bottom-right corners along two
//      *separate* circles. The interpolated rect therefore does not keep its
//      aspect ratio even when both endpoints have the same one: a 61x92 shelf book
//      flying to a 122x183 header passed through 107x114 — 0.94 where both ends
//      are 0.667. The cover is `BoxFit.cover` inside a `ClipRRect` pinned to that
//      box, so the artwork was cropped to fill it.
//   2. `BookChassis` sizes its three faces from `BookMetrics` in absolute pixels,
//      not from its constraints. Squeezed by the flight rect it kept its
//      destination-sized binding band, radii, perspective and page-block
//      translations while the box shrank, so nothing scaled as one object.
//
// Both are asserted on the *painted* rect, in screen coordinates, because a
// correctly laid out book that is painted through a distorting scale is exactly
// the failure mode here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

const String _isbn = '9788936434120';
const double _shelfHeight = 90;
const double _detailsHeight = 180;

/// The cover face — the one that carries the artwork, and so the one whose shape
/// a viewer reads as the book.
final Finder _coverFace = find.descendant(
  of: find.byType(BookChassis),
  matching: find.byType(ClipRRect),
);

Widget _book({required double height, VoidCallback? onTap}) => BookWidget(
  height: height,
  // Empty, so the cover is generated rather than fetched: a network image in a
  // widget test never resolves, and the book's aspect ratio would then depend on
  // load timing instead of on the flight.
  imageUrl: '',
  isbn: _isbn,
  title: '아몬드',
  heroTag: 'book_$_isbn',
  onTap: onTap,
);

Future<void> _pumpShelf(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: _book(
              height: _shelfHeight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _book(height: _detailsHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Samples the cover face frame by frame for the length of a route transition.
///
/// Returns the painted rect and the laid-out size at each sample. The two differ
/// only by the flight's scale, which is the whole point: the first shows what is
/// on screen, the second whether the subtree got to build at its own size.
Future<List<(Rect painted, Size laidOut)>> _sampleFlight(
  WidgetTester tester,
) async {
  final samples = <(Rect, Size)>[];
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final face = _coverFace.evaluate();
    // Both routes' heroes are replaced by placeholders during a flight, so there
    // is exactly one book on screen: the one in the overlay.
    expect(face.length, 1);
    samples.add((
      tester.getRect(_coverFace),
      (face.single.renderObject! as RenderBox).size,
    ));
  }
  await tester.pumpAndSettle();
  return samples;
}

void main() {
  // Resting aspect ratio of a generated cover, which both ends of the flight
  // share — only the base height differs between a shelf book and the header.
  const restingAspect = kDefaultCoverAspect;

  testWidgets('cover keeps its aspect ratio for the whole push flight', (
    tester,
  ) async {
    await _pumpShelf(tester);
    expect(
      tester.getRect(_coverFace).width / tester.getRect(_coverFace).height,
      closeTo(restingAspect, 1e-6),
    );

    await tester.tap(find.byType(BookChassis));
    await tester.pump();
    final samples = await _sampleFlight(tester);

    for (final (painted, _) in samples) {
      expect(
        painted.width / painted.height,
        closeTo(restingAspect, 1e-3),
        reason:
            'cover was $painted mid-flight, which crops the artwork to fill it',
      );
    }
  });

  testWidgets('flying book is laid out at its own metrics, then scaled', (
    tester,
  ) async {
    await _pumpShelf(tester);
    await tester.tap(find.byType(BookChassis));
    await tester.pump();
    final samples = await _sampleFlight(tester);

    // The shuttle is the destination's subtree, so it must build at the
    // destination's size at every point of the flight — anything else means the
    // flight's constraints reached the chassis and its pixel-valued internals
    // (binding band, radii, perspective, page-block offsets) no longer match the
    // cover they were computed for.
    final expected = BookMetrics.from(
      baseHeight: _detailsHeight,
      coverAspect: kDefaultCoverAspect,
      jitter: BookJitter.fromIsbn(_isbn),
    );
    for (final (_, laidOut) in samples) {
      expect(laidOut.width, closeTo(expected.width, 0.01));
      expect(laidOut.height, closeTo(expected.height, 0.01));
    }

    // And the painted size only ever grows on a push. The arc tween's distortion
    // overshot the destination width mid-flight and then came back, which reads as
    // a wobble even once the aspect ratio is held.
    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i].$1.width,
        greaterThanOrEqualTo(samples[i - 1].$1.width - 0.01),
      );
      expect(samples[i].$1.width, lessThanOrEqualTo(expected.width + 0.01));
    }
  });

  testWidgets('cover keeps its aspect ratio for the whole pop flight', (
    tester,
  ) async {
    await _pumpShelf(tester);
    await tester.tap(find.byType(BookChassis));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    final samples = await _sampleFlight(tester);

    for (final (painted, _) in samples) {
      expect(
        painted.width / painted.height,
        closeTo(restingAspect, 1e-3),
        reason:
            'cover was $painted mid-flight, which crops the artwork to fill it',
      );
    }
  });
}
