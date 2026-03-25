import SwiftUI

struct OchreButton: View {
    let label: String
    let action: () -> Void
    @State private var isPressed = false

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.rounded(18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(isPressed ? Color.burntOchre : Color.ochre)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(duration: 0.15), value: isPressed)
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
    }
}
