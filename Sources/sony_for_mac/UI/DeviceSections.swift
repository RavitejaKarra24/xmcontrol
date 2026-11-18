import SwiftUI

// MARK: - Headphone confirmation

/// A caution raised by the headphones that needs an answer before it applies.
struct HeadphoneAlertBanner: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    if let alert = controller.pendingAlert {
      VStack(alignment: .leading, spacing: 10) {
        Label(alert.title, systemImage: "exclamationmark.bubble.fill")
          .font(.callout.weight(.semibold))
          .foregroundStyle(XMTheme.warning)
        Text(alert.message)
          .font(.caption)
          .foregroundStyle(XMTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button("Cancel") { controller.respondToAlert(positive: false) }
          Button("Continue") { controller.respondToAlert(positive: true) }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
      }
      .padding(12)
      .background(XMTheme.warning.opacity(0.08), in: .rect(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12).strokeBorder(XMTheme.warning.opacity(0.35), lineWidth: 0.75)
      }
      .accessibilityElement(children: .contain)
    }
  }
}

struct DeviceNotice: View {
  let text: String?

  var body: some View {
    if let text {
      Label(text, systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(XMTheme.accentBright)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Controls

struct ControlsSection: View {
  @EnvironmentObject private var controller: HeadphoneController
  @State private var confirmingTouchPanelOff = false

  var body: some View {
    ControlCard("Headphone controls", symbol: "hand.tap.fill") {
      if let touchPanel = controller.touchPanelOn {
        FeatureToggleRow(
          symbol: "hand.tap",
          title: "Touch panel",
          subtitle: "Tap and swipe the right ear cup",
          isOn: Binding(
            get: { touchPanel },
            set: { on in
              if on { controller.setTouchPanel(true) } else { confirmingTouchPanelOff = true }
            }
          )
        )
        .confirmationDialog("Turn off the touch panel?", isPresented: $confirmingTouchPanelOff) {
          Button("Turn off") { controller.setTouchPanel(false) }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Taps and swipes will stop working, including playback, volume, Quick Attention and the voice assistant. sony_for_mac restores Siri when you turn it back on.")
        }
      }

      if let assistant = controller.voiceAssistant {
        MenuValueRow("Touch and hold") {
          if assistant == .unassigned, controller.touchPanelOn == true {
            Button("Use Siri") { controller.useDeviceVoiceAssistant() }
              .controlSize(.small)
              .help("Assign this Mac's or phone's voice assistant to touch and hold")
          } else {
            Text(assistant.label)
              .font(.caption.weight(.medium))
              .foregroundStyle(XMTheme.secondaryText)
          }
        }
        .padding(.leading, 39)
      }

      if let mode = controller.ncButtonMode {
        InsetDivider()
        MenuValueRow("NC/AMB button") {
          Menu {
            ForEach(NCButtonMode.allCases) { option in
              Button(option.label) { controller.setNCButtonMode(option) }
            }
          } label: {
            SoftMenuLabel(text: mode.shortLabel)
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
          .help("Modes the button on the left ear cup cycles through")
        }
      }

      if let pause = controller.pauseWhenRemoved {
        InsetDivider()
        FeatureToggleRow(
          symbol: "pause.circle",
          title: "Pause when taken off",
          subtitle: "Resume when you put them back on",
          isOn: Binding(get: { pause }, set: { controller.setPauseWhenRemoved($0) })
        )
      }

      if let guidance = controller.voiceGuidanceOn {
        InsetDivider()
        FeatureToggleRow(
          symbol: "text.bubble",
          title: "Voice guidance",
          subtitle: "Spoken battery, mode and connection updates",
          isOn: Binding(get: { guidance }, set: { controller.setVoiceGuidance($0) })
        )
      }
    }
  }
}

// MARK: - Multipoint

struct DevicesSection: View {
  @EnvironmentObject private var controller: HeadphoneController
  @State private var multipointChange: Bool?
  @State private var deviceToForget: PairedDevice?

  var body: some View {
    ControlCard("Devices", symbol: "laptopcomputer.and.iphone", trailing: {
      Button {
        controller.refreshPairedDevices()
      } label: {
        Image(systemName: "arrow.clockwise").font(.caption)
      }
      .buttonStyle(.borderless)
      .help("Refresh the device list")
      .accessibilityLabel("Refresh devices")
    }) {
      if let multipoint = controller.multipointOn {
        FeatureToggleRow(
          symbol: "point.3.connected.trianglepath.dotted",
          title: "Connect to 2 devices",
          subtitle: "Stay connected to this Mac and another device",
          isOn: Binding(get: { multipoint }, set: { multipointChange = $0 })
        )
        .confirmationDialog(
          multipointChange == true ? "Connect to two devices?" : "Connect to one device only?",
          isPresented: Binding(get: { multipointChange != nil }, set: { if !$0 { multipointChange = nil } })
        ) {
          Button(multipointChange == true ? "Turn on" : "Turn off") {
            if let on = multipointChange { controller.setMultipoint(on) }
            multipointChange = nil
          }
          Button("Cancel", role: .cancel) { multipointChange = nil }
        } message: {
          Text(multipointChange == true
            ? "Your headphones will reconnect. With two devices connected, LDAC is unavailable."
            : "Your headphones will reconnect and keep only one device connected.")
        }
      }

      if let autoSwitch = controller.autoSwitchOn, controller.multipointOn != false {
        FeatureToggleRow(
          symbol: "arrow.triangle.swap",
          title: "Switch automatically",
          subtitle: "Follow whichever device starts playing",
          isOn: Binding(get: { autoSwitch }, set: { controller.setAutoSwitch($0) })
        )
      }

      if let list = controller.pairedDevices {
        InsetDivider()
        if list.devices.isEmpty {
          Text("No paired devices reported.")
            .font(.caption).foregroundStyle(XMTheme.secondaryText)
        }
        ForEach(list.devices) { device in
          PairedDeviceRow(
            device: device,
            isThisMac: controller.isThisMac(device),
            onForget: { deviceToForget = device }
          )
        }
      }

      if let pairing = controller.pairingModeOn {
        InsetDivider()
        HStack(spacing: 10) {
          Image(systemName: pairing ? "dot.radiowaves.left.and.right" : "plus.circle")
            .foregroundStyle(pairing ? XMTheme.success : XMTheme.accentBright)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(pairing ? "Ready to pair" : "Pair a new device")
              .font(.callout.weight(.medium))
            Text(pairing ? "Choose WH-1000XM5 in the other device's Bluetooth settings." : "Your current connection stays on.")
              .font(.caption2).foregroundStyle(XMTheme.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          Button(pairing ? "Stop" : "Start pairing") { controller.setPairingMode(!pairing) }
            .controlSize(.small)
        }
      }

      DeviceNotice(text: controller.deviceNotice)
    }
    .confirmationDialog(
      "Forget \(deviceToForget?.name ?? "this device")?",
      isPresented: Binding(get: { deviceToForget != nil }, set: { if !$0 { deviceToForget = nil } })
    ) {
      Button("Forget device", role: .destructive) {
        if let device = deviceToForget { controller.forget(device) }
        deviceToForget = nil
      }
      Button("Cancel", role: .cancel) { deviceToForget = nil }
    } message: {
      Text("Your headphones remove this pairing. To use them with that device again, pair it from scratch.")
    }
  }
}

private struct PairedDeviceRow: View {
  @EnvironmentObject private var controller: HeadphoneController
  let device: PairedDevice
  let isThisMac: Bool
  let onForget: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isThisMac ? "laptopcomputer" : (device.isConnected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3"))
        .font(.system(.callout, weight: .medium))
        .foregroundStyle(device.isConnected ? XMTheme.accentBright : XMTheme.tertiaryText)
        .frame(width: 28, height: 28)
        .background(device.isConnected ? XMTheme.accent.opacity(0.12) : Color.white.opacity(0.035), in: .rect(cornerRadius: 8))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(device.name).font(.callout.weight(.medium)).lineLimit(1)
          if isThisMac {
            Text("THIS MAC")
              .font(.system(size: 9, weight: .bold)).tracking(0.8)
              .foregroundStyle(XMTheme.accentBright)
              .padding(.horizontal, 5).padding(.vertical, 2)
              .background(XMTheme.accent.opacity(0.14), in: Capsule())
          }
        }
        Text(status)
          .font(.caption2)
          .foregroundStyle(device.isPlaybackSource ? XMTheme.success : XMTheme.secondaryText)
      }
      Spacer(minLength: 8)
      if device.isConnected, !device.isPlaybackSource {
        Button("Play here") { controller.playOn(device) }
          .controlSize(.small)
          .help("Make \(device.name) the playback source")
      }
      Menu {
        if device.isConnected {
          if !device.isPlaybackSource {
            Button("Play from this device") { controller.playOn(device) }
          }
          if !isThisMac {
            Button("Disconnect") { controller.disconnect(device) }
          }
        } else {
          Button("Connect") { controller.connect(device) }
        }
        if !isThisMac {
          Divider()
          Button("Forget…", role: .destructive, action: onForget)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Actions for \(device.name)")
    }
    .accessibilityElement(children: .contain)
  }

  private var status: String {
    if device.isPlaybackSource { return "Playing" }
    if device.isConnected { return "Connected" }
    return "Paired"
  }
}

/// Menu bar quick switch, shown only when another device is connected too.
struct CompactDevicesBar: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    if let connected = controller.pairedDevices?.devices.filter({ $0.isConnected }), connected.count > 1 {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(connected) { device in
          HStack(spacing: 8) {
            Image(systemName: controller.isThisMac(device) ? "laptopcomputer" : "iphone.gen3")
              .font(.caption)
              .foregroundStyle(device.isPlaybackSource ? XMTheme.success : XMTheme.secondaryText)
              .frame(width: 16)
              .accessibilityHidden(true)
            Text(controller.isThisMac(device) ? "This Mac" : device.name)
              .font(.caption.weight(.medium))
              .lineLimit(1)
            Spacer(minLength: 6)
            if device.isPlaybackSource {
              Text("Playing").font(.caption2).foregroundStyle(XMTheme.success)
            } else {
              Button("Play here") { controller.playOn(device) }
                .controlSize(.mini)
            }
          }
        }
        DeviceNotice(text: controller.deviceNotice)
      }
      .padding(10)
      .xmCardSurface()
    }
  }
}

// MARK: - Automation

struct AutomationSection: View {
  @EnvironmentObject private var automation: Automation

  var body: some View {
    ControlCard("Automation", symbol: "wand.and.stars") {
      FeatureToggleRow(
        symbol: "macwindow.on.rectangle",
        title: "Profiles by app",
        subtitle: "Apply a profile while an app is in front, then put your settings back",
        isOn: $automation.appProfilesEnabled
      )

      if automation.appProfilesEnabled {
        VStack(spacing: 8) {
          ForEach(automation.rules) { rule in
            AppRuleRow(rule: rule)
          }
          HStack {
            Menu {
              ForEach(ListeningProfile.allCases) { profile in
                Button(profile.title) { automation.chooseApp(profile: profile) }
              }
            } label: {
              Label("Add app…", systemImage: "plus")
                .font(.caption.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
          }
        }
        .padding(.leading, 39)
      }

      InsetDivider()

      FeatureToggleRow(
        symbol: "command",
        title: "Keyboard shortcuts",
        subtitle: "Work in any app. No extra permissions.",
        isOn: $automation.hotkeysEnabled
      )
      if automation.hotkeysEnabled {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(HotKeyCenter.bindings.indices, id: \.self) { index in
            let binding = HotKeyCenter.bindings[index]
            HStack {
              Text(binding.label)
                .font(.caption.monospaced().weight(.semibold))
                .frame(width: 64, alignment: .leading)
              Text(Self.describe(binding.key))
                .font(.caption).foregroundStyle(XMTheme.secondaryText)
            }
          }
        }
        .padding(.leading, 39)
      }

      InsetDivider()

      VStack(alignment: .leading, spacing: 4) {
        Label("Shortcuts and scripts", systemImage: "link")
          .font(.callout.weight(.medium))
        Text("Open sonyformac://profile/focus, sonyformac://profile/off, sonyformac://mode/nc, sonyformac://mode/transparency, sonyformac://mode/off or sonyformac://mode/next.")
          .font(.caption2.monospaced())
          .foregroundStyle(XMTheme.secondaryText)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  static func describe(_ key: HotKeyCenter.Key) -> String {
    switch key {
    case .nextMode: return "Next listening mode"
    case .profile(let profile): return "\(profile.title) profile on/off"
    }
  }
}

private struct AppRuleRow: View {
  @EnvironmentObject private var automation: Automation
  let rule: AppProfileRule

  var body: some View {
    HStack(spacing: 8) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
      Text(rule.appName).font(.caption.weight(.medium)).lineLimit(1)
      Spacer(minLength: 6)
      Menu {
        ForEach(ListeningProfile.allCases) { profile in
          Button(profile.title) { automation.setProfile(profile, for: rule) }
        }
      } label: {
        SoftMenuLabel(text: rule.listeningProfile?.title ?? "—")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      Button {
        automation.removeRule(rule)
      } label: {
        Image(systemName: "minus.circle").foregroundStyle(XMTheme.secondaryText)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Remove \(rule.appName)")
    }
  }

  private var icon: NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
  }
}
