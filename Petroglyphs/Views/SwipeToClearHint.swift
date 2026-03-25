import SwiftUI

struct SwipeToClearHint: View {
    @Binding var isShowing: Bool
    @State private var opacity: Double = 0
    @State private var arrowOffset: CGFloat = -6

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.charcoal.opacity(0.7))
                    .offset(x: arrowOffset)

                Text("Swipe to clear")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.charcoal.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.sandstone.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: Color.charcoal.opacity(0.08), radius: 4, y: 2)
            .opacity(opacity)
            .padding(.top, 20)
            Spacer()
        }
        .allowsHitTesting(false)
        .onAppear {
            // Fade in after short delay
            withAnimation(.easeIn(duration: 0.4).delay(0.8)) {
                opacity = 1
            }
            // Animate arrow sliding right, repeating
            withAnimation(.easeInOut(duration: 0.7).delay(1.0).repeatForever(autoreverses: true)) {
                arrowOffset = 6
            }
            // Auto-dismiss after 4s
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.35)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isShowing = false
        }
    }
}
