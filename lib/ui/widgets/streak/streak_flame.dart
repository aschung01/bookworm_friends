import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

/// Where the flame graphic lives once it has been authored.
///
/// Absent from the repo until the artboard exists, which is deliberate and is why
/// [StreakFlame] falls back rather than asserting: this file ships the wiring, and the
/// `.riv` drops in beside it without a code change. `docs/streak-flame-rive.md` is the
/// build sheet for it.
const String kStreakFlameAsset = 'assets/rive/streak_flame.riv';

/// The state machine the artboard must expose.
const String kStreakFlameStateMachine = 'Ignite';

/// The view-model property the artboard must expose, as a Number in 0–100.
///
/// **Flutter keeps the clock, and this property is the whole reason Rive is acceptable here.**
/// An autoplaying one-shot would move the timing into the editor, where no `Interval` can be
/// read, `MediaQuery.disableAnimationsOf` would need the artboard seeked to its last frame by
/// hand, and the nine beats of `streak_celebration.dart` could drift out of step with the
/// graphic. A scrubbed timeline instead means the artboard is a *drawing that can be posed*
/// and the sequence stays in Dart — greppable, golden-testable, and gated exactly once.
///
/// **Data binding rather than a state-machine input**, because the runtime deprecates inputs:
/// `stateMachine.number(...)` warns "Use Data Binding instead of state machine inputs for
/// better editor and runtime control". Same one number, bound through the artboard's view
/// model.
const String kStreakFlameProgressProperty = 'progress';

/// Which renderer decodes and draws the artboard.
///
/// **`Factory.flutter`, and `Factory.rive` is not a tuning knob here — it crashes the
/// process.** The Rive Renderer wants a GPU context, and a headless `flutter test` shell has
/// none, so `File.asset` trips a native assertion (`Assertion failed: (factory)`, `file.cpp`
/// line 206) and the shell dies with SIGABRT. That is not catchable: the `catch` below never
/// runs, the whole test file reports `did not complete`, and every case in
/// `streak_celebration_test.dart` goes with it, because that screen pumps this widget. A
/// screen presented over the streak page may not carry a renderer that can abort the process.
///
/// The Flutter factory draws through Flutter's own canvas instead. For a drawing this size — a
/// dozen paths, no meshes, no images, no scripts — the Rive Renderer buys nothing that would
/// pay for that failure mode.
///
/// `final` rather than `const`: `Factory.flutter` is a getter, not a constant.
final rive.Factory kStreakFlameFactory = rive.Factory.flutter;

/// Where [StreakFlame] looks for the artboard, when a test needs it to look somewhere else.
///
/// **This exists because which path the widget takes depends on the machine, and a test may
/// not.** `rive_native`'s dynamic library is downloaded into `build/`, which is gitignored, so
/// the artboard renders on a developer machine that has run `dart run rive_native:setup` and
/// falls back on one that has not. Three cases in `streak_celebration_test.dart` assert the
/// hand-built choreography — the glyph's colour as it catches, the spark painter, the gleam's
/// `ShaderMask` — and those widgets exist only on the fallback path. Pointing this at a name
/// that cannot resolve makes that path certain rather than probable.
///
/// Nothing in `lib/` writes it. The artboard path is covered by `streak_flame_test.dart`,
/// which asks the file itself whether it decodes and exposes the contract.
@visibleForTesting
String? debugStreakFlameAssetOverride;

/// The flame at the top of the celebration: the Rive book-and-flame if it has been authored,
/// and the hand-built ignition if it has not.
///
/// **Rive draws the flame and nothing else.** The counter, the week row, the milestone bar
/// and every line of copy stay in Flutter, because they are localised strings and themed
/// colours — baking them into an artboard would put `l10n` and `AppColors` inside a binary
/// nobody can grep, which is the objection that kept Rive out of here in the first place. The
/// boundary is: Rive owns the *drawing*, Dart owns the *timing*, the *text* and the *theme*.
///
/// **It resolves the file itself instead of handing the asset name to `FileLoader`, and that
/// is not a preference.** `RiveWidgetBuilder` documents a [rive.RiveFailed] state, but a
/// missing asset does not reach it: `FileLoader.file` throws `RiveFileLoaderException` out of
/// `initState`, which takes down the subtree and fails every widget test that pumps this
/// screen. Loading the bytes first and only mounting the builder once they decoded means the
/// absent-artboard case — which is the case today, and the case on any checkout until the
/// `.riv` lands — is an ordinary `null`, not an exception.
class StreakFlame extends StatefulWidget {
  const StreakFlame({
    super.key,
    required this.progress,
    required this.size,
    required this.fallback,
  });

  /// 0 → 1 across the ignition window, driven by the celebration's own controller.
  final Animation<double> progress;

  /// The square the artboard is drawn into.
  final double size;

  /// What to draw when there is no artboard to draw.
  final WidgetBuilder fallback;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> {
  /// Null while resolving, and null forever if there is nothing to resolve.
  rive.File? _file;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    rive.File? file;
    try {
      file = await rive.File.asset(
        debugStreakFlameAssetOverride ?? kStreakFlameAsset,
        riveFactory: kStreakFlameFactory,
      );
    } catch (_) {
      // Absent, truncated, or authored against a newer format than this runtime reads. All
      // three mean the same thing to this screen: draw the fallback.
      file = null;
    }
    if (!mounted) {
      file?.dispose();
      return;
    }
    setState(() {
      _file = file;
      _settled = true;
    });
  }

  @override
  void dispose() {
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    // **The fallback is what shows while resolving, not a spinner and not a gap.** Reading an
    // asset takes a frame or two, and this is the first beat of a 1.5s sequence: a hole where
    // the flame belongs would be more visible than the swap. When the artboard is missing —
    // the common case until it exists — this is simply what ships.
    if (!_settled || file == null) return widget.fallback(context);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: rive.RiveWidgetBuilder(
        fileLoader: rive.FileLoader.fromFile(
          file,
          riveFactory: kStreakFlameFactory,
        ),
        stateMachineSelector: const rive.StateMachineNamed(
          kStreakFlameStateMachine,
        ),
        dataBind: rive.DataBind.auto(),
        builder: (context, state) => switch (state) {
          rive.RiveLoading() => widget.fallback(context),
          rive.RiveFailed() => widget.fallback(context),
          // A loaded artboard with no view model is an artboard that cannot be posed, so it
          // takes the fallback too rather than sitting on frame zero forever.
          rive.RiveLoaded(:final controller, :final viewModelInstance) =>
            viewModelInstance == null
                ? widget.fallback(context)
                : _Posed(
                    controller: controller,
                    viewModel: viewModelInstance,
                    progress: widget.progress,
                  ),
        },
      ),
    );
  }
}

/// Holds the artboard at whatever [progress] says, rather than letting it play itself.
class _Posed extends StatefulWidget {
  const _Posed({
    required this.controller,
    required this.viewModel,
    required this.progress,
  });

  final rive.RiveWidgetController controller;
  final rive.ViewModelInstance viewModel;
  final Animation<double> progress;

  @override
  State<_Posed> createState() => _PosedState();
}

class _PosedState extends State<_Posed> {
  rive.ViewModelInstanceNumber? _progress;

  @override
  void initState() {
    super.initState();
    _progress = widget.viewModel.number(kStreakFlameProgressProperty);

    // **The artboard must not tick on its own, and this is a correctness fix rather than an
    // optimisation.** `RiveWidgetController.advance` returns `didAdvance && active`, and a 1D
    // blend state considers itself always advancing, so with `active` left at its default the
    // ticker never stops: the celebration would repaint at 60fps forever on a screen a reader
    // opens nightly and then leaves sitting there. It also made `pumpAndSettle` time out the
    // moment the `.riv` landed, which is how it was found -- every widget test that pumps this
    // screen hung for its full timeout.
    //
    // Switching it off does not stop the drawing from being drawn: `active` gates the ticker,
    // the hit test and the pointer handlers, not `paint`. And the state machine registers
    // `scheduleRepaint` as an advance-request listener, so writing `progress` asks for a frame
    // by itself. The result is one frame per change and stillness in between -- which is the
    // same contract the poses are written to, now enforced on both sides.
    widget.controller.active = false;

    widget.progress.addListener(_pose);
    _pose();
  }

  @override
  void dispose() {
    widget.progress.removeListener(_pose);
    super.dispose();
  }

  /// **In 0–100, which is the range Rive's own scroll examples use** rather than 0–1: a
  /// number input has no declared domain, so the convention has to live somewhere, and the
  /// editor's timeline is easier to map onto a percentage.
  void _pose() {
    _progress?.value = widget.progress.value * 100;
    // Explicit rather than relying on the advance-request listener alone: the listener fires
    // on the state machine's own notion of dirtiness, and a pose that failed to repaint is a
    // frozen flame with no error attached to it.
    widget.controller.scheduleRepaint();
  }

  @override
  Widget build(BuildContext context) {
    return rive.RiveWidget(
      controller: widget.controller,
      fit: rive.Fit.contain,
    );
  }
}
