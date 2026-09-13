import Flutter
import UIKit

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
    registerDisplayChannel(messenger: engineBridge.applicationRegistrar.messenger())
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
