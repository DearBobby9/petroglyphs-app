import SwiftUI

struct WipeAnimationOverlay: View {
    @Binding var isShowing: Bool
    @State private var offset: CGFloat = -UIScreen.main.bounds.width

    var body: some View {
        if isShowing {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.limestone.opacity(0), Color.limestone.opacity(0.85), Color.limestone.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 120)
                .ignoresSafeArea()
                .offset(x: offset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        offset = UIScreen.main.bounds.width + 60
                    }
                }
                .allowsHitTesting(false)
        }
    }
}
