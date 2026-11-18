import Foundation

// Builders for every payload the app sends, and parsers for the replies.
// Byte layouts mirror Sony Sound Connect's serialization (via libmdr), with
// XM5-specific shapes verified on hardware.
//
// Two easily-confused value conventions in this protocol:
//  - EnableDisable / OnOffSettingValue (Speak-to-Chat, auto pause…): 0 = ON, 1 = OFF
//  - NcAsmOnOffValue / upscaling (total effect, DSEE):                 1 = ON, 0 = OFF

@inline(__always) private func invertedEnabledByte(_ on: Bool) -> UInt8 { on ? 0x00 : 0x01 }

/// Inquired type for NC/ASM on the XM5:
/// MODE_NC_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS. Note the XM5 puts the
/// equalizer on table 0x00 — querying 0x03 (ULT series) returns nothing at all.
private let ncAsmTypeXM5: UInt8 = 0x17

enum Cmd {
  // MARK: Requests

  /// Protocol handshake — must be sent once after the channel opens.
  static let initHandshake: [UInt8] = [T1Command.connectGetProtocolInfo.rawValue, 0x00]

  static let getBattery: [UInt8] = [T1Command.powerGetStatus.rawValue, 0x00]
  static let getANC: [UInt8] = [T1Command.ncAsmGetParam.rawValue, ncAsmTypeXM5]
  static let getEQ: [UInt8] = [T1Command.eqebbGetParam.rawValue, 0x00]
  static let getVolume: [UInt8] = [T1Command.playGetParam.rawValue, 0x20]

  /// Model (type 1) / firmware version (type 2), length-prefixed ASCII.
  static func getDeviceInfo(_ type: UInt8) -> [UInt8] {
    [T1Command.connectGetDeviceInfo.rawValue, type]
  }

  static let getDSEE: [UInt8] = [T1Command.audioGetParam.rawValue, 0x01]
  static let getConnectionMode: [UInt8] = [T1Command.audioGetParam.rawValue, 0x00]
  static let getAutoPowerOff: [UInt8] = [T1Command.powerGetParam.rawValue, 0x05]
  static let getSpeakToChat: [UInt8] = [T1Command.systemGetParam.rawValue, 0x0C]
  static let getSpeakToChatDetail: [UInt8] = [T1Command.systemGetExtParam.rawValue, 0x0C]

  // MARK: Setters

  /// `[68 17 01 enabled ambient voiceFocus level]`
  ///
  /// The SET body mirrors the GET reply exactly. Verified on hardware: the
  /// 8-byte variant used by some other Sony models (with an extra 0x02 before
  /// the level) silently pins the XM5's ambient level to 1 — levels only take
  /// when the byte sits at index 6.
  static func setANC(_ s: ANCState) -> [UInt8] {
    let enabled: UInt8 = (s.mode == .off) ? 0x00 : 0x01
    let ambient: UInt8 = (s.mode == .ambient) ? 0x01 : 0x00
    let level = UInt8(clamping: max(1, min(20, s.ambientLevel)))
    return [
      T1Command.ncAsmSetParam.rawValue, ncAsmTypeXM5, 0x01,
      enabled, ambient, s.voiceFocus ? 0x01 : 0x00, level,
    ]
  }

  /// `[58 00 preset count b1…b6]` or `[58 00 preset 0]` to just pick a preset.
  /// Bands are wire values (0…20); the device auto-switches to the Custom
  /// preset as soon as individual bands are written.
  static func setEQ(_ eq: EQState) -> [UInt8] {
    var out: [UInt8] = [
      T1Command.eqebbSetParam.rawValue, 0x00,
      eq.preset, eq.preset == EQPreset.custom.rawValue ? 6 : 0,
    ]
    if eq.preset == EQPreset.custom.rawValue {
      for index in 0..<6 {
        let value = eq.bands.indices.contains(index) ? eq.bands[index] : 10
        out.append(UInt8(clamping: max(0, min(20, value))))
      }
    }
    return out
  }

  static func setVolume(_ level: Int) -> [UInt8] {
    [T1Command.playSetParam.rawValue, 0x20, UInt8(clamping: max(0, min(30, level)))]
  }

  static func playbackControl(_ control: PlaybackControl) -> [UInt8] {
    [T1Command.playSetStatus.rawValue, 0x01, 0x00, control.rawValue]
  }

  static let powerOff: [UInt8] = [T1Command.powerSetStatus.rawValue, 0x03, 0x01]

  /// Upscaling = DSEE Extreme. 1 = on, 0 = off.
  static func setDSEE(_ on: Bool) -> [UInt8] {
    [T1Command.audioSetParam.rawValue, 0x01, on ? 0x01 : 0x00]
  }

  /// Bluetooth priority. 0 = sound quality prior, 1 = stable connection.
  static func setConnectionMode(qualityPrior: Bool) -> [UInt8] {
    [T1Command.audioSetParam.rawValue, 0x00, qualityPrior ? 0x00 : 0x01]
  }

  /// The XM5 only supports wear-detection based auto power-off; its
  /// predecessors' timed options are accepted on the wire but never applied.
  static func setAutoPowerOff(_ setting: AutoPowerOffSetting) -> [UInt8] {
    [T1Command.powerSetParam.rawValue, 0x05, setting.rawValue, 0x00]
  }

  static func setSpeakToChat(_ on: Bool) -> [UInt8] {
    // EnableDisable convention: 0 = ON, 1 = OFF.
    [T1Command.systemSetParam.rawValue, 0x0C, invertedEnabledByte(on), 0x01]
  }

  static func setSpeakToChatDetail(sensitivity: STCSensitivity, timeout: STCTimeout) -> [UInt8] {
    [T1Command.systemSetExtParam.rawValue, 0x0C, sensitivity.rawValue, timeout.rawValue]
  }

  // MARK: Response decoding

  /// `23 00 <level> <charging>` in reply to a request, or `25 00 …` when the
  /// headphones report a change on their own.
  static func parseBattery(_ p: [UInt8]) -> BatteryInfo? {
    guard p.count >= 4,
      p[0] == T1Command.powerRetStatus.rawValue
        || p[0] == T1Command.powerNtfyStatus.rawValue
    else { return nil }
    guard p[1] == 0x00, p[2] <= 100 else { return nil }
    return BatteryInfo(
      percent: max(0, min(100, Int(p[2]))),
      charging: ChargingStatus(rawValue: p[3]) ?? .unknown
    )
  }

  /// `67 17 01 <enabled> <ambient> <voiceFocus> <level>` (or `69 17 …` notify)
  static func parseANC(_ p: [UInt8]) -> ANCState? {
    guard p.count >= 7,
      p[0] == T1Command.ncAsmRetParam.rawValue
        || p[0] == T1Command.ncAsmNtfyParam.rawValue
    else { return nil }
    guard p[1] == ncAsmTypeXM5, p[2] == 1, p[3] <= 1, p[4] <= 1,
      p[5] <= 1, (1...20).contains(p[6]) else { return nil }
    let enabled = p[3] != 0
    let ambient = p[4] != 0
    let mode: ANCMode = !enabled ? .off : (ambient ? .ambient : .noiseCancelling)
    return ANCState(mode: mode, ambientLevel: Int(p[6]), voiceFocus: p[5] != 0)
  }

  /// `57 00 <preset> <count> <b1…bN>` (or `59 …` notify)
  static func parseEQ(_ p: [UInt8]) -> EQState? {
    guard p.count >= 4,
      p[0] == T1Command.eqebbRetParam.rawValue
        || p[0] == T1Command.eqebbNtfyParam.rawValue
    else { return nil }
    let count = Int(p[3])
    guard p[1] == 0x00, count == 6, p.count == 4 + count,
      p[4...].allSatisfy({ $0 <= 20 }) else { return nil }
    return EQState(preset: p[2], bands: p[4..<(4 + count)].map(Int.init))
  }

  /// `A7 20 <level>` (or `A9 …` notify) — 0…30.
  static func parseVolume(_ p: [UInt8]) -> Int? {
    guard p.count >= 3,
      p[0] == T1Command.playRetParam.rawValue
        || p[0] == T1Command.playNtfyParam.rawValue,
      p[1] == 0x20, p[2] <= 30
    else { return nil }
    return Int(p[2])
  }

  /// `E7 <subType> <value>` (or `E9 …`) — DSEE is sub-type 0x01.
  static func parseAudioFlag(_ p: [UInt8], subType: UInt8) -> Bool? {
    guard p.count >= 3,
      p[0] == T1Command.audioRetParam.rawValue
        || p[0] == T1Command.audioNtfyParam.rawValue,
      p[1] == subType, p[2] <= 1
    else { return nil }
    return p[2] != 0
  }

  /// `F7 0C <enabledByte>` — EnableDisable convention, 0 = ON.
  static func parseSpeakToChat(_ p: [UInt8]) -> Bool? {
    guard p.count >= 3, (p[0] == T1Command.systemRetParam.rawValue || p[0] == T1Command.systemNtfyParam.rawValue),
      p[1] == 0x0C, p[2] <= 1
    else { return nil }
    return p[2] == 0x00
  }

  /// `FB 0C <sensitivity> <timeout>`
  static func parseSpeakToChatDetail(_ p: [UInt8]) -> (STCSensitivity, STCTimeout)? {
    guard p.count >= 4, (p[0] == T1Command.systemRetExtParam.rawValue || p[0] == T1Command.systemNtfyExtParam.rawValue),
      p[1] == 0x0C,
      let sens = STCSensitivity(rawValue: p[2]),
      let to = STCTimeout(rawValue: p[3])
    else { return nil }
    return (sens, to)
  }

  /// `27 05 <c0> <c1>` — 10 00 = power off when taken off, 11 00 = never.
  static func parseAutoPowerOff(_ p: [UInt8]) -> AutoPowerOffSetting? {
    guard p.count >= 4, (p[0] == T1Command.powerRetParam.rawValue || p[0] == T1Command.powerNtfyParam.rawValue),
      p[1] == 0x05, p[3] == 0
    else { return nil }
    return AutoPowerOffSetting(rawValue: p[2])
  }

  /// Device info block — `37 <type> <len> <ascii…>`.
  static func parseDeviceInfoString(_ p: [UInt8]) -> String? {
    guard p.count > 3, p[0] == T1Command.connectRetDeviceInfo.rawValue else { return nil }
    let n = Int(p[2])
    guard n > 0, n <= 128, 3 + n <= p.count,
      [UInt8(1), 2].contains(p[1]),
      p[3..<(3 + n)].allSatisfy({ (0x20...0x7E).contains($0) }),
      let s = String(bytes: p[3..<(3 + n)], encoding: .ascii)
    else { return nil }
    return s
  }
}
