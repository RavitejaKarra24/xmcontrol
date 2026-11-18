import SwiftUI

struct SoundPressureSection: View {
  @EnvironmentObject private var controller: HeadphoneController

  var body: some View {
    ControlCard("Sound pressure", symbol: "ear.badge.waveform", trailing: {
      if controller.soundPressure.decibels != nil {
        StatusPill(color: XMTheme.accentBright, text: "Live")
      }
    }) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(controller.soundPressure.decibels.map(String.init) ?? "—")
          .font(.system(size: 42, weight: .medium, design: .rounded).monospacedDigit())
          .foregroundStyle(XMTheme.accentBright)
          .frame(minWidth: 62, alignment: .leading)
        Text("dB")
          .font(.title3.weight(.medium))
          .foregroundStyle(XMTheme.secondaryText)
        Spacer()
        if controller.soundPressure == .waiting {
          ProgressView().controlSize(.small)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Current sound pressure")
      .accessibilityValue(controller.soundPressure.decibels.map { "\($0) decibels, headphone estimate" } ?? controller.soundPressure.title)

      VStack(alignment: .leading, spacing: 5) {
        Text(controller.soundPressure.title)
          .font(.callout.weight(.medium))
        Text(controller.soundPressure.detail)
          .font(.caption)
          .foregroundStyle(XMTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      if controller.soundPressure == .unavailable {
        Button("Check again") { controller.retrySoundPressure() }
          .buttonStyle(.borderless)
          .font(.caption)
      }
    }
  }
}
