import Foundation
import OSLog

/// OS-managed retention, private interpolation, and no raw Bluetooth payloads.
/// Debug diagnostics are opt-in for the current process only.
enum Log {
  private static let logger = Logger(subsystem: "com.raviteja.xmcontrol", category: "Bluetooth")
  private static let enabled = ProcessInfo.processInfo.environment["XMCONTROL_DIAGNOSTICS"] == "1"

  static func write(_ tag: String, _ message: String) {
    guard enabled else { return }
    logger.debug("[\(tag, privacy: .private)] \(message, privacy: .private)")
  }
}
