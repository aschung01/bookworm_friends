import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the process lifetime. A `FlutterMethodChannel` does not retain its own
  /// handler's owner, so letting this go out of scope would silently stop answering.
  private var appStoreChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppStoreChannel(engineBridge)
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
}
