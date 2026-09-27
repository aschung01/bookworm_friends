import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

/// Pins [StreakFlame] to its hand-built fallback for every case in the calling group.
///
/// Call it once at the top of `main()`. It registers its own `setUp`/`tearDown`.
///
/// **There are two separate reasons to want this, and both of them are about tests that pass
/// or fail depending on the machine rather than on the code.**
///
/// The first is that `rive_native`'s dynamic library is downloaded by
/// `dart run rive_native:setup` into `build/`, which is gitignored and therefore does not
/// travel between checkouts or worktrees. `rive.File.asset` fails without it, `StreakFlame`
/// draws the fallback, and the failure is *printed* rather than thrown — so which of the two
/// drawings a test inspects is a property of whoever ran the setup. Cases that assert the
/// fallback's internals (the glyph's colour as it catches, the spark painter, the gleam's
/// `ShaderMask`) passed for weeks and then failed the hour the `.riv` was committed.
///
/// The second is newer and catches tests that do not care about the flame at all.
/// **The artboard's `Idle` timeline loops for as long as the celebration is on screen, so
/// `pumpAndSettle` never returns anywhere the Rive path is live.** That is the deliberate cost
/// of `kStreakFlameIdleAnimation` — a flame that freezes the instant it arrives reads as a
/// decal — and it is documented there. But it means any test that pushes the celebration and
/// then settles hangs for its full timeout on a configured machine and passes on an
/// unconfigured one, which is how four cases in `reading_streak_page_test.dart` started
/// failing without anything in that file changing. Those cases are about whether recording a
/// night writes the day; the flame is scenery, and this makes it hold still.
///
/// A test that wants the *artboard* should not call this: see `streak_flame_test.dart` and
/// `streak_flame_golden_test.dart`, which pass `liveness` of zero instead.
void useStillStreakFlame() {
  setUp(() {
    // A name that cannot resolve, rather than a flag: the point is to exercise the same
    // failure path a machine without the library takes, not a second code path that only
    // tests use.
    debugStreakFlameAssetOverride = 'assets/rive/__absent__.riv';
  });
  tearDown(() => debugStreakFlameAssetOverride = null);
}
