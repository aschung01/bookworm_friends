// Tests for `View and share`: the screen between the share button and the OS sheet.
//
// **What this screen exists to fix is an invisibility, so most of these tests are
// about what is on screen at a moment rather than about geometry.** Until Task 3 the
// Card tab's share button went from tap to platform sheet behind an `EasyLoading`
// spinner: the reader never saw the image and was never told which year was in it.
// Three of the four claims below are therefore about that — the scope is named, the
// preview is the export, and nothing can be sent while the covers are still holes.
//
// **The loading state is driven, not waited for.** `coverImageProvider` is swapped for
// a fake whose completion the test holds, which is the only way to assert "assembling"
// as a state rather than as a race. The fake is cached per URL on purpose: the drawn
// `Image` and the precache list are built by two separate calls to the resolver, and
// production's `NetworkImage` makes them one cache entry through value equality — a
// fake with identity equality would have the precache waiting on a provider the row
// never draws, and the test would pass for the wrong reason.
//
// `createTestImage` is decoded in `setUp`, not in a test body: it is real async work
// off the fake clock, so awaiting it inside `testWidgets` hangs the run with no output.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/services/card_destinations.dart';
import 'package:bookworm_friends/ui/pages/share_card_page.dart';
import 'package:bookworm_friends/services/cover_image.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_framing.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_destination_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_library_card.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';

import 'support/prefs.dart';

/// Wraps [app] in the scope the page needs.
///
/// **Every test that builds a `ShareCardPage` needs one.** The display setting is a stored
/// preference (`card_display_provider.dart`), so the page is a `ConsumerStatefulWidget`
/// and a bare `MaterialApp` gives it nowhere to read from — which fails as
/// `Bad state: No ProviderScope found` at the first build.
Future<Widget> _scoped(Widget app) async =>
    ProviderScope(overrides: [await sharedPreferencesOverride()], child: app);

const _surface = Size(400, 900);

/// A cover whose decode the test finishes by hand.
///
/// Identity is the cache key (no `==` override), which is what keeps one test's
/// providers out of the next one's `imageCache`. [_resolver] is what makes two calls
/// for the same URL return the same instance.
class _ManualImage extends ImageProvider<_ManualImage> {
  _ManualImage(this.image);

  final ui.Image image;
  final Completer<ImageInfo> _decoded = Completer<ImageInfo>();

  void finishDecoding() {
    if (!_decoded.isCompleted) {
      _decoded.complete(ImageInfo(image: image.clone()));
    }
  }

  @override
  Future<_ManualImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ManualImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _ManualImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_decoded.future);
}

Book _read(
  String id, {
  DateTime? finish,
  String thumbnail = '',
  List<String> authors = const [],
}) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: thumbnail,
  status: 2,
  position: 0,
  startDate: (finish ?? DateTime(2026, 3, 10)).subtract(
    const Duration(days: 6),
  ),
  finishDate: finish ?? DateTime(2026, 3, 10),
  createdAt: DateTime(2024),
  authors: authors,
);

void main() {
  late ui.Image pixels;
  late Map<String, _ManualImage> byUrl;

  setUp(() async {
    // In `setUp`, never in a test body. See the file header.
    pixels = await createTestImage(width: 8, height: 12);
    byUrl = {};
    coverImageProvider = (url) =>
        byUrl.putIfAbsent(url, () => _ManualImage(pixels));
    // **Stubbed, and this file broke once for want of it.** The page probes for Instagram
    // while the covers precache, and the real probe crosses a platform channel — which
    // under `flutter test` neither succeeds nor throws usefully, it just does not resolve
    // inside the two frames `pumpPage` allows. Every assertion about the artifact then
    // failed with `Bad state: No element`, because the screen was still assembling.
    instagramInstalledProbe = () async => false;
  });

  tearDown(() {
    coverImageProvider = networkCoverImage;
    resetCardDestinations();
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  /// Finishes every cover decode the page is waiting on.
  ///
  /// Also what drains the precache's own timeout timer: [kPrecacheBudget] is a real
  /// `Future.timeout`, and `Future.timeout` cancels its timer only when the future it
  /// guards completes. Leaving it pending fails the test on the framework's
  /// "a Timer is still pending" invariant, which is why every test that asserts the
  /// assembling state finishes by landing the covers.
  Future<void> landCovers(WidgetTester tester) async {
    for (final provider in byUrl.values) {
      provider.finishDecoding();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required ShareCardArgs args,
    Locale locale = const Locale('en'),
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        // The display setting is a stored preference now — see
        // `card_display_provider.dart`. [prefs] seeds it, which is how a test asserts what
        // the page does with a setting it *finds* rather than only with one it is given.
        overrides: [await sharedPreferencesOverride(prefs)],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShareCardPage(args: args),
        ),
      ),
    );
    // **Two pumps, and deliberately not `pumpAndSettle`.** The assembling state holds
    // an indefinite `CircularProgressIndicator`, so a frame is always scheduled while
    // it is on screen and `pumpAndSettle` would keep advancing the fake clock until
    // something else stopped it — which here is the precache's own five-second
    // timeout. That made every test see a *ready* page and the assembling assertions
    // pass vacuously. Two pumps is one frame for the tree and one for the precache's
    // continuation, which is all a page with nothing to decode needs.
    await tester.pump();
    await tester.pump();
  }

  group('scope', () {
    testWidgets(
      'Given all time, When the screen opens, Then the title says so',
      (tester) async {
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(find.text('Your all-time Library Card'), findsOneWidget);
        expect(find.text('View and share'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a year filter, When the screen opens, Then the title names the year',
      (tester) async {
        // The claim that earns this screen: the sheet's capsules are behind the
        // presentation now, so this line is the only thing that can say which year is
        // about to leave the phone.
        await pumpPage(
          tester,
          args: ShareCardArgs(
            books: [_read('a', finish: DateTime(2026, 4, 2))],
            year: 2026,
          ),
        );

        expect(find.text('Your 2026 Library Card'), findsOneWidget);
        expect(find.text('Your all-time Library Card'), findsNothing);
      },
    );

    testWidgets('Given Korean, When the screen opens, Then the chrome is Korean', (
      tester,
    ) async {
      await pumpPage(
        tester,
        args: ShareCardArgs(books: [_read('a')]),
        locale: const Locale('ko'),
      );

      expect(find.text('확인하고 공유하기'), findsOneWidget);
      // The artifact's own furniture stays fixed whatever the chrome does — that is
      // `card_furniture.dart`'s whole argument, and this is where the two meet.
      expect(find.text('MY LIBRARY CARD'), findsOneWidget);
    });
  });

  group('assembling', () {
    testWidgets(
      'Given covers still decoding, When they land, Then the placeholder gives way to '
      'the artifact and the destination goes live',
      (tester) async {
        // One test rather than two, because the fake clock will not let the pending
        // state be left behind — see [landCovers].
        await pumpPage(
          tester,
          args: ShareCardArgs(
            books: [_read('a', thumbnail: 'https://example.test/a.jpg')],
          ),
        );

        expect(find.byKey(kShareCardSkeletonKey), findsOneWidget);
        expect(find.byKey(kShareCardArtKey), findsNothing);
        // Inert, not absent. The row keeps its height so the artifact does not move
        // under the reader's eye when the covers land.
        expect(find.byKey(kShareCardMoreKey), findsOneWidget);
        expect(
          tester.widget<InkWell>(find.byKey(kShareCardMoreKey)).onTap,
          isNull,
        );

        await landCovers(tester);

        expect(find.byKey(kShareCardSkeletonKey), findsNothing);
        expect(find.byKey(kShareCardArtKey), findsOneWidget);
        expect(
          tester.widget<InkWell>(find.byKey(kShareCardMoreKey)).onTap,
          isNotNull,
        );
      },
    );

    testWidgets(
      'Given no cover art at all, When the screen opens, Then there is nothing to '
      'wait for',
      (tester) async {
        // The common case in the migrated corpus, and the one where a screen that
        // always showed a placeholder first would flash for no reason.
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(find.byKey(kShareCardArtKey), findsOneWidget);
        expect(find.byKey(kShareCardSkeletonKey), findsNothing);
      },
    );
  });

  group('the preview is the export', () {
    testWidgets(
      'Given the screen, When the artifact is laid out, Then it is laid out at the '
      'exported size',
      (tester) async {
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        // Scaled to fit by a `FittedBox`, which is a transform rather than a relayout
        // — so the box the card lays out in is still the one the PNG is taken from. A
        // preview laid out to the screen's width could break a line the export does
        // not, and the reader would have approved an image that is not the one that
        // left.
        expect(
          tester.getSize(find.byKey(kShareCardArtKey)),
          kShareableCardSize,
        );
      },
    );

    testWidgets(
      'Given the placeholder, When it is laid out, Then it holds the same size',
      (tester) async {
        await pumpPage(
          tester,
          args: ShareCardArgs(
            books: [_read('a', thumbnail: 'https://example.test/a.jpg')],
          ),
        );

        expect(
          tester.getSize(find.byKey(kShareCardSkeletonKey)),
          kShareableCardSize,
        );

        await landCovers(tester);
      },
    );

    testWidgets(
      'Given a large text scale, When the artifact is laid out, Then it does not '
      'overflow',
      (tester) async {
        // The export pins `TextScaler.noScaling` because the card is a fixed size; the
        // preview has to pin it too, or the one screen whose job is to show the reader
        // what they are about to send is the one screen showing them something else.
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          await _scoped(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              // Copied from the ambient data rather than built fresh: a bare
              // `MediaQueryData` has a zero size, and a zero-size screen would let this
              // pass without ever laying the card out against a real one.
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: ShareCardPage(
                    args: ShareCardArgs(
                      books: [
                        _read('a', authors: const ['Author One']),
                        _read('b', authors: const ['Author One']),
                        _read('c', authors: const ['Author Two']),
                      ],
                      displayName: '독서하는 사람',
                      memberSince: DateTime(2026, 6, 26),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(kShareCardArtKey)),
          kShareableCardSize,
        );
      },
    );
  });

  group('framing', () {
    testWidgets(
      'Given the screen opens, When nothing has been touched, Then the card is '
      'floating on a ground',
      (tester) async {
        // `sh-open`'s arrival state. The ground is what makes the card read as an
        // object being held out rather than as a screenshot of one.
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(
          tester
              .widget<FramedShareableCard>(find.byType(FramedShareableCard))
              .framing,
          CardFraming.float,
        );
      },
    );

    testWidgets(
      'Given Float, When the toggle is pressed, Then the framing flips and flips back',
      (tester) async {
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        CardFraming current() => tester
            .widget<FramedShareableCard>(find.byType(FramedShareableCard))
            .framing;

        await tester.tap(find.byKey(kShareCardFramingKey));
        await tester.pumpAndSettle();
        expect(current(), CardFraming.fill);

        await tester.tap(find.byKey(kShareCardFramingKey));
        await tester.pumpAndSettle();
        expect(current(), CardFraming.float);
      },
    );

    testWidgets(
      'Given the toggle is pressed, When the preview relays out, Then the canvas is '
      'the same size in both positions',
      (tester) async {
        // The finding that removed a second pinned constant: framing changes the
        // ground, never the shape of the file. A reader who toggles must not be handed
        // a differently-proportioned image of the same card.
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));
        final floated = tester.getSize(find.byKey(kShareCardArtKey));

        await tester.tap(find.byKey(kShareCardFramingKey));
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byKey(kShareCardArtKey)), floated);
        expect(floated, framedCardSize);
      },
    );

    testWidgets(
      'Given covers still decoding, When the placeholder is drawn, Then it carries '
      'the chosen framing',
      (tester) async {
        // Otherwise the artifact would change shape at the moment it appears, which is
        // the jump the placeholder exists to prevent.
        await pumpPage(
          tester,
          args: ShareCardArgs(
            books: [_read('a', thumbnail: 'https://example.test/a.jpg')],
          ),
        );

        expect(
          tester
              .widget<FramedShareableCard>(find.byType(FramedShareableCard))
              .framing,
          CardFraming.float,
        );

        await landCovers(tester);
      },
    );
  });

  group('candlelight', () {
    testWidgets(
      'Given the screen opens, When nothing has been touched, Then the card is in '
      'daylight',
      (tester) async {
        // Candlelight is a reveal, and something has to be revealed *from*.
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(
          tester
              .widget<ShareableLibraryCard>(find.byType(ShareableLibraryCard))
              .lighting,
          CardLighting.daylight,
        );
      },
    );

    testWidgets(
      'Given daylight, When the pill is pressed, Then the card is lit and the ground '
      'goes with it',
      (tester) async {
        // The ground too, because the chrome and the card are one scene: cool grey chrome
        // around a card in a dim room reads as two images stacked.
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        await tester.tap(find.byKey(kShareCardCandleKey));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ShareableLibraryCard>(find.byType(ShareableLibraryCard))
              .lighting,
          CardLighting.candlelight,
        );
        expect(
          tester
              .widget<FramedShareableCard>(find.byType(FramedShareableCard))
              .groundColors,
          [kCandleGroundTop, kCandleGroundBottom],
        );
      },
    );

    testWidgets(
      'Given the card is lit, When the pill is pressed again, Then it goes back to '
      'daylight',
      (tester) async {
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        await tester.tap(find.byKey(kShareCardCandleKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(kShareCardCandleKey));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ShareableLibraryCard>(find.byType(ShareableLibraryCard))
              .lighting,
          CardLighting.daylight,
        );
      },
    );

    testWidgets(
      'Given the card is lit, When the canvas is measured, Then the light has not '
      'changed its size',
      (tester) async {
        // The other half of "one pinned size": neither control is allowed to change the
        // shape of the file.
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));
        await tester.tap(find.byKey(kShareCardCandleKey));
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byKey(kShareCardArtKey)), framedCardSize);
      },
    );

    testWidgets(
      'Given covers still decoding, When the pill is pressed, Then the placeholder is '
      'lit too',
      (tester) async {
        await pumpPage(
          tester,
          args: ShareCardArgs(
            books: [_read('a', thumbnail: 'https://example.test/a.jpg')],
          ),
        );

        await tester.tap(find.byKey(kShareCardCandleKey));
        await tester.pump();

        expect(
          tester
              .widget<FramedShareableCard>(find.byType(FramedShareableCard))
              .lighting,
          CardLighting.candlelight,
        );

        await landCovers(tester);
      },
    );
  });

  group('the conditional destination', () {
    testWidgets(
      'Given Instagram is installed, When the screen assembles, Then Stories appears',
      (tester) async {
        // The probe is resolved once, while the covers precache, so the slot is either there
        // when the reader looks or never — it does not appear under their thumb.
        instagramInstalledProbe = () async => true;
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(find.byKey(kShareDestinationStoriesKey), findsOneWidget);
      },
    );

    testWidgets(
      'Given Instagram is absent, When the screen assembles, Then the row is one slot '
      'shorter',
      (tester) async {
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(find.byKey(kShareDestinationStoriesKey), findsNothing);
        expect(find.byKey(kShareCardMoreKey), findsOneWidget);
      },
    );

    testWidgets(
      'Given the probe fails, When the screen assembles, Then the screen still finishes',
      (tester) async {
        // A probe that throws must not leave the reader on an assembling screen forever —
        // the destination it governs is the least important thing on it.
        instagramInstalledProbe = () async => throw StateError('no channel');
        await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

        expect(find.byKey(kShareCardArtKey), findsOneWidget);
        expect(find.byKey(kShareDestinationStoriesKey), findsNothing);
      },
    );
  });

  group('dismissal', () {
    testWidgets(
      'Given the screen was pushed, When dismiss is tapped, Then it pops',
      (tester) async {
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          await _scoped(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ShareCardPage(
                        args: ShareCardArgs(books: [_read('a')]),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(ShareCardPage), findsOneWidget);

        await tester.tap(find.byKey(kShareCardCloseKey));
        await tester.pumpAndSettle();

        expect(find.byType(ShareCardPage), findsNothing);
        expect(find.text('open'), findsOneWidget);
      },
    );
  });

  group('the route the sheet pushes', () {
    testWidgets('Given the Card sheet, When share is tapped, Then it pushes the preview with '
        'the sheet\'s own scope and reader', (tester) async {
      // The sheet no longer exports directly, and the risk in that change is that it
      // pushes a *different* card from the one it is showing. So what is asserted is
      // the payload, field by field, rather than merely that something was pushed.
      Route<dynamic>? pushed;
      final books = [
        _read('a', finish: DateTime(2026, 4, 2)),
        _read('b', finish: DateTime(2025, 4, 2)),
      ];

      tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Intercepted rather than routed through `AppRoutes`, so the assertion is
          // about what the sheet asks for and does not depend on the page building.
          onGenerateRoute: (settings) {
            final route = MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const SizedBox.shrink(),
            );
            if (settings.name == AppRoutes.shareCard) pushed = route;
            return route;
          },
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox.expand()),
                LibraryCardSheet(
                  books: books,
                  filterYear: 2026,
                  username: '독서하는 사람',
                  handle: 'paper_fox_412',
                  memberSince: DateTime(2026, 6, 26),
                  maxExtent: _surface.height,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LibraryCardShareButton));
      await tester.pumpAndSettle();

      expect(pushed, isNotNull);
      final args = pushed!.settings.arguments as ShareCardArgs;
      expect(args.year, 2026);
      expect(args.displayName, '독서하는 사람');
      expect(args.memberSince, DateTime(2026, 6, 26));
      // The whole unfiltered list, because the page applies the year itself — the
      // one rule that keeps the covers and the hero figure from disagreeing.
      expect(args.books, books);
      // **Two identities, two jobs.** The display name goes in the record, in its own
      // script; the handle goes in the strip, which is Latin-only by construction. Both
      // travel, and confusing them is what would put `08269F2D` on somebody's card.
      expect(args.handle, 'paper_fox_412');
    });
  });

  // How the screen arrives and what its chrome is made of.
  //
  // Neither claim here can be seen by any other test in this file: a route's
  // transition and a button's *class* are both invisible to assertions about what is
  // on screen, and the one failure mode that matters most — an SF Symbol name that
  // does not exist — cannot be seen on this platform at all. `flutter test` reports
  // Android, so the glass rendering never runs and the symbol string is never handed
  // to anything that would reject it. Pinning the strings is the only guard short of
  // a device.
  group('presentation', () {
    test('Given the routing table, When it is read, Then it does not hold the '
        'preview', () {
      // **This is the silent-revert guard.** `MaterialApp` consults `routes` first and
      // falls through to `onGenerateRoute` only for a name the table does not hold, so
      // an entry in both would not conflict, would not throw, and would not look
      // wrong — the table would simply win and the screen would go back to sliding in
      // from the trailing edge. Nothing else in the suite would notice.
      expect(AppRoutes.routes.containsKey(AppRoutes.shareCard), isFalse);
      expect(
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.shareCard),
        ),
        isNotNull,
      );
    });

    test(
      'Given any name the table owns, When generated, Then the table keeps it',
      () {
        // Returning a route for a name the table already holds would be unreachable
        // code; returning one for an unknown name would swallow the framework's own
        // unknown-route handling.
        for (final name in AppRoutes.routes.keys) {
          expect(
            AppRoutes.onGenerateRoute(RouteSettings(name: name)),
            isNull,
            reason: name,
          );
        }
        expect(
          AppRoutes.onGenerateRoute(const RouteSettings(name: '/not_a_route')),
          isNull,
        );
      },
    );

    test('Given the preview route, When generated, Then it rises from the bottom '
        'and carries its arguments', () {
      const args = ShareCardArgs(year: 2026);
      final route = AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.shareCard, arguments: args),
      );

      // **A full-screen cover, not a page sheet.** Both rise from the bottom, which is
      // why the first build of this used `CupertinoSheetRoute` and looked right in a
      // still screenshot. A sheet is `UIModalPresentationPageSheet`: it stops short of
      // the top and scales the page behind it down into the iOS 18 stacked-card
      // effect. Flighty's Passport share, which this screen copies, covers everything
      // and leaves the app underneath still.
      expect(route, isA<CupertinoPageRoute<void>>());
      final page = route! as CupertinoPageRoute<void>;
      expect(page.fullscreenDialog, isTrue);
      // Opaque, so there is nothing behind it to see. A sheet is not.
      expect(page.opaque, isTrue);

      // Still a `PageRoute`, which is the whole reason the floating tab bar keeps
      // hiding for this screen without anything matching on the route's name.
      expect(route, isA<PageRoute<void>>());
      // And it reads as a *page* rather than a modal to `ShellRouteObserver`, which
      // sniffs type names for these three. Same arrangement as `scanBook`. The sheet
      // version matched "Sheet" and so also bumped the Liquid Glass halo counter;
      // asserted here because that difference is bought with a string.
      final typeName = route.runtimeType.toString();
      expect(typeName, isNot(contains('Sheet')));
      expect(typeName, isNot(contains('Popup')));
      expect(typeName, isNot(contains('Dialog')));

      // The arguments have to survive the hand-off: the page reads them back out of
      // `ModalRoute.of(context).settings.arguments`, and losing them here is a card
      // with no covers on it.
      expect(route.settings.arguments, same(args));
    });

    test('Given the preview route, When it covers the app, Then the page below is not '
        'animated', () {
      // **The regression this exists for is visible, and no other assertion sees it.**
      // A page sheet scales and dims whatever is underneath; a full-screen cover must
      // leave it perfectly still. `canTransitionFrom` is the framework hook that
      // decides, and it is false only because `fullscreenDialog` is set — so this
      // fails the moment the route type changes back to something sheet-like.
      final route =
          AppRoutes.onGenerateRoute(
                const RouteSettings(name: AppRoutes.shareCard),
              )!
              as CupertinoPageRoute<void>;
      final below = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );

      expect(route.canTransitionFrom(below), isFalse);
      // The other half of the same guard, and the reason the two are asserted
      // together: `CupertinoPageRoute` reports a non-null `delegatedTransition` even
      // for a fullscreen dialog, which is how an incoming route animates the outgoing
      // one. It cannot bite here because `canTransitionTo` short-circuits on
      // `fullscreenDialog` first — but that is the framework's `&&` protecting us, not
      // anything this app controls, so it is pinned.
      expect(below.canTransitionTo(route), isFalse);
    });

    testWidgets(
      'Given the real wiring, When the preview is pushed by name, Then it '
      'builds with its scope',
      (tester) async {
        // End to end through `AppRoutes` rather than the `args:` seam, because the seam
        // is exactly what these three lines are not allowed to rely on.
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        final navigator = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          await _scoped(
            MaterialApp(
              navigatorKey: navigator,
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              onGenerateRoute: AppRoutes.onGenerateRoute,
              home: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        );

        navigator.currentState!.pushNamed(
          AppRoutes.shareCard,
          arguments: ShareCardArgs(
            books: [_read('a', finish: DateTime(2026, 4, 2))],
            year: 2026,
          ),
        );
        // One frame to mount the route, then past the rise so the page is settled.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(ShareCardPage), findsOneWidget);
        expect(find.text('Your 2026 Library Card'), findsOneWidget);
        await landCovers(tester);
      },
    );

    testWidgets('Given the top bar, When it is drawn, Then both controls are glass', (
      tester,
    ) async {
      await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

      // `AdaptiveIconButton`, not `IconButton`: native Liquid Glass on iOS 26 and the
      // Material fallback everywhere else. Under `flutter test` the target platform
      // reports Android, so what actually renders here is always the fallback — which
      // is precisely why this asserts the widget rather than anything painted.
      expect(
        tester.widget(find.byKey(kShareCardCloseKey)),
        isA<AdaptiveIconButton>(),
      );
      expect(
        tester.widget(find.byKey(kShareCardFramingKey)),
        isA<AdaptiveIconButton>(),
      );
    });

    testWidgets('Given the top bar, When it is drawn, Then the SF Symbols are the '
        'verified names', (tester) async {
      // **A symbol name that does not exist is discarded silently**, leaving an empty
      // glass circle — see `native_glass.dart`, which warns about this twice. These
      // three were checked against the iOS 26.5 simulator runtime's own
      // `symbol_order.plist` rather than recalled. Pinning them means a rename has to
      // go and check the catalog again instead of guessing.
      await pumpPage(tester, args: ShareCardArgs(books: [_read('a')]));

      expect(
        tester
            .widget<AdaptiveIconButton>(find.byKey(kShareCardCloseKey))
            .symbol,
        'xmark',
      );

      // Float on arrival: a portrait card with an inset fill.
      expect(
        tester
            .widget<AdaptiveIconButton>(find.byKey(kShareCardFramingKey))
            .symbol,
        'inset.filled.rectangle.portrait',
      );

      await tester.tap(find.byKey(kShareCardFramingKey));
      await tester.pump();

      // Fill: the same portrait shape with the whole canvas filled.
      expect(
        tester
            .widget<AdaptiveIconButton>(find.byKey(kShareCardFramingKey))
            .symbol,
        'rectangle.portrait.fill',
      );
    });
  });
}
