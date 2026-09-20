// duo-pose — fold, unfold and rotate the iPhone Duo simulator from a script.
//
//   tool/duo-pose closed | book | open | rotate [n] | list
//
// Xcode 27 replaced Simulator.app with **Device Hub** (bundle
// `com.apple.dt.Devices`, process `DeviceHub`), and there is no `simctl`,
// `devicectl`, defaults key or darwin notification that changes a foldable's
// pose (all checked 2026-09-20, research/23 §1.1). AppleScript's System
// Events cannot see Device Hub at all. The raw Accessibility API can: a
// window carries `AXButton`s whose `AXDescription` is `Closed`, `Book`,
// `Open`, `Rotate Right` (plus Home, Screenshot, Record), and `AXPress` on
// them drives the device. That is the control path Kelly settled on (D9):
// press by accessibility name, never by coordinates, so it survives the
// window being moved or resized.
//
// **The window is found by its buttons, not by its title** (phase 2, 2026-09-20):
// after Device Hub is relaunched the Duo shows inside Device Hub's browser
// window, whose title is then "Device Hub", and a `hasPrefix("iPhone Duo")`
// match found nothing at all. Every window of the process is searched instead
// (a title starting with "iPhone Duo" is still taken first, because it is one
// lookup rather than a walk), and the first one carrying a pose button wins.
// The walk is **depth-bounded**: the tree has recursive `AXApplication` nodes
// under it and an unbounded walk never returns.
//
// After a pose press the tool waits (up to ~8 s) until a
// `simctl io <udid> screenshot` of the display that pose activates stops
// being black: Closed activates the cover (display 1), Book and Open the
// inner display (display 3). The inactive panel captures as solid black, so
// that is the one reliable "the simulator has caught up" signal.
//
//   list      prints every button the Duo window exposes — run this first
//             when a Device Hub update renames one.
//   rotate n  presses Rotate Right n times (default 1; four returns).
//
// Requirements: Device Hub running with the Duo window open, and
// Accessibility permission for the terminal (System Settings > Privacy &
// Security > Accessibility). Exit 2 means the window was not found.
//
// The UDID comes from `xcrun simctl list devices booted` (the first booted
// device whose name contains "iPhone Duo") or from `DUO_UDID`.

import ApplicationServices
import Cocoa

// MARK: - Accessibility helpers

func attr(_ element: AXUIElement, _ name: String) -> Any? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value
}

func string(_ element: AXUIElement, _ name: String) -> String {
  (attr(element, name) as? String) ?? ""
}

/// Every `AXButton` of Device Hub's own chrome under `element`.
///
/// The simulated screen is in the same tree: its contents hang under a group
/// whose subrole is `iOSContentGroup`, so Boardhop's own buttons ("Wiki",
/// "Search", a repository tile) would otherwise show up here and a name could
/// collide with a pose button. That subtree is skipped.
///
/// The walk stops at `maxDepth`. Device Hub's tree contains `AXApplication`
/// nodes that point back up it, so an unbounded walk hangs; 16 is deeper than
/// any real chrome button has been seen (the pose buttons sit at about 6).
func buttons(_ element: AXUIElement, maxDepth: Int = 16) -> [(String, AXUIElement)] {
  if maxDepth <= 0 { return [] }
  if string(element, kAXSubroleAttribute) == "iOSContentGroup" { return [] }
  var found: [(String, AXUIElement)] = []
  if string(element, kAXRoleAttribute) == "AXButton" {
    let label = string(element, kAXDescriptionAttribute)
    found.append((label.isEmpty ? string(element, kAXTitleAttribute) : label, element))
  }
  for child in (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
    found.append(contentsOf: buttons(child, maxDepth: maxDepth - 1))
  }
  return found
}

/// The pose buttons this tool presses; a window carrying one of them is the
/// window the Duo is shown in, whatever it is called.
let poseButtons: Set<String> = ["Closed", "Book", "Open", "Rotate Right"]

func fail(_ message: String, code: Int32 = 2) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

/// Device Hub's process id.
///
/// `runningApplications(withBundleIdentifier:)` answers with a placeholder
/// whose `processIdentifier` is **-1** for Device Hub (seen 2026-09-20), which
/// no accessibility call can use, so any such entry is dropped and the
/// workspace list is searched by bundle id as well.
func deviceHubPid() -> pid_t? {
  let byBundle = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.apple.dt.Devices")
  if let real = byBundle.first(where: { $0.processIdentifier > 0 }) {
    return real.processIdentifier
  }
  let running = NSWorkspace.shared.runningApplications.first {
    $0.processIdentifier > 0
      && ($0.bundleIdentifier == "com.apple.dt.Devices"
        || $0.executableURL?.lastPathComponent == "DeviceHub")
  }
  if let running { return running.processIdentifier }
  // Last resort: Device Hub runs as the process `DeviceHub`.
  let (status, out) = shell("/usr/bin/pgrep", ["-x", "DeviceHub"])
  guard status == 0, let first = out.split(separator: "\n").first,
    let pid = Int32(first.trimmingCharacters(in: .whitespaces))
  else { return nil }
  return pid
}

/// The Device Hub window the Duo is shown in: the one carrying the pose
/// buttons. Its title is "iPhone Duo – iOS 27.1" when the device has a window
/// of its own and "Device Hub" when it is shown inside the browser window, so
/// the title is only a fast path and never the test.
func duoWindow() -> AXUIElement {
  guard let pid = deviceHubPid() else {
    fail(
      "duo-pose: Device Hub (com.apple.dt.Devices) is not running. "
        + "Open it from Xcode > Window > Device Hub and show the iPhone Duo.")
  }
  let element = AXUIElementCreateApplication(pid)
  guard let windows = attr(element, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty
  else {
    fail(
      "duo-pose: Device Hub exposes no windows. Grant this terminal "
        + "Accessibility permission (System Settings > Privacy & Security > Accessibility).")
  }
  let ordered =
    windows.filter { string($0, kAXTitleAttribute).hasPrefix("iPhone Duo") }
    + windows.filter { !string($0, kAXTitleAttribute).hasPrefix("iPhone Duo") }
  for window in ordered {
    if buttons(window).contains(where: { poseButtons.contains($0.0) }) { return window }
  }
  let titles = windows.map { "'\(string($0, kAXTitleAttribute))'" }.joined(separator: ", ")
  fail(
    "duo-pose: no Device Hub window carries the pose buttons (saw: \(titles)). "
      + "Open the iPhone Duo in Device Hub and leave its window on screen.")
}

// MARK: - Simulator

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

func duoUdid() -> String? {
  if let fromEnvironment = ProcessInfo.processInfo.environment["DUO_UDID"],
    !fromEnvironment.isEmpty
  {
    return fromEnvironment
  }
  let (_, out) = shell("/usr/bin/xcrun", ["simctl", "list", "devices", "booted"])
  for line in out.split(separator: "\n") where line.contains("iPhone Duo") {
    // "    iPhone Duo (58DEB6C0-…-…) (Booted)"
    guard let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")")
    else { continue }
    return String(line[line.index(after: open)..<close])
  }
  return nil
}

/// True when a screenshot of `display` has any pixel that is not black.
///
/// The panel that is not active on a Duo captures as solid black, which is
/// how this tool knows the pose landed.
func displayIsLit(udid: String, display: Int) -> Bool {
  let path = NSTemporaryDirectory() + "duo-pose-\(display).png"
  let (status, _) = shell(
    "/usr/bin/xcrun",
    ["simctl", "io", udid, "screenshot", "--display=\(display)", path])
  defer { try? FileManager.default.removeItem(atPath: path) }
  guard status == 0, let image = NSImage(contentsOfFile: path),
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  else { return false }
  let rep = NSBitmapImageRep(cgImage: cgImage)
  let steps = 12
  for row in 1..<steps {
    for column in 1..<steps {
      let x = rep.pixelsWide * column / steps
      let y = rep.pixelsHigh * row / steps
      guard let colour = rep.colorAt(x: x, y: y) else { continue }
      if colour.brightnessComponent > 0.06 { return true }
    }
  }
  return false
}

func waitForDisplay(udid: String, display: Int, seconds: Double = 8) -> Bool {
  let deadline = Date().addingTimeInterval(seconds)
  while Date() < deadline {
    if displayIsLit(udid: udid, display: display) { return true }
    Thread.sleep(forTimeInterval: 0.4)
  }
  return false
}

// MARK: - Commands

func press(_ description: String, in window: AXUIElement) {
  guard let button = buttons(window).first(where: { $0.0 == description })?.1 else {
    let names = buttons(window).map { "'\($0.0)'" }.joined(separator: ", ")
    fail("duo-pose: no button described '\(description)'. Buttons here: \(names)")
  }
  let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
  guard result == .success else {
    fail("duo-pose: AXPress on '\(description)' failed (\(result.rawValue))")
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
  fail("usage: duo-pose closed | book | open | rotate [n] | list")
}

let window = duoWindow()

switch command {
case "list":
  for (description, _) in buttons(window) {
    print(description.isEmpty ? "(unnamed)" : description)
  }
case "closed", "book", "open":
  // The button labels are capitalised in Device Hub.
  let label = command.prefix(1).uppercased() + command.dropFirst()
  // Closed lights the cover (display 1); Book and Open the inner one (3).
  let display = command == "closed" ? 1 : 3
  press(label, in: window)
  if let udid = duoUdid() {
    if waitForDisplay(udid: udid, display: display) {
      print("\(command): display \(display) is live")
    } else {
      fail("duo-pose: pressed \(label) but display \(display) stayed black after 8 s", code: 3)
    }
  } else {
    print("\(command): pressed (no booted iPhone Duo found, so no wait)")
    Thread.sleep(forTimeInterval: 2)
  }
case "rotate":
  let times = arguments.count > 1 ? (Int(arguments[1]) ?? 1) : 1
  for _ in 0..<max(1, times) {
    press("Rotate Right", in: window)
    Thread.sleep(forTimeInterval: 1.2)
  }
  print("rotate: pressed \(max(1, times)) time(s)")
default:
  fail("duo-pose: unknown command '\(command)'. Try closed | book | open | rotate [n] | list")
}
