import Foundation

// MARK: - Ambient sound / noise cancelling

enum ANCMode: String, CaseIterable, Identifiable {
  case off
  case noiseCancelling
  case ambient

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off: return "Off"
    case .noiseCancelling: return "Noise Cancelling"
    case .ambient: return "Transparency"
    }
  }

  var shortTitle: String {
    switch self {
    case .off: return "Off"
    case .noiseCancelling: return "Noise cancel"
    case .ambient: return "Transparency"
    }
  }

  var symbol: String {
    switch self {
    case .off: return "speaker.minus"
    case .noiseCancelling: return "waveform.slash"
    case .ambient: return "waveform.and.person.filled"
    }
  }
}

/// Live state of the headphones' ambient-sound engine.
struct ANCState: Equatable {
  var mode: ANCMode = .noiseCancelling
  /// 1…20 on the wire. Only meaningful in `.ambient`. The device clamps 0 up
  /// to 1, so 1 is the true minimum rather than 0.
  var ambientLevel: Int = 20
  /// "Focus on Voice" — lets speech through while damping the rest.
  var voiceFocus: Bool = false
}

// MARK: - Equalizer

struct EQState: Equatable {
  /// Sony preset id. 0xA0 is "Custom" — the device switches to it
  /// automatically as soon as individual bands are written.
  var preset: UInt8 = EQPreset.custom.rawValue
  /// Six bands in wire order, each 0…20 with 10 = flat (±10 steps).
  var bands: [Int] = Array(repeating: 10, count: 6)

  static let flat = EQState()

  /// Band labels in wire order: Clear Bass (low shelf) first, then ascending.
  /// Established from the device's own presets rather than assumed — preset
  /// 0x16 ("Bass") reports [17,10,10,10,10,10] and 0x17 ("Speech") reports
  /// [0,14,13,11,12,0], which only makes sense with the low shelf at index 0
  /// and 16 kHz at index 5.
  static let bandLabels = ["Clear Bass", "400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"]
}

enum EQPreset: UInt8, CaseIterable, Identifiable {
  case off = 0x00
  case rock = 0x01
  case pop = 0x02
  case jazz = 0x03
  case dance = 0x04
  case edm = 0x05
  case rAndBHipHop = 0x06
  case acoustic = 0x07
  case bright = 0x10
  case excited = 0x11
  case mellow = 0x12
  case relaxed = 0x13
  case vocal = 0x14
  case treble = 0x15
  case bass = 0x16
  case speech = 0x17
  case custom = 0xA0

  var id: UInt8 { rawValue }

  var label: String {
    switch self {
    case .off: return "Off"
    case .rock: return "Rock"
    case .pop: return "Pop"
    case .jazz: return "Jazz"
    case .dance: return "Dance"
    case .edm: return "EDM"
    case .rAndBHipHop: return "R&B / Hip-Hop"
    case .acoustic: return "Acoustic"
    case .bright: return "Bright"
    case .excited: return "Excited"
    case .mellow: return "Mellow"
    case .relaxed: return "Relaxed"
    case .vocal: return "Vocal"
    case .treble: return "Treble Boost"
    case .bass: return "Bass Boost"
    case .speech: return "Speech"
    case .custom: return "Custom"
    }
  }
}

// MARK: - Speak-to-Chat

enum STCSensitivity: UInt8, CaseIterable, Identifiable {
  case auto = 0x00
  case high = 0x01
  case low = 0x02

  var id: UInt8 { rawValue }
  var label: String {
    switch self {
    case .auto: return "Auto"
    case .high: return "High"
    case .low: return "Low"
    }
  }
}

enum STCTimeout: UInt8, CaseIterable, Identifiable {
  case fast = 0x00  // ~5 s
  case mid = 0x01  // ~15 s
  case slow = 0x02  // ~30 s
  case none = 0x03  // stays open until music resumes manually

  var id: UInt8 { rawValue }
  var label: String {
    switch self {
    case .fast: return "Short (5 s)"
    case .mid: return "Standard (15 s)"
    case .slow: return "Long (30 s)"
    case .none: return "Manual"
    }
  }
}

// MARK: - Power

enum AutoPowerOffSetting: UInt8, CaseIterable, Identifiable {
  case whenRemoved = 0x10
  case disabled = 0x11

  var id: UInt8 { rawValue }
  var label: String {
    switch self {
    case .whenRemoved: return "When taken off"
    case .disabled: return "Never"
    }
  }
}

// MARK: - Battery

enum ChargingStatus: UInt8 {
  case notCharging = 0
  case charging = 1
  case unknown = 2
  case charged = 3
}

struct BatteryInfo: Equatable {
  var percent: Int
  var charging: ChargingStatus

  var display: String {
    switch charging {
    case .charging: return "\(percent)% ⚡︎"
    default: return "\(percent)%"
    }
  }
}
