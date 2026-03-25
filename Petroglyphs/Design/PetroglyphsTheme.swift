import SwiftUI

struct SandstoneCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.sandstone)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func sandstoneCard() -> some View {
        modifier(SandstoneCardModifier())
    }
}
