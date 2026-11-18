import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import sony_for_mac
#endif

private func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }

/// Same layout as a captured XM5 reply; names and addresses are synthetic.
private let deviceListReply: [UInt8] =
  [0x37, 0x02, 0x02]
  + ascii("0A:1B:2C:3D:4E:5F") + [0x01, 0x38, 0x01, 0x0C, 0x08] + ascii("Test Mac")
  + ascii("1a:2b:3c:4d:5e:6f") + [0x00, 0xFF, 0xFF, 0xFF, 0x0A] + ascii("Test Phone")
  + [0x01]

extension ProtocolTests {
  func testCapturedXM5DeviceControlReplies() {
    // Captured 2026-11-18, WH-1000XM5 firmware 2.5.1.
    XCTAssertEqual(DeviceCmd.parsePauseWhenRemoved([0xF7, 0x01, 0x00]), true)
    XCTAssertEqual(DeviceCmd.parsePauseWhenRemoved([0xF9, 0x01, 0x01]), false)
    XCTAssertEqual(DeviceCmd.parseNCButton([0x67, 0x30, 0x02]), .ncAmbient)
    XCTAssertEqual(DeviceCmd.parseNCButton([0x69, 0x30, 0x01]), .all)
    XCTAssertEqual(DeviceCmd.parseVoiceAssistant([0xF7, 0x04, 0x30]), .device)
    XCTAssertEqual(DeviceCmd.parseVoiceAssistant([0xF9, 0x04, 0xFF]), .unassigned)

    let touch: [UInt8] = [0xD1, 0xD1, 0x00, 0x01, 0x13] + ascii("TOUCH_PANEL_SETTING") + [0x00]
    let multipoint: [UInt8] = [0xD1, 0xD2, 0x00, 0x01, 0x12] + ascii("MULTIPOINT_SETTING")
      + [0x29] + ascii("MULTIPOINT_SETTING_SUMMARY_LDAC_AVAILABLE")
    XCTAssertTrue(DeviceCmd.parseGeneralSettingCapability(touch)! == (0xD1, .touchPanel))
    XCTAssertTrue(DeviceCmd.parseGeneralSettingCapability(multipoint)! == (0xD2, .multipoint))
    XCTAssertTrue(DeviceCmd.parseGeneralSetting([0xD7, 0xD1, 0x00, 0x00])! == (0xD1, true))
    XCTAssertTrue(DeviceCmd.parseGeneralSetting([0xD9, 0xD1, 0x00, 0x01])! == (0xD1, false))

    XCTAssertEqual(DeviceCmd.parseVoiceGuidance([0x47, 0x01, 0x00, 0x01]), true)
    XCTAssertEqual(DeviceCmd.parseVoiceGuidance([0x49, 0x01, 0x01]), false)
    XCTAssertEqual(DeviceCmd.parsePairingMode([0x33, 0x02, 0x00, 0x00]), false)
    XCTAssertEqual(DeviceCmd.parsePairingMode([0x35, 0x02, 0x01, 0x00]), true)
    XCTAssertEqual(DeviceCmd.parseAutoSwitch([0x37, 0x01, 0x01]), true)
    XCTAssertEqual(DeviceCmd.parseAutoSwitch([0x39, 0x01, 0x00, 0x00]), false)
    XCTAssertEqual(DeviceCmd.parseAlert([0x99, 0x00, 0x0A, 0x01]), HeadphoneAlert(messageType: 0x0A, actionType: 0x01))
  }

  func testDeviceControlRequestShapes() {
    // Every setter below was sent to the XM5 and read back before restoring.
    XCTAssertEqual(DeviceCmd.enableAlerts, [0x94, 0x00, 0x00])
    XCTAssertEqual(DeviceCmd.setPauseWhenRemoved(false), [0xF8, 0x01, 0x01])
    XCTAssertEqual(DeviceCmd.setNCButton(.all), [0x68, 0x30, 0x01])
    XCTAssertEqual(DeviceCmd.setGeneralSetting(0xD1, on: false), [0xD8, 0xD1, 0x00, 0x01])
    XCTAssertEqual(DeviceCmd.setVoiceGuidance(false), [0x48, 0x01, 0x01])
    XCTAssertEqual(DeviceCmd.setAutoSwitch(false), [0x38, 0x01, 0x00])
    XCTAssertEqual(DeviceCmd.setVoiceAssistant(VoiceAssistantSetting.deviceRaw), [0xF8, 0x04, 0x30])
    XCTAssertEqual(
      DeviceCmd.answerAlert(HeadphoneAlert(messageType: 0x0A, actionType: 0x01), positive: true),
      [0x98, 0x00, 0x0A, 0x01])
    XCTAssertEqual(DeviceCmd.setPairingMode(true), [0x34, 0x02, 0x01, 0x00])
    XCTAssertEqual(
      DeviceCmd.connectivity(.unpair, address: "1a:2b:3c:4d:5e:6f"),
      [0x3C, 0x02, 0x02] + ascii("1a:2b:3c:4d:5e:6f"))
    XCTAssertEqual(
      DeviceCmd.switchPlayback(to: "0A:1B:2C:3D:4E:5F"),
      [0x3C, 0x01] + ascii("0A:1B:2C:3D:4E:5F"))
    XCTAssertNil(DeviceCmd.connectivity(.connect, address: "not an address"))
    XCTAssertNil(DeviceCmd.switchPlayback(to: "0A:1B:2C:3D:4E"))
  }

  func testPairedDeviceListParsing() {
    let list = DeviceCmd.parsePairedDevices(deviceListReply)
    XCTAssertEqual(list?.devices.count, 2)
    XCTAssertEqual(list?.devices.first?.name, "Test Mac")
    XCTAssertEqual(list?.devices.first?.isPlaybackSource, true)
    XCTAssertEqual(list?.devices.last?.address, "1a:2b:3c:4d:5e:6f")
    XCTAssertEqual(list?.devices.last?.isConnected, false)
    XCTAssertEqual(list?.devices.last?.isPlaybackSource, false)
    XCTAssertEqual(DeviceCmd.normalizedAddress("1a-2b-3c-4d-5e-6f"), "1A:2B:3C:4D:5E:6F")

    // Truncated, padded or corrupted lists are rejected rather than half-shown.
    XCTAssertNil(DeviceCmd.parsePairedDevices(Array(deviceListReply.dropLast())))
    XCTAssertNil(DeviceCmd.parsePairedDevices(deviceListReply + [0x00]))
    var badAddress = deviceListReply
    badAddress[5] = UInt8(ascii: "-")
    XCTAssertNil(DeviceCmd.parsePairedDevices(badAddress))

    let result = DeviceCmd.parseConnectivityResult([0x3D, 0x02, 0x01, 0x10] + ascii("1a:2b:3c:4d:5e:6f"))
    XCTAssertEqual(result?.action, .connect)
    XCTAssertEqual(result?.succeeded, true)
    XCTAssertEqual(DeviceCmd.parsePlaybackSwitchResult([0x3D, 0x01, 0x02] + ascii("0A:1B:2C:3D:4E:5F"))?.code, 2)
  }

  func testRejectsMalformedDeviceControlReplies() {
    XCTAssertNil(DeviceCmd.parsePauseWhenRemoved([0xF7, 0x01, 0x02]))
    XCTAssertNil(DeviceCmd.parsePauseWhenRemoved([0xF7, 0x0C, 0x00]))
    XCTAssertNil(DeviceCmd.parseNCButton([0x67, 0x30, 0x09]))
    XCTAssertNil(DeviceCmd.parseNCButton([0x67, 0x17, 0x02]))
    XCTAssertNil(DeviceCmd.parseGeneralSetting([0xD7, 0xD1, 0x01, 0x00]))
    XCTAssertNil(DeviceCmd.parseGeneralSetting([0xD7, 0xE1, 0x00, 0x00]))
    XCTAssertNil(DeviceCmd.parseGeneralSettingCapability([0xD1, 0xD1, 0x00, 0x01, 0x30] + ascii("TOUCH")))
    XCTAssertNil(DeviceCmd.parseGeneralSettingCapability([0xD1, 0xD1, 0x00, 0x01, 0x05] + ascii("OTHER")))
    XCTAssertNil(DeviceCmd.parseVoiceGuidance([0x47, 0x20, 0x00, 0x01]))
    XCTAssertNil(DeviceCmd.parseAlert([0x99, 0x00, 0x0A]))
    XCTAssertNil(DeviceCmd.parseAutoSwitch([0x37, 0x01, 0x05]))
  }

  @MainActor
  func testAlertsNeedAnAnswerUnlessExpected() {
    let controller = HeadphoneController()
    controller.handleDeviceControl([0x99, 0x00, 0x07, 0x01])
    XCTAssertEqual(controller.pendingAlert?.messageType, 0x07)
    controller.respondToAlert(positive: false)
    XCTAssertNil(controller.pendingAlert)

    // An informational caution right after the user's own change is confirmed.
    controller.noteUserAction()
    controller.handleDeviceControl([0x99, 0x00, 0x08, 0x01])
    XCTAssertNil(controller.pendingAlert)
    XCTAssertEqual(controller.deviceNotice, HeadphoneAlert(messageType: 0x08, actionType: 0x01).message)

    // Without a recent action, even an informational caution waits for the user.
    controller.lastUserActionAt = -.infinity
    controller.handleDeviceControl([0x99, 0x00, 0x08, 0x01])
    XCTAssertEqual(controller.pendingAlert?.messageType, 0x08)
  }

  @MainActor
  func testDeviceStateFollowsHeadphoneReports() {
    let controller = HeadphoneController()
    let touch: [UInt8] = [0xD1, 0xD1, 0x00, 0x01, 0x13] + ascii("TOUCH_PANEL_SETTING") + [0x00]
    controller.handleDeviceControl([0xD7, 0xD1, 0x00, 0x00])
    XCTAssertNil(controller.touchPanelOn)  // slot meaning unknown until the capability arrives
    controller.handleDeviceControl(touch)
    controller.handleDeviceControl([0xD7, 0xD1, 0x00, 0x00])
    XCTAssertEqual(controller.touchPanelOn, true)
    controller.handleTableTwo(deviceListReply)
    XCTAssertEqual(controller.pairedDevices?.devices.count, 2)
    controller.handleTableTwo([0x37, 0x01, 0x01])
    XCTAssertEqual(controller.autoSwitchOn, true)

    // Offline, actions never change what the headphones reported.
    controller.setAutoSwitch(false)
    controller.setTouchPanel(false)
    XCTAssertEqual(controller.autoSwitchOn, true)
    XCTAssertEqual(controller.touchPanelOn, true)
  }

  func testURLCommands() {
    func command(_ text: String) -> URLCommand? { URL(string: text).flatMap(URLCommand.init(url:)) }
    XCTAssertEqual(command("sonyformac://mode/nc"), .mode(.noiseCancelling))
    XCTAssertEqual(command("sonyformac://mode/transparency"), .mode(.ambient))
    XCTAssertEqual(command("SonyForMac://mode/off"), .mode(.off))
    XCTAssertEqual(command("sonyformac://mode/next"), .nextMode)
    XCTAssertEqual(command("sonyformac://profile/Focus"), .profile(.focus))
    XCTAssertEqual(command("sonyformac://profile/off"), .profileOff)
    XCTAssertNil(command("sonyformac://profile/party"))
    XCTAssertNil(command("sonyformac://power/off"))
    XCTAssertNil(command("https://mode/nc"))
    XCTAssertEqual(ANCMode.noiseCancelling.next, .ambient)
    XCTAssertEqual(ANCMode.off.next, .noiseCancelling)
  }

  func testAppRulesIgnoreCorruptPreferences() {
    let name = "sony_for_macTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(Data("not json".utf8), forKey: Automation.rulesKey)
    XCTAssertTrue(Automation.loadRules(from: defaults).isEmpty)
    let rules = [
      AppProfileRule(bundleID: "com.example.editor", appName: "Editor", profile: "focus"),
      AppProfileRule(bundleID: "com.example.old", appName: "Old", profile: "removed-profile"),
    ]
    defaults.set(try? JSONEncoder().encode(rules), forKey: Automation.rulesKey)
    XCTAssertEqual(Automation.loadRules(from: defaults).map(\.bundleID), ["com.example.editor"])
  }
}
