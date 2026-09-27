import Flutter
import StoreKit
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the process lifetime. A `FlutterMethodChannel` does not retain its own
  /// handler's owner, so letting this go out of scope would silently stop answering.
  private var appStoreChannel: FlutterMethodChannel?

  /// Held for the same reason as [appStoreChannel].
  private var widgetChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppStoreChannel(engineBridge)
    registerWidgetChannel(engineBridge)
  }

  /// Exposes the reader's App Store storefront to Dart.
  ///
  /// **Why the app needs it.** Which Apple Books catalogue a person can buy from is
  /// decided by their Apple ID's country, not by the device's language or its
  /// location. Guessing it from the locale was wrong in both directions: a Korean
  /// phone on a US account had Apple Books hidden, and an English phone on a Korean
  /// account was handed `/us/` book links its store answers with a 404.
  ///
  /// `applicationRegistrar.messenger()` is the documented route for an
  /// application-level channel — this is the app's own, not a plugin's, so it does
  /// not go through `pluginRegistry`.
  private func registerAppStoreChannel(_ engineBridge: FlutterImplicitEngineBridge) {
    let channel = FlutterMethodChannel(
      name: "bookworm/app_store",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "storefrontCountryCode" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // StoreKit 1 rather than StoreKit 2's `Storefront.current`, which is `async`
      // and would need a `Task` here for no gain. Available since iOS 13 and the
      // deployment target is 15, so no availability check is required.
      //
      // **Nil is an ordinary answer, not a failure.** There is no storefront on the
      // simulator without a signed-in account, and StoreKit reports nil for a short
      // window early in launch before it has resolved one. Dart treats null as "fall
      // back to the locale", which is the behaviour this replaced.
      //
      // Returns ISO 3166-1 **alpha-3** ("USA", "KOR"); Dart converts it, because
      // Apple's own search API rejects alpha-3.
      result(SKPaymentQueue.default().storefront?.countryCode)
    }
    appStoreChannel = channel
  }

  /// Lets Dart put the streak snapshot where the home-screen widget can read it.
  ///
  /// **Three methods and no more, which is why this is a channel and not a package.** The widget
  /// extension cannot reach Supabase — `reading_days` is owner-only RLS and an extension has no
  /// auth session — so the app writes a JSON snapshot into the shared App Group container and the
  /// widget only ever reads. All of the native work that requires is a `UserDefaults` write, a file
  /// write for the jacket, and a timeline reload; `home_widget`'s real value is launch-URL
  /// plumbing, which `app_links` already does in this app.
  ///
  /// Like the storefront channel this is the application's own, so it goes through
  /// `applicationRegistrar.messenger()` rather than the plugin registry.
  private func registerWidgetChannel(_ engineBridge: FlutterImplicitEngineBridge) {
    let channel = FlutterMethodChannel(
      name: "bookworm/widget",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      // The group must match both targets' entitlements and `streakWidgetAppGroup` in
      // `ios/StreakWidget/StreakSnapshot.swift`. A mismatch is silent: `UserDefaults` hands back
      // a usable store for a group this process does not own, so the write appears to succeed and
      // the widget reads nothing.
      guard let defaults = UserDefaults(suiteName: "group.com.unicorn.bookwormFriends") else {
        result(
          FlutterError(
            code: "no_app_group",
            message: "App Group container unavailable",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "write":
        guard let json = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "expected a JSON string", details: nil))
          return
        }
        defaults.set(json, forKey: "streak_snapshot")
        // Reload rather than trust the timeline's own schedule: the app has just learned
        // something the widget could not have predicted — a night recorded, a book swapped — and
        // the next scheduled entry may be hours away.
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      case "writeCover":
        guard let args = call.arguments as? [String: Any],
          let name = args["name"] as? String,
          let data = args["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(code: "bad_args", message: "expected name and bytes", details: nil)
          )
          return
        }
        // **Validated, not trusted, even though Dart derives it from a Postgres UUID.** A name
        // containing a path separator or `..` would write outside the container — this is the one
        // place in the app where a value from the database becomes a filesystem path, so it gets
        // checked here rather than on the assumption that the caller stayed well behaved.
        guard Self.isSafeCoverName(name) else {
          result(FlutterError(code: "bad_name", message: "unsafe filename", details: nil))
          return
        }
        do {
          try Self.writeCover(named: name, data: data.data)
        } catch {
          result(
            FlutterError(
              code: "cover_write_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      case "clear":
        defaults.removeObject(forKey: "streak_snapshot")
        // **The jacket goes too.** The snapshot outlives the session, and a cover image says which
        // book far more legibly than a hex rectangle did — see `StreakWidgetChannel.clear`.
        Self.removeCovers()
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    widgetChannel = channel
  }

  // MARK: - The widget's jacket, on disk

  /// The App Group's `covers/` directory. **Must match `StreakWidgetCovers` in the extension**,
  /// which resolves the same path to read what this writes.
  private static func coversDirectory() -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.unicorn.bookwormFriends")?
      .appendingPathComponent("covers", isDirectory: true)
  }

  /// Reject anything that is not a plain `cover-<uuid>.png`-shaped name.
  ///
  /// Deliberately a whitelist rather than a search for `..` and `/`: the set of characters a
  /// filesystem treats specially is longer than it looks and differs by platform, whereas the set
  /// this feature actually needs is a UUID, a hyphen and an extension.
  static func isSafeCoverName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 128, name.hasSuffix(".png") else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
    guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
    // `.` is allowed for the extension, so rule out the traversal it also enables.
    return !name.contains("..")
  }

  /// Write [data] as the one cover in the container.
  ///
  /// **Exactly one file is kept, and the pruning is the reason this is not a plain write.** The
  /// name is keyed on the book id, so without it the container would accumulate a PNG per book the
  /// reader has ever had at the head of their shelf — an unbounded cache nobody would think to
  /// look for, inside a container shared with the snapshot.
  private static func writeCover(named name: String, data: Data) throws {
    guard let directory = coversDirectory() else {
      throw NSError(
        domain: "bookworm.widget",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable"]
      )
    }
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    for existing in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
    where existing != name {
      try? manager.removeItem(at: directory.appendingPathComponent(existing))
    }
    // Atomic, so a widget that wakes mid-write reads the old jacket rather than half a PNG.
    try data.write(to: directory.appendingPathComponent(name), options: .atomic)
  }

  private static func removeCovers() {
    guard let directory = coversDirectory() else { return }
    try? FileManager.default.removeItem(at: directory)
  }
}
