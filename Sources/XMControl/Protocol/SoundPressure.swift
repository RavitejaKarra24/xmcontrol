import Foundation

// MDR V2 table 2 wire layout researched in mos9527/SonyHeadphonesClient,
// ProtocolV2.hpp and ProtocolV2T2.hpp (see Docs/SoundPressure.md).
// These opcodes overlap EQ in table 1: always send/parse using DATA_MDR_NO2.
enum SoundPressureCommand {
  static let getSupport: [UInt8] = [0x06, 0x00]

  enum HeadbandType: UInt8 {
    case first = 0x00
    case second = 0x02
  }

  enum Support: Equatable {
    case supported(HeadbandType)
    case unsupported
  }

  static func getReading(_ type: HeadbandType) -> [UInt8] { [0x5A, type.rawValue] }

  /// Count-prefixed pairs of (function ID, priority). Unknown functions are skipped.
  static func parseSupport(_ payload: [UInt8]) -> Support? {
    guard payload.count >= 3, payload[0] == 0x07, payload[1] == 0x00,
      payload.count == 3 + 2 * Int(payload[2]) else { return nil }
    let functions = stride(from: 3, to: payload.count, by: 2).map { payload[$0] }
    if functions.contains(0x50) { return .supported(.first) }
    if functions.contains(0x52) { return .supported(.second) }
    return .unsupported
  }

  /// Reply: [0x5B, inquiredType, levelPerPeriod, errorCause].
  /// A missing reading must never be presented as zero decibels.
  static func parseReading(_ payload: [UInt8], type: HeadbandType) -> SoundPressureState? {
    guard payload.count == 4, payload[0] == 0x5B, payload[1] == type.rawValue else { return nil }
    switch payload[3] {
    case 0x00: return .notPlaying
    case 0x01: return .inCall
    case 0x02: return .notWorn
    case 0xFF:
      // 0 and 255 are not treated as usable acoustic measurements.
      guard payload[2] > 0, payload[2] < 255 else { return .unavailable }
      return .reading(Int(payload[2]))
    default: return nil
    }
  }
}

enum SoundPressureState: Equatable {
  case waiting, reading(Int), notPlaying, inCall, notWorn, unavailable, unsupported, stale

  var decibels: Int? {
    if case .reading(let value) = self { return value }
    return nil
  }

  var title: String {
    switch self {
    case .waiting: return "Waiting for a reading"
    case .reading: return "Headphone-reported level"
    case .notPlaying: return "No audio playing"
    case .inCall: return "Unavailable during a call"
    case .notWorn: return "Headphones not worn"
    case .unavailable: return "Reading unavailable"
    case .unsupported: return "Not supported by this firmware"
    case .stale: return "Waiting for a fresh reading"
    }
  }

  var detail: String {
    switch self {
    case .reading: return "Updates about every 2 seconds. This is the headphone’s estimate, not a calibrated sound-level measurement."
    case .waiting: return "Checking Safe Listening support on your headphones."
    case .notPlaying: return "Play audio through your headphones to see its level."
    case .inCall: return "The live level will return when the call ends."
    case .notWorn: return "Put on your headphones and play audio to see its level."
    case .unsupported: return "Your headphones did not advertise compatible Safe Listening telemetry."
    case .unavailable: return "If this persists, enable Safe Listening in Sony Sound Connect, then reconnect here."
    case .stale: return "The last response is too old to display. Checking again automatically."
    }
  }
}

/// A deterministic polling state machine, kept separate from timers and Bluetooth.
/// No readings are persisted. Unsupported devices are never sent telemetry queries.
struct SoundPressureMonitor {
  static let pollInterval: TimeInterval = 2
  static let staleInterval: TimeInterval = 6
  private(set) var state: SoundPressureState = .waiting
  private(set) var support: SoundPressureCommand.Support?
  private var discoveryAttempts = 0
  private var lastRequestAt: TimeInterval?
  private var lastResponseAt: TimeInterval?
  private var firstReadingRequestAt: TimeInterval?

  mutating func nextRequest(at now: TimeInterval) -> [UInt8]? {
    if let lastResponseAt, now - lastResponseAt >= Self.staleInterval {
      state = .stale
    } else if lastResponseAt == nil, let firstReadingRequestAt,
              now - firstReadingRequestAt >= Self.staleInterval {
      state = .unavailable
    }
    guard lastRequestAt.map({ now - $0 >= Self.pollInterval }) ?? true else { return nil }
    switch support {
    case .none:
      guard discoveryAttempts < 3 else {
        state = .unavailable
        return nil
      }
      discoveryAttempts += 1
      lastRequestAt = now
      return SoundPressureCommand.getSupport
    case .unsupported: return nil
    case .supported(let type):
      lastRequestAt = now
      if firstReadingRequestAt == nil { firstReadingRequestAt = now }
      return SoundPressureCommand.getReading(type)
    }
  }

  mutating func receive(_ payload: [UInt8], at now: TimeInterval) {
    if support == nil, discoveryAttempts > 0, let discovered = SoundPressureCommand.parseSupport(payload) {
      support = discovered
      lastRequestAt = nil
      if discovered == .unsupported { state = .unsupported }
      return
    }
    guard case .supported(let type) = support, firstReadingRequestAt != nil,
      let reading = SoundPressureCommand.parseReading(payload, type: type) else { return }
    state = reading
    lastResponseAt = now
  }
}
