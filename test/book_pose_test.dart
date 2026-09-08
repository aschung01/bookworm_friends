// Tests for the four things `BookWidget` gained so the read pile could turn a
// book out of a row of spines: a caller-resolved jitter, a pose in radians, the
// spine face and its pivot, and the cover-colour report.
//
// The angle and the metrics are read straight off the rendered `BookChassis`, so
// these assert what was actually composed rather than an internal flag. That is
// the same approach `book_hold_gesture_test.dart` takes, and for the same reason.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

const String _isbn = '9788936434120';
const double _base = 130;

BookChassis _chassis(WidgetTester tester) =>
    tester.widget<BookChassis>(find.byType(BookChassis));

Future<void> _pump(WidgetTester tester, Widget book) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Scaffold(body: Center(child: book)),
      ),
    ),
  );
  await tester.pump();
}

/// A solid image of [color], served to [BookWidget] through the image cache.
///
/// `NetworkImage` is its own cache key, so priming the cache under an identical
/// provider makes `resolve` return this completer and no request is ever made.
/// The alternative is a fake `HttpClient`, which is four classes of boilerplate
/// to deliver the same bytes.
Future<void> _primeCover(String url, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 8, 12), Paint()..color = color);
  final image = await recorder.endRecording().toImage(8, 12);
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url),
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))),
  );
}

void main() {
  group('jitterOverride', () {
    testWidgets(
      'Given an override, When the book builds, Then its metrics come from the '
      'override and not from the ISBN hash',
      (tester) async {
        // The pile lays out flat spines at a thickness it resolved itself and
        // then replaces the tapped one with a chassis. If the chassis re-derives
        // the jitter, the cover is a different thickness from the spine that was
        // tapped and the swap visibly steps.
        const override = BookJitter(1.05, 0.5);
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            jitterOverride: override,
          ),
        );

        final expected = BookMetrics.from(
          baseHeight: _base,
          coverAspect: kDefaultCoverAspect,
          jitter: override,
        );
        expect(
          _chassis(tester).metrics.height,
          closeTo(expected.height, 1e-9),
          reason: 'the override did not reach BookMetrics',
        );
        expect(
          _chassis(tester).metrics.thickness,
          closeTo(expected.thickness, 1e-9),
          reason: 'the override did not reach BookMetrics',
        );
        // And it is genuinely different from what the hash would have given, or
        // the assertion above proves nothing.
        final hashed = BookMetrics.from(
          baseHeight: _base,
          coverAspect: kDefaultCoverAspect,
          jitter: BookJitter.fromIsbn(_isbn),
        );
        expect(
          _chassis(tester).metrics.height,
          isNot(closeTo(hashed.height, 0.5)),
        );
      },
    );

    testWidgets(
      'Given jitter is off as well, When the book builds, Then the override '
      'still wins',
      (tester) async {
        // `jitter: false` means "do not invent variation", not "be neutral no
        // matter what you are told". A caller that resolved the size is the only
        // one who can know it.
        const override = BookJitter(1.04, 0.5);
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            jitter: false,
            jitterOverride: override,
          ),
        );

        expect(
          _chassis(tester).metrics.height,
          closeTo(_base * 1.04, 1e-9),
          reason: 'jitter: false overrode an explicit override',
        );
      },
    );
  });

  group('turnRadians — the pose', () {
    testWidgets(
      'Given a pose of -π/2, When the book builds, Then it is turned spine-on',
      (tester) async {
        // The pile's resting state, and the angle `turnDrive` cannot express: it
        // maps 0..1 onto kBookTurnAngle, so the most it can reach is +16°.
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            turnRadians: AlwaysStoppedAnimation(-1.5707963267948966),
            spine: SizedBox(),
            pivot: Alignment.centerLeft,
          ),
        );

        expect(_chassis(tester).turn, closeTo(-1.5707963267948966, 1e-9));
      },
    );

    testWidgets(
      'Given a pose and a hold, When the book is held, Then the hold adds to '
      'the pose rather than replacing it',
      (tester) async {
        // This is the difference between `turnRadians` and `turnDrive`, and it is
        // the whole reason a book turned out of the pile behaves like a book on a
        // shelf: the pose says where the pile put it, the hold says how it
        // answers your finger. `turnDrive` replaces the hold because it *is* the
        // hold, relocated to another recogniser; a pose is a different quantity,
        // so it composes.
        //
        // Held at a pose of 0 — a book fully turned out — the angle must reach
        // exactly what a shelf book reaches.
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            turnRadians: AlwaysStoppedAnimation(0),
          ),
        );
        expect(_chassis(tester).turn, 0);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(BookWidget)),
        );
        await tester.pump(kBookHoldDelay);
        await tester.pump(kBookTurnDuration);
        expect(
          _chassis(tester).turn,
          closeTo(kBookTurnAngle, 1e-9),
          reason: 'the hold did not reach the shelf angle over a pose of 0',
        );

        await gesture.up();
        // A bare pump first: `animateBack` is scheduled outside a frame, so its
        // ticker takes its start time from the *next* one. Advancing the clock
        // straight away measures the release from a moment it had not begun, and
        // the book reads as still held.
        await tester.pumpAndSettle();
        expect(
          _chassis(tester).turn,
          closeTo(0, 1e-6),
          reason: 'releasing did not return the book to its pose',
        );
      },
    );

    testWidgets(
      'Given a spine-on pose, When the book is held, Then the hold offsets that '
      'pose instead of unwinding it',
      (tester) async {
        // The failure mode this rules out: a hold on a spine-on book snapping it
        // to +16° absolute, i.e. flat, because something treated the hold as the
        // whole angle.
        const pose = -1.5707963267948966;
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            turnRadians: AlwaysStoppedAnimation(pose),
          ),
        );

        await tester.startGesture(tester.getCenter(find.byType(BookWidget)));
        await tester.pump(kBookHoldDelay);
        await tester.pump(kBookTurnDuration);
        expect(_chassis(tester).turn, closeTo(pose + kBookTurnAngle, 1e-9));
      },
    );

    testWidgets(
      'Given both a pose and a turnDrive, When the book is constructed, Then it '
      'asserts',
      (tester) async {
        // One replaces the hold and the other composes with it, so together they
        // leave no answer to "what does the hold do".
        expect(
          () => BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            turnDrive: const AlwaysStoppedAnimation(1),
            turnRadians: const AlwaysStoppedAnimation(0),
          ),
          throwsAssertionError,
        );
      },
    );
  });

  group('the spine face and the pivot', () {
    testWidgets(
      'Given a spine and a hinge pivot, When the book builds, Then both reach '
      'the chassis',
      (tester) async {
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            spine: SizedBox(key: ValueKey('spine')),
            pivot: Alignment.centerLeft,
          ),
        );

        expect(_chassis(tester).spine, isNotNull);
        expect(_chassis(tester).pivot, Alignment.centerLeft);
        expect(find.byKey(const ValueKey('spine')), findsOneWidget);
      },
    );

    testWidgets(
      'Given no spine, When the book builds, Then the chassis has none — the '
      'shelves are untouched',
      (tester) async {
        await _pump(
          tester,
          const BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
          ),
        );

        expect(_chassis(tester).spine, isNull);
        expect(_chassis(tester).pivot, Alignment.center);
      },
    );
  });

  group('onCoverSampled — the backfill', () {
    testWidgets(
      'Given a cover that decodes, When it is sampled, Then its average colour '
      'is reported once',
      (tester) async {
        // The colour is asserted, not just the call: this is the value that ends
        // up in `books.cover_color` and drives every spine in the pile, so a
        // callback that fired with the wrong pixel would be worse than one that
        // never fired.
        const url = 'https://example.com/solid-c81e64.png';
        const cover = Color(0xFFC81E64);
        final reported = <Color>[];
        addTearDown(PaintingBinding.instance.imageCache.clear);

        // All of it inside `runAsync`. `_sampleCoverColor` awaits
        // `Picture.toImage` and then `Image.toByteData`, which are real engine
        // round trips: inside `testWidgets`' fake-async zone they never complete,
        // so the callback silently never fires and the test passes for the wrong
        // reason if you only assert that nothing went wrong.
        await tester.runAsync(() async {
          await _primeCover(url, cover);
          await _pump(
            tester,
            BookWidget(
              imageUrl: url,
              isbn: _isbn,
              title: '아몬드',
              height: _base,
              onCoverSampled: reported.add,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();

        expect(reported, hasLength(1), reason: 'expected exactly one report');
        expect(reported.single, cover);
      },
    );

    testWidgets(
      'Given no cover url, When the book builds, Then nothing is reported',
      (tester) async {
        // A generated cover's colour is `generatedCoverColor(isbn)` — derived,
        // reproducible, and pointless to store. Only a decoded jacket carries
        // information the database does not already have.
        final reported = <Color>[];
        await _pump(
          tester,
          BookWidget(
            imageUrl: '',
            isbn: _isbn,
            title: '아몬드',
            height: _base,
            onCoverSampled: reported.add,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(reported, isEmpty);
      },
    );
  });
}
