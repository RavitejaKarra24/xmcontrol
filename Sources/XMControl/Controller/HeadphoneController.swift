import Combine
import Foundation

/// Session state machine: owns the link, performs the handshake, keeps the
/// published UI state in sync with the headphones, and exposes actions.
@MainActor
final class HeadphoneController: ObservableObject {
  enum ConnState: Equatable {
    case idle
    case waitingForHeadphones
    case connecting
    case connected(String)
    case failed(String)

    var isUp: Bool {
      if case .connected = self { return true }
      return false
    }

    init(from linkState: SonyLink.State) {
      switch linkState {
      case .idle: self = .idle
      case .waitingForHeadphones: self = .waitingForHeadphones
      case .connecting: self = .connecting
      case .connected(let name): self = .connected(name)
      case .failed(let reason): self = .failed(reason)
      }
    }
  }

  // MARK: Published state

  @Published private(set) var conn: ConnState = .idle
  @Published private(set) var battery: BatteryInfo?
  @Published private(set) var codec: AudioCodec = .unsettled
  @Published private(set) var anc = ANCState()
  @Published private(set) var eq = EQState.flat
  @Published private(set) var dseeOn = false
  @Published private(set) var qualityPrior = true
  @Published private(set) var autoPowerOff: AutoPowerOffSetting = .whenRemoved
  @Published private(set) var speakToChatOn = false
  @Published private(set) var stcSensitivity: STCSensitivity = .auto
  @Published private(set) var stcTimeout: STCTimeout = .mid
  @Published private(set) var volume = 15
  @Published private(set) var model = ""
  @Published private(set) var firmware = ""
  @Published private(set) var soundPressure: SoundPressureState = .waiting
  private var soundPressureMonitor = SoundPressureMonitor()
  private var soundPressureTimer: Timer?

  @Published private(set) var isReady = false
  @Published private(set) var savedEQBands: [Int]? = SavedEqualizer.load()
  @Published private(set) var notice: String?
  private var initialSettings: Set<String> = []

  var matchingProfile: ListeningProfile? {
    guard isReady else { return nil }
    return ListeningProfile.allCases.first { $0.matches(anc: anc, eq: eq, speakToChat: speakToChatOn) }
  }

  // MARK: Session

  private var link: SonyLink?
  private var gotHandshakeReply = false
  private var handshakeTimer: Timer?
  private var pollTimer: Timer?
  /// Debounce tasks for slider drags so we don't flood the control channel.
  private var eqSendTask: Task<Void, Never>?
  private var ambientSendTask: Task<Void, Never>?
  private var volumeSendTask: Task<Void, Never>?

  private var audioDSEEType: UInt8 { 0x01 }
  private var audioConnModeType: UInt8 { 0x00 }

  func ensureStarted() {
    guard link == nil else { return }
    let link = SonyLink()
    link.onState = { [weak self] state in
      self?.handleLinkState(state)
    }
    link.onFrame = { [weak self] frame in
      self?.handle(frame)
    }
    self.link = link
    link.start()
  }

  private func handleLinkState(_ state: SonyLink.State) {
    conn = ConnState(from: state)
    if case .connected = state {
      beginSession()
    } else {
      endSession()
    }
  }

  private func beginSession() {
    gotHandshakeReply = false
    send(Cmd.initHandshake)

    // If the device never answers the hello, tear the channel down and let
    // the link's retry logic reconnect.
    handshakeTimer?.invalidate()
    handshakeTimer = Timer(timeInterval: 4, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, !self.gotHandshakeReply else { return }
        Log.write("session", "handshake timed out, reconnecting")
        self.link?.retryAfterSessionFailure()
      }
    }
    RunLoop.main.add(handshakeTimer!, forMode: .common)
  }

  private func endSession() {
    handshakeTimer?.invalidate()
    handshakeTimer = nil
    pollTimer?.invalidate()
    pollTimer = nil
    eqSendTask?.cancel()
    volumeSendTask?.cancel()
    ambientSendTask?.cancel()
    isReady = false
    initialSettings.removeAll()
    battery = nil
    codec = .unsettled
    model = ""
    firmware = ""
    notice = nil
    gotHandshakeReply = false
    soundPressureTimer?.invalidate()
    soundPressureTimer = nil
    soundPressureMonitor = SoundPressureMonitor()
    soundPressure = .waiting
  }

  private func refreshAll() {
    send(Cmd.getBattery)
    send(Cmd.getANC)
    send(Cmd.getEQ)
    send(Cmd.getVolume)
    send(Cmd.getDSEE)
    send(Cmd.getConnectionMode)
    send(Cmd.getAutoPowerOff)
    send(Cmd.getSpeakToChat)
    send(Cmd.getSpeakToChatDetail)
    send(Cmd.getDeviceInfo(1))  // model name
    send(Cmd.getDeviceInfo(2))  // firmware version

    pollTimer?.invalidate()
    let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.send(Cmd.getBattery) }
    }
    pollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func send(_ payload: [UInt8]) {
    guard conn.isUp, gotHandshakeReply || payload == Cmd.initHandshake else { return }
    link?.send(payload)
  }

  // MARK: Frame dispatch

  private func handle(_ frame: MDRFrame) {
    if frame.type == Wire.dataMDRNo2 {
      guard isReady else { return }
      soundPressureMonitor.receive(frame.payload, at: ProcessInfo.processInfo.systemUptime)
      soundPressure = soundPressureMonitor.state
      return
    }
    guard frame.type == Wire.dataMDR, let op = frame.opcode else { return }

    guard gotHandshakeReply || op == T1Command.connectRetProtocolInfo.rawValue else { return }

    switch op {
    case T1Command.connectRetProtocolInfo.rawValue:
      guard !gotHandshakeReply, frame.payload.count >= 2 else { return }
      gotHandshakeReply = true
      handshakeTimer?.invalidate()
      refreshAll()
      handshakeTimer = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
        Task { @MainActor in
          guard let self, !self.isReady else { return }
          self.link?.retryAfterSessionFailure()
        }
      }
      RunLoop.main.add(handshakeTimer!, forMode: .common)

    case T1Command.powerRetStatus.rawValue,
      T1Command.powerNtfyStatus.rawValue:
      if let b = Cmd.parseBattery(frame.payload) { battery = b }

    case T1Command.ncAsmRetParam.rawValue,
      T1Command.ncAsmNtfyParam.rawValue:
      if let s = Cmd.parseANC(frame.payload) { anc = s; received("anc") }

    case T1Command.eqebbRetParam.rawValue,
      T1Command.eqebbNtfyParam.rawValue:
      if let e = Cmd.parseEQ(frame.payload) { eq = e; received("eq") }

    case T1Command.playRetParam.rawValue,
      T1Command.playNtfyParam.rawValue:
      if let v = Cmd.parseVolume(frame.payload) { volume = v; received("volume") }

    case T1Command.audioRetParam.rawValue,
      T1Command.audioNtfyParam.rawValue:
      if frame.subType == audioDSEEType,
        let on = Cmd.parseAudioFlag(frame.payload, subType: audioDSEEType)
      {
        dseeOn = on
      } else if frame.subType == audioConnModeType,
        let quality = Cmd.parseAudioFlag(frame.payload, subType: audioConnModeType)
      {
        // 0 = sound quality prior, 1 = stable connection.
        qualityPrior = !quality
      }

    case T1Command.systemRetParam.rawValue, T1Command.systemNtfyParam.rawValue:
      if frame.subType == 0x0C, let on = Cmd.parseSpeakToChat(frame.payload) {
        speakToChatOn = on
        received("speech")
      }

    case T1Command.systemRetExtParam.rawValue, T1Command.systemNtfyExtParam.rawValue:
      if frame.subType == 0x0C, let detail = Cmd.parseSpeakToChatDetail(frame.payload) {
        stcSensitivity = detail.0
        stcTimeout = detail.1
      }

    case T1Command.powerRetParam.rawValue, T1Command.powerNtfyParam.rawValue:
      if let s = Cmd.parseAutoPowerOff(frame.payload) { autoPowerOff = s }

    case T1Command.connectRetDeviceInfo.rawValue:
      if let s = Cmd.parseDeviceInfoString(frame.payload) {
        if frame.subType == 1 { model = s } else { firmware = s }
      }

    case T1Command.commonRetStatus.rawValue, T1Command.commonNtfyStatus.rawValue:
      if frame.subType == 0x02, frame.payload.count >= 3,
        let c = AudioCodec(rawValue: frame.payload[2])
      {
        codec = c
      }

    default:
      Log.write("rx", "unhandled opcode 0x\(String(op, radix: 16))")
    }
  }

  private func received(_ setting: String) {
    initialSettings.insert(setting)
    if initialSettings.isSuperset(of: ["anc", "eq", "volume", "speech"]) {
      let needsMonitoring = !isReady
      isReady = true
      handshakeTimer?.invalidate()
      if needsMonitoring { startSoundPressureMonitoring() }
    }
  }

  private func startSoundPressureMonitoring() {
    soundPressureTimer?.invalidate()
    let timer = Timer(timeInterval: SoundPressureMonitor.pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.pollSoundPressure() }
    }
    timer.tolerance = 0.2
    soundPressureTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    pollSoundPressure()
  }

  private func pollSoundPressure() {
    guard isReady, conn.isUp else { return }
    let payload = soundPressureMonitor.nextRequest(at: ProcessInfo.processInfo.systemUptime)
    soundPressure = soundPressureMonitor.state
    if let payload { link?.send(payload, type: Wire.dataMDRNo2) }
  }

  func retrySoundPressure() {
    guard isReady else { return }
    soundPressureMonitor = SoundPressureMonitor()
    soundPressure = .waiting
    pollSoundPressure()
  }

  func applyProfile(_ profile: ListeningProfile) {
    guard isReady else { return }
    eqSendTask?.cancel()
    ambientSendTask?.cancel()
    anc = profile.anc
    eq = profile.eq
    speakToChatOn = false
    send(Cmd.setANC(anc))
    send(Cmd.setEQ(eq))
    send(Cmd.setSpeakToChat(false))
    send(Cmd.getANC)
    send(Cmd.getEQ)
    send(Cmd.getSpeakToChat)
    notice = "\(profile.title) requested. Volume unchanged."
  }

  func saveEqualizer() {
    guard isReady, eq.bands.count == 6 else { return }
    savedEQBands = eq.bands
    UserDefaults.standard.set(eq.bands, forKey: SavedEqualizer.key)
    notice = "Your EQ curve is saved on this Mac."
  }

  func restoreEqualizer() {
    guard isReady, let bands = savedEQBands else { return }
    eqSendTask?.cancel()
    eq = EQState(preset: EQPreset.custom.rawValue, bands: bands)
    send(Cmd.setEQ(eq))
    send(Cmd.getEQ)
    notice = "Saved EQ requested."
  }

  func resetEqualizer() {
    guard isReady else { return }
    eqSendTask?.cancel()
    eq = .flat
    send(Cmd.setEQ(eq))
    send(Cmd.getEQ)
  }

  // MARK: Actions — ambient sound

  func setMode(_ mode: ANCMode) {
    guard isReady else { return }
    ambientSendTask?.cancel()
    anc.mode = mode
    send(Cmd.setANC(anc))
  }

  func setAmbientLevel(_ level: Int) {
    guard isReady else { return }
    guard anc.mode == .ambient else { return }
    anc.ambientLevel = max(1, min(20, level))
    let snapshot = anc
    ambientSendTask?.cancel()
    ambientSendTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      self?.send(Cmd.setANC(snapshot))
    }
  }

  func setVoiceFocus(_ on: Bool) {
    guard isReady else { return }
    ambientSendTask?.cancel()
    anc.voiceFocus = on
    send(Cmd.setANC(anc))
  }

  // MARK: Actions — equalizer

  func selectPreset(_ preset: EQPreset) {
    guard isReady else { return }
    eqSendTask?.cancel()
    eq.preset = preset.rawValue
    send(Cmd.setEQ(eq))
    send(Cmd.getEQ)
  }

  /// Slider drag: switch to Custom and debounce the actual write.
  func setBand(index: Int, wireValue: Int) {
    guard isReady else { return }
    guard eq.bands.indices.contains(index) else { return }
    eq.preset = EQPreset.custom.rawValue
    eq.bands[index] = max(0, min(20, wireValue))

    let snapshot = eq
    eqSendTask?.cancel()
    eqSendTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled else { return }
      self?.send(Cmd.setEQ(snapshot))
    }
  }

  // MARK: Actions — audio & power

  func setDSEE(_ on: Bool) {
    guard isReady else { return }
    dseeOn = on
    send(Cmd.setDSEE(on))
  }

  func setConnectionMode(qualityPrior: Bool) {
    guard isReady else { return }
    self.qualityPrior = qualityPrior
    send(Cmd.setConnectionMode(qualityPrior: qualityPrior))
  }

  func setAutoPowerOff(_ setting: AutoPowerOffSetting) {
    guard isReady else { return }
    autoPowerOff = setting
    send(Cmd.setAutoPowerOff(setting))
  }

  func setSpeakToChat(_ on: Bool) {
    guard isReady else { return }
    speakToChatOn = on
    send(Cmd.setSpeakToChat(on))
  }

  func setSpeakToChatDetail(sensitivity: STCSensitivity, timeout: STCTimeout) {
    guard isReady else { return }
    stcSensitivity = sensitivity
    stcTimeout = timeout
    send(Cmd.setSpeakToChatDetail(sensitivity: sensitivity, timeout: timeout))
  }

  /// Slider drag: debounce like the EQ.
  func setVolume(_ level: Int) {
    guard isReady else { return }
    volume = max(0, min(30, level))
    let v = volume
    volumeSendTask?.cancel()
    volumeSendTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      self?.send(Cmd.setVolume(v))
    }
  }

  func playback(_ control: PlaybackControl) {
    guard isReady else { return }
    send(Cmd.playbackControl(control))
  }

  func powerOff() {
    guard isReady else { return }
    send(Cmd.powerOff)
  }

  func reconnect() {
    link?.reconnect()
  }
}
