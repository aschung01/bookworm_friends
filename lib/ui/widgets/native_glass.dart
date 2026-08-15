import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';

/// Whether native Liquid Glass controls should be used for this build.
///
/// Both halves matter. [PlatformVersion.shouldUseNativeGlass] only inspects the
/// *host* OS version, so on a macOS 26 machine it is true even when the target
/// platform isn't Apple. The native widgets gate on target platform *and*
/// version internally, so without the target check they are handed SF Symbols
/// they then discard — leaving controls with no icon at all. (This is exactly
/// what happens under `flutter test`, which reports Android.)
bool get useNativeGlass {
  final isApplePlatform =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  return isApplePlatform && PlatformVersion.shouldUseNativeGlass;
}
