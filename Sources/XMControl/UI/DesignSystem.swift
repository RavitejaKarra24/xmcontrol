import SwiftUI

// MARK: - Visual language

enum XMTheme {
  static let canvas = Color(red: 0.035, green: 0.055, blue: 0.063)
  static let canvasRaised = Color(red: 0.065, green: 0.085, blue: 0.094)
  static let surface = Color.white.opacity(0.055)
  static let surfaceHover = Color.white.opacity(0.085)
  static let hairline = Color.white.opacity(0.09)
  static let hairlineStrong = Color.white.opacity(0.16)
  static let secondaryText = Color.white.opacity(0.72)
  static let tertiaryText = Color.white.opacity(0.58)
  static let accent = Color(red: 0.32, green: 0.76, blue: 0.69)
  static let accentBright = Color(red: 0.60, green: 0.91, blue: 0.80)
  static let success = Color(red: 0.35, green: 0.84, blue: 0.59)
  static let warning = Color(red: 1.0, green: 0.66, blue: 0.28)
}

struct DarkCanvas: View {
  var body: some View {
    XMTheme.canvas
      .overlay(alignment: .topLeading) {
        RadialGradient(
          colors: [XMTheme.accent.opacity(0.17), .clear],
          center: .topLeading,
          startRadius: 0,
          endRadius: 310
        )
        .frame(width: 380, height: 340)
        .offset(x: -90, y: -120)
        .allowsHitTesting(false)
      }
      .overlay(alignment: .topTrailing) {
        RadialGradient(
          colors: [XMTheme.accent.opacity(0.06), .clear],
          center: .topTrailing,
          startRadius: 0,
          endRadius: 260
        )
        .frame(width: 300, height: 300)
        .offset(x: 100, y: -130)
        .allowsHitTesting(false)
      }
      .ignoresSafeArea()
  }
}

private struct CardSurfaceModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content
      .background(
        reduceTransparency ? XMTheme.canvasRaised : XMTheme.surface,
        in: .rect(cornerRadius: 16)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(
            contrast == .increased ? XMTheme.hairlineStrong : XMTheme.hairline,
            lineWidth: contrast == .increased ? 1.25 : 0.75
          )
      }
      .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
  }
}

extension View {
  func xmCardSurface() -> some View {
    modifier(CardSurfaceModifier())
  }
}

struct ControlCard<Content: View, Trailing: View>: View {
  let title: String
  let symbol: String
  @ViewBuilder let trailing: Trailing
  @ViewBuilder let content: Content

  init(
    _ title: String,
    symbol: String,
    @ViewBuilder trailing: () -> Trailing,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.trailing = trailing()
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 9) {
        Image(systemName: symbol)
          .font(.system(.caption, weight: .semibold))
          .foregroundStyle(XMTheme.accentBright)
          .frame(width: 24, height: 24)
          .background(XMTheme.accent.opacity(0.12), in: .rect(cornerRadius: 7))
          .accessibilityHidden(true)

        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)

        Spacer(minLength: 8)
        trailing
      }

      content
    }
    .padding(18)
    .xmCardSurface()
  }
}

extension ControlCard where Trailing == EmptyView {
  init(
    _ title: String,
    symbol: String,
    @ViewBuilder content: () -> Content
  ) {
    self.init(title, symbol: symbol, trailing: { EmptyView() }, content: content)
  }
}

struct StatusPill: View {
  let color: Color
  let text: String

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
        .shadow(color: color.opacity(0.7), radius: 4)
      Text(text)
        .font(.caption2.weight(.medium))
        .foregroundStyle(XMTheme.secondaryText)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(Color.white.opacity(0.05), in: Capsule())
    .overlay { Capsule().strokeBorder(XMTheme.hairline, lineWidth: 0.75) }
    .accessibilityElement(children: .combine)
  }
}

struct MetricChip: View {
  let symbol: String
  let text: String
  var tint: Color = XMTheme.secondaryText

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.caption.weight(.medium))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color.white.opacity(0.045), in: Capsule())
      .overlay { Capsule().strokeBorder(XMTheme.hairline, lineWidth: 0.75) }
  }
}

struct FeatureToggleRow: View {
  let symbol: String
  let title: String
  let subtitle: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: symbol)
        .font(.system(.body, weight: .medium))
        .foregroundStyle(isOn ? XMTheme.accentBright : XMTheme.secondaryText)
        .frame(width: 28, height: 28)
        .background(
          isOn ? XMTheme.accent.opacity(0.12) : Color.white.opacity(0.035),
          in: .rect(cornerRadius: 8)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(XMTheme.secondaryText)
          .lineLimit(2)
      }

      Spacer(minLength: 10)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(XMTheme.accent)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityRepresentation {
      Toggle("\(title), \(subtitle)", isOn: $isOn)
    }
  }
}

struct InsetDivider: View {
  var body: some View {
    Rectangle()
      .fill(XMTheme.hairline)
      .frame(height: 1)
  }
}

struct MenuValueRow<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    HStack {
      Text(title)
        .font(.callout)
        .foregroundStyle(XMTheme.secondaryText)
      Spacer(minLength: 12)
      content
    }
  }
}

struct SoftMenuLabel: View {
  let text: String

  var body: some View {
    HStack(spacing: 6) {
      Text(text)
        .font(.caption.weight(.medium))
      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(XMTheme.tertiaryText)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(XMTheme.hairline, lineWidth: 0.75)
    }
  }
}

struct IconActionButton: View {
  let symbol: String
  let label: String
  var role: ButtonRole?
  let action: () -> Void

  @State private var hovered = false

  var body: some View {
    Button(role: role, action: action) {
      Image(systemName: symbol)
        .font(.system(.callout, weight: .semibold))
        .frame(width: 36, height: 36)
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        .background(
          hovered ? XMTheme.surfaceHover : Color.white.opacity(0.045),
          in: .rect(cornerRadius: 9)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9)
            .strokeBorder(hovered ? XMTheme.hairlineStrong : XMTheme.hairline, lineWidth: 0.75)
        }
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(label)
    .accessibilityLabel(label)
  }
}
