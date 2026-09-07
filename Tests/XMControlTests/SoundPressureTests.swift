import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import XMControl
#endif

extension ProtocolTests {
  func testCapturedXM5SoundPressureReplies() {
    // Captured 2026-09-07, WH-1000XM5 firmware 2.5.1. These are payloads,
    // not synthetic assumptions about the previously undocumented status byte.
    let capabilities: [UInt8] = [0x07, 0, 6, 0x41, 0x25, 0x50, 0xFF, 0xF2, 0xFF,
                                  0x32, 3, 0x31, 0xFF, 0xF8, 0x1E]
    let samples: [([UInt8], Int)] = [
      ([0x5B, 0, 0x46, 3], 70),
      ([0x5B, 0, 0x42, 3], 66),
      ([0x5B, 0, 0x43, 3], 67),
      ([0x5B, 0, 0x3E, 3], 62),
      ([0x5B, 0, 0x45, 3], 69),
      ([0x5B, 0, 0x49, 3], 73),
    ]
    var monitor = SoundPressureMonitor()
    let parser = MDRFrameParser()
    _ = monitor.nextRequest(at: 0)
    monitor.receive(capabilities, at: 0.1)
    XCTAssertEqual(monitor.support, .supported(.first))
    for (index, sample) in samples.enumerated() {
      let time = Double(index + 1) * 2
      XCTAssertEqual(monitor.nextRequest(at: time), [0x5A, 0])
      let wire = MDRFraming.encode(type: Wire.dataMDRNo2, seq: UInt8(index % 2), payload: sample.0)
      let frames = parser.feed(wire)
      XCTAssertEqual(frames.count, 1)
      for frame in frames { monitor.receive(frame.payload, at: time + 0.1) }
      XCTAssertEqual(monitor.state.decibels, sample.1)
    }
    _ = monitor.nextRequest(at: 20)
    XCTAssertNil(monitor.state.decibels)
    XCTAssertEqual(monitor.state, .stale)
  }

  func testTableTwoFramesRoundTripWithoutWeakeningValidation() {
    let payload: [UInt8] = [0x5B, 0, 0x3D, 0x03]
    let data = MDRFraming.encode(type: Wire.dataMDRNo2, seq: 1, payload: payload)
    for split in 0...data.count {
      let parser = MDRFrameParser()
      let frames = parser.feed(data.prefix(split)) + parser.feed(data.dropFirst(split))
      XCTAssertEqual(frames.count, 1)
      XCTAssertEqual(frames.first?.type, Wire.dataMDRNo2)
      XCTAssertEqual(frames.first?.payload, payload)
    }
    let parser = MDRFrameParser()
    XCTAssertTrue(parser.feed(MDRFraming.encode(type: 0x0F, seq: 0, payload: payload)).isEmpty)
    XCTAssertTrue(parser.feed(MDRFraming.encode(type: Wire.dataMDRNo2, seq: 3, payload: payload)).isEmpty)
  }

  func testSoundPressureCapabilityDiscovery() {
    XCTAssertEqual(SoundPressureCommand.getSupport, [0x06, 0])
    XCTAssertEqual(SoundPressureCommand.getReading(.first), [0x5A, 0])
    XCTAssertEqual(SoundPressureCommand.getReading(.second), [0x5A, 2])
    XCTAssertEqual(SoundPressureCommand.parseSupport([0x07, 0, 2, 0x30, 1, 0x50, 0]), .supported(.first))
    XCTAssertEqual(SoundPressureCommand.parseSupport([0x07, 0, 1, 0x52, 1]), .supported(.second))
    // A priority byte equal to a capability ID must not be mistaken for support.
    XCTAssertEqual(SoundPressureCommand.parseSupport([0x07, 0, 1, 0x30, 0x50]), .unsupported)
    XCTAssertEqual(SoundPressureCommand.parseSupport([0x07, 0, 0]), .unsupported)
    XCTAssertEqual(SoundPressureCommand.parseSupport([0x07, 0, 1, 0x51, 0]), .unsupported)
    for invalid: [UInt8] in [[], [7], [7, 0], [7, 0, 2, 0x50, 0], [7, 1, 0], [7, 0, 0, 0x50, 0], [7, 0, 255]] {
      XCTAssertNil(SoundPressureCommand.parseSupport(invalid))
    }
  }

  func testSoundPressureReadingsAndUnavailableCauses() {
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 72, 0x03], type: .first), .reading(72))
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 2, 61, 0x03], type: .second), .reading(61))
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 0, 0], type: .first), .notPlaying)
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 0, 1], type: .first), .inCall)
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 0, 2], type: .first), .notWorn)
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 255, 0x03], type: .first), .unavailable)
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 0, 0x03], type: .first), .unavailable)
    // Unknown status must not be assumed to mean a successful measurement.
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 72, 0xFF], type: .first), .unavailable)
    // Error states take precedence over a residual level byte.
    XCTAssertEqual(SoundPressureCommand.parseReading([0x5B, 0, 72, 1], type: .first), .inCall)
    for invalid: [UInt8] in [[], [0x5B], [0x5B, 0], [0x5B, 0, 72], [0x5B, 0, 72, 0x03, 0], [0x57, 0, 72, 0x03], [0x5B, 1, 72, 0x03], [0x5B, 0, 72, 4]] {
      XCTAssertNil(SoundPressureCommand.parseReading(invalid, type: .first))
    }
  }

  func testSoundPressurePollingAndStaleReadings() {
    var monitor = SoundPressureMonitor()
    XCTAssertEqual(monitor.nextRequest(at: 0), [6, 0])
    XCTAssertNil(monitor.nextRequest(at: 1))
    monitor.receive([7, 0, 1, 0x50, 0], at: 1)
    XCTAssertEqual(monitor.nextRequest(at: 1), [0x5A, 0])
    monitor.receive([0x5B, 0, 72, 0x03], at: 1.2)
    XCTAssertEqual(monitor.state.decibels, 72)
    XCTAssertNil(monitor.nextRequest(at: 2))
    XCTAssertEqual(monitor.nextRequest(at: 3), [0x5A, 0])
    // Truncated and wrong-subtype packets cannot keep an old value looking fresh.
    monitor.receive([0x5B, 0, 72], at: 5)
    monitor.receive([0x5B, 2, 72, 0x03], at: 5)
    _ = monitor.nextRequest(at: 7.3)
    XCTAssertEqual(monitor.state, .stale)
    XCTAssertNil(monitor.state.decibels)
    monitor.receive([0x5B, 0, 65, 0x03], at: 8)
    XCTAssertEqual(monitor.state, .reading(65))
    monitor.receive([0x5B, 0, 0, 0], at: 9)
    XCTAssertEqual(monitor.state, .notPlaying)
    XCTAssertNil(monitor.state.decibels)
    // Timer coalescing must not turn an approximately 2 s cadence into 4 s.
    var coalesced = SoundPressureMonitor()
    _ = coalesced.nextRequest(at: 0)
    coalesced.receive([7, 0, 1, 0x50, 0], at: 0.1)
    XCTAssertEqual(coalesced.nextRequest(at: 2.2), [0x5A, 0])
    XCTAssertNil(coalesced.nextRequest(at: 3.2))
    XCTAssertEqual(coalesced.nextRequest(at: 4.0), [0x5A, 0])
    monitor = SoundPressureMonitor()
    XCTAssertEqual(monitor.state, .waiting)
    XCTAssertNil(monitor.state.decibels)
  }

  func testSoundPressureDiscoveryTimeoutAndUnsupportedDevice() {
    var monitor = SoundPressureMonitor()
    for time in [0.0, 2.0, 4.0] { XCTAssertEqual(monitor.nextRequest(at: time), [6, 0]) }
    XCTAssertNil(monitor.nextRequest(at: 6))
    XCTAssertEqual(monitor.state, .unavailable)
    XCTAssertNil(monitor.nextRequest(at: 60))
    // A delayed, valid capability reply may recover discovery.
    monitor.receive([7, 0, 1, 0x52, 0], at: 61)
    XCTAssertEqual(monitor.nextRequest(at: 61), [0x5A, 2])
    _ = monitor.nextRequest(at: 68)
    XCTAssertEqual(monitor.state, .unavailable)
    monitor = SoundPressureMonitor()
    _ = monitor.nextRequest(at: 0)
    monitor.receive([7, 0, 0], at: 1)
    XCTAssertEqual(monitor.state, .unsupported)
    XCTAssertNil(monitor.nextRequest(at: 2))
    monitor.receive([0x5B, 0, 72, 0x03], at: 3)
    XCTAssertNil(monitor.state.decibels)
  }

  func testUnsolicitedTelemetryDoesNotEnableMonitoring() {
    var monitor = SoundPressureMonitor()
    monitor.receive([7, 0, 1, 0x50, 0], at: 0)
    monitor.receive([0x5B, 0, 72, 0x03], at: 0)
    XCTAssertNil(monitor.support)
    XCTAssertNil(monitor.state.decibels)
  }
}
