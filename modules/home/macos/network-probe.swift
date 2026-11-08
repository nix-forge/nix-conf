import Foundation
import Network

let arguments = CommandLine.arguments
guard arguments.count == 3, let number = UInt16(arguments[2]),
  let port = NWEndpoint.Port(rawValue: number)
else { exit(64) }
let connection = NWConnection(host: NWEndpoint.Host(arguments[1]), port: port, using: .tcp)
let queue = DispatchQueue(label: "LocalNetworkAcceptance")
var lastState = "setup"
var lastReason = "unknown"
var completed = false
func finish(_ ok: Bool) {
  if completed { return }
  completed = true
  let result: [String: Any] = ["ok": ok, "state": lastState, "reason": lastReason]
  if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
    let output = String(data: data, encoding: .utf8)
  {
    print(output)
  }
  connection.cancel()
  exit(ok ? 0 : 2)
}
connection.stateUpdateHandler = { state in
  lastState = String(describing: state)
  if let path = connection.currentPath { lastReason = String(describing: path.unsatisfiedReason) }
  switch state {
  case .ready: finish(true)
  case .failed: finish(false)
  default: break
  }
}
connection.start(queue: queue)
queue.asyncAfter(deadline: .now() + 5) { finish(false) }
dispatchMain()
