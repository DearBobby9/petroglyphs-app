import SwiftUI
import UIKit

extension Color {
    static let limestone = adaptive(light: 0xF5EDE3, dark: .systemGroupedBackground)
    static let sandstone = adaptive(light: 0xE8D5C0, dark: .tertiarySystemGroupedBackground)
    static let panelBackground = adaptive(light: 0xFFFFFF, dark: .secondarySystemGroupedBackground)
    static let cardBackground = adaptive(light: 0xF5EDE3, dark: .tertiarySystemGroupedBackground)

    static let charcoal = adaptive(light: 0x3D3530, dark: .label, highContrastLight: 0x201C19)
    static let ochre = adaptive(
        light: 0xD4874D, dark: rgb(0xE9A46B), highContrastDark: rgb(0xF3BD92)
    )
    static let burntOchre = adaptive(
        light: 0x93491D, dark: rgb(0xF0B383),
        highContrastLight: 0x743715, highContrastDark: rgb(0xFFD4B0)
    )
    // Ochre is a light surface in both appearances, so its content stays dark.
    static let onAccent = Color.black
    static let moss = adaptive(
        light: 0x4F6B42, dark: rgb(0xA8C896),
        highContrastLight: 0x36502C, highContrastDark: rgb(0xBDDDAA)
    )
    static let rust = adaptive(
        light: 0x994D40, dark: rgb(0xE6A092),
        highContrastLight: 0x793B32, highContrastDark: rgb(0xFFC3B7)
    )

    static let clay       = Color(hex: "#C4956A")
    static let deepCave   = Color(hex: "#2A2320")
    static let riverBlue  = Color(hex: "#5B8FA8")
    static let dustGold   = Color(hex: "#C9A84C")
    static let slate      = Color(hex: "#8A8078")

    private static func adaptive(
        light: UInt,
        dark: UIColor,
        highContrastLight: UInt? = nil,
        highContrastDark: UIColor? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let increasedContrast = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                let color = increasedContrast ? highContrastDark ?? dark : dark
                return color.resolvedColor(with: traits)
            }
            return rgb(increasedContrast ? highContrastLight ?? light : light)
        })
    }

    private static func rgb(_ value: UInt) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
