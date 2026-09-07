import SwiftUI

/// A focused menu bar surface; the dashboard holds the detailed controls.
struct PanelView: View {
  @EnvironmentObject private var controller: HeadphoneController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    ZStack {
      DarkCanvas()
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Label("XM CONTROL", systemImage: "headphones")
                .font(.caption.weight(.bold)).tracking(2)
                .foregroundStyle(XMTheme.secondaryText)
              Spacer()
              Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
              } label: {
                Label("All controls", systemImage: "arrow.up.right.square")
              }
              .buttonStyle(.borderless)
              .help("Open the full headphone dashboard")
            }
            StatusHeader()
            if controller.isReady {
              SoundPressureSection()
              ProfileSection(compact: true)
              AmbientSection()
              PlaybackSection()
            } else {
              ConnectionGuide()
            }
          }
          .padding(16)
        }
        ConnectionFooter()
          .padding(16)
          .background(XMTheme.canvasRaised)
      }
    }
    .frame(width: 410, height: 720)
    .preferredColorScheme(.dark)
    .tint(XMTheme.accent)
    .onAppear { controller.ensureStarted() }
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
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Made for your moment").font(.headline)
        Spacer()
        if !compact {
          Text("ONE-CLICK PROFILES")
            .font(.caption2.weight(.semibold)).tracking(1.5)
            .foregroundStyle(XMTheme.secondaryText)
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: compact ? 2 : 4), spacing: 10) {
        ForEach(ListeningProfile.allCases) { profile in
          Button { controller.applyProfile(profile) } label: {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Image(systemName: profile.symbol)
                  .font(.system(size: 19, weight: .medium))
                  .foregroundStyle(XMTheme.accentBright)
                Spacer()
                Image(systemName: controller.matchingProfile == profile ? "checkmark.circle.fill" : "arrow.up.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(XMTheme.secondaryText)
              }
              Text(profile.title).font(.callout.weight(.semibold))
              Text(profile.detail)
                .font(.caption).foregroundStyle(XMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(XMTheme.accent.opacity(0.065), in: .rect(cornerRadius: 14))
            .overlay {
              RoundedRectangle(cornerRadius: 14).strokeBorder(XMTheme.accent.opacity(controller.matchingProfile == profile ? 0.7 : 0.22))
            }
            .contentShape(.rect(cornerRadius: 14))
          }
          .buttonStyle(ProfileButtonStyle())
          .help(profile.summary)
          .accessibilityLabel("Apply \(profile.title): \(profile.summary)")
          .accessibilityAddTraits(controller.matchingProfile == profile ? .isSelected : [])
          .disabled(!controller.isReady)
        }
      }
      if let notice = controller.notice {
        Label(notice, systemImage: "info.circle")
          .font(.caption).foregroundStyle(XMTheme.accentBright)
      } else {
        Text(controller.isReady ? "Profiles adjust listening mode, EQ and Speak-to-Chat. Volume stays yours." : "Connect your WH-1000XM5 to apply a listening profile.")
          .font(.caption).foregroundStyle(XMTheme.secondaryText)
      }
    }
  }
}

private struct ProfileButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brightness(configuration.isPressed ? 0.09 : 0)
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
