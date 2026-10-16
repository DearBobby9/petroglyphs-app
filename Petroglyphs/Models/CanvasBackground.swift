import SwiftUI
import UIKit

struct CanvasBackground: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        let hex = rawValue.hasPrefix("#") ? String(rawValue.dropFirst()) : rawValue
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        self.init(rgb: rgb)
    }

    init(color: UIColor) {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        resolved.getRed(&red, green: &green, blue: &blue, alpha: nil)

        func byte(_ component: CGFloat) -> UInt32 {
            UInt32((min(max(component, 0), 1) * 255).rounded())
        }
        self.init(rgb: byte(red) << 16 | byte(green) << 8 | byte(blue))
    }

    private init(rgb: UInt32) {
        rawValue = String(format: "%06X", rgb)
    }

    static let white = CanvasBackground(rgb: 0xFFFFFF)
    static let warmPaper = CanvasBackground(rgb: 0xF4EDDE)
    static let gray = CanvasBackground(rgb: 0xB9BEC4)
    static let charcoal = CanvasBackground(rgb: 0x24272B)
    static let black = CanvasBackground(rgb: 0x000000)
    static let presets = [white, warmPaper, gray, charcoal, black]

    var displayName: String {
        switch self {
        case .white: return "White"
        case .warmPaper: return "Warm paper"
        case .gray: return "Gray"
        case .charcoal: return "Charcoal"
        case .black: return "Black"
        default: return "Custom"
        }
    }

    var uiColor: UIColor {
        let rgb = UInt32(rawValue, radix: 16) ?? 0xFFFFFF
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    var color: Color { Color(uiColor: uiColor) }

    var isDark: Bool {
        let rgb = UInt32(rawValue, radix: 16) ?? 0xFFFFFF
        func linear(_ byte: UInt32) -> Double {
            let channel = Double(byte) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((rgb >> 16) & 0xFF)
            + 0.7152 * linear((rgb >> 8) & 0xFF)
            + 0.0722 * linear(rgb & 0xFF)
        return luminance < 0.179
    }
}
