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
  // Verified end to end on Kelly's iPhone on 2026-09-13: token, registration,
  // a real push from the relay and a tap that routed.

  private var pushChannel: FlutterMethodChannel?

  /// Hex APNs token, kept so a late `register` call can be answered at once.
  private var apnsToken: String?

  /// True once Dart has asked for a token. iOS does not retry a failed
  /// `registerForRemoteNotifications` on its own, and it does not answer at
  /// all while the phone has no route to APNs, so the Runner asks again: after
  /// a failure with a growing delay, and whenever the app becomes active
  /// without a token. Registration with the relay follows the user's grant of
  /// the permission, not the next cold start.
  private var wantsToken = false
  private var registrationRetries = 0
  private static let maxRegistrationRetries = 5

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
        self?.wantsToken = true
        self?.registrationRetries = 0
        UIApplication.shared.registerForRemoteNotifications()
        result(self?.apnsToken)
        self?.installNotificationCentreProxy()
        // A tap that launched the app arrives before Dart has a handler:
        // the notification centre calls its delegate as soon as the engine
        // is up, while `_initIos` only runs once Flutter is running. Hold
        // it and deliver it here, where Dart is known to be listening.
        self?.flushPendingOpened()
      case "setAccount":
        // R2.7: BoardhopNotificationService runs in its own process and
        // cannot read `shared_preferences` (the app's standard UserDefaults),
        // so the MSAL account identifier that registered an organization is
        // mirrored into the app group under the same key name PushRegistrar
        // uses. An account identifier, not a token; never logged.
        guard let arguments = call.arguments as? [String: Any],
          let org = arguments["org"] as? String, !org.isEmpty,
          let accountId = arguments["accountId"] as? String, !accountId.isEmpty
        else {
          result(false)
          return
        }
        PushSharedDefaults.setAccountId(accountId, org: org)
        result(true)
      case "drainPushed":
        // Pointers the Notification Service Extension handled while the app
        // was not running: the feed rows and the notified marks.
        result(PushSharedDefaults.drainPending())
      case "clearAccount":
        guard let arguments = call.arguments as? [String: Any],
          let org = arguments["org"] as? String, !org.isEmpty
        else {
          result(false)
          return
        }
        PushSharedDefaults.clearAccountId(org: org)
        result(true)
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
    registrationRetries = 0
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
    retryRegistrationLater()
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

  /// Re-asserts the proxy whenever something else has taken the delegate.
  ///
  /// Ordering here is not ours to control: the notification centre's
  /// delegate is a single slot, the engine hands it to plugins at a time
  /// of its choosing, and `didFinishLaunchingWithOptions` runs after the
  /// engine callback that installs this. Rather than guess the order, the
  /// proxy is put back whenever Dart asks to register and whenever the app
  /// becomes active, wrapping whatever it displaces.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    installNotificationCentreProxy()
    // The scene may only have come up now, and the pose can change while
    // the app is away.
    installDisplayObservers()
    scheduleDisplayPush()
    if wantsToken, apnsToken == nil {
      // The earlier ask went unanswered (no network, or it failed and the
      // retries ran out); the app is in front again, so ask once more.
      registrationRetries = 0
      application.registerForRemoteNotifications()
    }
    super.applicationDidBecomeActive(application)
  }

  /// 5, 10, 20, 40, 60 seconds, then wait for the next activation.
  private func retryRegistrationLater() {
    guard wantsToken, apnsToken == nil,
      registrationRetries < Self.maxRegistrationRetries
    else { return }
    let delay = min(60.0, 5.0 * pow(2.0, Double(registrationRetries)))
    registrationRetries += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, self.wantsToken, self.apnsToken == nil else { return }
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  private func installNotificationCentreProxy() {
    let centre = UNUserNotificationCenter.current()
    let current = centre.delegate
    if current is NotificationCentreProxy { return }
    NSLog(
      "Boardhop: taking the notification delegate from %@",
      current.map { String(describing: type(of: $0)) } ?? "nobody")
    // `self`, never the delegate being displaced. FLTFirebaseMessagingPlugin
    // takes this slot when it registers and keeps whatever it found as its
    // own forwarding target, so wrapping it made the two forward to each
    // other and a local notification went round in a circle, never
    // presented. The app delegate implements the three
    // UNUserNotificationCenterDelegate selectors and fans them out to every
    // plugin registered with `addApplicationDelegate:` — both
    // flutter_local_notifications and Firebase register that way — so
    // handing it what we do not claim reaches all of them and cannot come
    // back here.
    let proxy = NotificationCentreProxy(inner: self)
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

  /// The display channel, read by `lib/core/display_cutout.dart` and
  /// `lib/core/display_environment.dart`.
  ///
  /// * `displayState` — everything below in one call, as
  ///   `{regions, verticalBarEdge, hinge, interfaceOrientation}`. This is
  ///   what `DisplayEnvironment` polls once at startup, and the same shape
  ///   the Runner pushes afterwards.
  /// * `interfaceOrientation` — Boardhop's glass rail asks which side the
  ///   Dynamic Island is on while the phone is in landscape. Flutter's
  ///   safe-area insets are the same on both sides there, so only the
  ///   interface orientation can tell.
  /// * `reservedRegions` — the rectangles the UI must keep clear of: a
  ///   folding device's hinge and any camera housing over the display.
  /// * `verticalBarEdge` — the edge iOS puts its own vertical bar on, which
  ///   is where the glass rail belongs (research/23 D1).
  /// * `hinge` — the fold's status and angle, from a `UIHingeInteraction`.
  /// * `cornerInsets` — the corner-adapted safe area (iOS 26's layout
  ///   regions), which is what a rounded corner costs the leading and
  ///   trailing ends of a top bar. `padding` is genuinely zero on those
  ///   edges of an iPhone Duo, so only this can say the corner is there
  ///   (research/23 section 4.3).
  /// * `regionInsets` — the same query for the plain safe area and for
  ///   both adaptivity axes, side by side. Diagnostics: the Display probe
  ///   page shows them so a pose can be measured rather than guessed.
  ///
  /// **Push, not poll (research/23 §9.2).** Folding an iPhone Duo changes
  /// no metric Flutter can see: `MediaQuery.size`, `padding` and
  /// `orientation` are byte-identical open and half-folded, and
  /// `didChangeMetrics` never fires. Only this channel knows, so the Runner
  /// calls `displayChanged` on it with a fresh `displayState` payload from
  /// three sources — the hinge interaction, a trait-change registration and
  /// the window's layout pass — coalesced to one call per runloop turn.
  /// Nothing is pushed until Dart has asked for `displayState` once, so a
  /// push can never race startup.
  private var displayChannel: FlutterMethodChannel?

  /// Dart has called `displayState`, so it has a handler installed and
  /// pushes are safe to send.
  private var displayPushesWanted = false

  /// One push per runloop turn: the hinge handler alone ran 38 times
  /// during a single fold (research/23 §9.2).
  private var displayPushScheduled = false

  private func registerDisplayChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.kammcs.boardhop/display", binaryMessenger: messenger)
    displayChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "displayState":
        self?.displayPushesWanted = true
        self?.installDisplayObservers()
        result(self?.displayState())
      case "interfaceOrientation":
        result(Self.interfaceOrientation())
      case "reservedRegions":
        result(self?.reservedRegions())
      case "verticalBarEdge":
        result(self?.verticalBarEdge())
      case "hinge":
        result(self?.hingeState())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // The sources have to be live before the first fold rather than
    // installed by the first `hinge` call, or a fold nobody asked about
    // would be missed. The scene is usually not up yet at registration
    // time, so this retries until it is.
    DispatchQueue.main.async { [weak self] in self?.installDisplayObservers() }
  }

  /// `{regions, verticalBarEdge, hinge, interfaceOrientation}` — what a
  /// fresh poll of the four methods would return, in one map.
  private func displayState() -> [String: Any] {
    return [
      "regions": reservedRegions(),
      "verticalBarEdge": verticalBarEdge(),
      "hinge": hingeState(),
      "interfaceOrientation": Self.interfaceOrientation(),
      "cornerInsets": cornerInsets(),
      "regionInsets": regionInsets(),
    ]
  }

  private func scheduleDisplayPush() {
    guard displayPushesWanted, !displayPushScheduled else { return }
    displayPushScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.displayPushScheduled = false
      guard self.displayPushesWanted, let channel = self.displayChannel else { return }
      let state = self.displayState()
      self.lastSentSignature = Self.signature(of: state)
      channel.invokeMethod("displayChanged", arguments: state)
      self.scheduleDisplayVerify()
    }
  }

  /// A late re-read, 0.35 s after the last push of a burst.
  ///
  /// UIKit flips a division region's `isActive` **after** the hinge
  /// interaction has reported the new status, so the payload sent from that
  /// handler can still carry the old region state — and on an unfold
  /// nothing follows it, because an unfold causes no layout pass and no
  /// metrics change. Measured on the simulator: opening from book left
  /// `hinge: fullyOpen` beside `division: active`, which would leave the
  /// app laying out around a crease that is no longer there. This settles
  /// it, and only sends when something the layout cares about differs, so
  /// it costs one extra call per pose change and none while nothing moves.
  private var displayVerify: DispatchWorkItem?
  private var lastSentSignature: String?

  private func scheduleDisplayVerify() {
    displayVerify?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.displayPushesWanted,
        let channel = self.displayChannel
      else { return }
      let state = self.displayState()
      let signature = Self.signature(of: state)
      guard signature != self.lastSentSignature else { return }
      self.lastSentSignature = signature
      channel.invokeMethod("displayChanged", arguments: state)
    }
    displayVerify = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
  }

  /// What the layout keys off, as one comparable string: the regions with
  /// their active flags, the bar edge, the orientation and the hinge's
  /// status. Deliberately not the angle or the update count, which change
  /// on every handler call and would make every re-read look different.
  private static func signature(of state: [String: Any]) -> String {
    var parts: [String] = [
      state["verticalBarEdge"] as? String ?? "",
      state["interfaceOrientation"] as? String ?? "",
      (state["hinge"] as? [String: Any])?["status"] as? String ?? "",
    ]
    let corner = state["cornerInsets"] as? [String: Any] ?? [:]
    for edge in ["left", "top", "right", "bottom"] {
      parts.append("\(corner[edge] ?? "")")
    }
    for region in state["regions"] as? [[String: Any]] ?? [] {
      parts.append(
        "\(region["kind"] ?? "")|\(region["x"] ?? "")|\(region["y"] ?? "")"
          + "|\(region["width"] ?? "")|\(region["height"] ?? "")"
          + "|\(region["active"] ?? "")")
    }
    return parts.joined(separator: ";")
  }

  // MARK: - Push sources

  private var layoutObserver: DisplayLayoutObserver?
  private var traitRegistration: Any?
  private var displayObserverAttempts = 0

  /// Installs the hinge interaction, the trait-change registration and the
  /// layout observer, once each. Idempotent and safe to call repeatedly:
  /// it runs at channel registration, on every `displayState`, and
  /// whenever the app becomes active.
  private func installDisplayObservers() {
    guard #available(iOS 27.1, *) else { return }
    guard let scene = Self.activeScene(),
      let hostWindow = scene.keyWindow ?? scene.windows.first,
      let controller = hostWindow.rootViewController
    else {
      // The scene is not connected yet. Keep trying for a few seconds;
      // `applicationDidBecomeActive` is the backstop after that.
      guard displayObserverAttempts < 40 else { return }
      displayObserverAttempts += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        self?.installDisplayObservers()
      }
      return
    }
    installHingeInteraction()
    installLayoutObserver(in: hostWindow)
    installTraitObserver(on: controller)
  }

  /// A window resize (rotation, Split View) reaches Dart as a metrics
  /// change already, but the reserved regions it implies do not, so the
  /// layout pass pushes too. Observed rather than subclassed: the
  /// `FlutterViewController` is built from the storyboard by the implicit
  /// engine, so there is nothing to subclass from the app delegate. The
  /// observer is an inert zero-alpha view behind the root view, sized to
  /// the window by its autoresizing mask, so its `layoutSubviews` runs in
  /// the same pass as the controller's `viewDidLayoutSubviews`.
  private func installLayoutObserver(in hostWindow: UIWindow) {
    guard layoutObserver == nil else { return }
    let observer = DisplayLayoutObserver(frame: hostWindow.bounds)
    observer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    observer.isUserInteractionEnabled = false
    observer.isAccessibilityElement = false
    observer.accessibilityElementsHidden = true
    observer.alpha = 0
    observer.onLayout = { [weak self] in self?.scheduleDisplayPush() }
    hostWindow.insertSubview(observer, at: 0)
    layoutObserver = observer
  }

  /// The traits that decide `verticalBarEdge`, plus both size classes so a
  /// Split View resize is caught even where the edge itself does not move.
  @available(iOS 27.1, *)
  private func installTraitObserver(on controller: UIViewController) {
    guard traitRegistration == nil else { return }
    var traits: [any UITraitDefinition.Type] =
      UITraitCollection.systemTraitsAffectingVerticalBarEdge
    traits.append(UITraitHorizontalSizeClass.self)
    traits.append(UITraitVerticalSizeClass.self)
    traitRegistration = controller.registerForTraitChanges(traits) {
      [weak self] (_: UIViewController, _: UITraitCollection) in
      self?.scheduleDisplayPush()
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

  /// Which view answers the display questions, best first.
  ///
  /// The whole Boardhop UI is one `UIView` under `FlutterViewController`,
  /// so that view is the one the layout cares about (research/12b). It is
  /// not guaranteed to be the view UIKit hangs the regions off, though, so
  /// the window is asked next and the answer says which one spoke.
  private func displayViews() -> [(String, UIView)] {
    var out: [(String, UIView)] = []
    // Boardhop is scene-based (`UIApplicationSceneManifest` in Info.plist),
    // where `FlutterAppDelegate.window` can be nil, so the scene's key
    // window is the one to start from and `window` is only a fallback.
    let windows = [
      Self.activeScene()?.keyWindow,
      Self.activeScene()?.windows.first,
      window,
    ].compactMap { $0 }
    for candidate in windows {
      if let controller = candidate.rootViewController {
        out.append(
          (controller is FlutterViewController ? "flutterView" : "rootView",
           controller.view))
      }
      out.append(("window", candidate))
    }
    return out
  }

  /// The Flutter view's reserved regions, as `[{kind, x, y, width, height,
  /// active, marginTop, marginLeft, marginBottom, marginRight, source}]` in
  /// that view's own coordinates (points).
  ///
  /// `reservedRegions(kind:options:)` is iOS 27.1 and the SDK on this Mac
  /// is 27.1, so this is the typed call the plan asked for; the old
  /// selector path passed an `NSNumber` where the API takes a
  /// `UIViewReservedRegionKind`, so it could never have answered anything.
  /// `includeInactive` matters: an iPhone Duo lying open flat still has a
  /// division region, and "this display folds" is what makes a page prefer
  /// an even number of columns.
  private func reservedRegions() -> [[String: Any]] {
    guard #available(iOS 27.1, *) else { return [] }
    for (source, view) in displayViews() {
      let regions = Self.regions(of: view, source: source)
      if !regions.isEmpty { return regions }
    }
    return []
  }

  @available(iOS 27.1, *)
  private static func regions(of view: UIView, source: String) -> [[String: Any]] {
    var out: [[String: Any]] = []
    let kinds: [(UIView.ReservedRegion.Kind, String)] = [
      (.division, "division"), (.occlusion, "occlusion"),
    ]
    for (kind, name) in kinds {
      for region in view.reservedRegions(kind: kind, options: .includeInactive) {
        out.append([
          "kind": name,
          "x": region.frame.origin.x,
          "y": region.frame.origin.y,
          "width": region.frame.size.width,
          "height": region.frame.size.height,
          "active": region.isActive,
          "marginTop": region.margins.top,
          "marginLeft": region.margins.left,
          "marginBottom": region.margins.bottom,
          "marginRight": region.margins.right,
          "source": source,
        ])
      }
    }
    return out
  }

  /// The corner-adapted safe area on the Flutter view, as
  /// `{left, top, right, bottom}` in points.
  ///
  /// An iPhone Duo reports **zero** padding on the top and leading edges
  /// in its wide pose and on its cover — the status bar lives in the
  /// trailing column — while the display's own corners are rounded, so a
  /// leading app-bar icon laid out against a zero inset is cut by the
  /// corner. `UIView.LayoutRegion.safeArea(cornerAdaptation:)` is Apple's
  /// answer: the region is pulled in far enough that a horizontal row of
  /// controls clears the curve. `.horizontal` is the axis a top bar wants.
  ///
  /// iOS 26, not 27.1: the layout regions shipped a release before the
  /// reserved regions did, so this answers on every iOS 26 device too.
  private func cornerInsets() -> [String: Any] {
    guard #available(iOS 26.0, *), let view = displayViews().first?.1 else {
      return Self.encode(.zero)
    }
    return Self.encode(view.edgeInsets(for: .safeArea(cornerAdaptation: .horizontal)))
  }

  /// The plain safe area beside both corner-adapted axes, for the Display
  /// probe page: what each query answers in this pose, measured.
  private func regionInsets() -> [String: Any] {
    guard #available(iOS 26.0, *), let view = displayViews().first?.1 else {
      return [:]
    }
    return [
      "safeArea": Self.encode(view.edgeInsets(for: .safeArea())),
      "cornerHorizontal": Self.encode(
        view.edgeInsets(for: .safeArea(cornerAdaptation: .horizontal))),
      "cornerVertical": Self.encode(
        view.edgeInsets(for: .safeArea(cornerAdaptation: .vertical))),
      "margins": Self.encode(view.edgeInsets(for: .margins())),
    ]
  }

  private static func encode(_ insets: UIEdgeInsets) -> [String: Any] {
    return [
      "left": insets.left, "top": insets.top,
      "right": insets.right, "bottom": insets.bottom,
    ]
  }

  /// `"leading"`, `"trailing"` or `"unspecified"`.
  ///
  /// The trait "reflects the system's preferred edge regardless of whether a
  /// vertical bar is currently visible", so it is the whole answer for where
  /// the rail goes; `unspecified` is both "this hardware never has one" and
  /// "not in this orientation", which is where today's rules stay.
  private func verticalBarEdge() -> String {
    guard #available(iOS 27.1, *), let view = displayViews().first?.1 else {
      return "unspecified"
    }
    switch view.traitCollection.verticalBarEdge {
    case .leading: return "leading"
    case .trailing: return "trailing"
    default: return "unspecified"
    }
  }

  /// The last hinge update, as `{status, angle}`.
  ///
  /// `status` is `closed`, `partiallyOpen`, `fullyOpen`, `unknown`, or
  /// `none` on hardware that does not fold (the update's `hinge` is nil
  /// there, and on anything before 27.1 there is no interaction at all).
  /// The interaction is added to the Flutter view once and kept; its
  /// handler is the only thing that ever learns the angle.
  private var hingeInteraction: Any?
  private var hingeStatusName = "unknown"
  private var hingeAngle: Double?

  /// How many times the interaction's handler has run, and which view it
  /// is attached to. Phase 0 needs to tell "the system says unknown" apart
  /// from "the handler never fired".
  private var hingeUpdates = 0
  private var hingeView = "none"

  private func hingeState() -> [String: Any] {
    guard #available(iOS 27.1, *) else { return ["status": "none"] }
    installHingeInteraction()
    var out: [String: Any] = [
      "status": hingeStatusName,
      "updates": hingeUpdates,
      "view": hingeView,
    ]
    if let hingeAngle { out["angle"] = hingeAngle }
    return out
  }

  @available(iOS 27.1, *)
  private func installHingeInteraction() {
    guard hingeInteraction == nil, let candidate = displayViews().first else { return }
    let (source, view) = candidate
    hingeView = source
    let interaction = UIHingeInteraction { [weak self] _, update in
      guard let self else { return }
      self.hingeUpdates += 1
      guard let hinge = update.hinge else {
        self.hingeStatusName = "none"
        self.hingeAngle = nil
        self.scheduleDisplayPush()
        return
      }
      self.hingeStatusName = switch hinge.status {
      case .closed: "closed"
      case .partiallyOpen: "partiallyOpen"
      case .fullyOpen: "fullyOpen"
      default: "unknown"
      }
      self.hingeAngle = Double(hinge.angle)
      self.scheduleDisplayPush()
    }
    view.addInteraction(interaction)
    hingeInteraction = interaction
  }
}

/// An inert view that reports the window's layout passes.
///
/// It draws nothing, takes no touches and is not an accessibility element;
/// it exists only so `layoutSubviews` can tell the app delegate that the
/// window laid out and the reserved regions may have moved.
private final class DisplayLayoutObserver: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    return nil
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

  /// The app delegate, which fans these out to the plugins. Weak because it
  /// owns this proxy; a strong reference back would be a retain cycle.
  private weak var inner: (any UNUserNotificationCenterDelegate)?

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
    // Let iOS present it. Android re-raises a foreground message itself
    // because FCM shows nothing while the app is open, and this first
    // copied that — but iOS does show remote pushes, so suppressing here
    // only made the phone silent once the replacement could not be
    // presented. Dart still hears about it through `onMessage`.
    completionHandler([.banner, .list, .sound])
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
