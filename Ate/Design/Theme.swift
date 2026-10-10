import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static func dyn(_ l: UInt32, _ d: UInt32) -> Color { dynamic(UIColor(hex: l), UIColor(hex: d)) }
}

/// PRD §9.1 design tokens.
enum Theme {
    static let background = Color.dyn(0xFCF7ED, 0x1A120C)
    static let foreground = Color.dyn(0x311F16, 0xF3EEE4)
    static let card = Color.dyn(0xFFFDF7, 0x271D16)
    static let primary = Color.dyn(0xC95028, 0xE77140)
    static let primaryForeground = Color.dyn(0xFEFAF1, 0x190F0A)
    static let secondary = Color.dyn(0xF3EAD7, 0x352820)
    static let secondaryForeground = Color.dyn(0x442C21, 0xF3EEE4)
    static let muted = Color.dyn(0xF3ECDF, 0x352820)
    static let mutedForeground = Color.dyn(0x7B675B, 0xADA397)
    static let accent = Color.dyn(0x4E7F50, 0x5E9660)
    static let warm = Color.dyn(0xF5E2C0, 0x453421)
    static let warmForeground = Color.dyn(0x512E1A, 0xEFE3CF)
    static let destructive = Color.dyn(0xCC2827, 0xFF6467)
    static let border = Color.dynamic(UIColor(hex: 0xE6DDCE), UIColor(white: 1, alpha: 0.10))
    static let input = Color.dynamic(UIColor(hex: 0xE6DDCE), UIColor(white: 1, alpha: 0.15))
    static let brown = Color(UIColor(hex: 0x311F16))
    static let maxWidth: CGFloat = 672
}

/// Fraunces / DM Sans, bundled. `Font.custom` falls back to the system font if a face is missing.
enum AteFont {
    static var hasFraunces: Bool { UIFont(name: "Fraunces", size: 12) != nil || !UIFont.fontNames(forFamilyName: "Fraunces").isEmpty }
    static var hasDMSans: Bool { !UIFont.fontNames(forFamilyName: "DM Sans").isEmpty }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        hasFraunces ? Font.custom("Fraunces", size: size).weight(weight) : .system(size: size, weight: weight, design: .serif)
    }
    static func body(_ size: CGFloat = 16, _ weight: Font.Weight = .regular) -> Font {
        hasDMSans ? Font.custom("DM Sans", size: size).weight(weight) : .system(size: size, weight: weight)
    }
}

struct CardSurface: ViewModifier {
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .shadow(color: Theme.brown.opacity(0.06), radius: 1, y: 1)
            .shadow(color: Theme.brown.opacity(0.18), radius: 15, y: 12)
    }
}

extension View {
    func cardSurface(padding: CGFloat = 0) -> some View { modifier(CardSurface(padding: padding)) }
    func floatShadow() -> some View { shadow(color: Theme.primary.opacity(0.45), radius: 15, y: 10) }
    func overline() -> some View {
        font(AteFont.body(12, .bold)).textCase(.uppercase).tracking(1.4).foregroundStyle(Theme.mutedForeground)
    }
    func pageWidth() -> some View { frame(maxWidth: Theme.maxWidth).frame(maxWidth: .infinity) }
}

enum AteButtonKind { case primary, secondary, ghost, destructiveGhost, outline }

struct AteButtonStyle: ButtonStyle {
    var kind: AteButtonKind = .primary
    var height: CGFloat = 48
    var capsule = true
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg): (Color, Color) = {
            switch kind {
            case .primary: return (Theme.primary, Theme.primaryForeground)
            case .secondary: return (Theme.secondary, Theme.secondaryForeground)
            case .ghost: return (.clear, Theme.foreground)
            case .destructiveGhost: return (.clear, Theme.destructive)
            case .outline: return (.clear, Theme.foreground)
            }
        }()
        return configuration.label
            .font(AteFont.body(15, .semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: capsule ? height / 2 : 14, style: .continuous))
            .overlay {
                if kind == .outline { RoundedRectangle(cornerRadius: capsule ? height / 2 : 14).stroke(Theme.border) }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == AteButtonStyle {
    static func ate(_ kind: AteButtonKind = .primary, height: CGFloat = 48, full: Bool = false) -> AteButtonStyle {
        AteButtonStyle(kind: kind, height: height, fullWidth: full)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.foreground
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(tint).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}
