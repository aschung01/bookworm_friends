import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// How far into a book the reader is, as a track spanning the whole book.
///
/// The hero of the merged status sheet, and the only control on it: the status word above
/// is a *read-out* of where this thumb sits, not a second thing to set.
///
/// ## It is a real slider, and it was hand-drawn first
///
/// **This was a `CustomPaint` groove with the app's bookmark ribbon for a thumb, and both
/// halves of that were wrong.** The ribbon made an ugly thumb -- it is a tall asymmetric
/// shape with a notch and a shadow, hung off a 4pt bar, and at rest it read as a mark
/// dropped on the track rather than as a handle on it. And the groove was a second
/// implementation of a control the toolchain already ships: [CNSlider] from
/// `cupertino_native_better` is a **native `UISlider`**, which on iOS 26 is where the real
/// Liquid Glass comes from. Painting a translucent rectangle and calling it glass got the
/// fallback's *look* on every platform, including the one platform that has the material.
///
/// So: [CNSlider] behind [useNativeGlass], [CupertinoSlider] everywhere else, and the thumb
/// is the platform's own disc in both cases.
///
/// **[CupertinoSlider] rather than letting [CNSlider] pick its own fallback**, which is the
/// one place this widget overrides the package. `CNSlider` falls back to a **Material**
/// `Slider` off Apple platforms, and a Material slider is *absolute*: tapping the track
/// moves the thumb there. That would reintroduce the exact behaviour this control was
/// designed around -- see below -- on Android and in every widget test, which is where the
/// rule is actually checked.
///
/// ## The tap is inert, and relative dragging is what makes it so
///
/// `docs/mockups/streaks/index.html`'s `band-scrubber` is this control, and it was rejected
/// because *"a stray touch could silently rewrite your position"*. The answer is not a
/// gesture filter bolted on top: **`CupertinoSlider` and `UISlider` are relative**. Flutter's
/// `_RenderCupertinoSlider` holds a lone `HorizontalDragGestureRecognizer` and sets
/// `_currentDragValue = _value` on drag start, then *adds* deltas -- so a tap opens and
/// closes a drag whose delta is zero. Absolute seeking is a Material idea, not an iOS one.
///
/// Two gates do that work, and it is worth naming them because neither is the delta:
/// `_RenderCupertinoSlider.hitTestSelf` accepts a pointer only within about 22pt of the
/// thumb, and `_handleChanged` reports only when the interpolated value differs from the
/// built one. A tap far from the thumb never opens a drag at all; a tap on the thumb opens
/// one that computes the value it already had. What is *not* gated is a sub-step slip, which
/// does fire `onChanged` with an unchanged value -- see `report` below.
///
/// An earlier version of this file reached the same place with a hand-rolled slop gate,
/// after discovering that a lone drag recognizer **wins its arena by default** on
/// pointer-down and so fires on a plain tap. That discovery is still true, and is still the
/// reason this cannot be done with a bare recognizer -- it is only that the two platform
/// sliders already solved it, by being relative rather than by measuring travel.
///
/// **Relative dragging reaches both ends from anywhere**, which was raised as an objection
/// and does not hold: the value moves at `1 / (width - 44)` per pixel -- the usable track is
/// inset by the thumb -- so from any value `v` there is exactly `v` of the travel to its left
/// and `(1 - v)` of it to the right.
/// Both ends are always exactly reachable, which matters because the minus/plus steppers
/// were deliberately not drawn.
///
/// ## The origin is `null`, not `0`
///
/// `progress == null` means "never asked" and `progress == 0` means "opened it and got
/// nowhere" -- two states the model keeps apart on purpose. A track's leftmost pixel can
/// only mean one of them, and it means **`null`**, because that is the state a reader needs
/// a gesture for: it is what makes Reading -> Not started reachable. `0%` survives, one tap
/// further on, at the percent wheel's own `0` stop.
///
/// Hence `ValueChanged<double?>`: the state is in the type rather than in a sentinel.
class ReadingTrack extends StatelessWidget {
  const ReadingTrack({
    super.key,
    required this.progress,
    required this.onChanged,
    this.semanticsLabel,
  });

  /// The stored fraction 0..1, or null when nothing has been recorded.
  final double? progress;

  /// Called with the new fraction, or **null** at the origin.
  ///
  /// Quantised to whole percents, so a value set here round-trips through the percent
  /// wheel's 101 stops unchanged instead of arriving as 0.5843137254901961.
  final ValueChanged<double?> onChanged;

  /// Spoken instead of a bare number. The parent's, because the strings are.
  final String? semanticsLabel;

  /// The slider's own band. [CNSlider]'s platform view is sized by this exactly, so it is
  /// the height a `UISlider` wants rather than a number chosen for the layout.
  static const double _kSliderHeight = 28;
  static const double _kLabelGap = 4;
  static const double _kLabelLine = 16;

  /// The control including its end labels, at text scale 1.
  ///
  /// The labels are free to grow past it; nothing is pinned to this but the sheet's own
  /// height estimate.
  static const double height = _kSliderHeight + _kLabelGap + _kLabelLine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final value = (progress ?? 0).clamp(0.0, 1.0);

    // Whole percents, and the origin reported as an erasure rather than as zero.
    //
    // **A value equal to the one we were given is not reported at all**, and that guard
    // earns its keep: `CupertinoSlider` fires `onChanged` for any sub-step movement, so a
    // 1pt slip on a 331pt track reports the value it already had. The parent's handler
    // treats every report as "the reader answered in percent" and clears the page
    // provenance, so without this a stray touch that moved nothing would drop `p.213` and
    // raise the Save button — a dirty sheet with no change in it, which is the same class
    // of defect as the wheel's `_touched` gate.
    void report(double raw) {
      final percent = (raw * 100).round();
      final next = percent == 0 ? null : percent / 100;
      if (next == progress) return;
      onChanged(next);
    }

    final labelStyle = AppTextStyles.label.copyWith(
      color: colors.secondaryText,
    );

    return Column(
      // Without this the control takes every pixel it is offered — 600pt in a bounded box,
      // measured — and [height] stops describing it. Latent in the sheet, which hands it an
      // unbounded main axis, and wrong anywhere else.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One node rather than two: the slider carries the role, the value and the
        // increase/decrease actions -- all of which the platform and Flutter both provide,
        // and none of which a hand-rolled node did better -- while the label names what is
        // being set. Merged so VoiceOver announces them together.
        MergeSemantics(
          child: Semantics(
            label: semanticsLabel,
            child: SizedBox(
              height: _kSliderHeight,
              child: useNativeGlass
                  ? CNSlider(
                      value: value,
                      onChanged: report,
                      // The wheel's granularity, so the two controls cannot disagree about
                      // which values exist.
                      step: 0.01,
                      trackColor: colors.brand,
                      trackBackgroundColor: colors.surfaceVariant,
                      thumbColor: CupertinoColors.white,
                      height: _kSliderHeight,
                      // Destroys the platform view while one of this sheet's three
                      // sub-sheets is above it. Left at its default on purpose: every door
                      // in the read-out opens a sheet over this one, and an undestroyed
                      // `UISlider` in the sheet *below* is the hybrid-composition z-order
                      // bleed the flag exists for. The app already publishes the modal
                      // depth it reads; see `native_glass.dart`.
                      autoHideOnModal: true,
                    )
                  : CupertinoSlider(
                      value: value,
                      onChanged: report,
                      activeColor: colors.brand,
                      thumbColor: CupertinoColors.white,
                    ),
            ),
          ),
        ),
        const SizedBox(height: _kLabelGap),
        // **The same strings as the status word above**, which is the point: the ends name
        // the two states the track's extremes mean, so a reader can see what the word is a
        // read-out of. Two words for one state is the defect this sheet exists to remove.
        // **Flexible, wrapping, and only then ellipsised — never overflowing.** Two words at
        // opposite ends of a 375pt row have plenty of space at scale 1 and none at 2×:
        // rigid `Text` children overflowed by 119pt at 2× and by 254pt in a 240pt box.
        // Restored after a rewrite dropped them; the row's own comment is the reason it was
        // written this way the first time.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                l10n.statusInterested,
                style: labelStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.statusFinished,
                style: labelStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
