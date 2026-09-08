import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:bookworm_friends/services/avatar_raster.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// The reader's avatar as a glass button that answers a press like a native one.
///
/// **What this widget is for.** [AdaptiveGlassCircle] can put its content *inside* the
/// native button, which is the only way UIKit will transform it along with the glass —
/// but only if it is handed PNG bytes. Producing those is asynchronous (an off-screen
/// capture, and a network fetch first for photo avatars), so something has to own the
/// lifecycle: ask for the raster, draw the Flutter fallback until it lands, and ask
/// again when the profile changes. That is all this does.
///
/// Split out of `home_page._LibraryBar` rather than inlined because the bar is already
/// long and this is a state machine, not a row of chrome.
class GlassAvatarButton extends StatefulWidget {
  /// The profile's emoji, used when [avatarPath] is null.
  final String? emoji;

  /// Storage object path for a photo avatar, or null for emoji mode.
  final String? avatarPath;

  /// The disc and the tap target.
  final double diameter;

  /// Size the avatar draws at on the *Material* fallback, where there is no disc to
  /// fill and the content is inset the way an `IconButton` would inset it.
  final double fallbackDiameter;

  final VoidCallback? onPressed;

  final String semanticLabel;

  const GlassAvatarButton({
    super.key,
    required this.emoji,
    required this.avatarPath,
    required this.semanticLabel,
    this.diameter = 44,
    this.fallbackDiameter = 32,
    this.onPressed,
  });

  @override
  State<GlassAvatarButton> createState() => _GlassAvatarButtonState();
}

class _GlassAvatarButtonState extends State<GlassAvatarButton> {
  Uint8List? _bytes;

  AvatarRasterKey get _key => AvatarRasterKey(
    emoji: widget.emoji,
    avatarPath: widget.avatarPath,
    diameter: widget.diameter,
  );

  /// Whether a *capture* is worth starting.
  ///
  /// **The raster exists only to be handed to a native button, so off that path it is
  /// pure waste** — `AdaptiveGlassCircle` draws the Flutter fallback and never looks
  /// at [AdaptiveGlassCircle.imageBytes]. Capturing anyway would mount an off-screen
  /// overlay and encode a PNG on every Android build for a result nothing reads.
  ///
  /// It also keeps the capture out of `flutter test`, which matters more than it
  /// sounds: `captureWidgetToPng` waits on two real frames and then `toImage`, which
  /// needs `runAsync` — a test cannot pump from inside it, so the future never
  /// completes and the pending work hangs the test. Every widget test that mounts the
  /// library bar would inherit that. `useNativeGlass` is false under the test binding
  /// (it reports Android), so this gate is what keeps them clean.
  ///
  /// **It gates the capture only, and that distinction was a bug.** This used to be the
  /// first line of both lifecycle methods, which put the synchronous cache read and the
  /// stale-bytes drop behind it too. Neither costs anything, and worse, gating them made
  /// the drop unreachable under test: a mutation that kept the previous face across a
  /// profile change passed the entire suite. Reading the cache is free on any platform,
  /// so only [_request] is conditional now.
  bool get _wantsCapture => useNativeGlass;

  @override
  void initState() {
    super.initState();
    // Synchronously, so an avatar already rasterised this session is native on its
    // very first frame rather than flickering through the fallback.
    _bytes = cachedAvatarRaster(_key);
    if (_bytes == null) _request(_key);
  }

  @override
  void didUpdateWidget(GlassAvatarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _key;
    final was = AvatarRasterKey(
      emoji: oldWidget.emoji,
      avatarPath: oldWidget.avatarPath,
      diameter: oldWidget.diameter,
    );
    if (key == was) return;

    // **The bytes in hand are the *old* face, so they have to go.** Keeping them for
    // one more frame would show the previous photo on a profile that has already
    // changed, which is worse than a frame of the fallback.
    final ready = cachedAvatarRaster(key);
    setState(() => _bytes = ready);
    if (ready == null) _request(key);
  }

  void _request(AvatarRasterKey key) {
    if (!_wantsCapture) return;
    // Deliberately not awaited in `initState`: the capture needs an `Overlay`, and
    // mounting one from inside a build is not allowed. A post-frame callback puts it
    // after the tree this widget was built into is live.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bytes = await rasterizeAvatar(context, key);
      // Two guards, and both fire in practice. `mounted` for a bar disposed mid-
      // capture; the key comparison for a profile that changed while this one was in
      // flight, where the arriving bytes are already stale.
      if (!mounted || key != _key) return;
      if (bytes == null) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveGlassCircle(
      diameter: widget.diameter,
      onPressed: widget.onPressed,
      semanticLabel: widget.semanticLabel,
      // Null until the raster lands, which is what makes the fallback below a normal
      // path rather than an error one.
      imageBytes: _bytes,
      builder: (context, glass) => AvatarCircle(
        emoji: widget.emoji,
        avatarPath: widget.avatarPath,
        // On glass the avatar *is* the disc; off it there is no disc to fill and this
        // is the inset an `IconButton` would have applied anyway.
        diameter: glass ? widget.diameter : widget.fallbackDiameter,
        // On glass the disc is the fill, and an opaque `surfaceVariant` would paint
        // straight over it. Off glass the fill is what keeps an emoji from reading as
        // a loose glyph.
        filled: !glass,
      ),
    );
  }
}
