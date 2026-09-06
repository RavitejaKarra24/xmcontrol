import SwiftUI

// MARK: - Device hero

struct StatusHeader: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    switch controller.conn {
    case .connected(let name):
      connectedHeader(name: name)
    case .connecting:
      transientHeader(
        symbol: "antenna.radiowaves.left.and.right",
        title: "Connecting",
        detail: "Opening Sony control channel…",
        color: XMTheme.accentBright,
        showsProgress: true
      )
    case .waitingForHeadphones:
      transientHeader(
        symbol: "headphones.slash",
        title: "Headphones unavailable",
        detail: "Connect your XM5 in Bluetooth settings.",
        color: XMTheme.warning
      )
    case .failed(let reason):
      transientHeader(
        symbol: "exclamationmark.triangle.fill",
        title: "Connection interrupted",
        detail: "\(reason). Retrying automatically.",
        color: XMTheme.warning
      )
    case .idle:
      transientHeader(
        symbol: "power",
        title: "XM Control",
        detail: "Ready when your headphones are.",
        color: XMTheme.secondaryText
      )
    }
  }

  private func connectedHeader(name: String) -> some View {
    HStack(spacing: 13) {
      Image(systemName: "headphones")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(
          LinearGradient(
            colors: [XMTheme.accent.opacity(0.92), XMTheme.accentBright.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          in: .rect(cornerRadius: 15)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 15)
            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: XMTheme.accent.opacity(0.28), radius: 14, y: 6)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(controller.model.isEmpty ? name : controller.model)
          .font(.title3.weight(.semibold))
          .lineLimit(1)
        HStack(spacing: 7) {
          StatusPill(color: controller.isReady ? XMTheme.success : XMTheme.warning, text: controller.isReady ? "Connected" : "Syncing")
          if controller.codec != .unsettled {
            MetricChip(symbol: "waveform", text: controller.codec.label)
          }
        }
      }

      Spacer(minLength: 8)

      if let battery = controller.battery {
        VStack(alignment: .trailing, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(battery.percent)")
              .font(.title2.weight(.semibold).monospacedDigit())
            Text("%")
              .font(.caption.weight(.semibold))
              .foregroundStyle(XMTheme.secondaryText)
            if battery.charging == .charging {
              Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(XMTheme.success)
            }
          }
          Text(controller.firmware.isEmpty ? "Battery" : "Firmware \(controller.firmware)")
            .font(.caption2)
            .foregroundStyle(XMTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery \(battery.percent) percent")
      }
    }
    .padding(14)
    .xmCardSurface()
  }

  private func transientHeader(
    symbol: String,
    title: String,
    detail: String,
    color: Color,
    showsProgress: Bool = false
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(.title3, weight: .medium))
        .foregroundStyle(color)
        .frame(width: 44, height: 44)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 13))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline)
        Text(detail)
          .font(.caption)
          .foregroundStyle(XMTheme.secondaryText)
          .lineLimit(2)
      }

      Spacer(minLength: 8)
      if showsProgress {
        ProgressView()
          .controlSize(.small)
          .tint(color)
      }
    }
    .padding(14)
    .xmCardSurface()
  }
}

// MARK: - Listening mode

struct AmbientSection: View {
  @EnvironmentObject private var controller: HeadphoneController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ControlCard("Listening mode", symbol: "waveform") {
      HStack(spacing: 7) {
        ForEach(ANCMode.allCases) { mode in
          ListeningModeButton(
            mode: mode,
            selected: controller.anc.mode == mode,
            action: { controller.setMode(mode) }
          )
        }
      }

      if controller.anc.mode == .ambient {
        InsetDivider()
          .transition(.opacity)

        VStack(spacing: 12) {
          HStack {
            Label("Transparency", systemImage: "ear.badge.waveform")
              .font(.callout.weight(.medium))
            Spacer()
            Text("\(controller.anc.ambientLevel)")
              .font(.caption.weight(.semibold).monospacedDigit())
              .foregroundStyle(XMTheme.accentBright)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(XMTheme.accent.opacity(0.12), in: Capsule())
          }

          Slider(
            value: Binding(
              get: { Double(max(1, min(20, controller.anc.ambientLevel))) },
              set: { controller.setAmbientLevel(Int($0.rounded())) }
            ),
            in: 1...20,
            step: 1
          )
          .tint(XMTheme.accent)
          .accessibilityLabel("Transparency level")
          .accessibilityValue("\(controller.anc.ambientLevel) of 20")

          FeatureToggleRow(
            symbol: "person.wave.2.fill",
            title: "Focus on Voice",
            subtitle: "Prioritize nearby speech",
            isOn: Binding(
              get: { controller.anc.voiceFocus },
              set: { controller.setVoiceFocus($0) }
            )
          )
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: controller.anc.mode)
  }
}

private struct ListeningModeButton: View {
  let mode: ANCMode
  let selected: Bool
  let action: () -> Void

  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: mode.symbol)
          .font(.system(.body, weight: .semibold))
        Text(mode.shortTitle)
          .font(.caption2.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(selected ? Color.white : XMTheme.secondaryText)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(background, in: .rect(cornerRadius: 11))
      .overlay {
        RoundedRectangle(cornerRadius: 11)
          .strokeBorder(
            selected ? XMTheme.accentBright.opacity(0.5) : XMTheme.hairline, lineWidth: 0.75)
      }
      .scaleEffect(selected ? 1 : (hovered ? 0.985 : 0.97))
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .accessibilityLabel(mode.title)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .animation(.smooth(duration: 0.18), value: selected)
    .animation(.easeOut(duration: 0.12), value: hovered)
  }

  private var background: some ShapeStyle {
    if selected {
      return AnyShapeStyle(
        LinearGradient(
          colors: [XMTheme.accent.opacity(0.92), XMTheme.accent.opacity(0.68)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
    return AnyShapeStyle(hovered ? XMTheme.surfaceHover : Color.white.opacity(0.035))
  }
}

// MARK: - Equalizer

private enum EQBand: Int, CaseIterable, Identifiable {
  case clearBass
  case hz400
  case khz1
  case khz2Point5
  case khz6Point3
  case khz16

  var id: Self { self }
  var shortLabel: String {
    switch self {
    case .clearBass: return "Bass"
    case .hz400: return "400"
    case .khz1: return "1k"
    case .khz2Point5: return "2.5k"
    case .khz6Point3: return "6.3k"
    case .khz16: return "16k"
    }
  }
  var fullLabel: String { EQState.bandLabels[rawValue] }
}

struct EQSection: View {
  @EnvironmentObject private var controller: HeadphoneController

  private var currentPreset: EQPreset? {
    EQPreset(rawValue: controller.eq.preset)
  }

  var body: some View {
    ControlCard(
      "Equalizer", symbol: "slider.vertical.3",
      trailing: {
        presetMenu
      },
      content: {
        HStack(alignment: .top, spacing: 6) {
          ForEach(EQBand.allCases) { band in
            EQBandControl(band: band)
          }
        }
        .frame(maxWidth: .infinity)

        HStack {
          Button("Reset to flat") { controller.resetEqualizer() }
          Spacer()
          if controller.savedEQBands != nil {
            Button("Restore saved") { controller.restoreEqualizer() }
          }
          Button("Save curve") { controller.saveEqualizer() }
        }
        .font(.caption)
        .buttonStyle(.borderless)

        Text(currentPreset == .custom ? "Custom curve · ±10 steps" : "Move any band to create a custom curve")
          .font(.caption2)
          .foregroundStyle(XMTheme.tertiaryText)
          .frame(maxWidth: .infinity, alignment: .center)
      }
    )
  }

  private var presetMenu: some View {
    Menu {
      ForEach(EQPreset.allCases) { preset in
        Button {
          controller.selectPreset(preset)
        } label: {
          if currentPreset == preset {
            Label(preset.label, systemImage: "checkmark")
          } else {
            Text(preset.label)
          }
        }
      }
    } label: {
      SoftMenuLabel(text: currentPreset?.label ?? "Preset")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel("Equalizer preset")
  }
}

private struct EQBandControl: View {
  @EnvironmentObject private var controller: HeadphoneController
  let band: EQBand

  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var wireValue: Int {
    guard controller.eq.bands.indices.contains(band.rawValue) else { return 10 }
    return controller.eq.bands[band.rawValue]
  }

  private var binding: Binding<Double> {
    Binding(
      get: { Double(wireValue) },
      set: { controller.setBand(index: band.rawValue, wireValue: Int($0.rounded())) }
    )
  }

  var body: some View {
    VStack(spacing: 7) {
      Text(dbLabel)
        .font(.caption2.weight(.semibold).monospacedDigit())
        .foregroundStyle(wireValue == 10 ? XMTheme.tertiaryText : XMTheme.accentBright)

      GeometryReader { proxy in
        let height = proxy.size.height
        let width = proxy.size.width
        let normalized = CGFloat(wireValue) / 20
        let knobY = min(height - 6, max(6, height * (1 - normalized)))

        ZStack(alignment: .topLeading) {
          Capsule()
            .fill(Color.white.opacity(hovered ? 0.09 : 0.055))
            .frame(width: 5, height: height)
            .position(x: width / 2, y: height / 2)

          Capsule()
            .fill(
              LinearGradient(
                colors: [XMTheme.accent, XMTheme.accentBright],
                startPoint: .bottom,
                endPoint: .top
              )
            )
            .frame(width: 5, height: max(2, height * normalized))
            .position(x: width / 2, y: height - (height * normalized / 2))
            .shadow(color: XMTheme.accent.opacity(0.32), radius: 5)

          Rectangle()
            .fill(Color.white.opacity(0.13))
            .frame(width: 17, height: 1)
            .position(x: width / 2, y: height / 2)

          Circle()
            .fill(hovered ? Color.white : Color.white.opacity(0.92))
            .frame(width: hovered ? 14 : 12, height: hovered ? 14 : 12)
            .overlay { Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .position(x: width / 2, y: knobY)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let normalizedValue = 1 - min(1, max(0, value.location.y / height))
              controller.setBand(
                index: band.rawValue,
                wireValue: Int((normalizedValue * 20).rounded())
              )
            }
        )
      }
      .frame(height: 92)

      Text(band.shortLabel)
        .font(.caption2.weight(.medium))
        .foregroundStyle(XMTheme.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .onHover { hovered = $0 }
    .focusable()
    .focused($focused)
    .onKeyPress(.upArrow) {
      controller.setBand(index: band.rawValue, wireValue: wireValue + 1)
      return .handled
    }
    .onKeyPress(.downArrow) {
      controller.setBand(index: band.rawValue, wireValue: wireValue - 1)
      return .handled
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(focused ? XMTheme.accent : .clear, lineWidth: 2)
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    .accessibilityRepresentation {
      Slider(value: binding, in: 0...20, step: 1) {
        Text(band.fullLabel)
      }
      .accessibilityValue(dbLabel)
    }
  }

  private var dbLabel: String {
    let db = wireValue - 10
    return db == 0 ? "0" : "\(db > 0 ? "+" : "")\(db)"
  }
}

// MARK: - Smart audio

struct AudioSection: View {
  @EnvironmentObject private var controller: HeadphoneController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ControlCard("Smart audio", symbol: "sparkles") {
      FeatureToggleRow(
        symbol: "waveform.badge.plus",
        title: "DSEE Extreme",
        subtitle: "Restore detail in compressed audio",
        isOn: Binding(
          get: { controller.dseeOn },
          set: { controller.setDSEE($0) }
        )
      )

      InsetDivider()

      FeatureToggleRow(
        symbol: "person.wave.2",
        title: "Speak-to-Chat",
        subtitle: "Pause playback when you speak",
        isOn: Binding(
          get: { controller.speakToChatOn },
          set: { controller.setSpeakToChat($0) }
        )
      )

      if controller.speakToChatOn {
        VStack(spacing: 9) {
          MenuValueRow("Sensitivity") {
            Menu {
              ForEach(STCSensitivity.allCases) { sensitivity in
                Button(sensitivity.label) {
                  controller.setSpeakToChatDetail(
                    sensitivity: sensitivity,
                    timeout: controller.stcTimeout
                  )
                }
              }
            } label: {
              SoftMenuLabel(text: controller.stcSensitivity.label)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          }

          MenuValueRow("Resume delay") {
            Menu {
              ForEach(STCTimeout.allCases) { timeout in
                Button(timeout.label) {
                  controller.setSpeakToChatDetail(
                    sensitivity: controller.stcSensitivity,
                    timeout: timeout
                  )
                }
              }
            } label: {
              SoftMenuLabel(text: controller.stcTimeout.label)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          }
        }
        .padding(.leading, 39)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: controller.speakToChatOn)
  }
}

// MARK: - Bluetooth priority

struct ConnectionSection: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    ControlCard("Connection", symbol: "antenna.radiowaves.left.and.right") {
      HStack(spacing: 8) {
        ConnectionPriorityButton(
          title: "Sound quality",
          subtitle: "Best detail",
          symbol: "waveform",
          selected: controller.qualityPrior,
          action: { controller.setConnectionMode(qualityPrior: true) }
        )
        ConnectionPriorityButton(
          title: "Stable",
          subtitle: "Fewer dropouts",
          symbol: "link",
          selected: !controller.qualityPrior,
          action: { controller.setConnectionMode(qualityPrior: false) }
        )
      }
    }
  }
}

private struct ConnectionPriorityButton: View {
  let title: String
  let subtitle: String
  let symbol: String
  let selected: Bool
  let action: () -> Void

  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(.caption, weight: .semibold))
          .foregroundStyle(selected ? XMTheme.accentBright : XMTheme.secondaryText)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.caption.weight(.semibold))
          Text(subtitle).font(.caption2).foregroundStyle(XMTheme.secondaryText)
        }
        Spacer(minLength: 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity)
      .background(
        selected ? XMTheme.accent.opacity(0.11) : Color.white.opacity(hovered ? 0.06 : 0.03),
        in: .rect(cornerRadius: 10)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(selected ? XMTheme.accent.opacity(0.55) : XMTheme.hairline, lineWidth: 0.75)
      }
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

// MARK: - Playback

struct PlaybackSection: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    ControlCard("Playback", symbol: "play.fill") {
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        IconActionButton(symbol: "backward.end.fill", label: "Previous track") {
          controller.playback(.trackDown)
        }
        IconActionButton(symbol: "play.fill", label: "Play") {
          controller.playback(.play)
        }
        IconActionButton(symbol: "pause.fill", label: "Pause") {
          controller.playback(.pause)
        }
        IconActionButton(symbol: "forward.end.fill", label: "Next track") {
          controller.playback(.trackUp)
        }
        Spacer(minLength: 0)
      }

      HStack(spacing: 10) {
        Image(systemName: "speaker.fill")
          .font(.caption)
          .foregroundStyle(XMTheme.secondaryText)
          .accessibilityHidden(true)
        Slider(
          value: Binding(
            get: { Double(controller.volume) },
            set: { controller.setVolume(Int($0.rounded())) }
          ),
          in: 0...30,
          step: 1
        )
        .tint(XMTheme.accent)
        .accessibilityLabel("Headphone volume")
        .accessibilityValue("\(controller.volume) of 30")
        Text("\(controller.volume)")
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(XMTheme.secondaryText)
          .frame(width: 22, alignment: .trailing)
      }
    }
  }
}

// MARK: - Device settings

struct PowerSection: View {
  @EnvironmentObject private var controller: HeadphoneController

  @State private var confirmingPowerOff = false

  var body: some View {
    ControlCard("Device", symbol: "gearshape.fill") {
      MenuValueRow("Auto power-off") {
        Menu {
          ForEach(AutoPowerOffSetting.allCases) { setting in
            Button(setting.label) { controller.setAutoPowerOff(setting) }
          }
        } label: {
          SoftMenuLabel(text: controller.autoPowerOff.label)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }

      InsetDivider()

      Button(role: .destructive) {
        confirmingPowerOff = true
      } label: {
        Label("Power off headphones", systemImage: "power")
          .font(.callout.weight(.medium))
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .background(Color.red.opacity(0.07), in: .rect(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(Color.red.opacity(0.22), lineWidth: 0.75)
          }
      }
      .buttonStyle(.plain)
      .confirmationDialog("Power off your headphones?", isPresented: $confirmingPowerOff) {
        Button("Power off", role: .destructive) { controller.powerOff() }
        Button("Cancel", role: .cancel) { }
      } message: {
        Text("Playback will stop. Turn the headphones on again using their power button.")
      }
    }
  }
}

// MARK: - Footer

struct ConnectionFooter: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    HStack(spacing: 8) {
      StatusPill(
        color: controller.conn.isUp ? XMTheme.success : XMTheme.warning,
        text: statusText
      )

      Spacer(minLength: 8)

      Button {
        controller.reconnect()
      } label: {
        Label("Reconnect", systemImage: "arrow.clockwise")
          .font(.caption.weight(.medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(XMTheme.secondaryText)
      .help("Reconnect headphones")
      .disabled(controller.conn == .connecting)

      Rectangle()
        .fill(XMTheme.hairline)
        .frame(width: 1, height: 14)

      Button {
        NSApp.terminate(nil)
      } label: {
        Label("Quit", systemImage: "xmark")
          .font(.caption.weight(.medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(XMTheme.secondaryText)
      .keyboardShortcut("q", modifiers: .command)
    }
    .padding(.horizontal, 2)
  }

  private var statusText: String {
    switch controller.conn {
    case .connected: return controller.isReady ? "Live" : "Syncing"
    case .waitingForHeadphones: return "Offline"
    case .connecting: return "Connecting"
    case .failed: return "Retrying"
    case .idle: return "Idle"
    }
  }
}
