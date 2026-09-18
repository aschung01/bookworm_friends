// Records the URLs a widget test's taps hand to the platform.
//
// **Why the sheet suite needs this at all.** Every row in "Where to read" is a URL,
// and until this landed the suite could only assert the row's *words*. That is the
// exact blind spot the feature's history is made of: a row that read "Open Play
// Books" and performed a Play Store search, and four Libby URLs that were wrong in
// four different ways. A label test cannot see any of it.
//
// **What it still cannot see, and this is worth stating plainly.** It asserts the URL
// the app *built*, never that the URL *arrives*. Two of the wrong Libby URLs were
// reasoned from real evidence and would have passed a test like this. So use it to
// pin a URL that has been verified by hand, not to convince yourself a new one works.

import 'package:flutter_test/flutter_test.dart';
// `LinkDelegate` is the one member of the interface that lives outside its barrel
// file, and it is `abstract` there, so it has to be imported to be overridden.
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A stand-in for whichever platform implementation `url_launcher` would have
/// registered, which under `flutter test` is a method channel with nothing behind it.
///
/// `extends UrlLauncherPlatform` rather than `implements`: the setter runs
/// `PlatformInterface.verify`, which only accepts an instance that inherited the
/// interface's private token — so a hand-rolled `implements` fake is rejected at
/// runtime, and no mocking package is needed to get past it.
class RecordingUrlLauncher extends UrlLauncherPlatform {
  /// Every URL handed over, oldest first. A list rather than a single slot because
  /// "and nothing else was launched" is half of most assertions here.
  final List<String> launched = [];

  /// What [launchUrl] reports back. False is how the app learns a custom scheme has
  /// no installed handler, and it takes a different branch — so it has to be settable.
  bool succeeds = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => succeeds;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return succeeds;
  }

  /// The single URL launched, failing the test if that is not exactly what happened.
  ///
  /// Reads better than `launched.single` at a call site because the failure names
  /// what went wrong: zero means the tap missed, more than one means something else
  /// on screen also fired.
  String get only {
    if (launched.length != 1) {
      throw StateError(
        'expected exactly one launch, got ${launched.length}: $launched',
      );
    }
    return launched.first;
  }
}

/// Installs a [RecordingUrlLauncher] for the duration of one test and restores the
/// real instance afterwards.
///
/// The instance is process-global, so restoring it is not optional: a leaked fake
/// would silently swallow launches in every later test in the same file.
RecordingUrlLauncher recordUrlLaunches() {
  final previous = UrlLauncherPlatform.instance;
  final fake = RecordingUrlLauncher();
  UrlLauncherPlatform.instance = fake;
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  return fake;
}
