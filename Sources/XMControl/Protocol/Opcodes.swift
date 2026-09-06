import Foundation

// Command IDs for MDR protocol V2, table 1 (DATA_MDR) and table 2
// (DATA_MDR_NO2). Extracted from Sony Sound Connect via the
// SonyHeadphonesClient / libmdr reverse-engineering effort (MIT), then
// verified live against a WH-1000XM5.

enum T1Command: UInt8 {
  case connectGetProtocolInfo = 0x00
  case connectRetProtocolInfo = 0x01
  case connectGetCapabilityInfo = 0x02
  case connectRetCapabilityInfo = 0x03
  case connectGetDeviceInfo = 0x04
  case connectRetDeviceInfo = 0x05
  case connectGetSupportFunction = 0x06
  case connectRetSupportFunction = 0x07

  case commonGetStatus = 0x12
  case commonRetStatus = 0x13
  case commonNtfyStatus = 0x15

  case powerGetStatus = 0x22
  case powerRetStatus = 0x23
  case powerSetStatus = 0x24
  case powerNtfyStatus = 0x25
  case powerGetParam = 0x26
  case powerRetParam = 0x27
  case powerSetParam = 0x28
  case powerNtfyParam = 0x29

  case eqebbGetParam = 0x56
  case eqebbRetParam = 0x57
  case eqebbSetParam = 0x58
  case eqebbNtfyParam = 0x59

  case ncAsmGetParam = 0x66
  case ncAsmRetParam = 0x67
  case ncAsmSetParam = 0x68
  case ncAsmNtfyParam = 0x69

  case playGetParam = 0xA6
  case playRetParam = 0xA7
  case playSetParam = 0xA8
  case playNtfyParam = 0xA9
  case playSetStatus = 0xA4

  case audioGetParam = 0xE6
  case audioRetParam = 0xE7
  case audioSetParam = 0xE8
  case audioNtfyParam = 0xE9

  case systemGetParam = 0xF6
  case systemRetParam = 0xF7
  case systemSetParam = 0xF8
  case systemNtfyParam = 0xF9
  case systemGetExtParam = 0xFA
  case systemRetExtParam = 0xFB
  case systemSetExtParam = 0xFC
  case systemNtfyExtParam = 0xFD
}

/// T1 support-function bits reported by CONNECT_RET_SUPPORT_FUNCTION.
enum T1Function: UInt8 {
  case batteryLevelIndicator = 0x20
  case autoPowerOffWithWearingDetection = 0x25
  case presetEq = 0x50
  case customEq = 0x55
  case modeNcAsmDualAmbientLevel = 0x6B  // -> inquired type 0x17 (XM5)
  case ambientSoundControlModeSelect = 0x69
  case connectionModeSoundConnection = 0xE1
  case upscalingAutoOff = 0xE2
}

// MARK: - Playback / value enums

enum PlaybackControl: UInt8 {
  case pause = 0x01
  case trackUp = 0x02
  case trackDown = 0x03
  case play = 0x07
}

enum AudioCodec: UInt8 {
  case unsettled = 0x00
  case sbc = 0x01
  case aac = 0x02
  case ldac = 0x10
  case aptX = 0x20
  case aptXHD = 0x21
  case lc3 = 0x30
  case other = 0xFF

  var label: String {
    switch self {
    case .unsettled: return "—"
    case .sbc: return "SBC"
    case .aac: return "AAC"
    case .ldac: return "LDAC"
    case .aptX: return "aptX"
    case .aptXHD: return "aptX HD"
    case .lc3: return "LC3"
    case .other: return "Other"
    }
  }
}
