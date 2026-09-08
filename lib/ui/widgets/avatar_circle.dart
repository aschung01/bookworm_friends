import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/services/avatar_image.dart';

/// The glyph an avatar wears when its profile is in emoji mode but has not
/// chosen one.
///
/// One constant because there used to be three answers, in three files, none of
/// them aware of the others. Books, matching the app's own mark.
const String kDefaultAvatarEmoji = '📚';

/// A person's avatar. Two mutually exclusive modes, not two layers.
///
/// **Emoji mode** ([avatarPath] null) draws the profile's emoji, or
/// [kDefaultAvatarEmoji]. Costs nothing and never touches the network.
///
/// **Photo mode** ([avatarPath] set) draws the photo, and while it is loading or
/// if it fails, a neutral placeholder — **deliberately not the emoji**. An
/// earlier draft used the emoji as the placeholder, on the theory that an avatar
/// should never depend on the network. That was wrong about what the emoji means:
/// showing it in place of a photo flashes a *different identity* at the viewer,
/// who then cannot tell whether this person is an emoji person or a photo person
/// whose picture has not arrived. The neutral placeholder says "a photo, not yet"
/// and cannot be mistaken for a choice.
///
/// The consequence, accepted knowingly: for profiles in photo mode the avatar
/// does depend on the network. Emoji-mode profiles — currently about two thirds
/// of active users — are unaffected.
///
/// Every avatar in the app goes through this widget. Only two of the six sites
/// used to: the other four drew a bare `Text` in a circle, and between them the
/// six disagreed three ways about the fallback glyph (`📚`, `📖`, and the empty
/// string). That was invisible while every avatar was an emoji, and would have
/// become three different answers the moment photos existed.
class AvatarCircle extends StatelessWidget {
  /// The profile's emoji, used only in emoji mode. Null falls back to
  /// [kDefaultAvatarEmoji]; required so that every site says out loud whose
  /// emoji it means.
  final String? emoji;

  /// Storage object path from `profiles.avatar_path`. Non-null puts the avatar in
  /// photo mode, where [emoji] is not drawn at all.
  final String? avatarPath;

  final double diameter;

  /// Defaults to half the [diameter], which is what the 40pt rail avatars have
  /// always used. Passed explicitly where a site had its own ratio.
  final double? emojiSize;

  /// The ring-and-tint treatment for the friend rail's current selection.
  final bool isSelected;

  /// Whether to fill the circle with [AppColors.surfaceVariant].
  ///
  /// False for the one site that draws a bare glyph on the dialog's own
  /// background. A photo is always clipped to the circle regardless, because
  /// there is no such thing as an unfilled photo.
  final bool filled;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AvatarCircle({
    super.key,
    required this.emoji,
    this.avatarPath,
    this.diameter = 40,
    this.emojiSize,
    this.isSelected = false,
    this.filled = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final path = avatarPath;

    // Both non-success states of photo mode land here: loading and failed look
    // the same on purpose, because to a viewer they are the same thing — a photo
    // that is not on screen. Sized against the diameter so it reads as an avatar
    // rather than an error badge.
    final Widget content = path == null
        ? Text(
            emoji ?? kDefaultAvatarEmoji,
            style: TextStyle(fontSize: emojiSize ?? diameter / 2),
          )
        : Image(
            image: avatarImageProvider(path),
            // The photo is square-ish but not guaranteed square: nothing crops
            // on upload, because `cover` inside a circle is the crop.
            fit: BoxFit.cover,
            width: diameter,
            height: diameter,
            frameBuilder: (_, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded || frame != null) return child;
              return _PhotoPending(diameter: diameter);
            },
            errorBuilder: (_, __, ___) => _PhotoPending(diameter: diameter),
          );

    final circle = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? (isSelected
                  ? context.colors.brand.withValues(alpha: 0.15)
                  : context.colors.surfaceVariant)
            : null,
      ),
      // The selection ring is a *foreground* decoration so it paints over the
      // child instead of insetting it. A `border` on the main decoration eats
      // 2pt of the content box on every side, which left a photo 4pt smaller
      // than its circle with a ring of background showing through. Nothing
      // caught that while avatars were emoji, because a centred glyph does not
      // care how much room it is given.
      foregroundDecoration: isSelected
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.brandText, width: 2),
            )
          : null,
      alignment: Alignment.center,
      clipBehavior: path == null ? Clip.none : Clip.antiAlias,
      child: content,
    );

    // No gesture detector at all when neither callback is given. Four of the six
    // sites pass none, and two of those sit inside a row-level `InkWell` or
    // `ListTile`, where an opaque child recogniser would win the arena and
    // swallow the row's tap — the same arena behaviour `friend_reading_test`
    // relies on where the avatar *does* answer taps.
    if (onTap == null && onLongPress == null) return circle;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: circle,
    );
  }
}

/// Photo mode's placeholder: a muted person glyph, shown while a photo loads and
/// if it fails.
///
/// Not the profile's emoji — see [AvatarCircle]. Not a blank disc either, which
/// would read as a rendering bug rather than as an avatar whose picture has not
/// arrived.
class _PhotoPending extends StatelessWidget {
  const _PhotoPending({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.person_rounded,
      size: diameter * 0.6,
      color: context.colors.secondaryText,
    );
  }
}
