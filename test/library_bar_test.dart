// The "My Library" row's trailing control: the reader's avatar.
//
// **There is no share button here any more.** It sat left of the avatar and handed
// over the same PNG the Card tab's own share button exports; the Card sheet keeps
// that entry point, and the top row is back to one control. The absence is pinned
// below rather than merely deleted, because the button had been added to this row
// once already and a test is the only thing that says it stayed out.
//
// The avatar is asserted as a forwarded `AvatarCircle`, not as a rendered photo: the
// bar's whole job there is to hand the profile through, and a photo needs
// `avatarImageProvider` swapped for a fake because the test binding stubs HTTP to
// 400. See `AvatarCircle` for the emoji-first fallback that makes that safe on a
// device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

import 'support/home_page_harness.dart';

List<Book> _readBooks() => [
  testBook('r1', 's1', position: 1, title: 'Dune', status: 2),
];

/// The bar is the `AppBar` at the top of the shell's stack, and scoping to it is
/// what keeps this find from picking up a sheet's own share button.
Finder _barShare() => find.descendant(
  of: find.byType(AppBar),
  matching: find.byIcon(Icons.ios_share),
);

Finder _barProfile() => find.descendant(
  of: find.byType(AppBar),
  matching: find.byType(AvatarCircle),
);

Future<void> _pumpBar(
  WidgetTester tester, {
  List<Book> read = const [],
  List<Profile> following = const [],
  Profile? me,
}) => pumpHome(
  tester,
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref) async => read),
    friendsProvider.overrideWith((ref) async => following),
    if (me != null) profileProvider.overrideWith((ref) async => me),
  ],
);

void main() {
  group('the library bar\'s trailing slot', () {
    testWidgets(
      'Given a book has been read, When the bar renders, Then the avatar is the only '
      'trailing control',
      (tester) async {
        // Sharing lives on the Library Card sheet, which is where the artifact
        // itself is. A second copy in the most permanent row on screen was one
        // entry point too many.
        await _pumpBar(tester, read: _readBooks());

        expect(_barShare(), findsNothing);
        expect(_barProfile(), findsOneWidget);
      },
    );

    testWidgets(
      'Given edit mode, When the bar renders, Then both controls take the platform '
      'material and the confirm one is a tinted check',
      (tester) async {
        // This row was two bare Material controls and a word: an up/down arrow and
        // a `TextButton` reading `Done`. The old finding — that a glass disc beside
        // a text button wins a contest it should lose — was answered by making Done
        // a disc too rather than by keeping the other one bare, so the pair is now
        // glass and the affirmative one is the only fill in the bar.
        await _pumpBar(tester, read: _readBooks());
        await enterEditMode(tester);

        expect(isEditing(), isTrue);

        final controls = tester
            .widgetList<AdaptiveIconButton>(
              find.descendant(
                of: find.byType(AppBar),
                matching: find.byType(AdaptiveIconButton),
              ),
            )
            .toList();
        expect(controls, hasLength(2));

        final shelves = controls.first;
        expect(
          shelves.assetPath,
          kStretchHorizontalIconAsset,
          reason:
              'Lucide stretch-horizontal represents the shelf rows and remains '
              'the scalable Flutter fallback',
        );
        expect(
          shelves.nativeAssetPath,
          kStretchHorizontalIconNativeAsset,
          reason: 'the native glass button uses the reliable raster glyph path',
        );
        expect(
          shelves.prominent,
          isFalse,
          reason: 'managing shelves is the secondary action here',
        );

        final done = controls.last;
        expect(done.symbol, 'checkmark');
        expect(done.icon, Icons.check);
        expect(
          done.prominent,
          isTrue,
          reason: 'the way out is the only filled disc in the row',
        );
        expect(done.tint, isNotNull, reason: 'and the fill is the brand green');
      },
    );

    testWidgets(
      'Given edit mode, When the trailing control is measured, Then it sits where '
      'the avatar it replaced did',
      (tester) async {
        // The bar's right padding was 4 while Done was text, because a `TextButton`
        // carries its own inset. Two discs at that padding would have slid the check
        // 11pt outboard of the avatar, so switching modes visibly shifted the
        // trailing control.
        await _pumpBar(tester, read: _readBooks());
        final atRest = tester
            .getRect(
              find.ancestor(
                of: _barProfile(),
                matching: find.byType(AdaptiveGlassCircle),
              ),
            )
            .right;

        await enterEditMode(tester);

        expect(
          tester
              .getRect(
                find
                    .descendant(
                      of: find.byType(AppBar),
                      matching: find.byType(AdaptiveIconButton),
                    )
                    .last,
              )
              .right,
          moreOrLessEquals(atRest, epsilon: 0.5),
          reason:
              'both are 44pt targets against the same 15pt inset, so the trailing '
              'control does not move when the mode changes',
        );
      },
    );
  });

  group('the library bar\'s avatar', () {
    testWidgets('Given a profile, When the bar renders, Then the avatar wears it', (
      tester,
    ) async {
      // The drawing has the reader's own circle here, the same one the rail's
      // "me" lead draws — not a generic person glyph, which is what this was
      // until photos existed.
      await _pumpBar(
        tester,
        me: Profile(
          id: 'u',
          username: 'tester',
          emoji: '🦋',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );

      final avatar = tester.widget<AvatarCircle>(_barProfile());
      expect(avatar.emoji, '🦋');
      expect(
        avatar.avatarPath,
        isNull,
        reason: 'this profile wears an emoji, so there is no photo to draw',
      );
      expect(
        tester.getSize(_barProfile()),
        const Size(32, 32),
        reason:
            'off glass there is no disc to fill, so the avatar takes the inset '
            'an IconButton would have applied',
      );
      expect(
        avatar.emojiSize,
        isNull,
        reason:
            'left to AvatarCircle, which sizes the glyph at half the diameter — '
            'pinning it made the emoji fill less of the glass disc than it did '
            'of the smaller filled one',
      );
    });

    testWidgets(
      'Given the fallback material, When the avatar renders, Then it is inset inside '
      'its target rather than filling it',
      (tester) async {
        // The pair of sizes is the whole fix, so both halves are pinned. `flutter
        // test` only ever runs the fallback — `useNativeGlass` is false — so the
        // glass half is asserted through the builder below rather than by rendering.
        await _pumpBar(tester);

        expect(tester.widget<AvatarCircle>(_barProfile()).diameter, 32);
      },
    );

    testWidgets('Given the glass material, When the avatar renders, Then it fills the disc '
        'instead of floating in it', (tester) async {
      // **The bug this pair exists for.** One size served both paths, so on glass
      // the photo sat 32pt inside a 44pt disc with a 6pt ring of bare glass around
      // it — a picture dropped onto a button rather than the button. Every other
      // glass control in this bar fills its diameter.
      //
      // Driven through the builder because the rendering cannot be reached here:
      // the glass path needs an iOS 26 host, and the binding reports Android. The
      // builder is the branch, so calling it with `glass: true` is the assertion.
      await _pumpBar(tester);

      final circle = tester.widget<AdaptiveGlassCircle>(
        find.ancestor(
          of: _barProfile(),
          matching: find.byType(AdaptiveGlassCircle),
        ),
      );
      final onGlass =
          circle.builder(
                tester.element(find.byType(AdaptiveGlassCircle).first),
                true,
              )
              as AvatarCircle;

      expect(onGlass.diameter, 44, reason: 'the avatar is the disc');
      expect(
        onGlass.filled,
        isFalse,
        reason: 'an opaque fill at full diameter would hide the glass entirely',
      );
      expect(
        onGlass.emojiSize,
        isNull,
        reason:
            'the glyph scales with the disc: measured, a 16pt emoji filled 50% '
            'of a 44pt disc where the old 32pt circle was 69% — so pinning it '
            'reintroduced the padding this pair exists to remove',
      );
    });

    testWidgets(
      'Given the avatar, When it is tapped, Then the whole 44pt target answers',
      (tester) async {
        // The circle is 32pt but the band's targets are 44pt, so the corner of
        // the button has to be live too — the avatar carries no gesture of its
        // own, precisely so the control around it owns the whole box.
        //
        // Asserted through `AdaptiveGlassCircle`'s box rather than the `IconButton`
        // inside it: the `IconButton` is the fallback path's, and under
        // `flutter test` that is always the path taken. The wrapper is what both
        // paths share.
        await _pumpBar(tester);

        final target = find.ancestor(
          of: _barProfile(),
          matching: find.byType(AdaptiveGlassCircle),
        );
        expect(tester.widget<AdaptiveGlassCircle>(target).onPressed, isNotNull);
        expect(tester.getSize(target), const Size(44, 44));
      },
    );

    testWidgets(
      'Given the fallback material, When the avatar renders, Then it keeps its own fill',
      (tester) async {
        // The half of the glass/fallback split that a widget test can see. On glass
        // the disc *is* the fill and `AvatarCircle` must not paint its opaque
        // `surfaceVariant` over it; off glass there is no disc, so the fill is what
        // keeps an emoji from reading as a loose glyph. `useNativeGlass` is false
        // here, so this pins the second case.
        await _pumpBar(tester);

        expect(tester.widget<AvatarCircle>(_barProfile()).filled, isTrue);
      },
    );
  });
}
