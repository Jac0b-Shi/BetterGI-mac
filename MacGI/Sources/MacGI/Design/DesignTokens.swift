import SwiftUI

enum BGIColors {
    static let appBackground = Color(red: 0.055, green: 0.067, blue: 0.083)
    static let sidebarBackground = Color(red: 0.075, green: 0.087, blue: 0.106)
    static let cardBackground = Color(red: 0.105, green: 0.121, blue: 0.145)
    static let cardElevated = Color(red: 0.135, green: 0.153, blue: 0.18)
    static let border = Color.white.opacity(0.095)
    static let borderStrong = Color.white.opacity(0.18)
    static let primaryText = Color(red: 0.925, green: 0.94, blue: 0.96)
    static let secondaryText = Color(red: 0.66, green: 0.70, blue: 0.76)
    static let mutedText = Color(red: 0.45, green: 0.50, blue: 0.57)
    static let accent = Color(red: 0.27, green: 0.62, blue: 0.92)
    static let accentSoft = Color(red: 0.15, green: 0.36, blue: 0.56)
    static let success = Color(red: 0.32, green: 0.82, blue: 0.55)
    static let warning = Color(red: 0.94, green: 0.68, blue: 0.26)
    static let danger = Color(red: 0.92, green: 0.30, blue: 0.35)
    static let muted = Color(red: 0.48, green: 0.55, blue: 0.64)
    static let consoleBackground = Color(red: 0.025, green: 0.032, blue: 0.044)
}

enum BGIRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 8
    static let large: CGFloat = 10
}

enum BGISpacing {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xlarge: CGFloat = 24
}

enum BGIFonts {
    static let title = Font.system(size: 22, weight: .semibold)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .medium)
    static let console = Font.system(size: 12, weight: .regular, design: .monospaced)
}

struct BGICardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(BGIColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BGIRadius.medium, style: .continuous)
                    .stroke(BGIColors.border, lineWidth: 1)
            )
    }
}

extension View {
    func bgiCard() -> some View {
        modifier(BGICardBackground())
    }
}
