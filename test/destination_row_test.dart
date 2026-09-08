// Tests for the destination row, the payload it hands over, and the first measurement in
// this app.
//
// **Three of the four drawn slots are real; the fourth is absent, and that asymmetry is
// what most of this file is about.** Stories, Photos and More are built. The *messenger* is
// not: Android could target KakaoTalk with an explicit intent but iOS cannot target an app
// from the share sheet at all, so it would work on one platform and silently fall back to
// the same sheet as `More` on the other. A slot wearing the Messages icon that opens the
// platform sheet is a lie about what pressing it does, so it is not drawn.
//
// **Stories is conditional rather than optional**, which is a stronger claim and is tested
// as one: the slot is absent when Instagram is not installed, and absent while the answer
// is still unknown, because offering a destination that might not work is worse than
// offering one fewer.
//
// Every hand-off crosses a platform channel, so all three are reached through the seams in
// `card_destinations.dart`. A test that let a real channel through would fail on
// `MissingPluginException` before it asserted anything.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/pages/share_card_page.dart';
import 'package:bookworm_friends/services/analytics.dart';
import 'package:bookworm_friends/services/card_destinations.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_framing.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

import 'support/prefs.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_destination_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_library_card.dart';

Future<void> _pumpRow(
  WidgetTester tester, {
  required bool enabled,
  bool instagramInstalled = true,
  CardLighting lighting = CardLighting.daylight,
  Locale locale = const Locale('en'),
  ValueChanged<Rect?>? onMore,
  VoidCallback? onStories,
  VoidCallback? onPhotos,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ShareDestinationRow(
            enabled: enabled,
            instagramInstalled: instagramInstalled,
            lighting: lighting,
            onMore: onMore ?? (_) {},
            onStories: onStories ?? () {},
            onPhotos: onPhotos ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  _handOffTests();

  group('the row', () {
    testWidgets(
      'Given the covers have landed, When the row is drawn, Then the platform slot is '
      'live',
      (tester) async {
        await _pumpRow(tester, enabled: true);

        expect(find.byKey(kShareDestinationMoreKey), findsOneWidget);
        expect(find.text('More'), findsOneWidget);
        expect(
          tester.widget<InkWell>(find.byKey(kShareDestinationMoreKey)).onTap,
          isNotNull,
        );
      },
    );

    testWidgets(
      'Given the card is still assembling, When the row is drawn, Then it is present '
      'and inert',
      (tester) async {
        // Present, because the row's height is part of the screen's layout and a row
        // that appeared once the covers landed would move the artifact the reader is
        // looking at. Inert, because a share started before the covers decode exports
        // the holes.
        await _pumpRow(tester, enabled: false);

        for (final key in const [
          kShareDestinationStoriesKey,
          kShareDestinationPhotosKey,
          kShareDestinationMoreKey,
        ]) {
          expect(find.byKey(key), findsOneWidget);
          expect(tester.widget<InkWell>(find.byKey(key)).onTap, isNull);
        }
      },
    );

    testWidgets(
      'Given Korean, When the row is drawn, Then the label is Korean',
      (tester) async {
        await _pumpRow(tester, enabled: true, locale: const Locale('ko'));

        expect(find.text('더 보기'), findsOneWidget);
      },
    );

    testWidgets(
      'Given Instagram is installed, When the row is drawn, Then Stories leads it',
      (tester) async {
        // First because it is the only surface here that reaches people who do not already
        // know you — the others reach people you have already chosen.
        await _pumpRow(tester, enabled: true);

        expect(find.byType(ShareDestination), findsNWidgets(3));
        final labels = tester
            .widgetList<ShareDestination>(find.byType(ShareDestination))
            .map((slot) => slot.label)
            .toList();
        expect(labels, ['Stories', 'Photos', 'More']);
      },
    );

    testWidgets(
      'Given Instagram is not installed, When the row is drawn, Then Stories is absent '
      'and the rest survive',
      (tester) async {
        // Exactly why a screenshot of Flighty's own row shows three destinations on one
        // device and four on another — which is the thing that misled an earlier reading of
        // it into concluding Stories did not exist.
        await _pumpRow(tester, enabled: true, instagramInstalled: false);

        expect(find.byKey(kShareDestinationStoriesKey), findsNothing);
        expect(find.byKey(kShareDestinationPhotosKey), findsOneWidget);
        expect(find.byKey(kShareDestinationMoreKey), findsOneWidget);
      },
    );

    testWidgets(
      'Given the messenger cannot be built, When the row is drawn, Then it is absent '
      'rather than faked',
      (tester) async {
        // The rule, asserted so that adding a slot means adding the channel behind it. A
        // `Messages` tile that opens the same platform sheet as `More` is a lie about what
        // pressing it does.
        await _pumpRow(tester, enabled: true);

        expect(find.text('Messages'), findsNothing);
        expect(find.text('KakaoTalk'), findsNothing);
      },
    );

    testWidgets(
      'Given a press, When the slot reports back, Then it hands over its own rect',
      (tester) async {
        // The iPad popover has to be anchored to whatever was tapped, and "whatever was
        // tapped" is now a destination rather than the header button that started the
        // journey.
        Rect? origin;
        await _pumpRow(tester, enabled: true, onMore: (rect) => origin = rect);

        await tester.tap(find.byKey(kShareDestinationMoreKey));
        await tester.pumpAndSettle();

        expect(origin, isNotNull);
        expect(origin!.width, greaterThan(0));
        expect(origin!.height, greaterThan(0));
      },
    );

    testWidgets(
      'Given candlelight, When the row is drawn, Then it is lit with the rest of the '
      'screen',
      (tester) async {
        await _pumpRow(
          tester,
          enabled: true,
          lighting: CardLighting.candlelight,
        );

        final label = tester.widget<Text>(find.text('More'));
        expect(label.style!.color, isNot(const Color(0xFF212529)));
      },
    );

    testWidgets('Given three slots, When the row is laid out, Then the tiles do not '
        'touch', (tester) async {
      // **The tiles shipped flush.** They are fixed squares placed straight into a
      // `Row`, so the only thing between two of them was the pair of rounded corners
      // where they met and the row read as one segmented control. Measured rather than
      // asserted on the constant alone: `spacing` on the wrong widget, or a slot that
      // grows to fit its label, both leave the constant correct and the gap wrong.
      await _pumpRow(tester, enabled: true);

      final stories = tester.getRect(find.byKey(kShareDestinationStoriesKey));
      final photos = tester.getRect(find.byKey(kShareDestinationPhotosKey));
      final more = tester.getRect(find.byKey(kShareDestinationMoreKey));

      // Left to right in the order the row declares them.
      expect(stories.right, lessThan(photos.left));
      expect(photos.right, lessThan(more.left));

      // **Asserted between slots, not between tiles, and the first draft of this test
      // got it wrong.** `Row.spacing` separates the row's children, and a child here is
      // the tile *and its label*, so the slot is as wide as whichever is wider. Under
      // `flutter test` that is always the label: the font is Ahem, where every glyph is
      // one em, which makes `Stories` about 80pt against a 56pt tile. Measuring the tile
      // gap therefore measured the test font and read 36.4 rather than 16.
      final slots = find.byType(ShareDestination);
      final slotRects = [
        for (var i = 0; i < 3; i++) tester.getRect(slots.at(i)),
      ];
      expect(slotRects[1].left - slotRects[0].right, kShareDestinationGap);
      expect(slotRects[2].left - slotRects[1].right, kShareDestinationGap);

      // Between the tiles the gap is a *floor*, which is the honest claim: a label wider
      // than its tile pushes neighbours further apart, never closer. That is the
      // trade-off the widget takes deliberately rather than clamping the label and
      // buying even gaps with an ellipsis.
      expect(
        photos.left - stories.right,
        greaterThanOrEqualTo(kShareDestinationGap),
      );
      expect(
        more.left - photos.right,
        greaterThanOrEqualTo(kShareDestinationGap),
      );

      // Still one row, not a stack: a gap large enough to break the grouping would
      // show up here as slots on different lines.
      expect(stories.top, photos.top);
      expect(photos.top, more.top);
    });
  });

  group('the payload', () {
    test(
      'Given a year, When the file is named, Then the name says whose card it is',
      () {
        // Some targets print the filename next to the image, so on a card whose whole
        // design problem is "nothing points home", this is one more place the name gets
        // read. The old name was `library_card.png`.
        expect(cardShareFileName(2026), 'libstack-library-card-2026.png');
        expect(cardShareFileName(2026), contains('libstack'));
      },
    );

    test(
      'Given all time, When the file is named, Then it does not claim a year',
      () {
        expect(cardShareFileName(0), 'libstack-library-card.png');
        expect(cardShareFileName(0), isNot(contains('0')));
      },
    );

    test(
      'Given two scopes, When both are shared, Then the files do not collide',
      () {
        // Not tidiness: a reader who shares 2026 and then all-time while the first is
        // still in a chat's upload queue would otherwise have the second overwrite it.
        expect(cardShareFileName(0), isNot(cardShareFileName(2026)));
        expect(cardShareFileName(2025), isNot(cardShareFileName(2026)));
      },
    );
  });

  group('measurement', () {
    late RecordingAnalyticsSink sink;

    setUp(() {
      sink = RecordingAnalyticsSink();
      analytics = sink;
    });

    tearDown(() => analytics = const FirebaseAnalyticsSink());

    test(
      'Given a sink, When an event is logged, Then it is recorded with its parameters',
      () async {
        // The seam itself, because this is the app's **first** measurement:
        // `firebase_analytics` has been a declared dependency with zero `logEvent` calls
        // behind it, so nothing established that a widget test can assert on an event
        // without Firebase in the room.
        await analytics.log(kShareOpened, {
          'surface': ShareSurface.preview.name,
          'format': CardFraming.float.name,
          'lighting': CardLighting.candlelight.name,
          'destination': 'more',
        });

        expect(sink[kShareOpened], hasLength(1));
        expect(sink[kShareOpened].single, {
          'surface': 'preview',
          'format': 'float',
          'lighting': 'candlelight',
          'destination': 'more',
        });
      },
    );

    test(
      'Given the two surfaces, When they are named, Then they are told apart',
      () {
        // The parameter that makes this screen falsifiable: does showing the reader the
        // image first make them more or less likely to send it than the library bar's
        // blind hand-off?
        expect(ShareSurface.preview.name, 'preview');
        expect(ShareSurface.libraryBar.name, 'libraryBar');
        expect(ShareSurface.values, hasLength(2));
      },
    );

    test(
      'Given the dimensions, When they are named, Then every one is low-cardinality',
      () {
        // Nothing that identifies a person or a book is ever a parameter, and every
        // value is an enum name rather than free text — which is what keeps the events
        // groupable and keeps a display name out of a dashboard.
        expect(CardFraming.values.map((f) => f.name), ['fill', 'float']);
        expect(CardLighting.values.map((l) => l.name), [
          'daylight',
          'candlelight',
        ]);
      },
    );
  });
}

void _handOffTests() {
  group('the hand-offs', () {
    late RecordingAnalyticsSink sink;
    late List<({String path, Color top, Color bottom})> stories;
    late List<String> saved;
    late List<CardExportRequest> rendered;

    setUp(() {
      sink = RecordingAnalyticsSink();
      analytics = sink;
      stories = [];
      saved = [];
      rendered = [];
      // The render is faked because `flutter test` cannot run it — `toImage` needs
      // `runAsync`, from which a test cannot pump, so the real exporter *hangs* rather than
      // failing. Recording the request instead makes the assertion sharper: what matters is
      // which card each destination asked for.
      exportCardFile = (context, request) async {
        rendered.add(request);
        return '/tmp/${cardShareFileName(request.year)}';
      };
      instagramInstalledProbe = () async => true;
      shareCardToStory =
          ({
            required String imagePath,
            required Color groundTop,
            required Color groundBottom,
          }) async {
            stories.add((
              path: imagePath,
              top: groundTop,
              bottom: groundBottom,
            ));
            return StoryOutcome.shared;
          };
      saveCardToGallery = (path) async {
        saved.add(path);
        return true;
      };
    });

    tearDown(() {
      analytics = const FirebaseAnalyticsSink();
      resetCardDestinations();
      resetCardExporter();
    });

    testWidgets(
      'Given Float is chosen, When Stories is pressed, Then the sticker is the Fill card',
      (tester) async {
        // **The decision the framing task turned on.** Instagram paints the ground itself
        // from the two colours it is handed, so a Float export would put our ground
        // underneath Instagram's — one ground on top of another. The toggle reaches this
        // destination through the ground *colours* instead, which come from the lighting
        // state, and that is the honest amount of control there is over a layer another app
        // owns.
        await _pumpPage(tester);
        expect(_framingOf(tester), CardFraming.float);

        await _settleHandOff(tester, kShareDestinationStoriesKey);

        // Read off the request rather than inferred from the output: this *is* the claim.
        expect(rendered, hasLength(1));
        expect(rendered.single.framing, CardFraming.fill);
        expect(stories, hasLength(1));
        expect(stories.single.top, kCardGroundTop);
        expect(stories.single.bottom, kCardGroundBottom);
        expect(sink[kShareOpened].single['destination'], 'instagram_stories');
        expect(sink[kShareCompleted].single['outcome'], 'shared');
      },
    );

    testWidgets(
      'Given the candle is lit, When Stories is pressed, Then Instagram paints the dark '
      'ground',
      (tester) async {
        // The lighting state is the one thing that does reach Instagram's layer, so it has
        // to reach it correctly: a lit card centred on a daylight-green gradient would be
        // two scenes in one image.
        await _pumpPage(tester);
        await tester.tap(find.byKey(kShareCardCandleKey));
        await tester.pump();

        await _settleHandOff(tester, kShareDestinationStoriesKey);

        expect(rendered.single.lighting, CardLighting.candlelight);
        expect(stories.single.top, kCandleGroundTop);
        expect(stories.single.bottom, kCandleGroundBottom);
        expect(sink[kShareOpened].single['lighting'], 'candlelight');
      },
    );

    testWidgets(
      'Given Photos is pressed, When the card is saved, Then the file is branded and the '
      'outcome logged',
      (tester) async {
        // Photos is the only destination that leaves the reader holding the file, which is
        // why the filename matters most here — some galleries show it.
        await _pumpPage(tester);

        await _settleHandOff(tester, kShareDestinationPhotosKey);

        // Photos exports exactly what is on screen, framing included — unlike Stories,
        // whose ground Instagram owns.
        expect(rendered.single.framing, CardFraming.float);
        expect(saved, hasLength(1));
        expect(saved.single, endsWith(cardShareFileName(0)));
        expect(sink[kShareCompleted].single['outcome'], 'saved');
        expect(sink[kShareCompleted].single['format'], 'float');
      },
    );

    testWidgets(
      'Given the reader refuses the photo permission, When Photos is pressed, Then it is '
      'reported rather than thrown',
      (tester) async {
        // A refused permission is a normal answer, not a fault: the reader said no. It has
        // to be distinguishable from a failure in the dashboard, because one is a product
        // problem and the other is not.
        saveCardToGallery = (path) async => false;
        await _pumpPage(tester);

        await _settleHandOff(tester, kShareDestinationPhotosKey);

        expect(tester.takeException(), isNull);
        expect(sink[kShareCompleted].single['outcome'], 'refused');
      },
    );

    testWidgets(
      'Given Instagram vanished between the probe and the tap, When Stories is pressed, '
      'Then it is reported and not counted as shared',
      (tester) async {
        // Reachable, because a reader can uninstall while this screen is open. The slot was
        // drawn honestly and the hand-off still has to fail honestly.
        shareCardToStory =
            ({
              required String imagePath,
              required Color groundTop,
              required Color groundBottom,
            }) async => StoryOutcome.notInstalled;
        await _pumpPage(tester);

        await _settleHandOff(tester, kShareDestinationStoriesKey);

        expect(tester.takeException(), isNull);
        expect(sink[kShareCompleted].single['outcome'], 'notInstalled');
      },
    );
  });
}

/// Taps a destination and pumps until the hand-off has finished.
///
/// **Fixed pumps rather than `pumpAndSettle`, and not by preference.** Every hand-off puts
/// an indefinite `EasyLoading` spinner up, so a frame is always scheduled while it is on
/// screen and `pumpAndSettle` runs until its own ten-minute timeout. The assertions are on
/// recorded calls rather than on pixels, so a bounded number of frames is all that is
/// needed — enough to carry the microtasks the awaits queue.
Future<void> _settleHandOff(WidgetTester tester, Key destination) async {
  await tester.tap(find.byKey(destination));
  // Short frames first, to carry the microtasks each `await` in the hand-off queues.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Then past `EasyLoading`'s own display duration, which is 2 seconds and leaves a timer
  // behind. The framework fails a test that ends with a timer pending, so a hand-off that
  // reports success or failure to the reader has to be pumped through the toast as well as
  // through the work — the success path needs this and the silent path does not, which is
  // why the first version of this helper passed three tests and failed three.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 500));
}

/// The framing the preview is currently rendering.
CardFraming _framingOf(WidgetTester tester) => tester
    .widget<FramedShareableCard>(find.byType(FramedShareableCard))
    .framing;

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize =
      const Size(400, 900) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      // The display setting is a stored preference, and the page reads it to draw the
      // preview and to build the export request.
      overrides: [await sharedPreferencesOverride()],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => FlutterEasyLoading(child: child!),
        home: ShareCardPage(
          args: ShareCardArgs(
            books: [
              Book(
                id: 'a',
                userId: 'u',
                shelfId: 's',
                isbn: 'a',
                title: 'Book a',
                thumbnail: '',
                status: 2,
                position: 0,
                startDate: DateTime(2026, 3, 4),
                finishDate: DateTime(2026, 3, 10),
                createdAt: DateTime(2024),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Two pumps rather than a settle: the assembling state holds an indefinite progress
  // indicator, so a settle would advance the fake clock until something else stopped it.
  await tester.pump();
  await tester.pump();
}
