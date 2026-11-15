import AppKit
import Foundation

@main
struct SetDefaultBrowser {
  @MainActor
  static func main() async {
    guard CommandLine.arguments.count == 2 else {
      fputs("usage: set-default-browser APPLICATION_PATH\n", stderr)
      exit(2)
    }
    let application = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    do {
      // Completion follows any system consent prompt and the actual registration.
      for scheme in ["http", "https"] {
        try await NSWorkspace.shared.setDefaultApplication(
          at: application, toOpenURLsWithScheme: scheme)
      }
    } catch {
      fputs("Could not set the default browser: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}
