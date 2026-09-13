import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerDisplayChannel(messenger: messenger)
    registerPushChannel(messenger: messenger)
    // After the plugins, never before: flutter_local_notifications makes
    // itself the notification centre's delegate during registration, and
    // the proxy has to wrap the delegate that is actually installed.
    installNotificationCentreProxy()
  }

  // MARK: - Push (research/06 R1)
  //
  // iOS talks to APNs directly: there is no Firebase iOS app and no
  // GoogleService-Info.plist, so the only push credential anywhere is the
  // team's .p8 on the relay. The Runner registers for remote notifications
  // and hands the device token to Dart over this channel; permission itself
  // comes from the existing local-notifications prompt
  // (NotificationService.setEnabled), so the user is asked once.
  //
  // UNVERIFIED: written on Windows for a session with no Mac. It has never
  // been compiled or run, and APNs is disabled on the relay until Apple's
  // Key ID for the .p8 is known.

  private var pushChannel: FlutterMethodChannel?

  /// Hex APNs token, kept so a late `register` call can be answered at once.
  private var apnsToken: String?

  private func registerPushChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.kammcs.boardhop/push", binaryMessenger: messenger)
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        // Safe to call repeatedly; iOS answers with the same token unless it
        // rotated. Does not prompt: without permission the delegate simply
        // never fires.
        UIApplication.shared.registerForRemoteNotifications()
        result(self?.apnsToken)
        // A tap that launched the app arrives before Dart has a handler:
        // the notification centre calls its delegate as soon as the engine
        // is up, while `_initIos` only runs once Flutter is running. Hold
        // it and deliver it here, where Dart is known to be listening.
        self?.flushPendingOpened()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsToken = hex
    pushChannel?.invokeMethod("onToken", arguments: hex)
    super.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // Expected on the simulator without a paired Apple ID, and whenever the
    // user has not granted notifications. Never log the token; there is none.
    NSLog("Boardhop: remote notification registration failed: \(error.localizedDescription)")
    super.application(
      application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // The pointer's `data` keys sit at the top level of the APNs payload
    // alongside `aps`; hand the string ones to Dart and let it decide.
    var pointer: [String: String] = [:]
    for (key, value) in userInfo {
      if let key = key as? String, key != "aps", let value = value as? String {
        pointer[key] = value
      }
    }
    // Only the foreground case belongs here now. A notification the user
    // taps reaches `userNotificationCenter(_:didReceive:)` on the proxy
    // below, and a normal push delivered while the app is in the
    // background does not call this method at all — only a silent
    // `content-available` one does, and that is not an "opened".
    if !pointer.isEmpty, application.applicationState == .active {
      pushChannel?.invokeMethod("onMessage", arguments: pointer)
    }
    super.application(
      application, didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler)
  }

  // MARK: - Notification centre proxy
  //
  // `UNUserNotificationCenter` has exactly one delegate and
  // flutter_local_notifications claims it, forwarding only the
  // notifications it raised itself. That left a pushed notification with
  // no route home when the user tapped it (research/06). This proxy sits
  // in front: it answers for remote notifications and passes everything
  // else to the delegate the plugin installed, so the feed's own local
  // notifications keep working exactly as before.

  /// Held strongly: the centre's `delegate` is weak.
  private var notificationProxy: NotificationCentreProxy?

  /// A tap that arrived before Dart had a handler.
  private var pendingOpened: [String: String]?

  private func installNotificationCentreProxy() {
    let centre = UNUserNotificationCenter.current()
    let proxy = NotificationCentreProxy(inner: centre.delegate)
    proxy.onRemote = { [weak self] pointer, opened in
      guard let self, !pointer.isEmpty else { return }
      if opened {
        // No handler yet means a cold start from the tap.
        if self.pushChannel == nil {
          self.pendingOpened = pointer
        } else {
          self.pushChannel?.invokeMethod("onOpened", arguments: pointer)
        }
      } else {
        self.pushChannel?.invokeMethod("onMessage", arguments: pointer)
      }
    }
    notificationProxy = proxy
    centre.delegate = proxy
  }

  fileprivate func flushPendingOpened() {
    guard let pointer = pendingOpened else { return }
    pendingOpened = nil
    pushChannel?.invokeMethod("onOpened", arguments: pointer)
  }

  /// The display channel, read by lib/core/display_cutout.dart.
  ///
  /// * `interfaceOrientation` — Boardhop's glass rail asks which side the
  ///   Dynamic Island is on while the phone is in landscape. Flutter's
  ///   safe-area insets are the same on both sides there, so only the
  ///   interface orientation can tell.
  /// * `reservedRegions` — the rectangles the UI must keep clear of: a
  ///   folding device's hinge and any camera housing over the display.
  private func registerDisplayChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.kammcs.boardhop/display", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "interfaceOrientation":
        result(Self.interfaceOrientation())
      case "reservedRegions":
        result(self?.reservedRegions())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func activeScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }

  private static func interfaceOrientation() -> String {
    switch activeScene()?.interfaceOrientation {
    case .landscapeLeft: return "landscapeLeft"
    case .landscapeRight: return "landscapeRight"
    case .portrait: return "portrait"
    case .portraitUpsideDown: return "portraitUpsideDown"
    default: return "unknown"
    }
  }

  /// The Flutter view's reserved regions, as `[{kind, x, y, width, height,
  /// active}]` in the view's own coordinates.
  ///
  /// The whole Boardhop UI is one `UIView` under `FlutterViewController`,
  /// so one view answers for the app (research/12b).
  ///
  /// **Reached by selector on purpose.** `reservedRegions(kind:)` is iOS
  /// 27.1. This machine has Xcode 27.0 and the iOS **27.0** SDK, whose
  /// UIKit headers carry no such symbol (checked 2026-09-13), so a direct
  /// call would not compile and an `#available` guard would not help.
  /// Asking the runtime keeps the app building today and lets the real
  /// answer arrive the first time it runs on an OS that has the API.
  ///
  /// **Unverified.** The selector spelling below is from Tech Talk 111461
  /// and has not been run against a real iPhone Duo or the 27.1 SDK (there
  /// is no Duo simulator device type in 27.0 either); when the headers
  /// land, check it and replace this with the typed call. Until then the
  /// method answers an empty list, which the Dart side reads as "asked,
  /// nothing reserved".
  private func reservedRegions() -> [[String: Any]] {
    guard let view = window?.rootViewController?.view else { return [] }
    var out: [[String: Any]] = []
    for (kind, name) in [(0, "division"), (1, "occlusion")] {
      for rect in Self.regions(of: view, kind: kind) {
        out.append([
          "kind": name,
          "x": rect.origin.x,
          "y": rect.origin.y,
          "width": rect.size.width,
          "height": rect.size.height,
          "active": !rect.isEmpty,
        ])
      }
    }
    return out
  }

  private static func regions(of view: UIView, kind: Int) -> [CGRect] {
    // Gate the probe on the OS that introduced the API. `#available` is a
    // runtime check and does not make an absent symbol compile — that is
    // why the call below still goes through the selector rather than
    // `view.reservedRegions(kind:)` — but it keeps the app from poking at
    // a same-named private selector on an older OS, and it is the line to
    // build the typed call inside once the 27.1 SDK is installed.
    guard #available(iOS 27.1, *) else { return [] }
    let selector = NSSelectorFromString("reservedRegionsOfKind:")
    guard view.responds(to: selector) else { return [] }
    guard
      let raw = view.perform(selector, with: NSNumber(value: kind))?
        .takeUnretainedValue() as? [NSValue]
    else { return [] }
    return raw.map { $0.cgRectValue }.filter { !$0.isNull }
  }
}

/// Wraps whatever delegate flutter_local_notifications installed.
///
/// Remote notifications are answered here and reported to Dart; anything
/// else is handed straight to [inner], which is how the activity feed's
/// local notifications keep their taps.
private final class NotificationCentreProxy: NSObject, UNUserNotificationCenterDelegate {
  init(inner: UNUserNotificationCenterDelegate?) {
    self.inner = inner
  }

  /// Strong on purpose: replacing the centre's weak `delegate` can be the
  /// last reference to the plugin's own.
  private let inner: UNUserNotificationCenterDelegate?

  /// `(pointer, opened)` — opened is false for a foreground arrival.
  var onRemote: (([String: String], Bool) -> Void)?

  /// True for a notification APNs delivered, false for one the app raised.
  private func isRemote(_ notification: UNNotification) -> Bool {
    notification.request.trigger is UNPushNotificationTrigger
  }

  /// The pointer's keys sit beside `aps` at the top level of the payload.
  private func pointer(of notification: UNNotification) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in notification.request.content.userInfo {
      if let key = key as? String, key != "aps", let value = value as? String {
        out[key] = value
      }
    }
    return out
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard isRemote(notification) else {
      if let inner, inner.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
        inner.userNotificationCenter?(
          center, willPresent: notification, withCompletionHandler: completionHandler)
      } else {
        completionHandler([.banner, .list, .sound])
      }
      return
    }
    onRemote?(pointer(of: notification), false)
    // Nothing from the system: Dart raises its own notification for a
    // foreground push through the feed's channel, the way Android does,
    // and two banners for one event is worse than none.
    completionHandler([])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard isRemote(response.notification) else {
      if let inner, inner.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
        inner.userNotificationCenter?(
          center, didReceive: response, withCompletionHandler: completionHandler)
      } else {
        completionHandler()
      }
      return
    }
    onRemote?(pointer(of: response.notification), true)
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    openSettingsFor notification: UNNotification?
  ) {
    if let inner, inner.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))) {
      inner.userNotificationCenter?(center, openSettingsFor: notification)
    }
  }
}
