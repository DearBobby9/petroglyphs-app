import SwiftUI

extension Font {
    static func caveat(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "Caveat-Bold" : "Caveat-Regular", size: size)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
