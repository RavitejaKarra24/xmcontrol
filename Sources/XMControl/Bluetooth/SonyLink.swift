import Foundation
import IOBluetooth

/// Transport for Sony's proprietary "Serial HPC" control service.
///
/// The WH-1000XM5 advertises the V2 UUID on RFCOMM channel 9 over *classic*
/// Bluetooth — not BLE, which is exactly why every BLE-based client fails to
/// find it. Only the WH-1000XM5 command layout is supported.
///
/// Transport approach follows Plutoberth/SonyHeadphonesClient and
/// argjentsahiti/aura-xm5 (both MIT).
private let serviceUUIDs: [[UInt8]] = [
  // V2 — WH-1000XM5 and newer
  [
    0x95, 0x6C, 0x7B, 0x26, 0xD4, 0x9A, 0x4B, 0xA8,
    0xB0, 0x3F, 0xB1, 0x7D, 0x39, 0x3C, 0xB6, 0xE2,
  ],

]

/// Only the model whose command layouts this app implements. Pairing is the trust boundary.
private let supportedDeviceName = "WH-1000XM5"

@MainActor
final class SonyLink: NSObject {
  enum State: Equatable {
    case idle
    case waitingForHeadphones
    case connecting
    case connected(String)
    case failed(String)
  }

  private(set) var state: State = .idle {
    didSet {
      guard state != oldValue else { return }
      Log.write("link", "\(state)")
      onState?(state)
    }
  }

  var onState: ((State) -> Void)?
  var onFrame: ((MDRFrame) -> Void)?

  private var activeDevice: IOBluetoothDevice?
  private var channel: IOBluetoothRFCOMMChannel?
  private var parser = MDRFrameParser()
  /// The device expects a short sequence number that alternates per frame.
  private var seq: UInt8 = 0
  private var retryTimer: Timer?
  /// Guards against IOBluetooth's async channel open never calling back.
  private var openTimer: Timer?
  private var connectNote: IOBluetoothUserNotification?
  private var disconnectNote: IOBluetoothUserNotification?

  // MARK: Lifecycle

  /// Watches for the headphones and connects whenever they appear.
  func start() {
    connectNote = IOBluetoothDevice.register(
      forConnectNotifications: self,
      selector: #selector(deviceConnected(_:device:))
    )
    connect()
  }

  func connect() {
    cancelRetry()
    if case .connected = state { return }
    if case .connecting = state { return }

    guard let device = pairedHeadphones() else {
      state = .waitingForHeadphones
      scheduleRetry()
      return
    }
    guard device.isConnected() else {
      state = .waitingForHeadphones
      scheduleRetry()
      return
    }

    activeDevice = device
    registerDisconnect(for: device)
    state = .connecting
    watchOpenCompletion()

    if openChannel(on: device) { return }

    // SDP records aren't cached yet right after the ACL link comes up —
    // query them, then retry from the callback.
    if device.performSDPQuery(self) != kIOReturnSuccess {
      fail("Could not query headphone services")
    }
  }

  func disconnect() {
    cancelRetry()
    cancelOpenWatchdog()
    let previous = channel
    channel = nil
    activeDevice = nil
    disconnectNote?.unregister()
    disconnectNote = nil
    previous?.close()
    parser.reset()
    seq = 0
    state = .idle
  }

  func retryAfterSessionFailure() {
    fail("Headphones did not complete setup")
  }

  /// User-initiated reconnect: tear everything down and start over.
  func reconnect() {
    Log.write("link", "manual reconnect")
    disconnect()
    connect()
  }

  // MARK: Sending

  func send(_ payload: [UInt8], type: UInt8 = Wire.dataMDR) {
    guard case .connected = state, let channel,
      [Wire.dataMDR, Wire.dataMDRNo2].contains(type),
      payload.count <= MDRFrameParser.maximumPayloadLength else { return }
    let data = MDRFraming.encode(type: type, seq: seq, payload: payload)
    seq = 1 &- seq
    write(data, on: channel)
  }

  private func sendAck(for receivedSeq: UInt8) {
    guard let channel else { return }
    write(
      MDRFraming.encode(type: Wire.dataAck, seq: 1 &- receivedSeq, payload: []),
      on: channel
    )
  }

  private func write(_ data: Data, on channel: IOBluetoothRFCOMMChannel) {
    var bytes = [UInt8](data)
    guard bytes.count <= Int(UInt16.max) else { return }
    let result = bytes.withUnsafeMutableBufferPointer { buf -> IOReturn in
      guard let base = buf.baseAddress else { return kIOReturnNoMemory }
      return channel.writeSync(base, length: UInt16(buf.count))
    }
    if result != kIOReturnSuccess { fail("Could not send headphone command") }
  }

  // MARK: Discovery

  private func pairedHeadphones() -> IOBluetoothDevice? {
    guard let raw = IOBluetoothDevice.pairedDevices() else { return nil }
    let devices = raw.compactMap { $0 as? IOBluetoothDevice }
    return devices.first { device in
      device.isConnected() && device.name == supportedDeviceName
    }
  }

  @discardableResult
  private func openChannel(on device: IOBluetoothDevice) -> Bool {
    for uuidBytes in serviceUUIDs {
      let uuid = IOBluetoothSDPUUID(bytes: uuidBytes, length: uuidBytes.count)
      guard let record = device.getServiceRecord(for: uuid) else { continue }

      var channelID: BluetoothRFCOMMChannelID = 0
      guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { continue }

      var opened: IOBluetoothRFCOMMChannel?
      let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
      guard result == kIOReturnSuccess else { continue }
      Log.write("link", "opening RFCOMM channel \(channelID)")

      parser.reset()
      channel = opened
      seq = 0
      watchOpenCompletion()
      return true
    }
    return false
  }

  /// If the async open never completes (a known IOBluetooth quirk when the
  /// control service is busy), close and let the retry loop try again.
  private func watchOpenCompletion() {
    cancelOpenWatchdog()
    let timer = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        guard case .connecting = self.state else { return }
        Log.write("link", "channel open timed out, forcing retry")
        self.fail("Control channel timed out")
      }
    }
    openTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func cancelOpenWatchdog() {
    openTimer?.invalidate()
    openTimer = nil
  }

  private func registerDisconnect(for device: IOBluetoothDevice) {
    disconnectNote?.unregister()
    disconnectNote = device.register(
      forDisconnectNotification: self,
      selector: #selector(deviceDisconnected(_:device:))
    )
  }

  // MARK: Retry

  private func scheduleRetry(after delay: TimeInterval = 4) {
    guard retryTimer == nil else { return }
    let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      Task { @MainActor in
        self?.retryTimer = nil
        self?.connect()
      }
    }
    retryTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func cancelRetry() {
    retryTimer?.invalidate()
    retryTimer = nil
  }

  private func fail(_ reason: String) {
    cancelOpenWatchdog()
    let previous = channel
    channel = nil
    activeDevice = nil
    disconnectNote?.unregister()
    disconnectNote = nil
    previous?.close()
    parser.reset()
    state = .failed(reason)
    scheduleRetry()
  }

  // MARK: Bluetooth notifications

  @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice)
  {
    guard device.name == supportedDeviceName else {
      return
    }
    // The control service isn't immediately ready when the ACL link comes up.
    scheduleRetry(after: 1.5)
  }

  @objc private func deviceDisconnected(
    _ note: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    guard device.name == supportedDeviceName else {
      return
    }
    guard device == activeDevice else { return }
    disconnect()
    state = .waitingForHeadphones
    scheduleRetry()
  }
}

// MARK: - SDP

extension SonyLink {
  @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
    Task { @MainActor in
      guard let device, device == self.activeDevice, case .connecting = self.state else { return }
      guard status == kIOReturnSuccess else {
        self.fail("Service lookup failed")
        return
      }
      if !self.openChannel(on: device) {
        self.fail("Control service not available")
      }
    }
  }
}

// MARK: - RFCOMM delegate

extension SonyLink: IOBluetoothRFCOMMChannelDelegate {
  nonisolated func rfcommChannelOpenComplete(
    _ ch: IOBluetoothRFCOMMChannel!, status error: IOReturn
  ) {
    let name = ch?.getDevice()?.name ?? "Headphones"
    Task { @MainActor in
      guard let ch, ch === self.channel, case .connecting = self.state else { return }
      self.cancelOpenWatchdog()
      guard error == kIOReturnSuccess else {
        self.fail("Could not open control channel")
        return
      }
      self.state = .connected(name)
    }
  }

  nonisolated func rfcommChannelData(
    _ ch: IOBluetoothRFCOMMChannel!,
    data pointer: UnsafeMutableRawPointer!,
    length: Int
  ) {
    guard let pointer, length > 0, length <= Int(UInt16.max) else { return }
    let data = Data(bytes: pointer, count: length)
    Task { @MainActor in
      guard let ch, ch === self.channel, case .connected = self.state else { return }
      for frame in self.parser.feed(data) {
        guard frame.type != Wire.dataAck else { continue }
        self.sendAck(for: frame.seq)
        guard ch === self.channel else { return }
        self.onFrame?(frame)
      }
    }
  }

  nonisolated func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
    Task { @MainActor in
      guard let ch, ch === self.channel else { return }
      self.cancelOpenWatchdog()
      self.channel = nil
      self.activeDevice = nil
      self.parser.reset()
      if case .idle = self.state { return }
      self.state = .waitingForHeadphones
      self.scheduleRetry()
    }
  }
}
