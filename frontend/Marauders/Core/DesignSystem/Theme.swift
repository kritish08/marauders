import SwiftUI

enum Theme {
    static let surface = Color(hex: 0xFEF9EF)
    static let surfaceLow = Color(hex: 0xF8F3E9)
    static let surfaceContainer = Color(hex: 0xF2EDE3)
    static let surfaceHigh = Color(hex: 0xEDE8DE)
    static let ink = Color(hex: 0x1D1C16)
    static let mutedInk = Color(hex: 0x554241)
    static let primary = Color(hex: 0x6D2325)
    static let primaryContainer = Color(hex: 0x8B3A3A)
    static let gold = Color(hex: 0x775A19)
    static let goldLight = Color(hex: 0xFED488)
    static let teal = Color(hex: 0x004544)
    static let outline = Color(hex: 0xDAC1BF)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct HeritageCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
                .shadow(color: Theme.ink.opacity(0.08), radius: 16, y: 8)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: Theme.ink.opacity(0.08), radius: 16, y: 8)
        }
    }
}

extension View {
    func heritageCard() -> some View { modifier(HeritageCardModifier()) }

    // Liquid Glass capsule on iOS 26+, material capsule below.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .frame(minHeight: 54)
            .foregroundStyle(.white)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}
