// duo-drag — synthetic taps and drags on the iPhone Duo's **inner** panel.
//
//   tool/duo-drag where                          (prints the mapping it found)
//   tool/duo-drag click X Y
//   tool/duo-drag press X Y [ms]
//   tool/duo-drag drag X1 Y1 X2 Y2 [ms]
//   tool/duo-drag holddrag X1 Y1 X2 Y2 [ms]      (long-press, then drag)
//
// X and Y are **device points** in the window the app sees (951 x 669 in the
// Duo's wide pose) — the same numbers `idb ui describe-all` prints, and the
// same ones the Flutter layout works in.
//
// Why this exists: idb's HID input only reaches the Duo's **cover** panel —
// `idb describe` reports the Duo as one 466 x 678 device and a coordinate tap
// on the inner panel lands nowhere (research/23 §9.4). `idb ui tap --api ax`
// reaches both, which is what `tool/shot-ios.sh press` uses, but accessibility
// has no long-press and no drag, so the Kanban board's `LongPressDraggable`
// cannot be exercised that way. A `CGEvent` mouse drag over Device Hub's
// rendered screen does reach the inner panel, including drags (§9.4), and that
// is what this posts.
//
// **Finding the rendered screen.** Not from the accessibility tree: Device Hub
// does expose the simulated screen as a group whose subrole is
// `iOSContentGroup`, and the app's own elements hang under it with frames of
// their own, but those frames are in an internal space — the group reads
// 626 x 890 at (285, 655) for a 951 x 669 display on a 1728 x 1117 desktop, so
// it is neither the right shape nor even on the desktop (measured 2026-09-20),
// and clicking there does nothing. What works is measuring the picture: the
// hub paints the device on a flat dark canvas, so a `screencapture` of its
// window has one bright rectangle in it and that rectangle is the screen.
// Verified the same day — the measurement gave origin (959, 323) and scale
// 0.676, and a click at device (909, 344) landed on the rail's Work
// destination, which `idb ui describe-all` puts at (873, 319.5) 72 x 50.
//
// That only works while the page on screen really is brighter than the hub's
// canvas all the way to its edges — a white list does, Home's two columns and
// a dark theme do not — so the measurement is checked against the panel's own
// aspect ratio and **refuses** rather than guessing. The reliable path is to
// measure once and then pin it: `DUO_OX`, `DUO_OY` (the screen's top-left in
// desktop points) and `DUO_SC` (device points to desktop points).
//
//   DUO_OX=959 DUO_OY=323 DUO_SC=0.6756 tool/duo-drag click 909 344
//
// `where` prints whichever mapping is in force, and is worth running before a
// drag matters. The pinned numbers hold until the hub's window is moved,
// resized or zoomed.
//
// Device Hub is brought to the front on every call: synthetic clicks only
// reach the front window, and `screencapture -R` captures the **desktop** in
// that rectangle, so a terminal over the hub would be measured instead of it.
//
// The panel's point size is read from `simctl io … screenshot` (pixels over a
// scale of 3; `DISPLAY=outer` for the cover) or given as `DUO_W` and `DUO_H`;
// the UDID comes from `DUO_UDID` or the first booted device named "iPhone Duo".
//
// Requires Accessibility permission for the terminal, screen-recording
// permission for `screencapture`, and Device Hub showing the panel you mean
// (`tool/duo-pose open`, `book` or `closed`). It moves the real mouse pointer,
// so do not use the Mac while it runs.

import ApplicationServices
import Cocoa

func attr(_ element: AXUIElement, _ name: String) -> Any? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value
}

func fail(_ message: String, code: Int32 = 2) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

@discardableResult
func shell(_ launchPath: String, _ arguments: [String]) -> (Int32, String) {
  let task = Process()
  task.executableURL = URL(fileURLWithPath: launchPath)
  task.arguments = arguments
  let pipe = Pipe()
  task.standardOutput = pipe
  task.standardError = Pipe()
  do { try task.run() } catch { return (-1, "") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  task.waitUntilExit()
  return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// Device Hub's process id; see `duo-pose.swift` for why the bundle lookup
/// alone is not enough (it answers with a placeholder whose pid is -1).
func deviceHubPid() -> pid_t? {
  let byBundle = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.apple.dt.Devices")
  if let real = byBundle.first(where: { $0.processIdentifier > 0 }) {
    return real.processIdentifier
  }
  if let running = NSWorkspace.shared.runningApplications.first(where: {
    $0.processIdentifier > 0
      && ($0.bundleIdentifier == "com.apple.dt.Devices"
        || $0.executableURL?.lastPathComponent == "DeviceHub")
  }) {
    return running.processIdentifier
  }
  let (status, out) = shell("/usr/bin/pgrep", ["-x", "DeviceHub"])
  guard status == 0, let first = out.split(separator: "\n").first,
    let pid = Int32(first.trimmingCharacters(in: .whitespaces))
  else { return nil }
  return pid
}

func frameOf(_ element: AXUIElement) -> CGRect? {
  var origin = CGPoint.zero
  var size = CGSize.zero
  guard let positionValue = attr(element, kAXPositionAttribute),
    let sizeValue = attr(element, kAXSizeAttribute)
  else { return nil }
  AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
  return CGRect(origin: origin, size: size)
}

/// Device Hub's biggest window: the one the device is drawn in.
///
/// Brings Device Hub to the front first, and not only so the clicks land: the
/// screen is measured with `screencapture -R`, which captures the **desktop**
/// in that rectangle, so a terminal overlapping the hub would be measured
/// instead of it (seen 2026-09-20 — the bright rectangle came back 5:1).
func hubWindow() -> CGRect {
  guard let pid = deviceHubPid() else {
    fail("duo-drag: Device Hub is not running. Open the iPhone Duo in it first.")
  }
  if let running = NSRunningApplication(processIdentifier: pid), !running.isActive {
    running.activate(options: [.activateAllWindows])
    usleep(400_000)
  }
  let application = AXUIElementCreateApplication(pid)
  guard let windows = attr(application, kAXWindowsAttribute) as? [AXUIElement] else {
    fail(
      "duo-drag: Device Hub exposes no windows. Grant this terminal "
        + "Accessibility permission (System Settings > Privacy & Security > Accessibility).")
  }
  let frames = windows.compactMap(frameOf).filter { $0.width > 200 && $0.height > 200 }
  guard let biggest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
    fail("duo-drag: no Device Hub window big enough to hold a device.")
  }
  return biggest
}

func duoUdid() -> String? {
  if let fromEnvironment = ProcessInfo.processInfo.environment["DUO_UDID"],
    !fromEnvironment.isEmpty
  {
    return fromEnvironment
  }
  let (_, out) = shell("/usr/bin/xcrun", ["simctl", "list", "devices", "booted"])
  for line in out.split(separator: "\n") where line.contains("iPhone Duo") {
    guard let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")")
    else { continue }
    return String(line[line.index(after: open)..<close])
  }
  return nil
}

func bitmapAt(_ path: String) -> NSBitmapImageRep? {
  guard let image = NSImage(contentsOfFile: path),
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  else { return nil }
  return NSBitmapImageRep(cgImage: cgImage)
}

/// The active panel's size in points, from a screenshot of it.
func displaySize() -> CGSize {
  let environment = ProcessInfo.processInfo.environment
  if let w = Double(environment["DUO_W"] ?? ""), let h = Double(environment["DUO_H"] ?? "") {
    return CGSize(width: w, height: h)
  }
  guard let udid = duoUdid() else {
    fail("duo-drag: no booted iPhone Duo; set DUO_UDID, or DUO_W and DUO_H.")
  }
  let display = environment["DISPLAY"] == "outer" ? 1 : 3
  let path = NSTemporaryDirectory() + "duo-drag-size.png"
  let (status, _) = shell(
    "/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--display=\(display)", path])
  defer { try? FileManager.default.removeItem(atPath: path) }
  guard status == 0, let bitmap = bitmapAt(path) else {
    fail("duo-drag: could not read the panel's size.")
  }
  return CGSize(width: Double(bitmap.pixelsWide) / 3, height: Double(bitmap.pixelsHigh) / 3)
}

/// The bright rectangle inside [window]: the rendered device screen, in
/// desktop points, or nil when what it found is not the panel's shape.
///
/// A convenience, not a contract. Device Hub paints the device on a flat dark
/// canvas, so with a light page on screen the hub's window has one bright
/// rectangle in it and that is the screen; the measurement is then checked
/// against the panel's own aspect ratio so a wrong answer fails loudly
/// instead of putting a drag somewhere unrelated. For anything that must not
/// miss — a dark page, a run where the answer matters — pass `DUO_OX`,
/// `DUO_OY` and `DUO_SC` and skip this entirely.
func renderedScreen(in window: CGRect, panel: CGSize) -> CGRect? {
  let path = NSTemporaryDirectory() + "duo-drag-window.png"
  let region =
    "\(Int(window.minX)),\(Int(window.minY)),\(Int(window.width)),\(Int(window.height))"
  let (status, _) = shell("/usr/sbin/screencapture", ["-x", "-R" + region, path])
  defer { try? FileManager.default.removeItem(atPath: path) }
  guard status == 0, let bitmap = bitmapAt(path) else {
    fail("duo-drag: screencapture of Device Hub's window failed.")
  }
  let wide = bitmap.pixelsWide
  let high = bitmap.pixelsHigh
  // Desktop points per captured pixel: the capture is at the backing scale.
  let perPixel = window.width / Double(wide)
  let step = max(1, wide / 400)
  func bright(_ x: Int, _ y: Int) -> Bool {
    (bitmap.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.55
  }
  let columns = stride(from: 0, to: wide, by: step).map { x in
    stride(from: 0, to: high, by: step).filter { bright(x, $0) }.count
  }
  let rows = stride(from: 0, to: high, by: step).map { y in
    stride(from: 0, to: wide, by: step).filter { bright($0, y) }.count
  }
  /// The run of lines carrying at least half the busiest line's count.
  func span(_ profile: [Int]) -> (Int, Int)? {
    guard let peak = profile.max(), peak > 4 else { return nil }
    let hits = profile.indices.filter { profile[$0] > peak / 2 }
    guard let first = hits.first, let last = hits.last, last > first else { return nil }
    return (first * step, last * step)
  }
  guard let (left, right) = span(columns), let (top, bottom) = span(rows) else { return nil }
  let rect = CGRect(
    x: window.minX + Double(left) * perPixel,
    y: window.minY + Double(top) * perPixel,
    width: Double(right - left) * perPixel,
    height: Double(bottom - top) * perPixel)
  let wanted = max(panel.width, panel.height) / min(panel.width, panel.height)
  let found = max(rect.width, rect.height) / min(rect.width, rect.height)
  // 2 % of the aspect is about ten points on this display.
  return abs(found - wanted) / wanted < 0.02 ? rect : nil
}

let environment = ProcessInfo.processInfo.environment
let device = displaySize()
let origin: CGPoint
let scale: Double
if let ox = Double(environment["DUO_OX"] ?? ""), let oy = Double(environment["DUO_OY"] ?? ""),
  let sc = Double(environment["DUO_SC"] ?? "")
{
  // The window still has to be in front for a synthetic click to reach it.
  _ = hubWindow()
  origin = CGPoint(x: ox, y: oy)
  scale = sc
} else {
  guard let screen = renderedScreen(in: hubWindow(), panel: device) else {
    fail(
      "duo-drag: nothing the panel's shape in Device Hub's window. Is the app on "
        + "the panel being shown? Otherwise pass DUO_OX/DUO_OY/DUO_SC.",
      code: 4)
  }
  origin = screen.origin
  // Both axes agree to within a pixel; the long side is the steadier one.
  scale = max(screen.width, screen.height) / max(device.width, device.height)
}

/// A device point as a desktop point.
func pt(_ x: Double, _ y: Double) -> CGPoint {
  CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
}

func post(_ type: CGEventType, _ point: CGPoint) {
  CGEvent(
    mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left
  )?.post(tap: .cghidEventTap)
}

/// A drag in forty steps over [milliseconds], held still for [hold] first so
/// a `LongPressDraggable` picks the card up before the pointer moves.
func drag(from: CGPoint, to: CGPoint, milliseconds: Double, hold: Double) {
  post(.mouseMoved, from)
  usleep(80_000)
  post(.leftMouseDown, from)
  if hold > 0 {
    usleep(UInt32(hold * 1000))
    post(.leftMouseDragged, from)
  }
  let steps = 40
  for step in 1...steps {
    let fraction = Double(step) / Double(steps)
    post(
      .leftMouseDragged,
      CGPoint(
        x: from.x + (to.x - from.x) * fraction,
        y: from.y + (to.y - from.y) * fraction))
    usleep(UInt32(milliseconds * 1000 / Double(steps)))
  }
  usleep(250_000)
  post(.leftMouseUp, to)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
  fail("usage: duo-drag where | click X Y | press X Y [ms] | drag X1 Y1 X2 Y2 [ms] | holddrag …")
}
func number(_ index: Int) -> Double {
  guard arguments.count > index, let value = Double(arguments[index]) else {
    fail("duo-drag: argument \(index) is not a number")
  }
  return value
}

switch command {
case "where":
  print(
    "origin (\(String(format: "%.1f", origin.x)), \(String(format: "%.1f", origin.y))) "
      + "scale \(String(format: "%.4f", scale)) "
      + "for a \(Int(device.width)) x \(Int(device.height)) pt panel; "
      + "device (0,0) -> \(pt(0, 0)) and "
      + "(\(Int(device.width)),\(Int(device.height))) -> \(pt(device.width, device.height))")
case "click":
  let point = pt(number(1), number(2))
  post(.mouseMoved, point)
  usleep(50_000)
  post(.leftMouseDown, point)
  usleep(60_000)
  post(.leftMouseUp, point)
  print("click at \(point)")
case "press":
  let point = pt(number(1), number(2))
  let milliseconds = arguments.count > 3 ? number(3) : 1200
  post(.mouseMoved, point)
  usleep(50_000)
  post(.leftMouseDown, point)
  usleep(UInt32(milliseconds * 1000))
  post(.leftMouseUp, point)
  print("press \(Int(milliseconds)) ms at \(point)")
case "drag", "holddrag":
  let from = pt(number(1), number(2))
  let to = pt(number(3), number(4))
  let milliseconds = arguments.count > 5 ? number(5) : 900
  drag(
    from: from, to: to, milliseconds: milliseconds,
    hold: command == "holddrag" ? 1400 : 0)
  print("\(command) \(from) -> \(to)")
default:
  fail("duo-drag: unknown command '\(command)'")
}
