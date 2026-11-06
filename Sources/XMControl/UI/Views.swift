import SwiftUI

/// A focused menu bar surface that fits without scrolling; the dashboard holds
/// the detailed controls.
struct PanelView: View {
  @EnvironmentObject private var controller: HeadphoneController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Label("XM CONTROL", systemImage: "headphones")
            .font(.caption.weight(.bold)).tracking(2)
            .foregroundStyle(XMTheme.secondaryText)
          Spacer()
          if let decibels = controller.soundPressure.decibels {
            MetricChip(symbol: "ear", text: "\(decibels) dB", tint: XMTheme.accentBright)
              .help("Sound pressure reported by your headphones")
          }
          Button {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
          } label: {
            Label("All controls", systemImage: "arrow.up.right.square")
              .font(.caption.weight(.medium))
          }
          .buttonStyle(.borderless)
          .help("Open the full headphone dashboard")
        }
        StatusHeader(compact: true)
        if controller.isReady {
          AmbientSection(compact: true)
          ProfileSection(compact: true)
          CompactPlaybackBar()
        } else {
          ConnectionGuide()
        }
      }
      .padding(14)
      ConnectionFooter()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(XMTheme.canvasRaised)
    }
    .frame(width: 360)
    .fixedSize(horizontal: false, vertical: true)
    .background(DarkCanvas())
    .preferredColorScheme(.dark)
    .tint(XMTheme.accent)
    .onAppear { controller.ensureStarted() }
  }
}

/// Transport and volume on a single line for the menu bar panel.
struct CompactPlaybackBar: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    HStack(spacing: 4) {
      IconActionButton(symbol: "backward.end.fill", label: "Previous track", size: 30) {
        controller.playback(.trackDown)
      }
      IconActionButton(symbol: "play.fill", label: "Play", size: 30) {
        controller.playback(.play)
      }
      IconActionButton(symbol: "pause.fill", label: "Pause", size: 30) {
        controller.playback(.pause)
      }
      IconActionButton(symbol: "forward.end.fill", label: "Next track", size: 30) {
        controller.playback(.trackUp)
      }
      Image(systemName: "speaker.fill")
        .font(.caption2)
        .foregroundStyle(XMTheme.secondaryText)
        .padding(.leading, 8)
        .accessibilityHidden(true)
      Slider(
        value: Binding(
          get: { Double(controller.volume) },
          set: { controller.setVolume(Int($0.rounded())) }
        ),
        in: 0...30,
        step: 1
      )
      .controlSize(.small)
      .tint(XMTheme.accent)
      .accessibilityLabel("Headphone volume")
      .accessibilityValue("\(controller.volume) of 30")
      Text("\(controller.volume)")
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(XMTheme.secondaryText)
        .frame(width: 20, alignment: .trailing)
    }
    .padding(10)
    .xmCardSurface()
  }
}

struct MainWindowView: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    ZStack {
      DarkCanvas()
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
              VStack(alignment: .leading, spacing: 7) {
                Text("PERSONAL AUDIO")
                  .font(.caption.weight(.bold)).tracking(3)
                  .foregroundStyle(XMTheme.accentBright)
                Text("Your listening space")
                  .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Fine-tune your headphones. Settle into your day.")
                  .font(.callout).foregroundStyle(XMTheme.secondaryText)
              }
              Spacer()
              Image(systemName: "waveform")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(XMTheme.accentBright.opacity(0.65))
                .accessibilityHidden(true)
            }
            StatusHeader()
            if !controller.isReady { ConnectionGuide() }
            ProfileSection()
            if controller.isReady {
              HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                  AmbientSection()
                  EQSection()
                  PlaybackSection()
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                  SoundPressureSection()
                  AudioSection()
                  ConnectionSection()
                  PowerSection()
                  PrivacyNote()
                }
                .frame(maxWidth: .infinity)
              }
            }
          }
          .padding(28)
          .frame(maxWidth: 1120)
          .frame(maxWidth: .infinity)
        }
        ConnectionFooter()
          .padding(.horizontal, 28)
          .padding(.vertical, 14)
          .background(XMTheme.canvasRaised)
      }
    }
    .frame(minWidth: 820, idealWidth: 960, minHeight: 700, idealHeight: 900)
    .preferredColorScheme(.dark)
    .tint(XMTheme.accent)
    .navigationTitle("XM Control")
    .onAppear { controller.ensureStarted() }
  }
}

struct ProfileSection: View {
  @EnvironmentObject private var controller: HeadphoneController
  var compact = false

  var body: some View {
    ControlCard("Made for your moment", symbol: "sparkles", compact: compact, trailing: {
      if !compact {
        Text("CLICK AGAIN TO TURN OFF")
          .font(.caption2.weight(.semibold)).tracking(1.2)
          .foregroundStyle(XMTheme.tertiaryText)
      }
    }) {
      HStack(spacing: compact ? 6 : 10) {
        ForEach(ListeningProfile.allCases) { profile in
          ProfileTile(
            profile: profile,
            selected: controller.selectedProfile == profile,
            compact: compact,
            action: { controller.toggleProfile(profile) }
          )
          .disabled(!controller.isReady)
        }
      }
      if let notice = controller.notice {
        Label(notice, systemImage: "info.circle")
          .font(.caption).foregroundStyle(XMTheme.accentBright)
          .lineLimit(2)
      } else if !compact {
        Text(controller.isReady ? "Profiles adjust listening mode, EQ and Speak-to-Chat. Volume stays yours." : "Connect your WH-1000XM5 to apply a listening profile.")
          .font(.caption).foregroundStyle(XMTheme.secondaryText)
      }
    }
  }
}

private struct ProfileTile: View {
  let profile: ListeningProfile
  let selected: Bool
  let compact: Bool
  let action: () -> Void

  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      VStack(alignment: compact ? .center : .leading, spacing: compact ? 5 : 10) {
        HStack {
          Image(systemName: profile.symbol)
            .font(.system(size: compact ? 15 : 19, weight: .medium))
            .foregroundStyle(selected ? Color.white : XMTheme.accentBright)
          if !compact {
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
              .font(.caption.weight(.semibold))
              .foregroundStyle(selected ? Color.white : XMTheme.tertiaryText)
          }
        }
        Text(profile.title)
          .font((compact ? Font.caption : Font.callout).weight(.semibold))
          .foregroundStyle(selected ? Color.white : Color.primary)
          .lineLimit(1)
        if !compact {
          Text(profile.detail)
            .font(.caption)
            .foregroundStyle(selected ? Color.white.opacity(0.85) : XMTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 32, alignment: .topLeading)
        }
      }
      .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
      .padding(.vertical, compact ? 8 : 14)
      .padding(.horizontal, compact ? 4 : 14)
      .background(background, in: .rect(cornerRadius: compact ? 11 : 14))
      .overlay {
        RoundedRectangle(cornerRadius: compact ? 11 : 14)
          .strokeBorder(selected ? XMTheme.accentBright.opacity(0.5) : XMTheme.hairline, lineWidth: 0.75)
      }
      .shadow(color: selected ? XMTheme.selectedGlow : .clear, radius: 8)
      .contentShape(.rect(cornerRadius: compact ? 11 : 14))
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(selected ? "\(profile.summary)\nClick to turn off and restore your previous settings" : profile.summary)
    .accessibilityLabel(selected ? "Turn off \(profile.title)" : "Apply \(profile.title): \(profile.summary)")
    .accessibilityAddTraits(selected ? .isSelected : [])
    .animation(.smooth(duration: 0.18), value: selected)
  }

  private var background: some ShapeStyle {
    if selected {
      return AnyShapeStyle(XMTheme.selectedFill)
    }
    return AnyShapeStyle(hovered ? XMTheme.surfaceHover : Color.white.opacity(0.035))
  }
}

struct ConnectionGuide: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if controller.conn.isUp || controller.conn == .connecting {
        HStack(spacing: 12) {
          ProgressView().controlSize(.small)
          VStack(alignment: .leading, spacing: 4) {
            Text("Getting everything in tune").font(.headline)
            Text("Reading your headphone settings. Controls will be ready in a moment.")
              .font(.callout).foregroundStyle(XMTheme.secondaryText)
          }
        }
      } else {
        Text("A direct connection. Just you and your music.")
          .font(.title3.weight(.semibold))
        Text("Turn on your WH-1000XM5 and connect it to this Mac as an audio device. XM Control will take it from there.")
          .font(.callout).foregroundStyle(XMTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
          }
        } label: {
          Label("Open Bluetooth Settings", systemImage: "arrow.up.right")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        Text("If asked, allow Bluetooth access in System Settings → Privacy & Security.")
          .font(.caption).foregroundStyle(XMTheme.secondaryText)
      }
      PrivacyNote()
    }
    .padding(22)
    .xmCardSurface()
  }
}

struct PrivacyNote: View {
  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text("Private by design").font(.caption.weight(.semibold))
        Text("Direct Bluetooth. No account, cloud, or analytics.")
          .font(.caption).foregroundStyle(XMTheme.secondaryText)
      }
    } icon: {
      Image(systemName: "lock.shield").foregroundStyle(XMTheme.accentBright)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
