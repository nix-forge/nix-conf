import AppKit
import CoreServices
import Foundation

private struct BrowserError: LocalizedError {
  let message: String

  var errorDescription: String? { message }

  init(_ message: String) {
    self.message = message
  }
}

private struct BundleInfo: Decodable {
  let identifier: String
  let version: String
  let shortVersion: String

  enum CodingKeys: String, CodingKey {
    case identifier = "CFBundleIdentifier"
    case version = "CFBundleVersion"
    case shortVersion = "CFBundleShortVersionString"
  }
}

private func log(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func registrationDump(using executable: String) throws -> String {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = ["-dump"]
  process.standardOutput = output
  try process.run()
  // Drain the pipe before waiting so a large Launch Services database cannot block the child.
  let data = try output.fileHandleForReading.readToEnd() ?? Data()
  process.waitUntilExit()
  guard process.terminationReason == .exit, process.terminationStatus == 0 else {
    throw BrowserError("lsregister -dump failed (status \(process.terminationStatus))")
  }
  guard let dump = String(data: data, encoding: .utf8) else {
    throw BrowserError("lsregister -dump did not return valid UTF-8")
  }
  return dump
}

private func registration(for path: String, in dump: String) -> (id: String, version: String)? {
  let records = dump.split(whereSeparator: \.isNewline).split { line in
    line.allSatisfy { $0 == "-" }
  }
  for record in records {
    func field(_ prefix: String) -> String {
      for line in record {
        let text = line.drop(while: \.isWhitespace)
        if text.hasPrefix(prefix) {
          return text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
      }
      return ""
    }

    let registeredPath = field("path:")
    // The final parenthesized field is a record key. App names can contain parentheses.
    guard let suffix = registeredPath.range(of: " (", options: .backwards),
      registeredPath.hasSuffix(")"),
      registeredPath[..<suffix.lowerBound] == path
    else {
      continue
    }
    let version = field("version:").prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
    return (field("identifier:"), version)
  }
  return nil
}

@MainActor
private func setDefaultBrowser(path: String, label: String, lsregister: String) async throws {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
    isDirectory.boolValue
  else {
    throw BrowserError("managed \(label) application was not found at \(path)")
  }

  let app = URL(fileURLWithPath: path, isDirectory: true)
  let plist = app.appendingPathComponent("Contents/Info.plist")
  let info: BundleInfo
  do {
    info = try PropertyListDecoder().decode(BundleInfo.self, from: Data(contentsOf: plist))
  } catch {
    throw BrowserError("could not read bundle identity at \(plist.path) (\(error))")
  }
  guard !info.identifier.isEmpty, !info.version.isEmpty else {
    throw BrowserError("bundle identifier and version must be nonempty at \(plist.path)")
  }

  log("refreshing \(label) Launch Services registration...")
  let status = LSRegisterURL(app as CFURL, true)
  guard status == 0 else {
    throw BrowserError("could not register \(path) with Launch Services (OSStatus \(status))")
  }
  // The registration dump exposes the cached version independently of the on-disk plist.
  let dump = try registrationDump(using: lsregister)
  guard let entry = registration(for: path, in: dump) else {
    throw BrowserError("Launch Services does not have a registration entry for \(path)")
  }
  guard entry.id == info.identifier else {
    throw BrowserError(
      "Launch Services registered bundle id \(entry.id) for \(path), expected \(info.identifier)")
  }
  guard entry.version == info.version else {
    throw BrowserError(
      "Launch Services reports \(label) bundle version \(entry.version), "
        + "expected \(info.version) (\(info.shortVersion))")
  }

  let workspace = NSWorkspace.shared
  let urls = try ["http", "https"].map { scheme in
    guard let url = URL(string: "\(scheme)://example.invalid/") else {
      throw BrowserError("could not construct a \(scheme) URL")
    }
    return (scheme, url)
  }
  log("setting \(label) as the default browser...")
  for (scheme, _) in urls {
    // Completion follows any system consent prompt.
    do {
      try await workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme)
    } catch {
      throw BrowserError("could not set \(label) for \(scheme) (\(error.localizedDescription))")
    }
  }
  for (scheme, url) in urls {
    let current = workspace.urlForApplication(toOpen: url).flatMap { Bundle(url: $0) }
    guard current?.bundleIdentifier == info.identifier else {
      let handler = current?.bundleIdentifier ?? "none"
      throw BrowserError("failed to set \(label) for \(scheme); current handler is \(handler)")
    }
  }
}

@main
private struct SetDefaultBrowser {
  @MainActor
  static func main() async {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else {
      log("usage: hm-set-default-browser APP LABEL LSREGISTER")
      exit(2)
    }
    do {
      try await setDefaultBrowser(path: arguments[1], label: arguments[2], lsregister: arguments[3])
    } catch {
      log("hm-set-default-browser: \(error.localizedDescription)")
      exit(1)
    }
  }
}
