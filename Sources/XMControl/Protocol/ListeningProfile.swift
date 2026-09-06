import Foundation

/// App-authored starting points, using the XM5's six-band custom EQ format.
/// Profiles never change volume, connection priority, or power preferences.
enum ListeningProfile: String, CaseIterable, Identifiable {
  case focus, commute, aware, podcast

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var symbol: String {
    switch self {
    case .focus: return "moon.fill"
    case .commute: return "tram.fill"
    case .aware: return "ear.badge.waveform"
    case .podcast: return "mic.fill"
    }
  }
  var detail: String {
    switch self {
    case .focus: return "Quiet space. Balanced sound."
    case .commute: return "Less noise. A little more bass."
    case .aware: return "Let your surroundings in."
    case .podcast: return "Bring spoken words forward."
    }
  }
  var summary: String {
    switch self {
    case .focus: return "Noise cancelling · Flat EQ · Speak-to-Chat off"
    case .commute: return "Noise cancelling · Warm EQ · Speak-to-Chat off"
    case .aware: return "Transparency 20 · Flat EQ · Speak-to-Chat off"
    case .podcast: return "Noise cancelling · Voice EQ · Speak-to-Chat off"
    }
  }
  var anc: ANCState {
    ANCState(mode: self == .aware ? .ambient : .noiseCancelling,
             ambientLevel: 20, voiceFocus: false)
  }
  var eq: EQState {
    let bands: [Int]
    switch self {
    case .focus, .aware: bands = [10, 10, 10, 10, 10, 10]
    case .commute: bands = [13, 10, 10, 11, 11, 10]
    case .podcast: bands = [8, 11, 13, 12, 11, 9]
    }
    return EQState(preset: EQPreset.custom.rawValue, bands: bands)
  }

  func matches(anc: ANCState, eq: EQState, speakToChat: Bool) -> Bool {
    anc.mode == self.anc.mode && !anc.voiceFocus
      && (anc.mode != .ambient || anc.ambientLevel == self.anc.ambientLevel)
      && eq == self.eq && !speakToChat
  }
}

enum SavedEqualizer {
  static let key = "savedEqualizerBands"
  static func load(from defaults: UserDefaults = .standard) -> [Int]? {
    guard let bands = defaults.array(forKey: key) as? [Int],
      bands.count == 6, bands.allSatisfy({ (0...20).contains($0) }) else { return nil }
    return bands
  }
}
