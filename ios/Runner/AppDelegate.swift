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

  /// Boardhop's glass rail asks which side the Dynamic Island is on while
  /// the phone is in landscape. Flutter's safe-area insets are the same on
  /// both sides there, so only the interface orientation can tell
  /// (lib/core/display_cutout.dart maps it to the island's side).
  private func registerDisplayChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.kammcs.boardhop/display", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "interfaceOrientation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
        ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
      switch scene?.interfaceOrientation {
      case .landscapeLeft: result("landscapeLeft")
      case .landscapeRight: result("landscapeRight")
      case .portrait: result("portrait")
      case .portraitUpsideDown: result("portraitUpsideDown")
      default: result("unknown")
      }
    }
  }
}
