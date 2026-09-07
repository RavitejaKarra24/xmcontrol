#if STANDALONE_TESTS
import Foundation

// A dependency-free runner for Command Line Tools installations without XCTest.
// The same test methods also run under XCTest with a full Xcode installation.
class XCTestCase {}
private var failures = 0
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
  if !value() { failures += 1; print("FAIL \(file):\(line): expected true") }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertTrue(!value(), file: file, line: line)
}
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertTrue(value() == nil, file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertTrue(lhs() == rhs(), file: file, line: line)
}
func XCTAssertLessThanOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
  XCTAssertTrue(lhs <= rhs, file: file, line: line)
}

@main
struct TestRunner {
  @MainActor static func main() async {
    let suite = ProtocolTests()
    let tests: [(String, () async -> Void)] = [
      ("round trips at every chunk boundary", suite.testEveryByteRoundTripsAcrossEverySplit),
      ("bounded stream buffering", suite.testNoiseAndUnterminatedFramesStayBoundedAndRecover),
      ("malformed frames and recovery", suite.testRejectsMalformedFramesAndResynchronizes),
      ("deterministic random stream", suite.testRandomStreamDoesNotPreventSubsequentFrame),
      ("EQ wire shapes", suite.testPresetAndCustomEQWireShapes),
      ("invalid payload rejection", suite.testRejectsInvalidPayloads),
      ("valid replies and notifications", suite.testValidRepliesAndNotifications),
      ("listening profiles", suite.testProfilesUseValidCustomCurvesAndListeningModes),
      ("saved curve validation", suite.testSavedCurveRejectsCorruptPreferences),
      ("offline action guards", suite.testOfflineActionsDoNotMutateHeadphoneState),
      ("captured XM5 sound-pressure replies", suite.testCapturedXM5SoundPressureReplies),
      ("table-2 framing", suite.testTableTwoFramesRoundTripWithoutWeakeningValidation),
      ("Safe Listening capability discovery", suite.testSoundPressureCapabilityDiscovery),
      ("sound-pressure replies and error causes", suite.testSoundPressureReadingsAndUnavailableCauses),
      ("poll cadence and stale readings", suite.testSoundPressurePollingAndStaleReadings),
      ("discovery timeout and unsupported firmware", suite.testSoundPressureDiscoveryTimeoutAndUnsupportedDevice),
      ("unsolicited telemetry rejection", suite.testUnsolicitedTelemetryDoesNotEnableMonitoring),
    ]
    for (name, test) in tests {
      let before = failures
      await test()
      print("\(failures == before ? "PASS" : "FAIL") \(name)")
    }
    print("\(tests.count) tests, \(failures) failures")
    exit(failures == 0 ? 0 : 1)
  }
}
#endif
