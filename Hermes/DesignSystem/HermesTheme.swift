import SwiftUI

enum HermesTheme {
    static let canvas = Color(red: 4 / 255, green: 28 / 255, blue: 28 / 255)
    static let surface = Color(red: 14 / 255, green: 40 / 255, blue: 38 / 255)
    static let raisedSurface = Color(red: 22 / 255, green: 48 / 255, blue: 45 / 255)
    static let textPrimary = Color(red: 1, green: 230 / 255, blue: 203 / 255)
    static let textSecondary = textPrimary.opacity(0.82)
    static let border = textPrimary.opacity(0.18)
    static let agent = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    static let success = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
    static let warning = Color(red: 1, green: 189 / 255, blue: 56 / 255)
    static let danger = Color(red: 251 / 255, green: 44 / 255, blue: 54 / 255)

    static let cardRadius: CGFloat = 12
}

enum HermesSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let standard: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

struct HermesCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(HermesSpacing.standard)
            .background(HermesTheme.surface, in: RoundedRectangle(cornerRadius: HermesTheme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.cardRadius)
                    .stroke(HermesTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func hermesCard() -> some View {
        modifier(HermesCardModifier())
    }

    func hermesScreen() -> some View {
        foregroundStyle(HermesTheme.textPrimary)
            .tint(HermesTheme.textPrimary)
            .background(HermesTheme.canvas.ignoresSafeArea())
    }
}
