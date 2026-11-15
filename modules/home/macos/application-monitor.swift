// Event-only reconciliation. Subscribe before the initial disk/process snapshot.
import AppKit
import CoreServices
import Foundation

let arguments = CommandLine.arguments
if arguments.count < 3 { exit(64) }
let directory = arguments[1]
let executable = arguments[2]
let helperArguments = Array(arguments.dropFirst(3))
var pending: DispatchWorkItem?
var running = false
var dirty = false

func startHelper() {
  if running {
    dirty = true
    return
  }
  running = true
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = helperArguments
  process.terminationHandler = { _ in
    DispatchQueue.main.async {
      running = false
      if dirty {
        dirty = false
        reconcile()
      }
    }
  }
  do { try process.run() } catch {
    running = false
    fputs("Application lifecycle helper failed: \(error)\n", stderr)
    exit(1)  // launchd owns bounded restarts.
  }
}

func reconcile() {
  pending?.cancel()
  let task = DispatchWorkItem { startHelper() }
  pending = task
  DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: task)
}

let observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, _ in
  DispatchQueue.main.async { reconcile() }
}
let wake = NSWorkspace.shared.notificationCenter.addObserver(
  forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in reconcile() }
let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
  // A full scan also covers dropped/coalesced events and root replacement.
  reconcile()
}
// Watch the stable parent, so replacing the managed app directory is observed.
guard
  let stream = FSEventStreamCreate(
    nil, callback, nil,
    [URL(fileURLWithPath: directory).deletingLastPathComponent().path] as CFArray,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
  )
else { exit(1) }
FSEventStreamSetDispatchQueue(stream, .main)
guard FSEventStreamStart(stream) else {
  FSEventStreamInvalidate(stream)
  FSEventStreamRelease(stream)
  exit(1)
}
reconcile()
RunLoop.main.run()
FSEventStreamStop(stream)
FSEventStreamInvalidate(stream)
FSEventStreamRelease(stream)
NSWorkspace.shared.notificationCenter.removeObserver(wake)
withExtendedLifetime(observation) {}
