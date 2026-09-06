import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import XMControl
#endif

final class ProtocolTests: XCTestCase {
  func testEveryByteRoundTripsAcrossEverySplit() {
    let payload = Array(UInt8.min...UInt8.max)
    let encoded = MDRFraming.encode(type: Wire.dataMDR, seq: 1, payload: payload)
    for split in 0...encoded.count {
      let parser = MDRFrameParser()
      let frames = parser.feed(encoded.prefix(split)) + parser.feed(encoded.dropFirst(split))
      XCTAssertEqual(frames.count, 1)
      XCTAssertEqual(frames.first?.payload, payload)
      XCTAssertEqual(frames.first?.seq, 1)
    }
  }

  func testNoiseAndUnterminatedFramesStayBoundedAndRecover() {
    let parser = MDRFrameParser()
    XCTAssertTrue(parser.feed(Data(repeating: 0x11, count: 100_000)).isEmpty)
    XCTAssertEqual(parser.bufferedByteCount, 0)
    let broken = Data([Wire.sof, 0x0C, 0, 0, 0, 0x10, 0] + Array(repeating: UInt8(0), count: 100_000))
    XCTAssertTrue(parser.feed(broken).isEmpty)
    XCTAssertLessThanOrEqual(parser.bufferedByteCount, MDRFrameParser.maximumPayloadLength + 7)
    let good = MDRFraming.encode(type: Wire.dataMDR, seq: 0, payload: Cmd.getBattery)
    XCTAssertEqual(parser.feed(good).first?.payload, Cmd.getBattery)
  }

  func testRejectsMalformedFramesAndResynchronizes() {
    let parser = MDRFrameParser()
    let good = MDRFraming.encode(type: Wire.dataMDR, seq: 0, payload: [0x22, 0])
    var checksum = good
    checksum[checksum.count - 2] ^= 1
    let malformed: [Data] = [
      checksum,
      Data([0x3E, 0x0C, 0, 0, 0, 0, 0, 0x3D, 0x3C]), // dangling escape
      Data([0x3E, 0x0C, 0, 0, 0, 0, 0, 0x3D, 0x00, 0x3C]),
      MDRFraming.encode(type: Wire.dataMDR, seq: 2, payload: []),
      MDRFraming.encode(type: 0xFF, seq: 0, payload: []),
      MDRFraming.encode(type: Wire.dataAck, seq: 0, payload: [1]),
      Data([0x3E, 0x0C, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0x3C]),
      Data([0x3E, 0x0C, 0, 0, 0, 0, 0, 0x0C, 0, 0x3C]), // trailing byte
    ]
    for invalid in malformed {
      XCTAssertTrue(parser.feed(invalid).isEmpty)
      XCTAssertEqual(parser.feed(good).count, 1)
    }
    XCTAssertEqual(parser.feed(Data([Wire.sof, 0, 0]) + good).count, 1)
    XCTAssertEqual(parser.feed(good + good).count, 2)
  }

  func testRandomStreamDoesNotPreventSubsequentFrame() {
    let parser = MDRFrameParser()
    var seed: UInt64 = 42
    for _ in 0..<1000 {
      let bytes = (0..<97).map { _ -> UInt8 in
        seed = seed &* 6364136223846793005 &+ 1
        return UInt8(truncatingIfNeeded: seed >> 32)
      }
      _ = parser.feed(Data(bytes))
      XCTAssertLessThanOrEqual(parser.bufferedByteCount, MDRFrameParser.maximumPayloadLength + 7)
    }
    XCTAssertEqual(parser.feed(MDRFraming.encode(type: Wire.dataAck, seq: 1, payload: [])).count, 1)
  }

  func testPresetAndCustomEQWireShapes() {
    XCTAssertEqual(Cmd.setEQ(EQState(preset: EQPreset.bass.rawValue, bands: [10, 10, 10, 10, 10, 10])), [0x58, 0, 0x16, 0])
    XCTAssertEqual(Cmd.setEQ(EQState(bands: [-1, 99])), [0x58, 0, 0xA0, 6, 0, 20, 10, 10, 10, 10])
    XCTAssertEqual(Cmd.setEQ(.flat).count, 10)
  }

  func testRejectsInvalidPayloads() {
    XCTAssertNil(Cmd.parseBattery([0x23, 1, 50, 0]))
    XCTAssertNil(Cmd.parseBattery([0x23, 0, 255, 0]))
    XCTAssertNil(Cmd.parseANC([0x67, 0x17, 1, 1, 1, 0, 255]))
    XCTAssertNil(Cmd.parseANC([0x67, 0x16, 1, 1, 1, 0, 10]))
    XCTAssertNil(Cmd.parseEQ([0x57, 0, 0xA0, 1, 10]))
    XCTAssertNil(Cmd.parseEQ([0x57, 0, 0xA0, 6, 10, 10, 10, 10, 10, 255]))
    XCTAssertNil(Cmd.parseVolume([0xA7, 0x20, 31]))
    XCTAssertNil(Cmd.parseAudioFlag([0xE7, 1, 2], subType: 1))
    XCTAssertNil(Cmd.parseDeviceInfoString([0x05, 1, 3, 65, 10, 66]))
    XCTAssertNil(Cmd.parseDeviceInfoString([0x05, 1, 10, 65]))
    for count in 0..<4 {
      let truncated = Array(repeating: UInt8(0), count: count)
      XCTAssertNil(Cmd.parseBattery(truncated))
      XCTAssertNil(Cmd.parseANC(truncated))
      XCTAssertNil(Cmd.parseEQ(truncated))
      XCTAssertNil(Cmd.parseDeviceInfoString(truncated))
    }
  }

  func testValidRepliesAndNotifications() {
    XCTAssertEqual(Cmd.parseBattery([0x25, 0, 72, 1])?.percent, 72)
    XCTAssertEqual(Cmd.parseANC([0x69, 0x17, 1, 1, 1, 0, 20])?.mode, .ambient)
    XCTAssertEqual(Cmd.parseEQ([0x59, 0, 0xA0, 6, 10, 10, 10, 10, 10, 10]), .flat)
    XCTAssertEqual(Cmd.parseVolume([0xA9, 0x20, 0]), 0)
    XCTAssertEqual(Cmd.parseSpeakToChat([0xF9, 0x0C, 0]), true)
    XCTAssertEqual(Cmd.parseSpeakToChatDetail([0xFD, 0x0C, 1, 2])?.1, .slow)
    XCTAssertEqual(Cmd.parseAutoPowerOff([0x29, 5, 0x10, 0]), .whenRemoved)
    XCTAssertEqual(Cmd.parseDeviceInfoString([0x05, 2, 3, 49, 46, 48]), "1.0")
  }

  func testProfilesUseValidCustomCurvesAndListeningModes() {
    for profile in ListeningProfile.allCases {
      XCTAssertEqual(profile.eq.bands.count, 6)
      XCTAssertTrue(profile.eq.bands.allSatisfy { (0...20).contains($0) })
      XCTAssertEqual(Cmd.setEQ(profile.eq).count, 10)
      XCTAssertEqual(Cmd.setANC(profile.anc).count, 7)
      XCTAssertTrue(profile.matches(anc: profile.anc, eq: profile.eq, speakToChat: false))
      XCTAssertFalse(profile.matches(anc: profile.anc, eq: profile.eq, speakToChat: true))
    }
    XCTAssertEqual(ListeningProfile.aware.anc.mode, .ambient)
    XCTAssertEqual(ListeningProfile.podcast.eq.bands[2], 13)
  }

  func testSavedCurveRejectsCorruptPreferences() {
    let name = "XMControlTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    for invalid in [[1], [0, 1, 2, 3, 4, 21], [-1, 1, 2, 3, 4, 5]] {
      defaults.set(invalid, forKey: SavedEqualizer.key)
      XCTAssertNil(SavedEqualizer.load(from: defaults))
    }
    defaults.set(ListeningProfile.commute.eq.bands, forKey: SavedEqualizer.key)
    XCTAssertEqual(SavedEqualizer.load(from: defaults), ListeningProfile.commute.eq.bands)
  }

  @MainActor
  func testOfflineActionsDoNotMutateHeadphoneState() async {
    let controller = HeadphoneController()
    controller.applyProfile(.commute)
    controller.setVolume(30)
    controller.setMode(.ambient)
    controller.setBand(index: 0, wireValue: 20)
    controller.setDSEE(true)
    XCTAssertFalse(controller.isReady)
    XCTAssertEqual(controller.volume, 15)
    XCTAssertEqual(controller.eq, .flat)
    XCTAssertEqual(controller.anc.mode, .noiseCancelling)
    XCTAssertFalse(controller.dseeOn)
  }
}
