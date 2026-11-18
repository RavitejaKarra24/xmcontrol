import SwiftUI

// MARK: - Visual language

enum XMTheme {
  static let canvas = Color(red: 0.031, green: 0.035, blue: 0.047)
  static let canvasRaised = Color(red: 0.060, green: 0.066, blue: 0.086)
  static let surface = Color.white.opacity(0.055)
  static let surfaceHover = Color.white.opacity(0.085)
  static let hairline = Color.white.opacity(0.09)
  static let hairlineStrong = Color.white.opacity(0.16)
  static let secondaryText = Color.white.opacity(0.72)
  static let tertiaryText = Color.white.opacity(0.58)
  // Vivid electric blue tuned to stand out on the near-black canvas.
  static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
  static let accentBright = Color(red: 0.40, green: 0.80, blue: 1.0)
  static let accentDeep = Color(red: 0.0, green: 0.36, blue: 0.86)
  /// Fill for selected controls, with a soft glow to match.
  static let selectedFill = LinearGradient(
    colors: [accent, accentDeep],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  static let selectedGlow = accent.opacity(0.45)
  static let success = Color(red: 0.42, green: 0.80, blue: 0.62)
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
  var compact = false
  @ViewBuilder let trailing: Trailing
  @ViewBuilder let content: Content

  init(
    _ title: String,
    symbol: String,
    compact: Bool = false,
    @ViewBuilder trailing: () -> Trailing,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.compact = compact
    self.trailing = trailing()
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 9 : 14) {
      HStack(spacing: compact ? 7 : 9) {
        Image(systemName: symbol)
          .font(.system(.caption, weight: .semibold))
          .foregroundStyle(XMTheme.accentBright)
          .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
          .background(XMTheme.accent.opacity(0.12), in: .rect(cornerRadius: 7))
          .accessibilityHidden(true)

        Text(title)
          .font(compact ? .subheadline.weight(.semibold) : .headline)
          .foregroundStyle(.primary)

        Spacer(minLength: 8)
        trailing
      }

      content
    }
    .padding(compact ? 12 : 18)
    .xmCardSurface()
  }
}

extension ControlCard where Trailing == EmptyView {
  init(
    _ title: String,
    symbol: String,
    compact: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.init(title, symbol: symbol, compact: compact, trailing: { EmptyView() }, content: content)
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
  var size: CGFloat = 36
  let action: () -> Void

  @State private var hovered = false

  var body: some View {
    Button(role: role, action: action) {
      Image(systemName: symbol)
        .font(.system(.callout, weight: .semibold))
        .frame(width: size, height: size)
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
