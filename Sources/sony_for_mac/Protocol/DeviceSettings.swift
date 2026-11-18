import Foundation

// Device-level settings beyond sound: controls, multipoint, voice guidance and
// headphone confirmation alerts. Layouts follow libmdr's ProtocolV2T1/T2
// structs and were verified against a WH-1000XM5 on firmware 2.5.1 with a
// read-only probe, then set-and-restore round trips (see Docs/DeviceSettings.md).

// MARK: - Table 1 / table 2 opcodes added for these features

enum T1Ext {
  static let alertSetStatus: UInt8 = 0x94
  static let alertSetParam: UInt8 = 0x98
  static let alertNtfyParam: UInt8 = 0x99

  static let gsGetCapability: UInt8 = 0xD0
  static let gsRetCapability: UInt8 = 0xD1
  static let gsGetParam: UInt8 = 0xD6
  static let gsRetParam: UInt8 = 0xD7
  static let gsSetParam: UInt8 = 0xD8
  static let gsNtfyParam: UInt8 = 0xD9

  static let systemPlaybackByWearing: UInt8 = 0x01
  static let systemVoiceAssistant: UInt8 = 0x04
  static let ncAsmButton: UInt8 = 0x30
}

enum T2Command {
  static let periGetStatus: UInt8 = 0x32
  static let periRetStatus: UInt8 = 0x33
  static let periSetStatus: UInt8 = 0x34
  static let periNtfyStatus: UInt8 = 0x35
  static let periGetParam: UInt8 = 0x36
  static let periRetParam: UInt8 = 0x37
  static let periSetParam: UInt8 = 0x38
  static let periNtfyParam: UInt8 = 0x39
  static let periSetExtendedParam: UInt8 = 0x3C
  static let periNtfyExtendedParam: UInt8 = 0x3D

  static let voiceGuidanceGetParam: UInt8 = 0x46
  static let voiceGuidanceRetParam: UInt8 = 0x47
  static let voiceGuidanceSetParam: UInt8 = 0x48
  static let voiceGuidanceNtfyParam: UInt8 = 0x49

  /// PeripheralInquiredType. The XM5 advertises function 0x32 (device
  /// management with Bluetooth class of device) and 0x31 (source switch).
  static let periDeviceManagement: UInt8 = 0x02
  static let periSourceSwitch: UInt8 = 0x01
  /// VoiceGuidanceInquiredType for the XM5's advertised function 0x41.
  static let voiceGuidanceOnOff: UInt8 = 0x01
}

// MARK: - Models

/// What the NC/AMB button cycles through.
enum NCButtonMode: UInt8, CaseIterable, Identifiable {
  case all = 0x01
  case ncAmbient = 0x02
  case ncOff = 0x03
  case ambientOff = 0x04

  var id: UInt8 { rawValue }
  var label: String {
    switch self {
    case .all: return "Noise cancelling → Transparency → Off"
    case .ncAmbient: return "Noise cancelling ↔ Transparency"
    case .ncOff: return "Noise cancelling ↔ Off"
    case .ambientOff: return "Transparency ↔ Off"
    }
  }
  var shortLabel: String {
    switch self {
    case .all: return "NC · Transparency · Off"
    case .ncAmbient: return "NC · Transparency"
    case .ncOff: return "NC · Off"
    case .ambientOff: return "Transparency · Off"
    }
  }
}

/// The voice assistant reached by touching and holding the right ear cup.
enum VoiceAssistantSetting: Equatable {
  case device, google, alexa, unassigned, other(UInt8)

  init(raw: UInt8) {
    switch raw {
    case 0x30: self = .device
    case 0x31: self = .google
    case 0x32: self = .alexa
    case 0xFF: self = .unassigned
    default: self = .other(raw)
    }
  }

  static let deviceRaw: UInt8 = 0x30

  var label: String {
    switch self {
    case .device: return "Siri (this device's assistant)"
    case .google: return "Google Assistant"
    case .alexa: return "Amazon Alexa"
    case .unassigned: return "None"
    case .other: return "Set in Sound Connect"
    }
  }
}

/// A headphone "general setting" slot whose meaning is named by the device.
enum GeneralSettingKind: String {
  case touchPanel = "TOUCH_PANEL_SETTING"
  case multipoint = "MULTIPOINT_SETTING"
}

struct PairedDevice: Identifiable, Equatable {
  /// 17-character ASCII Bluetooth address, as the headphones send it.
  let address: String
  let name: String
  /// Non-zero connection slot when connected.
  let connectionSlot: UInt8
  let isPlaybackSource: Bool

  var id: String { address }
  var isConnected: Bool { connectionSlot != 0 }
}

struct PairedDeviceList: Equatable {
  var devices: [PairedDevice]
}

enum ConnectivityAction: UInt8 {
  case disconnect = 0x00
  case connect = 0x01
  case unpair = 0x02
}

struct ConnectivityResult: Equatable {
  let action: ConnectivityAction
  let code: UInt8
  let address: String

  var succeeded: Bool { code & 0x0F == 0x00 }
  var inProgress: Bool { code & 0x0F == 0x02 }

  var message: String {
    let verb: String
    switch action {
    case .connect: verb = "connect"
    case .disconnect: verb = "disconnect"
    case .unpair: verb = "forget"
    }
    switch code & 0x0F {
    case 0x00:
      switch action {
      case .connect: return "Connected."
      case .disconnect: return "Disconnected."
      case .unpair: return "Device forgotten."
      }
    case 0x02: return "Working on it…"
    case 0x03: return "Headphones are busy. Try again in a moment."
    default: return "Couldn't \(verb) that device."
    }
  }
}

/// A caution the headphones raise before applying certain changes.
struct HeadphoneAlert: Equatable, Identifiable {
  let messageType: UInt8
  /// 0x00 confirmation only, 0x01 positive/negative, 0x02 positive with reply.
  let actionType: UInt8

  var id: UInt8 { messageType }
  var needsAnswer: Bool { actionType == 0x01 || actionType == 0x02 }

  /// Cautions that only inform. They are confirmed automatically when they
  /// directly follow the user's own change, and shown as a notice.
  var isInformational: Bool {
    [0x08, 0x09, 0x0A, 0x0C, 0x1C].contains(messageType)
  }

  var title: String {
    switch messageType {
    case 0x00, 0x06, 0x07: return "Your headphones will reconnect"
    case 0x01: return "Your headphones will reconnect"
    case 0x0A, 0x0B: return "Turn off the touch panel?"
    case 0x0C, 0x0D: return "Turn on the touch panel?"
    case 0x08: return "Battery life"
    case 0x1C: return "Sound quality priority"
    case 0x1D: return "Firmware update in progress"
    default: return "Confirm on your headphones"
    }
  }

  var message: String {
    switch messageType {
    case 0x00:
      return "Changing the connection mode briefly disconnects your headphones."
    case 0x01:
      return "Changing this button briefly disconnects your headphones."
    case 0x06:
      return "Connecting to two devices turns off LDAC, and the headphones reconnect."
    case 0x07:
      return "Changing multipoint disconnects your headphones, then they reconnect."
    case 0x08:
      return "Using the equalizer with DSEE Extreme shortens battery life."
    case 0x09:
      return "Playback control is assigned to more than one control."
    case 0x0A:
      return "Taps and swipes on the right ear cup will stop working, including playback, volume and the voice assistant."
    case 0x0B:
      return "Taps and swipes will stop working, and the headphones reconnect."
    case 0x0C:
      return "Taps and swipes on the right ear cup will work again."
    case 0x0D:
      return "Taps and swipes will work again after the headphones reconnect."
    case 0x1C:
      return "Sound quality priority can make the connection less stable in busy places."
    case 0x1D:
      return "Wait for the firmware update to finish."
    default:
      return "Your headphones asked to confirm this change (code \(String(format: "%02X", messageType)))."
    }
  }
}

// MARK: - Builders and parsers

enum DeviceCmd {
  // MARK: Alerts

  /// Opts in to confirmation alerts. Without this, the XM5 silently refuses
  /// changes that need one, such as turning the touch panel off.
  static let enableAlerts: [UInt8] = [T1Ext.alertSetStatus, 0x00, 0x00]

  static func answerAlert(_ alert: HeadphoneAlert, positive: Bool) -> [UInt8] {
    [T1Ext.alertSetParam, 0x00, alert.messageType, positive ? 0x01 : 0x00]
  }

  /// `99 00 <message> <actionType>`
  static func parseAlert(_ p: [UInt8]) -> HeadphoneAlert? {
    guard p.count == 4, p[0] == T1Ext.alertNtfyParam, p[1] == 0x00, p[3] <= 0x02 else { return nil }
    return HeadphoneAlert(messageType: p[2], actionType: p[3])
  }

  // MARK: Pause when taken off (OnOffSettingValue: 0 = on)

  static let getPauseWhenRemoved: [UInt8] = [T1Command.systemGetParam.rawValue, T1Ext.systemPlaybackByWearing]

  static func setPauseWhenRemoved(_ on: Bool) -> [UInt8] {
    [T1Command.systemSetParam.rawValue, T1Ext.systemPlaybackByWearing, on ? 0x00 : 0x01]
  }

  static func parsePauseWhenRemoved(_ p: [UInt8]) -> Bool? {
    guard p.count == 3,
      p[0] == T1Command.systemRetParam.rawValue || p[0] == T1Command.systemNtfyParam.rawValue,
      p[1] == T1Ext.systemPlaybackByWearing, p[2] <= 1 else { return nil }
    return p[2] == 0x00
  }

  // MARK: Voice assistant

  static let getVoiceAssistant: [UInt8] = [T1Command.systemGetParam.rawValue, T1Ext.systemVoiceAssistant]

  static func setVoiceAssistant(_ raw: UInt8) -> [UInt8] {
    [T1Command.systemSetParam.rawValue, T1Ext.systemVoiceAssistant, raw]
  }

  static func parseVoiceAssistant(_ p: [UInt8]) -> VoiceAssistantSetting? {
    guard p.count == 3,
      p[0] == T1Command.systemRetParam.rawValue || p[0] == T1Command.systemNtfyParam.rawValue,
      p[1] == T1Ext.systemVoiceAssistant else { return nil }
    return VoiceAssistantSetting(raw: p[2])
  }

  // MARK: NC/AMB button

  static let getNCButton: [UInt8] = [T1Command.ncAsmGetParam.rawValue, T1Ext.ncAsmButton]

  static func setNCButton(_ mode: NCButtonMode) -> [UInt8] {
    [T1Command.ncAsmSetParam.rawValue, T1Ext.ncAsmButton, mode.rawValue]
  }

  static func parseNCButton(_ p: [UInt8]) -> NCButtonMode? {
    guard p.count == 3,
      p[0] == T1Command.ncAsmRetParam.rawValue || p[0] == T1Command.ncAsmNtfyParam.rawValue,
      p[1] == T1Ext.ncAsmButton else { return nil }
    return NCButtonMode(rawValue: p[2])
  }

  // MARK: General settings (touch panel, multipoint)

  /// The XM5 answers slots D1 and D2. Others are asked about but may stay silent.
  static let generalSettingSlots: [UInt8] = [0xD1, 0xD2, 0xD3, 0xD4]

  /// Display language 0x01 (English) for the capability's names.
  static func getGeneralSettingCapability(_ slot: UInt8) -> [UInt8] {
    [T1Ext.gsGetCapability, slot, 0x01]
  }

  static func getGeneralSetting(_ slot: UInt8) -> [UInt8] { [T1Ext.gsGetParam, slot] }

  /// Boolean type (0x00); GsSettingValue 0 = on.
  static func setGeneralSetting(_ slot: UInt8, on: Bool) -> [UInt8] {
    [T1Ext.gsSetParam, slot, 0x00, on ? 0x00 : 0x01]
  }

  /// `D1 <slot> <settingType> <stringFormat> <len> <name…> <len> <summary…>`.
  /// Only boolean settings named in `GeneralSettingKind` are recognised.
  static func parseGeneralSettingCapability(_ p: [UInt8]) -> (slot: UInt8, kind: GeneralSettingKind)? {
    guard p.count >= 6, p[0] == T1Ext.gsRetCapability,
      generalSettingSlots.contains(p[1]), p[2] == 0x00 else { return nil }
    let length = Int(p[4])
    guard length > 0, 5 + length <= p.count,
      let name = String(bytes: p[5..<(5 + length)], encoding: .ascii),
      let kind = GeneralSettingKind(rawValue: name) else { return nil }
    return (p[1], kind)
  }

  /// `D7|D9 <slot> 00 <value>`
  static func parseGeneralSetting(_ p: [UInt8]) -> (slot: UInt8, on: Bool)? {
    guard p.count == 4, p[0] == T1Ext.gsRetParam || p[0] == T1Ext.gsNtfyParam,
      generalSettingSlots.contains(p[1]), p[2] == 0x00, p[3] <= 1 else { return nil }
    return (p[1], p[3] == 0x00)
  }

  // MARK: Voice guidance (table 2)

  static let getVoiceGuidance: [UInt8] = [T2Command.voiceGuidanceGetParam, T2Command.voiceGuidanceOnOff]

  static func setVoiceGuidance(_ on: Bool) -> [UInt8] {
    [T2Command.voiceGuidanceSetParam, T2Command.voiceGuidanceOnOff, on ? 0x00 : 0x01]
  }

  /// Reply `47 01 <value> <language>`; notification `49 01 <value>`.
  static func parseVoiceGuidance(_ p: [UInt8]) -> Bool? {
    guard p.count >= 3, p[1] == T2Command.voiceGuidanceOnOff, p[2] <= 1 else { return nil }
    switch p[0] {
    case T2Command.voiceGuidanceRetParam: guard p.count <= 4 else { return nil }
    case T2Command.voiceGuidanceNtfyParam: guard p.count == 3 else { return nil }
    default: return nil
    }
    return p[2] == 0x00
  }

  // MARK: Multipoint devices (table 2)

  static let getPairedDevices: [UInt8] = [T2Command.periGetParam, T2Command.periDeviceManagement]
  static let getPairingMode: [UInt8] = [T2Command.periGetStatus, T2Command.periDeviceManagement]
  static let getAutoSwitch: [UInt8] = [T2Command.periGetParam, T2Command.periSourceSwitch]

  /// Inquiry-scan mode makes the headphones discoverable while staying connected.
  static func setPairingMode(_ on: Bool) -> [UInt8] {
    [T2Command.periSetStatus, T2Command.periDeviceManagement, on ? 0x01 : 0x00, 0x00]
  }

  /// 1 = switch to whichever device starts playing; 0 = keep the current source.
  static func setAutoSwitch(_ on: Bool) -> [UInt8] {
    [T2Command.periSetParam, T2Command.periSourceSwitch, on ? 0x01 : 0x00]
  }

  static func connectivity(_ action: ConnectivityAction, address: String) -> [UInt8]? {
    guard let bytes = addressBytes(address) else { return nil }
    return [T2Command.periSetExtendedParam, T2Command.periDeviceManagement, action.rawValue] + bytes
  }

  static func switchPlayback(to address: String) -> [UInt8]? {
    guard let bytes = addressBytes(address) else { return nil }
    return [T2Command.periSetExtendedParam, T2Command.periSourceSwitch] + bytes
  }

  /// `33|35 02 <btMode> <enableDisable>` — btMode 1 is pairing (inquiry scan).
  static func parsePairingMode(_ p: [UInt8]) -> Bool? {
    guard p.count == 4, p[0] == T2Command.periRetStatus || p[0] == T2Command.periNtfyStatus,
      p[1] == T2Command.periDeviceManagement, p[2] <= 1, p[3] <= 1 else { return nil }
    return p[2] == 0x01 && p[3] == 0x00
  }

  /// `37 01 <value>` reply, `39 01 <value> <result>` notification.
  static func parseAutoSwitch(_ p: [UInt8]) -> Bool? {
    guard p.count >= 3, p[1] == T2Command.periSourceSwitch, p[2] <= 1 else { return nil }
    switch p[0] {
    case T2Command.periRetParam: guard p.count == 3 else { return nil }
    case T2Command.periNtfyParam: guard p.count == 4 else { return nil }
    default: return nil
    }
    return p[2] == 0x01
  }

  /// `37|39 02 <count> { addr[17] slot cod[3] len name… } <playbackSlot>`
  static func parsePairedDevices(_ p: [UInt8]) -> PairedDeviceList? {
    guard p.count >= 4, p[0] == T2Command.periRetParam || p[0] == T2Command.periNtfyParam,
      p[1] == T2Command.periDeviceManagement else { return nil }
    let count = Int(p[2])
    guard count <= 16 else { return nil }
    var offset = 3
    var raw: [(address: String, slot: UInt8, name: String)] = []
    for _ in 0..<count {
      guard offset + 22 <= p.count,
        let address = parseAddress(Array(p[offset..<(offset + 17)])) else { return nil }
      offset += 17
      let slot = p[offset]
      offset += 1 + 3  // connection slot, then 24-bit class of device
      let length = Int(p[offset])
      offset += 1
      guard offset + length <= p.count else { return nil }
      let name = String(decoding: p[offset..<(offset + length)], as: UTF8.self)
      offset += length
      raw.append((address, slot, name))
    }
    guard offset + 1 == p.count else { return nil }
    let playbackSlot = p[offset]
    return PairedDeviceList(devices: raw.map {
      PairedDevice(
        address: $0.address,
        name: $0.name.isEmpty ? "Unnamed device" : $0.name,
        connectionSlot: $0.slot,
        isPlaybackSource: $0.slot != 0 && $0.slot == playbackSlot
      )
    })
  }

  /// `3D 02 <action> <result> addr[17]`
  static func parseConnectivityResult(_ p: [UInt8]) -> ConnectivityResult? {
    guard p.count == 21, p[0] == T2Command.periNtfyExtendedParam,
      p[1] == T2Command.periDeviceManagement,
      let action = ConnectivityAction(rawValue: p[2]),
      let address = parseAddress(Array(p[4..<21])) else { return nil }
    return ConnectivityResult(action: action, code: p[3], address: address)
  }

  /// `3D 01 <result> addr[17]` — result 0 is success.
  static func parsePlaybackSwitchResult(_ p: [UInt8]) -> (succeeded: Bool, code: UInt8)? {
    guard p.count == 20, p[0] == T2Command.periNtfyExtendedParam,
      p[1] == T2Command.periSourceSwitch,
      parseAddress(Array(p[3..<20])) != nil else { return nil }
    return (p[2] == 0x00, p[2])
  }

  static func playbackSwitchMessage(code: UInt8) -> String {
    switch code {
    case 0x00: return "Playback source switched."
    case 0x02: return "Can't switch during a call."
    case 0x03: return "That device isn't connected for audio."
    case 0x04: return "Can't switch while the voice assistant is active."
    default: return "Couldn't switch the playback source."
    }
  }

  // MARK: Addresses

  /// Comparison form: "aa-bb-cc-dd-ee-ff" or "aa:bb:…" become "AA:BB:…".
  static func normalizedAddress(_ address: String) -> String? {
    let hex = address.uppercased().replacingOccurrences(of: "-", with: ":")
    return parseAddress(Array(hex.utf8))
  }

  private static func parseAddress(_ bytes: [UInt8]) -> String? {
    guard bytes.count == 17 else { return nil }
    for (index, byte) in bytes.enumerated() {
      if index % 3 == 2 {
        guard byte == UInt8(ascii: ":") else { return nil }
      } else {
        let isHex = (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
        guard isHex else { return nil }
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  /// Sends an address back exactly as the headphones reported it.
  private static func addressBytes(_ address: String) -> [UInt8]? {
    parseAddress(Array(address.utf8)).map { Array($0.utf8) }
  }
}
