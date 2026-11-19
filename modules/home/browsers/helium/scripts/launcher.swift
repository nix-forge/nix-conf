import AppKit
import Foundation

// Launch Services delivers URLs and files as application events, not argv.
// This helper has its own identity; the vendor browser bundle stays unchanged.
final class Launcher: NSObject, NSApplicationDelegate {
  private var arguments = Array(CommandLine.arguments.dropFirst())
  private var scheduled = false
  private var ready = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    ready = true
    scheduleLaunch()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    arguments.append(contentsOf: urls.map(\.absoluteString))
    if ready { scheduleLaunch() }
  }

  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    arguments.append(contentsOf: filenames)
    sender.reply(toOpenOrPrint: .success)
    if ready { scheduleLaunch() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    scheduleLaunch()
    return false
  }

  private func scheduleLaunch() {
    guard !scheduled else { return }
    scheduled = true
    // Coalesce events already in AppKit's launch queue without a timer.
    DispatchQueue.main.async { self.launch() }
  }

  private func launch() {
    scheduled = false
    do {
      guard let resource = Bundle.main.url(forResource: "launcher", withExtension: "txt") else {
        throw NSError(
          domain: "HeliumLauncher", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Launcher resource is missing"])
      }
      let executable = try String(contentsOf: resource, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      arguments.removeAll()
      try process.run()
      // The shell/browser child owns its own lifetime. Exit this helper
      // after dispatch so it does not stay running across app updates.
      NSApplication.shared.terminate(nil)
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
      NSApplication.shared.terminate(nil)
    }
  }
}

let application = NSApplication.shared
let delegate = Launcher()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
