import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:social_story_share/social_story_share.dart' as story;

/// The Meta App ID, sent as `source_application` on every Stories hand-off.
///
/// **Required since January 2023**, and omitting it does not fail quietly: Instagram
/// tells the reader *"The app you shared from doesn't currently support sharing to
/// Stories"*, which reads as our bug rather than as a missing registration. Field reports
/// suggest the value is loosely checked and an arbitrary string often works — that is not
/// a reason to send one, because the check can tighten at any time and the failure is
/// user-visible.
///
/// Not a secret. An App ID is public by design; it identifies the app to Meta and carries
/// no authority on its own, which is why it sits in source beside the URL constants rather
/// than in an environment variable. The App *Secret* is the one that would not belong
/// here, and nothing in this app needs it.
const String kMetaAppId = '1623819535975796';

/// How a Stories hand-off ended.
///
/// **Ours, not the plugin's.** `social_story_share` exposes a `ShareResult` whose name
/// collides with `share_plus`'s, and one of those two is already the return type of the
/// platform-sheet path. Translating at the boundary means the collision is confined to
/// this file and nothing downstream has to alias an import — and it means swapping the
/// plugin out for our own channel later touches this file only.
enum StoryOutcome {
  /// Instagram opened with the card on its composer.
  shared,

  /// Instagram is not installed. Not an error: it is the state the slot is supposed to be
  /// absent for, and reaching it means the install probe and the tap disagreed — which is
  /// possible, because a reader can uninstall between the two.
  notInstalled,

  /// Anything else: an unreadable file, nothing to share, a refused scheme.
  failed,
}

/// Whether Instagram is on the device.
typedef InstagramProbe = Future<bool> Function();

/// Hands a rendered card to the Instagram Stories composer as a *sticker*.
typedef StoryShareFn =
    Future<StoryOutcome> Function({
      required String imagePath,
      required Color groundTop,
      required Color groundBottom,
    });

/// Saves a rendered card to the photo library.
typedef GallerySaveFn = Future<bool> Function(String imagePath);

/// **Swappable, and that is not a nicety.** Every one of these three crosses a platform
/// channel, and a channel under `flutter test` throws `MissingPluginException` — so a
/// widget test that so much as builds the destination row would fail on the install probe
/// alone. The app already uses this seam for exactly this reason twice
/// (`coverImageProvider`, `avatarImageProvider`) and once for measurement (`analytics`);
/// this is the same shape.
InstagramProbe instagramInstalledProbe = _probeInstagram;
StoryShareFn shareCardToStory = _shareToStory;
GallerySaveFn saveCardToGallery = _saveToGallery;

/// Restores the real implementations. For a test's `tearDown`.
void resetCardDestinations() {
  instagramInstalledProbe = _probeInstagram;
  shareCardToStory = _shareToStory;
  saveCardToGallery = _saveToGallery;
}

Future<bool> _probeInstagram() async {
  try {
    return await story.SocialStoryShare.isInstalled(story.SocialApp.instagram);
  } catch (_) {
    // A probe that throws is a slot that should not be drawn, not a screen that should
    // fail. On iOS this needs `instagram-stories` in `LSApplicationQueriesSchemes` or it
    // answers false whatever is installed, which is a configuration bug that would
    // otherwise present as "Instagram is never installed".
    return false;
  }
}

/// The sticker route, deliberately — not `backgroundImagePath`.
///
/// **This is the decision the whole framing task turned on.** A background asset is
/// full-bleed and has to be 9:16; a *sticker* is composited by Instagram onto a ground it
/// paints from [groundTop] and [groundBottom], and lands centred, scalable and movable.
/// That is what Flighty's passport does, it is why there is no second pinned export size
/// (see `framedCardSize`), and it is why the card handed over here should be the **Fill**
/// render: baking our own ground into the sticker would put one ground on top of another.
///
/// The rounded corners that make Fill's PNG partly transparent — a liability in a
/// messenger that flattens onto black — are an asset here: they are what makes the card
/// read as an object lying on Instagram's gradient rather than as a screenshot pasted over
/// it.
Future<StoryOutcome> _shareToStory({
  required String imagePath,
  required Color groundTop,
  required Color groundBottom,
}) async {
  try {
    final result = await story.SocialStoryShare.shareToInstagramStory(
      appId: kMetaAppId,
      stickerImagePath: imagePath,
      backgroundTopColor: groundTop,
      backgroundBottomColor: groundBottom,
      // No `contentUrl`. It is the one parameter that would put a link in the payload,
      // and the whole phase turns on the share being the image and nothing else — the
      // return path is printed on the card instead. A tappable attribution sticker is
      // also subject to Meta's own review rules, which is a second reason not to.
    );
    return switch (result) {
      story.ShareResult.success => StoryOutcome.shared,
      story.ShareResult.appNotInstalled => StoryOutcome.notInstalled,
      _ => StoryOutcome.failed,
    };
  } catch (_) {
    return StoryOutcome.failed;
  }
}

/// Saves to the photo library, reporting success rather than throwing.
///
/// `Gal` raises `GalException` for a refused permission, which is a normal answer rather
/// than a fault: the reader said no. The caller shows a message either way, so a bool is
/// the whole of what it needs — and swallowing here keeps a denied permission from
/// surfacing as a crash report.
Future<bool> _saveToGallery(String imagePath) async {
  try {
    await Gal.putImage(imagePath);
    return true;
  } on GalException catch (_) {
    return false;
  } catch (_) {
    return false;
  }
}
