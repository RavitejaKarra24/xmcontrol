import Foundation

/// Device controls, multipoint management and headphone confirmation alerts.
extension HeadphoneController {
  // MARK: Session

  func resetDeviceControls() {
    pauseWhenRemoved = nil
    ncButtonMode = nil
    voiceGuidanceOn = nil
    voiceAssistant = nil
    touchPanelOn = nil
    multipointOn = nil
    pairedDevices = nil
    autoSwitchOn = nil
    pairingModeOn = nil
    pendingAlert = nil
    deviceNotice = nil
    generalSettingSlots = [:]
    preconfirmedAlerts = [:]
    lastUserActionAt = -.infinity
    restoreAssistantWhenTouchPanelOn = false
  }

  func requestDeviceControls() {
    send(DeviceCmd.enableAlerts)
    send(DeviceCmd.getPauseWhenRemoved)
    send(DeviceCmd.getNCButton)
    send(DeviceCmd.getVoiceAssistant)
    for slot in DeviceCmd.generalSettingSlots {
      send(DeviceCmd.getGeneralSettingCapability(slot))
    }
    sendT2(DeviceCmd.getVoiceGuidance)
    sendT2(DeviceCmd.getPairedDevices)
    sendT2(DeviceCmd.getAutoSwitch)
    sendT2(DeviceCmd.getPairingMode)
  }

  /// Re-reads settings an unanswered or declined caution may have left unchanged.
  private func resyncAfterAlert() {
    send(Cmd.getANC)
    send(Cmd.getEQ)
    send(Cmd.getDSEE)
    send(Cmd.getConnectionMode)
    send(DeviceCmd.getNCButton)
    send(DeviceCmd.getVoiceAssistant)
    for slot in generalSettingSlots.values { send(DeviceCmd.getGeneralSetting(slot)) }
    sendT2(DeviceCmd.getPairedDevices)
  }

  // MARK: Receiving

  func handleDeviceControl(_ payload: [UInt8]) {
    if let alert = DeviceCmd.parseAlert(payload) {
      receive(alert)
    } else if let capability = DeviceCmd.parseGeneralSettingCapability(payload) {
      generalSettingSlots[capability.kind] = capability.slot
      send(DeviceCmd.getGeneralSetting(capability.slot))
    } else if let setting = DeviceCmd.parseGeneralSetting(payload),
      let kind = generalSettingSlots.first(where: { $0.value == setting.slot })?.key
    {
      switch kind {
      case .touchPanel:
        touchPanelOn = setting.on
        if setting.on { restoreVoiceAssistantIfNeeded() }
      case .multipoint:
        multipointOn = setting.on
      }
    }
  }

  func handleTableTwo(_ payload: [UInt8]) {
    guard let opcode = payload.first else { return }
    switch opcode {
    case T2Command.voiceGuidanceRetParam, T2Command.voiceGuidanceNtfyParam:
      if let on = DeviceCmd.parseVoiceGuidance(payload) { voiceGuidanceOn = on }
    case T2Command.periRetStatus, T2Command.periNtfyStatus:
      if let on = DeviceCmd.parsePairingMode(payload) { pairingModeOn = on }
    case T2Command.periRetParam, T2Command.periNtfyParam:
      if let list = DeviceCmd.parsePairedDevices(payload) {
        pairedDevices = list
      } else if let on = DeviceCmd.parseAutoSwitch(payload) {
        autoSwitchOn = on
      }
    case T2Command.periNtfyExtendedParam:
      if let result = DeviceCmd.parseConnectivityResult(payload) {
        if !result.inProgress { deviceNotice = result.message }
        sendT2(DeviceCmd.getPairedDevices)
      } else if let result = DeviceCmd.parsePlaybackSwitchResult(payload) {
        deviceNotice = DeviceCmd.playbackSwitchMessage(code: result.code)
        sendT2(DeviceCmd.getPairedDevices)
      }
    default:
      break
    }
  }

  private func receive(_ alert: HeadphoneAlert) {
    let now = ProcessInfo.processInfo.systemUptime
    preconfirmedAlerts = preconfirmedAlerts.filter { now - $0.value < 10 }
    guard alert.needsAnswer else {
      deviceNotice = alert.message
      return
    }
    if preconfirmedAlerts.removeValue(forKey: alert.messageType) != nil {
      send(DeviceCmd.answerAlert(alert, positive: true))
    } else if alert.isInformational, now - lastUserActionAt < 10 {
      send(DeviceCmd.answerAlert(alert, positive: true))
      deviceNotice = alert.message
    } else {
      pendingAlert = alert
    }
  }

  func respondToAlert(positive: Bool) {
    guard let alert = pendingAlert else { return }
    pendingAlert = nil
    send(DeviceCmd.answerAlert(alert, positive: positive))
    if !positive { resyncAfterAlert() }
  }

  /// The app already explained these consequences, so confirm the headphones' copy.
  private func preconfirm(_ messageTypes: [UInt8]) {
    let now = ProcessInfo.processInfo.systemUptime
    for type in messageTypes { preconfirmedAlerts[type] = now }
  }

  // MARK: Controls

  func setPauseWhenRemoved(_ on: Bool) {
    guard isReady, pauseWhenRemoved != nil else { return }
    noteUserAction()
    pauseWhenRemoved = on
    send(DeviceCmd.setPauseWhenRemoved(on))
  }

  func setNCButtonMode(_ mode: NCButtonMode) {
    guard isReady, ncButtonMode != nil else { return }
    noteUserAction()
    ncButtonMode = mode
    send(DeviceCmd.setNCButton(mode))
  }

  func setVoiceGuidance(_ on: Bool) {
    guard isReady, voiceGuidanceOn != nil else { return }
    noteUserAction()
    voiceGuidanceOn = on
    sendT2(DeviceCmd.setVoiceGuidance(on))
  }

  /// Waits for the headphones' confirmation before updating state: turning the
  /// panel off needs an answered caution, and the device may refuse.
  func setTouchPanel(_ on: Bool) {
    guard isReady, let slot = generalSettingSlots[.touchPanel], touchPanelOn != nil else { return }
    noteUserAction()
    if on {
      restoreAssistantWhenTouchPanelOn = true
      preconfirm([0x0C, 0x0D])
    } else {
      if voiceAssistant != .unassigned { assistantBeforeTouchPanelOff = voiceAssistant }
      preconfirm([0x0A, 0x0B])
    }
    send(DeviceCmd.setGeneralSetting(slot, on: on))
  }

  /// Turning the touch panel off clears the voice assistant on the XM5 and turning
  /// it back on does not restore it. Put back the assistant the user had.
  private func restoreVoiceAssistantIfNeeded() {
    guard restoreAssistantWhenTouchPanelOn else { return }
    restoreAssistantWhenTouchPanelOn = false
    guard voiceAssistant == .unassigned else { return }
    switch assistantBeforeTouchPanelOff {
    case nil, .device, .unassigned:
      useDeviceVoiceAssistant()
    case let previous?:
      deviceNotice = "Touch panel on. Choose \(previous.label) again in Sony Sound Connect."
    }
  }

  func useDeviceVoiceAssistant() {
    guard isReady, voiceAssistant != nil else { return }
    send(DeviceCmd.setVoiceAssistant(VoiceAssistantSetting.deviceRaw))
    send(DeviceCmd.getVoiceAssistant)
  }

  // MARK: Multipoint

  func setMultipoint(_ on: Bool) {
    guard isReady, let slot = generalSettingSlots[.multipoint], multipointOn != nil else { return }
    noteUserAction()
    preconfirm([0x06, 0x07])
    send(DeviceCmd.setGeneralSetting(slot, on: on))
  }

  func setAutoSwitch(_ on: Bool) {
    guard isReady, autoSwitchOn != nil else { return }
    noteUserAction()
    autoSwitchOn = on
    sendT2(DeviceCmd.setAutoSwitch(on))
  }

  func setPairingMode(_ on: Bool) {
    guard isReady, pairingModeOn != nil else { return }
    noteUserAction()
    sendT2(DeviceCmd.setPairingMode(on))
    sendT2(DeviceCmd.getPairingMode)
  }

  func refreshPairedDevices() {
    guard isReady else { return }
    sendT2(DeviceCmd.getPairedDevices)
  }

  func isThisMac(_ device: PairedDevice) -> Bool {
    guard let hostAddress else { return false }
    return DeviceCmd.normalizedAddress(device.address) == hostAddress
  }

  func connect(_ device: PairedDevice) { perform(.connect, on: device) }
  func disconnect(_ device: PairedDevice) { perform(.disconnect, on: device) }
  func forget(_ device: PairedDevice) { perform(.unpair, on: device) }

  private func perform(_ action: ConnectivityAction, on device: PairedDevice) {
    // Disconnecting or forgetting this Mac would end this session.
    guard isReady, action == .connect || !isThisMac(device),
      let payload = DeviceCmd.connectivity(action, address: device.address) else { return }
    noteUserAction()
    deviceNotice = nil
    sendT2(payload)
  }

  func playOn(_ device: PairedDevice) {
    guard isReady, device.isConnected, !device.isPlaybackSource,
      let payload = DeviceCmd.switchPlayback(to: device.address) else { return }
    noteUserAction()
    deviceNotice = nil
    sendT2(payload)
  }
}
