import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

/// Where the exported card can go.
///
/// **Three of the four drawn slots, ordered by what each is for.** Stories reaches people
/// who do not already know you, which is why it leads; Photos is the escape hatch every
/// other destination can be reached through, and the only one that leaves the reader
/// holding the file; More is the platform. Stories is **conditional, not optional** — absent
/// when Instagram is not installed, which is exactly why a screenshot of Flighty's own row
/// shows three destinations on one device and four on another.
///
/// **The messenger is the one that stays absent, and it is a platform asymmetry rather than
/// a missing package.** Messages, or KakaoTalk on a Korean-*language* device, needs a
/// hand-off to a *named* app: Android can do that with an explicit `ACTION_SEND` to
/// `com.kakao.talk`, and iOS cannot target an app from the share sheet at all. So it would
/// work on one platform and silently fall back to the same sheet as `More` on the other —
/// and a tile wearing the Messages icon that opens the platform sheet is a lie about what
/// pressing it does. iOS would need `kakao_flutter_sdk_share`, whose `uploadImage` puts the
/// PNG on **Kakao's** server for up to 100 days; that means the hosted-URL requirement which
/// cut the public `cards` bucket from this phase could be met without a bucket of ours, but
/// a third-party upload is a decision rather than an implementation detail. Image-attached
/// SMS is covered by no package at all; iOS needs `MFMessageComposeViewController`.
///
/// Every hand-off is a **local** file, and nothing is uploaded — so the visibility rule
/// does not reach this row. That was not true of an earlier design, where routing Kakao
/// through its share SDK dragged in a public bucket, a domain and a hole in the privacy
/// model. (This used to name `is_private`, which no longer exists: visibility is
/// friendship now. The point survives the column — a card you export is yours to hand
/// over, and no policy governs a file on your own device.)
/// Corner radius of a destination tile, and therefore also [kShareDestinationGap].
const double kShareDestinationRadius = 16;

/// Clear space between two adjacent destination tiles.
///
/// **The tiles used to sit flush.** They are fixed 56pt squares dropped straight into a
/// `Row`, which gave them no gap at all — the only thing separating two of them was the
/// pair of rounded corners where they met, so the row read as one segmented control
/// rather than as three separate places the card can go.
///
/// Equal to [kShareDestinationRadius] on purpose: a gap the same size as the curve that
/// forms it makes the negative space read at the scale of the shapes around it. Smaller
/// and the corners still dominate; much larger and three tiles stop reading as one row.
///
/// This is the gap between *slots*, and a slot is as wide as the wider of its tile and
/// its label. Both locales' labels are narrower than 56pt at normal text scale, so in
/// practice it is the gap between the tiles. Under a large accessibility text scale a
/// label can exceed the tile and push its neighbours further apart — looser, never
/// tighter, which is why the label is not clamped. Clamping it would buy even gaps with
/// an ellipsis on a word like `Stories`.
const double kShareDestinationGap = kShareDestinationRadius;

class ShareDestinationRow extends StatefulWidget {
  /// False while the covers are still decoding. A share started then would export the
  /// holes where they should be.
  final bool enabled;

  /// Whether the Stories slot is drawn at all.
  ///
  /// **Conditional, not optional, and it is answered before the row is built.** The probe
  /// crosses a platform channel and cannot be awaited during `build`, so the page resolves
  /// it while the covers precache and hands the answer down — which also means the slot
  /// never appears and then vanishes. Null is "not answered yet", drawn the same as false:
  /// a slot that might not work must not be offered.
  final bool instagramInstalled;

  final CardLighting lighting;

  /// Handed the pressed slot's global rect, which is what anchors the popover on iPad.
  final ValueChanged<Rect?> onMore;

  final VoidCallback onStories;
  final VoidCallback onPhotos;

  const ShareDestinationRow({
    super.key,
    required this.enabled,
    required this.lighting,
    required this.onMore,
    required this.onStories,
    required this.onPhotos,
    this.instagramInstalled = false,
  });

  @override
  State<ShareDestinationRow> createState() => _ShareDestinationRowState();
}

class _ShareDestinationRowState extends State<ShareDestinationRow> {
  final _moreKey = GlobalKey();

  Rect? _originOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: kShareDestinationGap,
        children: [
          // Ordered by what each is for, and Stories is first because it is the only
          // surface here that reaches people who do not already know you.
          if (widget.instagramInstalled)
            ShareDestination(
              buttonKey: kShareDestinationStoriesKey,
              icon: Icons.auto_stories_outlined,
              label: l10n.shareCardDestinationStories,
              enabled: widget.enabled,
              lighting: widget.lighting,
              onPressed: widget.onStories,
            ),
          ShareDestination(
            buttonKey: kShareDestinationPhotosKey,
            icon: Icons.photo_library_outlined,
            label: l10n.shareCardDestinationPhotos,
            enabled: widget.enabled,
            lighting: widget.lighting,
            onPressed: widget.onPhotos,
          ),
          ShareDestination(
            slotKey: _moreKey,
            buttonKey: kShareDestinationMoreKey,
            icon: Icons.more_horiz,
            label: l10n.shareCardDestinationMore,
            enabled: widget.enabled,
            lighting: widget.lighting,
            onPressed: () => widget.onMore(_originOf(_moreKey)),
          ),
        ],
      ),
    );
  }
}

/// `Stories`: the Instagram composer, drawn only when Instagram is installed.
const Key kShareDestinationStoriesKey = Key('share-card-dest-stories');

/// `Photos`: the photo library.
const Key kShareDestinationPhotosKey = Key('share-card-dest-photos');

/// `More`: the platform sheet.
const Key kShareDestinationMoreKey = Key('share-card-dest-more');

/// One destination: a tile with a label under it.
class ShareDestination extends StatelessWidget {
  /// On the tile, for measuring the rect the iPad popover is anchored to. Only `More`
  /// needs one — the other two open an app rather than a popover.
  final Key? slotKey;

  /// On the `InkWell`, so a test presses the control and can read whether it is live.
  final Key buttonKey;

  final IconData icon;
  final String label;
  final bool enabled;
  final CardLighting lighting;
  final VoidCallback onPressed;

  const ShareDestination({
    super.key,
    this.slotKey,
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.lighting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lit = lighting == CardLighting.candlelight;
    return Opacity(
      // Dimmed rather than removed while assembling: the row's height is part of the
      // screen's layout, and a row that appeared once the covers landed would move the
      // artifact the reader is looking at.
      opacity: enabled ? 1 : 0.32,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            key: slotKey,
            dimension: 56,
            child: Material(
              color: lit
                  ? Colors.white.withValues(alpha: 0.14)
                  : colors.surface,
              borderRadius: BorderRadius.circular(kShareDestinationRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: buttonKey,
                onTap: enabled ? onPressed : null,
                child: Icon(
                  icon,
                  size: 26,
                  color: shareChromeInk(colors, lighting: lighting),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: shareChromeMutedInk(colors, lighting: lighting),
            ),
          ),
        ],
      ),
    );
  }
}
